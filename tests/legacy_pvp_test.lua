-- 3.1.2 Legacy Challenges: the PvP category shows as "PVP Ranking", a rank's challenge gets this faction's PvP
-- title, and an open challenge shows its own icon (not the "!").
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local function obj() return setmetatable({}, { __index = function() return function() end end }) end

local faction = "Alliance"
local CATS = {
	[1] = { "Player vs. Player", { { 21, "Rank 6", 7001 }, { 22, "First Sergeant", 7002 }, { 23, "Grand Marshal", 7003 } } },
	[2] = { "Exploration", { { 31, "Explorer", 7004, true } } },
}
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return obj() end, GetTime = function() return 100 end,
	C_QuestLog = { IsQuestFlaggedCompleted = function() return false end },
	UnitFactionGroup = function() return faction end,
	GetCategoryList = function() return { 1, 2 } end,
	GetCategoryInfo = function(c) return CATS[c][1] end,
	GetCategoryNumAchievements = function(c) return #CATS[c][2] end,
	GetAchievementInfo = function(c, i)
		local a = CATS[c][2][i]
		return a[1], a[2], 10, a[4] or false, nil, nil, nil, "", 0x8000000, a[3]
	end,
	GetAchievementNumCriteria = function() return 0 end,
	DEFAULT_CHAT_FRAME = { AddMessage = function() end }, GameTooltip = obj(),
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Guides.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do fn() end
local api = ns.api
ns.db.legacyShowDone = true

check("rank from a number", api.guidePvpRank("Rank 6") == 6 and api.guidePvpRank("Reach R12") == 12)
check("rank from either faction's title, the longest match", api.guidePvpRank("Senior Sergeant") == 4
	and api.guidePvpRank("Knight-Champion") == 9 and api.guidePvpRank("Champion") == 10 and api.guidePvpRank("Sergeant") == 3)
check("no rank in other text", api.guidePvpRank("Explorer") == nil)

local rows = api.guideLegacyRows()
local function find(t) for _, r in ipairs(rows) do if r[2]:find(t, 1, true) then return r end end end
check("PvP category shown as PVP Ranking", find("PVP Ranking") and find("PVP Ranking").header == true)
check("Rank 6 gets the Alliance title Knight", find("Rank 6")[2]:find("Knight", 1, true) ~= nil)
check("a Horde title gets the Alliance one of its rank", find("First Sergeant")[2]:find("Sergeant Major", 1, true) ~= nil)
check("a name that is already this title: not twice", find("Grand Marshal")[2] == "Grand Marshal")
check("other categories keep their name, no title", find("Exploration") and find("Explorer")[2] == "Explorer")
check("open challenge: its own icon", find("Rank 6")[1] == 7001)
check("done challenge: the check", find("Explorer")[1] == "Interface\\RaidFrame\\ReadyCheck-Ready")

faction = "Horde"
env.GetTime = function() return 1000 end -- a fresh read
rows = api.guideLegacyRows()
check("Horde: Rank 6 is Stone Guard", find("Rank 6")[2]:find("Stone Guard", 1, true) ~= nil)
check("Horde: Grand Marshal is High Warlord", find("Grand Marshal")[2]:find("High Warlord", 1, true) ~= nil)

-- folding: open by default, a click closes one, Open all / Close all
env.GetTime = function() return 2000 end
rows = api.guideLegacyRows()
check("open by default", rows[1].header and rows[1].fold == false and find("Rank 6") ~= nil and find("Explorer") ~= nil)
check("an open row says click to close", rows[1].clickHint == "Click: close")
local refreshed = 0
local pages, buttons = {}, {}
local kit = { page = function(key) pages[#pages + 1] = key end, heading = function() end, check = function() end,
	help = function() end, note = function() end, custom = function() end,
	buttons = function(label, list) buttons[label] = list end,
	pageByKey = setmetatable({}, { __index = function(t, k) local p = {}; rawset(t, k, p) return p end }),
	refresh = function() refreshed = refreshed + 1 end }
api.declareGuidePages(kit)
rows[1].onClick()
rows = api.guideLegacyRows()
check("a click closes that one only, and lays out again", refreshed == 1 and rows[1].fold == true and not find("Rank 6")
	and find("Explorer") ~= nil)
rows[1].onClick()
rows = api.guideLegacyRows()
check("a second click opens it", rows[1].fold == false and find("Rank 6") ~= nil)
local ob
for label, list in pairs(buttons) do if label:find("Open all", 1, true) then ob = list end end
check("Open all and Close all buttons", ob and ob[1][1] == "Open all" and ob[2][1] == "Close all")
ob[2][2]()
rows = api.guideLegacyRows()
check("Close all closes them", #rows == 2 and rows[1].fold == true)
ob[1][2]()
rows = api.guideLegacyRows()
check("Open all opens every category", find("Rank 6") ~= nil and find("Explorer") ~= nil)

print(pass and "ALL OK" or "SOME FAILED")
