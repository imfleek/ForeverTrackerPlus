-- ForeverTrackerPlus: RestedXP guide steps in the objective tracker (the AllObjectives RXP half, Objectives/) and a
-- scrollable tracker with zone sorting, rewards and tooltips (the tracker half, Tracker/), in one addon.
-- Each half keeps its own private namespace so their fields (both use ns.db, ns.say, ...) never collide:
--   root.objectives  every file under Objectives/
--   root.tracker     every file under Tracker/
local ADDON, root = ...
root.objectives, root.tracker = {}, {}
root.BRAND = "ForeverTrackerPlus"

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
