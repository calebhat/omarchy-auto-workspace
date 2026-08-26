#!/bin/bash
# I-042: Fresh must take apply.lock before closing windows; a held lock
# must not close anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/workscape.sh"

python3 - "$SH" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index("cmd_fresh_apply()")
end = text.index("\ncmd_launch_all")
body = text[start:end]
assert "reexec_apply_detached" in body, "fresh must detach from the panel Process"
assert "acquire_apply_lock" in body, "fresh must take apply.lock"
assert body.index("acquire_apply_lock") < body.index("close_preset_workspaces"), body
assert body.index("reexec_apply_detached") < body.index("close_preset_workspaces")
print("fresh locks before close ok")
PY

notify() { :; }
STATE_DIR=$(mktemp -d)
trap 'rm -rf "$STATE_DIR"' EXIT
# shellcheck disable=SC1091
eval "$(sed -n '/^acquire_apply_lock()/,/^}/p' "$SH")"
exec 8>"$STATE_DIR/apply.lock"
flock -n 8
if acquire_apply_lock; then
  echo "acquire_apply_lock took a held lock"
  exit 1
fi
echo "held apply.lock refuses second acquire ok"

python3 - "$SH" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index("apply_bindings()")
end = text.index("\nprofile_assignments")
body = text[start:end]
assert "bind_workspace_to_monitor" in body
assert "already has windows" not in body, body
assert "WORKSCAPE_MIGRATE_OCCUPIED" in text
assert "profile changed" in text
print("apply matching rebinds occupied pins ok")
PY
