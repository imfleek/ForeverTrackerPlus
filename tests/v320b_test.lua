-- 3.2 (second round): What's new window, NPC automation split, time groups, Legacy class filter, books, secrets,
-- tooltips on settings, sidebar order and icons. Run from tests/: texlua v320b_test.lua ..
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c and true or false end
local function read(path) local f = assert(io.open(dir .. "/" .. path, "rb")); local s = f:read("*a"); f:close(); return s end

---------------------------------------------------------------------------------------------------------------------
-- WhatsNew.lua: due once after an update, not on a fresh install, not when turned off
---------------------------------------------------------------------------------------------------------------------
local ver = "3.2"
local function loadNews(db)
	local ns = { api = { addSlash = function() end }, onLogin = {}, db = db }
	local env = setmetatable({ C_AddOns = { GetAddOnMetadata = function() return ver end },
		C_Timer = { After = function() end }, DEFAULT_CHAT_FRAME = { AddMessage = function() end } }, { __index = _G })
	env._G = env
	assert(loadfile(dir .. "/Tracker/WhatsNew.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	for _, fn in ipairs(ns.onLogin) do fn() end
	return ns.api
end
do
	local db = {}
	local api = loadNews(db)
	check("news: a fresh install is not due, and is marked seen", api.whatsNewDue() == false and db.whatsNewSeen == "3.2")
	db = { setupDone = 4 }
	api = loadNews(db)
	check("news: an update (setup done before, not seen) is due", api.whatsNewDue() == true)
	db.whatsNewSeen = "3.2"
	check("news: seen this version: not due", api.whatsNewDue() == false)
	db = { setupDone = 4, whatsNewSeen = "3.1.2", whatsNewOff = true }
	api = loadNews(db)
	check("news: turned off: not due, marked seen", api.whatsNewDue() == false and db.whatsNewSeen == "3.2")
	check("news: notes for 3.2 and 3.2.1", api.whatsNewNotes("3.2") ~= nil and api.whatsNewNotes("3.2.1") ~= nil)
	local src = read("Tracker/WhatsNew.lua")
	check("news: Ok and Do not show me changes in future buttons",
		src:find('"Ok"', 1, true) ~= nil and src:find('"Do not show me changes in future"', 1, true) ~= nil)
	check("news: in the toc after Setup.lua", read("ForeverTrackerPlus.toc"):find("Tracker/Setup.lua%s+Tracker/WhatsNew.lua") ~= nil)
	local prof = read("Tracker/Profiles.lua")
	check("news: not in profiles", prof:find("whatsNewSeen = true", 1, true) ~= nil and prof:find("whatsNewOff = true", 1, true) ~= nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Source wiring
---------------------------------------------------------------------------------------------------------------------
local config, stats, guides = read("Tracker/Config.lua"), read("Tracker/Stats.lua"), read("Tracker/Guides.lua")
local arrowAt, orphansAt = config:find('{ key = "arrow"', 1, true), config:find('{ key = "orphans"', 1, true)
check("sidebar: Orphaned quests after Arrow", arrowAt and orphansAt and orphansAt > arrowAt)
check("sidebar: the arrow is RxpArrow, orphans the journal's atlas",
	config:find("Textures\\\\RxpArrow", 1, true) ~= nil and config:find('atlas = "UI-HUD-MicroMenu-AdventureGuide-Up"', 1, true) ~= nil)
local tga = io.open(dir .. "/Textures/RxpArrow.tga", "rb")
check("texture: Textures/RxpArrow.tga is there", tga ~= nil)
if tga then tga:close() end
check("settings: hover tooltips on every row", config:find("local function rowHover", 1, true) ~= nil)
check("lists: tooltip title is the row's text", guides:find("tostring(d[2] or d.text", 1, true) ~= nil)
check("overview: no quests per hour", not stats:find('"Quests per hour"', 1, true))
check("run analysis: raids and battlegrounds tiles", stats:find('"In raids"', 1, true) ~= nil and stats:find('"In battlegrounds"', 1, true) ~= nil)
check("run analysis: 12 tiles fit (was 6, the 7th was cut)", stats:find("tiles(runTiles, 12)", 1, true) ~= nil)
check("discord: the surname through playerName", stats:find('local who, level = api.playerName and api.playerName()', 1, true) ~= nil)
check("time groups: every state in one group", (function()
	local seen = {}
	local block = stats:match("local TIME_GROUPS = (%b{})")
	for kind in block:gmatch('"(%l+)"') do seen[kind] = (seen[kind] or 0) + 1 end
	for _, k in ipairs({ "combat", "walk", "mount", "swim", "jump", "fall", "craft", "eat", "loot", "cast", "flight", "npc",
		"map", "load", "dead", "afk", "idle" }) do
		if seen[k] ~= 1 then return false end
	end
	return true
end)())
local awake = read("Objectives/features/RxpAwake.lua")
check("rxp awake: our automation is always blocked, the rest follows the setting",
	awake:find("local function oursBlocked", 1, true) ~= nil and awake:find("local function automationBlocked", 1, true) ~= nil)

---------------------------------------------------------------------------------------------------------------------
-- Guides.lua: class names in a text
---------------------------------------------------------------------------------------------------------------------
do
	local body = guides:match("(local CLASS_TOKENS.-\napi%.guideClassesIn = classesIn)") or guides:match("(local CLASS_TOKENS.-\r\napi%.guideClassesIn = classesIn)")
	check("legacy: class finder found", body ~= nil)
	if body then
		local api = {}
		local env = setmetatable({ api = api, isSecret = function() return false end }, { __index = _G })
		env._G = env
		assert((loadstring or load)(body, "classes", "t", env))()
		local function has(text, token) local s = {}; api.guideClassesIn(text, s); return s[token] == true end
		check("legacy: 'Complete the Mage quest' names Mage", has("Complete the Mage quest", "MAGE"))
		check("legacy: 'Warlocks' names Warlock", has("For Warlocks only", "WARLOCK"))
		check("legacy: 'image' is no Mage", not has("An image of the past", "MAGE"))
		check("legacy: 'Druids of the Fang' are no class", not has("Slay the Druids of the Fang", "DRUID"))
		check("legacy: 'bounty hunter' is no Hunter", not has("Become a bounty hunter", "HUNTER"))
		check("legacy: 'Death Knight' named", has("A Death Knight's task", "DEATHKNIGHT"))
	end
	check("legacy: other classes hidden with only-mine, also when done", guides:find("if a.otherClass then return false end", 1, true) ~= nil)
	check("legacy: search, progress, category and sort filters",
		guides:find("db.legacySearch", 1, true) and guides:find("db.legacyProgress", 1, true)
		and guides:find("db.legacyCategory", 1, true) and guides:find("db.legacySort", 1, true) and true or false)
	check("books: not in the game only for the listed books", guides:find("local BOOKS_NOT_IN_GAME = {", 1, true) ~= nil
		and not guides:find("questieHidden", 1, true))
	check("secrets: other faction switch, folds and splitters", guides:find("db.secretsOtherFaction", 1, true)
		and guides:find("db.secretsClosed", 1, true) and guides:find("split = not first", 1, true) and true or false)
	-- user: "attempt to index local 'states' (a nil value)" with other-faction secrets hidden
	check("secrets: hidden other-faction secrets: the step count does not read their (nil) states",
		guides:find('if states and states[i] == "done"', 1, true) ~= nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Battleground taint fix: nothing of ours makes Blizzard's tracker lay out (3.2: the old tracker's code was removed)
---------------------------------------------------------------------------------------------------------------------
do
	local count, where = 0, {}
	for _, f in ipairs({ "Core", "Extras", "ZoneSort", "Fonts", "Stats", "Guides", "Questing", "Dungeon", "DungeonPlus",
		"Chains", "Reminders", "Config", "QuestClicks", "Prereqs", "Party", "Questie" }) do
		local src = read("Tracker/" .. f .. ".lua")
		for line in src:gmatch("[^\n]+") do
			if line:find("securecallfunction", 1, true) and not line:match("^%s*%-%-") then count = count + 1; where[#where + 1] = f end
		end
	end
	check("taint: no MarkDirty / Update calls on Blizzard's tracker (" .. table.concat(where, ",") .. ")", count == 0)
	local core = read("Tracker/Core.lua")
	local body = core:match("(local function secretWorld%(%).-\nns%.api%.trackerSecretWorld = secretWorld)")
		or core:match("(local function secretWorld%(%).-\r\nns%.api%.trackerSecretWorld = secretWorld)")
	check("taint: secretWorld found", body ~= nil)
	if body then
		local inside, kind = false, "none"
		local env = setmetatable({ IsInInstance = function() return inside, kind end, ns = { api = {} } }, { __index = _G })
		env._G = env
		local fn = assert((loadstring or load)(body .. "\nreturn secretWorld", "sw", "t", env))()
		check("taint: open world is safe", fn() == false)
		inside, kind = true, "pvp"
		check("taint: a battleground is not", fn() == true)
		kind = "arena"
		check("taint: an arena is not", fn() == true)
		kind = "party"
		check("taint: a dungeon is", fn() == false)
		kind = "raid"
		check("taint: a raid is", fn() == false)
	end
end

-- 3.2 (user: "Delete the old tracker's code"): no step aside and no battleground reload left
do
	local core = read("Tracker/Core.lua")
	check("no step aside left", not core:find("stepAside", 1, true) and not core:find("moveTracker", 1, true))
	check("no battleground reload left", not core:find("AcceptBattlefieldPort", 1, true)
		and not read("Tracker/Config.lua"):find('"Reload when entering a battleground"', 1, true))
end

-- RestedXP 4.11.40 renamed its item bar (activeItemFrame -> activeItemWindow)
do
	local uses = read("Objectives/rxp/Uses.lua")
	check("rxp 4.11.40: item bar read as activeItemWindow or activeItemFrame",
		uses:find("RXP.activeItemWindow or RXP.activeItemFrame", 1, true) ~= nil
		and not uses:find("RXP.activeItemFrame.buttonList", 1, true))
end

-- a RestedXP timer bar with no start (user: error on taking a flight, Pin.lua:256 'start' nil)
do
	local src = read("Objectives/rxp/Readers.lua")
	local body = src:match("(function ns%.activeTimer%(%).-\nend)") or src:match("(function ns%.activeTimer%(%).-\r\nend)")
	check("timer: activeTimer found", body ~= nil)
	if body then
		local ns = { timerBars = function() return { Flight = { running = true, exp = 150 } } end }
		local on = false
		local flightBar = { running = true, exp = 150 }
		ns.timerBars = function() return { Flight = flightBar, Step = { running = true, start = 90, exp = 120 } } end
		local env = setmetatable({ ns = ns, GetTime = function() return 100 end, RXP = { flightInfo = { flightBar = flightBar } },
			root = { tracker = { api = { flightTrackerOn = function() return on end } } } }, { __index = _G })
		assert((loadstring or load)(body, "timer", "t", env))()
		local label, start, expires = ns.activeTimer()
		check("timer: no start -> now", label == "Flight" and start == 100 and expires == 150)
		on = true
		label = ns.activeTimer()
		check("clock ring: our flight tracker on -> RestedXP's flight bar left out, other timers stay", label == "Step")
	end
end

print(pass and "ALL PASS" or "SOME FAILED")
