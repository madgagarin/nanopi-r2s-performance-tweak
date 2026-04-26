# NanoPi R2S "Ultimate" Network Optimization
## For OpenWrt 21.02+ / FriendlyWrt

### Overview
This project provides an **"Ultimate"** network optimization suite for the NanoPi R2S. It tunes the **entire network stack** to handle modern high-speed connections (500Mbps - 1Gbps) with minimal latency and maximum stability.

It solves the hardware single-core bottleneck, protects your SD card from wear, and transforms the R2S into a low-latency, bufferbloat-free router capable of handling heavy loads even with an unstable ISP.

### Features
This script applies an advanced optimization stack:

1.  **CPU Load Balancing (IRQ/RPS + XPS):** 
    *   Distributes **Incoming (RPS)** AND **Outgoing (XPS)** traffic across **ALL 4 cores** (Mask: `f`).
    *   Pins Hardware Interrupts (IRQ) to dedicated cores (Eth0->CPU1, Eth1->CPU2) to prevent locking.
    *   **Hotplug Persistence:** Automatically re-applies settings when interfaces go up/down (prevents "settings drop" after network restart).
2.  **Flow Steering (RFS):** Enables global Receive Flow Steering (32k entries) to route packets to the CPU core processing the application.
3.  **Adaptive SQM CAKE (Bufferbloat Killer):** 
    *   Automatically configures **CAKE** with **Ack-Filtering** and **Autorate Ingress** to handle floating/unstable ISP speeds.
    *   *Overhead Tuning:* Includes presets for Ethernet (18), PPPoE (26), and VDSL (44).
4.  **System & TCP Tuning:** 
    *   **BBR + FQ:** Enables Google's BBR congestion control.
    *   **TCP Fast Open (TFO):** Speeds up handshake for faster web browsing.
    *   **Entropy (haveged):** Speeds up SSL/TLS handshakes and VPN.
5.  **Reliability & Self-Healing:** 
    *   **Auto-Recovery:** Automatically restores all installed packages after a firmware upgrade or backup restoration.
    *   **noatime:** Disables access time writes to reduce SD card wear.
    *   **RAM Logging:** Limits system logs to 512KB in RAM to prevent disk I/O spikes.
    *   **Memory Guard:** Reserves 16MB for kernel networking to prevent stalls under load.
6.  **Queue Tuning:** Sets `txqueuelen` to 10000 for both interfaces to handle bursts without packet loss.

### Installation

1.  Connect to your OpenWrt router via SSH.
2.  Run the following command to download and execute the optimizer:

```bash
wget -O install_optimized.sh https://raw.githubusercontent.com/madgagarin/nanopi-r2s-performance-tweak/main/install_optimized.sh && sh install_optimized.sh
```

**Persistence**: The script automatically updates `/etc/sysupgrade.conf` so optimizations survive firmware upgrades.

### Verification

Run the included check script to see the status of all optimizations:

```bash
./check_optimized.sh
```

**Expected Output:**
```text
[1] CPU Load Balancing (IRQ/RPS/XPS) -> OK (Optimized)
[2] Flow Steering & Queues          -> OK (TXQ: 10000)
[3] TCP & System Tuning             -> OK (BBR, TFO, 16MB)
[4] SQM & Firewall                  -> OK (CAKE, 360/360 Mbps)
[5] Persistence & Backup            -> OK (Hotplug Active)
[6] SD Card & Logs Optimization     -> OK (noatime, 512K)
```

### Requirements
*   **Device:** NanoPi R2S (or similar Rockchip RK3328 boards).
*   **OS:** OpenWrt 21.02 or newer (Tested on 24.10).
*   **Packages:** Internet connection required during install to fetch `kmod-tcp-bbr`, `sqm`, and `haveged`.
