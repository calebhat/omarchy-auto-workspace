#!/bin/bash
# Browser reuse stays on the assignment workspace; unique apps match anywhere.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(sed -n '/^find_existing_addr()/,/^}/p' "$ROOT/workscape.sh")"
eval "$(sed -n '/^browser_reuse_only_on_target()/,/^}/p' "$ROOT/workscape.sh")"

clients='[
  {"address":"0x1","class":"brave-browser","title":"Job Entry","initialClass":"brave-browser","workspace":{"id":7,"name":"7"}},
  {"address":"0x2","class":"brave-browser","title":"Job Entry","initialClass":"brave-browser","workspace":{"id":1,"name":"1"}},
  {"address":"0x3","class":"grok-bot","title":"Grok Bot","initialClass":"grok-bot","workspace":{"id":4,"name":"4"}},
  {"address":"0x4","class":"brave-outlook.office.com__mail_-Default","title":"Outlook","initialClass":"brave-outlook.office.com__mail_-Default","workspace":{"id":4,"name":"4"}},
  {"address":"0x5","class":"foot","title":"grok","initialClass":"foot","workspace":{"id":6,"name":"6"}}
]'

got=$(find_existing_addr "/home/user/.local/bin/brave" "Brave" "$clients" "1" "")
[[ $got == "0x2" ]] || { echo "brave on assigned ws: $got"; exit 1; }

got=$(find_existing_addr "/home/user/.local/bin/brave" "Brave" "$clients" "3" "")
[[ -z $got ]] || { echo "brave stole extra: $got"; exit 1; }

got=$(find_existing_addr "/home/user/.local/bin/grok-bot" "Grok Bot" "$clients" "3" "")
[[ $got == "0x3" ]] || { echo "grok unique off-target: $got"; exit 1; }

got=$(find_existing_addr "/home/user/.local/bin/grok-bot" "Grok Bot" "$clients" "3" "0x3")
[[ -z $got ]] || { echo "grok used-addr leaked: $got"; exit 1; }

got=$(find_existing_addr "omarchy-launch-webapp 'https://outlook.office.com/mail/'" "Outlook" "$clients" "4" "")
[[ $got == "0x4" ]] || { echo "outlook on target: $got"; exit 1; }

got=$(find_existing_addr "omarchy-launch-webapp 'https://outlook.office.com/mail/'" "Outlook" "$clients" "3" "")
[[ -z $got ]] || { echo "outlook stole: $got"; exit 1; }

got=$(find_existing_addr "outlook-mail" "Outlook" "$clients" "1" "")
[[ -z $got ]] || { echo "outlook-mail matched tabbed brave: $got"; exit 1; }

got=$(find_existing_addr "outlook-mail" "Outlook" "$clients" "4" "")
[[ $got == "0x4" ]] || { echo "outlook-mail missed site app: $got"; exit 1; }

prot=$(browser_reuse_only_on_target "outlook-mail")
[[ $prot == "true" ]] || { echo "outlook-mail not protected: $prot"; exit 1; }

prot=$(browser_reuse_only_on_target "/home/user/.local/bin/brave")
[[ $prot == "true" ]] || { echo "brave not protected: $prot"; exit 1; }
prot=$(browser_reuse_only_on_target "/home/user/.local/bin/grok-bot")
[[ $prot == "false" ]] || { echo "grok should move: $prot"; exit 1; }
prot=$(browser_reuse_only_on_target "foot")
[[ $prot == "true" ]] || { echo "foot not protected: $prot"; exit 1; }

got=$(find_existing_addr "foot" "Foot" "$clients" "6" "")
[[ $got == "0x5" ]] || { echo "foot on target: $got"; exit 1; }
got=$(find_existing_addr "foot" "Foot" "$clients" "3" "")
[[ -z $got ]] || { echo "foot stole off-target: $got"; exit 1; }
prot=$(browser_reuse_only_on_target "omarchy-launch-webapp 'https://outlook.office.com/mail/'")
[[ $prot == "true" ]] || { echo "webapp not protected: $prot"; exit 1; }

echo "reuse.test.sh ok"
