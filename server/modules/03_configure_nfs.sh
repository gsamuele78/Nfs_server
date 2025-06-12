#!/bin/bash
# /root/nfs_setup/modules/03_configure_nfs.sh

# Exit on error
set -euo pipefail

echo "--> Configuring NFS server..."

# Step 1: Configure /etc/default/nfs-kernel-server for performance
echo "--> Tuning NFS thread count to ${NFS_THREAD_COUNT}..."
sed -i "s/^RPCNFSDCOUNT=.*/RPCNFSDCOUNT=${NFS_THREAD_COUNT}/" /etc/default/nfs-kernel-server

# Step 2: Configure /etc/idmapd.conf for SSSD awareness
echo "--> Configuring domain in /etc/idmapd.conf for SSSD integration..."
sed -i "s/^#Domain = .*/Domain = ${NFS_DOMAIN}/" /etc/idmapd.conf
# Set nfsnobody to prevent mapping issues with unauthenticated users
sed -i "s/^#Nobody-User = .*/Nobody-User = nfsnobody/" /etc/idmapd.conf
sed -i "s/^#Nobody-Group = .*/Nobody-Group = nfsnobody/" /etc/idmapd.conf


# Step 3: Create /etc/exports file
echo "--> Generating /etc/exports configuration..."
NFS_ROOT="/srv/nfs"
EXPORTS_FILE="/etc/exports"

# Create a bind mount for the export root. This is a best practice for NFSv4.
if ! grep -q "${NFS_ROOT} /export" /etc/fstab; then
    echo "--> Setting up NFSv4 pseudo-filesystem root at /export..."
    mkdir -p /export
    echo "${NFS_ROOT} /export none bind 0 0" >> /etc/fstab
    mount -a
fi

# Write the exports file from scratch
{
  echo "# /etc/exports - configuration for NFS server"
  echo "# This file is managed by the nfs_setup script."
  echo ""
  echo "# Define the NFSv4 pseudo-filesystem root"
  echo "/export ${ALLOWED_CLIENTS}(ro,sync,no_subtree_check,fsid=0)"
  echo ""
} > "${EXPORTS_FILE}"

# Add entries for each share
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r lv_name lv_size mount_point_name <<< "${share_info}"
    mount_path="${NFS_ROOT}/${mount_point_name}"
    export_path="/export/${mount_point_name}"

    # Create the bind mount for the individual share
    if ! grep -q "${mount_path} ${export_path}" /etc/fstab; then
        mkdir -p "${export_path}"
        echo "${mount_path} ${export_path} none bind 0 0" >> /etc/fstab
    fi

    echo "--> Adding export entry for ${mount_point_name}..."

    # Example logic: if the share name contains 'sssd', treat it as SSSD-aware.
    if [[ "${mount_point_name}" == *"sssd"* ]]; then
        echo "    - Configuring as SSSD-aware share (sec=sys)."
        # sec=sys is used for SSSD clients. Kerberos (krb5p) is the next security level up.
        echo "${export_path} ${ALLOWED_CLIENTS}(rw,sync,no_subtree_check,sec=sys)" >> "${EXPORTS_FILE}"
        # Set permissions that allow SSSD-managed users/groups to take over.
        # This is a generic start; specific permissions should be set by the admin.
        chown root:root "${mount_path}"
        chmod 1777 "${mount_path}" # Sticky bit allows users to manage their own files
    else
        echo "    - Configuring as public, user-squashing share."
        # all_squash maps all connecting users to the anonuid/anongid.
        # We ensure the nfsnobody user/group exists for this.
        if ! id "nfsnobody" &>/dev/null; then useradd -r -s /usr/sbin/nologin nfsnobody; fi
        ANON_UID=$(id -u nfsnobody)
        ANON_GID=$(id -g nfsnobody)
        echo "${export_path} ${ALLOWED_CLIENTS}(rw,sync,no_subtree_check,all_squash,anonuid=${ANON_UID},anongid=${ANON_GID})" >> "${EXPORTS_FILE}"
        chown nfsnobody:nfsnobody "${mount_path}"
        chmod 770 "${mount_path}"
    fi
done

mount -a # Ensure all new bind mounts are active

echo "--> Applying new export configuration..."
exportfs -ra

echo "--> Restarting and enabling NFS services..."
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

echo "--> NFS configuration complete."
