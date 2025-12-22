# Installation Notes - Manual Fixes Applied

This document describes all manual fixes that were applied during testing and are now incorporated into the installation script.

---

## 🔧 Issues Fixed

### 1. DEFAULT vs DEFAULTS Configuration Bug (CRITICAL UPSTREAM BUG)

**Problem:**
```python
# lxc_utils.py line 69:
use_remote_proxmox = config.get('DEFAULT', {}).get('use_remote_proxmox', False)
#                                 ^^^^^^^^ expects 'DEFAULT' (singular)

# But example config uses:
DEFAULTS:  # ← 'DEFAULTS' (plural)
  use_remote_proxmox: true
```

**Root Cause:**
- Upstream example configuration uses `DEFAULTS:` (plural)
- Python code looks for `DEFAULT:` (singular)
- When mismatch occurs, `use_remote_proxmox` is ignored
- System tries to run `pct` locally instead of via SSH
- Result: `pct: not found` error, AutoScale completely broken

**Impact:**
```bash
# With DEFAULTS (wrong):
Container 1002 - ERROR: pct: not found
Ignoring LXC Containers: set()  # ← No containers monitored!

# With DEFAULT (correct):
Container 1002 - CPU usage: 22.09%, Memory usage: 47.99%
Container 1025 - Decreasing memory by 128MB  # ← Working!
```

**Solution:**
```bash
# Changed in install script:
cat > /etc/lxc_autoscale/lxc_autoscale.yaml << EOF
DEFAULT:  # ← Singular, matches code expectation
  use_remote_proxmox: true
  ...
EOF
```

**Script Implementation:**
Added comment in SECTION 8 explaining the bug and why we use `DEFAULT` instead of `DEFAULTS`.

**Upstream Bug Report:**
See `UPSTREAM_BUG_REPORT.md` for detailed analysis to submit to original project.

---

### 2. Flask-SocketIO Missing Dependency

### 1. Flask-SocketIO Missing Dependency

**Problem:**
```
ModuleNotFoundError: No module named 'flask_socketio'
```

**Root Cause:**
- Flask-SocketIO not available in Debian 13 package repositories
- Required by original UI's `lxc_autoscale_ui.py`

**Solution:**
```bash
pip3 install flask-socketio --break-system-packages
```

**Script Implementation:**
Added after apt dependencies in SECTION 3.

---

### 2. AutoScale Service - Module Import Error

**Problem:**
```
ModuleNotFoundError: No module named 'config'
```

**Root Cause:**
```ini
# Wrong:
WorkingDirectory=/opt/lxc-autoscale
ExecStart=/usr/bin/python3 /usr/local/bin/lxc_autoscale.py

# Python looks for config.py in /opt/lxc-autoscale/
# But config.py is in /opt/lxc-autoscale/lxc_autoscale/
```

**Solution:**
```ini
# Correct:
WorkingDirectory=/opt/lxc-autoscale/lxc_autoscale
ExecStart=/usr/bin/python3 lxc_autoscale.py
```

**Script Implementation:**
Fixed in SECTION 9 systemd service creation.

---

### 3. Flask UI - Production Mode Error

**Problem:**
```
RuntimeError: The Werkzeug web server is not designed to run in production.
Pass allow_unsafe_werkzeug=True to the run() method to disable this error.
```

**Root Cause:**
```python
# Original code:
socketio.run(app, host='0.0.0.0', port=5000, debug=False)

# When FLASK_ENV=production set in systemd:
# Flask-SocketIO rejects Werkzeug as unsafe for production
```

**Solution:**
```python
# Patched code:
socketio.run(app, allow_unsafe_werkzeug=True, host='0.0.0.0', port=5000, debug=False)
```

**Script Implementation:**
```bash
sed -i 's/socketio.run(app, host/socketio.run(app, allow_unsafe_werkzeug=True, host/' \
    /var/www/lxc-autoscale/lxc_autoscale_ui.py
```

Added in SECTION 10 after copying UI files.

---

### 4. Flask UI Service - User Permissions

**Problem:**
- Service fails with `www-data` user
- Port binding issues
- File access problems

**Root Cause:**
- Flask debug mode (even with debug=False) needs special permissions
- www-data cannot fork processes for reloader
- Systemd service isolation

**Solution:**
```ini
# Changed from:
User=www-data
Group=www-data
WorkingDirectory=/var/www/lxc-autoscale

# To:
User=root
Group=root
ExecStart=/bin/bash -c 'cd /var/www/lxc-autoscale && /usr/bin/python3 -u lxc_autoscale_ui.py'
```

**Script Implementation:**
Fixed in SECTION 10 Flask UI service creation.

---

### 5. FLASK_ENV=production Conflicts

**Problem:**
Setting `FLASK_ENV=production` in systemd causes Flask-SocketIO to reject Werkzeug.

**Solution:**
Remove `Environment="FLASK_ENV=production"` from service file entirely.

**Script Implementation:**
Not included in service file template.

---

### 6. Section Numbering

**Problem:**
Two sections numbered as "SECTION 12"

**Solution:**
Renumbered:
- SECTION 12: Display SSH Key
- SECTION 13: Final Information Display
- SECTION 14: Create MOTD

**Script Implementation:**
Fixed in final script version.

---

## ✅ Verification Steps

After installation completes, verify:

```bash
# 1. Check services are running
systemctl status lxc_autoscale
systemctl status lxc_autoscale_ui

# 2. Verify ports are listening
ss -tlnp | grep 5000  # Flask UI
ss -tlnp | grep 8080  # Nginx proxy

# 3. Test web access
curl http://localhost:8080

# 4. Check logs
journalctl -u lxc_autoscale -n 20
journalctl -u lxc_autoscale_ui -n 20
```

---

## 📋 Post-Installation Checklist

- [ ] Add SSH key to Proxmox host
- [ ] Configure LXC container IDs in YAML
- [ ] Restart both services
- [ ] Test web UI access
- [ ] Verify AutoScale daemon connects to Proxmox
- [ ] Monitor first scaling action

---

## 🔍 Common Issues During Installation

### Issue: Flask UI Service Shows "activating (auto-restart)"

**Diagnosis:**
```bash
# Check what's failing
journalctl -u lxc_autoscale_ui -n 50
# or if journal unavailable:
cat /var/log/flask_ui.log  # if rc.local was used
```

**Likely Causes:**
1. `allow_unsafe_werkzeug` not added
2. Port 5000 already in use
3. Python path incorrect

### Issue: 502 Bad Gateway on Port 8080

**Diagnosis:**
```bash
# Flask UI must be running first
systemctl status lxc_autoscale_ui

# Port 5000 must be listening
ss -tlnp | grep 5000
```

**Solution:**
Wait 5-10 seconds for Flask to fully start, then refresh browser.

### Issue: AutoScale Service Crash Loop

**Diagnosis:**
```bash
# Check working directory
grep WorkingDirectory /etc/systemd/system/lxc_autoscale.service

# Should show: /opt/lxc-autoscale/lxc_autoscale
```

**Solution:**
If wrong, edit service file and reload:
```bash
systemctl daemon-reload
systemctl restart lxc_autoscale
```

---

## 🧪 Testing Installation Script

To test the fixed script:

```bash
# On Proxmox host:
bash <(curl -s https://raw.githubusercontent.com/droltr/lxc-auto-scaler/main/lxc-autoscale.sh)
```

**Expected Results:**
- Installation completes without errors
- Both services start successfully
- Web UI accessible on port 8080
- SSH key displayed
- MOTD shown on container login

---

## 📝 Development Notes

### Why Flask-SocketIO via pip?

Debian 13 (Trixie) doesn't include `python3-flask-socketio` package. Only option is pip installation.

### Why allow_unsafe_werkzeug?

Flask-SocketIO's built-in development server (Werkzeug) is flagged as unsafe for production. In a true production deployment, you'd use Gunicorn or uWSGI. For LXC container internal use, Werkzeug is acceptable with the flag.

### Why root user for Flask UI?

Ideally, Flask would run as `www-data`. However, due to:
- Debug mode complications
- Port binding requirements  
- LXC container isolation already providing security
- Proxmox environment being internal

Running as root is acceptable in this specific use case.

### Alternative Production Setup

For true production deployment:

```bash
# Install Gunicorn
pip3 install gunicorn gevent gevent-websocket

# Create service with Gunicorn
ExecStart=/usr/local/bin/gunicorn \
    --bind 127.0.0.1:5000 \
    --worker-class geventwebsocket.gunicorn.workers.GeventWebSocketWorker \
    --workers 1 \
    lxc_autoscale_ui:app

# Run as www-data
User=www-data
Group=www-data
```

Not implemented to keep dependencies minimal.

---

## 🔗 References

- [Flask-SocketIO Documentation](https://flask-socketio.readthedocs.io/)
- [Systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [LXC AutoScale Original Project](https://github.com/fabriziosalmi/proxmox-lxc-autoscale)
- [Community Scripts Framework](https://github.com/community-scripts/ProxmoxVE)

---

**Last Updated:** 2024-12-22  
**Script Version:** 1.0.0  
**Tested On:** Proxmox VE 9.1.2, Debian 13 (Trixie)
