-- R106-51: every Icon Classification drawn at the Forever W's visible size: dungeon and raid 10 % larger than their slot
-- (their art has more empty border), centred on the same slots
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local function placeTitleIcons%(fs, icons%).-\nend)")
check("placeTitleIcons found", body ~= nil)
local function tex()
	local t = { points = {} }
	function t:SetSize(w, h) self.w, self.h = w, h end
	function t:SetAlpha() end
	function t:ClearAllPoints() self.points = {} end
	function t:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function t:Show() end
	function t:Hide() end
	return t
end
local parent = { CreateTexture = function() return tex() end }
local fs = { GetParent = function() return parent end, GetFont = function() return "f", 12, "" end }
local env = setmetatable({ db = { iconScale = 1 }, SLOT = 14, ICON_GAP = 2, SLOT_GAP = 2,
	iconSize = function() return 14 end, applyIcon = function() end }, { __index = _G })
local place = load(body .. "\nreturn placeTitleIcons", "p", "t", env)()
place(fs, { { file = "ForeverW" }, { atlas = "Dungeon", scale = 1.32 } })
local w, d = fs.qtsIcons[1], fs.qtsIcons[2]
check("the Forever W at its slot size (14)", w.w == 14 and w.h == 14)
check("the dungeon icon 1.32x (18): 10 % to match the W, then 20 % larger (R106-61)", d.w == 18 and d.h == 18)
check("both centred on their slots (the spacing is unchanged)", w.points[1][1] == "CENTER" and d.points[1][1] == "CENTER"
	and d.points[1][4] - w.points[1][4] == 16)
check("dungeon and raid carry the scale", src:find('dungeon = { atlas = "Dungeon", file = "Interface\\\\Minimap\\\\Dungeon", scale = 1.32 }', 1, true) ~= nil
	and src:find('raid = { atlas = "Raid", file = "Interface\\\\Minimap\\\\Raid", scale = 1.32 }', 1, true) ~= nil)
place(fs, { { file = "Skull", scale = 0.85 } })
check("the skull 15 % smaller (12)", fs.qtsIcons[1].w == 12)
-- user: a Dungeon icon drawn cut and stretched (/qt icons: the PvP badge's crop 0.62 kept on a reused texture). A
-- client whose SetAtlas leaves the crop alone (an atlas that is a whole file): the crop is reset before it
do
	local applySrc = src:match("(local function applyIcon%(tex, desc%).-\nend)")
	check("applyIcon found", applySrc ~= nil)
	local aenv = setmetatable({ C_Texture = { GetAtlasInfo = function() return {} end } }, { __index = _G })
	local applyIcon = load(applySrc .. "\nreturn applyIcon", "a", "t", aenv)()
	local t = { coords = { 0, 1, 0, 1 } }
	function t:SetTexCoord(...) self.coords = { ... } end
	function t:SetAtlas(a) self.atlas = a end -- keeps the crop, as the game does for a whole-file atlas
	function t:SetTexture(f) self.file = f end
	applyIcon(t, { file = "UI-PVP-Horde", coords = { 0, 40 / 64, 0, 40 / 64 } })
	check("the PvP badge is cropped", t.coords[2] == 40 / 64)
	applyIcon(t, { atlas = "Dungeon", file = "Dungeon", scale = 1.32 })
	check("the next icon on that texture (an atlas) is not cropped", t.atlas == "Dungeon" and t.coords[2] == 1 and t.coords[4] == 1)
end
print(pass and "PASS" or "FAILED")
