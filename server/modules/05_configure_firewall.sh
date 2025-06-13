#!/bin/bash
set -euo pipefail

# THE CRITICAL FIX: Add full logging definitions to make this module self-contained.
# --- Logging & Tracking ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_fatal() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; exit 1; }

# --- Load Configuration ---
if [[ -z "$1" ]]; then log_fatal "Config file path not provided."; fi
source "$1"
# MANIFEST_FILE ($2) is passed but not used in this module.

log_info "Configuring firewall with UFW..."
NFS_PORT="2049"

for client_net in ${ALLOWED_CLIENTS}; do
    log_info "Allowing NFS traffic (TCP port ${NFS_PORT}) from ${client_net}..."
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
