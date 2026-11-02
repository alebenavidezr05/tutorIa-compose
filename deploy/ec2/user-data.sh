#!/usr/bin/env bash
# Primera configuración de la instancia EC2 (cloud-init, Ubuntu 24.04). Idempotente y SIN secretos.
# ANTES de lanzar la instancia, edita los tres valores de abajo (no son secretos).
set -euxo pipefail

BUCKET_RESPALDOS="tutoria-respaldos-<cuenta>"
KMS_KEY_ID="alias/tutoria-prod"
AWS_REGION="us-east-1"

export DEBIAN_FRONTEND=noninteractive

# 1. Sistema al día y herramientas básicas.
apt-get update
apt-get -y upgrade
apt-get install -y ca-certificates curl gnupg git jq unzip unattended-upgrades

# 2. Docker Engine + plugin Compose desde el repositorio oficial de Docker.
if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
usermod -aG docker ubuntu

# 3. AWS CLI v2 (instalador oficial según la arquitectura).
if ! command -v aws >/dev/null 2>&1; then
    case "$(uname -m)" in
        x86_64) ARQ=x86_64 ;;
        aarch64) ARQ=aarch64 ;;
        *) echo "arquitectura no soportada"; exit 1 ;;
    esac
    TMP="$(mktemp -d)"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARQ}.zip" -o "$TMP/awscliv2.zip"
    unzip -q "$TMP/awscliv2.zip" -d "$TMP"
    "$TMP/aws/install"
    rm -rf "$TMP"
fi

# 4. Swap de 2 GB (compilar Angular en 2 GB de RAM puede agotar la memoria).
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
fi
swapon --show | grep -q /swapfile || swapon /swapfile
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 5. Configuración de la instancia para los scripts de respaldo (no es el .env de la app).
install -d -m 0755 /etc/tutoria
cat > /etc/tutoria/instancia.env <<EOF
BUCKET_RESPALDOS=${BUCKET_RESPALDOS}
KMS_KEY_ID=${KMS_KEY_ID}
AWS_REGION=${AWS_REGION}
EOF
chmod 0644 /etc/tutoria/instancia.env

# 6. Directorio de la aplicación.
install -d -o ubuntu -g ubuntu -m 0755 /home/ubuntu/tutoria

# 7. Actualizaciones de seguridad automáticas.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

echo "user-data de TutorIA completado"
