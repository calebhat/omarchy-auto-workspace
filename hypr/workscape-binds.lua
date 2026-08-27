-- WorkScape bind overlay. Does not register a layout.
-- Super+Left/Right on scrolling stay on this workspace (Omarchy
-- dsp.focus({direction}) jumps to the next monitor — I-049).
-- SUPER+J is dwindle togglesplit only; scrolling has no such layoutmsg.

pcall(function()
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

  local function tiled_layout()
    local ws = hl.get_active_workspace()
    if ws == nil then
      return ""
    end
    return tostring(field(ws, "tiled_layout") or "")
  end

  hl.unbind("SUPER + LEFT")
  hl.unbind("SUPER + RIGHT")
  hl.unbind("SUPER + UP")
  hl.unbind("SUPER + DOWN")
  o.bind("SUPER + LEFT", "Focus on left window", function()
    if tiled_layout() == "scrolling" then
      hl.dispatch(hl.dsp.layout("focus l"))
      return
    end
    hl.dispatch(hl.dsp.focus({ direction = "l" }))
  end)
  o.bind("SUPER + RIGHT", "Focus on right window", function()
    if tiled_layout() == "scrolling" then
      hl.dispatch(hl.dsp.layout("focus r"))
      return
    end
    hl.dispatch(hl.dsp.focus({ direction = "r" }))
  end)
  o.bind("SUPER + UP", "Focus on above window", function()
    if tiled_layout() == "scrolling" then
      hl.dispatch(hl.dsp.layout("focus u"))
      return
    end
    hl.dispatch(hl.dsp.focus({ direction = "u" }))
  end)
  o.bind("SUPER + DOWN", "Focus on below window", function()
    if tiled_layout() == "scrolling" then
      hl.dispatch(hl.dsp.layout("focus d"))
      return
    end
    hl.dispatch(hl.dsp.focus({ direction = "d" }))
  end)
end)

pcall(function()
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
