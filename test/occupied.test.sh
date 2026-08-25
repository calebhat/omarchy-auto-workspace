#!/bin/bash
# Occupied-workspace skip uses the same jq + glob as workscape.sh.
set -euo pipefail
sample='[{"workspace":{"id":1}},{"workspace":{"id":8}},{"workspace":{"id":10}},{"workspace":{"id":2}}]'
occupied=$(printf '%s' "$sample" | jq -r '[.[] | (.workspace.id|tostring)] | unique | join(" ")')
has() { [[ " $occupied " == *" $1 "* ]]; }
has 1 && has 2 && has 8 && has 10 || { echo "missing id in: $occupied"; exit 1; }
if has 3; then echo "false 3"; exit 1; fi
# "1" must not match "10"
occupied10="10 8"
[[ " $occupied10 " == *" 1 "* ]] && { echo "1 matched 10"; exit 1; }
[[ " $occupied10 " == *" 10 "* ]] || { echo "10 not matched"; exit 1; }
echo "occupied.test.sh ok"
