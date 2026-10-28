-- Actividad 2: enmascaramiento para el área de soporte

-- 8.1 Crear el rol (solo si no existe, para evitar errores al volver a ejecutar el script)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'soporte') THEN
    CREATE ROLE soporte NOLOGIN;
  END IF;
END $$;

-- 8.2 Vista con los datos enmascarados
CREATE OR REPLACE VIEW v_clientes_soporte AS
SELECT
  id,
  nombre,
  CONCAT(LEFT(correo, 2), '*****', SUBSTRING(correo FROM POSITION('@' IN correo))) AS correo,
  CONCAT('******', RIGHT(telefono, 4)) AS telefono,
  CONCAT('*********', RIGHT(rfc, 4)) AS rfc
FROM clientes;

SELECT * FROM v_clientes_soporte;

-- 8.3 Permisos
GRANT USAGE ON SCHEMA public TO soporte;
GRANT SELECT ON v_clientes_soporte TO soporte;
REVOKE ALL ON clientes FROM soporte;

-- Ver los permisos aplicados
\dp clientes
\dp v_clientes_soporte

-- 8.4 Verificar: actuar como el rol soporte
SET ROLE soporte;
SELECT * FROM v_clientes_soporte;  
SELECT * FROM clientes;             
RESET ROLE;