-- Actividades 5 y 6: anonimización y análisis de reidentificación

-- 12.1 Generalizar la edad (de edad exacta a rango)
SELECT
  CASE WHEN edad BETWEEN 18 AND 30 THEN '18-30'
       WHEN edad BETWEEN 31 AND 45 THEN '31-45'
       ELSE '46+' END AS rango_edad,
  COUNT(*) AS total
FROM clientes
GROUP BY 1;

-- 12.2 Generalizar la región (de código postal completo a 2 dígitos)
SELECT LEFT(codigo_postal, 2) AS region, COUNT(*) AS total
FROM clientes
GROUP BY 1;

-- 12.3 Combinar atributos
SELECT
  CASE WHEN edad BETWEEN 18 AND 30 THEN '18-30'
       WHEN edad BETWEEN 31 AND 45 THEN '31-45'
       ELSE '46+' END AS rango_edad,
  LEFT(codigo_postal, 2) AS region,
  COUNT(*) AS total
FROM clientes
GROUP BY 1, 2;

-- 12.4 Suprimir grupos con menos de 5 registros
SELECT
  CASE WHEN edad BETWEEN 18 AND 30 THEN '18-30'
       WHEN edad BETWEEN 31 AND 45 THEN '31-45'
       ELSE '46+' END AS rango_edad,
  LEFT(codigo_postal, 2) AS region,
  COUNT(*) AS total
FROM clientes
GROUP BY 1, 2
HAVING COUNT(*) >= 5;

-- Actividad 6: tamaño del grupo más pequeño (k) con la combinación de 12.3
SELECT MIN(total) AS k_original
FROM (
  SELECT COUNT(*) AS total
  FROM clientes
  GROUP BY
    CASE WHEN edad BETWEEN 18 AND 30 THEN '18-30'
         WHEN edad BETWEEN 31 AND 45 THEN '31-45'
         ELSE '46+' END,
    LEFT(codigo_postal, 2)
) t;

-- RETO: generalizar más (rango de edad más amplio y región de 1 dígito)
SELECT
  CASE WHEN edad BETWEEN 18 AND 50 THEN '18-50' ELSE '51+' END AS rango_edad,
  LEFT(codigo_postal, 1) || 'xxxx' AS region,
  COUNT(*) AS total
FROM clientes
GROUP BY 1, 2
HAVING COUNT(*) >= 5;

-- RETO: k después de generalizar más
SELECT MIN(total) AS k_reto
FROM (
  SELECT COUNT(*) AS total
  FROM clientes
  GROUP BY
    CASE WHEN edad BETWEEN 18 AND 50 THEN '18-50' ELSE '51+' END,
    LEFT(codigo_postal, 1)
) t;