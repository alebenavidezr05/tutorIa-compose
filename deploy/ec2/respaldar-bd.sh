#!/usr/bin/env bash
# Respaldo de PostgreSQL a S3 cifrado con KMS.
# pg_dump -> gzip a archivo temporal -> gzip -t -> aws s3 cp (SSE-KMS) -> borrar temporal.
# No usa una tubería directa a S3: si pg_dump fallara a mitad, se subiría un archivo truncado.
# Lee bucket, clave y región de /etc/tutoria/instancia.env (NO del .env de la aplicación).
# Uso manual: sudo /usr/local/bin/respaldar-bd.sh
set -euo pipefail

DIR_APP="${DIR_APP:-/home/ubuntu/tutoria}"
CONF=/etc/tutoria/instancia.env

leer() { grep -E "^$1=" "$CONF" | tail -n1 | cut -d= -f2-; }

[ -r "$CONF" ] || { logger -t tutoria "respaldo: falta $CONF"; exit 1; }
BUCKET="$(leer BUCKET_RESPALDOS)"
KMS="$(leer KMS_KEY_ID)"
REGION="$(leer AWS_REGION)"
[ -n "$BUCKET" ] && [ -n "$KMS" ] && [ -n "$REGION" ] \
    || { logger -t tutoria "respaldo: configuración incompleta en $CONF"; exit 1; }

FECHA="$(date -u +%Y%m%dT%H%M%SZ)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ARCHIVO="$TMP/tutoria-$FECHA.sql.gz"

cd "$DIR_APP"
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner' \
    | gzip -9 > "$ARCHIVO"
# Con pipefail, un fallo de pg_dump ya habría abortado; además se valida el gzip.
gzip -t "$ARCHIVO"

aws s3 cp "$ARCHIVO" "s3://$BUCKET/bd/tutoria-$FECHA.sql.gz" \
    --region "$REGION" --sse aws:kms --sse-kms-key-id "$KMS" --only-show-errors

logger -t tutoria "respaldo subido: s3://$BUCKET/bd/tutoria-$FECHA.sql.gz ($(du -h "$ARCHIVO" | cut -f1))"
echo "s3://$BUCKET/bd/tutoria-$FECHA.sql.gz"
