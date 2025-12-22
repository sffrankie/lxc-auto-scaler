# LXC AutoScale - Automated Proxmox LXC Container Installer

🚀 **One-command installer for [LXC AutoScale](https://github.com/fabriziosalmi/proxmox-lxc-autoscale)** with automatic container detection, locale selection, and professional UI setup.

Built using the [Community-Scripts](https://github.com/community-scripts/ProxmoxVE) framework for seamless Proxmox VE integration.

---

## 🎯 Features

- ✅ **One-Command Installation** - Single bash command to deploy everything
- ✅ **Automatic LXC Detection** - Automatically finds and configures existing containers
- ✅ **Multi-Language Support** - English and Turkish locale options
- ✅ **Professional UI** - Modern dark-themed web interface on port 8080
- ✅ **SSH Key Management** - Automatic SSH key generation and setup
- ✅ **Community-Scripts Framework** - Whiptail menus, advanced/default modes
- ✅ **No Telemetry** - Privacy-focused, no data collection

---

## 📋 Requirements

- **Proxmox VE** 8.4.x or 9.0.x
- **Root Access** to Proxmox host
- **Internet Connection** for downloading packages

---

## 🚀 Quick Start

Run this single command on your **Proxmox host**:

```bash
bash <(curl -s https://raw.githubusercontent.com/droltr/lxc-auto-scaler/main/lxc-autoscale.sh)
```

The installer will:
1. Show interactive menu (Default/Advanced mode)
2. Detect existing LXC containers
3. Ask for locale preference (EN/TR)
4. Create and configure the container
5. Install LXC AutoScale
6. Setup web interface
7. Display access information

---

## 📊 What Gets Installed

### LXC Container Specifications
- **OS:** Debian 13 (Trixie)
- **Type:** Unprivileged
- **CPU:** 2 cores (configurable)
- **RAM:** 2048 MB (configurable)
- **Disk:** 8 GB (configurable)
- **Network:** DHCP (configurable)

### Software Components
- **LXC AutoScale** - Resource auto-scaling daemon
- **Python 3** - Runtime environment
- **Nginx** - Web server (port 8080)
- **SSH Server** - Remote access
- **Original UI** - Web dashboard from upstream project

---

## 🎨 Web Interface

After installation, access the dashboard at:

```
http://<CONTAINER_IP>:8080
```

Features:
- 📝 Live log viewer (last 100 lines)
- 📈 Container metrics


---

## 🔧 Post-Installation

### 1. Add SSH Key to Proxmox Host

The installer displays an SSH key at the end. Run the provided command on your Proxmox host:

```bash
echo 'ssh-rsa AAAA...' >> /root/.ssh/authorized_keys
```

### 2. Configure Container List

Edit the configuration file:

```bash
nano /etc/lxc_autoscale/lxc_autoscale.yaml
```

Add container IDs to monitor:

```yaml
TIER_DEFAULT:
  lxc_containers: [101, 102, 103]  # Your container IDs
```

### 3. Restart Service

```bash
systemctl restart lxc_autoscale
```

---

## 🔧 Post-Installation (REQUIRED)

### ⚠️ IMPORTANT: These steps are MANDATORY for the system to work

The installation completes successfully, but AutoScale cannot function until you complete these steps:

### 1. Add SSH Key to Proxmox Host (CRITICAL)

The installer displays an SSH public key. This key MUST be added to your Proxmox host:

```bash
# On Proxmox host (NOT in the container):
echo 'ssh-rsa AAAA...' >> /root/.ssh/authorized_keys
```

**Why:** The AutoScale service runs inside the LXC container but needs to execute `pct` commands on the Proxmox host via SSH.

**Test the connection:**
```bash
# Inside the container:
ssh root@PROXMOX_IP "pct list"
```

If this works, SSH is configured correctly.

### 2. Add Container IDs to Monitor (CRITICAL)

Edit the configuration file **inside the container**:

```bash
# Inside the container (pct enter CONTAINER_ID):
nano /etc/lxc_autoscale/lxc_autoscale.yaml
```

Find the `TIER_DEFAULT` section and add your container IDs:

```yaml
TIER_DEFAULT:
  cpu_upper_threshold: 80
  cpu_lower_threshold: 20
  memory_upper_threshold: 70
  memory_lower_threshold: 20
  min_cores: 1
  max_cores: 4
  min_memory: 512
  max_memory: 4096
  lxc_containers: [101, 102, 103]  # ← ADD YOUR CONTAINER IDs HERE
```

**Get container IDs from Proxmox:**
```bash
# On Proxmox host:
pct list
```

**Important:** Do NOT add the AutoScale container itself to the list!

### 3. Restart Services

After adding container IDs:

```bash
# Inside the container:
systemctl restart lxc_autoscale
systemctl restart lxc_autoscale_ui
```

### 4. Verify Everything Works

```bash
# Check service status
systemctl status lxc_autoscale
systemctl status lxc_autoscale_ui

# Watch the logs (you should see container metrics)
tail -f /var/log/lxc_autoscale.log
```

**Expected log output:**
```
Container 101 - CPU usage: 25.3%, Memory usage: 45.2%
Container 102 - CPU usage: 10.1%, Memory usage: 30.5%
```

If you see `pct: not found` errors, SSH key was not added correctly.

---

## 🐛 Troubleshooting

### Web UI Not Accessible

**Symptom:** Cannot access http://CONTAINER_IP:8080

**Check:**
```bash
# Is Flask UI running?
systemctl status lxc_autoscale_ui

# Is port 5000 listening?
ss -tlnp | grep 5000

# Is Nginx running?
systemctl status nginx

# Check Nginx error log
tail -20 /var/log/nginx/error.log
```

**Common Issues:**
- Flask UI service failed to start: Check `/var/log/flask_ui.log` if it exists
- Port 5000 not listening: Service may be restarting, wait 10 seconds
- 502 Bad Gateway: Flask UI starting up, refresh after a few seconds

### AutoScale Service Not Working

**Symptom:** Containers not being scaled

**Check:**
```bash
# View service logs
journalctl -u lxc_autoscale -n 50

# Check configuration
cat /etc/lxc_autoscale/lxc_autoscale.yaml

# Test SSH connection to Proxmox host
ssh root@PROXMOX_IP "pct list"
```

**Common Issues:**
- SSH key not added to Proxmox host
- No containers configured in YAML
- Proxmox host IP incorrect in config

### Container Login Has No Prompt

**Symptom:** Can execute commands but no prompt visible

**Temporary Fix:**
```bash
export PS1='\u@\h:\w\$ '
```

**Permanent Fix:**
Add to `/root/.bashrc`:
```bash
echo 'export PS1="\u@\h:\w\$ "' >> /root/.bashrc
```

---

## 📖 Configuration

Main configuration file: `/etc/lxc_autoscale/lxc_autoscale.yaml`

Key settings:
- **CPU/Memory Thresholds** - When to scale up/down
- **Min/Max Resources** - Resource limits
- **Check Interval** - Polling frequency (default: 5 minutes)
- **Container List** - Which containers to manage
- **Off-Peak Hours** - Resource optimization schedule

For detailed configuration options, see the [LXC AutoScale Documentation](https://github.com/fabriziosalmi/proxmox-lxc-autoscale).

---

## 🛠️ Service Management

```bash
# Check service status
systemctl status lxc_autoscale

# View live logs
journalctl -u lxc_autoscale -f

# Restart service
systemctl restart lxc_autoscale

# Stop service
systemctl stop lxc_autoscale

# View log file
tail -f /var/log/lxc_autoscale.log
```

---

## 🔄 Updating

To update LXC AutoScale to the latest version:

```bash
# SSH into the container
pct enter <CONTAINER_ID>

# Update repository
cd /opt/lxc-autoscale
git pull

# Restart service
systemctl restart lxc_autoscale
```

---

## 🗑️ Uninstallation

To remove the container:

```bash
# Stop the container
pct stop <CONTAINER_ID>

# Delete the container
pct destroy <CONTAINER_ID>
```

---

## 🙏 Credits

This installer is built upon the excellent work of:

### LXC AutoScale
- **Author:** [Fabrizio Salmi](https://github.com/fabriziosalmi)
- **Project:** [proxmox-lxc-autoscale](https://github.com/fabriziosalmi/proxmox-lxc-autoscale)
- **Description:** Automatically scale LXC containers resources on Proxmox hosts

### Community Scripts
- **Project:** [ProxmoxVE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE)
- **Website:** [helper-scripts.com](https://helper-scripts.com)
- **Description:** Community-driven Proxmox VE automation scripts
- **Original Creator:** tteck (in memoriam)

---

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Areas for Improvement
- Additional locale support
- Enhanced UI features
- Configuration templates
- Documentation improvements

---

## 🐛 Issues & Support

- **LXC AutoScale Issues:** [Report here](https://github.com/fabriziosalmi/proxmox-lxc-autoscale/issues)
- **Installer Issues:** [Report here](https://github.com/droltr/lxc-auto-scaler/issues)
- **Community Scripts:** [Discord](https://discord.gg/3AnUqsXnmK)

---

## 📚 Documentation

- [LXC AutoScale Documentation](https://github.com/fabriziosalmi/proxmox-lxc-autoscale/tree/main/docs)
- [Community Scripts Wiki](https://github.com/community-scripts/ProxmoxVE/wiki)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)

---

## ⚠️ Disclaimer
I’m new to this kind of work, so if I’ve violated any rules, I apologize in advance to those concerned.
I think I may have made a mistake with the name; it should probably end with “installer.” If this will cause a serious issue, we can change it.
I hope I have properly credited the original code owners in the correct place.
I did not intend to make any changes to their code, but if I accidentally did (with AI – Claude), I would like to apologize for that as well.
Please excuse my inexperience.
This tool is provided as-is without any warranty. Always test in a non-production environment first. The author assumes no responsibility for any damage or issues that may arise from using this installer.

---

## 🌟 Star History

If this project helped you, please consider giving it a ⭐!

---

**Made with ❤️ for the Proxmox community**
