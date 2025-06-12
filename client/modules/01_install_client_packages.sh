#!/bin/bash
# /root/client_setup/modules/01_install_client_packages.sh
set -euo pipefail

echo "--> Updating package lists..."
apt-get update

echo "--> Installing NFS client packages (nfs-common)..."
# nfs-common provides the necessary tools for mounting NFS shares
apt-get install -y nfs-common

echo "--> Package installation complete."
