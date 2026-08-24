#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
from pathlib import Path

g = SourceFileLoader("gestures", str(Path(__file__).resolve().parent.parent / "scripts/gestures")).load_module()


def test_skip_empty_uses_m():
    lua = g.render_lua({"skipEmpty": True, "workspaceSwipe": True, "fingers": 3})
    assert "workspace_swipe_use_r = false" in lua
    assert "workspace_swipe_invert = true" in lua
    assert 'action = "workspace"' in lua


def test_include_empty_uses_r():
    lua = g.render_lua({"skipEmpty": False, "keyboard": True})
    assert "workspace_swipe_use_r = true" in lua
    assert 'workspace = "r-1"' in lua
    assert 'workspace = "r+1"' in lua


def test_occupied_keyboard():
    lua = g.render_lua({"skipEmpty": True, "keyboard": True})
    assert 'workspace = "e-1"' in lua
    assert "SUPER + comma" in lua


def test_four_fingers_sets_four():
    lua = g.render_lua({"fingers": 4, "workspaceSwipe": True})
    assert 'fingers = 4, direction = "horizontal", action = "workspace"' in lua
    assert "WORKBOOK_SWIPE_FINGERS = 4" in lua
    assert 'action = "unset"' not in lua


def test_scratchpad_and_touch():
    lua = g.render_lua({"scratchpadSwipe": True, "scratchpadFingers": 4, "touch": True})
    assert "workspace_swipe_touch = true" in lua
    assert 'workspace_name = "scratchpad"' in lua


def test_resolve_profile_vs_global():
    cfg = {
        "settings": {"gestureSource": "global", "gestures": {"skipEmpty": False}, "activeProfileId": "p"},
        "profiles": [{"id": "p", "gestures": {"skipEmpty": True}}],
    }
    assert g.resolve_gestures(cfg)["skipEmpty"] is False
    cfg["settings"]["gestureSource"] = "profile"
    assert g.resolve_gestures(cfg)["skipEmpty"] is True


if __name__ == "__main__":
    test_skip_empty_uses_m()
    test_four_fingers_sets_four()
    test_include_empty_uses_r()
    test_occupied_keyboard()
    test_scratchpad_and_touch()
    test_resolve_profile_vs_global()
    print("gestures.test.py ok")
