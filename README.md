## NanoPi R2S
# Network Performance Tweak for OpenWrt/FriendlyWrt

## Overview

This guide provides a definitive solution to optimize network performance on the **NanoPi R2S** running OpenWrt, FriendlyWrt, or similar Linux-based firmware. The goal is to resolve CPU core saturation and achieve stable, near-gigabit routing speeds by correctly balancing the network processing load.

This method has been tested and confirmed to work where other common approaches (like modifying hotplug scripts) may fail due to system overrides.

## The Problem: The Single-Core Bottleneck

By default, the NanoPi R2S often struggles to reach its full gigabit routing potential because all network interrupt (IRQ) processing for a given interface is handled by a **single CPU core**. This causes that one core to hit 100% utilization, creating a bottleneck that limits throughput, especially when using features like SQM or handling heavy traffic.

There are two underlying technical reasons for this:

1.  **Kernel/Hardware IRQ Limitation:** The Linux kernel on the R2S **cannot assign a single IRQ to multiple CPU cores**. Attempts to apply a multi-core affinity mask (e.g., `echo 3 > .../smp_affinity`) will fail with an `Invalid argument` error. Each network interrupt must be handled by one, and only one, core.
2.  **USB-Based Ethernet Overhead:** One of the two ethernet ports on the R2S is connected via an internal USB 3.0 controller. This architecture inherently creates more CPU overhead compared to a native SoC-based port, making efficient load distribution even more critical.

## The Solution: Two-Level CPU Load Balancing

Since we cannot share a single IRQ, we implement a more intelligent, two-level optimization strategy:

1.  **Level 1: Isolate IRQs:** We pin the hardware interrupt for each network port to its own **separate, dedicated CPU core**. This prevents them from competing for the same core's resources.
    * **LAN (eth0, IRQ 29)** is pinned to **CPU1**.
    * **WAN (eth1, IRQ 30)** is pinned to **CPU2**.
2.  **Level 2: Distribute Packet Queues (RPS):** After a core is "woken up" by an IRQ, we use Receive Packet Steering (RPS) to distribute the subsequent software processing of network packets across a **pair of cores**.
    * The packet queue for **LAN (eth0)** is handled by **CPU0 & CPU1**.
    * The packet queue for **WAN (eth1)** is handled by **CPU2 & CPU3**.

This configuration creates a balanced and efficient pipeline, resolving the single-core bottleneck.

## Installation: The Command-Line Method

This method inserts the necessary configuration directly into `/etc/rc.local` using terminal commands, without needing a text editor like `nano`.

1.  Connect to your router via SSH.
2.  **Backup your current `rc.local` file** (this is a safe practice):
    ```bash
    cp /etc/rc.local /etc/rc.local.bak
    ```
3.  **Run the following command** to automatically insert the optimization script. Copy the entire block below, paste it into your terminal, and press Enter.
    ```bash
    sed -i '/^exit 0/i \
    \
    # NanoPi R2S Network Performance Optimization\
    # This script is executed at the end of the boot process to ensure settings persist.\
    \
    # 1. Pin Hardware Interrupts to specific CPU cores\
    # Pin eth0 (LAN, IRQ 29) to CPU1\
    echo 2 > \/proc\/irq\/29\/smp_affinity\
    # Pin eth1 (WAN, IRQ 30) to CPU2\
    echo 4 > \/proc\/irq\/30\/smp_affinity\
    \
    # 2. Distribute Packet Processing (RPS) across CPU core pairs\
    # Handle eth0 (LAN) RPS on CPU0 and CPU1\
    echo 3 > \/sys\/class\/net\/eth0\/queues\/rx-0\/rps_cpus\
    # Handle eth1 (WAN) RPS on CPU2 and CPU3\
    echo c > \/sys\/class\/net\/eth1\/queues\/rx-0\/rps_cpus\
    ' /etc/rc.local
    ```
4.  Reboot the router to apply the changes:
    ```bash
    reboot
    ```

## Verification

After the router reboots, you can verify that the settings have been correctly applied.

1.  Log in via SSH again.
2.  **Copy the entire block below**, paste it into your terminal, and press Enter. This command block will create a verification script, make it executable, and run it for you.

    #### Create the script file using a 'here document' for clarity

    ```bash
    cat > check_affinity.sh << EOF
    #!/bin/sh
    echo "Verifying CPU Affinities..."
    echo "-------------------------------------"
    echo "LAN (eth0) IRQ 29 Affinity: \$(cat /proc/irq/29/smp_affinity)"
    echo "WAN (eth1) IRQ 30 Affinity: \$(cat /proc/irq/30/smp_affinity)"
    echo "LAN (eth0) RPS Affinity:    \$(cat /sys/class/net/eth0/queues/rx-0/rps_cpus)"
    echo "WAN (eth1) RPS Affinity:    \$(cat /sys/class/net/eth1/queues/rx-0/rps_cpus)"
    echo "-------------------------------------"
    EOF
    ```

    #### Make the script executable
    ```bash
    chmod +x check_affinity.sh
    ```

    #### Run the script to show the results
    ```bash
    ./check_affinity.sh
    ```
    
### Expected Output

The output of the script should be exactly this:

```
Verifying CPU Affinities...
-------------------------------------
LAN (eth0) IRQ 29 Affinity: 2
WAN (eth1) IRQ 30 Affinity: 4
LAN (eth0) RPS Affinity:    3
WAN (eth1) RPS Affinity:    c
-------------------------------------
```

If your output matches the above, your NanoPi R2S is now correctly optimized for high-performance networking.
