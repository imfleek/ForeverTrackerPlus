-- R106-58: at level 60, a popup asks once per character whether to disable RXPGuides entirely
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local loaded, disabled, reloaded, shown, timers, level, combat = { RXPGuides = true }, {}, false, nil, {}, 59, false
_G.C_AddOns = { IsAddOnLoaded = function(n) return loaded[n] or false end, DisableAddOn = function(n) disabled[#disabled + 1] = n end }
_G.ReloadUI = function() reloaded = true end
_G.InCombatLockdown = function() return combat end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which) shown = which end
_G.C_Timer = { After = function(d, f) timers[#timers + 1] = f end }
_G.UnitName = function() return "On" end
_G.GetRealmName = function() return "Forever" end
_G.UnitLevel = function() return level end
local evt
_G.CreateFrame = function() local f = { RegisterEvent = function() end }
	f.SetScript = function(_, _, fn) evt = fn end; return f end
local db = {}
local root = { BRAND = "ForeverTrackerPlus", tracker = { db = db, api = {} } }
assert(loadfile(dir .. "/Tracker/LevelCap.lua"))("ForeverTrackerPlus", root)
local function runTimers() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end

evt(nil, "PLAYER_ENTERING_WORLD", true, false); runTimers()
check("level 59 at login: not asked", shown == nil)
evt(nil, "PLAYER_LEVEL_UP", 60); runTimers()
check("reaching 60: asked", shown == "FOREVERTRACKERPLUS_LEVEL_CAP")
local d = StaticPopupDialogs.FOREVERTRACKERPLUS_LEVEL_CAP
check("buttons: Disable RXPGuides / Not now / Don't ask again", d.button1 == "Disable RXPGuides" and d.button2 == "Not now"
	and d.button3 == "Don't ask again")
-- "Not now": asked again on the next login (level 60 already)
shown = nil; level = 60
evt(nil, "PLAYER_ENTERING_WORLD", false, true); runTimers()
check("Not now: asked again on the next login at 60", shown == "FOREVERTRACKERPLUS_LEVEL_CAP")
-- a zone change is not a login
shown = nil
evt(nil, "PLAYER_ENTERING_WORLD", false, false); runTimers()
check("a zone change: not asked", shown == nil)
-- in combat: waits for its end
combat = true
evt(nil, "PLAYER_LEVEL_UP", 60); runTimers()
check("in combat: not shown yet", shown == nil)
combat = false
evt(nil, "PLAYER_REGEN_ENABLED")
check("combat over: asked", shown == "FOREVERTRACKERPLUS_LEVEL_CAP")
-- Disable: only RXPGuides, then reload, and not asked again for this character
StaticPopupDialogs.FOREVERTRACKERPLUS_LEVEL_CAP.OnAccept()
check("Disable RXPGuides: only it, then the UI reloads", disabled[1] == "RXPGuides" and #disabled == 1 and reloaded)
shown = nil
evt(nil, "PLAYER_ENTERING_WORLD", true, false); runTimers()
check("answered: not asked again for this character", shown == nil)
-- Don't ask again (another character)
_G.UnitName = function() return "Alt" end
evt(nil, "PLAYER_ENTERING_WORLD", true, false); runTimers()
check("another character at 60: asked for it too", shown == "FOREVERTRACKERPLUS_LEVEL_CAP")
StaticPopupDialogs.FOREVERTRACKERPLUS_LEVEL_CAP.OnAlt()
shown = nil
evt(nil, "PLAYER_ENTERING_WORLD", true, false); runTimers()
check("Don't ask again: not asked again", shown == nil)
-- RXPGuides not loaded: never asked
_G.UnitName = function() return "Third" end
loaded.RXPGuides = nil
evt(nil, "PLAYER_ENTERING_WORLD", true, false); runTimers()
check("RXPGuides not loaded: not asked", shown == nil)
local toc = io.open(dir .. "/ForeverTrackerPlus.toc"):read("a")
check("in the toc", toc:find("Tracker/LevelCap.lua", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
