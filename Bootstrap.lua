-- ForeverTrackerPlus: RestedXP guide steps in the objective tracker (the AllObjectives RXP half, Objectives/) and a
-- scrollable tracker with zone sorting, rewards and tooltips (the tracker half, Tracker/), in one addon.
-- Each half keeps its own private namespace so their fields (both use ns.db, ns.say, ...) never collide:
--   root.objectives  every file under Objectives/
--   root.tracker     every file under Tracker/
local ADDON, root = ...
root.objectives, root.tracker = {}, {}
root.BRAND = "ForeverTrackerPlus"

-- /qt lag (Tracker/Lag.lua): our main jobs run through root.timed. It only measures while /qt lag watches the
-- seconds after a quest is accepted; else it just calls the job.
root.lag = { on = false, jobs = {} }
local function finish(name, start, ...)
	local ms = debugprofilestop() - start
	local job = root.lag.jobs[name]
	if not job then job = { n = 0, total = 0, max = 0 }; root.lag.jobs[name] = job end
	job.n, job.total = job.n + 1, job.total + ms
	if ms > job.max then job.max = ms end
	return ...
end
function root.timed(name, fn, ...)
	if not root.lag.on or not debugprofilestop then return fn(...) end
	return finish(name, debugprofilestop(), fn(...))
end

-- /qt lag, everything in one file: its hooks, event and update scripts of plain frames, and timers, each named by
-- the file ("Extras hook SetText", "Stats QUEST_ACCEPTED", "ZoneSort timer"). Each file takes its own copies at the
-- top. While /qt lag is not measuring they just call the code. Only plain frames (no template): a secure frame's
-- methods are never replaced.
function root.lagWrap(file, hook, create, timer)
	local lag, timed = root.lag, root.timed
	local outHook = hook and function(a, b, c)
		if type(a) == "string" then
			local label = file .. " hook " .. a
			return hook(a, function(...) if not lag.on then return b(...) end return timed(label, b, ...) end)
		end
		local label = file .. " hook " .. tostring(b)
		return hook(a, b, function(...) if not lag.on then return c(...) end return timed(label, c, ...) end)
	end
	local outCreate = create and function(kind, name, parent, template, ...)
		local f = create(kind, name, parent, template, ...)
		if template == nil and (kind == nil or kind == "Frame") and type(f) == "table" and type(f.SetScript) == "function" then
			local set = f.SetScript
			f.SetScript = function(self, script, fn)
				if type(fn) == "function" and (script == "OnEvent" or script == "OnUpdate") then
					local inner, onUpdate = fn, script == "OnUpdate"
					fn = function(frame, a, ...)
						if not lag.on then return inner(frame, a, ...) end
						return timed(file .. " " .. (onUpdate and "OnUpdate" or tostring(a)), inner, frame, a, ...)
					end
				end
				return set(self, script, fn)
			end
		end
		return f
	end
	local outTimer = timer
	if type(timer) == "table" then
		local label = file .. " timer"
		local function wrap(fn)
			if type(fn) ~= "function" then return fn end
			return function(...) if not lag.on then return fn(...) end return timed(label, fn, ...) end
		end
		outTimer = setmetatable({
			After = timer.After and function(d, fn) return timer.After(d, wrap(fn)) end,
			NewTicker = timer.NewTicker and function(d, fn, n) return timer.NewTicker(d, wrap(fn), n) end,
			NewTimer = timer.NewTimer and function(d, fn) return timer.NewTimer(d, wrap(fn)) end,
		}, { __index = timer })
	end
	return outHook, outCreate, outTimer
end

local function say(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. root.BRAND .. "|r " .. text)
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = copy(v) end
	return out
end

-- Take settings over once from an older addon that is loaded in this session (OptionalDeps loads it first).
local function adopt(target, ...)
	if type(_G[target]) == "table" then return end
	for i = 1, select("#", ...) do
		local source = _G[(select(i, ...))]
		if type(source) == "table" then
			_G[target] = copy(source)
			return true
		end
	end
end

local loaded = C_AddOns.IsAddOnLoaded
local oldTracker = loaded("AllTrackerRXP")       -- the previous name of this addon (1.x or 2.0.0)
local oldGuide = loaded("AllObjectivesRXP")      -- the separate AllObjectives RXP addon

local oldName = loaded("RXPForeverTracker")     -- the previous name of this addon (2.x to 3.1)
-- From 3.1.1 that folder is a stub that only loads the old settings (Legacy/), so the CurseForge app's update keeps them
local stub = oldName and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("RXPForeverTracker", "X-ForeverTrackerPlus-Stub")
if stub then oldName = false end

adopt("ForeverTrackerPlusDB", "RXPForeverTrackerDB", "AllTrackerRXPDB")
adopt("ForeverTrackerPlusGuideDB", "RXPForeverTrackerGuideDB", "AllTrackerRXPObjectivesDB", "AllObjectivesRXPDB")

if oldName then
	-- The old copy under its old name runs this session too: stand down, and turn it off for the next /reload.
	root.disabledAll = true
	pcall(C_AddOns.DisableAddOn, "RXPForeverTracker")
	C_Timer.After(2, function()
		say("RXP ForeverTracker is now " .. root.BRAND .. ". Your settings have been copied. The old addon is turned "
			.. "off: type /reload, then you can delete the RXPForeverTracker folder.")
	end)
elseif oldTracker then
	-- Both would take over the same tracker: stand down for this session and let the old copy run.
	root.disabledAll = true
	C_Timer.After(2, function()
		say("AllTracker RXP is still enabled, so " .. root.BRAND .. " is off this session; your settings have been "
			.. "copied. Disable AllTracker RXP" .. (oldGuide and " and AllObjectives RXP" or "") .. " in the AddOns list and /reload.")
	end)
elseif oldGuide then
	-- The separate AllObjectives RXP would draw the guide a second time: the built-in copy stays off and the tracker
	-- half works with the separate one.
	root.standaloneObjectives = true
	C_Timer.After(2, function()
		say("AllObjectives RXP is built in. The separate AllObjectives RXP addon is still enabled, so it is used "
			.. "instead; your settings have been copied. Disable it in the AddOns list and /reload.")
	end)
end
