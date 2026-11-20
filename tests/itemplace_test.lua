-- R106-52: quest item buttons sit left of the objectives (under the title), so the title's left is free for the
-- Icon Classifications
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local placingItem = false\n.-\nlocal function placeItem%(block%).-\n	return false\nend)")
check("the item placement code found", body ~= nil)
if not body then print("FAILED") return end
local function item()
	local f = { points = {}, shown = true }
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function f:GetNumPoints() return #self.points end
	function f:GetPoint(i) return table.unpack(self.points[i]) end
	function f:IsShown() return self.shown end
	function f:GetScale() return self.scale or 1 end
	function f:SetScale(v) self.scale = v; self.scaled = (self.scaled or 0) + 1 end
	return f
end
local hooks = {}
local env = setmetatable({ api = { itemSide = function() return "left" end },
	InCombatLockdown = function() return false end,
	hooksecurefunc = function(t, name, fn) hooks[#hooks + 1] = { t, name, fn } end,
	itemButtonOf = function(block) return block.ItemButton end }, { __index = _G })
local placeItem = load(body .. "\nreturn placeItem", "i", "t", env)()
local title = {}
local button = item()
local block = { HeaderText = title, ItemButton = button }
placeItem(block)
local p = button.points[1]
check("the button's top right at the title's bottom left: beside the objectives", #button.points == 1
	and p[1] == "TOPRIGHT" and p[2] == title and p[3] == "BOTTOMLEFT" and p[4] == -4 and p[5] == -1)
-- Blizzard puts it back at the right on its next layout: moved back at once (the SetPoint hook)
button:ClearAllPoints()
button:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
for _, h in ipairs(hooks) do if h[1] == button and h[2] == "SetPoint" then h[3](button) end end
check("Blizzard's own place undone at once: under the title again", button.points[1][2] == title)
local before = #button.points
placeItem(block)
check("already in place: left alone (no re-anchoring every update)", #button.points == before)
-- R106-53: 12.5 % smaller
check("the button 12.5 % smaller (scale 0.875)", button.scale == 0.875)
placeItem(block)
check("scaled once, not on every update", button.scaled == 1)
print(pass and "PASS" or "FAILED")
