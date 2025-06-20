#!/bin/bash
set -euo pipefail

# --- Logging & Tracking ---
C_RESET='\033[0m'; C_BLUE='\033[0;34m'; log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
track_file() { echo "$1" >> "$MANIFEST_FILE"; }

# --- Load Configuration ---
if [[ -z "$1" ]]; then exit 1; fi
source "$1"
MANIFEST_FILE="$2"

log_info "Configuring NFS kernel server options..."
sed -i "s/^RPCNFSDCOUNT=.*/RPCNFSDCOUNT=${NFS_THREAD_COUNT}/" /etc/default/nfs-kernel-server
track_file "/etc/default/nfs-kernel-server"

log_info "Configuring idmapd.conf with domain '${NFS_DOMAIN}'..."
sed -i "s/^#Domain = .*/Domain = ${NFS_DOMAIN}/" /etc/idmapd.conf
sed -i "s/^#Nobody-User = .*/Nobody-User = nfsnobody/" /etc/idmapd.conf
sed -i "s/^#Nobody-Group = .*/Nobody-Group = nfsnobody/" /etc/idmapd.conf
track_file "/etc/idmapd.conf"

NFS_ROOT="/srv/nfs"
EXPORTS_FILE="/etc/exports"
if ! grep -q -w "${NFS_ROOT} /export" /etc/fstab; then
    log_info "Creating NFSv4 pseudo-filesystem root at /export..."
    mkdir -p /export
    echo "${NFS_ROOT} /export none bind 0 0" >> /etc/fstab
    track_file "/etc/fstab"
fi

{
  echo "# /etc/exports - This file is managed by the nfs_setup script."
  echo "/export ${ALLOWED_CLIENTS}(ro,sync,no_subtree_check,fsid=0)"
  echo ""
} > "${EXPORTS_FILE}"
track_file "/etc/exports"

for share_info in "${NFS_SHARES[@]}"; do
    IFS=';' read -r _ _ mount_point_name share_type <<< "${share_info}"
    mount_path="${NFS_ROOT}/${mount_point_name}"
    export_path="/export/${mount_point_name}"

    mkdir -p "${export_path}"
    if ! grep -q -w "${mount_path} ${export_path}" /etc/fstab; then
        echo "${mount_path} ${export_path} none bind 0 0" >> /etc/fstab
        track_file "/etc/fstab"
    fi

    log_info "Adding export for '${mount_point_name}' with type '${share_type}'"
    if [[ "${share_type}" == "sssd" ]]; then
        echo "${export_path} ${ALLOWED_CLIENTS}(rw,sync,no_subtree_check,sec=sys)" >> "${EXPORTS_FILE}"
        chown root:root "${mount_path}"; chmod 1777 "${mount_path}"
    else
        if ! id "nfsnobody" &>/dev/null; then useradd -r -s /usr/sbin/nologin nfsnobody; fi
        ANON_UID=$(id -u nfsnobody); ANON_GID=$(id -g nfsnobody)
        echo "${export_path} ${ALLOWED_CLIENTS}(rw,sync,no_subtree_check,all_squash,anonuid=${ANON_UID},anongid=${ANON_GID})" >> "${EXPORTS_FILE}"
        chown nfsnobody:nfsnobody "${mount_path}"; chmod 770 "${mount_path}"
    fi
done

log_info "Reloading systemd manager configuration..."
systemctl daemon-reload
log_info "Applying all mount points and NFS exports..."
mount -a && exportfs -ra
log_info "Restarting and enabling NFS services..."
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server
