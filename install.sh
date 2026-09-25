#!/bin/bash
# Monogray for Omarchy: installer.
#
#   curl -fsSL https://raw.githubusercontent.com/Halftec/Monogray-theme/main/install.sh | bash
#                             download (or update) and install everything
#   ./install.sh              the same, from a clone
#   ... | bash -s -- --no-dock   pass options when piping
#   ./install.sh --no-dock    skip the top-bar dock plugin
#   ./install.sh --no-layout  add the dock but leave the bar layout alone
#   ./install.sh --no-icons   skip the YAMIS monochrome icon set
#   ./install.sh --no-cursor  skip the Monogray cursor set
#   ./install.sh --link       symlink instead of copy (for working on the theme)
#
# Works from any clone, including the one `omarchy theme install` makes. For a
# theme folder that is a git clone, Omarchy drops every .lua file, and
# hyprland.lua is where the blur, window opacity, rounding and glow live. So
# this installs the theme as a plain user theme instead, and moves a clone
# made by `omarchy theme install` to ~/.local/share/monogray-theme first.
set -euo pipefail

REPO_URL="${MONOGRAY_REPO:-https://github.com/Halftec/Monogray-theme.git}"
SHARE_DIR="$HOME/.local/share/monogray-theme"

# One-command install: `curl -fsSL .../install.sh | bash`. Piped in, there's no
# repo next to this script, so fetch it (or update an earlier copy) and run the
# real installer from there with the same options.
self="${BASH_SOURCE[0]:-}"
if [[ -z $self || ! -f $(dirname "$self")/colors.toml ]]; then
  command -v git >/dev/null || { echo "git is required." >&2; exit 1; }
  if [[ -d $SHARE_DIR/.git ]]; then
    printf '\033[1;34m::\033[0m Updating Monogray in %s\n' "$SHARE_DIR"
    git -C "$SHARE_DIR" pull --ff-only --quiet
  else
    printf '\033[1;34m::\033[0m Downloading Monogray to %s\n' "$SHARE_DIR"
    rm -rf "$SHARE_DIR"
    mkdir -p "$(dirname "$SHARE_DIR")"
    git clone --depth 1 --quiet "$REPO_URL" "$SHARE_DIR"
  fi
  exec bash "$SHARE_DIR/install.sh" "$@"
fi

REPO="$(cd "$(dirname "$self")" && pwd)"
THEME_ID="monogray"
# The files that make up the theme itself (the rest of the repo is extras).
THEME_FILES=(colors.toml hyprland.lua shell.toml gtk.css gtk3.css icons.theme preview.png backgrounds)
PLUGIN_ID="monogray.dock"
CURSOR_ID="monogray.cursor"
HOOK_NAME="monogray-extras.sh"
ICON_THEME="yet-another-monochrome-icon-set"
ICON_REPO="https://bitbucket.org/dirn-typo/yet-another-monochrome-icon-set.git"

THEMES_DIR="$HOME/.config/omarchy/themes"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
HOOKS_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
ICONS_DIR="$HOME/.local/share/icons"

with_dock=1 with_layout=1 with_icons=1 with_cursor=1 link=0
for arg in "$@"; do
  case $arg in
    --no-dock) with_dock=0 ;;
    --no-layout) with_layout=0 ;;
    --no-icons) with_icons=0 ;;
    --no-cursor) with_cursor=0 ;;
    --link) link=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done

step() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

command -v omarchy >/dev/null || { echo "This needs Omarchy (https://omarchy.org)." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required: omarchy pkg add jq" >&2; exit 1; }

# Copy (or link) $1 to $2, replacing whatever is there.
place() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -L $dest || -e $dest ]]; then
    [[ $(readlink -f "$dest") == "$(readlink -f "$src")" ]] && return 0
    rm -rf "$dest"
  fi
  if (( link )); then
    ln -s "$src" "$dest"
  else
    cp -r "$src" "$dest"
  fi
}

# ------------------------------------------------------------------ theme
# Running from the clone `omarchy theme install` made: move it out of the
# themes folder (keeping it as a git clone, so it can still be updated) and
# install from the new location.
if [[ $REPO == "$(readlink -f "$THEMES_DIR/$THEME_ID" 2>/dev/null)" && ! -L $THEMES_DIR/$THEME_ID && -d $REPO/.git ]]; then
  step "Moving the downloaded theme to $SHARE_DIR"
  rm -rf "$SHARE_DIR"
  mkdir -p "$(dirname "$SHARE_DIR")"
  mv "$REPO" "$SHARE_DIR"
  REPO="$SHARE_DIR"
  cd "$REPO"
fi

step "Installing theme to $THEMES_DIR/$THEME_ID"
dest="$THEMES_DIR/$THEME_ID"
if (( link )); then
  # A symlinked theme counts as the user's own, so its hyprland.lua is kept.
  place "$REPO" "$dest"
else
  rm -rf "$dest"
  mkdir -p "$dest"
  for f in "${THEME_FILES[@]}"; do
    cp -r "$REPO/$f" "$dest/"
  done
fi

# ------------------------------------------------------------------ icons
if (( with_icons )); then
  if [[ -d $ICONS_DIR/$ICON_THEME ]]; then
    step "Icon set already installed"
  elif pacman -Qq yamis-icon-theme-git &>/dev/null || [[ -d /usr/share/icons/$ICON_THEME ]]; then
    step "Icon set already installed (system package)"
  else
    step "Downloading Yet Another Monochrome Icon Set to $ICONS_DIR"
    mkdir -p "$ICONS_DIR"
    if ! git clone --depth 1 --quiet "$ICON_REPO" "$ICONS_DIR/$ICON_THEME"; then
      warn "Couldn't download the icon set. Falling back to Yaru-blue icons."
      with_icons=0
    fi
  fi
fi
if (( ! with_icons )) && [[ ! -d $ICONS_DIR/$ICON_THEME && ! -d /usr/share/icons/$ICON_THEME ]]; then
  # Without YAMIS the theme would name a missing icon theme; use a stock one.
  if [[ -L $THEMES_DIR/$THEME_ID ]]; then
    warn "Linked install: leaving icons.theme alone (it names $ICON_THEME)."
  else
    echo "Yaru-blue" >"$THEMES_DIR/$THEME_ID/icons.theme"
  fi
fi

# ------------------------------------------------------------------- hook
step "Installing theme-set hook (GTK styling, Code - OSS theme)"
place "$REPO/hooks/theme-extras.sh" "$HOOKS_DIR/$HOOK_NAME"
chmod +x "$REPO/hooks/theme-extras.sh" "$HOOKS_DIR/$HOOK_NAME" 2>/dev/null || true

# ------------------------------------------------------------------- dock
if (( with_dock )); then
  step "Installing the Monogray Dock bar widget"
  place "$REPO/dock" "$PLUGINS_DIR/$PLUGIN_ID"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable "$PLUGIN_ID" --section center >/dev/null

  # Starter pins, written into shell.json so they're easy to find and edit.
  # An existing "pinned" list (from an earlier install) is left alone.
  if [[ -f $SHELL_JSON ]]; then
    pins=$(jq -c '.barWidget.defaults.pinned' "$REPO/dock/manifest.json")
    tmp=$(mktemp)
    jq --arg id "$PLUGIN_ID" --argjson pins "$pins" '
      .bar.layout |= with_entries(.value |= map(
        if .id == $id and (has("pinned") | not) then . + { pinned: $pins } else . end))
    ' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
  fi

  if (( with_layout )) && [[ -f $SHELL_JSON ]]; then
    step "Centering the dock in the bar and moving the clock to the right"
    cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
    tmp=$(mktemp)
    jq --arg dock "$PLUGIN_ID" '
      .bar.centerAnchor = $dock
      | (.bar.layout.center // []) as $c
      | ([($c + (.bar.layout.left // []) + (.bar.layout.right // []))[] | select(.id == "omarchy.clock")] | first) as $clock
      | .bar.layout.center = ([$c[] | select(.id != "omarchy.clock")])
      | if $clock then
          .bar.layout.right = ([(.bar.layout.right // [])[] | select(.id != "omarchy.clock")] + [$clock])
          | .bar.layout.left = [(.bar.layout.left // [])[] | select(.id != "omarchy.clock")]
        else . end
    ' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
  fi
fi

# ----------------------------------------------------------------- cursor
if (( with_cursor )); then
  step "Installing the Monogray cursor set"
  place "$REPO/cursor" "$PLUGINS_DIR/$CURSOR_ID"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable "$CURSOR_ID" >/dev/null
fi

# ------------------------------------------------------------------ apply
step "Applying the theme"
omarchy theme set "$THEME_ID"
# The shell draws the bar and desktop; restart it so it picks up the new cursor.
(( with_cursor )) && omarchy restart shell >/dev/null 2>&1 || true

cat <<EOF

Monogray is installed.
  Theme:  $THEMES_DIR/$THEME_ID
  Dock:   right-click any app in the dock and choose "Pin to dock"
  Undo:   $REPO/uninstall.sh

Apps that are already open pick up the new GTK styling and cursor when relaunched.
EOF
