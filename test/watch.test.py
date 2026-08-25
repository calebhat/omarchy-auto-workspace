#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
from pathlib import Path

watch = SourceFileLoader("watch", str(Path(__file__).resolve().parent.parent / "scripts/watch")).load_module()


def test_next_open_ws():
    assert watch.next_open_ws({"2": 1, "4": 1}, "2") == "3"
    assert watch.next_open_ws({"1": 1, "2": 1}, "2") == "3"


def test_handle_open_restores_when_not_blocked(monkey_calls):
    restored = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.load_block_map = lambda: {}
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    watch.handle_open("0xabc", "2")
    assert restored == [("2", "0xabc")]


def test_handle_open_skips_startup_grace():
    restored = []
    watch.STARTED_AT = watch.time.monotonic()
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.load_block_map = lambda: {}
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    watch.handle_open("0xabc", "2")
    assert restored == []


def test_handle_open_moves_then_restores():
    restored = []
    moved = []
    watch.STARTED_AT = 0
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.geom_mod = lambda: type("G", (), {"force_scrolling": staticmethod(lambda ws, vis=2: None)})()
    watch.load_block_map = lambda: {"2": 1}
    watch.window_count = lambda ws: 2
    watch.next_open_ws = lambda blocked, ws, profile=None: "3"
    watch.move_to_ws = lambda addr, dest: moved.append((addr, dest))
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    watch.handle_open("0xabc", "2")
    assert moved == [("0xabc", "3")]
    assert restored == [("2", "")]


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
    test_next_open_ws()
    test_handle_open_restores_when_not_blocked([])
    test_handle_open_skips_startup_grace()
    test_handle_open_moves_then_restores()
    test_sweep_skips_occupied()
    print("watch.test.py ok")
