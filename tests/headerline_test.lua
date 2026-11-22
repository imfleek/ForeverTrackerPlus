-- R106-97: the "Dungeon" header has the "Quests" header's line: its art copied piece by piece (layer, points, size,
-- colour, opacity), and the Quests header's width, left edge and height
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function frame(name, kind)
	local f = { name = name, kind = kind or "Frame", points = {}, shown = true, alpha = 1, w = 100, h = 10, scripts = {},
		regions = {}, vc = { 1, 1, 1 }, left = 100 }
	local methods = {
		ClearAllPoints = function(self) self.points = {} end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		SetAllPoints = function(self, rel) self.points = { { "ALL", rel } } end,
		GetNumPoints = function(self) return #self.points end,
		GetPoint = function(self, i) return table.unpack(self.points[i]) end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end, SetShown = function(self, v) self.shown = v and true or false end,
		SetAlpha = function(self, a) self.alpha = a end, GetAlpha = function(self) return self.alpha end,
		SetSize = function(self, w, h) self.w, self.h = w, h end, GetSize = function(self) return self.w, self.h end,
		SetWidth = function(self, w) self.w = w end, GetWidth = function(self) return self.w end,
		SetHeight = function(self, h) self.h = h end, GetHeight = function(self) return self.h end,
		GetLeft = function(self) return self.left end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		GetEffectiveScale = function() return 1 end, GetFrameStrata = function() return "MEDIUM" end,
		GetFrameLevel = function() return 1 end,
		CreateFontString = function() return frame("text", "FontString") end,
		CreateTexture = function(self, _, layer) local t = frame("tex", "Texture"); t.layer = layer; self.regions[#self.regions + 1] = t; return t end,
		GetRegions = function(self) return table.unpack(self.regions) end,
		GetObjectType = function(self) return self.kind end,
		SetAtlas = function(self, a) self.atlas = a end, GetAtlas = function(self) return self.atlas end,
		SetTexture = function(self, t) self.file = t end, GetTexture = function(self) return self.file end,
		SetColorTexture = function(self, ...) self.color = { ... } end,
		SetDrawLayer = function(self, l, sub) self.layer, self.sub = l, sub end,
		GetDrawLayer = function(self) return self.layer, self.sub end,
		SetVertexColor = function(self, r, g, b) self.vc = { r, g, b } end,
		GetVertexColor = function(self) return table.unpack(self.vc) end,
		GetFont = function() return "font", 12, "" end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
	}
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

-- Blizzard's Quests header: a background (atlas, stretched over it) and a line under it (its own size and place)
local quests = frame("QuestsHeader")
quests.w, quests.h, quests.left = 240, 30, 104
local bg = quests:CreateTexture(nil, "BACKGROUND")
bg.atlas = "UI-QuestTracker-Primary-Objective-Header"
bg.points = { { "TOPLEFT", quests, "TOPLEFT", -20, 4 }, { "BOTTOMRIGHT", quests, "BOTTOMRIGHT", 10, -6 } }
local line = quests:CreateTexture(nil, "ARTWORK")
line.atlas = "UI-QuestTracker-Header-Line"
line.points = { { "BOTTOM", quests, "BOTTOM", 0, -2 } }
line.w, line.h = 260, 3
line.vc, line.alpha = { 1, 0.8, 0.2 }, 0.7
quests.Shine = quests:CreateTexture(nil, "OVERLAY")
quests.Shine.atlas = "shine"
quests.Text = frame("QuestsText", "FontString")
quests.MinimizeButton = false -- (none in this test)
local module = frame("QuestObjectiveTracker")
module.Header = quests
module.w, module.left = 260, 100

local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function(_, name) return frame(name) end, UIParent = frame("UIParent"),
	QuestObjectiveTracker = module,
	IsInInstance = function() return true, "party" end,
	GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end,
	GetNumGroupMembers = function() return 1 end, IsInRaid = function() return false end,
	UnitExists = function() return false end, LFG_TYPE_DUNGEON = "Dungeon", GameTooltip = frame("tip"),
	issecretvalue = function() return false end, unpack = table.unpack,
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Dungeon.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
ns.onLogin[1]()
local anchor = frame("ghost")
api = ns.api
api.layoutDungeonCard(anchor, 0, 1)
local card = env.ForeverTrackerPlusDungeonCard
-- the card's header: the first frame made in the card with art copied (find the textures by their atlas)
local copiedLine, copiedBg, shine
local function scan(f, seen)
	seen = seen or {}
	if seen[f] then return end
	seen[f] = true
	for _, r in ipairs(rawget(f, "regions") or {}) do
		if r.atlas == "UI-QuestTracker-Header-Line" and r ~= line then copiedLine = r end
		if r.atlas == "UI-QuestTracker-Primary-Objective-Header" and r ~= bg then copiedBg = r end
		if r.atlas == "shine" and r ~= quests.Shine then shine = r end
	end
end
local header
-- the header is reachable through the card's layout function's upvalues
local i = 1
while true do
	local n, v = debug.getupvalue(api.layoutDungeonCard, i)
	if not n then break end
	if n == "header" then header = v end
	i = i + 1
end
scan(header)
check("the line under Quests copied (its atlas)", copiedLine ~= nil)
check("its own place: BOTTOM of the Dungeon header, 2 px under", copiedLine and copiedLine.points[1][1] == "BOTTOM"
	and copiedLine.points[1][2] == header and copiedLine.points[1][5] == -2)
check("its own size (260 x 3), not stretched", copiedLine and copiedLine.w == 260 and copiedLine.h == 3)
check("its colour and opacity", copiedLine and copiedLine.vc[2] == 0.8 and copiedLine.alpha == 0.7)
check("its layer", copiedLine and copiedLine.layer == "ARTWORK")
check("the background with its two points, moved to the Dungeon header", copiedBg and #copiedBg.points == 2
	and copiedBg.points[1][2] == header and copiedBg.points[1][4] == -20 and copiedBg.points[2][1] == "BOTTOMRIGHT")
check("not the Shine flash", shine == nil)
check("the Quests header's width and height", header.w == 240 and header.h == 30)
check("its left edge (4 px right of the tracker's)", header.points[1][1] == "TOPLEFT" and header.points[1][4] == 4)
print(pass and "PASS" or "FAILED")
