#!/bin/bash
set -e

DEFAULT_NAME="remnanode"
DEFAULT_PORT=2000
FILE="/etc/ufw/before.rules"
BACKUP="/etc/ufw/before.rules.bak_$(date +%s)"

echo "Обновление системы..."\r

apt update -y && apt upgrade -y && apt install curl wget ufw -y

echo "Проверка Docker..."

# Проверка Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker не найден. Устанавливаем..."
  curl -fsSL https://get.docker.com | sh
fi

mkdir -p /opt/$NODE_NAME && cd /opt/$NODE_NAME


read -p "Введите имя (remnanode) [по умолчанию ${DEFAULT_NAME}]: " NODE_NAME
NODE_NAME=${NODE_NAME:-$DEFAULT_NAME}

read -p "Введите порт (NODE_PORT) [по умолчанию ${DEFAULT_PORT}]: " NODE_PORT
NODE_PORT=${NODE_PORT:-$DEFAULT_PORT}

read -p "Настроить ufw + ICMP (port: OpenSSH, 443, ${NODE_PORT})? (y/n): " answer

start_ufw_icmp() {
  ufw --force enable && ufw allow OpenSSH && ufw allow 443/tcp && ufw allow $DEFAULT_PORT/tcp

  if [[ ! -f "$FILE" ]]; then
    echo "Файл $FILE не найден"
    exit 1
  fi

  cp "$FILE" "$BACKUP"
  echo "Создан backup: ${BACKUP}"
  echo "Замена ACCEPT → DROP для ICMP..."

  # INPUT
  sed -i '/ufw-before-input -p icmp/ s/-j ACCEPT/-j DROP/g' "$FILE"

  # FORWARD
  sed -i '/ufw-before-forward -p icmp/ s/-j ACCEPT/-j DROP/g' "$FILE"

  if ! grep -q "ufw-before-input -p icmp --icmp-type source-quench" "$FILE"; then
    sed -i '/ufw-before-input -p icmp --icmp-type echo-request/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$FILE"
  fi

  ufw --force disable && ufw --force enable
}

if [[ "$answer" =~ ^[Yy]$ ]]; then
  start_ufw_icmp
fi

read -p "Настроить sysctl? (y/n): " answer2

start_sysctl_update() {
  if [[ ! -f "/opt/sysctl.conf" ]]; then
    touch /opt/sysctl.conf
  fi
cat > /opt/sysctl.conf <<EOF
vm.overcommit_memory = 1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.icmp_echo_ignore_all=1
EOF
sysctl -p /opt/sysctl.conf
}

if [[ "$answer2" =~ ^[Yy]$ ]]; then
  start_sysctl_update
fi

read -p "Введите SECRET_KEY: " SECRET_KEY
if [[ -z "$SECRET_KEY" ]]; then
  echo "SECRET_KEY не может быть пустым"
  exit 1
fi

cat > docker-compose.yml <<EOF
services:
  remnanode:
    container_name: ${NODE_NAME}
    hostname: ${NODE_NAME}
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY="${SECRET_KEY}"
EOF

docker compose up -d && docker compose logs -f -t