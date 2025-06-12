#!/bin/bash
# /root/client_setup/modules/01_install_client_packages.sh
set -euo pipefail

echo "--> Updating package lists..."
apt-get update

echo "--> Installing client packages (nfs-common, chrony)..."
# nfs-common provides NFS tools, chrony provides time synchronization
apt-get install -y nfs-common chrony

echo "--> Package installation complete."
