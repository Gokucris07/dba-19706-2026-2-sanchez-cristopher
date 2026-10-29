-- =====================================================================
-- LAB-02 · Script 01 — Preparación y Actividad 1: protección de credenciales
-- Motor: PostgreSQL 16 · Base de datos: lab01 (la misma de LAB-01)
--
-- Ejecución (dentro del contenedor, como administrador):
--   docker exec -u postgres lab-postgres psql -d lab01 -e \
--       -f /unidad-02/lab-02-cifrado-credenciales/sql/01-credenciales.sql
--
-- Requiere la variable de entorno LAB02_APP_PASSWORD (definida en entorno/.env).
-- La contraseña NO está escrita en este script.
-- =====================================================================

\echo '== 6. Preparación: estructura y datos de LAB-01 =='
\d clientes
SELECT * FROM clientes ORDER BY id;

\echo '== 6. Extensión pgcrypto =='
CREATE EXTENSION IF NOT EXISTS pgcrypto;
SELECT extname, extversion FROM pg_extension WHERE extname = 'pgcrypto';

-- Permite volver a ejecutar el script desde cero
DROP TABLE IF EXISTS usuarios_insegura;
DROP TABLE IF EXISTS usuarios_segura;

-- ---------------------------------------------------------------------
-- 7.1 El problema: contraseña en texto claro
-- ---------------------------------------------------------------------
\echo '== 7.1 Implementación INCORRECTA: contraseña en texto claro =='
CREATE TABLE usuarios_insegura (
  id       BIGSERIAL PRIMARY KEY,
  usuario  VARCHAR(50)  NOT NULL,
  password VARCHAR(100) NOT NULL
);

INSERT INTO usuarios_insegura (usuario, password)
VALUES ('juan', 'Password123');

SELECT * FROM usuarios_insegura;

-- ---------------------------------------------------------------------
-- 7.3 Representación no reversible con crypt() + gen_salt('bf')
-- ---------------------------------------------------------------------
\echo '== 7.3 crypt() con sal aleatoria: dos ejecuciones con la MISMA contraseña =='
SELECT crypt('Password123', gen_salt('bf')) AS ejecucion_1;
SELECT crypt('Password123', gen_salt('bf')) AS ejecucion_2;

\echo '-- La sal que genera gen_salt(): cambia en cada llamada'
SELECT gen_salt('bf') AS sal_1, gen_salt('bf') AS sal_2;

\echo '-- Comparación: MD5 sin sal produce SIEMPRE el mismo valor (vulnerable a tablas precalculadas)'
SELECT md5('Password123') AS md5_1, md5('Password123') AS md5_2,
       md5('Password123') = md5('Password123') AS iguales;

\echo '-- Formato del resultado de bcrypt: $2a$<costo>$<sal de 22 caracteres><hash de 31 caracteres>'
WITH h AS (SELECT crypt('Password123', gen_salt('bf')) AS v)
SELECT v                    AS hash_completo,
       split_part(v, '$', 2) AS algoritmo,
       split_part(v, '$', 3) AS costo,
       left(split_part(v, '$', 4), 22) AS sal,
       length(v)            AS longitud
FROM h;

\echo '-- Costo de trabajo: bcrypt es lento a propósito (costo 6 = default de gen_salt, costo 12 = 64 veces más trabajo)'
\timing on
SELECT crypt('Password123', gen_salt('bf', 6))  IS NOT NULL AS bcrypt_costo_6;
SELECT crypt('Password123', gen_salt('bf', 12)) IS NOT NULL AS bcrypt_costo_12;
SELECT md5('Password123') IS NOT NULL AS md5;
\timing off

-- ---------------------------------------------------------------------
-- 7.4 Tabla para credenciales protegidas
-- ---------------------------------------------------------------------
\echo '== 7.4 Implementación CORRECTA: solo se guarda el hash =='
CREATE TABLE usuarios_segura (
  id            BIGSERIAL PRIMARY KEY,
  usuario       VARCHAR(50) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL
);

INSERT INTO usuarios_segura (usuario, password_hash)
VALUES ('juan', crypt('Password123', gen_salt('bf')));

-- Usuario adicional con la MISMA contraseña: su hash debe ser distinto
INSERT INTO usuarios_segura (usuario, password_hash)
VALUES ('maria', crypt('Password123', gen_salt('bf')));

SELECT * FROM usuarios_segura ORDER BY id;

\echo '-- ¿Se puede saber que juan y maria tienen la misma contraseña viendo la tabla?'
SELECT a.usuario, b.usuario, a.password_hash = b.password_hash AS hashes_iguales
FROM usuarios_segura a JOIN usuarios_segura b ON a.usuario = 'juan' AND b.usuario = 'maria';

-- ---------------------------------------------------------------------
-- 7.5 Verificar una contraseña
-- ---------------------------------------------------------------------
\echo '== 7.5 Verificación con la contraseña CORRECTA =='
SELECT usuario, password_hash = crypt('Password123', password_hash) AS contraseña_correcta
FROM usuarios_segura WHERE usuario = 'juan';

\echo '== 7.5 Verificación con una contraseña INCORRECTA =='
SELECT usuario, password_hash = crypt('OtraPassword', password_hash) AS contraseña_correcta
FROM usuarios_segura WHERE usuario = 'juan';

\echo '-- crypt(contraseña, hash_guardado) reutiliza la sal guardada dentro del hash:'
SELECT password_hash                         AS guardado,
       crypt('Password123', password_hash)   AS recalculado_correcta,
       crypt('OtraPassword', password_hash)  AS recalculado_incorrecta
FROM usuarios_segura WHERE usuario = 'juan';

\echo '-- No existe una función para "descifrar" el hash: no hay forma de obtener Password123 desde la tabla.'

-- ---------------------------------------------------------------------
-- Complemento: así protege PostgreSQL las contraseñas de SUS roles
-- ---------------------------------------------------------------------
\echo '== Complemento: contraseñas de roles de PostgreSQL (SCRAM-SHA-256) =='
SHOW password_encryption;

\getenv clave_app LAB02_APP_PASSWORD
SELECT :{?clave_app} AS existe_variable \gset
\if :existe_variable
  -- El rol se crea una sola vez; en ejecuciones posteriores solo se actualiza la contraseña
  SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_lab02') AS existe_rol \gset
  \if :existe_rol
  \else
    CREATE ROLE app_lab02 LOGIN;
  \endif
  -- ECHO se desactiva para que la contraseña no aparezca en la salida ni en las evidencias
  \set ECHO none
  ALTER ROLE app_lab02 LOGIN PASSWORD :'clave_app';
  \unset clave_app
  \set ECHO queries
  \echo 'Contraseña de app_lab02 asignada desde LAB02_APP_PASSWORD (no se muestra).'
\else
  \echo 'ERROR: define la variable de entorno LAB02_APP_PASSWORD (ver entorno/.env.example)'
  \quit
\endif

GRANT CONNECT ON DATABASE lab01 TO app_lab02;

-- pg_authid solo lo puede leer un superusuario
SELECT rolname,
       left(rolpassword, 40) || '...' AS rolpassword_inicio,
       split_part(rolpassword, '$', 1) AS mecanismo
FROM pg_authid WHERE rolname = 'app_lab02';
