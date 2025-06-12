#!/bin/bash
# /root/client_setup/modules/03_run_tests.sh
set -euo pipefail

echo "--> Starting live tests on mounted shares..."

for share in "${SHARES_TO_MOUNT[@]}"; do
    local_mount_path="${MOUNT_POINT_BASE}/${share}"
    test_file="${local_mount_path}/.client_test_$(hostname)_$(date +%s)"

    echo "--> Testing share: ${share} at ${local_mount_path}"

    # Verify it is actually a mount point
    if ! mountpoint -q "${local_mount_path}"; then
        echo "    - ERROR: ${local_mount_path} is not a mount point. Check server or firewall."
        exit 1
    fi
    echo "    - Verified as a mount point."

    # Perform a write test
    echo "    - Performing write/read/delete test..."
    if touch "${test_file}"; then
        echo "      - Write successful."
        # Verify file exists and capture details
        ls -l "${test_file}"
        rm "${test_file}"
        echo "      - Cleanup successful."
    else
        echo "    - ERROR: Write test failed for share '${share}'. Check server-side export permissions."
        exit 1
    fi
done

echo "--> All tests passed successfully."
