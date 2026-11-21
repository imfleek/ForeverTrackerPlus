-- R106-90: the dungeon card puts DungeonJournal's rares among its bosses, in the journal's order, with a silver star
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Dungeon.lua"):read("a")
local body = src:match("(local PER_ROW, PORTRAIT, PORTRAIT_GAP = .-\nlocal function mergeRares%(t%).-\nend\n)\nlocal fdjHooked")
check("the merge found", body ~= nil)
if not body then print("FAILED") return end

local function region(name)
	local r = { name = name, points = {}, shown = true, w = 38, h = 38 }
	function r:ClearAllPoints() self.points = {} end
	function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function r:GetPoint(i) return table.unpack(self.points[i]) end
	function r:IsShown() return self.shown end
	function r:Show() self.shown = true end
	function r:Hide() self.shown = false end
	function r:SetSize(w, h) self.w, self.h = w, h end
	function r:GetWidth() return self.w end
	function r:GetHeight() return self.h end
	function r:SetHeight(h) self.h = h end
	function r:SetTexture(t) self.texture = t end
	function r:CreateTexture() return region("tex") end
	function r:SetAllPoints() end
	function r:SetFrameLevel(l) self.level = l end
	function r:GetFrameLevel() return self.level or 1 end
	function r:SetAlpha(a) self.alpha = a end
	return r
end
-- DungeonJournal's layout: four bosses in a row, then "Rare" and the rare in its own row under them
local t = region("tracker")
t.w, t.h = 236, 200
t.portraits = {}
local names = { "Rhahk'Zor", "Sneed", "Gilnid", "Van Cleef" }
for i, n in ipairs(names) do
	local f = region(n)
	f.boss = { name = n }
	f:SetPoint("TOPLEFT", t, "TOPLEFT", 11 + (i - 1) * 44, -78)
	t.portraits[i] = f
end
local rare = region("Miner Johnson")
rare.boss = { name = "Miner Johnson", rare = true }
rare.isRare = true
rare:SetPoint("TOPLEFT", t, "TOPLEFT", 11, -140)
t.portraits[5] = rare
t.raresLabel = region("label")
t.run = { dungeon = "The Deadmines" }
local placed = 0
local FDJ = {
	DB = { ["The Deadmines"] = { bosses = { { name = "Rhahk'Zor" }, { name = "Miner Johnson", rare = true }, { name = "Sneed" },
		{ name = "Gilnid" }, { name = "Van Cleef" } } } },
	RunLogPlaceOnScreen = function() placed = placed + 1 end,
}
local target = region("click")
target.portrait = t.portraits[1]
local env = setmetatable({ fdj = function() return FDJ end, FDJ_WIDTH = 236, ADDON = "RXPForeverTracker",
	InCombatLockdown = function() return false end,
	CreateFrame = function(_, _, parent) local f = region("frame"); f.parent = parent; return f end, ForeverDungeonJournalBossTarget1 = target }, { __index = _G })
env._G = env
local merge = load(body .. "\nreturn mergeRares", "m", "t", env)()
merge(t)
local function x(f) return f.points[1][4] end
local function y(f) return f.points[1][5] end
check("the rare second, as in the journal (after Rhahk'Zor, before Sneed)", x(t.portraits[1]) == 11 and x(rare) == 55
	and y(rare) == -78 and x(t.portraits[2]) == 99)
check("Van Cleef last on the row (5 a row)", x(t.portraits[4]) == 187 and y(t.portraits[4]) == -78)
check("a silver star on the rare only", rare.qtsStar and rare.qtsStar.shown and rare.qtsStar.tex.texture:find("SilverStar", 1, true)
	and rare.qtsStar.points[1][1] == "BOTTOMRIGHT" and t.portraits[1].qtsStar == nil)
-- R106-94: the star on its own frame on the window (not the portrait), so the faded portrait does not fade it
check("the star not faded with its portrait (own frame on the window, above the portrait)", rare.qtsStar.parent == t
	and rare.qtsStar.level > rare:GetFrameLevel())
check("no \"Rare\" row any more", t.raresLabel.shown == false)
check("the window's height: one row now (78 + 44 - 6 + 4; the Rare row gone)", t.h == 120)
check("its click areas put on the portraits again", placed == 1)
rare:Hide(); merge(t)
check("its portrait hidden: the star hidden", rare.qtsStar.shown == false)
print(pass and "PASS" or "FAILED")
