#!/usr/bin/env bash
# Instala los scripts de operación, la unidad systemd y el cron de apagado automático.
# Se ejecuta una vez tras clonar (y puede repetirse sin problema):
#   sudo bash /home/ubuntu/tutoria/deploy/ec2/instalar.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta con sudo." >&2
    exit 1
fi

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for script in apagar-si-inactivo.sh respaldar-bd.sh restaurar-bd.sh; do
    install -m 0755 -o root -g root "$ORIGEN/$script" "/usr/local/bin/$script"
done

install -m 0644 -o root -g root "$ORIGEN/tutoria.service" /etc/systemd/system/tutoria.service
# cron.d exige archivos sin extensión, de root, sin permisos de escritura para otros.
install -m 0644 -o root -g root "$ORIGEN/tutoria-apagado.cron" /etc/cron.d/tutoria-apagado

install -d -m 0755 /etc/tutoria
[ -f /etc/tutoria/instancia.env ] || echo "AVISO: falta /etc/tutoria/instancia.env (ver user-data.sh)" >&2

systemctl daemon-reload
systemctl enable tutoria
systemctl restart cron

echo "Instalado: /usr/local/bin/{apagar-si-inactivo,respaldar-bd,restaurar-bd}.sh, tutoria.service y /etc/cron.d/tutoria-apagado"
echo "Siguiente paso: crear /home/ubuntu/tutoria/.env y ejecutar: sudo systemctl start tutoria"
