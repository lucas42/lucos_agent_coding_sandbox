#!/bin/bash
# setup-unattended-upgrades.sh — Add Docker-origin coverage to avalon's
# automatic upgrades.
#
# Purpose:
#   avalon runs on 100% stock unattended-upgrades behaviour today (Debian
#   routine + security auto-upgrades already enabled) but has never had any
#   lucos-managed apt config, so Docker-origin packages (docker-ce,
#   docker-ce-cli, containerd.io, ...) are excluded from automatic upgrades.
#   This adds Docker-origin coverage only — it does not touch avalon's
#   existing (already-working) Debian auto-upgrade behaviour, and does not
#   perform first-time install/enablement of unattended-upgrades itself.
#
# Design decisions:
#   - Origin-only match (Unattended-Upgrade::Origins-Pattern "origin=Docker"),
#     not the "Origin:Archive" Allowed-Origins syntax — matches the approach
#     taken on the Pi hosts (see pi-hosts/setup-unattended-upgrades.sh) and
#     avoids relying on Docker's archive-field-equals-codename coincidence.
#   - No security-only restriction: Docker doesn't publish a security-only
#     origin, and lucas42 explicitly decided against carve-outs for it. See
#     lucas42/lucos_agent_coding_sandbox#98 and #100 for the full design record.
#   - Package-Blacklist stays empty; Automatic-Reboot is left at whatever
#     avalon's stock config already has — no changes beyond adding Docker
#     origin coverage.
#   - Separate file/directory from pi-hosts/: avalon is amd64, not Raspberry
#     Pi hardware — it has no archive.raspberrypi.com repo, so there is no
#     Raspberry Pi Foundation origin to add here, and the script's scope
#     (add one origin to an already-working setup) is materially smaller
#     than the Pi hosts' first-time install-and-configure.
#   - Idempotent: safe to re-run on an already-configured host.
#
# Run as: sudo bash setup-unattended-upgrades.sh
# Or remotely: ssh avalon.s.l42.eu 'sudo bash -s' < setup-unattended-upgrades.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

if ! dpkg -s unattended-upgrades &>/dev/null; then
    echo "ERROR: unattended-upgrades is not installed on this host." >&2
    echo "This script only adds Docker-origin coverage to an existing stock" >&2
    echo "unattended-upgrades setup — it does not perform first-time install." >&2
    exit 1
fi

echo "Configuring Docker-origin automatic upgrades..."

cat > /etc/apt/apt.conf.d/51lucos-docker-upgrades << 'APTCONF'
// lucos avalon host — adds Docker-origin automatic upgrades on top of
// avalon's existing stock Debian (routine + security) unattended-upgrades
// behaviour.
// Managed by lucos_agent_coding_sandbox/avalon-host/setup-unattended-upgrades.sh
// Do not edit manually — changes will be overwritten by re-provisioning.

Unattended-Upgrade::Origins-Pattern {
    "origin=Docker";
};
APTCONF
echo "  Written /etc/apt/apt.conf.d/51lucos-docker-upgrades"

echo ""
echo "Verifying setup..."
echo "  Installed version: $(dpkg -l unattended-upgrades | awk '/^ii/ {print $3}')"
echo "  Origins pattern: $(grep 'Origins-Pattern' /etc/apt/apt.conf.d/51lucos-docker-upgrades -A2)"

echo ""
echo "Setup complete."
echo "  Docker-origin packages will now be included in avalon's existing daily"
echo "  automatic-upgrade run. Debian-origin behaviour is unchanged."
echo ""
echo "To test manually: unattended-upgrade --dry-run --debug 2>&1 | head -20"
