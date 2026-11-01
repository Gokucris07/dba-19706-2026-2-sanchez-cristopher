-- =====================================================================
-- LAB-03 · Script 01 — Inventario de datos y minimización
-- Actividades 1 y 2
-- Escenario: Comercializadora Norte S.A. de C.V. (ficticia), base lab01.
-- Requisito: tabla clientes del LAB-01 (../lab-01-proteccion-privacidad/sql/01-clasificacion.sql).
--
-- Ejecutar como administrador, desde la raíz del repositorio:
--   docker exec -u postgres lab-postgres psql -d lab01 -P pager=off -e -f /unidad-02/lab-03-privacidad-cumplimiento/sql/01-minimizacion.sql
-- Se puede ejecutar varias veces: recrea clientes_soporte y reescribe los comentarios.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Actividad 1 — Inventario: qué datos existen realmente
-- ---------------------------------------------------------------------

-- Estructura real de la tabla (el inventario parte de lo que hay, no de lo que se cree que hay)
\d clientes

-- Catálogo de datos dentro de la propia base: cada columna documenta
-- si es dato personal, su finalidad, quién la usa y su retención propuesta.
-- Así la clasificación viaja con la base y cualquier DBA la puede consultar.
COMMENT ON TABLE clientes IS
  'Clientes de Comercializadora Norte. Propietario de datos: Dirección comercial. Custodio técnico: DBA.';
COMMENT ON COLUMN clientes.id IS
  'Dato personal indirecto (vincula todos los registros del titular). Finalidad: llave interna. Acceso: operación. Retención: la del registro.';
COMMENT ON COLUMN clientes.nombre IS
  'Dato personal identificativo. Finalidad: atención y facturación. Acceso: atención, facturación. Retención: relación comercial + plazo fiscal.';
COMMENT ON COLUMN clientes.correo IS
  'Dato personal de contacto. Finalidad: atención al cliente. Acceso: atención. Retención: mientras exista la relación comercial.';
COMMENT ON COLUMN clientes.telefono IS
  'Dato personal de contacto. Finalidad: atención al cliente. Acceso: atención. Retención: mientras exista la relación comercial.';
COMMENT ON COLUMN clientes.rfc IS
  'Dato personal identificativo fiscal (alto riesgo). Finalidad: facturación. Acceso: facturación. Retención: plazo fiscal que confirme jurídico.';
COMMENT ON COLUMN clientes.edad IS
  'Dato personal. Finalidad: estadística (solo en rangos). Acceso: analítica solo como rango, vía vista. Retención: revisar necesidad; preferir rango.';
COMMENT ON COLUMN clientes.ciudad IS
  'Dato personal (ubicación) al combinarse con otros. Finalidad: estadística y atención. Acceso: analítica (agregada), atención.';
COMMENT ON COLUMN clientes.codigo_postal IS
  'Dato personal (cuasi-identificador). Finalidad: estadística por región (2 dígitos). Acceso: analítica (generalizado).';
COMMENT ON COLUMN clientes.fecha_alta IS
  'Dato de la relación con el titular. Finalidad: antigüedad y cálculo de retención. Acceso: operación, DBA.';

-- Consultar el catálogo
SELECT a.attnum                                   AS n,
       a.attname                                  AS campo,
       format_type(a.atttypid, a.atttypmod)       AS tipo,
       col_description(a.attrelid, a.attnum)      AS clasificacion_y_finalidad
FROM pg_attribute a
WHERE a.attrelid = 'public.clientes'::regclass
  AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum;


-- ---------------------------------------------------------------------
-- Actividad 2 — Minimización: la tabla que pidió atención al cliente
-- ---------------------------------------------------------------------

-- Solicitud original de atención al cliente. NO se ejecuta: copiaba los
-- 9 campos (incluidos RFC, edad y código postal) que soporte no necesita.
--
--   CREATE TABLE clientes_soporte ( id BIGSERIAL, nombre VARCHAR(120),
--       correo VARCHAR(150), telefono VARCHAR(20), rfc VARCHAR(13), edad INTEGER,
--       ciudad VARCHAR(80), codigo_postal VARCHAR(10), fecha_alta DATE );

-- 8.1 Estructura mínima: solo lo necesario para contactar e identificar al cliente
DROP TABLE IF EXISTS clientes_soporte;

CREATE TABLE clientes_soporte (
  id       BIGINT PRIMARY KEY,
  nombre   VARCHAR(120) NOT NULL,
  correo   VARCHAR(150) NOT NULL,
  telefono VARCHAR(20)
);

INSERT INTO clientes_soporte (id, nombre, correo, telefono)
SELECT id, nombre, correo, telefono
FROM clientes;

SELECT * FROM clientes_soporte;

-- Comparación campo por campo: qué se incluyó y qué se excluyó
SELECT c.ordinal_position AS n,
       c.column_name      AS campo,
       CASE WHEN s.column_name IS NULL THEN 'EXCLUIDO' ELSE 'incluido' END AS en_clientes_soporte
FROM information_schema.columns c
LEFT JOIN information_schema.columns s
       ON s.table_schema = 'public'
      AND s.table_name   = 'clientes_soporte'
      AND s.column_name  = c.column_name
WHERE c.table_schema = 'public' AND c.table_name = 'clientes'
ORDER BY c.ordinal_position;

-- Resumen: columnas de la solicitud original vs. columnas aprobadas
SELECT 9                                                        AS columnas_solicitadas,
       COUNT(*)                                                 AS columnas_aprobadas,
       9 - COUNT(*)                                             AS columnas_eliminadas
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'clientes_soporte';

-- Nota: clientes_soporte es una COPIA. No se actualiza sola cuando cambia
-- clientes (ver script 03, rectificación) y debe entrar en el ciclo de
-- vida de los datos (respaldos, cancelación, retención).
