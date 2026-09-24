#!/bin/bash
# theme-set hook: carries the active Omarchy theme into the apps Omarchy's own
# theme-set doesn't reach on this machine.
#
#   1. GTK (Nautilus and other GNOME/GTK apps): installs the theme's gtk.css
#      (GTK4/libadwaita) and gtk3.css (GTK3) when it ships them, and removes
#      them again when switching to a theme that doesn't.
#   2. Code - OSS: Omarchy only themes ~/.config/Code, but the Arch `code`
#      package reads "~/.config/Code - OSS" and ~/.vscode-oss, so it never
#      followed the theme. This mirrors Omarchy's generated theme there.
#
# Installed by install.sh as ~/.config/omarchy/hooks/theme-set.d/monogray-extras.sh.

THEME_DIR="$HOME/.local/state/omarchy/current/theme"
MARKER="/* managed by omarchy theme-extras hook — replaced on theme change */"

# --------------------------------------------------------------------- GTK
sync_gtk_css() {
  local src="$1" dest="$2"

  mkdir -p "$(dirname "$dest")"

  # Never clobber a gtk.css the user wrote by hand: keep one backup of it.
  if [[ -f $dest ]] && ! grep -qF "$MARKER" "$dest"; then
    [[ -f $dest.user-backup ]] || cp "$dest" "$dest.user-backup"
  fi

  if [[ -f $src ]]; then
    { echo "$MARKER"; cat "$src"; } >"$dest"
  elif [[ -f $dest ]] && grep -qF "$MARKER" "$dest"; then
    rm -f "$dest"
    [[ -f $dest.user-backup ]] && mv "$dest.user-backup" "$dest"
  fi
}

sync_gtk_css "$THEME_DIR/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
sync_gtk_css "$THEME_DIR/gtk3.css" "$HOME/.config/gtk-3.0/gtk.css"

# ----------------------------------------------------------------- Code - OSS
OSS_SETTINGS="$HOME/.config/Code - OSS/User/settings.json"
OSS_EXT_BASE="$HOME/.vscode-oss/extensions"
GENERATED_THEME="$THEME_DIR/vscode-theme.json"
DESCRIPTOR="$THEME_DIR/vscode.json"
EXT_ID="local.omarchy-theme"
EXT_VERSION="1.0.0"

install_oss_extension() {
  local ext_dir="$OSS_EXT_BASE/omarchy-theme" ui_theme="vs-dark" tmp

  [[ $(jq -r '.type // "dark"' "$GENERATED_THEME") == "light" ]] && ui_theme="vs"

  mkdir -p "$ext_dir/themes"
  ln -sfn "$GENERATED_THEME" "$ext_dir/themes/omarchy-color-theme.json"
  cat >"$ext_dir/package.json" <<EOF
{
    "name": "omarchy-theme",
    "displayName": "Omarchy",
    "description": "Omarchy color theme",
    "publisher": "local",
    "version": "$EXT_VERSION",
    "engines": { "vscode": "^1.70.0" },
    "categories": ["Themes"],
    "contributes": {
        "themes": [{ "label": "Omarchy", "uiTheme": "$ui_theme", "path": "./themes/omarchy-color-theme.json" }]
    }
}
EOF

  [[ -f $OSS_EXT_BASE/extensions.json ]] || printf '[]\n' >"$OSS_EXT_BASE/extensions.json"
  tmp=$(mktemp)
  if jq --arg id "$EXT_ID" --arg version "$EXT_VERSION" --arg p "$ext_dir" \
    'map(select(.identifier.id != $id)) + [{
      identifier: { id: $id }, version: $version,
      location: { "$mid": 1, fsPath: $p, external: ("file://" + $p), path: $p, scheme: "file" },
      relativeLocation: "omarchy-theme"
    }]' "$OSS_EXT_BASE/extensions.json" >"$tmp"; then
    mv "$tmp" "$OSS_EXT_BASE/extensions.json"
  else
    rm -f "$tmp"
  fi
}

set_oss_color_theme() {
  local name="$1" escaped
  [[ $name =~ ^[^[:cntrl:]\"\\]+$ ]] || return 0
  mkdir -p "$(dirname "$OSS_SETTINGS")"
  [[ -f $OSS_SETTINGS ]] || printf '{\n}\n' >"$OSS_SETTINGS"
  if ! grep -q '"workbench.colorTheme"' "$OSS_SETTINGS"; then
    sed -i --follow-symlinks -E '0,/\{/{s/\{/{\n    "workbench.colorTheme": "",/}' "$OSS_SETTINGS"
  fi
  escaped=${name//&/\\&}
  escaped=${escaped//|/\\|}
  sed -i --follow-symlinks -E \
    "s|(\"workbench.colorTheme\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")|\1$escaped\2|" "$OSS_SETTINGS"
}

if command -v code-oss >/dev/null && command -v jq >/dev/null; then
  if [[ -f $DESCRIPTOR ]]; then
    # Theme names a marketplace theme (stock themes do); Code - OSS installs from Open VSX.
    name=$(jq -r '.name // empty' "$DESCRIPTOR")
    ext=$(jq -r '.extension // empty' "$DESCRIPTOR")
    if [[ $ext =~ ^[a-zA-Z0-9._-]+$ ]] && ! code-oss --list-extensions 2>/dev/null | grep -Fxq "$ext"; then
      code-oss --install-extension "$ext" >/dev/null 2>&1
    fi
    set_oss_color_theme "$name"
  elif [[ -f $GENERATED_THEME ]]; then
    install_oss_extension
    set_oss_color_theme "Omarchy"
  fi
fi

exit 0
