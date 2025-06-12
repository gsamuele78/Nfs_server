# Create new file: /root/client_setup/modules/02_configure_time.sh

#!/bin/bash
set -euo pipefail

echo "--> Configuring time synchronization with chrony..."

echo "--> Enabling and starting chrony service..."
systemctl enable --now chrony

# Give chrony a moment to start its sync process
echo "--> Waiting for 10 seconds for chrony to establish connections..."
sleep 10

echo "--> Checking chrony synchronization status..."
if chronyc sources | grep -q '^*'; then
    echo "    - SUCCESS: Chrony is synchronized with a time source."
    chronyc sources
elif chronyc sources | grep -q '^?'; then
     echo "    - INFO: Chrony is attempting to sync. This is normal on first run."
     chronyc sources
else
    echo "    - WARNING: Chrony is not yet synchronized. This may take a few minutes."
    echo "    - Current status:"
    chronyc sources
fi

echo "--> Time synchronization setup complete."
