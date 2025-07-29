#!/bin/bash
set -euo pipefail

# --- Logging & Helper Functions ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_fatal() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; exit 1; }

source "$1" # Load Configuration

# =========================== Function: Enlarge a Share ============================
enlarge_share() {
    log_info "Select a share to enlarge:"
    # THE FIX IS HERE: Piping to awk trims the leading whitespace from lvs output.
    mapfile -t lvs_list < <(lvs --noheadings -o lv_name "${VG_NAME}" | awk '{print $1}')
    
    select lv_name in "${lvs_list[@]}"; do
        if [[ -n "$lv_name" ]]; then break; else log_warn "Invalid selection."; fi
    done
    
    local lv_path="/dev/${VG_NAME}/${lv_name}"
    log_info "Selected share: ${C_YELLOW}${lv_name}${C_RESET}"
    echo "--- Current Status ---"; lvs --units g "${lv_path}"; vgs --units g "${VG_NAME}"; echo "----------------------"
    
    read -p "Enter the amount of space to ADD (e.g., +10G, +500M): " size_to_add
    if ! [[ "${size_to_add}" =~ ^\+ ]]; then log_fatal "Invalid format. Must start with '+'."; fi

    read -p "This will add ${size_to_add} to ${lv_name}. Continue? (y/N): " confirm
    if [[ "${confirm,,}" != "y" ]]; then log_info "Operation cancelled."; return; fi

    lvextend -r -L "${size_to_add}" "${lv_path}"
    log_success "Share '${lv_name}' successfully enlarged."
}

# =========================== Function: Shrink a Share =============================
shrink_share() {
    echo -e "${C_RED}============================= DANGER ============================="
    log_warn "Shrinking a filesystem is an OFFLINE and RISKY operation."
    log_warn "The selected share will be UNMOUNTED and UNAVAILABLE during this process."
    echo -e "${C_RED}==================================================================${C_RESET}"
    
    log_info "Select a share to shrink:";
    # THE FIX IS HERE: Piping to awk trims the leading whitespace.
    mapfile -t lvs_list < <(lvs --noheadings -o lv_name "${VG_NAME}" | awk '{print $1}')
    
    select lv_name in "${lvs_list[@]}"; do
        if [[ -n "$lv_name" ]]; then break; else log_warn "Invalid selection."; fi
    done
    
    local lv_path="/dev/${VG_NAME}/${lv_name}"
    local mount_point; mount_point=$(findmnt -n -S "${lv_path}" -o TARGET)
    if [[ -z "$mount_point" ]]; then log_fatal "Could not find mount point for ${lv_name}."; fi
    
    log_info "Selected: ${C_YELLOW}${lv_name}${C_RESET} mounted at ${C_YELLOW}${mount_point}${C_RESET}"
    echo "--- Current Status ---"; lvs --units g "${lv_path}"; echo "----------------------"
    read -p "Enter the NEW TOTAL size for the share (e.g., 80G, 1.5T): " new_total_size
    
    read -p "Type 'I UNDERSTAND THE RISK' to proceed: " confirm
    if [[ "${confirm}" != "I UNDERSTAND THE RISK" ]]; then log_info "Operation cancelled."; return; fi

    log_info "Unmounting filesystem..."; umount "${mount_point}"
    log_info "Forcing filesystem check..."; e2fsck -f "${lv_path}"
    log_info "Shrinking filesystem..."; resize2fs "${lv_path}" "${new_total_size}"
    log_info "Shrinking Logical Volume..."; lvreduce -L "${new_total_size}" "${lv_path}" --yes
    log_info "Remounting and re-extending filesystem to fill volume..."; mount "${mount_point}"; resize2fs "${lv_path}"
    log_success "Share '${lv_name}' successfully shrunk."
}

# =========================== Function: Move a Share ===============================
find_unused_disks() { lsblk -dno NAME,TYPE | grep "disk" | awk '{print "/dev/"$1}' | xargs -I{} sh -c '! lsblk -no FSTYPE {} | grep -q . && echo {}'; }

move_share() {
    log_warn "This module moves a share (Logical Volume) to a new, unused disk."
    log_warn "This is a safe ONLINE operation, but can take a long time."
    
    log_info "Step 1: Select a share to move:"
    # THE FIX IS HERE: Piping to awk trims the leading whitespace.
    mapfile -t lvs_list < <(lvs --noheadings -o lv_name "${VG_NAME}" | awk '{print $1}')
    select lv_to_move in "${lvs_list[@]}"; do if [[ -n "$lv_to_move" ]]; then break; fi; done
    
    local lv_path="/dev/${VG_NAME}/${lv_to_move}"
    local lv_size_bytes; lv_size_bytes=$(lvs --noheadings --units b -o lv_size "${lv_path}" | tr -d '[:space:]' | cut -d'B' -f1)

    log_info "Step 2: Select an unused destination disk:"
    mapfile -t unused_disks < <(find_unused_disks)
    if [[ ${#unused_disks[@]} -eq 0 ]]; then log_fatal "No unused disks found."; fi
    select new_device_path in "${unused_disks[@]}"; do if [[ -n "$new_device_path" ]]; then break; fi; done
    
    local disk_size_bytes; disk_size_bytes=$(lsblk -b -d -n -o SIZE "${new_device_path}")
    if (( disk_size_bytes < lv_size_bytes )); then
        log_fatal "Destination disk is too small. Required: ${lv_size_bytes}B, Available: ${disk_size_bytes}B"
    fi

    echo -e "${C_YELLOW}================== MOVE OPERATION SUMMARY ==================${C_RESET}"
    echo "  - Share to move:      ${C_GREEN}${lv_to_move}${C_RESET}"
    echo "  - Destination Disk:   ${C_GREEN}${new_device_path}${C_RESET} (will be added to VG: ${VG_NAME})"
    echo -e "${C_YELLOW}===========================================================${C_RESET}"
    read -p "Type 'PROCEED WITH MOVE' to start this operation: " confirm
    if [[ "${confirm}" != "PROCEED WITH MOVE" ]]; then log_info "Operation cancelled."; return; fi

    log_info "Adding ${new_device_path} to the Volume Group..."; pvcreate "${new_device_path}"; vgextend "${VG_NAME}" "${new_device_path}"
    log_info "Starting online data migration with 'pvmove'. This can take a long time..."; pvmove -n "${lv_to_move}" "${new_device_path}"
    log_success "Data migration for '${lv_to_move}' is complete!"
    
    local old_pv_name; old_pv_name=$(pvs --noheadings -o pv_name,lv_name | grep "${lv_to_move}" | awk '{print $1}')
    read -p "Do you want to safely remove the old disk (${old_pv_name}) from the Volume Group? (y/N): " cleanup
    if [[ "${cleanup,,}" == "y" ]]; then
        log_info "Removing old Physical Volume ${old_pv_name} from VG..."; vgreduce "${VG_NAME}" "${old_pv_name}"; pvremove "${old_pv_name}"
        log_success "Old disk removed. It can now be physically detached."
    fi
}

# =========================== Main Management Menu ==============================
while true; do
    echo; echo -e "${C_YELLOW}=============== Storage Management Module ===============${C_RESET}"
    echo "  1) Enlarge a Share (Safe, No Downtime)"
    echo "  2) Shrink a Share (Risky, Requires Downtime)"
    echo "  3) Move a Share to a New Disk (Safe, No Downtime)"
    echo "  Q) Return to Main Menu"
    echo -e "${C_YELLOW}=======================================================${C_RESET}"
    read -p "Enter your choice: " choice

    case $choice in
        1) enlarge_share ;;
        2) shrink_share ;;
        3) move_share ;;
        [qQ]) log_info "Exiting Storage Management."; break ;;
        *) log_warn "Invalid option." ;;
    esac
done
