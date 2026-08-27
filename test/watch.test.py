#!/usr/bin/env python3
import json
import os
from importlib.machinery import SourceFileLoader
from pathlib import Path

watch = SourceFileLoader("watch", str(Path(__file__).resolve().parent.parent / "scripts/watch")).load_module()


def test_openwindow_addr_gets_0x_prefix():
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


def test_block_cap_is_assignment_count():
    orig = watch.config_path
    fd, path = __import__("tempfile").mkstemp(suffix=".json")
    os.close(fd)
    cfg = {
        "settings": {"activeProfileId": "p"},
        "profiles": [{
            "id": "p",
            "assignments": [
                {"workspace": 9, "exec": "foot", "enabled": True},
                {"workspace": 2, "exec": "herdr", "enabled": True},
                {"workspace": 2, "exec": "panel", "enabled": True},
            ],
            "workspacePrefs": {
                "9": {"layout": "scrolling", "visibleCount": 4, "extras": "block"},
                "2": {"layout": "dwindle", "visibleCount": 3, "extras": "block"},
            },
        }],
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh)
    watch.config_path = lambda: Path(path)
    try:
        blocked = watch.load_block_map()
        assert blocked.get("9") == 1, blocked
        assert blocked.get("2") == 2, blocked
    finally:
        watch.config_path = orig
        os.unlink(path)


def test_two_lock_place_is_block_even_when_around():
    orig = watch.config_path
    fd, path = __import__("tempfile").mkstemp(suffix=".json")
    os.close(fd)
    cfg = {
        "settings": {"activeProfileId": "p"},
        "profiles": [{
            "id": "p",
            "assignments": [
                {"workspace": 2, "exec": "herdr", "enabled": True, "lockPlace": True},
                {"workspace": 2, "exec": "panel", "enabled": True, "lockPlace": True},
            ],
            "workspacePrefs": {
                "2": {"layout": "scrolling", "visibleCount": 2, "extras": "around"},
            },
        }],
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh)
    watch.config_path = lambda: Path(path)
    try:
        blocked = watch.load_block_map()
        assert blocked.get("2") == 2, blocked
    finally:
        watch.config_path = orig
        os.unlink(path)


def test_next_open_ws_skips_assigned():
    profile = {
        "assignments": [
            {"workspace": 1, "exec": "brave", "enabled": True},
            {"workspace": 2, "exec": "herdr", "enabled": True},
            {"workspace": 3, "exec": "grok", "enabled": True},
        ],
        "workspaceMonitors": {"9": "laptop"},
        "workspacePrefs": {"2": {"extras": "block"}},
        "overflow": {"enabled": False, "workspaces": []},
    }
    orig_count = watch.window_count
    watch.window_count = lambda ws: 1 if ws in {"1", "2", "3"} else 0
    try:
        dest = watch.next_open_ws({"2": 2}, "2", profile)
        assert dest == "4", dest
    finally:
        watch.window_count = orig_count


def test_next_open_ws_empty_assigned():
    profile = {
        "assignments": [
            {"workspace": 1, "exec": "brave", "enabled": True},
            {"workspace": 2, "exec": "herdr", "enabled": True},
            {"workspace": 3, "exec": "grok", "enabled": True},
            {"workspace": 4, "exec": "outlook-mail", "enabled": True},
        ],
        "workspaceMonitors": {"9": "laptop"},
        "workspacePrefs": {"2": {"extras": "block"}},
        "overflow": {"enabled": False, "workspaces": []},
    }
    orig_count = watch.window_count
    watch.window_count = lambda ws: 0 if ws == "4" else 1
    try:
        dest = watch.next_open_ws({"2": 2}, "2", profile)
        assert dest == "4", dest
    finally:
        watch.window_count = orig_count


def test_next_open_ws_uses_overflow():
    profile = {
        "assignments": [{"workspace": 2, "exec": "herdr", "enabled": True}],
        "workspacePrefs": {"2": {"extras": "block"}},
        "overflow": {"enabled": True, "workspaces": [9]},
    }
    orig_count = watch.window_count
    watch.window_count = lambda ws: 0
    try:
        dest = watch.next_open_ws({"2": 1, "9": 1}, "2", profile)
        assert dest == "9", dest
    finally:
        watch.window_count = orig_count


def test_handle_open_moves_when_blocked():
    moved = []
    focused = []
    orig = (
        watch.apply_in_progress, watch.client_by_addr, watch.load_block_map,
        watch.window_count, watch.load_active_profile, watch.next_open_ws,
        watch.move_to_ws, watch.focus_ws_and_window, watch.time.sleep,
    )
    watch.apply_in_progress = lambda: False
    watch.client_by_addr = lambda addr: {"address": addr, "floating": False, "workspace": {"id": 2}}
    watch.load_block_map = lambda: {"2": 2}
    watch.window_count = lambda ws: 3
    watch.load_active_profile = lambda: {"assignments": [{"workspace": 2, "exec": "herdr"}]}
    watch.next_open_ws = lambda blocked, ws, profile=None: "5"
    watch.move_to_ws = lambda addr, dest: moved.append((addr, dest))
    watch.focus_ws_and_window = lambda ws, addr: focused.append((ws, addr))
    watch.time.sleep = lambda _s: None
    try:
        watch.handle_open("0xabc", "2")
        assert moved == [("0xabc", "5")], moved
        assert focused == [("5", "0xabc")], focused
    finally:
        (
            watch.apply_in_progress, watch.client_by_addr, watch.load_block_map,
            watch.window_count, watch.load_active_profile, watch.next_open_ws,
            watch.move_to_ws, watch.focus_ws_and_window, watch.time.sleep,
        ) = orig


def test_handle_open_skips_when_under_cap():
    moved = []
    orig = (watch.apply_in_progress, watch.client_by_addr, watch.load_block_map, watch.window_count, watch.move_to_ws, watch.time.sleep)
    watch.apply_in_progress = lambda: False
    watch.client_by_addr = lambda addr: {"address": addr, "floating": False}
    watch.load_block_map = lambda: {"2": 2}
    watch.window_count = lambda ws: 2
    watch.move_to_ws = lambda addr, dest: moved.append((addr, dest))
    watch.time.sleep = lambda _s: None
    try:
        watch.handle_open("0xabc", "2")
        assert moved == []
    finally:
        (watch.apply_in_progress, watch.client_by_addr, watch.load_block_map, watch.window_count, watch.move_to_ws, watch.time.sleep) = orig


def test_handle_open_skips_unblocked():
    moved = []
    orig = (watch.apply_in_progress, watch.client_by_addr, watch.load_block_map, watch.move_to_ws)
    watch.apply_in_progress = lambda: False
    watch.client_by_addr = lambda addr: {"address": addr, "floating": False}
    watch.load_block_map = lambda: {}
    watch.move_to_ws = lambda addr, dest: moved.append((addr, dest))
    try:
        watch.handle_open("0xabc", "1")
        assert moved == []
    finally:
        (watch.apply_in_progress, watch.client_by_addr, watch.load_block_map, watch.move_to_ws) = orig


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
    test_block_cap_is_assignment_count()
    test_two_lock_place_is_block_even_when_around()
    test_next_open_ws_skips_assigned()
    test_next_open_ws_empty_assigned()
    test_next_open_ws_uses_overflow()
    test_handle_open_moves_when_blocked()
    test_handle_open_skips_when_under_cap()
    test_handle_open_skips_unblocked()
    test_move_to_ws_follow_false()
    test_sweep_skips_occupied()
    print("watch.test.py ok")
