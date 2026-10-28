-- Actividad 1: tabla clientes y datos de prueba
DROP TABLE IF EXISTS clientes CASCADE;  -- por si existe la tabla, la eliminamos para crearla de nuevo

CREATE TABLE clientes (
  id BIGSERIAL PRIMARY KEY,
  nombre VARCHAR(120) NOT NULL,
  correo VARCHAR(150) NOT NULL,
  telefono VARCHAR(20),
  rfc VARCHAR(13),
  edad INTEGER,
  ciudad VARCHAR(80),
  codigo_postal VARCHAR(10),
  fecha_alta DATE DEFAULT CURRENT_DATE
);

\d clientes

INSERT INTO clientes (nombre, correo, telefono, rfc, edad, ciudad, codigo_postal) VALUES
('Ana López','ana.lopez@example.test','6671234567','LOAA850315ABC',41,'Culiacán','80000'),
('Carlos Pérez','carlos.perez@example.test','6672345678','PECA900720DEF',35,'Culiacán','80100'),
('María García','maria.garcia@example.test','6673456789','GAMA780912GHI',47,'Mazatlán','82000'),
('Luis Torres','luis.torres@example.test','6674567890','TOLU920201JKL',34,'Los Mochis','81200'),
('Laura Sánchez','laura.sanchez@example.test','6675678901','SALA880525MNO',38,'Culiacán','80200');

SELECT * FROM clientes;