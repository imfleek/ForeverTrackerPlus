-- Progress bars on objectives: "Khaz Modan Iron: 26/30" shows as "Khaz Modan Iron" with a framed bar at the right edge
-- (the user's reference: dark navy box, blue fill, the count inside); finished objectives show it full (Extras.lua,
-- MoreQuests.lua).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local BAR_GAP = 6\n.-\napi%.placeProgress = placeProgress\n)")
check("progress code found in Extras.lua", body ~= nil)

local db = { progressBars = true }
local api = {}
local env = setmetatable({ db = db, api = api, applying = false, ADDON = "ForeverTrackerPlus", isSecret = function() return false end,
	hooksecurefunc = function(t, k, fn) local o = t[k]; t[k] = function(...) local r = o(...); fn(...); return r end end,
	CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end },
	{ __index = _G })
load(body, "extras", "t", env)()

-- the text formats
local function parts(t) return { api.progressParts(t) } end
local p = parts("Khaz Modan Iron: 26/30")
check("Classic \"Name: 26/30\"", p[1] == "Khaz Modan Iron" and p[2] == 26 and p[3] == 30)
p = parts("6/6 Khaz Modan Timber")
check("Retail \"6/6 Name\"", p[1] == "Khaz Modan Timber" and p[2] == 6 and p[3] == 6)
p = parts("|cffffffffSandfury slain: 2/8|r")
check("colour codes ignored", p[1] == "Sandfury slain" and p[2] == 2)
check("no count: nothing", api.progressParts("Speak with someone in Ratchet") == nil)
check("Ready for turn-in: nothing", api.progressParts("Ready for turn-in") == nil)
check("0/0 is no progress", api.progressParts("Thing: 0/0") == nil)

-- a fake objective line
local function region()
	local r = { points = {}, shown = false }
	function r:ClearAllPoints() self.points = {} end
	function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function r:SetHeight(h) self.h = h end
	function r:SetWidth(w) self.w = w end
	function r:SetSize(w, h) self.w, self.h = w, h end
	function r:SetTexture(t) self.texture = t end
	function r:SetTexCoord(...) self.coords = { ... } end
	function r:SetAlpha(a) self.alpha = a end
	function r:SetVertexColor() end
	function r:SetShadowOffset() end
	function r:SetShadowColor() end
	function r:SetColorTexture(...) self.color = { ... } end
	function r:Show() self.shown = true end
	function r:Hide() self.shown = false end
	function r:SetShown(v) self.shown = v and true or false end
	function r:SetFont() end
	function r:SetText(t) self.text = t end
	function r:SetTextColor(...) self.tc = { ... } end
	function r:GetStringWidth() return #(self.text or "") * 6 end
	return r
end
local line = { CreateFontString = function() return region() end, CreateTexture = function() return region() end }
local fs = region()
function fs:GetParent() return line end
function fs:GetText() return self.text end
function fs:GetFont() return "font", 12, "" end
function fs:GetTextColor() return 0.8, 0.8, 0.8, 1 end
function fs:GetWidth() return 200 end
function fs:GetLeft() return self.left end
fs.left = 10
local block = { HeaderText = region(), GetRight = function() return 260 end }
fs.qtsBlock = block

local decorate = load(body .. "\nreturn decorateObjective", "extras", "t", env)()
local place = load(body .. "\nreturn placeProgress", "extras", "t", env)()

fs.text = "Khaz Modan Iron: 26/30"
decorate(fs, block); place(fs)
local w = fs.qtsProgress
check("the line shows the name only", fs.text == "Khaz Modan Iron")
local bw, bh = api.progressBarSize(12)
check("room for the bar at the right edge", fs.qtsReserve == bw + 6)
check("the bar's box: the reference art, right of the text", w.bg.shown and w.bg.texture:find("Textures\\BarBG", 1, true)
	and w.bg.points[1][1] == "TOPLEFT" and w.bg.points[1][2] == fs and w.bg.points[1][3] == "TOPLEFT"
	and w.bg.w == bw and w.bg.h == bh)
check("placed from the quest's right edge, not after the text (Blizzard may keep the text wide)",
	w.bg.points[1][4] == (260 - 10) - 4 - bw)
check("the blue fill cropped to 26/30", w.fill.shown and w.fill.texture:find("Textures\\BarFill", 1, true)
	and math.abs(w.fill.w - (bw - 2 * 6 * bh / 32) * 26 / 30) < 0.01)
-- R106-76: three slices: the ends at the image's shape, only the middle stretched; the fill inside the border
check("the ends keep the image's shape (8 texels of 32 at the bar's height)", w.left.shown and w.right.shown
	and math.abs(w.left.w - 8 * bh / 32) < 1e-9 and w.left.h == bh and w.right.points[1][1] == "TOPRIGHT")
check("the fill starts inside the left border (6 texels)", math.abs(w.fill.points[1][4] - 6 * bh / 32) < 1e-9)
check("the bar 2 px taller than before (font 12: 17)", bh == 17)
check("the count inside it, white", w.text.shown and w.text.text == "26/30" and w.text.points[1][1] == "CENTER"
	and w.text.tc[1] == 1 and w.text.tc[2] == 1)

fs.text = "Khaz Modan Timber: 6/6"
decorate(fs, block); place(fs)
check("done (6/6): the bar full", w.text.text == "6/6" and w.fill.shown
	and math.abs(w.fill.w - (bw - 2 * 6 * bh / 32)) < 0.01)

fs.text = "Thing slain: 0/8"
decorate(fs, block); place(fs)
check("not started (0/8): the box, no fill", w.bg.shown and not w.fill.shown and w.text.text == "0/8")

-- our own shortened text set again (Blizzard re-sets it, a re-layout): the full text is kept
fs.text = "Thing slain"
decorate(fs, block); place(fs)
check("our shortened text again: still decorated", fs.qtsProgressName == "Thing slain" and w.bg.shown)

fs.text = "Speak with someone in Ratchet"
decorate(fs, block); place(fs)
check("a line without a count: no bar", not w.bg.shown and not w.text.shown and fs.qtsReserve == nil)

fs.text = "Khaz Modan Iron: 26/30"
decorate(fs, block)
db.progressBars = false
decorate(fs, block); place(fs)
check("switched off: the full text comes back", fs.text == "Khaz Modan Iron: 26/30" and not w.bg.shown)
db.progressBars = true

decorate(block.HeaderText, block)
check("never on the quest title", block.HeaderText.qtsProgress == nil)

local more = io.open(dir .. "/Tracker/MoreQuests.lua"):read("a")
check("More quests draws the same bar", more:find("api.progressParts(line[1])", 1, true) ~= nil
	and more:find("api.drawProgressBar(b, lineFs", 1, true) ~= nil)
local f = io.open(dir .. "/Textures/BarBG.tga", "rb")
local g = io.open(dir .. "/Textures/BarFillGreen.tga", "rb")
check("Textures/BarBG.tga and BarFillGreen.tga exist (128x32)", f and g and f:read(18):byte(13) == 128 and g:read(18):byte(13) == 128)
if f then f:close() end
if g then g:close() end

-- R106-22: a line with no position yet: no bar drawn off the quest's edge; placed on the next pass
local retried = 0
env.api.applyExtras = function() retried = retried + 1 end
env.GetTime = function() return 100 end
fs.left = nil
fs.text = "Encased Fiery Essence: 0/1"
decorate(fs, block); place(fs)
check("no position yet: the bar waits (not drawn past the edge)", not w.bg.shown and retried == 1)
fs.left = 10
place(fs)
check("with a position: at the quest's right edge", w.bg.shown and w.bg.points[1][4] == (260 - 10) - 4 - bw)

-- R106-23: "Under the objective": the bar on a line of its own under the text, the room part of the text itself
db.progressBarUnder = true
fs.left = 10
fs.text = "Khaz Modan Iron: 26/30"
decorate(fs, block); place(fs)
local under = "Khaz Modan Iron" .. api.progressUnderLine(12)
check("under: the text's last line is the bar's room (Blizzard measures it: nothing collides)",
	fs.text == under)
-- R106-32: that line is an invisible texture as tall as the bar plus a gap above (3) and below (2)
local h = tonumber(under:match("BarFillGreen:(%d+):"))
check("under: the room is the bar (14, R106-76) + 3 above + 2 below = 19 px", h == 19 and under:find("\n|T", 1, true) ~= nil)
check("under: no room kept at the right (the text's full width)", fs.qtsReserve == nil)
check("under: the bar in that room, 2 px up from its bottom (3 px clear of the text above)", w.bg.shown
	and w.bg.points[1][1] == "BOTTOMLEFT" and w.bg.points[1][2] == fs and w.bg.points[1][3] == "BOTTOMLEFT"
	and w.bg.points[1][4] == 0 and w.bg.points[1][5] == 2 and w.bg.w == (260 - 10) - 4 and w.bg.h == 14)
check("under: still filled 26/30 with the count inside",
	math.abs(w.fill.w - (246 - 2 * 6 * 14 / 32) * 26 / 30) < 1e-6 and w.text.text == "26/30")
-- Blizzard sets our text again (a re-layout): kept
fs.text = under
decorate(fs, block)
check("under: our own text again: unchanged", fs.text == under and fs.qtsUnder)
db.progressBarUnder = false
decorate(fs, block); place(fs)
check("back to the right: the plain name, room at the right", fs.text == "Khaz Modan Iron" and fs.qtsReserve ~= nil
	and w.bg.points[1][1] == "TOPLEFT")
db.progressBarUnder = true
db.progressBars = false
decorate(fs, block); place(fs)
check("bars off (under): the full text back", fs.text == "Khaz Modan Iron: 26/30" and not w.bg.shown)
db.progressBars, db.progressBarUnder = true, nil
check("More quests: under the objective too", more:find("api.progressBarUnder()", 1, true) ~= nil)
local cfg = io.open(dir .. "/Tracker/Config.lua"):read("a")
check("/qt: \"Under the objective\" under \"Progress bars on objectives\"", cfg:find('check("Under the objective"', 1, true) ~= nil)

-- R106-30: the reputation frame's look (user's reference), drawn: the bronze-bordered dark box and the green fill
local function readTga(path)
	local f = io.open(path, "rb"); if not f then return nil end
	local d = f:read("a"); f:close(); return d
end
local function px(d, x, y) local i = 18 + (y * 128 + x) * 4; return d:byte(i + 3), d:byte(i + 2), d:byte(i + 1), d:byte(i + 4) end
local bgData, fillData = readTga(dir .. "/Textures/BarBG.tga"), readTga(dir .. "/Textures/BarFillGreen.tga")
local br, bgc, bb = px(bgData, 64, 2)
check("box: a bronze border along the top", br > 120 and br > bb + 20)
local ir, ig, ib = px(bgData, 64, 16)
check("box: a very dark brown inside", ir < 40 and ig < 25 and ib < 10)
local _, gm, _, am = px(fillData, 64, 16)
local _, gt = px(fillData, 64, 7)
check("fill: green, brightest in the middle (round)", am == 255 and gm > 70 and gm > gt + 15)
local _, _, _, edgeA = px(fillData, 64, 1)
check("fill: inside the border (see-through over it)", edgeA == 0)
check("no live reading of the reputation frame any more", not src:find("ReputationDetailFrame, 0", 1, true))

-- R106-31: the fill's colour by progress (red 0-32 %, orange 33-65 %, yellow 66-99 %, green done) or always blue
local function colour(have, need) return api.progressFillTexture(have, need):match("BarFill(%a+)$") end
check("0/8 and 2/8 (25 %): red", colour(0, 8) == "Red" and colour(2, 8) == "Red")
check("32 %: still red; 33 %: orange", colour(32, 100) == "Red" and colour(33, 100) == "Orange")
check("65 %: orange; 66 %: yellow", colour(65, 100) == "Orange" and colour(66, 100) == "Yellow")
check("99 %: yellow; done: green", colour(99, 100) == "Yellow" and colour(30, 30) == "Green")
db.progressBarBlue = true
check("\"Blue bars\": always blue, done or not", colour(2, 8) == "Blue" and colour(30, 30) == "Blue")
db.progressBarBlue = nil
local cw = api.newProgressBar(liveParentForColour or { CreateFontString = function() return region() end,
	CreateTexture = function() return region() end })
api.drawProgressBar(cw, fs, 0, "font", 12, "", 1, 4, "TOPLEFT")
local cbw, cbh = api.progressBarSize(12)
check("drawn: 1/4 red, a quarter of the inside", cw.fill.texture:find("BarFillRed", 1, true)
	and math.abs(cw.fill.w - (cbw - 2 * 6 * cbh / 32) * 0.25) < 1e-9)
api.drawProgressBar(cw, fs, 0, "font", 12, "", 4, 4, "TOPLEFT")
check("drawn: 4/4 green, full", cw.fill.texture:find("BarFillGreen", 1, true)
	and math.abs(cw.fill.w - (cbw - 2 * 6 * cbh / 32)) < 1e-9)
for _, name in ipairs({ "Red", "Orange", "Yellow", "Green", "Blue" }) do
	local t = io.open(dir .. "/Textures/BarFill" .. name .. ".tga", "rb")
	check("Textures/BarFill" .. name .. ".tga exists", t ~= nil)
	if t then t:close() end
end
local cfg2 = io.open(dir .. "/Tracker/Config.lua"):read("a")
check("/qt: \"Blue bars\"", cfg2:find('check("Blue bars"', 1, true) ~= nil)
-- R106-70: the bronze 3 texels thick at the top and the bottom (user: the bottom too thin; "make both 3")
do
	local f = io.open(dir .. "/Textures/BarBG.tga", "rb"); local data = f:read("a"); f:close()
	local W, H = 128, 32
	local function red(y) -- the middle column's pixel at row y (top-down TGA), its red channel
		return data:byte(18 + (y * W + 64) * 4 + 3)
	end
	-- bronze 3 texels top and bottom (user: "make both 3"): 2 full rows each (was 1), mirrored
	local top, bottom = 0, 0
	for y = 0, 7 do if red(y) >= 165 then top = top + 1 end end -- full top bronze (173)
	for y = H - 8, H - 1 do if red(y) >= 115 and red(y) <= 135 then bottom = bottom + 1 end end -- full bottom bronze (125)
	check("BarBG: the bronze is 2 full rows at the top and at the bottom: " .. top .. " / " .. bottom, top == 2 and bottom == 2)
end
-- R106-82: switching the bars' options lays the tracker out again (the objectives' texts changed)
check("the options lay the tracker out again", src:find("eachBlock(fitText)\n\t-- R106-82", 1, true) ~= nil
	and src:find("\twrapDirty = true\n\tif api.applyExtras then api.applyExtras() end\nend", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
