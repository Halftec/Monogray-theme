#!/bin/bash
# Install and apply the Monogray cursor theme to ~/.local/share/icons. Run by Service.qml each
# time the Omarchy shell loads the plugin (so at every login), or by hand.
#
#   apply.sh          install (if changed) and apply it
#   apply.sh --off    switch back to the system default cursor
set -euo pipefail

NAME="Monogray-Cursor"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONS="$HOME/.local/share/icons"
SIZE="${HYPRCURSOR_SIZE:-${XCURSOR_SIZE:-24}}"
UWSM_ENV="$HOME/.config/uwsm/env-hyprland"
BEGIN="# >>> monogray.cursor (managed by the Monogray Cursor plugin) >>>"
END="# <<< monogray.cursor <<<"

remove_env_block() {
  [[ -f $UWSM_ENV ]] || return 0
  sed -i "/^# >>> monogray.cursor/,/^# <<< monogray.cursor <<</d" "$UWSM_ENV"
  [[ -s $UWSM_ENV ]] || rm -f "$UWSM_ENV"
}

if [[ ${1:-} == --off ]]; then
  remove_env_block
  systemctl --user unset-environment XCURSOR_THEME HYPRCURSOR_THEME 2>/dev/null || true
  hyprctl setcursor default "$SIZE" >/dev/null
  gsettings reset org.gnome.desktop.interface cursor-theme 2>/dev/null || true
  rm -rf "${ICONS:?}/$NAME"
  echo "monogray-cursor: reverted to the default cursor"
  exit 0
fi

# Install a real copy (plugins can't hold symlinks, but Xcursor aliases are
# symlinks), refreshed only when the plugin's theme files change.
stamp="$(stat -c '%Y' "$DIR/theme/aliases.txt" "$DIR"/theme/cursors/* | md5sum | cut -c1-12)"
dest="$ICONS/$NAME"
if [[ $(cat "$dest/.stamp" 2>/dev/null) != "$stamp" ]]; then
  mkdir -p "$ICONS"
  rm -rf "${dest:?}"
  cp -r "$DIR/theme" "$dest"
  while read -r alias target; do
    [[ -n $alias && ! -e $dest/cursors/$alias ]] && ln -s "$target" "$dest/cursors/$alias"
  done <"$dest/aliases.txt"
  echo "$stamp" >"$dest/.stamp"
fi

# Session environment for the next login. Omarchy starts Hyprland through
# uwsm, which reads this file before anything launches, so the shell, bar
# and every app start with this cursor instead of picking it up late.
if ! grep -qF "$BEGIN" "$UWSM_ENV" 2>/dev/null; then
  remove_env_block
  mkdir -p "$(dirname "$UWSM_ENV")"
  printf '%s\nexport XCURSOR_THEME=%s\nexport HYPRCURSOR_THEME=%s\n%s\n' \
    "$BEGIN" "$NAME" "$NAME" "$END" >>"$UWSM_ENV"
fi

# This session: apps launched from now on (Omarchy launches them as systemd
# units, so they take the systemd user environment).
systemctl --user set-environment XCURSOR_THEME="$NAME" HYPRCURSOR_THEME="$NAME" 2>/dev/null || true
dbus-update-activation-environment --systemd XCURSOR_THEME="$NAME" HYPRCURSOR_THEME="$NAME" 2>/dev/null || true

# Hyprland's own cursor (hyprcursor) for this session.
hyprctl setcursor "$NAME" "$SIZE" >/dev/null
# GTK apps read the cursor theme from here.
gsettings set org.gnome.desktop.interface cursor-theme "$NAME" 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-size "$SIZE" 2>/dev/null || true
echo "monogray-cursor: applied $NAME at size $SIZE"
