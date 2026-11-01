# Evidencia 15 — Propuesta de arquitectura de datos protegidos

| | |
|---|---|
| Estudiante | Cristopher Enrique Sánchez Castañeda · Matrícula 20434863 · Grupo 403 |
| Actividad | 21. Actividad 15 — Propuesta de arquitectura de datos protegidos |
| Fecha | 2026-10-31 |

## Objetivo

Diseñar una arquitectura conceptual que separe la información de Comercializadora Norte según su finalidad (operación, facturación, analítica y auditoría) y que incluya controles de acceso, minimización, protección de datos sensibles, retención, trazabilidad, eliminación y atención de solicitudes.

## Procedimiento

Se partió de las finalidades del inventario (evidencia 01) y de la matriz de gobierno (evidencia 11). Cada finalidad se llevó a un esquema de PostgreSQL, porque con un esquema se pueden dar permisos por bloque; LAB-01 ya usaba `pii` y `analitica`.

Luego se definió cómo se mueven los datos entre zonas: en una sola dirección y solo con los campos necesarios. Por último, a cada zona se le asignaron los controles que pide el enunciado, marcando cuáles ya existen en el repositorio y cuáles son propuesta.

## Resultado

### Diagrama

```
                                BASE DE DATOS  lab01  (PostgreSQL 16, TLS verify-full · LAB-02)
                                                   │
         ┌──────────────────────────┬──────────────┴───────────┬──────────────────────────┐
         │                          │                          │                          │
         ▼                          ▼                          ▼                          ▼
   ┌─────────────┐          ┌───────────────┐          ┌───────────────┐          ┌───────────────┐
   │  OPERACIÓN  │          │  FACTURACIÓN  │          │   ANALÍTICA   │          │   AUDITORÍA   │
   │  esquema    │          │  esquema pii  │          │   esquema     │          │   esquema     │
   │  operacion  │          │               │          │   analitica   │          │   auditoria   │
   └──────┬──────┘          └───────┬───────┘          └───────┬───────┘          └───────┬───────┘
          │                         │                          │                          │
          ▼                         ▼                          ▼                          ▼
   Datos necesarios          RFC cifrado AES-256        Datos agregados            Registro de quién
   para operación            (pgcrypto, clave           (ciudad, rango de          consultó/cambió qué,
   nombre, correo,           fuera de la base)          edad, región CP,           solicitudes ARCO
   teléfono, ciudad,         mapa token ↔ cliente       conteos ≥ k)               atendidas, ejecución
   fecha_alta                                                                       de la retención
          │                         │                          ▲                          ▲
          │                         │                          │                          │
          └──── proceso mensual de agregación (solo ida) ──────┘                          │
          └──── todos los cambios y consultas sensibles ──────────────────────────────────┘

   ROLES:  atencion ─► vista operacion     facturacion ─► pii (con clave)
           analista ─► solo analitica      marketing ─► v_contactables_promociones (si se aprueba)
           dba ─► administra todo, sin uso de negocio      auditor ─► solo lectura de auditoria

   FUERA DE PRODUCCIÓN
   ┌──────────────────────┐   ┌──────────────────────────┐   ┌─────────────────────────────┐
   │ Respaldos cifrados    │   │ Desarrollo / pruebas     │   │ Exportaciones               │
   │ con retención propia  │   │ SOLO datos sintéticos o  │   │ registradas, cifradas, con  │
   │ (LAB-02, evidencia 07)│   │ enmascarados (LAB-01)    │   │ fecha de eliminación        │
   └──────────────────────┘   └──────────────────────────┘   └─────────────────────────────┘
```

### Zonas

| Zona | Contenido | Quién accede | Por qué va separada |
|---|---|---|---|
| Operación (`operacion`) | Nombre, correo, teléfono, ciudad, fecha de alta | Atención al cliente, por medio de una vista | Es lo que el negocio usa a diario. No incluye RFC ni edad. |
| Facturación (`pii`) | RFC cifrado; mapa token ↔ cliente | Facturación, con la clave | Es el dato de mayor riesgo; aislado se le puede aplicar cifrado y un rol propio. |
| Analítica (`analitica`) | Solo agregados (ciudad, rango de edad, región, conteos) | Analítica | Analítica no necesita saber quién es quién. Se alimenta con un proceso que solo manda agregados. |
| Auditoría (`auditoria`) | Registro de accesos, cambios, solicitudes ARCO y ejecuciones de retención | Auditor / privacidad (solo lectura) | Quien es auditado no debe poder tocar el registro. |

### Controles por zona

| Control | Operación | Facturación | Analítica | Auditoría | Estado |
|---|---|---|---|---|---|
| Acceso | Rol `atencion` con `SELECT` en una vista; sin acceso a `pii` | Rol `facturacion`; `REVOKE ALL FROM PUBLIC` | Rol `analista` solo con `SELECT` en agregados | Solo lectura para el auditor; solo el proceso escribe | Implementado para `analista` (script 03) y `soporte` (LAB-01); propuesto para el resto |
| Minimización | Sin RFC, edad ni CP completo (`clientes_soporte`, script 01) | Solo el RFC, no el resto del perfil | Rangos y regiones, nunca el dato exacto | Guarda quién y cuándo, no copia los datos completos | Implementado (scripts 01 y 02) |
| Protección de información sensible | Enmascaramiento cuando no hace falta el dato completo (LAB-01) | Cifrado AES-256, clave fuera del repositorio (LAB-02) | Supresión de grupos pequeños (k ≥ umbral, LAB-01) | Registro protegido contra cambios | Implementado en LAB-01/02; propuesto para auditoría |
| Retención | Relación comercial activa | Plazo fiscal que confirme jurídico; bloqueo | Los agregados no identifican y no tienen plazo; el detalle se elimina | Plazo propio que defina jurídico | Propuesto (evidencia 10); consulta de vencidos en LAB-01 |
| Trazabilidad | Cambios registrados en `auditoria` | Uso de la clave registrado | Consultas registradas | — | Propuesto (Unidad III). Hoy `log_statement = none` (Actividad 7) |
| Eliminación | Se borra el registro al vencer o por cancelación autorizada | Bloqueo durante el plazo legal; después se borra | Al borrar el detalle, los agregados no cambian | Se registra qué se borró, sin guardar el dato | Propuesto; mapa de ubicaciones (evidencia 08) |
| Atención de solicitudes | Consultas de acceso y rectificación sobre la tabla y sus copias | El RFC solo lo rectifica facturación | No aplica a agregados anónimos | Folio de cada solicitud, fecha y quién la atendió | Parcial: consultas de acceso y mapa (script 03), oposiciones (script 02) |

### Cómo se atendería una cancelación con esta arquitectura

1. Privacidad recibe la solicitud, verifica la identidad y decide si procede. No lo decide el DBA.
2. El DBA corre las consultas de localización (Actividad 6 y evidencia 08) y entrega el mapa.
3. Jurídico indica qué se guarda bloqueado (lo fiscal) y qué se borra.
4. El DBA borra en `operacion`, bloquea en `pii`, revisa que en analítica solo haya agregados y deja registro en `auditoria`.
5. Los respaldos conservan el dato hasta que expiran. Si se restaura uno, se vuelven a aplicar las cancelaciones registradas.

## Análisis

Con esta arquitectura los principios se vuelven fronteras dentro de la base: cada finalidad es un esquema, cada área un rol, y cada rol ve solo su esquema. La minimización ya no depende de que cada usuario se porte bien.

Hacia analítica los datos van en una sola dirección y ya agregados. Eso corrige lo que apareció en el script 03, donde `analitica.clientes` de LAB-01 tenía edad exacta, código postal completo y un token por persona.

Separar facturación permite poner el control más fuerte, el cifrado, solo donde hace falta, sin complicar la operación diaria.

Para que la arquitectura quede completa falta la zona de auditoría. Sin ella no se puede probar quién entró a los datos ni que una rectificación estaba autorizada. Es lo que conecta con la Unidad III.

Fuera de producción, la regla que más pesa es que desarrollo no reciba datos reales. De nada sirve separar todo en producción si una copia completa acaba en una laptop.

## Conclusión

La propuesta divide los datos en cuatro zonas según su finalidad (operación, facturación, analítica y auditoría), cada una con su rol y sus controles. De producción solo salen respaldos cifrados, datos sintéticos y exportaciones registradas. Buena parte ya está implementada en el repositorio. Lo que falta, la trazabilidad, es lo que permitiría demostrar que todo lo demás se cumple.
