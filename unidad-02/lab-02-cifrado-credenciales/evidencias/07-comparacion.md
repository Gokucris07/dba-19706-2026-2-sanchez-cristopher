# Evidencia 07 — Protección en reposo frente a protección en tránsito

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| **Actividad** | 14. Actividad 7 — Comparar protección en reposo y protección en tránsito |
| **Entorno** | PostgreSQL 16.15, base de datos `lab01`; `pg_dump` y `openssl` para la prueba de respaldos |
| **Fecha de ejecución** | 2026-10-27 |

## Objetivo

Relacionar cada tipo de información con el mecanismo criptográfico que le corresponde, distinguiendo entre datos **almacenados** (en reposo) y datos **transmitidos** (en tránsito), y explicar qué protege cada mecanismo.

## Comando o procedimiento

La tabla se completó con los resultados de las actividades anteriores (evidencias 01 a 04). Para la fila de respaldos, que no se había probado, se hizo una prueba adicional: se generó un respaldo con `pg_dump`, se buscaron datos sensibles en él, se cifró con `openssl enc -aes-256-cbc -pbkdf2` (clave tomada de una variable de entorno, no guardada en el repositorio) y se intentó restaurarlo con la clave correcta y con una incorrecta.

## Resultado obtenido

### Tabla comparativa

| Situación | Mecanismo apropiado | ¿Qué protege? | ¿En reposo o en tránsito? | Evidencia |
|---|---|---|---|---|
| **Contraseña de usuario** | Derivación de claves para contraseñas: bcrypt (`crypt()` + `gen_salt('bf')`), Argon2id o scrypt en la aplicación; SCRAM-SHA-256 para los roles de PostgreSQL. **Nunca** cifrado reversible. | La **confidencialidad de la credencial**: aunque se filtre la tabla, no se obtiene la contraseña; la sal impide comparar o usar tablas precalculadas y el costo encarece la fuerza bruta. | Reposo | 01 |
| **RFC almacenado en una tabla** | **Cifrado simétrico** de la columna (`pgp_sym_encrypt()` con AES-256, o cifrado en la aplicación), con la clave fuera de la base de datos, **más** control de acceso (`GRANT`/`REVOKE`, vistas). | La **confidencialidad del dato almacenado** frente a quien lea la tabla, un volcado o un respaldo sin tener la clave. Permite recuperarlo cuando hay autorización. | Reposo | 02, 03 |
| **Consulta enviada desde un cliente al servidor** | **TLS** (1.2 como mínimo; se negoció 1.3) con `sslmode=verify-full` y certificado emitido por una CA de confianza para el nombre del servidor; `pg_hba.conf` con `hostssl`. | **Confidencialidad** (nadie lee consulta ni resultados en la red), **integridad** (se detectan modificaciones) y **autenticación del servidor** (no se habla con un impostor). | Tránsito | 04 |
| **Respaldo de una base de datos** | **Cifrado del respaldo** (`pg_dump` + `openssl`/`gpg`/`age`, o la función de cifrado de la herramienta de respaldos), con clave distinta a la de los datos y guardada aparte; almacenamiento con acceso restringido, transferencia por canal cifrado y prueba de restauración. | La **confidencialidad de una copia completa** de la base fuera del servidor (discos, nube, medios externos), donde ya no aplican los permisos de PostgreSQL. | Reposo (y en tránsito al copiarlo) | 07 (abajo) |
| **Clave criptográfica** | **Gestión de claves**: gestor de secretos o KMS/HSM, separada de los datos y del código, con acceso mínimo, rotación, respaldo y revocación (ver evidencia 10). | La **eficacia de todos los demás mecanismos**: si la clave se expone, el cifrado del RFC y de los respaldos deja de proteger; si se pierde, los datos son irrecuperables. | Reposo y uso | 03, 10 |

### Prueba de respaldos

```text
$ pg_dump -d lab01 -t clientes -t usuarios_insegura -t usuarios_segura -t clientes_rfc_cifrado > respaldo.sql
$ ls -l respaldo.sql
10339 bytes  respaldo.sql
$ grep -E "LOAA850315ABC|Password123|ana.lopez" respaldo.sql
1	Ana López	ana.lopez@example.test	6671234567	LOAA850315ABC	41	Culiacán	80000	2026-10-22
1	juan	Password123
-- Datos de la tabla con el RFC cifrado dentro del mismo respaldo (inicio de la fila):
1	\\xc30d04090302144739dc8063d3037ed23e01fb6187685b5bb4a8a7e
```

```text
$ pg_dump -d lab01 -t clientes ... | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -pass env:LAB02_CLAVE_RESPALDO -out respaldo.sql.enc
10368 bytes  respaldo.sql.enc
$ grep -caE "LOAA850315ABC|Password123|ana.lopez" respaldo.sql.enc
0
$ od -A x -t x1z -N 48 respaldo.sql.enc   (primeros 48 bytes; "Salted__" = cabecera de openssl con la sal)
000000 53 61 6c 74 65 64 5f 5f 24 45 f4 31 ea 42 57 bb  >Salted__$E.1.BW.<
000010 f3 4f cb 03 72 10 fc 79 53 99 46 98 4f 47 7d 19  >.O..r..yS.F.OG}.<
000020 de b5 69 2b 8c aa e2 fe 7b 98 f0 3b cb 04 33 60  >..i+....{..;..3`<
000030
```

```text
$ openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:LAB02_CLAVE_RESPALDO -in respaldo.sql.enc | grep -c "LOAA850315ABC"
1
$ openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass pass:CLAVE-INCORRECTA -in respaldo.sql.enc
bad decrypt
```

## Análisis

**El respaldo es una copia de todo lo que se protegió, pero sin los controles del servidor.** El `pg_dump` sin protección contiene en texto claro el RFC, el correo y, de la tabla insegura, la contraseña `Password123`. Ahí no hay `REVOKE` que valga: los permisos de PostgreSQL protegen las tablas dentro del servidor, no un archivo `.sql` copiado a otro disco. La misma prueba muestra el valor del cifrado por columna: la tabla `clientes_rfc_cifrado` aparece en el respaldo solo como bytes (`\xc30d0409...`), y la columna `password_hash` como hashes bcrypt.

Cifrado completo, el respaldo no contiene ninguno de esos textos (0 coincidencias). Empieza con la cabecera `Salted__` seguida de bytes aleatorios. Restaurarlo exige la clave, y con una clave incorrecta `openssl` responde `bad decrypt`.

**Reposo y tránsito son problemas distintos que se resuelven con mecanismos distintos:**

- TLS protege **solo mientras el dato viaja**. Al llegar al servidor, el dato se descifra y se guarda como está; si la tabla tiene el RFC en claro, TLS no lo protege en el disco ni en el respaldo.
- El cifrado en reposo protege **el dato guardado**, pero si la consulta que lo descifra viaja sin TLS, el resultado sale en claro por la red (evidencia 04, prueba E).

Una base de datos bien protegida necesita las dos protecciones. Y las dos dependen de la gestión de claves: la clave TLS privada del servidor, la clave del RFC y la del respaldo deben vivir fuera del repositorio y separadas de los datos que protegen.

## Conclusión

No hay un mecanismo único: las contraseñas se derivan (no se cifran), los datos que deben recuperarse se cifran, las comunicaciones se protegen con TLS con verificación completa, los respaldos se cifran como un activo aparte y las claves se gestionan con un proceso propio. La prueba de respaldos confirmó que un `pg_dump` sin cifrar expone todo lo que los permisos protegían dentro del servidor, y que cifrarlo, con una clave guardada aparte, lo vuelve ilegible para quien no tenga la clave.
