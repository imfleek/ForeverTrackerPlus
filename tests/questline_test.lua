-- 3.1: the Questline ideas. Questing.lua (quest item bar, progress toasts, party chat), WorldMarker.lua (nearest quest
-- by itself), Guides.lua (Legacy Challenges, books, sleeping bag), Questie.lua (breadcrumbs, the guide data scan),
-- and the settings pages they declare
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

-- a frame mock: every method is a no-op, except what the files read back
local handlers, named = {}, {}
local function obj()
	local o = { attrs = {}, shown = false }
	return setmetatable(o, { __index = function(t, k)
		if k == "SetScript" then return function(self, what, fn) self[what] = fn; if what == "OnEvent" then handlers[#handlers + 1] = fn end end end
		if k == "SetAttribute" then return function(self, a, v) self.attrs[a] = v end end
		if k == "SetText" then return function(self, v) self.text = v end end
		if k == "Show" then return function(self) self.shown = true end end
		if k == "Hide" then return function(self) self.shown = false end end
		if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
		if k == "IsShown" then return function(self) return self.shown end end
		if k == "GetPoint" then return function() return "BOTTOM", nil, "BOTTOM", 0, 230 end end
		if k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then
			return function() return obj() end
		end
		return function() end
	end })
end
local combat = false
local clock = 100
local afters = {}
local sent = {}
local superTracked, setTo = 0, nil
local log = {
	{ id = 101, title = "Wolf Hunt", boards = { { "Wolves slain: 2/8", "monster", false } }, complete = false,
		item = "|cffffffff|Hitem:5555::::|h[Wolf Bait]|h|r", dist = 900 },
	{ id = 102, title = "Bear Trouble", boards = { { "Bears slain: 0/5", "monster", false } }, complete = false, dist = 100 },
}
local ns = { api = {}, onLogin = {}, db = {} }
local uiErrors = { registered = true, got = {} }
uiErrors.UnregisterEvent = function(self) self.registered = false end
uiErrors.RegisterEvent = function(self) self.registered = true end
uiErrors.IsEventRegistered = function(self) return self.registered end
uiErrors.GetScript = function() return function(_, _, _, msg) uiErrors.got[#uiErrors.got + 1] = msg end end
local env = setmetatable({
	CreateFrame = function(_, name) local o = obj(); if name then named[name] = o end return o end,
	GetTime = function() return clock end,
	C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) afters[#afters + 1] = fn end },
	InCombatLockdown = function() return combat end,
	C_QuestLog = {
		GetNumQuestLogEntries = function() return #log end,
		GetInfo = function(i) local q = log[i] return q and { questID = q.id, title = q.title, isHeader = false } end,
		IsComplete = function(id) for _, q in ipairs(log) do if q.id == id then return q.complete end end return false end,
		GetLogIndexForQuestID = function(id) for i, q in ipairs(log) do if q.id == id then return i end end return nil end,
		GetTitleForQuestID = function(id) for _, q in ipairs(log) do if q.id == id then return q.title end end end,
		GetDistanceSqToQuest = function(id) for _, q in ipairs(log) do if q.id == id then return q.dist, true end end end,
		IsQuestFlaggedCompleted = function(id) return id == 900 end,
	},
	GetNumQuestLeaderBoards = function(i) return #log[i].boards end,
	GetQuestLogLeaderBoard = function(j, i) local b = log[i].boards[j] return b[1], b[2], b[3] end,
	GetQuestLogSpecialItemInfo = function(i) local q = log[i] if q.item then return q.item, 134400, 1, false end end,
	C_SuperTrack = { GetSuperTrackedQuestID = function() return superTracked end,
		SetSuperTrackedQuestID = function(id) setTo = id; superTracked = id end,
		IsSuperTrackingUserWaypoint = function() return false end },
	C_Navigation = { GetFrame = function() return nil end },
	IsInGroup = function() return true end, IsInRaid = function() return false end,
	SendChatMessage = function(text, chan) sent[#sent + 1] = { text, chan } end,
	DEFAULT_CHAT_FRAME = { AddMessage = function() end },
	UIParent = obj(), GameTooltip = obj(), C_Item = { GetItemCount = function() return 1 end },
	IsShiftKeyDown = function() return false end,
	GetCategoryList = function() return { 1, 2 } end,
	GetCategoryInfo = function(c) return c == 1 and "Dungeon Explorer" or "Other" end,
	GetCategoryNumAchievements = function(c) return c == 1 and 3 or 1 end,
	GetAchievementInfo = function(c, i)
		if c == 1 then
			if i == 1 then return 11, "Explore Deadmines", 10, false, nil, nil, nil, "Enter it", 0x8000000 end
			if i == 2 then return 12, "Explore Wailing Caverns", 10, true, nil, nil, nil, "", 0x8000000 + 2 end
			return 13, "Not legacy", 10, false, nil, nil, nil, "", 2
		end
		return 21, "Normal one", 10, false, nil, nil, nil, "", 0
	end,
	GetAchievementNumCriteria = function(id) return id == 11 and 2 or 0 end,
	GetAchievementCriteriaInfo = function(_, k) if k == 1 then return "Entrance", 0, true else return "Boss room", 0, false end end,
	hooksecurefunc = function() end,
	UIErrorsFrame = uiErrors,
}, { __index = _G })
env._G = env
local root = { tracker = ns }
for _, f in ipairs({ "Questing", "WorldMarker", "Guides" }) do
	assert(loadfile(dir .. "/Tracker/" .. f .. ".lua", "t", env))("ForeverTrackerPlus", root)
end
local api = ns.api
for _, fn in ipairs(ns.onLogin) do fn() end
local function flush() local list = afters; afters = {}; for _, fn in ipairs(list) do fn() end end
local function fire(e, ...) for _, h in ipairs(handlers) do h(nil, e, ...) end end
flush() -- the first scan and the bar

-- the quest item bar
local b1, key = named.RXPFTQuestItem1, named.RXPFTQuestItemKey
check("item bar: a button for the quest item", b1 and b1.attrs.item == "item:5555" and b1.shown)
check("item bar: the key uses the first item", key and key.attrs.item == "item:5555")
check("item bar: second button hidden", named.RXPFTQuestItem2 and not named.RXPFTQuestItem2.shown)
combat = true
log[1].item = nil
fire("QUEST_LOG_UPDATE")
check("item bar: no change in combat", b1.attrs.item == "item:5555")
combat = false
fire("PLAYER_REGEN_ENABLED")
check("item bar: changed after combat", b1.attrs.item == nil and not b1.shown)

-- progress toasts and party chat
ns.db.partyDone = true
log[1].boards[1][1] = "Wolves slain: 3/8"
fire("QUEST_LOG_UPDATE"); flush()
check("no party line for a step (off by default)", #sent == 0)
log[1].boards[1] = { "Wolves slain: 8/8", "monster", true }
log[1].complete = true
fire("QUEST_LOG_UPDATE"); flush()
check("party line when a quest is done", sent[1] and sent[1][1] == "[RXPFT] Wolf Hunt is ready to turn in" and sent[1][2] == "PARTY")
-- the tooltip's party progress (db.partyProgress) is its own switch: on, it must not turn the chat lines on
ns.db.partyProgress = true
log[2].boards[1][1] = "Bears slain: 1/5"
clock = clock + 5
fire("QUEST_LOG_UPDATE"); flush()
check("tooltip party switch leaves chat steps off", #sent == 1)
ns.db.partyChatSteps = true
log[2].boards[1][1] = "Bears slain: 2/5"
clock = clock + 5
fire("QUEST_LOG_UPDATE"); flush()
check("party line for a step when on", sent[2] and sent[2][1] == "[RXPFT] Bear Trouble: Bears slain: 2/5")

-- the game's yellow progress line
check("progress line recognised", api.isQuestProgressMessage("Verdant Leaves: 11/12"))
check("kill line recognised", api.isQuestProgressMessage("Wolf slain: 3/8"))
check("other info message kept", not api.isQuestProgressMessage("You are too far away."))
check("game's info event taken over", uiErrors.registered == false)
uiErrors.got = {}
fire("UI_INFO_MESSAGE", 0, "Verdant Leaves: 11/12")
fire("UI_INFO_MESSAGE", 0, "You are too far away.")
check("only the other message reaches the game's frame", #uiErrors.got == 1 and uiErrors.got[1] == "You are too far away.")
ns.db.toastsHideGame = false
api.applyToastsHideGame()
check("switch off: the event goes back to the game", uiErrors.registered == true)

-- the nearest quest by itself
api.markerAutoPick()
check("auto pick off by default", setTo == nil)
ns.db.markerAuto = true
api.markerAutoPick()
check("auto pick: the nearest quest", setTo == 102)
superTracked = 101; setTo = nil
api.markerAutoPick()
check("auto pick keeps a quest you picked yourself", setTo == nil)

-- Legacy Challenges
local rows = api.guideLegacyRows()
check("legacy: category header", rows[1] and rows[1].header and rows[1][2] == "Dungeon Explorer" and rows[1][3] == "1 of 2 done")
check("legacy: open challenge with criteria count", rows[2] and rows[2][2] == "Explore Deadmines" and rows[2][3] == "1 / 2")
check("legacy: open criteria in the tooltip", rows[2] and table.concat(rows[2].tip, "|"):find("Boss room", 1, true) ~= nil)
check("legacy: done and non-legacy left out", #rows == 2)
ns.db.legacyShowDone = true
ns.api.guideLegacyRows() -- cached for 10 s, the switch resets it in the page; here the cache still holds
check("books: without Questie says so", api.guideBookRows()[1][2] == "Needs Questie.")

-- the pages
local pages = {}
local kit = { page = function(key) pages[#pages + 1] = key end, heading = function() end, check = function() end,
	help = function() end, note = function() end, buttons = function() end, custom = function() end,
	pageByKey = setmetatable({}, { __index = function(t, k) local p = {}; rawset(t, k, p) return p end }), refresh = function() end }
api.declareScreenPage(kit)
api.declareGuidePages(kit)
local all = table.concat(pages, ",")
check("pages declared", all == "onscreen,legacy,books,bedroll")

-- Questie.lua: breadcrumbs
local qfields = { [500] = { breadcrumbForQuestId = 900 }, [501] = { breadcrumbForQuestId = 901 }, [502] = {} }
local qenv = setmetatable({
	QuestieLoader = { ImportModule = function(_, name)
		if name == "QuestieDB" then return { QueryQuestSingle = function(id, f) return qfields[id] and qfields[id][f] end } end
	end },
	LibQuestieDB = false,
	C_AddOns = { IsAddOnLoaded = function() return true end },
	Questie = { API = { isReady = true } },
	C_QuestLog = { IsQuestFlaggedCompleted = function(id) return id == 900 end, GetLogIndexForQuestID = function() return nil end },
	C_Timer = env.C_Timer, CreateFrame = env.CreateFrame, hooksecurefunc = function() end,
}, { __index = _G })
qenv._G = qenv
local qns = { api = {}, onLogin = {}, db = {} }
local okQ, errQ = pcall(function() assert(loadfile(dir .. "/Tracker/Questie.lua", "t", qenv))("ForeverTrackerPlus", { tracker = qns }) end)
check("Questie.lua loads", okQ or print(errQ))
if okQ then
	check("breadcrumb: its quest done -> hidden", qns.api.questieBreadcrumbDone(500) == true)
	check("breadcrumb: its quest open -> shown", qns.api.questieBreadcrumbDone(501) == false)
	check("not a breadcrumb -> shown", qns.api.questieBreadcrumbDone(502) == false)
	qns.db.breadcrumbHide = false
	check("breadcrumb switch off -> shown", qns.api.questieBreadcrumbDone(500) == false)
end

print(pass and "ALL OK" or "SOME FAILED")
