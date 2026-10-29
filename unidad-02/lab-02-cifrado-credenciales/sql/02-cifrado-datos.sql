-- =====================================================================
-- LAB-02 · Script 02 — Actividad 2: cifrado de información sensible
--                      Actividad 3: el problema de la gestión de claves
-- Motor: PostgreSQL 16 · Base de datos: lab01
--
-- Ejecución:
--   docker exec -u postgres lab-postgres psql -d lab01 -e \
--       -f /unidad-02/lab-02-cifrado-credenciales/sql/02-cifrado-datos.sql
--
-- 'CLAVE-DE-PRUEBA' es la clave FICTICIA que indica el laboratorio y se usa
-- solo en las secciones 8.x para reproducir el enunciado. La sección 9.3
-- muestra la alternativa: la clave se lee de la variable de entorno
-- LAB02_CLAVE_RFC y no queda escrita en el script.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Permite volver a ejecutar el script desde cero
DROP TABLE IF EXISTS clientes_protegidos;
DROP TABLE IF EXISTS clientes_rfc_cifrado;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'consulta_lab02') THEN
    CREATE ROLE consulta_lab02 NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sin_acceso_lab02') THEN
    CREATE ROLE sin_acceso_lab02 NOLOGIN;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 8.1 Tabla de demostración con el RFC cifrado
-- ---------------------------------------------------------------------
\echo '== 8.1 Cifrado simétrico del RFC con pgp_sym_encrypt() =='
CREATE TABLE clientes_protegidos (
  id          BIGSERIAL PRIMARY KEY,
  nombre      VARCHAR(120) NOT NULL,
  rfc_cifrado BYTEA NOT NULL
);

INSERT INTO clientes_protegidos (nombre, rfc_cifrado)
VALUES ('Ana López', pgp_sym_encrypt('LOPA900101ABC', 'CLAVE-DE-PRUEBA'));

SELECT * FROM clientes_protegidos;

\echo '-- Tamaño: el RFC tiene 13 caracteres, el texto cifrado ocupa más (cabecera OpenPGP, sal, vector inicial, integridad)'
SELECT length('LOPA900101ABC') AS bytes_rfc, octet_length(rfc_cifrado) AS bytes_cifrado
FROM clientes_protegidos;

\echo '-- El mismo RFC cifrado dos veces con la misma clave produce textos cifrados distintos'
SELECT pgp_sym_encrypt('LOPA900101ABC', 'CLAVE-DE-PRUEBA') =
       pgp_sym_encrypt('LOPA900101ABC', 'CLAVE-DE-PRUEBA') AS cifrados_iguales;

-- ---------------------------------------------------------------------
-- 8.2 Recuperar el dato
-- ---------------------------------------------------------------------
\echo '== 8.2 Descifrado con la clave CORRECTA =='
SELECT id, nombre, pgp_sym_decrypt(rfc_cifrado, 'CLAVE-DE-PRUEBA') AS rfc
FROM clientes_protegidos;

\echo '== 8.2 Descifrado con una clave INCORRECTA =='
SELECT id, nombre, pgp_sym_decrypt(rfc_cifrado, 'CLAVE-INCORRECTA') AS rfc
FROM clientes_protegidos;

\echo '== 8.2 crypt() frente a pgp_sym_encrypt() =='
SELECT 'crypt()'           AS funcion,
       crypt('LOPA900101ABC', gen_salt('bf'))                     AS resultado,
       'no existe función inversa'                                AS como_se_recupera
UNION ALL
SELECT 'pgp_sym_encrypt()',
       encode(pgp_sym_encrypt('LOPA900101ABC', 'CLAVE-DE-PRUEBA'), 'base64'),
       'pgp_sym_decrypt(dato, clave)';

-- ---------------------------------------------------------------------
-- 8.3 El cifrado NO sustituye al control de acceso
-- ---------------------------------------------------------------------
\echo '== 8.3 Cifrado y control de acceso son complementarios =='
GRANT SELECT ON clientes_protegidos TO consulta_lab02;
REVOKE ALL   ON clientes_protegidos FROM sin_acceso_lab02;

SET ROLE consulta_lab02;
\echo '-- consulta_lab02 (tiene SELECT) sin la clave: solo ve bytes'
SELECT id, nombre, rfc_cifrado FROM clientes_protegidos;
\echo '-- consulta_lab02 (tiene SELECT) CON la clave: ve el RFC'
SELECT id, nombre, pgp_sym_decrypt(rfc_cifrado, 'CLAVE-DE-PRUEBA') AS rfc FROM clientes_protegidos;
RESET ROLE;

SET ROLE sin_acceso_lab02;
\echo '-- sin_acceso_lab02 (sin SELECT) aunque conozca la clave: rechazado'
SELECT id, nombre, pgp_sym_decrypt(rfc_cifrado, 'CLAVE-DE-PRUEBA') AS rfc FROM clientes_protegidos;
RESET ROLE;

-- ---------------------------------------------------------------------
-- 9.3 Alternativa: la clave NO está escrita en el script
-- ---------------------------------------------------------------------
\echo '== 9.3 Clave leída desde la variable de entorno LAB02_CLAVE_RFC =='
\getenv clave_rfc LAB02_CLAVE_RFC
SELECT :{?clave_rfc} AS existe_clave \gset
\if :existe_clave
\else
  \echo 'ERROR: define la variable de entorno LAB02_CLAVE_RFC (ver entorno/.env.example)'
  \quit
\endif

CREATE TABLE clientes_rfc_cifrado (
  cliente_id  BIGINT PRIMARY KEY REFERENCES clientes(id),
  rfc_cifrado BYTEA NOT NULL
);

-- El eco se desactiva: así la clave no aparece en la salida ni en las evidencias
\set ECHO none
INSERT INTO clientes_rfc_cifrado (cliente_id, rfc_cifrado)
SELECT id, pgp_sym_encrypt(rfc, :'clave_rfc', 'cipher-algo=aes256')
FROM clientes WHERE rfc IS NOT NULL;
\set ECHO queries
\echo 'INSERT ejecutado: RFC de los clientes de LAB-01 cifrados con AES-256 y la clave de LAB02_CLAVE_RFC (no se muestra).'

SELECT cliente_id, left(encode(rfc_cifrado, 'hex'), 40) || '...' AS rfc_cifrado_hex
FROM clientes_rfc_cifrado ORDER BY cliente_id;

\echo '-- Tipo de clave según la cabecera OpenPGP (SYMKEY = cifrado simétrico con clave compartida)'
SELECT pgp_key_id(rfc_cifrado) AS tipo_clave, count(*) AS registros
FROM clientes_rfc_cifrado GROUP BY 1;

\set ECHO none
SELECT c.id, c.nombre,
       pgp_sym_decrypt(r.rfc_cifrado, :'clave_rfc') AS rfc_descifrado,
       pgp_sym_decrypt(r.rfc_cifrado, :'clave_rfc') = c.rfc AS coincide_con_original
FROM clientes c JOIN clientes_rfc_cifrado r ON r.cliente_id = c.id
ORDER BY c.id;
\set ECHO queries
\unset clave_rfc
\echo '(consulta de descifrado ejecutada con la clave de la variable de entorno; la clave no se muestra)'
