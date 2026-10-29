-- =====================================================================
-- LAB-02 · Script 03 — Actividades 5 y 6: verificar el estado de TLS
-- Motor: PostgreSQL 16 · Base de datos: lab01
--
-- Este script se ejecuta varias veces, una por cada forma de conexión, para
-- comparar los resultados (ver evidencias/04-tls.md):
--
--   a) Socket local, como administrador (sin red):
--      docker exec -u postgres lab-postgres psql -d lab01 -e \
--          -f /unidad-02/lab-02-cifrado-credenciales/sql/03-verificacion-tls.sql
--
--   b) Por red, como aplicación, con verificación completa del servidor:
--      docker compose --profile cliente run --rm cliente \
--          "host=db.lab02.local port=5432 dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=/tls/ca.crt" \
--          -e -f /unidad-02/lab-02-cifrado-credenciales/sql/03-verificacion-tls.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 11. Configuración TLS del servidor
-- ---------------------------------------------------------------------
\echo '== 11. Configuración TLS del servidor =='
SHOW ssl;
SHOW port;
SHOW listen_addresses;

-- Las rutas de archivos y pg_hba_file_rules solo las puede consultar un superusuario
SELECT current_setting('is_superuser') = 'on' AS es_superusuario \gset
\if :es_superusuario
  -- ssl_min_protocol_version solo lo pueden ver superusuarios o miembros de pg_read_all_settings
  SHOW ssl_min_protocol_version;

  \echo '-- Archivos de certificado configurados (solo administrador)'
  SELECT name, setting
  FROM pg_settings
  WHERE name IN ('ssl_cert_file', 'ssl_key_file', 'ssl_ca_file',
                 'ssl_max_protocol_version', 'password_encryption')
  ORDER BY name;

  \echo '-- Reglas de pg_hba.conf que se están aplicando (solo administrador)'
  SELECT line_number, type, database, user_name, address, auth_method
  FROM pg_hba_file_rules
  ORDER BY line_number;
\else
  \echo '-- (ssl_min_protocol_version, rutas de certificados y pg_hba.conf omitidos: requieren privilegios de administrador)'
\endif

-- ---------------------------------------------------------------------
-- 11.1 Conexión actual
-- ---------------------------------------------------------------------
\echo '== 11.1 Conexión actual =='
SELECT current_user, inet_client_addr(), inet_client_port();

SELECT ssl, version, cipher, bits
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
