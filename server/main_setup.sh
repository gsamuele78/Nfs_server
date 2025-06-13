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
if [[ $EUID -ne 0 ]]; then log_fatal "This script must be run as root."; fi

CONFIG_FILE="nfs_config.conf"
if [[ ! -f "${CONFIG_FILE}" ]]; then log_fatal "Configuration file '${CONFIG_FILE}' not found."; fi

# --- Manifest for Reporting ---
# Create a temporary file to track all modified configuration files.
MANIFEST_FILE=$(mktemp)
# Ensure the manifest is cleaned up automatically on script exit (success, failure, or interrupt)
trap 'rm -f "$MANIFEST_FILE"' EXIT

# --- Main Execution ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"

log_info "### Starting NFS Server Setup ###"
log_info "Using configuration from ${BASE_DIR}/${CONFIG_FILE}"
log_info "Changes will be tracked in a temporary manifest file."

for module in "${MODULE_DIR}"/*.sh; do
    if [[ ! -x "${module}" ]]; then chmod +x "${module}"; fi
    log_info "--- Executing module: $(basename "${module}") ---"
    # Pass both the config and manifest file paths to each module
    "${module}" "${BASE_DIR}/${CONFIG_FILE}" "${MANIFEST_FILE}"
    log_success "--- Module $(basename "${module}") completed successfully. ---"
done

# --- Final Sysadmin Report ---
echo
log_success "### NFS Server Setup Completed Successfully! ###"
echo
echo -e "====================== ${C_GREEN}Sysadmin Report${C_RESET} ======================"
echo -e "The following configuration files were created or modified by this script:"
echo -e "You can inspect these files to verify the configuration."
echo -e "---------------------------------------------------------------"
# Sort the manifest to show a unique, ordered list of files.
sort -u "${MANIFEST_FILE}" | while read -r file; do
    echo -e "  - ${C_YELLOW}${file}${C_RESET}"
done
echo -e "---------------------------------------------------------------"
echo -e "Additionally, the following services were configured and enabled:"
echo -e "  - ${C_YELLOW}chrony${C_RESET} (Time Synchronization)"
echo -e "      (View status with: ${C_GREEN}chronyc sources${C_RESET})"
echo -e "  - ${C_YELLOW}ufw${C_RESET} (Firewall)"
echo -e "      (View status with: ${C_GREEN}ufw status verbose${C_RESET})"
echo
echo -e "Final LVM and Filesystem Status:"
vgs
lvs
df -h | grep --color=auto /srv/nfs
echo -e "==============================================================="
