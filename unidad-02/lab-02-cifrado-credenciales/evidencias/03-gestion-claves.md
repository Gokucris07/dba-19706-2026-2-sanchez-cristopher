# Evidencia 03 — El problema de la gestión de claves

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| **Actividad** | 9. Actividad 3 — El problema de la gestión de claves |
| **Archivos** | `sql/ejemplo-mala-practica.sql` (temporal, eliminado), `sql/02-cifrado-datos.sql` (sección 9.3), `.gitignore` |
| **Entorno** | PostgreSQL 16.15, base de datos `lab01`; Git |
| **Fecha de ejecución** | 2026-10-27 |

## Objetivo

Analizar por qué una clave criptográfica escrita dentro de un script es una mala práctica, comprobar por qué medios concretos puede quedar expuesta y aplicar medidas para que el repositorio no contenga secretos.

## Comando o procedimiento

1. Se creó el archivo temporal `sql/ejemplo-mala-practica.sql` con la consulta del enunciado y se verificó si Git lo incluiría en un commit.
2. Se ejecutó el archivo en una sesión con `log_statement = all` y se buscó la clave en el registro del servidor.
3. Se repitió con la alternativa de la sección 9.3: clave leída de la variable de entorno `LAB02_CLAVE_RFC` con `\getenv`, sin escribirla en el script.
4. En un repositorio desechable se agregó un archivo con una clave, se borró en un segundo commit y se intentó recuperarla del historial (sección 4.6).
5. Se eliminó el archivo de demostración y se comprobó que nunca formó parte del historial del repositorio (9.2).

## Resultado obtenido

### Archivo de demostración

```text
$ cat sql/ejemplo-mala-practica.sql
-- Archivo de DEMOSTRACIÓN (Actividad 3). No forma parte de la entrega.
-- La clave es ficticia y aparece escrita a propósito para analizar la mala práctica.
SELECT pgp_sym_decrypt(rfc_cifrado, 'CLAVE-DE-PRUEBA') FROM clientes_protegidos;
$ grep -n "CLAVE" sql/ejemplo-mala-practica.sql
3:SELECT pgp_sym_decrypt(rfc_cifrado, 'CLAVE-DE-PRUEBA') FROM clientes_protegidos;
```

### ¿Git lo incluiría en un commit?

```text
$ git status --short --ignored unidad-02/
!! unidad-02/lab-02-cifrado-credenciales/sql/ejemplo-mala-practica.sql
$ git check-ignore -v unidad-02/lab-02-cifrado-credenciales/sql/ejemplo-mala-practica.sql
.gitignore:16:**/sql/ejemplo-mala-practica.sql	unidad-02/lab-02-cifrado-credenciales/sql/ejemplo-mala-practica.sql
```

### La clave queda en el registro del servidor

```text
-- Sesión con log_statement = all (registro de todas las sentencias, común en auditoría o depuración)
SELECT pgp_sym_decrypt(rfc_cifrado, 'CLAVE-DE-PRUEBA') FROM clientes_protegidos;
 pgp_sym_decrypt 
-----------------
 LOPA900101ABC
(1 row)


-- Lo que quedó escrito en el log del servidor:
$ grep "CLAVE-DE-PRUEBA" <log de PostgreSQL>
[919] LOG:  statement: SELECT pgp_sym_decrypt(rfc_cifrado, 'CLAVE-DE-PRUEBA') FROM clientes_protegidos;
```

### Con la clave en una variable de entorno

```text
-- La clave NO está en ningún archivo del repositorio:
$ grep -rF "<valor de LAB02_CLAVE_RFC>" . --exclude-dir=.git | wc -l
0
-- Pero SÍ llega al servidor dentro de la consulta y queda en el log (valor reemplazado por [CLAVE-OCULTA]):
[927] LOG:  statement: SELECT count(pgp_sym_decrypt(rfc_cifrado, '[CLAVE-OCULTA]')) FROM clientes_rfc_cifrado;
```

### El historial conserva un secreto aunque se borre

```text
$ echo "clave_rfc=CLAVE-DE-PRUEBA" > config.ini && git add . && git commit -m "agrega configuracion"
$ git rm config.ini && git commit -m "elimina la clave"
$ ls
(el archivo ya no existe en la carpeta)
$ git log --oneline
<hash> elimina la clave
<hash> agrega configuracion
$ git log -p --all -S "CLAVE-DE-PRUEBA" --format="commit: %s"
commit: elimina la clave
-clave_rfc=CLAVE-DE-PRUEBA
commit: agrega configuracion
+clave_rfc=CLAVE-DE-PRUEBA
$ git show HEAD~1:config.ini
clave_rfc=CLAVE-DE-PRUEBA
```

### Eliminación del archivo de demostración

```text
$ rm sql/ejemplo-mala-practica.sql
$ ls sql/
01-credenciales.sql
02-cifrado-datos.sql
$ git log --all --oneline -- "*ejemplo-mala-practica*"   (nunca formó parte del historial)
(sin resultados)
$ git log --all -S "CLAVE-DE-PRUEBA" --oneline   (commits que agregan o quitan la cadena)
feat: implementa cifrado de datos sensibles
```

## Análisis

### 9.1 ¿Qué ocurriría si esta clave fuera real y el archivo se publicara en un repositorio Git?

Quien tenga acceso al repositorio tendría la clave que protege los RFC de todos los clientes y podría descifrarlos si obtiene también los datos cifrados: un respaldo, un volcado, una réplica o un acceso de lectura a la tabla. En la práctica, el cifrado dejaría de proteger. Además:

- **No basta con borrar el archivo.** Como se demostró, después de `git rm` la clave sigue en el historial: `git show HEAD~1:config.ini` la devuelve completa, y cada clon del repositorio tiene una copia. Una vez publicada, hay que tratarla como comprometida.
- **La exposición se multiplica:** forks, clones de compañeros, respaldos del servidor Git, integraciones de CI/CD y herramientas que indexan repositorios.
- **La respuesta correcta es rotar la clave:** generar una nueva, volver a cifrar todos los datos con ella, revocar la anterior y revisar si hubo accesos. Reescribir el historial ayuda, pero no recupera las copias que ya salieron.

### Por cuántos lugares se escapa una clave escrita en la consulta

La lista del enunciado (scripts, repositorios, registros, capturas, respaldos, documentación) no es teórica. En esta actividad se comprobaron dos de esos caminos:

1. **Archivo / repositorio:** la clave queda en texto claro en `ejemplo-mala-practica.sql`.
2. **Registro de ejecución:** con `log_statement = all` el servidor escribió la consulta completa, con la clave, en su log. Quien tenga acceso a los logs (otro administrador, una herramienta de monitoreo, un sistema centralizado de logs) tiene la clave.

### La variable de entorno resuelve una parte, no todo

La alternativa de la sección 9.3 (`\getenv clave_rfc LAB02_CLAVE_RFC`) sí logra que la clave **no exista en ningún archivo del repositorio** (`grep` devolvió 0). Además, con `\set ECHO none` no aparece en la salida de `psql` ni en estas evidencias.

Pero la prueba muestra que **la clave sigue viajando al servidor dentro de la consulta** y quedó en el log como `pgp_sym_decrypt(rfc_cifrado, '[CLAVE-OCULTA]')`. Es una limitación del cifrado dentro de la base de datos con `pgcrypto`: el servidor necesita la clave para descifrar, así que la recibe. En un entorno real esto se mitiga así:

- Cifrar y descifrar en la **aplicación**, para que la clave nunca llegue a PostgreSQL.
- Obtener la clave de un **gestor de secretos o KMS** en tiempo de ejecución, con permisos y auditoría.
- No activar `log_statement = all` en las sesiones que manejan claves, y proteger el acceso a los logs.
- Usar conexiones TLS (Actividad 5), porque la clave también viaja por la red.

### Medidas aplicadas en este repositorio

| Medida | Para qué |
|---|---|
| `.gitignore` excluye `.env`, `*.key`, `*.pem`, certificados generados, respaldos y `ejemplo-mala-practica.sql` | Que Git no los agregue por accidente con `git add .`. Se verificó con `git check-ignore -v`. |
| `entorno/.env.example` con valores `CAMBIAR` | Documentar qué variables existen sin publicar sus valores. |
| `\getenv` + `\set ECHO none` en los scripts | La contraseña de `app_lab02` y la clave del RFC no están escritas en los scripts ni aparecen en las salidas. |
| Las claves privadas TLS se generan localmente | `server.key` y `ca.key` nunca entran al repositorio. |
| El archivo de demostración se borró **antes** de hacer commit | `git log --all -- "*ejemplo-mala-practica*"` no devuelve nada: nunca estuvo en el historial. |

**Sobre `CLAVE-DE-PRUEBA` en el repositorio.** El texto aparece en `sql/02-cifrado-datos.sql` y en las evidencias porque es la clave **ficticia** que el enunciado ordena usar para la Actividad 2, y la regla 9.2 lo permite ("únicamente se utilizarán valores ficticios"). No protege ningún dato real. Los valores reales del entorno (contraseña de `app_lab02` y clave de `LAB02_CLAVE_RFC`) no están en ningún archivo del repositorio.

## Conclusión

El algoritmo de cifrado solo es tan fuerte como la protección de su clave. Escribir la clave en un script la expone en el repositorio, y el historial de Git la conserva aunque después se borre. Además, si la base de datos descifra, la clave llega al servidor y puede terminar en los registros. Sacar la clave del código (variables de entorno, `.gitignore`, plantillas `.env.example`) es el primer paso obligatorio, pero en producción la clave debe vivir en un gestor de secretos o KMS, con acceso mínimo, rotación y auditoría, y lo ideal es que el cifrado se haga en la aplicación.
