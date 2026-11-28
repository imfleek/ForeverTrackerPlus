-- RestedXP's window hidden by RestedXP itself pauses its engine (RXP.isHidden); the RXP Tracker keeps it running and
-- redraws on quest progress; its guide features (automation, timers, arrow) work while its window is hidden.
local A = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local timers = {}
_G.C_Timer = { After = function(_, f) timers[#timers + 1] = f end }
local function run() while #timers > 0 do table.remove(timers, 1)() end end

local registered, onEvent = {}, nil
_G.CreateFrame = function()
	return {
		RegisterEvent = function(_, e) registered[e] = true end,
		RegisterUnitEvent = function(_, e, u) registered[e] = u end,
		SetScript = function(_, k, f) if k == "OnEvent" then onEvent = f end end,
	}
end

local shown, scripts = true, {}
local rxpFrame = { IsShown = function() return shown end,
	HookScript = function(_, k, f) scripts[k] = scripts[k] or {}; table.insert(scripts[k], f) end }
local profile = { showEnabled = true, hideGuideWindow = false }
local automationSaw
local RXP = { isHidden = false, RXPFrame = rxpFrame }
RXP.QuestAutomation = function() automationSaw = RXP.isHidden end
local lastGossipSaw
local optionSaw
RXP.functions = { skipgossip = function() lastGossipSaw = RXP.isHidden end, gossipoption = function() optionSaw = RXP.isHidden end }
local function hide() shown = false; RXP.isHidden = true; for _, f in ipairs(scripts.OnHide or {}) do f() end end
local function show() shown = true; RXP.isHidden = false; for _, f in ipairs(scripts.OnShow or {}) do f() end end

local invalidated, views, messages = 0, {}, {}
local ns = { rxp = RXP, db = { enabled = true }, rxpProfile = function() return profile end,
	invalidate = function() invalidated = invalidated + 1 end, suspended = function() return false end,
	onView = function(f) views[#views + 1] = f end, onRxpMessage = function(m, f) messages[m] = f end }
local root = { objectives = ns }
_G.EnumerateFrames = nil
assert(loadfile(A .. "/Objectives/features/RxpFixes.lua"))("x", root)
assert(loadfile(A .. "/Objectives/features/RxpAwake.lua"))("x", root)
local gossipHandler = RXP.functions.skipgossip -- as RestedXP binds it when a step becomes active
check("gossip step handler wrapped", type(gossipHandler) == "function")

check("quest events registered (UNIT_QUEST_LOG_CHANGED for the player)", registered.QUEST_LOG_UPDATE
	and registered.QUEST_WATCH_UPDATE and registered.QUEST_TURNED_IN and registered.UNIT_QUEST_LOG_CHANGED == "player")
check("RestedXP shown: left alone", RXP.isHidden == false and not ns.rxpAsleep())

hide()
check("RestedXP hides its window: its engine kept running", RXP.isHidden == false and ns.rxpAsleep())
RXP.QuestAutomation()
check("automation setting off (default): quest automation sees RestedXP hidden", automationSaw == true
	and RXP.isHidden == false)
gossipHandler()
check("automation setting off: gossip step handlers see RestedXP hidden", lastGossipSaw == true and RXP.isHidden == false)
ns.db.hiddenAutomation = true
RXP.QuestAutomation()
check("3.2 setting on: quest automation is ours, still sees RestedXP hidden", automationSaw == true
	and RXP.isHidden == false)
gossipHandler()
check("3.2 setting on: .skipgossip is ours, still hidden", lastGossipSaw == true)
RXP.functions.gossipoption()
check("3.2 setting on: .gossipoption (not ours) runs", optionSaw == false)
ns.db.hiddenAutomation = false
RXP.functions.gossipoption()
check("3.2 setting off: .gossipoption sees RestedXP hidden", optionSaw == true)
ns.db.hiddenAutomation = true
local okErr = pcall(function() ns.db.hiddenAutomation = false; ns.runRxpAutomation(function() error("boom") end) end)
check("automation off: an error is passed on and the engine stays awake", not okErr and RXP.isHidden == false)
ns.db.hiddenAutomation = true

invalidated = 0
onEvent(nil, "QUEST_LOG_UPDATE"); onEvent(nil, "UNIT_QUEST_LOG_CHANGED", "player"); onEvent(nil, "QUEST_WATCH_UPDATE")
check("quest progress: one coalesced redraw", invalidated == 0 and #timers == 1)
run()
check("redrawn after the delay", invalidated == 1)
onEvent(nil, "UNIT_QUEST_LOG_CHANGED", "party1")
check("another unit's quest log ignored", #timers == 0)

-- RestedXP zoning (PLAYER_LEAVING_WORLD) or its PLAYER_ENTERING_WORLD sets isHidden again
RXP.isHidden = true
onEvent(nil, "PLAYER_ENTERING_WORLD"); run()
check("re-woken after RestedXP's PLAYER_ENTERING_WORLD", RXP.isHidden == false)
RXP.isHidden = true
onEvent(nil, "QUEST_LOG_UPDATE")
check("re-woken by quest progress", RXP.isHidden == false)
run()

ns.db.enabled = false
for _, f in ipairs(views) do f() end
check("guide display off: RestedXP paused again, as it had it", RXP.isHidden == true and not ns.rxpAsleep())
RXP.QuestAutomation()
check("guide display off: automation as RestedXP has it (off)", automationSaw == true)
ns.db.enabled = true
for _, f in ipairs(views) do f() end
check("guide display on again: woken", RXP.isHidden == false)

show()
check("RestedXP shows its window: its own state", RXP.isHidden == false and not ns.rxpAsleep())
RXP.QuestAutomation()
check("automation as RestedXP has it while shown", automationSaw == false)

profile.standbyMode, profile.showEnabled = true, false
hide()
check("standby mode with the guide toggled off: left paused", RXP.isHidden == true and not ns.rxpAsleep())
profile.standbyMode, profile.showEnabled = nil, true
show()

profile.hideGuideWindow = true
hide()
check("'Hide Window' setting: kept running", RXP.isHidden == false and ns.rxpAsleep())

-- Waypoint arrow: RestedXP's map passes only show it with showEnabled on (map.lua updateArrowData)
profile.hideGuideWindow = false
show()
local arrowShown, mapFlagged, nestedSaw = false, 0, nil
local function arrowPass() arrowShown = not profile.disableArrow and profile.showEnabled and true or false end
local arrowScripts = {}
RXP.arrowFrame = { HookScript = function(_, k, f) arrowScripts[k] = f end }
RXP.UpdateMap = function(reset) if reset then arrowPass() else mapFlagged = mapFlagged + 1 end end
RXP.UpdateGotoSteps = function() RXP.UpdateMap(); nestedSaw = profile.showEnabled; arrowPass() end
scripts = {}
local ns2 = setmetatable({ onView = function() end }, { __index = ns })
assert(loadfile(A .. "/Objectives/features/RxpAwake.lua"))("x", { objectives = ns2 })

RXP.UpdateMap(true)
check("arrow: RestedXP shown, arrow shown as before", arrowShown and profile.showEnabled == true)
-- minimap toggle: showEnabled off, every window hidden, the arrow too
profile.showEnabled = false
hide()
mapFlagged = 0
arrowScripts.OnHide()
check("arrow hidden by the toggle: a map pass is asked for", mapFlagged == 1)
RXP.UpdateMap(true)
check("arrow: map pass places it while the guide display is on", arrowShown and profile.showEnabled == false)
arrowShown = false
RXP.UpdateGotoSteps()
check("arrow: goto pass too, with its nested UpdateMap keeping the setting", arrowShown and nestedSaw == true
	and profile.showEnabled == false)
profile.disableArrow = true
RXP.UpdateMap(true)
check("arrow: 'Hide waypoint arrow' still hides it", not arrowShown)
profile.disableArrow = nil
ns.db.enabled = false
RXP.UpdateMap(true)
check("arrow: guide display off, RestedXP's own rule (hidden)", not arrowShown and profile.showEnabled == false)
mapFlagged = 0
arrowScripts.OnHide()
check("arrow: no map pass asked for when not kept", mapFlagged == 0)
ns.db.enabled = true

-- Timers: RestedXP starts one only while RXPFrame is shown; its toggle hides running bars (dropping them)
local bars, faded = {}, 0
rxpFrame.IsShown = function() return shown end
local function startTimer(duration, label)
	if not RXP.RXPFrame:IsShown() then return end
	bars[label] = { running = true, exp = duration }
	return bars[label]
end
RXP.StartTimer = startTimer
RXP.PLAYER_CONTROL_LOST = function() if RXP.RXPFrame:IsShown() and profile.showFlightTimers then startTimer(60, "flight") end end
RXP.HideTimers = function() for k in pairs(bars) do bars[k] = nil end end
scripts = {}
local ns3 = setmetatable({ onView = function() end, fadeTimers = function() faded = faded + 1 end }, { __index = ns })
assert(loadfile(A .. "/Objectives/features/RxpAwake.lua"))("x", { objectives = ns3 })
profile.showEnabled = false -- toggled off; RXPFrame hidden (shown = false from the arrow part)
check("timers: window hidden", not shown and ns3.rxpAsleep())
faded = 0
check("timers: a step timer starts while hidden", RXP.StartTimer(30, "step") ~= nil and bars.step and faded > 0)
check("timers: RXPFrame's own IsShown back after the pass", rawget(rxpFrame, "IsShown") ~= nil and not rxpFrame:IsShown())
profile.showFlightTimers = true
RXP:PLAYER_CONTROL_LOST()
check("timers: flight timer starts while hidden", bars.flight ~= nil)
RXP.HideTimers()
check("timers: the toggle fades instead of dropping them", bars.step ~= nil and bars.flight ~= nil)
profile.showFlightTimers = false
RXP.HideTimers()
check("timers: 'Show Flight Timers' off still hides them", next(bars) == nil)
bars.flight = nil
RXP:PLAYER_CONTROL_LOST()
check("timers: no flight timer with the setting off", bars.flight == nil)
ns.db.enabled = false
check("timers: guide display off, RestedXP's rule (none while hidden)", RXP.StartTimer(30, "step2") == nil)
ns.db.enabled = true

-- R105-7: hardened wrappers (all return values, RestedXP's own stack on an error, functions RestedXP puts in later)
local function manyReturns(...) return RXP.RXPFrame:IsShown(), 2, 3, 4, select("#", ...) end
RXP.StartTimer = manyReturns
check("wrapper: a function RestedXP puts in later is left until the next sync", RXP.StartTimer == manyReturns)
ns3.syncRxpAwake()
local r = { RXP.StartTimer("a", nil, "c") }
check("wrapper: a function RestedXP puts in later is wrapped on the next sync", RXP.StartTimer ~= manyReturns
	and r[1] == true)
check("wrapper: every return value and argument passes through", r[2] == 2 and r[4] == 4 and r[5] == 3)
local wrapped = RXP.StartTimer
ns3.syncRxpAwake()
check("wrapper: never wrapped twice", RXP.StartTimer == wrapped)
_G.debugstack = function() return "RESTEDXP STACK" end
RXP.StartTimer = function() error("boom") end
ns3.syncRxpAwake()
local okErr, err = pcall(RXP.StartTimer)
check("wrapper: an error goes on, with RestedXP's own stack in its text", not okErr and tostring(err):find("boom", 1, true)
	and tostring(err):find("RESTEDXP STACK", 1, true))
check("wrapper: after an error RXPFrame's own IsShown is back", not rxpFrame:IsShown())
RXP.StartTimer = manyReturns
ns3.syncRxpAwake()
check("wrapper: after an error the next pass works", (RXP.StartTimer()) == true)
profile.showEnabled = false
RXP.UpdateMap = function() error("map") end
ns3.syncRxpAwake()
pcall(RXP.UpdateMap, true)
check("wrapper: after an error in a map pass showEnabled is back", profile.showEnabled == false)
RXP.UpdateMap = function() end
_G.debugstack = nil
-- automation: a nested pass keeps isHidden as the outer one set it
RXP.isHidden = true
ns3.syncRxpAwake()
ns.db.hiddenAutomation = false
local inner
ns3.runRxpAutomation(function() ns3.runRxpAutomation(function() inner = RXP.isHidden end) end)
check("automation off: a nested pass also sees RestedXP hidden, awake again after", inner == true
	and RXP.isHidden == false)
ns.db.hiddenAutomation = true

-- R106-12: RestedXP's item bar and active targets window follow its "Show all Enabled Frames" (showEnabled): off,
-- they stay hidden, also while the guide is kept running (R105-10 undone)
local itemShown, targetShown
local updateItem = function() itemShown = profile.showEnabled and not profile.disableItemWindow and true or false end
local updateTargets = function(self) targetShown = self == RXP.targeting and profile.showEnabled and true or false end
RXP.UpdateItemFrame = updateItem
RXP.targeting = { UpdateTargetFrame = updateTargets }
local message
local ns4 = setmetatable({ onView = function() end, rxpWindowsHidden = function() return false end,
	onRxpMessage = function(_, f) message = f end }, { __index = ns })
scripts = {}
assert(loadfile(A .. "/Objectives/features/RxpAwake.lua"))("x", { objectives = ns4 })
check("item bar / active targets: not wrapped", RXP.UpdateItemFrame == updateItem
	and RXP.targeting.UpdateTargetFrame == updateTargets)
profile.showEnabled = false -- "Show all Enabled Frames" off (or the minimap toggle)
message()
RXP.UpdateItemFrame(); RXP.targeting:UpdateTargetFrame()
check("Show all Enabled Frames off: the active targets window stays hidden", not targetShown)
check("Show all Enabled Frames off: the item bar stays hidden", not itemShown)
local windowsSrc = io.open(A .. "/Objectives/features/Windows.lua"):read("a")
check("Windows.lua shows no RestedXP window with showEnabled off",
	windowsSrc:find("window:SetShown(not hidden and enabled and ns.rxpProfile().showEnabled ~= false)", 1, true) ~= nil
	and windowsSrc:find("KEPT_WINDOWS", 1, true) == nil)
profile.showEnabled = true
RXP.UpdateItemFrame(); RXP.targeting:UpdateTargetFrame()
check("on: both show as RestedXP has it", itemShown and targetShown)

-- NPC step actions (.fly, .fp, .home, .buy, .deathskip, .tradeskill) follow the automation setting too
local flySaw = {}
RXP.functions.fly = function(self, event) flySaw[#flySaw + 1] = event or "nil"; return "flew" end
ns4.keepRxpWrapped()
check(".fly wrapped once RestedXP has it", RXP.functions.fly ~= nil and flySaw[1] == nil)
RXP.isHidden = true
ns4.syncRxpAwake()
check(".fly: RestedXP hidden and kept running", RXP.isHidden == false)
ns.db.hiddenAutomation = false
local element = {}
RXP.functions.fly(element, "TAXIMAP_OPENED")
check(".fly, setting off: no flight taken at the flight master", #flySaw == 0)
RXP.functions.fly(element, "WindowUpdate")
check(".fly, setting off: its own window pass still runs", flySaw[1] == "WindowUpdate")
check(".fly: guide parse still runs (step text)", RXP.functions.fly("Fly to Booty Bay", "", "Booty Bay") == "flew")
ns.db.hiddenAutomation = true
check(".fly, setting on: flight taken", RXP.functions.fly(element, "TAXIMAP_OPENED") == "flew"
	and flySaw[#flySaw] == "TAXIMAP_OPENED")
ns.db.hiddenAutomation = false
show()
ns4.syncRxpAwake()
check(".fly, setting off, RestedXP shown: flight taken, as RestedXP has it",
	RXP.functions.fly(element, "TAXIMAP_OPENED") == "flew")
ns.db.hiddenAutomation = true
print(pass and "PASS" or "FAILED")
