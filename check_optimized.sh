#!/bin/sh

# NanoPi R2S Optimization Check Script (Kernel 6.12 APK Version)
# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================================="
echo "      NanoPi R2S Optimization Check (Kernel 6.12)"
echo "=================================================="

# 1. CPU & LOAD BALANCING
echo "[1] CPU & IRQ Management"
GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
printf "  %-25s " "CPU Governor:"
if [ "$GOV" = "schedutil" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

IRQ_ETH0=$(awk -F: '/eth0/ {print $1}' /proc/interrupts | sed 's/ //g')
AFF_ETH0=$(cat /proc/irq/$IRQ_ETH0/smp_affinity 2>/dev/null)
printf "  %-25s " "IRQ eth0 (WAN):"
if [ "$AFF_ETH0" = "2" ]; then printf "${GREEN}OK (CPU1)${NC}\n"; else printf "${RED}FAIL ($AFF_ETH0)${NC}\n"; fi

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
TFO=$(sysctl -n net.ipv4.tcp_fastopen)

printf "  %-25s " "Algorithm (BBR):"
if [ "$CC" = "bbr" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "TCP ECN Synergie:"
if [ "$ECN" = "1" ]; then printf "${GREEN}OK (Enabled)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi
printf "  %-25s " "TCP Fast Open:"
if [ "$TFO" = "3" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 4. SQM & FIREWALL
echo ""
echo "[4] SQM & Firewall"
SQM_LIMIT=$(uci get sqm.eth0.download 2>/dev/null)
CAKE_ACTIVE=$(tc qdisc show dev eth0 | grep cake)

printf "  %-25s " "SQM Limit (360M):"
if [ "$SQM_LIMIT" = "360000" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL ($SQM_LIMIT)${NC}\n"; fi
printf "  %-25s " "WAN Qdisc (SQM):"
if echo "$CAKE_ACTIVE" | grep -q "cake"; then printf "${GREEN}OK (CAKE Active)${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

# 5. PERSISTENCE
echo ""
echo "[5] Persistence & APK Backup"
if [ -f "/etc/backup/installed_packages.txt" ]; then printf "  %-25s ${GREEN}OK${NC}\n" "Package List Saved:"; else printf "  %-25s ${RED}FAIL${NC}\n" "Package List:"; fi
HOTPLUG="/etc/hotplug.d/iface/99-r2s-optimize"
printf "  %-25s " "Hotplug Script:"
if [ -f "$HOTPLUG" ]; then printf "${GREEN}OK${NC}\n"; else printf "${RED}FAIL${NC}\n"; fi

echo "=================================================="
