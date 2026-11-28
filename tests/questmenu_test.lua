-- R106-85: "Wowhead URL" in the quest tracker's right-click menu, and its copy box
-- R106-86: "Expand current zone only"
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local all = {}
local function frame(name)
	local f = { name = name, scripts = {}, shown = true }
	local methods = {
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end,
		IsShown = function(self) return self.shown end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		HighlightText = function(self) self.highlighted = true end,
		SetFocus = function(self) self.focused = true end, ClearFocus = function(self) self.focused = false end,
		CreateFontString = function() return frame("text") end,
	}
	all[#all + 1] = f
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

local menuHandler
local ns = { api = {}, onLogin = {}, db = {} }
local now = 100
local env = setmetatable({
	CreateFrame = function(_, name) return frame(name) end,
	UIParent = frame("UIParent"), UISpecialFrames = {}, GetTime = function() return now end,
	Menu = { ModifyMenu = function(tag, fn) if tag == "MENU_QUEST_OBJECTIVE_TRACKER" then menuHandler = fn end end },
	C_Timer = { After = function(_, fn) fn() end }, IsControlKeyDown = function() return true end,
	issecretvalue = function() return false end, ChatFontNormal = {},
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/QuestMenu.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
local api = ns.api
ns.onLogin[1]()
check("the link is WoW Forever's Wowhead page", api.wowheadQuestURL(5212) == "https://www.wowhead.com/forever/quest=5212")
check("added to Blizzard's tracker menu", type(menuHandler) == "function")

-- right-click on a quest: the menu gets the green line; clicking it opens the box with the link selected
api.lastQuestPressed = { id = 5212, at = now }
local button
local rootDescription = { CreateButton = function(_, text, fn) button = { text = text, fn = fn } end }
menuHandler(nil, rootDescription)
check("the menu line: \"Wowhead URL\" in green", button and button.text == "|cff1eff00Wowhead URL|r")
button.fn()
local box = nil
for _, f in ipairs(all) do if f.name == "ForeverTrackerPlusCopyURL" then box = f end end
local edit
for _, f in ipairs(all) do if rawget(f, "scripts") and f.scripts.OnKeyDown then edit = f end end
check("the box shows the link, selected and ready to copy", box and box.shown and edit and edit.text
	== "https://www.wowhead.com/forever/quest=5212" and edit.highlighted and edit.focused)
check("Escape closes it with the game's windows", env.UISpecialFrames[1] == "ForeverTrackerPlusCopyURL")
edit.scripts.OnTextChanged(edit, true)
edit.text = "typed"
edit.scripts.OnTextChanged(edit, true)
check("typing puts the link back", edit.text == "https://www.wowhead.com/forever/quest=5212")
edit.scripts.OnKeyDown(edit, "C")
check("Ctrl+C: copied, the box closes by itself", box.shown == false)
-- an old press (not this menu's): no line without a quest under the mouse
button = nil
now = 200
menuHandler(nil, rootDescription)
check("no quest known: no line", button == nil)

local rows = io.open(dir .. "/Tracker/Own/Rows.lua"):read("a")
check("the quest pressed is recorded on mouse down", rows:find("api.lastQuestPressed = { id = self.questID, at = GetTime(),", 1, true) ~= nil)
local toc = io.open(dir .. "/ForeverTrackerPlus.toc"):read("a")
check("in the toc", toc:find("Tracker/QuestMenu.lua", 1, true) ~= nil)

-- R106-86: Expand current zone only
local zs = io.open(dir .. "/Tracker/ZoneSort.lua"):read("a")
local body = zs:match("(local function wantedWatches%(list%).-\nend)")
check("the watch list found", body ~= nil)
if body then
	local zenv = setmetatable({ db = { expandCurrentZone = true, trackMode = "all" },
		sorted = function(l) return l end, candidates = function(l) return l end, maxWatches = function() return 25 end,
		api = { inCurrentZone = function(id) return id < 10 end },
		C_SuperTrack = { GetSuperTrackedQuestID = function() return 50 end } }, { __index = _G })
	local wanted = load(body .. "\nreturn wantedWatches", "w", "t", zenv)()
	local got = wanted({ { id = 1 }, { id = 20 }, { id = 2 }, { id = 50 } })
	local ids = {}
	for _, q in ipairs(got) do ids[#ids + 1] = q.id end
	check("only the player's zone tracked (and the super-tracked quest): " .. table.concat(ids, ","), table.concat(ids, ",") == "1,2,50")
	zenv.db.expandCurrentZone = false
	check("option off: every quest as before", #wanted({ { id = 1 }, { id = 20 } }) == 2)
end
check("its option", io.open(dir .. "/Tracker/Config.lua"):read("a"):find('"Expand current zone only"', 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
