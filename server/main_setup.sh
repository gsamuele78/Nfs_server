#!/bin/bash
# /root/nfs_setup/main_setup.sh

# Ensure the script exits on any error
set -euo pipefail

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

if [[ ! -f "nfs_config.conf" ]]; then
    echo "ERROR: Configuration file 'nfs_config.conf' not found."
    exit 1
fi

# Load configuration
source "nfs_config.conf"
export STORAGE_DISK VG_NAME NFS_SHARES NFS_DOMAIN ALLOWED_CLIENTS NFS_THREAD_COUNT

# --- Main Execution ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"

echo "### Starting NFS Server Setup ###"

# Execute modules in order
for module in "${MODULE_DIR}"/*.sh; do
    if [[ -f "${module}" && -x "${module}" ]]; then
        echo "--- Executing module: $(basename "${module}") ---"
        "${module}"
        echo "--- Module $(basename "${module}") completed successfully. ---"
    else
        # Make modules executable if they aren't
        echo "--- Setting executable permission and running module: $(basename "${module}") ---"
        chmod +x "${module}"
        "${module}"
        echo "--- Module $(basename "${module}") completed successfully. ---"
    fi
done

echo "### NFS Server Setup Completed Successfully! ###"
echo
echo "The server is now configured. Please review the output for any important notices."
echo "You can test the setup from a client machine using the 'testing/test_from_client.sh' script."
