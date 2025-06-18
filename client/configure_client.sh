#!/bin/bash
set -euo pipefail

# --- Color and Logging Definitions ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_fatal() { log_error "$1"; exit 1; }

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then log_fatal "This script must be run as root."; fi
CONFIG_FILE="client_config.conf"
if [[ ! -f "${CONFIG_FILE}" ]]; then log_fatal "Configuration file '${CONFIG_FILE}' not found."; fi

# --- Manifest for Reporting ---
MANIFEST_FILE=$(mktemp)
trap 'rm -f "$MANIFEST_FILE"' EXIT

# --- Main Execution ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"

log_info "### Starting NFS Client Provisioning ###"
log_info "Using configuration from ${BASE_DIR}/${CONFIG_FILE}"

for module in "${MODULE_DIR}"/*.sh; do
    if [[ ! -x "${module}" ]]; then chmod +x "${module}"; fi
    log_info "--- Executing module: $(basename "${module}") ---"
    "${module}" "${BASE_DIR}/${CONFIG_FILE}" "${MANIFEST_FILE}"
    log_success "--- Module $(basename "${module}") completed successfully. ---"
done

# --- Final Sysadmin Report ---
echo
log_success "### NFS Client Provisioning Completed! ###"
echo
echo -e "====================== ${C_GREEN}Sysadmin Report${C_RESET} ======================"
if [[ -s "${MANIFEST_FILE}" ]]; then
    echo -e "The following configuration files were modified:"
    sort -u "${MANIFEST_FILE}" | while read -r file; do
        echo -e "  - ${C_YELLOW}${file}${C_RESET}"
    done
else
    echo -e "No configuration files were modified."
fi
echo -e "---------------------------------------------------------------"
NFS_SERVER_IP=$(grep 'NFS_SERVER_IP' "$CONFIG_FILE" | cut -d'"' -f2)
echo -e "Current NFS Mounts from ${NFS_SERVER_IP}:"
df -h | grep --color=auto "${NFS_SERVER_IP}" || echo "  (None)"
echo -e "==============================================================="
