#!/bin/bash
set -euo pipefail

# --- Color and Logging Definitions ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_fatal() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; exit 1; }

# --- Sanity Checks ---
if [[ $EUID -ne 0 ]]; then log_fatal "This script must be run as root."; fi
CONFIG_FILE="nfs_config.conf"
if [[ ! -f "${CONFIG_FILE}" ]]; then log_fatal "Configuration file '${CONFIG_FILE}' not found."; fi

# --- Global Variables ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"
source "${BASE_DIR}/${CONFIG_FILE}" # Source config to get VG_NAME

# ==============================================================================
#                            MAIN SCRIPT LOGIC
# ==============================================================================

if ! vgdisplay "${VG_NAME}" &>/dev/null; then
    # --- INSTALLATION MODE ---
    log_info "Volume Group '${VG_NAME}' not found. Starting initial installation process..."
    MANIFEST_FILE=$(mktemp)
    trap 'rm -f "$MANIFEST_FILE"' EXIT
    for module in "${MODULE_DIR}"/0[1-5]*.sh; do
        if [[ ! -x "${module}" ]]; then chmod +x "${module}"; fi
        "${module}" "${BASE_DIR}/${CONFIG_FILE}" "${MANIFEST_FILE}"
    done
    log_success "### NFS Server Initial Installation Completed! ###"
else
    # --- MANAGEMENT MODE ---
    log_info "NFS Server already installed. Entering Management Mode."
    while true; do
        echo
        echo -e "${C_GREEN}====================== NFS Management Menu ======================${C_RESET}"
        echo "  1) Manage Share Storage (Enlarge/Shrink/Move)"
        echo "  2) Re-apply Server Configuration (Firewall, Exports)"
        echo "  Q) Quit"
        echo -e "${C_GREEN}===================================================================${C_RESET}"
        read -p "Enter your choice: " choice

        case $choice in
            1)
                log_info "Launching Share Storage Management module..."
                "${MODULE_DIR}/07_manage_shares.sh" "${BASE_DIR}/${CONFIG_FILE}"
                ;;
            2)
                read -p "Re-apply config from nfs_config.conf? (y/N): " confirm
                if [[ "${confirm,,}" == "y" ]]; then
                    MANIFEST_FILE=$(mktemp); trap 'rm -f "$MANIFEST_FILE"' EXIT
                    for module in "${MODULE_DIR}"/0[3-5]*.sh; do
                         "${module}" "${BASE_DIR}/${CONFIG_FILE}" "${MANIFEST_FILE}"
                    done
                    log_success "Configuration re-applied."
                fi
                ;;
            [qQ])
                log_info "Exiting Management Mode."; break ;;
            *)
                log_warn "Invalid option." ;;
        esac
    done
fi
