# Upstream Bug Report - DEFAULT vs DEFAULTS

## Issue Summary

There is a critical inconsistency in the LXC AutoScale project between the example configuration file and the Python code that reads it.

## Problem

**File:** `lxc_autoscale/lxc_utils.py` (Line 69)
```python
use_remote_proxmox = config.get('DEFAULT', {}).get('use_remote_proxmox', False)
#                                 ^^^^^^^^ expects 'DEFAULT' (singular)
```

**File:** `lxc_autoscale/lxc_autoscale.yaml` (Example config)
```yaml
DEFAULTS:  # ← Uses 'DEFAULTS' (plural)
  log_file: /var/log/lxc_autoscale.log
  ...
```

## Impact

When using the example configuration file as-is:
1. ❌ `use_remote_proxmox: true` is ignored
2. ❌ System tries to run `pct` commands locally instead of via SSH
3. ❌ Error: `/bin/sh: 1: pct: not found`
4. ❌ AutoScale service fails to monitor any containers

## Reproduction Steps

1. Clone the repository
2. Use the example `lxc_autoscale.yaml` with `DEFAULTS:` (as provided)
3. Set `use_remote_proxmox: true`
4. Run the service
5. Observe error: `pct: not found`

## Root Cause Analysis

```python
# lxc_utils.py - Line 69-72
def run_command(cmd, timeout=60):
    config = load_config()
    use_remote_proxmox = config.get('DEFAULT', {}).get('use_remote_proxmox', False)
    #                                 ^^^^^^^^ Looking for 'DEFAULT'
    logging.debug("Inside run_command: use_remote_proxmox = %s", use_remote_proxmox)
    return (run_remote_command if use_remote_proxmox else run_local_command)(cmd, timeout)
```

When the YAML has `DEFAULTS:`, Python's `config.get('DEFAULT', {})` returns `{}` (empty dict), so `use_remote_proxmox` is always `False`.

## Solution Options

### Option 1: Fix the Code (Recommended)
Change `lxc_utils.py` line 69:
```python
use_remote_proxmox = config.get('DEFAULTS', {}).get('use_remote_proxmox', False)
#                                 ^^^^^^^^^ Plural to match YAML
```

### Option 2: Fix the Example Config
Change `lxc_autoscale.yaml`:
```yaml
DEFAULT:  # ← Singular to match code
  log_file: /var/log/lxc_autoscale.log
```

## Our Workaround

In our installer, we use `DEFAULT:` (singular) to match what the code expects:

```bash
# lxc-autoscale-install.sh
cat > /etc/lxc_autoscale/lxc_autoscale.yaml << EOF
DEFAULT:  # ← Singular
  use_remote_proxmox: true
  ...
TIER_DEFAULT:
  lxc_containers: [101, 102, 103]
  ...
EOF
```

## Testing Evidence

**Before fix (using DEFAULTS):**
```bash
$ grep -A1 "^DEFAULTS:" /etc/lxc_autoscale/lxc_autoscale.yaml
DEFAULTS:
  use_remote_proxmox: true

$ python3 -c "import yaml; print(yaml.safe_load(open('/etc/lxc_autoscale/lxc_autoscale.yaml')).get('DEFAULT', {}).get('use_remote_proxmox'))"
None  # ← Returns None instead of True!
```

**After fix (using DEFAULT):**
```bash
$ grep -A1 "^DEFAULT:" /etc/lxc_autoscale/lxc_autoscale.yaml
DEFAULT:
  use_remote_proxmox: true

$ python3 -c "import yaml; print(yaml.safe_load(open('/etc/lxc_autoscale/lxc_autoscale.yaml')).get('DEFAULT', {}).get('use_remote_proxmox'))"
True  # ← Correctly returns True
```

## System Information

- **Tested on:** Proxmox VE 9.1.2, Debian 13 (Trixie)
- **Python version:** 3.13.5
- **LXC AutoScale commit:** Latest from main branch

## Additional Notes

This bug affects ALL deployments where the service runs inside an LXC container and needs to communicate with the Proxmox host via SSH. Without the fix, remote execution is completely broken.

## Recommendation

We recommend fixing the code (`lxc_utils.py`) rather than the example config, because:
1. "DEFAULTS" is more intuitive and matches common YAML conventions
2. Less breaking change for existing users
3. Aligns with similar projects (most use `DEFAULTS` or `default` sections)

## Related Files

- `lxc_autoscale/lxc_utils.py` - Line 69 (bug location)
- `lxc_autoscale/lxc_autoscale.yaml` - Example configuration

## Reporter

- **Reported by:** droltr/lxc-auto-scaler fork maintainers
- **Date:** 2024-12-22
- **Fork repository:** https://github.com/droltr/lxc-auto-scaler

---

**This issue will be reported to the upstream repository for resolution.**
