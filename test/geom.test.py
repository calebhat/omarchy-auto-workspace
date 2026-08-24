#!/usr/bin/env python3
import time
from importlib.machinery import SourceFileLoader

geom = SourceFileLoader("geom", str(__import__("pathlib").Path(__file__).resolve().parent.parent / "scripts/geom")).load_module()


def test_layout_metrics_scale():
    mon = {
        "width": 2880,
        "height": 1920,
        "scale": 2,
        "reserved": [0, 26, 0, 0],
        "x": 0,
        "y": 0,
    }
    orig = geom.gaps_out
    geom.gaps_out = lambda: (8, 8, 8, 8)
    try:
        m = geom.layout_metrics(mon)
    finally:
        geom.gaps_out = orig
    assert m["lw"] == 1440
    assert m["lh"] == 960
    assert m["x"] == 8
    assert m["y"] == 34
    assert m["w"] == 1424
    assert m["h"] == 918


def test_geom_pixels():
    metrics = {"x": 8, "y": 34, "w": 1424, "h": 918, "scale": 2}
    left = geom.geom_pixels({"x": 0, "y": 0, "w": 0.5, "h": 1}, metrics)
    right = geom.geom_pixels({"x": 0.5, "y": 0, "w": 0.5, "h": 1}, metrics)
    assert left["x"] == 8
    assert right["x"] == 8 + 712
    assert left["w"] + right["w"] == 1424


def test_box_to_geom():
    metrics = {"x": 8, "y": 34, "w": 1000, "h": 900, "scale": 1}
    g = geom.box_to_geom({"x": 8, "y": 34, "w": 628, "h": 900}, metrics)
    assert g["x"] == 0
    assert g["y"] == 0
    assert abs(g["w"] - 0.628) < 0.001
    assert g["h"] == 1


def test_lock_plan_and_assignment():
    prefs = {"2": {"lockSizes": False, "extras": "around", "visibleCount": 2}}
    locked = {"workspace": 2, "exec": "herdr", "lockPlace": True}
    unlocked = {"workspace": 2, "exec": "panel", "lockPlace": False}
    assert geom.assignment_is_locked(locked, prefs) is True
    assert geom.assignment_is_locked(unlocked, prefs) is False
    assert geom.assignment_is_locked(unlocked, {"2": {"lockSizes": True}}) is True
    profile = {
        "workspacePrefs": prefs,
        "assignments": [locked, unlocked, {"workspace": 3, "exec": "x", "lockPlace": True}],
    }
    plan = geom.lock_plan_for_workspace(profile, "2")
    assert len(plan["locked"]) == 1
    assert plan["locked"][0]["exec"] == "herdr"
    assert plan["extras"] == "around"


def test_close_enough_and_fallback():
    assert geom.close_enough({"w": 600, "h": 900}, {"w": 608, "h": 900})
    assert not geom.close_enough({"w": 400, "h": 900}, {"w": 600, "h": 900})
    g = geom.fallback_geom(0, 2)
    assert g["x"] == 0 and g["w"] == 0.5
    g2 = geom.fallback_geom(1, 2)
    assert g2["x"] == 0.5


def test_column_width_frac():
    assert geom.extra_column_frac(2) == 0.5
    assert geom.extra_column_frac(3) == 0.3333
    assert geom.extra_column_frac(4) == 0.25
    assert geom.extra_column_frac(10) == 0.1
    assert geom.extra_column_frac(20) == 0.05
    assert geom.clamp_visible_count(21) == 20
    assert geom.clamp_visible_count(0) == 1
    locked = {"lock": True, "geom": {"x": 0, "y": 0, "w": 0.6279, "h": 1}}
    extra = {"lock": False, "geom": {}}
    assert geom.column_width_frac(locked, 0.5) == 0.6279
    assert geom.column_width_frac(extra, 0.5) == 0.5
    assert "fullscreen_on_one_column = false" in geom.scrolling_layout_opts(2, lock=True)
    assert "fullscreen_on_one_column" not in geom.scrolling_layout_opts(2, lock=False)


def test_restore_resizes_locked_pane():
    calls = []
    clients = [
        {
            "address": "0x1",
            "class": "herdr",
            "title": "herdr",
            "initialClass": "herdr",
            "workspace": {"id": 2, "name": "2"},
            "at": [8, 34],
            "size": [400, 900],
        },
        {
            "address": "0x2",
            "class": "foot",
            "title": "foot",
            "initialClass": "foot",
            "workspace": {"id": 2, "name": "2"},
            "at": [8, 34],
            "size": [-3, 900],
        },
    ]
    monitors = [{"name": "DVI-I-1", "width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0, "reserved": [0, 0, 0, 0], "focused": True}]
    workspaces = [{"id": 2, "name": "2", "monitor": "DVI-I-1"}]

    def fake_j(cmd, cached=False):
        if cmd == "clients":
            return clients
        if cmd == "monitors":
            return monitors
        if cmd == "workspaces":
            return workspaces
        if cmd == "activewindow":
            return {"address": "0x2"}
        if cmd.startswith("getoption"):
            return {"css": "8"}
        return {}

    orig_j, orig_eval, orig_sleep = geom.hypr_j, geom.hypr_eval, time.sleep
    geom.hypr_j = fake_j
    geom.hypr_eval = lambda lua: calls.append(lua)
    time.sleep = lambda _s: None
    try:
        cfg = {
            "settings": {"activeProfileId": "p"},
            "profiles": [{
                "id": "p",
                "assignments": [{
                    "workspace": 2,
                    "name": "Herdr",
                    "exec": "herdr",
                    "lockPlace": True,
                    "geom": {"x": 0, "y": 0, "w": 0.6, "h": 1},
                }],
                "workspacePrefs": {"2": {"layout": "dwindle", "lockSizes": False, "extras": "around", "visibleCount": 2}},
            }],
        }
        result = geom.restore_locks_for_workspace("2", cfg, prefer_addr="0x2")
    finally:
        geom.hypr_j, geom.hypr_eval, time.sleep = orig_j, orig_eval, orig_sleep
    assert result["ok"] is True
    assert result.get("skipped") is not True
    joined = "\n".join(calls)
    assert "layout = \"scrolling\"" in joined
    assert "fullscreen_on_one_column = false" in joined
    assert "hl.dsp.focus" in joined
    assert "expel" in joined
    assert "colresize 0.6" in joined
    assert "colresize 0.5" in joined
    assert "window.resize" not in joined
    assert "fit all" not in joined
    inhibit_at = next(i for i, c in enumerate(calls) if "inhibit_scroll true" in c)
    first_locked_focus = next(i for i, c in enumerate(calls) if 'window = "address:0x1"' in c)
    first_extra_focus = next(i for i, c in enumerate(calls) if 'window = "address:0x2"' in c)
    assert first_extra_focus < inhibit_at < first_locked_focus, (first_extra_focus, inhibit_at, first_locked_focus)


def test_match_herdr_not_shophawk():
    herdr = {"address": "0x1", "class": "org.omarchy.herdr", "title": "omarchy: master", "initialClass": "org.omarchy.herdr"}
    panel = {"address": "0x2", "class": "org.quickshell", "title": "Shophawk Control", "initialClass": "org.quickshell"}
    used = set()
    a = geom.match_client({"name": "ShopHawk Herdr", "exec": "/home/caleb/.local/bin/herdr-shophawk"}, [herdr, panel], used)
    assert a and a["address"] == "0x1"
    used.add("0x1")
    b = geom.match_client({"name": "Shophawk Control", "exec": "/home/caleb/.local/bin/shophawk-panel"}, [herdr, panel], used)
    assert b and b["address"] == "0x2"


if __name__ == "__main__":
    test_layout_metrics_scale()
    test_geom_pixels()
    test_box_to_geom()
    test_lock_plan_and_assignment()
    test_close_enough_and_fallback()
    test_column_width_frac()
    test_restore_resizes_locked_pane()
    test_match_herdr_not_shophawk()
    print("geom.test.py ok")
