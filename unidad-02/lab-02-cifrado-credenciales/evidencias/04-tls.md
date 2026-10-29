# Evidencia 04 — TLS: protección de datos durante la comunicación

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| **Actividades** | 10. Actividad 4 · 11. Actividad 5 · 12. Actividad 6 · 13. Comprender `sslmode` |
| **Script** | `sql/03-verificacion-tls.sql` + pruebas de conexión con `psql`, `openssl` y `tcpdump` |
| **Entorno** | PostgreSQL 16.15 con la configuración de `entorno/` (`ssl=on`, `ssl_min_protocol_version=TLSv1.2`, `pg_hba.conf` solo `hostssl` + `scram-sha-256`), certificados de `entorno/tls/generar-certificados.sh` |
| **Fecha de ejecución** | 2026-10-27 |

## Objetivo

Configurar y verificar TLS en PostgreSQL. En concreto: comprobar qué viaja por la red con y sin TLS, verificar el estado real de la conexión desde `pg_stat_ssl` y entender en la práctica qué verifica cada valor de `sslmode`.

## Comando o procedimiento

**Configuración del servidor** (archivos en `entorno/`):

1. `tls/generar-certificados.sh` crea una CA de laboratorio y un certificado de servidor firmado por ella, válido para `localhost` y `db.lab02.local`.
2. PostgreSQL arranca con `ssl=on`, el certificado, la clave privada, la CA y `ssl_min_protocol_version=TLSv1.2`.
3. `pg_hba.conf` acepta conexiones de red **solo** con TLS (`hostssl ... scram-sha-256`) y rechaza las que no lo usan (`hostnossl ... reject`).
4. Se creó el rol de aplicación `app_lab02` (script 01), con la contraseña tomada de una variable de entorno.

**Pruebas:**

| Prueba | Comando |
|---|---|
| A. Socket local (administrador) | `docker exec -u postgres lab-postgres psql -d lab01 -e -f .../sql/03-verificacion-tls.sql` |
| B. Por red (aplicación, Actividad 6) | `psql "host=db.lab02.local port=5432 dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt" -e -f sql/03-verificacion-tls.sql` |
| C. Matriz de `sslmode` | Una conexión por cada modo y caso (ver resultados) |
| D. Servidor impostor | Un segundo PostgreSQL en el puerto 5433 con un certificado autofirmado que **no** emitió nuestra CA |
| E. Captura de tráfico | `tcpdump -i lo port 5432` mientras se ejecuta la misma consulta sin TLS y con TLS |

Para la prueba E sin TLS se agregó **temporalmente** una regla `hostnossl` solo para `app_lab02` desde `127.0.0.1` y un `GRANT SELECT` temporal sobre `clientes`. Ambos se revirtieron al terminar (E3).

## Resultado obtenido

### A. Sesión por socket local (administrador)

```text
SHOW ssl;
 ssl 
-----
 on
(1 row)

SHOW port;
 port 
------
 5432
(1 row)

SHOW listen_addresses;
 listen_addresses 
------------------
 *
(1 row)

SELECT current_setting('is_superuser') = 'on' AS es_superusuario 
SHOW ssl_min_protocol_version;
 ssl_min_protocol_version 
--------------------------
 TLSv1.2
(1 row)

-- Archivos de certificado configurados (solo administrador)
SELECT name, setting
  FROM pg_settings
  WHERE name IN ('ssl_cert_file', 'ssl_key_file', 'ssl_ca_file',
                 'ssl_max_protocol_version', 'password_encryption')
  ORDER BY name;
           name           |          setting          
--------------------------+---------------------------
 password_encryption      | scram-sha-256
 ssl_ca_file              | /var/lib/pglab/ca.crt
 ssl_cert_file            | /var/lib/pglab/server.crt
 ssl_key_file             | /var/lib/pglab/server.key
 ssl_max_protocol_version | 
(5 rows)

-- Reglas de pg_hba.conf que se están aplicando (solo administrador)
SELECT line_number, type, database, user_name, address, auth_method
  FROM pg_hba_file_rules
  ORDER BY line_number;
 line_number |   type    | database | user_name | address |  auth_method  
-------------+-----------+----------+-----------+---------+---------------
           9 | local     | {all}    | {all}     |         | peer
          12 | hostssl   | {all}    | {all}     | 0.0.0.0 | scram-sha-256
          13 | hostssl   | {all}    | {all}     | ::      | scram-sha-256
          16 | hostnossl | {all}    | {all}     | 0.0.0.0 | reject
          17 | hostnossl | {all}    | {all}     | ::      | reject
(5 rows)
```

```text
SELECT current_user, inet_client_addr(), inet_client_port();
 current_user | inet_client_addr | inet_client_port 
--------------+------------------+------------------
 postgres     |                  |                 
(1 row)

SELECT ssl, version, cipher, bits
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
 ssl | version | cipher | bits 
-----+---------+--------+------
 f   |         |        |     
(1 row)
```

### B. Sesión por red con `sslmode=verify-full` (Actividad 6)

```text
SHOW ssl;
 ssl 
-----
 on
(1 row)

SHOW port;
 port 
------
 5432
(1 row)

SHOW listen_addresses;
 listen_addresses 
------------------
 *
(1 row)

SELECT current_setting('is_superuser') = 'on' AS es_superusuario 
-- (ssl_min_protocol_version, rutas de certificados y pg_hba.conf omitidos: requieren privilegios de administrador)
```

```text
SELECT current_user, inet_client_addr(), inet_client_port();
 current_user | inet_client_addr | inet_client_port 
--------------+------------------+------------------
 app_lab02    | 127.0.0.1        |            48798
(1 row)

SELECT ssl, version, cipher, bits
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
 ssl | version |         cipher         | bits 
-----+---------+------------------------+------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384 |  256
(1 row)
```

### C. Comportamiento de cada `sslmode` contra el servidor legítimo

| # | Modo y caso | Resultado |
|---|---|---|
| 1 | `disable` | **Rechazada** por `pg_hba.conf` ("no encryption") |
| 2 | `prefer` (default de libpq) | Conecta con TLS 1.3 |
| 3 | `require` | Conecta con TLS 1.3 (no verifica certificado ni nombre) |
| 4 | `require` + `sslrootcert` de otra CA | **Falla**: si se indica una CA, libpq se comporta como `verify-ca` |
| 5 | `verify-ca` con un nombre que no está en el certificado | Conecta: verifica la CA, **no** el nombre |
| 6 | `verify-ca` con otra CA | **Falla**: `certificate verify failed` |
| 7 | `verify-full` con un nombre que no está en el certificado | **Falla**: `does not match host name "postgres"` |
| 8 | `verify-full` por IP (`127.0.0.1`) | **Falla**: la IP no está en el certificado |
| 9 | `verify-full` sin certificado de CA | **Falla**: no encuentra `~/.postgresql/root.crt` |
| 10 | `verify-full` con nombre y CA correctos | Conecta con TLS 1.3 |

```text
$ psql "host=localhost dbname=lab01 user=app_lab02 sslmode=disable"
psql: error: connection to server at "localhost" (127.0.0.1), port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "127.0.0.1", user "app_lab02", database "lab01", no encryption
```

```text
$ psql "host=localhost dbname=lab01 user=app_lab02 sslmode=prefer"
 ssl | version |         cipher         
-----+---------+------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

```text
$ psql "host=127.0.0.1 dbname=lab01 user=app_lab02 sslmode=require"
 ssl | version |         cipher         
-----+---------+------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

```text
$ psql "host=127.0.0.1 dbname=lab01 user=app_lab02 sslmode=require sslrootcert=otra-ca/ca-falsa.crt"
psql: error: connection to server at "127.0.0.1", port 5432 failed: SSL error: certificate verify failed
```

```text
$ psql "host=postgres dbname=lab01 user=app_lab02 sslmode=verify-ca sslrootcert=entorno/tls/ca.crt"
 ssl | version |         cipher         
-----+---------+------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

```text
$ psql "host=db.lab02.local dbname=lab01 user=app_lab02 sslmode=verify-ca sslrootcert=otra-ca/ca-falsa.crt"
psql: error: connection to server at "db.lab02.local" (127.0.0.1), port 5432 failed: SSL error: certificate verify failed
```

```text
$ psql "host=postgres dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt"
psql: error: connection to server at "postgres" (127.0.0.1), port 5432 failed: server certificate for "localhost" (and 1 other name) does not match host name "postgres"
```

```text
$ psql "host=127.0.0.1 dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt"
psql: error: connection to server at "127.0.0.1", port 5432 failed: server certificate for "localhost" (and 2 other names) does not match host name "127.0.0.1"
```

```text
$ psql "host=db.lab02.local dbname=lab01 user=app_lab02 sslmode=verify-full"
psql: error: connection to server at "db.lab02.local" (127.0.0.1), port 5432 failed: root certificate file "~/.postgresql/root.crt" does not exist
Either provide the file, use the system's trusted roots with sslrootcert=system, or change sslmode to disable server certificate verification.
```

```text
$ psql "host=db.lab02.local dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt"
 ssl | version |         cipher         
-----+---------+------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

```text
$ openssl x509 -in entorno/tls/server.crt -noout -subject -issuer -dates -ext subjectAltName
subject=C = MX, ST = Sinaloa, O = Comercializadora Norte LAB, CN = localhost
issuer=C = MX, ST = Sinaloa, O = Comercializadora Norte LAB, CN = CA Laboratorio DBA
notBefore=Oct 28 02:41:55 2026 GMT
notAfter=Oct 28 02:41:55 2027 GMT
X509v3 Subject Alternative Name: 
    DNS:localhost, DNS:db.lab02.local
```

### D. Servidor impostor: ¿con quién me estoy conectando?

```text
$ psql "host=db.lab02.local port=5432 dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt"
      servidor       | puerto | ssl | version 
---------------------+--------+-----+---------
 (servidor legítimo) |   5432 | t   | TLSv1.3
(1 row)
```

```text
$ psql "host=db.lab02.local port=5433 dbname=lab01 user=app_lab02 sslmode=require"
     servidor      | puerto | ssl | version 
-------------------+--------+-----+---------
 SERVIDOR-IMPOSTOR |   5433 | t   | TLSv1.3
(1 row)
```

```text
$ psql "host=db.lab02.local port=5433 dbname=lab01 user=app_lab02 sslmode=verify-ca sslrootcert=entorno/tls/ca.crt"
psql: error: connection to server at "db.lab02.local" (127.0.0.1), port 5433 failed: SSL error: certificate verify failed
```

```text
$ psql "host=db.lab02.local port=5433 dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt"
psql: error: connection to server at "db.lab02.local" (127.0.0.1), port 5433 failed: SSL error: certificate verify failed
```

```text
$ openssl s_client -starttls postgres -connect 127.0.0.1:5433 -servername db.lab02.local </dev/null | openssl x509 -noout -subject -issuer
subject=CN = localhost
issuer=CN = localhost
```

### E. Lo que viaja por la red (Actividad 4)

```text
$ psql "host=127.0.0.1 dbname=lab01 user=app_lab02 sslmode=disable" -c "SELECT nombre, correo, rfc FROM clientes WHERE id = 1;"
  nombre   |         correo         |      rfc      
-----------+------------------------+---------------
 Ana López | ana.lopez@example.test | LOAA850315ABC
(1 row)

-- Lo que ve alguien que captura el tráfico de red (tcpdump -i lo -A port 5432), filtrado:
Ana L..pez....ana.lopez@example.test....LOAA850315ABCC....SELECT
SELECT nombre, correo, rfc FROM clientes WHERE id = 1;
user.app_lab02.database.lab01
-- Paquetes capturados: 17

-- ¿La contraseña de app_lab02 aparece en la captura SIN TLS? (búsqueda del valor real)
0 coincidencias: el método SCRAM-SHA-256 no envía la contraseña, sino una prueba criptográfica.
```

```text
$ psql "host=db.lab02.local dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt" -c "SELECT nombre, correo, rfc FROM clientes WHERE id = 1;"
  nombre   |         correo         |      rfc      
-----------+------------------------+---------------
 Ana López | ana.lopez@example.test | LOAA850315ABC
(1 row)

-- Búsqueda de los mismos textos en la captura:
$ tcpdump -r con-tls.pcap -A | grep -caE 'SELECT nombre|ana.lopez|LOAA850315ABC|app_lab02'
0
-- Paquetes capturados: 25
-- Muestra de bytes capturados (inicio de la negociación TLS; 16 03 01 = registro TLS de tipo handshake):
	0x0030:  5ac4 be2c 1603 0101 3701 0001 3303 03c7
	0x0040:  f6a7 6208 91fd ccae c188 5a2d e9bc 4a41
	0x0050:  7949 9a6b 4a13 d393 a8b6 d54c 0c42 f420
```

```text
$ psql "host=127.0.0.1 dbname=lab01 user=app_lab02 sslmode=disable"
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "127.0.0.1", user "app_lab02", database "lab01", no encryption
```

### Capturas de ejecución

Ejecución en el equipo del estudiante (Windows, usuario `crist`, equipo `DESKTOP-GHVPR5B`) con el entorno Docker de `entorno/`, el 2026-10-27. Las capturas complementan los resultados en texto de arriba.

**Contenedor `lab-postgres` en ejecución**

![Contenedor `lab-postgres` en ejecución](capturas/00-entorno.png)

**Sesión local por socket: `ssl = f`**

![Sesión local por socket: `ssl = f`](capturas/05-tls-socket.png)

**Sesión por red con `verify-full`: TLSv1.3**

![Sesión por red con `verify-full`: TLSv1.3](capturas/06-tls-red-verify-full.png)

**`disable` rechazado, nombre incorrecto rechazado, `verify-full` correcto**

![`disable` rechazado, nombre incorrecto rechazado, `verify-full` correcto](capturas/07-sslmode.png)

## Análisis

### Actividad 4: ¿qué sucede con la información mientras viaja?

La prueba E lo responde con datos. **Sin TLS**, quien pueda observar el tráfico (otro equipo en la misma red, un switch o router comprometido, un Wi-Fi público) lee en texto claro la consulta completa (`SELECT nombre, correo, rfc ...`), los resultados (`Ana López`, `ana.lopez@example.test`, `LOAA850315ABC`) y el usuario y la base de datos de la conexión. **Con TLS**, la misma consulta y el mismo resultado no aparecen en ningún paquete (0 coincidencias): solo hay bytes cifrados.

La contraseña no apareció ni siquiera sin TLS, porque SCRAM-SHA-256 envía una prueba criptográfica y no la contraseña. Pero con el método `password` sí viajaría en texto claro. Además, los datos de la consulta quedan expuestos de todos modos. SCRAM protege la contraseña; TLS protege **toda** la comunicación.

### 11.1 Preguntas

1. **¿La conexión actual utiliza TLS?** Depende de cómo se conecta:
   - Por **socket local** (prueba A, `docker exec`): `ssl = f` e `inet_client_addr` vacío. No hay red, los datos no salen del equipo, así que TLS no aplica.
   - Por **red** (prueba B, la forma en que se conecta una aplicación): `ssl = t`. Además, `pg_hba.conf` hace que **no exista otra opción**: `sslmode=disable` se rechaza (C1).
2. **¿Qué versión de TLS?** `TLSv1.3`. El servidor tiene `ssl_min_protocol_version = TLSv1.2`, así que no acepta versiones obsoletas (SSL 3.0, TLS 1.0 y 1.1); cliente y servidor negociaron la más reciente.
3. **¿Qué algoritmo de cifrado aparece?** `TLS_AES_256_GCM_SHA384` con 256 bits: AES con clave de 256 bits en modo GCM, que da confidencialidad e integridad, y SHA-384 en la derivación de claves de la sesión.
4. **Diferencia entre una conexión con TLS y una sin TLS.** Sin TLS, consultas, resultados y metadatos viajan legibles y se pueden **modificar** en el camino sin que nadie lo note. Con TLS, el contenido viaja cifrado (confidencialidad), cualquier alteración se detecta (integridad) y, con `verify-full`, el cliente comprueba que habla con el servidor correcto (autenticación).

### Actividad 6

La conexión por `psql` usó `host=db.lab02.local port=5432 dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=entorno/tls/ca.crt` y `pg_stat_ssl` confirmó `ssl = t`, `TLSv1.3`, `TLS_AES_256_GCM_SHA384`. También apareció una restricción: `app_lab02` no puede ejecutar `SHOW ssl_min_protocol_version` ("Only roles with privileges of the pg_read_all_settings role may examine this parameter"). Un usuario de aplicación no necesita ver la configuración del servidor, así que esa consulta quedó solo para el administrador.

### 13. `sslmode`: cifrar no es lo mismo que verificar con quién hablo

La prueba D es la más importante del laboratorio. Con **`sslmode=require`**, el cliente se conectó al **servidor impostor** (`SERVIDOR-IMPOSTOR`, puerto 5433) por TLS 1.3 sin ninguna advertencia. La conexión estaba "cifrada", pero cifrada **con el atacante**: un ataque de intermediario (*man-in-the-middle*) recibiría las consultas, los datos y, según el método de autenticación, las credenciales.

- **`require`** solo exige cifrado. No revisa quién firmó el certificado ni para qué nombre es (C3, D1).
- **`verify-ca`** comprueba que el certificado lo firmó una CA de confianza. Rechazó al impostor (D2) y una CA distinta (C6), pero aceptó un nombre que no está en el certificado (C5). Si un atacante consiguiera **otro** certificado válido de la misma CA, para otro servidor, `verify-ca` lo aceptaría.
- **`verify-full`** comprueba la CA **y** que el nombre usado para conectarse esté en el certificado: rechazó `postgres` (C7) y la IP `127.0.0.1` (C8), y solo aceptó `db.lab02.local` (C10). Es el único modo que garantiza que el cliente habla con **el** servidor que espera.

Dos detalles prácticos que mostraron las pruebas:

- **C4:** si se indica `sslrootcert`, libpq trata `require` como `verify-ca` (compatibilidad con versiones antiguas). Esto confunde fácilmente, así que conviene escribir explícitamente `verify-full`.
- **C9:** `verify-full` sin CA configurada falla en lugar de conectarse sin verificar. Es lo correcto: falla de forma segura.

Por eso, en este entorno el certificado se emitió para un **nombre** (`db.lab02.local`) y las aplicaciones deben conectarse por ese nombre, no por IP.

## Conclusión

TLS quedó configurado y **obligatorio** para toda conexión por red: el servidor usa TLS 1.3 con AES-256-GCM, no acepta versiones anteriores a TLS 1.2 y `pg_hba.conf` rechaza cualquier conexión sin cifrar. La captura de tráfico comprobó que sin TLS se leen consulta y resultados (RFC incluido) y con TLS no. La prueba del impostor demostró que cifrar no basta: con `require` el cliente puede estar cifrando la comunicación con un atacante. Solo `verify-full`, con una CA de confianza y un certificado emitido para el nombre del servidor, garantiza confidencialidad, integridad **y** autenticación del servidor. TLS protege los datos en tránsito; no reemplaza a los permisos ni al cifrado de los datos almacenados.
