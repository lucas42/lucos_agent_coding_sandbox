#!/bin/bash
# Exercises check-drift.sh against a fake global git config, crontab and lima.yaml.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; failed=0

reset() {
    cp "$DIR/lima.yaml" "$T/lima.yaml"
    export GIT_CONFIG_GLOBAL="$T/gitconfig" LIMA_YAML="$T/lima.yaml"
    : > "$T/gitconfig"
    while read -r k; do
        case "$k" in url.*) git config --global 'url.git@github.com:.insteadOf' x;; *) git config --global "$k" x;; esac
    done < <(grep -vE '^\s*(#|$)' "$DIR/drift-manifest/git-config-keys.txt")
    grep -vE '^\s*(#|$)' "$DIR/drift-manifest/crontab.txt" | sed "s|\$HOME|$HOME|g" > "$T/cron"
    export CRONTAB_CMD="cat $T/cron"
}
# check <name> <expected rc> <expected output substring or ''>
check() {
    local out rc; out=$("$DIR/check-drift.sh" 2>&1); rc=$?
    if [ "$rc" -eq "$2" ] && { [ -z "$3" ] || grep -qF -- "$3" <<<"$out"; }; then pass=$((pass+1)); echo "ok - $1"
    else failed=$((failed+1)); echo "FAIL - $1 (rc=$rc): $out"; fi
}

reset; check "clean state exits 0" 0 "No drift"
reset; git config --global user.name x; check "extra live git key flagged" 1 "user.name"
reset; echo '0 1 * * * /tmp/x' >> "$T/cron"; check "extra live cron line flagged" 1 "/tmp/x"
reset; sed -i '/pull.rebase/d' "$T/gitconfig" 2>/dev/null; git config --global --unset pull.rebase; check "missing live git key flagged" 1 "pull.rebase"
reset; sed -i '0,/git config --global pull.rebase false/s//git config --global pull.rebase false\n      git config --global foo.bar 1/' "$T/lima.yaml"; check "lima.yaml git key absent from manifest flagged" 1 "foo.bar"
reset; sed -i 's|^\(\s*\)PRUNE_ENTRY=|\1NEW_ENTRY="0 1 * * * /tmp/new"\n\1PRUNE_ENTRY=|' "$T/lima.yaml"; check "lima.yaml cron entry absent from manifest flagged" 1 "/tmp/new"

echo "$pass passed, $failed failed"; [ "$failed" -eq 0 ]
