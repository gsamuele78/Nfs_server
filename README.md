# Automated NFSv4 Server & Client Deployment Kit for Ubuntu 24.04

![Shell Logo](https://img.shields.io/badge/Shell-Bash-blue)
![OS](https://img.shields.io/badge/OS-Ubuntu%2024.04%20LTS-orange)
![License](https://img.shields.io/badge/License-GPL3.0-green)
![Compliance](https://img.shields.io/badge/ShellCheck-Compliant-brightgreen)

This repository provides a robust, modular, and automated set of scripts for deploying a high-performance NFSv4 server and provisioning NFS clients on Ubuntu 24.04 LTS.

The entire solution is designed with sysadmin-friendliness, robustness, and manageability in mind. It uses a configuration-driven approach, meaning you only need to edit simple `.conf` files to customize your entire setup, with no need to modify the script logic itself.

## Core Features

*   **Modular Storage with LVM:** Utilizes the Logical Volume Manager (LVM) to create dynamic shares that can be easily expanded without downtime.
*   **Configuration-Driven:** All user-specific settings (disks, share names, IPs) are kept in simple `*.conf` files, separating configuration from logic.
*   **SSSD-Aware Exports:** Correctly configures NFSv4 to integrate with SSSD-managed users (e.g., from Active Directory), ensuring permissions are correctly mapped between client and server.
*   **Proxmox VE Optimized:** Built with best practices for virtualized environments, including guidance on `VirtIO SCSI` and `IO Thread` settings for maximum disk performance.
*   **Automated Client Provisioning:** Includes a dedicated, safe `client_kit` to automatically configure client machines, set up persistent mounts in `/etc/fstab`, and test the connection.
*   **Robust and Idempotent:** Scripts are designed to be re-runnable. They check for existing configurations and skip steps that are already complete. Uses `set -euo pipefail` for safe execution.
*   **Automated Firewall & NTP:** Automatically configures `ufw` to allow NFS/SSH traffic and sets up `chrony` for critical time synchronization.

## Project Structure

The project is divided into two main components: the `server_kit` for setting up the NFS server and the `client_kit` for provisioning clients.

```
.
├── server
│   ├── main_setup.sh             # Main server orchestrator script
│   ├── nfs_config.conf           # SERVER configuration file (EDIT THIS)
│   └── modules                   # Server setup modules
│       ├── 01_install_packages.sh
│       ├── 02_setup_storage.sh
│       ├── 03_configure_nfs.sh
│       ├── 04_configure_time.sh
│       └── 05_configure_firewall.sh
│
├── client
│   ├── configure_client.sh       # Main client orchestrator script
│   ├── client_config.conf        # CLIENT configuration file (EDIT THIS)
│   └── modules                   # Client setup modules
│       ├── 01_install_client_packages.sh
|       ├── 02_configure_time.sh 
│       ├── 03_setup_mounts.sh
│       └── 04_run_tests.sh
│
└── README.md                     # This documentation
```

---

## Part 1: NFS Server Deployment

Follow these steps on the machine that will become your NFS server.

### Prerequisites

1.  A fresh **Ubuntu 24.04 LTS** server instance (VM or physical).
2.  A dedicated, unformatted block device (virtual disk, physical disk) for the NFS data. **This disk will be completely wiped.**
3.  **(Proxmox VE Optimization)** For best performance:
    *   Use the **`VirtIO SCSI`** controller for the VM.
    *   For the dedicated NFS data disk, enable the **`IO Thread`** option in the Proxmox VM hardware settings.

### Step-by-Step Instructions

#### 1. Clone the Repository

Log in to your server as `root` and clone this repository.

```bash
git clone https://github.com/gsamuele78/Nfs_server.git
cd Nfs_server/server_kit
```

#### 2. Configure the Server

Edit the `nfs_config.conf` file. This is the **only file you need to modify**.

```bash
nano nfs_config.conf
```

Fill in the following details:

```ini
# /server_kit/nfs_config.conf

# --- Storage Configuration ---
# WARNING: THIS DISK WILL BE ENTIRELY WIPED.
# Use 'lsblk' to find the name of your empty data disk.
STORAGE_DISK="/dev/sdb"

# LVM Volume Group name
VG_NAME="nfs_vg"

# --- NFS Shares Configuration ---
# Define shares as "LV_NAME;LV_SIZE;MOUNT_POINT_NAME"
NFS_SHARES=(
  "sssd_share;20G;sssd_share"
  "public_share;5G;public"
)

# --- Networking and Security ---
# CRITICAL: This MUST match your Active Directory / SSSD domain name.
NFS_DOMAIN="yourdomain.com"

# Client networks allowed to connect.
ALLOWED_CLIENTS="192.168.10.0/24"

# --- Performance Tuning ---
# Number of NFS server threads. Match your vCPU count for a good start.
NFS_THREAD_COUNT=8
```

#### 3. Run the Setup Script

Execute the main script as `root`. It will automatically make the modules executable and run them in sequence.

```bash
./main_setup.sh
```

The script will ask for a final confirmation before formatting the storage disk. After it completes, your NFS server is fully configured and ready to accept client connections.

---

## Part 2: NFS Client Provisioning

Follow these steps on any client machine that needs to access the NFS shares.

### Prerequisites

1.  An Ubuntu client machine (22.04, 24.04, etc.).
2.  Network connectivity to the NFS server.
3.  If you need to access SSSD-aware shares, the client should already be joined to your domain.

### Step-by-Step Instructions

#### 1. Copy the Client Kit

From your control machine or the server, copy the `client_kit` directory to the client machine (e.g., into the `/root/` directory).

```bash
# Example using scp from the server to the client
scp -r ../client_kit root@<client_ip>:/root/client_setup
```

#### 2. Configure the Client

Log in to the client machine as `root`, navigate to the setup directory, and edit `client_config.conf`.

```bash
cd /root/client_setup
nano client_config.conf
```

Fill in the server details:

```ini
# /client_kit/client_config.conf

# --- Server Details ---
# The IP address or DNS name of your NFSv4 server.
NFS_SERVER_IP="192.168.10.100" # <-- EDIT THIS

# --- Mount Configuration ---
# The local parent directory where all NFS shares will be mounted.
MOUNT_POINT_BASE="/mnt/nfs"

# List the shares you want this client to mount.
SHARES_TO_MOUNT=(
  "sssd_share"
  "public_share"
)
```

#### 3. Run the Configuration Script

Execute the main client script as `root`.

```bash
./configure_client.sh
```

The script will install the necessary client tools, configure `/etc/fstab` for permanent mounts that survive reboots, mount the shares, and run a write/read test to verify permissions.

---

## Post-Deployment Management

### Expanding an Existing Share

Thanks to LVM, you can grow a share without downtime.

1.  **Add Storage (if needed):** If your Volume Group (`nfs_vg`) is full, add a new virtual disk to the server VM.
2.  **Extend VG:** On the NFS server, initialize the new disk and add it to the Volume Group.
    ```bash
    pvcreate /dev/sdX
    vgextend nfs_vg /dev/sdX
    ```
3.  **Extend LV:** Extend the Logical Volume and resize the filesystem in one command. To add 10GB to `sssd_share`:
    ```bash
    lvextend -L +10G --resizefs /dev/nfs_vg/sssd_share
    ```

### Adding a New Share

1.  On the NFS server, edit `nfs_config.conf` and add a new line to the `NFS_SHARES` array.
2.  Re-run the `./main_setup.sh` script. It will safely create the new share without affecting existing ones.
3.  On the clients, add the new share name to `client_config.conf` and re-run `./configure_client.sh`.

## Architectural Decisions

*   **Why LVM?** LVM provides a flexible abstraction layer over physical storage. This allows for dynamic resizing (growing) of volumes, which is essential for scalable file shares.
*   **How SSSD Integration Works:** NFSv4 relies on string names (`user@domain`) for identity mapping, not legacy UID/GID numbers. By setting the `Domain` in `/etc/idmapd.conf` to match the SSSD domain, we tell the NFS components to correctly map identities provided by SSSD. The export option `sec=sys` trusts the client's assertion of user identity, which is secure on a trusted network.
*   **NFSv4 Pseudo-Filesystem:** The use of `/export` as the `fsid=0` root and bind-mounting the actual shares into it is an NFSv4 best practice. It creates a single, browsable namespace for clients and prevents issues related to filesystem boundaries.

## License

This project is licensed under the GPL3.0 License. See the ([`LICENSE`](https://github.com/gsamuele78/Nfs_server/tree/main?tab=GPL-3.0-1-ov-file)) file for details.
