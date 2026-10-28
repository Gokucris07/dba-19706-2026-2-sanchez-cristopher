-- Actividades 3 y 4: seudonimización y separación de funciones

-- Limpieza por si ya existen los esquemas y tablas
DROP SCHEMA IF EXISTS analitica CASCADE;
DROP SCHEMA IF EXISTS pii CASCADE;

-- 9.1 Esquemas (carpetas lógicas dentro de la base)
CREATE SCHEMA pii;
CREATE SCHEMA analitica;

-- 9.2 Tabla de correspondencia: relaciona cada token con el cliente real
CREATE TABLE pii.mapa_cliente (
  token UUID PRIMARY KEY,
  cliente_id BIGINT UNIQUE REFERENCES public.clientes(id)
);

-- 9.3 Generar un token por cliente
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO pii.mapa_cliente (token, cliente_id)
SELECT gen_random_uuid(), id FROM clientes;

SELECT * FROM pii.mapa_cliente;

-- 10. Tabla para analítica: sin nombre, correo, teléfono ni RFC
CREATE TABLE analitica.clientes AS
SELECT
  m.token AS cliente_token,
  c.edad,
  c.ciudad,
  c.codigo_postal,
  c.fecha_alta
FROM pii.mapa_cliente m
JOIN clientes c ON c.id = m.cliente_id;

SELECT * FROM analitica.clientes;

-- 11. Rol analista (solo se crea si no existe)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'analista') THEN
    CREATE ROLE analista NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA analitica TO analista;
GRANT SELECT ON analitica.clientes TO analista;

-- Permisos aplicados
\dp analitica.clientes
\dp pii.mapa_cliente

-- 11.1 Verificar actuando como analista
SET ROLE analista;
SELECT * FROM analitica.clientes;   -- debe funcionar
SELECT * FROM pii.mapa_cliente;     -- debe dar permission denied
SELECT * FROM public.clientes;      -- debe dar permission denied
RESET ROLE;