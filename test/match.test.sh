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
lid_bind=$(python3 "$MATCH" --config "$TMP/config.json" --live-json "$TMP/live-desk-lid.json" --profile-id desk-dock --bindings)
[[ $(printf '%s' "$lid_bind" | jq -r '.["9"]') == "null" ]]

echo "match.test.sh ok"
