#!/bin/bash
# Monogray for Omarchy: uninstaller.
#
#   ./uninstall.sh [fallback-theme]   default fallback theme: tokyo-night
#   ./uninstall.sh --remove-icons     also delete the downloaded YAMIS icon set
#
# Removes the theme, the dock and cursor plugins, the theme-set hook and the GTK styling
# the hook installed, then switches to the fallback theme. The icon set is
# kept unless you ask, since other themes or apps may use it.
set -euo pipefail

THEME_ID="monogray"
PLUGIN_ID="monogray.dock"
fallback="tokyo-night"
remove_icons=0
for arg in "$@"; do
  case $arg in
    --remove-icons) remove_icons=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fallback="$arg" ;;
  esac
done

SHELL_JSON="$HOME/.config/omarchy/shell.json"
MARKER="managed by omarchy theme-extras hook"
step() { printf '\033[1;34m::\033[0m %s\n' "$*"; }

# Switch away first so nothing still points at the files being removed.
if [[ $(omarchy theme current 2>/dev/null) == "Monogray" ]]; then
  step "Switching to $fallback"
  omarchy theme set "$fallback"
fi

step "Removing the dock"
if omarchy plugin list 2>/dev/null | grep -q "^$PLUGIN_ID "; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null || true
fi
rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
if [[ -f $SHELL_JSON ]] && [[ $(jq -r '.bar.centerAnchor // ""' "$SHELL_JSON") == "$PLUGIN_ID" ]]; then
  tmp=$(mktemp)
  jq '.bar.centerAnchor = "omarchy.clock"' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
fi

step "Removing the cursor set"
CURSOR_DIR="$HOME/.config/omarchy/plugins/monogray.cursor"
[[ -x $CURSOR_DIR/apply.sh ]] && "$CURSOR_DIR/apply.sh" --off >/dev/null || true
if omarchy plugin list 2>/dev/null | grep -q "^monogray.cursor "; then
  omarchy plugin disable monogray.cursor >/dev/null || true
fi
rm -rf "$CURSOR_DIR"

step "Removing the theme-set hook and its GTK styling"
rm -f "$HOME/.config/omarchy/hooks/theme-set.d/monogray-extras.sh"
for f in "$HOME/.config/gtk-4.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"; do
  if [[ -f $f ]] && grep -qF "$MARKER" "$f"; then
    rm -f "$f"
    [[ -f $f.user-backup ]] && mv "$f.user-backup" "$f"
  fi
done

step "Removing the theme"
rm -rf "$HOME/.config/omarchy/themes/$THEME_ID"

# The clone install.sh moved here after `omarchy theme install` (if any).
if [[ -d $HOME/.local/share/monogray-theme ]]; then
  step "Removing the downloaded copy in ~/.local/share/monogray-theme"
  rm -rf "$HOME/.local/share/monogray-theme"
fi

if (( remove_icons )); then
  step "Removing the icon set"
  rm -rf "$HOME/.local/share/icons/yet-another-monochrome-icon-set"
fi

echo
echo "Monogray is removed. Your bar layout backups are next to $SHELL_JSON (*.bak.*)."
