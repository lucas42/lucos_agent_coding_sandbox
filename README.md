# lucOS Agent Coding Sandbox

A Lima VM for running Claude Code in an isolated environment. Claude gets
access to all lucas42 GitHub repositories but has no access to the host
machine or its credentials.

## Files

| File | Purpose |
|---|---|
| `lima.yaml` | Lima VM configuration |
| `setup-repos.sh` | Host-readable copy of the repo setup script (canonical version is embedded in `lima.yaml`) |

---

## First-time Setup

### 1. Install Lima

```bash
brew install lima
```

### 2. Create and start the VM

```bash
limactl start --name lucos-coding-sandbox ~/sandboxes/lucos_agent_coding_sandbox/lima.yaml
```

Lima will download the Ubuntu 24.04 image and run the provision scripts.
This takes a few minutes on first run — it installs Node.js, git, GitHub CLI,
and Claude Code inside the VM.

### 3. Shell into the VM

```bash
limactl shell lucos-coding-sandbox
```

### 4. Run the repository setup script

Inside the VM:

```bash
~/setup-repos.sh
```

This script will:

1. **Generate an SSH key** at `~/.ssh/id_ed25519_lucos_agent` inside the VM.
   The private key never leaves the VM.

2. **Print the public key** and ask you to add it to GitHub.
   Go to https://github.com/settings/keys, click "New SSH key",
   set the title to `lucos-agent-coding-sandbox`, type `Authentication Key`,
   and paste the key shown by the script.

3. **Test the SSH connection** to GitHub.

4. **Authenticate the GitHub CLI** using a device code flow.
   The script will show a URL and a one-time code.
   Open the URL in your Mac browser and enter the code.
   This gives the `gh` CLI inside the VM access to private repositories.

5. **Clone `lucos_claude_config`** to `~/.claude` so all Claude configuration
   (including agent persona definitions) is available inside the VM.

6. **Clone all non-archived `lucas42` repositories** into `~/sandboxes/`.

---

## Daily Use

### Start the VM (if not running)

```bash
limactl start lucos-coding-sandbox
```

### Shell in

```bash
limactl shell lucos-coding-sandbox
```

### Launch Claude Code inside the VM

```bash
# Inside the VM:
cd ~/sandboxes/<repo-name>
claude
```

### Stop the VM

```bash
limactl stop lucos-coding-sandbox
```

### Update all repo checkouts

Re-running the setup script inside the VM is safe and idempotent:

```bash
# Inside the VM:
~/setup-repos.sh
```

---

## Security Model

- **No host mounts**: The VM has no access to the host filesystem.
  Claude cannot reach host SSH keys, credentials, or config files.

- **No SSH agent forwarding**: SSH agent forwarding is explicitly disabled.
  Claude inside the VM must use its own dedicated SSH key
  (`~/.ssh/id_ed25519_lucos_agent`).

- **Isolated identity**: Git commits from inside the VM are attributed to
  `lucos-agent[bot]` (`2943201+lucos-agent[bot]@users.noreply.github.com`),
  making it clear which commits originated from the sandboxed agent.

- **Network access**: The VM has outbound internet access (via vzNAT) so
  Claude can clone repos and make API calls. It does not have any inbound
  access from the network.

- **Persistent storage**: The VM disk is persistent. Work survives VM
  restarts. This is intentional — ephemerality would mean losing in-progress
  work every time.

---

## VM Specifications

| Setting | Value |
|---|---|
| OS | Ubuntu 24.04 LTS |
| VM type | vz (Apple Virtualization Framework) |
| CPU | 4 cores |
| Memory | 8 GiB |
| Disk | 100 GiB |
| Host mounts | None |

---

## Maintenance Notes

**If the VM gets into a bad state:**

```bash
limactl stop lucos-coding-sandbox
limactl delete lucos-coding-sandbox
limactl start --name lucos-coding-sandbox ~/sandboxes/lucos_agent_coding_sandbox/lima.yaml
```

Then re-run `~/setup-repos.sh` inside the VM. The SSH key will be regenerated —
you will need to remove the old key from https://github.com/settings/keys
and add the new one.

**If a new repository is added to `lucas42`:**

Re-run `~/setup-repos.sh` inside the VM. It will clone any new repos
and skip existing ones.

**If `lucos_claude_config` is updated:**

```bash
# Inside the VM:
git -C ~/.claude pull
```

---

## lucos-agent Bot Identity

Git commits authored by Claude inside this VM use:

- **Name**: `lucos-agent[bot]`
- **Email**: `2943201+lucos-agent[bot]@users.noreply.github.com`

The number `2943201` is the GitHub App ID for the `lucos-agent` GitHub App.
This is the standard GitHub noreply email format for bot accounts.
