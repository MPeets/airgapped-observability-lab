#!/usr/bin/env bash
# Creates a small internal CA and a server certificate for the tls-demo service.
# Mirrors what an air-gapped network does: no public CA, an internal PKI instead.
#
# Usage: ./scripts/gen-lab-certs.sh [days]
#   days  validity of the server certificate (default 20, so the 30-day warning fires)
#
# Only relative paths are passed to openssl, and subjects come from config files
# instead of -subj "/CN=...". That keeps it working in Git Bash on Windows, where
# the native openssl.exe can't resolve Unix-style absolute paths like /tmp/...
set -euo pipefail

DAYS="${1:-20}"
cd "$(dirname "$0")/.."
OUT=certs
WORK="$OUT/.work"
mkdir -p "$OUT/private" "$OUT/public" "$OUT/tls-demo" "$WORK"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/ca.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no
[dn]
CN = Lab Internal CA
[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
CNF

cat > "$WORK/server.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = tls-demo
CNF

cat > "$WORK/server.ext" <<CNF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:tls-demo, DNS:localhost
CNF

if [[ ! -f "$OUT/private/ca.key" ]]; then
  echo "Creating lab CA (valid 365 days)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -config "$WORK/ca.cnf" \
    -keyout "$OUT/private/ca.key" -out "$OUT/public/ca.crt"
else
  echo "Reusing existing lab CA"
fi

echo "Issuing tls-demo certificate (valid $DAYS days)"
openssl req -new -newkey rsa:2048 -nodes \
  -config "$WORK/server.cnf" \
  -keyout "$OUT/tls-demo/tls.key" -out "$WORK/tls.csr"
openssl x509 -req -in "$WORK/tls.csr" -days "$DAYS" \
  -CA "$OUT/public/ca.crt" -CAkey "$OUT/private/ca.key" \
  -CAcreateserial -CAserial "$OUT/private/ca.srl" \
  -extfile "$WORK/server.ext" -out "$OUT/tls-demo/tls.crt"

# Containers run as non-root users; the key must be readable inside them.
chmod 644 "$OUT/tls-demo/tls.key"

echo
openssl verify -CAfile "$OUT/public/ca.crt" "$OUT/tls-demo/tls.crt"
openssl x509 -in "$OUT/tls-demo/tls.crt" -noout -subject -enddate