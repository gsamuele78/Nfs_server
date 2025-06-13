#!/bin/bash
set -euo pipefail

# --- Color and Logging Definitions ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'

log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; }
log_fatal() { log_error "$1"; exit 1; }

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then
   log_fatal "This script must be run as root."
fi

CONFIG_FILE="nfs_config.conf"
if [[ ! -f "${CONFIG_FILE}" ]]; then
    log_fatal "Configuration file '${CONFIG_FILE}' not found in the current directory."
fi

# --- Main Execution ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"

log_info "### Starting NFS Server Setup ###"
log_info "Using configuration from ${BASE_DIR}/${CONFIG_FILE}"

# Execute modules in order
for module in "${MODULE_DIR}"/*.sh; do
    if [[ ! -x "${module}" ]]; then chmod +x "${module}"; fi
    log_info "--- Executing module: $(basename "${module}") ---"
    # Pass the config file path and logging functions to each module
    "${module}" "${BASE_DIR}/${CONFIG_FILE}"
    log_success "--- Module $(basename "${module}") completed successfully. ---"
done

echo
log_success "### NFS Server Setup Completed Successfully! ###"
log_info "### Final Status ###"
vgs
lvs
df -h | grep --color=auto /srv/nfs
