#!/usr/bin/env bash

# Copyright (c) 2025 droltr
# License: MIT
# based on https://github.com/fabriziosalmi/proxmox-lxc-autoscale?tab=readme-ov-file
# https://github.com/droltr/lxc-auto-scaler

# ==============================================================================
# LXC AUTOSCALE - PROXMOX CONTAINER AUTO SCALING
# ==============================================================================
#
# This script creates an LXC container for LXC AutoScale system
# Based on community-scripts framework
# 
# Features:
#   - Automatic LXC container detection
#   - Locale selection (EN/TR)
#   - Original UI installation from GitHub
#   - SSH key management
#   - Automated configuration
#
# Usage:
#   bash <(curl -s https://raw.githubusercontent.com/droltr/lxc-auto-scaler/main/lxc-autoscale.sh)
#
# ==============================================================================

# ==============================================================================
# SECTION 1: LOAD COMMUNITY-SCRIPTS FRAMEWORK
# ==============================================================================

# Load core functions (colors, messages, formatting)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)

# Load error handler (catch_errors, error management)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)

# Load build functions (container creation, menus, whiptail)
# source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
source <(curl -fsSL https://raw.githubusercontent.com/droltr/lxc-auto-scaler/main/misc/build.func)

# ❌ NOTE: api.func is NOT loaded - no telemetry/statistics will be sent

# Initialize framework
load_functions
catch_errors

# ==============================================================================
# SECTION 2: APPLICATION PARAMETERS
# ==============================================================================

APP="LXC AutoScale"
var_tags="monitoring;automation"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_os="debian"
var_version="13"
var_unprivileged="1"

# ==============================================================================
# SECTION 3: PRE-INSTALLATION - DETECT EXISTING LXC CONTAINERS
# ==============================================================================

detect_lxc_containers() {
    msg_info "Detecting existing LXC containers on Proxmox host"
    
    # Get all LXC containers except the one being created
    DETECTED_LXC=$(pct list 2>/dev/null | awk 'NR>1 {print $1}' | grep -v "^${CTID}$" | tr '\n' ',' | sed 's/,$//')
    
    if [[ -n "$DETECTED_LXC" ]]; then
        msg_ok "Found containers: $DETECTED_LXC"
        export DETECTED_LXC
    else
        msg_info "No existing containers found"
        export DETECTED_LXC=""
    fi
}

# ==============================================================================
# SECTION 4: LOCALE SELECTION
# ==============================================================================

select_locale() {
    if [ "$VERB" == "yes" ]; then
        msg_info "Selecting system locale"
    fi
    
    LOCALE_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "Locale Selection" \
        --menu "Choose system locale:" 12 50 2 \
        "1" "English (en_US.UTF-8)" \
        "2" "Turkish (tr_TR.UTF-8)" \
        3>&1 1>&2 2>&3)
    
    case $LOCALE_CHOICE in
        1)
            SELECTED_LOCALE="en_US.UTF-8"
            LOCALE_NAME="English"
            ;;
        2)
            SELECTED_LOCALE="tr_TR.UTF-8"
            LOCALE_NAME="Turkish"
            ;;
        *)
            SELECTED_LOCALE="en_US.UTF-8"
            LOCALE_NAME="English"
            ;;
    esac
    
    export SELECTED_LOCALE
    export LOCALE_NAME
    
    if [ "$VERB" == "yes" ]; then
        msg_ok "Selected locale: $LOCALE_NAME ($SELECTED_LOCALE)"
    fi
}

# ==============================================================================
# SECTION 5: CONTAINER INSTALLATION SCRIPT
# ==============================================================================

default_settings() {
    msg_info "Using Default Settings"
    echo "Using Default Settings" >>"${BUILD_LOG}"
    detect_lxc_containers
    select_locale
}

# This function will be executed inside the container
install_lxc_autoscale() {
    # Update system
    msg_info "Updating container system"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "System updated"
    
    # Configure locale
    msg_info "Configuring locale: $LOCALE_NAME"
    $STD apt-get install -y locales
    
    if [[ "$SELECTED_LOCALE" == "tr_TR.UTF-8" ]]; then
        echo "tr_TR.UTF-8 UTF-8" >> /etc/locale.gen
    fi
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    
    $STD locale-gen
    $STD update-locale LANG=$SELECTED_LOCALE
    export LANG=$SELECTED_LOCALE
    export LC_ALL=$SELECTED_LOCALE
    msg_ok "Locale configured: $LOCALE_NAME"
    
    # Install dependencies
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
        openssh-client \
        nginx \
        ca-certificates \
        gnupg \
        build-essential \
        python3-dev
    msg_ok "Dependencies installed"
    
    # Create SSH key
    msg_info "Creating SSH key"
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
    SSH_PUBLIC_KEY=$(cat /root/.ssh/id_rsa.pub)
    msg_ok "SSH key created"
    
    # Clone LXC AutoScale repository
    msg_info "Cloning LXC AutoScale repository"
    cd /opt
    $STD git clone https://github.com/fabriziosalmi/proxmox-lxc-autoscale.git lxc-autoscale
    msg_ok "Repository cloned"
    
    # Create directories
    msg_info "Creating directories"
    mkdir -p /etc/lxc_autoscale
    mkdir -p /var/lib/lxc_autoscale/backups
    mkdir -p /var/log
    msg_ok "Directories created"
    
    # Setup application
    msg_info "Setting up LXC AutoScale"
    cp /opt/lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/
    chmod +x /usr/local/bin/lxc_autoscale.py
    msg_ok "Application setup complete"
    
    # Get Proxmox host IP
    HOST_IP=$(ip route get 1 | awk '{print $7}' | head -1)
    
    # Convert detected LXC list to YAML array format
    if [[ -n "$DETECTED_LXC" ]]; then
        LXC_ARRAY="[$DETECTED_LXC]"
    else
        LXC_ARRAY="[]"
    fi
    
    # Create configuration file with detected containers
    msg_info "Creating configuration file"
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
    msg_ok "Configuration created with detected containers"
    
    # Create systemd service
    msg_info "Creating systemd service"
    cat > /etc/systemd/system/lxc_autoscale.service << 'EOF'
[Unit]
Description=LXC AutoScale Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lxc-autoscale
ExecStart=/usr/bin/python3 /usr/local/bin/lxc_autoscale.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable -q --now lxc_autoscale.service
    msg_ok "Service created and started"
    
    # Setup web interface
    msg_info "Setting up web interface"
    mkdir -p /var/www/lxc-autoscale
    
    # Check if original UI exists in repo
    if [ -d "/opt/lxc-autoscale/lxc_autoscale/ui" ]; then
        msg_info "Installing original UI from repository"
        cp -r /opt/lxc-autoscale/lxc_autoscale/ui/* /var/www/lxc-autoscale/
        msg_ok "Original UI installed"
    else
        # Fallback UI
        msg_info "Creating fallback dashboard"
        cat > /var/www/lxc-autoscale/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LXC AutoScale Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; background: #0f172a; color: #e2e8f0; }
        .container { max-width: 1400px; margin: 0 auto; padding: 2rem; }
        header { background: linear-gradient(135deg, #1e293b 0%, #334155 100%); padding: 2rem; border-radius: 1rem; margin-bottom: 2rem; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.3); }
        h1 { color: #38bdf8; font-size: 2rem; margin-bottom: 0.5rem; }
        .subtitle { color: #94a3b8; font-size: 1.1rem; }
        .card { background: #1e293b; padding: 1.5rem; border-radius: 1rem; margin-bottom: 1.5rem; border: 1px solid #334155; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.2); }
        .card h2 { color: #38bdf8; margin-bottom: 1rem; font-size: 1.5rem; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; }
        .info-item { background: #0f172a; padding: 1.5rem; border-radius: 0.75rem; border: 1px solid #1e293b; }
        .info-label { color: #64748b; font-size: 0.875rem; margin-bottom: 0.5rem; text-transform: uppercase; letter-spacing: 0.05em; }
        .info-value { color: #38bdf8; font-size: 1.5rem; font-weight: 600; }
        .status { display: inline-block; padding: 0.5rem 1rem; border-radius: 2rem; font-size: 0.875rem; font-weight: 600; }
        .status.running { background: #059669; color: white; }
        pre { background: #0f172a; padding: 1rem; border-radius: 0.5rem; overflow-x: auto; max-height: 500px; overflow-y: auto; border: 1px solid #1e293b; font-size: 0.875rem; line-height: 1.5; }
        .btn { background: linear-gradient(135deg, #0ea5e9 0%, #38bdf8 100%); color: white; padding: 0.75rem 1.5rem; border: none; border-radius: 0.5rem; cursor: pointer; text-decoration: none; display: inline-block; margin: 0.25rem; font-weight: 600; transition: all 0.2s; }
        .btn:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(14, 165, 233, 0.4); }
        code { background: #1e293b; padding: 0.25rem 0.5rem; border-radius: 0.25rem; color: #38bdf8; font-family: 'Courier New', monospace; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🚀 LXC AutoScale Dashboard</h1>
            <p class="subtitle">Proxmox Container Auto Scaling Management</p>
        </header>

        <div class="card">
            <h2>📊 System Status</h2>
            <div class="info-grid">
                <div class="info-item">
                    <div class="info-label">Service Status</div>
                    <div class="info-value"><span class="status running">RUNNING</span></div>
                </div>
                <div class="info-item">
                    <div class="info-label">Container IP</div>
                    <div class="info-value" id="container-ip">Loading...</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Managed Containers</div>
                    <div class="info-value" id="managed-containers">Loading...</div>
                </div>
            </div>
        </div>

        <div class="card">
            <h2>🎯 Quick Actions</h2>
            <a href="/api/logs" class="btn" target="_blank">📄 View Logs</a>
            <a href="/api/metrics" class="btn" target="_blank">📊 View Metrics</a>
            <button class="btn" onclick="location.reload()">🔄 Refresh</button>
        </div>

        <div class="card">
            <h2>📝 Recent Logs (Last 100 lines)</h2>
            <pre id="logs">Loading logs...</pre>
        </div>

        <div class="card">
            <h2>⚙️ Configuration</h2>
            <p style="margin-bottom: 1rem;">Manage your LXC AutoScale configuration:</p>
            <p><strong>Config file:</strong> <code>/etc/lxc_autoscale/lxc_autoscale.yaml</code></p>
            <p><strong>Edit config:</strong> <code>nano /etc/lxc_autoscale/lxc_autoscale.yaml</code></p>
            <p><strong>Restart service:</strong> <code>systemctl restart lxc_autoscale</code></p>
            <p><strong>View service logs:</strong> <code>journalctl -u lxc_autoscale -f</code></p>
        </div>
    </div>

    <script>
        async function loadStatus() {
            try {
                const response = await fetch('/api/logs');
                const logs = await response.text();
                document.getElementById('logs').textContent = logs.split('\n').slice(-100).join('\n');
            } catch(e) {
                document.getElementById('logs').textContent = 'Error loading logs: ' + e.message;
            }
            
            document.getElementById('container-ip').textContent = window.location.hostname;
            
            try {
                const response = await fetch('/api/metrics');
                const metrics = await response.json();
                if (metrics.containers) {
                    document.getElementById('managed-containers').textContent = metrics.containers.length;
                }
            } catch(e) {
                document.getElementById('managed-containers').textContent = 'N/A';
            }
        }
        
        loadStatus();
        setInterval(loadStatus, 30000);
    </script>
</body>
</html>
HTMLEOF
        msg_ok "Fallback UI created"
    fi
    
    # Configure Nginx
    cat > /etc/nginx/sites-available/lxc-autoscale << 'EOF'
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
        add_header Content-Type 'text/plain; charset=utf-8';
    }
    
    location /api/metrics {
        alias /var/log/lxc_autoscale.json;
        default_type application/json;
        add_header Content-Type 'application/json; charset=utf-8';
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/lxc-autoscale /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
    msg_ok "Web interface configured"
}

# ==============================================================================
# SECTION 6: UPDATE SCRIPT
# ==============================================================================

update_script() {
    header_info
    check_container_storage
    check_container_resources
    
    if [[ ! -d /opt/lxc-autoscale ]]; then
        msg_error "LXC AutoScale is not installed"
        exit
    fi
    
    msg_info "Updating LXC AutoScale"
    cd /opt/lxc-autoscale
    $STD git pull
    
    systemctl restart lxc_autoscale
    msg_ok "Updated LXC AutoScale"
    exit
}

# ==============================================================================
# SECTION 7: START INSTALLATION
# ==============================================================================

start
build_container
description

# Container description
cat <<EOF > /dev/null
LXC AutoScale - Automated Container Resource Management

Configuration:
  - Config: /etc/lxc_autoscale/lxc_autoscale.yaml
  - Logs: /var/log/lxc_autoscale.log
  - Service: systemctl status lxc_autoscale
  
Web Interface:
  - URL: http://CONTAINER_IP:8080
  
Documentation:
  - https://github.com/fabriziosalmi/proxmox-lxc-autoscale
EOF
