# Informe — LAB-01: Protección y privacidad de datos

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda |
| **Matrícula** | 20434863 |
| **Grupo** | 403 |
| **Materia** | Gestión de Seguridad y Desempeño de Bases de Datos |
| **Unidad / Tema** | II — Seguridad, privacidad y control de acceso / 2.3 Datos sensibles, privacidad y protección de la información |
| **Motor** | PostgreSQL 16 en Docker, ejecutado desde VS Code |
| **Escenario** | Comercializadora Norte S.A. de C.V. (datos ficticios) |


---

## 19.1 Clasificación

En la tabla clientes todos los campos requieren protección, pero por razones distintas:

- **Identificadores directos** (nombre, correo, telefono, rfc): identifican a la persona por sí solos y su exposición permite fraude, suplantación o acoso. El RFC además revela iniciales y fecha de nacimiento.
- **Cuasi-identificadores** (edad, ciudad, codigo_postal, fecha_alta): no identifican por sí mismos, pero combinados reducen el grupo de personas posibles hasta una sola; en este laboratorio edad + ciudad + codigo_postal hace únicos a los 5 clientes.
- **id**: es la llave que enlaza todos los datos del cliente dentro de la base; quien lo tiene puede unirlo con clientes.

No todos son datos personales sensibles en el sentido jurídico (LFPDPPP): nombre, correo, teléfono y RFC son datos personales de identificación, contacto y fiscales, no sensibles, y aun así deben protegerse. Proteger un dato depende del riesgo que genera su exposición, no solo de su categoría legal. El detalle campo por campo está en la matriz de abajo y en evidencias/01-clasificacion.pdf.

### Matriz de clasificación (Actividad 1)

| Campo |  ¿Requiere protección? | Nivel | Justificación |
|---|---|---|---|
| id | Sí | Interno | Es la llave que enlaza todos los datos del cliente dentro de la BD. Quien tiene el id puede unirlo con clientes y obtener todo. Por eso en analítica se sustituye por un token. |
| nombre |  Sí | Restringido | Identificador directo. Puede haber homónimos, pero junto con la ciudad casi siempre apunta a una persona. |
| correo | Sí | Restringido | Único por persona y en este caso contiene el nombre (ana.lopez@…). Además permite contactar o suplantar. |
| telefono | Sí | Restringido | Único por persona, permite contacto directo y búsqueda en otras fuentes (WhatsApp, directorios). |
| rfc | Sí | Restringido | Identificador oficial único. Además revela iniciales del nombre y fecha de nacimiento (LOAA850315… → 15/03/1985). Útil para fraudes fiscales. |
| edad | Sí | Confidencial | Cuasi-identificador. Combinada con ciudad/CP reduce mucho el grupo de personas posibles. |
| ciudad | Sí | Confidencial | Cuasi-identificador. En ciudades con pocos clientes (Mazatlán y Los Mochis tienen 1 cada una) señala a una sola persona. |
| codigo_postal | Sí | Confidencial | Cuasi-identificador fuerte: un CP es una zona pequeña (una colonia). |
| fecha_alta | Sí (baja) | Interno | Combinada con conocimiento externo ("sé que se registró ese día") ayuda a distinguir. Es la base de la regla de retención. |





## 19.2 Enmascaramiento (Actividad 2)

| | |
|---|---|
| **Qué se ocultó** | Correo (solo 2 primeros caracteres + dominio: an\*\*\*\*\*@example.test), teléfono (últimos 4 dígitos: \*\*\*\*\*\*4567) y RFC (últimos 4 caracteres: \*\*\*\*\*\*\*\*\*5ABC). Nombre e id se muestran completos. |
| **Para quién** | Rol soporte. |
| **Por qué** | Soporte necesita identificar al cliente (nombre) y verificar su identidad cuando llama ("¿me confirma los últimos 4 dígitos de su teléfono?"), pero no necesita los datos completos. Mínimo privilegio y minimización. |
| **Mecanismo** | Enmascaramiento dinámico con una VIEW (v_clientes_soporte) + control de acceso: GRANT SELECT sobre la vista y REVOKE ALL sobre la tabla. La vista se ejecuta con los privilegios de su propietario (el DBA), por eso soporte puede leer la vista sin tener permiso sobre clientes. |


---

## 19.3 Seudonimización (Actividades 3 y 4)

| | |
|---|---|
| **Cómo se generaron los tokens** | Con gen_random_uuid() (extensión pgcrypto): un UUID v4 aleatorio por cliente, guardado en pii.mapa_cliente. No se deriva del id ni de ningún dato del cliente, así que no se puede "calcular" la identidad a partir del token; solo se puede recuperar consultando el mapa. |
| **Dónde está el mapa** | pii.mapa_cliente(token, cliente_id), en un esquema separado (pii) sin USAGE para PUBLIC ni para analista. |
| **Quién debería acceder** | Solo un rol muy limitado: el DBA y, si existiera, un rol de "custodio de datos" para reidentificaciones autorizadas y documentadas (p. ej. atender un derecho ARCO o un caso de fraude). Nunca analítica. |
| **Por qué se separaron los permisos** | Si el mismo rol tiene los datos seudonimizados y el mapa, la seudonimización no protege nada: un JOIN devuelve la identidad. Separar los accesos es separación de funciones y mínimo privilegio. |


---

## 19.4 Anonimización (Actividades 5 y 6)


| | |
|---|---|
| **Identificadores eliminados** | nombre, correo, telefono, rfc e id. Las consultas de dirección solo devuelven conteos. |
| **Atributos generalizados** | edad → rangos (18-30, 31-45, 46+; en el reto 18-50 y 51+). codigo_postal → prefijo de 2 dígitos (80, 81, 82) y, en el reto, de 1 dígito (8xxxx). ciudad y fecha_alta se omitieron. |
| **Grupos suprimidos** | Con la consulta 12.4 (HAVING COUNT(\*) >= 5) se suprimieron los 3 grupos de 12.3 (de 3, 1 y 1 registros), por eso devolvió 0 rows: con solo 5 clientes ningún grupo llega a 5. En el reto no se suprime ninguno porque los 5 caen en un solo grupo (18-50 / 8xxxx / 5); k pasó de 1 a 5, pero a costa de casi toda la utilidad de la información. |
| **Riesgo que permanece** | a) La anonimización depende del contexto y de las fuentes externas que existan; ninguna técnica aislada la garantiza.<br>b) Cumplir k >= 5 protege contra identificar a quién pertenece una fila, pero no contra inferir atributos: en el reto el único grupo publicado es 18-50 / 8xxxx / 5, lo que revela que todos los clientes tienen entre 18 y 50 años y viven en la región 8xxxx (Sinaloa); si sé que alguien es cliente, ya sé su rango de edad y su región (homogeneidad, la limitación que motiva l-diversidad).<br>c) Con solo 5 registros, un grupo de k = 5 es la base completa.<br>d) Publicaciones repetidas en el tiempo permiten restar resultados y aislar registros nuevos.<br>Lo correcto es hablar de riesgo de reidentificación reducido, no eliminado. |






---

## 19.5 Retención (Actividad 7)

| | |
|---|---|
| **Criterio utilizado** | 5 años contados desde fecha_alta (parámetro del ejercicio). Consulta: SELECT \* FROM clientes WHERE fecha_alta < CURRENT_DATE - INTERVAL '5 years'; |
| **Registros afectados** | Ninguno con los datos del laboratorio: los 5 se dieron de alta hoy (DEFAULT CURRENT_DATE). Para comprobar que la consulta funciona, se retrocedió fecha_alta de los clientes 1 y 2 a 6 años atrás dentro de una transacción con ROLLBACK (UPDATE 2): la consulta los detectó (Ana López y Carlos Pérez) y no a los otros 3. Tras el ROLLBACK las 5 fechas volvieron a su valor original y no se borró nada. |
| **Qué debería conservarse** | Datos con obligación vigente: información fiscal (RFC y datos de facturación) por el plazo que marcan las disposiciones fiscales; datos de clientes con relación activa o con aclaraciones/litigios abiertos; estadísticas agregadas (no son datos personales). |
| **Qué podría eliminarse** | Datos de contacto (correo, teléfono) y cuasi-identificadores de clientes sin relación activa cuya finalidad ya se cumplió; sus tokens en pii.mapa_cliente. |

### Procedimiento propuesto (antes de eliminar)

1. **Identificación:** ejecutar la consulta de retención y generar la lista de id candidatos (sin exportar datos personales).
2. **Revisión de excepciones:** excluir clientes activos, con adeudos, aclaraciones abiertas, litigios o retención legal (legal hold).
3. **Aprobación:** autorización por escrito del responsable del tratamiento / área legal y del dueño del proceso (no del DBA solo: separación de funciones).
4. **Respaldo:** respaldo completo verificado (pg_dump cifrado o respaldo físico) con fecha, ubicación y periodo de vida definido, para poder recuperar un borrado accidental. El respaldo también debe tener fecha de caducidad; si no, la retención es solo aparente.
5. **Dependencias:** resolver primero pii.mapa_cliente. Por la llave foránea (mapa_cliente_cliente_id_fkey), un DELETE directo sobre clientes sería rechazado mientras el cliente tenga token en el mapa (no se ejecutó, porque la práctica indica no borrar). Al eliminar el token, las filas de analitica.clientes quedan sin forma de reidentificarse por el mapa (siguen teniendo cuasi-identificadores, así que también deben evaluarse).
6. **Ejecución en transacción:** BEGIN; DELETE … WHERE id = ANY(lista); -- verificar conteo esperado; COMMIT; (o ROLLBACK si el conteo no coincide).
7. **Evidencia que se conserva:** acta con fecha, criterio, número de registros, id eliminados (o un hash de ellos), aprobaciones, quién ejecutó y el identificador del respaldo. No se conservan los datos personales eliminados en la bitácora.
8. **Recuperación ante borrado accidental:** restaurar el respaldo en un entorno aislado y reinsertar solo los registros afectados; con archivado de WAL habilitado, recuperación a un punto en el tiempo (PITR) previo al borrado.


---

## 19.6 Conclusiones

- **¿Qué técnica para soporte?** Enmascaramiento dinámico mediante vista + REVOKE sobre la tabla. Soporte necesita saber quién es el cliente para atenderlo, así que no se le puede quitar la identidad; solo se le oculta lo que no necesita completo.
- **¿Qué técnica para analítica?** Seudonimización con token aleatorio y mapa en un esquema separado sin acceso para el analista. Permite seguir al mismo cliente a lo largo del tiempo (útil para tendencias) sin conocer su identidad; la reidentificación queda reservada a un rol autorizado. Idealmente, además, generalizar la edad y el CP en el conjunto analítico.
- **¿Qué técnica para publicar estadísticas?** Anonimización por agregación: generalización, supresión de grupos pequeños (umbral k) y solo totales, entregada mediante una vista exclusiva para dirección.
- **¿Por qué ninguna sustituye al control de acceso?** Porque las tres transforman una copia o una presentación del dato, pero el dato original sigue en clientes. Si alguien puede leer clientes o el mapa pii.mapa_cliente, se salta cualquier máscara, token o agregado. Además, el control de acceso es lo que decide quién ve cada versión (la vista, analitica.clientes o el mapa); sin él, las técnicas serían solo cosméticas.

---

## 20. Preguntas de reflexión

1. **Diferencia entre enmascaramiento y seudonimización.** El enmascaramiento oculta parte del valor al mostrarlo (\*\*\*\*\*\*4567) y el dato original no cambia; quien ve la vista sigue sabiendo quién es la persona (ve su nombre). La seudonimización sustituye el identificador por otro (token) y aparta la relación en un mapa protegido; quien recibe los datos no sabe quién es la persona, pero se puede volver a asociar con autorización.
2. **¿Por qué seudonimización no significa anonimización?** Porque es reversible: existe información adicional (el mapa) que permite reidentificar, y los cuasi-identificadores siguen presentes. Sigue siendo dato personal y sigue sujeto a las mismas obligaciones.
3. **¿Por qué quitar nombre y RFC no garantiza anonimato?** Porque los cuasi-identificadores combinados identifican. En este laboratorio, sin nombre ni RFC, edad + ciudad + CP deja a los 5 clientes en grupos de 1. Y con fuentes externas (redes sociales, padrones, conocidos) es fácil vincular esos atributos con una persona.
4. **Función de los cuasi-identificadores.** No identifican solos, pero al combinarse reducen el conjunto de personas posibles hasta, a veces, una sola. Son el puente que usa un atacante para unir un conjunto "anónimo" con una fuente externa que sí tiene nombres.
5. **¿Por qué separar el mapa de seudonimización?** Porque el mapa es la "llave" que revierte la protección. Si está junto a los datos analíticos, o accesible para el mismo rol, la seudonimización no aporta nada. Separado y con acceso mínimo, una fuga del conjunto analítico no expone identidades.
6. **Principio aplicado al impedir que el analista acceda al mapa.** Separación de funciones, apoyada en mínimo privilegio: quien analiza los datos no debe poder reidentificarlos, así que el analista recibe solo analitica.clientes y el mapa queda en manos de otro rol.
7. **¿Por qué una vista puede ser preferible a dar acceso a la tabla?** Porque permite entregar solo las columnas y filas necesarias, en la forma necesaria (enmascarada, agregada), sin dar permiso sobre la tabla base. Si la tabla cambia (se agregan columnas sensibles), el rol no las ve automáticamente. Y el permiso se administra sobre un objeto con finalidad clara.
8. **Diferencia entre proteger un dato para visualización y contra acceso no autorizado.** Proteger la visualización (enmascarar) solo cambia cómo se presenta el dato. Protegerlo contra acceso no autorizado (control de acceso, cifrado) impide que quien no debe pueda leer el dato real por cualquier vía. El primero sin el segundo es fácil de evadir, como se explicó en la Actividad 2: si soporte tuviera SELECT en clientes, la máscara no serviría.
9. **¿Por qué la retención es parte de la protección de datos?** Porque el dato que ya no existe no puede filtrarse. Conservar solo lo necesario y durante el tiempo justificado reduce la superficie de exposición y cumple los principios de finalidad y minimización.
10. **Riesgo de conservar información indefinidamente.** Mayor impacto ante una brecha (más personas y más años expuestos), incumplimiento normativo (conservar sin finalidad), datos desactualizados que llevan a decisiones erróneas, más costo de almacenamiento y respaldos, y más trabajo para atender solicitudes de los titulares.

---
 