#!/bin/bash
set -euo pipefail

# --- Color and Logging Definitions ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_fatal() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; exit 1; }

# --- Function: Final Sysadmin Report ---
generate_final_report() {
    local manifest_path="$1"
    echo; log_success "### Operation Completed ###"; echo
    echo -e "====================== ${C_GREEN}Sysadmin Report${C_RESET} ======================"
    if [[ -s "${manifest_path}" ]]; then
        echo -e "The following configuration files were modified:"; echo "---------------------------------------------------------------"
        sort -u "${manifest_path}" | while read -r file; do echo -e "  - ${C_YELLOW}${file}${C_RESET}"; done
    else
        echo -e "No configuration files were modified during this session."
    fi
    echo -e "---------------------------------------------------------------"; echo
    echo -e "Final LVM and Filesystem Status:"
    # Use '|| true' to prevent script exit if vg/lv doesn't exist after removal
    vgs "${VG_NAME}" 2>/dev/null || log_warn "Volume Group '${VG_NAME}' no longer exists."
    lvs "${VG_NAME}" 2>/dev/null || true
    df -h | grep --color=auto "/srv/nfs" || true
    echo -e "==============================================================="
}

# --- Main Script Logic ---
if [[ $EUID -ne 0 ]]; then log_fatal "This script must be run as root."; fi
CONFIG_FILE="nfs_config.conf"
if [[ ! -f "${CONFIG_FILE}" ]]; then log_fatal "Configuration file '${CONFIG_FILE}' not found."; fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_DIR="${BASE_DIR}/modules"
source "${BASE_DIR}/${CONFIG_FILE}"

MANIFEST_FILE=$(mktemp)
trap 'rm -f "$MANIFEST_FILE"' EXIT

if ! vgdisplay "${VG_NAME}" &>/dev/null; then
    # --- INSTALLATION MODE ---
    log_info "Volume Group '${VG_NAME}' not found. Starting initial installation..."
    for module in "${MODULE_DIR}"/0[1-5]*.sh; do
        "${module}" "${BASE_DIR}/${CONFIG_FILE}" "${MANIFEST_FILE}"
    done
else
    # --- MANAGEMENT MODE ---
    log_info "NFS Server already installed. Entering Management Mode."
    while true; do
        echo
        echo -e "${C_GREEN}====================== NFS Management Menu ======================${C_RESET}"
        echo "  1) Manage Share Storage (Enlarge/Shrink/Move/Remove)"
        echo "  2) Re-apply Server Configuration (Firewall, Exports)"
        echo "  Q) Quit and Show Report"
        echo -e "${C_GREEN}===================================================================${C_RESET}"
        read -p "Enter your choice: " choice

        case $choice in
            1)
                # Pass the manifest file so the 'remove' function can track changes
                "${MODULE_DIR}/07_manage_shares.sh" "${BASE_DIR}/${CONFIG_FILE}" "${MANIFEST_FILE}"
                ;;
            2)
                read -p "Re-apply config from nfs_config.conf? (y/N): " confirm
                if [[ "${confirm,,}" == "y" ]]; then
                    for module in "${MODULE_DIR}"/0[3-5]*.sh; do
                        "${module}" "${BASE_DIR}/${CONFIG_FILE}" "${MANIFEST_FILE}"
                    done
                fi
                ;;
            [qQ])
                break ;;
            *)
                log_warn "Invalid option." ;;
        esac
    done
fi

generate_final_report "${MANIFEST_FILE}"
