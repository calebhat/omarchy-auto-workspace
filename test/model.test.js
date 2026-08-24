#!/usr/bin/env node
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
eval(src + "\nmodule.exports = { defaultConfig, sanitizeConfig, migrateV1, profileMatch, bestProfile, sameMonitor, normalizeMonitor, displayNameForExec, upsertLiveMonitor, normalizeGeom, autoLayoutRects, workspaceUsesCustomLayout }")
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

console.log("model.test.js ok")
