#!/bin/bash
# setup-unattended-upgrades.sh — Configure automatic security updates on Pi hosts.
#
# Purpose:
#   1. Install and configure unattended-upgrades for Debian security packages only.
#   2. Add a read-only sudoers entry allowing lucos-agent to run 'apt list --upgradable'
#      without a password, so the agent can observe (but not apply) patch status.
#
# Design decisions:
#   - Security-only (not all upgrades): minimises the risk of a routine update
#     breaking services. Security patches have a much higher value/risk ratio.
#   - No apt sudo access for lucos-agent: avoids introducing a privilege escalation
#     path via the agent SSH key. The host patches itself autonomously.
#   - Read-only apt list sudoers: allows observability without write access.
#     Scoped to /usr/bin/apt specifically to avoid shell escape risks.
#   - Idempotent: safe to re-run on an already-configured host.
#
# Supported: Debian bookworm (12), Debian trixie (13). Detects codename at runtime.
#
# Run as: sudo bash setup-unattended-upgrades.sh
# Or remotely: ssh <host>.s.l42.eu 'sudo bash -s' < setup-unattended-upgrades.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

# Detect Debian codename (e.g. bookworm, trixie)
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
if [ -z "$CODENAME" ]; then
    echo "ERROR: Could not detect Debian codename from /etc/os-release." >&2
    exit 1
fi
echo "Detected Debian codename: $CODENAME"

# ---------------------------------------------------------------------------
# Step 1: Install unattended-upgrades if not already present
# ---------------------------------------------------------------------------
echo ""
echo "Step 1: Installing unattended-upgrades..."
if dpkg -s unattended-upgrades &>/dev/null; then
    echo "  unattended-upgrades is already installed -- skipping apt-get install."
else
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q unattended-upgrades
    echo "  Installed unattended-upgrades."
fi

# ---------------------------------------------------------------------------
# Step 2: Configure unattended-upgrades for security packages only
# ---------------------------------------------------------------------------
echo ""
echo "Step 2: Configuring unattended-upgrades..."

# Write the local override configuration.
# Scoped to Debian:${CODENAME}-security only — no routine updates.
# AutoFixInterruptedDpkg: recover from interrupted installs automatically.
# MinimalSteps: apply each upgrade as a minimal atomic step, reducing breakage risk.
# Remove: do NOT auto-remove unused packages (safer, avoids unintended removals).
cat > /etc/apt/apt.conf.d/51lucos-security-upgrades << APTCONF
// lucos Pi host — security-only automatic upgrades.
// Managed by lucos_agent_coding_sandbox/pi-hosts/setup-unattended-upgrades.sh
// Do not edit manually — changes will be overwritten by re-provisioning.

Unattended-Upgrade::Allowed-Origins {
    "Debian:${CODENAME}-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "false";
APTCONF
echo "  Written /etc/apt/apt.conf.d/51lucos-security-upgrades"

# ---------------------------------------------------------------------------
# Step 3: Enable the unattended-upgrades APT periodic job
# ---------------------------------------------------------------------------
echo ""
echo "Step 3: Enabling APT periodic updates..."

# APT::Periodic::Update-Package-Lists: run apt-get update daily (value = days)
# APT::Periodic::Unattended-Upgrade: run unattended-upgrade daily (value = days)
cat > /etc/apt/apt.conf.d/20auto-upgrades-lucos << 'APTPERIODIC'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APTPERIODIC
echo "  Written /etc/apt/apt.conf.d/20auto-upgrades-lucos"

# ---------------------------------------------------------------------------
# Step 4: Add read-only sudoers entry for lucos-agent
# ---------------------------------------------------------------------------
echo ""
echo "Step 4: Configuring read-only sudoers entry for lucos-agent..."

SUDOERS_FILE="/etc/sudoers.d/90-lucos-agent-apt-readonly"
SUDOERS_CONTENT="# Allow lucos-agent to check for upgradable packages without a password.
# Read-only: does not grant ability to install or apply patches.
# Scoped to /usr/bin/apt to avoid shell escape risks with /usr/bin/apt-get.
lucos-agent ALL=(ALL) NOPASSWD: /usr/bin/apt list --upgradable
"

if [ -f "$SUDOERS_FILE" ] && [ "$(cat "$SUDOERS_FILE")" = "$SUDOERS_CONTENT" ]; then
    echo "  Sudoers file already correctly configured -- skipping."
else
    echo "$SUDOERS_CONTENT" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    # Validate the sudoers file before leaving it in place
    if visudo -c -f "$SUDOERS_FILE"; then
        echo "  Written and validated $SUDOERS_FILE"
    else
        echo "ERROR: sudoers validation failed. Removing $SUDOERS_FILE for safety." >&2
        rm -f "$SUDOERS_FILE"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 5: Verify setup
# ---------------------------------------------------------------------------
echo ""
echo "Step 5: Verifying setup..."

echo "  Installed version: $(dpkg -l unattended-upgrades | awk '/^ii/ {print $3}')"
echo "  Allowed origins: $(grep 'Allowed-Origins' /etc/apt/apt.conf.d/51lucos-security-upgrades -A2)"
echo "  Sudoers entry: $(cat $SUDOERS_FILE | grep -v '^#' | grep -v '^$')"

echo ""
echo "Setup complete."
echo "  Security upgrades will run daily via APT periodic."
echo "  lucos-agent can check upgrade status with: sudo apt list --upgradable"
echo ""
echo "To test manually: unattended-upgrade --dry-run --debug 2>&1 | head -20"
