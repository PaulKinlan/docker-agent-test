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

# Create shared workspace for inter-agent file sharing (SwarmKit ArtifactStore)
# Writable by all agents via group ownership, readable by root for observation
RUN mkdir -p /home/shared && \
    chown root:agents /home/shared && \
    chmod 2775 /home/shared

# Explicitly deny sudo access for all agent users
RUN mkdir -p /etc/sudoers.d && \
    echo '%agents ALL=(ALL) !ALL' > /etc/sudoers.d/deny-agents && \
    chmod 440 /etc/sudoers.d/deny-agents

# Install Claude Code and Agent SDK globally (uses system node)
RUN npm install -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk && \
    ln -s /usr/lib/node_modules /usr/local/bin/node_modules

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
    chmod 755 /etc/agent-api-keys

# Copy systemd system-level service units
COPY config/systemd/ /etc/systemd/system/

# Copy management scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh /usr/local/bin/*.mjs

# Configure journald for persistent storage so logs survive in /var/log/journal
# (mounted to host via docker-compose for external observation)
RUN mkdir -p /etc/systemd/journald.conf.d && \
    printf '[Journal]\nStorage=persistent\n' > /etc/systemd/journald.conf.d/persistent.conf

# Copy custom smtpd configuration (aliases.static for custom per-agent aliases)
COPY config/smtpd/ /etc/smtpd/

# Configure opensmtpd for local-only mail delivery
# Use explicit 127.0.0.1 instead of "localhost" to avoid IPv4/IPv6 race
# conditions under Docker QEMU/Rosetta emulation.
RUN printf 'table aliases file:/etc/smtpd/aliases\nlisten on 127.0.0.1 port 25\naction "local" mbox alias <aliases>\nmatch from local for local action "local"\n' > /etc/smtpd/smtpd.conf && \
    touch /etc/smtpd/aliases && \
    mkdir -p /var/spool/smtpd/{offline,purge,temporary,incoming,queue,corrupt} && \
    chmod 711 /var/spool/smtpd && \
    chmod 700 /var/spool/smtpd/{purge,temporary,incoming,queue,corrupt} && \
    chmod 770 /var/spool/smtpd/offline && \
    chown smtpq:root /var/spool/smtpd/{purge,temporary,incoming,queue,corrupt} && \
    chown root:smtpq /var/spool/smtpd/offline && \
    mkdir -p /var/spool/mail && chmod 0755 /var/spool/mail

# Override smtpd.service: run in foreground via a wrapper script.
# Direct exec of /usr/bin/smtpd from systemd fails with 0B memory / exit 255
# under Docker + Rosetta (cgroup2 interaction). A shell wrapper avoids this.
# Also remove Requires=network-online.target which we mask in Docker.
RUN mkdir -p /etc/systemd/system/smtpd.service.d && \
    printf '[Unit]\nRequires=\nAfter=basic.target\n\n[Service]\nType=simple\nExecStart=\nExecStart=/usr/local/bin/start-smtpd.sh\n' \
    > /etc/systemd/system/smtpd.service.d/override.conf && \
    printf '#!/bin/sh\nrm -f /var/run/smtpd.sock\nexec /usr/bin/smtpd -d -f /etc/smtpd/smtpd.conf\n' \
    > /usr/local/bin/start-smtpd.sh && \
    chmod +x /usr/local/bin/start-smtpd.sh

# Configure s-nail to use the local sendmail binary (provided by opensmtpd).
# Using mta=/usr/sbin/sendmail allows bare usernames (e.g., "mail alice")
# which the smtp:// MTA mode rejects.
RUN printf 'set sendwait\nset mta=/usr/sbin/sendmail\nset hostname=localhost\n' > /etc/mail.rc

# Mask services that are unnecessary inside Docker and block the boot process.
#
# systemd-networkd-wait-online: Blocks ~2 minutes waiting for network
#   connectivity that Docker manages externally, preventing multi-user.target
#   (and therefore all agent services) from starting on time.
#
# systemd-firstboot: Runs Before=basic.target on every container start
#   (ConditionFirstBoot=yes, because the root filesystem is ephemeral) and
#   hangs waiting for interactive input when a TTY is attached. This prevents
#   basic.target from being reached and blocks all agent services.
#   Its job (locale, timezone, hostname, root password) is unnecessary here:
#   these settings are either inherited from Docker or lost on restart anyway.
#
#   To revert to pre-seeding instead of masking, replace the firstboot mask
#   line below with:
#     RUN systemd-firstboot --locale=C.UTF-8 --timezone=UTC --hostname=agent-host --root-shell=/bin/bash
#   This satisfies firstboot so it exits immediately on boot instead of
#   prompting, but still lets it run.
RUN systemctl mask systemd-networkd-wait-online.service && \
    systemctl mask systemd-firstboot.service

# Enable boot-time services
RUN systemctl enable api-keys-sync.service && \
    systemctl enable agent-manager.service && \
    systemctl enable smtpd.service && \
    systemctl enable swarm-orchestrator.service

# Systemd environment
ENV container=docker

# Expose /home so all agent home dirs are visible from the host
VOLUME ["/home"]

# Health check — verifies systemd boot complete and mail system running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD systemctl is-active basic.target && systemctl is-active smtpd.service

# Systemd must run as root (PID 1)
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/lib/systemd/systemd"]
