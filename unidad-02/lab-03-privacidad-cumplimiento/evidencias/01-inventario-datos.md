# Evidencia 01 — Inventario y finalidad de los datos

| | |
|---|---|
| Estudiante | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| Actividad | 7. Actividad 1 — Inventario y finalidad de los datos |
| Fecha | 2026-10-31 |
| Script | `sql/01-minimizacion.sql` (primera parte) |

## Objetivo

Saber qué datos de la tabla `clientes` son personales, para qué sirve cada uno, si de verdad hace falta, quién debería poder verlo y cuánto tiempo conviene guardarlo. Sin este inventario no hay forma de proteger, limitar o borrar nada, porque no se sabe qué hay.

## Procedimiento

Primero se revisó la estructura real de la tabla con `\d clientes`, en lugar de suponerla. Después cada campo se cruzó con los cuatro procesos del escenario (atención al cliente, facturación, analítica y DBA) para decidir si es dato personal, para qué se usa, si es necesario, quién lo ve y cuánto tiempo se guarda. Cada decisión lleva su justificación.

Al final, la clasificación se guardó en la base con `COMMENT ON COLUMN`. Así viaja con la tabla y se consulta con `col_description()`.

## Resultado

Estructura real (salida de `\d clientes`):

```
    Column     |          Type          | Nullable |               Default
---------------+------------------------+----------+--------------------------------------
 id            | bigint                 | not null | nextval('clientes_id_seq'::regclass)
 nombre        | character varying(120) | not null |
 correo        | character varying(150) | not null |
 telefono      | character varying(20)  |          |
 rfc           | character varying(13)  |          |
 edad          | integer                |          |
 ciudad        | character varying(80)  |          |
 codigo_postal | character varying(10)  |          |
 fecha_alta    | date                   |          | CURRENT_DATE
Referenced by:
    TABLE "clientes_rfc_cifrado" CONSTRAINT "clientes_rfc_cifrado_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES clientes(id)
    TABLE "pii.mapa_cliente" CONSTRAINT "mapa_cliente_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES clientes(id)
```

La sección `Referenced by` ya adelanta algo: los datos del cliente no están solo en esta tabla. LAB-01 y LAB-02 dejaron tablas que dependen de ella (`pii.mapa_cliente` y `clientes_rfc_cifrado`).

### Matriz de inventario

| Campo | ¿Es dato personal? | Finalidad | ¿Es necesario? | Nivel de acceso | Retención |
|---|---|---|---|---|---|
| `id` | Sí, indirecto. No dice quién es la persona, pero une todos sus registros. | Llave interna para relacionar registros. | Sí (técnico). | Operación (atención, facturación). No se entrega a analítica. | La del registro del cliente. |
| `nombre` | Sí, identificativo. | Atención al cliente y facturación. | Sí. | Atención y facturación. | Mientras dure la relación comercial y, para facturación, el plazo fiscal que confirme jurídico. |
| `correo` | Sí, de contacto. | Atención al cliente. | Sí, para atención. | Solo atención. | Mientras dure la relación comercial. |
| `telefono` | Sí, de contacto. | Atención al cliente. | Sí, para atención (es opcional, la columna acepta nulos). | Solo atención. | Mientras dure la relación comercial. |
| `rfc` | Sí, identificador fiscal. Revela fecha de nacimiento e iniciales; es el de mayor riesgo. | Facturación. | Sí, solo para facturar. | Solo facturación (cifrado en LAB-02). | Plazo de conservación fiscal que determine jurídico. |
| `edad` | Sí. | Estadística. | Dudoso. Ningún proceso usa la edad exacta; analítica trabaja con rangos. | Analítica, solo como rango y a través de una vista. | Revisar si vale la pena seguir guardándola. Además envejece: un número fijo que deja de ser cierto. |
| `ciudad` | Sí; combinada con otros atributos ubica a la persona. | Estadística y atención. | Sí. | Atención; analítica en forma agregada. | Mientras dure la relación comercial. |
| `codigo_postal` | Sí, es un cuasi-identificador. | Estadística por región. | En parte: analítica solo usa los 2 primeros dígitos. | Analítica, generalizado a región. | Mientras dure la relación comercial. |
| `fecha_alta` | Sí, describe la relación con el titular. | Antigüedad del cliente y cálculo de retención. | Sí; sin ella no se puede aplicar ninguna política de retención. | Operación y DBA. | La del registro. |

### Justificación de las decisiones

El `id` parece un simple número, pero es dato personal porque con él se reúne todo lo que la empresa sabe de alguien. Por eso no se le da a analítica: un identificador fijo por persona permite seguirla de un reporte a otro.

Con `nombre`, `correo` y `telefono` atención identifica y contacta al cliente. Facturación necesita el nombre, pero no tiene por qué llamar a nadie.

El `rfc` solo tiene una finalidad legítima en el escenario, que es facturar. Ningún otro proceso lo usa, y por eso es el campo con el acceso más cerrado.

La `edad` es el punto más débil del inventario. Se guarda exacta y nadie la necesita así. Sería menos riesgoso guardar solo el rango o no guardarla; esa decisión es del propietario de los datos.

`ciudad` y `codigo_postal` parecen inofensivos por separado, pero junto con la edad pueden señalar a una persona (ver README, sección 4). Por eso se entregan generalizados.

`fecha_alta` no se le muestra a nadie y aun así hace falta: sin ella no hay forma de saber qué registros ya pasaron su periodo de retención.

Los periodos de retención se escribieron como eventos ("mientras dure la relación comercial", "plazo fiscal") y no como números inventados. El plazo exacto lo pone el área jurídica. Por ejemplo, el art. 30 del Código Fiscal de la Federación marca, en general, cinco años para conservar la contabilidad; jurídico tendría que confirmar si aplica aquí y desde cuándo se cuenta.

### Catálogo registrado en la base

```sql
COMMENT ON COLUMN clientes.rfc IS
  'Dato personal identificativo fiscal (alto riesgo). Finalidad: facturación. Acceso: facturación. Retención: plazo fiscal que confirme jurídico.';
-- (uno por cada columna, ver sql/01-minimizacion.sql)
```

Consulta del catálogo:

```
 n |     campo     |          tipo          |                           clasificacion_y_finalidad
---+---------------+------------------------+---------------------------------------------------------------------------------------------
 1 | id            | bigint                 | Dato personal indirecto (vincula todos los registros del titular). Finalidad: llave interna. ...
 2 | nombre        | character varying(120) | Dato personal identificativo. Finalidad: atención y facturación. Acceso: atención, facturación. ...
 3 | correo        | character varying(150) | Dato personal de contacto. Finalidad: atención al cliente. Acceso: atención. ...
 4 | telefono      | character varying(20)  | Dato personal de contacto. Finalidad: atención al cliente. Acceso: atención. ...
 5 | rfc           | character varying(13)  | Dato personal identificativo fiscal (alto riesgo). Finalidad: facturación. Acceso: facturación. ...
 6 | edad          | integer                | Dato personal. Finalidad: estadística (solo en rangos). Acceso: analítica solo como rango, vía vista. ...
 7 | ciudad        | character varying(80)  | Dato personal (ubicación) al combinarse con otros. Finalidad: estadística y atención. ...
 8 | codigo_postal | character varying(10)  | Dato personal (cuasi-identificador). Finalidad: estadística por región (2 dígitos). ...
 9 | fecha_alta    | date                   | Dato de la relación con el titular. Finalidad: antigüedad y cálculo de retención. ...
(9 rows)
```

## Análisis

Los 9 campos resultaron ser datos personales. Hasta `id` y `fecha_alta` se refieren a una persona que se puede identificar, así que las obligaciones de privacidad aplican a toda la tabla y no solo a las columnas que "se ven" sensibles.

Tampoco todos los datos sirven a todas las finalidades. Solo `id`, `nombre` y `fecha_alta` los usa más de un proceso. El RFC es solo de facturación; el correo y el teléfono, solo de atención. De esa diferencia salen la minimización de la Actividad 2 y el control de acceso de la Actividad 4.

La edad exacta es el único dato sin una finalidad que justifique tanto detalle. Es el primer candidato a reducirse.

El inventario de columnas se queda corto si no se acompaña de otro inventario: dónde más están esos datos (tablas relacionadas, copias, respaldos). Eso se trabaja en la evidencia 08.

Guardar la clasificación con `COMMENT ON` mezcla lo administrativo con lo técnico. La decisión es de la organización, pero queda escrita donde trabaja el DBA y no en un documento que nadie vuelve a abrir.

## Conclusión

Más que buscar qué columnas son sensibles, el inventario sirvió para preguntar para qué se usa cada dato y quién lo necesita. Todos los campos son personales y cada uno tiene una finalidad distinta. Con esta matriz ya se puede justificar qué recibe cada área, qué conviene reducir (edad y código postal) y qué información necesita jurídico para fijar la retención.
