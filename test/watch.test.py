#!/usr/bin/env python3
import json
from importlib.machinery import SourceFileLoader
from pathlib import Path

watch = SourceFileLoader("watch", str(Path(__file__).resolve().parent.parent / "scripts/watch")).load_module()
watch.PACK_DEBOUNCE_SEC = 0
_ORIG_RESTORE = watch.restore_locks
_ORIG_GEOM = watch.geom_mod
_ORIG_EXTRA = watch.extra_width_workspaces
_ORIG_LOCK_COUNT = watch.lock_count
_ORIG_WINDOW_COUNT = watch.window_count
_ORIG_SCHED_CLOSE = watch.schedule_close_restore
_ORIG_STARTUP = watch.in_startup_grace
_ORIG_SLEEP = watch.time.sleep
_ORIG_STAGE_FILL = watch.schedule_stage_fill


def _reset_watch_timers():
    for t in list(watch._close_restore_timers.values()):
        t.cancel()
    watch._close_restore_timers.clear()
    for t in list(watch._quiet_end_timers.values()):
        t.cancel()
    watch._quiet_end_timers.clear()
    for t in list(watch._pack_timers.values()):
        t.cancel()
    watch._pack_timers.clear()
    for t in list(getattr(watch, "_warp_timers", {}) or {}):
        try:
            watch._warp_timers[t].cancel()
        except Exception:
            pass
    if hasattr(watch, "_warp_timers"):
        watch._warp_timers.clear()
    watch._layout_quiet_until.clear()
    watch._appended_extra.clear()


def test_openwindow_addr_gets_0x_prefix():
    # Hyprland socket2 openwindow>> omits 0x; clients JSON includes it.
    line = "openwindow>>5643708e24c0,2,foot,foot"
    payload = line.split(">>", 1)[1]
    parts = payload.split(",", 3)
    addr, ws = parts[0], parts[1]
    if addr and not addr.startswith("0x"):
        addr = "0x" + addr
    assert addr == "0x5643708e24c0"
    assert ws == "2"


def test_monitor_hotplug_line():
    assert "monitoradded>>DVI-I-1".startswith("monitoradded")
    assert "monitorremoved>>DVI-I-1".startswith("monitorremoved")
    assert "monitoraddedv2>>1,DVI-I-1".startswith("monitoradded")


def test_set_width_block_cap_is_visible_count():
    orig = watch.config_path
    import json, tempfile, os
    fd, path = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    cfg = {
        "settings": {"activeProfileId": "p"},
        "profiles": [{
            "id": "p",
            "assignments": [
                {"workspace": 9, "exec": "foot", "enabled": True},
                {"workspace": 2, "exec": "herdr", "enabled": True},
            ],
            "workspacePrefs": {
                "9": {"layout": "set-width", "visibleCount": 4, "extras": "block"},
                "2": {"layout": "scrolling", "visibleCount": 3, "extras": "block"},
            },
        }],
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh)
    watch.config_path = lambda: Path(path)
    try:
        blocked = watch.load_block_map()
        assert blocked.get("9") == 4, blocked
        assert blocked.get("2") == 1, blocked
    finally:
        watch.config_path = orig
        os.unlink(path)


def test_next_open_ws():
    assert watch.next_open_ws({"2": 1, "4": 1}, "2") == "3"
    assert watch.next_open_ws({"1": 1, "2": 1}, "2") == "3"


def test_handle_open_restores_when_not_blocked(monkey_calls):
    appended = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {}
    watch.geom_mod = lambda: type(
        "G",
        (),
        {
            "managed_workspaces": staticmethod(lambda: {"2"}),
            "append_extra_after_locked": staticmethod(lambda ws, addr: appended.append((ws, addr))),
        },
    )()
    watch.time.sleep = lambda _s: None
    try:
        watch.lock_count = lambda ws: 2
        watch.handle_open("0xabc", "2")
        assert appended == [("2", "0xabc")]
    finally:
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.geom_mod = _ORIG_GEOM
        watch.time.sleep = _ORIG_SLEEP


def test_handle_open_2lock_tape_skips_pack():
    appended = []
    warps = []
    orig_warp = watch.schedule_warp_cursor
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {}
    watch.lock_count = lambda ws: 2
    watch.geom_mod = lambda: type(
        "G",
        (),
        {
            "managed_workspaces": staticmethod(lambda: {"2"}),
            "workspace_tiled_layout": staticmethod(lambda ws: "lua:workscape"),
            "append_extra_after_locked": staticmethod(lambda ws, addr: appended.append((ws, addr))),
        },
    )()
    watch.schedule_warp_cursor = lambda addr: warps.append(addr)
    try:
        watch.handle_open("0xabc", "2")
        assert appended == []
        assert warps == ["0xabc"]
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.schedule_warp_cursor = orig_warp
        _reset_watch_timers()


def test_close_does_not_restore_every_locked_workspace():
    restored = []
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["1", "2", "3", "4"]
    watch.extra_width_workspaces = lambda: {}
    watch.lock_count = lambda ws: 2
    watch.window_count = lambda ws: 2
    watch._layout_quiet_until.clear()
    watch.restore_locks = lambda ws, addr="", keep_focus=False: restored.append(ws)
    watch.schedule_close_restore = lambda ws: scheduled.append(ws)
    watch._window_ws.clear()
    watch.remember_window("0xabc", "2")
    try:
        watch.handle_close_or_move(None)
        assert restored == []
        assert scheduled == []
        watch.handle_close_or_move(None, "0xabc")
        assert restored == []
        assert scheduled == ["2"]
        watch.handle_close_or_move(None, "0xdead")
        assert scheduled == ["2"]
    finally:
        watch.restore_locks = _ORIG_RESTORE
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.schedule_close_restore = _ORIG_SCHED_CLOSE


def test_close_skips_restore_while_extras_remain():
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.extra_width_workspaces = lambda: {}
    watch.lock_count = lambda ws: 2
    watch.window_count = lambda ws: 5
    watch._layout_quiet_until.clear()
    watch.schedule_close_restore = lambda ws: scheduled.append(ws)
    watch._window_ws.clear()
    watch.remember_window("0xextra", "2")
    try:
        watch.handle_close_or_move(None, "0xextra")
        assert scheduled == []
    finally:
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.schedule_close_restore = _ORIG_SCHED_CLOSE
        watch.extra_width_workspaces = _ORIG_EXTRA


def test_close_skips_restore_during_layout_quiet():
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.extra_width_workspaces = lambda: {}
    watch.lock_count = lambda ws: 2
    watch.window_count = lambda ws: 2
    watch.schedule_close_restore = lambda ws: scheduled.append(ws)
    watch._window_ws.clear()
    watch.remember_window("0xextra", "2")
    watch.begin_layout_quiet("2", 5.0)
    try:
        watch.handle_close_or_move(None, "0xextra")
        assert scheduled == []
    finally:
        watch._layout_quiet_until.clear()
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.schedule_close_restore = _ORIG_SCHED_CLOSE
        watch.extra_width_workspaces = _ORIG_EXTRA


def test_handle_open_quiets_close_restore():
    appended = []
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {}
    watch.lock_count = lambda ws: 2
    watch.window_count = lambda ws: 3
    watch._layout_quiet_until.clear()
    watch.schedule_close_restore = lambda ws: scheduled.append(ws)
    watch.geom_mod = lambda: type(
        "G",
        (),
        {
            "managed_workspaces": staticmethod(lambda: {"2"}),
            "append_extra_after_locked": staticmethod(lambda ws, addr: appended.append((ws, addr))),
        },
    )()
    watch.time.sleep = lambda _s: None
    try:
        watch.handle_open("0xabc", "2")
        assert appended == [("2", "0xabc")]
        assert watch.in_layout_quiet("2") is True
        watch.remember_window("0xghost", "2")
        watch.handle_close_or_move(None, "0xghost")
        assert scheduled == []
    finally:
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.geom_mod = _ORIG_GEOM
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.schedule_close_restore = _ORIG_SCHED_CLOSE
        watch.time.sleep = _ORIG_SLEEP
        _reset_watch_timers()


def test_quiet_end_restores_when_extras_gone():
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.in_startup_grace = lambda: False
    watch.lock_count = lambda ws: 2
    watch.window_count = lambda ws: 2
    watch.schedule_close_restore = lambda ws: scheduled.append(ws)
    watch.time.sleep = _ORIG_SLEEP
    _reset_watch_timers()
    try:
        watch.begin_layout_quiet("2", 0.05)
        _ORIG_SLEEP(0.2)
        assert scheduled == ["2"]
    finally:
        _reset_watch_timers()
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.schedule_close_restore = _ORIG_SCHED_CLOSE
        watch.in_startup_grace = _ORIG_STARTUP


def test_quiet_end_skips_restore_while_extras_remain():
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.in_startup_grace = lambda: False
    watch.lock_count = lambda ws: 2
    watch.window_count = lambda ws: 4
    watch.schedule_close_restore = lambda ws: scheduled.append(ws)
    watch.time.sleep = _ORIG_SLEEP
    _reset_watch_timers()
    try:
        watch.begin_layout_quiet("2", 0.05)
        _ORIG_SLEEP(0.2)
        assert scheduled == []
    finally:
        _reset_watch_timers()
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.schedule_close_restore = _ORIG_SCHED_CLOSE
        watch.in_startup_grace = _ORIG_STARTUP


def test_handle_open_skips_startup_grace():
    restored = []
    watch.STARTED_AT = watch.time.monotonic()
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: []
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {}
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    try:
        watch.handle_open("0xabc", "2")
        assert restored == []
    finally:
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.time.sleep = _ORIG_SLEEP


def test_handle_open_moves_then_restores():
    restored = []
    moved = []
    orig_move = watch.move_to_ws
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.geom_mod = lambda: type("G", (), {"force_scrolling": staticmethod(lambda ws, vis=2: None), "managed_workspaces": staticmethod(lambda: {"2"})})()
    watch.load_block_map = lambda: {"2": 1}
    watch.extra_width_workspaces = lambda: {}
    watch.window_count = lambda ws: 2
    watch.next_open_ws = lambda blocked, ws, profile=None: "3"
    watch.move_to_ws = lambda addr, dest: moved.append((addr, dest))
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    try:
        watch.handle_open("0xabc", "2")
        assert moved == [("0xabc", "3")]
        assert restored == [("2", "")]
    finally:
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.geom_mod = _ORIG_GEOM
        watch.time.sleep = _ORIG_SLEEP
        watch.move_to_ws = orig_move
        watch.restore_locks = _ORIG_RESTORE
        watch.window_count = _ORIG_WINDOW_COUNT


def test_handle_open_block_tiles_covering_float():
    tiled = []
    orig_block = watch.load_block_map
    orig_locked = watch.locked_workspaces
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: []
    watch.load_block_map = lambda: {"8": 2}
    watch.extra_width_workspaces = lambda: {}
    watch.lock_count = lambda ws: 0
    watch.window_count = lambda ws: 1
    watch.geom_mod = lambda: type(
        "G",
        (),
        {
            "managed_workspaces": staticmethod(lambda: set()),
            "tile_covering_floats": staticmethod(lambda ws: tiled.append(ws)),
        },
    )()
    watch.time.sleep = lambda _s: None
    try:
        watch.handle_open("0xabc", "8")
        assert tiled == ["8"]
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.time.sleep = _ORIG_SLEEP
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.load_block_map = orig_block
        watch.locked_workspaces = orig_locked
        _reset_watch_timers()


def test_note_event_burst_trips_grace():
    watch._event_times.clear()
    watch._burst_until = 0.0
    orig_n, orig_w, orig_g = watch.BURST_EVENTS, watch.BURST_WINDOW_SEC, watch.BURST_GRACE_SEC
    watch.BURST_EVENTS = 4
    watch.BURST_WINDOW_SEC = 2.0
    watch.BURST_GRACE_SEC = 3.0
    try:
        for _ in range(3):
            assert watch.note_event() is False
        assert watch.note_event() is True
        assert watch.note_event() is True
    finally:
        watch.BURST_EVENTS, watch.BURST_WINDOW_SEC, watch.BURST_GRACE_SEC = orig_n, orig_w, orig_g
        watch._event_times.clear()
        watch._burst_until = 0.0


def test_restore_locks_debounced():
    calls = []
    orig_d = watch.RESTORE_DEBOUNCE_SEC
    watch.restore_locks = _ORIG_RESTORE
    watch._restoring = False
    watch._last_restore.clear()
    watch._burst_until = 0.0
    watch.RESTORE_DEBOUNCE_SEC = 10
    watch.geom_mod = lambda: type("G", (), {"restore_locks_for_workspace": staticmethod(lambda *a, **k: calls.append(1) or {"ok": True})})()
    try:
        watch.restore_locks("2", "0x1")
        watch.restore_locks("2", "0x1")
        assert len(calls) == 1
    finally:
        watch.RESTORE_DEBOUNCE_SEC = orig_d
        watch.geom_mod = _ORIG_GEOM
        watch.restore_locks = _ORIG_RESTORE
        watch._restoring = False
        watch._last_restore.clear()


def test_extra_width_workspaces():
    orig = watch.load_active_profile
    watch.load_active_profile = lambda: {
        "workspacePrefs": {
            "2": {"layout": "scrolling", "visibleCount": 3},
            "3": {"layout": "scrolling", "visibleCount": 4},
            "5": {"layout": "dwindle", "visibleCount": 4},
        }
    }
    try:
        got = watch.extra_width_workspaces()
        assert got["2"]["visibleCount"] == 3
        assert got["3"]["visibleCount"] == 4 and got["3"]["stage"] is False
        assert "5" not in got
    finally:
        watch.load_active_profile = orig


def test_handle_open_sizes_locked_scrolling_then_restores():
    sized = []
    restored = []
    watch.STARTED_AT = 0
    watch._burst_until = 0.0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["3"]
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {"3": {"visibleCount": 4, "stage": False}}
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.geom_mod = lambda: type(
        "G",
        (),
        {"size_new_scrolling_column": staticmethod(lambda *a, **k: sized.append((a, k)) or None)},
    )()
    scheduled = []
    fills = []
    watch.schedule_open_settle = lambda ws, addr="": scheduled.append((ws, addr))
    watch.schedule_stage_fill = lambda ws: fills.append(ws)
    watch.lock_count = lambda ws: 1
    try:
        watch.handle_open("0xabc", "3")
        assert scheduled == []
        assert fills == []
        assert sized == []
        assert restored == []
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.restore_locks = _ORIG_RESTORE
        watch.schedule_stage_fill = _ORIG_STAGE_FILL


def test_handle_open_set_width_sizes_extra():
    sized = []
    watch.STARTED_AT = 0
    watch._burst_until = 0.0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: []
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {"15": {"visibleCount": 3, "stage": False, "setWidth": True}}
    watch.lock_count = lambda ws: 0
    watch.geom_mod = lambda: type(
        "G",
        (),
        {
            "managed_workspaces": staticmethod(lambda: {"15"}),
            "size_new_scrolling_column": staticmethod(lambda *a, **k: sized.append((a, k))),
        },
    )()
    fills = []
    watch.schedule_stage_fill = lambda ws: fills.append(ws)
    try:
        watch.handle_open("0xabc", "15")
        assert sized, sized
        assert sized[0][1].get("set_width") is True or (len(sized[0][0]) >= 4)
        assert fills == []
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.schedule_stage_fill = _ORIG_STAGE_FILL


def test_handle_open_sizes_unlocked_scrolling():
    sized = []
    watch.STARTED_AT = 0
    watch._burst_until = 0.0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: []
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {"3": {"visibleCount": 4, "stage": False}}
    watch.geom_mod = lambda: type(
        "G",
        (),
        {"size_new_scrolling_column": staticmethod(lambda *a, **k: sized.append((a, k)) or None)},
    )()
    scheduled = []
    fills = []
    watch.schedule_open_settle = lambda ws, addr="": scheduled.append((ws, addr))
    watch.schedule_stage_fill = lambda ws: fills.append(ws)
    watch.lock_count = lambda ws: 0
    try:
        watch.handle_open("0xabc", "3")
        assert scheduled == []
        assert fills == []
        assert sized == []
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.schedule_stage_fill = _ORIG_STAGE_FILL


def test_handle_open_1lock_scroll_warps_not_fills():
    warps = []
    fills = []
    orig_prof = watch.load_active_profile
    orig_assigned = watch.window_is_assigned
    orig_check = watch.subprocess.check_output
    orig_warp = watch.schedule_warp_cursor
    orig_fill = watch.schedule_stage_fill
    orig_locked = watch.locked_workspaces
    orig_block = watch.load_block_map
    watch.STARTED_AT = 0
    watch._burst_until = 0.0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["3"]
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {"3": {"visibleCount": 4, "stage": False}}
    watch.lock_count = lambda ws: 1
    watch.window_count = lambda ws: 2
    watch.load_active_profile = lambda: {"assignments": [{"workspace": 3, "name": "Grok Bot", "enabled": True}]}
    watch.window_is_assigned = lambda c, p, ws: True
    watch.schedule_warp_cursor = lambda addr: warps.append(addr)
    watch.schedule_stage_fill = lambda ws: fills.append(ws)
    watch.geom_mod = lambda: type("G", (), {"managed_workspaces": staticmethod(lambda: {"3"})})()
    watch.subprocess.check_output = lambda *a, **k: '[{"address":"0xabc","class":"foot","workspace":{"id":3},"floating":false}]'
    try:
        watch.handle_open("0xabc", "3")
        assert warps == ["0xabc"]
        assert fills == []
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.load_active_profile = orig_prof
        watch.window_is_assigned = orig_assigned
        watch.subprocess.check_output = orig_check
        watch.schedule_warp_cursor = orig_warp
        watch.schedule_stage_fill = _ORIG_STAGE_FILL
        watch.locked_workspaces = orig_locked
        watch.load_block_map = orig_block


def test_lock_count_set_width_is_zero():
    orig = watch.load_active_profile
    watch.load_active_profile = lambda: {
        "assignments": [{"workspace": "3", "lockPlace": True, "enabled": True}],
        "workspacePrefs": {"3": {"layout": "set-width", "visibleCount": 4}},
    }
    try:
        assert watch.lock_count("3") == 0
    finally:
        watch.load_active_profile = orig


def test_stage_fill_set_width_resizes_not_full():
    sized = []
    focused = []
    orig_delay = watch.CLOSE_RESTORE_DELAY_SEC
    orig_check = watch.subprocess.check_output
    orig_extra = watch.extra_width_workspaces
    orig_geom = watch.geom_mod
    watch.CLOSE_RESTORE_DELAY_SEC = 0
    watch.extra_width_workspaces = lambda: {"3": {"visibleCount": 4, "stage": False, "setWidth": True}}
    watch.geom_mod = lambda: type(
        "G",
        (),
        {
            "force_scrolling": staticmethod(lambda *a, **k: focused.append(("scroll", k))),
            "focus_window": staticmethod(lambda addr: focused.append(("focus", addr))),
            "layout_msg": staticmethod(lambda msg: focused.append(("msg", msg))),
            "size_new_scrolling_column": staticmethod(lambda ws, addr, vis, set_width=False, **k: sized.append((ws, addr, vis, set_width))),
        },
    )()

    def check(*a, **k):
        joined = " ".join(str(x) for x in a)
        if "clients" in joined:
            return '[{"address":"0xg","floating":false,"workspace":{"id":3}}]'
        return '{"id": 3}'

    watch.subprocess.check_output = check
    _reset_watch_timers()
    try:
        watch.schedule_stage_fill("3")
        assert sized == [("3", "0xg", 4, True)], sized
        assert not any(c[0] == "msg" and "1.0" in str(c) for c in focused)
    finally:
        _reset_watch_timers()
        watch.CLOSE_RESTORE_DELAY_SEC = orig_delay
        watch.subprocess.check_output = orig_check
        watch.extra_width_workspaces = orig_extra
        watch.geom_mod = orig_geom


def test_stage_fill_skips_inactive_workspace():
    focused = []
    orig_delay = watch.CLOSE_RESTORE_DELAY_SEC
    orig_check = watch.subprocess.check_output
    orig_extra = watch.extra_width_workspaces
    orig_geom = watch.geom_mod
    watch.CLOSE_RESTORE_DELAY_SEC = 0.05
    watch.extra_width_workspaces = lambda: {"1": {"visibleCount": 2, "stage": True}}
    watch.geom_mod = lambda: type(
        "G",
        (),
        {
            "force_scrolling": staticmethod(lambda *a, **k: focused.append("scroll")),
            "focus_window": staticmethod(lambda addr: focused.append(("focus", addr))),
            "layout_msg": staticmethod(lambda msg: focused.append(("msg", msg))),
        },
    )()

    def check(*a, **k):
        joined = " ".join(str(x) for x in a)
        if "clients" in joined:
            return '[{"address":"0xbrave","floating":false,"workspace":{"id":1}}]'
        return '{"id": 2}'

    watch.subprocess.check_output = check
    _reset_watch_timers()
    try:
        watch.schedule_stage_fill("1")
        _ORIG_SLEEP(0.2)
        assert focused == []
    finally:
        _reset_watch_timers()
        watch.CLOSE_RESTORE_DELAY_SEC = orig_delay
        watch.subprocess.check_output = orig_check
        watch.extra_width_workspaces = orig_extra
        watch.geom_mod = orig_geom


def test_warp_does_not_shadow_width_with_workspace():
    evals = []
    orig_check = watch.subprocess.check_output
    orig_eval = watch.hypr_eval
    orig_sleep = watch.time.sleep
    watch.hypr_eval = lambda lua: evals.append(lua)
    watch.time.sleep = lambda _s: None

    def check(*a, **k):
        joined = " ".join(str(x) for x in a)
        if "clients" in joined:
            return '[{"address":"0xabc","floating":false,"workspace":{"id":4},"at":[726,36],"size":[704,914],"monitor":0}]'
        if "activeworkspace" in joined:
            return '{"id":4}'
        if "monitors" in joined:
            return '[{"id":0,"x":0,"y":0,"width":2880,"height":1920,"scale":2}]'
        if "workspaces" in joined:
            return '[{"id":4,"tiledLayout":"scrolling"}]'
        return "[]"

    watch.subprocess.check_output = check
    try:
        watch.warp_cursor_to_window("0xabc")
        assert any("cursor.move" in e for e in evals), evals
        assert not any("move +col" in e for e in evals), evals
    finally:
        watch.subprocess.check_output = orig_check
        watch.hypr_eval = orig_eval
        watch.time.sleep = orig_sleep


def test_warp_pans_offscreen_scrolling_extra():
    evals = []
    orig_check = watch.subprocess.check_output
    orig_eval = watch.hypr_eval
    orig_sleep = watch.time.sleep
    watch.hypr_eval = lambda lua: evals.append(lua)
    watch.time.sleep = lambda _s: None
    step = {"n": 0}

    def check(*a, **k):
        joined = " ".join(str(x) for x in a)
        if "clients" in joined:
            step["n"] += 1
            x = 2400 if step["n"] < 3 else 200
            return json.dumps([{
                "address": "0xextra",
                "floating": False,
                "workspace": {"id": 3},
                "at": [x, 36],
                "size": [944, 1034],
                "monitor": 2,
            }])
        if "activeworkspace" in joined:
            return '{"id":3}'
        if "monitors" in joined:
            return '[{"id":2,"x":0,"y":0,"width":1920,"height":1080,"scale":1}]'
        if "workspaces" in joined:
            return '[{"id":3,"tiledLayout":"scrolling"}]'
        return "[]"

    watch.subprocess.check_output = check
    try:
        watch.warp_cursor_to_window("0xextra")
        joined = "\n".join(evals)
        assert "move +col" in joined, evals
        assert "fit_into_view" in joined, evals
        assert any("cursor.move" in e for e in evals), evals
        assert not any('focus({ monitor' in e or "focus({ workspace" in e for e in evals), evals
    finally:
        watch.subprocess.check_output = orig_check
        watch.hypr_eval = orig_eval
        watch.time.sleep = orig_sleep


def test_pick_successor_after_close_order():
    remaining = [
        {"address": "0xb", "at": [720, 36], "size": [104, 900], "floating": False, "workspace": {"id": 4}},
        {"address": "0xc", "at": [830, 36], "size": [400, 900], "floating": False, "workspace": {"id": 4}},
    ]
    # Closed the left extra; next is the thin strip, not the wide one after it.
    assert watch.pick_successor_after_close("4", 10, remaining) == "0xb"
    assert watch.pick_successor_after_close("4", 720, remaining[1:]) == "0xc"
    assert watch.pick_successor_after_close("4", 830, remaining[:1]) == "0xb"
    assert watch.pick_successor_after_close("4", None, remaining) == "0xb"
    assert watch.pick_successor_after_close("4", 10, []) is None


def test_move_to_ws_follow_false():
    calls = []
    orig = watch.hypr_eval
    watch.hypr_eval = lambda lua: calls.append(lua)
    try:
        watch.move_to_ws("0xabc", "3")
        assert calls, calls
        assert "follow=false" in calls[0]
        assert "follow=true" not in calls[0]
    finally:
        watch.hypr_eval = orig


def test_extras_remain_unknown_clients_do_not_restore():
    orig_n, orig_l = watch.window_count, watch.lock_count
    watch.window_count = lambda ws: -1
    watch.lock_count = lambda ws: 2
    try:
        assert watch.extras_remain("2") is True
    finally:
        watch.window_count = orig_n
        watch.lock_count = orig_l


def test_quiet_end_skips_restore_after_extra_append():
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.in_startup_grace = lambda: False
    watch.lock_count = lambda ws: 2
    watch.window_count = lambda ws: 2
    watch.schedule_close_restore = lambda ws: scheduled.append(ws)
    _reset_watch_timers()
    watch._appended_extra["2"] = True
    try:
        watch.begin_layout_quiet("2", 0.05)
        _ORIG_SLEEP(0.2)
        assert scheduled == []
    finally:
        _reset_watch_timers()
        watch.lock_count = _ORIG_LOCK_COUNT
        watch.window_count = _ORIG_WINDOW_COUNT
        watch.schedule_close_restore = _ORIG_SCHED_CLOSE
        watch.in_startup_grace = _ORIG_STARTUP


def test_sweep_skips_occupied():
    moved = []
    orig_move = watch.move_to_ws
    orig_profile = watch.load_active_profile
    orig_block = watch.load_block_map
    orig_next = watch.next_open_ws
    watch.load_active_profile = lambda: {"assignments": [], "overflow": {"enabled": True, "workspaces": [5]}}
    watch.load_block_map = lambda: {"5": 1}
    watch.move_to_ws = lambda addr, dest: moved.append((addr, dest))
    watch.next_open_ws = lambda blocked, ws, profile=None: "6"
    watch.os.environ["WORKSCAPE_OCCUPIED_WS"] = "5 8"
    orig_check = watch.subprocess.check_output
    watch.subprocess.check_output = lambda *a, **k: '[{"address":"0x1","class":"foot","workspace":{"id":5}},{"address":"0x2","class":"foot","workspace":{"id":5}}]'
    try:
        out = watch.sweep_block_extras()
        assert out == []
        assert moved == []
    finally:
        watch.subprocess.check_output = orig_check
        watch.os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
        watch.move_to_ws = orig_move
        watch.load_active_profile = orig_profile
        watch.load_block_map = orig_block
        watch.next_open_ws = orig_next


if __name__ == "__main__":
    test_openwindow_addr_gets_0x_prefix()
    test_monitor_hotplug_line()
    test_set_width_block_cap_is_visible_count()
    test_close_does_not_restore_every_locked_workspace()
    test_close_skips_restore_while_extras_remain()
    test_close_skips_restore_during_layout_quiet()
    test_handle_open_quiets_close_restore()
    test_quiet_end_restores_when_extras_gone()
    test_quiet_end_skips_restore_while_extras_remain()
    test_next_open_ws()
    test_handle_open_restores_when_not_blocked([])
    test_handle_open_2lock_tape_skips_pack()
    test_handle_open_skips_startup_grace()
    test_handle_open_moves_then_restores()
    test_handle_open_block_tiles_covering_float()
    test_note_event_burst_trips_grace()
    test_restore_locks_debounced()
    test_sweep_skips_occupied()
    test_extra_width_workspaces()
    test_handle_open_set_width_sizes_extra()
    test_handle_open_sizes_unlocked_scrolling()
    test_handle_open_sizes_locked_scrolling_then_restores()
    test_handle_open_1lock_scroll_warps_not_fills()
    test_lock_count_set_width_is_zero()
    test_stage_fill_set_width_resizes_not_full()
    test_stage_fill_skips_inactive_workspace()
    test_warp_does_not_shadow_width_with_workspace()
    test_warp_pans_offscreen_scrolling_extra()
    test_pick_successor_after_close_order()
    test_move_to_ws_follow_false()
    test_extras_remain_unknown_clients_do_not_restore()
    test_quiet_end_skips_restore_after_extra_append()
    print("watch.test.py ok")
