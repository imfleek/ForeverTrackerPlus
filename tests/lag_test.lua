-- /qt lag (Tracker/Lag.lua, root.timed in Bootstrap.lua): measures our jobs only while it watches a quest accept
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local t, timers, frames, cvar = 0, {}, {}, "0"
local env = setmetatable({
	debugprofilestop = function() return t end,
	wipe = function(x) for k in pairs(x) do x[k] = nil end return x end,
	C_AddOns = { IsAddOnLoaded = function() return false end, GetNumAddOns = function() return 0 end },
	C_Timer = { After = function(_, f) timers[#timers + 1] = f end },
	GetCVar = function() return cvar end,
	DEFAULT_CHAT_FRAME = { AddMessage = function() end },
	CreateFrame = function()
		local f = { shown = true }
		function f:Hide() self.shown = false end
		function f:Show() self.shown = true end
		function f:SetScript(k, fn) self[k] = fn end
		function f:RegisterEvent(e) self.event = e end
		function f:UnregisterAllEvents() self.event = nil end
		frames[#frames + 1] = f
		return f
	end,
}, { __index = _G })
env._G = env
local root = {}
assert(loadfile(dir .. "/Bootstrap.lua", "t", env))("ForeverTrackerPlus", root)
root.tracker.api = {}
assert(loadfile(dir .. "/Tracker/Lag.lua", "t", env))("ForeverTrackerPlus", root)
local api = root.tracker.api

local function job() t = t + 12 return "done" end
check("not watching: the job just runs", root.timed("zone sort", job) == "done" and next(root.lag.jobs) == nil)

local said = {}
api.lagWatch(function(s) said[#said + 1] = s end)
local clock, events = frames[1], frames[2]
check("watching: waits for QUEST_ACCEPTED", events.event == "QUEST_ACCEPTED")
events.OnEvent(events, "QUEST_ACCEPTED")
clock.OnUpdate(clock, 0.45)
root.timed("zone sort", job); root.timed("zone sort", job)
timers[#timers]()
local all = table.concat(said, " | ")
check("prints the longest frame", all:find("longest frame after accepting the quest: 450 ms", 1, true) ~= nil)
check("prints our job with its time", all:find('our job "zone sort": 24.0 ms (2 runs, longest 12.0 ms)', 1, true) ~= nil)
check("profiler off: tells how to turn it on", all:find("scriptProfile 1", 1, true) ~= nil)
check("after the report: not measuring", root.lag.on == false and next(root.lag.jobs) == nil)
api.lagWatch(function(s) said[#said + 1] = s end)
check("/qt lag again: stops", events.event == nil and said[#said] == "lag: stopped.")
print(pass and "ALL OK" or "SOME FAILED")
