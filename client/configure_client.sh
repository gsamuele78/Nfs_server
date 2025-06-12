#!/bin/bash
# /root/client_setup/configure_client.sh

# Ensure the script exits on any error
set -euo pipefail

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

if [[ ! -f "client_config.conf" ]]; then
    echo "ERROR: Configuration file 'client_config.conf' not found."
    exit 1
fi

# Load configuration and export it for modules
source "client_config.conf"
export NFS_SERVER_IP MOUNT_POINT_BASE SHARES_TO_MOUNT

# --- Main Execution ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"

echo "### Starting NFS Client Configuration ###"

# Execute modules in order
for module in "${MODULE_DIR}"/*.sh; do
    if [[ ! -x "${module}" ]]; then
        chmod +x "${module}"
    fi
    echo "--- Executing module: $(basename "${module}") ---"
    "${module}"
    echo "--- Module $(basename "${module}") completed successfully. ---"
done

echo
echo "### NFS Client Configuration and Testing Completed! ###"
echo "The following NFS shares are now configured in /etc/fstab and mounted:"
df -h | grep "${NFS_SERVER_IP}"
