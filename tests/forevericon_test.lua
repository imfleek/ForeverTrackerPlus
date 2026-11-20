-- Icon Classifications: an infinity sign on quests added in World of Warcraft Forever (quest ID at or above
-- FOREVER_MIN_QUEST_ID), on the tracked quests (Extras.lua render) and in More quests (MoreQuests.lua).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local FOREVER_MIN_QUEST_ID = .-\napi%.foreverIcon = foreverIcon\n)")
check("Forever icon code found in Extras.lua", body ~= nil)
local db = { condense = true }
local api = {}
local env = setmetatable({ db = db, api = api, ADDON = "RXPForeverTracker" }, { __index = _G })
load(body, "extras", "t", env)()

check("a new Forever quest (Downstream, 91733)", api.isForeverQuest(91733) == true)
check("another (Show of Force, 98407)", api.isForeverQuest(98407) == true)
check("a quest Forever only changed keeps its old ID: no icon (The Sleeper Has Awakened, 5321)",
	api.isForeverQuest(5321) == false)
check("not a number: no icon", api.isForeverQuest(nil) == false and api.isForeverQuest("91733") == false)
local icon = api.foreverIcon(91733)
check("the Forever \"W\" emblem (the user's picture)", icon and icon.file == "Interface\\AddOns\\RXPForeverTracker\\Textures\\ForeverW")
check("our infinity sign when it cannot be loaded", icon and icon.fallback == "Interface\\AddOns\\RXPForeverTracker\\Textures\\Infinity")
-- applyIcon: SetTexture answers false for a file the client cannot load -> the fallback
local applyBody = src:match("(local function applyIcon%(tex, desc%).-\nend\n)")
check("applyIcon found", applyBody ~= nil)
if applyBody then
	local applyIcon = load(applyBody .. "\nreturn applyIcon", "x", "t", setmetatable({}, { __index = _G }))()
	local set = {}
	local tex = { SetTexture = function(_, f) set[#set + 1] = f; return not f:find("ForeverW", 1, true) end,
		SetTexCoord = function() end }
	applyIcon(tex, icon)
	check("badge missing: the infinity sign drawn instead", set[1] == icon.file and set[2] == icon.fallback)
	set = {}
	tex.SetTexture = function(_, f) set[#set + 1] = f; return true end
	applyIcon(tex, icon)
	check("badge found: only the badge", #set == 1 and set[1] == icon.file)
end
db.condense = false
check("Icon Classifications off: no icon", api.foreverIcon(91733) == nil)
db.condense = true

-- placed with the other title icons: furthest out on tracked quests, and in More quests
check("render adds it furthest out", src:find("if forever then table.insert(slots, 1, forever) end", 1, true) ~= nil)
local more = io.open(dir .. "/Tracker/MoreQuests.lua"):read("a")
check("More quests shows it too", more:find("api.foreverIcon(quest.id)", 1, true) ~= nil)

-- the texture: a 64x64, 32-bit uncompressed TGA (the game loads TGA textures with power-of-two sides)
local f = io.open(dir .. "/Textures/Infinity.tga", "rb")
check("Textures/Infinity.tga exists", f ~= nil)
if f then
	local data = f:read("a")
	f:close()
	local h = data:sub(1, 18)
	local w = h:byte(13) + h:byte(14) * 256
	local ht = h:byte(15) + h:byte(16) * 256
	check("64x64, 32 bit, uncompressed", h:byte(3) == 2 and w == 64 and ht == 64 and h:byte(17) == 32)
	local function alpha(x, y) return data:byte(18 + (y * 64 + x) * 4 + 4) end
	check("infinity: no background (corners and centre of a loop see-through)", alpha(0, 0) == 0 and alpha(63, 63) == 0
		and alpha(0, 32) == 0 and alpha(17, 32) == 0)
	check("infinity: the sign itself solid (where the two loops cross)", alpha(32, 32) == 255)
end

-- the elite skull: the addon's own Textures/Skull.tga (user's reference art), with no square behind it
check("elite icon uses Textures/Skull", src:find([[skull = { file = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Skull", scale = 0.85 }]], 1, true) ~= nil)
local sf = io.open(dir .. "/Textures/Skull.tga", "rb")
check("Textures/Skull.tga exists", sf ~= nil)
if sf then
	local data = sf:read("a")
	sf:close()
	local w = data:byte(13) + data:byte(14) * 256
	check("skull: 64x64, 32 bit", data:byte(3) == 2 and w == 64 and data:byte(17) == 32)
	-- top-left origin, BGRA: alpha of the corner pixel and of the centre
	local function alpha(x, y) return data:byte(18 + (y * 64 + x) * 4 + 4) end
	check("skull: corners see-through (no square)", alpha(0, 0) == 0 and alpha(63, 0) == 0 and alpha(0, 63) == 0
		and alpha(63, 63) == 0)
	check("skull: solid in the middle", alpha(32, 20) == 255)
end

-- R106-29: Textures/ForeverW.tga: 64x64, see-through around the emblem, no white halo at its edge
local fw = io.open(dir .. "/Textures/ForeverW.tga", "rb")
check("Textures/ForeverW.tga exists", fw ~= nil)
if fw then
	local data = fw:read("a")
	fw:close()
	check("ForeverW: 64x64, 32 bit", data:byte(3) == 2 and data:byte(13) == 64 and data:byte(15) == 64 and data:byte(17) == 32)
	local function at(x, y) local i = 18 + (y * 64 + x) * 4; return data:byte(i + 3), data:byte(i + 2), data:byte(i + 1), data:byte(i + 4) end
	local _, _, _, a = at(0, 0)
	check("ForeverW: corners see-through", a == 0)
	-- no light (whitish) pixel that is only partly opaque: the white bleeding is gone
	local halo = 0
	for y = 0, 63 do for x = 0, 63 do
		local r, g, b, al = at(x, y)
		if al > 0 and al < 200 and math.min(r, g, b) > 200 then halo = halo + 1 end
	end end
	check("ForeverW: no white halo at the edge (" .. halo .. " light half-see-through pixels)", halo == 0)
end
-- R106-68: its own on/off option
do
	local ex = io.open(dir .. "/Tracker/Extras.lua"):read("a")
	local cf = io.open(dir .. "/Tracker/Config.lua"):read("a")
	check("the W follows its option (db.foreverIcon, on unless switched off)",
		ex:find("if db and db.condense and db.foreverIcon ~= false and isForeverQuest(id) then return FOREVER_ICON end", 1, true) ~= nil)
	check("the option in the menu", cf:find('"Icon on quests new to Forever"', 1, true) ~= nil)
end
print(pass and "PASS" or "FAILED")
