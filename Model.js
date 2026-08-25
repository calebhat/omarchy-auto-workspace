.pragma library

// Shared helpers for WorkScape panel + service.
// Config lives outside the plugin dir so saves do not reload the plugin.

function defaultConfig() {
    return {
        version: 2,
        settings: {
            enabled: true,
            applyOnBoot: false,
            launchDelayMs: 800,
            staggerMs: 80,
            silent: true,
            onlyOnBoot: true,
            lastFormWorkspace: 1,
            activeProfileId: "default",
            gestureSource: "global",
            persistHyprGestures: false,
            gestures: defaultGestures()
        },
        monitors: [],
        extraApps: [],
        profiles: [defaultProfile()]
    }
}

function defaultProfile() {
    return {
        id: "default",
        name: "Default",
        matchMode: "exact",
        monitors: [],
        workspaceMonitors: {},
        disabledMonitors: [],
        monitorLayout: {},
        workspacePrefs: {},
        assignments: [],
        gestures: defaultGestures(),
        workspaceNames: {},
        defaultWorkspace: 0,
        persistentWorkspaces: false,
        network: emptyNetwork(),
        overflow: emptyOverflow(),
        claimedAt: 0
    }
}

function maxWorkspace() { return 20 }

function emptyOverflow() {
    return { enabled: false, workspaces: [], maxWindows: 1 }
}

function normalizeOverflow(raw) {
    var src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
    var seen = {}
    var list = []
    var arr = Array.isArray(src.workspaces) ? src.workspaces : []
    var maxWs = maxWorkspace()
    for (var i = 0; i < arr.length && list.length < maxWs; i++) {
        var n = parseInt(arr[i], 10)
        if (!(n >= 1 && n <= maxWs) || seen[n]) continue
        seen[n] = true
        list.push(n)
    }
    return {
        enabled: src.enabled === true,
        workspaces: list,
        maxWindows: clampVisibleCount(src.maxWindows != null ? src.maxWindows : 1)
    }
}

function assignedWorkspaceSet(profile) {
    var used = {}
    var list = (profile && profile.assignments) || []
    for (var i = 0; i < list.length; i++) {
        var ws = parseInt(list[i].workspace, 10)
        if (ws >= 1 && ws <= maxWorkspace()) used[ws] = true
    }
    return used
}

function unsetWorkspaces(profile) {
    var used = assignedWorkspaceSet(profile)
    var out = []
    var maxWs = maxWorkspace()
    for (var i = 1; i <= maxWs; i++) if (!used[i]) out.push(i)
    return out
}

function overflowSummary(profile) {
    var ov = normalizeOverflow(profile && profile.overflow)
    if (!ov.enabled) return "Off — extras only follow each workspace’s own send-extra toggle."
    if (!ov.workspaces.length) return "On — no workspaces in the chain yet. Use Choose… then Set Stage."
    return "On · " + ov.maxWindows + "/ws · " + ov.workspaces.join(" → ")
}

function emptyNetwork() {
    return { ssids: [], subnets: [], connections: [] }
}

function uniqueStrings(list, maxLen, maxCount) {
    var out = []
    var seen = {}
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length && out.length < maxCount; i++) {
        var s = String(list[i] || "").trim().slice(0, maxLen)
        var k = s.toLowerCase()
        if (!s || seen[k]) continue
        seen[k] = true
        out.push(s)
    }
    return out
}

function normalizeNetwork(raw) {
    var src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
    return {
        ssids: uniqueStrings(src.ssids, 64, 8),
        subnets: uniqueStrings(src.subnets, 64, 8),
        connections: uniqueStrings(src.connections, 64, 8)
    }
}

function networkConfigured(raw) {
    var n = normalizeNetwork(raw)
    return n.ssids.length + n.subnets.length + n.connections.length > 0
}

function captureNetwork(live) {
    var liveObj = live && typeof live === "object" ? live : {}
    return normalizeNetwork({
        ssids: liveObj.ssid ? [liveObj.ssid] : [],
        subnets: liveObj.subnet ? [liveObj.subnet] : [],
        connections: liveObj.connection ? [liveObj.connection] : []
    })
}

function anyNetworkHit(savedArr, liveVal) {
    if (!liveVal) return false
    var want = String(liveVal).toLowerCase()
    for (var i = 0; i < savedArr.length; i++) {
        if (String(savedArr[i]).toLowerCase() === want) return true
    }
    return false
}

function networkMatches(saved, live) {
    var n = normalizeNetwork(saved)
    if (!networkConfigured(n)) return { constrained: false, matches: true }
    if (!live || typeof live !== "object") return { constrained: true, matches: false }
    var hit = anyNetworkHit(n.ssids, live.ssid) || anyNetworkHit(n.subnets, live.subnet) || anyNetworkHit(n.connections, live.connection)
    return { constrained: true, matches: hit }
}

function networksOverlap(a, b) {
    var na = normalizeNetwork(a)
    var nb = normalizeNetwork(b)
    var ca = networkConfigured(na)
    var cb = networkConfigured(nb)
    if (!ca && !cb) return true
    if (ca !== cb) return false
    function share(left, right) {
        var other = {}
        for (var i = 0; i < right.length; i++) other[String(right[i]).toLowerCase()] = true
        for (var j = 0; j < left.length; j++) if (other[String(left[j]).toLowerCase()]) return true
        return false
    }
    return share(na.ssids, nb.ssids) || share(na.subnets, nb.subnets) || share(na.connections, nb.connections)
}

function monitorKey(profile) {
    var mons = []
    var raw = (profile && profile.monitors) ? profile.monitors : []
    for (var i = 0; i < raw.length; i++) {
        var id = String(raw[i] || "")
        if (id) mons.push(id)
    }
    mons.sort()
    return mons.join(",")
}

function subtractNetwork(fromNet, claimed) {
    var n = normalizeNetwork(fromNet)
    var c = normalizeNetwork(claimed)
    function drop(arr, other) {
        var skip = {}
        for (var i = 0; i < other.length; i++) skip[String(other[i]).toLowerCase()] = true
        var out = []
        for (var j = 0; j < arr.length; j++) if (!skip[String(arr[j]).toLowerCase()]) out.push(arr[j])
        return out
    }
    return normalizeNetwork({
        ssids: drop(n.ssids, c.ssids),
        subnets: drop(n.subnets, c.subnets),
        connections: drop(n.connections, c.connections)
    })
}

function environmentOwner(cfg, key, network, exceptId) {
    var list = (cfg && cfg.profiles) || []
    for (var i = 0; i < list.length; i++) {
        if (exceptId && list[i].id === exceptId) continue
        if (monitorKey(list[i]) !== key) continue
        if (networksOverlap(list[i].network, network)) return list[i]
    }
    return null
}

function claimEnvironment(cfg, profileId, network) {
    var out = clone(cfg)
    var net = normalizeNetwork(network)
    var stolen = []
    var prof = profileById(out, profileId)
    if (!prof) return { config: out, stolen: stolen }
    var key = monitorKey(prof)
    for (var i = 0; i < out.profiles.length; i++) {
        var p = out.profiles[i]
        if (p.id === profileId) {
            p.network = net
            p.claimedAt = Date.now()
            continue
        }
        if (monitorKey(p) !== key) continue
        if (!networksOverlap(p.network, net)) continue
        if (!networkConfigured(net) || !networkConfigured(p.network)) continue
        var next = subtractNetwork(p.network, net)
        if (JSON.stringify(next) !== JSON.stringify(normalizeNetwork(p.network))) {
            stolen.push({ id: p.id, name: p.name })
            p.network = next
        }
    }
    return { config: out, stolen: stolen }
}

function suggestedProfileName(liveMonitors) {
    var n = (liveMonitors || []).length
    return n <= 1 ? "Laptop" : ("Desk " + n + " monitors")
}

function liveNetworkSummary(live) {
    if (!live || typeof live !== "object") return "No LAN / Wi-Fi yet"
    if (live.kind === "wifi" && live.ssid)
        return "Wi-Fi " + live.ssid + (live.subnet ? " · " + live.subnet : "")
    if (live.subnet)
        return (live.kind === "ethernet" ? "Ethernet " : "") + live.subnet
    if (live.iface) return String(live.iface)
    return "No LAN / Wi-Fi yet"
}

function networkSummary(raw) {
    var n = normalizeNetwork(raw)
    if (!networkConfigured(n)) return "Any network (fallback for this layout)"
    var parts = []
    if (n.ssids.length) parts.push("Wi-Fi " + n.ssids.join(", "))
    if (n.subnets.length) parts.push(n.subnets.join(", "))
    if (n.connections.length) {
        var same = n.ssids.join(",").toLowerCase() === n.connections.join(",").toLowerCase()
        if (!same) parts.push(n.connections.join(", "))
    }
    return parts.join(" · ")
}

function splitNetworkField(s) {
    var out = []
    var raw = String(s || "").replace(/\n/g, ",")
    var parts = raw.split(",")
    for (var i = 0; i < parts.length; i++) {
        var t = String(parts[i] || "").trim()
        if (t) out.push(t)
    }
    return out
}

function parseNetworkText(ssidsText, subnetsText, connectionsText) {
    return normalizeNetwork({
        ssids: splitNetworkField(ssidsText),
        subnets: splitNetworkField(subnetsText),
        connections: splitNetworkField(connectionsText)
    })
}

function networkFieldText(raw) {
    var n = normalizeNetwork(raw)
    return {
        ssids: n.ssids.join(", "),
        subnets: n.subnets.join(", "),
        connections: n.connections.join(", ")
    }
}

function boundNetworkLine(profile, liveNet) {
    var net = profile && profile.network
    var bound = networkSummary(net)
    if (!networkConfigured(net)) return bound
    var hit = networkMatches(net, liveNet)
    if (hit.matches) return bound + " · connected now"
    var live = liveNetworkSummary(liveNet)
    if (live && live.indexOf("No LAN") !== 0) return bound + " · now " + live
    return bound
}

function matchReasonLabel(reason) {
    if (reason === "network") return "wrong network"
    if (reason === "missing") return "missing displays"
    if (reason === "extra") return "extra displays"
    if (reason === "exact" || reason === "all-present") return "matches now"
    return String(reason || "")
}

function defaultGestures() {
    return {
        workspaceSwipe: true,
        fingers: 3,
        skipEmpty: true,
        invert: true,
        createNew: false,
        forever: false,
        touch: false,
        keyboard: false,
        scratchpadSwipe: false,
        scratchpadFingers: 4
    }
}

function normalizeGestures(raw) {
    var src = raw && typeof raw === "object" ? raw : {}
    var out = defaultGestures()
    out.workspaceSwipe = src.workspaceSwipe !== false
    out.fingers = parseInt(src.fingers, 10) === 4 ? 4 : 3
    out.skipEmpty = src.skipEmpty !== false
    out.invert = src.invert !== false
    out.createNew = src.createNew === true
    out.forever = src.forever === true
    out.touch = src.touch === true
    out.keyboard = src.keyboard === true
    out.scratchpadSwipe = src.scratchpadSwipe === true
    out.scratchpadFingers = parseInt(src.scratchpadFingers, 10) === 3 ? 3 : 4
    return out
}

function normalizeWorkspaceNames(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var ws = parseInt(keys[i], 10)
        if (!(ws >= 1 && ws <= 10)) continue
        var name = String(raw[keys[i]] || "").trim().slice(0, 24)
        if (name) out[String(ws)] = name
    }
    return out
}

function layoutDescription(layout, hasLock) {
    if (layout === "stage")
        return "The first window stays full width. Extra windows are smaller columns to the right; scroll to see them. Visible sets extra-column width, not the first window."
    if (layout === "master" && !hasLock)
        return "Hyprland master: one large pane with the rest stacked beside it on the same screen. No scrolling."
    if (layout === "scrolling" || hasLock)
        return "Windows sit in a row of columns. Locked panes keep their width; extra windows use the Visible size. Focusing a column to the right can clip a wider locked pane off the left."
    return "Each new window splits the current one in half (Hyprland’s default tiling)."
}

function clampVisibleCount(n) {
    var v = parseInt(n, 10)
    if (isNaN(v)) return 2
    if (v < 1) return 1
    if (v > 20) return 20
    return v
}

function visibleCountHelp(visibleCount, hasLock) {
    var n = clampVisibleCount(visibleCount)
    if (hasLock)
        return "Extra columns are 1/" + n + " of the screen (1–20). Locked panes keep the size you set."
    return n + " extra columns (not the first, in Stage) fit on screen before you scroll. Ultrawides can go up to 20."
}

function normalizeWorkspacePref(p) {
    if (!p || typeof p !== "object") {
        return { layout: "dwindle", visibleCount: 2, lockSizes: false, extras: "around" }
    }
    var layout = p.layout
    if (layout !== "scrolling" && layout !== "master" && layout !== "stage") layout = "dwindle"
    var vis = clampVisibleCount(p.visibleCount)
    var extras = p.extras === "block" ? "block" : "around"
    return {
        layout: layout,
        visibleCount: vis,
        lockSizes: p.lockSizes === true,
        extras: extras
    }
}

function normalizeWorkspacePrefs(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var ws = parseInt(keys[i], 10)
        if (!(ws >= 1 && ws <= 10)) continue
        out[String(ws)] = normalizeWorkspacePref(raw[keys[i]])
    }
    return out
}

function workspacePref(profile, ws) {
    var map = (profile && profile.workspacePrefs) || {}
    return normalizeWorkspacePref(map[String(ws)])
}

function normalizeMonitorLayout(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var id = String(keys[i] || "").slice(0, 40)
        var p = raw[keys[i]]
        if (!id || !p || typeof p !== "object") continue
        var x = parseInt(p.x, 10)
        var y = parseInt(p.y, 10)
        if (isNaN(x)) x = 0
        if (isNaN(y)) y = 0
        out[id] = {
            x: Math.max(-20000, Math.min(20000, x)),
            y: Math.max(-20000, Math.min(20000, y))
        }
    }
    return out
}

function rectsOverlap(a, b) {
    if (!a || !b) return false
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

function spanOverlap(a0, a1, b0, b1) {
    return Math.min(a1, b1) - Math.max(a0, b0)
}

function edgesTouch(a, b, eps) {
    if (eps == null) eps = 1.5
    var yOv = spanOverlap(a.y, a.y + a.h, b.y, b.y + b.h)
    var xOv = spanOverlap(a.x, a.x + a.w, b.x, b.x + b.w)
    var flushR = Math.abs((a.x + a.w) - b.x) <= eps
    var flushL = Math.abs((b.x + b.w) - a.x) <= eps
    var flushB = Math.abs((a.y + a.h) - b.y) <= eps
    var flushT = Math.abs((b.y + b.h) - a.y) <= eps
    return ((flushR || flushL) && yOv > eps) || ((flushT || flushB) && xOv > eps)
}

function uniqueNums(vals) {
    var seen = {}, out = []
    for (var i = 0; i < vals.length; i++) {
        var n = Math.round(Number(vals[i]))
        if (seen[n]) continue
        seen[n] = true
        out.push(n)
    }
    return out
}

function compoundEdgeSlots(dragged, others) {
    var w = dragged.w, h = dragged.h
    var slots = []
    var list = others || []

    function groups(keyFn) {
        var map = {}
        for (var i = 0; i < list.length; i++) {
            var k = String(Math.round(keyFn(list[i])))
            if (!map[k]) map[k] = []
            map[k].push(list[i])
        }
        return map
    }

    function vertical(lineX, members, placeLeft) {
        if (!members || !members.length) return
        var y0 = members[0].y, y1 = members[0].y + members[0].h
        var i
        for (i = 1; i < members.length; i++) {
            y0 = Math.min(y0, members[i].y)
            y1 = Math.max(y1, members[i].y + members[i].h)
        }
        var x = placeLeft ? lineX - w : lineX
        var yMin = y0 - h + 24
        var yMax = y1 - 24
        if (yMax < yMin) {
            yMin = y0
            yMax = y1 - h
        }
        var yDrop = Math.max(yMin, Math.min(yMax, dragged.y))
        if (Math.abs(h - (y1 - y0)) <= 48) yDrop = y0
        else if (Math.abs(yDrop - y0) <= 48) yDrop = y0
        else if (Math.abs(yDrop - (y1 - h)) <= 48) yDrop = y1 - h
        slots.push({ x: x, y: yDrop })
        slots.push({ x: x, y: y0 })
        slots.push({ x: x, y: y1 - h })
    }

    function horizontal(lineY, members, placeAbove) {
        if (!members || !members.length) return
        var x0 = members[0].x, x1 = members[0].x + members[0].w
        var i
        for (i = 1; i < members.length; i++) {
            x0 = Math.min(x0, members[i].x)
            x1 = Math.max(x1, members[i].x + members[i].w)
        }
        var y = placeAbove ? lineY - h : lineY
        var xMin = x0 - w + 24
        var xMax = x1 - 24
        if (xMax < xMin) {
            xMin = x0
            xMax = x1 - w
        }
        var xDrop = Math.max(xMin, Math.min(xMax, dragged.x))
        if (Math.abs(w - (x1 - x0)) <= 48) xDrop = x0
        else if (Math.abs(xDrop - x0) <= 48) xDrop = x0
        else if (Math.abs(xDrop - (x1 - w)) <= 48) xDrop = x1 - w
        slots.push({ x: xDrop, y: y })
        slots.push({ x: x0, y: y })
        slots.push({ x: x1 - w, y: y })
    }

    var g, k
    g = groups(function(o) { return o.x })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) vertical(Number(k), g[k], true)
    g = groups(function(o) { return o.x + o.w })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) vertical(Number(k), g[k], false)
    g = groups(function(o) { return o.y })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) horizontal(Number(k), g[k], true)
    g = groups(function(o) { return o.y + o.h })
    for (k in g) if (Object.prototype.hasOwnProperty.call(g, k)) horizontal(Number(k), g[k], false)
    return slots
}

function flushSlots(dragged, o) {
    var w = dragged.w, h = dragged.h
    return [
        { x: o.x + o.w, y: o.y },
        { x: o.x + o.w, y: o.y + o.h - h },
        { x: o.x + o.w, y: o.y + (o.h - h) / 2 },
        { x: o.x - w, y: o.y },
        { x: o.x - w, y: o.y + o.h - h },
        { x: o.x - w, y: o.y + (o.h - h) / 2 },
        { x: o.x, y: o.y + o.h },
        { x: o.x + o.w - w, y: o.y + o.h },
        { x: o.x + (o.w - w) / 2, y: o.y + o.h },
        { x: o.x, y: o.y - h },
        { x: o.x + o.w - w, y: o.y - h },
        { x: o.x + (o.w - w) / 2, y: o.y - h }
    ]
}

function anyRectsOverlap(items) {
    for (var i = 0; i < items.length; i++) {
        for (var j = i + 1; j < items.length; j++) {
            if (rectsOverlap(items[i], items[j])) return true
        }
    }
    return false
}

function arrangeMonitorsAfterDrop(dragged, others) {
    var w = dragged.w, h = dragged.h
    var dropCx = dragged.x + w / 2
    var dropCy = dragged.y + h / 2
    var list = others || []
    var best = null
    var bestScore = Infinity

    function consider(positions, draggedPos) {
        if (!draggedPos) return
        var items = []
        var ids = Object.keys(positions)
        var i
        for (i = 0; i < ids.length; i++) {
            var p = positions[ids[i]]
            var src = ids[i] === dragged.id ? dragged : null
            if (!src) {
                for (var k = 0; k < list.length; k++) if (list[k].id === ids[i]) { src = list[k]; break }
            }
            if (!src) continue
            items.push({ id: ids[i], x: p.x, y: p.y, w: src.w, h: src.h })
        }
        if (anyRectsOverlap(items)) return
        var placed = positions[dragged.id]
        if (!placed) return
        var r = { x: placed.x, y: placed.y, w: w, h: h }
        var nTouch = 0
        for (i = 0; i < items.length; i++) {
            if (items[i].id === dragged.id) continue
            if (edgesTouch(r, items[i])) nTouch++
        }
        if (list.length && nTouch === 0) return
        var d = (placed.x + w / 2 - dropCx) * (placed.x + w / 2 - dropCx) + (placed.y + h / 2 - dropCy) * (placed.y + h / 2 - dropCy)
        // Prefer bordering more parallel monitors when the drop spans them.
        var score = d - nTouch * 400 * 400
        if (score < bestScore) {
            bestScore = score
            best = JSON.parse(JSON.stringify(positions))
        }
    }

    function basePositions(dragX, dragY) {
        var pos = {}
        pos[dragged.id] = { x: dragX, y: dragY }
        for (var i = 0; i < list.length; i++) pos[list[i].id] = { x: list[i].x, y: list[i].y }
        return pos
    }

    if (!list.length) {
        var only = {}
        only[dragged.id] = { x: dragged.x, y: dragged.y }
        return only
    }

    var xs = [], ys = [], i, j, o
    for (i = 0; i < list.length; i++) {
        o = list[i]
        xs.push(o.x, o.x + o.w, o.x - w, o.x + o.w - w, o.x + (o.w - w) / 2)
        ys.push(o.y, o.y + o.h, o.y - h, o.y + o.h - h, o.y + (o.h - h) / 2)
        var slots = flushSlots(dragged, o)
        for (j = 0; j < slots.length; j++) consider(basePositions(slots[j].x, slots[j].y), slots[j])
    }
    xs = uniqueNums(xs)
    ys = uniqueNums(ys)
    for (i = 0; i < xs.length; i++) {
        for (j = 0; j < ys.length; j++) consider(basePositions(xs[i], ys[j]), { x: xs[i], y: ys[j] })
    }
    var compound = compoundEdgeSlots(dragged, list)
    for (i = 0; i < compound.length; i++) consider(basePositions(compound[i].x, compound[i].y), compound[i])

    // Insert between two horizontal neighbors (split them apart if needed).
    for (i = 0; i < list.length; i++) {
        for (j = 0; j < list.length; j++) {
            if (i === j) continue
            var a = list[i], b = list[j]
            var yOv = spanOverlap(a.y, a.y + a.h, b.y, b.y + b.h)
            if (yOv <= 8) continue
            if (a.x + a.w > b.x + 2) continue
            var pairY0 = Math.max(a.y, b.y)
            var pairY1 = Math.min(a.y + a.h, b.y + b.h)
            if (dropCy < pairY0 - 80 || dropCy > pairY1 + 80) continue
            var seam = a.x + a.w
            var gap = b.x - seam
            if (Math.abs(dropCx - (seam + gap / 2)) > Math.max(w, 240)) continue
            var yOpts = uniqueNums([a.y, b.y, a.y + a.h - h, b.y + b.h - h, (a.y + b.y) / 2])
            var yi
            for (yi = 0; yi < yOpts.length; yi++) {
                var shift = Math.max(0, w - gap)
                var pos = {}
                pos[dragged.id] = { x: seam, y: yOpts[yi] }
                var k
                for (k = 0; k < list.length; k++) {
                    var n = list[k]
                    var nx = n.x
                    if (n.x >= b.x - 1) nx = n.x + shift
                    pos[n.id] = { x: nx, y: n.y }
                }
                consider(pos, pos[dragged.id])
            }
        }
    }
    // Insert between stacked neighbors.
    for (i = 0; i < list.length; i++) {
        for (j = 0; j < list.length; j++) {
            if (i === j) continue
            var a2 = list[i], b2 = list[j]
            var xOv = spanOverlap(a2.x, a2.x + a2.w, b2.x, b2.x + b2.w)
            if (xOv <= 8) continue
            if (a2.y + a2.h > b2.y + 2) continue
            var pairX0 = Math.max(a2.x, b2.x)
            var pairX1 = Math.min(a2.x + a2.w, b2.x + b2.w)
            if (dropCx < pairX0 - 80 || dropCx > pairX1 + 80) continue
            var seamY = a2.y + a2.h
            var gapY = b2.y - seamY
            if (Math.abs(dropCy - (seamY + gapY / 2)) > Math.max(h, 240)) continue
            var xOpts = uniqueNums([a2.x, b2.x, a2.x + a2.w - w, b2.x + b2.w - w, (a2.x + b2.x) / 2])
            var xi
            for (xi = 0; xi < xOpts.length; xi++) {
                var shiftY = Math.max(0, h - gapY)
                var pos2 = {}
                pos2[dragged.id] = { x: xOpts[xi], y: seamY }
                var k2
                for (k2 = 0; k2 < list.length; k2++) {
                    var n2 = list[k2]
                    var ny = n2.y
                    if (n2.y >= b2.y - 1) ny = n2.y + shiftY
                    pos2[n2.id] = { x: n2.x, y: ny }
                }
                consider(pos2, pos2[dragged.id])
            }
        }
    }

    if (!best) {
        var maxR = list[0].x + list[0].w
        var top = list[0].y
        for (i = 1; i < list.length; i++) {
            maxR = Math.max(maxR, list[i].x + list[i].w)
            top = Math.min(top, list[i].y)
        }
        best = basePositions(maxR, top)
    }
    return best
}

function placeMonitorNoOverlap(dragged, others) {
    var all = arrangeMonitorsAfterDrop(dragged, others)
    var p = all && dragged && all[dragged.id]
    if (!p) return dragged
    return { x: p.x, y: p.y, w: dragged.w, h: dragged.h, id: dragged.id }
}

function snapLayoutRect(dragged, others, thresh) {
    return placeMonitorNoOverlap(dragged, others)
}

function liveLogicalSize(live) {
    var scale = Number(live && live.scale) || 1
    if (scale <= 0) scale = 1
    var w = Number(live && live.width) || 1920
    var h = Number(live && live.height) || 1080
    return { w: Math.max(200, Math.round(w / scale)), h: Math.max(200, Math.round(h / scale)) }
}

function monitorLayoutTiles(cfg, profile, liveList) {
    var tiles = []
    if (!profile) return tiles
    var off = {}
    var dis = profile.disabledMonitors || []
    for (var d = 0; d < dis.length; d++) off[String(dis[d])] = true
    var layout = profile.monitorLayout || {}
    var ids = profile.monitors || []
    var live = liveList || []
    for (var i = 0; i < ids.length; i++) {
        var id = ids[i]
        var saved = monitorById(cfg, id)
        var hit = findLive(saved, live)
        var size = hit ? liveLogicalSize(hit) : { w: 1920, h: 1080 }
        var pos = layout[id]
        var x = pos ? pos.x : (hit ? Number(hit.x) || 0 : i * (size.w + 32))
        var y = pos ? pos.y : (hit ? Number(hit.y) || 0 : 0)
        var mlabel = saved ? saved.label : id
        tiles.push({
            id: id,
            label: mlabel,
            x: x,
            y: y,
            w: size.w,
            h: size.h,
            off: !!off[id],
            connected: !!hit
        })
    }
    return tiles
}

function clone(o) { return JSON.parse(JSON.stringify(o)) }

function makeId(prefix) {
    return (prefix || "aw") + "-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6)
}

function defaultOnlyOnBootForType(type) {
    return type === "app" ? false : true
}

function slugId(s) {
    var t = String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return t.slice(0, 32) || makeId("mon")
}

function shortMonitorLabel(m) {
    var desc = String((m && m.description) || "").trim()
    if (desc) {
        desc = desc.replace(/^HP Inc\.\s+/i, "")
        return desc.slice(0, 48)
    }
    var make = String((m && m.make) || "").trim()
    var model = String((m && m.model) || "").trim()
    if (make && model) return (make + " " + model).slice(0, 48)
    return String((m && (m.label || m.name)) || "Monitor").slice(0, 48)
}

function normalizeMonitor(m) {
    if (!m || typeof m !== "object") return null
    var serial = String(m.serial || "").trim()
    var description = String(m.description || "").trim()
    var name = String(m.name || "").trim()
    if (!serial && !description && !name) return null
    var id = String(m.id || "").trim()
    if (!id) id = slugId(serial || description || name)
    return {
        id: id.slice(0, 40),
        label: String(m.label || shortMonitorLabel(m)).slice(0, 48),
        serial: serial.slice(0, 80),
        description: description.slice(0, 160),
        name: name.slice(0, 40)
    }
}

function round4(n) {
    return Math.round(Number(n) * 10000) / 10000
}

function normalizeGeom(g) {
    if (!g || typeof g !== "object") return null
    var x = Number(g.x), y = Number(g.y), w = Number(g.w), h = Number(g.h)
    if (isNaN(x) || isNaN(y) || isNaN(w) || isNaN(h)) return null
    w = Math.max(0.12, Math.min(1, w))
    h = Math.max(0.12, Math.min(1, h))
    x = Math.max(0, Math.min(1 - w, x))
    y = Math.max(0, Math.min(1 - h, y))
    var out = { x: round4(x), y: round4(y), w: round4(w), h: round4(h) }
    var z = parseInt(g.z, 10)
    if (!isNaN(z)) out.z = z
    return out
}

function autoLayoutRects(count, layout, columnWidth) {
    var gap = 0
    var rects = []
    if (!(count > 0)) return rects
    function push(x, y, w, h) { rects.push(normalizeGeom({ x: x, y: y, w: w, h: h })) }
    if (layout === "scrolling") {
        var cw = columnWidth > 0.1 && columnWidth < 1 ? columnWidth : 0.49
        for (var i = 0; i < count; i++) push(i * (cw + gap), 0, cw, 1)
        return rects
    }
    if (layout === "stage") {
        push(0, 0, 1, 1)
        var scw = columnWidth > 0.1 && columnWidth < 1 ? columnWidth : 0.5
        for (var s = 1; s < count; s++) push(1 + (s - 1) * scw, 0, scw, 1)
        return rects
    }
    if (layout === "master") {
        if (count === 1) { push(0, 0, 1, 1); return rects }
        var mw = 0.55
        push(0, 0, mw - gap / 2, 1)
        var stackN = count - 1
        var sh = (1 - gap * (stackN - 1)) / stackN
        for (var j = 0; j < stackN; j++) push(mw + gap / 2, j * (sh + gap), 1 - mw - gap / 2, sh)
        return rects
    }
    if (count === 1) { push(0, 0, 1, 1); return rects }
    if (count === 2) { push(0, 0, 0.5 - gap / 2, 1); push(0.5 + gap / 2, 0, 0.5 - gap / 2, 1); return rects }
    if (count === 3) {
        push(0, 0, 0.5 - gap / 2, 1)
        push(0.5 + gap / 2, 0, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0.5 + gap / 2, 0.5 + gap / 2, 0.5 - gap / 2, 0.5 - gap / 2)
        return rects
    }
    if (count === 4) {
        push(0, 0, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0.5 + gap / 2, 0, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0, 0.5 + gap / 2, 0.5 - gap / 2, 0.5 - gap / 2)
        push(0.5 + gap / 2, 0.5 + gap / 2, 0.5 - gap / 2, 0.5 - gap / 2)
        return rects
    }
    var cols = count <= 6 ? 3 : 4
    var rows = Math.ceil(count / cols)
    var tw = (1 - gap * (cols - 1)) / cols
    var th = (1 - gap * (rows - 1)) / rows
    for (var k = 0; k < count; k++) {
        var col = k % cols
        var row = Math.floor(k / cols)
        push(col * (tw + gap), row * (th + gap), tw, th)
    }
    return rects
}

function assignmentHasGeom(a) {
    return !!(a && normalizeGeom(a.geom))
}

function workspaceUsesCustomLayout(apps) {
    var list = apps || []
    for (var i = 0; i < list.length; i++) if (assignmentHasGeom(list[i])) return true
    return false
}

var GEOM_EPS = 0.03
var GEOM_MIN = 0.12

function geomRight(g) { return Number(g.x) + Number(g.w) }
function geomBottom(g) { return Number(g.y) + Number(g.h) }

function rangeOverlap(a0, a1, b0, b1) {
    return Math.min(a1, b1) - Math.max(a0, b0) > GEOM_EPS
}

function geomsOverlap(a, b) {
    if (!a || !b) return false
    return rangeOverlap(a.x, geomRight(a), b.x, geomRight(b)) &&
           rangeOverlap(a.y, geomBottom(a), b.y, geomBottom(b))
}

function layoutHasOverlap(geoms) {
    var list = geoms || []
    for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
            if (geomsOverlap(list[i], list[j])) return true
        }
    }
    return false
}

function repairOverlappingLayouts(cfg, layout, columnWidth) {
    if (!cfg || !Array.isArray(cfg.profiles)) return { config: cfg, changed: false }
    var out = clone(cfg)
    var changed = false
    for (var p = 0; p < out.profiles.length; p++) {
        var assignments = out.profiles[p].assignments || []
        var byWs = {}
        for (var i = 0; i < assignments.length; i++) {
            var ws = String(assignments[i].workspace)
            if (!byWs[ws]) byWs[ws] = []
            byWs[ws].push(assignments[i])
        }
        for (var wsKey in byWs) {
            var group = byWs[wsKey]
            var packed = packedGeomsForApps(group, layout || "dwindle", columnWidth)
            for (var g = 0; g < group.length; g++) {
                if (!assignmentHasGeom(group[g])) continue
                var next = packed[g]
                var cur = normalizeGeom(group[g].geom)
                if (!next || !cur) continue
                if (cur.x !== next.x || cur.y !== next.y || cur.w !== next.w || cur.h !== next.h) {
                    group[g].geom = { x: next.x, y: next.y, w: next.w, h: next.h }
                    changed = true
                }
            }
        }
    }
    return { config: out, changed: changed }
}

function packedGeomsForApps(apps, layout, columnWidth) {
    var list = apps || []
    var n = list.length
    var packLayout = layout === "scrolling" ? "dwindle" : (layout || "dwindle")
    var autos = autoLayoutRects(n, packLayout, columnWidth)
    var geoms = []
    var anyCustom = false
    for (var i = 0; i < n; i++) {
        var g = normalizeGeom(list[i] && list[i].geom)
        if (g) {
            anyCustom = true
            geoms.push(g)
        } else {
            geoms.push(autos[i] || normalizeGeom({ x: 0, y: 0, w: 1, h: 1 }))
        }
    }
    var use = (!anyCustom || layoutHasOverlap(geoms)) ? autos : geoms
    var out = []
    for (var k = 0; k < n; k++) {
        var item = clone(use[k] || { x: 0, y: 0, w: 1, h: 1 })
        if (list[k] && list[k].id) item.id = list[k].id
        out.push(item)
    }
    return out
}

function listSplits(geoms) {
    var list = geoms || []
    var v = {}
    var h = {}
    function bucket(map, pos, side, idx) {
        var p = round4(pos)
        var k = null
        for (var existing in map) {
            if (Math.abs(map[existing].pos - p) < GEOM_EPS) { k = existing; break }
        }
        if (!k) {
            k = String(p)
            map[k] = { pos: p, left: [], right: [], top: [], bottom: [] }
        }
        map[k][side].push(idx)
    }
    for (var i = 0; i < list.length; i++) {
        var g = list[i]
        if (!g) continue
        if (g.x > GEOM_EPS) bucket(v, g.x, "right", i)
        if (geomRight(g) < 1 - GEOM_EPS) bucket(v, geomRight(g), "left", i)
        if (g.y > GEOM_EPS) bucket(h, g.y, "bottom", i)
        if (geomBottom(g) < 1 - GEOM_EPS) bucket(h, geomBottom(g), "top", i)
    }
    var splits = []
    function spanY(ids) {
        var y0 = 0, y1 = 1, first = true
        for (var i = 0; i < ids.length; i++) {
            var g = list[ids[i]]
            if (!g) continue
            if (first) { y0 = g.y; y1 = geomBottom(g); first = false }
            else { y0 = Math.min(y0, g.y); y1 = Math.max(y1, geomBottom(g)) }
        }
        return { s0: y0, s1: y1 }
    }
    function spanX(ids) {
        var x0 = 0, x1 = 1, first = true
        for (var i = 0; i < ids.length; i++) {
            var g = list[ids[i]]
            if (!g) continue
            if (first) { x0 = g.x; x1 = geomRight(g); first = false }
            else { x0 = Math.min(x0, g.x); x1 = Math.max(x1, geomRight(g)) }
        }
        return { s0: x0, s1: x1 }
    }
    for (var vk in v) {
        var vb = v[vk]
        if (vb.left.length && vb.right.length) {
            var ys = spanY(vb.left.concat(vb.right))
            splits.push({ axis: "v", pos: vb.pos, aIds: vb.left, bIds: vb.right, s0: ys.s0, s1: ys.s1 })
        }
    }
    for (var hk in h) {
        var hb = h[hk]
        if (hb.top.length && hb.bottom.length) {
            var xs = spanX(hb.top.concat(hb.bottom))
            splits.push({ axis: "h", pos: hb.pos, aIds: hb.top, bIds: hb.bottom, s0: xs.s0, s1: xs.s1 })
        }
    }
    return splits
}

function nudgeSplit(geoms, split, delta) {
    if (!split || !geoms || !geoms.length) return geoms
    var next = clone(geoms)
    var minD = -1
    var maxD = 1
    var i, g
    var aIds = split.aIds || []
    var bIds = split.bIds || []
    if (split.axis === "v") {
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) minD = Math.max(minD, -(g.w - GEOM_MIN))
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) maxD = Math.min(maxD, g.w - GEOM_MIN)
        }
        delta = Math.max(minD, Math.min(maxD, Number(delta) || 0))
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) g.w = round4(g.w + delta)
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) {
                g.x = round4(g.x + delta)
                g.w = round4(g.w - delta)
            }
        }
    } else {
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) minD = Math.max(minD, -(g.h - GEOM_MIN))
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) maxD = Math.min(maxD, g.h - GEOM_MIN)
        }
        delta = Math.max(minD, Math.min(maxD, Number(delta) || 0))
        for (i = 0; i < aIds.length; i++) {
            g = next[aIds[i]]
            if (g) g.h = round4(g.h + delta)
        }
        for (i = 0; i < bIds.length; i++) {
            g = next[bIds[i]]
            if (g) {
                g.y = round4(g.y + delta)
                g.h = round4(g.h - delta)
            }
        }
    }
    return next
}

function normalizeAssignment(a) {
    var ws = parseInt(a.workspace, 10)
    if (!(ws >= 1 && ws <= 10) && String(a.workspace).indexOf("special:") !== 0) ws = 1
    var type = (a.type === "webapp" || a.type === "app" || a.type === "custom") ? a.type : "app"
    var onlyOnBoot = defaultOnlyOnBootForType(type)
    if (typeof a.onlyOnBoot === "boolean") {
        onlyOnBoot = a.onlyOnBoot
    } else if (a.onlyOnBoot === 1 || a.onlyOnBoot === "1" || a.onlyOnBoot === "true") {
        onlyOnBoot = true
    } else if (a.onlyOnBoot === 0 || a.onlyOnBoot === "0" || a.onlyOnBoot === "false") {
        onlyOnBoot = false
    }
    var out = {
        id: String(a.id || makeId()),
        workspace: ws,
        name: String(a.name || a.command || "App").slice(0, 80),
        command: canonicalExec(String(a.command || a.exec || "")).slice(0, 500),
        exec: canonicalExec(String(a.exec || a.command || "")).slice(0, 500),
        type: type,
        enabled: a.enabled !== false,
        onlyOnBoot: onlyOnBoot,
        lockPlace: a.lockPlace === true
    }
    var geom = normalizeGeom(a.geom)
    if (geom) out.geom = geom
    return out
}

function assignmentIsLocked(a, profile) {
    if (!a) return false
    if (a.lockPlace === true) return true
    var pref = workspacePref(profile, a.workspace)
    return pref.lockSizes === true
}

function workspaceHasLockedApp(profile, ws) {
    var pref = workspacePref(profile, ws)
    if (pref.lockSizes === true) return true
    var list = (profile && profile.assignments) || []
    for (var i = 0; i < list.length; i++) {
        if (Number(list[i].workspace) === Number(ws) && list[i].lockPlace === true) return true
    }
    return false
}

function ensureAssignmentGeoms(assignments, ws, pref) {
    var list = assignments || []
    var idxs = []
    var group = []
    for (var i = 0; i < list.length; i++) {
        if (Number(list[i].workspace) === Number(ws)) {
            idxs.push(i)
            group.push(list[i])
        }
    }
    if (!group.length) return list
    var packed = packedGeomsForApps(group, (pref && pref.layout) || "dwindle", 1 / Math.max(1, (pref && pref.visibleCount) || 2))
    for (var g = 0; g < group.length; g++) {
        if (assignmentHasGeom(group[g])) continue
        var pg = packed[g]
        if (!pg) continue
        list[idxs[g]].geom = { x: pg.x, y: pg.y, w: pg.w, h: pg.h }
    }
    return list
}

function normalizeExtraApp(a) {
    if (!a || typeof a !== "object") return null
    var exec = String(a.exec || a.command || "").trim()
    if (!exec) return null
    return {
        name: String(a.name || displayNameForExec(exec, "App")).slice(0, 80),
        exec: exec.slice(0, 500),
        command: String(a.command || exec).slice(0, 500),
        icon: String(a.icon || "").slice(0, 80),
        type: a.type === "webapp" || a.type === "custom" ? a.type : "custom"
    }
}

function normalizeWorkspaceMonitors(raw, knownIds) {
    var out = {}
    if (!raw || typeof raw !== "object") return out
    var keys = Object.keys(raw)
    for (var i = 0; i < keys.length; i++) {
        var ws = parseInt(keys[i], 10)
        if (!(ws >= 1 && ws <= 10)) continue
        var mid = String(raw[keys[i]] || "").trim()
        if (!mid) continue
        if (knownIds && knownIds.length && knownIds.indexOf(mid) < 0) continue
        out[String(ws)] = mid.slice(0, 40)
    }
    return out
}

function normalizeProfile(p, monitorIds) {
    if (!p || typeof p !== "object") return defaultProfile()
    var matchMode = p.matchMode === "all-present" ? "all-present" : "exact"
    var mons = []
    var seen = {}
    var rawMons = Array.isArray(p.monitors) ? p.monitors : []
    for (var i = 0; i < rawMons.length; i++) {
        var id = String(rawMons[i] || "").trim()
        if (!id || seen[id]) continue
        if (monitorIds && monitorIds.length && monitorIds.indexOf(id) < 0) continue
        seen[id] = true
        mons.push(id.slice(0, 40))
        if (mons.length >= 8) break
    }
    var assignments = []
    if (Array.isArray(p.assignments)) {
        assignments = p.assignments.slice(0, 50).map(function(raw) {
            return normalizeAssignment(clone(raw))
        })
    }
    return {
        id: String(p.id || makeId("pr")).slice(0, 40),
        name: String(p.name || "Profile").slice(0, 48),
        matchMode: matchMode,
        monitors: mons,
        workspaceMonitors: normalizeWorkspaceMonitors(p.workspaceMonitors, monitorIds),
        disabledMonitors: (function() {
            var off = []
            var raw = Array.isArray(p.disabledMonitors) ? p.disabledMonitors : []
            var oseen = {}
            for (var d = 0; d < raw.length; d++) {
                var did = String(raw[d] || "").trim()
                if (!did || oseen[did] || mons.indexOf(did) < 0) continue
                oseen[did] = true
                off.push(did)
            }
            if (mons.length < 2) return []
            if (off.length >= mons.length) off = off.slice(0, mons.length - 1)
            return off
        })(),
        monitorLayout: normalizeMonitorLayout(p.monitorLayout),
        workspacePrefs: normalizeWorkspacePrefs(p.workspacePrefs),
        assignments: assignments,
        gestures: normalizeGestures(p.gestures),
        workspaceNames: normalizeWorkspaceNames(p.workspaceNames),
        defaultWorkspace: (function() {
            var n = parseInt(p.defaultWorkspace, 10)
            if (!(n >= 0 && n <= 10)) n = 0
            return n
        })(),
        persistentWorkspaces: p.persistentWorkspaces === true,
        overflow: normalizeOverflow(p.overflow),
        network: normalizeNetwork(p.network),
        claimedAt: (function() {
            var n = parseInt(p.claimedAt, 10)
            return n > 0 ? n : 0
        })()
    }
}

function migrateV1(cfg) {
    var out = defaultConfig()
    if (cfg.settings && typeof cfg.settings === "object") {
        out.settings.enabled = cfg.settings.enabled !== false
        out.settings.applyOnBoot = cfg.settings.applyOnBoot === true
        out.settings.launchDelayMs = Math.max(0, Math.min(10000, parseInt(cfg.settings.launchDelayMs) || 800))
        out.settings.staggerMs = Math.max(0, Math.min(2000, parseInt(cfg.settings.staggerMs) || 80))
        out.settings.silent = cfg.settings.silent !== false
        out.settings.onlyOnBoot = cfg.settings.onlyOnBoot !== false
        out.settings.lastFormWorkspace = Math.max(1, Math.min(10, parseInt(cfg.settings.lastFormWorkspace) || 1))
    }
    var prof = defaultProfile()
    if (Array.isArray(cfg.assignments)) {
        prof.assignments = cfg.assignments.slice(0, 50).map(function(raw) {
            return normalizeAssignment(clone(raw))
        })
    }
    out.profiles = [prof]
    out.settings.activeProfileId = prof.id
    return out
}

function sanitizeConfig(cfg) {
    if (!cfg || typeof cfg !== "object") return defaultConfig()
    if (!Array.isArray(cfg.profiles) && Array.isArray(cfg.assignments)) return migrateV1(cfg)
    var out = clone(defaultConfig())
    if (cfg.settings && typeof cfg.settings === "object") {
        out.settings.enabled = cfg.settings.enabled !== false
        out.settings.applyOnBoot = cfg.settings.applyOnBoot === true
        out.settings.launchDelayMs = Math.max(0, Math.min(10000, parseInt(cfg.settings.launchDelayMs) || 800))
        out.settings.staggerMs = Math.max(0, Math.min(2000, parseInt(cfg.settings.staggerMs) || 80))
        out.settings.silent = cfg.settings.silent !== false
        out.settings.onlyOnBoot = cfg.settings.onlyOnBoot !== false
        out.settings.lastFormWorkspace = Math.max(1, Math.min(10, parseInt(cfg.settings.lastFormWorkspace) || 1))
        out.settings.activeProfileId = String(cfg.settings.activeProfileId || "default").slice(0, 40)
        out.settings.gestureSource = cfg.settings.gestureSource === "profile" ? "profile" : "global"
        out.settings.persistHyprGestures = cfg.settings.persistHyprGestures === true
        out.settings.gestures = normalizeGestures(cfg.settings.gestures)
    }
    var monitors = []
    var ids = []
    var seen = {}
    if (Array.isArray(cfg.monitors)) {
        for (var i = 0; i < cfg.monitors.length && monitors.length < 16; i++) {
            var mon = normalizeMonitor(cfg.monitors[i])
            if (!mon || seen[mon.id]) continue
            seen[mon.id] = true
            monitors.push(mon)
            ids.push(mon.id)
        }
    }
    out.monitors = monitors
    var extras = []
    if (Array.isArray(cfg.extraApps)) {
        for (var e = 0; e < cfg.extraApps.length && extras.length < 20; e++) {
            var extra = normalizeExtraApp(cfg.extraApps[e])
            if (extra) extras.push(extra)
        }
    }
    out.extraApps = extras
    var profiles = []
    var pseen = {}
    if (Array.isArray(cfg.profiles)) {
        for (var p = 0; p < cfg.profiles.length && profiles.length < 12; p++) {
            var prof = normalizeProfile(clone(cfg.profiles[p]), ids)
            if (pseen[prof.id]) continue
            pseen[prof.id] = true
            profiles.push(prof)
        }
    }
    if (profiles.length === 0) profiles = [defaultProfile()]
    out.profiles = profiles
    var active = out.settings.activeProfileId
    if (!profileById(out, active)) out.settings.activeProfileId = profiles[0].id
    out.version = 2
    return out
}

function profileById(cfg, id) {
    var list = (cfg && cfg.profiles) || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
}

function monitorById(cfg, id) {
    var list = (cfg && cfg.monitors) || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
}

function liveIsReal(m) {
    if (!m) return false
    var name = String(m.name || "")
    if (name.indexOf("HEADLESS") >= 0) return false
    return true
}

function sameMonitor(saved, live) {
    if (!saved || !live) return false
    var ss = String(saved.serial || "").trim()
    var ls = String(live.serial || "").trim()
    if (ss && ls && ss === ls) return true
    var sd = String(saved.description || "").trim()
    var ld = String(live.description || "").trim()
    if (sd && ld && sd === ld) return true
    if (!ss && !sd) {
        var sn = String(saved.name || "").trim()
        var ln = String(live.name || "").trim()
        return !!(sn && sn === ln)
    }
    return false
}

function findLive(saved, liveList) {
    for (var i = 0; i < liveList.length; i++) {
        if (liveIsReal(liveList[i]) && sameMonitor(saved, liveList[i])) return liveList[i]
    }
    return null
}

function profileMatch(cfg, profile, liveList, liveNet) {
    var live = (liveList || []).filter(liveIsReal)
    var required = profile && profile.monitors ? profile.monitors : []
    var missing = []
    var matched = []
    var used = {}
    for (var i = 0; i < required.length; i++) {
        var saved = monitorById(cfg, required[i])
        if (!saved) { missing.push(required[i]); continue }
        var hit = findLive(saved, live)
        if (!hit) missing.push(required[i])
        else {
            matched.push(required[i])
            used[String(hit.name || hit.description)] = true
        }
    }
    var extra = []
    for (var j = 0; j < live.length; j++) {
        var key = String(live[j].name || live[j].description)
        var claimed = false
        for (var k = 0; k < required.length; k++) {
            var s = monitorById(cfg, required[k])
            if (s && sameMonitor(s, live[j])) { claimed = true; break }
        }
        if (!claimed) extra.push(shortMonitorLabel(live[j]))
    }
    var allPresent = missing.length === 0 && required.length > 0
    var exact = allPresent && extra.length === 0
    var mode = profile && profile.matchMode === "all-present" ? "all-present" : "exact"
    var matches = mode === "all-present" ? allPresent : exact
    if (required.length === 0) {
        matches = live.length <= 1
        exact = matches
        allPresent = matches
    }
    var reason = matches ? (exact ? "exact" : "all-present") : (missing.length ? "missing" : "extra")
    var net = networkMatches(profile && profile.network, liveNet)
    if (matches && net.constrained && !net.matches) {
        matches = false
        reason = "network"
    }
    return {
        matches: matches,
        exact: exact,
        allPresent: allPresent,
        missing: missing,
        extra: extra,
        matchedCount: matched.length,
        requiredCount: required.length,
        reason: reason,
        networkConstrained: net.constrained,
        networkMatches: net.matches
    }
}

function bestProfile(cfg, liveList, liveNet) {
    var list = (cfg && cfg.profiles) || []
    var scored = []
    for (var i = 0; i < list.length; i++) {
        var info = profileMatch(cfg, list[i], liveList, liveNet)
        if (!info.matches) continue
        scored.push({
            profile: list[i],
            info: info,
            netBoost: info.networkConstrained && info.networkMatches ? 2 : 1,
            exactBoost: info.exact ? 2 : 1,
            claimed: Number(list[i].claimedAt) || 0
        })
    }
    if (!scored.length) return null
    scored.sort(function(a, b) {
        if (b.netBoost !== a.netBoost) return b.netBoost - a.netBoost
        if (b.exactBoost !== a.exactBoost) return b.exactBoost - a.exactBoost
        if (b.info.requiredCount !== a.info.requiredCount) return b.info.requiredCount - a.info.requiredCount
        if (b.claimed !== a.claimed) return b.claimed - a.claimed
        return 0
    })
    return scored[0].profile
}

function monitorOptions(cfg, profile, liveList) {
    var opts = []
    var seen = {}
    function add(id, label) {
        if (!id || seen[id]) return
        seen[id] = true
        opts.push({ value: id, label: label })
    }
    var prefer = (profile && profile.monitors) || []
    var off = {}
    var dis = (profile && profile.disabledMonitors) || []
    for (var d = 0; d < dis.length; d++) off[String(dis[d])] = true
    for (var i = 0; i < prefer.length; i++) {
        if (off[prefer[i]]) continue
        var m = monitorById(cfg, prefer[i])
        if (m) add(m.id, m.label)
    }
    if (prefer.length === 0) {
        var live = liveList || []
        for (var k = 0; k < live.length; k++) {
            if (!liveIsReal(live[k])) continue
            var tmp = normalizeMonitor(live[k])
            if (tmp) add(tmp.id, tmp.label)
        }
    }
    if (opts.length > 1) opts.unshift({ value: "", label: "Any monitor" })
    return opts
}

function copyWorkspace(cfg, fromId, fromWs, toId, toWs) {
    if (!cfg) return cfg
    var srcWs = parseInt(fromWs, 10)
    var dstWs = parseInt(toWs == null || toWs === "" ? fromWs : toWs, 10)
    if (!(srcWs >= 1 && srcWs <= 10) || !(dstWs >= 1 && dstWs <= 10)) return cfg
    if (fromId === toId && srcWs === dstWs) return cfg
    var out = clone(cfg)
    var from = profileById(out, fromId)
    var to = profileById(out, toId)
    if (!from || !to) return cfg
    var kept = []
    var list = to.assignments || []
    for (var i = 0; i < list.length; i++) if (list[i].workspace !== dstWs) kept.push(list[i])
    var copies = []
    var src = from.assignments || []
    for (var j = 0; j < src.length; j++) {
        if (src[j].workspace !== srcWs) continue
        var item = clone(src[j])
        item.id = makeId()
        item.workspace = dstWs
        copies.push(normalizeAssignment(item))
    }
    to.assignments = kept.concat(copies)
    if (!to.workspacePrefs) to.workspacePrefs = {}
    if ((from.workspacePrefs || {})[String(srcWs)])
        to.workspacePrefs[String(dstWs)] = clone(normalizeWorkspacePref(from.workspacePrefs[String(srcWs)]))
    if (!to.workspaceMonitors) to.workspaceMonitors = {}
    var pin = (from.workspaceMonitors || {})[String(srcWs)]
    if (pin && (to.monitors || []).indexOf(pin) >= 0) to.workspaceMonitors[String(dstWs)] = pin
    else if ((to.monitors || []).length === 1) to.workspaceMonitors[String(dstWs)] = to.monitors[0]
    else delete to.workspaceMonitors[String(dstWs)]
    return out
}

function moveWorkspace(cfg, profileId, fromWs, toWs) {
    var srcWs = parseInt(fromWs, 10)
    var dstWs = parseInt(toWs, 10)
    if (!cfg || srcWs === dstWs) return cfg
    if (!(srcWs >= 1 && srcWs <= 10) || !(dstWs >= 1 && dstWs <= 10)) return cfg
    var out = clone(cfg)
    var prof = profileById(out, profileId)
    if (!prof) return cfg
    var next = []
    var list = prof.assignments || []
    for (var i = 0; i < list.length; i++) {
        var item = clone(list[i])
        if (item.workspace === srcWs) item.workspace = dstWs
        else if (item.workspace === dstWs) item.workspace = srcWs
        next.push(normalizeAssignment(item))
    }
    prof.assignments = next
    var prefs = prof.workspacePrefs || {}
    var prefFrom = prefs[String(srcWs)]
    var prefTo = prefs[String(dstWs)]
    if (prefFrom) prefs[String(dstWs)] = prefFrom
    else delete prefs[String(dstWs)]
    if (prefTo) prefs[String(srcWs)] = prefTo
    else delete prefs[String(srcWs)]
    prof.workspacePrefs = prefs
    var pins = prof.workspaceMonitors || {}
    var pFrom = pins[String(srcWs)]
    var pTo = pins[String(dstWs)]
    if (pFrom) pins[String(dstWs)] = pFrom
    else delete pins[String(dstWs)]
    if (pTo) pins[String(srcWs)] = pTo
    else delete pins[String(srcWs)]
    prof.workspaceMonitors = pins
    return out
}

function upsertLiveMonitor(cfg, live) {
    var mon = normalizeMonitor(live)
    if (!mon) return { config: cfg, id: "" }
    var out = clone(cfg)
    for (var i = 0; i < out.monitors.length; i++) {
        if (out.monitors[i].id === mon.id || sameMonitor(out.monitors[i], mon)) {
            return { config: out, id: out.monitors[i].id }
        }
    }
    out.monitors = out.monitors.concat([mon])
    return { config: out, id: mon.id }
}

function extractWebappUrl(s) {
    var m = String(s || "").match(/https:\/\/[^\s\"']+/g)
    if (!m || !m.length) return ""
    var i
    for (i = 0; i < m.length; i++) if (m[i].indexOf("deeplink") < 0) return m[i]
    return m[m.length - 1]
}

function extractChromiumAppKey(s) {
    var t = String(s || "")
    var id = t.match(/--app-id=([A-Za-z0-9_-]+)/)
    if (id) return "id:" + id[1]
    var app = t.match(/--app=(\S+)/)
    if (app) return "app:" + app[1]
    return ""
}

function canonicalExec(s) {
    var t = String(s || "").trim()
    if (!t) return ""
    var url = extractWebappUrl(t)
    if (t.indexOf("omarchy-launch-webapp") >= 0 && url) return "omarchy-launch-webapp '" + url + "'"
    return t
}

function execBasename(s) {
    var t = canonicalExec(s)
    var first = t.split(/\s+/)[0] || ""
    return first.split("/").pop().toLowerCase()
}

function isGenericLauncher(base) {
    var b = String(base || "").toLowerCase()
    return b === "sh" || b === "bash" || b === "env" || b === "uwsm-app"
        || b === "omarchy-launch-webapp" || b === "omarchy-launch-tui"
        || b === "omarchy-launch-or-focus-tui"
}

function sameAppExec(a, b) {
    var ca = canonicalExec(a), cb = canonicalExec(b)
    if (ca && cb && ca === cb) return true
    var ua = extractWebappUrl(a), ub = extractWebappUrl(b)
    if (ua && ub) return ua === ub
    var ka = extractChromiumAppKey(a), kb = extractChromiumAppKey(b)
    if (ka || kb) return !!(ka && kb && ka === kb)
    if (ua || ub) return false
    var ba = execBasename(a), bb = execBasename(b)
    if (!ba || !bb) return false
    if (isGenericLauncher(ba) || isGenericLauncher(bb)) return false
    return ba === bb
}

function execForAssignment(a) {
    if (a.exec && String(a.exec).trim().length) return String(a.exec).trim()
    if (a.command && String(a.command).trim().length) {
        var cmd = String(a.command).trim()
        if (a.type === "webapp") {
            if (cmd.indexOf("http://") === 0 || cmd.indexOf("https://") === 0) {
                return "omarchy-launch-webapp '" + cmd.replace(/'/g, "'\\''") + "'"
            }
            return cmd
        }
        return cmd
    }
    return ""
}

function displayNameForExec(execStr, fallback) {
    var s = String(execStr || "").trim()
    if (!s) return fallback || "App"
    var m = s.match(/omarchy-launch-webapp\s+'([^']+)'/)
    if (m) {
        try {
            var u = new URL(m[1])
            return u.hostname.replace(/^www\./, "") + u.pathname.split("/").slice(0, 2).join("/")
        } catch (e) { return m[1].slice(0, 40) }
    }
    if (/herdr/.test(s) && /shophawk/.test(s)) return "ShopHawk Herdr"
    if (/(^|[\/\s])herdr(\s|$)/.test(s)) return "Herdr"
    var first = s.split(/\s+/)[0]
    var base = first.split("/").pop()
    return base || fallback || "App"
}
