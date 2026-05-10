#!/bin/bash
set -euo pipefail

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

docker compose down --rmi all && docker compose up -d

TARGET="/etc/ufw/before.rules"
BACKUP="/etc/ufw/before.rules.backup"

# Ищем первый файл before.rules.bak_*
SOURCE=$(find /etc/ufw -maxdepth 1 -type f -name "before.rules.bak_*" | head -n 1)

# Проверяем найден ли файл
if [[ -z "$SOURCE" ]]; then
    echo "Ошибка: файл before.rules.bak_* не найден"
    exit 1
fi

# Делаем backup текущего before.rules
cp "$TARGET" "$BACKUP"

# Копируем содержимое backup файла обратно в before.rules
cp "$SOURCE" "$TARGET"

ufw --force disable && ufw --force enable