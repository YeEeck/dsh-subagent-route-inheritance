#!/usr/bin/env bash
# Install the dsh-subagent-route-inheritance plugin into one or more dsh profiles.
#
# Usage:
#   ./install.sh [--profile <name>]... [--all] [--help]
#
#   --profile <name>  target a dsh profile (default: web); repeatable
#   --all             install into every profile (web, headless, ...)
#
# The plugin row is inserted as its own `- insert:` block in the profile's
# cordis.patch.yml, so the loader picks it up after the next `dsh` start.
# Installing twice is a no-op. The dsh home resolves as $DSH_HOME, else
# ~/.dsh. Windows users: use install.ps1 instead.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_FILE="subagent-route-inheritance.mjs"
PLUGIN_SRC="$REPO_DIR/plugin/$PLUGIN_FILE"
PLUGIN_ID="subagent-route-inheritance"

# The canonical insert block; uninstall.sh removes exactly this unit.
BLOCK="# dsh-subagent-route-inheritance: subagent children inherit the parent's live model/effort route
- insert:
    - id: subagent-route-inheritance
      name: ./plugins/subagent-route-inheritance.mjs"

PROFILES=()
usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|-p) PROFILES+=("$2"); shift 2 ;;
    --all) PROFILES=(web headless); shift ;;
    --help|-h) usage 0 ;;
    *) echo "install.sh: unknown argument: $1" >&2; usage 1 ;;
  esac
done
if [[ ${#PROFILES[@]} -eq 0 ]]; then PROFILES=(web); fi

[[ -f "$PLUGIN_SRC" ]] || { echo "install.sh: plugin source not found: $PLUGIN_SRC" >&2; exit 1; }

DSH_HOME_RESOLVED="${DSH_HOME:-$HOME/.dsh}"
PROFILES_DIR="$DSH_HOME_RESOLVED/profiles"

for profile in "${PROFILES[@]}"; do
  profile_dir="$PROFILES_DIR/$profile"
  plugins_dir="$profile_dir/plugins"
  patch_file="$profile_dir/cordis.patch.yml"
  echo "== profile: $profile ($profile_dir)"

  mkdir -p "$plugins_dir"
  cp "$PLUGIN_SRC" "$plugins_dir/$PLUGIN_FILE"
  echo "  plugin copied to $plugins_dir/$PLUGIN_FILE"

  # Idempotency is keyed on the exact row line, not any mention of the plugin
  # id: a comment can legitimately name the plugin without installing it.
  if [[ -f "$patch_file" ]] && grep -qF "    - id: $PLUGIN_ID" "$patch_file"; then
    echo "  cordis.patch.yml already contains '$PLUGIN_ID'; nothing to do"
    continue
  fi

  if [[ ! -f "$patch_file" ]]; then
    printf '# Your patch layer for this dsh profile, applied after every bundle layer:\n# a top-level YAML array of loader patch entries (id-targeted config\n# overrides, disables, and insert lists; `!!js` expressions allowed).\n\n%s\n' "$BLOCK" > "$patch_file"
  else
    tmp="$(mktemp)"
    # Replace a bare `[]` (keeping any header comments) or append the block.
    awk -v block="$BLOCK" '
      /^[ \t]*\[\][ \t]*$/ { print ""; print block; found = 1; next }
      { print }
      END { if (!found) { print ""; print block } }
    ' "$patch_file" > "$tmp"
    mv "$tmp" "$patch_file"
  fi
  echo "  insert block added to $patch_file"
done

echo
echo "Done. Restart dsh (or reload the web profile) for the plugin to take effect."
echo "Verify with: ls \"$DSH_HOME_RESOLVED/profiles/<profile>/plugins/\""
