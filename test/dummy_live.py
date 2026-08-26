#!/usr/bin/env python3
"""Isolated dummy-profile live harness.

Never writes ~/.local/state/omarchy/workscape/config.json.
Spawns foot windows with app-id workscape-dummy-* on workspaces 11–19
without focusing them, drives the shipped extras path (watch.handle_open),
records window geometry at each step, then restores focus.

  python3 test/dummy_live.py              # self-check only (no Hyprland spawn)
  python3 test/dummy_live.py --live       # run dummy matrix on WS 11–19
  python3 test/dummy_live.py --live --scenario S12
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "test/fixtures/dummy-profile.json"
USER_CONFIG = Path.home() / ".local/state/omarchy/workscape/config.json"
RECORDS = ROOT / "test/records"
APP_PREFIX = "workscape-dummy"

geom = SourceFileLoader("dummy_live_geom", str(ROOT / "scripts/geom")).load_module()
watch = SourceFileLoader("dummy_live_watch", str(ROOT / "scripts/watch")).load_module()


def load_dummy() -> dict:
    return json.loads(FIXTURE.read_text())


def user_config_stamp() -> tuple[int, int] | None:
    if not USER_CONFIG.exists():
        return None
    st = USER_CONFIG.stat()
    return (st.st_mtime_ns, st.st_size)


def assert_user_config_untouched(before: tuple[int, int] | None) -> None:
    after = user_config_stamp()
    if before != after:
        raise SystemExit(f"user config changed during dummy run: {before} -> {after}")
    if USER_CONFIG.exists():
        cfg = json.loads(USER_CONFIG.read_text())
        ids = {p.get("id") for p in (cfg.get("profiles") or [])}
        if "dummy-matrix" in ids:
            raise SystemExit("dummy-matrix leaked into user config")


def remap_to_live(dummy: dict) -> dict:
    offset = int(dummy["_test"]["liveWorkspaceOffset"])
    cfg = json.loads(json.dumps(dummy))
    profile = cfg["profiles"][0]
    prefs = {}
    for key, pref in (profile.get("workspacePrefs") or {}).items():
        prefs[str(int(key) + offset)] = pref
    profile["workspacePrefs"] = prefs
    for a in profile.get("assignments") or []:
        a["workspace"] = int(a["workspace"]) + offset
    ov = profile.get("overflow") if isinstance(profile.get("overflow"), dict) else {}
    if ov.get("workspaces"):
        ov["workspaces"] = [int(n) + offset for n in ov["workspaces"]]
    return cfg


def hypr_j(cmd: str):
    return json.loads(subprocess.check_output(["hyprctl", "-j", cmd], text=True))


def hypr_eval(lua: str) -> None:
    subprocess.run(
        ["hyprctl", "eval", lua],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=3,
    )


def watch_pids() -> list[int]:
    try:
        out = subprocess.check_output(["pgrep", "-f", "plugins/.*/scripts/watch"], text=True)
    except subprocess.CalledProcessError:
        return []
    pids = []
    for line in out.split():
        try:
            pids.append(int(line))
        except ValueError:
            continue
    return pids


def pause_watch() -> list[int]:
    pids = watch_pids()
    for pid in pids:
        os.kill(pid, signal.SIGSTOP)
    return pids


def resume_watch(pids: list[int]) -> None:
    for pid in pids:
        try:
            os.kill(pid, signal.SIGCONT)
        except ProcessLookupError:
            pass


def snapshot_focus() -> dict:
    aw = hypr_j("activewindow") or {}
    aws = hypr_j("activeworkspace") or {}
    return {"addr": str(aw.get("address") or ""), "ws": str(aws.get("id") or "")}


def restore_focus(snap: dict) -> None:
    if snap.get("ws"):
        hypr_eval(f'hl.dispatch(hl.dsp.focus({{ workspace = "{snap["ws"]}" }}))')
    if snap.get("addr"):
        hypr_eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{snap["addr"]}" }}))')


def record_step(name: str, ws: str | None = None) -> dict:
    spaces = hypr_j("workspaces")
    mons = hypr_j("monitors")
    clients = hypr_j("clients")
    aw = hypr_j("activewindow") or {}
    layout = None
    mon_name = None
    if ws:
        hit = next((w for w in spaces if str(w.get("id")) == str(ws)), None)
        if hit:
            layout = hit.get("tiledLayout")
            mon_name = hit.get("monitor")
    mon = next((m for m in mons if m.get("name") == mon_name), None)
    windows = []
    for c in clients:
        cid = str((c.get("workspace") or {}).get("id") or "")
        if ws and cid != str(ws):
            continue
        if ws is None and APP_PREFIX not in str(c.get("class") or ""):
            continue
        at = c.get("at") or [0, 0]
        size = c.get("size") or [0, 0]
        mx = float((mon or {}).get("x") or 0)
        mw = float((mon or {}).get("width") or 0) / (float((mon or {}).get("scale") or 1) or 1)
        windows.append({
            "addr": c.get("address"),
            "class": c.get("class"),
            "title": c.get("title"),
            "floating": bool(c.get("floating")),
            "x": int(at[0] or 0),
            "y": int(at[1] or 0),
            "w": int(size[0] or 0),
            "h": int(size[1] or 0),
            "fracW": round((int(size[0] or 0) / mw), 4) if mw else None,
            "xOnMon": int(at[0] or 0) - int(mx),
        })
    windows.sort(key=lambda w: w["x"])
    rec = {
        "step": name,
        "ws": ws,
        "layout": layout,
        "monitor": mon_name,
        "focusClass": aw.get("class"),
        "focusWs": str(((aw.get("workspace") or {}).get("id") or "")),
        "windows": windows,
    }
    return rec


def write_records(rows: list[dict], dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(rows, indent=2) + "\n")


def close_dummy_windows() -> None:
    for c in hypr_j("clients"):
        cls = str(c.get("class") or "")
        title = str(c.get("title") or "")
        if APP_PREFIX in cls or title.startswith("dummy-"):
            addr = c.get("address")
            if addr:
                hypr_eval(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{addr}" }}))')
    time.sleep(0.2)


def desk_monitor_name() -> str:
    spaces = hypr_j("workspaces")
    ws2 = next((w for w in spaces if w.get("id") == 2), None)
    if ws2 and ws2.get("monitor"):
        return str(ws2["monitor"])
    for m in hypr_j("monitors"):
        name = str(m.get("name") or "")
        if name and not name.startswith("eDP"):
            return name
    mons = hypr_j("monitors")
    return str((mons[0] or {}).get("name") or "")


def snapshot_monitors() -> list[dict]:
    out = []
    for m in hypr_j("monitors"):
        out.append({
            "name": str(m.get("name") or ""),
            "ws": str(((m.get("activeWorkspace") or {}).get("id") or "")),
        })
    return out


def restore_monitors(saved: list[dict]) -> None:
    for m in saved:
        name, ws = m.get("name") or "", m.get("ws") or ""
        if not name or not ws:
            continue
        hypr_eval(f'hl.dispatch(hl.dsp.focus({{ monitor = "{name}" }}))')
        hypr_eval(f'hl.dispatch(hl.dsp.workspace.move({{ workspace = "{ws}", monitor = "{name}" }}))')
        hypr_eval(f'hl.dispatch(hl.dsp.focus({{ workspace = "{ws}" }}))')


def pin_workspace(ws: str, mon: str) -> None:
    if not ws or not mon:
        return
    geom.pin_workspace_silent(ws, mon)
    time.sleep(0.05)


def spawn_named(ws: str, app_id: str, title: str, mon: str = "") -> str:
    before = {str(c.get("address") or "") for c in hypr_j("clients")}
    if mon:
        pin_workspace(ws, mon)
    cmd = f"foot --app-id={app_id} -T {title}"
    geom.exec_silent(cmd, ws, monitor=mon)
    for _ in range(40):
        time.sleep(0.08)
        for c in hypr_j("clients"):
            addr = str(c.get("address") or "")
            if addr in before:
                continue
            blob = f"{c.get('class','')} {c.get('initialClass','')} {c.get('title','')} {c.get('initialTitle','')}"
            if app_id in blob or title in blob:
                return addr
    return ""


def wait_named(ws: str, title: str, timeout: float = 3.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for c in hypr_j("clients"):
            if str((c.get("workspace") or {}).get("id")) != str(ws):
                continue
            if title in str(c.get("title") or "") or title in str(c.get("class") or ""):
                return True
        time.sleep(0.08)
    return False


def frac_w(rec: dict, title: str) -> float | None:
    for w in rec.get("windows") or []:
        if title in str(w.get("title") or "") or title in str(w.get("class") or ""):
            return w.get("fracW")
    return None


def floating(rec: dict, title: str) -> bool | None:
    for w in rec.get("windows") or []:
        if title in str(w.get("title") or "") or title in str(w.get("class") or ""):
            return w.get("floating")
    return None


def self_check() -> int:
    dummy = load_dummy()
    assert dummy["settings"]["activeProfileId"] == "dummy-matrix"
    assert dummy["settings"]["applyOnBoot"] is False
    live = remap_to_live(dummy)
    ws = {str(a["workspace"]) for a in live["profiles"][0]["assignments"]}
    assert ws == {"11", "12", "13", "14", "15", "16", "17", "18"}
    assert live["profiles"][0]["overflow"]["workspaces"] == [19]
    orig = os.environ.get("WORKSCAPE_CONFIG")
    os.environ["WORKSCAPE_CONFIG"] = str(FIXTURE)
    try:
        assert geom.config_path() == str(FIXTURE)
    finally:
        if orig is None:
            os.environ.pop("WORKSCAPE_CONFIG", None)
        else:
            os.environ["WORKSCAPE_CONFIG"] = orig
    stamp = user_config_stamp()
    assert_user_config_untouched(stamp)
    print("dummy_live self-check ok")
    print("  fixture", FIXTURE)
    print("  live workspaces", sorted(ws | {"19"}))
    print("  user config untouched")
    return 0


def run_live(scenarios: set[str] | None) -> int:
    dummy = load_dummy()
    cfg = remap_to_live(dummy)
    fd, tmp_name = tempfile.mkstemp(prefix="workscape-dummy-", suffix=".json")
    os.close(fd)
    tmp_cfg = Path(tmp_name)
    tmp_cfg.write_text(json.dumps(cfg))
    orig_cfg = os.environ.get("WORKSCAPE_CONFIG")
    os.environ["WORKSCAPE_CONFIG"] = str(tmp_cfg)
    geom.cache_clear()
    stamp = user_config_stamp()
    snap = snapshot_focus()
    mons_saved = snapshot_monitors()
    desk = desk_monitor_name()
    rows: list[dict] = []
    fails: list[str] = []
    want = scenarios or {"S11", "S12", "S13", "S15", "S16", "S20", "S30"}
    print(f"dummy live on monitor {desk}; saving {mons_saved}")
    watch.STARTED_AT = 0
    watch.PACK_DEBOUNCE_SEC = 0
    paused: list[int] = []
    try:
        # Pause the *installed* extras watch so a stale copy cannot dwindle
        # dummy WS 11–19. Drive the shipped handle_open from this process.
        paused = pause_watch()
        close_dummy_windows()

        if "S12" in want:
            spawn_named("12", f"{APP_PREFIX}-left", "dummy-left", desk)
            spawn_named("12", f"{APP_PREFIX}-right", "dummy-right", desk)
            if not wait_named("12", "dummy-left") or not wait_named("12", "dummy-right"):
                fails.append("S12 locked panes did not map")
            geom.cache_clear()
            settled = geom.restore_locks_for_workspace("12", cfg)
            print("S12 restore", {k: settled.get(k) for k in ("ok", "skipped", "closeEnough", "mode", "reason", "error")})
            if settled.get("skipped") or settled.get("closeEnough") is False:
                fails.append(f"S12 restore did not apply locked split: {settled}")
            time.sleep(0.25)
            rec = record_step("S12-baseline", "12")
            rows.append(rec)
            left = frac_w(rec, "dummy-left") or 0
            right = frac_w(rec, "dummy-right") or 0
            if not (0.58 <= left <= 0.72 and 0.28 <= right <= 0.42):
                fails.append(f"S12 baseline split left={left} right={right} want ~0.65/0.35")
            xs = [int(w.get("xOnMon") if w.get("xOnMon") is not None else w.get("x") or 0) for w in rec["windows"]]
            if xs and min(xs) > 28:
                fails.append(f"S12 baseline shifted right min xOnMon={min(xs)} want <=28")
            extra = spawn_named("12", f"{APP_PREFIX}-extra", "dummy-extra", desk)
            rec_map = record_step("S12-extra-mapped", "12")
            rows.append(rec_map)
            if extra:
                watch.handle_open(extra, "12")
            else:
                fails.append("S12 extra did not map")
            time.sleep(0.3)
            rec = record_step("S12-after-extra", "12")
            rows.append(rec)
            left = frac_w(rec, "dummy-left") or 0
            right = frac_w(rec, "dummy-right") or 0
            extra_f = frac_w(rec, "dummy-extra") or 0
            if not (0.58 <= left <= 0.72 and 0.28 <= right <= 0.42):
                fails.append(f"S12 extra preserved split left={left} right={right}")
            if extra_f and not (0.22 <= extra_f <= 0.42):
                fails.append(f"S12 extra frac {extra_f} want ~1/3")
            ordered = sorted(rec["windows"], key=lambda w: w.get("x") or 0)
            labels = []
            for w in ordered:
                blob = f"{w.get('class','')} {w.get('title','')}"
                if "dummy-extra" in blob:
                    labels.append("extra")
                elif "dummy-left" in blob:
                    labels.append("left")
                elif "dummy-right" in blob:
                    labels.append("right")
            if labels and labels[-1] != "extra":
                fails.append(f"S12 extra not after locked columns: {labels}")
            extras = [extra] if extra else []
            for i in range(2):
                nxt = spawn_named("12", f"{APP_PREFIX}-extra", f"dummy-extra-{i+2}", desk)
                if nxt:
                    watch.handle_open(nxt, "12")
                    extras.append(nxt)
            time.sleep(0.5)
            rec = record_step("S12-three-extras", "12")
            rows.append(rec)
            ordered = sorted(rec["windows"], key=lambda w: w.get("x") or 0)
            labels = []
            for w in ordered:
                blob = f"{w.get('class','')} {w.get('title','')}"
                if "dummy-extra" in blob:
                    labels.append("extra")
                elif "dummy-left" in blob:
                    labels.append("left")
                elif "dummy-right" in blob:
                    labels.append("right")
            if labels[:2] != ["left", "right"]:
                fails.append(f"S12 three extras swapped locked panes: {labels}")
            left = frac_w(rec, "dummy-left") or 0
            right = frac_w(rec, "dummy-right") or 0
            if not (0.58 <= left <= 0.72 and 0.28 <= right <= 0.42):
                fails.append(f"S12 three extras split left={left} right={right}")
            for addr in extras:
                if addr:
                    hypr_eval(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{addr}" }}))')
            time.sleep(0.5)
            geom.restore_locks_for_workspace("12", cfg, keep_focus=True)
            time.sleep(0.25)
            rec = record_step("S12-after-close", "12")
            rows.append(rec)
            if floating(rec, "dummy-left") or floating(rec, "dummy-right"):
                fails.append("S12 after close a locked pane is floating")
            left = frac_w(rec, "dummy-left") or 0
            right = frac_w(rec, "dummy-right") or 0
            if not (0.58 <= left <= 0.72 and 0.28 <= right <= 0.42):
                fails.append(f"S12 after close split left={left} right={right} want ~0.65/0.35")
            if rec.get("layout") not in ("scrolling", "dwindle", "lua:workscape"):
                fails.append(f"S12 after close layout={rec.get('layout')}")

        if "S11" in want:
            spawn_named("11", f"{APP_PREFIX}-stage", "dummy-stage", desk)
            wait_named("11", "dummy-stage")
            geom.restore_locks_for_workspace("11", cfg)
            time.sleep(0.2)
            rows.append(record_step("S11-baseline", "11"))
            extra = spawn_named("11", f"{APP_PREFIX}-extra", "dummy-extra", desk)
            if extra:
                watch.handle_open(extra, "11")
            time.sleep(0.25)
            rec = record_step("S11-after-extra", "11")
            rows.append(rec)
            locked = frac_w(rec, "dummy-stage") or 0
            extra_f = frac_w(rec, "dummy-extra") or 0
            if locked < 0.85:
                fails.append(f"S11 locked frac {locked} want ~1.0")
            if extra_f and not (0.40 <= extra_f <= 0.60):
                fails.append(f"S11 extra frac {extra_f} want ~0.5")
            if extra:
                hypr_eval(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{extra}" }}))')
            time.sleep(0.4)
            rows.append(record_step("S11-after-close", "11"))

        if "S13" in want:
            spawn_named("13", f"{APP_PREFIX}-scroll", "dummy-scroll", desk)
            wait_named("13", "dummy-scroll")
            geom.restore_locks_for_workspace("13", cfg)
            time.sleep(0.2)
            rows.append(record_step("S13-baseline", "13"))
            extra = spawn_named("13", f"{APP_PREFIX}-extra", "dummy-extra", desk)
            if extra:
                watch.handle_open(extra, "13")
            time.sleep(0.25)
            rec = record_step("S13-after-extra", "13")
            rows.append(rec)
            extra_f = frac_w(rec, "dummy-extra") or 0
            if extra_f and not (0.18 <= extra_f <= 0.32):
                fails.append(f"S13 extra frac {extra_f} want ~0.25")
            if extra:
                hypr_eval(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{extra}" }}))')
            time.sleep(0.3)
            rows.append(record_step("S13-after-close", "13"))

        if "S15" in want:
            spawn_named("15", f"{APP_PREFIX}-setwidth", "dummy-setwidth", desk)
            wait_named("15", "dummy-setwidth")
            geom.restore_locks_for_workspace("15", cfg)
            time.sleep(0.2)
            rec = record_step("S15-one", "15")
            rows.append(rec)
            extra = spawn_named("15", f"{APP_PREFIX}-extra", "dummy-extra", desk)
            if extra:
                watch.handle_open(extra, "15")
            time.sleep(0.25)
            rec = record_step("S15-two", "15")
            rows.append(rec)
            widths = [w["fracW"] or 0 for w in rec["windows"]]
            if widths and not all(0.22 <= f <= 0.45 for f in widths):
                fails.append(f"S15 set-width fracs {widths} want ~1/3")
            if extra:
                hypr_eval(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{extra}" }}))')

        if "S16" in want:
            spawn_named("16", f"{APP_PREFIX}-block", "dummy-block", desk)
            wait_named("16", "dummy-block")
            extras = [spawn_named("16", f"{APP_PREFIX}-extra", f"dummy-extra-{i}", desk) for i in range(5)]
            time.sleep(0.3)
            watch.sweep_block_extras()
            time.sleep(0.2)
            rec = record_step("S16-block-cap", "16")
            rows.append(rec)
            on16 = [w for w in rec["windows"]]
            if len(on16) > 4:
                fails.append(f"S16 extras=block kept {len(on16)} windows, cap is 4")
            for addr in extras:
                if addr:
                    hypr_eval(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{addr}" }}))')

        if "S20" in want:
            probe = spawn_named("20", f"{APP_PREFIX}-probe", "dummy-probe", "eDP-1")
            time.sleep(0.2)
            before = record_step("S20-before", "20")
            rows.append(before)
            geom.restore_locks_for_workspace("12", cfg)
            time.sleep(0.2)
            after = record_step("S20-after-layout-12", "20")
            rows.append(after)
            if before.get("windows") and after.get("windows"):
                b, a = before["windows"][0], after["windows"][0]
                if abs(b["w"] - a["w"]) > 24 or abs(b["x"] - a["x"]) > 24:
                    fails.append(f"S20 unassigned window moved {b} -> {a}")
            if probe:
                hypr_eval(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{probe}" }}))')

        if "S30" in want:
            close_dummy_windows()
            parked = snapshot_focus()
            spawn_named("12", f"{APP_PREFIX}-left", "dummy-left", desk)
            spawn_named("12", f"{APP_PREFIX}-right", "dummy-right", desk)
            wait_named("12", "dummy-left")
            rec = record_step("S30-silent-spawn", "12")
            rows.append(rec)
            if parked.get("ws") and rec.get("focusWs") and rec["focusWs"] != parked["ws"]:
                if parked["ws"] not in {"12", "11", "13", "14", "15", "16", "17", "18", "19", "20"}:
                    fails.append(f"S30 silent spawn stole focus {parked['ws']} -> {rec['focusWs']}")
    finally:
        close_dummy_windows()
        restore_monitors(mons_saved)
        restore_focus(snap)
        resume_watch(paused)
        if orig_cfg is None:
            os.environ.pop("WORKSCAPE_CONFIG", None)
        else:
            os.environ["WORKSCAPE_CONFIG"] = orig_cfg
        try:
            tmp_cfg.unlink()
        except OSError:
            pass
        assert_user_config_untouched(stamp)
        dest = RECORDS / time.strftime("dummy-%Y%m%d-%H%M%S.json")
        write_records(rows, dest)
        print("records", dest)
    if fails:
        for f in fails:
            print("FAIL:", f)
        return 1
    print("dummy live matrix ok")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Dummy WorkScape matrix (does not touch user config)")
    parser.add_argument("--live", action="store_true", help="spawn dummy windows on WS 11–19")
    parser.add_argument("--scenario", action="append", default=[], help="limit to S11/S12/...")
    args = parser.parse_args()
    if not args.live:
        return self_check()
    scenarios = set(args.scenario) if args.scenario else None
    return run_live(scenarios)


if __name__ == "__main__":
    sys.exit(main())
