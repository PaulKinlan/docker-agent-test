FROM archlinux:latest

# Update the system and install dependencies
# Note: sudo is pulled in by base-devel but agents are explicitly denied sudo access
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    vim \
    systemd \
    nodejs \
    npm && \
    pacman -Scc --noconfirm

# No default user — users are created dynamically via create-agent.sh
RUN groupadd -f agents

# Explicitly deny sudo access for all agent users
RUN mkdir -p /etc/sudoers.d && \
    echo '%agents ALL=(ALL) !ALL' > /etc/sudoers.d/deny-agents && \
    chmod 440 /etc/sudoers.d/deny-agents

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Copy persona definitions (used by create-agent.sh to build agents.md)
COPY config/personas/ /etc/agent-personas/

# Copy /etc/skel template (applied to every new user created with useradd -m)
COPY config/skel/ /etc/skel/

# Copy global profile.d scripts (sourced on every interactive login)
COPY config/profile.d/ /etc/profile.d/
RUN chmod +x /etc/profile.d/*.sh

# Copy systemd system-level service units
COPY config/systemd/ /etc/systemd/system/

# Copy management scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Enable the agent-manager service so it runs at boot
RUN systemctl enable agent-manager.service

# Systemd environment
ENV container=docker

# Expose /home so all agent home dirs are visible from the host
VOLUME ["/home"]

# Systemd must run as root (PID 1)
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/lib/systemd/systemd"]
