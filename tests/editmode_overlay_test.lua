-- Unlocked tracker: an Edit Mode style overlay (yellow see-through panel with a yellow edge over the whole tracker,
-- "Objective Tracker" in the middle) replaces the green drag bar; the game's Edit Mode art when the client has it.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local src = io.open(dir .. "/Tracker/Core.lua"):read("a")
local body = src:match("(local EDIT_FILL, EDIT_EDGE = .-\nlocal function editModeArt%(frame%).-\n\treturn false\nend\n)")
check("Edit Mode art code found in Tracker/Core.lua", body ~= nil)

local function frame()
	local f = { textures = {} }
	function f:CreateTexture(_, layer)
		local t = { layer = layer, points = {} }
		function t:SetAllPoints() self.all = true end
		function t:SetPoint(p) self.points[#self.points + 1] = p end
		function t:SetWidth(v) self.w = v end
		function t:SetHeight(v) self.h = v end
		function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
		f.textures[#f.textures + 1] = t
		return t
	end
	return f
end

-- a client without the Edit Mode art: the same look in plain colours
local env = setmetatable({ C_Texture = { GetAtlasInfo = function() return nil end } }, { __index = _G })
local art = load(body .. "\nreturn editModeArt", "core", "t", env)()
local f = frame()
check("no Edit Mode art: drawn in plain colours", art(f) == false)
local fill = f.textures[1]
check("a see-through yellow panel over the whole tracker", fill.all and fill.color[1] == 1 and fill.color[2] > 0.7
	and fill.color[3] == 0 and fill.color[4] < 0.5)
local edges = 0
for i = 2, #f.textures do
	local c = f.textures[i].color
	if c and c[1] == 1 and c[2] > 0.7 and c[4] > 0.8 then edges = edges + 1 end
end
check("a yellow edge on all four sides", edges == 4)

-- a client with it: the game's own Edit Mode selection art
local applied
env.C_Texture = { GetAtlasInfo = function(name) return name:find("^editmode%-actionbar%-selected") and {} or nil end }
env.NineSliceUtil = { ApplyLayoutByName = function(fr, layout, kit) applied = { layout, kit }; fr.TopLeftCorner = {} end }
art = load(body .. "\nreturn editModeArt", "core", "t", env)()
local g = frame()
check("Edit Mode art: the game's selection nine-slice", art(g) == true and applied[1] == "EditModeSystemSelectionLayout"
	and applied[2] == "editmode-actionbar-selected" and #g.textures == 0)
-- the layout name exists but builds nothing (another client): plain colours instead
env.NineSliceUtil = { ApplyLayoutByName = function() end }
art = load(body .. "\nreturn editModeArt", "core", "t", env)()
local h = frame()
check("layout builds nothing: plain colours", art(h) == false and #h.textures == 5)

-- the overlay itself
check("covers the tracker (ghost), not a bar above it", src:find('handle:SetPoint("TOPLEFT", ghost, "TOPLEFT", -4, 4)', 1, true)
	and src:find('handle:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", 4, -4)', 1, true))
check("\"Objective Tracker\" in the middle", src:find('text:SetText("Objective Tracker")', 1, true) ~= nil)
check("right-click locks it", src:find('if button == "RightButton" then ns.api.setLocked(true) return end', 1, true) ~= nil)
check("the green bar is gone", src:find("bg:SetColorTexture(0.1, 0.6, 0.4, 0.85)", 1, true) == nil
	and src:find("Quest tracker - drag to move", 1, true) == nil)
print(pass and "PASS" or "FAILED")
