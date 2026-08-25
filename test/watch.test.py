#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
from pathlib import Path

watch = SourceFileLoader("watch", str(Path(__file__).resolve().parent.parent / "scripts/watch")).load_module()
_ORIG_RESTORE = watch.restore_locks
_ORIG_GEOM = watch.geom_mod
_ORIG_EXTRA = watch.extra_width_workspaces


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
    restored = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {}
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    try:
        watch.handle_open("0xabc", "2")
        assert restored == [("2", "0xabc")]
    finally:
        watch.extra_width_workspaces = _ORIG_EXTRA


def test_close_does_not_restore_every_locked_workspace():
    restored = []
    scheduled = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["1", "2", "3", "4"]
    watch.extra_width_workspaces = lambda: {}
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


def test_handle_open_moves_then_restores():
    restored = []
    moved = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.geom_mod = lambda: type("G", (), {"force_scrolling": staticmethod(lambda ws, vis=2: None)})()
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
    try:
        watch.handle_open("0xabc", "3")
        assert sized == [(("3", "0xabc", 4), {"stage": False, "set_width": False})], sized
        assert restored == [("3", "0xabc")]
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.extra_width_workspaces = _ORIG_EXTRA
        watch.restore_locks = _ORIG_RESTORE


def test_handle_open_sizes_unlocked_scrolling():
    sized = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: []
    watch.load_block_map = lambda: {}
    watch.extra_width_workspaces = lambda: {"3": {"visibleCount": 4, "stage": False}}
    watch.geom_mod = lambda: type(
        "G",
        (),
        {"size_new_scrolling_column": staticmethod(lambda *a, **k: sized.append((a, k)) or None)},
    )()
    try:
        watch.handle_open("0xabc", "3")
        assert sized == [(("3", "0xabc", 4), {"stage": False, "set_width": False})], sized
    finally:
        watch.geom_mod = _ORIG_GEOM
        watch.extra_width_workspaces = _ORIG_EXTRA


def test_sweep_skips_occupied():
    moved = []
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


if __name__ == "__main__":
    test_openwindow_addr_gets_0x_prefix()
    test_set_width_block_cap_is_visible_count()
    test_close_does_not_restore_every_locked_workspace()
    test_next_open_ws()
    test_handle_open_restores_when_not_blocked([])
    test_handle_open_skips_startup_grace()
    test_handle_open_moves_then_restores()
    test_note_event_burst_trips_grace()
    test_restore_locks_debounced()
    test_sweep_skips_occupied()
    test_extra_width_workspaces()
    test_handle_open_sizes_unlocked_scrolling()
    test_handle_open_sizes_locked_scrolling_then_restores()
    print("watch.test.py ok")
