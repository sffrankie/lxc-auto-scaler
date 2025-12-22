# Contributing to LXC AutoScale Installer

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

---

## 🎯 How to Contribute

### Reporting Issues

Before creating an issue, please:
1. Check existing issues to avoid duplicates
2. Use the issue template (if available)
3. Provide detailed information:
   - Proxmox VE version
   - Container OS and version
   - Error messages and logs
   - Steps to reproduce

### Suggesting Enhancements

Enhancement suggestions are welcome! Please:
1. Check if the enhancement is already requested
2. Clearly describe the feature and its benefits
3. Provide use cases and examples
4. Consider backward compatibility

---

## 🔧 Development Setup

### Prerequisites

- Proxmox VE test environment
- Git installed
- Basic bash scripting knowledge
- Understanding of LXC containers

### Local Development

```bash
# Fork the repository on GitHub

# Clone your fork
git clone https://github.com/YOUR_USERNAME/lxc-auto-scaler.git
cd lxc-auto-scaler

# Create a branch for your changes
git checkout -b feature/your-feature-name

# Make your changes
# Test thoroughly in a Proxmox environment

# Commit your changes
git add .
git commit -m "Description of changes"

# Push to your fork
git push origin feature/your-feature-name

# Create a Pull Request on GitHub
```

---

## 📝 Coding Guidelines

### Bash Scripting Standards

1. **Use shellcheck** for linting
2. **Follow community-scripts patterns** where applicable
3. **Add comments** for complex logic
4. **Use meaningful variable names**
5. **Handle errors properly** with error messages

### Code Style

```bash
# Good - descriptive function name with comments
detect_lxc_containers() {
    # Get all LXC containers except the one being created
    DETECTED_LXC=$(pct list 2>/dev/null | awk 'NR>1 {print $1}')
}

# Bad - unclear purpose
get_stuff() {
    X=$(pct list | awk 'NR>1 {print $1}')
}
```

### Message Standards

Use community-scripts message functions:
```bash
msg_info "Informational message"
msg_ok "Success message"
msg_error "Error message"
```

---

## 🧪 Testing

### Required Testing

Before submitting a PR, test:

1. **Fresh Installation**
   - Default mode installation
   - Advanced mode installation
   - Different storage backends
   
2. **Locale Selection**
   - English installation
   - Turkish installation
   
3. **Container Detection**
   - With existing containers
   - Without existing containers
   
4. **Web Interface**
   - UI accessibility
   - API endpoints
   - Log viewing

5. **Service Management**
   - Service starts correctly
   - Logs are generated
   - Configuration is valid

### Test Environment

- Clean Proxmox VE installation
- At least 2 existing LXC containers for detection testing
- Network connectivity for package downloads

---

## 📋 Pull Request Process

1. **Update Documentation**
   - Update README.md if adding features
   - Add comments to complex code
   - Update CHANGELOG.md (if exists)

2. **Follow Commit Message Format**
   ```
   type: brief description
   
   Detailed explanation of changes
   
   - Bullet point 1
   - Bullet point 2
   ```
   
   Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

3. **PR Description Template**
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Code refactoring
   
   ## Testing Done
   - [ ] Fresh installation tested
   - [ ] Locale selection tested
   - [ ] Web UI tested
   - [ ] Service functionality tested
   
   ## Related Issues
   Fixes #123
   ```

4. **Review Process**
   - Maintainer will review your PR
   - Address any feedback
   - Once approved, PR will be merged

---

## 🌍 Localization

### Adding New Locale Support

To add a new language:

1. Add locale option in `select_locale()` function
2. Update locale installation in install script
3. Test locale generation
4. Update documentation

Example:
```bash
select_locale() {
    LOCALE_CHOICE=$(whiptail --menu "Choose locale:" 12 50 3 \
        "1" "English (en_US.UTF-8)" \
        "2" "Turkish (tr_TR.UTF-8)" \
        "3" "German (de_DE.UTF-8)" \  # New locale
        3>&1 1>&2 2>&3)
    
    case $LOCALE_CHOICE in
        3)
            SELECTED_LOCALE="de_DE.UTF-8"
            LOCALE_NAME="German"
            ;;
    esac
}
```

---

## 🎨 UI Enhancements

### Modifying Web Interface

The web UI is located in the install script as fallback HTML. To enhance:

1. Maintain dark theme consistency
2. Keep mobile-responsive design
3. Test API endpoints
4. Ensure accessibility

### Adding Features

When adding UI features:
- Keep JavaScript vanilla (no frameworks)
- Maintain current design language
- Add proper error handling
- Update API endpoints if needed

---

## 📚 Documentation

### README Updates

Keep README updated with:
- New features
- Configuration changes
- New requirements
- Updated examples

### Code Comments

Add comments for:
- Complex logic
- Non-obvious decisions
- Important variables
- Function purposes

---

## ❓ Questions?

- Open a discussion on GitHub
- Review existing documentation

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to LXC AutoScale Installer! 🎉
