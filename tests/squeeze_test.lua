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
check("prepareText uses it for a title anchored on both sides",
	src:find("elseif fs == block.HeaderText and fs:GetNumPoints() > 1 then\n\t\tsqueezeTitle(fs, fs.qtsReserve or 0)", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
