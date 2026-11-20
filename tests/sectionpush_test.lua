-- Tracked profession recipes (and every section after the quests) go below every quest: Core.lua
-- pushSectionsAfterQuests moves the first section after the quests down by how far the quest entries (or More quests)
-- reach below the quests section's frame (Blizzard anchors that section to the frame's bottom).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local src = io.open(dir .. "/Tracker/Core.lua"):read("a")
local body = src:match("(local function pushSectionsAfterQuests%(%).-\nend\n)")
check("pushSectionsAfterQuests found in Tracker/Core.lua", body ~= nil)

local function module(bottom, shown)
	return { bottom = bottom, shown = shown ~= false, GetBottom = function(self) return self.bottom end,
		IsCollapsed = function(self) return self.collapsed end }
end
local quests, professions, scenario = module(400), module(300), module(600)
local contentBottom = 340 -- the last quest entry ends 60 below the quests frame
local moreBottom
local pushedTo, pushedPx = "unset", nil
local env = setmetatable({
	tracker = { modules = { scenario, quests, professions } },
	moduleVisible = function(m) return m.shown end,
	moduleContentBottom = function(m) return m == quests and contentBottom or nil end,
	toScreen = function(_, v) return v end,
	ns = { api = { moreQuestsBottom = function() return moreBottom end,
		pushBelowMoreQuests = function(m, px) pushedTo, pushedPx = m, px end } },
}, { __index = _G })
_G.QuestObjectiveTracker = quests
local push = load(body .. "\nreturn pushSectionsAfterQuests", "core", "t", env)()

push()
check("the Profession section goes below the last quest entry", pushedTo == professions and pushedPx == 60)
moreBottom = 150
push()
check("and below More quests when it shows", pushedTo == professions and pushedPx == 250)
moreBottom = nil
contentBottom = 420 -- entries inside the frame: nothing to move
push()
check("quests within their frame: not moved", pushedTo == professions and pushedPx == 0)
contentBottom = 340
professions.shown = false
push()
check("no section after the quests: nothing moved", pushedTo == nil)
professions.shown = true
quests.collapsed = true
push()
check("Quests folded: nothing moved", pushedTo == nil)
quests.collapsed = nil
quests.shown = false
push()
check("no quests shown: nothing moved", pushedTo == nil)
quests.shown = true
check("runs on every tracker layout pass, after More quests",
	src:find("if ns.api.layoutMoreQuests then pcall(ns.api.layoutMoreQuests) end\n\tpushSectionsAfterQuests()", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
