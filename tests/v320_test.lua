-- 3.2: closest-quest sorting choices, the grey threshold, rewards (upgrade, disenchant, auto pick), reminders
-- (trainer, talents, quest-start items), kill counts, session summary, camp time, dungeon splits and lines, the
-- attunement / class chain pages, the setup's "New in 3.2" steps and the source-level wiring.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local function read(path) local f = assert(io.open(dir .. "/" .. path, "rb")); local s = f:read("*a"); f:close(); return s end
local function obj()
	local o = {}
	return setmetatable(o, { __index = function(t, k)
		if k == "scripts" then local s = {}; rawset(t, k, s); return s end
		return function(self, a, b)
			if k == "SetScript" or k == "HookScript" then self.scripts[a] = b end
			if k == "SetText" then rawset(self, "text", a) end
			if k == "IsShown" then return rawget(self, "shown") ~= false end
			if k == "GetEffectiveScale" or k == "GetScale" then return 1 end
			if k == "GetWidth" or k == "GetHeight" then return 200 end
			if k == "GetFrameLevel" then return 1 end
			if k == "GetFont" then return "font", 12, "" end
			if k == "Hide" then rawset(self, "shown", false) end
			if k == "Show" then rawset(self, "shown", true) end
		end
	end })
end
local clock, level = 100, 20
local base = {
	CreateFrame = function() return obj() end, GetTime = function() return clock end, time = function() return 1000 end,
	UnitLevel = function() return level end, UnitName = function() return "Ana" end, GetRealmName = function() return "Realm" end,
	UnitClass = function() return "Warrior", "WARRIOR", 1 end, DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) _G.lastChat = t end },
	C_Timer = { After = function(_, fn) end, NewTicker = function() return { Cancel = function() end } end },
	GameTooltip = obj(), UIParent = obj(), STANDARD_TEXT_FONT = "font",
}
local function load(file, ns, extra)
	-- the stubs set as real globals of the file (it reads some with rawget(_G, name))
	local env = setmetatable({}, { __index = _G })
	for k, v in pairs(base) do env[k] = v end
	for k, v in pairs(extra or {}) do env[k] = v end
	env._G = env
	assert(loadfile(dir .. "/" .. file, "t", env))("ForeverTrackerPlus", { tracker = ns })
	return env
end
local function newNs(db) return { api = {}, onLogin = {}, db = db or {} } end
local function login(ns) for _, fn in ipairs(ns.onLogin) do fn() end end

---------------------------------------------------------------------------------------------------------------------
-- Core.lua: the grey threshold (loaded alone through its function's source)
---------------------------------------------------------------------------------------------------------------------
do
	local core = read("Tracker/Core.lua")
	local body = core:match("(function ns%.api%.questDifficultyRGB.-\n end\n)") or core:match("(function ns%.api%.questDifficultyRGB.-\r?\nend\r?\n)")
	check("core: questDifficultyRGB found", body ~= nil)
	local db = { greyLevels = 0 }
	local ns = { api = {} }
	local env = setmetatable({ ns = ns, db = db, UnitLevel = function() return 30 end,
		GetQuestDifficultyColor = function(l) if l <= 21 then return { r = 0.5, g = 0.5, b = 0.5 } end return { r = 0.25, g = 0.75, b = 0.25 } end },
		{ __index = _G })
	local chunk = assert((loadstring or _G.load)(body, "rgb", "t", env))
	chunk()
	local r, g, b = ns.api.questDifficultyRGB(20)
	check("grey: game's rule (0) keeps the game's grey", r == 0.5 and g == 0.5)
	db.greyLevels = 12
	r, g = ns.api.questDifficultyRGB(20)
	check("grey: 12 levels: a quest 10 below stays green", r == 0.25 and g == 0.75)
	r = ns.api.questDifficultyRGB(18)
	check("grey: 12 levels: a quest 12 below is grey", r == 0.5)
	db.greyLevels = 3
	r = ns.api.questDifficultyRGB(26)
	check("grey: 3 levels: a quest 4 below is grey", r == 0.5)
	check("core: combat fade and situation alpha", core:find("situationAlpha", 1, true) ~= nil and core:find("combatFade", 1, true) ~= nil)
	check("our tracker: reminders row in the strip", io.open(dir .. "/Tracker/Own/Frame.lua"):read("a"):find("layoutReminders", 1, true) ~= nil)
	check("core: /qt commands from other files", core:find("function ns.api.addSlash", 1, true) ~= nil)
	check("core: 3.2 defaults", core:find("distanceClosest = 3", 1, true) ~= nil and core:find('autoReward = "off"', 1, true) ~= nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Rewards.lua
---------------------------------------------------------------------------------------------------------------------
do
	local items = {
		["item:1"] = { "Plate Helm", 2, 25, "INVTYPE_HEAD", 500, 4, 4, { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 5 } },
		["item:2"] = { "Cloth Hat", 2, 25, "INVTYPE_HEAD", 900, 4, 1, { ITEM_MOD_INTELLECT_SHORT = 12 } },
		["item:3"] = { "Mail Helm", 3, 33, "INVTYPE_HEAD", 300, 4, 3, { ITEM_MOD_STRENGTH_SHORT = 8 } },
		["item:9"] = { "Old Helm", 1, 10, "INVTYPE_HEAD", 10, 4, 3, { ITEM_MOD_STRENGTH_SHORT = 2 } },
	}
	local choices = { "item:1", "item:2", "item:3" }
	local loaded = true
	local ns = newNs({})
	load("Tracker/Rewards.lua", ns, {
		GetNumQuestChoices = function() return #choices end,
		GetQuestItemLink = function(_, i) return choices[i] end,
		GetQuestItemInfo = function() return "x", "t", 1 end,
		GetInventoryItemLink = function(_, slot) return slot == 1 and "item:9" or nil end,
		C_Item = {
			GetItemInfo = function(link)
				local i = items[link]
				if not i or not loaded then return nil end
				return i[1], link, i[2], i[3], 1, "Armor", "x", 1, i[4], 0, i[5], i[6], i[7]
			end,
			GetItemStats = function(link) return items[link] and items[link][8] or {} end,
		},
	})
	login(ns)
	local api = ns.api
	level = 45
	local list = api.rewardChoices()
	check("rewards: plate helm is an upgrade for a level 45 warrior", list[1].upgrade == true)
	check("rewards: cloth intellect hat is not", not list[2].upgrade)
	check("rewards: mail helm (strength 8 > 2) is an upgrade", list[3].upgrade == true)
	check("rewards: green item disenchants into dust and essence", list[1].de == "Strange Dust, Lesser Astral Essence")
	check("rewards: blue item level 33 disenchants into a glowing shard", list[3].de == "Small Glowing Shard")
	check("rewards: upgrade pick = biggest gain (plate)", api.pickReward("upgrade") == 1)
	check("rewards: value pick = sells for the most (hat)", api.pickReward("value") == 2)
	level = 20
	list = api.rewardChoices()
	check("rewards: plate is not wearable at level 20", not list[1].upgrade)
	loaded = false
	local pick, pending = api.pickReward("upgrade")
	check("rewards: items not loaded: wait", pick == nil and pending == true)
	loaded = true
	ns.db.rewardStat = "int"
	list = api.rewardChoices()
	check("rewards: stat picked by hand (intellect): the hat is an upgrade", list[2].upgrade == true)
end

---------------------------------------------------------------------------------------------------------------------
-- Reminders.lua
---------------------------------------------------------------------------------------------------------------------
do
	local services = {
		{ "Heroic Strike", "Rank 3", "available", 16, 600 }, { "Rend", "Rank 3", "unavailable", 20, 800 },
		{ "Cleave", "Rank 1", "unavailable", 22, 1000 }, { "Battle Shout", "Rank 1", "used", 1, 10 },
	}
	local talents = 2
	local bagQuest = { questID = 55, isActive = false }
	local ns = newNs({})
	local laid = 0
	ns.api.applyLayout = function() laid = laid + 1 end
	load("Tracker/Reminders.lua", ns, {
		IsTradeskillTrainer = function() return false end,
		GetNumTrainerServices = function() return #services end,
		GetTrainerServiceInfo = function(i) local s = services[i]; return s[1], s[2], s[3] end,
		GetTrainerServiceLevelReq = function(i) return services[i][4] end,
		GetTrainerServiceCost = function(i) return services[i][5] end,
		UnitCharacterPoints = function() return talents end,
		C_Map = { GetBestMapForUnit = function() return 1429 end,
			GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end },
		C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
			GetContainerItemQuestInfo = function() return bagQuest end,
			GetContainerItemLink = function() return "[Torn Note]" end },
		C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, GetTitleForQuestID = function() return "A Note" end },
		UIErrorsFrame = { AddMessage = function() end },
	})
	login(ns)
	local api = ns.api
	level = 20
	api.remindersScanTrainer()
	local due, cost = api.trainerDue()
	check("trainer: two spells at level 20 (not the used one, not level 22)", #due == 2 and cost == 1400)
	check("trainer: where the trainer stands is kept", ns.db.trainerLog["Ana-Realm"].trainer.map == 1429)
	check("trainer: the row asked again", laid > 0)
	check("talents: unspent points read", api.unspentTalents() == 2)
	local e = api.remindersEntries()
	check("reminders: trainer line and talent line", #e == 2 and e[1][1]:find("2 new spells", 1, true) ~= nil
		and e[2][1]:find("2 talent points", 1, true) ~= nil)
	ns.db.trainerReminder = false
	talents = 0
	check("reminders: both off or nothing to do: no line", #api.remindersEntries() == 0)
	_G.lastChat = nil
	api.remindersScanBags(true)
	check("quest item: alert in chat", type(_G.lastChat) == "string" and _G.lastChat:find("starts a quest", 1, true) ~= nil)
	_G.lastChat = nil
	api.remindersScanBags(true)
	check("quest item: only once", _G.lastChat == nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Journal.lua: kill counts
---------------------------------------------------------------------------------------------------------------------
do
	local units = {}
	local ns = newNs({})
	load("Tracker/Journal.lua", ns, {
		UnitExists = function(u) return units[u] ~= nil end,
		UnitGUID = function(u) return units[u] and units[u].guid end,
		UnitIsDead = function(u) return units[u] and units[u].dead end,
		UnitIsTapDenied = function(u) return units[u] and units[u].denied end,
		UnitAffectingCombat = function(u) return units[u] and units[u].combat end,
		UnitCanAttack = function() return true end,
	})
	login(ns)
	local api = ns.api
	check("kills: npc ID from a creature GUID", api.journalNpcId("Creature-0-3110-0-1234-299-0000ABCD") == 299)
	check("kills: a player GUID is no npc", api.journalNpcId("Player-1-0ABC") == nil)
	units.target = { guid = "Creature-0-1-0-1-299-01", combat = true }
	api.journalLook("target")
	units.target.dead = true
	api.journalLook("target")
	check("kills: a mob that fought us and died counts", api.killCount(299) == 1)
	api.journalLook("target")
	check("kills: the same one counts once", api.killCount(299) == 1)
	units.target = { guid = "Creature-0-1-0-1-299-02", combat = true, denied = true }
	api.journalLook("target")
	units.target.dead = true
	api.journalLook("target")
	check("kills: another player's mob does not count", api.killCount(299) == 1)
	check("kills: session count", api.killSessionCount() == 1)
end
-- 3.2 (user: "I dont see gold dots of where I've went"): a path point on whatever map is shown
do
	local function vec(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
	-- map 10 is a zone inside map 20 (its parent), at x 0.5-0.75 and y 0.25-0.5
	local ns = newNs({})
	load("Tracker/Journal.lua", ns, {
		CreateVector2D = vec,
		C_Map = {
			GetWorldPosFromMapPos = function(m, p)
				if m == 10 then return 0, vec(0.5 + p.x * 0.25, 0.25 + p.y * 0.25) end
				if m == 20 then return 0, vec(p.x, p.y) end
			end,
			GetMapPosFromWorldPos = function(_, w, shown)
				if shown == 20 then return 20, vec(w.x, w.y) end
				if shown == 10 then return 10, vec((w.x - 0.5) * 4, (w.y - 0.25) * 4) end
			end,
		},
	})
	local project = ns.api.journalProject
	local x, y = project(10, 0.4, 0.6, 10)
	check("path: same map, same spot", x == 0.4 and y == 0.6)
	x, y = project(10, 0.4, 0.6, 20)
	check("path: a zone's point on its parent map", math.abs(x - 0.6) < 1e-9 and math.abs(y - 0.4) < 1e-9)
	check("path: a point off the shown map is left out", project(20, 0.1, 0.1, 10) == nil)
	local om = { WorldFromMap = function(m, px, py) return px + m, py + m end,
		MapFromWorld = function(host, u, v) return u - host, v - host end }
	x, y = project(10, 0.4, 0.6, 30, om)
	check("path: OpenMap's stitched map, through its world space (past the edge too)", math.abs(x + 19.6) < 1e-9
		and math.abs(y + 19.4) < 1e-9)
end

---------------------------------------------------------------------------------------------------------------------
-- DungeonPlus.lua: splits and the card's lines
---------------------------------------------------------------------------------------------------------------------
do
	local ns = newNs({})
	ns.api.dungeonInstance = function() return "party", "Deadmines", 36 end
	ns.api.partyQuestHolders = function(want)
		local out = {}
		if want(101) then out[101] = { "You", "Bob Smith" } end
		if want(102) then out[102] = { "Bob Smith" } end
		return out
	end
	ns.api.questieGet = function(_, id, field)
		if field == "zoneOrSort" then return (id == 101 or id == 102) and 1581 or 12 end
		if field == "name" then return "Quest " .. id end
	end
	ns.api.questieZoneName = function(area) return area == 1581 and "The Deadmines" or "Elwynn" end
	load("Tracker/DungeonPlus.lua", ns, { IsInGroup = function() return true end,
		C_QuestLog = { GetTitleForQuestID = function() return nil end, GetNumQuestLogEntries = function() return 0 end } })
	login(ns)
	local api = ns.api
	clock = 100
	api.dungeonOnEnter()
	clock = 400
	api.dungeonOnEncounterEnd(nil, "Rhahk'Zor", 1, 5, 1)
	check("splits: first kill kept as the best", ns.db.splitLog.Deadmines["Rhahk'Zor"] == 300)
	clock = 1000
	api.dungeonOnEnter()
	check("splits: back within 30 min: the same run", api.dungeonRunForTests().start == 100)
	-- the instance name must match Questie's zone name: "Deadmines" vs "The Deadmines" does not, so none
	local e = api.dungeonExtraEntries("The Deadmines")
	local texts = {}
	for _, d in ipairs(e) do texts[#texts + 1] = type(d.text) == "function" and d.text() or d.text end
	local all = table.concat(texts, " | ")
	check("card: the run line", all:find("Run", 1, true) ~= nil and all:find("1 boss", 1, true) ~= nil)
	check("card: quests here, with who", all:find("Quests here", 1, true) ~= nil and all:find("Bob 2", 1, true) ~= nil)
	check("card: share line for my one quest", all:find("Share 1 quest", 1, true) ~= nil)
	ns.db.dungeonSplits, ns.db.dungeonPartyQuests, ns.db.dungeonShare = false, false, false
	check("card: switched off: no lines", #api.dungeonExtraEntries("The Deadmines") == 0)
end

---------------------------------------------------------------------------------------------------------------------
-- Chains.lua
---------------------------------------------------------------------------------------------------------------------
do
	local ns = newNs({})
	local next = { [1] = 2, [2] = 3, [10] = nil }
	ns.api.questieGet = function(_, id, field)
		if field == "nextQuestInChain" then return next[id] end
		if field == "questLevel" then return id end
		if field == "name" then return "Q" .. id end
	end
	load("Tracker/Chains.lua", ns, { UnitFactionGroup = function() return "Horde" end })
	login(ns)
	local api = ns.api
	local chains = api.chainsOf({ 3, 10, 1, 2 })
	check("chains: 1 > 2 > 3 is one chain, 10 alone", #chains == 2 and #chains[1] == 3 and chains[1][1] == 1 and chains[2][1] == 10)
	local att = api.chainsAttunements
	local horde, alliance = 0, 0
	for _, a in ipairs(att) do
		if a.faction == "Horde" then horde = #a.quests end
		if a.faction == "Alliance" then alliance = #a.quests end
	end
	check("attunements: both Onyxia chains listed", horde == 14 and alliance == 16)
end

---------------------------------------------------------------------------------------------------------------------
-- Source wiring: settings, setup, toc
---------------------------------------------------------------------------------------------------------------------
do
	local toc = read("ForeverTrackerPlus.toc")
	check("toc: version 3.2", toc:find("## Version: 3.2", 1, true) ~= nil)
	local order = {}
	for line in toc:gmatch("[^\r\n]+") do order[#order + 1] = line end
	local pos = {}
	for i, l in ipairs(order) do pos[l] = i end
	local ok = true
	for _, f in ipairs({ "Journal", "Reminders", "Rewards", "DungeonPlus", "Chains" }) do
		ok = ok and pos["Tracker/" .. f .. ".lua"] ~= nil and pos["Tracker/" .. f .. ".lua"] < pos["Tracker/Config.lua"]
	end
	check("toc: the new files load before Config.lua", ok and pos["Tracker/DungeonPlus.lua"] > pos["Tracker/Dungeon.lua"])
	local config = read("Tracker/Config.lua")
	for _, key in ipairs({ "reminders", "rewards", "dungeonextras", "attunements", "classquests", "profquests" }) do
		check("config: page " .. key .. " has a section", config:find(key .. ' = "', 1, true) ~= nil)
	end
	check("config: pageDeclarers called", config:find("api.pageDeclarers", 1, true) ~= nil)
	for _, label in ipairs({ "Closest quests with distance", "Time to arrive", "In combat", "In a raid group",
		"Hide done objectives", "Sort quests in a zone", "Grey quests from" }) do
		check("config: " .. label, config:find('"' .. label .. '"', 1, true) ~= nil)
	end
	local setup = read("Tracker/Setup.lua")
	check("setup: version 4", setup:find("SETUP_VERSION = 4", 1, true) ~= nil)
	check("setup: new title", setup:find("TrackerPlus|r  |cffb0a99cSetup", 1, true) ~= nil and setup:find("|cfff2e6c8RXP|r", 1, true) == nil)
	local changelog = read("CHANGELOG.md")
	check("changelog: 3.2 section", changelog:find("\n## 3.2\r?\n") ~= nil)
	local extras = read("Tracker/Extras.lua")
	check("extras: no CLEU anywhere new", not read("Tracker/Journal.lua"):find('"COMBAT_LOG_EVENT', 1, true))
	check("our tracker: done objectives left out", io.open(dir .. "/Tracker/Own/Data.lua"):read("a"):find("hideDoneObjectives", 1, true) ~= nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Setup.lua: the "New in 3.2" steps fit the window (6 rows at most)
---------------------------------------------------------------------------------------------------------------------
do
	local setup = read("Tracker/Setup.lua")
	local fn = setup:match("local function newSteps.-\nend\r?\n")
	check("setup: newSteps found", fn ~= nil)
	local env = setmetatable({ api = {}, call = function() end, questieLoaded = function() return true end }, { __index = _G })
	local src = "local function row(label, helpText, get, set, only) if only == false then return nil end return { label = label } end\n"
		.. "local function list(...) local out = {} for i = 1, select('#', ...) do local r = select(i, ...); if r then out[#out + 1] = r end end return out end\n"
		.. fn .. "\nreturn newSteps"
	local newSteps = assert((loadstring or _G.load)(src, "steps", "t", env))()
	local out = {}
	newSteps({}, out)
	local okRows = #out == 4
	for _, s in ipairs(out) do okRows = okRows and #(s.rows or {}) <= 6 end
	check("setup: four new steps, each with at most 6 switches", okRows)
end

print(pass and "ALL PASS" or "SOME FAILED")
