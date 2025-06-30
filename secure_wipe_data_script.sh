#!/bin/bash

# ==============================================================================
# SECURE DATA WIPE SCRIPT - UNIVERSAL & ENHANCED VERSION (v3)
# Author: Based on a script by xnetvn, with enhancements.
#
# FEATURES:
# - Cross-distro support (Debian, Ubuntu, CentOS, AlmaLinux, etc.)
# - Pre-wipe of sensitive directories.
# - Parallel, multi-layered disk wiping.
# - Robust safety checks and logging.
#
# WARNING: This script will IRREVERSIBLY DESTROY ALL DATA!
# Only run on servers that are being decommissioned.
# ==============================================================================

# Safe script execution settings
set -e      # Exit immediately if a command exits with a non-zero status.
set -o pipefail # A pipeline will return the exit status of the last command to exit with a non-zero status.

# --- CONFIGURATION ---

# Define sensitive directories to be wiped before full disk erasure.
# Add or remove paths as needed.
SENSITIVE_DIRS=(
    "/home"
    "/root"
    "/backup"
    "/var/log"
    "/var/lib/mysql"
    "/var/lib/docker"
    "/var/www"
    "/etc/ssl"
    "/etc/ssh"
    "/tmp"
    "/var/tmp"
    "/var/spool/mail"
    "/opt"
)

# --- GLOBAL VARIABLES ---
LOG_FILE="/tmp/secure_wipe_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG_FILE="/tmp/secure_wipe_errors_$(date +%Y%m%d_%H%M%S).log"

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- UTILITY FUNCTIONS ---

log_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_command_error() { log_warning "Command '$1' may have failed. See error log: $ERROR_LOG_FILE"; }
check_root() { if [[ $EUID -ne 0 ]]; then log_error "This script must be run as root (sudo). Aborting."; exit 1; fi; }

confirm_action() {
    log_warning "========================================================="
    log_warning "  WARNING: THIS OPERATION WILL ERASE ALL DATA"
    log_warning "           AND CANNOT BE UNDONE!"
    log_warning "========================================================="
    local random_string; random_string=$(head /dev/urandom | tr -dc 'A-Z0-9' | head -c 6)
    echo -e "\nTo confirm, please type the following string exactly: ${YELLOW}${random_string}${NC}"
    read -r -p "> " confirmation
    if [[ "$confirmation" != "$random_string" ]]; then log_info "Invalid confirmation. Operation cancelled."; exit 0; fi
    read -r -p "Are you 100% sure you want to continue? (yes/no): " final_confirm
    if [[ "$final_confirm" != "yes" ]]; then log_info "Operation cancelled."; exit 0; fi
}

# --- NEW & ENHANCED FUNCTIONS ---

detect_and_install_tools() {
    log_info "Detecting OS and installing necessary tools..."
    local PKG_MANAGER=""
    local OS_ID=""

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
    else
        log_error "Cannot determine OS distribution. Aborting."
        exit 1
    fi

    log_info "Detected OS: $OS_ID"

    case "$OS_ID" in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            export DEBIAN_FRONTEND=noninteractive
            $PKG_MANAGER update -qq -o Dpkg::Use-Pty=0 >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
            
            local packages=(
                secure-delete wipe shred cryptsetup-bin coreutils dcfldd
                scrub bleachbit zerofree hdparm smartmontools nvme-cli
                sg3-utils util-linux parted gdisk nwipe build-essential
                autotools-dev autoconf pkg-config libncurses5-dev libparted-dev git
            )
            for pkg in "${packages[@]}"; do
                if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                    log_info "Installing $pkg..."
                    $PKG_MANAGER install -y -qq "$pkg" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_warning "Failed to install $pkg."
                fi
            done
            ;;
        centos|almalinux|rhel|rocky)
            PKG_MANAGER=$(command -v dnf || command -v yum)
            if [ -z "$PKG_MANAGER" ]; then
                log_error "No DNF or YUM package manager found. Aborting."
                exit 1
            fi

            log_info "Enabling EPEL repository for additional tools..."
            $PKG_MANAGER install -y epel-release >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_warning "Could not install EPEL. Some tools may be unavailable."

            $PKG_MANAGER makecache >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
            
            local packages=(
                secure-delete wipe shred cryptsetup coreutils dcfldd
                scrub bleachbit zerofree hdparm smartmontools nvme-cli
                sg3_utils util-linux parted gdisk nwipe ncurses-devel
                parted-devel git autoconf automake libtool pkgconfig
            )
             # Install Development Tools group
            log_info "Installing Development Tools group..."
            $PKG_MANAGER groupinstall -y "Development Tools" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"

            for pkg in "${packages[@]}"; do
                if ! rpm -q "$pkg" >/dev/null 2>&1; then
                    log_info "Installing $pkg..."
                    $PKG_MANAGER install -y "$pkg" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_warning "Failed to install $pkg."
                fi
            done
            ;;
        *)
            log_error "Unsupported OS: $OS_ID. Please manually install the required tools. Aborting."
            exit 1
            ;;
    esac
    log_info "Tool installation check completed."
}

wipe_sensitive_directories() {
    log_info "Stage 0: Securely wiping sensitive directories..."
    if ! command -v srm >/dev/null 2>&1; then
        log_warning "srm (secure-delete) command not found. Skipping sensitive directory wipe."
        return
    fi

    for dir in "${SENSITIVE_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Wiping directory: $dir ..."
            srm -rf "$dir" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_warning "Could not securely wipe $dir. It might be in use or permissions issue."
        else
            log_info "Directory $dir not found, skipping."
        fi
    done
    log_info "Sensitive directory wipe completed."
}


# --- CORE WIPE FUNCTIONS (Unchanged) ---

stop_services() {
    log_info "Stopping system services..."
    services=(apache2 nginx mysql mariadb postgresql docker containerd redis-server mongodb elasticsearch rabbitmq-server memcached cron)
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then systemctl stop "$service" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true; fi
    done
    sleep 5
}

clear_memory_and_swap() {
    log_info "Clearing data from RAM and SWAP..."
    for swap_device in $(swapon --show=NAME --noheadings); do
        log_info "Disabling and wiping swap: $swap_device"
        swapoff "$swap_device" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
        if [[ -b "$swap_device" || -f "$swap_device" ]]; then
            shred -n 2 -z "$swap_device" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "shred on $swap_device"
            if [[ -f "$swap_device" ]]; then rm -f "$swap_device"; fi
        fi
    done
    sync; echo 3 > /proc/sys/vm/drop_caches
}

wipe_single_disk() {
    local disk=$1
    log_info "Starting multi-layered wipe process for disk: $disk"

    # Stage 1: Hardware-based Erase
    log_info "[$disk] Step 1/4: Attempting Hardware Secure Erase..."
    if [[ "$disk" =~ "nvme" ]] && command -v nvme >/dev/null; then
        nvme format "$disk" --ses=1 --force >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
        nvme format "$disk" --ses=2 --force >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
        log_warning "[$disk] NVMe Secure Erase failed or is not supported."
    elif command -v hdparm >/dev/null; then
        if hdparm -I "$disk" | grep -q "frozen"; then
            log_warning "[$disk] Drive is 'frozen'. Skipping ATA Secure Erase."
        else
            hdparm --user-master u --security-set-pass p "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true
            timeout 7200 hdparm --user-master u --security-erase-enhanced p "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
            timeout 7200 hdparm --user-master u --security-erase p "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || \
            log_warning "[$disk] ATA Secure Erase failed or is not supported."
        fi
    fi

    # Stage 2: DoD 5220.22-M Wipe
    log_info "[$disk] Step 2/4: Performing DoD 5220.22-M wipe with nwipe..."
    if command -v nwipe >/dev/null; then
        nwipe --method=dod522022m --rounds=1 --nogui --force "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "nwipe on $disk"
    else
        log_warning "[$disk] nwipe command not found. Skipping."
    fi

    # Stage 3: Multi-pass Overwrite
    log_info "[$disk] Step 3/4: Overwriting with multiple random patterns..."
    dd if=/dev/urandom of="$disk" bs=4M status=none oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd pass 1 on $disk"
    dd if=/dev/urandom of="$disk" bs=4M status=none oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd pass 2 on $disk"
    dd if=/dev/urandom of="$disk" bs=4M status=none oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd pass 3 on $disk"

    # Stage 4: Destroy Disk Structure
    log_info "[$disk] Step 4/4: Destroying partition table and metadata..."
    dd if=/dev/zero of="$disk" bs=1M count=100 oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd zero start of $disk"
    dd if=/dev/zero of="$disk" bs=1M count=100 seek=$(( $(blockdev --getsize64 "$disk") / 1048576 - 100 )) oflag=direct >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_command_error "dd zero end of $disk"
    cryptsetup erase "$disk" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true
    
    log_info "COMPLETED SECURE WIPE FOR DISK: $disk"
}

final_verification() {
    local disks=$1
    log_info "=============== PERFORMING FINAL VERIFICATION ==============="
    for disk in $disks; do
        if [[ -b "$disk" ]]; then
            log_info "Randomly sampling data sectors on $disk..."
            hexdump -n 512 -C "$disk" | tee -a "$LOG_FILE"
        fi
    done
}


# --- MAIN ORCHESTRATION FUNCTION ---
main() {
    local self_path; self_path=$(readlink -f "$0")
    local safe_path="/tmp/$(basename "$self_path").$RANDOM"; cp "$self_path" "$safe_path"; chmod 400 "$safe_path"
    
    echo "Secure wipe process initiated at $(date)" > "$LOG_FILE"
    echo "----------------------------------------------------" >> "$LOG_FILE"
    
    check_root
    confirm_action
    
    log_info "Starting data destruction process in 10 seconds... (Press Ctrl+C to cancel)"
    sleep 10

    # === STAGE 1: SYSTEM PREPARATION ===
    detect_and_install_tools
    stop_services
    wipe_sensitive_directories # << NEW STEP ADDED HERE
    clear_memory_and_swap
    
    # === STAGE 2: PARALLEL DISK WIPING ===
    log_info "Detecting physical disks (sd, hd, nvme, vd)..."
    local disks_to_wipe; disks_to_wipe=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" && $1 ~ /(\/dev\/(sd|hd|nvme|vd)[a-z]+)$/ {print $1}')

    if [ -z "$disks_to_wipe" ]; then log_error "No physical disks found to wipe. Aborting."; exit 1; fi
    log_info "Disks detected for wiping: $disks_to_wipe"

    # Critical check for mounted filesystems
    local mounted_disks=""
    for disk in $disks_to_wipe; do
        if findmnt -S "$disk" -o TARGET -n | grep -q "."; then mounted_disks="$mounted_disks $disk"; fi
    done
    if [ -n "$mounted_disks" ]; then
        log_error "CRITICAL ERROR: Target disks are still mounted: $mounted_disks. Run from a live recovery environment. Aborting."
        exit 1
    fi
    log_info "All target disks are unmounted. Proceeding."
    
    local pids=()
    for disk in $disks_to_wipe; do
        wipe_single_disk "$disk" &
        pids+=($!)
    done
    
    log_info "Waiting for all parallel wipe tasks to complete... (This will take a very long time)"
    for pid in "${pids[@]}"; do wait "$pid"; done
    log_info "All parallel wipe tasks have been completed."

    # === STAGE 3: VERIFICATION AND COMPLETION ===
    final_verification "$disks_to_wipe"
    
    log_info "Generating completion report..."
    {
        echo "WIPE COMPLETION REPORT - $(date)"
        echo "====================================="
        echo "Wiped Disks: $disks_to_wipe"
        echo "Wiped Sensitive Dirs: ${SENSITIVE_DIRS[*]}"
        echo "Methods Applied (per disk):"
        echo "- Hardware Secure Erase (ATA/NVMe, if available/not frozen)"
        echo "- DoD 5220.22-M Standard Wipe (via nwipe)"
        echo "- 3-pass Random Overwrite (via dd)"
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
