# Gestión de Seguridad y Desempeño de Bases de Datos

| | |
|---|---|
| **Estudiante** | Cristopher Enrique Sánchez Castañeda |
| **Matrícula** | 20434863 |
| **Grupo** | 403 |
| **Motor** | PostgreSQL 16 |

Repositorio personal de prácticas de la materia.

## Contenido

```
.
├── README.md                          ← este archivo
├── .gitignore                         ← excluye secretos, claves, certificados y respaldos
├── entorno/                           ← entorno compartido de la Unidad II (Docker)
│   ├── docker-compose.yml             ← PostgreSQL 16 con TLS obligatorio por red
│   ├── .env.example                   ← plantilla de variables (sin secretos reales)
│   ├── pg_hba.conf                    ← solo conexiones hostssl + scram-sha-256
│   └── tls/generar-certificados.sh    ← crea CA y certificado del servidor de laboratorio
└── unidad-02/
    └── lab-02-cifrado-credenciales/   ← LAB-02
```

## Preparar el entorno

Requisitos: Docker Desktop.

```bash
cd entorno
cp .env.example .env                 # PowerShell: Copy-Item .env.example .env
# editar .env y poner contraseñas propias

# Generar CA y certificado del servidor (las claves privadas no se suben al repo)
sh tls/generar-certificados.sh       # Linux, macOS o Git Bash
# o, solo con Docker:
docker run --rm -v "${PWD}/tls:/tls" alpine:3.20 sh -c "apk add --no-cache openssl >/dev/null && sh /tls/generar-certificados.sh /tls"

docker compose up -d
```

Consola de administración dentro del contenedor (socket local, autenticación `peer`):

```bash
docker exec -it -u postgres lab-postgres psql -d lab01
```

Conexión por red, como una aplicación, con verificación completa del servidor:

```bash
docker compose --profile cliente run --rm cliente "host=db.lab02.local dbname=lab01 user=app_lab02 sslmode=verify-full sslrootcert=/tls/ca.crt"
```

## Reglas del repositorio

- No se suben contraseñas, claves, tokens ni certificados privados. Los valores reales viven en `entorno/.env` (ignorado por Git).
- Antes de cada commit se revisa el contenido con `grep -RniE 'password|passwd|secret|token|api_key|clave' .`.
