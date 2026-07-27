#!/bin/bash
# setup-apt-timer-stagger.sh — Offset salvare's apt-daily-upgrade.timer so it
# doesn't fire in the same window as xwing's.
#
# Purpose:
#   xwing and salvare both run the stock apt-daily-upgrade.timer schedule
#   (OnCalendar=*-*-* 6:00, RandomizedDelaySec=60m). Each host draws its own
#   random delay independently, but independence doesn't guarantee separation:
#   on 2026-07-15 the two hosts' upgrade runs landed 28 seconds apart. A bad
#   release from any covered apt origin can therefore land on both hosts in
#   the same window, with no chance to notice breakage on one before it
#   applies to the other.
#
# Design decisions:
#   - Deterministic timer offset, not a wider RandomizedDelaySec: widening the
#     random window only reduces the probability of overlap, it can't
#     guarantee a minimum gap. A fixed offset between the two hosts' schedules
#     gives an auditable, stated minimum separation instead.
#   - Only salvare gets an override; xwing stays on the stock 06:00 schedule.
#     This keeps a single point of configuration to audit ("which one moved")
#     rather than maintaining two custom schedules.
#   - salvare moves to 12:00 — a ~6-hour minimum gap from xwing's 06:00+60m
#     jitter, comfortably clear even at the jitter extremes on both sides.
#   - RandomizedDelaySec is left untouched on both hosts — it's harmless local
#     jitter and isn't the mechanism doing the separation work here.
#   - Host-aware via `hostname -f`: safe to run unmodified on either host, so
#     it matches the same "run this on all pi hosts" operational pattern as
#     setup-unattended-upgrades.sh / setup-journald.sh, even though only one
#     host actually changes.
#   - Idempotent: safe to re-run on an already-configured host.
#
# Supported: Debian bookworm (12), Debian trixie (13).
#
# Run as: sudo bash setup-apt-timer-stagger.sh
# Or remotely: ssh <host>.s.l42.eu 'sudo bash -s' < pi-hosts/setup-apt-timer-stagger.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

HOSTNAME_FQDN="$(hostname -f)"
DROP_IN_DIR="/etc/systemd/system/apt-daily-upgrade.timer.d"
DROP_IN_FILE="${DROP_IN_DIR}/lucos-stagger.conf"

echo "Detected hostname: ${HOSTNAME_FQDN}"

if [[ "$HOSTNAME_FQDN" != *salvare* ]]; then
    echo ""
    echo "This host is not salvare -- no timer change needed here by design."
    echo "  xwing (and any other host) stays on the stock apt-daily-upgrade.timer"
    echo "  schedule (OnCalendar=*-*-* 6:00). Only salvare's schedule is offset."

    if [ -f "$DROP_IN_FILE" ]; then
        echo ""
        echo "WARNING: ${DROP_IN_FILE} exists on a non-salvare host -- this is" >&2
        echo "  unexpected and was not written by this script on this host. Investigate" >&2
        echo "  before assuming it's safe to remove." >&2
    fi

    echo ""
    echo "Nothing to do. Exiting."
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: Write the systemd timer override
# ---------------------------------------------------------------------------
echo ""
echo "Step 1: Writing apt-daily-upgrade.timer override..."

mkdir -p "$DROP_IN_DIR"

# The empty OnCalendar= clears the inherited stock value before setting the
# new one -- systemd timer drop-ins append by default, so without the clear
# line salvare would end up with two OnCalendar entries (both would fire).
DESIRED_CONTENT="# lucos Pi host — stagger apt-daily-upgrade.timer away from xwing's schedule.
# Managed by lucos_agent_coding_sandbox/pi-hosts/setup-apt-timer-stagger.sh
# Do not edit manually — changes will be overwritten by re-provisioning.

[Timer]
OnCalendar=
OnCalendar=*-*-* 12:00
"

if [ -f "$DROP_IN_FILE" ] && printf '%s' "$DESIRED_CONTENT" | cmp -s "$DROP_IN_FILE" -; then
    echo "  Drop-in config already correctly configured -- skipping."
else
    printf '%s' "$DESIRED_CONTENT" > "$DROP_IN_FILE"
    chmod 644 "$DROP_IN_FILE"
    echo "  Written ${DROP_IN_FILE}"
fi

# ---------------------------------------------------------------------------
# Step 2: Reload and apply
# ---------------------------------------------------------------------------
echo ""
echo "Step 2: Reloading systemd and restarting the timer..."

systemctl daemon-reload
systemctl restart apt-daily-upgrade.timer
echo "  apt-daily-upgrade.timer restarted -- new schedule is active immediately,"
echo "  no reboot or wait for the next stock-scheduled run required."

# ---------------------------------------------------------------------------
# Step 3: Verify
# ---------------------------------------------------------------------------
echo ""
echo "Step 3: Verifying setup..."

EFFECTIVE_ONCALENDAR=$(systemctl show apt-daily-upgrade.timer -p TimersCalendar --value 2>/dev/null || echo "(not found)")
echo "  Effective OnCalendar: ${EFFECTIVE_ONCALENDAR}"

echo ""
systemctl list-timers apt-daily-upgrade.timer --no-pager

echo ""
echo "Setup complete."
echo "  salvare's apt-daily-upgrade.timer now fires at 12:00 (+/- up to 60m jitter),"
echo "  a ~6-hour minimum gap from xwing's stock 06:00 (+/- up to 60m jitter)."
echo "  RandomizedDelaySec was not changed on this host."
