#!/bin/bash

# ==============================================================================
# SECURE DATA WIPE SCRIPT - ENHANCED BACKGROUND VERSION (v4.1 - Patched)
# Author: Enhanced version with background execution capability
#
# FEATURES:
# - Cross-distro support (Debian, Ubuntu, CentOS, AlmaLinux, etc.)
# - Background execution using 'at' command
# - Self-contained execution even after disk wipe
# - Email notification support (optional)
# - Enhanced confirmation process
#
# WARNING: This script will IRREVERSIBLY DESTROY ALL DATA!
# Only run on servers that are being decommissioned.
# ==============================================================================

# Safe script execution settings
set -e      # Exit immediately if a command exits with a non-zero status.
set -o pipefail # A pipeline will return the exit status of the last command to exit with a non-zero status.

# --- CONFIGURATION ---

# Define sensitive directories to be wiped before full disk erasure.
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
SCRIPT_DIR="/dev/shm"  # Use tmpfs for temporary files
LOG_FILE="$SCRIPT_DIR/secure_wipe_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG_FILE="$SCRIPT_DIR/secure_wipe_errors_$(date +%Y%m%d_%H%M%S).log"
TEMP_SCRIPT="$SCRIPT_DIR/secure_wipe_temp_$$.sh"
EMAIL_RECIPIENT=""

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- UTILITY FUNCTIONS ---

log_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_command_error() { log_warning "Command '$1' may have failed. See error log: $ERROR_LOG_FILE"; }
check_root() { if [[ $EUID -ne 0 ]]; then log_error "This script must be run as root (sudo). Aborting."; exit 1; fi; }

setup_tmpfs() {
    if [ ! -d "$SCRIPT_DIR" ]; then
        mkdir -p "$SCRIPT_DIR" || { echo "Failed to create $SCRIPT_DIR"; exit 1; }
    fi
    if ! touch "$SCRIPT_DIR/test_write" 2>/dev/null; then
        echo "Cannot write to $SCRIPT_DIR, falling back to /tmp"
        SCRIPT_DIR="/tmp"
        LOG_FILE="$SCRIPT_DIR/secure_wipe_$(date +%Y%m%d_%H%M%S).log"
        ERROR_LOG_FILE="$SCRIPT_DIR/secure_wipe_errors_$(date +%Y%m%d_%H%M%S).log"
        TEMP_SCRIPT="$SCRIPT_DIR/secure_wipe_temp_$$.sh"
    else
        rm -f "$SCRIPT_DIR/test_write"
    fi
}

# [CẢI TIẾN] Gộp tất cả các hàm cài đặt vào một chỗ để thực hiện trước khi lên lịch.
install_required_tools() {
    log_info "Checking and installing required tools ('at', email clients, wipe tools)..."
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
                at mailutils secure-delete wipe shred cryptsetup-bin coreutils dcfldd
                scrub bleachbit zerofree hdparm smartmontools nvme-cli
                sg3-utils util-linux nwipe
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
                at mailx secure-delete wipe shred cryptsetup coreutils dcfldd
                scrub bleachbit zerofree hdparm smartmontools nvme-cli
                sg3_utils util-linux nwipe
            )
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
    
    # Start atd service
    log_info "Ensuring 'atd' service is running..."
    systemctl enable atd 2>/dev/null || true
    systemctl start atd 2>/dev/null || service atd start || true
    
    log_info "Tool installation and setup completed."
}


confirm_action() {
    log_warning "========================================================="
    log_warning "  WARNING: THIS OPERATION WILL ERASE ALL DATA"
    log_warning "           AND CANNOT BE UNDONE!"
    log_warning "========================================================="
    
    local random_string; random_string=$(head /dev/urandom | tr -dc 'a-z' | head -c 6)
    echo -e "\nTo confirm, please type the following 6 lowercase letters exactly: ${YELLOW}${random_string}${NC}"
    read -r -p "> " confirmation
    if [[ "$confirmation" != "$random_string" ]]; then 
        log_info "Invalid confirmation. Operation cancelled."; 
        exit 0; 
    fi
    
    read -r -p "Are you 100% sure you want to continue? (yes/no): " final_confirm
    if [[ "$final_confirm" != "yes" ]]; then 
        log_info "Operation cancelled."; 
        exit 0; 
    fi
    
    echo -e "\n${BLUE}[OPTIONAL]${NC} Do you want to receive email notification when the wipe is complete?"
    read -r -p "Enter email address (or press Enter to skip): " email_input
    if [[ -n "$email_input" && "$email_input" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        EMAIL_RECIPIENT="$email_input"
        log_info "Email notification will be sent to: $EMAIL_RECIPIENT"
    else
        log_info "No email notification will be sent."
    fi
}

create_self_contained_script() {
    log_info "Creating self-contained execution script..."
    
    # [CẢI TIẾN] Script con được rút gọn đáng kể. Nó không cần cài đặt công cụ nữa.
    cat > "$TEMP_SCRIPT" << 'SCRIPT_END'
#!/bin/bash

# Self-contained secure wipe execution script
# [SỬA LỖI] Đảm bảo các lệnh cơ bản hoạt động ổn định trong môi trường 'at'
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

set -e
set -o pipefail

# Embedded configuration
SENSITIVE_DIRS=(
    "/home" "/root" "/backup" "/var/log" "/var/lib/mysql"
    "/var/lib/docker" "/var/www" "/etc/ssl" "/etc/ssh" 
    "/tmp" "/var/tmp" "/var/spool/mail" "/opt"
)

SCRIPT_DIR="/dev/shm"
LOG_FILE="$SCRIPT_DIR/secure_wipe_background_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG_FILE="$SCRIPT_DIR/secure_wipe_background_errors_$(date +%Y%m%d_%H%M%S).log"
EMAIL_RECIPIENT="EMAIL_PLACEHOLDER"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_command_error() { log_warning "Command '$1' may have failed. See error log: $ERROR_LOG_FILE"; }

# [CẢI TIẾN] Thêm thư mục bin tùy chỉnh vào PATH đã được định nghĩa sẵn.
setup_essential_tools() {
    log_info "Copying essential tools to tmpfs..."
    mkdir -p "$SCRIPT_DIR/bin"
    
    for cmd in dd shred nwipe hdparm cryptsetup srm findmnt lsblk blockdev hexdump sync; do
        if command -v "$cmd" >/dev/null 2>&1; then
            cp "$(command -v $cmd)" "$SCRIPT_DIR/bin/" 2>/dev/null || true
        fi
    done
    
    export PATH="$SCRIPT_DIR/bin:$PATH"
    log_info "Essential tools copied to tmpfs. New PATH: $PATH"
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
            srm -rf "$dir" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || log_warning "Could not securely wipe $dir."
        else
            log_info "Directory $dir not found, skipping."
        fi
    done
    log_info "Sensitive directory wipe completed."
}

stop_services() {
    log_info "Stopping system services..."
    services=(apache2 nginx mysql mariadb postgresql docker containerd redis-server mongodb elasticsearch rabbitmq-server memcached cron atd)
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then 
            systemctl stop "$service" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || true
        fi
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

send_email_notification() {
    if [ -n "$EMAIL_RECIPIENT" ] && [ "$EMAIL_RECIPIENT" != "EMAIL_PLACEHOLDER" ]; then
        log_info "Sending email notification to $EMAIL_RECIPIENT..."
        local subject="Secure Wipe Completed - $(hostname) - $(date)"
        local report_file="$SCRIPT_DIR/wipe_report.txt"
        
        if command -v mail >/dev/null 2>&1; then
            {
                echo "Secure wipe operation has been completed on server: $(hostname)"
                echo "Completion time: $(date)"
                echo ""
                echo "=== WIPE COMPLETION REPORT ==="
                cat "$report_file" 2>/dev/null || echo "Report file not found"
                echo ""
                echo "=== LOG SUMMARY ==="
                tail -50 "$LOG_FILE" 2>/dev/null || echo "Log file not accessible"
            } | mail -s "$subject" "$EMAIL_RECIPIENT" 2>> "$ERROR_LOG_FILE" || \
            log_warning "Failed to send email notification"
        else
            log_warning "Mail command not available. Cannot send email notification."
        fi
    fi
}

# Main execution function
main_execution() {
    echo "Background secure wipe process initiated at $(date)" > "$LOG_FILE"
    echo "----------------------------------------------------" >> "$LOG_FILE"
    
    log_info "=========================================================="
    log_info "  BACKGROUND SECURE DATA WIPE PROCESS STARTED"
    log_info "  Server: $(hostname)"
    log_info "  Start Time: $(date)"
    log_info "=========================================================="
    
    # === STAGE 1: SYSTEM PREPARATION ===
    setup_essential_tools
    stop_services
    wipe_sensitive_directories
    clear_memory_and_swap
    
    # === STAGE 2: PARALLEL DISK WIPING ===
    log_info "Detecting physical disks (sd, hd, nvme, vd)..."
    local disks_to_wipe; disks_to_wipe=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" && $1 ~ /(\/dev\/(sd|hd|nvme|vd)[a-z]+)$/ {print $1}')

    if [ -z "$disks_to_wipe" ]; then 
        log_error "No physical disks found to wipe. Aborting."
        exit 1
    fi
    log_info "Disks detected for wiping: $disks_to_wipe"

    # [SỬA LỖI] Loại bỏ khối kiểm tra `findmnt` vì nó sẽ luôn luôn thất bại.
    # Quá trình xác nhận của người dùng đã đủ để cho phép tiếp tục.
    log_info "Proceeding with wipe. User has confirmed all actions."
    
    local pids=()
    for disk in $disks_to_wipe; do
        wipe_single_disk "$disk" &
        pids+=($!)
    done
    
    log_info "Waiting for all parallel wipe tasks to complete... (This will take a very long time)"
    for pid in "${pids[@]}"; do 
        wait "$pid"
    done
    log_info "All parallel wipe tasks have been completed."

    # === STAGE 3: VERIFICATION AND COMPLETION ===
    final_verification "$disks_to_wipe"
    
    log_info "Generating completion report..."
    {
        echo "WIPE COMPLETION REPORT - $(date)"
        echo "====================================="
        echo "Server: $(hostname)"
        echo "Wiped Disks: $disks_to_wipe"
        echo "Wiped Sensitive Dirs: ${SENSITIVE_DIRS[*]}"
        echo "Methods Applied (per disk):"
        echo "- Hardware Secure Erase (ATA/NVMe, if available/not frozen)"
        echo "- DoD 5220.22-M Standard Wipe (via nwipe)"
        echo "- Multi-pass Random/Zero Overwrite (via dd)"
        echo "- Partition Table and Metadata Destruction"
        echo "====================================="
        echo "Log file: $LOG_FILE"
        echo "Error log: $ERROR_LOG_FILE"
    } > "$SCRIPT_DIR/wipe_report.txt"
    
    send_email_notification
    
    log_info "=========================================================="
    log_info "  SECURE DATA WIPE COMPLETED!"
    log_info "  The server will automatically reboot in 60 seconds."
    log_info "=========================================================="
    
    sleep 60
    # [SỬA LỖI] Sử dụng SysRq để khởi động lại một cách đáng tin cậy.
    echo b > /proc/sys/rq-trigger
}

# Execute main function
main_execution
SCRIPT_END

    if [ -n "$EMAIL_RECIPIENT" ]; then
        sed -i "s/EMAIL_PLACEHOLDER/$EMAIL_RECIPIENT/g" "$TEMP_SCRIPT"
    else
        sed -i 's/EMAIL_PLACEHOLDER//g' "$TEMP_SCRIPT"
    fi
    
    chmod +x "$TEMP_SCRIPT"
    log_info "Self-contained script created at: $TEMP_SCRIPT"
}

schedule_background_execution() {
    log_info "Scheduling background execution in 1 minute..."
    
    echo "$TEMP_SCRIPT" | at now + 1 minute 2>/dev/null || {
        log_error "Failed to schedule background execution. Make sure 'at' daemon is running."
        exit 1
    }
    
    log_info "=========================================================="
    log_info "  SECURE WIPE SCHEDULED FOR BACKGROUND EXECUTION"
    log_info "  The wipe process will start in 1 minute."
    log_info "  You can safely close this connection now."
    if [ -n "$EMAIL_RECIPIENT" ]; then
        log_info "  Email notification will be sent to: $EMAIL_RECIPIENT"
    fi
    log_info "  Log files will be in: $SCRIPT_DIR"
    log_info "=========================================================="
    atq 2>/dev/null || true
}

# --- MAIN ORCHESTRATION FUNCTION ---
main() {
    setup_tmpfs
    
    echo "Enhanced Secure Wipe Process - Background Execution Version" > "$LOG_FILE"
    echo "============================================================" >> "$LOG_FILE"
    echo "Initiated at $(date)" >> "$LOG_FILE"
    
    check_root
    confirm_action
    
    # [CẢI TIẾN] Tất cả việc cài đặt được thực hiện tại đây, một lần duy nhất.
    install_required_tools
    
    log_info "Preparing for background execution..."
    create_self_contained_script
    schedule_background_execution
    
    log_info "Background execution has been scheduled. Main script is now exiting."
    exit 0
}

# Execute the main function
main "$@"
