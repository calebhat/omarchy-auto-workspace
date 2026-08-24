# SceneBook

Omarchy + Hyprland plugin: assign apps to workspaces, pin those workspaces to
monitors, and switch the whole setup with a hotkey based on the displays that
are actually connected.

Fork of [tenzin.auto-workspace](https://github.com/yesheytenzin/auto-workspace)
with monitor-layout profiles. Not listed on the Omarchy plugin marketplace.

Plugin id: `io.github.calebhat.scenebook`

## Install

```sh
omarchy plugin add https://github.com/calebhat/omarchy-scenebook.git --enable
omarchy bar move io.github.calebhat.scenebook --section right
```

If you already had `tenzin.auto-workspace`, disable it so both do not launch:

```sh
omarchy plugin disable tenzin.auto-workspace
```

## Usage

1. Click the workspace icon in the bar → **SceneBook**. The header profile
   selector is the object you are editing (like a theme in ThemeBook).
2. **Profiles**: **Save current monitors as profile** while docked, then
   again on laptop-only. Matching uses EDID serial, then description — not
   `DP-1` / `DVI-I-1` (those names swap on a dock).
3. **Workspaces**: pick workspace 1–10, set **Load workspace on** to a named
   monitor, then toggle apps. ShopHawk Herdr is injected even though it is
   not a `.desktop` file. Custom commands go in the row at the bottom. Drag
   the splitter between windows to resize both sides (they stay tiled and
   cannot overlap). Lock an app (🔒) or **Lock all assigned sizes** so a new
   window cannot move or resize those panes — extras either scroll around
   them or get sent to another workspace. Apply keeps windows in the
   Hyprland tile layout so later resize still moves the shared split.
   **Reset** restores the default split. Layouts: Dwindle (Hyprland split
   tree), Scrolling (equal columns), Master (Hyprland large pane + stack),
   Stage (first window full width; extras are smaller columns you scroll to).
4. **Displays**: arrange monitors on the canvas (edges snap), turn a display
   off for this profile (laptop panel on the dock setup), and set match mode.
   At least one display must stay on.
5. **Apply matching** (or **SUPER+ALT+W**, or middle-click the bar chip)
   snapshots the connected monitors and loads the matching profile.
   **Apply this profile** on Displays runs the header profile as saved.
6. **Apply matching profile at login** (Profiles tab) is off by default.

Desk example: workspace 1 on the left external, 2–5 on the right external,
workspace 9 on the laptop. A separate laptop profile has a different app set.

## Config

`~/.local/state/omarchy/scenebook/config.json` (outside the plugin tree so
saves do not reload the shell plugin).

## CLI

```sh
scenebook.sh --live-status
scenebook.sh --apply-matching
scenebook.sh --apply-profile desk-dock
omarchy-shell -q io.github.calebhat.scenebook applyMatching
```

## License

MIT. See `NOTICE.md` for upstream attribution.
