#!/bin/bash
# /root/nfs_setup/modules/01_install_packages.sh

# Exit on error
set -euo pipefail

echo "--> Updating package lists..."
apt-get update

echo "--> Installing required packages: nfs-kernel-server, lvm2, qemu-guest-agent, chrony, ufw..."
apt-get install -y nfs-kernel-server lvm2 qemu-guest-agent chrony ufw

echo "--> Ensuring QEMU Guest Agent is enabled and running..."
systemctl enable --now qemu-guest-agent

echo "--> Package installation complete."
