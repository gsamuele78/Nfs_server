#!/bin/bash
# /root/nfs_setup/modules/05_configure_firewall.sh

# Exit on error
set -euo pipefail

echo "--> Configuring firewall with UFW..."

# The 'ufw allow from' rules are more specific and secure
for client_net in ${ALLOWED_CLIENTS}; do
    echo "--> Allowing 'NFS' traffic from ${client_net}..."
    ufw allow from "${client_net}" to any app NFS
done

echo "--> Allowing 'OpenSSH' traffic..."
ufw allow OpenSSH

# Check if UFW is active. If not, enable it with a prompt.
if ! ufw status | grep -q "Status: active"; then
    echo "==================================================================="
    echo "Firewall (UFW) is about to be enabled."
    echo "This will block all traffic except for SSH and the NFS rules just added."
    echo "==================================================================="
    # The '-f' option in the main script call will bypass this prompt
    read -p "Type 'yes' to enable the firewall: " ENABLE_UFW
    if [[ "${ENABLE_UFW}" == "yes" ]]; then
        ufw enable
        echo "--> Firewall has been enabled."
    else
        echo "--> Firewall not enabled. Please enable it manually with 'ufw enable'."
    fi
else
    echo "--> UFW is already active. Reloading to apply new rules..."
    ufw reload
fi

echo "--> Firewall status:"
ufw status verbose

echo "--> Firewall configuration complete."
