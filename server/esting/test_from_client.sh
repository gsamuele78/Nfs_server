#!/bin/bash
# /root/nfs_setup/testing/test_from_client.sh
# --- Script to be run on a client machine to test the NFS server ---

set -e

# --- Configuration ---
NFS_SERVER_IP="<your_nfs_server_ip>" # !!! EDIT THIS !!!
SSSD_SHARE_NAME="sssd_share"      # Must match a name from nfs_config.conf
PUBLIC_SHARE_NAME="public"        # Must match a name from nfs_config.conf

MOUNT_POINT_BASE="/mnt/nfs_test"

# --- Pre-flight Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

if [[ "${NFS_SERVER_IP}" == "<your_nfs_server_ip>" ]]; then
    echo "ERROR: Please edit this script and set the NFS_SERVER_IP variable."
    exit 1
fi

echo "--> Installing NFS client tools..."
apt-get update
apt-get install -y nfs-common

echo "--> Pinging the NFS server to check network connectivity..."
ping -c 3 "${NFS_SERVER_IP}"

echo "--> Creating local mount points..."
mkdir -p "${MOUNT_POINT_BASE}/${SSSD_SHARE_NAME}"
mkdir -p "${MOUNT_POINT_BASE}/${PUBLIC_SHARE_NAME}"

# --- Mounting ---
echo "--> Mounting the SSSD-aware share: ${SSSD_SHARE_NAME}"
mount -t nfs4 "${NFS_SERVER_IP}:/${SSSD_SHARE_NAME}" "${MOUNT_POINT_BASE}/${SSSD_SHARE_NAME}"

echo "--> Mounting the public share: ${PUBLIC_SHARE_NAME}"
mount -t nfs4 "${NFS_SERVER_IP}:/${PUBLIC_SHARE_NAME}" "${MOUNT_POINT_BASE}/${PUBLIC_SHARE_NAME}"

echo "--> Verifying mounts:"
df -h | grep "${NFS_SERVER_IP}"

# --- Testing Permissions ---
echo "--> Performing write tests..."

# Test 1: SSSD Share (should succeed if you are logged in as an SSSD user)
SSSD_TEST_FILE="${MOUNT_POINT_BASE}/${SSSD_SHARE_NAME}/test_by_${USER}_$(date +%s).txt"
echo "--> Writing to SSSD share as user ${USER}..."
touch "${SSSD_TEST_FILE}"
echo "Test file created on SSSD share: ${SSSD_TEST_FILE}"
ls -l "${SSSD_TEST_FILE}"
rm "${SSSD_TEST_FILE}"
echo "Cleaned up test file."

# Test 2: Public Share (should succeed, and file should be owned by nfsnobody)
PUBLIC_TEST_FILE="${MOUNT_POINT_BASE}/${PUBLIC_SHARE_NAME}/test_by_${USER}_$(date +%s).txt"
echo "--> Writing to public share as user ${USER}..."
touch "${PUBLIC_TEST_FILE}"
echo "Test file created on public share: ${PUBLIC_TEST_FILE}"
echo "Verifying ownership (should be nfsnobody or similar):"
ls -l "${PUBLIC_TEST_FILE}"
rm "${PUBLIC_TEST_FILE}"
echo "Cleaned up test file."

# --- Cleanup ---
echo "--> Unmounting test shares..."
umount "${MOUNT_POINT_BASE}/${SSSD_SHARE_NAME}"
umount "${MOUNT_POINT_BASE}/${PUBLIC_SHARE_NAME}"
rm -rf "${MOUNT_POINT_BASE}"

echo "### NFS Client Test Completed Successfully! ###"
