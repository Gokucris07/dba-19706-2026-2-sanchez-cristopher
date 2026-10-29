# Evidencia 08 — Análisis de un escenario de seguridad

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| **Actividad** | 15. Actividad 8 — Analizar un escenario de seguridad |
| **Fecha** | 2026-10-27 |

## Objetivo

Evaluar un escenario en el que el control de acceso está bien configurado, pero contraseñas, datos sensibles, comunicaciones, claves y respaldos no tienen protección. Identificar los riesgos, el mecanismo adecuado para cada elemento y el problema más crítico.

## Comando o procedimiento

Análisis del escenario del enunciado, contrastado con lo que se **comprobó en la práctica** en las actividades anteriores. Cada riesgo se relaciona con la evidencia que lo demuestra en este laboratorio.

**Escenario.** La empresa almacena nombre, correo, contraseña, RFC, información financiera y claves criptográficas. Usuarios y roles están bien configurados, pero:

1. las contraseñas están en texto claro;
2. el RFC está en texto claro;
3. las conexiones no validan adecuadamente al servidor;
4. las claves criptográficas aparecen en archivos SQL;
5. los respaldos se almacenan sin protección.

## Resultado obtenido

### Pregunta 1 — ¿Cuáles son los principales riesgos?

| # | Debilidad | Riesgo concreto | Comprobado en |
|---|---|---|---|
| 1 | Contraseñas en texto claro | Cualquier lectura de la tabla (un DBA, un respaldo, una inyección SQL, una réplica) entrega las contraseñas listas para usarse: suplantación de usuarios y, por reutilización, acceso a otros sistemas (correo, banca). Una fuga de datos se vuelve una fuga de credenciales. | 01: `SELECT * FROM usuarios_insegura` devuelve `Password123` |
| 2 | RFC en texto claro | Exposición de un identificador oficial que revela fecha de nacimiento e iniciales; permite fraude fiscal y suplantación de identidad. Combinado con nombre y correo da un perfil completo. | 07: el RFC aparece legible en un `pg_dump` |
| 3 | Conexiones sin validar al servidor | Ataque de intermediario: un servidor falso intercepta consultas, resultados y, según el método de autenticación, credenciales. Si además no hay TLS, cualquiera en la red lee el tráfico. | 04: con `require` el cliente se conectó al **servidor impostor**; sin TLS se capturaron la consulta y el RFC |
| 4 | Claves en archivos SQL | Quien acceda al repositorio, a una copia del script, al historial de Git o a los registros puede descifrar todos los datos protegidos con esa clave. El cifrado deja de tener efecto. | 03: la clave quedó en el archivo, en el log del servidor y en el historial de Git después de borrarla |
| 5 | Respaldos sin protección | Una copia completa de toda la base (contraseñas, RFC, información financiera) fuera del servidor, donde no aplican los permisos. Es el objetivo más rentable para un atacante y el más fácil de extraviar (disco externo, nube mal configurada). | 07: el respaldo contiene `Password123`, el RFC y el correo en texto claro |

Además, la **información financiera** sin cifrar tiene el mismo riesgo que el RFC pero con impacto directo en dinero (fraude, extorsión) y obligaciones regulatorias más estrictas. Y el escenario **se encadena**: la clave en un script permite descifrar datos, el respaldo sin cifrar evita incluso tener que descifrar y la conexión sin validación permite robar credenciales nuevas.

### Pregunta 2 — ¿Qué mecanismo utilizarías para cada elemento?

| Elemento | Mecanismo |
|---|---|
| **Nombre** | Control de acceso por rol y vistas (enmascaramiento, LAB-01); TLS en tránsito; respaldo cifrado. No necesita cifrado de columna en la mayoría de los casos, pero sí minimización: mostrarlo solo a quien lo necesita. |
| **Correo electrónico** | Igual que el nombre: vistas con enmascaramiento para áreas que no lo necesitan completo, TLS y respaldo cifrado. |
| **Contraseña** | Derivación de claves para contraseñas en la aplicación (Argon2id o bcrypt con costo actual), sal única por usuario. Migración: forzar el cambio de contraseña o recalcular el hash en el siguiente inicio de sesión, y eliminar la columna en texto claro de la tabla **y de los respaldos**. Para los roles de PostgreSQL: `password_encryption = scram-sha-256`. |
| **RFC** | Cifrado de columna (AES-256), preferentemente en la aplicación, con la clave en un KMS; acceso al dato descifrado solo para los roles que lo necesitan (facturación). Seudonimización o enmascaramiento para las demás áreas. |
| **Información financiera** | Cifrado de columna con una clave **distinta** a la del RFC (si se expone una, no se exponen todos los datos), control de acceso estricto, auditoría de quién consulta, y tokenización si el dato es de tarjetas. |
| **Claves criptográficas** | Sacarlas de los archivos SQL y del repositorio; guardarlas en un gestor de secretos o KMS. **Rotar** todas las claves que estuvieron en archivos (deben considerarse comprometidas) y volver a cifrar los datos. Aplicar la política de la evidencia 10. |
| **Conexiones** | TLS obligatorio (`hostssl` y `hostnossl ... reject` en `pg_hba.conf`, `ssl_min_protocol_version = TLSv1.2`), certificado emitido por una CA de confianza para el nombre del servidor y clientes configurados con `sslmode=verify-full`. |
| **Respaldos** | Cifrado del respaldo con una clave propia guardada aparte, almacenamiento con acceso restringido y copia fuera del sitio, retención definida, transferencia cifrada y pruebas periódicas de restauración (un respaldo que no se puede descifrar tampoco sirve). |

### Pregunta 3 — ¿Cuál es el problema más crítico y por qué?

**Las contraseñas en texto claro.** Es el más crítico por cuatro razones:

1. **El daño sale de la empresa.** El RFC o un respaldo expuestos dañan la información de esta organización; las contraseñas en claro dañan también **otras** cuentas de los usuarios, porque mucha gente reutiliza contraseñas. El impacto no se puede contener.
2. **No hay ninguna barrera.** Para el RFC cifrado haría falta la clave; para la contraseña en claro basta un `SELECT`, un respaldo o una inyección SQL. No requiere ningún paso adicional.
3. **Da acceso, no solo información.** Con las credenciales el atacante entra como usuario legítimo, puede modificar datos y sus acciones parecen normales en la auditoría.
4. **Ninguna buena práctica lo justifica.** El sistema nunca necesita conocer la contraseña, solo verificarla; guardarla en claro es un riesgo sin ningún beneficio.

Muy cerca están las **claves en archivos SQL** y los **respaldos sin cifrar**, porque cada uno, por sí solo, anula la protección de **todos** los datos a la vez. Si la pregunta fuera qué corregir **primero** por facilidad e impacto, el orden sería: rotar las claves expuestas y sacarlas del repositorio, convertir las contraseñas a hash, cifrar los respaldos, imponer TLS con `verify-full` y cifrar RFC e información financiera.

### Pregunta 4 — ¿Usuarios y permisos correctamente configurados eliminan estos riesgos?

**No.** Los permisos controlan **quién puede ejecutar qué consulta dentro del servidor PostgreSQL**, y nada más. Ninguno de los cinco problemas pasa por ahí:

- **Respaldos:** el archivo de `pg_dump` vive fuera del servidor; ahí no existen roles ni `GRANT` (evidencia 07).
- **Red:** los permisos no impiden que alguien lea los paquetes que viajan sin TLS, ni que el cliente se conecte a un servidor falso (evidencia 04).
- **Claves en archivos:** están en el repositorio y en los registros, fuera de la base de datos (evidencia 03).
- **Usuarios autorizados:** un DBA o un rol con `SELECT` legítimo **sí** ve las contraseñas y el RFC en claro. Un permiso correcto no impide que quien lo tiene vea lo que no necesita, ni protege si esa cuenta es robada.
- **Fallos del propio control:** una inyección SQL, un error de configuración o una vulnerabilidad del servidor pueden saltarse los permisos. Las demás capas (hash, cifrado) limitan el daño cuando eso ocurre.

El control de acceso es necesario, pero es **una** capa. La protección real es en profundidad: permisos + hash de contraseñas + cifrado de datos + TLS + respaldos cifrados + gestión de claves.

## Análisis

El escenario muestra el error más común: suponer que "ya está protegido" porque los roles están bien hechos. Cada debilidad del escenario se comprobó en este laboratorio con un resultado concreto (contraseña legible, RFC en el respaldo, conexión al impostor, clave en el log y en el historial de Git), y ninguna se habría detectado revisando solo los `GRANT`. También muestra que los mecanismos dependen entre sí: cifrar el RFC no sirve si la clave está en un archivo SQL, y TLS no sirve si el cliente no valida al servidor.

## Conclusión

Los riesgos del escenario no son de **autorización**, sino de **protección de la información**: almacenamiento (contraseñas, RFC, datos financieros), transmisión (TLS sin validación), secretos (claves en scripts) y copias (respaldos). Cada uno requiere su propio mecanismo, y el más urgente es eliminar las contraseñas en texto claro, porque su impacto llega más allá de la organización. Unos permisos correctos son la base, pero no reemplazan a ninguna de las otras capas.
