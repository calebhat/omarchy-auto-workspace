# WorkScape

**Monitor and workspace management suite for [Omarchy](https://omarchy.org) + Hyprland.**

WorkScape is the control panel for how this machine should look in each place you sit: which displays are on, which workspace lives on which monitor, which apps open where, how tiling behaves, and what happens when a new window does not fit. Profiles switch from the bar (or at login) when the connected displays — and optionally Wi‑Fi / LAN — match.

It is a fork of [tenzin.auto-workspace](https://github.com/yesheytenzin/auto-workspace), extended into a full workspace automation suite.

Plugin id: `io.github.calebhat.workscape`  
Formerly **WorkBook**. Existing data under `~/.local/state/omarchy/workbook/` is copied on first run.

---

## Marketplace blurb

Use this on [omarchyplugins.com](https://omarchyplugins.com) / the marketplace issue form.

**Short (listing description)**

> Monitor and workspace management suite for Omarchy. Preset windows per workspace, bind workspaces to displays, automate overflow and locks, and switch the whole layout from the bar when you dock, undock, or change networks.

**Longer (about / README excerpt)**

> WorkScape is an Omarchy + Hyprland suite for people who live on more than one monitor layout. Save a **laptop** profile and a **desk** profile: connected displays (EDID, not `DP-1`) pick the match, optional Wi‑Fi SSID / LAN subnet splits two identical laptop-only setups. Each profile presets apps onto workspaces, pins those workspaces to named monitors, and chooses tiling (dwindle, scrolling, master, stage), locked pane sizes, and whether extras stay or move to the next workspace. **Fill next open workspace** chains unused workspaces as Stage with a global max windows per workspace. Trackpad workspace swipes can follow the profile or stay global. Apply from the bar, a middle-click, or optionally at login.

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

**Apply matching** (or middle-click the bar chip) does the same match any time. **Apply** on a profile card runs that profile as saved, even if it is not the match.

### 2. Displays — monitors for this profile

- Canvas of the profile’s monitors; drag to arrange; **Apply this profile** writes Hyprland output layout.
- Turn a display **off** for this profile (keep at least one on).
- Match mode: **exact layout** vs **all required present**.
- Capture live arrangement after you rearrange in the compositor.

### 3. Workspaces — presets, tiling, locks, overflow

Pick workspace **1–10** for app presets (overflow chain can use **1–20**).

**Load workspace on** pins that workspace to a named monitor in this profile.

**Toggle apps** in the list to place them on the selected workspace. Custom commands go in the bottom row. Apps without a `.desktop` file (TUIs) need a desktop entry or WorkScape **extraApps** in config.

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

The extras watcher listens to Hyprland window events (no extra polling). A bounced window focuses the **destination workspace and that window**. After **Apply**, leftover windows on blocked workspaces are swept off so they do not steal lock geometry.

**Preview** on the right: drag splitters between preset panes. Apply keeps them tiled.

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
omarchy-shell -q io.github.calebhat.workscape applyMatching
omarchy-shell -q io.github.calebhat.workscape applyProfile laptop
omarchy-shell -q io.github.calebhat.workscape status
omarchy-shell -q io.github.calebhat.workscape toggle
```

---

## License

MIT. See `NOTICE.md` for upstream attribution.
