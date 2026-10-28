#!/bin/sh
# ---------------------------------------------------------------------------
# Genera una autoridad certificadora (CA) de laboratorio y un certificado de
# servidor para PostgreSQL.
#
#   ca.key / ca.crt          -> CA privada del laboratorio
#   server.key / server.crt  -> certificado del servidor, firmado por la CA
#
# El certificado del servidor es válido para los nombres:
#   localhost  y  db.lab02.local
# (NO incluye la IP 127.0.0.1: así se puede demostrar que verify-full rechaza
#  una conexión cuyo nombre no coincide con el certificado).
#
# Las claves privadas (*.key) NUNCA se suben al repositorio (ver .gitignore).
# Cada estudiante genera las suyas en su máquina.
#
# Uso (Linux, macOS o Git Bash en Windows):
#   sh entorno/tls/generar-certificados.sh
# Uso solo con Docker (sin openssl instalado):
#   docker run --rm -v "$PWD/entorno/tls:/tls" alpine:3.20 \
#     sh -c "apk add --no-cache openssl >/dev/null && sh /tls/generar-certificados.sh /tls"
# ---------------------------------------------------------------------------
set -eu
DIR="${1:-$(dirname "$0")}"
cd "$DIR"

if [ -f server.key ] && [ -f server.crt ] && [ -f ca.crt ]; then
  echo "Los certificados ya existen en $DIR (bórralos si quieres regenerarlos)."
  exit 0
fi

# 1. Autoridad certificadora del laboratorio
openssl req -new -x509 -nodes -days 365 -newkey rsa:3072 \
  -keyout ca.key -out ca.crt \
  -subj "/C=MX/ST=Sinaloa/O=Comercializadora Norte LAB/CN=CA Laboratorio DBA"

# 2. Clave y solicitud de firma (CSR) del servidor
openssl req -new -nodes -newkey rsa:3072 \
  -keyout server.key -out server.csr \
  -subj "/C=MX/ST=Sinaloa/O=Comercializadora Norte LAB/CN=localhost"

# 3. Extensiones: nombres alternativos válidos para verify-full
cat > server.ext <<'EOF'
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, DNS:db.lab02.local
EOF

# 4. La CA firma el certificado del servidor
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 365 -sha256 -extfile server.ext -out server.crt

rm -f server.csr server.ext ca.srl
chmod 600 ca.key server.key
echo "Certificados generados en $DIR:"
ls -l .
