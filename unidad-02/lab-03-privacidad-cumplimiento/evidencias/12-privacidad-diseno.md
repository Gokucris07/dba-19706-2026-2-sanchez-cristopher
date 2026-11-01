# Evidencia 12 — Privacidad por diseño

| | |
|---|---|
| Estudiante | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| Actividad | 18. Actividad 12 — Privacidad por diseño |
| Fecha | 2026-10-31 |

## Objetivo

Revisar, antes de aprobarlo, el diseño de tabla que propone un desarrollador para una aplicación nueva de registro de clientes, y proponer una alternativa con privacidad por diseño y por defecto.

## Procedimiento

El diseño se revisó columna por columna contra una finalidad concreta: registrar clientes para venderles, atenderlos y facturarles. Luego se respondieron las seis preguntas del enunciado y se escribió un diseño alternativo.

Ese diseño se probó en PostgreSQL 16 dentro de una transacción con `ROLLBACK`, en un esquema temporal `propuesta`, para no dejar nada en la base.

Diseño que propone el desarrollador:

```sql
CREATE TABLE clientes ( id BIGSERIAL, nombre TEXT, correo TEXT, telefono TEXT, rfc TEXT,
    edad INTEGER, direccion TEXT, ciudad TEXT, codigo_postal TEXT, fecha_nacimiento DATE,
    ocupacion TEXT, salario NUMERIC, estado_civil TEXT, ...);
```

Su justificación: "Es mejor guardar todos los datos por si posteriormente necesitamos alguno."

## Resultado

### Pregunta 1 — ¿Qué problemas identificas?

Del lado de privacidad:

- Hay datos que no sirven para ninguna finalidad: salario, ocupación y estado civil no tienen que ver con vender ni con atender.
- Hay datos repetidos. `edad` y `fecha_nacimiento` dicen lo mismo, y el RFC también trae la fecha de nacimiento: es el mismo dato guardado tres veces.
- El salario es información económica. Junto con estado civil y ocupación arma un perfil bastante detallado de la persona, sin ninguna necesidad.
- Todo vive en una sola tabla. No hay forma de dar a cada área solo lo suyo sin recurrir a vistas, y el RFC queda junto al correo, a la vista de cualquiera con acceso.
- El `...` del final deja la puerta abierta a seguir agregando columnas sin que nadie las revise.

Del lado técnico, que también pega en la privacidad:

- `id BIGSERIAL` no tiene `PRIMARY KEY`, así que puede haber registros duplicados. Eso complica cualquier solicitud de acceso o cancelación: ¿cuál de los dos es el titular?
- Todo es `TEXT` sin `NOT NULL` ni `CHECK`. No se valida nada, y los datos incorrectos van contra el principio de calidad.
- No hay `fecha_alta`, así que no se puede aplicar ninguna política de retención.
- No hay dónde guardar preferencias ni oposiciones.

### Pregunta 2 — ¿Qué principio de privacidad se está ignorando?

Sobre todo la minimización de datos: solo lo adecuado, relevante y necesario para una finalidad. También la limitación de finalidad y la proporcionalidad. "Por si posteriormente necesitamos alguno" es justo al revés: primero se recolecta y luego se busca para qué. Y se ignora la privacidad por defecto, porque el diseño recolecta lo más posible en vez de lo menos posible.

### Pregunta 3 — ¿Qué preguntas realizarías antes de aprobar el diseño?

1. ¿Para qué es la aplicación? ¿Qué proceso usa cada columna?
2. ¿Qué pantalla o reporte usa `salario`, `ocupacion`, `estado_civil` y `fecha_nacimiento`?
3. ¿Todos los clientes piden factura, o el RFC solo se le pide a quien la quiere?
4. ¿Hay entregas a domicilio? Si no, ¿para qué la dirección?
5. ¿El aviso de privacidad menciona estos datos y finalidades? (Esto lo valida privacidad o jurídico.)
6. ¿Quién va a consultar cada dato y cuánto tiempo se va a guardar?
7. ¿Qué datos son obligatorios para registrarse y cuáles opcionales?
8. ¿Se van a usar datos reales en desarrollo y pruebas?

### Pregunta 4 — ¿Qué datos eliminarías?

| Dato | Decisión | Motivo |
|---|---|---|
| `salario` | Eliminar | Ninguna finalidad comercial lo pide, y es información económica de alto riesgo. |
| `estado_civil` | Eliminar | No tiene relación con la finalidad. |
| `ocupacion` | Eliminar | No tiene relación con la finalidad. |
| `edad` | Eliminar | Se puede calcular y se vuelve vieja. Si analítica necesita rangos, se calculan. |
| `fecha_nacimiento` | Eliminar | Repite lo que ya dicen la edad y el RFC. Solo se justificaría con una finalidad concreta, como verificar mayoría de edad. |
| `...` | Rechazar | No se aprueban columnas sin nombre ni finalidad. |

### Pregunta 5 — ¿Qué datos requerirían una justificación adicional?

| Dato | Qué justificación se pediría |
|---|---|
| `rfc` | Solo si el cliente pide factura. Va en otra tabla y cifrado (LAB-02). |
| `direccion` | Solo si hay entregas a domicilio, y ligada al pedido, no al cliente para siempre. |
| `codigo_postal` | Si es para estadística, basta con los 2 primeros dígitos o con la ciudad. |
| `telefono` | Opcional, si con el correo alcanza para atender. |
| `fecha_nacimiento` | Solo con una finalidad explícita, y quizá baste con un indicador de "es mayor de edad". |

### Pregunta 6 — ¿Cómo aplicarías privacidad por defecto?

Solo nombre y correo serían obligatorios (`NOT NULL`); lo demás, opcional. El RFC iría en otra tabla, cifrado, y únicamente existiría si el cliente pidió factura.

Las promociones quedarían apagadas de entrada con `acepta_promociones BOOLEAN NOT NULL DEFAULT false`. El titular las activa si quiere; no tiene que pedir que lo saquen.

Además:

- `REVOKE ALL ... FROM PUBLIC`, y cada área recibe un rol con acceso solo a su vista;
- `fecha_alta NOT NULL` desde el inicio, para poder aplicar la retención;
- en desarrollo, datos sintéticos como los `example.test` de este curso.

### Diseño alternativo (validado)

```sql
CREATE TABLE clientes (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre        VARCHAR(120) NOT NULL,
  correo        VARCHAR(150) NOT NULL UNIQUE CHECK (correo LIKE '%_@_%'),
  telefono      VARCHAR(20),                       -- opcional
  ciudad        VARCHAR(80),                       -- opcional, para estadística
  fecha_alta    DATE NOT NULL DEFAULT CURRENT_DATE -- necesaria para la retención
);

-- Solo existe si el cliente pide factura; cifrado con pgcrypto (LAB-02)
CREATE TABLE datos_fiscales (
  cliente_id     BIGINT PRIMARY KEY REFERENCES clientes(id),
  rfc_cifrado    BYTEA NOT NULL,
  fecha_registro DATE NOT NULL DEFAULT CURRENT_DATE
);

-- Privacidad por defecto: promociones desactivadas hasta que el titular las acepte
CREATE TABLE preferencias (
  cliente_id          BIGINT PRIMARY KEY REFERENCES clientes(id),
  acepta_promociones  BOOLEAN NOT NULL DEFAULT false,
  fecha_actualizacion DATE NOT NULL DEFAULT CURRENT_DATE
);

REVOKE ALL ON clientes, datos_fiscales, preferencias FROM PUBLIC;
```

Prueba en PostgreSQL 16 (dentro de `BEGIN ... ROLLBACK`, esquema `propuesta`):

```
CREATE TABLE
CREATE TABLE
CREATE TABLE
REVOKE
INSERT 0 1        -- cliente de prueba: solo nombre, correo y ciudad
INSERT 0 1        -- preferencias sin indicar nada

 cliente_id | acepta_promociones | fecha_actualizacion
------------+--------------------+---------------------
          1 | f                  | 2026-10-31

INSERT INTO clientes (nombre, correo) VALUES ('Mal', 'sin-arroba');
ERROR:  new row for relation "clientes" violates check constraint "clientes_correo_check"
ROLLBACK
```

La prueba confirma tres cosas. Un cliente se puede registrar solo con nombre y correo. Si no se indica nada, las promociones quedan apagadas. Y la base rechaza un correo mal escrito.

### Comparación

| | Propuesta del desarrollador | Diseño alternativo |
|---|---|---|
| Columnas con datos personales | 13 o más (`...`) | 5 en `clientes` + RFC solo si se factura |
| Datos sin finalidad | salario, ocupación, estado civil, fecha de nacimiento, edad | Ninguno |
| RFC | Junto al correo, en texto | Tabla aparte, cifrado, opcional |
| Llave primaria | No | Sí |
| Validación | Ninguna | `NOT NULL`, `UNIQUE`, `CHECK` |
| Promociones | No contemplado | Desactivadas por defecto |
| Permisos por defecto | Los que tenga `PUBLIC` | Ninguno |
| Retención | Sin `fecha_alta` | `fecha_alta NOT NULL` |

## Análisis

El diseño original deja para después una decisión que hay que tomar ahora. Cada columna sin finalidad es un riesgo que se acepta a cambio de nada: si hay una fuga, salen salarios que nadie estaba usando.

Privacidad por diseño y buen diseño de base de datos van de la mano. La llave primaria, los tipos con longitud, las restricciones y la separación en tablas hacen que la base sea más correcta y, al mismo tiempo, más privada.

Con el RFC en su propia tabla es fácil aplicarle controles distintos (cifrado, rol de facturación) sin armar vistas complicadas.

El valor por defecto de una columna también es una decisión de privacidad. `DEFAULT false` en promociones quiere decir que el sistema no usa datos para mercadotecnia a menos que el titular lo active.

Qué datos se recolectan no lo decide ni el DBA ni el desarrollador. El DBA revisa y propone; el propietario de los datos, con privacidad, aprueba.

## Conclusión

El diseño propuesto recolecta "por si acaso" y con eso se salta la minimización. La alternativa deja solo los datos que tienen finalidad, separa y cifra el RFC, apaga por defecto los usos secundarios y deja la base lista para retención y control de acceso. Se probó en PostgreSQL y funciona como se describe. Estas decisiones se toman al escribir el `CREATE TABLE`, no después de una fuga.
