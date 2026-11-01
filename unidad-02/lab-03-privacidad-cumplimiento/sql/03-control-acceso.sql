-- =====================================================================
-- LAB-03 · Script 03 — Control de acceso por finalidad y derechos ARCO
-- Actividad 4 (rol analista y vista), Actividades 6 y 7 (acceso y
-- rectificación) y Actividad 8 (mapa de copias antes de una cancelación)
-- Requisitos, en ESTE mismo contenedor (lab-postgres):
--   LAB-01 scripts 01, 02 y 03 (tabla clientes, v_clientes_soporte, pii y analitica),
--   LAB-02 script 02 (clientes_rfc_cifrado) y los scripts 01 y 02 de este laboratorio.
--
-- Ejecutar como administrador:
--   docker exec -u postgres lab-postgres psql -d lab01 -P pager=off -e -f /unidad-02/lab-03-privacidad-cumplimiento/sql/03-control-acceso.sql
-- Se puede ejecutar varias veces. Los errores "permission denied" y
-- "column does not exist" son ESPERADOS: son la prueba de que el control funciona.
-- =====================================================================

-- Si una sentencia falla dentro de una transacción, psql deshace solo esa
-- sentencia y la transacción continúa (necesario para la Actividad 7).
\set ON_ERROR_ROLLBACK on


-- ---------------------------------------------------------------------
-- Actividad 4 — Control de acceso relacionado con la finalidad
-- ---------------------------------------------------------------------

-- El rol analista existe desde LAB-01 (script 03). Se crea solo si falta.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'analista') THEN
    CREATE ROLE analista NOLOGIN;
  END IF;
END $$;

-- Vista con lo único que analítica necesita: ciudad y rango de edad
CREATE OR REPLACE VIEW v_analitica_clientes AS
SELECT ciudad,
       CASE
         WHEN edad < 18 THEN 'Menor de 18'
         WHEN edad BETWEEN 18 AND 29 THEN '18-29'
         WHEN edad BETWEEN 30 AND 44 THEN '30-44'
         WHEN edad BETWEEN 45 AND 59 THEN '45-59'
         ELSE '60 o más'
       END AS rango_edad
FROM clientes;

GRANT USAGE  ON SCHEMA public       TO analista;
GRANT SELECT ON v_analitica_clientes TO analista;
-- Deliberadamente NO se ejecuta:  GRANT SELECT ON clientes TO analista;

-- Verificación de privilegios (tal como la pide el enunciado)
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'analista'
ORDER BY table_schema, table_name;

-- Hallazgo: además de la vista, analista conserva desde LAB-01 el SELECT sobre
-- analitica.clientes, que tiene edad EXACTA, código postal COMPLETO, fecha de alta
-- y un token por persona. Es más de lo que la finalidad de LAB-03 (estadística
-- agregada) necesita. Los privilegios se acumulan si nadie los revisa: se retiran.
-- (Solo si el esquema analitica de LAB-01 existe en esta base.)
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_namespace WHERE nspname = 'analitica') THEN
    EXECUTE 'REVOKE ALL   ON ALL TABLES IN SCHEMA analitica FROM analista';
    EXECUTE 'REVOKE USAGE ON SCHEMA analitica FROM analista';
    RAISE NOTICE 'Privilegios de analista sobre el esquema analitica (LAB-01) retirados';
  END IF;
END $$;

-- Verificación después de la revisión
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'analista'
ORDER BY table_schema, table_name;

-- Matriz de acceso efectiva del rol sobre todos los objetos con datos de clientes
-- (to_regclass devuelve NULL si el objeto no existe, así la consulta no falla)
SELECT objeto,
       to_regclass(objeto) IS NOT NULL                                AS existe,
       has_table_privilege('analista', to_regclass(objeto), 'SELECT') AS analista_puede_leer
FROM unnest(ARRAY[
  'public.v_analitica_clientes',
  'public.clientes',
  'public.clientes_soporte',
  'public.v_clientes_soporte',
  'public.clientes_rfc_cifrado',
  'public.oposiciones_tratamiento',
  'analitica.clientes',
  'pii.mapa_cliente'
]) AS objeto;

-- Prueba actuando como analista
SET ROLE analista;
SELECT current_user AS actuando_como;
SELECT * FROM v_analitica_clientes;                     -- permitido
SELECT ciudad, rango_edad, COUNT(*) AS cantidad          -- permitido: estadística
FROM v_analitica_clientes GROUP BY 1, 2 ORDER BY 1, 2;
SELECT nombre, correo, rfc FROM v_analitica_clientes;   -- ERROR esperado: la vista no tiene esas columnas
SELECT * FROM clientes;                                 -- ERROR esperado: permission denied
SELECT * FROM clientes_soporte;                         -- ERROR esperado: permission denied
SELECT * FROM analitica.clientes;                       -- ERROR esperado: permiso retirado
RESET ROLE;
SELECT current_user AS de_regreso_como;


-- ---------------------------------------------------------------------
-- Actividad 6 — Derecho de acceso
-- Un titular (Ana López) pide saber qué datos suyos tiene la organización.
-- ---------------------------------------------------------------------

-- Consulta del enunciado, con el correo real del escenario (dominio example.test)
SELECT id, nombre, correo, telefono, rfc, edad, ciudad, codigo_postal, fecha_alta
FROM clientes
WHERE correo = 'ana.lopez@example.test';

-- Implicación técnica: la tabla principal no es todo. ¿En qué otras tablas está?
SELECT 'public.clientes'                 AS ubicacion, COUNT(*) AS registros FROM clientes             WHERE id = 1
UNION ALL
SELECT 'public.clientes_soporte (copia)',             COUNT(*) FROM clientes_soporte     WHERE id = 1
UNION ALL
SELECT 'public.clientes_rfc_cifrado (LAB-02)',        COUNT(*) FROM clientes_rfc_cifrado WHERE cliente_id = 1
UNION ALL
SELECT 'public.oposiciones_tratamiento',              COUNT(*) FROM oposiciones_tratamiento WHERE cliente_id = 1;

-- Copias seudonimizadas de LAB-01: sin nombre, pero se llega a Ana por el token
SELECT 'pii.mapa_cliente (LAB-01)'      AS ubicacion, COUNT(*) AS registros FROM pii.mapa_cliente WHERE cliente_id = 1
UNION ALL
SELECT 'analitica.clientes (vía token)',              COUNT(*)
FROM analitica.clientes a JOIN pii.mapa_cliente m ON m.token = a.cliente_token
WHERE m.cliente_id = 1;


-- ---------------------------------------------------------------------
-- Actividad 7 — Derecho de rectificación
-- "Mi correo electrónico registrado es incorrecto."
-- Se ejecuta dentro de una transacción y se deshace al final, para que los
-- datos del LAB-01 queden iguales y el script pueda repetirse. En una solicitud
-- real, el COMMIT se haría solo con la solicitud autorizada y su folio.
-- ---------------------------------------------------------------------

BEGIN;

-- Lo único que la base "sabe" del cambio sin auditoría: quién está conectado y cuándo
SELECT current_user AS quien_ejecuta, now() AS cuando;

UPDATE clientes SET correo = 'ana.lopez.nuevo@example.test' WHERE id = 1;

SELECT id, nombre, correo FROM clientes WHERE id = 1;            -- rectificado

-- La copia de soporte (script 01) conserva el dato INCORRECTO
SELECT id, nombre, correo FROM clientes_soporte WHERE id = 1;

-- La vista enmascarada de LAB-01 sí refleja el cambio: lee la tabla original
SELECT id, nombre, correo FROM v_clientes_soporte WHERE id = 1;

-- ¿Quedó registro de quién hizo el cambio? Con la configuración por defecto, no.
SHOW log_statement;

ROLLBACK;

SELECT id, nombre, correo FROM clientes WHERE id = 1;            -- sin cambios tras el ROLLBACK


-- ---------------------------------------------------------------------
-- Actividad 8 — Cancelación: mapa de copias ANTES de borrar
-- No se ejecuta ningún DELETE. Se identifica dónde más vive el dato.
-- ---------------------------------------------------------------------

-- Tablas que dependen de clientes por llave foránea
SELECT conrelid::regclass          AS tabla_relacionada,
       conname                     AS restriccion,
       pg_get_constraintdef(oid)   AS definicion
FROM pg_constraint
WHERE confrelid = 'public.clientes'::regclass AND contype = 'f'
ORDER BY 1;

-- Vistas que leen directamente de clientes
SELECT view_schema || '.' || view_name AS vista_sobre_clientes
FROM information_schema.view_table_usage
WHERE table_schema = 'public' AND table_name = 'clientes'
ORDER BY 1;

-- Tablas con columnas de datos de clientes, tengan o no llave foránea
-- (aquí aparecen las COPIAS, que ninguna restricción relaciona con clientes)
SELECT c.table_schema || '.' || c.table_name AS tabla,
       string_agg(c.column_name, ', ' ORDER BY c.ordinal_position) AS columnas_de_clientes,
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint k
                         WHERE k.conrelid = (quote_ident(c.table_schema) || '.' || quote_ident(c.table_name))::regclass
                           AND k.confrelid = 'public.clientes'::regclass)
            THEN 'sí' ELSE 'NO' END AS tiene_fk_a_clientes
FROM information_schema.columns c
JOIN information_schema.tables t
  ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
  AND c.column_name IN ('nombre', 'correo', 'telefono', 'rfc', 'rfc_cifrado',
                        'edad', 'ciudad', 'codigo_postal', 'cliente_id', 'cliente_token')
  AND NOT (c.table_schema = 'public' AND c.table_name = 'clientes')
GROUP BY c.table_schema, c.table_name
ORDER BY 1;
