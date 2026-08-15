#!/usr/bin/env bash
# Uninstall the dsh-subagent-route-inheritance plugin from one or more dsh profiles.
#
# Usage:
#   ./uninstall.sh [--profile <name>]... [--all] [--help]
#
# Removes the plugin file and the insert block (or its row lines, if the block
# was hand-edited) from each profile's cordis.patch.yml. Other patch content is
# left untouched.

set -euo pipefail

PLUGIN_FILE="subagent-route-inheritance.mjs"
PLUGIN_ID="subagent-route-inheritance"
BLOCK_COMMENT="# dsh-subagent-route-inheritance: subagent children inherit the parent's live model/effort route"

PROFILES=()
usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|-p) PROFILES+=("$2"); shift 2 ;;
    --all) PROFILES=(web headless); shift ;;
    --help|-h) usage 0 ;;
    *) echo "uninstall.sh: unknown argument: $1" >&2; usage 1 ;;
  esac
done
if [[ ${#PROFILES[@]} -eq 0 ]]; then PROFILES=(web); fi

DSH_HOME_RESOLVED="${DSH_HOME:-$HOME/.dsh}"
PROFILES_DIR="$DSH_HOME_RESOLVED/profiles"

for profile in "${PROFILES[@]}"; do
  profile_dir="$PROFILES_DIR/$profile"
  plugins_dir="$profile_dir/plugins"
  patch_file="$profile_dir/cordis.patch.yml"
  echo "== profile: $profile ($profile_dir)"

  rm -f "$plugins_dir/$PLUGIN_FILE"
  echo "  plugin file removed"

  if [[ ! -f "$patch_file" ]]; then
    echo "  no cordis.patch.yml; nothing else to do"
    continue
  fi

  tmp="$(mktemp)"
  awk -v c1="$BLOCK_COMMENT" \
      -v id="    - id: $PLUGIN_ID" \
      -v nm="      name: ./plugins/$PLUGIN_FILE" '
    BEGIN { skip = 0 }
    {
      s = $0; sub(/\r$/, "", s)
      if (skip > 0) { skip--; next }
      # The canonical block is the comment line plus its three body lines
      # (insert header, id row, name row); drop it as one unit.
      if (s == c1) { skip = 3; next }
      # Stray exact rows (hand-edited block) are dropped individually.
      if (s == id || s == nm) next
      lines[++n] = $0
    }
    END {
      for (i = 1; i <= n; i++) {
        drop = 0
        s = lines[i]; sub(/\r$/, "", s)
        # Drop an insert header whose block ended up with no rows.
        if (s ~ /^[ \t]*- insert:[ \t]*$/) {
          j = i + 1
          while (j <= n && lines[j] ~ /^[ \t]*$/) j++
          if (j > n || lines[j] ~ /^[^ \t]/) drop = 1
        }
        if (!drop) print lines[i]
      }
    }
  ' "$patch_file" > "$tmp"
  # The loader requires the patch file to stay a top-level YAML array: a file
  # left with only comments and blank lines would fail boot, so restore `[]`.
  if ! grep -qE '^[^#[:space:]]' "$tmp"; then printf '[]\n' >> "$tmp"; fi
  mv "$tmp" "$patch_file"

  echo "  plugin rows removed from $patch_file"
done

echo
echo "Done. Restart dsh for the change to take effect."
