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
    npm \
    python \
    python-pip \
    curl \
    wget \
    jq \
    ripgrep \
    tree \
    openssh \
    unzip \
    s-nail \
    opensmtpd && \
    pacman -Scc --noconfirm

# No default user — users are created dynamically via create-agent.sh
RUN groupadd -f agents

# Explicitly deny sudo access for all agent users
RUN mkdir -p /etc/sudoers.d && \
    echo '%agents ALL=(ALL) !ALL' > /etc/sudoers.d/deny-agents && \
    chmod 440 /etc/sudoers.d/deny-agents

# Install Claude Code globally (uses system node)
RUN npm install -g @anthropic-ai/claude-code

# Install nvm system-wide so agents can manage their own Node versions
# System node (pacman) is kept for root/Claude Code; nvm is for agent dev work
ENV NVM_DIR=/usr/local/share/nvm
RUN mkdir -p "$NVM_DIR" && \
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install --lts && \
    nvm alias default lts/* && \
    chmod -R a+rX "$NVM_DIR"

# Copy persona definitions (used by create-agent.sh to build agents.md)
COPY config/personas/ /etc/agent-personas/

# Copy /etc/skel template (applied to every new user created with useradd -m)
COPY config/skel/ /etc/skel/

# Copy global profile.d scripts (sourced on every interactive login)
COPY config/profile.d/ /etc/profile.d/
RUN chmod +x /etc/profile.d/*.sh

# Copy API keys configuration directory
# If global.env exists, rename to .static so it can be merged with env vars at boot
COPY config/api-keys/ /etc/agent-api-keys/
RUN if [ -f /etc/agent-api-keys/global.env ]; then \
        mv /etc/agent-api-keys/global.env /etc/agent-api-keys/global.env.static; \
    fi && \
    chmod 700 /etc/agent-api-keys

# Copy systemd system-level service units
COPY config/systemd/ /etc/systemd/system/

# Copy management scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Configure journald for persistent storage so logs survive in /var/log/journal
# (mounted to host via docker-compose for external observation)
RUN mkdir -p /etc/systemd/journald.conf.d && \
    printf '[Journal]\nStorage=persistent\n' > /etc/systemd/journald.conf.d/persistent.conf

# Configure opensmtpd for local-only mail delivery
RUN echo 'listen on localhost' > /etc/smtpd/smtpd.conf && \
    echo 'action "local" mbox alias <aliases>' >> /etc/smtpd/smtpd.conf && \
    echo 'match from local for local action "local"' >> /etc/smtpd/smtpd.conf

# Mask services that are unnecessary inside Docker and block the boot process.
# systemd-networkd-wait-online blocks for ~2 minutes waiting for network
# connectivity that Docker manages externally, preventing multi-user.target
# (and therefore all agent services) from starting on time.
# systemd-firstboot runs Before=basic.target on every container start
# (ConditionFirstBoot=yes) and hangs waiting for interactive input when a
# TTY is attached, preventing basic.target from being reached and blocking
# all agent services that depend on it.
RUN systemctl mask systemd-networkd-wait-online.service && \
    systemctl mask systemd-firstboot.service

# Enable boot-time services
RUN systemctl enable api-keys-sync.service && \
    systemctl enable agent-manager.service && \
    systemctl enable smtpd.service

# Systemd environment
ENV container=docker

# Expose /home so all agent home dirs are visible from the host
VOLUME ["/home"]

# Systemd must run as root (PID 1)
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/lib/systemd/systemd"]
