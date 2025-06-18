#!/bin/bash
set -euo pipefail

# --- Logging & Tracking ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_fatal() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; exit 1; }
track_file() { echo "$1" >> "$MANIFEST_FILE"; }

# --- Load Configuration ---
if [[ -z "$1" ]]; then log_fatal "Config file path not provided."; fi
source "$1"
MANIFEST_FILE="$2"

# --- 1. Port Check & Discovery ---
log_info "Checking connectivity and discovering shares from ${NFS_SERVER_IP}..."
# The showmount command uses RPC, which is a good test for the hardened ports.
available_shares=($(showmount -e "${NFS_SERVER_IP}" | awk '{print $1}' | grep '^/export/' | sed 's|^/export/||' || true))

if [[ ${#available_shares[@]} -eq 0 ]]; then
    log_fatal "Could not discover any mountable shares. Please check the server's firewall and ensure the RPC hardening script has been run."
fi
log_success "Successfully discovered ${#available_shares[@]} share(s)."

# --- 2. Interactive Selection (THE NEW, FIXED MENU) ---
echo
log_info "The following shares are available to mount:"
PS3=$'\n'"Enter the number of a share to add (or 'done' to finish): "
shares_to_mount=()
while true; do
    select share in "${available_shares[@]}" "Done"; do
        case "${share}" in
            "Done")
                log_info "Finished selection."
                break 2 # Break out of both the 'select' and 'while' loops
                ;;
            "") # Invalid input
                log_warn "Invalid selection. Please try again."
                ;;
            *) # Valid share selected
                if [[ " ${shares_to_mount[*]} " =~ " ${share} " ]]; then
                    log_warn "'${share}' has already been selected."
                else
                    shares_to_mount+=("${share}")
                    log_success "Added '${share}'. Current selection: ${C_YELLOW}${shares_to_mount[*]}${C_RESET}"
                fi
                break # Break out of the inner 'select' loop to re-display the menu
                ;;
        esac
    done
done

if [[ ${#shares_to_mount[@]} -eq 0 ]]; then
    log_info "No shares were selected. Exiting."
    exit 0
fi

# --- 3. Configure and Mount ---
log_info "Configuring the ${#shares_to_mount[@]} selected share(s)..."
mkdir -p "${MOUNT_POINT_BASE}"

for share in "${shares_to_mount[@]}"; do
    local_mount_path="${MOUNT_POINT_BASE}/${share}"
    remote_mount_path="${NFS_SERVER_IP}:/${share}"
    mkdir -p "${local_mount_path}"

    if ! grep -q -w "${local_mount_path}" /etc/fstab; then
        fstab_entry="${remote_mount_path} ${local_mount_path} nfs4 defaults,auto,nofail,_netdev 0 0"
        echo "${fstab_entry}" >> /etc/fstab
        track_file "/etc/fstab"
    fi
done

log_info "Reloading systemd and mounting shares..."
systemctl daemon-reload
mount -a -t nfs4

# --- 4. Final Test ---
log_info "Performing final check..."
for share in "${shares_to_mount[@]}"; do
    if mountpoint -q "${MOUNT_POINT_BASE}/${share}"; then
        log_success "Share '${share}' is successfully mounted."
    else
        log_warn "Share '${share}' FAILED to mount."
    fi
done
