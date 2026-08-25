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
    stage_profile = {
        "workspacePrefs": {"1": {"layout": "stage", "visibleCount": 2, "extras": "around"}},
        "assignments": [{"workspace": 1, "exec": "brave", "lockPlace": False}],
    }
    sp = geom.lock_plan_for_workspace(stage_profile, "1")
    assert sp["stage"] is True
    assert len(sp["locked"]) == 1
    assert sp["locked"][0]["geom"]["w"] == 1.0


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
    assert "fullscreen_on_one_column = false" in geom.scrolling_layout_opts(2, lock=False)
    assert "fullscreen_on_one_column = true" in geom.scrolling_layout_opts(2, stage=True)
    assert "follow_focus = false" in geom.scrolling_layout_opts(2, lock=True)
    assert "follow_focus = false" in geom.scrolling_layout_opts(2, stage=True)
    assert "fullscreen_on_one_column = true" in geom.scrolling_layout_opts(2, lock=True, fill_one=True)
    assert "column_width = 0.3333" in geom.scrolling_layout_opts(3)
    assert "column_width = 0.25" in geom.scrolling_layout_opts(4)
    assert "fullscreen_on_one_column = false" in geom.scrolling_layout_opts(4, fill_one=False)


def test_push_column_after_locked():
    calls = []
    ranks = {"0xL0": 0, "0xL1": 2, "0x3": 1}
    orig = (
        geom.hypr_eval,
        geom.cache_clear,
        geom.stacked_with_other,
        geom.column_collapsed,
        geom.column_rank,
        geom.focus_window,
        geom.layout_msg,
    )
    geom.hypr_eval = lambda lua: calls.append(lua)
    geom.cache_clear = lambda: None
    geom.stacked_with_other = lambda *a, **k: False
    geom.column_collapsed = lambda *a, **k: False
    def layout_msg(msg):
        calls.append(msg)
        if msg == "swapcol r":
            ranks["0x3"] = 3
    geom.column_rank = lambda addr, ws: ranks.get(addr)
    geom.focus_window = lambda addr: calls.append(f"focus {addr}")
    geom.layout_msg = layout_msg
    try:
        geom.push_column_after_locked("0x3", "2", {"0xL0", "0xL1"})
        assert "swapcol r" in calls
    finally:
        (
            geom.hypr_eval,
            geom.cache_clear,
            geom.stacked_with_other,
            geom.column_collapsed,
            geom.column_rank,
            geom.focus_window,
            geom.layout_msg,
        ) = orig


def test_fit_column_fracs_keeps_columns_on_screen():
    orig_out, orig_in, orig_b = geom.gaps_out, geom.gaps_in, geom.border_size
    geom.gaps_out = lambda: (8, 8, 8, 8)
    geom.gaps_in = lambda: (4, 4, 4, 4)
    geom.border_size = lambda: 2
    try:
        metrics = {"lw": 1440.0, "w": 1424.0}
        raw = [0.6764, 0.3236]
        out = geom.fit_column_fracs(raw, metrics, 2)
        assert out[0] > out[1]
        assert abs(out[0] / out[1] - raw[0] / raw[1]) < 0.02
        px = sum(f * metrics["lw"] for f in out)
        between = 4 + 4
        assert px + between <= metrics["w"] + 2
        assert px >= metrics["w"] * 0.95
    finally:
        geom.gaps_out, geom.gaps_in, geom.border_size = orig_out, orig_in, orig_b


def test_force_scrolling_not_persistent_by_default():
    calls = []
    orig = geom.hypr_eval
    geom.hypr_eval = lambda lua: calls.append(lua)
    try:
        geom.force_scrolling("3", visible_count=2, lock=False, stage=True)
        assert calls, "expected workspace_rule"
        lua = calls[0]
        assert "persistent = false" in lua
        assert "layout = \"scrolling\"" in lua
        assert "fullscreen_on_one_column = true" in lua
        calls.clear()
        geom.force_scrolling("2", visible_count=2, lock=True, persist=True)
        assert "persistent = true" in calls[0]
    finally:
        geom.hypr_eval = orig


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


def test_apply_config_skips_occupied(monkeypatch=None):
    orig_env = geom.os.environ.get("WORKSCAPE_OCCUPIED_WS")
    calls = []
    geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = "2 8"
    orig_hypr_j = geom.hypr_j
    orig_apply_items = geom.apply_items
    geom.hypr_j = lambda cmd, cached=False: [
        {
            "address": "0xabc",
            "class": "herdr",
            "title": "herdr",
            "initialClass": "herdr",
            "workspace": {"id": 2, "name": "2"},
            "at": [8, 34],
            "size": [700, 900],
        }
    ] if cmd == "clients" else []
    geom.apply_items = lambda *a, **k: calls.append(a) or []
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
                "workspacePrefs": {"2": {"layout": "scrolling"}},
            }],
        }
        import tempfile, json, os
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh)
        try:
            result = geom.apply_config(path, "p")
        finally:
            os.unlink(path)
        assert result.get("ok") is True
        assert calls == []
    finally:
        geom.hypr_j = orig_hypr_j
        geom.apply_items = orig_apply_items
        if orig_env is None:
            geom.os.environ.pop("WORKSCAPE_OCCUPIED_WS", None)
        else:
            geom.os.environ["WORKSCAPE_OCCUPIED_WS"] = orig_env


def test_apply_items_scrolling_vs_stacked_rows():
    metrics = {"x": 8, "y": 34, "w": 1424, "h": 918, "scale": 2}
    items = [
        {"addr": "0x1", "geom": {"x": 0, "y": 0, "w": 1, "h": 0.5}, "px": {"x": 8, "y": 34, "w": 1424, "h": 459}},
        {"addr": "0x2", "geom": {"x": 0, "y": 0.5, "w": 1, "h": 0.5}, "px": {"x": 8, "y": 493, "w": 1424, "h": 459}},
    ]
    boxes = {
        "0x1": {"x": 8, "y": 34, "w": 1424, "h": 900},
        "0x2": {"x": 8, "y": 34, "w": 1424, "h": 18},
    }
    axes = []
    orig_force = geom.force_tiled
    orig_box = geom.actual_box
    orig_resize = geom.resize_relative
    orig_swap = geom.swap_windows
    orig_scroll = geom.workspace_is_scrolling
    orig_place = geom.place_scrolling_columns
    geom.force_tiled = lambda addr: None
    geom.actual_box = lambda addr: dict(boxes[addr])
    geom.resize_relative = lambda addr, dx, dy: axes.append(("resize", addr, dx, dy))
    geom.swap_windows = lambda a, b: axes.append(("swap", a, b))
    geom.workspace_is_scrolling = lambda ws, workspaces=None: False
    geom.place_scrolling_columns = lambda *a, **k: axes.append(("scroll", a, k)) or items
    try:
        geom.apply_items(items, metrics, ws="7")
        assert any(c[0] == "resize" and c[3] != 0 for c in axes), axes
        assert not any(c[0] == "scroll" for c in axes)
        axes.clear()
        geom.workspace_is_scrolling = lambda ws, workspaces=None: True
        geom.apply_items(
            [
                {"addr": "0x1", "geom": {"x": 0, "y": 0, "w": 0.5, "h": 1}, "px": {"x": 8, "y": 34, "w": 712, "h": 918}},
                {"addr": "0x2", "geom": {"x": 0.5, "y": 0, "w": 0.5, "h": 1}, "px": {"x": 720, "y": 34, "w": 712, "h": 918}},
            ],
            metrics,
            ws="6",
        )
        assert any(c[0] == "scroll" for c in axes), axes
    finally:
        geom.force_tiled = orig_force
        geom.actual_box = orig_box
        geom.resize_relative = orig_resize
        geom.swap_windows = orig_swap
        geom.workspace_is_scrolling = orig_scroll
        geom.place_scrolling_columns = orig_place


def test_geom_pixels_master_stack():
    metrics = {"x": 8, "y": 34, "w": 1000, "h": 900, "scale": 1}
    left = geom.geom_pixels({"x": 0, "y": 0, "w": 0.55, "h": 1}, metrics)
    top = geom.geom_pixels({"x": 0.55, "y": 0, "w": 0.45, "h": 0.5}, metrics)
    bot = geom.geom_pixels({"x": 0.55, "y": 0.5, "w": 0.45, "h": 0.5}, metrics)
    assert left["x"] == 8
    assert top["x"] == 8 + 550
    assert bot["y"] == 34 + 450
    assert top["h"] + bot["h"] == 900
    assert left["w"] + top["w"] == 1000


def test_match_herdr_not_shophawk():
    herdr = {"address": "0x1", "class": "org.omarchy.herdr", "title": "omarchy: master", "initialClass": "org.omarchy.herdr"}
    panel = {"address": "0x2", "class": "org.quickshell", "title": "Shophawk Control", "initialClass": "org.quickshell"}
    used = set()
    a = geom.match_client({"name": "ShopHawk Herdr", "exec": "/home/caleb/.local/bin/herdr-shophawk"}, [herdr, panel], used)
    assert a and a["address"] == "0x1"
    used.add("0x1")
    b = geom.match_client({"name": "Shophawk Control", "exec": "/home/caleb/.local/bin/shophawk-panel"}, [herdr, panel], used)
    assert b and b["address"] == "0x2"


def test_match_outlook_prefers_full_pane():
    extra = {
        "address": "0xnew",
        "class": "brave-outlook.office.com__mail_-Default",
        "title": "Message",
        "at": [740, 36],
        "size": [704, 914],
    }
    main = {
        "address": "0xmain",
        "class": "brave-outlook.office.com__mail_-Default",
        "title": "Mail - Outlook",
        "at": [10, 36],
        "size": [1420, 914],
    }
    a = {"name": "Outlook", "exec": "omarchy-launch-webapp 'https://outlook.office.com/mail/'"}
    hit = geom.match_client(a, [extra, main], set())
    assert hit and hit["address"] == "0xmain", hit


if __name__ == "__main__":
    test_layout_metrics_scale()
    test_geom_pixels()
    test_box_to_geom()
    test_lock_plan_and_assignment()
    test_close_enough_and_fallback()
    test_column_width_frac()
    test_push_column_after_locked()
    test_fit_column_fracs_keeps_columns_on_screen()
    test_force_scrolling_not_persistent_by_default()
    test_restore_resizes_locked_pane()
    test_apply_config_skips_occupied()
    test_apply_items_scrolling_vs_stacked_rows()
    test_geom_pixels_master_stack()
    test_match_herdr_not_shophawk()
    test_match_outlook_prefers_full_pane()
    print("geom.test.py ok")
