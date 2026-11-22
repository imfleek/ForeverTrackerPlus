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
local watching, rounds, before, longest, quiet = false, 0, nil, 0, false
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

-- The key lines (longest frame, each addon) come last, at the bottom of the chat, and the whole report also opens in
-- the copy window (/qt debug's): the chat cut the first lines off (user sent only the job lines).
local function report(say)
	root.lag.on = false
	clock:Hide()
	local lines = {}
	local function add(text) lines[#lines + 1] = "lag: " .. text end
	local jobs = sorted(root.lag.jobs, function(v) return v.total end)
	local sum = 0
	for _, j in ipairs(jobs) do sum = sum + j[2] end
	if #jobs == 0 then add("our timed jobs: none ran") end
	for i = 1, math.min(15, #jobs) do
		local j = root.lag.jobs[jobs[i][1]]
		add(("our job \"%s\": %.1f ms (%d runs, longest %.1f ms)"):format(jobs[i][1], j.total, j.n, j.max))
	end
	if #jobs > 0 then add(("our timed jobs together: %.1f ms in %d s"):format(sum, WINDOW)) end
	if profilerOn() then
		local after, delta = addonTimes(), {}
		for name, ms in pairs(after) do
			local d = ms - (before[name] or 0)
			if d >= 1 then delta[name] = d end
		end
		local top = sorted(delta, function(v) return v end)
		if #top == 0 then add("no addon used 1 ms or more") end
		for i = math.min(6, #top), 1, -1 do add(("ADDON %s: %d ms"):format(top[i][1], top[i][2])) end
	else
		add("the game's time meter is OFF, so no addon times. Type /console scriptProfile 1 and /reload, "
			.. "then /qt lag again. Afterwards: /console scriptProfile 0 and /reload.")
	end
	add(("LONGEST FRAME after accepting the quest: %d ms (a smooth frame is under 20 ms)"):format(longest * 1000))
	for _, text in ipairs(lines) do say(text) end
	if api.showDebugWindow and api.themeKit then pcall(api.showDebugWindow, lines) end
	wipe(root.lag.jobs)
	rounds = rounds + 1
	if not profilerOn() then
		if rounds >= ROUNDS then watching = false; say("lag: done. Type /qt lag to watch again.")
		else say("lag: still watching. Accept another quest, or type /qt lag to stop.") end
		return
	end
	-- the same 4 s again with nothing accepted: is the time from the quest, or there all the time? (user's report:
	-- ForeverTrackerPlus 773 ms, our timed jobs only 152 ms of it)
	quiet = true
	say("lag: now the same check with nothing happening. Do not accept a quest for 5 seconds.")
	C_Timer.After(1, function()
		local start = addonTimes()
		wipe(root.lag.jobs)
		root.lag.on = true
		C_Timer.After(WINDOW, function()
			root.lag.on = false
			quiet = false
			local after = addonTimes()
			local ours = (after[ADDON] or 0) - (start[ADDON] or 0)
			add(("QUIET 4 s, nothing accepted: ADDON %s: %d ms"):format(ADDON, ours))
			local qjobs = sorted(root.lag.jobs, function(v) return v.total end)
			for i = 1, math.min(4, #qjobs) do
				local j = root.lag.jobs[qjobs[i][1]]
				add(("QUIET our job \"%s\": %.1f ms (%d runs)"):format(qjobs[i][1], j.total, j.n))
			end
			for i = #lines - math.min(4, #qjobs), #lines do say(lines[i]) end
			if api.showDebugWindow and api.themeKit then pcall(api.showDebugWindow, lines) end
			wipe(root.lag.jobs)
			if rounds >= ROUNDS then watching = false; say("lag: done. Type /qt lag to watch again.")
			else say("lag: still watching. Accept another quest, or type /qt lag to stop.") end
		end)
	end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
	if not watching or root.lag.on or quiet then return end
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
