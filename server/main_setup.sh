#!/bin/bash
set -euo pipefail

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." >&2
   exit 1
fi

CONFIG_FILE="nfs_config.conf"
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Configuration file '${CONFIG_FILE}' not found in the current directory." >&2
    exit 1
fi

# --- Main Execution ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"

echo "### Starting NFS Server Setup ###"
echo "### Using configuration from ${BASE_DIR}/${CONFIG_FILE} ###"

# Execute modules in order
for module in "${MODULE_DIR}"/*.sh; do
    if [[ ! -x "${module}" ]]; then chmod +x "${module}"; fi
    echo "--- Executing module: $(basename "${module}") ---"
    # Pass the config file path to each module for sourcing
    "${module}" "${BASE_DIR}/${CONFIG_FILE}"
    echo "--- Module $(basename "${module}") completed successfully. ---"
done

echo
echo "### NFS Server Setup Completed Successfully! ###"
echo "### Final Status ###"
vgs
lvs
df -h | grep --color=auto /srv/nfs
