# LAB-02 — Cifrado, credenciales y comunicaciones seguras

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda |
| **Matrícula** | 20434863 |
| **Grupo** | 403 |
| **Materia** | Gestión de Seguridad y Desempeño de Bases de Datos |
| **Unidad / Tema** | II — Seguridad, privacidad y control de acceso / 2.4 Cifrado, credenciales y protección de las comunicaciones |
| **Motor** | PostgreSQL 16 (16.15), extensión `pgcrypto` 1.3 |
| **Escenario** | Comercializadora Norte S.A. de C.V. (ficticia), base de datos `lab01` de LAB-01 |

## Contenido

```
lab-02-cifrado-credenciales/
├── README.md                     ← este informe
├── sql/
│   ├── 01-credenciales.sql       ← preparación, texto claro vs bcrypt, verificación, SCRAM
│   ├── 02-cifrado-datos.sql      ← pgp_sym_encrypt/decrypt, clave incorrecta, roles, clave desde variable de entorno
│   └── 03-verificacion-tls.sql   ← configuración TLS del servidor y estado de la sesión (pg_stat_ssl)
└── evidencias/
    ├── 01-credenciales.md        ← Actividad 1
    ├── 02-cifrado-datos.md       ← Actividad 2
    ├── 03-gestion-claves.md      ← Actividad 3
    ├── 04-tls.md                 ← Actividades 4, 5 y 6 y sslmode
    ├── 07-comparacion.md         ← Actividad 7 (incluye prueba de respaldo cifrado)
    ├── 08-analisis-escenario.md  ← Actividad 8
    ├── 09-verificacion-secretos.md ← Actividad 9
    ├── 10-politica-claves.md     ← Actividad 10
    └── capturas/                 ← capturas de la ejecución en el equipo del estudiante (PNG)
```

La configuración del servidor (TLS, `pg_hba.conf`, certificados, variables) está en `../../entorno/`, porque se comparte con los demás laboratorios de la unidad.

## Cómo ejecutar
   **Requisito:** la tabla `clientes` del LAB-01 en la base `lab01`. Se crea con `../lab-01-proteccion-privacidad/sql/01-clasificacion.sql`.
Con el entorno preparado (ver `README.md` en la raíz del repositorio):

```bash
# Como administrador, por socket dentro del contenedor
docker exec -u postgres lab-postgres psql -d lab01 -e -f /unidad-02/lab-02-cifrado-credenciales/sql/01-credenciales.sql
docker exec -u postgres lab-postgres psql -d lab01 -e -f /unidad-02/lab-02-cifrado-credenciales/sql/02-cifrado-datos.sql
docker exec -u postgres lab-postgres psql -d lab01 -e -f /unidad-02/lab-02-cifrado-credenciales/sql/03-verificacion-tls.sql

# Como aplicación, por red, con TLS y verificación completa del servidor
docker compose -f entorno/docker-compose.yml --profile cliente run --rm cliente \
  "host=db.lab02.local dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=/tls/ca.crt" \
  -e -f /unidad-02/lab-02-cifrado-credenciales/sql/03-verificacion-tls.sql
```

Los scripts se pueden ejecutar varias veces: recrean sus tablas y reutilizan los roles existentes. La contraseña de `app_lab02` y la clave del RFC se leen de las variables `LAB02_APP_PASSWORD` y `LAB02_CLAVE_RFC` (archivo `entorno/.env`, que no se sube al repositorio).

---

## 1. Introducción

En LAB-01 se controló **quién** puede ver cada dato (roles, vistas, seudonimización). Pero una base con permisos bien configurados todavía puede exponer información por cinco caminos que los permisos no cubren:

- contraseñas guardadas de forma recuperable;
- datos sensibles legibles para quien obtenga la tabla, un volcado o un respaldo;
- información que viaja por la red sin cifrar o hacia un servidor no verificado;
- claves criptográficas escritas en scripts, repositorios o registros;
- respaldos sin protección.

Este laboratorio aplica a cada problema el mecanismo que le corresponde: derivación de claves para las **credenciales**, cifrado simétrico para los **datos almacenados**, TLS con verificación completa para las **comunicaciones** y gestión de claves para los **secretos**. Cada mecanismo se verificó con resultados reales, incluidas las pruebas de lo que pasa cuando falta.

## 2. Protección de credenciales

| | Texto claro | Hash / derivación de contraseña | Cifrado |
|---|---|---|---|
| **Qué se guarda** | La contraseña tal cual | Un valor derivado con sal y costo (`$2a$06$<sal><hash>`) | La contraseña transformada con una clave |
| **¿Se puede recuperar el original?** | Sí, se lee directo | **No**, no existe función inversa | Sí, con la clave |
| **Cómo se verifica** | Comparando textos | Recalculando con la misma sal y comparando | Descifrando y comparando |
| **Si se filtra la tabla** | Todas las contraseñas expuestas | El atacante debe adivinar cada contraseña, y cada intento es costoso | Si también se filtra la clave, **todas** las contraseñas a la vez |
| **¿Apropiado para contraseñas?** | Nunca | **Sí** | No |

Resultados (evidencia 01):

- `usuarios_insegura` devolvió `Password123` con un `SELECT`.
- `crypt('Password123', gen_salt('bf'))` dio un valor distinto en cada ejecución por la sal aleatoria; `md5('Password123')` dio siempre `42f749ade7f9e195bf475f37a44cafcb`.
- Dos usuarios con la misma contraseña tienen hashes distintos.
- La verificación devolvió `t` con la contraseña correcta y `f` con la incorrecta, sin recuperar nunca la original.
- El costo de bcrypt se midió: ≈ 4 ms con costo 6 y ≈ 245 ms con costo 12, frente a ≈ 0.35 ms de MD5. Para un usuario es imperceptible; para la fuerza bruta es un multiplicador.
- PostgreSQL aplica la misma idea a sus roles: `app_lab02` quedó guardado como `SCRAM-SHA-256$4096:<sal>...`.

## 3. Protección de datos sensibles

Se protegió el **RFC** porque es un identificador oficial que revela fecha de nacimiento e iniciales, permite fraude fiscal y, a diferencia de una contraseña, la organización **necesita recuperarlo** (facturación). Por eso le corresponde **cifrado** y no hash.

Resultados (evidencia 02):

- Con `pgp_sym_encrypt()` el RFC (13 bytes) se guardó como 79 bytes ilegibles; cifrar dos veces el mismo valor dio resultados distintos.
- `pgp_sym_decrypt()` con la clave correcta devolvió `LOPA900101ABC`; con una incorrecta, `ERROR: Wrong key or corrupt data`.
- Un rol con `SELECT` pero sin clave solo ve bytes; con la clave ve el RFC. Un rol sin `SELECT` es rechazado aunque conozca la clave. Cifrado y control de acceso son **complementarios**.
- Versión mejorada (sección 9.3): los RFC de los 5 clientes de LAB-01 se cifraron con AES-256 (`cipher-algo=aes256`, cabecera `c30d0409`) y una clave leída de una variable de entorno; la clave no aparece en el script ni en las salidas.

## 4. TLS

TLS resuelve la protección **en tránsito**: **confidencialidad** (nadie lee la comunicación), **integridad** (se detectan modificaciones) y **autenticación del servidor** (el cliente sabe con quién habla, si lo verifica).

Configuración aplicada (`entorno/`): CA de laboratorio y certificado de servidor para `localhost` y `db.lab02.local`; `ssl=on`; `ssl_min_protocol_version=TLSv1.2`; `pg_hba.conf` con `hostssl ... scram-sha-256` y `hostnossl ... reject`.

Lo que se verificó (evidencia 04):

- `SHOW ssl` = `on`. Por socket local, `pg_stat_ssl` muestra `ssl = f` (no hay red). Por red, `ssl = t`, **TLSv1.3**, **TLS_AES_256_GCM_SHA384**, 256 bits.
- `sslmode=disable` es **rechazado** por `pg_hba.conf`: no se puede conectar por red sin TLS.
- **Captura de tráfico:** sin TLS se leyeron en la red la consulta, el nombre, el correo y el RFC; con TLS, 0 coincidencias.
- **Matriz de `sslmode`:** `require` cifra pero no verifica; `verify-ca` verifica la CA pero no el nombre; `verify-full` rechazó un nombre que no está en el certificado, la conexión por IP, otra CA y la ausencia de CA, y solo conectó con `db.lab02.local` y la CA correcta.
- **Servidor impostor:** con `require`, el cliente se conectó por TLS 1.3 a un PostgreSQL falso sin advertencia; con `verify-ca` y `verify-full` fue rechazado. **Cifrar no es lo mismo que verificar con quién se habla.**

## 5. Gestión de claves

Las claves no deben guardarse junto con los scripts porque **el script viaja**: se sube al repositorio, se copia, se comparte, se documenta y se respalda. Cada copia es una copia de la clave, y con ella cualquiera descifra todos los datos protegidos.

Lo que se comprobó (evidencia 03):

- La clave escrita en `ejemplo-mala-practica.sql` quedó en texto claro en el archivo y, con `log_statement = all`, también en el **registro del servidor**.
- En un repositorio desechable, una clave borrada en un segundo commit se recuperó completa con `git show HEAD~1:config.ini`: **borrarla no la elimina del historial**.
- Leer la clave desde una variable de entorno (`\getenv`) la saca del repositorio (0 coincidencias), pero la clave **sigue llegando al servidor** dentro de la consulta y quedó en el log. Con `pgcrypto`, el servidor necesita la clave; la solución de fondo es cifrar en la aplicación con la clave en un KMS.
- El archivo de demostración estaba cubierto por `.gitignore` y se eliminó antes de cualquier commit: no existe en el historial.

La evidencia 10 define una política de 10 reglas para el ciclo de vida de las claves.

## 6. Resultados

| Necesidad | Mecanismo | Resultado verificado |
|---|---|---|
| Credenciales | bcrypt (`crypt` + `gen_salt('bf')`); SCRAM-SHA-256 en roles | Contraseña no recuperable; hashes distintos para contraseñas iguales; verificación `t`/`f` correcta |
| Datos sensibles | `pgp_sym_encrypt` (AES-128 del enunciado y AES-256 en la versión mejorada) | RFC ilegible sin la clave; clave incorrecta rechazada; 5 RFC de LAB-01 cifrados y descifrados correctamente |
| Gestión de claves | Variables de entorno, `.gitignore`, `.env.example`, `ECHO none` | Ningún secreto real en el repositorio; exposición por log y por historial de Git demostrada |
| Comunicaciones | TLS 1.3 obligatorio + `verify-full` | Conexión sin TLS rechazada; tráfico ilegible con TLS; impostor rechazado con `verify-full` |
| Respaldos | `pg_dump` + `openssl enc -aes-256-cbc -pbkdf2` | Respaldo sin cifrar expone contraseña, RFC y correo; cifrado, 0 coincidencias y `bad decrypt` con clave incorrecta |
| Revisión de secretos | `grep -RniE` antes del commit | Todas las coincidencias revisadas y clasificadas (evidencia 09) |

## 7. Problemas encontrados

1. **El usuario de aplicación no puede ver `ssl_min_protocol_version`.** Al ejecutar el script 03 como `app_lab02`: `ERROR: permission denied to examine "ssl_min_protocol_version"` (*Only roles with privileges of the "pg_read_all_settings" role may examine this parameter*). PostgreSQL 16 restringe ese parámetro. **Solución:** esa consulta, junto con las rutas de certificados y `pg_hba_file_rules`, se ejecuta solo si el usuario es administrador (`\if :es_superusuario`). No se le dio a la aplicación un privilegio que no necesita.
2. **El script 01 fallaba al ejecutarse por segunda vez.** `DROP ROLE app_lab02` no es posible cuando el rol ya tiene privilegios (`GRANT CONNECT`). **Solución:** el rol se crea solo si no existe y en cada ejecución se actualiza su contraseña con `ALTER ROLE`.
3. **La opción `-e` de `psql` habría impreso la contraseña y la clave.** Con el eco activado, `psql` muestra la consulta ya con la variable sustituida. **Solución:** `\set ECHO none` antes de las sentencias con secretos y `\set ECHO queries` después; se verificó que el valor real no aparece en ninguna salida ni evidencia.
4. **La clave llega al log aunque venga de una variable de entorno.** No es un error del script, sino una limitación del cifrado en el servidor: documentada y analizada en la evidencia 03.
5. **`sslmode=require` con `sslrootcert` no se comporta como "solo cifrar".** Si se indica una CA, libpq lo trata como `verify-ca` (compatibilidad con versiones anteriores). Se documentó en la evidencia 04 y por eso se usa explícitamente `verify-full`.
6. **`verify-full` rechaza conexiones por IP.** El certificado se emitió para nombres (`localhost`, `db.lab02.local`), no para `127.0.0.1`. **Solución:** conectarse por el nombre del servidor; en Docker, `db.lab02.local` es un alias de red del contenedor.
7. **Para demostrar el tráfico sin TLS hubo que abrir una excepción.** Como `pg_hba.conf` rechaza conexiones sin cifrar, la captura de la evidencia 04 requirió una regla `hostnossl` temporal (solo `app_lab02` desde `127.0.0.1`) y un `GRANT SELECT` temporal. Ambos se revirtieron, y se comprobó que la conexión sin TLS vuelve a ser rechazada.
8. **Permisos de la clave privada del servidor en Docker sobre Windows.** PostgreSQL exige que `server.key` pertenezca a su usuario y tenga permisos `600`, y los archivos montados desde Windows no conservan permisos. **Solución:** el `entrypoint` del contenedor copia los certificados a una ruta interna y ajusta dueño y permisos antes de arrancar el servidor.

## 8. Conclusiones

La lección principal es que **cada problema tiene su mecanismo y ninguno sustituye a otro**. Las contraseñas se derivan, no se cifran, porque nunca hay que recuperarlas. El RFC se cifra porque sí hay que recuperarlo. TLS protege el dato solo mientras viaja, y solo si el cliente verifica al servidor: la prueba del impostor mostró que una conexión cifrada puede estar cifrada con el atacante. Y todo el cifrado depende de dónde está la clave: en un script, en un log o en el historial de Git, deja de proteger.

También quedó claro que el control de acceso de LAB-01 sigue siendo necesario, pero no alcanza: un respaldo, el tráfico de red o un script con una clave están fuera del alcance de `GRANT` y `REVOKE`.

**Medidas para un entorno productivo:**

- Contraseñas de aplicación con Argon2id o bcrypt (costo actual) desde el framework; `password_encryption = scram-sha-256` y nunca `password` ni `trust` por red.
- Cifrado de columnas sensibles en la aplicación, con una clave por tipo de dato guardada en un KMS y rotación periódica.
- TLS obligatorio (`hostssl`, `hostnossl ... reject`, TLS ≥ 1.2), certificados de una CA corporativa con renovación automatizada y todos los clientes con `sslmode=verify-full`.
- Respaldos cifrados con clave propia, almacenados aparte, con pruebas de restauración.
- Gestor de secretos para contraseñas y claves; `.gitignore` y escaneo automático de secretos en el repositorio (pre-commit y CI); rotación inmediata ante cualquier exposición.
- Registros del servidor protegidos y sin `log_statement = all` en sesiones que manejan claves.

---

## Verificación final (sección 18)

- **Credenciales: ¿una contraseña se cifra o se protege con derivación de claves?** Con **derivación de claves para contraseñas** (bcrypt, scrypt, Argon2id; SCRAM en PostgreSQL). Cifrarla la haría recuperable para quien tenga la clave.
- **Datos sensibles: ¿enmascaramiento, seudonimización y cifrado?** El **enmascaramiento** oculta parte del valor al mostrarlo; el dato original sigue intacto (LAB-01). La **seudonimización** reemplaza el identificador por un token y guarda la relación en un mapa protegido; se revierte con el mapa (LAB-01). El **cifrado** transforma el propio dato almacenado para que sea ilegible sin la clave; se revierte con la clave (LAB-02).
- **Comunicaciones: ¿qué problema resuelve TLS?** La exposición y manipulación de la información mientras viaja por la red, y la suplantación del servidor cuando se usa `verify-full`.
- **Claves: ¿dónde debe almacenarse una clave en un entorno real?** En un gestor de secretos, KMS o HSM, separada de los datos, del código y de los respaldos, con acceso mínimo y auditado.
- **Repositorio: ¿es correcto subir una contraseña o clave real a GitLab aunque el repositorio sea privado?** **No.** Un repositorio privado reduce la exposición, pero no convierte un secreto en información apropiada para guardar dentro del código: el historial lo conserva, se clona en cada equipo y su acceso no está diseñado para proteger secretos.

## Preguntas de reflexión (sección 23)

1. **¿Por qué una contraseña no debe almacenarse como texto claro?**
   Porque cualquier lectura de la tabla (un DBA, un respaldo, una inyección SQL) la entrega lista para usarse, y por la reutilización de contraseñas el daño llega a otras cuentas del usuario. El sistema no necesita conocerla, solo verificarla. En la evidencia 01, un `SELECT` bastó para obtener `Password123`.

2. **¿Por qué un hash no es equivalente a un cifrado?**
   Porque el hash es de **una vía**: no tiene clave ni función inversa, y solo permite recalcular y comparar. El cifrado es **reversible** por diseño, con la clave. `crypt()` no se puede revertir; `pgp_sym_decrypt()` sí devolvió el RFC original. Por eso el hash sirve para verificar y el cifrado para guardar y recuperar.

3. **¿Por qué el cifrado de una columna no sustituye al control de acceso?**
   Porque quien tiene permiso de lectura **y** la clave ve el dato en claro (evidencia 02: `consulta_lab02` con la clave vio el RFC), y porque el cifrado no impide modificar, borrar ni leer las demás columnas. Los permisos deciden quién llega al dato; la clave decide quién lo entiende. Son barreras distintas y se necesitan las dos.

4. **¿Por qué TLS no sustituye a los mecanismos de autorización de PostgreSQL?**
   Porque TLS protege el **canal**, no decide **qué** puede hacer quien está al otro lado. Un usuario conectado por TLS 1.3 con `verify-full` puede ejecutar cualquier consulta que sus permisos le permitan; TLS solo garantiza que nadie más la lea o la altere en el camino. Además, al llegar al servidor el dato se descifra: TLS no protege lo almacenado.

5. **¿Qué ocurriría si una organización pierde una clave utilizada para cifrar información?**
   La información cifrada con ella se vuelve **irrecuperable**. No hay forma de "saltarse" el cifrado: con una clave distinta, `pgp_sym_decrypt` responde `Wrong key or corrupt data` y `openssl` responde `bad decrypt`. Para la organización equivale a perder los datos, incluidos los de los respaldos cifrados con esa clave. Por eso las claves necesitan respaldo propio, separado y probado (política R7).

6. **¿Qué ocurriría si una clave criptográfica se publica accidentalmente en GitLab?**
   Debe considerarse comprometida de inmediato: cualquiera con acceso al repositorio o a sus clones puede descifrar los datos si los obtiene. Borrar el archivo no basta, porque el historial la conserva (evidencia 03: se recuperó con `git show HEAD~1:config.ini`). Hay que rotarla, volver a cifrar los datos con una clave nueva, revisar los accesos del periodo expuesto, limpiar el historial cuando sea posible y documentar el incidente (política R8 y R9).

7. **¿Por qué un repositorio privado no debe considerarse un almacén de secretos?**
   Porque su propósito es compartir y versionar código, no proteger secretos. Lo clonan todos los colaboradores y sistemas de CI, cada clon guarda todo el historial, los permisos suelen ser amplios (todo el equipo lee todo), los secretos no se pueden rotar ni revocar desde ahí, no hay auditoría de quién usa cada secreto, y un repositorio privado puede volverse público por error o filtrarse con una cuenta comprometida.

8. **¿Qué diferencia existe entre proteger información almacenada y proteger información durante su transmisión?**
   La protección **en reposo** (hash, cifrado de columna, respaldos cifrados) actúa sobre el dato guardado en disco, tablas o copias, y protege contra quien obtenga esos archivos. La protección **en tránsito** (TLS) actúa sobre el canal entre cliente y servidor, y protege contra quien observe o altere la red. Cada una deja expuesto lo que cubre la otra: con TLS, el dato se guarda tal cual; con cifrado en reposo, el resultado de la consulta viaja en claro si no hay TLS (evidencia 04, prueba E). Se necesitan las dos.

9. **¿Por qué la gestión de claves es tan importante como el algoritmo criptográfico?**
   Porque los algoritmos modernos (AES-256, bcrypt) no se rompen en la práctica: los ataques reales consisten en **obtener la clave**. Una clave en un script, en un log o en el historial de Git anula el mejor algoritmo; una clave perdida destruye los datos. En este laboratorio, todas las fallas observadas fueron de gestión (clave en archivo, en log, en historial), ninguna del algoritmo.

10. **¿Qué mecanismo adicional implementarías para proteger los respaldos?**
    **Cifrado de los respaldos** con una clave exclusiva guardada en un KMS (no junto al respaldo ni junto a la base), como se probó en la evidencia 07 con `openssl enc -aes-256-cbc -pbkdf2`. Lo complementaría con: almacenamiento inmutable o con versiones para resistir ransomware, copia fuera del sitio (regla 3-2-1), acceso restringido y auditado al repositorio de respaldos, transferencia por canal cifrado, retención definida con eliminación segura y **pruebas periódicas de restauración**, incluida la recuperación de la clave.
