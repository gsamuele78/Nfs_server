#!/bin/bash
set -euo pipefail

# --- Color and Logging Definitions (from main script) ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; }
log_fatal() { log_error "$1"; exit 1; }

# --- Load Configuration ---
if [[ -z "$1" ]]; then log_fatal "Configuration file path was not provided."; fi
source "$1"

# --- Pre-flight Checks ---
log_info "Validating storage configuration..."
if ! lsblk -no NAME "/dev/${STORAGE_DISK##*/}" &>/dev/null; then
    log_fatal "Storage disk '${STORAGE_DISK}' does not exist."
fi

if pvs --noheadings -o vg_name "${STORAGE_DISK}" | grep -q -v "${VG_NAME}"; then
    log_warn "Disk '${STORAGE_DISK}' is already part of another Volume Group."
    log_warn "Script will proceed, but this is unusual. Ensure this is intended."
fi

declare -A lv_names_seen
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name _ <<< "${share_info}"
    # The CRITICAL FIX is here: using -v to check for key existence.
    if [[ -v lv_names_seen[$lv_name] ]]; then
        log_fatal "Duplicate LV_NAME '${lv_name}' found in nfs_config.conf. Names must be unique."
    fi
    lv_names_seen["$lv_name"]=1
done
log_success "Configuration is valid."

# --- LVM Setup ---
log_info "Starting LVM and storage setup..."
if ! vgdisplay "${VG_NAME}" &>/dev/null; then
    log_warn "Volume Group '${VG_NAME}' not found. It will be created."
    echo -e "${C_YELLOW}===================================================================${C_RESET}"
    echo -e "${C_RED}!!! WARNING: This will destroy all data on ${STORAGE_DISK} !!!${C_RESET}"
    echo -e "${C_YELLOW}===================================================================${C_RESET}"
    read -p "Type 'CONFIRM' to proceed, or any other key to abort: " CONFIRMATION
    if [[ "${CONFIRMATION}" != "CONFIRM" ]]; then echo "Aborted by user."; exit 1; fi

    log_info "Wiping any existing signatures from ${STORAGE_DISK}..."
    wipefs -a "${STORAGE_DISK}"
    log_info "Creating LVM Physical Volume on ${STORAGE_DISK}..."
    pvcreate -f "${STORAGE_DISK}"
    log_info "Creating Volume Group '${VG_NAME}'..."
    vgcreate "${VG_NAME}" "${STORAGE_DISK}"
    log_success "Volume Group '${VG_NAME}' created successfully."
else
    log_info "Volume Group '${VG_NAME}' already exists. Skipping creation."
fi

NFS_ROOT="/srv/nfs"; mkdir -p "${NFS_ROOT}"; chmod 755 "${NFS_ROOT}"

# --- Share Creation Loop ---
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name lv_size mount_point_name _ <<< "${share_info}"
    lv_path="/dev/${VG_NAME}/${lv_name}"
    mount_path="${NFS_ROOT}/${mount_point_name}"

    log_info "Processing share '${mount_point_name}' (LV: ${lv_name})"
    if ! lvdisplay "${lv_path}" &>/dev/null; then
        log_info "  - Creating Logical Volume '${lv_name}' with size ${lv_size}..."
        lvcreate -n "${lv_name}" -L "${lv_size}" "${VG_NAME}"
        log_info "  - Formatting ${lv_path} with ext4 filesystem..."
        mkfs.ext4 "${lv_path}"
    else
        log_info "  - Logical Volume '${lv_name}' already exists. Skipping creation."
    fi

    mkdir -p "${mount_path}"
    if ! grep -q -w "${mount_path}" /etc/fstab; then
        UUID=$(blkid -s UUID -o value "${lv_path}")
        log_info "  - Adding entry to /etc/fstab for ${mount_path}..."
        echo "UUID=${UUID} ${mount_path} ext4 defaults 0 0" >> /etc/fstab
    else
        log_info "  - fstab entry for ${mount_path} already exists. Skipping."
    fi
done

log_info "Mounting all filesystems defined in /etc/fstab..."
mount -a
