-- A coin amount in a quest title never splits from its coin across lines: when the coin would wrap without its number
-- ("8300xp 2" / "(gold) 49 (silver)"), the whole amount starts the next line (Extras.lua keepCoinsTogether).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local measureTitle\n.-\napi%.keepCoinsTogether = keepCoinsTogether\n)")
check("keepCoinsTogether found in Extras.lua", body ~= nil)

-- a pretend FontString that wraps like the game: 6 px per character, 12 px per texture; a line may break at a space,
-- at an explicit "\n", and between a number and a texture (as the game does)
local CHAR, TEX = 6, 12
local function tokens(text)
	local out = {}
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local i = 1
	while i <= #text do
		local c = text:sub(i, i)
		if c == "\n" then out[#out + 1] = { nl = true }; i = i + 1
		elseif c == " " then out[#out + 1] = { space = true, w = CHAR }; i = i + 1
		elseif text:sub(i, i + 1) == "|T" then
			local e = text:find("|t", i, true)
			out[#out + 1] = { w = TEX, breakBefore = true }; i = e + 2
		else
			local j = i
			while j <= #text and not text:sub(j, j):match("[ \n|]") do j = j + 1 end
			out[#out + 1] = { w = (j - i) * CHAR }; i = j
		end
	end
	return out
end
local function lines(text, width)
	local n, x = 1, 0
	for _, t in ipairs(tokens(text)) do
		if t.nl then n, x = n + 1, 0
		elseif t.space then if x > 0 then x = x + t.w end
		else
			if x + t.w > width and x > 0 then n, x = n + 1, 0 end
			x = x + t.w
		end
	end
	return n
end
local function fontString(width)
	local f = { width = width }
	function f:GetFont() return "font", 12, "" end
	function f:GetWidth() return self.width end
	function f:SetFont() end
	function f:SetWidth(w) self.width = w end
	function f:SetWordWrap() end
	function f:SetMaxLines() end
	function f:Hide() end
	function f:SetText(t) self.text = t end
	function f:GetNumLines() return lines(self.text, self.width) end
	return f
end
local db = { goldCoins = true, wordWrap = true }
local env = setmetatable({ db = db, api = {}, UIParent = { CreateFontString = function() return fontString(0) end } },
	{ __index = _G })
local keep = load(body .. "\nreturn keepCoinsTogether", "extras", "t", env)()

local GOLD = "|cffffd7002|r|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:0:16:16:2:14:2:14|t"
local SILVER = "|cffc7c7cf49|r|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:0:0:16:16:2:14:2:14|t"
local title = "[60] Show Me the Money!  |cffb087ff8300xp|r  " .. GOLD .. " " .. SILVER
-- "[60] Show Me the Money!  8300xp  2" is 34 characters = 204 px: the "2" fits a 210 px title, its coin does not
local out = keep(fontString(210), title)
check("the coin would wrap without its number: the amount starts the next line",
	out == "[60] Show Me the Money!  |cffb087ff8300xp|r\n" .. GOLD .. " " .. SILVER)
check("the number and its coin now on the same line", lines(out, 210) == 2)
check("wide enough for all of it: unchanged", keep(fontString(400), title) == title)
-- the number already wraps with its coin (both on line 2): unchanged
check("number and coin wrap together: unchanged", keep(fontString(190), title) == title)
-- R106-47: gold fits with its coin but the silver would wrap: the whole money starts the next line together
-- ("...8300xp  2(g)" = 216 px fits 230, " 49" would reach 234)
local out2 = keep(fontString(230), title)
check("gold and silver stay together: the whole money starts the next line",
	out2 == "[60] Show Me the Money!  |cffb087ff8300xp|r\n" .. GOLD .. " " .. SILVER)
db.goldCoins = false
check("letters, not coins (\"2g\"): unchanged", keep(fontString(210), title) == title)
db.goldCoins, db.wordWrap = true, false
check("word wrap off: unchanged (cut off as before)", keep(fontString(210), title) == title)
db.wordWrap = true

-- the moved amount still comes off with the rest of the decorations (baseTitle)
local bt = src:match("(local REWARD_PATTERNS = {.-\nlocal function baseTitle%(text%).-\nend)")
local baseTitle = load(bt .. "\nreturn baseTitle", "x", "t", setmetatable({}, { __index = _G }))()
check("the decorations still come off cleanly", baseTitle(out) == "[60] Show Me the Money!")

-- R106-47: coin icons on titles a little smaller than the text (85 % of the font size); elsewhere the text height
local cb = src:match("(local COIN_SCALE = .-\napi%.coinPx = coinPx\n)")
check("the coin size code found", cb ~= nil)
if cb then
	local e2 = setmetatable({ api = {} }, { __index = _G })
	local coin = load(cb .. "\nreturn coin", "c", "t", e2)()
	check("a 12 pt title: 10 px coins", e2.api.coinPx(12) == 10)
	check("no size given: the text height (0)", e2.api.coinPx(nil) == 0)
	check("the size goes into the icon", coin("UI-GoldIcon", 10):find(":10:10:0:0:16:16:2:14:2:14|t", 1, true) ~= nil)
end
check("titles pass their font size", src:find("api.rewardSuffix(id, select(2, fs:GetFont()))", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
