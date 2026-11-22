-- R106-99: the model panel (Tracker/NpcPanel.lua): an NPC's name, title, level, type and full-body model; an object's
-- name and model (its model file from ns.objectModels); no model, no panel; the model turns while shown; the quest
-- tracker's objective lines find their NPC or object
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local created = {}
local function frame(kind)
	local f = { kind = kind, points = {}, shown = true, calls = {}, scripts = {}, w = 0, h = 0 }
	local methods = {
		ClearAllPoints = function(self) self.points = {} end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetWidth = function(self, w) self.w = w end, SetHeight = function(self, h) self.h = h end,
		SetSize = function(self, w, h) self.w, self.h = w, h end,
		GetEffectiveScale = function() return 1 end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		CreateFontString = function() return frame("FontString") end,
		CreateTexture = function() return frame("Texture") end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		GetStringHeight = function() return 12 end,
		SetTexture = function(self, t) self.tex = t end,
		SetTextColor = function(self, r, g, b) self.color = { r, g, b } end,
		IsMouseOver = function(self) return self.over ~= false end,
		IsVisible = function(self) return self.shown ~= false end,
		GetTop = function(self) return self.top end, GetLeft = function(self) return self.left end,
		GetRight = function(self) return self.right end,
	}
	for _, m in ipairs({ "SetCreature", "SetItem", "SetPortraitZoom", "SetCamDistanceScale", "SetFacing", "ClearModel",
		"SetPosition", "SetKeepModelOnHide", "SetModel" }) do
		methods[m] = function(self, ...) self.calls[m] = { ... } end
	end
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

local ticks
local tracker = frame("Frame")
tracker.left, tracker.right = 1500, 1750
local env = setmetatable({
	CreateFrame = function(kind) local f = frame(kind); created[#created + 1] = f; return f end,
	UIParent = frame("Frame"), ObjectiveTrackerFrame = tracker,
	C_Timer = { NewTicker = function(_, fn) ticks = fn; return { Cancel = function() ticks = nil end } end, After = function() end },
	LibQuestieDB = { Object = { BuildNameIndexAsync = function() end,
		IdsByName = function(n) return n == "Taillasher Eggs" and { 900, 3240 } or n == "Bush" and { 7 } or nil end },
		Item = { BuildNameIndexAsync = function() end,
			IdsByName = function(n) return n == "Un'Goro Soil" and { 11018 } or nil end } },
	strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = p end return table.unpack(out) end,
	unpack = table.unpack, issecretvalue = function() return false end, geterrorhandler = function() return print end,
}, { __index = _G })
env._G = env
local ns = { api = {}, onLogin = {}, db = { npcTypes = { [3205] = "Humanoid" } } }
local root = { tracker = ns, objectives = { npcIdFor = function(name) return name == "Zalazane" and 3205 or nil end,
	rxp = { guideTextColors = { RXP_ENEMY_ = "FFFF5722" } } } }
assert(loadfile(dir .. "/Tracker/NpcPanel.lua", "t", env))("ForeverTrackerPlus", root)
local api = ns.api
api.questieNpc = function(id)
	return id == 3205 and { name = "Zalazane", minLevel = 10, maxLevel = 10, rank = 1 } or nil
end
ns.onLogin[1]()

local line = frame("Frame")
line.top = 600
api.showNpcPanel("Zalazane", { kind = "enemy", owner = line })
local panel = env.ForeverTrackerPlusNpcPanel or created[2]
local model
for _, f in ipairs(created) do if f.kind == "PlayerModel" then model = f end end
for _, f in ipairs(created) do if f.scripts.OnUpdate and f.kind == "Frame" and f.w == 210 then panel = f end end
check("an NPC: the panel is shown", panel and panel.shown)
check("its model by npc id (looked up by name)", model and model.calls.SetCreature and model.calls.SetCreature[1] == 3205)
check("the whole body (portrait zoom 0)", model.calls.SetPortraitZoom and model.calls.SetPortraitZoom[1] == 0)
-- find the font strings through the panel's upvalue "texts"
local function upv(fn, want) local i = 1 while true do local n, v = debug.getupvalue(fn, i); if not n then return end; if n == want then return v end; i = i + 1 end end
local render = upv(api.showNpcPanel, "render")
local fsList = upv(render, "texts")
local function visible() local out = {} for _, fs in ipairs(fsList) do if fs.shown then out[#out + 1] = fs.text end end return out end
local v = visible()
check("name, level and rank, creature type", v[1] == "Zalazane" and v[2] == "Level 10 Elite" and v[3] == "Humanoid")
check("the name in RestedXP's enemy colour", math.abs(fsList[1].color[1] - 1) < 0.01 and math.abs(fsList[1].color[2] - 0x57 / 255) < 0.01)
check("left of the tracker, level with the line", panel.points[1][1] == "TOPRIGHT" and panel.points[1][4] == 1500 - 8
	and panel.points[1][5] == 610)
-- turning
panel.scripts.OnUpdate(panel, 1)
check("the model turns while shown", model.calls.SetFacing and math.abs(model.calls.SetFacing[1] - 0.6) < 1e-6)
-- hide for another owner: stays; for its own: hidden
api.hideNpcPanel(frame("Frame"))
check("another line's leave keeps it", panel.shown)
api.hideNpcPanel(line)
check("its own line's leave hides it", not panel.shown)

-- an NPC with no id (so no model): no panel; it opens when the id turns up while still hovered
local later
root.objectives.npcIdFor = function(name) return name == "Zalazane" and 3205 or name == "Vol'jin" and later or nil end
api.showNpcPanel("Vol'jin", { kind = "friendly", owner = line })
check("no model: no panel", not panel.shown)
later = 10540
if ticks then ticks() end
check("the id found while hovered: the panel opens", panel.shown and model.calls.SetCreature[1] == 10540)
api.hideNpcPanel(line)

-- an object to pick up: by its name, the first of its object ids with a model file
api.showNpcPanel("Bush", { kind = "pick", owner = line })
check("an object without a model file: no panel", not panel.shown)
api.hideNpcPanel()
ns.objectModels[3240] = 200000
api.showNpcPanel("Taillasher Eggs", { kind = "pick", owner = line })
check("an object: its model by model file", panel.shown and model.calls.SetModel and model.calls.SetModel[1] == 200000)
v = visible()
check("an object: its name only", v[1] == "Taillasher Eggs" and v[2] == nil)
check("an object turns too", (function() panel.scripts.OnUpdate(panel, 1) return model.calls.SetFacing[1] > 0 end)())
api.hideNpcPanel()
-- R106-108: an item picked up from an object: the object's model, its name under the item's
api.itemObjectSources = function(id) return id == 11018 and { { objectId = 1, name = "Nothing" },
	{ objectId = 157936, name = "Un'Goro Dirt Pile" } } or {} end
ns.objectModels[157936] = 201234
api.showNpcPanel("Un'Goro Soil", { kind = "pick", owner = line })
v = visible()
check("an item from an object: the object's model (the first with one)", panel.shown and model.calls.SetModel[1] == 201234)
check("the item's name, then <the object>", v[1] == "Un'Goro Soil" and v[2] == "<Un'Goro Dirt Pile>")
api.hideNpcPanel()

-- R106-111: a vague name on a quest's step: the quest's object with that word
local dist = api.npcPanelDistance
check("distance: one letter off", dist("loost dirt", "loose dirt", 2) == 1)
check("distance: too far is nil", dist("chest", "crate", 1) == nil)
local objectNames = { [500] = "Battered Chest", [501] = "Loose Dirt", [502] = "Cliffspring Chest", [503] = "Loose Dirt" }
ns.objectModels[500], ns.objectModels[501], ns.objectModels[502], ns.objectModels[503] = 300500, 300501, 300502, 300503
api.questObjects = function(q) return q == 77 and { { objectId = 500, name = "Battered Chest" } } or {} end
api.showNpcPanel("Chest", { kind = "pick", owner = line, quests = { 77 } })
v = visible()
check("vague 'Chest': the quest's Battered Chest", panel.shown and model.calls.SetModel[1] == 300500 and v[2] == "<Battered Chest>")
api.hideNpcPanel()
api.showNpcPanel("Chest", { kind = "pick", owner = line, quests = { 78 } })
check("vague 'Chest' with no quest object: no panel", not panel.shown)
api.hideNpcPanel()
-- a typo with no quest to go by: the near name that spawns on your map
api.questieObjectName = function(id) return objectNames[id] end
api.questieObjectMaps = function(id) return id == 502 and { [1411] = true } or id == 501 and { [1411] = true } or { [1] = true } end
env.C_Map = { GetBestMapForUnit = function() return 1411 end, GetMapInfo = function() return { parentMapID = 1414 } end }
api.showNpcPanel("Clliffspring Chest", { kind = "pick", owner = line })
v = visible()
check("typo: Clliffspring Chest -> Cliffspring Chest here", panel.shown and model.calls.SetModel[1] == 300502
	and v[2] == "<Cliffspring Chest>")
api.hideNpcPanel()
api.showNpcPanel("Loost Dirt", { kind = "pick", owner = line })
check("typo: the copy on another map is left out (no tie)", panel.shown and model.calls.SetModel[1] == 300501)
api.hideNpcPanel()
env.C_Map = { GetBestMapForUnit = function() return 1 end }
api.showNpcPanel("Clliffspring Chest", { kind = "pick", owner = line })
check("typo: not on your map, no panel", not panel.shown)
api.hideNpcPanel()
-- R106-112: same name, shared model (strict)
local shared = api.npcPanelSharedModel
ns.objectModels[600], ns.objectModels[601], ns.objectModels[602] = 400600, 400600, 400602
check("same name, one model: the new copy (no model) takes it", shared({ 699, 600, 601 }) == 400600)
api.questieObjectMaps = function(id) return id == 602 and { [1411] = true } or { [1] = true } end
env.C_Map = { GetBestMapForUnit = function() return 1411 end }
check("models differ: the copy where you are", shared({ 699, 600, 602 }) == 400602)
env.C_Map = { GetBestMapForUnit = function() return 50 end }
check("models differ, none where you are: none", shared({ 699, 600, 602 }) == nil)
check("no copy has a model: none", shared({ 699 }) == nil)
env.C_Map = nil

-- an item not from an object: its icon
env.C_Item = { GetItemInfoInstant = function(n) if n == "Phial of Scrying" then return 7667, nil, nil, nil, 134776 end end }
api.showNpcPanel("Phial of Scrying", { kind = "pick", owner = line })
v = visible()
local iconTex = upv(render, "iconTex")
check("item: its icon, no model", panel.shown and iconTex.shown and iconTex.tex == 134776 and not model.shown)
check("item: name, then 'Item (no 3D model)'", v[1] == "Phial of Scrying" and v[2] == "Item (no 3D model)")
api.hideNpcPanel()
api.showNpcPanel("Taillasher Eggs", { kind = "pick", owner = line })
check("a model again: the icon hidden", panel.shown and model.shown and not iconTex.shown)
api.hideNpcPanel()
env.C_Item = nil

-- quest tracker: the objective line under the mouse
local npcs = { { id = 3205, name = "Zalazane" }, { objectId = 3240, name = "Taillasher Egg" } }
check("line match: an NPC", api.npcPanelLineMatch("|cffffffffZalazane slain: 0/1|r", npcs) == npcs[1])
check("line match: an object", api.npcPanelLineMatch("Taillasher Egg: 3/8", npcs) == npcs[2])
check("line match: nothing", api.npcPanelLineMatch("Explore the cave", npcs) == nil)
api.questObjectiveNpcs = function() return npcs end
local block = frame("Frame")
local l1, l2 = frame("Frame"), frame("Frame")
l1.Text, l2.Text = frame("FontString"), frame("FontString")
l1.Text.text, l2.Text.text = "Zalazane slain: 0/1", "Taillasher Egg: 0/8"
l1.over, l1.top, l2.over, l2.top = false, 520, true, 500
block.usedLines = { a = l1, b = l2 }
api.npcHoverStart(block, 826)
check("hovering the egg line: the object's panel", panel.shown and model.calls.SetModel[1] == 200000)
api.hideNpcPanel()
-- R106-108: an item objective: matched by the item's name, the object's model shown
npcs[#npcs + 1] = { objectId = 157936, name = "Un'Goro Dirt Pile", item = "Un'Goro Soil", text = "Un'Goro Soil" }
l2.Text.text = "Un'Goro Soil: 0/25"
api.npcHoverStart(block, 4141)
v = visible()
check("hovering an item objective: its object's model, the item's name over the object's",
	panel.shown and model.calls.SetModel[1] == 201234 and v[1] == "Un'Goro Soil" and v[2] == "<Un'Goro Dirt Pile>")
-- R106-115: another quest hovered before this one's OnLeave: the panel goes
api.questObjectiveNpcs = function(q) return q == 999 and {} or npcs end
api.npcHoverStart(frame("Frame"), 999)
check("another quest (no objectives to show) hovered: the old panel closes", not panel.shown)
api.questObjectiveNpcs = function() return npcs end
-- R106-127: a "More quests" line's hover button (MoreQuests.lua)
local moreLine = frame("Button")
moreLine.over, moreLine.top = true, 480
api.npcLineHover(moreLine, 4141, "Un'Goro Soil: 0/25")
check("More quests line: the item's object model", panel.shown and model.calls.SetModel[1] == 201234
	and api.npcPanelShown().owner == moreLine)
api.hideNpcPanel(moreLine)
check("More quests line left: the panel closes", not panel.shown)
api.npcLineHover(moreLine, 4141, "Explore the cave")
check("More quests line naming nothing: no panel", not panel.shown)
ns.db.npcPanelQuests = false
api.hideNpcPanel()
api.npcHoverStart(block, 826)
check("option off: no panel", not panel.shown)
api.npcLineHover(moreLine, 4141, "Un'Goro Soil: 0/25")
check("option off: no panel on a More quests line", not panel.shown)
print(pass and "PASS" or "FAILED")
