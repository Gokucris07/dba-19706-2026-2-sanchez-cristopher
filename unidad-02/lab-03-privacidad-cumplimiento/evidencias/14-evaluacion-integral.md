# Evidencia 14 — Evaluación integral de un escenario

| | |
|---|---|
| Estudiante | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| Actividad | 20. Actividad 14 — Escenario integral |
| Fecha | 2026-10-31 |

## Objetivo

Encontrar al menos 10 problemas o riesgos de privacidad, cumplimiento y gobierno en un escenario de administración de datos, y proponer un control concreto para cada uno.

## Procedimiento

Cada hecho del escenario se separó como un problema aparte. Para cada uno se anotó el principio afectado, el riesgo y un control; cuando el control ya está implementado en este repositorio, se dice dónde. Al final se ordenaron por prioridad.

El escenario:

- 50,000 clientes.
- Todo el equipo de analítica consulta directamente la tabla `clientes`.
- La tabla tiene nombre, correo, teléfono, RFC, edad, ciudad y código postal.
- Analítica solo genera estadísticas mensuales.
- Los datos se guardan desde hace 12 años y no hay política de retención por escrito.
- Los desarrolladores reciben copias completas de la base, con información real.
- Marketing usa los correos para campañas promocionales.
- No hay documentación de qué finalidad tiene cada dato.

## Resultado

| # | Problema | Principio afectado | Riesgo | Control propuesto |
|---|---|---|---|---|
| 1 | Analítica consulta directamente la tabla `clientes`. | Mínimo privilegio; limitación de finalidad | Cualquier analista puede ver o exportar nombre, correo, teléfono y RFC de 50,000 personas. | Revocar `SELECT` sobre `clientes` y dar solo una vista o tabla agregada (`v_analitica_clientes`, script 03). |
| 2 | Analítica tiene nombre, correo, teléfono y RFC, aunque solo hace estadísticas. | Minimización; necesidad | Se exponen identificadores que esa área no usa. | Vista sin identificadores, con rangos de edad y región de código postal (scripts 02 y 03). |
| 3 | Todo el equipo de analítica tiene el mismo acceso. | Mínimo privilegio; necesidad de conocer | Entre más personas con acceso, más posibilidades de error, abuso o robo de credenciales. | Rol de grupo (`analista`) con miembros individuales, altas y bajas aprobadas y revisión periódica de permisos. |
| 4 | Las estadísticas son mensuales, pero se calculan sobre datos individuales. | Proporcionalidad | Se trabaja por persona lo que se publica por grupo; con grupos chicos se puede señalar a alguien. | Agregados mensuales que supriman grupos pequeños (k mínimo, LAB-01); analítica consulta solo esos agregados. |
| 5 | Los datos se guardan desde hace 12 años. | Retención; minimización | Clientes inactivos desde hace una década siguen expuestos; una fuga alcanza a todos los históricos. | Política de retención por categoría (evidencia 10); encontrar los registros vencidos (`05-retencion.sql` de LAB-01) y eliminarlos, anonimizarlos o bloquearlos. |
| 6 | No hay política de retención por escrito. | Gobierno de datos; responsabilidad demostrada | No hay forma de justificar por qué se guarda un dato ni de demostrar que se cumple. | Política aprobada por el propietario de datos y jurídico, con fundamento, periodo y acción al vencer; revisión anual. |
| 7 | Los desarrolladores reciben copias completas. | Minimización; privacidad por defecto | 50,000 registros reales en equipos y servidores de desarrollo, con menos protección que producción. | Prohibir restaurar producción en desarrollo; usar datos sintéticos (como `example.test`) o subconjuntos anonimizados. |
| 8 | Esas copias tienen información real, incluido el RFC. | Seguridad; ciclo de vida | Fuga desde un ambiente menos protegido; copias que nadie controla ni borra, y a las que no llegan las cancelaciones ARCO (evidencia 08). | Inventario de ambientes; enmascaramiento irreversible antes de entregar (LAB-01); borrar las copias que ya existen; incluirlas en el mapa de ciclo de vida. |
| 9 | Marketing usa los correos para promociones. | Limitación de finalidad; consentimiento / oposición | Uso para una finalidad que quizá nunca se informó; quejas, oposiciones e incumplimiento. | Que privacidad y jurídico validen si procede; si procede, vista con lo indispensable y sin quienes se opusieron (`v_contactables_promociones`, script 02). |
| 10 | Marketing no tiene cómo saber quién se opuso. | Derechos ARCO (oposición) | Se mandan promociones a quien pidió no recibirlas. | Registro de oposiciones por finalidad (`oposiciones_tratamiento`, script 02), de uso obligatorio en la vista de marketing. |
| 11 | No hay documentación de qué finalidad tiene cada dato. | Gobierno; transparencia | Nadie puede decidir con fundamento quién accede, y no se puede contestar completa una solicitud de acceso. | Catálogo de datos (evidencia 01; `COMMENT ON COLUMN` en el script 01) y matriz de gobierno (evidencia 11). |
| 12 | El RFC está en la misma tabla, al alcance de analítica. | Protección reforzada de datos de alto riesgo | Fraude fiscal o suplantación con un identificador oficial. | Separar y cifrar el RFC (LAB-02); acceso solo para facturación. |
| 13 | No queda registro de quién consulta o modifica datos. | Trazabilidad; responsabilidad | No se puede investigar un incidente ni demostrar que un cambio estaba autorizado (Actividad 7: `log_statement = none`). | Auditoría de accesos y cambios (Unidad III); cuentas individuales, no compartidas. |
| 14 | 50,000 registros sin clasificar. | Proporcionalidad del control | Una sola fuga se vuelve un incidente grave que puede obligar a avisar a titulares y autoridades. | Clasificar la información y poner más controles en los datos de mayor riesgo (RFC, contacto). |

### Prioridad

Lo más urgente son las copias de desarrollo con datos reales (problemas 7 y 8). Ahí están los datos completos de 50,000 personas, con RFC, fuera de producción y con menos controles.

Le sigue el acceso directo de analítica (1, 2, 3 y 12): mucha gente con identificadores que no necesita. Se corrige rápido con una vista y un `REVOKE`.

Después:

- marketing (9 y 10), que necesita una decisión de jurídico antes de seguir usando los correos;
- retención y documentación (5, 6 y 11), que requieren trabajo de la organización y son la base para justificar los demás controles;
- trazabilidad (13), que se ve en la Unidad III.

## Análisis

Ninguno de los 14 problemas es una vulnerabilidad técnica en el sentido clásico. La base podría tener TLS, contraseñas SCRAM y el RFC cifrado, y el escenario seguiría siendo un problema serio de privacidad. Tener la base segura no la hace cumplir con la privacidad.

Además, unos problemas empeoran a otros. Sin documentación de finalidades (11), nadie puede justificar que se le quite el acceso a analítica (1). Sin política de retención (6), los 12 años de datos (5) terminan copiados en desarrollo (7).

Muchos de los controles ya están en este repositorio: la vista para analítica y la revisión de permisos (LAB-03), el cifrado del RFC (LAB-02), el enmascaramiento y la seudonimización (LAB-01), el registro de oposiciones (LAB-03). No hace falta tecnología nueva; hace falta decidir y aplicar.

Varias correcciones pasan por otras áreas. Si marketing puede usar los correos lo decide jurídico; los plazos de retención, el propietario de los datos junto con jurídico. El DBA encuentra los problemas, propone e implementa, pero esas respuestas no le tocan.

## Conclusión

Se encontraron 14 problemas, y el peor no está en producción sino en las copias de desarrollo con datos reales. Casi todos se corrigen con controles que ya se practicaron en LAB-01, LAB-02 y LAB-03 (vistas, roles, cifrado, enmascaramiento, registro de oposiciones), siempre que la empresa primero escriba para qué usa cada dato y cuánto tiempo lo necesita.
