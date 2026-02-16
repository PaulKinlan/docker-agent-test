#!/bin/bash
# test-systemd-services.sh — Verify systemd service management works in this container
#
# Usage: test-systemd-services.sh [--verbose]
#
# This script tests that:
#   1. cgroup v2 is available and writable
#   2. systemd is fully booted and functional
#   3. A test agent can be created and managed via systemctl
#   4. Resource limits (MemoryMax, CPUQuota) are applied
#   5. Service lifecycle (start/stop/restart) works
#   6. Boot-time reconciliation (agent-manager) is functional
#
# Exit codes:
#   0 — All tests passed
#   1 — One or more tests failed
#
# Designed to run inside the container. Use `make test-systemd` from the host.

set -euo pipefail

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# --- Options ---
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift ;;
        *) shift ;;
    esac
done

# --- Test framework ---
PASS=0
FAIL=0
TESTS=()

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

log() { echo -e "$*"; }
verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "  ${YELLOW}-> $*${RESET}" || true; }

pass() {
    local name="$1"
    ((PASS++)) || true
    TESTS+=("PASS: $name")
    log "  ${GREEN}✓${RESET} $name"
}

fail() {
    local name="$1"
    local detail="${2:-}"
    ((FAIL++)) || true
    TESTS+=("FAIL: $name")
    log "  ${RED}✗${RESET} $name"
    [[ -n "$detail" ]] && log "    ${RED}$detail${RESET}"
}

section() {
    log ""
    log "${BOLD}$1${RESET}"
}

# --- Cleanup ---
TEST_USER="__test_systemd__"

cleanup() {
    verbose "Cleaning up test user $TEST_USER"
    if id "$TEST_USER" &>/dev/null; then
        systemctl stop "agent@${TEST_USER}.service" 2>/dev/null || true
        systemctl disable "agent@${TEST_USER}.service" 2>/dev/null || true
        userdel -r "$TEST_USER" 2>/dev/null || true
    fi
    # Clean up the test cgroup if it was left behind
    rmdir /sys/fs/cgroup/test_harness.scope 2>/dev/null || true
}
trap cleanup EXIT

log ""
log "${BOLD}systemd Service Management Test Harness${RESET}"
log "Platform: $(uname -srm)"
log "systemd:  $(systemctl --version | head -1)"
log "Docker:   container=$(cat /proc/1/cgroup 2>/dev/null | head -1 || echo 'unknown')"
log ""

# =====================================================
# Phase 1: cgroup v2 infrastructure
# =====================================================
section "Phase 1: cgroup v2 infrastructure"

# Test: cgroup v2 filesystem type
CGROUP_FS=$(stat -fc %T /sys/fs/cgroup/ 2>/dev/null || echo "unknown")
if [[ "$CGROUP_FS" == "cgroup2fs" ]]; then
    pass "cgroup v2 filesystem detected ($CGROUP_FS)"
else
    fail "cgroup v2 filesystem not detected (got: $CGROUP_FS)" \
         "Expected cgroup2fs. Is the host running cgroup v2?"
fi

# Test: cgroup hierarchy is writable
if touch /sys/fs/cgroup/.test_harness 2>/dev/null; then
    rm -f /sys/fs/cgroup/.test_harness
    pass "cgroup hierarchy is writable"
else
    fail "cgroup hierarchy is read-only" \
         "Add 'cgroup: host' and '/sys/fs/cgroup:/sys/fs/cgroup:rw' to docker-compose.yml"
fi

# Test: can create child cgroups
if mkdir /sys/fs/cgroup/test_harness.scope 2>/dev/null; then
    rmdir /sys/fs/cgroup/test_harness.scope
    pass "Can create child cgroups"
else
    fail "Cannot create child cgroups" \
         "systemd needs to create cgroups for services. Check cgroup delegation."
fi

# Test: cgroup controllers are available
CONTROLLERS=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || echo "")
verbose "Available controllers: $CONTROLLERS"
if echo "$CONTROLLERS" | grep -q "memory"; then
    pass "Memory controller available"
else
    fail "Memory controller not available" \
         "MemoryMax=512M in agent@.service requires the memory controller"
fi

if echo "$CONTROLLERS" | grep -q "cpu"; then
    pass "CPU controller available"
else
    fail "CPU controller not available" \
         "CPUQuota=50% in agent@.service requires the cpu controller"
fi

# =====================================================
# Phase 2: systemd health
# =====================================================
section "Phase 2: systemd health"

# Test: systemd is PID 1
PID1_COMM=$(cat /proc/1/comm 2>/dev/null || echo "unknown")
if [[ "$PID1_COMM" == "systemd" ]]; then
    pass "systemd is PID 1"
else
    fail "systemd is not PID 1 (got: $PID1_COMM)"
fi

# Test: basic.target reached
if systemctl is-active basic.target &>/dev/null; then
    pass "basic.target is active"
else
    fail "basic.target is not active" \
         "systemd has not finished booting"
fi

# Test: multi-user.target reached
if systemctl is-active multi-user.target &>/dev/null; then
    pass "multi-user.target is active"
else
    fail "multi-user.target is not active"
fi

# Test: systemd is not degraded (or at least running)
SYSTEM_STATE=$(systemctl is-system-running 2>/dev/null || echo "unknown")
verbose "System state: $SYSTEM_STATE"
if [[ "$SYSTEM_STATE" == "running" || "$SYSTEM_STATE" == "degraded" ]]; then
    pass "systemd system state: $SYSTEM_STATE"
    if [[ "$SYSTEM_STATE" == "degraded" ]]; then
        verbose "Failed units: $(systemctl --failed --no-legend 2>/dev/null | head -5)"
    fi
else
    fail "systemd system state: $SYSTEM_STATE"
fi

# Test: journald is functional
if journalctl --no-pager -n 1 &>/dev/null; then
    pass "journald is functional"
else
    fail "journald is not functional"
fi

# =====================================================
# Phase 3: Agent service template
# =====================================================
section "Phase 3: Agent service template"

# Test: agent@.service template exists
if [[ -f /etc/systemd/system/agent@.service ]]; then
    pass "agent@.service template exists"
else
    fail "agent@.service template not found at /etc/systemd/system/agent@.service"
fi

# Test: run-agent.sh exists and is executable
if [[ -x /usr/local/bin/run-agent.sh ]]; then
    pass "run-agent.sh is executable"
else
    fail "run-agent.sh not found or not executable"
fi

# =====================================================
# Phase 4: Service lifecycle
# =====================================================
section "Phase 4: Service lifecycle (create/start/stop/restart)"

# Clean up any leftover test user from a previous run
cleanup

# Create a minimal test user
verbose "Creating test user: $TEST_USER"
groupadd -f agents 2>/dev/null || true
useradd -M -s /bin/bash -G agents -d "/home/$TEST_USER" "$TEST_USER" 2>/dev/null
mkdir -p "/home/$TEST_USER"
cp -a /etc/skel/. "/home/$TEST_USER/" 2>/dev/null || true
chown -R "$TEST_USER:$TEST_USER" "/home/$TEST_USER"
chmod 700 "/home/$TEST_USER"

# Create minimal .claude directory
mkdir -p "/home/$TEST_USER/.claude"
echo '{"agent":{"enabled":true,"persona":"base"}}' > "/home/$TEST_USER/.claude/config.json"
chown -R "$TEST_USER:$TEST_USER" "/home/$TEST_USER/.claude"

pass "Test user created: $TEST_USER"

# Test: systemctl daemon-reload
if systemctl daemon-reload 2>/dev/null; then
    pass "systemctl daemon-reload succeeded"
else
    fail "systemctl daemon-reload failed"
fi

# Test: enable service
if systemctl enable "agent@${TEST_USER}.service" 2>/dev/null; then
    pass "systemctl enable agent@${TEST_USER}.service"
else
    fail "systemctl enable agent@${TEST_USER}.service"
fi

# Test: start service
# The service will likely fail quickly (no API key), but the important thing
# is that systemd can successfully fork and exec the process.
if timeout --kill-after=5 10 systemctl start "agent@${TEST_USER}.service" 2>/dev/null; then
    pass "systemctl start agent@${TEST_USER}.service"
else
    # The service may have started then stopped (exit code from run-agent.sh).
    # Check if it was at least activated (even if it later failed).
    STATUS=$(systemctl show -p ActiveState "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
    RESULT=$(systemctl show -p Result "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
    EXEC_MAIN_PID=$(systemctl show -p ExecMainPID "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
    verbose "ActiveState=$STATUS Result=$RESULT ExecMainPID=$EXEC_MAIN_PID"

    if [[ "$EXEC_MAIN_PID" != "0" ]]; then
        # A process was spawned — systemd service management works even if the
        # process exited (expected without an API key).
        pass "systemctl start spawned process (PID $EXEC_MAIN_PID, exited: $RESULT)"
    else
        fail "systemctl start failed — no process was spawned" \
             "This is the core cgroup v2 issue. ExecMainPID=0 means systemd could not fork."
        verbose "Journal output:"
        journalctl -u "agent@${TEST_USER}.service" --no-pager -n 10 2>/dev/null | while read -r line; do
            verbose "  $line"
        done
    fi
fi

# Test: service shows in systemctl list
if systemctl list-units "agent@${TEST_USER}.service" --no-legend 2>/dev/null | grep -q "agent@"; then
    pass "Service visible in systemctl list-units"
else
    # May not show if it exited immediately — check list-unit-files instead
    if systemctl list-unit-files "agent@${TEST_USER}.service" --no-legend 2>/dev/null | grep -q "agent@"; then
        pass "Service visible in systemctl list-unit-files"
    else
        fail "Service not visible in systemctl"
    fi
fi

# Test: stop service
if timeout --kill-after=5 10 systemctl stop "agent@${TEST_USER}.service" 2>/dev/null; then
    pass "systemctl stop agent@${TEST_USER}.service"
else
    fail "systemctl stop agent@${TEST_USER}.service"
fi

# Test: restart service (start again after stop)
systemctl reset-failed "agent@${TEST_USER}.service" 2>/dev/null || true
if timeout --kill-after=5 10 systemctl start "agent@${TEST_USER}.service" 2>/dev/null; then
    pass "Service restart (stop then start) succeeded"
    systemctl stop "agent@${TEST_USER}.service" 2>/dev/null || true
else
    EXEC_MAIN_PID=$(systemctl show -p ExecMainPID "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
    if [[ "$EXEC_MAIN_PID" != "0" ]]; then
        pass "Service restart spawned process (exited — expected without API key)"
    else
        fail "Service restart failed — no process spawned"
    fi
fi

# Test: disable service
if systemctl disable "agent@${TEST_USER}.service" 2>/dev/null; then
    pass "systemctl disable agent@${TEST_USER}.service"
else
    fail "systemctl disable agent@${TEST_USER}.service"
fi

# =====================================================
# Phase 5: Resource limits
# =====================================================
section "Phase 5: Resource limits (cgroup controllers)"

# Re-enable and start the service for resource limit checks
systemctl reset-failed "agent@${TEST_USER}.service" 2>/dev/null || true
systemctl enable "agent@${TEST_USER}.service" 2>/dev/null || true
systemctl start "agent@${TEST_USER}.service" 2>/dev/null || true
sleep 1

# Test: MemoryMax is applied
MEMORY_MAX=$(systemctl show -p MemoryMax "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
verbose "MemoryMax value: $MEMORY_MAX"
if [[ "$MEMORY_MAX" == "536870912" ]]; then
    # 512M = 536870912 bytes
    pass "MemoryMax=512M is applied (536870912 bytes)"
elif [[ "$MEMORY_MAX" == "infinity" || -z "$MEMORY_MAX" ]]; then
    fail "MemoryMax not applied (got: ${MEMORY_MAX:-empty})" \
         "cgroup memory controller may not be delegated"
else
    # Could be a different representation
    pass "MemoryMax is set ($MEMORY_MAX)"
fi

# Test: CPUQuota is applied
CPU_QUOTA=$(systemctl show -p CPUQuotaPerSecUSec "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
verbose "CPUQuotaPerSecUSec: $CPU_QUOTA"
if [[ "$CPU_QUOTA" == "500ms" ]]; then
    pass "CPUQuota=50% is applied (500ms per second)"
elif [[ "$CPU_QUOTA" == "infinity" || -z "$CPU_QUOTA" ]]; then
    fail "CPUQuota not applied (got: ${CPU_QUOTA:-empty})" \
         "cgroup cpu controller may not be delegated"
else
    pass "CPUQuota is set ($CPU_QUOTA)"
fi

# Test: NoNewPrivileges
NNP=$(systemctl show -p NoNewPrivileges "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
if [[ "$NNP" == "yes" ]]; then
    pass "NoNewPrivileges=true is applied"
else
    fail "NoNewPrivileges not applied (got: ${NNP:-empty})"
fi

# Test: RestrictSUIDSGID
RSUID=$(systemctl show -p RestrictSUIDSGID "agent@${TEST_USER}.service" 2>/dev/null | cut -d= -f2)
if [[ "$RSUID" == "yes" ]]; then
    pass "RestrictSUIDSGID=true is applied"
else
    fail "RestrictSUIDSGID not applied (got: ${RSUID:-empty})"
fi

systemctl stop "agent@${TEST_USER}.service" 2>/dev/null || true

# =====================================================
# Phase 6: Journal logging
# =====================================================
section "Phase 6: Journal logging"

# Test: journal entries exist for our test service
JOURNAL_LINES=$(journalctl -u "agent@${TEST_USER}.service" --no-pager 2>/dev/null | wc -l)
verbose "Journal lines for test service: $JOURNAL_LINES"
if (( JOURNAL_LINES > 0 )); then
    pass "Journal entries recorded for agent service ($JOURNAL_LINES lines)"
else
    fail "No journal entries for agent service"
fi

# =====================================================
# Phase 7: Boot services
# =====================================================
section "Phase 7: Boot services"

# Test: agent-manager.service exists and ran
if systemctl list-unit-files agent-manager.service --no-legend 2>/dev/null | grep -q "agent-manager"; then
    pass "agent-manager.service is installed"
    AM_RESULT=$(systemctl show -p Result agent-manager.service 2>/dev/null | cut -d= -f2)
    verbose "agent-manager result: $AM_RESULT"
    if [[ "$AM_RESULT" == "success" ]]; then
        pass "agent-manager.service completed successfully"
    else
        fail "agent-manager.service result: $AM_RESULT"
    fi
else
    fail "agent-manager.service not found"
fi

# Test: api-keys-sync.service exists
if systemctl list-unit-files api-keys-sync.service --no-legend 2>/dev/null | grep -q "api-keys-sync"; then
    pass "api-keys-sync.service is installed"
else
    fail "api-keys-sync.service not found"
fi

# =====================================================
# Summary
# =====================================================
section "Summary"

TOTAL=$((PASS + FAIL))
log ""
log "  Total: $TOTAL tests"
log "  ${GREEN}Passed: $PASS${RESET}"
if (( FAIL > 0 )); then
    log "  ${RED}Failed: $FAIL${RESET}"
    log ""
    log "${RED}${BOLD}FAIL${RESET} — $FAIL test(s) failed. See docs/systemd-cgroup-docker-compat.md for troubleshooting."
    exit 1
else
    log ""
    log "${GREEN}${BOLD}PASS${RESET} — All tests passed. systemd service management is functional."
    exit 0
fi
