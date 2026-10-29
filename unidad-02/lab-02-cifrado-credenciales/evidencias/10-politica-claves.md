# Evidencia 10 — Política mínima de protección de claves criptográficas

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| **Actividad** | 17. Actividad 10 — Crear una política mínima de protección de claves |
| **Organización** | Comercializadora Norte S.A. de C.V. (ficticia) |
| **Fecha** | 2026-10-27 |

## Objetivo

Definir reglas para gestionar las claves criptográficas de la base de datos durante todo su ciclo de vida (generación, almacenamiento, acceso, rotación, respaldo, revocación, exposición accidental y eliminación), a partir de los problemas observados en este laboratorio.

## Comando o procedimiento

1. Se identificaron las claves que existen en el entorno del laboratorio: la clave del RFC (`LAB02_CLAVE_RFC`), la clave de respaldos (`LAB02_CLAVE_RESPALDO`), la clave privada TLS del servidor (`server.key`) y la clave privada de la CA (`ca.key`).
2. Para cada riesgo comprobado en las evidencias 02, 03, 04 y 07 se redactó una regla que lo previene.
3. Se verificó qué reglas ya se aplican en este repositorio.

**Alcance.** Claves criptográficas que protegen datos de la base de datos (cifrado de columnas y de respaldos) y claves privadas de los certificados TLS. Las contraseñas de usuarios no son claves: se protegen con derivación (evidencia 01).

## Resultado obtenido: la política

**R1. Generación con aleatoriedad criptográfica y de un solo propósito.**
Las claves se generan con un generador criptográficamente seguro (KMS, HSM u `openssl rand`), nunca escritas por una persona ni derivadas de palabras, nombres o fechas. Cada clave tiene un único propósito: la del RFC no cifra respaldos, la de respaldos no cifra columnas y la información financiera usa una clave distinta a la del RFC. Así, la exposición de una clave compromete un solo tipo de dato.

**R2. La clave nunca vive junto a lo que protege.**
Las claves se almacenan en un gestor de secretos o KMS, no en la base de datos, ni en el mismo servidor que los datos cifrados, ni en el mismo medio que los respaldos. Un atacante que obtenga los datos no debe obtener, en el mismo paso, la clave para leerlos.

**R3. Ningún secreto en código, scripts, repositorios ni documentación.**
Los scripts reciben las claves en tiempo de ejecución (variables de entorno inyectadas, gestor de secretos), y el repositorio solo contiene plantillas sin valores (`.env.example`). Antes de cada commit se buscan secretos y los archivos sensibles están en `.gitignore`. Un repositorio privado no es una excepción.

**R4. Acceso mínimo, nominal y auditado.**
Solo los servicios y personas que necesitan descifrar pueden usar cada clave, y de preferencia el servicio **usa** la clave en el KMS sin poder **leerla**. Ningún acceso es compartido ni anónimo: cada uso queda registrado (quién, cuándo, qué clave) y los registros se revisan. Los administradores de la base de datos no tienen, por defecto, acceso a las claves de los datos (separación de funciones).

**R5. Mantener las claves fuera de registros, salidas y capturas.**
Las sesiones que manejan claves no usan `log_statement = all` ni guardan historial de consola, las salidas de los scripts no muestran la clave (`\set ECHO none`) y no se toman capturas de pantalla con claves visibles. Siempre que sea posible, el cifrado y el descifrado se hacen en la aplicación, para que la clave no viaje al servidor de base de datos (evidencia 03: la clave llegó al log aunque viniera de una variable de entorno).

**R6. Rotación periódica y por evento.**
Las claves de datos se rotan al menos una vez al año, al cambiar el personal con acceso y siempre que se sospeche una exposición. Los certificados TLS se renuevan antes de su vencimiento (los del laboratorio duran 365 días). La rotación incluye volver a cifrar los datos con la clave nueva y conservar la anterior, solo para descifrar, hasta terminar la migración. Cada versión de clave se identifica para saber con cuál se cifró cada dato.

**R7. Respaldo de claves separado, cifrado y probado.**
Cada clave tiene un respaldo cifrado, guardado en una ubicación distinta a la de los datos y a la de sus respaldos, bajo control dual (se requieren dos personas para recuperarla). La restauración de la clave se prueba junto con las pruebas de restauración de la base. Perder una clave equivale a perder todos los datos que protege.

**R8. Revocación inmediata con procedimiento documentado.**
Si una clave deja de ser confiable (persona que se va, servidor dado de baja, sospecha de compromiso), se revoca: se desactiva en el KMS para cifrar, se emite una nueva, se vuelven a cifrar los datos y, en TLS, se revoca el certificado y se reemplaza en el servidor y en los clientes. La revocación tiene responsables y tiempos máximos definidos.

**R9. Exposición accidental: tratar la clave como comprometida.**
Si una clave aparece en un repositorio, un log, un ticket, un correo o una captura, se considera comprometida **aunque** se borre enseguida (el historial de Git la conserva, evidencia 03). Se aplica de inmediato la regla R8: rotar, volver a cifrar, revisar los registros de acceso a los datos durante el periodo expuesto, limpiar el historial donde sea posible y documentar el incidente.

**R10. Eliminación segura al final del ciclo de vida.**
Cuando una clave ya no se necesita (los datos se migraron a una clave nueva o se eliminaron por su periodo de retención, LAB-01), se destruye en el KMS y en sus respaldos, después de confirmar que ningún dato vigente depende de ella. La destrucción se registra con fecha, responsable y aprobación. Destruir la clave de datos que deben eliminarse vuelve ilegibles también las copias que pudieran quedar en respaldos antiguos.

### Cobertura de los aspectos solicitados

| Aspecto | Reglas |
|---|---|
| 1. Generación | R1 |
| 2. Almacenamiento | R2, R3 |
| 3. Acceso | R4, R5 |
| 4. Rotación | R6 |
| 5. Respaldo | R7 |
| 6. Revocación | R8 |
| 7. Exposición accidental | R9 (y R3 y R5 como prevención) |
| 8. Eliminación | R10 |

### Aplicación en este repositorio

| Regla | Cómo se aplica en el laboratorio |
|---|---|
| R1 | Las claves de prueba del entorno se generaron con `openssl rand`; los certificados, con `openssl req` (RSA 3072). |
| R2 | La clave del RFC no está en la base de datos; se recibe al ejecutar el script. |
| R3 | `.gitignore` excluye `.env`, `*.key`, `*.pem` y los certificados generados; `entorno/.env.example` solo trae `CAMBIAR`; búsqueda de secretos antes de cada commit (evidencia 09). |
| R5 | `\set ECHO none` al usar la contraseña de `app_lab02` y la clave del RFC; ninguna aparece en las evidencias. |
| R6 | Los certificados TLS tienen vigencia de 365 días. |
| R9 | La clave del ejemplo de mala práctica es ficticia y el archivo se eliminó **antes** de hacer commit. |

R4, R7, R8 y R10 requieren infraestructura que no existe en un laboratorio local (KMS, control dual, procedimientos de la organización); quedan definidas para un entorno productivo.

## Análisis

La política sigue el ciclo de vida de la clave porque los incidentes observados ocurrieron en distintas etapas: una clave **almacenada** en un script (R3), una clave que llegó a un **registro** del servidor (R5), un secreto que sigue **expuesto** después de borrarlo (R9) y un respaldo que solo se puede recuperar si existe la clave (R7). Las reglas buscan que la seguridad no dependa de una sola persona ni de un solo control. Por ejemplo, R1 y R2 limitan el daño de una exposición, R4 la hace detectable y R8 y R9 la contienen.

## Conclusión

La seguridad del cifrado depende de la clave más que del algoritmo: AES-256 no protege nada si la clave está en un script, y protege demasiado bien si la clave se pierde. Esta política de 10 reglas cubre los ocho aspectos solicitados y convierte las lecciones del laboratorio en prácticas verificables. En este repositorio ya se aplican las reglas de generación, almacenamiento fuera del código y prevención de exposición, y el resto queda definido para un entorno productivo con KMS.
