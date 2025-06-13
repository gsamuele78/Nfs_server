#!/bin/bash
# shellcheck disable=SC2128
set -euo pipefail

echo "--> Configuring NFS server..."
sed -i "s/^RPCNFSDCOUNT=.*/RPCNFSDCOUNT=${NFS_THREAD_COUNT}/" /etc/default/nfs-kernel-server
sed -i "s/^#Domain = .*/Domain = ${NFS_DOMAIN}/" /etc/idmapd.conf
sed -i "s/^#Nobody-User = .*/Nobody-User = nfsnobody/" /etc/idmapd.conf
sed -i "s/^#Nobody-Group = .*/Nobody-Group = nfsnobody/" /etc/idmapd.conf

NFS_ROOT="/srv/nfs"
EXPORTS_FILE="/etc/exports"
# Configure NFSv4 pseudo-filesystem root
if ! grep -q -w "${NFS_ROOT} /export" /etc/fstab; then
    mkdir -p /export
    echo "${NFS_ROOT} /export none bind 0 0" >> /etc/fstab
fi

# Create exports file from scratch
{
  echo "# /etc/exports - This file is managed by the nfs_setup script."
  echo "# NFSv4 pseudo-filesystem root"
  echo "/export ${ALLOWED_CLIENTS}(ro,sync,no_subtree_check,fsid=0)"
  echo ""
} > "${EXPORTS_FILE}"

# Add entries for each share based on its configured TYPE
for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r _ _ mount_point_name share_type <<< "${share_info}"
    mount_path="${NFS_ROOT}/${mount_point_name}"
    export_path="/export/${mount_point_name}"
    
    mkdir -p "${export_path}"
    if ! grep -q -w "${mount_path} ${export_path}" /etc/fstab; then
        echo "${mount_path} ${export_path} none bind 0 0" >> /etc/fstab
    fi

    echo "--> Adding export for '${mount_point_name}' with type '${share_type}'"
    # Use the explicit share_type to configure security options
    if [[ "${share_type}" == "sssd" ]]; then
        echo "${export_path} ${ALLOWED_CLIENTS}(rw,sync,no_subtree_check,sec=sys)" >> "${EXPORTS_FILE}"
        chown root:root "${mount_path}"
        chmod 1777 "${mount_path}" # Sticky bit for multi-user collaboration
    else # Default to "public"
        if ! id "nfsnobody" &>/dev/null; then useradd -r -s /usr/sbin/nologin nfsnobody; fi
        ANON_UID=$(id -u nfsnobody); ANON_GID=$(id -g nfsnobody)
        echo "${export_path} ${ALLOWED_CLIENTS}(rw,sync,no_subtree_check,all_squash,anonuid=${ANON_UID},anongid=${ANON_GID})" >> "${EXPORTS_FILE}"
        chown nfsnobody:nfsnobody "${mount_path}"; chmod 770 "${mount_path}"
    fi
done

mount -a
exportfs -ra
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server
echo "--> NFS configuration complete."
