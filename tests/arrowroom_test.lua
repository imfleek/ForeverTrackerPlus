-- R106-65: objective lines level with the distance column (yards and arrow under them) leave its room; lines below it
-- keep their full width
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local function squeezeTitle.-)\n%-%- Progress on objectives")
check("prepareText found", body ~= nil)
local env = setmetatable({ db = { wordWrap = true }, api = { distanceColumnHeight = function() return 11 + 12 end, distanceArrowShown = function() return true end,
	distanceYardsShown = function() return true end,
	distanceArrowSize = function(sz) return sz end },
	hooksecurefunc = function() end }, { __index = _G })
local prepareText = load(body:gsub("^", "local prepareText\n") .. "\nreturn prepareText", "p", "t", env)()
local function text(top, left)
	local f = { top = top, left = left, width = 0 }
	function f:GetTop() return self.top end
	function f:GetLeft() return self.left end
	function f:GetWidth() return self.width end
	function f:SetWidth(w) self.width = w end
	function f:GetNumPoints() return 1 end
	function f:GetFont() return "font", 12, "" end
	function f:CanWordWrap() return true end
	function f:SetWordWrap() end
	function f:SetMaxLines() end
	return f
end
local title = text(500, 100)
title.qtsReserve, title.qtsDistance = 46, {}
local block = { HeaderText = title, GetRight = function() return 400 end }
local first, second = text(486, 110), text(460, 110)
prepareText(first, block)
prepareText(second, block)
check("the first objective (14 below the title, the column reaches 23): leaves the room (290 - 4 - 46)", first.width == 240)
check("the next objective (40 below): its full width (290 - 4)", second.width == 286)
title.qtsReserve = nil
prepareText(first, block)
check("no distance on the title: the first objective gets its full width back", first.width == 286)
-- an objective line anchored on both sides (SetWidth does nothing): its right anchor moves in by the room
local both = text(486, 110)
both.points = { { "TOPLEFT", "line", "TOPLEFT", 0, 0 }, { "RIGHT", "line", "RIGHT", -2, 0 } }
function both:GetNumPoints() return #self.points end
function both:GetPoint(i) return table.unpack(self.points[i]) end
function both:SetPoint(p, rel, rp, x, y)
	for _, a in ipairs(self.points) do if a[1] == p then a[2], a[3], a[4], a[5] = rel, rp, x, y end end
end
function both:GetParent() return "line" end
function both:ClearAllPoints() end
title.qtsReserve = 46
prepareText(both, block)
check("both sides anchored: the right anchor moved in by the room (-2 - 46)", both.points[2][4] == -48)
title.qtsReserve = nil
prepareText(both, block)
check("both sides anchored, no distance: Blizzard's right anchor back", both.points[2][4] == -2)
-- R106-81: a progress bar at its right (room 72) and the distance beside it (46): the text stops before the wider
both.qtsReserve = 72
title.qtsReserve = 46
prepareText(both, block)
check("both sides anchored, a bar and the distance: the wider room (-2 - 72)", both.points[2][4] == -74)
both.qtsReserve = nil
title.qtsReserve = nil
prepareText(both, block)
check("both sides anchored, the bar gone: Blizzard's right anchor back", both.points[2][4] == -2)
local single = text(486, 110)
single.qtsReserve = 72
title.qtsReserve = 46
prepareText(single, block)
check("one anchor, a bar and the distance: the wider room (290 - 4 - 72), not both added", single.width == 214)
title.qtsReserve = nil
-- R106-66: with a place, the arrow's real bottom decides (the user's Felwood quest: a line starting under it)
local arrow = { GetBottom = function() return 470 end }
title.qtsReserve, title.qtsDistance = 46, { arrow = arrow, text = arrow }
local under, beside = text(466, 110), text(480, 110)
prepareText(under, block); prepareText(beside, block)
check("a line starting under the arrow's bottom: full width", under.width == 286)
check("a line starting beside the arrow: leaves the room", beside.width == 240)
-- R106-67: the letters start below the line's top: a line 2 px above the arrow's bottom is under it
local touching = text(472, 110)
prepareText(touching, block)
check("a line whose letters start below the arrow: full width", touching.width == 286)
-- R106-69: a line beside the arrow but below the yards leaves only the arrow's room (half the widest yards + half
-- the art + 3: 40/2 + 12*0.84/2 + 3 = 28.04 -> 29), not the yards' 46
title.qtsYardsW = 40
title.qtsDistance.text = { GetBottom = function() return 488 end }
local besideArrow = text(484, 110)
prepareText(besideArrow, block)
check("beside the arrow, below the yards: the arrow's room only (290 - 4 - 29)", besideArrow.width == 257)
local besideYards = text(492, 110)
prepareText(besideYards, block)
check("beside the yards: the whole room (290 - 4 - 46)", besideYards.width == 240)
-- with places: the real arrow (square 380..400, centre 390) under yards 30 wide (the widest 40: centre 385), yards
-- end at 400: art left 385 - 10*0.84 = 376.6 -> room 400 - 376.6 + 3 = 26.4 -> 27
arrow.GetLeft = function() return 380 end
arrow.GetRight = function() return 400 end
title.qtsDistance.text.GetRight = function() return 400 end
title.qtsDistance.text.GetWidth = function() return 30 end
local placed = text(484, 110)
prepareText(placed, block)
check("beside the arrow, real places: room from the arrow's art at the widest yards (290 - 4 - 27)", placed.width == 259)
check("the 0.1 s pass lays out again when a line's room changes",
	src:find("if fs ~= block.HeaderText and math.abs((fs:GetWidth() or 0) - (width or 0)) > 1 and fs.qtsDistRoom ~= nil then", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
