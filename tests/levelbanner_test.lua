-- 3.2 (user): the level-up banner (Tracker/LevelBanner.lua)
local root = arg[1] or ".."
local fails = 0
local function check(name, ok) print((ok and "ok   " or "FAIL ") .. name); if not ok then fails = fails + 1 end end
local function obj()
	local o = { shown = false, alpha = 1, scale = 1, text = "", points = {} }
	return setmetatable(o, { __index = function(t, k)
		if k == "CreateTexture" or k == "CreateFontString" then return function(self) return obj() end end
		if k == "SetText" then return function(self, v) self.text = v end end
		if k == "Show" then return function(self) self.shown = true end end
		if k == "Hide" then return function(self) self.shown = false end end
		if k == "SetAlpha" then return function(self, v) self.alpha = v end end
		if k == "SetScale" then return function(self, v) self.scale = v end end
		if k == "SetScript" then return function(self, n, f) self[n] = f end end
		if k == "SetPoint" then return function(self, ...) self.points[#self.points + 1] = { ... } end end
		if k == "GetTop" then return function() return 768 end end
		if k == "GetCenter" then return function() return 512, 600 end end
		if k == "GetEffectiveScale" then return function() return 1 end end
		if k == "GetFrameLevel" then return function() return 1 end end
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
local env = setmetatable({ CreateFrame = function() return obj() end, UIParent = obj(), StaticPopup1 = obj() }, { __index = _G })
local db = {}
local ns = { api = {}, db = db }
assert(loadfile(root .. "/Tracker/LevelBanner.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
local api = ns.api
api.showLevelBanner(23, "Level 22 took 1h 2m")
local b = api.levelBanner()
check("shown", b and b.shown)
check("level in the diamond", b.level.text == "23")
check("title", b.title.text == "LEVEL 23")
check("sub line", b.sub.text == "Level 22 took 1h 2m")
check("placed at the popup's height, on UIParent (not anchored to it)", b.points[1][2] == env.UIParent and b.points[1][1] == "TOP")
check("starts small and faded", b.seal.alpha == 0)
b.OnUpdate(b, 0.5)
check("comes in", b.seal.alpha > 0.5 and b.title.alpha > 0)
b.OnUpdate(b, 7)
check("goes away", not b.shown)
db.levelBanner = false
b.shown = false
api.showLevelBanner(24)
check("off: not shown", not b.shown)
if fails > 0 then print("SOME FAILED") else print("ALL OK") end
