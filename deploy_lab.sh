#!/bin/bash
# deploy_lab.sh
# Script d'installation et de déploiement du lab Purple Team sur Debian 12

set -e
set -u

echo "=== Vérification des privilèges sudo ==="
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté avec sudo"
    exit 1
fi

echo "=== Vérification et installation Docker ==="
if ! command -v docker &>/dev/null; then
    echo "Docker non trouvé, installation..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        apt-get remove -y $pkg || true
    done
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "Docker est déjà installé, on skip cette étape."
fi

# Crée un répertoire pour les volumes persistants
mkdir -p ~/lab-volumes/{debian12,ubuntu,windows,netdata}

# Fonction de déploiement qui skip si le conteneur existe
deploy_container() {
    local name=$1
    shift
    if [ "$(docker ps -a -q -f name=^/${name}$)" ]; then
        echo "Conteneur $name existe déjà, skip."
    else
        echo "Démarrage du conteneur $name..."
        docker run "$@"
    fi
}

# === Déploiement Wazuh ===
if [ ! -d ~/wazuh-docker ]; then
    echo "=== Déploiement Wazuh ==="
    cd ~
    git clone https://github.com/wazuh/wazuh-docker.git -b v4.12.0
    cd wazuh-docker/single-node/
    docker compose -f generate-indexer-certs.yml run --rm generator
    docker compose up -d
    cd ~
else
    echo "Wazuh déjà déployé, skip."
fi

# === Déploiement Caldera ===
if [ ! -d ~/caldera ]; then
    echo "=== Déploiement Caldera ==="
    cd ~
    git clone https://github.com/mitre/caldera.git --recursive --branch 5.3.0
    cd caldera
    docker build --build-arg WIN_BUILD=true -t caldera:server .
    docker compose build
    docker run -d -p 7010:7010 -p 7011:7011/udp -p 7012:7012 -p 8888:8888 caldera:server
    cd ~
else
    echo "Caldera déjà déployé, skip."
fi

# === Déploiement Netdata ===
deploy_container netdata -d --name=netdata \
  --pid=host \
  --network=host \
  -v netdataconfig:/etc/netdata \
  -v netdatalib:/var/lib/netdata \
  -v netdatacache:/var/cache/netdata \
  -v /:/host/root:ro,rslave \
  -v /etc/passwd:/host/etc/passwd:ro \
  -v /etc/group:/host/etc/group:ro \
  -v /etc/localtime:/etc/localtime:ro \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /etc/os-release:/host/etc/os-release:ro \
  -v /var/log:/host/var/log:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /run/dbus:/run/dbus:ro \
  --restart unless-stopped \
  --cap-add SYS_PTRACE \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  netdata/netdata

# === Déploiement Windows Server 2022 ===
deploy_container windows -d \
  --name windows \
  --restart always \
  --stop-timeout 120 \
  -e VERSION=2022 \
  --device /dev/kvm \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -p 8006:8006 \
  -p 3389:3389/tcp \
  -p 3389:3389/udp \
  -v ~/lab-volumes/windows:/storage \
  dockurr/windows

# === Déploiement Debian 12 ===
deploy_container debian12 -d \
  --name debian12 \
  --hostname debian12 \
  --restart always \
  -it \
  -p 2222:22 \
  -v ~/lab-volumes/debian12:/root \
  debian:12 sleep infinity

# === Déploiement Ubuntu ===
deploy_container ubuntu -d \
  --name ubuntu \
  --hostname ubuntu \
  --restart always \
  -it \
  -p 2223:22 \
  -v ~/lab-volumes/ubuntu:/root \
  ubuntu:latest sleep infinity

echo "=== Déploiement terminé ==="
docker ps
