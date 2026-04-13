#!/bin/sh

# NanoPi R2S "Ultimate" Performance Tweak
# Major Update: BBR, CAKE SQM, XPS, RFS, Schedutil, Buffer Tuning, Auto-Install, Persistence

echo "Starting NanoPi R2S Ultimate Optimization..."

# ----------------------------------------------------------------
# 0. INSTALL PREREQUISITES
# ----------------------------------------------------------------
echo "[0/6] Checking and installing required packages..."
echo "Updating package lists..."
opkg update

PACKAGES="kmod-tcp-bbr kmod-sched kmod-sched-cake luci-app-sqm sqm-scripts haveged"

for PKG in $PACKAGES; do
    if opkg list-installed | grep -q "^$PKG"; then
        echo "  - $PKG is already installed."
    else
        echo "  - Installing $PKG..."
        opkg install "$PKG"
        if [ $? -ne 0 ]; then
            echo "Error installing $PKG. Please check your internet connection or repositories."
        fi
    fi
done

# ----------------------------------------------------------------
# 1. NETWORK KERNEL SETTINGS (sysctl)
# ----------------------------------------------------------------
echo "[1/6] Configuring Kernel Network Parameters (BBR, FQ, Buffers)..."

# Use temp file to avoid duplicates
grep -v "net.core.default_qdisc" /etc/sysctl.conf > /tmp/sysctl.conf.tmp
grep -v "net.ipv4.tcp_congestion_control" /tmp/sysctl.conf.tmp > /tmp/sysctl.conf.tmp2
grep -v "net.core.rmem_max" /tmp/sysctl.conf.tmp2 > /tmp/sysctl.conf.tmp
grep -v "net.core.wmem_max" /tmp/sysctl.conf.tmp > /tmp/sysctl.conf.tmp2
grep -v "net.ipv4.tcp_rmem" /tmp/sysctl.conf.tmp2 > /tmp/sysctl.conf.tmp
grep -v "net.ipv4.tcp_wmem" /tmp/sysctl.conf.tmp > /tmp/sysctl.conf.tmp2
grep -v "net.core.netdev_max_backlog" /tmp/sysctl.conf.tmp2 > /tmp/sysctl.conf.tmp
grep -v "net.core.rps_sock_flow_entries" /tmp/sysctl.conf.tmp > /tmp/sysctl.conf.tmp2

mv /tmp/sysctl.conf.tmp2 /etc/sysctl.conf

cat << 'EOF' >> /etc/sysctl.conf

# --- NanoPi R2S Optimized Settings ---
# 1. Congestion Control & Queuing (BBR + FQ)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 2. Network Buffers (16MB for high speed)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 16384 16777216
net.core.netdev_max_backlog = 5000

# 3. Connection & Memory Optimization
net.ipv4.tcp_fastopen = 3
vm.min_free_kbytes = 16384

# 4. Flow Steering Global
net.core.rps_sock_flow_entries = 32768
EOF

sysctl -p > /dev/null

# ----------------------------------------------------------------
# 2. FIREWALL & NETWORK (Disable Offloading, Set Queues)
# ----------------------------------------------------------------
echo "[2/6] Configuring Network & Firewall..."
uci set firewall.@defaults[0].flow_offloading='0'
uci set firewall.@defaults[0].flow_offloading_hw='0'
uci commit firewall
/etc/init.d/firewall reload

# Set TX Queue Length to 5000 permanently via UCI
uci set network.wan.txqueuelen='5000'
uci set network.lan.txqueuelen='5000'
uci commit network
/etc/init.d/network reload

# ----------------------------------------------------------------
# 3. SQM QoS (CAKE)
# ----------------------------------------------------------------
echo "[3/6] Configuring SQM (CAKE)..."
uci set sqm.eth0=queue
uci set sqm.eth0.interface='eth0'
uci set sqm.eth0.qdisc='cake'
uci set sqm.eth0.script='piece_of_cake.qos'
uci set sqm.eth0.linklayer='none'
# Defaulting to Download=0 (Auto/Unlimited), Upload=480Mbps
# If your ISP speed is unstable, set these to 85-90% of your MINIMUM speed.
uci set sqm.eth0.download='0'
uci set sqm.eth0.upload='480000'

# Advanced Tuning for Unstable/Floating ISP Speed:
uci set sqm.eth0.qdisc_advanced='1'
uci set sqm.eth0.squash_dscp='1'
uci set sqm.eth0.squash_ingress='1'
uci set sqm.eth0.ingress_update='1'
uci set sqm.eth0.extra_params='ack-filter'

# PRESETS FOR OVERHEAD (Select your ISP type):
# 18: Pure Ethernet (Default)
# 26: PPPoE
# 44: VDSL / Older Cable
uci set sqm.eth0.overhead='18'

uci set sqm.eth0.enabled='1'
uci commit sqm
/etc/init.d/sqm enable
/etc/init.d/sqm restart

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
    # 1. IRQ Affinity (Hard Pinning)
    # R2S RK3328: eth0 (internal) to CPU1, eth1 (USB) to CPU2
    IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
    IRQ_USB=$(awk -F: '/xhci-hcd:usb1/ {print $1}' /proc/interrupts | sed 's/ //g')

    [ -n "$IRQ_ETH0" ] && echo 2 > /proc/irq/$IRQ_ETH0/smp_affinity
    [ -n "$IRQ_USB" ] && echo 4 > /proc/irq/$IRQ_USB/smp_affinity

    # 2. RPS (Receive Packet Steering) & RFS (Receive Flow Steering)
    # Distribute traffic across all 4 cores (f)
    for q in /sys/class/net/eth*/queues/rx-*; do
        [ -e "$q/rps_cpus" ] && echo f > "$q/rps_cpus"
        [ -e "$q/rps_flow_cnt" ] && echo 4096 > "$q/rps_flow_cnt"
    done

    # 3. XPS (Transmit Packet Steering)
    for q in /sys/class/net/eth*/queues/tx-*; do
        [ -e "$q/xps_cpus" ] && echo f > "$q/xps_cpus"
    done

    # 4. TX Queue Length
    for dev in eth0 eth1; do
        ifconfig $dev txqueuelen 5000 2>/dev/null
    done
}

start() {
    # 0. I/O Optimization (Reduce SD Card wear)
    mount -o remount,noatime /

    # 1. CPU Governor
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo schedutil > $cpu
    done

    # Wait for interfaces and apply initial optimization
    (
        sleep 10
        apply_net_optim
        sleep 20
        apply_net_optim
    ) &
}
EOF

chmod +x /etc/init.d/r2s_optimize
/etc/init.d/r2s_optimize enable
/etc/init.d/r2s_optimize start

# Add Hotplug script for interface up events (fixes settings resetting)
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

# NanoPi R2S Optimization Check Script (Generated)
# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=================================================="
echo "      NanoPi R2S Full Optimization Check"
echo "=================================================="

# 1. CPU & LOAD BALANCING
echo "[1] CPU Load Balancing (IRQ/RPS/XPS)"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
printf "  %-25s " "CPU Governor:"
if [ "$GOV" = "schedutil" ]; then printf "${GREEN}OK ($GOV)${NC}\n"; else printf "${RED}FAIL ($GOV)${NC}\n"; fi

IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
IRQ_USB=$(awk -F: '/xhci-hcd:usb1/ {print $1}' /proc/interrupts | sed 's/ //g')
AFF_ETH0=$(cat /proc/irq/$IRQ_ETH0/smp_affinity 2>/dev/null)
AFF_USB=$(cat /proc/irq/$IRQ_USB/smp_affinity 2>/dev/null)

printf "  %-25s " "IRQ eth0 (WAN):"
if [ "$AFF_ETH0" = "2" ]; then printf "${GREEN}OK (CPU1)${NC}\n"; else printf "${RED}FAIL ($AFF_ETH0)${NC}\n"; fi
printf "  %-25s " "IRQ eth1 (USB):"
if [ "$AFF_USB" = "4" ]; then printf "${GREEN}OK (CPU2)${NC}\n"; else printf "${RED}FAIL ($AFF_USB)${NC}\n"; fi

RPS_ETH0=$(cat /sys/class/net/eth0/queues/rx-0/rps_cpus)
RPS_ETH1=$(cat /sys/class/net/eth1/queues/rx-0/rps_cpus)
XPS_ETH0=$(cat /sys/class/net/eth0/queues/tx-0/xps_cpus 2>/dev/null)

printf "  %-25s " "RPS eth0 (WAN):"
if [ "$RPS_ETH0" = "f" ]; then printf "${GREEN}OK (All Cores)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH0)${NC}\n"; fi
printf "  %-25s " "RPS eth1 (LAN):"
if [ "$RPS_ETH1" = "f" ]; then printf "${GREEN}OK (All Cores)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH1)${NC}\n"; fi
printf "  %-25s " "XPS eth0 (WAN):"
if [ "$XPS_ETH0" = "f" ]; then printf "${GREEN}OK (All Cores)${NC}\n"; else printf "${RED}FAIL ($XPS_ETH0)${NC}\n"; fi

# 2. FLOW STEERING & QUEUES
echo ""
echo "[2] Flow Steering & Queues"
RFS_ENTRIES=$(cat /proc/sys/net/core/rps_sock_flow_entries)
RFS_CNT=$(cat /sys/class/net/eth0/queues/rx-0/rps_flow_cnt)
TXQ_ETH0=$(cat /sys/class/net/eth0/tx_queue_len)

printf "  %-25s " "Global RFS Entries:"
if [ "$RFS_ENTRIES" = "32768" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "Queue Flow Count:"
if [ "$RFS_CNT" = "4096" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "TX Queue Length:"
if [ "$TXQ_ETH0" = "5000" ]; then printf "${GREEN}OK (5000)${NC}\n"; else printf "${RED}FAIL ($TXQ_ETH0)${NC}\n"; fi

# 3. TCP & SYSTEM TUNING
echo ""
echo "[3] TCP & System Tuning"
CC=$(sysctl -n net.ipv4.tcp_congestion_control)
TFO=$(sysctl -n net.ipv4.tcp_fastopen)
MFREE=$(sysctl -n vm.min_free_kbytes)
HAVEGED=$(/etc/init.d/haveged status 2>/dev/null)

printf "  %-25s " "Algorithm (BBR):"
if [ "$CC" = "bbr" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "TCP Fast Open:"
if [ "$TFO" = "3" ]; then printf "${GREEN}OK (Enabled)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "Min Free Kbytes:"
if [ "$MFREE" = "16384" ]; then printf "${GREEN}OK (16MB)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "Entropy (haveged):"
if echo "$HAVEGED" | grep -q "running"; then printf "${GREEN}OK (Running)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 4. SQM & FIREWALL
echo ""
echo "[4] SQM & Firewall"
SQM_STATE=$(uci get sqm.eth0.enabled 2>/dev/null)
SQM_OVERHEAD=$(uci get sqm.eth0.overhead 2>/dev/null)
FW_OFFLOAD=$(uci get firewall.@defaults[0].flow_offloading 2>/dev/null)
CAKE_ACTIVE=$(tc qdisc show dev eth0 | grep cake)

printf "  %-25s " "SQM Enabled:"
if [ "$SQM_STATE" = "1" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "SQM Overhead:"
if [ "$SQM_OVERHEAD" = "18" ]; then printf "${GREEN}OK (Ethernet)${NC}\n"; else printf "${RED}INFO ($SQM_OVERHEAD)${NC}\n"; fi

SQM_AUTORATE=$(uci get sqm.eth0.ingress_update 2>/dev/null)
printf "  %-25s " "SQM Autorate (Ingress):"
if [ "$SQM_AUTORATE" = "1" ]; then printf "${GREEN}OK (Active)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

SQM_ACK=$(uci get sqm.eth0.extra_params 2>/dev/null)
printf "  %-25s " "SQM Ack-Filter:"
if echo "$SQM_ACK" | grep -q "ack-filter"; then printf "${GREEN}OK (Active)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

printf "  %-25s " "Flow Offloading:"
if [ "$FW_OFFLOAD" = "0" ]; then printf "${GREEN}OK (Disabled)${NC}\n"; else printf "${RED}FAIL (Conflict!)${NC}\n"; fi
printf "  %-25s " "WAN Qdisc (SQM):"
if echo "$CAKE_ACTIVE" | grep -q "cake"; then printf "${GREEN}OK (CAKE Active)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 5. PERSISTENCE
echo ""
echo "[5] Persistence & Backup"
INIT_D="/etc/rc.d/*r2s_optimize"
SYS_UPG="/etc/sysupgrade.conf"
HOTPLUG="/etc/hotplug.d/iface/99-r2s-optimize"

printf "  %-25s " "Auto-Start Script:"
if ls $INIT_D >/dev/null 2>&1; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "Hotplug Persistence:"
if [ -f "$HOTPLUG" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "Backup (Service):"
if grep -q "init.d/r2s_optimize" "$SYS_UPG"; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 6. SD CARD & LOGS
echo ""
echo "[6] SD Card & Logs Optimization"
LOG_SIZE=$(uci get system.@system[0].log_size 2>/dev/null)
NO_ATIME=$(mount | grep " / " | grep "noatime")

printf "  %-25s " "System Log Limit:"
if [ "$LOG_SIZE" = "512" ]; then printf "${GREEN}OK (512K)${NC}\n"; else printf "${RED}FAIL ($LOG_SIZE)${NC}\n"; fi
printf "  %-25s " "SD Wear (noatime):"
if [ -n "$NO_ATIME" ]; then printf "${GREEN}OK (Active)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

echo "=================================================="
EOF
chmod +x /root/check_full_optimization.sh

# ----------------------------------------------------------------
# 6. PERSISTENCE (Backup)
# ----------------------------------------------------------------
echo "[6/6] Configuring Backup Persistence..."

# 1. Create uci-defaults script for auto-enable after upgrade
cat << 'EOF' > /etc/uci-defaults/99-r2s-optimize
/etc/init.d/r2s_optimize enable
/etc/init.d/r2s_optimize start
exit 0
EOF
chmod +x /etc/uci-defaults/99-r2s-optimize

# 2. Add files to sysupgrade.conf
for FILE in /etc/init.d/r2s_optimize /etc/hotplug.d/iface/99-r2s-optimize /etc/uci-defaults/99-r2s-optimize; do
    if ! grep -q "$FILE" /etc/sysupgrade.conf; then
        echo "$FILE" >> /etc/sysupgrade.conf
    fi
done

echo "Optimization Complete!"