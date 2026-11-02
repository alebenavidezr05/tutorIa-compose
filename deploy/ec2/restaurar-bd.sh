#!/usr/bin/env bash
# Restaura un respaldo de S3 SOBRE la base de datos actual (la borra).
# Uso: sudo /usr/local/bin/restaurar-bd.sh tutoria-20260101T000000Z.sql.gz
#      (nombre dentro de s3://<bucket>/bd/ o ruta s3:// completa)
# Para una restauración de PRUEBA a otra base:  BD_DESTINO=tutoria_prueba restaurar-bd.sh <archivo>
# Los datos cifrados solo se leen con la misma clave KMS y la misma CIFRADO_DEK_ENVUELTA.
set -euo pipefail

DIR_APP="${DIR_APP:-/home/ubuntu/tutoria}"
CONF=/etc/tutoria/instancia.env
leer() { grep -E "^$1=" "$CONF" | tail -n1 | cut -d= -f2-; }

[ $# -eq 1 ] || { echo "Uso: $0 <archivo.sql.gz | s3://...>" >&2; exit 1; }
BUCKET="$(leer BUCKET_RESPALDOS)"
REGION="$(leer AWS_REGION)"
ORIGEN="$1"
[[ "$ORIGEN" == s3://* ]] || ORIGEN="s3://$BUCKET/bd/$ORIGEN"

cd "$DIR_APP"
DESTINO="${BD_DESTINO:-}"
PRINCIPAL="$(docker compose exec -T db sh -c 'printf %s "$POSTGRES_DB"')"
DESTINO="${DESTINO:-$PRINCIPAL}"
[[ "$DESTINO" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "Nombre de base inválido: $DESTINO" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
aws s3 cp "$ORIGEN" "$TMP/respaldo.sql.gz" --region "$REGION" --only-show-errors
gzip -t "$TMP/respaldo.sql.gz"

echo "Se BORRARÁ la base '$DESTINO' y se reemplazará con $ORIGEN."
read -r -p "Escribe BORRAR para continuar: " CONFIRMA
[ "$CONFIRMA" = "BORRAR" ] || { echo "Cancelado."; exit 1; }

ES_PRINCIPAL=0
[ "$DESTINO" = "$PRINCIPAL" ] && ES_PRINCIPAL=1
[ "$ES_PRINCIPAL" -eq 1 ] && docker compose stop backend

docker compose exec -T db sh -c "psql -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d postgres \
    -c 'DROP DATABASE IF EXISTS $DESTINO WITH (FORCE);' \
    -c 'CREATE DATABASE $DESTINO OWNER \"'\"\$POSTGRES_USER\"'\";'"
gunzip -c "$TMP/respaldo.sql.gz" \
    | docker compose exec -T db sh -c "psql -v ON_ERROR_STOP=1 -q -U \"\$POSTGRES_USER\" -d $DESTINO"

[ "$ES_PRINCIPAL" -eq 1 ] && docker compose start backend
logger -t tutoria "restauración completada en '$DESTINO' desde $ORIGEN"
echo "Restauración completada en '$DESTINO'."
