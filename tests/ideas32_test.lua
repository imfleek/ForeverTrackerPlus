-- 3.2 (user ideas 10, 12, 14, 16, 24, 31): DungeonLoot, DungeonRuns, QuestLogTags, CorpseRun, BugReport.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function frame(name)
	local f = { name = name, shown = false, scripts = {}, lines = {} }
	local methods = {
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		SetShown = function(self, v) self.shown = v and true or false end, IsShown = function(self) return self.shown end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end, GetScript = function(self, k) return self.scripts[k] end,
		CreateFontString = function() return frame("text") end, CreateTexture = function() return frame("tex") end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		NumLines = function(self) return #self.lines end,
	}
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

local now, money, xp, xpMax, level = 100, 50000, 1000, 5000, 30
local api = { addSlash = function() end }
local ns = { api = api, onLogin = {}, db = {} }
local env
local scan -- the hidden tooltip: SetItemByID fills its lines
local SBT = "|TInterface\\AddOns\\SpecBisTooltip\\icon"
env = setmetatable({
	CreateFrame = function(kind, name)
		local f = frame(name)
		if kind == "GameTooltip" then
			scan = f
			f.SetItemByID = function(self, id)
				self.lines = {}
				env[name .. "TextLeft1"], env[name .. "TextRight1"] = frame(), frame()
				env[name .. "TextLeft1"].text = "Item " .. id
				if id == 101 then -- best in slot for your spec
					env[name .. "TextLeft2"], env[name .. "TextRight2"] = frame(), frame()
					env[name .. "TextLeft2"].text = "|cff90ee90Fury|r"
					env[name .. "TextRight2"].text = SBT .. ":14|t"
					self.lines = { 1, 2 }
				else
					self.lines = { 1 }
				end
			end
		end
		return f
	end,
	UIParent = frame("UIParent"),
	GetTime = function() return now end, time = function() return 1700000000 end,
	GetMoney = function() return money end, UnitXP = function() return xp end, UnitXPMax = function() return xpMax end,
	UnitLevel = function() return level end, UnitName = function() return "Tester" end, GetRealmName = function() return "Realm" end,
	C_AddOns = { IsAddOnLoaded = function(n) return n == "SpecBisTooltip" end,
		GetAddOnMetadata = function(n, f) if n == "SpecBisTooltip" and f == "IconTexture" then return "Interface\\AddOns\\SpecBisTooltip\\icon" end
			if f == "Version" then return "3.2" end end },
	GetItemInfo = function(id) return "Item " .. id, "|cffa335ee[Item " .. id .. "]|r", 4 end,
	C_Item = { GetItemInfoInstant = function() return 1, "Armor", "Plate", "INVTYPE_CHEST" end },
	C_Timer = { After = function(_, fn) end, NewTicker = function() end },
	InCombatLockdown = function() return false end,
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
	hooksecurefunc = function() end, issecretvalue = function() return false end,
	date = function() return "27 Nov" end, BreakUpLargeNumbers = function(n) return tostring(n) end,
	GetBuildInfo = function() return "1.15.8", "65000", "", 11508 end, GetLocale = function() return "enUS" end,
	DEFAULT_CHAT_FRAME = { AddMessage = function() end },
}, { __index = _G })
env._G = env
local function load(file)
	local chunk = assert(loadfile(dir .. "/Tracker/" .. file, "t", env))
	chunk("ForeverTrackerPlus", { tracker = ns })
end

-- 12. Loot you want -------------------------------------------------------------------------------------------------
env.ForeverDungeonJournal_NS = {
	DB = { Deadmines = { bosses = { { name = "Rhahk'Zor", loot = { { 100, "Plain" }, { 101, "Bis Chest" } } },
		{ name = "VanCleef", loot = { { 102, "Fav Sword" } } } } } },
	IsFavouriteItem = function(id) return id == 102 end,
}
load("DungeonLoot.lua")
check("SpecBisTooltip's green line for your spec: best in slot", api.dungeonLootReadSbt(101) == "bis")
check("no SpecBisTooltip line: not wanted", api.dungeonLootReadSbt(100) == false)
local list = api.dungeonWantedLoot("Deadmines")
check("two wanted items: the best in slot one and the favourite", #list == 2 and list[1].id == 101 and list[2].id == 102
	and list[2].why == "favourite")
local e = api.dungeonLootEntry("Deadmines")
check("the card line names the first and counts the rest", e and e.text:find("Item 101", 1, true) and e.text:find("+1", 1, true))
ns.db.dungeonLoot = false
check("switched off: no line", api.dungeonLootEntry("Deadmines") == nil)
ns.db.dungeonLoot = nil

-- 14 / 16. Run summary and history -------------------------------------------------------------------------------
load("DungeonRuns.lua")
local run = { key = "36", name = "Deadmines", start = now, kills = {} }
api.dungeonRunForTests = function() return run end
api.dungeonRunStarted(run)
xp = 4800
api.dungeonRunsXPEvent()
xp, xpMax = 300, 6000 -- a level-up: 200 to the end of the level, then 300
api.dungeonRunsXPEvent()
check("experience counted over a level-up: 3800 + 200 + 300", run.xp == 4300)
money = 80000
run.kills = { { "Rhahk'Zor", 60 }, { "VanCleef", 900 } }
run.cleared, run.deaths, run.bosses = true, 2, 2
now = now + 1000
run.left = now
api.dungeonRunLeft(run)
local h = ns.db.dungeonRuns
check("the run is kept", type(h) == "table" and #h == 1 and h[1].dur == 1000 and h[1].money == 30000 and h[1].cleared)
run.left = nil; now = now + 100; run.left = now
api.dungeonRunLeft(run)
check("a resumed run updates its record", #ns.db.dungeonRuns == 1 and ns.db.dungeonRuns[1].dur == 1100)
local text = api.runDiscordText(ns.db.dungeonRuns[1])
check("Discord line: one line with time, bosses, deaths, gold", not text:find("\n") and text:find("Deadmines cleared", 1, true)
	and text:find("15:00", 1, true) and text:find("2/2 bosses", 1, true) and text:find("2 deaths", 1, true) and text:find("3g 0s", 1, true))
local rows = api.dungeonRunRows()
check("per dungeon: best time and run count", rows[1] and rows[1][1] == "15:00" and rows[1][2] == "Deadmines" and rows[1][3]:find("1 run,", 1, true))
check("last runs list", #api.dungeonLastRunRows() == 1)
local r0 = { key = "x", name = "Stockade", start = now, kills = {} }
api.dungeonRunStarted(r0); r0.left = now
api.dungeonRunLeft(r0)
check("a run with no boss kill is not kept", #ns.db.dungeonRuns == 1)

-- 10. Quest log tags ------------------------------------------------------------------------------------------------
env.C_QuestLog = { GetLogIndexForQuestID = function() return 1 end, GetInfo = function() return { level = 24 } end }
api.questDifficultyRGB = function() return 1, 1, 0 end
api.foreverIcon = function(id) if id >= 90000 then return { file = "W" } end end
load("QuestLogTags.lua")
local t = api.questLogTagText(91000)
check("quest log tag: the Forever W and the level", t:find("|TW:13:13|t", 1, true) and t:find("[24]", 1, true))
ns.db.questLogLevels = false
check("no level when it is off", not api.questLogTagText(91000):find("[24]", 1, true))

-- 31. Corpse run ----------------------------------------------------------------------------------------------------
load("CorpseRun.lua")
check("spirit healer below 11: no sickness", api.corpseHealerText(9):find("no sickness", 1, true))
check("spirit healer at 15: 5 min", api.corpseHealerText(15):find("5 min", 1, true))
check("spirit healer at 60: 10 min", api.corpseHealerText(60):find("10 min", 1, true))
check("run text: yards and seconds", api.corpseRunText(140, 7):find("140 yd", 1, true) and api.corpseRunText(140, 7):find("20 s", 1, true))
-- (user: Warsong Gulch) measured on your map with its size in yards
env.C_Map = { GetBestMapForUnit = function() return 1460 end, GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
	GetMapWorldSize = function() return 1000, 1000 end }
env.C_DeathInfo = { GetCorpseMapPosition = function() return { x = 0.5, y = 0.45 } end }
local yards, angle = api.corpseDirection()
check("corpse 50 yards to the north", yards and math.abs(yards - 50) < 0.01 and math.abs(angle) < 1e-6)
env.C_DeathInfo = { GetCorpseMapPosition = function() return { x = 0.45, y = 0.5 } end }
yards, angle = api.corpseDirection()
check("corpse to the west: a quarter turn left", yards and math.abs(angle - math.pi / 2) < 1e-6)
env.C_Map.GetPlayerMapPosition = function() return nil end
yards, angle = api.corpseDirection()
check("no position for you: says why", yards == nil and angle == "you")

-- 24. Bug report ----------------------------------------------------------------------------------------------------
api.DEFAULTS = { scale = 1, tooltips = true }
ns.db.scale = 1.2
ns.db.tooltips = true
env.BugGrabber = { GetDB = function() return { { message = "Other addon error", counter = 1 },
	{ message = "ForeverTrackerPlus/Tracker/X.lua:1: boom", stack = "stack", counter = 3 } } end }
load("BugReport.lua")
local report = api.bugReportText()
check("bug report: version and build", report:find("Version 3.2", 1, true) and report:find("1.15.8", 1, true))
check("bug report: only our errors", report:find("boom", 1, true) and not report:find("Other addon", 1, true))
check("bug report: changed settings only", report:find("scale=1.2", 1, true) and not report:find("tooltips=", 1, true))

-- 35. Dead-end alert (rules 1 and 2; small reward = grey) -----------------------------------------------------------
level = 40
env.GetQuestGreenRange = function() return 8 end
local qlevel, nextQ, opens, links, rep = { [1] = 20, [2] = 38 }, {}, {}, {}, {}
env.C_QuestLog = { GetLogIndexForQuestID = function(id) return id end, GetInfo = function(i) return { level = qlevel[i] } end }
api.questieOn = function() return true end
api.questieGet = function(_, id, field) if field == "nextQuestInChain" then return nextQ[id] end end
api.questieForPlayer = function(id) return id ~= 99 end
api.questieNextQuests = function(id) return opens[id] end
api.questRewardLinks = function(id) return links[id] or {} end
api.repRewards = function(id) return rep[id] or {} end
opens[1], opens[2] = {}, {}
load("DeadEnd.lua")
check("dead end: grey, no follow-up, no item", api.deadEndReason(1) ~= nil and api.deadEndIcon(1) ~= nil)
check("not grey: not a dead end", api.deadEndReason(2) == nil)
nextQ[1] = 99
check("rule 2: a follow-up for another class still leaves it a dead end", api.deadEndReason(1) ~= nil)
nextQ[1] = 50
check("a follow-up you can take: not a dead end", api.deadEndReason(1) == nil)
nextQ[1] = nil; opens[1] = nil
check("Questie still building: not a dead end", api.deadEndReason(1) == nil)
opens[1] = {}
links[3], qlevel[3], opens[3] = { "item" }, 10, {}
check("an item reward: not a dead end", api.deadEndReason(3) == nil)
ns.db.deadEnd = false
check("switched off: nothing", api.deadEndReason(1) == nil)
ns.db.deadEnd = nil

print(pass and "ALL OK" or "SOME FAILED")
