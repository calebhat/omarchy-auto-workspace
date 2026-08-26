-- WorkScape tape layout (lua:workscape).
-- Places locked columns at planned monitor fractions, extras after them at
-- extraFrac. Recalculate owns geometry — no swapcol/colresize packing.
-- Never iterate HL.Window userdata (pairs/unknown fields SIGABRT).

Workscape = Workscape or {
  plans = {},
  offsets = {},
  extraIds = {},
  fresh = {},
  justMapped = {},
  ignoreFollowUntil = 0,
}

local function field(obj, key)
  if obj == nil then
    return nil
  end
  local ok, val = pcall(function()
    return obj[key]
  end)
  if ok then
    return val
  end
  return nil
end

local function lower(s)
  return string.lower(tostring(s or ""))
end

local function workspace_id(target)
  local win = field(target, "window")
  if win == nil then
    return ""
  end
  local ws = field(win, "workspace")
  if ws == nil then
    return ""
  end
  local id = field(ws, "id")
  if id ~= nil and tostring(id) ~= "" then
    return tostring(id)
  end
  local name = field(ws, "name")
  if name ~= nil then
    return tostring(name)
  end
  return ""
end

local function win_id(win)
  if win == nil then
    return ""
  end
  local sid = field(win, "stable_id")
  if sid ~= nil and tostring(sid) ~= "" then
    return "s" .. tostring(sid)
  end
  return tostring(field(win, "address") or "")
end

local function matches_spec(win, spec)
  if win == nil or type(spec) ~= "table" then
    return false
  end
  local addr = tostring(field(win, "address") or "")
  local spec_addr = tostring(spec.address or "")
  if spec_addr ~= "" and addr ~= "" and addr == spec_addr then
    return true
  end
  local cls = lower(field(win, "class") or field(win, "initial_class") or "")
  local spec_cls = lower(spec.class or "")
  if spec_cls == "" or cls == "" then
    return false
  end
  return cls == spec_cls
    or string.find(cls, spec_cls, 1, true) ~= nil
    or string.find(spec_cls, cls, 1, true) ~= nil
end

local function fallback_columns(ctx)
  local n = #ctx.targets
  if n == 0 then
    return
  end
  for i, target in ipairs(ctx.targets) do
    target:place(ctx:column(i, n))
  end
end

local function plan_for(ctx)
  local ws = ""
  if ctx.targets[1] then
    ws = workspace_id(ctx.targets[1])
  end
  if ws == "" then
    return nil, ""
  end
  local plan = Workscape.plans[ws] or Workscape.plans[tostring(ws)]
  local as_num = tonumber(ws)
  if type(plan) ~= "table" and as_num ~= nil then
    plan = Workscape.plans[as_num]
  end
  if type(plan) ~= "table" then
    return nil, ws
  end
  return plan, ws
end

local function build_order(ctx, plan, ws)
  local used = {}
  local locked = {}
  local specs = plan.locked
  if type(specs) ~= "table" then
    specs = {}
  end
  for _, spec in ipairs(specs) do
    for i, target in ipairs(ctx.targets) do
      if not used[i] then
        local win = field(target, "window")
        if matches_spec(win, spec) then
          used[i] = true
          local frac = tonumber(spec.w) or 0.5
          if frac < 0.08 then
            frac = 0.08
          end
          if frac > 0.98 then
            frac = 0.98
          end
          table.insert(locked, { target = target, frac = frac, locked = true })
          break
        end
      end
    end
  end
  local extra_frac = tonumber(plan.extraFrac) or 0.3333
  if extra_frac < 0.08 then
    extra_frac = 0.08
  end
  if extra_frac > 0.98 then
    extra_frac = 0.98
  end
  local present = {}
  local unmatched = {}
  for i, target in ipairs(ctx.targets) do
    if not used[i] then
      local id = win_id(field(target, "window"))
      if id == "" then
        id = "i" .. tostring(i)
      end
      present[id] = target
      table.insert(unmatched, { id = id, target = target })
    end
  end
  Workscape.extraIds[ws] = Workscape.extraIds[ws] or {}
  local kept = {}
  local seen = {}
  for _, id in ipairs(Workscape.extraIds[ws]) do
    if present[id] and not seen[id] then
      table.insert(kept, id)
      seen[id] = true
    end
  end
  for _, item in ipairs(unmatched) do
    if not seen[item.id] then
      table.insert(kept, item.id)
      seen[item.id] = true
    end
  end
  Workscape.extraIds[ws] = kept
  local extras = {}
  for _, id in ipairs(kept) do
    local target = present[id]
    if target then
      table.insert(extras, { target = target, frac = extra_frac, locked = false })
    end
  end
  return locked, extras, extra_frac
end

local function num(v)
  v = tonumber(v)
  return v
end

local function win_box(win)
  if win == nil then
    return nil
  end
  local at = field(win, "at")
  local size = field(win, "size")
  local x, y, w, h
  if type(at) == "table" then
    x = num(at.x or at[1])
    y = num(at.y or at[2])
  else
    x = num(at)
  end
  if type(size) == "table" then
    w = num(size.x or size.w or size[1])
    h = num(size.y or size.h or size[2])
  else
    w = num(size)
  end
  if x == nil or y == nil or w == nil or h == nil then
    return nil
  end
  return { x = x, y = y, w = w, h = h }
end

local function warp_cursor_to_window(win)
  local box = win_box(win)
  if not box or box.w < 8 or box.h < 8 then
    return
  end
  local cx = box.x + box.w / 2
  local cy = box.y + box.h / 2
  pcall(function()
    hl.dispatch(hl.dsp.cursor.move({ x = cx, y = cy }))
  end)
end

local function is_locked_spec(win, plan)
  if type(plan) ~= "table" or type(plan.locked) ~= "table" then
    return false
  end
  for _, spec in ipairs(plan.locked) do
    if matches_spec(win, spec) then
      return true
    end
  end
  return false
end

local function first_locked_address(plan)
  if type(plan) ~= "table" or type(plan.locked) ~= "table" then
    return ""
  end
  for _, spec in ipairs(plan.locked) do
    local addr = tostring(spec.address or "")
    if addr ~= "" then
      return addr
    end
  end
  return ""
end

local function col_is_active(col)
  local win = field(col.target, "window")
  if win == nil then
    return false
  end
  return field(win, "active") == true
end

local function place_tape(ctx, locked, extras, extra_frac, ws)
  local area = ctx.area
  if type(area) ~= "table" then
    fallback_columns(ctx)
    return
  end
  local order = {}
  for _, col in ipairs(locked) do
    table.insert(order, col)
  end
  for _, col in ipairs(extras) do
    table.insert(order, col)
  end
  if #order == 0 then
    fallback_columns(ctx)
    return
  end
  local widths = {}
  local total = 0
  for i, col in ipairs(order) do
    local w = col.frac * area.w
    if #extras == 0 and i == #order then
      w = math.max(80, area.w - total)
    end
    if w < 80 then
      w = 80
    end
    widths[i] = w
    total = total + w
  end
  local max_off = math.max(0, total - area.w)
  local off = tonumber(Workscape.offsets[ws]) or 0
  local active_i = nil
  for i, col in ipairs(order) do
    if col_is_active(col) then
      active_i = i
      break
    end
  end
  if active_i ~= nil then
    local tape_x = 0
    for i = 1, active_i - 1 do
      tape_x = tape_x + widths[i]
    end
    local w = widths[active_i]
    local vis_left = tape_x - off
    local vis_right = vis_left + w
    if vis_left < 0 then
      off = tape_x
    elseif vis_right > area.w then
      off = tape_x + w - area.w
    end
  end
  if off < 0 then
    off = 0
  end
  if off > max_off then
    off = max_off
  end
  Workscape.offsets[ws] = off
  local x = area.x - off
  for i, col in ipairs(order) do
    col.target:place({ x = x, y = area.y, w = widths[i], h = area.h })
    x = x + widths[i]
  end
end

local function recalculate(ctx)
  local n = #ctx.targets
  if n == 0 then
    return
  end
  local plan, ws = plan_for(ctx)
  if type(plan) ~= "table" or type(plan.locked) ~= "table" or #plan.locked == 0 then
    fallback_columns(ctx)
    return
  end
  local locked, extras, extra_frac = build_order(ctx, plan, ws)
  if #locked == 0 then
    fallback_columns(ctx)
    return
  end
  place_tape(ctx, locked, extras, extra_frac, ws)
end

local function layout_msg(ctx, msg)
  local command = tostring(msg or ""):match("^(%S+)") or ""
  local plan, ws = plan_for(ctx)
  local area = ctx.area
  local step = 0
  if type(area) == "table" then
    local extra = 0.3333
    if type(plan) == "table" then
      extra = tonumber(plan.extraFrac) or extra
    end
    step = extra * area.w
  end
  if command == "move" then
    local arg = tostring(msg or ""):match("^%S+%s+(%S+)") or ""
    local off = tonumber(Workscape.offsets[ws]) or 0
    if arg == "l" or arg == "-col" or arg == "-1" or arg == "left" then
      Workscape.offsets[ws] = off - step
    elseif arg == "r" or arg == "+col" or arg == "+1" or arg == "right" then
      Workscape.offsets[ws] = off + step
    else
      return "workscape: move l/r"
    end
    return true
  end
  if command == "reset" then
    Workscape.offsets[ws] = 0
    return true
  end
  if command == "fit" or command == "refit" or command == "follow" or command == "fit_into_view" then
    return true
  end
  if command == "inhibit_scroll" then
    return true
  end
  return true
end

pcall(function()
  local function tape_move(msg)
    local ws = hl.get_active_workspace()
    if not ws then
      return
    end
    local layout = tostring(ws.tiled_layout or "")
    if layout == "lua:workscape" then
      hl.dispatch(hl.dsp.layout(msg))
    end
  end
  hl.bind("SUPER + ALT + comma", function()
    tape_move("move l")
  end)
  hl.bind("SUPER + ALT + period", function()
    tape_move("move r")
  end)
end)

-- Camera pans on Super+arrows, not on hover (I-040). Was Omarchy
-- "Focus on left/right/above/below window".
pcall(function()
  local function focus_and_pan(dir)
    hl.dispatch(hl.dsp.focus({ direction = dir }))
    local ws = hl.get_active_workspace()
    if ws == nil then
      return
    end
    local layout = tostring(field(ws, "tiled_layout") or "")
    -- Scrolling has fit_into_view, not follow. Sending follow paints Hyprland's
    -- on-screen Lua error overlay even inside pcall (I-047).
    if layout == "scrolling" then
      -- fit_into_view alone keeps a leftover sliver "in view" and does not
      -- pan (I-048). Step the camera with the focus, then snug.
      if dir == "l" then
        hl.dispatch(hl.dsp.layout("move -col"))
      elseif dir == "r" then
        hl.dispatch(hl.dsp.layout("move +col"))
      end
      hl.dispatch(hl.dsp.layout("fit_into_view"))
    elseif layout == "lua:workscape" then
      hl.dispatch(hl.dsp.layout("follow"))
    end
  end
  hl.unbind("SUPER + LEFT")
  hl.unbind("SUPER + RIGHT")
  hl.unbind("SUPER + UP")
  hl.unbind("SUPER + DOWN")
  o.bind("SUPER + LEFT", "Focus on left window", function()
    focus_and_pan("l")
  end)
  o.bind("SUPER + RIGHT", "Focus on right window", function()
    focus_and_pan("r")
  end)
  o.bind("SUPER + UP", "Focus on above window", function()
    focus_and_pan("u")
  end)
  o.bind("SUPER + DOWN", "Focus on below window", function()
    focus_and_pan("d")
  end)
end)

-- SUPER+J is dwindle togglesplit. Scrolling / lua:workscape have no such
-- layoutmsg and Hyprland paints an on-screen Lua error if we send it.
pcall(function()
  hl.unbind("SUPER + J")
  o.bind("SUPER + J", "Toggle window split", function()
    local ws = hl.get_active_workspace()
    if ws == nil then
      return
    end
    local layout = tostring(field(ws, "tiled_layout") or "")
    if layout ~= "dwindle" then
      return
    end
    hl.dispatch(hl.dsp.layout("togglesplit"))
  end)
end)

pcall(function()
  hl.on("window.open", function(w)
    if w == nil then
      return
    end
    local addr = tostring(field(w, "address") or "")
    if addr ~= "" then
      Workscape.justMapped[addr] = os.clock()
    end
    -- First extra on the tape often maps off-screen with the pointer still
    -- on a locked pane (I-036). Allow follow/warp even right after Super+2.
    local ws = field(w, "workspace")
    if ws == nil then
      return
    end
    local layout = tostring(field(ws, "tiled_layout") or "")
    if layout ~= "lua:workscape" then
      return
    end
    local id = tostring(field(ws, "id") or field(ws, "name") or "")
    local plan = Workscape.plans[id] or Workscape.plans[tostring(id)]
    if is_locked_spec(w, plan) then
      return
    end
    local active = hl.get_active_workspace()
    if active == nil or tostring(field(active, "id") or "") ~= id then
      return
    end
    Workscape.ignoreFollowUntil = 0
    pcall(function()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
    end)
    pcall(function()
      hl.dispatch(hl.dsp.layout("follow"))
    end)
  end)
end)

pcall(function()
  hl.on("workspace.active", function(ws)
    if ws == nil then
      return
    end
    local layout = tostring(field(ws, "tiled_layout") or "")
    if layout ~= "lua:workscape" then
      return
    end
    local id = tostring(field(ws, "id") or field(ws, "name") or "")
    Workscape.ignoreFollowUntil = os.clock() + 0.28
    local plan = Workscape.plans[id] or Workscape.plans[tostring(id)]
    local fresh = Workscape.fresh[id] or Workscape.fresh[tostring(id)]
    if fresh then
      Workscape.fresh[id] = false
      Workscape.fresh[tostring(id)] = false
      Workscape.offsets[id] = 0
      local addr = first_locked_address(plan)
      if addr ~= "" then
        pcall(function()
          hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
        end)
      end
      pcall(function()
        hl.dispatch(hl.dsp.layout("reset"))
      end)
      return
    end
    local win = hl.get_active_window()
    local wsid = ""
    if win ~= nil then
      local wws = field(win, "workspace")
      wsid = tostring(field(wws, "id") or "")
    end
    if wsid ~= id then
      local addr = first_locked_address(plan)
      if addr ~= "" then
        pcall(function()
          hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
        end)
      end
    end
  end)
end)

pcall(function()
  hl.on("window.active", function(w)
    if w == nil then
      return
    end
    if os.clock() < (tonumber(Workscape.ignoreFollowUntil) or 0) then
      return
    end
    local ws = field(w, "workspace")
    if ws == nil then
      return
    end
    local layout = tostring(field(ws, "tiled_layout") or "")
    if layout ~= "lua:workscape" then
      return
    end
    local active = hl.get_active_workspace()
    if active == nil then
      return
    end
    local id = tostring(field(ws, "id") or "")
    if tostring(field(active, "id") or "") ~= id then
      return
    end
    -- Hover must not pan (I-040). Only a newly mapped extra.
    local addr = tostring(field(w, "address") or "")
    local mapped_at = Workscape.justMapped[addr]
    if not mapped_at or os.clock() - mapped_at >= 1.2 then
      return
    end
    Workscape.justMapped[addr] = nil
    local plan = Workscape.plans[id]
    if is_locked_spec(w, plan) then
      return
    end
    hl.dispatch(hl.dsp.layout("follow"))
    warp_cursor_to_window(w)
  end)
end)

pcall(function()
  hl.layout.register("workscape", {
    recalculate = function(ctx)
      local ok = pcall(recalculate, ctx)
      if not ok then
        pcall(fallback_columns, ctx)
      end
    end,
    layout_msg = function(ctx, msg)
      local ok, result = pcall(layout_msg, ctx, msg)
      if not ok then
        return true
      end
      return result
    end,
  })
end)
