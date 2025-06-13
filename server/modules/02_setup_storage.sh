#!/bin/bash
# shellcheck disable=SC2128 # We are intentionally reading the array this way.
set -euo pipefail

echo "--> Validating NFS_SHARES configuration..."
# --- PRE-FLIGHT CHECK: Ensure all LV_NAMEs are unique ---
declare -A lv_names_seen
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name _ <<< "${share_info}"
    if [[ -n "${lv_names_seen[${lv_name}]}" ]]; then
        echo "ERROR: Duplicate LV_NAME '${lv_name}' found in nfs_config.conf." >&2
        echo "       Every share must have a unique LV_NAME (the first field)." >&2
        exit 1
    fi
    lv_names_seen["${lv_name}"]=1
done
echo "--> Configuration is valid."

echo "--> Starting LVM and storage setup..."
# Only prompt for confirmation if the Volume Group doesn't already exist.
if ! vgdisplay "${VG_NAME}" &>/dev/null; then
    echo "==================================================================="
    echo "!!! WARNING: This script will destroy all data on ${STORAGE_DISK} !!!"
    echo "==================================================================="
    read -p "Type 'CONFIRM' to proceed, or any other key to abort: " CONFIRMATION
    if [[ "${CONFIRMATION}" != "CONFIRM" ]]; then echo "Aborted by user."; exit 1; fi

    wipefs -a "${STORAGE_DISK}"
    pvcreate -f "${STORAGE_DISK}"
    vgcreate "${VG_NAME}" "${STORAGE_DISK}"
fi

NFS_ROOT="/srv/nfs"
mkdir -p "${NFS_ROOT}"
chmod 755 "${NFS_ROOT}"

# Loop through shares to create LVs, format, and configure fstab
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name lv_size mount_point_name _ <<< "${share_info}"
    lv_path="/dev/${VG_NAME}/${lv_name}"
    mount_path="${NFS_ROOT}/${mount_point_name}"

    echo "--> Processing share '${mount_point_name}' (LV: ${lv_name})"

    # Create Logical Volume if it doesn't exist
    if ! lvdisplay "${lv_path}" &>/dev/null; then
        echo "    - Creating Logical Volume '${lv_name}' with size ${lv_size}..."
        lvcreate -n "${lv_name}" -L "${lv_size}" "${VG_NAME}"
        echo "    - Formatting ${lv_path} with ext4 filesystem..."
        mkfs.ext4 "${lv_path}"
    else
        echo "    - Logical Volume '${lv_name}' already exists. Skipping creation."
    fi

    mkdir -p "${mount_path}"
    # Add to fstab if not already present, using robust UUID
    if ! grep -q -w "${mount_path}" /etc/fstab; then
        UUID=$(blkid -s UUID -o value "${lv_path}")
        echo "    - Adding entry to /etc/fstab..."
        echo "UUID=${UUID} ${mount_path} ext4 defaults 0 0" >> /etc/fstab
    fi
done

echo "--> Mounting all filesystems defined in /etc/fstab..."
mount -a

echo "--> Verifying LVM and mount status:"
vgs "${VG_NAME}"
lvs "${VG_NAME}"
df -h | grep "${NFS_ROOT}"

echo "--> LVM and storage setup complete."
