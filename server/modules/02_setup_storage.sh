#!/bin/bash
# /root/nfs_setup/modules/02_setup_storage.sh

# Exit on error
set -euo pipefail

echo "--> Starting LVM and storage setup..."
echo "==================================================================="
echo "!!! WARNING !!!"
echo "This script is about to partition and format the disk: ${STORAGE_DISK}"
echo "ALL DATA ON THIS DISK WILL BE DESTROYED."
echo "==================================================================="
read -p "Type 'CONFIRM' to proceed, or any other key to abort: " CONFIRMATION

if [[ "${CONFIRMATION}" != "CONFIRM" ]]; then
    echo "Aborted by user."
    exit 1
fi

# Check if the volume group already exists
if vgdisplay "${VG_NAME}" &>/dev/null; then
    echo "--> Volume Group '${VG_NAME}' already exists. Skipping LVM creation."
else
    echo "--> Wiping any existing signatures from ${STORAGE_DISK}..."
    wipefs -a "${STORAGE_DISK}"

    echo "--> Creating LVM Physical Volume on ${STORAGE_DISK}..."
    pvcreate -f "${STORAGE_DISK}"

    echo "--> Creating Volume Group '${VG_NAME}'..."
    vgcreate "${VG_NAME}" "${STORAGE_DISK}"
fi

# Create the main NFS root directory if it doesn't exist
NFS_ROOT="/srv/nfs"
mkdir -p "${NFS_ROOT}"
chmod 755 "${NFS_ROOT}"

# Loop through the shares defined in the config file
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name lv_size mount_point_name <<< "${share_info}"
    lv_path="/dev/${VG_NAME}/${lv_name}"
    mount_path="${NFS_ROOT}/${mount_point_name}"

    echo "--> Processing share: ${lv_name}"

    if lvdisplay "${lv_path}" &>/dev/null; then
        echo "    - Logical Volume '${lv_name}' already exists. Skipping creation."
    else
        echo "    - Creating Logical Volume '${lv_name}' with size ${lv_size}..."
        lvcreate -n "${lv_name}" -L "${lv_size}" "${VG_NAME}"
    fi

    # Check if the LV is already formatted
    if ! blkid -s TYPE -o value "${lv_path}"; then
        echo "    - Formatting ${lv_path} with ext4 filesystem..."
        mkfs.ext4 "${lv_path}"
    else
        echo "    - Logical Volume '${lv_name}' is already formatted. Skipping format."
    fi

    # Create mount point directory
    mkdir -p "${mount_path}"

    # Add to /etc/fstab if not already present
    if ! grep -q "${mount_path}" /etc/fstab; then
        echo "    - Adding entry to /etc/fstab..."
        # Using UUID for robustness
        UUID=$(blkid -s UUID -o value "${lv_path}")
        echo "UUID=${UUID} ${mount_path} ext4 defaults 0 0" >> /etc/fstab
    else
        echo "    - Entry for '${mount_path}' already in /etc/fstab. Skipping."
    fi
done

echo "--> Mounting all filesystems defined in /etc/fstab..."
mount -a

echo "--> Setting base ownership for NFS root..."
# This helps prevent issues with 'nobody' ownership later
chown root:root "${NFS_ROOT}"

echo "--> Verifying mounts:"
df -h | grep "${NFS_ROOT}"

echo "--> LVM and storage setup complete."
