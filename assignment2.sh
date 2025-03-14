#!/bin/bash

set -euo pipefail  # to enable strict error handling

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

error_exit() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
    exit 1
}

# to make sure script runs as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root. Use sudo."
fi

# to identify primary network interface
default_iface=$(ip route | awk '/default/ {print $5; exit}')
NETPLAN_FILE=$(find /etc/netplan/ -type f -name "*.yaml" | head -n 1)
if [[ -z "$NETPLAN_FILE" ]]; then
    error_exit "No Netplan configuration file found in /etc/netplan/"
fi

if grep -q "192.168.16.21/24" "$NETPLAN_FILE"; then
    log "Netplan configuration already set."
else
    log "Updating Netplan configuration in $NETPLAN_FILE."
    chmod 600 "$NETPLAN_FILE"
    cat >> "$NETPLAN_FILE" <<EOL
network:
  ethernets:
    $default_iface:
      dhcp4: no
      addresses:
        - 192.168.16.21/24
      routes:
        - to: default
          via: 192.168.16.2
  version: 2
EOL
    chmod 644 "$NETPLAN_FILE"
    netplan apply || error_exit "Failed to apply Netplan configuration."
fi

# we are updating /etc/hosts
HOSTS_FILE="/etc/hosts"
if ! grep -q "192.168.16.21 server1" "$HOSTS_FILE"; then
    log "Updating /etc/hosts."
    sed -i '/server1/d' "$HOSTS_FILE"
    echo "192.168.16.21 server1" >> "$HOSTS_FILE"
fi

# Install necessary packages simultaneously
log "Installing required software packages."
echo "apache2 squid" | xargs -n1 -P2 apt install -y || error_exit "Failed to install required software."

# Activate and initiate services
log "activating and initiating services."
systemctl enable --now apache2 squid || error_exit "Failed to start required services."

# list of users
USERS=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")

# for configuring users
for USER in "${USERS[@]}"; do
    if ! id "$USER" &>/dev/null; then
        log "Creating user $USER."
        useradd -m -s /bin/bash "$USER" || error_exit "Failed to create user $USER."
    fi
    
    USER_HOME="/home/$USER"
    SSH_DIR="$USER_HOME/.ssh"
    mkdir -p "$SSH_DIR"
    chown "$USER:$USER" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    # generate SSH keys if not existing
    for key_type in rsa ed25519; do
        key_file="$SSH_DIR/id_${key_type}"
        if [[ ! -f "${key_file}.pub" ]]; then
            log "Generating ${key_type^^} SSH key for $USER."
            sudo -u "$USER" ssh-keygen -t "$key_type" -b 4096 -N "" -f "$key_file"
        fi
    done
    
    # add keys tothe list of  authorized_keys
    cat "$SSH_DIR/id_rsa.pub" "$SSH_DIR/id_ed25519.pub" > "$SSH_DIR/authorized_keys"
    chown "$USER:$USER" "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"

done

# doing special configuration for dennis
if id "dennis" &>/dev/null; then
    log "Ensuring dennis has sudo access."
    usermod -aG sudo dennis
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm" >> "/home/dennis/.ssh/authorized_keys"
fi

log "Script execution completed successfully."
