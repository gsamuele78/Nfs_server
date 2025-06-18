#!/bin/bash
set -euo pipefail

# --- Logging & Tracking ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_fatal() { log_error "$1"; exit 1; }
track_file() { echo "$1" >> "$MANIFEST_FILE"; }

# --- Load Configuration ---
if [[ -z "$1" ]]; then log_fatal "Config file path not provided."; fi
source "$1"
MANIFEST_FILE="$2"

# --- 1. Port Check ---
log_info "Checking connectivity to NFS server ${NFS_SERVER_IP} on port 2049..."
if ! nc -z -v -w5 "${NFS_SERVER_IP}" 2049 &>/dev/null; then
    log_warn "Could not connect to ${NFS_SERVER_IP} on TCP port 2049."
    log_warn "This could be due to:"
    log_warn "  - A firewall on the NFS server blocking the port."
    log_warn "  - The NFS service not running on the server."
    log_warn "  - A network issue between this client and the server."
    read -p "Do you want to continue anyway? (y/N): " choice
    if [[ "${choice}" != "y" && "${choice}" != "Y" ]]; then
        log_fatal "Aborted by user."
    fi
else
    log_success "Successfully connected to the NFS server port."
fi

# --- 2. Discover Shares ---
log_info "Discovering available shares on ${NFS_SERVER_IP}..."
# Get a clean list of share names, removing the /export/ prefix.
# The `|| true` prevents the script from exiting if showmount fails (e.g., port blocked)
available_shares=($(showmount -e "${NFS_SERVER_IP}" | tail -n +2 | awk '{print $1}' | sed 's|^/export/||' || true))

if [[ ${#available_shares[@]} -eq 0 ]]; then
    log_warn "No available shares found on ${NFS_SERVER_IP}."
    log_warn "Please check the server's /etc/exports file and firewall."
    exit 0
fi

# --- 3. Interactive Selection ---
log_info "Please select the shares you wish to mount."
PS3="Enter a number (or 'q' to finish): "
shares_to_mount=()
select share in "${available_shares[@]}"; do
    if [[ -n "${share}" ]]; then
        # Check for duplicates
        if [[ " ${shares_to_mount[*]} " =~ " ${share} " ]]; then
            log_warn "'${share}' has already been selected."
        else
            log_success "Selected: ${share}"
            shares_to_mount+=("${share}")
        fi
    else
        log_warn "Invalid selection. Please try again."
    fi
# The user's reply is in the special $REPLY variable
done <<< "q" # A little trick to allow 'q' to be processed by the loop

if [[ ${#shares_to_mount[@]} -eq 0 ]]; then
    log_info "No shares were selected. Exiting."
    exit 0
fi

# --- 4. Configure and Mount ---
log_info "Configuring the selected shares..."
mkdir -p "${MOUNT_POINT_BASE}"

for share in "${shares_to_mount[@]}"; do
    local_mount_path="${MOUNT_POINT_BASE}/${share}"
    remote_mount_path="${NFS_SERVER_IP}:/${share}"
    mkdir -p "${local_mount_path}"

    if grep -q -w "${local_mount_path}" /etc/fstab; then
        log_info "fstab entry for '${share}' already exists. Skipping."
    else
        log_info "Adding fstab entry for '${share}'..."
        # These are the best-practice options for a robust client mount
        fstab_entry="${remote_mount_path} ${local_mount_path} nfs4 defaults,auto,nofail,_netdev 0 0"
        echo "${fstab_entry}" >> /etc/fstab
        track_file "/etc/fstab"
    fi
done

log_info "Reloading systemd and mounting all configured shares..."
systemctl daemon-reload
mount -a -t nfs4

# --- 5. Final Test ---
log_info "Performing a quick test on mounted shares..."
for share in "${shares_to_mount[@]}"; do
    local_mount_path="${MOUNT_POINT_BASE}/${share}"
    if mountpoint -q "${local_mount_path}"; then
        log_success "Share '${share}' is successfully mounted at ${local_mount_path}."
    else
        log_warn "Share '${share}' failed to mount. Please check logs."
    fi
done
