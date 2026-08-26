# WorkScape test matrix

Rerun this instead of improvising against the user’s Desk dock profile.

Two layers:

| Layer | Command | Touches user config? | Touches live windows? |
|---|---|---|---|
| Unit | `test/run` | no | no |
| Dummy live | `python3 test/dummy_live.py --live` | **no** | real dock monitors, WS **11–19** only (`workscape-dummy-*`). This is the Hyprland test; `test/run` is unit-only. First run 2026-08-25: **S12 failed** (locked split → 1/3 columns; pane floated after close). Record: `test/records/dummy-20260825-154215.json`. |

The dummy profile is `test/fixtures/dummy-profile.json`. It is **not** copied into `~/.local/state/omarchy/workscape/config.json`. Geom/watch read it via `WORKSCAPE_CONFIG` (unit) or an in-memory remapped copy (live). Live maps dummy workspace `N` → `N+10`.

Desk-dock WS1–4 / Fresh Workscape is **not** part of the default run. Use it only when the user asks to verify their real profile.

Before changing extras, restore, layoutmsg, or Fresh Workscape, read `test/ISSUES.md`.

## Isolation rules

- Do not write user `config.json`. Dummy live asserts mtime/size unchanged.
- Do not `omarchy restart shell` for dummy live (watch is `SIGSTOP`’d instead).
- Do not spawn on WS1–5, 9, 10. Dummy live is 11–19; unassigned probe is 20.
- Close only `workscape-dummy-*` / titles `dummy-*`.
- Restore the previously focused window at the end.
- If user config ever contains `dummy-matrix`, abort.

## How to rerun

```bash
cd ~/Work/omarchy-workscape
test/run                          # unit + dummy fixture + dummy_live self-check
python3 test/dummy_live.py        # self-check only
python3 test/dummy_live.py --live
python3 test/dummy_live.py --live --scenario S12
```

Live records: `test/records/dummy-YYYYMMDD-HHMMSS.json` (gitignored). Each step stores layout, focus, and every window’s `x,y,w,h`, `fracW`, `floating`.

## Ready-before-step (gate)

Do not take an action until the previous record passes:

1. Expected windows are mapped (`floating` as required).
2. They sit on the dummy workspace (11–19), not the user’s 1–5.
3. `fracW` for locked panes is within the scenario band (below).
4. Focus is on that dummy workspace (or the extra just spawned).
5. User config stamp is unchanged.

If the gate fails, **stop**. Record the step as `FAIL` and clean up dummy windows. Do not “keep clicking extras” on a broken baseline (that is how I-021/I-024 get misdiagnosed).

## Dummy slots

| Dummy WS (file) | Live WS | Layout | vis | extras | Locks | Mirrors |
|---|---|---|---|---|---|---|
| 1 | 11 | stage | 2 | around | 1 × full | Desk WS1 Brave |
| 2 | 12 | scrolling (dwindle until extras) | 3 | around | 2 × 0.6456 / 0.3544 | Desk WS2 Herdr\|Control |
| 3 | 13 | scrolling | 4 | around | 1 × full | Desk WS3 Grok Bot |
| 4 | 14 | stage | 2 | around | 1 × full | Desk WS4 Outlook |
| 5 | 15 | set-width | 3 | around | 0 | Set width + scroll extras |
| 6 | 16 | set-width | 4 | block | 0 | Visible cap then bounce |
| 7 | 17 | master | 2 | around | 0 | Master stack |
| 8 | 18 | dwindle | 2 | around | 2 × 0.5 (lockSizes) | 50/50 dwindle |
| 9 | 19 | stage | 1 | around | 0 | Overflow destination |
| — | 20 | *unassigned* | — | — | — | Must not move (like WS5) |

Expected fractions are of **monitor logical width** (`width/scale`), ±0.06 unless noted.

## Scenarios

### S00 — Dummy fixture + isolation

- **Action:** `python3 test/dummy_live.py` and `python3 test/dummy.test.py`
- **Expect:** fixture `applyOnBoot=false`; live map 11–18 + overflow 19; `WORKSCAPE_CONFIG` override; user profiles do not include `dummy-matrix`.
- **Unit:** `test_fixture_is_not_user_config`, `test_config_path_honors_env`, `test_live_offset_does_not_collide_with_desk_dock`

### S11 — Stage extra around a full pane (live 11)

- **Gate:** `dummy-stage` tiled, `fracW` ≥ 0.90, layout scrolling.
- **Action:** spawn one extra; record; close extra; record.
- **Expect after extra:** locked `fracW` ≥ 0.85; extra `fracW` ≈ 0.50; extra to the **right** of locked; focus not stolen to WS5.
- **Expect after close:** locked `fracW` ≥ 0.90 again (stage fill).
- **Issues:** I-016 (closed), I-017 (closed), I-022 (open — extra must not be ~1.0).
- **Unit:** `test_dummy_stage_append_is_skipped`, watch 1-lock open does not restore.

### S12 — Two locked panes + extras (live 12)  **highest churn**

- **Gate:** `dummy-left` ≈ 0.65, `dummy-right` ≈ 0.35, both **tiled**, layout **dwindle**.
- **Action 1:** one extra. Record. Extra `fracW` ≈ 0.33; extra x > both locked x; locked fractions **unchanged**.
- **Action 2:** two more extras quickly. Record. Same locked fractions; no `restore` focus fight.
- **Action 3:** close all extras. Record. Layout dwindle; both locked tiled; fractions back to 0.65/0.35.
- **Issues:** I-018, I-019, I-020 closed; I-021, I-024, I-025 open.
- **Unit:** `test_dummy_append_extra_uses_locked_geoms`, `test_append_extra_preserves_locked_column_sizes`, `test_push_column_after_locked`, `test_two_locked_no_extras_uses_dwindle`, quiet/skipRestore watch tests.

### S13 — Scrolling 1-lock vis=4 (live 13)

- **Gate:** `dummy-scroll` `fracW` ≥ 0.90.
- **Action:** extra. Extra `fracW` ≈ 0.25; locked stays ≥ 0.85.
- **Close:** locked full again.
- **Issues:** I-007.

### S14 — Stage vis=2 second copy (live 14)

- Same expectations as S11 (Outlook-shaped). Catches “WS1 extra full-width but WS4 extra 1/2” (I-022).

### S15 — Set-width vis=3 extras around (live 15)

- **Gate:** first column ≈ 0.33 (not 1.0).
- **Action:** extra. Both columns ≈ 0.33.
- **Issues:** I-007, set-width fill_one false.

### S16 — Set-width vis=4 extras=block (live 16)

- **Action:** spawn 5 extras; `sweep_block_extras` with dummy `WORKSCAPE_CONFIG`.
- **Expect:** ≤ 4 windows remain on 16; overflow on 19.
- **Unit:** `test_dummy_watch_maps_via_env` (`blocked["6"]==4`).

### S17 — Master (live 17)

- **Gate:** `dummy-master` tiled.
- **Action:** extra. Extra joins the master stack (not a scrolling tape). Unassigned WS20 unchanged.

### S18 — Dwindle lockSizes 50/50 (live 18)

- **Gate:** two locked panes ≈ 0.50 each, dwindle.
- **Action:** extra after locked; locked stay ≈ 0.50; extra 1/2 (vis=2).
- **Close:** back to 50/50 tiled dwindle.

### S19 — Overflow dest (live 19)

- Filled only by S16 bounce. Must not layoutmsg the user’s WS5.

### S20 — Unassigned probe (live 20)

- **Gate:** `dummy-probe` mapped, record x/w.
- **Action:** run restore/append on live 12.
- **Expect:** probe x/w unchanged (±24px).
- **Issues:** I-014.
- **Unit:** `test_managed_workspaces`.

### S21 — Rapid extras (no restore log)

- On live 12, three extras in <1s. Journal (if watch not stopped) must show `extraWidth` / `skipRestore`, **not** `restore`. Dummy live pauses watch and drives geom itself — unit tests cover the watch JSON.

### S22 — Close last extra vs remaining extras

- Two extras on live 12. Close one: locked sizes stay; no dwindle restore. Close last: dwindle restore, both tiled.
- **Unit:** `test_quiet_end_skips_restore_while_extras_remain`, `test_quiet_end_restores_when_extras_gone`.

## Record schema

Each step in `test/records/*.json`:

```json
{
  "step": "S12-after-extra",
  "ws": "12",
  "layout": "scrolling",
  "monitor": "DVI-I-2",
  "focusClass": "workscape-dummy-extra",
  "focusWs": "12",
  "windows": [
    {"title": "dummy-left", "floating": false, "x": 3370, "w": 1229, "fracW": 0.6401, "xOnMon": 10}
  ]
}
```

Compare `fracW` and `floating` across steps, not raw `x` (monitor origin changes).

## Unit suite (always)

| File | What |
|---|---|
| `dummy.test.py` | Dummy fixture, env override, lock plans, append_extra geoms, stage skip |
| `geom.test.py` | Metrics, colresize, dwindle vs scrolling, clamp, restore, managed WS |
| `watch.test.py` | extra open/close, quiet restore, burst, block/overflow, I-033/I-034 |
| `match.test.sh` | Profile match, bindings, layout rules, occupied, mismatch Apply refuse |
| `reuse.test.sh` | Browser on-target only; unique apps move |
| `occupied.test.sh` | Occupied id glob |
| `model.test.js` | Config sanitize, layouts, organizer |
| `gestures.test.py` / `network.test.py` | Gestures persist; network match |
| `workscape_layout.test.py` | SUPER+J dwindle-only; thin-strip warp floor |
| `hyprsafe.test.py` | Lua interpolation allowlist |
| `geom.test.py` | Metrics, colresize, force_tiled off, covering floats, managed WS |

## Optional: user Desk dock (only if asked)

Do **not** auto-run Fresh Workscape. If the user clicks it:

| WS | After Fresh (idle 1s) | Extra open | Extra close |
|---|---|---|---|
| 1 DVI-I-1 stage | Brave ~1900 tiled | extra ~1/2, Brave stays full | Brave full, no focus jump |
| 2 DVI-I-2 2-lock | Herdr ~1229 \| Control ~659 tiled dwindle | extras after both, locked stay ~1229/659 | dwindle 1229/659, both tiled |
| 3 DVI-I-2 scroll | Grok ~1900 | extra ~1/4 | Grok full |
| 4 DVI-I-2 stage | Outlook ~1900 | extra ~1/2; click Inbox pans it on-screen | Outlook full |
| 5 eDP-1 | untouched (Grok CLI ~1420) | n/a | n/a |
| 9, 10 | untouched | n/a | n/a |

Logs: `journalctl --user --since '2 min ago' | grep '\[workscape\]'`
Look for `extraWidth` / `skipRestore`, never a delayed `restore ws=2` while extras exist.

## Adding a regression

1. Reproduce once; put it in `ISSUES.md` (`open` or `closed`).
2. Prefer a **unit** test named after the issue (`test_append_extra_preserves_locked_column_sizes` for I-021).
3. If it needs Hyprland, add a dummy live scenario on 11–19, not the user profile.
4. Link the test name in the issue entry.
