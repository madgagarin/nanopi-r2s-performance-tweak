#!/bin/sh

# NanoPi R2S Script (OpenWrt 25.12+ APK Version)
# Optimized for Kernel 6.12 (MGLRU, ECN, GRO Tuning)

set -e

echo "=================================================="
echo "    NanoPi R2S Configuration (Kernel 6.12)"
echo "=================================================="

# 1. INSTALL DEPENDENCIES
echo "[1/6] Updating package lists and installing dependencies (APK)..."
apk update
apk add ethtool haveged sqm-scripts luci-app-sqm bash

# ----------------------------------------------------------------
# 2. FIREWALL, NETWORK & STORAGE
# ----------------------------------------------------------------
echo "[2/6] Configuring Network, Storage & Services..."
uci set firewall.@defaults[0].flow_offloading='0'
uci set firewall.@defaults[0].flow_offloading_hw='0'
uci commit firewall
/etc/init.d/firewall reload

# Storage: Enable FSTAB and check_fs for /opt (mmcblk0p3)
if uci get fstab.@mount[0] >/dev/null 2>&1; then
    uci set fstab.@mount[0].check_fs='1'
    uci commit fstab
fi
/etc/init.d/fstab enable
/etc/init.d/fstab start

# Set TX Queue Length to 10000 permanently via UCI
uci set network.wan.txqueuelen='10000'
uci set network.lan.txqueuelen='10000'
uci commit network
/etc/init.d/network reload

# ----------------------------------------------------------------
# 3. KERNEL TUNING (TCP, MGLRU, Flow Steering)
# ----------------------------------------------------------------
echo "[3/6] Applying Kernel 6.12 Optimizations (BBR, ECN, MGLRU)..."

# Enable MGLRU full potential
[ -f /sys/kernel/mm/lru_gen/enabled ] && echo 7 > /sys/kernel/mm/lru_gen/enabled

cat << 'EOF' > /etc/sysctl.d/99-r2s-performance.conf
# Network Core Budget
net.core.netdev_budget=600
net.core.netdev_max_backlog=10000

# TCP Optimizations
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_ecn=1

# Kernel 6.12 Specific: GRO & VFS
net.core.gro_normal_batch=16
vm.vfs_cache_pressure=50

# RFS & Flow Steering
net.core.rps_sock_flow_entries=32768
EOF

sysctl -p /etc/sysctl.d/99-r2s-performance.conf

# ----------------------------------------------------------------
# 4. SYSTEM SERVICE (Init Script)
# ----------------------------------------------------------------
echo "[4/6] Installing System Service (IRQ, RPS, XPS, Governor, I/O)..."

# Optimize system logging (RAM only, 512KB limit)
uci set system.@system[0].log_size='512'
uci commit system
/etc/init.d/system restart

cat << 'EOF' > /etc/init.d/r2s_optimize
#!/bin/sh /etc/rc.common

START=99

apply_net_optim() {
    # 0. Global RFS (Receive Flow Steering)
    echo 32768 > /proc/sys/net/core/rps_sock_flow_entries

    # 1. IRQ Affinity (Hard Pinning)
    IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
    IRQ_USB=$(awk -F: '/xhci-hcd:usb1/ {print $1}' /proc/interrupts | sed 's/ //g')

    [ -n "$IRQ_ETH0" ] && echo 2 > /proc/irq/$IRQ_ETH0/smp_affinity
    [ -n "$IRQ_USB" ] && echo 4 > /proc/irq/$IRQ_USB/smp_affinity

    # 2. RPS & RFS
    if [ -e "/sys/class/net/eth0" ]; then
        echo d > /sys/class/net/eth0/queues/rx-0/rps_cpus
        echo 16384 > /sys/class/net/eth0/queues/rx-0/rps_flow_cnt
    fi
    if [ -e "/sys/class/net/eth1" ]; then
        echo b > /sys/class/net/eth1/queues/rx-0/rps_cpus
        echo 16384 > /sys/class/net/eth1/queues/rx-0/rps_flow_cnt
    fi

    # 3. XPS
    for q in /sys/class/net/eth*/queues/tx-*; do
        [ -e "$q/xps_cpus" ] && echo f > "$q/xps_cpus"
    done

    # 4. Hardware Tuning (ethtool)
    for dev in eth0 eth1; do
        if [ -e "/sys/class/net/$dev" ]; then
            ifconfig $dev txqueuelen 10000 2>/dev/null
            ethtool -G $dev rx 1024 tx 1024 2>/dev/null
            ethtool -C $dev rx-usecs 30 tx-usecs 30 2>/dev/null
        fi
    done
}

start() {
    # 0. I/O Optimization (Reduce SD Card wear)
    mount -o remount,noatime /
    
    # Enable MGLRU
    [ -f /sys/kernel/mm/lru_gen/enabled ] && echo 7 > /sys/kernel/mm/lru_gen/enabled

    # 1. CPU Governor
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo schedutil > $cpu
    done

    # 2. Apply Network Optimization in stages
    (
        for delay in 10 30 60; do
            sleep $delay
            apply_net_optim
        done
    ) &
}
EOF

chmod +x /etc/init.d/r2s_optimize
/etc/init.d/r2s_optimize enable
/etc/init.d/r2s_optimize start

# Add Hotplug script
mkdir -p /etc/hotplug.d/iface/
cat << 'EOF' > /etc/hotplug.d/iface/99-r2s-optimize
[ "$ACTION" = "ifup" ] || exit 0
/etc/init.d/r2s_optimize start
EOF

# ----------------------------------------------------------------
# 5. VERIFICATION SCRIPT GENERATION
# ----------------------------------------------------------------
echo "[5/6] Generating Verification Script..."

cat << 'EOF' > /root/check_full_optimization.sh
#!/bin/sh

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================================="
echo "      NanoPi R2S Check (6.12)"
echo "=================================================="

# 1. CPU & LOAD BALANCING
echo "[1] CPU & IRQ Management"
GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
printf "  %-25s " "CPU Governor:"
if [ "$GOV" = "schedutil" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 2. KERNEL 6.12 FEATURES
echo ""
echo "[2] Kernel 6.12 Special Features"
MGLRU=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null)
GRO=$(sysctl -n net.core.gro_normal_batch 2>/dev/null)

printf "  %-25s " "MGLRU State:"
if [ "$MGLRU" = "0x0007" ]; then printf "${GREEN}OK (Aggressive)${NC}\n"; else printf "${RED}FAIL ($MGLRU)${NC}\n"; fi
printf "  %-25s " "GRO Batching:"
if [ "$GRO" = "16" ]; then printf "${GREEN}OK (16)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 3. TCP & SYSTEM TUNING
echo ""
echo "[3] TCP & System Tuning"
CC=$(sysctl -n net.ipv4.tcp_congestion_control)
ECN=$(sysctl -n net.ipv4.tcp_ecn)
printf "  %-25s " "Algorithm (BBR):"
if [ "$CC" = "bbr" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "TCP ECN Synergie:"
if [ "$ECN" = "1" ]; then printf "${GREEN}OK (Enabled)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 4. SQM & FIREWALL
echo ""
echo "[4] SQM & Firewall"
SQM_LIMIT=$(uci get sqm.eth0.download 2>/dev/null)
printf "  %-25s " "SQM Limit (360M):"
if [ "$SQM_LIMIT" = "360000" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 5. PERSISTENCE
echo ""
echo "[5] Persistence & APK Backup"
if [ -f "/etc/backup/installed_packages.txt" ]; then printf "  %-25s ${GREEN}OK${NC}\n" "Package List Saved:"; else printf "  %-25s ${RED}FAIL${NC}\n" "Package List:"; fi

echo "=================================================="
EOF
chmod +x /root/check_full_optimization.sh

# ----------------------------------------------------------------
# 6. PERSISTENCE (Backup & Recovery - APK Version)
# ----------------------------------------------------------------
echo "[6/6] Configuring Backup Persistence (APK)..."

# 1. Create package backup script
cat << 'EOF' > /usr/bin/save-package-list
#!/bin/sh
mkdir -p /etc/backup
TARGET_FILE='/etc/backup/installed_packages.txt'
apk info | sort > "$TARGET_FILE"
logger -t backup_packages 'Package list updated (APK).'
EOF
chmod +x /usr/bin/save-package-list

# 2. Create package restore script
cat << 'EOF' > /usr/bin/restore-packages
#!/bin/sh
LIST='/etc/backup/installed_packages.txt'
[ ! -f "$LIST" ] && exit 0
logger -t restore_packages 'Starting automatic package restoration (APK)...'
apk update
cat "$LIST" | xargs apk add
logger -t restore_packages 'Package restoration complete.'
EOF
chmod +x /usr/bin/restore-packages

# 3. Create uci-defaults script
cat << 'EOF' > /etc/uci-defaults/99-r2s-optimize
#!/bin/sh
[ -x /usr/bin/restore-packages ] && /usr/bin/restore-packages
/etc/init.d/r2s_optimize enable
/etc/init.d/r2s_optimize start
exit 0
EOF
chmod +x /etc/uci-defaults/99-r2s-optimize

# 4. Add to sysupgrade.conf
for FILE in /etc/init.d/r2s_optimize /etc/hotplug.d/iface/99-r2s-optimize /etc/uci-defaults/99-r2s-optimize /etc/backup/installed_packages.txt /usr/bin/save-package-list /usr/bin/restore-packages; do
    if ! grep -q "$FILE" /etc/sysupgrade.conf; then
        echo "$FILE" >> /etc/sysupgrade.conf
    fi
done

# 5. Initial save of package list
/usr/bin/save-package-list

echo "Optimization Complete (OpenWrt 25.12 Kernel 6.12 APK)!"
