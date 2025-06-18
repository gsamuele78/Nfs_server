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

# --- 1. Port Check (Core NFS Port) ---
log_info "Checking core NFS connectivity to ${NFS_SERVER_IP} on port 2049..."
if ! nc -z -v -w5 "${NFS_SERVER_IP}" 2049 &>/dev/null; then
    log_fatal "Cannot connect to ${NFS_SERVER_IP} on TCP port 2049. Please check server firewall and ensure NFS service is running."
else
    log_success "Core NFS port 2049 is open and reachable."
fi

# --- 2. Mode Selection ---
shares_to_mount=()
echo
log_info "How would you like to specify the shares to mount?"
echo "  1) Manually Enter Share Names (Most Secure - No server changes needed)"
echo "  2) Temporarily Enable Share Discovery (Requires temporary firewall changes on the server)"
read -p "Please choose an option [1]: " mode_choice
mode_choice=${mode_choice:-1} # Default to 1 if user just hits Enter

if [[ "${mode_choice}" == "1" ]]; then
    # --- Manual Mode ---
    log_info "Entering Manual Mode."
    while true; do
        read -p "Enter the exact name of a share to mount (or press Enter to finish): " share_name
        if [[ -z "${share_name}" ]]; then
            break
        fi
        shares_to_mount+=("${share_name}")
        log_success "Added '${share_name}' to the list."
    done

else
    # --- Discovery Mode ---
    CLIENT_IP=$(hostname -I | awk '{print $1}')
    RPCBIND_PORT=111
    log_warn "To enable share discovery, you must TEMPORARILY open port ${RPCBIND_PORT} on the NFS SERVER."
    echo -e "${C_YELLOW}====================== On the NFS SERVER, run this command ======================${C_RESET}"
    echo -e "${C_GREEN}sudo ufw allow from ${CLIENT_IP} to any port ${RPCBIND_PORT} proto tcp comment 'Temp NFS Discovery'${C_RESET}"
    echo -e "${C_YELLOW}==================================================================================${C_RESET}"
    read -p "Press [Enter] after running the command on the server."

    log_info "Discovering available shares on ${NFS_SERVER_IP}..."
    available_shares=($(showmount -e "${NFS_SERVER_IP}" | awk '{print $1}' | grep '^/export/' | sed 's|^/export/||' || true))

    if [[ ${#available_shares[@]} -eq 0 ]]; then
        log_fatal "Could not discover any shares. Please verify the firewall rule was added and the server is exporting shares."
    fi

    log_info "Please select the shares you wish to mount from the list below."
    PS3="Enter a number (or 'q' to quit): "
    select share in "${available_shares[@]}"; do
        if [[ "${REPLY}" == "q" || "${REPLY}" == "Q" ]]; then break; fi
        if [[ -n "${share}" ]]; then
            shares_to_mount+=("${share}")
            log_success "Selected: ${share}"
        else
            log_warn "Invalid selection."
        fi
    done
    
    echo -e "${C_YELLOW}================== To restore security, run this command on the SERVER =================${C_RESET}"
    echo -e "${C_GREEN}sudo ufw delete allow from ${CLIENT_IP} to any port ${RPCBIND_PORT} comment 'Temp NFS Discovery'${C_RESET}"
    echo -e "${C_YELLOW}==================================================================================${C_RESET}"
    read -p "Press [Enter] to continue the setup."
fi

if [[ ${#shares_to_mount[@]} -eq 0 ]]; then
    log_info "No shares were selected. Exiting."
    exit 0
fi

# --- 3. Configure and Mount ---
log_info "Configuring the selected share(s)..."
mkdir -p "${MOUNT_POINT_BASE}"

for share in "${shares_to_mount[@]}"; do
    local_mount_path="${MOUNT_POINT_BASE}/${share}"
    remote_mount_path="${NFS_SERVER_IP}:/${share}"
    mkdir -p "${local_mount_path}"

    if ! grep -q -w "${local_mount_path}" /etc/fstab; then
        log_info "Adding fstab entry for '${share}'..."
        fstab_entry="${remote_mount_path} ${local_mount_path} nfs4 defaults,auto,nofail,_netdev 0 0"
        echo "${fstab_entry}" >> /etc/fstab
        track_file "/etc/fstab"
    fi
done

log_info "Reloading systemd and mounting shares..."
systemctl daemon-reload
mount -a -t nfs4

# --- 4. Final Test ---
log_info "Performing final check on mounted shares..."
for share in "${shares_to_mount[@]}"; do
    local_mount_path="${MOUNT_POINT_BASE}/${share}"
    if mountpoint -q "${local_mount_path}"; then
        log_success "Share '${share}' is successfully mounted."
    else
        log_warn "Share '${share}' FAILED to mount."
    fi
done
