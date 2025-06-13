#!/bin/bash
set -euo pipefail

# --- Logging Definitions ---
C_RESET='\033[0m'; C_BLUE='\033[0;34m'; log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }

# --- Load Configuration ---
if [[ -z "$1" ]]; then exit 1; fi
source "$1"

log_info "Configuring firewall with UFW..."

# Define required ports. NFSv4 only requires TCP port 2049.
NFS_PORT="2049"

# Allow from specified client networks
for client_net in ${ALLOWED_CLIENTS}; do
    log_info "Allowing NFS traffic (TCP port ${NFS_PORT}) from ${client_net}..."
    # Using the port number directly is more robust than relying on the 'NFS' app profile.
    ufw allow from "${client_net}" to any port "${NFS_PORT}" proto tcp comment "NFSv4 access"
done

log_info "Allowing SSH traffic..."
ufw allow OpenSSH

if ! ufw status | grep -q "Status: active"; then
    log_info "Enabling firewall..."
    ufw --force enable
else
    log_info "Firewall is already active. Reloading rules..."
    ufw reload
fi

log_success "Firewall configured."
log_info "--- Final Firewall Status ---"
ufw status verbose
