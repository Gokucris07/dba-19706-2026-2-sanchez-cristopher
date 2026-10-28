# LAB-01 — Protección y privacidad de datos
> Historial original de este laboratorio: https://github.com/Gokucris07/LAB-01

- Estudiante: Cristopher Enrique Sánchez Castañeda
- Matrícula: 20434863
- Grupo: 403
- Materia: Gestión de Seguridad y Desempeño de Bases de Datos

## Cómo ejecutarlo

Requisito: Docker Desktop. Desde la carpeta del proyecto:

```
docker compose up -d
```

Luego se ejecutan los scripts en orden (cambia el nombre del archivo en cada paso):

```
docker exec -it lab01-postgres psql -U postgres -d lab01 -P pager=off -e -f /sql/01-clasificacion.sql
```

Orden: 01-clasificacion, 02-enmascaramiento, 03-seudonimizacion, 04-anonimizacion, 05-retencion.

## Contenido

- sql/: scripts de cada actividad
- evidencias/: PDFs con las capturas y respuestas de cada actividad
- informe.md: informe con explicaciones, conclusiones y preguntas de reflexión