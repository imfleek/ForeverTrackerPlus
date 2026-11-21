-- R106-59: a title anchored on both sides keeps the room for the distance: its right-side anchors move in by it
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local function squeezeTitle%(fs, room%).-\nend\n)")
check("squeezeTitle found", body ~= nil)
local hooks = {}
local env = setmetatable({ hooksecurefunc = function(t, name, fn) hooks[name] = fn end }, { __index = _G })
local squeeze = load(body .. "\nreturn squeezeTitle", "s", "t", env)()
local block = {}
local fs = { points = {} }
function fs:GetNumPoints() return #self.points end
function fs:GetPoint(i) return table.unpack(self.points[i]) end
function fs:GetParent() return block end
function fs:SetPoint(p, rel, rp, x, y)
	for i, q in ipairs(self.points) do if q[1] == p then table.remove(self.points, i) break end end
	self.points[#self.points + 1] = { p, rel, rp, x, y }
	if hooks.SetPoint then hooks.SetPoint(self, p, rel, rp, x, y) end
end
local function at(p) for _, q in ipairs(fs.points) do if q[1] == p then return q end end end
fs:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
fs:SetPoint("TOPRIGHT", block, "TOPRIGHT", -2, 0)
squeeze(fs, 46)
check("the right anchor moved in by the room (-2 - 46)", at("TOPRIGHT")[4] == -48)
check("the left anchor untouched", at("TOPLEFT")[4] == 0)
-- Blizzard sets its own right anchor again: ours on top of it at once
fs:SetPoint("TOPRIGHT", block, "TOPRIGHT", -5, 0)
check("Blizzard's anchor set again: moved in at once (-5 - 46)", at("TOPRIGHT")[4] == -51)
squeeze(fs, 0)
check("no room (no distance): Blizzard's own anchor back", at("TOPRIGHT")[4] == -5)
-- R106-121: the item button moved to the left: its room (negative) widens the title again
fs:SetPoint("TOPRIGHT", block, "TOPRIGHT", -32, 0) -- Blizzard: the title ends before the item button (30 + 2)
squeeze(fs, -32)
check("item room given back: the right anchor at the block's edge again (-32 + 32)", at("TOPRIGHT")[4] == 0)
fs:SetPoint("TOPRIGHT", block, "TOPRIGHT", -32, 0)
check("Blizzard's anchor set again: widened at once", at("TOPRIGHT")[4] == 0)
squeeze(fs, 46 - 32)
check("distance room and item room together (-32 - 14)", at("TOPRIGHT")[4] == -46)
check("prepareText uses it for a title anchored on both sides, less the moved item's room",
	src:find("squeezeTitle(fs, (fs.qtsReserve or 0) - api.movedItemRoom(block))", 1, true) ~= nil)
-- the moved item's room: its width and 2 px, only when moved to the left and shown
local roomBody = src:match("(local ITEM_EDGE_SPACING = 2\nfunction api.movedItemRoom%(block%).-\nend\n)")
check("movedItemRoom found", roomBody ~= nil)
local api2 = {}
local item = { qtsSide = "left", shown = true }
function item:IsShown() return self.shown end
function item:GetWidth() return 26 end
local env2 = setmetatable({ api = api2, itemButtonOf = function(b) return b.item end }, { __index = _G })
load(roomBody, "r", "t", env2)()
check("moved left: 26 + 2", api2.movedItemRoom({ item = item }) == 28)
item.qtsSide = nil
check("still on the right: 0", api2.movedItemRoom({ item = item }) == 0)
item.qtsSide, item.shown = "left", false
check("hidden: 0", api2.movedItemRoom({ item = item }) == 0)
check("no item: 0", api2.movedItemRoom({}) == 0)
print(pass and "PASS" or "FAILED")
