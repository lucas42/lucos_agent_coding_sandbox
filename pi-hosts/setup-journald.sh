#!/bin/bash
# setup-journald.sh — Configure persistent systemd journal storage on Pi hosts.
#
# Purpose:
#   Configure journald to store logs persistently in /var/log/journal/ rather
#   than the default volatile RAM storage (/run/log/journal/). This ensures
#   logs survive reboots and are available for post-incident investigation.
#
# Background:
#   Raspberry Pi hosts ship with /etc/systemd/journald.conf setting
#   Storage=volatile, which means all system logs are held in RAM and
#   permanently lost on every reboot. When salvare lost network connectivity
#   on 2026-05-06 and was physically rebooted, it was impossible to determine
#   the root cause from logs — they had been wiped by the reboot.
#
# Design decisions:
#   - Uses a drop-in config (/etc/systemd/journald.conf.d/10-lucos-persistent.conf)
#     rather than modifying /etc/systemd/journald.conf directly. Drop-ins are
#     more robust: they survive package updates that might regenerate the main
#     config file, and they make our intent explicit.
#   - SystemMaxUse=500M caps disk usage to prevent runaway log growth on the
#     Pi's SD card / SSD. Journald rotates automatically to stay within this.
#   - Creates /var/log/journal/ explicitly. journald will create it on restart
#     if it doesn't exist, but being explicit avoids any edge cases.
#   - Idempotent: safe to re-run on an already-configured host.
#
# Supported: Debian bookworm (12), Debian trixie (13).
#
# Run as: sudo bash setup-journald.sh
# Or remotely: ssh <host>.s.l42.eu 'sudo bash -s' < pi-hosts/setup-journald.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Create the persistent journal directory
# ---------------------------------------------------------------------------
echo ""
echo "Step 1: Ensuring /var/log/journal/ exists..."

if [ -d /var/log/journal ]; then
    echo "  /var/log/journal/ already exists -- skipping mkdir."
else
    mkdir -p /var/log/journal
    echo "  Created /var/log/journal/"
fi

# Ensure correct ownership (systemd-journal group)
chown root:systemd-journal /var/log/journal 2>/dev/null || chown root:root /var/log/journal
chmod 2755 /var/log/journal
echo "  Permissions set on /var/log/journal/"

# ---------------------------------------------------------------------------
# Step 2: Write the journald drop-in config
# ---------------------------------------------------------------------------
echo ""
echo "Step 2: Writing journald drop-in configuration..."

DROP_IN_DIR="/etc/systemd/journald.conf.d"
DROP_IN_FILE="${DROP_IN_DIR}/10-lucos-persistent.conf"

mkdir -p "$DROP_IN_DIR"

DESIRED_CONTENT="# lucos Pi host — persistent journal storage.
# Managed by lucos_agent_coding_sandbox/pi-hosts/setup-journald.sh
# Do not edit manually — changes will be overwritten by re-provisioning.

[Journal]
Storage=persistent
SystemMaxUse=500M
"

if [ -f "$DROP_IN_FILE" ] && [ "$(cat "$DROP_IN_FILE")x" = "${DESIRED_CONTENT}x" ]; then
    echo "  Drop-in config already correctly configured -- skipping."
else
    printf '%s' "$DESIRED_CONTENT" > "$DROP_IN_FILE"
    chmod 644 "$DROP_IN_FILE"
    echo "  Written ${DROP_IN_FILE}"
fi

# ---------------------------------------------------------------------------
# Step 3: Restart systemd-journald to apply changes
# ---------------------------------------------------------------------------
echo ""
echo "Step 3: Restarting systemd-journald..."

systemctl restart systemd-journald
echo "  systemd-journald restarted."

# ---------------------------------------------------------------------------
# Step 4: Verify setup
# ---------------------------------------------------------------------------
echo ""
echo "Step 4: Verifying setup..."

EFFECTIVE_STORAGE=$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null | grep '^Storage=' | tail -1 || echo "(not found)")
echo "  Effective Storage setting: ${EFFECTIVE_STORAGE}"

if journalctl --disk-usage &>/dev/null; then
    echo "  Journal disk usage: $(journalctl --disk-usage 2>/dev/null | grep -oP 'Archived and active journals take up \K.*' || echo '(see journalctl --disk-usage)')"
fi

JOURNAL_DIR_CONTENTS=$(ls /var/log/journal/ 2>/dev/null || echo "(empty)")
echo "  /var/log/journal/ contents: ${JOURNAL_DIR_CONTENTS}"

echo ""
echo "Setup complete."
echo "  Logs will now be stored persistently in /var/log/journal/"
echo "  Maximum disk usage capped at 500M (journald rotates automatically)"
echo ""
echo "To verify: journalctl --disk-usage"
echo "To view logs from previous boot: journalctl -b -1"
