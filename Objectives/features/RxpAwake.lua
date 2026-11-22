local _, root = ...; local ns = root.objectives
local timed = root.timed or function(_, fn, ...) return fn(...) end -- /qt lag (Bootstrap.lua)
if not ns.rxp then return end

local RXP, db = ns.rxp, ns.db

-- RestedXP pauses its whole guide engine while its own window is hidden (its minimap toggle, "Hide Window", or
-- anything hiding RXPFrame): RXPFrame's OnHide sets RXP.isHidden (RXPGuides.lua PLAYER_LEAVING_WORLD, v4.11.36), and
-- then its step element handlers return early (GuideWindow.lua ActiveStepElementEventHandler, functions.lua) and its
-- update ticker stops (RXPGuides.lua tickers:ShouldContinue). Objective counts, completed steps and the next step then
-- never reach the RXP Tracker, which shows RestedXP's step rows. While the RXP Tracker shows the guide, the engine is
-- kept running with RestedXP's window left hidden. The skin's own hiding (Windows.lua) fades instead, so it never
-- needs this.
-- Everything gated on isHidden comes back with it: quest/gossip automation (auto accept, turn in, gossip options;
-- only when chosen in /qt, see runAutomation below),
-- step auto-skip (xp, reputation, skills, zones, quest state, ...), timers and countdowns, waypoints, map and minimap
-- pins, the quest log cleanup button. RestedXP's own settings (enableQuestAutomation, disableAutoSkip, disableArrow,
-- showFlightTimers, ...) still decide each of them.
-- CONSTRAINT: RestedXP's standby mode ("standbyMode" with the guide toggled off) means stay idle: left as it is.

local awake = false -- RestedXP had set isHidden and this file cleared it

-- Wrappers around RestedXP functions (below): each sets something for one pass of RestedXP's own function and puts it
-- back after (restore). Every return value passes through; on an error the setting is put back first and the error
-- goes on with RestedXP's own stack in its text, as if unwrapped.
local function traced(err)
	return tostring(err) .. (debugstack and ("\n" .. debugstack(2)) or "")
end
local function settle(restore, ok, ...)
	restore()
	if not ok then error((...), 0) end
	return ...
end
local function around(restore, original, ...)
	return settle(restore, xpcall(original, traced, ...))
end

-- CONSTRAINT: RestedXP (an update, a module loading late) may put a new function in a wrapped field; each sync wraps
-- the new one. Our wrappers are known, so one is never wrapped twice; one another addon put around ours is wrapped
-- again, and the depth guards below keep the nested pass plain.
local ours = setmetatable({}, { __mode = "k" })
local wraps = {}
local function wrapField(entry)
	local tbl, key, make = entry[1], entry[2], entry[3]
	local current = type(tbl) == "table" and tbl[key] or nil
	if type(current) ~= "function" or ours[current] then return end
	local wrapper = make(current)
	ours[wrapper] = true
	tbl[key] = wrapper
end
local function wrap(tbl, key, make)
	local entry = { tbl, key, make }
	wraps[#wraps + 1] = entry
	wrapField(entry)
end
local function keepWrapped()
	for i = 1, #wraps do wrapField(wraps[i]) end
end
ns.keepRxpWrapped = keepWrapped

local function rxpWindowHidden()
	local profile = ns.rxpProfile()
	local frame = RXP.RXPFrame
	local shown = type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown()
	return profile.hideGuideWindow or profile.showEnabled == false or not shown
end

local function wanted()
	local profile = ns.rxpProfile()
	if profile.standbyMode and profile.showEnabled == false then return false end
	return db.enabled and not (ns.suspended and ns.suspended())
end

-- whether RestedXP's window is hidden while this file keeps its guide features running
local function keeping()
	return wanted() and rxpWindowHidden() and true or false
end
ns.rxpAsleep = keeping

local function fadeTimers()
	if ns.fadeTimers then ns.fadeTimers() end
end

local function sync()
	keepWrapped()
	local hidden = rxpWindowHidden()
	if awake and not hidden then
		awake = false -- RestedXP shows its window again: its own state from here on
	elseif wanted() then
		if hidden and RXP.isHidden then
			RXP.isHidden = false
			awake = true
			-- waypoints and arrow placed again on the next ticker pass (UpdateMap with no argument only flags it)
			if type(RXP.UpdateMap) == "function" then RXP.UpdateMap() end
			ns.invalidate()
		end
	elseif awake then
		awake = false
		RXP.isHidden = true
	end
	fadeTimers()
end
ns.syncRxpAwake = sync

-- Quest and gossip automation (auto accept, turn in, gossip options) while RestedXP's window is hidden and kept
-- running here: off unless chosen in /qt (db.hiddenAutomation), so hiding RestedXP still stops it acting at NPCs, as
-- RestedXP has it. Off: each pass sees isHidden as RestedXP set it (true), then the engine is awake again.
-- RestedXP's own settings (enableQuestAutomation, enableGossipAutomation, Ctrl / Shift) still decide when it is on.
-- CONSTRAINT: the automation paths (v4.11.36): RXP.QuestAutomation (RxpFixes.lua's wrapper calls this), and the
-- .skipgossip / .skipgossipid / .gossipoption step handlers (functions.lua), which RestedXP binds from
-- RXP.functions when a step becomes active (GuideWindow.lua BindActiveStepElement).
local function automationBlocked()
	return awake and not db.hiddenAutomation
end
ns.rxpAutomationBlocked = automationBlocked
local automationDepth = 0
local function restoreAwake()
	automationDepth = 0
	if awake then RXP.isHidden = false end
end
local function runAutomation(original, ...)
	if automationDepth > 0 or not automationBlocked() then return original(...) end
	RXP.isHidden, automationDepth = true, 1
	return around(restoreAwake, original, ...)
end
ns.runRxpAutomation = runAutomation
local function asAutomation(original)
	return function(...) return runAutomation(original, ...) end
end
for _, tag in ipairs({"skipgossip", "skipgossipid", "gossipoption"}) do wrap(RXP.functions, tag, asAutomation) end
-- Step handlers that act at an NPC without an isHidden check of their own (RestedXP's only gate for them is its event
-- dispatcher, ActiveStepElementEventHandler): .fly (flight master gossip, TakeTaxiNode), .fp (learns the flight
-- path), .home (sets the hearthstone, ConfirmBinder), .buy (BuyMerchantItem), .deathskip (spirit healer),
-- .tradeskill (BuyTrainerService). Off: a game event is not passed to them, as RestedXP has it while hidden; so the
-- step does not complete by itself either. Its guide parse (self is the step text) and its own window passes
-- (WindowUpdate, TaskUpdate) still run.
local OWN_PASSES = { WindowUpdate = true, TaskUpdate = true }
local function asNpcAction(original)
	return function(self, event, ...)
		if type(self) ~= "string" and automationDepth == 0 and automationBlocked()
			and not (event == nil or OWN_PASSES[event]) then
			return
		end
		return original(self, event, ...)
	end
end
for _, tag in ipairs({"fly", "fp", "home", "buy", "deathskip", "tradeskill"}) do wrap(RXP.functions, tag, asNpcAction) end

-- Quest progress: also redraw from our own events, coalesced, after RestedXP's handlers have had their pass.
local REFRESH_DELAY = 0.2
local queued = false
local function questChanged()
	timed("guide: keep RestedXP awake", sync)
	if queued then return end
	queued = true
	C_Timer.After(REFRESH_DELAY, function()
		queued = false
		timed("guide steps redraw", ns.invalidate)
	end)
end

local QUEST_EVENTS = {"QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED"}
local watcher = CreateFrame("Frame")
local function valid(event)
	local utils = _G.C_EventUtils
	if type(utils) == "table" and type(utils.IsEventValid) == "function" then return utils.IsEventValid(event) end
	return true
end
local function watch(event, unit)
	if not valid(event) then return end
	if unit and watcher.RegisterUnitEvent then
		pcall(watcher.RegisterUnitEvent, watcher, event, unit)
	else
		pcall(watcher.RegisterEvent, watcher, event)
	end
end
for _, event in ipairs(QUEST_EVENTS) do watch(event) end
watch("UNIT_QUEST_LOG_CHANGED", "player")
watch("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_ENTERING_WORLD" then
		-- RestedXP sets isHidden again from its window on this event; ours may run first
		C_Timer.After(0, sync)
	elseif event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then
		return
	else
		questChanged()
	end
end)

-- RestedXP's window going away or coming back (its OnHide/OnShow scripts run first, HookScript after them)
local frame = RXP.RXPFrame
if type(frame) == "table" and type(frame.HookScript) == "function" then
	frame:HookScript("OnHide", sync)
	frame:HookScript("OnShow", sync)
end
ns.onRxpMessage("RXPGuidesV2_GuideWindowRefresh", function() sync() end)

-- The waypoint arrow (RestedXP's arrowFrame, which the RXP Tracker's arrow button sits on). Its data comes from the
-- ticker kept running above; but RestedXP's guide toggle (minimap click, ToggleActive) also sets showEnabled off,
-- hides the arrow with its other windows and then only shows it with showEnabled on (map.lua updateArrowData, the
-- only showEnabled read on that path). While the guide display is on, those two map passes see showEnabled on, and
-- the arrow is placed again after the toggle hid it. Its own settings (disableArrow, hideArrow in instances, no
-- waypoint) still decide.
local function keepArrow()
	return wanted() and ns.rxpProfile().showEnabled == false
end
ns.keepRxpArrow = keepArrow

-- CONSTRAINT: UpdateGotoSteps calls UpdateMap: only the outermost pass sets and restores the setting.
local depth = 0
local function restoreShown()
	ns.rxpProfile().showEnabled, depth = false, 0
end
-- a pass of RestedXP's function that sees showEnabled on while keep() says so
local function shownWhile(keep)
	return function(original)
		return function(...)
			if depth > 0 or not keep() then return original(...) end
			ns.rxpProfile().showEnabled, depth = true, 1
			return around(restoreShown, original, ...)
		end
	end
end
-- CONSTRAINT: RestedXP calls both through its table (ticker CycleZero / CycleThree, the world map's OnShow); the
-- arrow work inside map.lua (updateArrowData) is local and only reached through these.
local asShown = shownWhile(keepArrow)
for _, name in ipairs({"UpdateMap", "UpdateGotoSteps"}) do wrap(RXP, name, asShown) end

-- CONSTRAINT: RestedXP's active item bar (RXPItemFrame) and active targets window (RXPTargetFrame) are left to
-- RestedXP's "Show all Enabled Frames" (showEnabled): off, they stay hidden (user, R106-12). Their buttons are filled
-- either way, so the tracker's circles keep working.

local function requestArrow()
	if keepArrow() and type(RXP.UpdateMap) == "function" then RXP.UpdateMap() end -- flag only: next ticker pass
end
local af = RXP.arrowFrame
if type(af) == "table" and type(af.HookScript) == "function" then af:HookScript("OnHide", requestArrow) end
-- RestedXP sends it after its toggle has hidden its windows (SettingsPanel.lua ToggleActive)
ns.onRxpMessage("RXPGuidesV2_GuideWindowRefresh", requestArrow)
-- the guide display turned on or off (/qt), or a stand-down: after each refresh
ns.onView(sync)
sync()

-- Timers (step .timer / countdowns, hearthstone batching, flight timers): RestedXP starts one only while RXPFrame is
-- shown (Timers.lua StartTimer and PLAYER_CONTROL_LOST), and its guide toggle hides the running ones (HideTimers),
-- which drops them from the list the RXP Tracker reads (ns.activeTimer). While its window is hidden and the guide
-- display is on, those passes see RXPFrame shown, a toggle fades the bars instead of hiding them, and the bars stay
-- faded (they are UIParent children: Windows.lua ns.fadeTimers). showFlightTimers off still hides them.
-- CONSTRAINT: RestedXP calls these through its table (addon.StartTimer; AceEvent looks the event method up when it
-- fires), so replacing the fields reaches every caller.
local frameDepth = 0
local function frameShown() return true end
local shownFrame, ownIsShown -- the frame and its own IsShown field (nil: the frame's method) during one pass
local function restoreFrame()
	rawset(shownFrame, "IsShown", ownIsShown)
	shownFrame, ownIsShown, frameDepth = nil, nil, 0
	fadeTimers()
end
local function asFrameShown(original)
	return function(...)
		local frame = RXP.RXPFrame
		if frameDepth > 0 or type(frame) ~= "table" or not keeping() then return original(...) end
		shownFrame, ownIsShown, frameDepth = frame, rawget(frame, "IsShown"), 1
		frame.IsShown = frameShown
		return around(restoreFrame, original, ...)
	end
end
for _, name in ipairs({"StartTimer", "PLAYER_CONTROL_LOST"}) do wrap(RXP, name, asFrameShown) end
local function asFading(hideTimers)
	return function(...)
		if keeping() and ns.rxpProfile().showFlightTimers ~= false then return fadeTimers() end
		return hideTimers(...)
	end
end
wrap(RXP, "HideTimers", asFading)
