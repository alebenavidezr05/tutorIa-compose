#!/usr/bin/env bash
# Apaga la instancia si nadie usó la API en los últimos MIN_INACTIVO minutos.
# Lo invoca /etc/cron.d/tutoria-apagado cada 5 minutos como root.
#
# Cuenta como uso: peticiones a /api/v1/ (excepto /api/v1/health*) con respuesta 2xx/3xx en el
# registro de acceso JSON de Caddy. Robots/escáneres (401/404) y healthchecks NO cuentan.
# Seguro ante fallos: si no puede leer los logs, NO apaga.
# Siempre encendida: si existe /etc/tutoria/siempre-encendido, no apaga nunca.
# Revisa lo que hizo con: journalctl -t tutoria
set -uo pipefail

MIN_INACTIVO="${MIN_INACTIVO:-30}"
GRACIA_MIN="${GRACIA_MIN:-20}"
DIR_APP="${DIR_APP:-/home/ubuntu/tutoria}"

cd "$DIR_APP" || exit 0
[ -f /etc/tutoria/siempre-encendido ] && exit 0

# Periodo de gracia: da tiempo a quien acaba de despertar la instancia.
up_min=$(( $(cut -d. -f1 /proc/uptime) / 60 ))
[ "$up_min" -lt "$GRACIA_MIN" ] && exit 0

if ! logs=$(docker compose logs --since "${MIN_INACTIVO}m" --no-log-prefix frontend 2>/dev/null); then
    logger -t tutoria "no pude leer los logs de Caddy; no apago"
    exit 0
fi

n=$(printf '%s\n' "$logs" \
    | jq -Rc 'fromjson? | select(type == "object" and .request.uri != null)
        | select((.request.uri | startswith("/api/v1/")) and ((.request.uri | startswith("/api/v1/health")) | not))
        | select(.status >= 200 and .status < 400) | 1' 2>/dev/null \
    | wc -l) || { logger -t tutoria "no pude filtrar los logs; no apago"; exit 0; }

if [ "${n:-0}" -eq 0 ]; then
    logger -t tutoria "sin uso en ${MIN_INACTIVO} min: limpieza, respaldo y apagado"
    timeout 120 docker compose exec -T backend python -m app.scripts.limpiar_datos_vencidos >/dev/null 2>&1 \
        || logger -t tutoria "la limpieza de datos vencidos falló"
    timeout 900 /usr/local/bin/respaldar-bd.sh || logger -t tutoria "el respaldo falló"
    /sbin/shutdown -h now
fi
