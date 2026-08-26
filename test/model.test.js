#!/usr/bin/env node
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
eval(src + "\nmodule.exports = { defaultConfig, sanitizeConfig, migrateV1, profileMatch, bestProfile, nextFollowedMatch, sameMonitor, normalizeMonitor, displayNameForExec, upsertLiveMonitor, normalizeGeom, autoLayoutRects, workspaceUsesCustomLayout, layoutHasOverlap, packedGeomsForApps, listSplits, nudgeSplit, splitDrop, swapGeoms, dropZone, splitRect, fillHole, removeAppAndFill, setAppsPlace, monitorOptions, copyWorkspace, moveWorkspace, snapLayoutRect, normalizeMonitorLayout, placeMonitorNoOverlap, rectsOverlap, arrangeMonitorsAfterDrop, workspacePref, normalizeWorkspacePref, normalizeWorkspacePrefs, assignmentIsLocked, workspaceHasLockedApp, ensureAssignmentGeoms, normalizeAssignment, sameAppExec, canonicalExec, extractChromiumAppKey, layoutDescription, visibleCountHelp, clampVisibleCount, emptyNetwork, captureNetwork, networkConfigured, networkMatches, networksOverlap, environmentOwner, claimEnvironment, monitorKey, suggestedProfileName, parseNetworkText, boundNetworkLine, matchReasonLabel, applyRefuseText, applyHint, allowedMainView, normalizeOverflow, unsetWorkspaces, overflowSummary, maxWorkspace, maxOrganizerPanes, normalizeChrome, clampOpacity, assignmentPlace, safeCwd, safeUrl, chromeIsDefault }")
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
if (m.allowedMainView("workspaces") !== "workspaces") throw new Error("keep workspaces view")
if (m.allowedMainView("nope") !== "profiles") throw new Error("unknown view is profiles home")
if (m.defaultConfig().settings.lastMainView !== "profiles") throw new Error("home is profiles")
if (m.sanitizeConfig({ version: 2, settings: { lastMainView: "gestures" }, profiles: [{ id: "p", name: "P" }] }).settings.lastMainView !== "gestures")
  throw new Error("persist last page")
if (m.defaultConfig().settings.gestureSource !== "global") throw new Error("gestures default global")
const gsrcMissing = m.sanitizeConfig({ version: 2, settings: {}, profiles: [{ id: "p", name: "P" }] })
if (gsrcMissing.settings.gestureSource !== "global") throw new Error("sanitize missing source is global")
const gsrcKeep = m.sanitizeConfig({ version: 2, settings: { gestureSource: "profile" }, profiles: [{ id: "p", name: "P" }] })
if (gsrcKeep.settings.gestureSource !== "profile") throw new Error("sanitize keeps explicit profile gestures")

const laptop = { id: "laptop", label: "Laptop", serial: "", description: "BOE NE135A1M-NY1", name: "eDP-1" }
const left = { id: "desk-left", label: "Desk left", serial: "", description: "HP Inc. HP E24 G5 SN-LEFT", name: "DVI-I-1" }
const right = { id: "desk-right", label: "Desk right", serial: "", description: "HP Inc. HP E24 G5 SN-RIGHT", name: "DVI-I-2" }
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
  { name: "DVI-I-2", description: "HP Inc. HP E24 G5 SN-LEFT", serial: "", disabled: false },
  { name: "DVI-I-1", description: "HP Inc. HP E24 G5 SN-RIGHT", serial: "", disabled: false }
]

if (m.bestProfile(cfg, liveLaptop).id !== "laptop") throw new Error("laptop layout should pick laptop profile")
if (m.bestProfile(cfg, liveDesk).id !== "desk-dock") throw new Error("dock layout should pick desk-dock")
if (m.nextFollowedMatch("desk-dock", "") !== "desk-dock") throw new Error("dock should follow first match")
if (m.nextFollowedMatch("desk-dock", "desk-dock") !== "") throw new Error("same match must not refollow")
if (m.nextFollowedMatch("laptop", "desk-dock") !== "laptop") throw new Error("undock should follow laptop")
if (m.nextFollowedMatch("", "desk-dock") !== "") throw new Error("empty match must not follow")
if (m.profileMatch(cfg, cfg.profiles[1], liveDesk).matches) throw new Error("laptop profile must not match while docked")
const dockOnLaptop = m.applyHint(cfg, cfg.profiles[0], liveLaptop, {})
if (dockOnLaptop.canApply) throw new Error("desk-dock must not apply on laptop-only")
if ((dockOnLaptop.refuseText || "").indexOf("aren't connected") < 0) throw new Error("desk-dock refuse text: " + dockOnLaptop.refuseText)
const lapOnLaptop = m.applyHint(cfg, cfg.profiles[1], liveLaptop, {})
if (!lapOnLaptop.canApply) throw new Error("laptop must apply on laptop-only")
const lapOnDesk = m.applyHint(cfg, cfg.profiles[1], liveDesk, {})
if (lapOnDesk.canApply) throw new Error("laptop must not apply while docked")
if (!m.sameMonitor(left, { description: "HP Inc. HP E24 G5 SN-LEFT", name: "HDMI-A-1", serial: "" }))
  throw new Error("match by description across connector rename")
if (m.sameMonitor(left, { description: "HP Inc. HP E24 G5 SN-RIGHT", name: "DVI-I-1", serial: "" }))
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
if (tooFar[1].w < 0.04 - 1e-6) throw new Error("min size on right")

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

const stackedTop = { id: "t", x: 0, y: 0, w: 1920, h: 1080 }
const stackedBot = { id: "b", x: 0, y: 1080, w: 1920, h: 1080 }
const side = m.placeMonitorNoOverlap(
  { id: "s", x: -1800, y: 500, w: 1920, h: 1080 },
  [stackedTop, stackedBot]
)
if (side.x !== -1920) throw new Error("flush left of stacked pair")
var ovTop = Math.min(side.y + 1080, 1080) - Math.max(side.y, 0)
var ovBot = Math.min(side.y + 1080, 2160) - Math.max(side.y, 1080)
if (!(ovTop > 0 && ovBot > 0)) throw new Error("must border both stacked monitors, y=" + side.y)

const wide = m.placeMonitorNoOverlap(
  { id: "w", x: 200, y: -200, w: 3840, h: 900 },
  [a, b]
)
if (wide.y !== -900) throw new Error("ultrawide sits on top edge")
if (wide.x !== 0) throw new Error("ultrawide spans both side-by-side, x=" + wide.x)

const prefCfg = m.sanitizeConfig({
  version: 2,
  profiles: [{ id: "p", name: "P", workspacePrefs: { "2": { layout: "scrolling", visibleCount: 3, lockSizes: true, extras: "block" }, "99": { layout: "nope" } } }]
})
const pref = prefCfg.profiles[0].workspacePrefs["2"]
if (pref.layout !== "scrolling" || pref.visibleCount !== 3 || pref.lockSizes !== true || pref.extras !== "block")
  throw new Error("workspace prefs")
if (m.layoutDescription("master").indexOf("stack") < 0) throw new Error("master layout copy")
if (m.layoutDescription("stage").indexOf("full width") < 0) throw new Error("stage layout copy")
if (m.normalizeWorkspacePref({ layout: "stage" }).layout !== "stage") throw new Error("persist stage")
if (m.normalizeWorkspacePref({ layout: "set-width" }).layout !== "set-width") throw new Error("persist set-width")
if (m.layoutDescription("set-width").indexOf("1/Visible") < 0) throw new Error("set-width layout copy")
const setWidthRects = m.autoLayoutRects(1, "set-width", 0.25)
if (setWidthRects.length !== 1 || Math.abs(setWidthRects[0].w - 0.25) > 0.02) throw new Error("set-width first is not full")
if (m.visibleCountHelp(4, false, "set-width").indexOf("1/4") < 0) throw new Error("set-width visible help")
const stageRects = m.autoLayoutRects(2, "stage", 0.5)
if (stageRects[0].w !== 1) throw new Error("stage first full")
if (!(stageRects[1].w > 0.4 && stageRects[1].w < 0.6)) throw new Error("stage extra width")
if (m.layoutDescription("scrolling").indexOf("column") < 0) throw new Error("scrolling layout copy")
if (m.layoutDescription("dwindle").indexOf("split") < 0) throw new Error("dwindle layout copy")
if (m.layoutDescription("dwindle", true).indexOf("clip") < 0) throw new Error("lock uses scrolling copy")
if (m.visibleCountHelp(2, true).indexOf("1/2") < 0) throw new Error("visible extra width")
if (m.clampVisibleCount(10) !== 10) throw new Error("visible 10")
if (m.clampVisibleCount(21) !== 20) throw new Error("visible max 20")
if (m.clampVisibleCount(0) !== 1) throw new Error("visible min 1")
const widePref = m.sanitizeConfig({
  version: 2,
  profiles: [{ id: "p", name: "P", workspacePrefs: { "1": { layout: "scrolling", visibleCount: 10 } } }]
})
if (widePref.profiles[0].workspacePrefs["1"].visibleCount !== 10) throw new Error("persist visible 10")
if (prefCfg.profiles[0].workspacePrefs["99"]) throw new Error("invalid ws pref dropped")
const lockedApp = m.normalizeAssignment({ workspace: 2, name: "Herdr", exec: "herdr", lockPlace: true })
if (!lockedApp.lockPlace) throw new Error("per-app lock")
if (!m.assignmentIsLocked(lockedApp, prefCfg.profiles[0])) throw new Error("effective lock")
if (!m.workspaceHasLockedApp({ assignments: [lockedApp], workspacePrefs: {} }, 2)) throw new Error("ws has lock")
if (m.workspaceHasLockedApp({ assignments: [{ workspace: 2, lockPlace: false }], workspacePrefs: {} }, 2)) throw new Error("ws unlocked")
const needGeom = m.ensureAssignmentGeoms([
  { workspace: 2, name: "Herdr", exec: "herdr", lockPlace: true },
  { workspace: 2, name: "Panel", exec: "panel", lockPlace: false }
], 2, { layout: "dwindle", visibleCount: 2 })
if (!needGeom[0].geom || needGeom[0].geom.x !== 0) throw new Error("lock captures left geom")
if (!needGeom[1].geom || needGeom[1].geom.x < 0.4) throw new Error("lock captures right geom")
const wrap = 'sh -c if echo "%u" | grep -q "^mailto:"; then exec omarchy-launch-webapp "https://outlook.office.com/mail/deeplink/compose?to=x"; else exec omarchy-launch-webapp "https://outlook.office.com/mail/"; fi'
if (!m.sameAppExec(wrap, "omarchy-launch-webapp 'https://outlook.office.com/mail/'")) throw new Error("outlook exec match")
if (m.canonicalExec(wrap).indexOf("outlook.office.com/mail") < 0) throw new Error("canonical outlook exec")
if (m.sameAppExec(wrap, "omarchy-launch-webapp 'https://calendar.google.com/'")) throw new Error("webapps must not share launcher name")
if (m.sameAppExec(wrap, "/home/user/.local/bin/brave")) throw new Error("outlook is not brave")
if (!m.sameAppExec("/home/user/.local/bin/brave", "/home/user/.local/bin/brave")) throw new Error("brave match")
const teamsPwa = "/opt/brave-bin/brave --profile-directory=Default --app-id=ompifgpmddkgmclendfeacglnodjjndh %U"
if (m.sameAppExec("/home/user/.local/bin/brave", teamsPwa)) throw new Error("brave must not match Teams PWA")
if (m.sameAppExec(teamsPwa, "/home/user/.local/bin/brave %U")) throw new Error("Teams PWA must not match brave")
if (!m.sameAppExec(teamsPwa, "/opt/brave-bin/brave --app-id=ompifgpmddkgmclendfeacglnodjjndh")) throw new Error("same PWA app-id")
if (m.sameAppExec(teamsPwa, "/opt/brave-bin/brave --app-id=otherid")) throw new Error("different PWA app-id")

if (m.suggestedProfileName([{ name: "eDP-1" }]) !== "Laptop") throw new Error("suggest laptop name")
if (!m.networkConfigured(m.captureNetwork({ ssid: "HomeNet", subnet: "192.168.1.0/24" }))) throw new Error("capture wifi")
const netHome = { ssids: ["HomeNet"], subnets: ["192.168.1.0/24"], connections: ["HomeNet"] }
const netOffice = { ssids: ["Office"], subnets: ["192.168.2.0/24"], connections: [] }
if (!m.networkMatches(netHome, { ssid: "HomeNet", subnet: "192.168.1.0/24" }).matches) throw new Error("ssid match")
if (m.networkMatches(netHome, { ssid: "Office", subnet: "192.168.2.0/24" }).matches) throw new Error("ssid mismatch")
if (!m.networksOverlap(netHome, { ssids: ["homenet"], subnets: [], connections: [] })) throw new Error("ssid overlap case")
if (m.networksOverlap(netHome, netOffice)) throw new Error("home/office must not overlap")
if (!m.networksOverlap(m.emptyNetwork(), m.emptyNetwork())) throw new Error("two fallbacks overlap")
if (m.networksOverlap(netHome, m.emptyNetwork())) throw new Error("bound vs fallback do not overlap")

const netCfg = m.sanitizeConfig({
  version: 2,
  settings: { activeProfileId: "home" },
  monitors: [laptop],
  profiles: [
    { id: "home", name: "Home", monitors: ["laptop"], network: netHome, claimedAt: 1 },
    { id: "office", name: "Office", monitors: ["laptop"], network: netOffice, claimedAt: 2 },
    { id: "any", name: "Any", monitors: ["laptop"], network: {}, claimedAt: 0 }
  ]
})
if (m.bestProfile(netCfg, liveLaptop, { ssid: "HomeNet", subnet: "192.168.1.0/24" }).id !== "home") throw new Error("home wifi wins")
if (m.bestProfile(netCfg, liveLaptop, { ssid: "Office", subnet: "192.168.2.0/24" }).id !== "office") throw new Error("office wifi wins")
if (m.bestProfile(netCfg, liveLaptop, { ssid: "Cafe", subnet: "10.0.0.0/24" }).id !== "any") throw new Error("unbound fallback on unknown net")
const office = netCfg.profiles.find(function(p) { return p.id === "office" })
const cafeHint = m.applyHint(netCfg, office, liveLaptop, { ssid: "Cafe", subnet: "10.0.0.0/24" })
if (cafeHint.matches) throw new Error("office should not match cafe")
if (cafeHint.text.indexOf("wrong network") < 0) throw new Error("hint says wrong network")
if (cafeHint.text.indexOf("Any") < 0 || cafeHint.text.indexOf("will apply") < 0) throw new Error("hint names fallback that will apply")
if (cafeHint.willId !== "any") throw new Error("will apply Any")
if (cafeHint.text.indexOf("currently applied") >= 0) throw new Error("unmatched profile must not look applied")
const anyHint = m.applyHint(netCfg, netCfg.profiles.find(function(p) { return p.id === "any" }), liveLaptop, { ssid: "Cafe", subnet: "10.0.0.0/24" })
if (!anyHint.matches || anyHint.text.indexOf("fallback") < 0) throw new Error("unbound profile is the fallback")
const homeHint = m.applyHint(netCfg, netCfg.profiles.find(function(p) { return p.id === "home" }), liveLaptop, { ssid: "HomeNet", subnet: "192.168.1.0/24" })
if (!homeHint.matches || homeHint.text.indexOf("this applies") < 0) throw new Error("home wifi this applies")
const noFallbackCfg = m.sanitizeConfig({
  version: 2,
  settings: { activeProfileId: "laptop" },
  monitors: [laptop],
  profiles: [{ id: "laptop", name: "Laptop", monitors: ["laptop"], network: netHome }]
})
const status = {
  matchedProfileId: null,
  matchedProfileName: null,
  needsNetworkWait: true,
  profiles: [{ id: "laptop", name: "Laptop", matches: false, reason: "network", networkConstrained: true, networkMatches: false }]
}
const workHint = m.applyHint(noFallbackCfg, noFallbackCfg.profiles[0], liveLaptop, { ssid: "CafeWifi", subnet: "192.168.2.0/24" }, status)
if (workHint.matches) throw new Error("laptop must not match work wifi")
if (workHint.text.indexOf("wrong network") < 0) throw new Error("work wifi is wrong network")
if (workHint.text.indexOf("no matching profile") < 0) throw new Error("no fallback means nothing applies")
if (workHint.text.indexOf("matches now") >= 0) throw new Error("must not say matches now")
const owner = m.environmentOwner(netCfg, "laptop", netHome, "home")
if (owner) throw new Error("home should uniquely own HomeNet")
const claimed = m.claimEnvironment(netCfg, "office", netHome)
if (!claimed.stolen.some(function(s) { return s.id === "home" })) throw new Error("steal HomeNet from home")
const homeAfter = claimed.config.profiles.find(function(p) { return p.id === "home" })
if (m.networkConfigured(homeAfter.network) && homeAfter.network.ssids.indexOf("HomeNet") >= 0) throw new Error("stolen ssid remains")
const parsed = m.parseNetworkText("HomeNet, Guest", "192.168.2.0/24", "")
if (parsed.ssids[1] !== "Guest" || parsed.subnets[0] !== "192.168.2.0/24") throw new Error("parse network text")
const boundLine = m.boundNetworkLine({ network: netHome }, { ssid: "HomeNet", subnet: "192.168.1.0/24" })
if (boundLine.indexOf("HomeNet") < 0 || boundLine.indexOf("connected now") < 0) throw new Error("bound line live")
if (m.matchReasonLabel("network") !== "wrong network") throw new Error("reason label")
if (m.maxWorkspace() !== 20) throw new Error("max ws 20")
const ovProf = { assignments: [{ workspace: 1 }, { workspace: 2 }], overflow: { enabled: true, workspaces: [5, 5, 0, 21, 6] } }
const ov = m.normalizeOverflow(ovProf.overflow)
if (ov.workspaces.join(",") !== "5,6") throw new Error("overflow unique 1-20")
if (ov.maxWindows !== 1) throw new Error("overflow default max 1")
if (m.normalizeOverflow({ enabled: true, workspaces: [8], maxWindows: 4 }).maxWindows !== 4) throw new Error("overflow max persist")
if (m.normalizeOverflow({ maxWindows: 99 }).maxWindows !== 20) throw new Error("overflow max clamp")
if (m.maxOrganizerPanes() !== 20) throw new Error("max panes 20")
if (m.dropZone(0.1, 0.5) !== "left") throw new Error("drop left")
if (m.dropZone(0.5, 0.5) !== "center") throw new Error("drop center")
const twoPanes = [{ x: 0, y: 0, w: 0.5, h: 1 }, { x: 0.5, y: 0, w: 0.5, h: 1 }]
const swapped = m.swapGeoms(twoPanes, 0, 1)
if (swapped[0].x !== 0.5) throw new Error("swap")
const splitR = m.splitDrop(twoPanes, 0, 1, "bottom")
if (!(splitR[1].h < 0.6 && splitR[0].h < 0.6)) throw new Error("split drop bottom")
if (m.clampOpacity(0.05) !== 0.2) throw new Error("opacity floor")
if (m.assignmentPlace({ place: "float" }) !== "float") throw new Error("place float")
const mixedPack = m.packedGeomsForApps([
  { id: "t", geom: { x: 0, y: 0, w: 0.5, h: 1 }, place: "tile" },
  { id: "f", geom: { x: 0.2, y: 0.2, w: 0.3, h: 0.3 }, place: "float" }
], "dwindle", 0.49)
if (Math.abs(mixedPack[0].w - 1) > 0.02) throw new Error("lone tiled pane fills under a float")
if (Math.abs(mixedPack[1].w - 0.3) > 0.02) throw new Error("keep float geom")
if (m.safeCwd("/tmp/foo; rm") !== "") throw new Error("cwd inject")
if (m.safeCwd("/home/user/project") !== "/home/user/project") throw new Error("cwd ok")
if (m.safeUrl("https://x.com' ; rm") !== "") throw new Error("url inject")
if (m.safeUrl("https://outlook.office.com/mail") !== "https://outlook.office.com/mail") throw new Error("url ok")
if (m.normalizeAssignment({ workspace: 1, exec: "foot", cwd: "/tmp/x;y" }).cwd) throw new Error("cwd stripped")
const pair = [
  { id: "a", geom: { x: 0, y: 0, w: 0.5, h: 1 }, place: "tile" },
  { id: "b", geom: { x: 0.5, y: 0, w: 0.5, h: 1 }, place: "tile" }
]
const floated = m.setAppsPlace(pair, 0, "float", "dwindle", 0.5)
if (floated[0].place !== "float") throw new Error("place float")
if (Math.abs(floated[1].w - 1) > 0.08) throw new Error("remaining tile should fill after float")
const tiledBack = m.setAppsPlace(floated, 0, "tile", "dwindle", 0.5)
if (tiledBack[0].place !== "tile") throw new Error("place tile")
if (m.layoutHasOverlap([tiledBack[0].geom, tiledBack[1].geom])) throw new Error("unfloat overlap")
if (Math.abs(tiledBack[0].w + tiledBack[1].w - 1) > 0.08 && Math.abs(tiledBack[0].h + tiledBack[1].h - 1) > 0.08)
  throw new Error("unfloat should share the workspace")
if (m.unsetWorkspaces(ovProf).indexOf(1) >= 0) throw new Error("unset excludes assigned")
if (m.unsetWorkspaces(ovProf).indexOf(5) < 0) throw new Error("unset includes 5")

function noOverlap(rects) {
  if (m.layoutHasOverlap(rects)) throw new Error("overlap in " + JSON.stringify(rects))
}
function areaOk(r) { return r && r.w > 0.03 && r.h > 0.03 }

const zeroPack = m.packedGeomsForApps([], "dwindle", 0.49)
if (zeroPack.length !== 0) throw new Error("zero apps pack empty")
const oneDwindle = m.autoLayoutRects(1, "dwindle", 0.49)
if (oneDwindle.length !== 1 || oneDwindle[0].w !== 1 || oneDwindle[0].h !== 1) throw new Error("dwindle 1 is full")
noOverlap(oneDwindle)
const dwindle3 = m.autoLayoutRects(3, "dwindle", 0.49)
if (dwindle3.length !== 3) throw new Error("dwindle 3 count")
dwindle3.forEach(function(r) { if (!areaOk(r)) throw new Error("dwindle 3 empty pane") })
noOverlap(dwindle3)
const scroll2 = m.autoLayoutRects(2, "scrolling", 0.5)
if (scroll2.length !== 2 || Math.abs(scroll2[0].w - 0.5) > 0.02 || Math.abs(scroll2[1].x - 0.5) > 0.02) throw new Error("scrolling columns")
noOverlap(scroll2)
const scroll1 = m.autoLayoutRects(1, "scrolling", 0.5)
if (scroll1.length !== 1 || scroll1[0].w !== 1 || scroll1[0].h !== 1) throw new Error("scrolling 1 is full even if visible columns is 2")
const leftoverCol = m.packedGeomsForApps(
  [{ id: "only", workspace: 2, geom: { x: 0, y: 0, w: 0.5, h: 1 }, place: "tile" }],
  "scrolling",
  0.5
)
if (Math.abs(leftoverCol[0].w - 1) > 0.02 || Math.abs(leftoverCol[0].x) > 0.02) throw new Error("single scrolling pane preview must fill after dropping the extra column")
const master3 = m.autoLayoutRects(3, "master", 0.5)
if (master3.length !== 3) throw new Error("master 3 count")
if (!(master3[0].w > 0.5 && master3[0].h === 1)) throw new Error("master left pane")
if (!(master3[1].x > 0.5 && master3[2].x > 0.5)) throw new Error("master stack on right")
if (Math.abs(master3[1].y + master3[1].h - master3[2].y) > 0.05) throw new Error("master stack stacked")
noOverlap(master3)
const stage3 = m.autoLayoutRects(3, "stage", 0.5)
if (stage3.length !== 3 || stage3[0].w !== 1) throw new Error("stage lead full")
if (!(stage3[1].w > 0.4 && stage3[1].w < 0.6)) throw new Error("stage extra width")
if (!(stage3[2].w > 0.4 && stage3[2].w < 0.6)) throw new Error("stage second extra width")
const sameType = m.packedGeomsForApps([
  { id: "f1", exec: "foot", geom: { x: 0, y: 0, w: 0.5, h: 1 } },
  { id: "f2", exec: "foot", geom: { x: 0.5, y: 0, w: 0.5, h: 1 } }
], "dwindle", 0.49)
if (sameType[0].id !== "f1" || sameType[1].id !== "f2") throw new Error("same-type keep order")
noOverlap(sameType.map(function(a) { return a.geom || a }))

const holeFill = m.fillHole(
  [{ x: 0, y: 0, w: 0.5, h: 1 }, { x: 0.5, y: 0.5, w: 0.5, h: 0.5 }],
  { x: 0.5, y: 0, w: 0.5, h: 0.5 },
  {}
)
if (Math.abs(holeFill[1].y) > 0.02 || Math.abs(holeFill[1].h - 1) > 0.05) throw new Error("fillHole grows neighbor into hole")

const splitPair = [
  { id: "left", workspace: 2, geom: { x: 0, y: 0, w: 0.5, h: 1 }, place: "tile" },
  { id: "right", workspace: 2, geom: { x: 0.5, y: 0, w: 0.5, h: 1 }, place: "tile" },
  { id: "other", workspace: 3, geom: { x: 0, y: 0, w: 0.4, h: 1 }, place: "tile" }
]
const afterRm = m.removeAppAndFill(splitPair, "left")
if (afterRm.length !== 2) throw new Error("remove drops one")
const stay = afterRm.find(function(a) { return a.id === "right" })
if (!stay || Math.abs(stay.geom.w - 1) > 0.04 || Math.abs(stay.geom.x) > 0.04) throw new Error("remaining tile should fill the hole")
const other = afterRm.find(function(a) { return a.id === "other" })
if (Math.abs(other.geom.w - 0.4) > 0.02) throw new Error("other workspace geoms stay")
const threePanes = [
  { id: "a", workspace: 1, geom: { x: 0, y: 0, w: 0.5, h: 1 } },
  { id: "b", workspace: 1, geom: { x: 0.5, y: 0, w: 0.5, h: 0.5 } },
  { id: "c", workspace: 1, geom: { x: 0.5, y: 0.5, w: 0.5, h: 0.5 } }
]
const afterC = m.removeAppAndFill(threePanes, "c")
if (afterC.length !== 2) throw new Error("dwindle remove count")
noOverlap([afterC[0].geom, afterC[1].geom])
const bStay = afterC.find(function(a) { return a.id === "b" })
if (Math.abs(bStay.geom.h - 1) > 0.06) throw new Error("upper-right should grow into closed pane")
const lastOne = m.removeAppAndFill(afterC, "a")
if (lastOne.length !== 1 || Math.abs(lastOne[0].geom.w - 1) > 0.02 || Math.abs(lastOne[0].geom.h - 1) > 0.02)
  throw new Error("last pane fills the workspace")
const floatPair = [
  { id: "t", workspace: 1, geom: { x: 0, y: 0, w: 1, h: 1 }, place: "tile" },
  { id: "f", workspace: 1, geom: { x: 0.2, y: 0.2, w: 0.3, h: 0.3 }, place: "float" }
]
const afterFloat = m.removeAppAndFill(floatPair, "f")
if (afterFloat.length !== 1 || Math.abs(afterFloat[0].geom.w - 1) > 0.02) throw new Error("removing a float leaves tiles")

const leftFloat = [
  { id: "L", geom: { x: 0, y: 0, w: 0.5, h: 1 }, place: "tile" },
  { id: "R", geom: { x: 0.5, y: 0, w: 0.5, h: 1 }, place: "tile" }
]
const floatedL = m.setAppsPlace(leftFloat, 0, "float", "dwindle", 0.5)
floatedL[0].geom = { x: 0.05, y: 0.2, w: 0.3, h: 0.4 }
const snapL = m.setAppsPlace(floatedL, 0, "tile", "dwindle", 0.5)
if (snapL[0].place !== "tile") throw new Error("unfloat left place")
if (snapL[0].x >= 0.5 && snapL[0].geom && snapL[0].geom.x >= 0.5) throw new Error("unfloat left should snap into left tile")
noOverlap([snapL[0].geom, snapL[1].geom])
const rightFloat = [
  { id: "L", geom: { x: 0, y: 0, w: 0.5, h: 1 }, place: "tile" },
  { id: "R", geom: { x: 0.5, y: 0, w: 0.5, h: 1 }, place: "tile" }
]
const floatedR = m.setAppsPlace(rightFloat, 1, "float", "dwindle", 0.5)
floatedR[1].geom = { x: 0.65, y: 0.2, w: 0.3, h: 0.4 }
const snapR = m.setAppsPlace(floatedR, 1, "tile", "dwindle", 0.5)
if (!(snapR[1].geom.x >= 0.45)) throw new Error("unfloat right should snap into right tile")
noOverlap([snapR[0].geom, snapR[1].geom])

const chromeClamp = m.normalizeChrome({
  opacityActive: 0,
  opacityInactive: 9,
  borderSize: 99,
  borderColorActive: "red;rm",
  borderColorInactive: "#aabbccddEE"
})
if (chromeClamp.opacityActive !== 0.2) throw new Error("chrome opacity floor")
if (chromeClamp.opacityInactive !== 1) throw new Error("chrome opacity ceil")
if (chromeClamp.borderSize !== -1) throw new Error("chrome size clamp")
if (chromeClamp.borderColorActive.indexOf(";") >= 0 || chromeClamp.borderColorActive.length > 9)
  throw new Error("chrome color strips junk and caps length")
if (chromeClamp.borderColorInactive !== "#aabbccdd") throw new Error("chrome color hex keep")
if (!m.chromeIsDefault(m.normalizeChrome({}))) throw new Error("empty chrome is default")
const withChrome = m.normalizeAssignment({ workspace: 2, exec: "foot", chrome: { opacityActive: 0.5, borderSize: 3, borderColorActive: "#ff8800" } })
if (!withChrome.chrome || withChrome.chrome.opacityActive !== 0.5 || withChrome.chrome.borderSize !== 3) throw new Error("chrome persist on assignment")
const noChrome = m.normalizeAssignment({ workspace: 2, exec: "foot" })
if (noChrome.chrome) throw new Error("default chrome omitted")

const isoCfg = m.sanitizeConfig({
  version: 2,
  profiles: [{
    id: "p",
    name: "P",
    workspacePrefs: {
      "1": { layout: "dwindle", visibleCount: 2, extras: "around" },
      "2": { layout: "scrolling", visibleCount: 3, extras: "block", lockSizes: true }
    },
    overflow: { enabled: true, workspaces: [5, 6], maxWindows: 2 },
    assignments: [{ workspace: 1, exec: "foot", name: "A" }, { workspace: 2, exec: "foot", name: "B" }]
  }]
})
const p2 = isoCfg.profiles[0]
p2.workspacePrefs["2"] = m.normalizeWorkspacePref({ layout: "master", visibleCount: 3, extras: "block", lockSizes: true })
if (p2.workspacePrefs["1"].layout !== "dwindle") throw new Error("layout change must not touch other ws")
if (p2.workspacePrefs["1"].visibleCount !== 2) throw new Error("visibleCount isolation")
if (p2.assignments[0].exec !== "foot" || p2.assignments[1].name !== "B") throw new Error("pref change must not rewrite apps")
if (m.normalizeOverflow(p2.overflow).workspaces.join(",") !== "5,6") throw new Error("overflow isolation")
p2.workspacePrefs["1"] = m.normalizeWorkspacePref({ layout: "dwindle", visibleCount: 8, extras: "around" })
if (p2.workspacePrefs["2"].layout !== "master") throw new Error("visible bump isolation")
if (m.clampVisibleCount(8) !== 8) throw new Error("visible 8")
const ovBlock = m.normalizeWorkspacePref({ extras: "block" })
const ovAround = m.normalizeWorkspacePref({ extras: "around" })
if (ovBlock.extras !== "block" || ovAround.extras !== "around") throw new Error("extras block vs around")
if (m.maxOrganizerPanes() !== 20) throw new Error("cap 20")
const twenty = m.autoLayoutRects(20, "dwindle", 0.49)
if (twenty.length !== 20) throw new Error("20 panes")
noOverlap(twenty)

const named = m.upsertLiveMonitor({
  monitors: [{ id: "desk-left", label: "Desk left (HP E24)", serial: "", description: "HP Inc. HP E24 G5 SN-LEFT", name: "" }]
}, { name: "DVI-I-1", description: "HP Inc. HP E24 G5 SN-LEFT", serial: "", make: "HP Inc.", model: "HP E24 G5" })
const filled = named.config.monitors.find(function(x) { return x.id === "desk-left" })
if (!filled || filled.name !== "DVI-I-1") throw new Error("upsert fills empty connector name")

console.log("model.test.js ok")
