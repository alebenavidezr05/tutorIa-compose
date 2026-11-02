#!/usr/bin/env bash
# Actualiza TutorIA en la EC2: respaldo, git pull de los TRES repositorios, build, up -d y verificación.
# Uso (sesión SSM):  sudo -u ubuntu bash /home/ubuntu/tutoria/deploy/ec2/actualizar.sh
# Lo usa también .github/workflows/deploy.yml (vía SSM, como root).
set -euo pipefail

DIR_APP="${DIR_APP:-/home/ubuntu/tutoria}"
cd "$DIR_APP"

# Si se ejecuta como root (SSM), git y docker corren como el dueño del repositorio.
como_ubuntu() {
    if [ "$(id -un)" = "ubuntu" ]; then "$@"; else sudo -u ubuntu -H "$@"; fi
}

echo "1/5 Respaldo previo"
if [ -x /usr/local/bin/respaldar-bd.sh ]; then
    sudo /usr/local/bin/respaldar-bd.sh || { echo "El respaldo falló; no actualizo." >&2; exit 1; }
fi

echo "2/5 git pull (compose, backend, frontend)"
for repo in . backend frontend; do
    como_ubuntu git -C "$DIR_APP/$repo" pull --ff-only
done

echo "3/5 docker compose build"
como_ubuntu docker compose build --pull

echo "4/5 docker compose up -d"
como_ubuntu docker compose up -d --remove-orphans

echo "5/5 Esperando healthchecks"
for _ in $(seq 1 60); do
    estados="$(como_ubuntu docker compose ps --format '{{.Service}} {{.Health}}')"
    if ! grep -qv ' healthy$' <<<"$estados"; then break; fi
    sleep 5
done
echo "$estados"
grep -qv ' healthy$' <<<"$estados" && { echo "Algún servicio no está healthy." >&2; exit 1; }

# Verificación externa a través de Caddy y HTTPS.
DOMINIO="$(grep -E '^SITE_ADDRESS=' .env | tail -n1 | cut -d= -f2-)"
if [[ -n "$DOMINIO" && "$DOMINIO" != :* ]]; then
    curl -fsS --max-time 15 "https://$DOMINIO/api/v1/health/ready" >/dev/null
    echo "OK: https://$DOMINIO/api/v1/health/ready"
fi
docker image prune -f >/dev/null || true
echo "Actualización completada."
