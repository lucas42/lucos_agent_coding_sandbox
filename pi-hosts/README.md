# Pi Hosts Provisioning

Scripts for provisioning the lucos Raspberry Pi hosts (salvare, xwing).

These hosts run Raspberry Pi OS / Debian and are not managed by Lima. They require manual bootstrapping the first time, after which they are largely self-maintaining.

## Scripts

### `setup-unattended-upgrades.sh`

Installs and configures automatic OS patching — security-only for Debian, full (not security-only) for Docker and Raspberry Pi Foundation packages — and adds a read-only sudoers entry allowing `lucos-agent` to check upgrade status. See lucas42/lucos_agent_coding_sandbox#98 and #100 for the design record.

**Run once per host** (and again if re-provisioning):

```bash
scp pi-hosts/setup-unattended-upgrades.sh <host>.s.l42.eu:/tmp/
ssh <host>.s.l42.eu 'sudo bash /tmp/setup-unattended-upgrades.sh'
```

Or directly:

```bash
ssh <host>.s.l42.eu 'sudo bash -s' < pi-hosts/setup-unattended-upgrades.sh
```

Note: This must be run as a user with passwordless sudo access (e.g. the `pi` user). The `lucos-agent` SSH user does not have sudo access by design.

**What it does:**
- Installs `unattended-upgrades` if not already present
- Configures security-only automatic upgrades for Debian (`Debian:${CODENAME}-security`)
- Configures full automatic upgrades (not security-only) for Docker and Raspberry Pi Foundation packages, matched by origin only (`Unattended-Upgrade::Origins-Pattern`) — no archive/codename constraint, since Raspberry Pi Foundation's archive field (`stable`/`oldstable`) isn't the Debian codename and that mapping shifts at release boundaries
- Enables daily apt periodic updates
- Adds `/etc/sudoers.d/90-lucos-agent-apt-readonly` so `lucos-agent` can run `sudo apt list --upgradable`
- `Package-Blacklist` stays empty and `Automatic-Reboot` stays `false` for all origins — no carve-outs (decided on lucas42/lucos_agent_coding_sandbox#98)

### `setup-apt-timer-stagger.sh`

Offsets salvare's `apt-daily-upgrade.timer` so it doesn't fire in the same window as xwing's — see the script's header comment for the full rationale (independent `RandomizedDelaySec` draws don't guarantee separation between hosts; a deterministic offset does).

**Run once per host** (safe to run unmodified on both — it's a no-op on any host that isn't salvare):

```bash
ssh <host>.s.l42.eu 'sudo bash -s' < pi-hosts/setup-apt-timer-stagger.sh
```

Note: Must be run as a user with passwordless sudo access (e.g. the `pi` user).

**What it does:**
- On salvare: writes `/etc/systemd/system/apt-daily-upgrade.timer.d/lucos-stagger.conf` overriding `OnCalendar` to `*-*-* 12:00`, then reloads systemd and restarts the timer so the new schedule takes effect immediately
- On any other host (e.g. xwing): no-op — stays on the stock `06:00` schedule by design
- Does not change `RandomizedDelaySec` on either host

### `setup-journald.sh`

Configures systemd journal storage to be persistent, so logs survive reboots.

Background: Pi hosts default to `Storage=volatile`, storing logs only in RAM (`/run/log/journal/`). This means all system logs are permanently lost on every reboot, making post-incident investigation impossible.

**Run once per host** (and again if re-provisioning):

```bash
ssh <host>.s.l42.eu 'sudo bash -s' < pi-hosts/setup-journald.sh
```

Note: Must be run as a user with passwordless sudo access (e.g. the `pi` user).

**What it does:**
- Creates `/var/log/journal/` with correct ownership
- Writes a drop-in config at `/etc/systemd/journald.conf.d/50-lucos-persistent.conf` setting `Storage=persistent` and `SystemMaxUse=500M` (named `50-` to sort after Raspberry Pi OS's `/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf` on Trixie hosts)
- Restarts `systemd-journald` and runs `journalctl --flush` to migrate any existing volatile logs immediately

## Active Pi Hosts

- `salvare.s.l42.eu` — Debian bookworm (12), aarch64
- `xwing.s.l42.eu` — Debian trixie (13), aarch64
