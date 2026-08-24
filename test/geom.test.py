#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader

geom = SourceFileLoader("geom", "/home/caleb/Work/omarchy-auto-workspace/scripts/geom").load_module()


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


if __name__ == "__main__":
    test_layout_metrics_scale()
    test_geom_pixels()
    print("geom.test.py ok")
