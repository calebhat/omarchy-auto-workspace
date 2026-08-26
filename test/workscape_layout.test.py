#!/usr/bin/env python3
from pathlib import Path

LUA = Path(__file__).resolve().parent.parent / "hypr" / "workscape-layout.lua"


def test_super_j_only_togglesplit_on_dwindle():
    text = LUA.read_text()
    assert 'hl.unbind("SUPER + J")' in text
    assert 'layout("togglesplit")' in text
    assert 'layout ~= "dwindle"' in text
    assert "no such layoutmsg" in text or "on-screen Lua error" in text


def test_thin_strip_warp_floor():
    text = LUA.read_text()
    assert "box.w < 8" in text
    assert "box.h < 8" in text
    assert "box.w < 40" not in text


def test_tape_extra_open_clears_ignore_follow():
    text = LUA.read_text()
    assert "I-036" in text
    assert "Workscape.ignoreFollowUntil = 0" in text
    assert 'layout("follow")' in text


def test_arrow_focus_pans_and_hover_does_not():
    text = LUA.read_text()
    assert "SUPER + LEFT" in text
    assert "fit_into_view" in text
    assert "I-040" in text


if __name__ == "__main__":
    test_super_j_only_togglesplit_on_dwindle()
    test_thin_strip_warp_floor()
    test_tape_extra_open_clears_ignore_follow()
    test_arrow_focus_pans_and_hover_does_not()
    print("workscape_layout.test.py ok")

