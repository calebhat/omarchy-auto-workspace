#!/usr/bin/env node
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
eval(src + "\nmodule.exports = { defaultConfig, sanitizeConfig, migrateV1, profileMatch, bestProfile, sameMonitor, normalizeMonitor, displayNameForExec, upsertLiveMonitor, normalizeGeom, autoLayoutRects, workspaceUsesCustomLayout, layoutHasOverlap, packedGeomsForApps, listSplits, nudgeSplit, monitorOptions, copyWorkspace, moveWorkspace, snapLayoutRect, normalizeMonitorLayout, placeMonitorNoOverlap, rectsOverlap, arrangeMonitorsAfterDrop }")
const m = module.exports

const v1 = m.sanitizeConfig({
  version: 1,
  settings: { enabled: true, lastFormWorkspace: 4 },
  assignments: [{ workspace: 2, name: "Foot", command: "foot", exec: "foot", type: "app", enabled: true }]
})
if (v1.version !== 2) throw new Error("migrate version")
if (v1.profiles.length !== 1) throw new Error("migrate profile")
if (v1.profiles[0].assignments.length !== 1) throw new Error("migrate assignments")
if (v1.settings.applyOnBoot !== false) throw new Error("boot default off")

const laptop = { id: "laptop", label: "Laptop", serial: "", description: "BOE NE135A1M-NY1", name: "eDP-1" }
const left = { id: "desk-left", label: "Desk left", serial: "", description: "HP Inc. HP E24 G5 CNK436071M", name: "DVI-I-1" }
const right = { id: "desk-right", label: "Desk right", serial: "", description: "HP Inc. HP E24 G5 CNK436070F", name: "DVI-I-2" }
const cfg = m.sanitizeConfig({
  version: 2,
  settings: { applyOnBoot: false, activeProfileId: "desk-dock" },
  monitors: [laptop, left, right],
  profiles: [
    { id: "desk-dock", name: "Desk dock", matchMode: "exact", monitors: ["laptop", "desk-left", "desk-right"], workspaceMonitors: { "1": "desk-left", "2": "desk-right", "9": "laptop" }, assignments: [] },
    { id: "laptop", name: "Laptop", matchMode: "exact", monitors: ["laptop"], workspaceMonitors: {}, assignments: [] }
  ]
})

const liveLaptop = [{ name: "eDP-1", description: "BOE NE135A1M-NY1", serial: "", disabled: false }]
const liveDesk = [
  { name: "eDP-1", description: "BOE NE135A1M-NY1", serial: "", disabled: false },
  { name: "DVI-I-2", description: "HP Inc. HP E24 G5 CNK436071M", serial: "", disabled: false },
  { name: "DVI-I-1", description: "HP Inc. HP E24 G5 CNK436070F", serial: "", disabled: false }
]

if (m.bestProfile(cfg, liveLaptop).id !== "laptop") throw new Error("laptop layout should pick laptop profile")
if (m.bestProfile(cfg, liveDesk).id !== "desk-dock") throw new Error("dock layout should pick desk-dock")
if (m.profileMatch(cfg, cfg.profiles[1], liveDesk).matches) throw new Error("laptop profile must not match while docked")
if (!m.sameMonitor(left, { description: "HP Inc. HP E24 G5 CNK436071M", name: "HDMI-A-1", serial: "" }))
  throw new Error("match by description across connector rename")
if (m.sameMonitor(left, { description: "HP Inc. HP E24 G5 CNK436070F", name: "DVI-I-1", serial: "" }))
  throw new Error("do not match the other HP by connector name")
if (m.displayNameForExec("omarchy-launch-or-focus-tui --app-id=org.omarchy.herdr herdr --session shophawk") !== "ShopHawk Herdr")
  throw new Error("herdr display name")

const g = m.normalizeGeom({ x: -0.2, y: 0.9, w: 0.5, h: 0.5 })
if (!g || g.x < 0 || g.x + g.w > 1.0001) throw new Error("geom clamp x")
if (g.h < 0.12) throw new Error("geom min h")
if (m.normalizeGeom(null) !== null) throw new Error("geom null")
const two = m.autoLayoutRects(2, "dwindle", 0.49)
if (two.length !== 2 || two[0].w < 0.4 || two[1].x < 0.4) throw new Error("dwindle 2-split")
const withGeom = m.sanitizeConfig({
  version: 2,
  profiles: [{ id: "p", name: "P", assignments: [{ workspace: 1, name: "A", exec: "foot", geom: { x: 0, y: 0, w: 0.4, h: 1 } }] }]
})
if (!m.workspaceUsesCustomLayout(withGeom.profiles[0].assignments)) throw new Error("custom layout flag")
if (!withGeom.profiles[0].assignments[0].geom) throw new Error("persist geom")

const overlap = [{ x: 0, y: 0, w: 0.7, h: 1 }, { x: 0.5, y: 0, w: 0.5, h: 1 }]
if (!m.layoutHasOverlap(overlap)) throw new Error("detect overlap")
const apps = [
  { id: "a", geom: overlap[0] },
  { id: "b", geom: overlap[1] }
]
const packed = m.packedGeomsForApps(apps, "dwindle", 0.49)
if (m.layoutHasOverlap(packed)) throw new Error("repair overlap")
if (packed[0].id !== "a" || packed[1].id !== "b") throw new Error("keep ids")
const tiled = m.autoLayoutRects(2, "dwindle", 0.49)
const splits = m.listSplits(tiled)
if (!splits.length || splits[0].axis !== "v") throw new Error("vertical split for 2 panes")
const nudged = m.nudgeSplit(tiled, splits[0], 0.1)
if (m.layoutHasOverlap(nudged)) throw new Error("nudge overlap")
if (Math.abs((nudged[0].x + nudged[0].w) - nudged[1].x) > 0.02) throw new Error("shared edge after nudge")
const tooFar = m.nudgeSplit(tiled, splits[0], 0.9)
if (tooFar[1].w < 0.12 - 1e-6) throw new Error("min size on right")

const laptopOpts = m.monitorOptions(cfg, cfg.profiles[1], liveDesk)
if (laptopOpts.some(function(o){ return o.value === "desk-left" || o.value === "desk-right" }))
  throw new Error("laptop profile must not list desk monitors")
if (!laptopOpts.some(function(o){ return o.value === "laptop" })) throw new Error("laptop option missing")
const deskOpts = m.monitorOptions(cfg, cfg.profiles[0], liveDesk)
if (!deskOpts.some(function(o){ return o.value === "desk-left" })) throw new Error("desk profile lists desk-left")

let copied = m.copyWorkspace(cfg, "laptop", 1, "desk-dock")
copied.profiles[1].assignments = [{ id: "src", workspace: 1, name: "Herdr", exec: "herdr-shophawk", type: "custom", geom: { x: 0, y: 0, w: 0.6, h: 1 } }]
copied = m.copyWorkspace(copied, "laptop", 1, "desk-dock")
const dest = copied.profiles.find(function(p){ return p.id === "desk-dock" })
if (!dest.assignments.some(function(a){ return a.name === "Herdr" && a.workspace === 1 && a.id !== "src" }))
  throw new Error("copy workspace apps")
if (dest.assignments.filter(function(a){ return a.workspace === 1 }).length !== 1)
  throw new Error("copy replaces dest ws assignments")
copied = m.copyWorkspace(copied, "laptop", 1, "desk-dock", 4)
const dest2 = copied.profiles.find(function(p){ return p.id === "desk-dock" })
if (!dest2.assignments.some(function(a){ return a.name === "Herdr" && a.workspace === 4 }))
  throw new Error("copy to a different workspace number")

const movedCfg = m.sanitizeConfig({
  version: 2,
  profiles: [{
    id: "p",
    name: "P",
    monitors: ["laptop"],
    workspaceMonitors: { "1": "laptop" },
    assignments: [
      { id: "a", workspace: 1, name: "A", exec: "foot" },
      { id: "b", workspace: 5, name: "B", exec: "brave" }
    ]
  }]
})
const moved = m.moveWorkspace(movedCfg, "p", 1, 5)
const mp = moved.profiles[0]
if (!mp.assignments.some(function(a){ return a.name === "A" && a.workspace === 5 })) throw new Error("move src to dest")
if (!mp.assignments.some(function(a){ return a.name === "B" && a.workspace === 1 })) throw new Error("move swaps dest back")
if (mp.workspaceMonitors["5"] !== "laptop") throw new Error("move pin")

const oneScreen = m.sanitizeConfig({
  version: 2,
  monitors: [{ id: "laptop", label: "Laptop", description: "BOE", name: "eDP-1" }],
  profiles: [{ id: "solo", name: "Solo", monitors: ["laptop"], disabledMonitors: ["laptop"], assignments: [] }]
})
if ((oneScreen.profiles[0].disabledMonitors || []).length !== 0)
  throw new Error("cannot disable the only display in a profile")

const snapped = m.placeMonitorNoOverlap(
  { id: "a", x: 1905, y: 3, w: 1920, h: 1080 },
  [{ id: "b", x: 0, y: 0, w: 1920, h: 1080 }]
)
if (snapped.x !== 1920 || snapped.y !== 0) throw new Error("snap to neighbor edge")
const overlapped = m.placeMonitorNoOverlap(
  { id: "a", x: 400, y: 100, w: 1920, h: 1080 },
  [{ id: "b", x: 0, y: 0, w: 1920, h: 1080 }]
)
if (m.rectsOverlap(overlapped, { x: 0, y: 0, w: 1920, h: 1080 })) throw new Error("no overlap after place")
if (overlapped.x !== 1920 && overlapped.x !== -1920 && overlapped.y !== 1080 && overlapped.y !== -1080)
  throw new Error("flush to a neighbor side")

const a = { id: "a", x: 0, y: 0, w: 1920, h: 1080 }
const b = { id: "b", x: 1920, y: 0, w: 1920, h: 1080 }
const c = { id: "c", x: 1600, y: 40, w: 1440, h: 960 }
const inserted = m.arrangeMonitorsAfterDrop(c, [a, b])
if (inserted.c.x !== 1920) throw new Error("insert between packed pair")
if (inserted.a.x !== 0) throw new Error("left stays")
if (inserted.b.x !== 1920 + 1440) throw new Error("right shifts for insert")
if (m.rectsOverlap({ x: inserted.c.x, y: inserted.c.y, w: 1440, h: 960 }, { x: inserted.a.x, y: inserted.a.y, w: 1920, h: 1080 }))
  throw new Error("insert overlap a")
if (m.rectsOverlap({ x: inserted.c.x, y: inserted.c.y, w: 1440, h: 960 }, { x: inserted.b.x, y: inserted.b.y, w: 1920, h: 1080 }))
  throw new Error("insert overlap b")

const far = m.placeMonitorNoOverlap(
  { id: "c", x: 9000, y: 8000, w: 1440, h: 900 },
  [a, b]
)
if (m.rectsOverlap(far, a) || m.rectsOverlap(far, b)) throw new Error("far drop overlap")
const touchesA = Math.abs(far.x - (a.x + a.w)) < 2 || Math.abs(far.x + far.w - a.x) < 2 || Math.abs(far.y - (a.y + a.h)) < 2 || Math.abs(far.y + far.h - a.y) < 2
const touchesB = Math.abs(far.x - (b.x + b.w)) < 2 || Math.abs(far.x + far.w - b.x) < 2 || Math.abs(far.y - (b.y + b.h)) < 2 || Math.abs(far.y + far.h - b.y) < 2
if (!touchesA && !touchesB) throw new Error("far drop must dock to the cluster")

console.log("model.test.js ok")
