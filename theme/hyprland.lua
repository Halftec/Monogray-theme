-- Monogray: blue gradient borders with a soft gray glow, rounded glassy windows (mirrors the KDE Better Blur look)
local active_border_color = { colors = { "rgba(6a97ffee)", "rgba(9aa0d0ee)" }, angle = 45 }
local inactive_border_color = "rgba(ffffff1a)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    rounding = 10,

    shadow = {
      enabled = true,
      range = 12,
      render_power = 3,
      color = "rgba(b4b4be55)",
      color_inactive = "rgba(00000066)",
    },

    blur = {
      enabled = true,
      size = 8,
      passes = 3,
      vibrancy = 0.2,
      new_optimizations = true,
      ignore_opacity = true,
    },
  },
})

-- Glass windows: 85% when focused, 75% when not, blurred behind (see blur above).
-- Loaded after Omarchy's windows.lua, so these win over its 0.985/0.96 default.
-- Video, games, VMs and PiP stay opaque: Omarchy strips the default-opacity
-- tag from those, and they carry no browser tag either.
local glass = { opacity = "0.85 0.75" }
o.window({ tag = "default-opacity" }, glass)
o.window({ tag = "chromium-based-browser" }, glass)
o.window({ tag = "firefox-based-browser" }, glass)
