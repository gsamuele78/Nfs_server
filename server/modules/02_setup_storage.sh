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
CONFIG_FILE="$1"
source "${CONFIG_FILE}"
# The manifest file is the second argument
MANIFEST_FILE="$2"

# --- Pre-flight Checks & LVM Setup ---
log_info "Validating storage configuration..."
declare -A lv_names_seen
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name _ <<< "${share_info}"
    if [[ -v lv_names_seen[$lv_name] ]]; then
        log_fatal "Duplicate LV_NAME '${lv_name}' found. Names must be unique."
    fi
    lv_names_seen["$lv_name"]=1
done
log_success "Configuration is valid."

if ! vgdisplay "${VG_NAME}" &>/dev/null; then
    read -p "Type 'CONFIRM' to proceed, or any other key to abort: " CONFIRMATION
    if [[ "${CONFIRMATION}" != "CONFIRM" ]]; then echo "Aborted by user."; exit 1; fi
    wipefs -a "${STORAGE_DISK}" && pvcreate -f "${STORAGE_DISK}" && vgcreate "${VG_NAME}" "${STORAGE_DISK}"
fi
NFS_ROOT="/srv/nfs"; mkdir -p "${NFS_ROOT}"; chmod 755 "${NFS_ROOT}"

# --- Share Creation Loop ---
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name lv_size mount_point_name _ <<< "${share_info}"
    lv_path="/dev/${VG_NAME}/${lv_name}"
    mount_path="${NFS_ROOT}/${mount_point_name}"

    log_info "Processing share '${mount_point_name}' (LV: ${lv_name})"
    if ! lvdisplay "${lv_path}" &>/dev/null; then
        lvcreate -n "${lv_name}" -L "${lv_size}" "${VG_NAME}"
        mkfs.ext4 "${lv_path}"
    fi

    mkdir -p "${mount_path}"
    if ! grep -q -w "${mount_path}" /etc/fstab; then
        UUID=$(blkid -s UUID -o value "${lv_path}")
        log_info "  - Adding entry to /etc/fstab for ${mount_path}..."
        echo "UUID=${UUID} ${mount_path} ext4 defaults 0 0" >> /etc/fstab
        # Add the file to our report manifest
        track_file "/etc/fstab"
    fi
done
log_info "Mounting all filesystems defined in /etc/fstab..."
mount -a
