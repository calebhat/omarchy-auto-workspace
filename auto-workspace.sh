#!/bin/bash
set -uo pipefail

PLUGIN_ID="io.github.calebhat.auto-workspace"
# Config lives OUTSIDE the plugin dir: the shell watches the plugin folder and
# reloads the whole plugin on any file change there, which would close the
# panel and restart the service on every settings save.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/auto-workspace"
CONFIG_FILE="$STATE_DIR/config.json"
LEGACY_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/tenzin.auto-workspace/config.json"
STATE_FILE="$STATE_DIR/state.json"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATCH="$PLUGIN_DIR/scripts/match"
GEOM="$PLUGIN_DIR/scripts/geom"

mkdir -p "$STATE_DIR"

migrate_config() {
  if [[ ! -f $CONFIG_FILE && -f $LEGACY_CONFIG_FILE ]]; then
    cp "$LEGACY_CONFIG_FILE" "$CONFIG_FILE" 2>/dev/null || true
  fi
}

default_config() {
  cat <<'JSON'
{
  "version": 2,
  "settings": {
    "enabled": true,
    "applyOnBoot": false,
    "launchDelayMs": 800,
    "staggerMs": 80,
    "silent": true,
    "onlyOnBoot": true,
    "lastFormWorkspace": 1,
    "activeProfileId": "default"
  },
  "monitors": [],
  "extraApps": [],
  "profiles": [
    {
      "id": "default",
      "name": "Default",
      "matchMode": "exact",
      "monitors": [],
      "workspaceMonitors": {},
      "assignments": []
    }
  ]
}
JSON
}

ensure_config() {
  migrate_config
  if [[ ! -f $CONFIG_FILE ]]; then
    default_config >"$CONFIG_FILE"
  fi
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)" 2>/dev/null || true
    default_config >"$CONFIG_FILE"
  fi
}

cmd_ensure_config() {
  ensure_config
  cat "$CONFIG_FILE"
}

live_monitors_json() {
  hyprctl -j monitors 2>/dev/null || echo "[]"
}

cmd_live_status() {
  ensure_config
  live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --status
}

cmd_match_id() {
  ensure_config
  live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --print-id
}

notify() {
  local title=$1 body=$2
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Auto Workspace" "$title" "$body" >/dev/null 2>&1 || true
  fi
}

bind_workspace_to_monitor() {
  local ws=$1 name=$2
  [[ -n $ws && -n $name ]] || return 0
  hyprctl keyword workspace "$ws,monitor:$name,persistent:true" >/dev/null 2>&1 || true
  local lua
  lua=$(printf 'hl.dispatch(hl.dsp.workspace.move({workspace="%s", monitor="%s"}))' "$ws" "$name")
  hyprctl eval "$lua" >/dev/null 2>&1 \
    || hyprctl dispatch moveworkspacetomonitor "$ws" "$name" >/dev/null 2>&1 \
    || true
}

# geom JSON {x,y,w,h} is 0–1 of the workspace's *layout* area (backend pixels / scale).
apply_window_geom() {
  local addr=$1 geom_json=$2 ws=$3
  [[ -n $addr && -n $geom_json && $geom_json != "null" ]] || return 0
  python3 "$GEOM" --apply-one --addr "$addr" --geom "$geom_json" --workspace "$ws" || true
}

apply_profile_geoms() {
  local profile_id=$1
  python3 "$GEOM" --apply-config --config "$CONFIG_FILE" --profile-id "$profile_id" || true
}

apply_bindings() {
  local bindings_json=$1
  [[ -n $bindings_json && $bindings_json != "{}" && $bindings_json != "null" ]] || return 0
  python3 -c '
import json, sys
b = json.loads(sys.argv[1])
for ws, name in b.items():
    if ws and name:
        print(f"{ws}\t{name}")
' "$bindings_json" | while IFS=$'\t' read -r ws name; do
    bind_workspace_to_monitor "$ws" "$name"
    echo "bound workspace $ws → $name"
  done
}

profile_assignments() {
  local profile_id=$1
  if jq -e '.profiles' "$CONFIG_FILE" >/dev/null 2>&1; then
    jq -c --arg id "$profile_id" '
      (.profiles // [] | map(select(.id == $id)) | .[0].assignments // [])
      | sort_by(.geom.z // 0)[]?
    ' "$CONFIG_FILE" 2>/dev/null
  else
    jq -c '.assignments[]?' "$CONFIG_FILE" 2>/dev/null
  fi
}

cmd_list_apps() {
  # List .desktop apps: Name | Exec | Icon | IconPath | File | Score
  # Score = rough frecency from shell histories + recently-used.xbel, so the
  # panel can show commonly used apps first. IconPath lets the UI render
  # real icons instead of glyphs.
  local seen=""
  local -A seen_desk
  local -A seen_name
  # Extra / TUI apps that are not .desktop files (Herdr, custom extras).
  ensure_config
  local extra_line extra_name extra_exec extra_icon
  while IFS= read -r extra_line; do
    [[ -n $extra_line ]] || continue
    extra_name=$(printf '%s' "$extra_line" | jq -r '.name')
    extra_exec=$(printf '%s' "$extra_line" | jq -r '.exec // .command')
    extra_icon=$(printf '%s' "$extra_line" | jq -r '.icon // empty')
    [[ -n $extra_name && -n $extra_exec ]] || continue
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$extra_name" "$extra_exec" "${extra_icon:-utilities-terminal}" "" "extra" "9999"
    seen+="|$extra_exec|"
    seen_name["${extra_name,,}"]=1
  done < <(jq -c '.extraApps[]?' "$CONFIG_FILE" 2>/dev/null)

  local herdr_cmd=""
  if command -v herdr-shophawk >/dev/null 2>&1; then
    herdr_cmd="$(command -v herdr-shophawk)"
  elif [[ -x $HOME/.local/bin/herdr-shophawk ]]; then
    herdr_cmd="$HOME/.local/bin/herdr-shophawk"
  elif command -v herdr >/dev/null 2>&1; then
    herdr_cmd="omarchy-launch-or-focus-tui --app-id=org.omarchy.herdr herdr --session shophawk"
  fi
  if [[ -n $herdr_cmd && $seen != *"|$herdr_cmd|"* ]]; then
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "ShopHawk Herdr" "$herdr_cmd" "utilities-terminal" "" "extra-herdr" "10000"
    seen+="|$herdr_cmd|"
    seen_name["shophawk herdr"]=1
  fi

  # Skip walking the icon themes here — the panel resolves Icon= via Quickshell.
  local hist_txt="" h
  for h in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.local/share/fish/fish_history"; do
    [[ -f $h ]] || continue
    hist_txt+="$(cat "$h" 2>/dev/null)"
    hist_txt+="\n"
  done
  local -A tok_count
  local token count
  while read -r token count; do
    [[ -n $token ]] && tok_count["$token"]="$count"
  done < <(awk '{ for (i=1; i<=NF && i<=2; i++) { if ($i ~ /^[a-zA-Z0-9_.+-]+$/ && $i !~ /^[0-9:-]+$/) print tolower($i) } }' < <(printf "%b" "$hist_txt") | sort | uniq -c | awk '{ print $2, $1 }')
  local -A xbel_count
  while read -r count path; do
    [[ -n $path ]] && xbel_count["$path"]="$count"
  done < <(grep -oE 'file://[^"]+\.desktop' "$HOME/.local/share/recently-used.xbel" 2>/dev/null | sed 's#file://##' | sort | uniq -c | awk '{ print $2, $1 }')
  for dir in "$HOME/.local/share/applications" "/usr/share/applications" "/var/lib/flatpak/exports/share/applications" "$HOME/.local/share/flatpak/exports/share/applications"; do
    [[ -d $dir ]] || continue
    while IFS= read -r -d '' file; do
      local name="" exec_line="" icon="" hidden="" nodisplay=""
      name=$(grep -m1 "^Name=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      exec_line=$(grep -m1 "^Exec=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      icon=$(grep -m1 "^Icon=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      hidden=$(grep -m1 "^Hidden=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      nodisplay=$(grep -m1 "^NoDisplay=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      [[ $hidden == "true" || $nodisplay == "true" ]] && continue
      [[ -z $name || -z $exec_line ]] && continue
      local icon_path=""
      if [[ -n $icon && $icon == /* && -f $icon ]]; then
        icon_path="$icon"
      fi
      exec_line=$(echo "$exec_line" | sed -E 's/ \%[UuFfDdNnickvm]//g' | xargs)
      [[ -z $exec_line ]] && continue
      local desk_base="${file##*/}"
      desk_base="${desk_base,,}"
      local name_key="${name,,}"
      if [[ -n ${seen_desk[$desk_base]:-} ]]; then continue; fi
      if [[ -n ${seen_name[$name_key]:-} ]]; then continue; fi
      if [[ $seen == *"|$exec_line|"* ]]; then continue; fi
      seen_desk["$desk_base"]=1
      seen_name["$name_key"]=1
      seen+="|$exec_line|"
      local base="${exec_line%% *}"
      local appname="${base##*/}"
      local score=0
      local base_l="${base,,}" appname_l="${appname,,}" nfirst_l="${name%% *}" domain_l=""
      nfirst_l="${nfirst_l,,}"
      [[ -n ${tok_count[$base_l]:-} ]] && score=$((score + tok_count["$base_l"]))
      [[ -n ${tok_count[$appname_l]:-} ]] && score=$((score + tok_count["$appname_l"]))
      [[ -n ${tok_count[$nfirst_l]:-} ]] && score=$((score + tok_count["$nfirst_l"]))
      if [[ $exec_line == omarchy-launch-webapp* ]]; then
        local url="${exec_line#*\'}"; url="${url%%\'*}"
        if [[ $url == http* ]]; then
          domain_l=$(echo "$url" | sed -E 's#^[a-z]+://([^/:]+).*#\1#' | sed -E 's/^www\.//')
          domain_l="${domain_l%%.*}"
          domain_l="${domain_l,,}"
          [[ -n ${tok_count[$domain_l]:-} ]] && score=$((score + tok_count["$domain_l"]))
        fi
      fi
      [[ -n ${xbel_count[$file]:-} ]] && score=$((score + xbel_count["$file"]))
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$name" "$exec_line" "$icon" "$icon_path" "$file" "$score"
    done < <(find "$dir" -maxdepth 1 -name "*.desktop" -print0 2>/dev/null)
  done
}

cmd_status() {
  ensure_config
  local count enabled_count profile_count
  count=$(jq '[.profiles[]?.assignments[]?] | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  enabled_count=$(jq '[.profiles[]?.assignments[]? | select(.enabled==true)] | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  profile_count=$(jq '.profiles | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  local enabled apply_on_boot
  enabled=$(jq -r '.settings.enabled // true' "$CONFIG_FILE" 2>/dev/null)
  apply_on_boot=$(jq -r '.settings.applyOnBoot // false' "$CONFIG_FILE" 2>/dev/null)
  cat <<EOF
{
  "configFile": "$CONFIG_FILE",
  "total": $count,
  "enabled": $enabled_count,
  "profiles": $profile_count,
  "pluginEnabled": $enabled,
  "applyOnBoot": $apply_on_boot,
  "exists": true
}
EOF
}

wait_for_hyprland() {
  local timeout=20 tries=0
  while ! hyprctl -j version >/dev/null 2>&1; do
    tries=$((tries + 1))
    if ((tries >= timeout)); then
      echo "hyprctl not ready after ${timeout}s, aborting launch" >&2
      return 1
    fi
    sleep 1
  done
  return 0
}

cmd_launch() {
  local workspace="$1"
  local exec_cmd="$2"
  local silent="${3:-true}"
  local geom_json="${4:-}"
  if [[ -z $workspace || -z $exec_cmd ]]; then
    echo "usage: $0 --launch <workspace> <exec> [silent] [geom-json]" >&2
    exit 1
  fi
  if ! [[ $workspace =~ ^[0-9]+$ ]] && ! [[ $workspace =~ ^special: ]]; then
    echo "invalid workspace: $workspace" >&2
    exit 1
  fi
  local prefix="[workspace $workspace"
  if [[ $silent == "true" ]]; then
    prefix+=" silent]"
  else
    prefix+="]"
  fi
  local final_cmd="$exec_cmd"
  local base_for_tui
  base_for_tui=$(printf '%s' "$exec_cmd" | awk '{print $1}' | xargs basename 2>/dev/null)
  case "$base_for_tui" in
    nvim|vim|vi|nano|helix|hx|emacs|micro|btop|htop|yazi|ranger|lf|herdr)
      if [[ $exec_cmd != omarchy-launch-tui* && $exec_cmd != omarchy-launch-or-focus-tui* && $exec_cmd != *herdr-shophawk* ]]; then
        local tui_args="${exec_cmd#"$base_for_tui"}"
        tui_args=$(printf '%s' "$tui_args" | sed 's/^ *//')
        if [[ -n $tui_args ]]; then
          final_cmd="omarchy-launch-tui --app-id=org.omarchy.$base_for_tui $base_for_tui $tui_args"
        else
          final_cmd="omarchy-launch-tui --app-id=org.omarchy.$base_for_tui $base_for_tui"
        fi
      fi
      ;;
    *)
      if [[ $exec_cmd != uwsm-app* && $exec_cmd != omarchy-launch* && $exec_cmd != "chromium"* && $exec_cmd != "google-chrome"* && $exec_cmd != "firefox"* ]]; then
        if [[ $exec_cmd =~ ^[a-zA-Z0-9._-]+$ || $exec_cmd =~ ^[a-zA-Z0-9._-]+[[:space:]] ]]; then
          final_cmd="uwsm-app -- $exec_cmd"
        fi
      fi
      ;;
  esac
  local dispatch_cmd="$prefix $final_cmd"
  local lua_escaped
  lua_escaped=$(printf '%s' "$dispatch_cmd" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  local is_browser_like="false"
  local is_tui_like="false"
  if [[ $final_cmd == *"chromium"* || $final_cmd == *"chrome"* || $final_cmd == *"omarchy-launch-webapp"* ]]; then
    is_browser_like="true"
  fi
  case "$base_for_tui" in
    nvim|vim|vi|nano|helix|hx|emacs|micro|btop|htop|yazi|ranger|lf|herdr) is_tui_like="true" ;;
  esac

  local before
  before=$(hyprctl clients -j 2>/dev/null | jq -r '.[].address' 2>/dev/null | sort -u | tr '\n' ' ')

  if ! hyprctl eval "hl.exec_cmd(\"$lua_escaped\")" >/dev/null 2>&1 \
    && ! hyprctl eval "hl.dsp.exec_cmd(\"$lua_escaped\")" >/dev/null 2>&1 \
    && ! hyprctl dispatch exec "$dispatch_cmd" >/dev/null 2>&1; then
    echo "failed to execute launch command on workspace $workspace: $final_cmd" >&2
    return 1
  fi

  local target_ws="$workspace"
  local ok=false
  local tries=12
  local placed_addrs=()
  local clients_json
  for _try in $(seq 1 $tries); do
    local new_addrs moved=0
    clients_json=$(hyprctl clients -j 2>/dev/null || echo "[]")
    new_addrs=$(printf '%s' "$clients_json" | jq -r --arg before "$before" '
      ($before | split(" ") | map(select(length>0))) as $old |
      [.[].address] | map(select(. as $a | ($old | index($a) | not))) | .[]
    ' 2>/dev/null)
    if [[ -n $new_addrs ]]; then
      while IFS= read -r addr; do
        [[ -z $addr ]] && continue
        local cls on_ws
        cls=$(printf '%s' "$clients_json" | jq -r --arg a "$addr" '.[] | select(.address==$a) | .class // empty' 2>/dev/null)
        if [[ $is_browser_like == "true" ]]; then
          if ! [[ $cls =~ chrome|chromium ]] && ! [[ ${cls,,} =~ chrome|chromium ]]; then
            continue
          fi
        elif [[ $is_tui_like == "true" ]]; then
          if ! [[ $cls =~ foot|org\.omarchy|herdr ]] && ! [[ ${cls,,} =~ foot|nvim|herdr ]]; then
            continue
          fi
        fi
        on_ws=$(printf '%s' "$clients_json" | jq -r --arg a "$addr" --arg ws "$target_ws" '
          def ws_ok($ws):
            if ($ws|test("^[0-9]+$")) then
              (.workspace.id == ($ws|tonumber) or .workspace.name == $ws)
            else
              .workspace.name == $ws
            end;
          .[] | select(.address == $a) | if ws_ok($ws) then "true" else "false" end
        ' 2>/dev/null)
        if [[ $on_ws != "true" ]]; then
          hyprctl eval "hl.dispatch(hl.dsp.window.move({workspace=\"$target_ws\", window=\"address:$addr\", follow=false}))" >/dev/null 2>&1 \
            || true
        fi
        moved=$((moved + 1))
        placed_addrs+=("$addr")
      done <<< "$new_addrs"
      if ((moved > 0)); then
        ok=true
        break
      fi
    fi
    sleep 0.08
  done
  # Geometry is applied in a second pass after every assignment has launched.

  if [[ $ok != "true" ]]; then
    echo "warn: no new window detected for workspace $workspace: $final_cmd (may have reused existing window)" >&2
  fi
  return 0
}

default_only_on_boot_for_type() {
  local type="${1:-app}"
  if [[ $type == "app" ]]; then
    echo "false"
  else
    echo "true"
  fi
}

already_running() {
  local ws=$1 exec_cmd=$2 name=$3 clients_json=$4
  local needle=""
  needle=$(printf '%s' "$exec_cmd" | awk '{print $1}' | xargs basename 2>/dev/null)
  needle=$(basename "$needle" 2>/dev/null || echo "$needle")
  local app_id=""
  if [[ $exec_cmd =~ --app-id=([^[:space:]]+) ]]; then
    app_id="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$clients_json" | jq -e --arg ws "$ws" --arg n "${needle,,}" --arg appid "${app_id,,}" --arg name "${name,,}" --arg exec "${exec_cmd,,}" '
    def ws_ok($ws):
      if ($ws|test("^[0-9]+$")) then
        (.workspace.id == ($ws|tonumber) or .workspace.name == $ws)
      else
        .workspace.name == $ws
      end;
    def hay: ((.class // "") + " " + (.initialClass // "") + " " + (.title // "") | ascii_downcase);
    any(.[];
      ws_ok($ws) and (
        ($appid != "" and hay | contains($appid)) or
        ($n != "" and $n != "." and (hay | contains($n))) or
        ($name != "" and (hay | contains($name))) or
        (($exec | contains("herdr")) and (hay | contains("herdr"))) or
        (($exec | contains("shophawk-panel")) and (hay | contains("shophawk")))
      )
    )
  ' >/dev/null 2>&1
}

launch_profile_assignments() {
  local profile_id=$1
  local force=${2:-false}

  local only_on_boot_global boot_id last_boot_file last_boot stagger silent
  only_on_boot_global=$(jq -r '.settings.onlyOnBoot // true' "$CONFIG_FILE")
  boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "unknown")
  last_boot_file="$STATE_DIR/last_boot_id"
  last_boot=""
  [[ -f $last_boot_file ]] && last_boot=$(cat "$last_boot_file" 2>/dev/null || echo "")
  stagger=$(jq -r '.settings.staggerMs // 80' "$CONFIG_FILE")
  silent=$(jq -r '.settings.silent // true' "$CONFIG_FILE")
  local clients_json
  clients_json=$(hyprctl clients -j 2>/dev/null || echo "[]")

  local boot_log="$STATE_DIR/launch-$boot_id.log"
  : > "$boot_log" 2>/dev/null || true
  echo "$(date -u) boot_id=$boot_id profile=$profile_id force=$force" >> "$boot_log" 2>/dev/null || true

  local idx=0 item
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    local ws exec_cmd name type
    ws=$(echo "$item" | jq -r '.workspace')
    exec_cmd=$(echo "$item" | jq -r '.exec // .command // empty')
    name=$(echo "$item" | jq -r '.name // empty')
    type=$(echo "$item" | jq -r '.type // "app"')
    local enabled
    enabled=$(echo "$item" | jq -r '.enabled // true')
    if [[ $enabled != "true" ]]; then
      continue
    fi
    if [[ -z $ws || -z $exec_cmd ]]; then
      echo "skip invalid item: $item" >&2
      continue
    fi

    local item_only
    item_only=$(echo "$item" | jq -r 'if has("onlyOnBoot") then .onlyOnBoot else empty end')
    if [[ -z $item_only || $item_only == "null" ]]; then
      item_only=$(default_only_on_boot_for_type "$type")
      [[ -z $item_only ]] && item_only="$only_on_boot_global"
    fi
    if [[ $item_only == "1" ]]; then item_only="true"; fi
    if [[ $item_only == "0" ]]; then item_only="false"; fi
    if [[ $item_only == "true" && $force != "true" && -n $last_boot && $last_boot == "$boot_id" ]]; then
      echo "skip $name on ws $ws — already launched this boot (once per boot)"
      continue
    fi

    if already_running "$ws" "$exec_cmd" "$name" "$clients_json"; then
      echo "skip $name on ws $ws — already running"
      continue
    fi

    echo "launching [$ws] $name: $exec_cmd (silent=$silent)"
    echo "$(date -u) START ws=$ws name=$name exec=$exec_cmd" >> "$boot_log" 2>/dev/null || true
    if ((idx > 0)) && [[ $stagger -gt 0 ]]; then
      sleep "$(awk "BEGIN {print $stagger/1000}")"
    fi
    local geom_json
    geom_json=$(echo "$item" | jq -c '.geom // empty')
    if cmd_launch "$ws" "$exec_cmd" "$silent" "$geom_json"; then
      echo "$(date -u) OK ws=$ws name=$name" >> "$boot_log" 2>/dev/null || true
    else
      echo "$(date -u) FAIL ws=$ws name=$name" >> "$boot_log" 2>/dev/null || true
      echo "failed to launch $name" >&2
    fi
    idx=$((idx + 1))
  done < <(profile_assignments "$profile_id")

  echo "applying window geometry for $profile_id"
  apply_profile_geoms "$profile_id"

  echo "$boot_id" > "$last_boot_file"
  echo "done"
}

cmd_apply() {
  local mode=$1
  local requested_id=${2:-}
  local force=${3:-false}
  mkdir -p "$STATE_DIR"
  exec 9>"$STATE_DIR/apply.lock"
  if ! flock -n 9; then
    echo "apply already in progress"
    exit 0
  fi
  ensure_config
  wait_for_hyprland || exit 1

  local enabled
  enabled=$(jq -r '.settings.enabled // true' "$CONFIG_FILE")
  if [[ $enabled != "true" && $force != "true" && $mode == "boot" ]]; then
    echo "plugin disabled, skipping (use --force to override)" >&2
    exit 0
  fi

  if [[ $mode == "boot" ]]; then
    local apply_on_boot
    apply_on_boot=$(jq -r '.settings.applyOnBoot // false' "$CONFIG_FILE")
    if [[ $apply_on_boot != "true" && $force != "true" ]]; then
      echo "apply on boot disabled — use hotkey or Apply now"
      exit 0
    fi
  fi

  local status_json profile_id profile_name bindings
  status_json=$(cmd_live_status)
  if [[ -n $requested_id ]]; then
    profile_id=$requested_id
    profile_name=$(jq -r --arg id "$profile_id" '([.profiles[]? | select(.id==$id) | .name][0] // $id)' "$CONFIG_FILE")
    bindings=$(live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --bindings)
  else
    profile_id=$(printf '%s' "$status_json" | jq -r '.matchedProfileId // empty')
    profile_name=$(printf '%s' "$status_json" | jq -r '.matchedProfileName // empty')
    bindings=$(printf '%s' "$status_json" | jq -c '.bindings // {}')
  fi

  if [[ -z $profile_id || $profile_id == "null" ]]; then
    echo "no matching profile for the current monitor layout"
    notify "Auto Workspace" "No profile matches the current monitors"
    exit 0
  fi

  echo "applying profile $profile_name ($profile_id)"
  apply_bindings "$bindings"
  # Hotkey still bypasses "once per boot", but never relaunches a window
  # that is already on the workspace (duplicate Apply was stacking apps).
  local launch_force=$force
  if [[ $mode == "hotkey" ]]; then
    launch_force=true
  fi
  launch_profile_assignments "$profile_id" "$launch_force"
  notify "Auto Workspace" "Applied $profile_name"
}

cmd_launch_all() {
  local force="${1:-false}"
  cmd_apply boot "" "$force"
}

case "${1:-}" in
  --ensure-config) cmd_ensure_config ;;
  --list-apps) cmd_list_apps ;;
  --status) cmd_status ;;
  --live-status) cmd_live_status ;;
  --match-id) cmd_match_id ;;
  --launch) shift; cmd_launch "$@" ;;
  --launch-all) shift; cmd_launch_all "${1:-false}" ;;
  --force-launch-all) cmd_launch_all "true" ;;
  --apply-matching) cmd_apply hotkey "" true ;;
  --apply-profile) cmd_apply hotkey "${2:-}" true ;;
  --default-config) default_config ;;
  --help|-h|"") cat <<'HELP'
auto-workspace.sh — helper for io.github.calebhat.auto-workspace

  --ensure-config              ensure config exists and print it
  --list-apps                  list .desktop + extra apps as TSV
  --status                     json status
  --live-status                current monitors + matching profile
  --match-id                   print matching profile id
  --launch <ws> <exec> [silent]  launch single app on workspace
  --launch-all                 boot path (no-op unless applyOnBoot)
  --force-launch-all           launch matching profile regardless of boot flag
  --apply-matching             detect layout, bind workspaces, launch apps
  --apply-profile <id>         bind + launch a specific profile
  --default-config             print default config
HELP
  ;;
  *) echo "unknown arg: $1" >&2; exit 1 ;;
esac
