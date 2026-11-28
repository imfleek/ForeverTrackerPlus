-- 3.2 (user): the big quest item button (Tracker/QuestAction.lua).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function frame(name)
	local f = { name = name, shown = false, scripts = {}, points = {}, attrs = {}, alpha = 1 }
	local methods = {
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		CreateTexture = function() return frame("tex") end, CreateFontString = function() return frame("text") end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		GetPoint = function(self) local p = self.points[1]; if p then return p[1], p[2], p[3], p[4], p[5] end end,
		ClearAllPoints = function(self) self.points = {} end,
		SetAttribute = function(self, k, v) self.attrs[k] = v end,
		SetAlpha = function(self, a) self.alpha = a end, GetAlpha = function(self) return self.alpha end,
		SetText = function(self, t) self.text = t end, SetTexture = function(self, t) self.texture = t end,
		StartMoving = function(self) self.moved = true end,
	}
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

local made = {}
local api = {}
local ns = { api = api, onLogin = {}, db = {} }
local combat, taxi, dist = false, false, {}
local quests = { 11, 22 }
local items = { [11] = { itemID = 500, link = "item:500", icon = "icon500" }, [22] = { itemID = 600, link = "item:600" } }
api.ownQuestIDs = function() return quests end
api.questItemFor = function(id) return items[id] end
api.playerWorldPos = function() return { continent = 1, x = 0, y = 0 } end
api.questDirection = function(id) return dist[id] end
local ticker, binding
local env = setmetatable({
	CreateFrame = function(kind, name) local f = frame(name); if name then made[name] = f end; return f end,
	C_Timer = { After = function() end, NewTicker = function(_, fn) ticker = fn end },
	C_QuestLog = { IsComplete = function() return false end, GetTitleForQuestID = function(id) return "Quest " .. id end },
	C_Item = { GetItemCount = function() return 1 end },
	InCombatLockdown = function() return combat end,
	UnitOnTaxi = function() return taxi end,
	IsControlKeyDown = function() return true end,
	UIParent = frame("UIParent"),
	GameTooltip = frame("tip"),
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/QuestAction.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
ns.onLogin[1]()
local name = "ForeverTrackerPlusQuestAction"
check("the binding has a name", env["BINDING_NAME_CLICK " .. name .. ":LeftButton"] == "Use the nearby quest item")
check("a 0.5 s timer", type(ticker) == "function")

-- far from both: nothing
dist[11], dist[22] = 400, 250
ticker()
check("far away: no button", made[name] == nil or not made[name].shown)
-- near quest 22 (the closest): its item
dist[22] = 60
ticker()
local b = made[name]
check("near: the button shows", b and b.shown)
check("with the closest quest's item", b and b.attrs.item == "item:600" and b.attrs.type == "item")
check("Ctrl+right-click does not use the item", b and b.attrs["ctrl-type2"] == "rxpftnone")
check("bottom middle by default", b and b.points[1][1] == "BOTTOM" and b.points[1][3] == "BOTTOM")
check("count top-left", b and b.count.text == "1")
-- the closer quest wins
dist[11] = 30
ticker()
check("a closer quest's item takes over", b.attrs.item == "item:500" and b.icon.texture == "icon500")
-- range setting
ns.db.questActionRange = 30
dist[11] = 35
ticker()
check("out of the set range: hidden", not b.shown)
ns.db.questActionRange = nil
ticker()
check("back in range: shown", b.shown)
-- combat: no change to the secure button, opacity 0 when it is no longer wanted
combat = true
dist[11], dist[22] = 400, 400
ticker()
check("combat: not hidden (secure), opacity 0", b.shown and b.alpha == 0)
combat = false
b.scripts.OnEvent = nil
api.refreshQuestAction()
check("after combat: hidden", not b.shown)
-- a flight path
dist[11] = 30
taxi = true
api.refreshQuestAction()
check("on a flight path: hidden", not b.shown)
taxi = false
api.refreshQuestAction()
check("off the flight path: shown", b.shown and b.alpha == 1)
-- complete quests and quests without items are skipped
env.C_QuestLog.IsComplete = function(id) return id == 11 end
api.questActionDirty()
api.refreshQuestAction()
check("a complete quest is skipped (the other one is far)", not b.shown)
env.C_QuestLog.IsComplete = function() return false end
api.questActionDirty()
-- moving: Ctrl+right-drag, the place is saved
b.points = { { "BOTTOM", env.UIParent, "BOTTOM", 12.4, 300.6 } }
b.scripts.OnDragStart(b)
b.scripts.OnDragStop(b)
check("Ctrl+drag moves it", b.moved == true)
check("the place is saved", ns.db.questActionPos and ns.db.questActionPos[3] == 12 and ns.db.questActionPos[4] == 301)
combat = true
b.moved = nil
b.scripts.OnDragStart(b)
check("no move in combat", rawget(b, "moved") == nil)
combat = false
api.resetQuestAction()
check("reset: back to the bottom middle", ns.db.questActionPos == nil and b.points[1][5] == 290)
-- the setting off
ns.db.questAction = false
ticker()
check("setting off: hidden", not b.shown)
ns.db.questAction = nil
-- the animation switch exists
local anim = io.open(dir .. "/Tracker/Animations.lua"):read("a")
check("animKinds row questaction", anim:find('key = "questaction"', 1, true) ~= nil)
local toc = io.open(dir .. "/ForeverTrackerPlus.toc"):read("a")
check("in the toc", toc:find("Tracker/QuestAction.lua", 1, true) ~= nil)
local bind = io.open(dir .. "/Bindings.xml"):read("a")
check("in Bindings.xml", bind:find("CLICK ForeverTrackerPlusQuestAction:LeftButton", 1, true) ~= nil)
print(pass and "PASS" or "SOME FAILED")
