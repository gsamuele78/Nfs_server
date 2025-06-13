#!/bin/bash
# /root/nfs_setup/modules/04_configure_time.sh

# Exit on error
set -euo pipefail
# This module currently doesn't use the config, but we load it for consistency.
source "$1"



echo "--> Configuring time synchronization with chrony..."

echo "--> Enabling and starting chrony service..."
systemctl enable --now chrony

# Wait a moment for chrony to sync
echo "--> Waiting for 10 seconds for chrony to establish connections..."
sleep 10

echo "--> Checking chrony synchronization status..."
if chronyc sources | grep -q '^*'; then
    echo "    - SUCCESS: Chrony is synchronized with a time source."
    chronyc sources
else
    echo "    - WARNING: Chrony is not yet synchronized. This may take a few minutes."
    echo "    - Current status:"
    chronyc sources
fi

echo "--> Time synchronization setup complete."


#!/bin/bash
set -euo pipefail

