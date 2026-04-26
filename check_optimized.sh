#!/bin/sh

# NanoPi R2S Optimization Check Script
# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=================================================="
echo "      NanoPi R2S Full Optimization Check"
echo "=================================================="

# 1. CPU & LOAD BALANCING
echo "[1] CPU Load Balancing (IRQ/RPS/XPS)"

# CPU Governor
GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
printf "  %-25s " "CPU Governor:"
if [ "$GOV" = "schedutil" ]; then printf "${GREEN}OK ($GOV)${NC}\n"; else printf "${RED}FAIL ($GOV)${NC}\n"; fi

# IRQ Affinity
IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
IRQ_USB=$(awk -F: '/xhci-hcd:usb1/ {print $1}' /proc/interrupts | sed 's/ //g')
AFF_ETH0=$(cat /proc/irq/$IRQ_ETH0/smp_affinity 2>/dev/null)
AFF_USB=$(cat /proc/irq/$IRQ_USB/smp_affinity 2>/dev/null)

printf "  %-25s " "IRQ eth0 (WAN):"
if [ "$AFF_ETH0" = "2" ]; then printf "${GREEN}OK (CPU1)${NC}\n"; else printf "${RED}FAIL ($AFF_ETH0)${NC}\n"; fi
printf "  %-25s " "IRQ eth1 (USB):"
if [ "$AFF_USB" = "4" ]; then printf "${GREEN}OK (CPU2)${NC}\n"; else printf "${RED}FAIL ($AFF_USB)${NC}\n"; fi

# RPS & XPS (All Cores)
RPS_ETH0=$(cat /sys/class/net/eth0/queues/rx-0/rps_cpus)
RPS_ETH1=$(cat /sys/class/net/eth1/queues/rx-0/rps_cpus)
XPS_ETH0=$(cat /sys/class/net/eth0/queues/tx-0/xps_cpus 2>/dev/null)

printf "  %-25s " "RPS eth0 (WAN):"
if [ "$RPS_ETH0" = "d" ]; then printf "${GREEN}OK (Optimized)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH0)${NC}\n"; fi
printf "  %-25s " "RPS eth1 (LAN):"
if [ "$RPS_ETH1" = "b" ]; then printf "${GREEN}OK (Optimized)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH1)${NC}\n"; fi
printf "  %-25s " "XPS eth0 (WAN):"
if [ "$XPS_ETH0" = "f" ]; then printf "${GREEN}OK (All Cores)${NC}\n"; else printf "${RED}FAIL ($XPS_ETH0)${NC}\n"; fi

# 2. FLOW STEERING & QUEUES
echo ""
echo "[2] Flow Steering & Queues"
RFS_ENTRIES=$(cat /proc/sys/net/core/rps_sock_flow_entries)
RFS_CNT=$(cat /sys/class/net/eth0/queues/rx-0/rps_flow_cnt)
TXQ_ETH0=$(cat /sys/class/net/eth0/tx_queue_len)

printf "  %-25s " "Global RFS Entries:"
if [ "$RFS_ENTRIES" = "32768" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL ($RFS_ENTRIES)${NC}\n"; fi
printf "  %-25s " "Queue Flow Count:"
if [ "$RFS_CNT" = "16384" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL ($RFS_CNT)${NC}\n"; fi
printf "  %-25s " "TX Queue Length:"
if [ "$TXQ_ETH0" = "10000" ]; then printf "${GREEN}OK (10000)${NC}\n"; else printf "${RED}FAIL ($TXQ_ETH0)${NC}\n"; fi

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
