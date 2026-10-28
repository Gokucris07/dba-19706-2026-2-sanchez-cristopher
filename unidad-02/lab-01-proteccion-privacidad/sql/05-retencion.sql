-- Actividad 7: retención de datos (periodo de 5 años)

-- Consulta oficial: clientes con más de 5 años de antigüedad
SELECT *
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years';

-- Cuántos registros serían afectados
SELECT COUNT(*) AS registros_afectados
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years';

-- Simulacoin: como todos los clientes son de hoy, la consulta sale vacia.
-- Para comprobar que funciona, se envejecen 2 clientes dentro de una
-- transacción  y al final se deshace todo .
BEGIN;

UPDATE clientes
SET fecha_alta = CURRENT_DATE - INTERVAL '6 years'
WHERE id IN (1, 2);

SELECT id, nombre, fecha_alta
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years';

ROLLBACK;

-- Comprobar que no cambió nada
SELECT id, nombre, fecha_alta FROM clientes ORDER BY id;