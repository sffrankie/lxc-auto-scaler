#!/usr/bin/env bash

# LXC AutoScale Installation Script
# Copyright (c) 2025 Murat
# License: MIT

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
CTID=""
TEMPLATE="debian-13-standard_13.1-2_amd64.tar.zst"
STORAGE_TEMPLATE="local"
STORAGE_ROOT="local-lvm"
HOSTNAME="lxc-autoscale"
CORES="2"
MEMORY="2048"
SWAP="512"
DISK="8"
PASSWORD="autoscale$(date +%s)"

# Helper functions
msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if root
if [[ $EUID -ne 0 ]]; then
   msg_error "This script must be run as root"
   exit 1
fi

# Get next available CTID
get_next_ctid() {
    local id=100
    while pct status $id &>/dev/null || qm status $id &>/dev/null; do
        ((id++))
    done
    echo $id
}

CTID=$(get_next_ctid)
HOSTNAME="${HOSTNAME}-${CTID}"

msg_info "Starting LXC AutoScale Installation"
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo ""

# Check template
msg_info "Checking template"
if ! pveam list $STORAGE_TEMPLATE | grep -q "$TEMPLATE"; then
    msg_info "Template not found, updating list"
    pveam update
    
    msg_info "Downloading template"
    pveam download $STORAGE_TEMPLATE $TEMPLATE
fi
msg_ok "Template ready"

# Get available storages
msg_info "Available storages for container:"
mapfile -t STORAGES < <(pvesm status | grep -v '^Name' | grep -E 'active|available' | awk '{print $1}' | grep -v "^local$")

if [ ${#STORAGES[@]} -eq 0 ]; then
    msg_error "No suitable storage found"
    exit 1
fi

# Display storage menu
echo ""
for i in "${!STORAGES[@]}"; do
    echo "  $((i+1)). ${STORAGES[$i]}"
done
echo ""

# Ask user to select
while true; do
    read -p "Select storage (1-${#STORAGES[@]}): " STORAGE_CHOICE
    if [[ "$STORAGE_CHOICE" =~ ^[0-9]+$ ]] && [ "$STORAGE_CHOICE" -ge 1 ] && [ "$STORAGE_CHOICE" -le ${#STORAGES[@]} ]; then
        STORAGE_ROOT="${STORAGES[$((STORAGE_CHOICE-1))]}"
        break
    else
        msg_error "Invalid selection. Please choose 1-${#STORAGES[@]}"
    fi
done

msg_ok "Selected storage: $STORAGE_ROOT"

# Create container
msg_info "Creating container"
pct create $CTID ${STORAGE_TEMPLATE}:vztmpl/${TEMPLATE} \
    --hostname $HOSTNAME \
    --cores $CORES \
    --memory $MEMORY \
    --swap $SWAP \
    --rootfs ${STORAGE_ROOT}:${DISK} \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --features nesting=1 \
    --unprivileged 1 \
    --onboot 1 \
    --password "$PASSWORD" \
    --start 1

msg_ok "Container created (ID: $CTID)"

# Wait for container to start
msg_info "Waiting for container to start"
sleep 10

# Get container IP
msg_info "Getting container IP"
for i in {1..30}; do
    CONTAINER_IP=$(pct exec $CTID -- hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$CONTAINER_IP" ]]; then
        msg_ok "Container IP: $CONTAINER_IP"
        break
    fi
    sleep 2
done

if [[ -z "$CONTAINER_IP" ]]; then
    msg_error "Could not get container IP"
    exit 1
fi

# Update container
msg_info "Updating container system"
pct exec $CTID -- bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
msg_ok "System updated"

# Install dependencies
msg_info "Installing dependencies"
pct exec $CTID -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
    ca-certificates"
msg_ok "Dependencies installed"

# Create SSH key
msg_info "Creating SSH key"
pct exec $CTID -- bash -c "mkdir -p /root/.ssh && ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' -q"
msg_ok "SSH key created"

# Clone repository
msg_info "Cloning LXC AutoScale repository"
pct exec $CTID -- bash -c "cd /opt && git clone https://github.com/fabriziosalmi/proxmox-lxc-autoscale.git lxc-autoscale"
msg_ok "Repository cloned"

# Create directories
msg_info "Creating directories"
pct exec $CTID -- bash -c "mkdir -p /etc/lxc_autoscale /var/lib/lxc_autoscale/backups /var/log"
msg_ok "Directories created"

# Setup application
msg_info "Setting up LXC AutoScale"
pct exec $CTID -- bash -c "cp /opt/lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/lxc_autoscale.py && chmod +x /usr/local/bin/lxc_autoscale.py"
msg_ok "Application setup complete"

# Get Proxmox host IP
HOST_IP=$(hostname -I | awk '{print $1}')

# Detect all LXC containers on host
msg_info "Detecting LXC containers on Proxmox host"
DETECTED_LXC=$(pct list | grep -v VMID | awk '{print $1}' | grep -v "^$CTID$" | tr '\n' ',' | sed 's/,$//')

if [[ -n "$DETECTED_LXC" ]]; then
    msg_ok "Found containers: $DETECTED_LXC"
    LXC_ARRAY="[$DETECTED_LXC]"
else
    msg_info "No existing containers found"
    LXC_ARRAY="[]"
fi

# Create config
msg_info "Creating configuration file"
pct exec $CTID -- bash -c "cat > /etc/lxc_autoscale/lxc_autoscale.yaml << 'EOF'
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
EOF"
msg_ok "Configuration created with detected containers"

# Create systemd service
msg_info "Creating systemd service"
pct exec $CTID -- bash -c "cat > /etc/systemd/system/lxc_autoscale.service << 'EOF'
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
EOF"

pct exec $CTID -- bash -c "systemctl daemon-reload && systemctl enable lxc_autoscale.service && systemctl start lxc_autoscale.service"
msg_ok "Service created and started"

# Setup web interface
msg_info "Setting up web interface"
pct exec $CTID -- bash -c "mkdir -p /var/www/lxc-autoscale"

# Copy original UI from repository if exists
if pct exec $CTID -- bash -c "[ -d /opt/lxc-autoscale/lxc_autoscale/ui ]"; then
    msg_info "Copying original UI files"
    pct exec $CTID -- bash -c "cp -r /opt/lxc-autoscale/lxc_autoscale/ui/* /var/www/lxc-autoscale/ 2>/dev/null || true"
    msg_ok "Original UI installed"
else
    # Fallback: Create simple dashboard
    msg_info "Creating fallback dashboard"
    pct exec $CTID -- bash -c "cat > /var/www/lxc-autoscale/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>LXC AutoScale Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #1a1a2e; color: #eee; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        header { background: #16213e; padding: 20px; border-radius: 10px; margin-bottom: 20px; }
        h1 { color: #00d9ff; }
        .card { background: #16213e; padding: 20px; border-radius: 10px; margin-bottom: 20px; }
        .card h2 { color: #00d9ff; margin-bottom: 15px; }
        pre { background: #0f0f23; padding: 15px; border-radius: 5px; overflow-x: auto; max-height: 400px; }
        .btn { background: #00d9ff; color: #000; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; text-decoration: none; display: inline-block; margin: 5px; }
        .btn:hover { background: #00b8d4; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; }
        .info-item { background: #0f0f23; padding: 15px; border-radius: 5px; }
        .info-label { color: #888; font-size: 12px; margin-bottom: 5px; }
        .info-value { color: #00d9ff; font-size: 18px; font-weight: bold; }
        .status.running { background: #00ff88; color: #000; padding: 5px 15px; border-radius: 20px; display: inline-block; }
    </style>
</head>
<body>
    <div class=\"container\">
        <header>
            <h1>🚀 LXC AutoScale Dashboard</h1>
            <p>Proxmox Container Auto Scaling System</p>
        </header>

        <div class=\"card\">
            <h2>System Status</h2>
            <div class=\"info-grid\">
                <div class=\"info-item\">
                    <div class=\"info-label\">Service Status</div>
                    <div class=\"info-value\"><span class=\"status running\">RUNNING</span></div>
                </div>
                <div class=\"info-item\">
                    <div class=\"info-label\">Container IP</div>
                    <div class=\"info-value\" id=\"container-ip\"></div>
                </div>
            </div>
        </div>

        <div class=\"card\">
            <h2>Quick Actions</h2>
            <a href=\"/api/logs\" class=\"btn\" target=\"_blank\">📄 View Logs</a>
            <a href=\"/api/metrics\" class=\"btn\" target=\"_blank\">📊 View Metrics</a>
            <button class=\"btn\" onclick=\"location.reload()\">🔄 Refresh</button>
        </div>

        <div class=\"card\">
            <h2>📝 Recent Logs (Last 100 lines)</h2>
            <pre id=\"logs\">Loading logs...</pre>
        </div>

        <div class=\"card\">
            <h2>⚙️ Configuration</h2>
            <p>Config file: <code>/etc/lxc_autoscale/lxc_autoscale.yaml</code></p>
            <p>Edit config: <code>nano /etc/lxc_autoscale/lxc_autoscale.yaml</code></p>
            <p>Restart service: <code>systemctl restart lxc_autoscale</code></p>
        </div>
    </div>

    <script>
        async function loadStatus() {
            try {
                const response = await fetch('/api/logs');
                const logs = await response.text();
                document.getElementById('logs').textContent = logs.split('\\n').slice(-100).join('\\n');
            } catch(e) {
                document.getElementById('logs').textContent = 'Error loading logs: ' + e.message;
            }
            document.getElementById('container-ip').textContent = window.location.hostname;
        }
        loadStatus();
        setInterval(loadStatus, 30000);
    </script>
</body>
</html>
HTMLEOF"
fi

pct exec $CTID -- bash -c "cat > /etc/nginx/sites-available/lxc-autoscale << 'EOF'
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
        add_header Content-Type 'text/plain; charset=utf-8';
    }
    
    location /api/metrics {
        alias /var/log/lxc_autoscale.json;
        default_type application/json;
        add_header Content-Type 'application/json; charset=utf-8';
    }
}
EOF"

pct exec $CTID -- bash -c "ln -sf /etc/nginx/sites-available/lxc-autoscale /etc/nginx/sites-enabled/ && rm -f /etc/nginx/sites-enabled/default && systemctl restart nginx"
msg_ok "Web interface configured"

# Get SSH public key
SSH_PUBLIC_KEY=$(pct exec $CTID -- cat /root/.ssh/id_rsa.pub)

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          LXC AutoScale Installation Complete!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Container Information:${NC}"
echo -e "  Container ID    : ${GREEN}$CTID${NC}"
echo -e "  Hostname        : ${GREEN}$HOSTNAME${NC}"
echo -e "  IP Address      : ${GREEN}$CONTAINER_IP${NC}"
echo -e "  Root Password   : ${YELLOW}$PASSWORD${NC}"
echo ""
echo -e "${BLUE}Access:${NC}"
echo -e "  Web Interface   : ${GREEN}http://${CONTAINER_IP}:8080${NC}"
echo -e "  SSH             : ${GREEN}ssh root@${CONTAINER_IP}${NC}"
echo -e "  Console         : ${GREEN}pct enter $CTID${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo -e "  Config File     : ${GREEN}/etc/lxc_autoscale/lxc_autoscale.yaml${NC}"
echo -e "  Log File        : ${GREEN}/var/log/lxc_autoscale.log${NC}"
if [[ -n "$DETECTED_LXC" ]]; then
echo -e "  Managed LXCs    : ${GREEN}$DETECTED_LXC${NC}"
fi
echo ""
echo -e "${YELLOW}IMPORTANT - Add SSH Key to Proxmox Host:${NC}"
echo -e "${GREEN}echo '$SSH_PUBLIC_KEY' >> /root/.ssh/authorized_keys${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Add SSH key to Proxmox host (command above)"
echo "  2. Check detected containers: pct exec $CTID -- cat /etc/lxc_autoscale/lxc_autoscale.yaml"
echo "  3. View logs: pct exec $CTID -- journalctl -u lxc_autoscale -f"
echo "  4. Access web UI: http://${CONTAINER_IP}:8080"
echo ""
