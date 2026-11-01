# Evidencia 11 — Matriz de gobierno de datos

| | |
|---|---|
| Estudiante | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| Actividad | 17. Actividad 11 — Diseñar una matriz de gobierno de datos |
| Fecha | 2026-10-31 |

## Objetivo

Asignar a cada dato principal de `clientes` una finalidad, un responsable, los usuarios autorizados, su protección, su retención y lo que se hace al terminar. Con eso se busca mostrar que el acceso depende de lo que cada área necesita para trabajar, no de que técnicamente pueda consultar la tabla.

## Procedimiento

Las finalidades salieron del inventario (evidencia 01) y las retenciones de la evidencia 10. Como responsable se puso al rol que decide sobre el dato (el propietario), no a quien lo administra; el DBA aparece como custodio.

En usuarios autorizados quedaron solo las áreas que usan el dato en su trabajo, así que no todas aparecen en todos los renglones. La columna de protección apunta a controles que ya existen en el repositorio, de LAB-01, LAB-02 y LAB-03.

## Resultado

### Roles

| Rol | Qué hace con los datos |
|---|---|
| Dirección (comercial) | Es dueña de los datos de clientes: decide para qué se usan y aprueba accesos. |
| Facturación | Dueña del dato fiscal; usa nombre y RFC. |
| Atención al cliente | Usa los datos de contacto. |
| Analítica | Usa información agregada. No identifica personas. |
| DBA | Custodio: implementa roles, vistas, cifrado, respaldos y retención. Tiene acceso técnico, pero no lo usa para el negocio. |
| Privacidad / jurídico | Valida finalidades, avisos, plazos legales y solicitudes ARCO. |

### Matriz

| Dato | Finalidad | Responsable | Usuarios autorizados | Protección | Retención | Acción al finalizar |
|---|---|---|---|---|---|---|
| `nombre` | Identificar al cliente para atención y facturación | Dirección | Atención, Facturación | Roles de PostgreSQL; `clientes_soporte` / vistas por área; no se entrega a analítica | El mayor entre la relación comercial y el plazo fiscal | Eliminar (o bloquear mientras dure el plazo fiscal) |
| `correo` | Contactar al cliente | Dirección | Atención | Solo en `clientes_soporte`; enmascarado en `v_clientes_soporte` (LAB-01) cuando no se necesita completo | Relación comercial activa | Eliminar |
| `telefono` | Contactar al cliente | Dirección | Atención | Igual que `correo` | Relación comercial activa | Eliminar |
| `rfc` | Facturación | Facturación | Facturación | Cifrado AES-256 con `pgcrypto` y clave fuera del repositorio (LAB-02); acceso solo a facturación | Plazo de conservación fiscal (lo confirma jurídico) | Bloquear durante el plazo; después eliminar |
| `edad` | Estadística en rangos | Dirección | Analítica (solo como rango vía `v_analitica_clientes`) | Generalización en la vista; analítica sin acceso a la tabla | Relación comercial activa; evaluar guardar solo el rango | Eliminar el dato individual; conservar solo agregados |
| `ciudad` | Estadística y atención | Dirección | Atención; Analítica (vía vista) | Vista; agregados con cuidado de grupos pequeños | Relación comercial activa | Eliminar; conservar solo agregados |
| `codigo_postal` | Estadística por región | Dirección | Analítica (generalizado a 2 dígitos) | Generalización (`LEFT(codigo_postal, 2)`) | Relación comercial activa | Eliminar; conservar solo agregados |

El DBA no figura como usuario autorizado de ningún dato. Su acceso administrativo es para cuidar la base, no para consultar datos con fines de negocio. Dirección, aunque decide, tampoco necesita ver registros individuales.

### Lo que ya está implementado en el repositorio

| Usuario autorizado | Objeto que usa | Laboratorio |
|---|---|---|
| Atención al cliente | `clientes_soporte` (completo) o `v_clientes_soporte` (enmascarado) | LAB-03 / LAB-01 |
| Facturación | `clientes_rfc_cifrado` + clave de facturación | LAB-02 |
| Analítica | `v_analitica_clientes` (único permiso del rol `analista`, comprobado con `role_table_grants`) | LAB-03 |
| Marketing | Ninguno: `v_contactables_promociones` existe, pero no se otorga hasta que se apruebe la finalidad | LAB-03 |

### Quién decide qué

| Decisión | Dirección / propietario | Privacidad / jurídico | DBA |
|---|---|---|---|
| Qué datos se recolectan y para qué | Decide | Valida | Informa el impacto técnico |
| Quién accede a cada dato | Aprueba | Valida | Implementa (roles, vistas) |
| Periodo de retención | Propone | Fija el plazo legal | Implementa y documenta |
| Respuesta a una solicitud ARCO | — | Decide si procede | Localiza los datos y ejecuta |
| Nueva finalidad (promociones) | Propone | Aprueba o rechaza | Prepara controles; no da acceso sin aprobación |
| Cifrado, respaldos, configuración | Aprueba el presupuesto | Define requisitos | Decide e implementa |

## Análisis

Ninguna área necesita todos los datos. Atención no usa el RFC, facturación no usa el teléfono y analítica no tiene por qué saber quién es quién. Darle a cualquiera de ellas la tabla completa sería darle de más.

Responsable y custodio son papeles distintos. El DBA puede leer todo, pero la decisión no es suya. Cuando esos papeles se mezclan, el DBA termina decidiendo finalidades sin darse cuenta: "me lo pidieron, se lo di".

La columna de protección no se quedó en el papel. Cada control apunta a un objeto que ya está en el repositorio, y por eso la matriz se puede verificar contra los permisos reales de la base.

Lo que todavía falta es trazabilidad. La base no registra quién consultó o cambió un dato (Actividad 7). La matriz dice quién debería entrar, pero no permite comprobar quién entró. Eso queda para la Unidad III.

## Conclusión

Cada dato tiene un dueño que decide, usuarios autorizados según lo que hacen y un custodio técnico que lo implementa. Con eso, el acceso deja de ser "quien pueda consultar la tabla" y pasa a ser "quien necesite este campo para su trabajo". En este laboratorio quedó aplicado en la base: el rol `analista` tiene un solo permiso, sobre una vista sin identificadores.
