FROM archlinux:latest

# Update the system and install basic tools
# Note: This requires network connectivity to Arch package repositories
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    vim \
    sudo \
    systemd \
    nodejs \
    npm && \
    pacman -Scc --noconfirm

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Create a user
RUN useradd -m -s /bin/bash user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy custom /etc/skel files (template for new users)
COPY config/skel/ /etc/skel/

# Copy custom /etc/profile.d files (global environment scripts)
COPY config/profile.d/ /etc/profile.d/

# Set permissions for profile.d scripts
RUN chmod +x /etc/profile.d/*.sh

# Set up systemd environment variable
ENV container=docker

# The home directory will be mounted from the host
VOLUME ["/home/user"]

# Switch to the user
USER user
WORKDIR /home/user

# Default command
CMD ["/bin/bash"]
