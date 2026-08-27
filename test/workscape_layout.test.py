#!/usr/bin/env python3
from pathlib import Path

LUA = Path(__file__).resolve().parent.parent / "hypr" / "workscape-binds.lua"


def test_super_j_only_togglesplit_on_dwindle():
    text = LUA.read_text()
    assert 'hl.unbind("SUPER + J")' in text
    assert 'layout("togglesplit")' in text
    assert 'layout ~= "dwindle"' in text
    assert "no such layoutmsg" in text or "scrolling has no such layoutmsg" in text


def test_arrow_focus_uses_layout_on_scrolling():
    text = LUA.read_text()
    assert "SUPER + LEFT" in text
    assert 'tiled_layout() == "scrolling"' in text
    assert 'layout("focus l")' in text
    assert 'dsp.focus({ direction = "l" })' in text
    assert "0.46" not in text
    assert "lua:workscape" not in text
    assert "hl.layout.register" not in text


if __name__ == "__main__":
    test_super_j_only_togglesplit_on_dwindle()
    test_arrow_focus_uses_layout_on_scrolling()
    print("workscape_layout.test.py ok")
