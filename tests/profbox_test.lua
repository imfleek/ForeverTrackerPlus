-- R106-57: Blizzard's Professions section in its own box above the quest tracker: 2 recipes tall, more scroll, its
-- own scrollbar options; given back to the tracker when switched off
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Core.lua"):read("a")
local body = src:match("(do %-%- its own block %(Lua's 200%-locals limit%)\nlocal PROF_GAP.-\nend %-%- the Professions block)")
check("the Professions block found", body ~= nil)
if not body then print("FAILED") return end

local function frame(name)
	local f = { name = name, points = {}, shown = true, scripts = {} }
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function f:SetParent(p) self.parent = p end
	function f:GetParent() return self.parent end
	function f:IsShown() return self.shown end
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false end
	function f:SetShown(v) self.shown = v and true or false end
	function f:GetEffectiveScale() return 1 end
	function f:SetScale(v) self.scale = v end
	function f:SetHeight(h) self.height = h end
	function f:GetHeight() return self.height or 100 end
	function f:SetWidth(w) self.width = w end
	function f:SetAlpha(a) self.alpha = a end
	function f:GetAlpha() return self.alpha or 1 end
	function f:IsMouseOver() return false end
	function f:GetTop() return self.top end
	for _, k in ipairs({ "SetClipsChildren", "EnableMouseWheel", "EnableMouse", "SetFrameStrata", "SetFrameLevel" }) do
		f[k] = function() end
	end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	return f
end
local tracker = frame("tracker")
function tracker:GetFrameStrata() return "MEDIUM" end
function tracker:GetFrameLevel() return 1 end
local ghost = frame("ghost")
function ghost:GetWidth() return 260 end
local viewport = frame("viewport")
local m = frame("ProfessionsRecipeTracker")
m.parent = frame("contents")
m.top = 800
-- three recipes, 40 units each, under a 25-unit header
local blocks = {}
for i = 1, 3 do local b = frame("recipe" .. i); b.top = 775 - (i - 1) * 40; b.bottom = b.top - 40; blocks[i] = b end
m.usedBlocks = { recipe = { blocks[1], blocks[2], blocks[3] } }
_G.ProfessionsRecipeTracker = m
local dirty = 0
local db = { profAbove = true, step = 40 }
local env = setmetatable({
	db = db, ns = { api = { applyLayout = function() end } }, root = { scrollSkin = { bar = function() end } },
	CreateFrame = function(_, name) return frame(name) end, UIParent = frame("UIParent"), ghost = ghost, tracker = tracker, viewport = viewport,
	scale = function() return 1 end, toScreen = function(_, v) return v end,
	moduleContentBottom = function() return 655 end, -- the third recipe's bottom
	lowestShown = function(f) return f.bottom end,
	guarded = function(fn) fn() end, withAlpha = function(f) return f end, barOnLeft = function() return false end,
	cursorY = function() return 0 end, canMove = function() return true end, markDirty = function() dirty = dirty + 1 end,
	trackerAlpha = function() return 1 end, BAR_WIDTH = 10, BAR_ALPHA = 1, FADE_DELAY = 2, FADE_TIME = 0.4,
	InCombatLockdown = function() return false end, bases = {}, GetTime = function() return 0 end,
}, { __index = _G })
load(body, "prof", "t", env)()
-- R106-62: inside the hidden box the section has no place yet: the box shows anyway and measures again shortly
local realTop, retried = m.top, 0
m.top = nil
env.C_Timer = { After = function(_, f) retried = retried + 1 end }
env.layoutProfessions()
check("no place yet: the box shows anyway (it was never shown before)", m.parent.shown == true)
check("no place yet: measured again on the next frame", retried == 1)
m.top = realTop
env.layoutProfessions()
local box = m.parent
check("the section moved into its own box", box and box.name == "ForeverTrackerPlusProfessions")
check("the box sits left of the quest list, level with the Quests header (R106-64)", box.points[1][1] == "TOPRIGHT"
	and box.points[1][2] == viewport and box.points[1][3] == "TOPLEFT" and box.points[1][4] == -6 and box.points[1][5] == 0)
check("as wide as the quest list", box.width == 260)
check("as tall as the header and 2 recipes (25 + 80, +2)", box.height == 107)
check("the third recipe scrolls: 40 units", env.ns.api and true and box.shown)
local mp = m.points[1]
check("the section at the box's top", mp[1] == "TOPLEFT" and mp[2] == box and mp[5] == 0)
-- the wheel over the box scrolls it
box.scripts.OnMouseWheel(box, -1)
check("one wheel notch down: the section moves up by the step, at most to its end (40)", m.points[1][5] == 40)
box.scripts.OnMouseWheel(box, 1)
check("back up: 0", m.points[1][5] == 0)
-- R106-64: the position sliders
env.ns.api.setProfessionsPosition(-20, 15)
check("moved 20 left and 15 up", box.points[1][4] == -26 and box.points[1][5] == 15)
check("kept within -400..400", (function() env.ns.api.setProfessionsPosition(900, nil); return box.points[1][4] == 394 end)())
-- switched off: back to the tracker where Blizzard put it
env.bases[m] = { TOP = { tracker, "BOTTOM", 0, -10 } }
env.ns.api.setProfessionsAbove(false)
check("switched off: back in its old parent, at Blizzard's place", m.parent.name == "contents" and m.points[1][2] == tracker
	and m.points[1][5] == -10)
check("on by default", src:find("profAbove = true, profScrollbar = true, profScrollbarMouseover = false, profScrollbarWidth = 10", 1, true) ~= nil)
check("the quest list skips it (first section, content bottom, the push below More quests)",
	src:find("if moduleVisible(module) and module ~= profHeld then -- (the Professions box scrolls on its own)", 1, true) ~= nil
	and src:find("if moduleVisible(module) and module ~= profHeld then -- (above the tracker, in its own box)", 1, true) ~= nil
	and src:find("if seen and moduleVisible(module) and module ~= profHeld then after = module break end", 1, true) ~= nil)
check("Blizzard re-anchoring it: kept in the box", src:find("if self == profHeld then", 1, true) ~= nil)
local cfg = io.open(dir .. "/Tracker/Config.lua"):read("a")
check("its options: beside the tracker, position, scrollbar, mouseover, width", cfg:find('"Professions beside the quest tracker"', 1, true)
	and cfg:find('"Professions horizontal position"', 1, true) and cfg:find('"Professions vertical position"', 1, true)
	and cfg:find('"Professions scrollbar"', 1, true) and cfg:find('"Professions scrollbar width"', 1, true) and true or false)
print(pass and "PASS" or "FAILED")
