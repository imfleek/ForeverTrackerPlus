-- /qt lag: finds what makes a short freeze when you accept a quest. After each quest you accept it watches 4 s:
--   the longest frame (the freeze itself)
--   each addon's script time (needs the game's script profiler: /console scriptProfile 1, then /reload)
--   the time of our own main jobs (timed, Bootstrap.lua)
-- and prints them. /qt lag again stops it; it also stops after 3 quests.
local ADDON, root = ...; local ns = root.tracker
local timed = root.timed or function(_, fn, ...) return fn(...) end -- /qt lag (Bootstrap.lua)
if not ns or ns.disabled then return end
local api = ns.api

local WINDOW, ROUNDS = 4, 3
local watching, rounds, before, longest = false, 0, nil, 0
local clock = CreateFrame("Frame")
clock:Hide()
clock:SetScript("OnUpdate", function(_, elapsed) if elapsed > longest then longest = elapsed end end)

local function cpuFns()
	local get = rawget(_G, "GetAddOnCPUUsage") or (C_AddOns and C_AddOns.GetAddOnCPUUsage)
	local update = rawget(_G, "UpdateAddOnCPUUsage") or (C_AddOns and C_AddOns.UpdateAddOnCPUUsage)
	return get, update
end

local function profilerOn()
	return GetCVar and tostring(GetCVar("scriptProfile")) == "1"
end

-- [addon name] = ms of script time so far (empty without the profiler)
local function addonTimes()
	local out = {}
	local get, update = cpuFns()
	if not (profilerOn() and get and update and C_AddOns and C_AddOns.GetNumAddOns) then return out end
	pcall(update)
	for i = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(i)
		if name and C_AddOns.IsAddOnLoaded(name) then
			local ok, ms = pcall(get, name)
			if ok and type(ms) == "number" then out[name] = ms end
		end
	end
	return out
end

local function sorted(map, value)
	local list = {}
	for k, v in pairs(map) do list[#list + 1] = { k, value(v) } end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	return list
end

local function report(say)
	root.lag.on = false
	clock:Hide()
	say(("lag: longest frame after accepting the quest: %d ms (a smooth frame is under 20 ms)"):format(longest * 1000))
	if profilerOn() then
		local after, delta = addonTimes(), {}
		for name, ms in pairs(after) do
			local d = ms - (before[name] or 0)
			if d >= 1 then delta[name] = d end
		end
		local top = sorted(delta, function(v) return v end)
		if #top == 0 then say("lag: no addon used 1 ms or more") end
		for i = 1, math.min(6, #top) do say(("lag: addon %s: %d ms"):format(top[i][1], top[i][2])) end
	else
		say("lag: for the time of each addon, type /console scriptProfile 1 and /reload, then /qt lag again. "
			.. "Afterwards turn it off: /console scriptProfile 0 and /reload.")
	end
	local jobs = sorted(root.lag.jobs, function(v) return v.total end)
	if #jobs == 0 then say("lag: our jobs: none ran") end
	for i = 1, math.min(8, #jobs) do
		local j = root.lag.jobs[jobs[i][1]]
		say(("lag: our job \"%s\": %.1f ms (%d runs, longest %.1f ms)"):format(jobs[i][1], j.total, j.n, j.max))
	end
	wipe(root.lag.jobs)
	rounds = rounds + 1
	if rounds >= ROUNDS then watching = false; say("lag: done. Type /qt lag to watch again.")
	else say("lag: still watching. Accept another quest, or type /qt lag to stop.") end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
	if not watching or root.lag.on then return end
	before = addonTimes()
	wipe(root.lag.jobs)
	longest = 0
	root.lag.on = true
	clock:Show()
	C_Timer.After(WINDOW, function() report(api.lagSay) end)
end)

function api.lagWatch(say)
	api.lagSay = say
	if watching then
		watching = false
		root.lag.on = false
		clock:Hide()
		events:UnregisterAllEvents()
		say("lag: stopped.")
		return
	end
	watching, rounds = true, 0
	pcall(events.RegisterEvent, events, "QUEST_ACCEPTED")
	say("lag: watching. Accept a quest; the result shows here 4 seconds later."
		.. (profilerOn() and "" or " Tip: /console scriptProfile 1 and /reload first shows each addon's time."))
end
