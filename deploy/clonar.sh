#!/usr/bin/env bash
# Clona (o actualiza) tutorIa-backend y tutorIa-frontend dentro de esta carpeta como
# backend/ y frontend/. Los repositorios son públicos: no hacen falta llaves ni tokens.
# Uso (desde la raíz de tutorIa-compose):  bash deploy/clonar.sh
set -euo pipefail

# Direcciones de los repositorios (cámbialas si usas un fork).
REPO_BACKEND="${REPO_BACKEND:-https://github.com/alebenavidezr05/tutorIa-backend.git}"
REPO_FRONTEND="${REPO_FRONTEND:-https://github.com/alebenavidezr05/tutorIa-frontend.git}"
RAMA="${RAMA:-main}"

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$REPO_BACKEND" == *"<usuario>"* || "$REPO_FRONTEND" == *"<usuario>"* ]]; then
    echo "Edita REPO_BACKEND y REPO_FRONTEND al inicio de deploy/clonar.sh (o expórtalas)." >&2
    exit 1
fi

traer() {
    local url="$1" destino="$RAIZ/$2"
    if [ -d "$destino/.git" ]; then
        echo "Actualizando $2 ..."
        git -C "$destino" pull --ff-only
    elif [ -e "$destino" ]; then
        echo "$destino existe pero no es un repositorio git; no lo toco." >&2
        exit 1
    else
        echo "Clonando $2 ..."
        git clone --branch "$RAMA" "$url" "$destino"
    fi
}

traer "$REPO_BACKEND" backend
traer "$REPO_FRONTEND" frontend
echo "Listo: backend/ y frontend/ junto a docker-compose.yml"
