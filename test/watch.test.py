#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
from pathlib import Path

watch = SourceFileLoader("watch", str(Path(__file__).resolve().parent.parent / "scripts/watch")).load_module()


def test_next_open_ws():
    assert watch.next_open_ws({"2": 1, "4": 1}, "2") == "3"
    assert watch.next_open_ws({"1": 1, "2": 1}, "2") == "3"


def test_handle_open_restores_when_not_blocked(monkey_calls):
    restored = []
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.load_block_map = lambda: {}
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    watch.handle_open("0xabc", "2")
    assert restored == [("2", "0xabc")]


def test_handle_open_moves_then_restores():
    restored = []
    moved = []
    watch.apply_in_progress = lambda: False
    watch.locked_workspaces = lambda: ["2"]
    watch.geom_mod = lambda: type("G", (), {"force_scrolling": staticmethod(lambda ws, vis=2: None)})()
    watch.load_block_map = lambda: {"2": 1}
    watch.window_count = lambda ws: 2
    watch.next_open_ws = lambda blocked, ws: "3"
    watch.move_to_ws = lambda addr, dest: moved.append((addr, dest))
    watch.restore_locks = lambda ws, addr="": restored.append((ws, addr))
    watch.time.sleep = lambda _s: None
    watch.handle_open("0xabc", "2")
    assert moved == [("0xabc", "3")]
    assert restored == [("2", "")]


if __name__ == "__main__":
    test_next_open_ws()
    test_handle_open_restores_when_not_blocked([])
    test_handle_open_moves_then_restores()
    print("watch.test.py ok")
