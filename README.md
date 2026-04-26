# NanoPi R2S Performance Tweak (OpenWrt 25.12+ APK)

Configuration for NanoPi R2S (Rockchip RK3328) router running OpenWrt 25.12 or newer. Optimized for high-speed Gigabit networking, low latency (Bufferbloat A+), and CPU efficiency.

### Features
This script applies an configuration adapted for the **APK package manager**:

1.  **CPU Load Balancing (IRQ/RPS + XPS):** 
    *   Distributes **Incoming (RPS)** AND **Outgoing (XPS)** traffic across **ALL 4 cores**.
    *   **Advanced Core Separation:** Pins HW Interrupts to dedicated cores (Eth0->CPU1, Eth1->CPU2) while excluding them from RPS to prevent SoftIRQ bottlenecks.
    *   **Hotplug Persistence:** Automatically re-applies settings when interfaces go up/down.
2.  **Flow Steering (RFS):** Enables global Receive Flow Steering (32k entries) and optimized queue flow counts (16k).
3.  **Adaptive SQM CAKE (Bufferbloat Killer):** 
    *   Symmetric **360/360 Mbps** limits to ensure CPU stability on RK3328.
    *   Includes **Ack-Filtering** and **Autorate Ingress**.
4.  **Hardware & System Tuning:** 
    *   **APK Support:** Fully compatible with OpenWrt 25.12+ package management (using `apk`).
    *   **Ethtool Tuning:** Increased Ring Buffers (1024) and optimized Coalescing (30ms).
    *   **BBR + FQ:** Enables Google's BBR congestion control.
5.  **Reliability & Self-Healing:** 
    *   **Auto-Recovery (APK):** Automatically restores all installed packages using `apk add` after firmware upgrades.
    *   **Filesystem Check:** Automatically verifies `/opt` (F2FS) integrity on boot.
6.  **Queue Tuning:** Sets `txqueuelen` to 10000 for both interfaces.

### Installation

1.  Connect to your OpenWrt router via SSH.
2.  Run the following command:
```bash
wget -O install_optimized.sh https://raw.githubusercontent.com/username/nanopi-r2s-performance-tweak/main/install_optimized.sh
chmod +x install_optimized.sh
./install_optimized.sh
```

### Verification
Run the included check script:
```bash
./check_optimized.sh
```

**Expected Output:**
```text
[1] CPU Load Balancing (IRQ/RPS/XPS) -> OK
[2] Flow Steering & Queues          -> OK (TXQ: 10000)
[3] TCP & System Tuning             -> OK (BBR, TFO, 16MB)
[4] SQM & Firewall                  -> OK (CAKE, 360/360 Mbps)
[5] Persistence & APK Backup        -> OK (Hotplug Active)
```

### Requirements
*   **OS:** OpenWrt 25.12 or newer (with APK support).
*   **Hardware:** NanoPi R2S (Rockchip RK3328).
