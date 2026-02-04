# Configuration Files

This directory contains configuration files that are copied into the Docker image.

## Directory Structure

### `skel/` - User Template Files

Files in this directory are copied to `/etc/skel/` in the container. These files serve as templates for new user home directories.

**Current files:**
- `.bashrc` - Default bash configuration for interactive shells
- `.bash_profile` - Bash login configuration
- `.config/systemd/user/example.service` - Example systemd user service

**How to use:**
1. Edit or add files in this directory
2. Rebuild the Docker image: `docker-compose build`
3. New users will automatically get these files in their home directory

**For systemd user services:**
- Place service files in `skel/.config/systemd/user/`
- Enable them in `.bash_profile` or `.bashrc` with commands like:
  ```bash
  systemctl --user enable example.service
  systemctl --user start example.service
  ```

### `profile.d/` - Global Environment Scripts

Files in this directory are copied to `/etc/profile.d/` in the container. These scripts are executed for all users during login.

**Current files:**
- `custom-env.sh` - Custom global environment variables and startup messages

**How to use:**
1. Create `.sh` files in this directory
2. Make them executable (or the Dockerfile will do it automatically)
3. Rebuild the Docker image: `docker-compose build`
4. Scripts will run for all users on login

**Best practices:**
- Use descriptive filenames (e.g., `company-env.sh`, `dev-tools.sh`)
- Scripts should be idempotent (safe to run multiple times)
- Keep scripts simple and fast to avoid slowing down login
- Export environment variables that should be available to all processes
- Set up PATH additions here for global tools

## Examples

### Adding a custom command for all users

Create `config/profile.d/custom-commands.sh`:
```bash
#!/bin/bash
# Add a custom greeting command
greet() {
    echo "Hello $(whoami), welcome to the development environment!"
}
export -f greet
```

### Setting up systemd user service at login

Edit `config/skel/.bashrc` to add:
```bash
# Enable and start user services
if systemctl --user is-enabled example.service >/dev/null 2>&1; then
    systemctl --user start example.service
fi
```

### Adding custom aliases for new users

Edit `config/skel/.bashrc` to add:
```bash
# Docker-specific aliases
alias dps='docker ps'
alias dim='docker images'
```
