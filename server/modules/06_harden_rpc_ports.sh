#!/bin/bash
set -euo pipefail

# --- Logging & Tracking ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
track_file() { echo "$1" >> "$MANIFEST_FILE"; }

# --- Load Configuration ---
source "$1"
MANIFEST_FILE="$2"

# --- Static Port Definitions ---
STATD_PORT=32765
MOUNTD_PORT=32767
NLOCKMGR_PORT=32768
RPCBIND_PORT=111

log_info "Hardening NFS server by setting static ports for legacy RPC services..."

# Configure /etc/default/nfs-common & nfs-kernel-server
log_info "Configuring static ports in /etc/default/* files..."
sed -i 's/^NEED_STATD=.*/NEED_STATD=yes/' /etc/default/nfs-common
sed -i "s/^STATDOPTS=.*/STATDOPTS=\"--port ${STATD_PORT} --outgoing-port ${STATD_PORT}\"/" /etc/default/nfs-common
sed -i "s/^RPCMOUNTDOPTS=.*/RPCMOUNTDOPTS=\"-p ${MOUNTD_PORT}\"/" /etc/default/nfs-kernel-server
track_file "/etc/default/nfs-common"
track_file "/etc/default/nfs-kernel-server"

# Configure /etc/modprobe.d/lockd.conf
log_info "Setting static port for nlockmgr (lockd): ${NLOCKMGR_PORT}..."
echo "options lockd nlm_tcpport=${NLOCKMGR_PORT} nlm_udpport=${NLOCKMGR_PORT}" > /etc/modprobe.d/lockd.conf
track_file "/etc/modprobe.d/lockd.conf"

# --- Update Firewall (THE CRITICAL FIX IS HERE) ---
log_info "Updating UFW firewall rules for new static ports (TCP & UDP)..."
for client_net in ${ALLOWED_CLIENTS}; do
    # By not specifying 'proto', UFW applies the rule to BOTH TCP and UDP.
    ufw allow from "${client_net}" to any port ${RPCBIND_PORT} comment "NFS RPC"
    ufw allow from "${client_net}" to any port ${STATD_PORT} comment "NFS statd"
    ufw allow from "${client_net}" to any port ${MOUNTD_PORT} comment "NFS mountd"
    ufw allow from "${client_net}" to any port ${NLOCKMGR_PORT} comment "NFS lockmgr"
done
ufw reload

log_info "Applying changes requires a service restart..."
systemctl restart nfs-kernel-server
systemctl restart rpcbind

log_success "NFS RPC services have been hardened to use static ports."
echo -e "${C_YELLOW}=========================== Verification ===========================${C_RESET}"
echo "You can verify the ports are correctly registered by running this"
echo "command from a client machine:"
echo -e "${C_GREEN}rpcinfo -p ${NFS_SERVER_IP}${C_RESET}"
echo "Look for 'mountd', 'nlockmgr', and 'status' using the new ports."
echo -e "${C_YELLOW}==================================================================${C_RESET}"
