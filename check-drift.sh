#!/bin/bash
# Reports drift between the live VM, drift-manifest/, and lima.yaml for global git
# config keys and the user crontab. Exits 1 and names each offending item on drift.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMA_YAML="${LIMA_YAML:-$DIR/lima.yaml}"
MANIFEST_DIR="${MANIFEST_DIR:-$DIR/drift-manifest}"
CRONTAB_CMD="${CRONTAB_CMD:-crontab -l}"   # overridable for tests

fail=0
body() { grep -vE '^\s*(#|$)' "$1" | sort -u; }

# compare <label-a> <file-a> <label-b> <file-b> <what>
compare() {
    local only_a only_b
    only_a=$(comm -23 "$2" "$4"); only_b=$(comm -13 "$2" "$4")
    [ -n "$only_a" ] && { fail=1; while IFS= read -r l; do echo "DRIFT [$5] in $1 but not $3: $l"; done <<<"$only_a"; }
    [ -n "$only_b" ] && { fail=1; while IFS= read -r l; do echo "DRIFT [$5] in $3 but not $1: $l"; done <<<"$only_b"; }
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# --- git config keys ---
body "$MANIFEST_DIR/git-config-keys.txt" | tr 'A-Z' 'a-z' | sort -u > "$tmp/git.manifest"
sed -nE 's/^\s*git config --global\s+(\S+).*/\1/p' "$LIMA_YAML" | tr -d '"' | tr 'A-Z' 'a-z' | sort -u > "$tmp/git.lima"
git config --global --list 2>/dev/null | cut -d= -f1 | tr 'A-Z' 'a-z' | sort -u > "$tmp/git.live"
compare "lima.yaml" "$tmp/git.lima" "manifest" "$tmp/git.manifest" "git config"
compare "live" "$tmp/git.live" "manifest" "$tmp/git.manifest" "git config"

# --- crontab ---
body "$MANIFEST_DIR/crontab.txt" | sed "s|\$HOME|$HOME|g" | sort -u > "$tmp/cron.manifest"
sed -nE 's/^\s*[A-Z_]+_ENTRY="(.*)"\s*$/\1/p' "$LIMA_YAML" | sed "s|\$HOME|$HOME|g" | sort -u > "$tmp/cron.lima"
$CRONTAB_CMD 2>/dev/null | grep -vE '^\s*(#|$)' | sort -u > "$tmp/cron.live"
compare "lima.yaml" "$tmp/cron.lima" "manifest" "$tmp/cron.manifest" "crontab"
compare "live" "$tmp/cron.live" "manifest" "$tmp/cron.manifest" "crontab"

[ "$fail" -eq 0 ] && echo "No drift (git config keys, crontab)."
exit "$fail"
