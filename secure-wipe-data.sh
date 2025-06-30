#!/bin/bash

# ==============================================================================
# SECURE DATA WIPE SCRIPT - OPTIMIZED VERSION
# Author: Based on a script by xnet-vn and refined by Copilot
#
# WARNING: This script will IRREVERSIBLY DESTROY ALL DATA!
# Only run on servers that are being decommissioned.
# ==============================================================================

# Safe script execution settings
set -e  # Exit immediately if a command exits with a non-zero status.
set -o pipefail # A pipeline will return the exit status of the last command to exit with a non-zero status.

# Global variables
LOG_FILE="/tmp/secure_wipe_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG_FILE="/tmp/secure_wipe_errors_$(date +%Y%m%d_%H%M%S).log"

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- UTILITY FUNCTIONS ---

# Logging function (outputs to both console and log file)
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Logs command errors to a separate file for debugging
log_command_error() {
    local command_name=$1
    log_warning "Command '$command_name' may have failed or was not applicable. See error log for details: $ERROR_LOG_FILE"
}

# Checks for root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo). Aborting."
        exit 1
    fi
}

# Safer user confirmation
confirm_action() {
    log_warning "========================================================="
    log_warning "  WARNING: THIS OPERATION WILL ERASE ALL DATA"
    log_warning "           AND CANNOT BE UNDONE!"
    log_warning "========================================================="
    
    local random_string
    random_string=$(head /dev/urandom | tr -dc 'A-Z0-9' | head -c 6)
    
    echo -e "\nTo confirm, please type the following string exactly: ${YELLOW}${random_string}${NC}"
    read -r -p "> " confirmation
    
    if [[ "$confirmation" != "$random_string" ]]; then
        log_info "Invalid confirmation. Operation cancelled."
        exit 0
    fi
    
    read -r -p "Are you 100% sure you want to continue? (yes/no): " final_confirm
    if [[ "$final_confirm" != "yes" ]]; then
        log_info "Operation cancelled."
        exit 0
    fi
}

# --- DATA WIPE FUNCTIONS ---

# Installs necessary tools
install_tools() {
    log_info "Checking for and installing necessary tools..."
    export DEBIAN_FRONTEND=noninteractive
    
    apt-get update -qq -o Dpkg::Use-Pty=0 >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
    
    # List of required packages
    packages=(
        secure-delete wipe shred cryptsetup-bin coreutils dcfldd
        scrub bleachbit zerofree hdparm smartmontools nvme-cli
        sg3-utils util-linux parted gdisk nwipe build-essential
        autotools-dev autoconf pkg-config libncurses5-dev libparted-dev git
    )
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            log_info "Installing $pkg..."
            apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_warning "Failed to install $pkg."
        fi
    done
}

# Stops critical services
stop_services() {
    log_info "Stopping system services..."
    services=(
        apache2 nginx mysql mariadb postgresql docker containerd 
        redis-server mongodb elasticsearch rabbitmq-server memcached cron
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            systemctl stop "$service" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true
        fi
    done
    # Ensure processes have time to terminate
    sleep 5
}

# Clears RAM and SWAP
clear_memory_and_swap() {
    log_info "Clearing data from RAM and SWAP..."
    
    # Disable and overwrite swap devices/files
    for swap_device in $(swapon --show=NAME --noheadings); do
        log_info "Disabling and wiping swap: $swap_device"
        swapoff "$swap_device" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
        if [[ -b "$swap_device" ]]; then # If it's a block device
            shred -n 2 -z "$swap_device" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "shred on $swap_device"
        elif [[ -f "$swap_device" ]]; then # If it's a file
             shred -n 2 -z "$swap_device" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "shred on $swap_device"
             rm -f "$swap_device"
        fi
    done
    
    # Clear RAM caches
    echo 3 > /proc/sys/vm/drop_caches
}

# This function performs the entire wipe process for a SINGLE disk
wipe_single_disk() {
    local disk=$1
    log_info "Starting multi-layered wipe process for disk: $disk"

    # --- Stage 1: Hardware-based Erase (if supported) ---
    log_info "[$disk] Step 1/4: Attempting Hardware Secure Erase..."
    if [[ "$disk" =~ "nvme" ]] && command -v nvme >/dev/null 2>&1; then
        nvme format "$disk" --ses=1 --force >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
        nvme format "$disk" --ses=2 --force >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
        log_warning "[$disk] NVMe Secure Erase failed or is not supported."
    elif command -v hdparm >/dev/null 2>&1; then
        # Attempt to unfreeze the drive if necessary
        hdparm --user-master u --security-set-pass p "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true
        if hdparm -I "$disk" | grep -q "frozen"; then
            log_warning "[$disk] Drive is in a 'frozen' state. A reboot or sleep cycle is required to unfreeze. Skipping ATA Secure Erase."
        else
            hdparm --user-master u --security-set-pass p "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true
            timeout 7200 hdparm --user-master u --security-erase-enhanced p "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
            timeout 7200 hdparm --user-master u --security-erase p "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
            log_warning "[$disk] ATA Secure Erase failed or is not supported."
        fi
    fi

    # --- Stage 2: DoD 5220.22-M Standard Wipe with nwipe ---
    log_info "[$disk] Step 2/4: Performing DoD 5220.22-M wipe with nwipe..."
    if command -v nwipe >/dev/null 2>&1; then
        nwipe --method=dod522022m --rounds=1 --nogui --force "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "nwipe on $disk"
    else
        log_warning "[$disk] nwipe command not found. Skipping this step."
    fi

    # --- Stage 3: Multi-pass Overwrite with dd ---
    log_info "[$disk] Step 3/4: Overwriting with multiple patterns..."
    log_info "[$disk] - Overwriting with random data (Pass 1/3)..."
    dd if=/dev/urandom of="$disk" bs=4M status=none oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd random on $disk"
    log_info "[$disk] - Overwriting with zeros (Pass 2/3)..."
    dd if=/dev/zero of="$disk" bs=4M status=none oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd zero on $disk"
    log_info "[$disk] - Overwriting with random data (Pass 3/3)..."
    dd if=/dev/urandom of="$disk" bs=4M status=none oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd random on $disk"

    # --- Stage 4: Destroy Disk Structure ---
    log_info "[$disk] Step 4/4: Destroying partition table and metadata..."
    # Wipe the beginning and end of the disk
    dd if=/dev/zero of="$disk" bs=1M count=100 oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd zero start of $disk"
    dd if=/dev/zero of="$disk" bs=1M count=100 seek=$(( $(blockdev --getsize64 "$disk") / 1048576 - 100 )) oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd zero end of $disk"
    # Erase LUKS headers if they exist
    cryptsetup erase "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true
    
    log_info "COMPLETED SECURE WIPE FOR DISK: $disk"
}

# Final verification step
final_verification() {
    local disks=$1
    log_info "=============== PERFORMING FINAL VERIFICATION ==============="
    
    for disk in $disks; do
        if [[ -b "$disk" ]]; then
            log_info "Randomly sampling data sectors on $disk..."
            local disk_size_bytes
            disk_size_bytes=$(blockdev --getsize64 "$disk" 2>/dev/null || echo "0")
            
            echo "--- Data sample from start of disk $disk ---"
            hexdump -n 512 -C "$disk" | tee -a "$LOG_FILE"
            
            if (( disk_size_bytes > 2 * 1024 * 1024 )); then
                 echo "--- Data sample from middle of disk $disk ---"
                 local middle_offset=$(( disk_size_bytes / 2 ))
                 dd if="$disk" bs=1 skip=$middle_offset count=512 status=none | hexdump -C | tee -a "$LOG_FILE"
            fi
            
            echo "--- Data sample from end of disk $disk ---"
            dd if="$disk" bs=512 skip=$(( $(blockdev --getsz "$disk") - 1 )) count=1 status=none | hexdump -C | tee -a "$LOG_FILE"
        fi
    done
}


# --- MAIN ORCHESTRATION FUNCTION ---
main() {
    # Self-protection: copy the script to /tmp and lock it
    local self_path
    self_path=$(readlink -f "$0")
    local safe_path="/tmp/$(basename "$self_path").$RANDOM"
    cp "$self_path" "$safe_path"
    chmod 400 "$safe_path"
    
    # Start logging
    echo "Secure wipe process initiated at $(date)" > "$LOG_FILE"
    echo "----------------------------------------------------" >> "$LOG_FILE"
    
    check_root
    confirm_action
    
    log_info "Starting data destruction process in 10 seconds... (Press Ctrl+C to cancel)"
    sleep 10

    # === STAGE 1: SYSTEM PREPARATION ===
    install_tools
    stop_services
    clear_memory_and_swap
    
    # === STAGE 2: PARALLEL DISK WIPING ===
    log_info "Detecting physical disks (sata, nvme, scsi, vd)..."
    # Get the list of disks once
    local disks_to_wipe
    disks_to_wipe=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" {print $1}')

    if [ -z "$disks_to_wipe" ]; then
        log_error "No physical disks found to wipe. Aborting."
        exit 1
    fi
    log_info "The following disks will be completely WIPED: $disks_to_wipe"
    
    local pids=()
    for disk in $disks_to_wipe; do
        # Run the wipe function for each disk in a background process
        wipe_single_disk "$disk" &
        pids+=($!) # Store the PID of the background process
    done
    
    log_info "Waiting for all parallel wipe tasks to complete... (This will take a very long time)"
    # Wait for all background processes to finish
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    log_info "All parallel wipe tasks have been completed."

    # === STAGE 3: VERIFICATION AND COMPLETION ===
    final_verification "$disks_to_wipe"
    
    # Create final report
    log_info "Generating completion report..."
    {
        echo "WIPE COMPLETION REPORT - $(date)"
        echo "====================================="
        echo "Wiped Disks: $disks_to_wipe"
        echo "Methods Applied (per disk):"
        echo "- Hardware Secure Erase (ATA/NVMe, if available)"
        echo "- DoD 5220.22-M Standard Wipe (via nwipe)"
        echo "- Multi-pass Overwrite (random/zero patterns via dd)"
        echo "- Partition Table and Metadata Destruction"
        echo "====================================="
        echo "Log file is available at: $LOG_FILE"
        echo "Error log is available at: $ERROR_LOG_FILE"
    } | tee /tmp/wipe_report.txt
    
    log_info "=========================================================="
    log_info "  SECURE DATA WIPE COMPLETED!"
    log_info "  The server will automatically reboot in 60 seconds."
    log_info "=========================================================="
    
    sleep 60
    reboot
}

# Execute the main function
main "$@"
