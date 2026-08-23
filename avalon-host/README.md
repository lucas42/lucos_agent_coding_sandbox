# avalon Host Provisioning

Scripts for provisioning `avalon` — the main lucos production host (amd64,
Debian bookworm). Unlike the Pi hosts, avalon is not Raspberry Pi hardware
and has no `archive.raspberrypi.com` repo.

## Scripts

### `setup-unattended-upgrades.sh`

Adds Docker-origin coverage to avalon's automatic upgrades. avalon already
runs 100% stock `unattended-upgrades` behaviour (Debian routine + security
auto-upgrades), but until this script is run, Docker-origin packages
(`docker-ce`, `docker-ce-cli`, `containerd.io`, ...) are excluded. See
lucas42/lucos_agent_coding_sandbox#98 and #100 for the full design record.

This script does **not** install or enable `unattended-upgrades` itself — it
assumes avalon's existing stock setup is already working, and only adds the
Docker origin on top of it.

**Run once** (and again if re-provisioning):

```bash
ssh avalon.s.l42.eu 'sudo bash -s' < avalon-host/setup-unattended-upgrades.sh
```

Note: Must be run as a user with passwordless sudo access.

**What it does:**
- Writes `/etc/apt/apt.conf.d/51lucos-docker-upgrades`, adding
  `Unattended-Upgrade::Origins-Pattern { "origin=Docker"; }` — matched by
  origin only, with no archive/codename constraint
- Does not touch `Package-Blacklist` (stays empty/absent) or
  `Automatic-Reboot` (left at avalon's existing stock value) — no carve-outs

## Active Hosts

- `avalon.s.l42.eu` — Debian bookworm (12), amd64
