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
    assert "WORKSCAPE_SWIPE_FINGERS = 4" in lua
    assert 'action = "unset"' not in lua


def test_scratchpad_and_touch():
    lua = g.render_lua({"scratchpadSwipe": True, "scratchpadFingers": 4, "touch": True})
    assert "workspace_swipe_touch = true" in lua
    assert 'workspace_name = "scratchpad"' in lua


def test_ensure_hyprland_require(tmp_path):
    lua = tmp_path / "hyprland.lua"
    lua.write_text("-- Learn how to configure Hyprland\nrequire(\"default.hypr.omarchy\")\n")
    assert g.ensure_hyprland_require(tmp_path) is True
    text = lua.read_text()
    assert 'pcall(require, "hypr.workscape-gestures")' in text
    assert g.ensure_hyprland_require(tmp_path) is False


def test_write_registers_workspace_swipe(tmp_path, monkeypatch=None):
    hypr = tmp_path / "hypr"
    hypr.mkdir()
    (hypr / "hyprland.lua").write_text("-- user hyprland\n")
    cfg = {
        "settings": {
            "persistHyprGestures": False,
            "gestures": {"workspaceSwipe": True, "fingers": 3},
        }
    }
    orig_eval = g.hypr_eval
    g.hypr_eval = lambda lua: None
    try:
        out = g.write_and_apply(cfg, hypr_dir=str(hypr / "workscape-gestures.lua"))
    finally:
        g.hypr_eval = orig_eval
    assert out["ok"] is True
    written = (hypr / "workscape-gestures.lua").read_text()
    assert 'action = "workspace"' in written
    assert 'fingers = 3' in written
    assert 'pcall(require, "hypr.workscape-gestures")' in (hypr / "hyprland.lua").read_text()


def test_resolve_profile_vs_global():
    cfg = {
        "settings": {"gestureSource": "global", "gestures": {"skipEmpty": False}, "activeProfileId": "p"},
        "profiles": [{"id": "p", "gestures": {"skipEmpty": True}}],
    }
    assert g.resolve_gestures(cfg)["skipEmpty"] is False
    cfg["settings"]["gestureSource"] = "profile"
    assert g.resolve_gestures(cfg)["skipEmpty"] is True
    del cfg["settings"]["gestureSource"]
    assert g.resolve_gestures(cfg)["skipEmpty"] is False


if __name__ == "__main__":
    test_skip_empty_uses_m()
    test_four_fingers_sets_four()
    test_include_empty_uses_r()
    test_occupied_keyboard()
    test_scratchpad_and_touch()
    test_resolve_profile_vs_global()
    import tempfile
    from pathlib import Path as P
    with tempfile.TemporaryDirectory() as d:
        test_ensure_hyprland_require(P(d))
        test_write_registers_workspace_swipe(P(d))
    print("gestures.test.py ok")
