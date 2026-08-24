# Auto Workspace

Omarchy + Hyprland plugin: assign apps to workspaces, pin those workspaces to
monitors, and switch the whole setup with a hotkey based on the displays that
are actually connected.

Fork of [tenzin.auto-workspace](https://github.com/yesheytenzin/auto-workspace)
with monitor-layout profiles. Not listed on the Omarchy plugin marketplace.

Plugin id: `io.github.calebhat.auto-workspace`

## Install

```sh
omarchy plugin add https://github.com/calebhat/omarchy-auto-workspace.git --enable
omarchy bar move io.github.calebhat.auto-workspace --section right
```

If you already had `tenzin.auto-workspace`, disable it so both do not launch:

```sh
omarchy plugin disable tenzin.auto-workspace
```

## Usage

1. Click the workspace icon in the bar → **Auto Workspace**.
2. **Profiles** tab: **Save current monitors as profile** while docked, then
   again on laptop-only. Matching uses EDID serial, then description — not
   `DP-1` / `DVI-I-1` (those names swap on a dock).
3. **Apps** tab: pick a profile, pick workspace 1–10, set **Load workspace on**
   to a named monitor, then toggle apps. ShopHawk Herdr is injected even
   though it is not a `.desktop` file. Custom commands go in the row at the
   bottom. Drag the splitter between windows to resize both sides (they stay
   tiled and cannot overlap). Apply keeps windows in the Hyprland tile
   layout so later resize still moves the shared split. **Reset** restores
   the default split.
4. **Apply matching** (or **SUPER+ALT+W**, or middle-click the bar chip)
   snapshots the connected monitors and loads the matching profile: bind
   workspaces to monitors, then launch that profile’s apps.
5. **Apply matching profile at login** is off by default.

Desk example: workspace 1 on the left external, 2–5 on the right external,
workspace 9 on the laptop. A separate laptop profile has a different app set.

## Config

`~/.local/state/omarchy/auto-workspace/config.json` (outside the plugin tree so
saves do not reload the shell plugin).

## CLI

```sh
auto-workspace.sh --live-status
auto-workspace.sh --apply-matching
auto-workspace.sh --apply-profile desk-dock
omarchy-shell -q io.github.calebhat.auto-workspace applyMatching
```

## License

MIT. See `NOTICE.md` for upstream attribution.
