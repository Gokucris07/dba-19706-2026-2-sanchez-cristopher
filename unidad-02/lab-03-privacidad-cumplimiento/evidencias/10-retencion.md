# Evidencia 10 — Política de retención

| | |
|---|---|
| Estudiante | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| Actividad | 16. Actividad 10 — Política de retención |
| Fecha | 2026-10-31 |

## Objetivo

Evaluar la propuesta "Conservar todos los datos de clientes indefinidamente porque podrían ser útiles en el futuro" y definir qué tiene que establecer y dejar por escrito la organización para fijar periodos de retención con fundamento.

## Procedimiento

1. Comparar la propuesta con los principios de minimización, finalidad y ciclo de vida.
2. Identificar los riesgos de guardar información que ya no se necesita, apoyándose en lo que se comprobó en LAB-02 y en las evidencias 05 y 08 de este laboratorio.
3. Responder las cuatro preguntas del enunciado.
4. Proponer una plantilla de política por categoría de dato, separando lo que decide la organización de lo que implementa el DBA.
5. Revisar lo que ya había en LAB-01 (`05-retencion.sql`), que busca registros con más de 5 años.

## Resultado

### Pregunta 1 — ¿Es compatible con el principio de minimización?

No. La minimización limita los datos a lo necesario para una finalidad determinada, y "podrían ser útiles en el futuro" no es una finalidad. Si no se sabe para qué se guarda un dato, no se puede sostener que sea necesario.

La necesidad también caduca. El correo de un cliente hace falta mientras se le atiende, no veinte años después de su última compra.

### Pregunta 2 — ¿Qué riesgos genera conservar información innecesaria?

| Riesgo | Por qué |
|---|---|
| Incidentes más grandes | Una fuga expone a todos los clientes que ha tenido la empresa, no solo a los activos. En LAB-02 un respaldo sin cifrar mostró correo y RFC; con retención indefinida, ese respaldo traería a todos los que alguna vez fueron clientes. |
| Incumplimiento | Guardar datos cuando su finalidad ya se cumplió, sin una obligación que lo justifique, va contra los principios de finalidad y proporcionalidad. |
| Usos no informados | Un acervo guardado "por si acaso" invita a usarlo para cosas nuevas, como las promociones de la evidencia 05. |
| Datos desactualizados | Edad, teléfono y correo se vuelven viejos. Tomar decisiones con ellos perjudica al titular. |
| Más trabajo con ARCO | Cada año de datos suma tablas, copias y respaldos que revisar en una solicitud de acceso o cancelación (evidencia 08). |
| Costo y desempeño | Más almacenamiento, respaldos e índices más pesados, restauraciones más lentas. |

### Pregunta 3 — ¿Qué debería determinar la organización antes de establecer un periodo de retención?

Lo primero es la finalidad de cada dato (evidencia 01) y en qué momento se cumple: cuando termina la relación comercial, con la última compra, al cerrar el ejercicio fiscal.

Después vienen las obligaciones legales, fiscales o contractuales que obliguen a guardar algo más tiempo. El ejemplo claro es la información fiscal ligada al RFC; el plazo lo confirma jurídico (el art. 30 del Código Fiscal de la Federación marca, en general, cinco años para la contabilidad).

También hay que definir:

- qué pasa cuando vence el plazo: eliminar, anonimizar de verdad o bloquear (guardar sin usar, solo para responder por obligaciones);
- desde cuándo se cuenta, porque "5 años desde el alta" no es lo mismo que "5 años desde la última operación";
- en qué lugares está el dato (tablas, copias, respaldos, réplicas, exportaciones; evidencia 08), porque el periodo se aplica en todos;
- quién lo aprueba (el propietario de los datos con jurídico y privacidad) y quién lo ejecuta (el DBA).

### Pregunta 4 — ¿Qué información debería documentarse para justificar el periodo seleccionado?

- La categoría de dato y los campos que incluye.
- La finalidad que justifica guardarlo.
- El fundamento (obligación legal, contractual o necesidad operativa) con su referencia.
- El periodo y el evento desde el que se cuenta.
- La acción al vencer y cómo se aplica a respaldos y copias.
- Quién lo aprobó, cuándo, y cuándo toca revisarlo.
- Constancia de cada ejecución: fecha, número de registros y quién la hizo.

### Propuesta de política (plantilla)

Los periodos están escritos como eventos. Los plazos legales quedan pendientes de que jurídico los confirme; el DBA no los inventa.

| Categoría | Campos | Finalidad | Periodo propuesto | Fundamento (a validar) | Acción al vencer | Aprueba |
|---|---|---|---|---|---|---|
| Contacto | `correo`, `telefono` | Atención al cliente | Relación comercial activa + periodo de aclaraciones | Necesidad operativa | Eliminar | Propietario de datos |
| Identificación | `nombre`, `id` | Atención y facturación | El mayor entre el periodo de contacto y el fiscal | Necesidad operativa / fiscal | Eliminar o bloquear | Propietario + jurídico |
| Fiscal | `rfc` | Facturación | Plazo de conservación fiscal | Legislación fiscal (jurídico confirma) | Bloquear durante el plazo; después eliminar | Jurídico |
| Demográfico | `edad`, `ciudad`, `codigo_postal` | Estadística | Relación comercial activa | Necesidad operativa | Conservar solo agregados anónimos; eliminar el dato individual | Propietario de datos |
| Relación | `fecha_alta` | Calcular antigüedad y retención | Igual que el registro | Necesario para aplicar la política | Eliminar con el registro | Propietario de datos |
| Respaldos | Todo | Recuperación | Ciclo de rotación definido por TI | Continuidad | Expiración del respaldo; reaplicar cancelaciones si se restaura | TI + privacidad |
| Copias de desarrollo | — | Pruebas | No deben contener datos reales | Privacidad por defecto | Usar datos sintéticos | Privacidad |

### Lo que le toca implementar al DBA

LAB-01 ya tiene la consulta que encuentra los registros vencidos sin borrarlos:

```sql
SELECT COUNT(*) AS registros_afectados
FROM clientes
WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years';
```

Una vez aprobada la política, cada fila de la tabla anterior se vuelve un procedimiento: encontrar los registros (con una consulta como esta), validarlos con el responsable, aplicar la acción en la tabla y en sus copias (evidencia 08) y anotar cuántos registros se trataron y cuándo.

## Análisis

La propuesta confunde que un dato pueda tener valor con que tenga una finalidad. Casi cualquier dato "podría" servir algún día, así que ese criterio no limita nada.

El riesgo de guardar de más no es teórico. En LAB-02 quedó claro que una copia o un respaldo exponen todo lo que contienen. Con retención indefinida, cada copia trae a todos los clientes que ha tenido la empresa.

Los 5 años de LAB-01 eran un número puesto en un script, sin justificación escrita. Aquí aparece lo que faltaba: quién decide, con qué fundamento, desde cuándo se cuenta y qué pasa con las copias.

Y un periodo de retención solo funciona si también se aplica a respaldos, réplicas y copias. Si no, se borra la tabla y el dato sigue en otro lado.

## Conclusión

Guardar todo para siempre no cabe en la minimización y hace más grave cualquier incidente. La empresa necesita un periodo por categoría de dato, con su finalidad, fundamento, evento de inicio, acción al vencer y responsable, por escrito y con revisiones periódicas. El plazo legal no lo pone el DBA; él se encarga de que se pueda cumplir: encuentra los registros vencidos, aplica la acción en todos los lugares donde están y deja constancia.
