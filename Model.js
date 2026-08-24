.pragma library

// Shared helpers for Auto Workspace panel + service.
// Config lives outside the plugin dir so saves do not reload the plugin.

function defaultConfig() {
    return {
        version: 2,
        settings: {
            enabled: true,
            applyOnBoot: false,
            launchDelayMs: 1500,
            staggerMs: 400,
            silent: true,
            onlyOnBoot: true,
            lastFormWorkspace: 1,
            activeProfileId: "default"
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
        assignments: []
    }
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
    var gap = 0.012
    var rects = []
    if (!(count > 0)) return rects
    function push(x, y, w, h) { rects.push(normalizeGeom({ x: x, y: y, w: w, h: h })) }
    if (layout === "scrolling") {
        var cw = columnWidth > 0.1 && columnWidth < 1 ? columnWidth : 0.49
        for (var i = 0; i < count; i++) push(i * (cw + gap), 0, cw, 1)
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
        command: String(a.command || a.exec || "").slice(0, 500),
        exec: String(a.exec || a.command || "").slice(0, 500),
        type: type,
        enabled: a.enabled !== false,
        onlyOnBoot: onlyOnBoot
    }
    var geom = normalizeGeom(a.geom)
    if (geom) out.geom = geom
    return out
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
        assignments: assignments
    }
}

function migrateV1(cfg) {
    var out = defaultConfig()
    if (cfg.settings && typeof cfg.settings === "object") {
        out.settings.enabled = cfg.settings.enabled !== false
        out.settings.applyOnBoot = cfg.settings.applyOnBoot === true
        out.settings.launchDelayMs = Math.max(0, Math.min(10000, parseInt(cfg.settings.launchDelayMs) || 1500))
        out.settings.staggerMs = Math.max(0, Math.min(2000, parseInt(cfg.settings.staggerMs) || 400))
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
        out.settings.launchDelayMs = Math.max(0, Math.min(10000, parseInt(cfg.settings.launchDelayMs) || 1500))
        out.settings.staggerMs = Math.max(0, Math.min(2000, parseInt(cfg.settings.staggerMs) || 400))
        out.settings.silent = cfg.settings.silent !== false
        out.settings.onlyOnBoot = cfg.settings.onlyOnBoot !== false
        out.settings.lastFormWorkspace = Math.max(1, Math.min(10, parseInt(cfg.settings.lastFormWorkspace) || 1))
        out.settings.activeProfileId = String(cfg.settings.activeProfileId || "default").slice(0, 40)
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
    if (!m || m.disabled) return false
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

function profileMatch(cfg, profile, liveList) {
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
    return {
        matches: matches,
        exact: exact,
        allPresent: allPresent,
        missing: missing,
        extra: extra,
        matchedCount: matched.length,
        requiredCount: required.length,
        reason: matches ? (exact ? "exact" : "all-present") : (missing.length ? "missing" : "extra")
    }
}

function bestProfile(cfg, liveList) {
    var list = (cfg && cfg.profiles) || []
    var exact = []
    var present = []
    for (var i = 0; i < list.length; i++) {
        var info = profileMatch(cfg, list[i], liveList)
        if (info.exact) exact.push({ profile: list[i], info: info })
        else if (info.allPresent) present.push({ profile: list[i], info: info })
    }
    function moreMonitors(a, b) { return b.info.requiredCount - a.info.requiredCount }
    if (exact.length) {
        exact.sort(moreMonitors)
        return exact[0].profile
    }
    if (present.length) {
        present.sort(moreMonitors)
        return present[0].profile
    }
    return null
}

function monitorOptions(cfg, profile, liveList) {
    var opts = [{ value: "", label: "Any monitor" }]
    var seen = {}
    function add(id, label) {
        if (!id || seen[id]) return
        seen[id] = true
        opts.push({ value: id, label: label })
    }
    var mons = (cfg && cfg.monitors) || []
    var prefer = (profile && profile.monitors) || []
    for (var i = 0; i < prefer.length; i++) {
        var m = monitorById(cfg, prefer[i])
        if (m) add(m.id, m.label)
    }
    for (var j = 0; j < mons.length; j++) add(mons[j].id, mons[j].label)
    var live = liveList || []
    for (var k = 0; k < live.length; k++) {
        if (!liveIsReal(live[k])) continue
        var existing = null
        for (var n = 0; n < mons.length; n++) {
            if (sameMonitor(mons[n], live[k])) { existing = mons[n]; break }
        }
        if (existing) add(existing.id, existing.label)
        else {
            var tmp = normalizeMonitor(live[k])
            if (tmp) add(tmp.id, tmp.label + " (now)")
        }
    }
    return opts
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
