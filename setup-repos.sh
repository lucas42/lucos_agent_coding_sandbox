#!/bin/bash
# setup-repos.sh — Run this inside the Lima VM after first boot.
#
# What this does:
#   1. Generates a new Ed25519 SSH key for Claude inside this VM
#   2. Prints the public key so you can add it to GitHub
#   3. Waits for you to confirm the key has been added
#   4. Tests GitHub SSH connectivity
#   5. Authenticates the GitHub CLI using device code flow
#   6. Clones lucos_claude_config -> ~/.claude
#   7. Clones all non-archived lucas42 repositories into ~/sandboxes/
#      (including private repos, since gh CLI is authenticated)
#
# This script is idempotent — safe to re-run.

set -euo pipefail

SSH_KEY="$HOME/.ssh/id_ed25519_lucos_agent"
SANDBOXES="$HOME/sandboxes"

echo "======================================================="
echo "  lucOS Agent Coding Sandbox -- Repository Setup"
echo "======================================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1: Generate SSH key
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$SSH_KEY" ]; then
    echo "SSH key already exists at $SSH_KEY -- skipping generation."
else
    echo "Generating new Ed25519 SSH key..."
    ssh-keygen -t ed25519 -C "lucos-agent-coding-sandbox" -f "$SSH_KEY" -N ""
    echo "Key generated."
fi

echo ""
echo "-------------------------------------------------------"
echo "  ACTION REQUIRED: Add this public key to GitHub"
echo "-------------------------------------------------------"
echo ""
echo "Go to:  https://github.com/settings/keys"
echo "Click 'New SSH key', title it 'lucos-agent-coding-sandbox',"
echo "set type to 'Authentication Key', and paste the following:"
echo ""
cat "${SSH_KEY}.pub"
echo ""
echo "-------------------------------------------------------"
echo ""
read -rp "Press Enter once you have added the key to GitHub... "

# ---------------------------------------------------------------------------
# Step 2: Configure SSH to use this key for GitHub
# ---------------------------------------------------------------------------
SSH_CONFIG="$HOME/.ssh/config"

if grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
    echo "SSH config already has a github.com entry -- skipping."
else
    {
        echo ""
        echo "Host github.com"
        echo "    HostName github.com"
        echo "    User git"
        echo "    IdentityFile ~/.ssh/id_ed25519_lucos_agent"
        echo "    IdentitiesOnly yes"
    } >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "SSH config updated."
fi

# ---------------------------------------------------------------------------
# Step 3: Test GitHub SSH connectivity
# ---------------------------------------------------------------------------
echo ""
echo "Testing GitHub SSH connectivity..."
SSH_RESULT=$(ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 || true)
echo "$SSH_RESULT"
if echo "$SSH_RESULT" | grep -q "successfully authenticated"; then
    echo "GitHub SSH authentication successful."
else
    echo ""
    echo "WARNING: GitHub SSH test did not return the expected success message."
    echo "The key may not have been saved correctly, or GitHub may be slow to"
    echo "propagate the new key. If cloning fails below, check the key on"
    echo "https://github.com/settings/keys and re-run this script."
    echo ""
    read -rp "Continue anyway? (y/N) " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 4: Authenticate GitHub CLI (for private repo access)
# ---------------------------------------------------------------------------
echo ""
echo "Authenticating GitHub CLI..."
if gh auth status &>/dev/null; then
    echo "GitHub CLI already authenticated."
else
    echo "This will use a device code flow."
    echo "A URL and one-time code will be shown below."
    echo "Open the URL on your Mac browser and enter the code to authenticate."
    echo ""
    # --git-protocol ssh: use SSH for git operations
    # gh will show a device code URL since we are in a headless environment
    gh auth login --git-protocol ssh --hostname github.com
fi

# ---------------------------------------------------------------------------
# Step 5: Clone lucos_claude_config -> ~/.claude
# ---------------------------------------------------------------------------
echo ""
echo "Cloning lucos_claude_config -> ~/.claude ..."
if [ -d "$HOME/.claude/.git" ]; then
    echo "~/.claude already has a git repo -- pulling latest."
    git -C "$HOME/.claude" pull --ff-only || echo "  (could not fast-forward, skipping pull)"
elif [ -d "$HOME/.claude" ] && [ "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
    echo "WARNING: ~/.claude exists and is non-empty but is not a git repo."
    echo "Moving existing contents to ~/.claude.bak before cloning."
    mv "$HOME/.claude" "$HOME/.claude.bak"
    git clone git@github.com:lucas42/lucos_claude_config.git "$HOME/.claude"
else
    git clone git@github.com:lucas42/lucos_claude_config.git "$HOME/.claude"
fi
echo "lucos_claude_config cloned to ~/.claude"

# ---------------------------------------------------------------------------
# Step 6: Clone all non-archived lucas42 repos into ~/sandboxes/
# ---------------------------------------------------------------------------
echo ""
echo "Fetching list of lucas42 repositories from GitHub..."

# Use authenticated gh CLI to get all repos including private ones
REPO_LIST=$(gh repo list lucas42 --limit 200 --json name,sshUrl,isArchived \
    --jq '.[] | select(.isArchived == false) | .sshUrl')

REPOS=()
while IFS= read -r line; do
    [ -n "$line" ] && REPOS+=("$line")
done <<< "$REPO_LIST"

echo "Found ${#REPOS[@]} non-archived repositories."
echo ""

mkdir -p "$SANDBOXES"

CLONED=0
UPDATED=0
SKIPPED=0

for REPO_URL in "${REPOS[@]}"; do
    REPO_NAME=$(basename "$REPO_URL" .git)

    # lucos_claude_config is already at ~/.claude
    if [ "$REPO_NAME" = "lucos_claude_config" ]; then
        echo "  [skip] $REPO_NAME (already at ~/.claude)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    TARGET="$SANDBOXES/$REPO_NAME"
    if [ -d "$TARGET/.git" ]; then
        echo "  [pull] $REPO_NAME"
        git -C "$TARGET" pull --ff-only 2>/dev/null \
            || echo "    (could not fast-forward, skipping pull)"
        UPDATED=$((UPDATED + 1))
    else
        echo "  [clone] $REPO_NAME"
        git clone "$REPO_URL" "$TARGET" 2>/dev/null \
            || echo "    WARNING: clone failed for $REPO_NAME"
        CLONED=$((CLONED + 1))
    fi
done

echo ""
echo "======================================================="
echo "  Setup complete!"
echo "======================================================="
echo ""
echo "Summary:"
echo "  Cloned:  $CLONED repositories"
echo "  Updated: $UPDATED repositories"
echo "  Skipped: $SKIPPED repositories"
echo ""
echo "Key locations:"
echo "  ~/.claude         <- lucos_claude_config (Claude config + personas)"
echo "  ~/sandboxes/      <- all other lucas42 repositories"
echo "  ~/.ssh/id_ed25519_lucos_agent  <- SSH key for GitHub"
echo ""
echo "To launch Claude Code inside the VM:"
echo "  cd ~/sandboxes/<repo-name>"
echo "  claude"
echo ""
