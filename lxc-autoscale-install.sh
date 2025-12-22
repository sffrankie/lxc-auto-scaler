#!/usr/bin/env bash

# Copyright (c) 2025 droltr
# License: MIT
# https://github.com/droltr/lxc-auto-scaler

# ==============================================================================
# LXC AUTOSCALE INSTALL SCRIPT
# ==============================================================================
#
# This script runs INSIDE the LXC container
# Called automatically by build.func after container creation
#
# ==============================================================================

set -e

# Source the functions file from build.func
if [[ -n "${FUNCTIONS_FILE_PATH}" ]]; then
  source <(echo "${FUNCTIONS_FILE_PATH}")
fi

# ==============================================================================
# SECTION 1: SYSTEM UPDATE
# ==============================================================================

msg_info "Updating container system"
$STD apt-get update
$STD apt-get -y upgrade
msg_ok "System updated"

# ==============================================================================
# SECTION 2: LOCALE CONFIGURATION
# ==============================================================================

msg_info "Configuring locale: ${LOCALE_NAME:-English}"
$STD apt-get install -y locales

# Use locale from parent script or default to en_US.UTF-8
SELECTED_LOCALE="${SELECTED_LOCALE:-en_US.UTF-8}"

if [[ "$SELECTED_LOCALE" == "tr_TR.UTF-8" ]]; then
    echo "tr_TR.UTF-8 UTF-8" >> /etc/locale.gen
fi
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen

$STD locale-gen
$STD update-locale LANG=$SELECTED_LOCALE
export LANG=$SELECTED_LOCALE
export LC_ALL=$SELECTED_LOCALE
msg_ok "Locale configured: ${LOCALE_NAME:-English}"

# ==============================================================================
# SECTION 3: INSTALL DEPENDENCIES
# ==============================================================================

msg_info "Installing dependencies"
$STD apt-get install -y \
    curl \
    git \
    python3 \
    python3-pip \
    python3-yaml \
    python3-requests \
    python3-paramiko \
    python3-cryptography \
    python3-flask \
    python3-flask-cors \
    openssh-client \
    nginx \
    ca-certificates \
    gnupg \
    build-essential \
    python3-dev
msg_ok "Dependencies installed"

# Install Flask-SocketIO via pip (not available in Debian repos)
msg_info "Installing Flask-SocketIO"
$STD pip3 install flask-socketio --break-system-packages
msg_ok "Flask-SocketIO installed"

# ==============================================================================
# SECTION 4: SSH KEY GENERATION
# ==============================================================================

msg_info "Creating SSH key"
mkdir -p /root/.ssh
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
SSH_PUBLIC_KEY=$(cat /root/.ssh/id_rsa.pub)
msg_ok "SSH key created"

# ==============================================================================
# SECTION 5: CLONE REPOSITORY
# ==============================================================================

msg_info "Cloning LXC AutoScale repository"
cd /opt
$STD git clone https://github.com/fabriziosalmi/proxmox-lxc-autoscale.git lxc-autoscale
msg_ok "Repository cloned"

# ==============================================================================
# SECTION 6: CREATE DIRECTORIES
# ==============================================================================

msg_info "Creating directories"
mkdir -p /etc/lxc_autoscale
mkdir -p /var/lib/lxc_autoscale/backups
mkdir -p /var/log
msg_ok "Directories created"

# ==============================================================================
# SECTION 7: SETUP APPLICATION
# ==============================================================================

msg_info "Setting up LXC AutoScale"
cp /opt/lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/
chmod +x /usr/local/bin/lxc_autoscale.py
msg_ok "Application setup complete"

# ==============================================================================
# SECTION 8: CREATE CONFIGURATION
# ==============================================================================

msg_info "Creating configuration file"

# Get Proxmox host IP
HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)

# Use detected containers from parent script or empty array
DETECTED_LXC="${DETECTED_LXC:-}"
if [[ -n "$DETECTED_LXC" ]]; then
    LXC_ARRAY="[$DETECTED_LXC]"
else
    LXC_ARRAY="[]"
fi

cat > /etc/lxc_autoscale/lxc_autoscale.yaml << EOF
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
  lxc_containers: ${LXC_ARRAY}
EOF

if [[ -n "$DETECTED_LXC" ]]; then
    msg_ok "Configuration created with detected containers: $DETECTED_LXC"
else
    msg_ok "Configuration created (no containers detected)"
fi

# ==============================================================================
# SECTION 9: CREATE SYSTEMD SERVICE
# ==============================================================================

msg_info "Creating systemd service"
cat > /etc/systemd/system/lxc_autoscale.service << 'EOFSERVICE'
[Unit]
Description=LXC AutoScale Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lxc-autoscale/lxc_autoscale
ExecStart=/usr/bin/python3 lxc_autoscale.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

$STD systemctl daemon-reload
$STD systemctl enable lxc_autoscale.service
$STD systemctl start lxc_autoscale.service
msg_ok "Service created and started"

# ==============================================================================
# SECTION 10: SETUP ORIGINAL FLASK WEB INTERFACE
# ==============================================================================

msg_info "Setting up original Flask web interface"

# Check if original UI exists in repo
if [ -d "/opt/lxc-autoscale/lxc_autoscale/ui" ] && [ -f "/opt/lxc-autoscale/lxc_autoscale/ui/lxc_autoscale_ui.py" ]; then
    msg_info "Installing original Flask UI from repository"
    
    # Create UI directory
    mkdir -p /var/www/lxc-autoscale
    
    # Copy entire UI directory
    cp -r /opt/lxc-autoscale/lxc_autoscale/ui/* /var/www/lxc-autoscale/
    
    # Fix Flask-SocketIO production mode issue
    msg_info "Patching Flask UI for production mode"
    sed -i 's/socketio.run(app, host/socketio.run(app, allow_unsafe_werkzeug=True, host/' /var/www/lxc-autoscale/lxc_autoscale_ui.py
    
    # Set proper permissions
    chown -R www-data:www-data /var/www/lxc-autoscale
    chmod -R 755 /var/www/lxc-autoscale
    find /var/www/lxc-autoscale -type f -exec chmod 644 {} \;
    chmod +x /var/www/lxc-autoscale/lxc_autoscale_ui.py
    
    # Create systemd service for Flask UI
    cat > /etc/systemd/system/lxc_autoscale_ui.service << 'EOFUISERVICE'
[Unit]
Description=LXC AutoScale Web UI (Flask)
After=network.target lxc_autoscale.service
Wants=lxc_autoscale.service

[Service]
Type=simple
User=root
Group=root
Environment="PYTHONUNBUFFERED=1"
ExecStart=/bin/bash -c 'cd /var/www/lxc-autoscale && /usr/bin/python3 -u lxc_autoscale_ui.py'
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFUISERVICE
    
    # Enable and start Flask UI service
    $STD systemctl daemon-reload
    $STD systemctl enable lxc_autoscale_ui.service
    $STD systemctl start lxc_autoscale_ui.service
    
    msg_ok "Original Flask UI installed and started"
else
    msg_error "Original UI not found in repository"
    exit 1
fi

# ==============================================================================
# SECTION 11: CONFIGURE NGINX AS REVERSE PROXY
# ==============================================================================

msg_info "Configuring Nginx as reverse proxy for Flask UI"
cat > /etc/nginx/sites-available/lxc-autoscale << 'EOFNGINX'
server {
    listen 8080;
    server_name _;
    
    # Proxy to Flask UI running on port 5000
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Direct access to static files (optimization)
    location /static/ {
        alias /var/www/lxc-autoscale/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    # API endpoints for logs and metrics
    location /api/logs {
        alias /var/log/lxc_autoscale.log;
        default_type text/plain;
        add_header Content-Type 'text/plain; charset=utf-8';
    }
    
    location /api/metrics {
        alias /var/log/lxc_autoscale.json;
        default_type application/json;
        add_header Content-Type 'application/json; charset=utf-8';
    }
    
    # Logging
    access_log /var/log/nginx/lxc_autoscale_access.log;
    error_log /var/log/nginx/lxc_autoscale_error.log;
}
EOFNGINX

ln -sf /etc/nginx/sites-available/lxc-autoscale /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD systemctl restart nginx
msg_ok "Nginx configured as reverse proxy"

# ==============================================================================
# SECTION 12: DISPLAY SSH KEY
# ==============================================================================

msg_info "Installation Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SSH Public Key (Add to Proxmox host):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat /root/.ssh/id_rsa.pub
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Run this command on Proxmox host:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "echo '$(cat /root/.ssh/id_rsa.pub)' >> /root/.ssh/authorized_keys"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -n "$DETECTED_LXC" ]]; then
    echo "  Detected containers: $DETECTED_LXC"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
echo ""

# ==============================================================================
# CLEANUP
# ==============================================================================

$STD apt-get autoremove -y
$STD apt-get autoclean -y

msg_ok "LXC AutoScale installation completed successfully!"

# ==============================================================================
# SECTION 13: FINAL INFORMATION DISPLAY
# ==============================================================================

# Get container IP
CONTAINER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🎉 LXC AutoScale Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  📍 Container IP: ${CONTAINER_IP}"
echo ""
echo "  🌐 Web Interface (Flask UI):"
echo "     http://${CONTAINER_IP}:8080"
echo ""
echo "  📁 Configuration:"
echo "     /etc/lxc_autoscale/lxc_autoscale.yaml"
echo ""
echo "  🔧 AutoScale Service:"
echo "     systemctl status lxc_autoscale"
echo "     systemctl restart lxc_autoscale"
echo "     journalctl -u lxc_autoscale -f"
echo ""
echo "  🌐 Web UI Service:"
echo "     systemctl status lxc_autoscale_ui"
echo "     systemctl restart lxc_autoscale_ui"
echo "     journalctl -u lxc_autoscale_ui -f"
echo ""
echo "  📊 View Logs:"
echo "     tail -f /var/log/lxc_autoscale.log"
echo ""
echo "  🔑 SSH to container:"
echo "     ssh root@${CONTAINER_IP}"
echo ""
if [[ -n "$DETECTED_LXC" ]]; then
echo "  📦 Detected Containers: ${DETECTED_LXC}"
echo ""
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ==============================================================================
# SECTION 14: CREATE MOTD (LOGIN BANNER)
# ==============================================================================

msg_info "Creating login banner (MOTD)"

CONTAINER_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

cat > /etc/motd << 'EOFMOTDINNER'
LXC AutoScale - Container Resource Management

    🌐   Provided by: github.com/droltr/lxc-auto-scaler
    🖥️   Based on: github.com/fabriziosalmi/proxmox-lxc-autoscale
    📦   Framework: community-scripts.github.io/ProxmoxVE
EOFMOTDINNER

# Add dynamic info
cat >> /etc/motd << EOFDYNAMIC
    🏠   Hostname: ${HOSTNAME}
    💡   IP Address: ${CONTAINER_IP}
    🌐   Web UI: http://${CONTAINER_IP}:8080
    📁   Config: /etc/lxc_autoscale/lxc_autoscale.yaml
EOFDYNAMIC

msg_ok "Login banner created"

# ==============================================================================
# CLEANUP
# ==============================================================================

$STD apt-get autoremove -y
$STD apt-get autoclean -y
