# systemd + cgroup v2 + Docker Desktop: Compatibility Research

> **Context:** Commit `b4fc140` replaced `systemctl enable/start agent@<user>.service`
> with `nohup su -` because systemd's cgroup-based process spawning is broken
> inside Docker Desktop on macOS with cgroup v2 and systemd v256+.
> This document captures the research needed to restore systemd service management.

## The Symptom

When running `systemctl start agent@alice.service` inside the container:

- The service goes straight to `inactive (dead)`
- Exit code 255, 0B memory consumed
- No journal output — the process was never actually exec'd
- systemd itself boots fine (`basic.target`, `multi-user.target` reached)
- The same issue affects `smtpd.service` (worked around with a shell wrapper in the Dockerfile)

## Root Cause

A three-way incompatibility between systemd's cgroup expectations, Docker's cgroup mount behavior, and Docker Desktop's LinuxKit VM constraints.

### How systemd uses cgroups to start services

When systemd starts a service, it:

1. Creates a child cgroup (e.g., `/sys/fs/cgroup/system.slice/agent@alice.service`)
2. Writes the service's PID into that cgroup
3. Enables resource controllers (memory, cpu, etc.) via `cgroup.subtree_control`
4. Applies resource limits (MemoryMax, CPUQuota) through controller files

If any of these writes fail, systemd silently fails to start the service.

### cgroup v2's two rules

systemd's [CGROUP_DELEGATION.md](https://systemd.io/CGROUP_DELEGATION/) defines two rules that container runtimes must respect:

1. **No-processes-in-inner-nodes**: A cgroup v2 node is either a leaf (has processes) or inner (has child cgroups), never both. systemd must create child cgroups like `init.scope` before it can set up `cgroup.subtree_control`.

2. **Single-writer**: Each cgroup must have exactly one process managing it. If Docker manages the container's root cgroup AND the container's systemd also tries to manage it, they conflict.

### Why Docker Desktop is worse than native Linux

On **native Linux**, the host's systemd can delegate a cgroup subtree to Docker via a scope/service unit with `Delegate=yes`. The container gets a private cgroup namespace rooted at its delegated path. systemd inside the container can write to this subtree.

On **Docker Desktop for macOS**, Docker runs inside a **LinuxKit VM**:

```
macOS host
  → Docker Desktop
    → LinuxKit VM (kernel ~6.10.x, cgroupfs driver, NO systemd)
      → containerd / dockerd
        → Container (systemd as PID 1)
```

The LinuxKit VM:
- Uses `cgroupfs` as its cgroup driver, not systemd
- Does not run systemd as its own init system
- Cannot provide `Delegate=yes` because there is no host-side systemd to delegate from
- Mounts `/sys/fs/cgroup` read-only inside containers by default

The result: the container's systemd cannot write to the cgroup hierarchy, so it cannot create child cgroups, so it cannot start services.

### systemd v256+ made things worse

| Version | Change |
|---------|--------|
| **v248** (2021) | Read-only `/sys/fs/cgroup` mount inside containers started causing failures ([systemd#19245](https://github.com/systemd/systemd/issues/19245)) |
| **v256** (June 2024) | cgroup v1 formally deprecated; systemd refuses to boot under cgroup v1 by default |
| **v258** (Sept 2025) | cgroup v1 support **removed entirely** |

Since Arch Linux (`FROM archlinux:latest`) ships the latest systemd, our container always has v256+. Falling back to cgroup v1 is not an option.

## What Our Container Currently Does

From `docker-compose.yml`:

```yaml
privileged: true
tmpfs:
  - /run
  - /run/lock
```

We use `privileged: true` but do **not** explicitly set:
- `cgroup: host` (or `--cgroupns=host`)
- A read-write `/sys/fs/cgroup` volume mount

This means Docker uses its default cgroup namespace mode. On cgroup v2 hosts, the default is `private`, which gives the container a private cgroup namespace — but one that may be read-only.

## Fix Options

### Option 1: `cgroup: host` + rw cgroup mount (recommended first attempt)

Add to `docker-compose.yml`:

```yaml
services:
  agent-host:
    privileged: true
    cgroup: host          # Compose spec key; older versions may need cgroupns_mode: host
    tmpfs:
      - /run
      - /run/lock
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
      # ... existing mounts
```

> **Note:** The Compose spec uses `cgroup: host`. Some older Docker Compose
> versions (pre-2.x) may require `cgroupns_mode: host` instead. With `docker run`,
> use `--cgroupns=host`.

This is the "Jeff Geerling pattern" — the most widely tested approach for running systemd inside Docker. It gives the container's systemd access to the host's (or VM's) cgroup hierarchy.

**Pros:**
- Most compatible approach, works on native Linux and Docker Desktop
- Enables full `systemctl` functionality including resource limits
- Well-documented, used by Ansible/Molecule testing community

**Cons:**
- Container can see and potentially affect the host's cgroup hierarchy
- Already using `privileged: true` so the security delta is small
- On Docker Desktop, "host" means the LinuxKit VM, not macOS itself

**Testing:**
```bash
# After changing docker-compose.yml, rebuild and enter the container:
make build && make up && make shell

# Verify cgroup v2 is writable:
ls -la /sys/fs/cgroup/
cat /proc/self/cgroup  # should show the container's cgroup path
mkdir /sys/fs/cgroup/test.scope 2>/dev/null \
  && rmdir /sys/fs/cgroup/test.scope && echo "cgroup writable" \
  || echo "cgroup NOT writable"

# Test systemd service management:
systemctl start agent-manager.service
systemctl status agent-manager.service

# Create a test agent and verify it starts via systemd:
# (after restoring systemctl in create-agent.sh)
create-agent.sh testuser
systemctl status agent@testuser.service
journalctl -u agent@testuser.service --no-pager -n 20
```

### Option 2: Entrypoint cgroup remount (more targeted)

Instead of sharing the host cgroup namespace, remount the cgroup filesystem read-write inside the container before systemd starts:

```bash
#!/bin/bash
# /usr/local/bin/container-init.sh — runs before systemd
umount /sys/fs/cgroup 2>/dev/null || true
mount -t cgroup2 -o rw,relatime,nsdelegate,memory_recursiveprot cgroup2 /sys/fs/cgroup
exec /usr/lib/systemd/systemd "$@"
```

Then in the Dockerfile:
```dockerfile
ENTRYPOINT ["/usr/local/bin/container-init.sh"]
```

**Pros:**
- Keeps cgroup namespace private (container-scoped)
- More security isolation than host cgroup namespace
- Fix is contained within the image, no docker-compose changes needed

**Cons:**
- May not work on all Docker Desktop versions
- Requires `CAP_SYS_ADMIN` (already granted by `privileged: true`)
- Less tested in the community

### Option 3: Shell wrapper pattern (per-service workaround)

This is what we already do for `smtpd.service` — wrap the ExecStart in a shell script:

```ini
[Service]
Type=simple
ExecStart=
ExecStart=/bin/sh -c 'exec /usr/local/bin/run-agent.sh'
```

The theory: systemd's cgroup write failure happens during its internal fork+exec. If the shell is already running (forked by systemd before cgroup setup fully fails), the `exec` inside the shell may succeed.

**Pros:**
- No infrastructure changes needed
- Proven to work for smtpd in this exact environment

**Cons:**
- Fragile — depends on a race condition / implementation detail
- May not work for resource limits (MemoryMax, CPUQuota)
- Doesn't fix the root cause

### Option 4: Hybrid approach (recommended)

Combine Options 1 and 3:

1. Add `cgroup: host` + rw cgroup mount to `docker-compose.yml` (Option 1)
2. If that alone fixes service spawning, use it
3. If individual security directives still fail, re-enable them one at a time
4. For any directive that cannot work in Docker, document it and leave it commented out

## Security Hardening Re-enablement Plan

Once systemd service management works, re-enable directives in `agent@.service` in tiers:

### Tier 1: Safe in Docker (re-enable immediately)
```ini
NoNewPrivileges=true          # Kernel no_new_privs flag (prctl), no mount/cgroup interaction
RestrictSUIDSGID=true         # Blocks setuid/setgid file creation, no mount/cgroup interaction
```

### Tier 2: Likely safe with cgroup host access (test carefully)
```ini
MemoryMax=512M                # Requires cgroup write access
CPUQuota=50%                  # Requires cgroup write access
```

### Tier 3: May conflict with Docker overlay2 (test on both platforms)
```ini
ProtectSystem=full            # Remounts /usr, /boot read-only (may conflict with overlay)
PrivateTmp=true               # Creates private /tmp mount namespace
RestrictNamespaces=true       # May conflict with container namespace setup
```

### Tier 4: Likely incompatible with Docker (leave disabled)
```ini
ProtectKernelTunables=true    # Mounts /proc/sys read-only, conflicts with privileged
ProtectKernelModules=true     # Blocks module loading, conflicts with privileged
ProtectControlGroups=true     # Mounts /sys/fs/cgroup read-only — directly contradicts our fix
ProtectKernelLogs=true        # Blocks /dev/kmsg access
CapabilityBoundingSet=        # Drops all capabilities, conflicts with privileged
AmbientCapabilities=          # No capabilities to pass to children
RestrictAddressFamilies=...   # May conflict with container seccomp profile
```

## Platform Test Matrix

Any fix must be tested on both platforms:

| Platform | cgroup version | Docker cgroup driver | Expected behavior |
|----------|---------------|---------------------|-------------------|
| Docker Desktop macOS (Apple Silicon) | v2 | cgroupfs (LinuxKit) | Primary target — this is where the bug was found |
| Docker Desktop macOS (Intel) | v2 | cgroupfs (LinuxKit) | Should behave same as Apple Silicon |
| Native Linux (Ubuntu 22.04+) | v2 | systemd | Should work with proper delegation |
| Native Linux (older, cgroup v1) | v1 | cgroupfs | Not supported — systemd v256+ requires v2 |

## Diagnostic Commands

Run these inside the container to understand the current cgroup state:

```bash
# What cgroup version is active?
stat -fc %T /sys/fs/cgroup/
# "cgroup2fs" = v2, "tmpfs" = v1

# Is the cgroup hierarchy writable?
touch /sys/fs/cgroup/.test 2>&1 && rm /sys/fs/cgroup/.test && echo "writable" || echo "read-only"

# What cgroup is PID 1 in?
cat /proc/1/cgroup

# What controllers are available?
cat /sys/fs/cgroup/cgroup.controllers

# What controllers are delegated to children?
cat /sys/fs/cgroup/cgroup.subtree_control

# Can systemd create child cgroups?
mkdir /sys/fs/cgroup/test.scope 2>&1 && rmdir /sys/fs/cgroup/test.scope && echo "yes" || echo "no"

# systemd's view of cgroup state:
systemctl show --property=ControlGroup --property=MemoryCurrent --property=CPUUsageNSec agent@testuser.service

# Check if systemd is in degraded state:
systemctl --failed
systemd-analyze blame
```

## Key References

- [systemd CGROUP_DELEGATION.md](https://systemd.io/CGROUP_DELEGATION/) — the canonical guide
- [systemd v256 NEWS](https://github.com/systemd/systemd/blob/v256-stable/NEWS) — deprecation announcement
- [moby/moby#42275](https://github.com/moby/moby/issues/42275) — systemd + ro cgroup mount
- [docker/for-mac#6073](https://github.com/docker/for-mac/issues/6073) — Docker Desktop systemd issues
- [Jeff Geerling — Docker and systemd](https://www.jeffgeerling.com/blog/2022/docker-and-systemd-getting-rid-dreaded-failed-connect-bus-error/) — the `--privileged --cgroupns=host` pattern
- [pinkeen's gist](https://gist.github.com/pinkeen/bba0a6790fec96d6c8de84bd824ad933) — entrypoint remount approach
- [moby/moby#51111](https://github.com/moby/moby/issues/51111) — Docker's own cgroup v1 deprecation timeline
