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

PACKAGES="kmod-tcp-bbr kmod-sched kmod-sched-cake luci-app-sqm sqm-scripts"

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

# 3. Flow Steering Global
net.core.rps_sock_flow_entries = 32768
EOF

sysctl -p > /dev/null

# ----------------------------------------------------------------
# 2. FIREWALL (Disable Offloading)
# ----------------------------------------------------------------
echo "[2/6] Disabling Offloading to fix SQM..."
uci set firewall.@defaults[0].flow_offloading='0'
uci set firewall.@defaults[0].flow_offloading_hw='0'
uci commit firewall
/etc/init.d/firewall reload

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
uci set sqm.eth0.download='0'
uci set sqm.eth0.upload='480000'
uci set sqm.eth0.enabled='1'
uci commit sqm
/etc/init.d/sqm enable
/etc/init.d/sqm restart

# ----------------------------------------------------------------
# 4. SYSTEM SERVICE (Init Script)
# ----------------------------------------------------------------
echo "[4/6] Installing System Service (IRQ, RPS, XPS, Governor)..."

cat << 'EOF' > /etc/init.d/r2s_optimize
#!/bin/sh /etc/rc.common

START=99

start() {
    # Wait for interfaces to be fully up
    sleep 15

    # 1. IRQ Affinity (Hard Pinning)
    IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
    IRQ_USB=$(awk -F: '/xhci-hcd:usb1/ {print $1}' /proc/interrupts | sed 's/ //g')

    [ -n "$IRQ_ETH0" ] && echo 2 > /proc/irq/$IRQ_ETH0/smp_affinity
    [ -n "$IRQ_USB" ] && echo 4 > /proc/irq/$IRQ_USB/smp_affinity

    # 2. CPU Governor (Schedutil)
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo schedutil > $cpu
    done

    # 3. RPS (Receive Packet Steering)
    echo 3 > /sys/class/net/eth0/queues/rx-0/rps_cpus
    echo c > /sys/class/net/eth1/queues/rx-0/rps_cpus

    # 4. XPS (Transmit Packet Steering)
    echo 3 > /sys/class/net/eth0/queues/tx-0/xps_cpus

    # 5. RFS (Receive Flow Steering)
    echo 2048 > /sys/class/net/eth0/queues/rx-0/rps_flow_cnt
    echo 2048 > /sys/class/net/eth1/queues/rx-0/rps_flow_cnt
}
EOF

chmod +x /etc/init.d/r2s_optimize
/etc/init.d/r2s_optimize enable
/etc/init.d/r2s_optimize start

# ----------------------------------------------------------------
# 5. VERIFICATION SCRIPT GENERATION
# ----------------------------------------------------------------
echo "[5/6] Generating Verification Script..."

cat << 'EOF' > /root/check_full_optimization.sh
#!/bin/sh

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=================================================="
echo "      NanoPi R2S Full Optimization Check"
echo "=================================================="

# 1. CPU & LOAD BALANCING
echo "[1] CPU Load Balucing (IRQ/RPS/XPS)"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
printf "  %-20s " "CPU Governor:"
if [ "$GOV" = "schedutil" ]; then printf "${GREEN}OK ($GOV)${NC}\n"; else printf "${RED}FAIL ($GOV)${NC}\n"; fi

IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
IRQ_USB=$(awk -F: '/xhci-hcd:usb1/ {print $1}' /proc/interrupts | sed 's/ //g')
AFF_ETH0=$(cat /proc/irq/$IRQ_ETH0/smp_affinity 2>/dev/null)
AFF_USB=$(cat /proc/irq/$IRQ_USB/smp_affinity 2>/dev/null)

printf "  %-20s " "IRQ eth0 (WAN):"
if [ "$AFF_ETH0" = "2" ]; then printf "${GREEN}OK (CPU1)${NC}\n"; else printf "${RED}FAIL ($AFF_ETH0)${NC}\n"; fi
printf "  %-20s " "IRQ eth1 (USB):"
if [ "$AFF_USB" = "4" ]; then printf "${GREEN}OK (CPU2)${NC}\n"; else printf "${RED}FAIL ($AFF_USB)${NC}\n"; fi

RPS_ETH0=$(cat /sys/class/net/eth0/queues/rx-0/rps_cpus)
RPS_ETH1=$(cat /sys/class/net/eth1/queues/rx-0/rps_cpus)
printf "  %-20s " "RPS eth0 (WAN):"
if [ "$RPS_ETH0" = "3" ]; then printf "${GREEN}OK (CPU0+1)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH0)${NC}\n"; fi
printf "  %-20s " "RPS eth1 (LAN):"
if [ "$RPS_ETH1" = "c" ]; then printf "${GREEN}OK (CPU2+3)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH1)${NC}\n"; fi

XPS_ETH0=$(cat /sys/class/net/eth0/queues/tx-0/xps_cpus 2>/dev/null)
printf "  %-20s " "XPS eth0 (WAN):"
if [ "$XPS_ETH0" = "3" ]; then printf "${GREEN}OK (CPU0+1)${NC}\n"; else printf "${RED}FAIL ($XPS_ETH0)${NC}\n"; fi

# 2. FLOW STEERING (RFS)
echo ""
echo "[2] Flow Steering (RFS)"
RFS_ENTRIES=$(cat /proc/sys/net/core/rps_sock_flow_entries)
RFS_CNT=$(cat /sys/class/net/eth0/queues/rx-0/rps_flow_cnt)

printf "  %-20s " "Global Entries:"
if [ "$RFS_ENTRIES" = "32768" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-20s " "Queue Flow Count:"
if [ "$RFS_CNT" = "2048" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 3. TCP & CONGESTION
echo ""
echo "[3] TCP & Congestion Control"
CC=$(sysctl -n net.ipv4.tcp_congestion_control)
QDISC=$(sysctl -n net.core.default_qdisc)
RMEM=$(sysctl -n net.core.rmem_max)

printf "  %-20s " "Algorithm:"
if [ "$CC" = "bbr" ]; then printf "${GREEN}OK (BBR)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-20s " "Sys Default (BBR):"
if [ "$QDISC" = "fq" ]; then printf "${GREEN}OK (FQ)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-20s " "TCP Buffer (Max):"
if [ "$RMEM" = "16777216" ]; then printf "${GREEN}OK (16MB)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 4. SQM & FIREWALL
echo ""
echo "[4] SQM & Firewall"
SQM_STATE=$(uci get sqm.eth0.enabled 2>/dev/null)
FW_OFFLOAD=$(uci get firewall.@defaults[0].flow_offloading 2>/dev/null)
CAKE_ACTIVE=$(tc qdisc show dev eth0 | grep cake)

printf "  %-20s " "SQM Enabled:"
if [ "$SQM_STATE" = "1" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-20s " "Flow Offloading:"
if [ "$FW_OFFLOAD" = "0" ]; then printf "${GREEN}OK (Disabled)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-20s " "WAN Qdisc (SQM):"
if echo "$CAKE_ACTIVE" | grep -q "cake"; then printf "${GREEN}OK (CAKE Active)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

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
if ! grep -q "/etc/init.d/r2s_optimize" /etc/sysupgrade.conf; then
    echo "/etc/init.d/r2s_optimize" >> /etc/sysupgrade.conf
fi

if ! grep -q "/etc/uci-defaults/99-r2s-optimize" /etc/sysupgrade.conf; then
    echo "/etc/uci-defaults/99-r2s-optimize" >> /etc/sysupgrade.conf
fi

echo "Optimization Complete!"