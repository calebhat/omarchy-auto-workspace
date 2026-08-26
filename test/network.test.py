#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
from pathlib import Path

n = SourceFileLoader("workscape_network", str(Path(__file__).resolve().parent.parent / "scripts/network")).load_module()


def test_normalize_and_match():
    live = {"ssid": "HomeNet", "subnet": "192.168.1.0/24", "connection": "HomeNet"}
    captured = n.capture_from_live(live)
    assert captured["ssids"] == ["HomeNet"]
    assert n.network_matches(captured, live)["matches"] is True
    assert n.network_matches(captured, {"ssid": "Office", "subnet": "192.168.2.0/24"})["matches"] is False
    assert n.network_matches(n.empty_network(), live) == {"constrained": False, "matches": True}


def test_overlap_and_claim():
    home = {"ssids": ["HomeNet"], "subnets": ["192.168.1.0/24"], "connections": []}
    office = {"ssids": ["Office"], "subnets": ["192.168.2.0/24"], "connections": []}
    assert n.networks_overlap(home, {"ssids": ["homenet"], "subnets": [], "connections": []})
    assert not n.networks_overlap(home, office)
    assert n.networks_overlap(n.empty_network(), n.empty_network())
    assert not n.networks_overlap(home, n.empty_network())
    cfg = {
        "profiles": [
            {"id": "home", "name": "Home", "monitors": ["laptop"], "network": home},
            {"id": "office", "name": "Office", "monitors": ["laptop"], "network": office},
        ]
    }
    claimed = n.claim_environment(cfg, "office", home)
    assert any(s["id"] == "home" for s in claimed["stolen"])
    home_after = next(p for p in claimed["config"]["profiles"] if p["id"] == "home")
    assert "HomeNet" not in home_after["network"]["ssids"]


if __name__ == "__main__":
    test_normalize_and_match()
    test_overlap_and_claim()
    print("network.test.py ok")
