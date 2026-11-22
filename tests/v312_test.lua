-- 3.1.2: Guides (Legacy Challenges "only this character" + unlearnt professions, tooltips; library books "?" status,
-- "Show collected books"; the sleeping bag chain done), Statistics (max level, gold, tiles, jump / swim / craft
-- states, standing kept in Time per level) and Forever Style as the only RXP Tracker look.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local function tipText(tip) local t = {} for i, l in ipairs(tip or {}) do t[i] = type(l) == "table" and l[1] or l end return table.concat(t, "|") end
local function obj()
	return setmetatable({}, { __index = function() return function() end end })
end

---------------------------------------------------------------------------------------------------------------------
-- Guides.lua
---------------------------------------------------------------------------------------------------------------------
local done = {}
local clock = 100
local ACH = {
	{ 11, "Master Alchemist", "Reach a high skill.", { { "Skill 300", 7, false, 171 } } },
	{ 12, "Herb Lover", "Pick Herbalism herbs.", { { "Pick 10", 0, false, 0 } } },
	{ 13, "Other Side", "Win for them.", { { "Their city", 0, false, 0, false } } },
	{ 14, "Class Chain", "Do a chain.", { { "Class quest", 27, false, 500 } } },
	{ 15, "Explorer", "Go places.", { { "A cave", 0, false, 0 }, { "A hill", 0, true, 0 } } },
}
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return obj() end,
	GetTime = function() return clock end,
	C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end, GetLogIndexForQuestID = function() return nil end },
	C_Item = { GetItemCount = function(id) return id == 9605 and 1 or 0 end },
	C_SkillInfo = {
		GetSkillLineInfoByID = function(id) if id == 182 then return { name = "Herbalism", skillID = 182, rank = 50 } end end,
		GetNumSkillLines = function() return 2 end,
		GetSkillLineInfo = function(i)
			if i == 1 then return { name = "Professions", isHeader = true } end
			return { name = "Herbalism", skillID = 182, rank = 50, isHeader = false }
		end,
	},
	GetCategoryList = function() return { 1 } end,
	GetCategoryInfo = function() return "Legacy" end,
	GetCategoryNumAchievements = function() return #ACH end,
	GetAchievementInfo = function(_, i) local a = ACH[i] return a[1], a[2], 10, false, nil, nil, nil, a[3], 0x8000000 end,
	GetAchievementNumCriteria = function(id) for _, a in ipairs(ACH) do if a[1] == id then return #a[4] end end return 0 end,
	GetAchievementCriteriaInfo = function(id, k)
		for _, a in ipairs(ACH) do
			if a[1] == id then
				local c = a[4][k]
				local eligible = c[5]
				if eligible == nil then eligible = true end
				return c[1], c[2], c[3], 0, 1, nil, 0, c[4], "", k, eligible
			end
		end
	end,
	DEFAULT_CHAT_FRAME = { AddMessage = function() end }, GameTooltip = obj(),
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Guides.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do fn() end
local api = ns.api
api.questieOn = function() return true end
api.questieForPlayer = function(id) return id ~= 500 end

local function names(rows)
	local out = {}
	for _, r in ipairs(rows) do if not r.header then out[#out + 1] = r[2] end end
	return table.concat(out, ",")
end
local function row(rows, name) for _, r in ipairs(rows) do if r[2] == name then return r end end end

-- the professions this character knows
local known = api.guideKnownSkills()
check("skills: Herbalism known by ID and name", known[182] and known.herbalism and true or false)
check("skills: Alchemy not known", not known[171] and not known.alchemy)

-- Legacy Challenges, the switch off: every open one
local rows = api.guideLegacyRows()
check("legacy: all five open ones listed", names(rows) == "Master Alchemist,Herb Lover,Other Side,Class Chain,Explorer")
check("legacy: the header has a tooltip", rows[1].header and rows[1].tip and rows[1].tip[1]:find("5 Legacy Challenges", 1, true) ~= nil)
local alch = row(rows, "Master Alchemist")
check("legacy tooltip: names the unlearnt profession", tipText(alch.tip):find("not learned: Alchemy", 1, true) ~= nil)
check("legacy tooltip: steps done line", tipText(alch.tip):find("0 of 1 steps done", 1, true) ~= nil)
check("legacy tooltip: description", alch.tip[1] == "Reach a high skill.")
local other = row(rows, "Other Side")
check("legacy: not eligible -> red reason and a cross", tipText(other.tip):find("cannot do", 1, true) ~= nil
	and other[1] == "Interface\\RaidFrame\\ReadyCheck-NotReady")
check("legacy: quest for another race or class -> reason", tipText(row(rows, "Class Chain").tip):find("another race or class", 1, true) ~= nil)
check("legacy: profession named in the text of a known one -> no need", tipText(row(rows, "Herb Lover").tip):find("not learned", 1, true) == nil)
check("legacy: still-to-do list in the tooltip", tipText(row(rows, "Explorer").tip):find("A cave", 1, true) ~= nil)

-- only the ones this character can do
ns.db.legacyOnlyMine = true
check("only mine: blocked and unlearnt-profession ones hidden", names(api.guideLegacyRows()) == "Herb Lover,Explorer")
ns.db.legacyWithProfs = true
check("only mine + unlearnt professions: the profession one back", names(api.guideLegacyRows()) == "Master Alchemist,Herb Lover,Explorer")
ns.db.legacyOnlyMine = false
check("unlearnt professions box does nothing alone", names(api.guideLegacyRows()):find("Other Side", 1, true) ~= nil)

-- library books
local SPOTS = { [701] = { 1429, 0.5, 0.25, "Elwynn Forest" }, [702] = { 1429, 0.1, 0.1, "Elwynn Forest" },
	[704] = { 1453, 0.3, 0.4, "Stormwind City" }, [705] = { 1453, 0.3, 0.4, "Stormwind City" } }
api.questieGuideData = function() return { books = {
	{ quest = 601, name = "Book A", object = 701 }, { quest = 602, name = "Book B", object = 702 },
	{ quest = 603, name = "Book C", object = 703 }, { quest = 604, name = "Book D", object = 704 },
	{ quest = 605, name = "Book E", object = 705, item = 9605 },
}, named = {} } end
api.questieSpot = function(_, id) local s = SPOTS[id] if s then return s[1], s[2], s[3], s[4] end end
api.questieHidden = function(id) return id == 602 end
api.questieLibrarian = function() return "Librarian Mae" end
done[601] = true
local books = api.guideBookRows()
check("books: header counts every book", books[1].header and books[1][3] == "1 of 5 turned in")
local b = row(books, "Book B")
check("books: hidden by Questie -> ?", b[1] == "Interface\\Icons\\INV_Misc_QuestionMark" and b[3] == "status unknown"
	and tipText(b.tip):find("not in the game", 1, true) ~= nil and b.onClick == nil)
local c = row(books, "Book C")
check("books: no place known -> ? with its reason", c[1] == "Interface\\Icons\\INV_Misc_QuestionMark"
	and tipText(c.tip):find("does not know where", 1, true) ~= nil)
local d = row(books, "Book D")
check("books: open book has a place, librarian and waypoint", tipText(d.tip):find("Stormwind City (30.0, 40.0)", 1, true) ~= nil
	and tipText(d.tip):find("Librarian Mae", 1, true) ~= nil and d.onClick ~= nil)
check("books: in the bags", row(books, "Book E")[3] == "in your bags")
check("books: a turned-in one has a tooltip", tipText(row(books, "Book A").tip):find("Turned in", 1, true) ~= nil)
ns.db.booksShowDone = false
books = api.guideBookRows()
check("books: Show collected books off hides the turned-in one", row(books, "Book A") == nil and row(books, "Book D") ~= nil
	and books[1][3] == "1 of 5 turned in")
ns.db.booksShowDone = nil

-- the sleeping bag chain
local NEXT = { [79008] = { 79192 }, [79192] = { 79976 }, [79976] = {} }
api.questieGuideData = function() return { books = {}, named = {} } end -- the name search found nothing
api.questieGet = function(kind, id, field)
	if kind == "Quest" and field == "name" then return ({ [79008] = "... and that note you found", [79192] = "Stepping Stones",
		[79976] = "This Must Be The Place" })[id] end
end
api.questieForPlayer = function(id) return id ~= 79007 end
api.questieNextQuests = function(id) return NEXT[id] or {} end
api.questieSpot = function() return nil end
local bed = api.guideBedrollRows()
check("bedroll: the note row first, wrapped", bed[1].note == true and bed[1][2]:find("From level 14", 1, true) ~= nil)
check("bedroll: found by its known IDs when the name search finds nothing", bed[2].header and bed[2][3] == "0 of 3 done"
	and bed[3][2] == "... and that note you found")
done[79008], done[79192] = true, true
bed = api.guideBedrollRows()
check("bedroll: part done shows the steps", bed[2][3] == "2 of 3 done")
done[79976] = true
bed = api.guideBedrollRows()
check("bedroll: all done -> one green line with a check", #bed == 1 and bed[1][2] == "You have completed this questchain."
	and bed[1][1] == "Interface\\RaidFrame\\ReadyCheck-Ready" and bed[1][4] and bed[1][4][2] > 0.8)
api.questieOn = function() return false end
bed = api.guideBedrollRows()
check("bedroll: done even without Questie", #bed == 1 and bed[1][2] == "You have completed this questchain.")
done[79976] = nil
bed = api.guideBedrollRows()
check("bedroll: not done, no Questie -> note and Needs Questie", bed[1].note and bed[2][2] == "Needs Questie.")

-- the pages
local checks, notes, byPage, current = {}, {}, {}, nil
local kit = { page = function(key) current = key; byPage[key] = {} end, heading = function() end,
	check = function(l, get, set, enabled, indent) checks[l] = { get = get, set = set, enabled = enabled, indent = indent };
		byPage[current][#byPage[current] + 1] = l end,
	help = function() end, note = function(t) notes[current] = t end, custom = function() end, buttons = function() end,
	pageByKey = setmetatable({}, { __index = function(t, k) local p = {}; rawset(t, k, p) return p end }), refresh = function() end }
api.declareGuidePages(kit)
check("legacy page: the only-mine switch", checks["Only challenges this character can do"] ~= nil)
local profs = checks["Include professions you have not learned"]
check("legacy page: the professions box sits under it, on only with the switch", profs and profs.indent and profs.enabled ~= nil)
ns.db.legacyOnlyMine = false
check("legacy page: professions box greyed while the switch is off", profs and profs.enabled() == false)
check("books page: Show collected books, on by default", checks["Show collected books"] and checks["Show collected books"].get() == true)
check("bedroll page: no fixed note (the rows carry it)", notes.bedroll == nil)

---------------------------------------------------------------------------------------------------------------------
-- Stats.lua
---------------------------------------------------------------------------------------------------------------------
local handlers = {}
local function frame()
	return setmetatable({}, { __index = function(t, k)
		if k == "SetScript" then return function(_, _, fn) handlers[#handlers + 1] = fn end end
		if k == "IsEventRegistered" then return function() return true end end
		return function() end
	end })
end
local now, wall = 1000, 5000000
local tickers, afters, hooks = {}, {}, {}
local st = { swim = false, fall = false, speed = 0, level = 59, xp = 100, max = 1000, money = 5000, cast = nil, channel = nil }
local shownFrames = {}
local sns = { api = {}, onLogin = {}, db = {} }
local senv
senv = setmetatable({
	CreateFrame = frame, GetTime = function() return now end, time = function() return wall end,
	C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn return { Cancel = function() end } end,
		After = function(_, fn) afters[#afters + 1] = fn end },
	UnitName = function() return "Jugo" end, GetRealmName = function() return "Realm" end,
	UnitClass = function() return "Warlock", "WARLOCK" end,
	UnitLevel = function() return st.level end, UnitXP = function() return st.xp end, UnitXPMax = function() return st.max end,
	UnitIsDeadOrGhost = function() return false end, UnitOnTaxi = function() return false end,
	UnitAffectingCombat = function() return false end, UnitIsAFK = function() return false end,
	GetUnitSpeed = function() return st.speed end, IsMounted = function() return false end,
	IsSwimming = function() return st.swim end, IsFalling = function() return st.fall end,
	UnitCastingInfo = function() if st.cast then return table.unpack(st.cast) end end,
	UnitChannelInfo = function() if st.channel then return table.unpack(st.channel) end end,
	C_Spell = { GetSpellInfo = function(id) if id == 7620 then return { name = "Fishing" } end end },
	GetMoney = function() return st.money end,
	GetNumLootItems = function() return 1 end,
	GetLootSourceInfo = function() return st.lootGuid or "Creature-0-1-2-3-4-5" end,
	GetMaxPlayerLevel = function() return 60 end,
	JumpOrAscendStart = function() end,
	hooksecurefunc = function(a, b, c) if type(a) == "string" then hooks[a] = b else hooks[b] = c end end,
	RequestTimePlayed = function() end, GetRealZoneText = function() return "Elwynn Forest" end,
	C_QuestLog = { GetTitleForQuestID = function(id) return "Quest " .. id end },
	DEFAULT_CHAT_FRAME = { AddMessage = function() end }, NUM_CHAT_WINDOWS = 0,
	StaticPopupDialogs = {}, wipe = function(t) for k in pairs(t) do t[k] = nil end end,
	UIParent = frame(),
}, { __index = function(_, k)
	if shownFrames[k] then return { IsShown = function() return true end } end
	return _G[k]
end })
senv._G = senv
assert(loadfile(dir .. "/Tracker/Stats.lua", "t", senv))("ForeverTrackerPlus", { tracker = sns })
local sapi = sns.api
for _, fn in ipairs(sns.onLogin) do fn() end
local function fire(e, ...) for _, h in ipairs(handlers) do h(nil, e, ...) end end
local function tick(seconds) for _ = 1, seconds do now = now + 1; for _, t in ipairs(tickers) do pcall(t) end end end

-- the new states
tick(1)
st.swim = true; tick(4); st.swim = false
st.fall = true; tick(2); st.fall = false
rawset(senv, "TradeSkillFrame", { IsShown = function() return true end }); tick(3); rawset(senv, "TradeSkillFrame", nil)
st.cast = { "Linen Bandage", "", 0, 0, 0, true, 1, false, 3275 }; tick(2); st.cast = nil
st.cast = { "Mining", "", 0, 0, 0, false, 1, false, 2575 }; tick(1); st.cast = nil
st.channel = { "Fishing", "", 0, 0, 0, false, false, 99999 }; tick(2); st.channel = nil
st.cast = { "Fireball", "", 0, 0, 0, false, 1, false, 133 }; tick(1); st.cast = nil
tick(5)
local r = sapi.statsRun()
local t = r.levels[59].t
check("swimming counted", math.floor(t.swim + 0.5) == 4)
check("in the air with no jump counted as falling", math.floor(t.fall + 0.5) == 2 and (t.jump or 0) == 0)
check("crafting: window, tradeskill cast, gathering spell, fishing by name", math.floor(t.craft + 0.5) == 8)
check("a normal cast is not crafting (it is casting)", math.floor(t.cast + 0.5) == 1 and math.floor(t.idle + 0.5) >= 5)

-- jumps
check("jump hook installed", type(hooks.JumpOrAscendStart) == "function")
hooks.JumpOrAscendStart(); hooks.JumpOrAscendStart(); hooks.JumpOrAscendStart()
check("jumps counted for the run and the level", r.jumps == 3 and r.levels[59].jumps == 3)

-- gold
fire("QUEST_TURNED_IN", 501, 450, 1234)
check("gold from a quest", r.gold.quests == 1234)
st.money = 5000 + 1234; fire("PLAYER_MONEY")
check("money from a quest is not counted as loot", r.gold.loot == 0)
fire("LOOT_OPENED")
st.money = 6000; fire("PLAYER_MONEY") -- less money is never counted
st.money = 6250; fire("PLAYER_MONEY")
check("gold off a mob while its loot window is open", r.gold.loot == 250)
fire("LOOT_CLOSED")
now = now + 3
st.money = 9000; fire("PLAYER_MONEY")
check("money after the loot window closed is not counted", r.gold.loot == 250)
st.lootGuid = "GameObject-0-1-2-3-4-5"
fire("LOOT_OPENED"); st.money = 9500; fire("PLAYER_MONEY"); fire("LOOT_CLOSED")
check("a chest's money is not gold off mobs", r.gold.loot == 250)
local gold = sapi.statsGoldTiles()
check("gold tiles: quests, mobs, session, total", #gold == 4 and gold[1][3] == "Gold from quests" and gold[2][3] == "Gold off mobs"
	and gold[2][2]:find("2", 1, true) ~= nil and gold[3][3] == "Gold this session")
check("money text", sapi.statsMoney(123456):find("^12|cffffd100g|r 34") ~= nil and sapi.statsMoney(305):find("^3|cffc7c7cfs|r 5") ~= nil)

-- overview tiles
local function labels(list) local o = {} for i, x in ipairs(list) do o[i] = x[3] end return table.concat(o, ",") end
local tiles = sapi.statsOverviewTiles()
check("overview: no Fastest quest", not labels(tiles):find("Fastest", 1, true))
check("overview: experience tiles below the cap", labels(tiles):find("Experience from quests", 1, true) and labels(tiles):find("Session experience", 1, true) and true or false)
local xpTile
for _, x in ipairs(tiles) do if x[3] == "Experience from quests" then xpTile = x end end
check("overview: Experience from quests has no coin icon", xpTile and not xpTile[1]:find("Coin", 1, true))
check("level bar below the cap: xp numbers", sapi.statsLevelBar()[1][2]:find("/", 1, true) ~= nil)
st.level = 60
tiles = sapi.statsOverviewTiles()
check("overview at the cap: no experience tiles", not labels(tiles):find("xperience", 1, true) and #tiles == 5)
local bar = sapi.statsLevelBar()[1]
check("level bar at the cap: no bar to 61, a full one marked maximum", bar[1] == "Level 60" and bar[2] == "maximum level" and bar[3] == 1)

-- run analysis
local bars = sapi.statsTimeBars()
local bl = {}
for i, x in ipairs(bars) do bl[i] = x[1] end
bl = table.concat(bl, ",")
check("run analysis: Standing kept, Jumping / Swimming / Crafting in", bl:find("Standing", 1, true)
	and bl:find("Jumping", 1, true) and bl:find("Swimming", 1, true) and bl:find("Crafting/gathering", 1, true) and true or false)
local run = sapi.statsRunTiles()
check("run analysis: a Jumps tile", run[6][3] == "Jumps" and run[6][2] == "3")
check("run analysis: Gold acquired after XP from quests, no coin on XP", run[3][3] == "XP from quests" and not run[3][1]:find("Coin", 1, true)
	and run[4][3] == "Gold acquired" and run[4][1]:find("Coin", 1, true) ~= nil)
local lines = sapi.statsLevelLines()
check("time per level keeps standing", lines[1] and lines[1][3]:find("Standing", 1, true) ~= nil)
check("discord text: jumps and the standing line", sapi.statsDiscordText():find("3 jumps", 1, true) ~= nil
	and sapi.statsDiscordText():match("\nStanding ") ~= nil)

---------------------------------------------------------------------------------------------------------------------
-- Forever Style only
---------------------------------------------------------------------------------------------------------------------
local gdb = { theme = "rxp" }
local ons = {}
local oenv = setmetatable({ ForeverTrackerPlusGuideDB = gdb, C_AddOns = { GetAddOnMetadata = function() return "3.1.2" end },
	Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end, DEFAULT_CHAT_FRAME = { AddMessage = function() end },
	C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end },
	CreateFrame = function() return obj() end, hooksecurefunc = function() end },
	{ __index = function(_, k) local v = _G[k]; if v ~= nil then return v end return nil end })
oenv._G = oenv
local okCore, errCore = pcall(function() assert(loadfile(dir .. "/Objectives/Core.lua", "t", oenv))("ForeverTrackerPlus", { objectives = ons }) end)
check("Objectives/Core.lua loads", okCore or print(errCore))
check("a saved RXP Style becomes Forever Style", gdb.theme == "forever")
check("Forever Style always on", ons.forever and ons.forever() == true)
local config = io.open(dir .. "/Tracker/Config.lua"):read("a")
check("settings: no theme choice", not config:find("RXP Style", 1, true) and not config:find('choice("Theme"', 1, true))

print(pass and "ALL OK" or "SOME FAILED")
