-- 3.1.1 speed check: the nearby-quest scan spreads its first build and looks up levels only for close givers
-- (Questie.lua); the world marker's clock stops while it cannot show (WorldMarker.lua)
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local noop = function() end
local function fakeFrame()
	local f = { shown = true, alpha = 1, scripts = {} }
	return setmetatable(f, { __index = function(_, k)
		if k == "Show" then return function(self) self.shown = true end
		elseif k == "Hide" then return function(self) self.shown = false end
		elseif k == "IsShown" then return function(self) return self.shown end
		elseif k == "SetAlpha" then return function(self, a) self.alpha = a end
		elseif k == "GetAlpha" then return function(self) return self.alpha end
		elseif k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end
		elseif k == "RegisterEvent" then return function() return true end
		elseif k == "CreateFontString" or k == "CreateTexture" then return function() return fakeFrame() end end
		return noop
	end })
end

-- Questie: 100 available quests; only quest 7's giver stands close
local levelLookups = 0
local function npcOf(id) return 1000 + id end
local qenv = setmetatable({
	QuestieLoader = { ImportModule = function(_, name)
		if name == "QuestieDB" then return {
			QueryQuestSingle = function(id, f)
				if f == "startedBy" then return { { npcOf(id) } } end
				if f == "questLevel" then levelLookups = levelLookups + 1; return 10 end
				if f == "name" then return "Quest " .. id end
			end,
			QueryNPCSingle = function(id, f) if f == "spawns" then return { [12] = { { id == npcOf(7) and 50 or 10, 50 } } } end
				if f == "name" then return "Giver" end end,
		} end
		if name == "ZoneDB" then return { GetUiMapIdByAreaId = function() return 1429 end } end
		if name == "AvailableQuests" then local l = {}; for i = 1, 100 do l[i] = true end; return { __availableQuests = l } end
	end },
	LibQuestieDB = false,
	C_AddOns = { IsAddOnLoaded = function() return true end },
	Questie = { API = { isReady = true } },
	UnitLevel = function() return 12 end, GetQuestGreenRange = function() return 8 end,
	CreateVector2D = function(x, y) return { x = x, y = y } end,
	C_Map = { GetWorldPosFromMapPos = function(_, v) return 0, { x = v.x * 1000, y = v.y * 1000 } end },
	C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, GetLogIndexForQuestID = function() return nil end },
	C_Timer = { NewTicker = function() return {} end, After = noop }, CreateFrame = fakeFrame, hooksecurefunc = noop,
}, { __index = _G })
qenv._G = qenv
local qns = { api = {}, onLogin = {}, db = {} }
assert(loadfile(dir .. "/Tracker/Questie.lua", "t", qenv))("ForeverTrackerPlus", { tracker = qns })
local me = { continent = 0, x = 500, y = 500 }
local found
for _ = 1, 3 do found = qns.api.questieAvailableNear(me, 70, {}) or found end
check("nearby: the close quest is found once its places are built", found and found.id == 7 and found.d < 1)
check("nearby: levels looked up only for close givers", levelLookups <= 3)
levelLookups = 0
qns.api.questieAvailableNear(me, 70, {})
check("nearby: a later scan looks up one level, not 100", levelLookups == 1)

-- World marker
local nav
local menv = setmetatable({
	CreateFrame = fakeFrame, UIParent = fakeFrame(),
	C_Navigation = { GetFrame = function() return nav end, GetDistance = function() return 42 end, WasClampedToScreen = function() return false end },
	C_SuperTrack = { GetSuperTrackedQuestID = function() return 5 end },
	C_QuestLog = { GetTitleForQuestID = function() return "Wolves" end, GetLogIndexForQuestID = function() return 1 end },
	GetNumQuestLeaderBoards = function() return 0 end,
	InCombatLockdown = function() return false end,
	C_Timer = { NewTicker = function() return {} end, After = noop },
}, { __index = _G })
menv._G = menv
local mns = { api = {}, onLogin = {}, db = {} }
assert(loadfile(dir .. "/Tracker/WorldMarker.lua", "t", menv))("ForeverTrackerPlus", { tracker = mns })
for _, fn in ipairs(mns.onLogin) do fn() end
check("marker: no navigation frame, the clock is stopped", not mns.api.worldMarkerRunning())
nav = fakeFrame(); mns.api.refreshWorldMarker()
check("marker: a navigation frame, the clock runs", mns.api.worldMarkerRunning())
mns.db.worldMarker = false; mns.api.refreshWorldMarker()
check("marker: switched off, the clock is stopped", not mns.api.worldMarkerRunning())
print(pass and "ALL OK" or "SOME FAILED")
