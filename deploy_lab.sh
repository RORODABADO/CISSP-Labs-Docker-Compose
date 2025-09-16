#!/bin/bash
# deploy_lab.sh
# Script d'installation et de déploiement du lab Purple Team sur Debian 12

set -e  # exit on error
set -u  # exit on unset variables

echo "=== Vérification des privilèges sudo ==="
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté avec sudo"
    exit 1
fi

echo "=== Suppression d'anciennes installations Docker ==="
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y $pkg || true
done

echo "=== Installation des prérequis ==="
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

echo "=== Ajout de la clé GPG officielle Docker ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "=== Ajout du dépôt Docker ==="
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Vérification Docker ==="
docker --version
docker compose version

# Crée un répertoire pour les volumes persistants
mkdir -p ~/lab-volumes/{debian12,ubuntu,windows,netdata}

# === Déploiement Wazuh ===
echo "=== Déploiement Wazuh ==="
cd ~
git clone https://github.com/wazuh/wazuh-docker.git -b v4.12.0
cd wazuh-docker/single-node/
docker compose -f generate-indexer-certs.yml run --rm generator
docker compose up -d
cd ~  # Retour au home

# === Déploiement Caldera ===
echo "=== Déploiement Caldera ==="
git clone https://github.com/mitre/caldera.git --recursive --branch 5.3.0
cd caldera
docker build --build-arg WIN_BUILD=true -t caldera:server .
docker compose build
docker run -d -p 7010:7010 -p 7011:7011/udp -p 7012:7012 -p 8888:8888 caldera:server
cd ~

# === Déploiement Netdata ===
echo "=== Déploiement Netdata ==="
docker run -d --name=netdata \
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
echo "=== Déploiement Windows Server 2022 ==="
mkdir -p ~/lab-volumes/windows
docker run -d \
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
echo "=== Déploiement Debian 12 ==="
mkdir -p ~/lab-volumes/debian12
docker run -d \
  --name debian12 \
  --hostname debian12 \
  --restart always \
  -it \
  -p 2222:22 \
  -v ~/lab-volumes/debian12:/root \
  debian:12 sleep infinity

# === Déploiement Ubuntu ===
echo "=== Déploiement Ubuntu ==="
mkdir -p ~/lab-volumes/ubuntu
docker run -d \
  --name ubuntu \
  --hostname ubuntu \
  --restart always \
  -it \
  -p 2223:22 \
  -v ~/lab-volumes/ubuntu:/root \
  ubuntu:latest sleep infinity

echo "=== Déploiement terminé ==="
echo "Vérifiez vos conteneurs avec : docker ps"
