#!/usr/bin/env bash

# Copyright (c) 2025 Murat
# License: MIT
# Source: https://github.com/fabriziosalmi/proxmox-lxc-autoscale

# ==============================================================================
# LXC AutoScale - Proxmox LXC Container Auto Scaling
# ==============================================================================

source /dev/stdin <<< "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)"

# ==============================================================================
# APP VARIABLES
# ==============================================================================
var_disk="8"
var_cpu="2"
var_ram="2048"
var_os="debian"
var_version="13"
var_unprivileged="1"

# ==============================================================================
# APP INFO
# ==============================================================================
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

# ==============================================================================
# SYSTEM UPDATE
# ==============================================================================
msg_info "Updating system"
$STD apt-get update
$STD apt-get -y upgrade
msg_ok "System updated"

# ==============================================================================
# INSTALLING DEPENDENCIES
# ==============================================================================
msg_info "Installing dependencies"
$STD apt-get install -y \
    curl \
    sudo \
    git \
    make \
    g++ \
    gcc \
    ca-certificates \
    gnupg \
    python3 \
    python3-pip \
    python3-yaml \
    python3-requests \
    python3-paramiko \
    python3-cryptography \
    openssh-client
msg_ok "Dependencies installed"

# ==============================================================================
# SSH KEY SETUP
# ==============================================================================
msg_info "Configuring SSH key"
if [[ ! -f /root/.ssh/id_rsa ]]; then
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' -q
    msg_ok "SSH key created"
else
    msg_ok "SSH key exists"
fi

# ==============================================================================
# LXC AUTOSCALE INSTALLATION
# ==============================================================================
msg_info "Downloading LXC AutoScale"
cd /opt
$STD git clone https://github.com/fabriziosalmi/proxmox-lxc-autoscale.git lxc-autoscale
msg_ok "LXC AutoScale downloaded"

msg_info "Creating directories"
mkdir -p /etc/lxc_autoscale
mkdir -p /var/lib/lxc_autoscale/backups
mkdir -p /var/log
msg_ok "Directories created"

msg_info "Configuring LXC AutoScale"
cp /opt/lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/lxc_autoscale.py
chmod +x /usr/local/bin/lxc_autoscale.py
msg_ok "LXC AutoScale configured"

# ==============================================================================
# CONFIGURATION FILE
# ==============================================================================
msg_info "Creating configuration file"

# Ask for Proxmox host IP
read -p "Proxmox Host IP Address: " HOST_IP

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

# Örnek Tier - Container ID'lerini ekleyin
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
  # Example: lxc_containers: [100, 101, 102]
EOF

msg_ok "Configuration file created"

# ==============================================================================
# SYSTEMD SERVICE
# ==============================================================================
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

# ==============================================================================
# WEB INTERFACE (NGINX)
# ==============================================================================
msg_info "Installing web interface"
$STD apt-get install -y nginx

mkdir -p /var/www/lxc-autoscale

if [[ -d /opt/lxc-autoscale/lxc_autoscale/ui ]]; then
    cp -r /opt/lxc-autoscale/lxc_autoscale/ui/* /var/www/lxc-autoscale/ 2>/dev/null || true
fi

cat <<EOF >/etc/nginx/sites-available/lxc-autoscale
server {
    listen 8080;
    server_name _;
    
    root /var/www/lxc-autoscale;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
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

# ==============================================================================
# MOTD UPDATE
# ==============================================================================
customize

msg_ok "LXC AutoScale installed successfully\n"
echo -e "${TAB}${GATEWAY}${YW} Web Interface: ${GN}http://$(hostname -I | awk '{print $1}'):8080${CL}"
echo -e "${TAB}${GATEWAY}${YW} Config: ${GN}/etc/lxc_autoscale/lxc_autoscale.yaml${CL}"
echo -e "${TAB}${GATEWAY}${YW} SSH Public Key: ${GN}$(cat /root/.ssh/id_rsa.pub)${CL}\n"
echo -e "${TAB}${INFO} Add SSH public key to Proxmox host:"
echo -e "${TAB}${INFO} ${GN}echo '$(cat /root/.ssh/id_rsa.pub)' >> /root/.ssh/authorized_keys${CL}\n"
echo -e "${TAB}${INFO} To add container IDs:"
echo -e "${TAB}${INFO} ${GN}nano /etc/lxc_autoscale/lxc_autoscale.yaml${CL}\n"
