-- R106-128: "More quests" (Tracker/MoreQuests.lua) has what tracked quests have: the type marker, the right-click
-- menu, Ctrl+left / Ctrl+right clicks and the quest item button (secure, on UIParent, never moved in combat)
local dir = arg[1]
local pass = true
local function check(name, ok)
	print((ok and "ok   " or "FAIL ") .. name)
	if not ok then pass = false end
end

local created = {}
STRINGS = {}
local F = {}
F.__index = function(t, k)
	if k == "GetStringHeight" then return function() return 12 end end
	if k == "GetWidth" then return function() return 260 end end
	if k == "GetEffectiveScale" or k == "GetScale" then return function(s) return rawget(s, "_scale") or 1 end end
	if k == "SetScale" then return function(s, v) rawset(s, "_scale", v) end end
	if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12, "" end end
	if k == "GetLeft" then return function(s) return rawget(s, "_left") or 100 end end
	if k == "GetRight" then return function() return 360 end end
	if k == "GetFrameLevel" then return function() return 1 end end
	if k == "GetFrameStrata" then return function() return "MEDIUM" end end
	if k == "GetAlpha" then return function(s) return rawget(s, "_alpha") or 1 end end
	if k == "SetAlpha" then return function(s, v) rawset(s, "_alpha", v) end end
	if k == "GetBottom" then return function(s) return rawget(s, "_bottom") or ((rawget(s, "_top") or 800) - 12) end end
	if k == "GetTop" then return function(s) return rawget(s, "_top") or 800 end end
	if k == "IsShown" or k == "IsVisible" then return function(s) return rawget(s, "_shown") ~= false end end
	if k == "Show" then return function(s) rawset(s, "_shown", true) end end
	if k == "Hide" then return function(s) rawset(s, "_shown", false) end end
	if k == "SetText" then return function(s, v) rawset(s, "_text", v) end end
	if k == "GetText" then return function(s) return rawget(s, "_text") end end
	if k == "SetScript" then return function(s, n, f) rawset(s, "_" .. n, f) end end
	if k == "GetParent" then return function(s) return rawget(s, "_parent") end end
	if k == "SetParent" then return function(s, p) rawset(s, "_parent", p) end end
	if k == "SetPoint" then return function(s, ...)
		local pt = { ... }
		rawset(s, "_point", pt)
		-- a row placed on the list: its top follows the list's offset (the list's top is 800)
		if pt[2] == rawget(s, "_owner") and type(pt[5]) == "number" then rawset(s, "_top", 800 + pt[5]) end
	end end
	if k == "SetAttribute" then return function(s, n, v) local a = rawget(s, "_attr") or {}; a[n] = v; rawset(s, "_attr", a) end end
	if k == "SetTexture" then return function(s, v) rawset(s, "_tex", v) end end
	if k == "CreateFontString" then return function(s)
		local fs = setmetatable({ _owner = s }, F); STRINGS[#STRINGS + 1] = fs; return fs
	end end
	if k:match("^Create") then return function() return setmetatable({}, F) end end
	return function() end
end
_G.CreateFrame = function(kind, name, parent, template)
	local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _template = template }, F)
	created[#created + 1] = f
	if name then _G[name] = f end
	return f
end
_G.geterrorhandler = function() return function(e) print("ERROR", e) end end
_G.UIParent = setmetatable({}, F)
_G.ForeverTrackerPlusViewport = setmetatable({ _top = 900, _bottom = 100 }, F)
local questModule = setmetatable({ GetContentsHeight = function() return 900 end }, F)
_G.QuestObjectiveTracker = questModule
_G.ObjectiveTrackerFrame = setmetatable({ modules = { questModule }, IsCollapsed = function() return false end }, F)
_G.Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 1 } }
_G.GetTime = function() return 10 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local combat = false
_G.InCombatLockdown = function() return combat end
local ctrl = false
_G.IsControlKeyDown = function() return ctrl end
_G.IsInGroup = function() return true end

local log = {
	{ isHeader = true, title = "Stratholme" },
	{ questID = 1, title = "Tracked one", level = 60 },
	{ questID = 5848, title = "Of Love and Family", level = 60 },
	{ questID = 2, title = "Group quest", level = 58, suggestedGroup = 5 },
}
local opened, focused, pushed = nil, nil, false
_G.C_QuestLog = { GetNumQuestLogEntries = function() return #log end, GetInfo = function(i) return log[i] end,
	GetQuestWatchType = function(id) return id == 1 and 0 or nil end,
	IsComplete = function() return false end,
	GetLogIndexForQuestID = function(id) for i, e in ipairs(log) do if e.questID == id then return i end end end,
	GetQuestObjectives = function(id) return { { text = "Of Love and Family: 0/1", finished = false } } end,
	IsPushableQuest = function() return true end, SetSelectedQuest = function() end, GetSelectedQuest = function() return 0 end }
_G.QuestLogPushQuest = function() pushed = true end
_G.QuestMapFrame_OpenToQuestDetails = function(id) opened = id end
_G.C_SuperTrack = { SetSuperTrackedQuestID = function(id) focused = id end, GetSuperTrackedQuestID = function() return 0 end }
_G.GetQuestLogSpecialItemInfo = function(index)
	if log[index] and log[index].questID == 5848 then return "|cffffffff|Hitem:12345::|h[Painting]|h|r", 134400, 0, false end
end
local menu
_G.MenuUtil = { CreateContextMenu = function(owner, gen)
	menu = { owner = owner, buttons = {} }
	local root = { SetTag = function(_, t) menu.tag = t end,
		CreateButton = function(_, text, fn) menu.buttons[#menu.buttons + 1] = { text = text, fn = fn } end }
	gen(owner, root)
end }
local timers = {}
_G.C_Timer = { After = function(_, f) timers[#timers + 1] = f end }
local function runTimers() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end

local api = {}
local SKULL = { atlas = "skull" }
api.moduleContentBottom = function() return 790 end
api.questClassifier = function(id)
	if id == 5848 then return SKULL, "Elite" end
	if id == 2 then return "|cffff8040[+5]|r", "Group" end
end
local placed = {}
api.placeTitleIcons = function(fs, icons) placed[fs] = icons return "" end
local linked, grouped
api.linkQuestRewards = function(id) linked = id end
api.findGroupForQuest = function(id) grouped = id end
api.questGroupFinderOn = function() return true end
local ns = { api = api, onLogin = {}, db = { enabled = true, trackMode = "all", moreQuests = true, questScale = 1, condense = true } }
assert(loadfile(dir .. "/Tracker/MoreQuests.lua"))("ForeverTrackerPlus", { tracker = ns, BRAND = "ForeverTrackerPlus" })
ns.onLogin[1]()
runTimers()
local frame = _G.ForeverTrackerPlusMoreQuests
check("the list is drawn", frame and frame:IsShown())

-- the type marker
local titleFs, groupFs
for fs, icons in pairs(placed) do
	local t = fs:GetText() or ""
	if t:find("Of Love and Family", 1, true) then titleFs = fs end
end
for _, fs in ipairs(STRINGS) do
	if fs:IsShown() and (fs:GetText() or ""):find("Group quest", 1, true) then groupFs = fs end
end
check("elite quest: its icon next to the title", titleFs and placed[titleFs][#placed[titleFs]] == SKULL)
check("group quest: [+5] in front of the title", groupFs and groupFs:GetText():find("[+5]", 1, true) == 11)
ns.db.condense = false
for k in pairs(placed) do placed[k] = nil end
api.rebuildMoreQuests(); runTimers()
local any = false
for _, icons in pairs(placed) do if icons[#icons] == SKULL then any = true end end
for _, fs in ipairs(STRINGS) do if fs:IsShown() and (fs:GetText() or ""):find("[+5]", 1, true) then any = true end end
check("Icon Classifications off: no marker", not any)
ns.db.condense = true
api.rebuildMoreQuests(); runTimers()

-- the clicks
local owner = { questID = 5848 }
api.moreQuestsClick(owner, "LeftButton")
check("left click: the quest log", opened == 5848)
ctrl = true
opened = nil
api.moreQuestsClick(owner, "LeftButton")
check("Ctrl+left: look for a group, not the quest log", grouped == 5848 and opened == nil)
api.moreQuestsClick(owner, "RightButton")
check("Ctrl+right: reward links in chat, no menu", linked == 5848 and menu == nil)
ctrl = false
api.moreQuestsClick(owner, "RightButton")
check("right click: the menu, with the tracker's tag (Wowhead URL joins it)",
	menu and menu.tag == "MENU_QUEST_OBJECTIVE_TRACKER" and menu.owner == owner)
local texts = {}
for _, b in ipairs(menu.buttons) do texts[b.text] = b.fn end
check("menu: Focus, Open in quest log, Share quest", texts["Focus"] and texts["Open in quest log"] and texts["Share quest"])
texts["Focus"](); texts["Share quest"]()
check("menu actions: focus and share", focused == 5848 and pushed)

-- the item button
local item = _G.ForeverTrackerPlusMoreQuestItem1
check("item button: secure, on UIParent", item and item._template == "SecureActionButtonTemplate" and item._parent == UIParent)
check("item button: uses the quest's item", item and item._attr.type == "item" and item._attr.item == "item:12345")
check("item button: shown left of the objectives, under the title", item and item:IsShown() and item._point[1] == "TOPRIGHT"
	and item._point[2] == UIParent and item._point[4] == 96)
check("only quests with an item get one", _G.ForeverTrackerPlusMoreQuestItem2 == nil)
-- the list scrolls: the button follows
titleFs = nil
for fs in pairs(placed) do if (fs:GetText() or ""):find("Of Love", 1, true) then titleFs = fs end end
rawset(titleFs, "_top", 700)
frame._OnUpdate(frame, 0.01)
check("the title moved: the button follows", item._point[5] == 700 - 12 - 1)
-- in combat: never moved, made see-through instead; placed when the fight ends
combat = true
local before = item._point
rawset(titleFs, "_top", 650)
frame._OnUpdate(frame, 0.01)
check("in combat: not moved, see-through", item._point == before and item:GetAlpha() == 0)
combat = false
for _, f in ipairs(created) do
	if f._OnEvent then f._OnEvent(f, "PLAYER_REGEN_ENABLED") end
end
check("fight over: placed again and visible", item._point[5] == 650 - 12 - 1 and item:GetAlpha() == 1)
-- scrolled out of the list's visible part: hidden
rawset(titleFs, "_top", 1000)
frame._OnUpdate(frame, 0.01)
check("scrolled out of view: hidden", not item:IsShown())
rawset(titleFs, "_top", 700)
frame._OnUpdate(frame, 0.01)
check("back in view: shown", item:IsShown())
-- the list hidden (out of combat): the button goes too
frame:Hide(); frame._OnHide(frame)
check("list hidden: the button hidden", not item:IsShown())
print(pass and "PASS" or "FAILED")
