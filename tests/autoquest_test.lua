-- 3.1.1: quest automation (Tracker/AutoQuest.lua): accept, turn in, skip the chat, and what it leaves alone
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local calls = {}
local function log(name) return function(...) calls[#calls + 1] = { name, ... } end end
local shift, instance = false, false
local gossip = { active = {}, available = {}, options = {} }
local quest = { id = 0, completable = true, choices = 0, money = 0, autoAccept = false }
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
	GetTime = function() return 100 end,
	IsShiftKeyDown = function() return shift end,
	IsInInstance = function() return instance, instance and "party" or "none" end,
	C_GossipInfo = {
		GetActiveQuests = function() return gossip.active end, GetAvailableQuests = function() return gossip.available end,
		GetOptions = function() return gossip.options end,
		SelectActiveQuest = log("SelectActiveQuest"), SelectAvailableQuest = log("SelectAvailableQuest"),
		SelectOption = log("SelectOption"),
	},
	GetQuestID = function() return quest.id end,
	QuestGetAutoAccept = function() return quest.autoAccept end,
	AcceptQuest = log("AcceptQuest"), AcknowledgeAutoAcceptQuest = log("AcknowledgeAutoAcceptQuest"),
	IsQuestCompletable = function() return quest.completable end, CompleteQuest = log("CompleteQuest"),
	GetQuestMoneyToGet = function() return quest.money end,
	GetNumQuestChoices = function() return quest.choices end, GetQuestReward = log("GetQuestReward"),
	GetNumActiveQuests = function() return 1 end, GetActiveTitle = function() return "Done one", true end,
	GetActiveQuestID = function() return 77 end, SelectActiveQuest = log("greet:SelectActiveQuest"),
	GetNumAvailableQuests = function() return 1 end,
	GetAvailableQuestInfo = function() return false, 0, false, false, 78 end,
	SelectAvailableQuest = log("greet:SelectAvailableQuest"),
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/AutoQuest.lua", "t", env))("RXPForeverTracker", { tracker = ns })
local api = ns.api
for _, fn in ipairs(ns.onLogin) do fn() end
local H = api.autoQuestHandlers
local function last() return calls[#calls] and calls[#calls][1] end
local function reset() calls = {} end

-- all off by default
gossip.active = { { questID = 1, isComplete = true } }
gossip.available = { { questID = 2 } }
check("off by default: nothing happens", H.GOSSIP_SHOW() == nil and #calls == 0)
check("off by default: quest window untouched", H.QUEST_DETAIL() == nil and H.QUEST_COMPLETE() == nil and #calls == 0)

ns.db.autoAccept, ns.db.autoTurnIn, ns.db.autoGossip = true, true, true
-- gossip: turn in first, then accept
check("gossip: a finished quest is turned in first", H.GOSSIP_SHOW() == "turnin" and last() == "SelectActiveQuest" and calls[1][2] == 1)
gossip.active = {}
reset()
check("gossip: then a new quest is opened", H.GOSSIP_SHOW() == "accept" and last() == "SelectAvailableQuest" and calls[1][2] == 2)
-- grey, repeatable
gossip.available = { { questID = 3, isTrivial = true }, { questID = 4, repeatable = true }, { questID = 5, frequency = 1 } }
reset()
check("grey, repeatable and daily quests are left alone", H.GOSSIP_SHOW() == nil and #calls == 0)
ns.db.autoTrivial = true
check("grey on: the grey quest is taken", H.GOSSIP_SHOW() == "accept" and calls[1][2] == 3)
ns.db.autoTrivial = false
-- a repeatable quest's turn-in window is left alone
quest.id = 4
reset()
check("repeatable turn-in left to you", H.QUEST_PROGRESS() == nil and H.QUEST_COMPLETE() == nil and #calls == 0)
quest.id = 9
-- Shift and dungeons
gossip.available = { { questID = 6 } }
shift = true; reset()
check("Shift held: nothing", H.GOSSIP_SHOW() == nil and H.QUEST_DETAIL() == nil and #calls == 0)
shift = false; instance = true; reset()
check("in a dungeon: nothing", H.GOSSIP_SHOW() == nil and #calls == 0)
ns.db.autoInDungeon = true
check("dungeon switch on: works", H.GOSSIP_SHOW() == "accept")
instance = false
-- quest window
reset()
check("detail: accepted", H.QUEST_DETAIL() == "accepted" and last() == "AcceptQuest")
quest.autoAccept = true; reset()
H.QUEST_DETAIL()
check("detail: an auto-accept quest is acknowledged", last() == "AcknowledgeAutoAcceptQuest")
reset()
check("progress: completed", H.QUEST_PROGRESS() == "completed" and last() == "CompleteQuest")
quest.money = 500; reset()
check("progress: a turn-in that costs money is left to you", H.QUEST_PROGRESS() == nil and #calls == 0)
quest.money = 0
quest.choices = 1; reset()
check("one reward: taken", H.QUEST_COMPLETE() == "rewarded" and last() == "GetQuestReward" and calls[1][2] == 1)
quest.choices = 3; reset()
check("a reward choice: yours to pick", H.QUEST_COMPLETE() == "choose" and #calls == 0)
-- greeting window
reset()
check("greeting: turn in", H.QUEST_GREETING() == "turnin" and last() == "greet:SelectActiveQuest")
-- the chat
gossip.active, gossip.available = {}, {}
gossip.options = { { gossipOptionID = 50, icon = 132053, status = 0 } }
reset()
check("one chat option: picked", H.GOSSIP_SHOW() == "chat" and last() == "SelectOption" and calls[1][2] == 50)
reset()
check("the same option again at once: not picked (no loop)", H.GOSSIP_SHOW() == nil and #calls == 0)
gossip.options = { { gossipOptionID = 51, icon = 132060, status = 0 } }
reset()
check("a vendor option: never picked", H.GOSSIP_SHOW() == nil and #calls == 0)
gossip.options = { { gossipOptionID = 52, icon = 132053 }, { gossipOptionID = 53, icon = 132053 } }
reset()
check("two options: left to you", H.GOSSIP_SHOW() == nil and #calls == 0)

-- the page
local pages, checks = {}, 0
local kit = { page = function(key) pages[#pages + 1] = key end, heading = function() end, note = function() end,
	check = function() checks = checks + 1 end, help = function() end,
	pageByKey = setmetatable({}, { __index = function(t, k) local p = {}; rawset(t, k, p) return p end }) }
api.declareAutoQuestPage(kit)
check("page declared with six switches", pages[1] == "automation" and checks == 6)

print(pass and "ALL OK" or "SOME FAILED")
