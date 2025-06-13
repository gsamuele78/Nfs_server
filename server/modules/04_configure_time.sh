#!/bin/bash
set -euo pipefail

# --- Logging Definitions ---
C_RESET='\033[0m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }

# --- Load Configuration ---
source "$1"

log_info "Configuring time synchronization with chrony..."
systemctl enable --now chrony
log_info "Waiting up to 15 seconds for chrony to establish connections..."
sleep 15

log_info "Checking chrony synchronization status..."
# The '^*' indicates the primary sync source.
if chronyc sources | grep -q '^\^\*'; then
    log_success "Chrony is synchronized with a time source."
else
    log_warn "Chrony is not yet fully synchronized. This may take a few more minutes."
fi
echo -e "--- Chrony Status ---\n$(chronyc sources)\n---------------------"
