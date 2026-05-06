# Pi Hosts Provisioning

Scripts for provisioning the lucos Raspberry Pi hosts (salvare, xwing).

These hosts run Raspberry Pi OS / Debian and are not managed by Lima. They require manual bootstrapping the first time, after which they are largely self-maintaining.

## Scripts

### `setup-unattended-upgrades.sh`

Installs and configures automatic security-only OS patching, and adds a read-only sudoers entry allowing `lucos-agent` to check upgrade status.

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
- Configures security-only automatic upgrades (`Debian:${CODENAME}-security`)
- Enables daily apt periodic updates
- Adds `/etc/sudoers.d/90-lucos-agent-apt-readonly` so `lucos-agent` can run `sudo apt list --upgradable`

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
