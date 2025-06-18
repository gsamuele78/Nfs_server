#!/bin/bash
set -euo pipefail

C_BLUE='\033[0;34m'; C_RESET='\033[0m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }

log_info "Updating package lists..."
apt-get update >/dev/null

log_info "Installing client packages (nfs-common, chrony, netcat)..."
# netcat-openbsd provides the 'nc' tool for port checking
apt-get install -y nfs-common chrony netcat-openbsd
