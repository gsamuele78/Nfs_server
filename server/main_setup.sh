#!/bin/bash
# /root/nfs_setup/main_setup.sh

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
# shellcheck source=./nfs_config.conf
source "nfs_config.conf"
export STORAGE_DISK VG_NAME NFS_SHARES NFS_DOMAIN ALLOWED_CLIENTS NFS_THREAD_COUNT

# --- Main Execution ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"

echo "### Starting NFS Server Setup ###"

if [[ ${#NFS_SHARES[@]} -eq 0 ]]; then
    cat <<'EOF'
==================================================================
!!! WARNING: No NFS shares are configured in nfs_config.conf. !!!
------------------------------------------------------------------
To create shares:
1. Edit the NFS_SHARES array in nfs_config.conf
   Example:
   NFS_SHARES=(
     "sssd_share;20G;sssd_share"
     "public_share;5G;public"
   )
2. Re-run ./main_setup.sh
==================================================================
EOF
fi

# Ensure modules are executable
find "${MODULE_DIR}" -type f -name "*.sh" -exec chmod +x {} \;

# Execute modules in order
for module in "${MODULE_DIR}"/*.sh; do
    if [[ -f "${module}" && -x "${module}" ]]; then
        echo "--- Executing module: $(basename "${module}") ---"
        "${module}"
        echo "--- Module $(basename "${module}") completed successfully. ---"
    fi
done
