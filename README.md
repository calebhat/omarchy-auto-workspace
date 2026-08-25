# WorkScape

**Monitor and workspace management suite for [Omarchy](https://omarchy.org) + Hyprland.**

WorkScape is the control panel for how this machine should look in each place you sit: which displays are on, which workspace lives on which monitor, which apps open where, how tiling behaves, and what happens when a new window does not fit. Profiles switch from the bar (or at login) when the connected displays — and optionally Wi‑Fi / LAN — match.

It is a fork of [tenzin.auto-workspace](https://github.com/yesheytenzin/auto-workspace), extended into a full workspace automation suite.

Plugin id: `io.github.calebhat.workscape`  
Formerly **WorkBook**. Existing data under `~/.local/state/omarchy/workbook/` is copied on first run.

<p align="center"><img src="preview.png" alt="WorkScape — workspace presets, overflow, and live preview" width="900"></p>

| Workspaces | Displays | Gestures | Profiles |
|---|---|---|---|
| [![Workspaces](docs/screenshots/workspaces.png)](docs/screenshots/workspaces.png) | [![Displays](docs/screenshots/displays.png)](docs/screenshots/displays.png) | [![Gestures](docs/screenshots/gestures.png)](docs/screenshots/gestures.png) | [![Profiles](docs/screenshots/profiles.png)](docs/screenshots/profiles.png) |

`preview.png` is the omarchyplugins.com card and detail image (16:9). Extra shots live in `docs/screenshots/` and in this README.

---

## Marketplace blurb

Use this on [omarchyplugins.com](https://omarchyplugins.com) / the marketplace issue form.

**Short (listing description)**

> Monitor and workspace management suite for Omarchy. Preset windows per workspace, bind workspaces to displays, automate overflow and locks, and switch the whole layout from the bar when you dock, undock, or change networks.

**Longer (about / README excerpt)**

> WorkScape is an Omarchy + Hyprland suite for people who live on more than one monitor layout. Save a **laptop** profile and a **desk** profile: connected displays (EDID, not `DP-1`) pick the match, optional Wi‑Fi SSID / LAN subnet splits two identical laptop-only setups. Each profile presets apps onto workspaces, pins those workspaces to named monitors, and chooses tiling (dwindle, scrolling, master, stage), locked pane sizes, and whether extras stay or move to the next workspace. The **organizer** edits up to 20 panes with horizontal and vertical splits, drag-to-swap, tile vs float, and per-window opacity/borders. **Fill next open workspace** chains unused workspaces as Stage with a global max windows per workspace. Trackpad workspace swipes can follow the profile or stay global. Apply from the bar, a middle-click, or optionally at login. Occupied workspaces are left alone unless you **Fresh set**.

**Suggested listing metadata**

| Field | Value |
|---|---|
| Category | Desktop |
| Tags | Hyprland, Workspaces, Bar |
| Install | `omarchy plugin add https://github.com/calebhat/omarchy-workscape.git --enable` |

---

## Install

```sh
omarchy plugin add https://github.com/calebhat/omarchy-workscape.git --enable
```

The widget defaults to the **right** of the bar:

```sh
omarchy bar move io.github.calebhat.workscape --section right
```

If `tenzin.auto-workspace` is still enabled, disable it so both do not launch apps:

```sh
omarchy plugin disable tenzin.auto-workspace
```

### Dependencies

Stock Omarchy already has these:

- `python3`, `jq`, `hyprctl`, `notify-send`, `flock`, `socat`
- Optional: `nmcli` / `iw` (Wi‑Fi SSID for network matching)

### Remove

```sh
omarchy plugin remove io.github.calebhat.workscape
```

That does **not** delete saved profiles or a Hyprland persist file you opted into:

```sh
rm -rf ~/.local/state/omarchy/workscape ~/.local/state/omarchy/workbook
rm -f ~/.config/hypr/workscape-gestures.lua ~/.config/hypr/workbook-gestures.lua
```

If you added `pcall(require, "hypr.workscape-gestures")` to `hyprland.lua`, delete that line too.

---

## User manual

Open the panel from the workspace chip in the bar (left click). **Middle-click** the chip to apply the matching profile without opening the panel.

The **header profile** is what you are editing — same idea as picking a theme in ThemeBook. Tabs: **Workspaces**, **Displays**, **Gestures**, **Profiles**.

### 1. Profiles — one setup per environment

A profile is a named snapshot: monitors, workspace pins, app presets, layout prefs, optional network bind, optional overflow chain, optional gestures.

**Save current layout as profile** asks for a name, then stores the connected displays. Optionally bind the current network (on by default).

**How a profile is chosen**

1. Connected displays, matched by EDID serial then description — **not** `DP-1` / `DVI-I-1` (those names swap on a dock).
2. If the profile has a bound network, Wi‑Fi SSID or the default-route IPv4 subnet must match (never Tailscale or public IP).
3. If two still match, the network-bound profile wins. Only one layout applies.

**Network**

- **Bind this network / Rebind now** snapshots the live SSID + subnet.
- **Edit network** types SSID/subnet when you are not on that LAN.
- **Clear network** makes that profile the any-network fallback for its display set (only one fallback per display set).
- A display set + network can belong to one profile; binding a network already used on the same displays takes those tokens off the other profile.

SSID names can be spoofed. Treat network matching as home vs office convenience, not a security boundary.

**Apply matching profile at login** is **off** by default. When on, login waits for Hyprland; if this layout has no any-network fallback it also waits up to 45s for Wi‑Fi/LAN, then applies the unique match.

**Apply matching** (or middle-click the bar chip) does the same match any time. **Apply** on a profile card runs that profile as saved, even if it is not the match. Workspaces that already have windows are left alone entirely (no launches, no scrolling/master/stage rules, no geometry). Empty assigned workspaces still get their apps and layouts. **Fresh set** closes windows on this profile’s preset workspaces, then applies from scratch; workspaces that are not part of the profile (for example a terminal on WS 8) stay put.

### 2. Displays — monitors for this profile

- Canvas of the profile’s monitors; drag to arrange; **Apply this profile** writes Hyprland output layout. **Fresh set** closes windows on this profile’s preset workspaces, then applies empty so apps and layouts load from scratch.
- Turn a display **off** for this profile (keep at least one on).
- Match mode: **exact layout** vs **all required present**.
- Capture live arrangement after you rearrange in the compositor.

### 3. Workspaces — presets, tiling, locks, overflow

Pick workspace **1–10** for app presets (overflow chain can use **1–20**).

**Load workspace on** pins that workspace to a named monitor in this profile.

**Toggle apps** in the list to place them on the selected workspace. The name shows a live **×N** count of that app on this workspace; the subtitle says **N on this workspace** when there is more than one. **+** adds another window of the same app (two Braves, two terminals). Toggle off removes one instance (the last). Custom commands go in the bottom row.

**Capture WS** snapshots whatever is open on this workspace into the profile: size/place, terminal working directory (from the shell child of `foot` / Ghostty), and a URL when Hyprland exposes it (Brave *web apps* encode the site in the window class; a normal Brave tab only has the page title — that URL cannot be read). Apps without a `.desktop` file (TUIs) need a desktop entry or WorkScape **extraApps** in config.

**What can be saved per window:** exec, name, class, title, tile vs float, geometry, opacity/borders, lock, **cwd** (terminals), **url** (web apps / explicit `https://` in the command). Not available: the URL of an ordinary browser tab, scroll position, cookies/login, tmux sessions, SSH remote cwd unless it is the local shell.

**Layouts** (per workspace)

| Layout | Behavior |
|---|---|
| Dwindle | Hyprland default split tree |
| Scrolling | Columns; **Visible columns** is how many extra columns fit before you scroll |
| Master | Large pane + stack |
| Stage | First window full width; extras are smaller columns to the right |

**Visible columns** (1–20) is **per workspace**. It is *not* the global overflow max.

**Lock every app / lock a pane** pins sizes so later windows tile around them. **Send extra windows to the next workspace** (on a workspace that has locks or extras=block) moves overflow off this workspace instead of stacking more columns.

**Fill next open workspace** is the **global** chain for this profile:

- Toggle it on; unused workspaces (no pinned apps) are added if the chain is empty.
- **− / N / +** is **max windows per overflow workspace**, separate from each unique Stage workspace’s Visible columns.
- **Choose…** lists workspaces 1–20. Dots mark workspaces that already have pinned apps. **Set Stage** selects unused workspaces and uses Stage on them. **None** clears the list. **Max / workspace** in that dialog is the same global cap.
- Assigned workspaces keep their own send-extra / lock / Visible columns. Overflow only fills the chain (typically empty Stage workspaces).

The extras watcher listens to Hyprland window events (no extra polling). A bounced window focuses the **destination workspace and that window**. After **Apply**, leftover windows on blocked workspaces are swept off so they do not steal lock geometry — except **occupied** workspaces, which Apply never touches.

**Preview and organizer**

- Mini preview (right column): drag **vertical and horizontal** splitters. **×** on a pane removes that window from the workspace; the left list updates live (toggle, **+**, and **×N**). Right-click a pane to lock/unlock its size. **Expand** opens the full organizer.
- **Organizer** (almost the whole panel): up to **20** panes.
  - Drag a **shared edge** to resize both tiled neighbors.
  - Drag a **tiled** pane as a whole: onto another pane’s **center** to **swap** cells; onto an **edge** to **split** that way (left/right/up/down). Dropping off a pane snaps back. Tiled panes stay in the grid (no overlapping).
  - **← → ↑ ↓** split the selected pane with the next tiled app.
  - **Tile / Float** per window. **Float** lifts that pane out of the tiling set; remaining tiled panes **expand to fill the hole** (like Hyprland when you float a window). The float is drawn and applied **above** tiled windows (`alter_zorder top`). Drag a float by the body (clamped to the workspace); drag its edges to resize it alone.
  - **Tile** again **snaps** the window into the tiled cell under it (left/right/top/bottom of the tile you are over), and neighbors shrink — same idea as unfloating in Hyprland.
  - **⚙** sets focused and unfocused **opacity**, border on/off, and border width for that window. Focus changes update chrome without extra polling.
  - **×** removes that window from the workspace.
  - **Reset** clears custom geoms and re-packs from the workspace layout.
- Apply places tiled splits in the compositor; float windows are placed at their organizer boxes and raised above tiles. Workspaces that already have windows are still skipped on Apply.

### 4. Gestures — trackpad workspace swipes

Edits save and apply on change (no Apply button).

- **Global** is the default store and the default view. Every profile uses it until you opt into **This profile**.
- Profile gestures are a separate store; editing one does not overwrite the other.
- **Swipe method** (Natural vs Swap left/right) is one row.
- **Keep swipes after Hyprland reload** is **off** by default. On: writes `~/.config/hypr/workscape-gestures.lua` (explicit consent). Off: session + login apply only.

### 5. Typical day

**Laptop-only (home Wi‑Fi bound)**  
One profile, laptop panel, browser / mail / chat presets, overflow chain for spare Stage workspaces.

**Same laptop at the office (different SSID or subnet)**  
Second profile, same monitors, different network bind and maybe different apps.

**Desk dock**  
Three-display profile, workspaces pinned to named monitors, locked two-pane coding workspace with extras sent away.

Undock → **Apply matching** (or login apply) → laptop profile. Dock → desk profile.

---

## Config and CLI

Config: `~/.local/state/omarchy/workscape/config.json` (outside the plugin tree so saves do not reload the shell).

```sh
workscape.sh --live-status
workscape.sh --apply-matching
workscape.sh --apply-profile desk-dock
workscape.sh --fresh-apply-profile laptop   # close that profile’s preset workspaces, then apply empty
workscape.sh --capture-workspace 2          # snapshot live windows on WS 2 as JSON
omarchy-shell -q io.github.calebhat.workscape applyMatching
omarchy-shell -q io.github.calebhat.workscape applyProfile laptop
omarchy-shell -q io.github.calebhat.workscape status
omarchy-shell -q io.github.calebhat.workscape.panel toggle   # open/close the popout
```

---

## License

MIT. See `NOTICE.md` for upstream attribution.
