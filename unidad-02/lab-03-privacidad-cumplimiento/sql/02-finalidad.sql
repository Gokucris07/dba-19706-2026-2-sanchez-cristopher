-- =====================================================================
-- LAB-03 · Script 02 — Separación por finalidad
-- Actividad 3 (analítica con datos agregados) y Actividad 9 (oposición)
-- Requisito: tabla clientes del LAB-01.
--
-- Ejecutar como administrador:
--   docker exec -u postgres lab-postgres psql -d lab01 -P pager=off -e -f /unidad-02/lab-03-privacidad-cumplimiento/sql/02-finalidad.sql
-- Se puede ejecutar varias veces.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Actividad 3 — Analítica: estadísticas sin identificar a nadie
-- Analítica necesita: ciudad, rango de edad, región del código postal.
-- No necesita: nombre, correo, teléfono, RFC.
-- ---------------------------------------------------------------------

-- Clientes por ciudad
SELECT ciudad,
       COUNT(*) AS cantidad_clientes
FROM clientes
GROUP BY ciudad
ORDER BY cantidad_clientes DESC;

-- Clientes por rango de edad (la edad exacta no sale de la base)
SELECT CASE
         WHEN edad < 18 THEN 'Menor de 18'
         WHEN edad BETWEEN 18 AND 29 THEN '18-29'
         WHEN edad BETWEEN 30 AND 44 THEN '30-44'
         WHEN edad BETWEEN 45 AND 59 THEN '45-59'
         ELSE '60 o más'
       END AS rango_edad,
       COUNT(*) AS cantidad
FROM clientes
GROUP BY CASE
           WHEN edad < 18 THEN 'Menor de 18'
           WHEN edad BETWEEN 18 AND 29 THEN '18-29'
           WHEN edad BETWEEN 30 AND 44 THEN '30-44'
           WHEN edad BETWEEN 45 AND 59 THEN '45-59'
           ELSE '60 o más'
         END
ORDER BY rango_edad;

-- Clientes por región del código postal (2 primeros dígitos, no el CP completo)
SELECT LEFT(codigo_postal, 2) || 'xxx' AS region_cp,
       COUNT(*)                        AS cantidad
FROM clientes
GROUP BY 1
ORDER BY 1;

-- Comparación: lo que recibiría analítica si se le entregara la tabla completa
-- (solo se cuenta; no se muestran los datos)
SELECT COUNT(*)                                  AS registros,
       COUNT(DISTINCT correo)                    AS correos_identificables,
       COUNT(DISTINCT rfc)                       AS rfc_identificables,
       COUNT(DISTINCT (ciudad, edad, codigo_postal)) AS combinaciones_unicas_ciudad_edad_cp
FROM clientes;

-- Riesgo residual: al cruzar los tres atributos, algunos grupos quedan de 1 persona.
-- Un grupo de 1 permite singularizar a alguien aunque no aparezca su nombre.
SELECT ciudad,
       CASE
         WHEN edad < 18 THEN 'Menor de 18'
         WHEN edad BETWEEN 18 AND 29 THEN '18-29'
         WHEN edad BETWEEN 30 AND 44 THEN '30-44'
         WHEN edad BETWEEN 45 AND 59 THEN '45-59'
         ELSE '60 o más'
       END                              AS rango_edad,
       LEFT(codigo_postal, 2) || 'xxx'  AS region_cp,
       COUNT(*)                         AS cantidad
FROM clientes
GROUP BY 1, 2, 3
ORDER BY cantidad, ciudad;


-- ---------------------------------------------------------------------
-- Actividad 9 — Oposición a una finalidad secundaria
-- Un cliente pide que sus datos no se usen para promociones.
-- No se borra nada: se registra la oposición y se excluye al titular
-- SOLO de esa finalidad. Facturación y atención no cambian.
-- ---------------------------------------------------------------------

DROP VIEW  IF EXISTS v_contactables_promociones;
DROP TABLE IF EXISTS oposiciones_tratamiento;

-- Registro de oposiciones por finalidad (quién, a qué, cuándo, con qué folio)
CREATE TABLE oposiciones_tratamiento (
  cliente_id      BIGINT      NOT NULL REFERENCES clientes(id),
  finalidad       VARCHAR(40) NOT NULL CHECK (finalidad IN ('promociones')),
  fecha_solicitud DATE        NOT NULL DEFAULT CURRENT_DATE,
  folio_solicitud VARCHAR(20) NOT NULL,
  PRIMARY KEY (cliente_id, finalidad)
);

-- Vista que cualquier proceso de promociones tendría que usar.
-- Excluye automáticamente a quien se opuso. Expone solo lo necesario para
-- enviar un correo (nombre y correo) y la ciudad para segmentar.
-- IMPORTANTE: no se otorga a ningún rol. La finalidad "promociones" todavía no
-- está aprobada por privacidad/jurídico (Actividad 5); esto solo deja lista
-- la capacidad técnica de respetar la oposición.
CREATE VIEW v_contactables_promociones AS
SELECT c.id, c.nombre, c.correo, c.ciudad
FROM clientes c
WHERE NOT EXISTS (
  SELECT 1 FROM oposiciones_tratamiento o
  WHERE o.cliente_id = c.id AND o.finalidad = 'promociones'
);

-- Antes de la solicitud
SELECT * FROM v_contactables_promociones ORDER BY id;

-- Laura Sánchez (id 5) se opone a recibir promociones
INSERT INTO oposiciones_tratamiento (cliente_id, finalidad, folio_solicitud)
VALUES (5, 'promociones', 'ARCO-2026-0001');

SELECT * FROM oposiciones_tratamiento;

-- Después: ya no aparece para promociones...
SELECT * FROM v_contactables_promociones ORDER BY id;

-- ...pero sigue siendo cliente: facturación y atención la siguen viendo
SELECT id, nombre, rfc   FROM clientes         WHERE id = 5;  -- facturación
SELECT id, nombre, correo FROM clientes_soporte WHERE id = 5;  -- atención (creada en el script 01)
