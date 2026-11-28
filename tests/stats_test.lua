-- 3.0: statistics (Stats.lua): the clock's states, quests, /played splits, the level-up line, comparing runs, the
-- Discord text; helpers (Helpers.lua): the quest items read from the log; the settings pages they declare
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local handlers = {}
local function frame()
	local f = {}
	return setmetatable(f, { __index = function(t, k)
		if k == "SetScript" then return function(_, _, fn) handlers[#handlers + 1] = fn end end
		if k == "IsEventRegistered" then return function() return true end end
		return function() end
	end })
end
local now, wall = 1000, 5000000
local tickers, afters = {}, {}
local chat = {}
local state = { dead = false, taxi = false, combat = false, afk = false, speed = 0, mounted = false, level = 10, xp = 100, max = 1000 }
local shownFrames = {}
local played = nil
local log = {
	{ title = "Linen for the Tailor", header = false, boards = { { "Linen Cloth: 3/10", "item", false }, { "Kill wolves: 2/5", "monster", false } } },
	{ title = "Done Things", header = false, boards = { { "Silk Cloth: 5/5", "item", true } } },
}
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = frame, GetTime = function() return now end, time = function() return wall end,
	C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn return { Cancel = function() end } end,
		After = function(_, fn) afters[#afters + 1] = fn end },
	UnitName = function() return "Jugo" end, GetRealmName = function() return "Realm" end,
	UnitClass = function() return "Warlock", "WARLOCK" end,
	UnitLevel = function() return state.level end, UnitXP = function() return state.xp end, UnitXPMax = function() return state.max end,
	UnitIsDeadOrGhost = function() return state.dead end, UnitOnTaxi = function() return state.taxi end,
	UnitAffectingCombat = function() return state.combat end, UnitIsAFK = function() return state.afk end,
	GetUnitSpeed = function() return state.speed end, IsMounted = function() return state.mounted end,
	RequestTimePlayed = function() if played then for _, h in ipairs(handlers) do h(nil, "TIME_PLAYED_MSG", played[1], played[2]) end end end,
	GetRealZoneText = function() return "Elwynn Forest" end,
	C_QuestLog = { GetTitleForQuestID = function(id) return "Quest " .. id end, GetNumQuestLogEntries = function() return #log end,
		GetInfo = function(i) local q = log[i] return q and { title = q.title, isHeader = q.header } end },
	GetNumQuestLeaderBoards = function(i) return #log[i].boards end,
	GetQuestLogLeaderBoard = function(j, i) local b = log[i].boards[j] return b[1], b[2], b[3] end,
	DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end },
	NUM_CHAT_WINDOWS = 1, ChatFrame1 = frame(),
	hooksecurefunc = function() end, StaticPopupDialogs = {}, wipe = function(t) for k in pairs(t) do t[k] = nil end end,
	UIParent = frame(),
}, { __index = function(_, k)
	if shownFrames[k] then return { IsShown = function() return true end } end
	return _G[k]
end })
env._G = env
local root = { tracker = ns }
assert(loadfile(dir .. "/Tracker/Stats.lua", "t", env))("ForeverTrackerPlus", root)
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("ForeverTrackerPlus", root)
local api = ns.api
for _, fn in ipairs(ns.onLogin) do fn() end
local function fire(e, ...) for _, h in ipairs(handlers) do h(nil, e, ...) end end
local function tick(seconds) for _ = 1, seconds do now = now + 1; for _, t in ipairs(tickers) do pcall(t) end end end
local function flush() local list = afters; afters = {}; for _, fn in ipairs(list) do fn() end end

-- the clock
tick(1)
state.speed = 7; tick(10)
state.mounted = true; tick(5)
state.combat = true; tick(4)
state.combat, state.speed, state.mounted = false, 0, false
rawset(env, "MerchantFrame", { IsShown = function() return true end }); tick(3); rawset(env, "MerchantFrame", nil)
state.afk = true; tick(2); state.afk = false
tick(6)
local r = api.statsRun()
local t = r.levels[10].t
check("walking counted", math.floor(t.walk + 0.5) == 10)
check("mounted counted", math.floor(t.mount + 0.5) == 5)
check("combat counted", math.floor(t.combat + 0.5) == 4)
check("npc window counted", math.floor(t.npc + 0.5) == 3)
check("afk counted", math.floor(t.afk + 0.5) == 2)
check("standing counted", math.floor(t.idle + 0.5) >= 6)
now = now + 600; tick(1)
check("a long stall counts at most 5 s", t.idle < 14)

-- quests
fire("QUEST_ACCEPTED", 3, 501)
wall = wall + 125
fire("QUEST_TURNED_IN", 501, 450, 0)
fire("QUEST_TURNED_IN", 502, 50, 0)
check("two quests done", r.quests.done == 2 and r.quests.xp == 500)
check("zone counted", r.quests.zones["Elwynn Forest"] == 2)
check("quest time from accept to hand-in", r.quests.timed == 1 and r.quests.timeSum == 125)
check("fastest quest named", r.quests.fastest and r.quests.fastest.title == "Quest 501")
check("level record has the quests", r.levels[10].quests == 2 and r.levels[10].questXP == 500)

-- experience and a level up with /played
state.xp = 600; fire("PLAYER_XP_UPDATE")
check("xp gained counted", r.levels[10].xp == 500)
played = { 7200, 1800 }
api.statsRequestPlayed()
check("the level's start from /played", r.reached[10] == 5400)
state.level, state.xp = 11, 200; fire("PLAYER_XP_UPDATE")
check("xp across the level boundary", r.levels[10].xp == 1100)
played = { 9000, 10 }
fire("PLAYER_LEVEL_UP", 11)
flush()
check("level 11's start", r.reached[11] == 8990)
local line = chat[#chat] or ""
check("level-up line: level and time taken", line:find("Level 11!", 1, true) ~= nil and line:find("Level 10 took 59m 50s", 1, true) ~= nil)
check("level time from /played", api.statsLevelTime(r, 10) == 3590)

-- compare and Discord
ns.db.statsRuns["Alt-Realm"] = { reached = { [10] = 100, [11] = 3000 }, levels = {} }
ns.db.statsCompare = "Alt-Realm"
local opts = api.statsCompareOptions()
check("compare options list the other run", opts[2] and opts[2][1] == "Alt-Realm")
local text = api.statsDiscordText()
check("discord text has the header", text:find("**Jugo**", 1, true) ~= nil)
check("discord text compares level 10", text:find("Lv 10", 1, true) ~= nil and text:find("+11m 30s", 1, true) ~= nil)

-- 3.2: the Character dropdown: another character's record on the pages, recording stays ours
local vopts = api.statsViewOptions()
check("view options: this character first, then the alt", vopts[1][1] == "me" and vopts[1][2]:find("Jugo", 1, true) ~= nil
	and vopts[2] and vopts[2][1] == "Alt-Realm" and vopts[2][2] == "Alt (level 11)")
ns.db.statsView = "Alt-Realm"
check("viewing the alt", api.statsViewKey() == "Alt-Realm" and api.statsViewed() == ns.db.statsRuns["Alt-Realm"])
check("compare leaves out the viewed one", (function()
	for _, o in ipairs(api.statsCompareOptions()) do if o[1] == "Alt-Realm" then return false end end
	return true end)())
check("recording still goes to this character", api.statsRun() ~= ns.db.statsRuns["Alt-Realm"])
check("discord names the viewed character", api.statsDiscordText():find("**Alt**", 1, true) ~= nil)
ns.db.statsView = "Gone-Realm"
check("a missing record falls back to this character", api.statsViewKey() ~= "Gone-Realm")
ns.db.statsView = nil

-- a younger character under the same name
played = { 50, 50 }
api.statsRequestPlayed(); now = now + 20; api.statsRequestPlayed()
check("rolled again: old run kept as previous", type(ns.db.statsRuns["Jugo-Realm (previous)"]) == "table")

-- abandon and death
state.level = 11
fire("PLAYER_DEAD")
check("death counted", api.statsRun().levels[11].deaths == 1)

-- the pages
local declared, pages = {}, {}
local kit = {
	page = function(key, group, title) pages[#pages + 1] = key end,
	heading = function(l) declared[#declared + 1] = { kind = "heading", label = l } end,
	check = function(l) declared[#declared + 1] = { kind = "check", label = l } end,
	help = function(h) declared[#declared].sub = h end,
	note = function() end, buttons = function() end, choice = function(l) declared[#declared + 1] = { kind = "choice", label = l } end,
	slider = function() end, statusBox = function() end,
	custom = function(l, make) declared[#declared + 1] = { kind = "custom", label = l, make = make } end,
	input = function() declared[#declared + 1] = { kind = "input" } end,
	pageByKey = setmetatable({}, { __index = function(t, k) local p = {}; rawset(t, k, p) return p end }),
	declared = declared, reset = function() end, refresh = function() end,
}
api.declareStatsPages(kit)
api.declareHelperPages(kit)
local all = table.concat(pages, ",")
check("stats pages declared", all:find("statsoverview", 1, true) and all:find("statsrun", 1, true) and all:find("statssplits", 1, true) and true or false)
check("helper pages declared", all:find("helpers", 1, true) and all:find("world", 1, true) and true or false)
local helps = 0
for _, d in ipairs(declared) do if d.kind == "check" and d.sub then helps = helps + 1 end end
check("every helper and stats switch has a help line", helps >= 7)

print(pass and "ALL OK" or "SOME FAILED")
