#!/usr/bin/env bash

# Copyright (c) 2025 Murat
# License: MIT
# Source: https://github.com/fabriziosalmi/proxmox-lxc-autoscale

source /dev/stdin <<< "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)"

# App info
var_disk="8"
var_cpu="2"
var_ram="2048"
var_os="debian"
var_version="13"
var_unprivileged="1"

# App name and tags
APP="LXC-AutoScale"
var_tags="autoscale;monitoring"

# Main functions
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    
    if [[ ! -d /opt/lxc-autoscale ]]; then
        msg_error "LXC AutoScale is not installed"
        exit
    fi
    
    msg_info "Updating LXC AutoScale"
    systemctl stop lxc_autoscale 2>/dev/null
    cd /opt/lxc-autoscale
    git pull
    cp /opt/lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/lxc_autoscale.py
    chmod +x /usr/local/bin/lxc_autoscale.py
    systemctl start lxc_autoscale
    msg_ok "LXC AutoScale updated"
    exit
}

start
build_container
description

msg_ok "Completed!\n"
msg_info "LXC AutoScale Installation"

# System update
msg_info "Updating system"
$STD apt-get update
$STD apt-get -y upgrade
msg_ok "System updated"

# Install dependencies
msg_info "Installing dependencies"
$STD apt-get install -y \
    curl \
    sudo \
    git \
    ca-certificates \
    gnupg \
    python3 \
    python3-pip \
    python3-yaml \
    python3-requests \
    python3-paramiko \
    python3-cryptography \
    openssh-client \
    nginx
msg_ok "Dependencies installed"

# SSH key setup
msg_info "Configuring SSH key"
if [[ ! -f /root/.ssh/id_rsa ]]; then
    mkdir -p /root/.ssh
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' -q
    msg_ok "SSH key created"
else
    msg_ok "SSH key exists"
fi

# Clone repository
msg_info "Downloading LXC AutoScale"
cd /opt
$STD git clone https://github.com/fabriziosalmi/proxmox-lxc-autoscale.git lxc-autoscale
msg_ok "LXC AutoScale downloaded"

# Create directories
msg_info "Creating directories"
mkdir -p /etc/lxc_autoscale
mkdir -p /var/lib/lxc_autoscale/backups
mkdir -p /var/log
msg_ok "Directories created"

# Setup application
msg_info "Configuring LXC AutoScale"
cp /opt/lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/lxc_autoscale.py
chmod +x /usr/local/bin/lxc_autoscale.py
msg_ok "LXC AutoScale configured"

# Get Proxmox host IP
msg_info "Configuration setup"
read -p "Enter Proxmox Host IP Address: " HOST_IP

# Create config
cat <<EOF >/etc/lxc_autoscale/lxc_autoscale.yaml
DEFAULTS:
  log_file: /var/log/lxc_autoscale.log
  lock_file: /var/lock/lxc_autoscale.lock
  backup_dir: /var/lib/lxc_autoscale/backups
  reserve_cpu_percent: 10
  reserve_memory_mb: 2048
  off_peak_start: 22
  off_peak_end: 6
  behaviour: normal
  cpu_upper_threshold: 80
  cpu_lower_threshold: 20
  memory_upper_threshold: 70
  memory_lower_threshold: 20
  min_cores: 1
  max_cores: 4
  min_memory: 512
  max_memory: 4096
  check_interval: 300
  use_remote_proxmox: true
  ssh_user: root
  ssh_key: /root/.ssh/id_rsa
  proxmox_host: ${HOST_IP}

TIER_DEFAULT:
  cpu_upper_threshold: 80
  cpu_lower_threshold: 20
  memory_upper_threshold: 70
  memory_lower_threshold: 20
  min_cores: 1
  max_cores: 4
  min_memory: 512
  max_memory: 4096
  lxc_containers: []
EOF
msg_ok "Configuration file created"

# Create systemd service
msg_info "Creating systemd service"
cat <<EOF >/etc/systemd/system/lxc_autoscale.service
[Unit]
Description=LXC AutoScale Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/python3 /usr/local/bin/lxc_autoscale.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now lxc_autoscale.service
msg_ok "Systemd service created and started"

# Setup web interface
msg_info "Installing web interface"
mkdir -p /var/www/lxc-autoscale

if [[ -d /opt/lxc-autoscale/lxc_autoscale/ui ]]; then
    cp -r /opt/lxc-autoscale/lxc_autoscale/ui/* /var/www/lxc-autoscale/ 2>/dev/null || true
fi

cat <<'EOF' >/etc/nginx/sites-available/lxc-autoscale
server {
    listen 8080;
    server_name _;
    
    root /var/www/lxc-autoscale;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location /api/logs {
        alias /var/log/lxc_autoscale.log;
        default_type text/plain;
    }
    
    location /api/metrics {
        alias /var/log/lxc_autoscale.json;
        default_type application/json;
    }
}
EOF

ln -sf /etc/nginx/sites-available/lxc-autoscale /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx
msg_ok "Web interface installed"

# Cleanup and finalize
motd_ssh
customize

msg_ok "LXC AutoScale installed successfully\n"
echo -e "${APP} should be reachable by going to the following URL."
echo -e "${BL}http://$(hostname -I | awk '{print $1}'):8080${CL}\n"
