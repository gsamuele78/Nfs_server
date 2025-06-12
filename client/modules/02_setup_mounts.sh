#!/bin/bash
# /root/client_setup/modules/02_setup_mounts.sh
set -euo pipefail

echo "--> Configuring persistent mounts in /etc/fstab..."

# Create the base directory for all mounts if it doesn't exist
echo "--> Ensuring base mount directory exists: ${MOUNT_POINT_BASE}"
mkdir -p "${MOUNT_POINT_BASE}"

# Check network connectivity before proceeding
echo "--> Pinging the NFS server at ${NFS_SERVER_IP}..."
if ! ping -c 2 "${NFS_SERVER_IP}"; then
    echo "ERROR: NFS Server is not reachable. Aborting."
    exit 1
fi

for share in "${SHARES_TO_MOUNT[@]}"; do
    local_mount_path="${MOUNT_POINT_BASE}/${share}"
    remote_mount_path="${NFS_SERVER_IP}:/${share}"

    echo "--> Processing share: ${share}"

    echo "    - Ensuring local mount point exists: ${local_mount_path}"
    mkdir -p "${local_mount_path}"

    # Check if the mount is already configured in fstab to make script re-runnable
    if grep -q "${remote_mount_path} ${local_mount_path}" /etc/fstab; then
        echo "    - fstab entry already exists. Skipping."
    else
        echo "    - Adding entry to /etc/fstab..."
        # Explanation of options:
        #   nfs4:       Use the NFSv4 protocol.
        #   auto:       Mount the filesystem at boot time.
        #   nofail:     CRITICAL! Prevents the client from hanging during boot if the NFS server is unavailable.
        #   _netdev:    Tells the system this is a network device and to wait for networking before mounting.
        #   defaults:   A standard set of options (rw, suid, dev, exec, auto, nouser, async).
        fstab_entry="${remote_mount_path} ${local_mount_path} nfs4 defaults,auto,nofail,_netdev 0 0"
        echo "${fstab_entry}" >> /etc/fstab
    fi
done

echo "--> Reloading systemd manager configuration to recognize new fstab entries..."
systemctl daemon-reload

echo "--> Attempting to mount all newly configured NFS filesystems..."
# The -t nfs4 flag ensures we only try to mount our new shares
mount -a -t nfs4

echo "--> Mount setup complete."
