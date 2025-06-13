#!/bin/bash
# /root/nfs_setup/modules/02_setup_storage.sh

set -euo pipefail

echo "--> Starting LVM and storage setup..."

# Create the main NFS root directory if it doesn't exist
NFS_ROOT="/srv/nfs"
mkdir -p "${NFS_ROOT}"
chmod 755 "${NFS_ROOT}"

if [[ ${#NFS_SHARES[@]} -eq 0 ]]; then
    cat <<'EOF'
==================================================================
!!! WARNING: No NFS shares are configured in nfs_config.conf. !!!
------------------------------------------------------------------
To create shares:
1. Edit the NFS_SHARES array in nfs_config.conf
   Example:
   NFS_SHARES=(
     "sssd_share;20G;sssd_share"
     "public_share;5G;public"
   )
2. Re-run ./main_setup.sh
==================================================================
EOF
    exit 0
fi

# Disk and VG setup (assume disk is already checked for safety in main script)
if ! pvs "${STORAGE_DISK}" &>/dev/null; then
    echo "==================================================================="
    echo "!!! WARNING !!!"
    echo "This script is about to partition and format the disk: ${STORAGE_DISK}"
    echo "ALL DATA ON THIS DISK WILL BE DESTROYED."
    echo "==================================================================="
    read -rp "Type 'CONFIRM' to proceed, or any other key to abort: " confirm
    if [[ "${confirm}" != "CONFIRM" ]]; then
        echo "Aborted by user."
        exit 1
    fi
    echo "--> Creating LVM Physical Volume on ${STORAGE_DISK}..."
    pvcreate -f "${STORAGE_DISK}"
    echo "--> Creating Volume Group '${VG_NAME}'..."
    vgcreate "${VG_NAME}" "${STORAGE_DISK}"
fi

mount -a

# Loop through the shares defined in the config file
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name lv_size mount_point_name <<<"${share_info}"
    lv_path="/dev/${VG_NAME}/${lv_name}"
    mount_path="${NFS_ROOT}/${mount_point_name}"

    echo "--> Processing share: ${lv_name}"

    if lvdisplay "${lv_path}" &>/dev/null; then
        echo "    - Logical Volume '${lv_name}' already exists. Skipping creation."
    else
        echo "    - Creating Logical Volume '${lv_name}' with size ${lv_size}..."
        lvcreate -n "${lv_name}" -L "${lv_size}" "${VG_NAME}"
        mkfs.ext4 "${lv_path}"
    fi

    mkdir -p "${mount_path}"
    if ! grep -q -F "${lv_path} ${mount_path}" /etc/fstab; then
        echo "${lv_path} ${mount_path} ext4 defaults 0 2" >> /etc/fstab
    fi
    mount "${mount_path}"
done

echo "--> Setting base ownership for NFS root..."
chown root:root "${NFS_ROOT}"

echo "--> Verifying mounts:"
df -h | grep "${NFS_ROOT}"

echo "--> LVM and storage setup complete."
