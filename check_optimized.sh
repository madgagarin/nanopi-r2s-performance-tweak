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
printf "  %-20s " "CPU Governor:"
if [ "$GOV" = "schedutil" ]; then printf "${GREEN}OK ($GOV)${NC}\n"; else printf "${RED}FAIL ($GOV)${NC}\n"; fi

# IRQ Affinity
IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
IRQ_USB=$(awk -F: '/xhci-hcd:usb1/ {print $1}' /proc/interrupts | sed 's/ //g')
AFF_ETH0=$(cat /proc/irq/$IRQ_ETH0/smp_affinity 2>/dev/null)
AFF_USB=$(cat /proc/irq/$IRQ_USB/smp_affinity 2>/dev/null)

printf "  %-20s " "IRQ eth0 (WAN):"
if [ "$AFF_ETH0" = "2" ]; then printf "${GREEN}OK (CPU1)${NC}\n"; else printf "${RED}FAIL ($AFF_ETH0)${NC}\n"; fi
printf "  %-20s " "IRQ eth1 (USB):"
if [ "$AFF_USB" = "4" ]; then printf "${GREEN}OK (CPU2)${NC}\n"; else printf "${RED}FAIL ($AFF_USB)${NC}\n"; fi

# RPS (Receive Packet Steering)
RPS_ETH0=$(cat /sys/class/net/eth0/queues/rx-0/rps_cpus)
RPS_ETH1=$(cat /sys/class/net/eth1/queues/rx-0/rps_cpus)

printf "  %-20s " "RPS eth0 (WAN):"
if [ "$RPS_ETH0" = "3" ]; then printf "${GREEN}OK (CPU0+1)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH0)${NC}\n"; fi
printf "  %-20s " "RPS eth1 (LAN):"
if [ "$RPS_ETH1" = "c" ]; then printf "${GREEN}OK (CPU2+3)${NC}\n"; else printf "${RED}FAIL ($RPS_ETH1)${NC}\n"; fi

# XPS (Transmit Packet Steering)
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

printf "  %-20s " "Algorithm (BBR):"
if [ "$CC" = "bbr" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-20s " "Sys Default (FQ):"
if [ "$QDISC" = "fq" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
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

# 5. PERSISTENCE
echo ""
echo "[5] Persistence & Backup"
UCI_DEF="/etc/uci-defaults/99-r2s-optimize"
SYS_UPG="/etc/sysupgrade.conf"

printf "  %-20s " "Auto-Start Script:"
if [ -f "$UCI_DEF" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL (Missing $UCI_DEF)${NC}\n"; fi

printf "  %-20s " "Backup (Service):"
if grep -q "init.d/r2s_optimize" "$SYS_UPG"; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

printf "  %-20s " "Backup (Auto-Start):"
if grep -q "uci-defaults/99-r2s-optimize" "$SYS_UPG"; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

echo "=================================================="