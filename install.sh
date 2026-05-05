#!/bin/bash
set -euo pipefail

DEFAULT_NAME="remnanode"
DEFAULT_PORT=2000
FILE="/etc/ufw/before.rules"
BACKUP="/etc/ufw/before.rules.bak_$(date +%s)"

UPDATE=false
SETUP_UFW=false
SETUP_SYSCTL=false
NODE_NAME=""
NODE_PORT=""
SECRET_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      UPDATE=true
      shift
      ;;
    --name)
      NODE_NAME="$2"
      shift 2
      ;;
    --port)
      NODE_PORT="$2"
      shift 2
      ;;
    --key)
      SECRET_KEY="$2"
      shift 2
      ;;
    --ufw)
      SETUP_UFW=true
      shift
      ;;
    --sysctl)
      SETUP_SYSCTL=true
      shift
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      exit 1
      ;;
  esac
done

if [[ "$UPDATE" == false ]]; then
  read -p "Обновить систему? (y/n): " update
  if [[ "$update" =~ ^[Yy]$ ]]; then
    UPDATE=true
  fi
fi

if [[ "$UPDATE" == true ]]; then
  echo "Обновление системы..."
  apt update -y && apt upgrade -y && apt install curl wget ufw -y
fi

echo "Проверка Docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker не найден. Устанавливаем..."
  curl -fsSL https://get.docker.com | sh
fi

NODE_NAME=${NODE_NAME:-}
if [[ -z "$NODE_NAME" ]]; then
  read -p "Введите имя (remnanode) [по умолчанию ${DEFAULT_NAME}]: " NODE_NAME
  NODE_NAME=${NODE_NAME:-$DEFAULT_NAME}
fi

NODE_PORT=${NODE_PORT:-}
if [[ -z "$NODE_PORT" ]]; then
  read -p "Введите порт (NODE_PORT) [по умолчанию ${DEFAULT_PORT}]: " NODE_PORT
  NODE_PORT=${NODE_PORT:-$DEFAULT_PORT}
fi

mkdir -p /opt/$NODE_NAME && cd /opt/$NODE_NAME

if [[ "$SETUP_UFW" == false ]]; then
  read -p "Настроить ufw + ICMP (port: OpenSSH, 443, ${NODE_PORT})? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    SETUP_UFW=true
  fi
fi

start_ufw_icmp() {
  apt install ufw -y
  ufw --force enable
  ufw allow OpenSSH
  ufw allow 443/tcp
  ufw allow ${NODE_PORT}/tcp

  [[ -f "$FILE" ]] || { echo "Файл $FILE не найден"; exit 1; }

  cp "$FILE" "$BACKUP"

  sed -i '/ufw-before-input -p icmp/ s/-j ACCEPT/-j DROP/g' "$FILE"
  sed -i '/ufw-before-forward -p icmp/ s/-j ACCEPT/-j DROP/g' "$FILE"

  if ! grep -q "source-quench" "$FILE"; then
    sed -i '/echo-request/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$FILE"
  fi

  ufw --force reload
}

[[ "$SETUP_UFW" == true ]] && start_ufw_icmp

if [[ "$SETUP_SYSCTL" == false ]]; then
  read -p "Настроить sysctl? (y/n): " answer2
  if [[ "$answer2" =~ ^[Yy]$ ]]; then
    SETUP_SYSCTL=true
  fi
fi

start_sysctl_update() {
cat > /opt/sysctl.conf <<EOF
vm.overcommit_memory = 1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.icmp_echo_ignore_all=1
EOF
sysctl -p /opt/sysctl.conf
}

[[ "$SETUP_SYSCTL" == true ]] && start_sysctl_update

if [[ -z "$SECRET_KEY" ]]; then
  read -p "Введите SECRET_KEY: " SECRET_KEY
fi

[[ -z "$SECRET_KEY" ]] && { echo "SECRET_KEY не может быть пустым"; exit 1; }

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

docker compose up -d
docker compose logs -f -t