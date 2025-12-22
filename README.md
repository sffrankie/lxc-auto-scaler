# LXC AutoScale - Automated Container Installation Script

Based on https://github.com/fabriziosalmi/proxmox-lxc-autoscale?tab=readme-ov-file

Based on https://github.com/community-scripts/ProxmoxVE/tree/main

Professional installation script for LXC AutoScale on Proxmox VE, built using community-scripts framework.

## Features

- ✅ Automatic LXC container creation using community-scripts framework
- ✅ Interactive installation with colored output
- ✅ Debian 13 template
- ✅ Pre-configured resources (2 CPU, 2GB RAM, 8GB disk)
- ✅ SSH key auto-generation and setup
- ✅ Nginx web interface on port 8080
- ✅ Systemd service with auto-restart
- ✅ Update script included
- ✅ MOTD integration

## Requirements

- Proxmox VE 8.x
- Root access
- Internet connection

## Quick Installation

### One-Line Install

```bash
bash <(curl -s https://raw.githubusercontent.com/YOUR_REPO/lxc-autoscale.sh)
```

### Manual Installation

```bash
# Download script
wget https://raw.githubusercontent.com/YOUR_REPO/lxc-autoscale.sh

# Make executable
chmod +x lxc-autoscale.sh

# Run
./lxc-autoscale.sh
```

## What Does This Script Do?

1. **Creates LXC Container**: Uses community-scripts framework to create a new container
2. **System Update**: Updates the container OS and installs dependencies
3. **Installs Python Dependencies**: Python3, pip, yaml, requests, paramiko, cryptography
4. **SSH Setup**: Creates SSH keys for passwordless connection to Proxmox host
5. **LXC AutoScale Installation**: Clones repository and sets up the application
6. **Configuration**: Creates YAML config file (asks for Proxmox host IP)
7. **Systemd Service**: Creates and starts the autoscale service
8. **Web Interface**: Installs Nginx and sets up web UI on port 8080
9. **Summary**: Displays all connection details and next steps

## Post-Installation

After installation completes, you will see:

- Container IP address
- Web interface URL (http://CONTAINER_IP:8080)
- SSH public key (to add to Proxmox host)
- Configuration file location

### 1. Add SSH Key to Proxmox Host

On the **Proxmox host**, run:

```bash
echo 'YOUR_SSH_PUBLIC_KEY' >> /root/.ssh/authorized_keys
```

### 2. Configure Container IDs

Edit the configuration file:

```bash
pct enter CONTAINER_ID
nano /etc/lxc_autoscale/lxc_autoscale.yaml
```

Add your container IDs:

```yaml
TIER_DEFAULT:
  lxc_containers: [100, 101, 102]
```

### 3. Restart Service

```bash
systemctl restart lxc_autoscale
```

### 4. Monitor Logs

```bash
journalctl -u lxc_autoscale -f
```

## Configuration

### Main Configuration File

Location: `/etc/lxc_autoscale/lxc_autoscale.yaml`

```yaml
DEFAULTS:
  log_file: /var/log/lxc_autoscale.log
  check_interval: 300
  use_remote_proxmox: true
  ssh_user: root
  ssh_key: /root/.ssh/id_rsa
  proxmox_host: YOUR_PROXMOX_IP

TIER_DEFAULT:
  cpu_upper_threshold: 80
  cpu_lower_threshold: 20
  memory_upper_threshold: 70
  memory_lower_threshold: 20
  min_cores: 1
  max_cores: 4
  min_memory: 512
  max_memory: 4096
  lxc_containers: [100, 101, 102]
```

## Service Management

```bash
# Check status
systemctl status lxc_autoscale

# Start service
systemctl start lxc_autoscale

# Stop service
systemctl stop lxc_autoscale

# Restart service
systemctl restart lxc_autoscale

# View logs
journalctl -u lxc_autoscale -f
```

## Web Interface

The web interface is accessible at:

```
http://CONTAINER_IP:8080
```

### API Endpoints

- `/api/logs` - View log file
- `/api/metrics` - JSON metrics

## Updating

To update LXC AutoScale to the latest version:

```bash
pct enter CONTAINER_ID
bash /root/update.sh
```

Or manually:

```bash
systemctl stop lxc_autoscale
cd /opt/lxc-autoscale
git pull
cp /opt/lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/lxc_autoscale.py
systemctl start lxc_autoscale
```

## Container Specifications

- **OS**: Debian 13
- **CPU**: 2 cores
- **RAM**: 2048 MB
- **Swap**: 512 MB
- **Disk**: 8 GB
- **Network**: DHCP on vmbr0
- **Features**: Nesting enabled
- **Type**: Unprivileged container

## Customization

You can customize the container resources by editing the script before running:

```bash
var_disk="8"     # Disk size in GB
var_cpu="2"      # CPU cores
var_ram="2048"   # RAM in MB
```

## Troubleshooting

### Container won't start

```bash
pct start CONTAINER_ID
journalctl -xe
```

### Service not running

```bash
pct enter CONTAINER_ID
systemctl status lxc_autoscale
journalctl -u lxc_autoscale -n 100
```

### SSH connection fails

```bash
# Inside container
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ''
cat /root/.ssh/id_rsa.pub

# On Proxmox host
echo "PUBLIC_KEY" >> /root/.ssh/authorized_keys
```

### Web interface not accessible

```bash
systemctl status nginx
netstat -tlnp | grep 8080
```

## Removal

To remove the container completely:

```bash
pct stop CONTAINER_ID
pct destroy CONTAINER_ID
```

## File Locations

```
/opt/lxc-autoscale/                      # Application directory
/etc/lxc_autoscale/lxc_autoscale.yaml   # Configuration file
/usr/local/bin/lxc_autoscale.py         # Main script
/var/log/lxc_autoscale.log              # Log file
/var/log/lxc_autoscale.json             # JSON metrics
/var/lib/lxc_autoscale/backups/         # Backup directory
/var/www/lxc-autoscale/                 # Web interface
/etc/systemd/system/lxc_autoscale.service # Systemd service
/root/.ssh/id_rsa                        # SSH private key
/root/.ssh/id_rsa.pub                    # SSH public key
```

## License

MIT License

## Credits

- Built using [community-scripts framework](https://github.com/community-scripts/ProxmoxVE)
- LXC AutoScale by [fabriziosalmi](https://github.com/fabriziosalmi/proxmox-lxc-autoscale)

## Support

For issues and support:
- GitHub Issues
- Community Forums

## Contributing

Pull requests are welcome. For major changes, please open an issue first.
