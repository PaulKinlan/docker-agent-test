# Quick Start Guide

This guide will help you get started with the Arch Linux Docker environment.

## Prerequisites

- Docker installed on your system
- Docker Compose installed (optional, but recommended)
- Network access to download Arch Linux packages

## Quick Start

### 1. Build the Docker Image

```bash
docker-compose build
```

Or using Docker directly:
```bash
docker build -t arch-dev .
```

### 2. Start the Container

```bash
docker-compose up -d
```

Or using Docker directly:
```bash
docker run -it -v $(pwd)/home:/home/user arch-dev
```

### 3. Access the Container

```bash
docker-compose exec arch-dev /bin/bash
```

You should see the custom welcome message from `/etc/profile.d/custom-env.sh`.

### 4. Verify the Setup

Inside the container, verify that:

1. **Home directory is mounted:**
   ```bash
   pwd  # Should show /home/user
   touch test-file.txt
   ls -la test-file.txt
   ```
   
   Exit the container and check that `test-file.txt` exists in `./home/` directory.

2. **Custom environment variables are loaded:**
   ```bash
   echo $CUSTOM_VAR  # Should display: "This is a custom global variable"
   ```

3. **Bash configuration is applied:**
   ```bash
   ll  # Custom alias from .bashrc should work
   ```

4. **Systemd user services are available:**
   ```bash
   systemctl --user status
   ```

## Customizing Configuration

### For All Users (Global)

Edit files in `config/profile.d/`:
```bash
nano config/profile.d/custom-env.sh
```

Then rebuild the image:
```bash
docker-compose build
```

### For New Users (Template)

Edit files in `config/skel/`:
```bash
nano config/skel/.bashrc
```

Then rebuild the image:
```bash
docker-compose build
```

### For Systemd User Services

1. Add service files to `config/skel/.config/systemd/user/`
2. Rebuild the image
3. Inside the container, enable and start services:
   ```bash
   systemctl --user enable example.service
   systemctl --user start example.service
   ```

## Stopping and Cleaning Up

Stop the container:
```bash
docker-compose down
```

Remove the image:
```bash
docker rmi arch-dev:latest
```

Clean up all data (WARNING: This deletes the home directory contents):
```bash
rm -rf home/*  # Be careful!
```

## Troubleshooting

### Build fails with network errors

If you see errors like "Could not resolve host", this means the build environment cannot access the Arch Linux package repositories. You'll need to build the image on a machine with internet access.

### Changes to config files don't appear

Remember to rebuild the image after making changes:
```bash
docker-compose build
docker-compose up -d
```

### Build fails on Apple Silicon / ARM hosts

The Arch Linux base image only publishes `linux/amd64` manifests. The `platform: linux/amd64` setting in `docker-compose.yml` tells Docker to use QEMU emulation on non-amd64 hosts. Make sure Docker Desktop's QEMU/Rosetta emulation is enabled (it is by default).

### Home directory permissions

If you encounter permission issues, you may need to adjust the user ID in the Dockerfile to match your host system user ID.

## File Structure Reference

```
.
├── Dockerfile              # Main Docker image definition
├── docker-compose.yml      # Docker Compose configuration
├── home/                   # User home (mounted as /home/user)
├── config/
│   ├── README.md          # Detailed config documentation
│   ├── skel/              # Template for new user homes → /etc/skel
│   │   ├── .bashrc
│   │   ├── .bash_profile
│   │   └── .config/systemd/user/
│   │       └── example.service
│   └── profile.d/         # Global environment scripts → /etc/profile.d
│       └── custom-env.sh
└── USAGE.md               # This file
```

## Next Steps

1. Explore the configuration files in `config/`
2. Add your own customizations
3. Test the setup with your development workflow
4. Commit your configuration changes to version control

For more detailed information, see:
- `README.md` - Project overview and detailed documentation
- `config/README.md` - Configuration file details and examples
