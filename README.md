# NanoPi R2S "Ultimate" Network Optimization
## For OpenWrt 24.10+ / FriendlyWrt

### Overview
This project provides an **"Ultimate"** network optimization suite for the NanoPi R2S running OpenWrt. It tunes the **entire network stack** for modern high-speed connections (500Mbps - 1Gbps).

It solves the hardware single-core bottleneck and transforms the R2S into a low-latency, bufferbloat-free router capable of handling heavy loads without choking.

### Features
This script applies a 6-layer optimization stack:

1.  **CPU Load Balancing (IRQ/RPS + XPS):** 
    *   Distributes **Incoming (RPS)** AND **Outgoing (XPS)** traffic across all 4 cores.
    *   Pins Hardware Interrupts (IRQ) to dedicated cores (Eth0->CPU1, Eth1->CPU2) to prevent locking.
2.  **Flow Steering (RFS):** Enables global Receive Flow Steering to route packets to the CPU core processing the application, maximizing CPU cache efficiency.
3.  **Smart Frequency Scaling (Schedutil):** Replaces the lazy `ondemand` governor with `schedutil`, which reacts instantly to traffic bursts, preventing micro-stutters.
4.  **BBR Congestion Control + FQ:** Enables Google's BBR algorithm and Fair Queueing (FQ) system-wide for higher throughput and lower latency on 'noisy' lines.
5.  **SQM CAKE (Bufferbloat Killer):** Automatically installs and configures Smart Queue Management (SQM) with the **CAKE** algorithm.
    *   *Default Target:* 500Mbps (Editable).
    *   *Fixes:* Disables "Flow Offloading" which is known to break SQM.
6.  **Buffer Tuning:** Increases TCP/UDP kernel buffers to 16MB to prevent packet loss at high speeds.

### Installation

1.  Connect to your OpenWrt router via SSH.
2.  Run the following single command to download and execute the optimizer:

```bash
wget -O install_optimized.sh https://raw.githubusercontent.com/madgagarin/nanopi-r2s-performance-tweak/main/install_optimized.sh && sh install_optimized.sh
```

**What the script does:**
1.  Updates `opkg` and installs missing packages (`kmod-tcp-bbr`, `sqm-scripts`, etc.).
2.  Backs up your existing config.
3.  Applies all kernel, network, and firewall fixes.
4.  **Installs a System Service** (`/etc/init.d/r2s_optimize`) that runs on every boot to apply CPU balancing.
5.  **Adds Persistence**: Updates `/etc/sysupgrade.conf` so the script survives firmware upgrades.

### Configuration

#### Adjusting Speed
By default, SQM is set to **500 Mbps**. To match your ISP speed:
1.  Go to LuCI (Web Interface) -> **Network** -> **SQM QoS**.
2.  Or edit via terminal:
    ```bash
    uci set sqm.eth0.download='YOUR_SPEED_KBPS'
    uci set sqm.eth0.upload='YOUR_SPEED_KBPS'
    uci commit sqm
    /etc/init.d/sqm restart
    ```

### Verification

Run the included check script to see the status of all optimizations:

```bash
./check_optimized.sh
```

**Expected Output:**
```text
[1] CPU Load Balancing (IRQ/RPS/XPS)
  CPU Governor:      OK (schedutil)
  IRQ eth0 (WAN):    OK (CPU1)
  IRQ eth1 (USB):    OK (CPU2)
  RPS eth0 (WAN):    OK (CPU0+1)
  RPS eth1 (LAN):    OK (CPU2+3)
  XPS eth0 (WAN):    OK (CPU0+1)

[2] Flow Steering (RFS)
  Global Entries:    OK
  Queue Flow Count:  OK

[3] TCP & Congestion Control
  Algorithm (BBR):   OK
  Sys Default (FQ):  OK
  TCP Buffer (Max):  OK (16MB)

[4] SQM & Firewall
  SQM Enabled:       OK
  Flow Offloading:   OK (Disabled)
  WAN Qdisc (SQM):   OK (CAKE Active)

[5] Persistence & Backup
  Auto-Start Script: OK
  Backup (Service):  OK
  Backup (Auto-Start): OK
```

### Requirements
*   **Device:** NanoPi R2S (or similar Rockchip RK3328 boards).
*   **OS:** OpenWrt 21.02 or newer (Tested on 24.10).
*   **Packages:** Internet connection required during install to fetch `kmod-tcp-bbr` and `sqm`.