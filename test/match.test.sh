#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MATCH="$ROOT/scripts/match"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/config.json" <<'JSON'
{
  "monitors": [
    { "id": "laptop", "label": "Laptop", "serial": "", "description": "BOE NE135A1M-NY1", "name": "eDP-1" },
    { "id": "desk-left", "label": "Desk left", "serial": "", "description": "HP Inc. HP E24 G5 CNK436071M", "name": "DVI-I-1" },
    { "id": "desk-right", "label": "Desk right", "serial": "", "description": "HP Inc. HP E24 G5 CNK436070F", "name": "DVI-I-2" }
  ],
  "profiles": [
    {
      "id": "desk-dock",
      "name": "Desk dock",
      "matchMode": "exact",
      "monitors": ["laptop", "desk-left", "desk-right"],
      "workspaceMonitors": { "1": "desk-left", "2": "desk-right", "9": "laptop" }
    },
    {
      "id": "laptop",
      "name": "Laptop",
      "matchMode": "exact",
      "monitors": ["laptop"],
      "workspaceMonitors": {}
    }
  ]
}
JSON

cat >"$TMP/live-laptop.json" <<'JSON'
[{ "name": "eDP-1", "description": "BOE NE135A1M-NY1", "serial": "", "disabled": false }]
JSON

# Connector names flipped vs the saved name field — must still match descriptions.
cat >"$TMP/live-desk.json" <<'JSON'
[
  { "name": "eDP-1", "description": "BOE NE135A1M-NY1", "serial": "", "disabled": false },
  { "name": "DVI-I-1", "description": "HP Inc. HP E24 G5 CNK436070F", "serial": "", "disabled": false },
  { "name": "DVI-I-2", "description": "HP Inc. HP E24 G5 CNK436071M", "serial": "", "disabled": false }
]
JSON

laptop_id=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-laptop.json" --print-id)
desk_id=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk.json" --print-id)
[[ $laptop_id == "laptop" ]]
[[ $desk_id == "desk-dock" ]]

bindings=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk.json" --profile-id desk-dock --bindings)
left=$(printf '%s' "$bindings" | jq -r '.["1"]')
right=$(printf '%s' "$bindings" | jq -r '.["2"]')
lap=$(printf '%s' "$bindings" | jq -r '.["9"]')
[[ $left == "DVI-I-2" ]]
[[ $right == "DVI-I-1" ]]
[[ $lap == "eDP-1" ]]

cat >"$TMP/live-desk-lid.json" <<'JSON'
[
  { "name": "eDP-1", "description": "BOE NE135A1M-NY1", "serial": "", "disabled": true },
  { "name": "DVI-I-1", "description": "HP Inc. HP E24 G5 CNK436070F", "serial": "", "disabled": false },
  { "name": "DVI-I-2", "description": "HP Inc. HP E24 G5 CNK436071M", "serial": "", "disabled": false }
]
JSON
lid_id=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk-lid.json" --print-id)
[[ $lid_id == "desk-dock" ]]

cat >"$TMP/net-config.json" <<'JSON'
{
  "monitors": [
    { "id": "laptop", "label": "Laptop", "serial": "", "description": "BOE NE135A1M-NY1", "name": "eDP-1" }
  ],
  "profiles": [
    { "id": "home", "name": "Home", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": ["Hataj"], "subnets": ["192.168.1.0/24"], "connections": [] }, "claimedAt": 1 },
    { "id": "office", "name": "Office", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": ["Office"], "subnets": ["192.168.2.0/24"], "connections": [] }, "claimedAt": 2 },
    { "id": "any", "name": "Any", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": [], "subnets": [], "connections": [] }, "claimedAt": 0 }
  ]
}
JSON
cat >"$TMP/net-home.json" <<'JSON'
{ "ssid": "Hataj", "subnet": "192.168.1.0/24", "connection": "Hataj" }
JSON
cat >"$TMP/net-cafe.json" <<'JSON'
{ "ssid": "Cafe", "subnet": "10.1.1.0/24", "connection": "" }
JSON
home_id=$(python3 "$MATCH" --config "$TMP/net-config.json" --live-json "$TMP/live-laptop.json" --network-json "$TMP/net-home.json" --print-id)
cafe_id=$(python3 "$MATCH" --config "$TMP/net-config.json" --live-json "$TMP/live-laptop.json" --network-json "$TMP/net-cafe.json" --print-id)
[[ $home_id == "home" ]]
[[ $cafe_id == "any" ]]
needs=$(python3 "$MATCH" --config "$TMP/net-config.json" --live-json "$TMP/live-laptop.json" --needs-identity)
# net-config has unconstrained "any" for laptop, so no wait required
[[ $needs == "no" ]]
cat >"$TMP/net-only.json" <<'JSON'
{
  "monitors": [
    { "id": "laptop", "label": "Laptop", "serial": "", "description": "BOE NE135A1M-NY1", "name": "eDP-1" }
  ],
  "profiles": [
    { "id": "home", "name": "Home", "matchMode": "exact", "monitors": ["laptop"], "network": { "ssids": ["Hataj"], "subnets": [], "connections": [] } }
  ]
}
JSON
needs_only=$(python3 "$MATCH" --config "$TMP/net-only.json" --live-json "$TMP/live-laptop.json" --needs-identity)
[[ $needs_only == "yes" ]]
lid_bind=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk-lid.json" --profile-id desk-dock --bindings)
[[ $(printf '%s' "$lid_bind" | jq -r '.["9"]') == "null" ]]

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
assert m.disable_plan(["eDP-1"], ["eDP-1"]) == []
assert m.disable_plan(["eDP-1", "DVI-I-1"], ["eDP-1"]) == ["eDP-1"]
assert m.disable_plan(["eDP-1", "DVI-I-1"], ["eDP-1", "DVI-I-1"]) == ["eDP-1"]
assert m.safe_connector("eDP-1") == "eDP-1"
assert m.safe_connector("eDP-1; rm -rf /") is None
s = m.SAFE
assert s.safe_ws("3") == "3"
assert s.safe_ws("20") == "20"
assert s.safe_ws("21") is None
assert s.safe_ws('1"}); os.execute("id")') is None
assert s.safe_addr("0xabc") == "0xabc"
assert s.safe_addr("5602fd5c9090") == "0x5602fd5c9090"
assert s.safe_addr('0x1"}); os.execute("id")') is None
assert abs(s.clamp_scale("2") - 2.0) < 1e-9
assert s.clamp_scale("1}); x") == 1.0
print("disable_plan ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {"2": "DVI-I-1"}
m.subprocess.run = lambda *a, **k: calls.append(a)
profile = {
    "workspacePrefs": {"2": {"layout": "dwindle", "visibleCount": 2, "lockSizes": False, "extras": "block"}},
    "assignments": [{"workspace": 2, "exec": "herdr", "lockPlace": True}],
    "workspaceMonitors": {"2": "desk-right"},
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"scrolling\"" in lua, lua
assert "fullscreen_on_one_column = true" in lua, lua
assert "follow_focus = false" in lua, lua
print("lock forces scrolling ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
profile = {
    "assignments": [{"workspace": 1, "exec": "brave"}, {"workspace": 2, "exec": "herdr"}],
    "workspacePrefs": {"1": {"layout": "stage"}, "5": {"layout": "stage"}, "8": {"layout": "scrolling"}},
    "overflow": {"enabled": False, "workspaces": [5, 6, 7], "maxWindows": 2},
}
assert m.assigned_workspaces(profile) == {"1", "2"}
assert m.overflow_active_workspaces(profile) == set()
profile["overflow"]["enabled"] = True
assert m.overflow_active_workspaces(profile) == {"5", "6", "7"}
calls = []
m.subprocess.run = lambda *a, **k: calls.append(a[0] if a else [])
m.SAFE.lua_str = lambda s: s
out = m.reset_empty_workspaces({"profiles": [profile]}, profile)
assert "5" in out["overflowKept"]
assert "8" in out["cleared"]
assert "1" not in out["cleared"]
assert "5" not in (profile.get("workspacePrefs") or {}) or profile["workspacePrefs"]["5"]["layout"] == "stage"
assert "8" not in profile.get("workspacePrefs", {})
print("reset empty keeps overflow, clears leftovers ok")
PY

python3 - <<'PY'
import json, subprocess, tempfile, os
from pathlib import Path
cfg = {
  "profiles": [{
    "id": "p",
    "assignments": [{"workspace": 2, "exec": "herdr"}],
    "workspacePrefs": {"2": {"layout": "scrolling"}, "5": {"layout": "stage"}, "8": {"layout": "scrolling"}},
    "workspaceMonitors": {"2": "laptop", "9": "laptop"}
  }]
}
# jq used by close_preset_workspaces
raw = json.dumps(cfg)
import subprocess as sp
out = sp.check_output(["jq", "-r", '--arg', "id", "p", '[.profiles[]? | select(.id==$id) | .assignments[]? | .workspace | tostring] | unique | .[]'], input=raw, text=True)
got = set(out.split())
assert got == {"2"}, got
print("fresh close only assigned workspaces ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {"1": "DVI-I-2"}
m.subprocess.run = lambda *a, **k: calls.append(a)
profile = {
    "workspacePrefs": {"1": {"layout": "master", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 1, "exec": "brave", "lockPlace": False}],
    "workspaceMonitors": {"1": "desk-left"},
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"master\"" in lua, lua
assert "orientation = \"left\"" in lua, lua
assert "column_width" not in lua, lua
print("master layout rule ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {"5": "DVI-I-2"}
m.subprocess.run = lambda *a, **k: calls.append(a)
profile = {
    "workspacePrefs": {"5": {"layout": "stage", "visibleCount": 3, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 5, "exec": "foot", "lockPlace": False}],
    "workspaceMonitors": {"5": "desk-left"},
}
out = m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert out["workspaces"][0]["layout"] == "stage", out
assert "layout = \"scrolling\"" in lua, lua
assert "fullscreen_on_one_column = true" in lua, lua
assert "follow_focus = false" in lua, lua
assert "column_width = 0.3333" in lua, lua
assert "orientation" not in lua, lua
print("stage layout rule ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {}
m.subprocess.run = lambda *a, **k: calls.append(a)
profile = {
    "workspacePrefs": {"3": {"layout": "scrolling", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 3, "exec": "grok-bot", "lockPlace": True}],
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "fullscreen_on_one_column = true" in lua, lua
assert "follow_focus = false" in lua, lua
print("single locked window fills ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {}
m.subprocess.run = lambda *a, **k: calls.append(a)
profile = {
    "workspacePrefs": {"2": {"layout": "scrolling", "visibleCount": 2, "lockSizes": False, "extras": "around"}},
    "assignments": [
        {"workspace": 2, "exec": "herdr", "lockPlace": True},
        {"workspace": 2, "exec": "shophawk-panel", "lockPlace": True},
    ],
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "fullscreen_on_one_column = false" in lua, lua
assert "follow_focus = false" in lua, lua
print("multi locked split keeps fill off ok")
PY

python3 - "$MATCH" <<'PY'
from importlib.machinery import SourceFileLoader
import sys
m = SourceFileLoader("match", sys.argv[1]).load_module()
calls = []
m.safe_connector = lambda n: n or ""
m.workspace_bindings = lambda cfg, profile, live: {}
m.subprocess.run = lambda *a, **k: calls.append(a)
profile = {
    "workspacePrefs": {"1": {"layout": "set-width", "visibleCount": 4, "lockSizes": False, "extras": "around"}},
    "assignments": [{"workspace": 1, "exec": "foot", "lockPlace": False}],
}
m.apply_ws_prefs({"monitors": []}, profile, [])
lua = " ".join(str(c) for c in calls)
assert "layout = \"scrolling\"" in lua, lua
assert "fullscreen_on_one_column = false" in lua, lua
assert "column_width = 0.25" in lua, lua
assert "scrolling_width = 0.25" in lua, lua
print("set-width spawn rule ok")
PY

echo "match.test.sh ok"
