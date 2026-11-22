-- R106-113: the model panel (Tracker/NpcPanel.lua): an object in a ModelScene, the camera set back to show it whole
-- (its bounding box); the panel left of the quest tooltip when there is one
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function frame(kind)
	local f = { kind = kind, points = {}, shown = true, calls = {}, scripts = {}, w = 0, h = 0 }
	local methods = {
		ClearAllPoints = function(self) self.points = {} end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetWidth = function(self, w) self.w = w end, SetHeight = function(self, h) self.h = h end,
		SetSize = function(self, w, h) self.w, self.h = w, h end,
		GetWidth = function(self) return self.w end, GetHeight = function(self) return self.h end,
		GetEffectiveScale = function() return 1 end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		CreateFontString = function() return frame("FontString") end,
		CreateTexture = function() return frame("Texture") end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		GetStringHeight = function() return 12 end,
		GetTop = function(self) return self.top end, GetLeft = function(self) return self.left end,
		GetRight = function(self) return self.right end,
		GetParent = function(self) return rawget(self, "parent") end, GetOwner = function(self) return rawget(self, "owner") end,
		IsMouseOver = function(self) return rawget(self, "over") ~= false end,
		IsVisible = function(self) return self.shown ~= false end,
	}
	for _, m in ipairs({ "SetCreature", "SetModel", "SetCameraPosition", "SetCameraOrientationByAxisVectors",
		"SetCameraFieldOfView", "SetCameraNearClip", "SetCameraFarClip", "SetModelByFileID", "SetYaw", "SetAlpha",
		"SetPosition", "ClearModel", "SetUseCenterForOrigin", "SetFacing" }) do
		methods[m] = function(self, ...) self.calls[m] = { ... } end
	end
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

now = 100
local actor = frame("Actor")
actor.loaded = false
actor.IsLoaded = function(self) return self.loaded end
actor.GetActiveBoundingBox = function() return { x = -3, y = -4, z = 0 }, { x = 3, y = 4, z = 0 } end -- radius 5
local scene, created = nil, {}
local tip = frame("GameTooltip")
tip.shown = false
local env = setmetatable({
	CreateFrame = function(kind)
		local f = frame(kind)
		if kind == "ModelScene" then
			scene = f
			f.CreateActor = function() return actor end
			f.GetCameraFieldOfView = function() return 0.7 end
		end
		created[#created + 1] = f
		return f
	end,
	UIParent = frame("Frame"), ObjectiveTrackerFrame = (function() local t = frame("Frame") t.left, t.right = 1500, 1750 return t end)(),
	GameTooltip = tip, GetTime = function() return now end,
	C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function() end },
	unpack = table.unpack, issecretvalue = function() return false end, geterrorhandler = function() return print end,
	strsplit = function() end,
}, { __index = _G })
env._G = env
local ns = { api = {}, onLogin = {}, db = {}, objectModels = { [3240] = 200000 } }
local root = { tracker = ns, objectives = {} }
assert(loadfile(dir .. "/Tracker/NpcPanel.lua", "t", env))("ForeverTrackerPlus", root)
local api = ns.api
ns.onLogin[1]()

-- the distance: a radius-5 model, fov 0.7, a stage wider than tall (the height holds it)
local d = api.npcPanelFitDistance(5, 0.7, 200, 250)
local want = 5 / math.sin(math.atan(math.tan(0.35) * 200 / 250)) * 1.08
check("fit distance: the narrower side holds the model", math.abs(d - want) < 1e-9)
check("a bigger model: the camera farther back", api.npcPanelFitDistance(50, 0.7, 200, 250) > d * 9.9)

local line = frame("Frame")
line.top, line.left = 600, 1500
-- an object by its id: shown in the scene, not the PlayerModel
api.showNpcPanel("Taillasher Eggs", { kind = "pick", objectId = 3240, owner = line })
local panel
for _, f in ipairs(created) do if f.scripts.OnUpdate and f.w == 210 then panel = f end end
check("an object: the scene shows it", scene and scene.shown and actor.calls.SetModelByFileID[1] == 200000)
check("a first camera while it loads (some distance back)", scene.calls.SetCameraPosition
	and scene.calls.SetCameraPosition[1] == 6)
scene.calls.SetCameraPosition = nil
panel.scripts.OnUpdate(panel, 0.1)
check("not loaded yet: not framed", scene.calls.SetCameraPosition == nil)
actor.loaded = true
scene.w, scene.h = 200, 250
panel.scripts.OnUpdate(panel, 0.1)
local cam = scene.calls.SetCameraPosition
check("loaded: the camera set back to fit it", cam and math.abs(cam[1] - want) < 1e-6 and cam[2] == 0 and cam[3] == 0)
check("looking back at the centre, z up", scene.calls.SetCameraOrientationByAxisVectors
	and scene.calls.SetCameraOrientationByAxisVectors[1] == -1 and scene.calls.SetCameraOrientationByAxisVectors[9] == 1)
check("it turns", actor.calls.SetYaw and actor.calls.SetYaw[1] > 0)
scene.calls.SetCameraPosition = nil
panel.scripts.OnUpdate(panel, 0.1)
check("framed once only", scene.calls.SetCameraPosition == nil)
check("the panel is placed by the tracker (no quest tooltip)", panel.points[1][2] == env.UIParent)
api.hideNpcPanel()

-- the quest tooltip is up for the quest the line is in: the panel goes left of it
local block = frame("Frame")
line.parent = block
tip.shown, tip.owner, tip.left, tip.top = true, block, 1200, 700
api.showNpcPanel("Taillasher Eggs", { kind = "pick", objectId = 3240, owner = line })
check("left of the quest tooltip, at a fixed place (not tied to it)", panel.points[1][1] == "TOPRIGHT"
	and panel.points[1][2] == env.UIParent and panel.points[1][4] == 1200 - 8 and panel.points[1][5] == 700)
api.hideNpcPanel()
tip.left = 100
api.showNpcPanel("Taillasher Eggs", { kind = "pick", objectId = 3240, owner = line })
check("no room left of the tooltip: by the tracker", panel.points[1][2] == env.UIParent)
api.hideNpcPanel()
tip.left, tip.owner = 1200, frame("Frame")
api.showNpcPanel("Taillasher Eggs", { kind = "pick", objectId = 3240, owner = line })
check("a tooltip of something else: by the tracker", panel.points[1][2] == env.UIParent)
api.hideNpcPanel()

-- R106-113: a model that never loads in the scene: after 1.5 s it goes back to the PlayerModel
local player
for _, f in ipairs(created) do if f.kind == "PlayerModel" then player = f end end
env.ns_unused = nil
ns.objectModels[4000] = 500000
tip.shown = false
actor.loaded = false
api.showNpcPanel("Fifth Mosh'aru Tablet", { kind = "pick", objectId = 4000, owner = line })
check("in the scene first", scene.shown and actor.calls.SetModelByFileID[1] == 500000)
now = now + 1
panel.scripts.OnUpdate(panel, 0.1)
check("1 s: still waiting", scene.shown)
now = now + 1
panel.scripts.OnUpdate(panel, 0.1)
check("1.5 s: back to the PlayerModel", not scene.shown and player.shown and player.calls.SetModel
	and player.calls.SetModel[1] == 500000 and panel.shown)
local lines = {}
api.npcPanelDebug(function(t) lines[#lines + 1] = t end)
check("/qt debug tells it", lines[1] and lines[1]:find("back to PlayerModel=1", 1, true) and lines[1]:find("loaded=false", 1, true))
api.hideNpcPanel()
api.showNpcPanel("Fifth Mosh'aru Tablet", { kind = "pick", objectId = 4000, owner = line })
check("next time: straight to the PlayerModel", not scene.shown and player.shown)
api.hideNpcPanel()

-- R106-114: scrolls and documents: the PlayerModel, not the scene
local paper = api.npcPanelIsPaper
check("paper words", paper("Important Blackrock Documents") and paper("Scroll of Myzrael") and paper(nil, "Inconspicuous Documents")
	and paper("Gorishi Scent Gland") == false and paper("Fifth Mosh'aru Tablet") == false)
ns.objectModels[4100] = 510000
api.showNpcPanel("Important Blackrock Documents", { kind = "pick", objectId = 4100, owner = line })
check("documents: the old frame", not scene.shown and player.shown and player.calls.SetModel[1] == 510000)
api.hideNpcPanel()
actor.loaded = true
api.showNpcPanel("Taillasher Eggs", { kind = "pick", objectId = 3240, owner = line })
check("other objects: still the scene", scene.shown and not player.shown)
api.hideNpcPanel()

-- R106-115: the panel closes when its line is hidden or no longer under the mouse (no OnLeave)
api.showNpcPanel("Taillasher Eggs", { kind = "pick", objectId = 3240, owner = line })
panel.scripts.OnUpdate(panel, 0.1)
check("line hovered: stays", panel.shown)
line.shown = false
panel.scripts.OnUpdate(panel, 0.1)
check("line hidden: closes", not panel.shown and api.npcPanelShown() == nil)
line.shown = true
api.showNpcPanel("Taillasher Eggs", { kind = "pick", objectId = 3240, owner = line })
line.over = false
panel.scripts.OnUpdate(panel, 0.1)
check("mouse gone from the line: closes", not panel.shown)
line.over = nil

-- R106-117: a left click on a boss portrait: the boss's model left of the dungeon card
local npcModel
for _, f in ipairs(created) do if f.kind == "PlayerModel" then npcModel = f end end
local card = frame("Frame")
card.left, card.top = 1500, 800
env.ForeverTrackerPlusDungeonCard = card
local portrait = frame("Frame")
portrait.top, portrait.left = 700, 1600
portrait.boss = { name = "Rhahk'Zor", npcID = 644 }
local hooks = {}
portrait.HookScript = function(self, name, fn) hooks[name] = fn end
tip.shown, tip.owner, tip.left, tip.top = true, portrait, 1640, 720
api.npcPanelBossTooltip(tip)
check("hover: no panel (click only)", not panel.shown)
check("hover: the portrait's mouse-up hooked", hooks.OnMouseUp ~= nil)
hooks.OnMouseUp(portrait, "RightButton")
check("right click: nothing", not panel.shown)
hooks.OnMouseUp(portrait, "LeftButton")
check("left click: its model by npc id", panel.shown and npcModel.calls.SetCreature and npcModel.calls.SetCreature[1] == 644)
check("left click: left of the dungeon card, level with its top", panel.points[1][1] == "TOPRIGHT"
	and panel.points[1][2] == env.UIParent and panel.points[1][4] == 1500 - 8 and panel.points[1][5] == 800)
portrait.over = false
panel.scripts.OnUpdate(panel, 0.1)
check("mouse off the portrait but on the card: stays", panel.shown)
hooks.OnMouseUp(portrait, "LeftButton")
check("same boss clicked again: closes", not panel.shown)
hooks.OnMouseUp(portrait, "LeftButton")
card.over = false
panel.scripts.OnUpdate(panel, 0.1)
check("mouse off the card: closes", not panel.shown)
card.over = nil
local button = frame("Button")
button.portrait = { boss = { name = "Ironfel", portraitNpcID = 270887 } }
local bh = {}
button.HookScript = function(self, name, fn) bh[name] = fn end
tip.owner = button
api.npcPanelBossTooltip(tip)
bh.OnMouseUp(button, "LeftButton")
check("target button over a portrait: its boss, by portraitNpcID", panel.shown and npcModel.calls.SetCreature[1] == 270887)
api.hideNpcPanel()

-- R106-118: the hint "Left-click to show 3D", above DungeonJournal's gold hint
local function fakeTip(lines)
	local t = { lines = {} }
	local function fs(text, r, g, b)
		return { text = text, c = { r or 1, g or 1, b or 1 }, GetText = function(self) return self.text end,
			SetText = function(self, v) self.text = v end, GetTextColor = function(self) return self.c[1], self.c[2], self.c[3] end }
	end
	for i, l in ipairs(lines) do t.lines[i] = fs(l[1], l[2], l[3], l[4]); env["FakeTipTextLeft" .. i] = t.lines[i] end
	function t:GetName() return "FakeTip" end
	function t:NumLines() return #self.lines end
	function t:AddLine(text, r, g, b) local f = fs(text, r, g, b); self.lines[#self.lines + 1] = f; env["FakeTipTextLeft" .. #self.lines] = f end
	function t:Show() end
	return t
end
local t1 = fakeTip({ { "Rhahk'Zor", 1, 0.82, 0 }, { "Not killed", 0.75, 0.72, 0.66 }, { "Click to show loot", 1, 0.82, 0 } })
api.npcPanelBossHint(t1)
check("hint above DungeonJournal's gold hint", t1.lines[3].text == "Left-click to show 3D" and t1.lines[4].text == "Click to show loot"
	and #t1.lines == 4)
api.npcPanelBossHint(t1)
check("once per tooltip", #t1.lines == 4)
local t2 = fakeTip({ { "Rhahk'Zor", 1, 0.82, 0 }, { "Not killed", 0.75, 0.72, 0.66 } })
api.npcPanelBossHint(t2)
check("no gold hint: ours at the end", t2.lines[3] and t2.lines[3].text == "Left-click to show 3D" and t2.lines[2].text == "Not killed")
local t3 = fakeTip({ { "Rhahk'Zor", 1, 0.82, 0 } })
api.npcPanelBossHint(t3)
check("only the name: added under it (the name kept)", t3.lines[1].text == "Rhahk'Zor" and t3.lines[2].text == "Left-click to show 3D")

-- R106-119: a rare not found yet: "Rare not found (yet?)" at the very bottom, DungeonJournal's grey line gone
local rare = { boss = { name = "Ironfel" }, isRare = true, notFound = true }
local t4 = fakeTip({ { "Ironfel", 1, 0.82, 0 }, { "not found", 0.75, 0.72, 0.66 } })
api.npcPanelBossHint(t4, rare)
check("rare: hint, then 'Rare not found (yet?)' at the bottom", #t4.lines == 3 and t4.lines[2].text == "Left-click to show 3D"
	and t4.lines[3].text == "Rare not found (yet?)")
t4:AddLine("Click to show loot", 1, 0.82, 0) -- DungeonJournal adds its loot hint after its first Show
api.npcPanelBossHint(t4, rare)
check("a line added later: ours still above it, not found still last", #t4.lines == 4 and t4.lines[2].text == "Left-click to show 3D"
	and t4.lines[3].text == "Click to show loot" and t4.lines[4].text == "Rare not found (yet?)")
api.npcPanelBossHint(t4, rare)
check("again: no change", #t4.lines == 4 and t4.lines[4].text == "Rare not found (yet?)")
local t5 = fakeTip({ { "Ironfel", 1, 0.82, 0 }, { "not killed", 0.75, 0.72, 0.66 }, { "Click to target", 1, 0.82, 0 } })
api.npcPanelBossHint(t5, { portrait = rare })
check("target button over a not-found rare: its 'not killed' line replaced too", #t5.lines == 4
	and t5.lines[2].text == "Left-click to show 3D" and t5.lines[3].text == "Click to target" and t5.lines[4].text == "Rare not found (yet?)")
local t6 = fakeTip({ { "Ironfel", 1, 0.82, 0 }, { "not killed", 0.75, 0.72, 0.66 } })
api.npcPanelBossHint(t6, { boss = { name = "Ironfel" }, isRare = true, notFound = false })
check("a rare already seen: its line kept", t6.lines[2].text == "not killed" and t6.lines[3].text == "Left-click to show 3D")

-- R106-120: an NPC model blank the first time: set again every half second until it has loaded
local p2 = frame("Frame")
p2.top, p2.left = 700, 1600
p2.boss = { name = "Cookie", npcID = 645 }
local h2 = {}
p2.HookScript = function(self, name, fn) h2[name] = fn end
tip.shown, tip.owner = true, p2
api.npcPanelBossTooltip(tip)
h2.OnMouseUp(p2, "LeftButton")
check("Cookie shown", panel.shown and npcModel.calls.SetCreature[1] == 645)
local sets = 0
local realSet = npcModel.SetCreature
npcModel.SetCreature = function(self, id) sets = sets + 1; self.calls.SetCreature = { id } end
npcModel.GetModelFileID = function() return nil end
panel.scripts.OnUpdate(panel, 0.1)
check("before half a second: not set again", sets == 0)
now = now + 0.6
panel.scripts.OnUpdate(panel, 0.1)
check("not loaded after half a second: set again", sets == 1 and npcModel.calls.SetCreature[1] == 645)
npcModel.GetModelFileID = function() return 123456 end
now = now + 0.6
panel.scripts.OnUpdate(panel, 0.1)
check("loaded: no more", sets == 1)
now = now + 5
panel.scripts.OnUpdate(panel, 0.1)
check("still no more", sets == 1)
npcModel.SetCreature = realSet
api.hideNpcPanel()
print(pass and "PASSED" or "FAILED")
