# Changelog

All notable changes to LXC AutoScale Installer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- File permission fixes for web interface (403 error resolution)
- Comprehensive installation summary with IP address and access information
- Professional README with credits and documentation links
- CONTRIBUTING guidelines for developers
- Issue templates for bug reports and feature requests

---

## [1.0.0] - 2024-12-22

### Added
- Initial release
- One-command installation using Community-Scripts framework
- Automatic LXC container detection on Proxmox host
- Multi-language support (English and Turkish)
- Interactive locale selection via whiptail menu
- SSH key generation and display
- Original UI installation from upstream repository
- Fallback UI with modern dark theme
- Nginx web server on port 8080
- API endpoints for logs and metrics
- Systemd service configuration
- Automatic YAML configuration generation
- Support for Default and Advanced installation modes
- Integration with LXC AutoScale project
- No telemetry or data collection (privacy-focused)

### Technical Details
- Based on Community-Scripts build.func framework
- Modified build.func to use custom repository URLs
- Debian 13 (Trixie) unprivileged container
- Python 3 with required dependencies
- Automated dependency installation
- Service auto-start on boot

### Credits
- Built on [fabriziosalmi/proxmox-lxc-autoscale](https://github.com/fabriziosalmi/proxmox-lxc-autoscale)
- Uses [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) framework
- In memory of tteck, original creator of Community Scripts

---

## Template for Future Releases

## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security improvements

---

[Unreleased]: https://github.com/droltr/lxc-auto-scaler/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/droltr/lxc-auto-scaler/releases/tag/v1.0.0
