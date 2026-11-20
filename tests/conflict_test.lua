local dir, scenario = arg[1], arg[2]
local loaded = scenario == "questieOff" and { Questie = true } or { ["!KalielsTracker"] = true }
_G.Questie = { db = { profile = { trackerEnabled = false } } }
local disabled, reloaded, shown, timers = {}, false, nil, {}
_G.C_AddOns = { IsAddOnLoaded = function(n) return loaded[n] or false end, DisableAddOn = function(n) disabled[#disabled + 1] = n end,
	GetAddOnMetadata = function(n) return n == "!KalielsTracker" and "|cffff0000Kaliel's|r Tracker" or n end }
_G.ReloadUI = function() reloaded = true end
_G.InCombatLockdown = function() return false end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which, a, b) shown = { which = which, a = a } end
_G.C_Timer = { After = function(d, f) timers[#timers + 1] = { d, f } end }
local evt
_G.CreateFrame = function() local f = { RegisterEvent = function() end, UnregisterEvent = function() end }
	f.SetScript = function(_, _, fn) evt = fn end; return f end
_G.RXPForeverTrackerDB = { enabled = true }
local root = { BRAND = "RXP ForeverTracker", tracker = { db = _G.RXPForeverTrackerDB, api = {} } }
assert(loadfile(dir .. "/Tracker/Conflicts.lua"))("RXPForeverTracker", root)
evt({ UnregisterEvent = function() end }, "PLAYER_ENTERING_WORLD", true, false)
print("timer delay:", timers[1] and timers[1][1])
timers[1][2]()
if not shown then print("no prompt"); return end
local d = StaticPopupDialogs[shown.which]
print("prompt about:", shown.a, "| buttons:", d.button1, "/", d.button2, "/", d.button3)
d.OnCancel(nil, nil, "override"); print("closed another way -> disabled:", #disabled)
d.OnCancel(nil, nil, "clicked"); print("Disable other -> disabled:", disabled[1], "reload:", reloaded)
d.OnAlt(); print("Keep both -> remembered:", tostring(RXPForeverTrackerDB.conflictKept["!KalielsTracker"]))
shown = nil; timers = {}
assert(loadfile(dir .. "/Tracker/Conflicts.lua"))("RXPForeverTracker", root)
evt({ UnregisterEvent = function() end }, "PLAYER_ENTERING_WORLD", false, true); timers[1][2]()
print("after Keep both, next reload prompts:", shown ~= nil)

-- R106-45: EllesmereUI Quest Tracker (restyles the tracker's text): asked about, with its own text, and only it disabled
do
	local function check(l, c) print((c and "ok   " or "FAIL ") .. l) end
	loaded = { EllesmereUIQuestTracker = true }
	disabled, reloaded, shown, timers = {}, false, nil, {}
	_G.RXPForeverTrackerDB = { enabled = true }
	root.tracker.db = _G.RXPForeverTrackerDB
	assert(loadfile(dir .. "/Tracker/Conflicts.lua"))("RXPForeverTracker", root)
	evt({ UnregisterEvent = function() end }, "PLAYER_ENTERING_WORLD", true, false)
	timers[1][2]()
	local d = shown and StaticPopupDialogs[shown.which]
	check("EllesmereUI Quest Tracker: asked about", d ~= nil and shown.a == "EllesmereUIQuestTracker")
	check("its own text: it restyles the text, the rest of the suite keeps working",
		d and d.text:find("restyles the same quest tracker text", 1, true) ~= nil and d.text:find("keeps working", 1, true) ~= nil)
	if d then d.OnCancel(nil, nil, "clicked") end
	check("Disable it: only EllesmereUIQuestTracker, then reload", disabled[1] == "EllesmereUIQuestTracker" and #disabled == 1 and reloaded)
end
