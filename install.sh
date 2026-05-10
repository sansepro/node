#!/bin/bash
set -euo pipefail

DEFAULT_NAME="remnanode"
DEFAULT_PORT=2000
FILE="/etc/ufw/before.rules"
BACKUP="/etc/ufw/before.rules.bak_$(date +%s)"

UPDATE="ask"
SETUP_UFW="ask"
SETUP_SYSCTL="ask"
NODE_NAME=""
NODE_PORT=""
SECRET_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      UPDATE=true
      shift
      ;;
    --no-update)
      UPDATE=false
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
    --no-ufw)
      SETUP_UFW=false
      shift
      ;;
    --sysctl)
      SETUP_SYSCTL=true
      shift
      ;;
    --no-sysctl)
      SETUP_SYSCTL=false
      shift
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      exit 1
      ;;
  esac
done

if [[ "$UPDATE" == "ask" ]]; then
  read -p "Обновить систему? (y/n): " update
  if [[ "$update" =~ ^[Yy]$ ]]; then
    UPDATE=true
  else
    UPDATE=false
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

if [[ -z "$NODE_NAME" ]]; then
  read -p "Введите имя (remnanode) [по умолчанию ${DEFAULT_NAME}]: " NODE_NAME
  NODE_NAME=${NODE_NAME:-$DEFAULT_NAME}
fi

if [[ -z "$NODE_PORT" ]]; then
  read -p "Введите порт (NODE_PORT) [по умолчанию ${DEFAULT_PORT}]: " NODE_PORT
  NODE_PORT=${NODE_PORT:-$DEFAULT_PORT}
fi

mkdir -p /opt/$NODE_NAME && mkdir -p /opt/$NODE_NAME/logs && cd /opt/$NODE_NAME

if [[ "$SETUP_UFW" == "ask" ]]; then
  read -p "Настроить ufw + ICMP (port: OpenSSH, 443, ${NODE_PORT})? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    SETUP_UFW=true
  else
    SETUP_UFW=false
  fi
fi

start_ufw_icmp() {
  ufw --force enable && ufw allow OpenSSH && ufw allow 443/tcp && ufw allow $DEFAULT_PORT/tcp

  if [[ ! -f "$FILE" ]]; then
    echo "Файл $FILE не найден"
    exit 1
  fi

  cp "$FILE" "$BACKUP"
  echo "Создан backup: ${BACKUP}"
  echo "Замена ACCEPT → DROP для ICMP..."

  sed -i '/ufw-before-input -p icmp/ s/-j ACCEPT/-j DROP/g' "$FILE"
  sed -i '/ufw-before-forward -p icmp/ s/-j ACCEPT/-j DROP/g' "$FILE"
  
  if ! grep -q "ufw-before-input -p icmp --icmp-type source-quench" "$FILE"; then
    sed -i '/ufw-before-input -p icmp --icmp-type echo-request/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$FILE"
  fi

  ufw --force disable && ufw --force enable
}

[[ "$SETUP_UFW" == true ]] && start_ufw_icmp

if [[ "$SETUP_SYSCTL" == "ask" ]]; then
  read -p "Настроить sysctl? (y/n): " answer2
  if [[ "$answer2" =~ ^[Yy]$ ]]; then
    SETUP_SYSCTL=true
  else
    SETUP_SYSCTL=false
  fi
fi

start_sysctl_update() {
cat > /opt/sysctl.conf <<EOF
vm.overcommit_memory = 1

kernel.apparmor_restrict_unprivileged_userns = 1

kernel.printk = 4 4 1 7
kernel.kptr_restrict = 1
kernel.sysrq = 176
kernel.yama.ptrace_scope = 1
kernel.pid_max = 4194304

vm.max_map_count = 1048576
vm.mmap_min_addr = 65536

fs.protected_fifos = 1
fs.protected_hardlinks = 1
fs.protected_regular = 2
fs.protected_symlinks = 1

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.default.use_tempaddr = 0



net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864

net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

net.ipv4.tcp_fin_timeout = 15

net.ipv4.tcp_tw_reuse = 1

net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

net.ipv4.tcp_syncookies = 1

net.core.netdev_max_backlog = 250000

net.ipv4.tcp_max_orphans = 262144

net.netfilter.nf_conntrack_max = 262144

net.ipv4.ip_local_port_range = 1024 65535

net.ipv4.tcp_mtu_probing = 1

net.ipv4.tcp_slow_start_after_idle = 0
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
    volumes:
    - './logs:/var/log/remnanode'
EOF

docker compose up -d && docker compose logs -f -t