#!/bin/bash
set -euo pipefail

# --- Load Configuration ---
if [[ -z "$1" ]]; then
    echo "FATAL: Configuration file path was not provided to this module." >&2
    exit 1
fi
source "$1"

echo "--> Configuring NFS server..."
sed -i "s/^RPCNFSDCOUNT=.*/RPCNFSDCOUNT=${NFS_THREAD_COUNT}/" /etc/default/nfs-kernel-server
sed -i "s/^#Domain = .*/Domain = ${NFS_DOMAIN}/" /etc/idmapd.conf
sed -i "s/^#Nobody-User = .*/Nobody-User = nfsnobody/" /etc/idmapd.conf
sed -i "s/^#Nobody-Group = .*/Nobody-Group = nfsnobody/" /etc/idmapd.conf

NFS_ROOT="/srv/nfs"
EXPORTS_FILE="/etc/exports"
if ! grep -q -w "${NFS_ROOT} /export" /etc/fstab; then
    mkdir -p /export
    echo "${NFS_ROOT} /export none bind 0 0" >> /etc/fstab
fi

{
  echo "# /etc/exports - This file is managed by the nfs_setup script."
  echo "/export ${ALLOWED_CLIENTS}(ro,sync,no_subtree_check,fsid=0)"
  echo ""
} > "${EXPORTS_FILE}"

for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r _ _ mount_point_name share_type <<< "${share_info}"
    mount_path="${NFS_ROOT}/${mount_point_name}"
    export_path="/export/${export_point_name}"

    mkdir -p "${export_path}"
    if ! grep -q -w "${mount_path} ${export_path}" /etc/fstab; then
        echo "${mount_path} ${export_path} none bind 0 0" >> /etc/fstab
    fi

    echo "--> Adding export for '${mount_point_name}' with type '${share_type}'"
    # Note: sec=sys relies on matching user names. SSSD must be configured on client
    # and server for this to work seamlessly with AD users, but the server does
    # not need to be joined to AD for the NFS service itself to run.
    if [[ "${share_type}" == "sssd" ]]; then
        echo "${export_path} ${ALLOWED_CLIENTS}(rw,sync,no_subtree_check,sec=sys)" >> "${EXPORTS_FILE}"
        chown root:root "${mount_path}"
        chmod 1777 "${mount_path}"
    else # "public"
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
