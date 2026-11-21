-- Distance and direction after quest titles: "120 yds" and a gold arrow turned towards the quest (ZoneSort.lua
-- api.playerWorldPos / api.questDirection; Extras.lua attachDistance / refreshDistances).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end

-- ZoneSort: where the player and the quest are (world yards; x runs north, y west)
local maps = { [1] = { name = "Kalimdor" }, [71] = { name = "Tanaris", parentMapID = 1 } }
_G.C_Map = {
	GetBestMapForUnit = function() return 71 end,
	GetMapInfo = function(id) return maps[id] end,
	GetMapChildrenInfo = function() return {} end,
	-- map 71: x 0..1 -> world north 1000..0, y 0..1 -> world west 1000..0
	GetWorldPosFromMapPos = function(_, v) return 1, { x = 1000 - v.y * 1000, y = 1000 - v.x * 1000 } end,
	GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end, -- world (500, 500)
}
_G.CreateVector2D = function(x, y) return { x = x, y = y } end
_G.IsInInstance = function() return false end
_G.GetTime = function() return 0 end
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
_G.hooksecurefunc = function() end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local waypoint
_G.C_QuestLog = { GetNextWaypoint = function() if waypoint then return 71, waypoint[1], waypoint[2] end end }
local api = {}
local ns = { api = api, onLogin = {}, db = { zoneSort = true, enabled = true } }
assert(loadfile(dir .. "/Tracker/ZoneSort.lua"))("x", { tracker = ns })

local me = api.playerWorldPos()
check("the player's world position", me and me.continent == 1 and near(me.x, 500) and near(me.y, 500))
waypoint = { 0.5, 0.38 } -- 120 yards north
local yards, angle = api.questDirection(5, me)
check("120 yards to the quest's waypoint", near(yards, 120))
check("north: angle 0", near(angle, 0))
waypoint = { 0.38, 0.5 } -- 120 yards west
yards, angle = api.questDirection(5, me)
check("west: a quarter turn left (as GetPlayerFacing counts)", near(angle, math.pi / 2))
-- Questie's nearest spawn comes first
api.questiePoints = function() return { { 440, 50, 30 }, { 440, 50, 90 } } end
api.questieUiMap = function() return 71 end
yards = api.questDirection(5, me)
check("Questie's nearest spawn, not the waypoint", near(yards, 200))
api.questiePoints = nil
waypoint = nil
-- R106-40: the last place is kept 60 s, so this is read after that
_G.GetTime = function() return 61 end
check("nowhere known (for over 60 s): nothing", api.questDirection(5, me) == nil)
_G.GetTime = function() return 0 end
-- R106-15: a quest in this zone without Questie: its marker on the player's map (the game's next waypoint is only for
-- quests in another zone), so the arrow has a direction
_G.C_QuestLog.GetQuestsOnMap = function(map) return map == 71 and { { questID = 5, x = 0.62, y = 0.5 } } or {} end
local here = api.playerWorldPos()
yards, angle = api.questDirection(5, here)
check("the quest's map marker: 120 yards east, an arrow (a quarter turn right)", near(yards, 120) and near(angle, -math.pi / 2))
_G.C_QuestLog.GetQuestsOnMap = nil
_G.C_QuestLog.GetNextWaypointForMap = function(id, map) if id == 5 and map == 71 then return 0.5, 0.62 end end
yards, angle = api.questDirection(5, api.playerWorldPos())
check("else the game's waypoint on this map (120 yards south)", near(yards, 120) and near(math.abs(angle), math.pi))
_G.C_QuestLog.GetNextWaypointForMap = nil
_G.IsInInstance = function() return true, "party" end
_G.GetInstanceInfo = function() return "Zul'Farrak" end
check("inside an instance: no position", api.playerWorldPos() == nil)
_G.IsInInstance = function() return false end
_G.C_Map.GetPlayerMapPosition = function() return nil end
check("no map position: no guess", api.playerWorldPos() == nil)

-- Extras: the text and the arrow
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local DIST_GAP, DIST_ARROW_GAP = 2, 3\n.-\napi%.refreshQuestDistances = refreshDistances\n)")
check("distance code found in Extras.lua", body ~= nil)
local function region()
	local r = { shown = false, points = {} }
	for _, k in ipairs({ "SetJustifyH", "SetShadowOffset", "SetShadowColor", "SetTextColor", "SetFont" }) do
		r[k] = function() end
	end
	function r:SetSize(w, h) self.w, self.h = w, h end
	function r:SetAlpha(a) self.alpha = a end
	function r:SetTexture(t) self.texture = t end
	function r:SetText(t) self.text = t end
	function r:GetStringWidth() return 40 end
	function r:GetLeft() return self.left end
	function r:IsVisible() return true end
	function r:ClearAllPoints() self.points = {} end
	function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function r:SetRotation(a) self.usedSetRotation = true end
	function r:SetTexCoord(...) self.coords = { ... } end
	function r:Show() self.shown = true end
	function r:Hide() self.shown = false end
	return r
end
local parent = { CreateFontString = function() return region() end, CreateTexture = function() return region() end }
local facing = 0
local db = { questDistance = true }
local where = {}
local env = setmetatable({ db = db, api = { playerWorldPos = function() return { continent = 1, x = 0, y = 0 } end,
	questDirection = function(id) local w = where[id]; if w then return w[1], w[2] end end },
	ADDON = "RXPForeverTracker", isSecret = function() return false end,
	UIParent = { CreateFontString = function() return region() end }, GetPlayerFacing = function() return facing end },
	{ __index = _G })
local relayouts = 0
env.api.applyExtras = function() relayouts = relayouts + 1 end
env.questIDOf = function(block) return block.questID end
local chunk = load(body .. "\nreturn attachDistance, refreshDistances, distanceText, distanceReserve", "x", "t", env)
local attach, refresh, text, reserve = chunk()
check("yards as \"120 yds\"", text(120.4) == "120 yds" and text(1530) == "1.5k yds")
-- R106-60: the yards above the arrow: the room is the wider of the two and the gap
check("room kept: the widest yards (wider than the arrow) and the gap", reserve("font", 12, "") == 40 + 2)

local fs = region()
function fs:GetParent() return parent end
function fs:GetFont() return "font", 12, "" end
function fs:IsVisible() return true end
fs.qtsReserve = reserve("font", 12, "")
where[77] = { 120, math.pi / 2 }
attach(fs, 77)
local w = fs.qtsDistance
check("the gold arrow texture", w.arrow.texture:find("Textures\\DirArrow", 1, true) ~= nil)
check("the yards at the title's right edge, the arrow under them", w.text.points[1][1] == "TOPRIGHT"
	and w.text.points[1][4] == fs.qtsReserve - 2 and w.arrow.points[1][1] == "TOP" and w.arrow.points[1][2] == w.text
	and w.arrow.points[1][3] == "BOTTOM" and w.arrow.points[1][5] == -1)
refresh(true)
check("shows \"120 yds\"", w.text.shown and w.text.text == "120 yds")
check("facing north, quest west: the arrow turned a quarter left", w.arrow.shown and near(w.arrow.qtsAngle, math.pi / 2))
facing = math.pi / 2
refresh(false)
check("turned to face it: the arrow points ahead", near(w.arrow.qtsAngle, 0))
facing = nil
refresh(false)
check("no facing (restricted): the arrow points the map's way (north up)", w.text.shown and w.arrow.shown and near(w.arrow.qtsAngle, math.pi / 2))
facing = 0
where[77] = { 300, nil }
refresh(true)
check("only the game's distance: no arrow", w.text.text == "300 yds" and not w.arrow.shown)
where[77] = nil
refresh(true)
check("unknown: nothing", not w.text.shown and not w.arrow.shown)
db.questDistance = false
attach(fs, 77)
check("switched off: hidden", not w.text.shown and not w.arrow.shown)

-- R106-55: on a tracked quest the yards are placed from the quest's right edge, so a title that kept its full width
-- (Blizzard anchors it on both sides) does not push them past the tracker's edge
db.questDistance = true
local fs5 = region()
function fs5:GetParent() return parent end
function fs5:GetFont() return "font", 12, "" end
function fs5:IsVisible() return true end
fs5.left = 100
fs5.qtsReserve = reserve("font", 12, "")
local block5 = { GetRight = function() return 400 end }
attach(fs5, 77, block5)
local p5 = fs5.qtsDistance.text.points[1]
check("from the quest's right edge: 300 - 4 from the title's left", p5[1] == "TOPRIGHT" and p5[2] == fs5
	and p5[3] == "TOPLEFT" and p5[4] == 296)
local fs6 = region()
function fs6:GetParent() return parent end
function fs6:GetFont() return "font", 12, "" end
function fs6:IsVisible() return true end
fs6.qtsReserve = reserve("font", 12, "")
attach(fs6, 77, block5) -- no position yet
check("no position yet: after the title for now", fs6.qtsDistance.text.points[1][3] == "TOPRIGHT")
fs6.left = 100
where[77] = { 120, 0 }
refresh(true)
check("placed from the quest's edge once it has a position", fs6.qtsDistance.text.points[1][3] == "TOPLEFT")
-- done with these two titles: no longer watched (the checks below count re-layouts)
db.questDistance = false
attach(fs5, 77); attach(fs6, 77)
where[77] = nil

local more = io.open(dir .. "/Tracker/MoreQuests.lua"):read("a")
check("More quests titles show it too", more:find("api.attachQuestDistance(fs, quest.id)", 1, true) ~= nil)
local f = io.open(dir .. "/Textures/DirArrow.tga", "rb")
check("Textures/DirArrow.tga exists (64x64)", f and f:read(18):byte(13) == 64)
if f then f:close() end

-- R106-14: the room only on titles of quests that show a distance; set before Blizzard measures the title
db.questDistance = true
local title = { HeaderText = fs, questID = 77 }
where[77] = { 120, 0 }
check("a quest with a distance: the title keeps the room", env.api.titleReserve(title) == reserve("font", 12, ""))
where[77] = nil
check("a quest without one: no room (the title keeps its full width)", env.api.titleReserve(title) == nil)
local fs2 = region()
function fs2:GetParent() return parent end
function fs2:GetFont() return "font", 12, "" end
function fs2:IsVisible() return true end
fs2.qtsBlock = title
attach(fs2, 88) -- no room yet
refresh(true)
check("no room: watched, nothing drawn", not fs2.qtsDistance.text.shown and not fs2.qtsDistance.arrow.shown)
where[88] = { 50, 0 }
_G.GetTime = function() return 10 end
refresh(true)
check("its distance appears: the title is laid out again (to get the room)", relayouts == 1
	and not fs2.qtsDistance.text.shown)
refresh(true)
check("at most every 2 s", relayouts == 1)
check("the title's SetText hook sets the room before the width (before Blizzard measures it)",
	src:find("if api.titleReserve then block.HeaderText.qtsReserve, block.HeaderText.qtsYardsW = api.titleReserve(block) end\n\t\tlocal width = block.HeaderText:GetWidth()\n\t\tprepareText(block.HeaderText, block)", 1, true) ~= nil)
check("More quests keeps the room only for quests with a distance",
	more:find("api.questHasDistance(quest.id)", 1, true) ~= nil)

-- R106-17: the arrow file cannot be loaded (added since the game started): the game's minimap arrow instead
local parent3 = { CreateFontString = function() return region() end, CreateTexture = function()
	local t = region()
	function t:SetTexture(path) self.texture = path; return not path:find("DirArrow", 1, true) end
	return t
end }
local fs3 = region()
function fs3:GetParent() return parent3 end
function fs3:GetFont() return "font", 12, "" end
db.questDistance = true
attach(fs3, 99)
check("DirArrow.tga not found: the game's minimap arrow", fs3.qtsDistance.arrow.texture == [[Interface\Minimap\MinimapArrow]]
	and fs3.qtsDistance.arrowFallback)

-- R106-18: the arrow is turned by its texture coordinates, never SetRotation (it left the arrow blank in Forever)
check("never SetRotation", not w.arrow.usedSetRotation)
local turn = load(body .. "\nreturn turnTexture", "x", "t", env)()
local t = region()
turn(t, 0)
local c0 = t.coords
check("not turned: the whole image, upright", near(c0[1], 0) and near(c0[2], 0) and near(c0[3], 0) and near(c0[4], 1)
	and near(c0[5], 1) and near(c0[6], 0) and near(c0[7], 1) and near(c0[8], 1))
turn(t, math.pi / 2)
local c = t.coords
-- a quarter turn left: the quad's top-left shows the image's top-right, its bottom-left the image's top-left
check("a quarter turn left: the tip points left", near(c[1], 1) and near(c[2], 0) and near(c[3], 0) and near(c[4], 0)
	and near(c[5], 1) and near(c[6], 1) and near(c[7], 0) and near(c[8], 1))

-- R106-20: "Arrow size" and "Arrow opacity" sliders
local fs4 = region()
function fs4:GetParent() return parent end
function fs4:GetFont() return "font", 12, "" end
db.questDistance = true
fs4.qtsReserve = reserve("font", 12, "")
attach(fs4, 77)
check("100 %: the arrow is the title's font size, fully opaque", fs4.qtsDistance.arrow.w == 12 and fs4.qtsDistance.arrow.alpha == 1)
db.distArrowScale, db.distArrowAlpha = 1.5, 0.4
check("150 %: the title's room does not change", reserve("font", 12, "") == 40 + 2)
fs4.qtsReserve = reserve("font", 12, "")
attach(fs4, 77)
check("150 %, 40 % opacity: the arrow drawn 18 px and see-through", fs4.qtsDistance.arrow.w == 18
	and fs4.qtsDistance.arrow.h == 18 and math.abs(fs4.qtsDistance.arrow.alpha - 0.4) < 1e-9)
check("150 %: the yards stay where they were; the arrow grows downwards under them",
	fs4.qtsDistance.text.points[1][4] == fs4.qtsReserve - 2 and fs4.qtsDistance.arrow.points[1][1] == "TOP"
	and fs4.qtsDistance.arrow.points[1][2] == fs4.qtsDistance.text)
db.distArrowScale, db.distArrowAlpha = 5, 0
attach(fs4, 77)
check("kept within 50-200 % and 10-100 %", fs4.qtsDistance.arrow.w == 24 and math.abs(fs4.qtsDistance.arrow.alpha - 0.1) < 1e-9)
db.distArrowScale, db.distArrowAlpha = nil, nil
local cfg = io.open(dir .. "/Tracker/Config.lua"):read("a")
check("/qt sliders: Arrow size 50-200 %, Arrow opacity 10-100 %", cfg:find('percent("Arrow size", 50, 200', 1, true) ~= nil
	and cfg:find('percent("Arrow opacity", 10, 100', 1, true) ~= nil)

-- R106-63: "Show distance" and "Show arrow"
db.questDistance = true
local fs7 = region()
function fs7:GetParent() return parent end
function fs7:GetFont() return "font", 12, "" end
function fs7:IsVisible() return true end
where[79] = { 120, 0 }
db.distanceText = false
check("distance hidden: the room is the arrow and the gap", reserve("font", 12, "") == 12 + 2)
fs7.qtsReserve = reserve("font", 12, "")
attach(fs7, 79)
refresh(true)
check("distance hidden: no yards, the arrow shown in their place", not fs7.qtsDistance.text.shown
	and fs7.qtsDistance.arrow.shown and fs7.qtsDistance.arrow.points[1][1] == "TOPRIGHT")
db.distanceText, db.distanceArrow = true, false
check("arrow hidden: the room is the yards and the gap", reserve("font", 12, "") == 40 + 2)
fs7.qtsReserve = reserve("font", 12, "")
attach(fs7, 79)
refresh(true)
check("arrow hidden: the yards, no arrow", fs7.qtsDistance.text.shown and not fs7.qtsDistance.arrow.shown)
db.distanceText = false
check("both hidden: no room kept on the title", env.api.titleReserve({ HeaderText = fs7, questID = 79 }) == nil)
db.distanceText, db.distanceArrow = nil, nil
check("the two options in Quest titles", cfg:find('check("Show distance"', 1, true) ~= nil
	and cfg:find('check("Show arrow"', 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
