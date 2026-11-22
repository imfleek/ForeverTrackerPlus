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

-- each file's copies: hooks, plain frames' scripts and timers are timed under the file's name
local hooked, ran = {}, {}
local hook, create, timer = root.lagWrap("Extras", function(a, b, c) hooked[#hooked + 1] = c or b end,
	function() local f = {}; function f:SetScript(k, fn) self[k] = fn end; return f end,
	{ After = function(_, fn) ran[#ran + 1] = fn end })
hook({}, "SetText", function() t = t + 5 end)
local plain = create("Frame"); plain:SetScript("OnEvent", function() t = t + 3 end)
timer.After(0, function() t = t + 2 end)
root.lag.on = true
hooked[1](); plain.OnEvent(plain, "QUEST_ACCEPTED"); ran[1]()
check("a hook is timed by file and method", root.lag.jobs["Extras hook SetText"] and root.lag.jobs["Extras hook SetText"].total == 5)
check("an event script is timed by file and event", root.lag.jobs["Extras QUEST_ACCEPTED"] and root.lag.jobs["Extras QUEST_ACCEPTED"].total == 3)
check("a timer is timed by file", root.lag.jobs["Extras timer"] and root.lag.jobs["Extras timer"].total == 2)
root.lag.on = false
for k in pairs(root.lag.jobs) do root.lag.jobs[k] = nil end
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
check("prints the longest frame", all:find("LONGEST FRAME after accepting the quest: 450 ms", 1, true) ~= nil)
check("prints our job with its time", all:find('our job "zone sort": 24.0 ms (2 runs, longest 12.0 ms)', 1, true) ~= nil)
check("profiler off: tells how to turn it on", all:find("scriptProfile 1", 1, true) ~= nil)
check("the longest frame is the last report line", said[#said - 1]:find("LONGEST FRAME", 1, true) ~= nil)
check("after the report: not measuring", root.lag.on == false and next(root.lag.jobs) == nil)
api.lagWatch(function(s) said[#said + 1] = s end)
check("/qt lag again: stops", events.event == nil and said[#said] == "lag: stopped.")

-- with the time meter on: a quiet 4 s follows, with our addon's time while nothing happens
cvar = "1"
local cpu = 0
env.C_AddOns.GetNumAddOns = function() return 1 end
env.C_AddOns.GetAddOnInfo = function() return "ForeverTrackerPlus" end
env.C_AddOns.IsAddOnLoaded = function() return true end
env.GetAddOnCPUUsage = function() return cpu end
env.UpdateAddOnCPUUsage = function() end
said = {}
api.lagWatch(function(s) said[#said + 1] = s end)
events.OnEvent(events, "QUEST_ACCEPTED")
cpu = 700
timers[#timers]()                   -- the accept report
check("meter on: our addon's time", table.concat(said, " | "):find("ADDON ForeverTrackerPlus: 700 ms", 1, true) ~= nil)
timers[#timers]()                   -- 1 s later the quiet window starts
events.OnEvent(events, "QUEST_ACCEPTED") -- an accept now is not a new round
cpu = 1300
timers[#timers]()                   -- quiet window ends
all = table.concat(said, " | ")
check("quiet window: our addon's time while nothing happens", all:find("QUIET 4 s, nothing accepted: ADDON ForeverTrackerPlus: 600 ms", 1, true) ~= nil or print(all))
print(pass and "ALL OK" or "SOME FAILED")
