-- R106-74: the watched reputation at the top of the quest list; the game's reputation bar see-through meanwhile.
-- R106-71/72/73: reward colours by the item's quality, surnames in the party lines, Ctrl + right-click links.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

-- a frame stub: records points, size, alpha; any other method does nothing
local function frame(name)
	local f = { name = name, points = {}, shown = false, alpha = 1, mouse = true, w = 100, h = 10, scripts = {} }
	local methods = {
		ClearAllPoints = function(self) self.points = {} end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetAlpha = function(self, a) self.alpha = a end, GetAlpha = function(self) return self.alpha end,
		EnableMouse = function(self, v) self.mouse = v end,
		SetSize = function(self, w, h) self.w, self.h = w, h end, GetWidth = function(self) return self.w end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		GetEffectiveScale = function() return 1 end, GetLeft = function() return 100 end,
		GetFrameStrata = function() return "MEDIUM" end, GetFrameLevel = function() return 1 end,
		CreateFontString = function() return frame("text") end, CreateTexture = function() return frame("tex") end,
		SetText = function(self, t) self.text = t end, GetFont = function() return "font", 12, "" end,
	}
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

local hooks = {}
local api = { newProgressBar = function(parent) return { bg = frame("bg"), fill = frame("fill"), text = frame("count") } end,
	progressBarSize = function(size) return size * 5, size + 3 end }
local drawn
api.drawProgressBar = function(w, anchor, x, font, size, flags, have, need) drawn = { have, need } end
local ns = { api = api, onLogin = {}, db = { } }
local watchedData = { name = "Cenarion Circle", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000,
	currentStanding = 4500, factionID = 609 }
local repBar = frame("repBar")
repBar.shown = true
local xpBar = frame("xpBar")
xpBar.shown = true
local mixin = { Update = function() end }
repBar.Update = mixin.Update
local mainContainer, secondContainer = frame("main"), frame("second")
mainContainer.bars = { repBar }
secondContainer.bars = { xpBar }
local env = setmetatable({
	CreateFrame = function(_, name) return frame(name) end, UIParent = frame("UIParent"),
	C_Reputation = { GetWatchedFactionData = function() return watchedData end },
	FACTION_STANDING_LABEL5 = "Friendly", FACTION_BAR_COLORS = { [5] = { r = 0, g = 0.6, b = 0.1 } },
	ReputationStatusBarMixin = mixin, StatusTrackingBarManager = { barContainers = { mainContainer, secondContainer } },
	hooksecurefunc = function(t, k, fn) hooks[#hooks + 1] = { t, k, fn } end,
	InCombatLockdown = function() return false end, GameTooltip = frame("tip"),
	issecretvalue = function() return false end,
}, { __index = _G })
env._G = env
local chunk = assert(loadfile(dir .. "/Tracker/Reputation.lua", "t", env))
chunk("RXPForeverTracker", { tracker = ns })
ns.onLogin[1]()

local w = api.watchedReputation()
check("the watched faction read: 1500 of 6000 in Friendly", w and w.name == "Cenarion Circle" and w.have == 1500
	and w.need == 6000 and w.label == "Friendly")
local ghost = frame("ghost")
ghost.shown = true
local room = api.layoutTrackedReputation(ghost, 40, 0.8)
check("the row takes room in the fixed strip (" .. tostring(room) .. ")", type(room) == "number" and room > 20)
local row = env.RXPForeverTrackerReputation or nil
check("the bar drawn with the points in this standing", drawn and drawn[1] == 1500 and drawn[2] == 6000)
check("the game's reputation bar see-through and deaf to the mouse", repBar.alpha == 0 and repBar.mouse == false)
check("its container too (the reputation bar is the only bar in it)", mainContainer.alpha == 0)
check("the experience bar's container untouched", secondContainer.alpha == 1 and xpBar.alpha == 1)
-- Blizzard sets the alpha again: kept at 0
for _, h in ipairs(hooks) do if h[1] == repBar and h[2] == "SetAlpha" then repBar.alpha = 1; h[3](repBar) end end
check("Blizzard setting its alpha again: back to 0", repBar.alpha == 0)
-- nothing watched: no room, the game's bar back
watchedData = nil
check("nothing watched: no room", api.layoutTrackedReputation(ghost, 40, 1) == 0)
check("nothing watched: the game's bar back", repBar.alpha == 1 and repBar.mouse == true and mainContainer.alpha == 1)
-- switched off
watchedData = { name = "Cenarion Circle", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000,
	currentStanding = 4500, factionID = 609 }
ns.db.repTrack = false
check("option off: no room, the game's bar shown", api.layoutTrackedReputation(ghost, 40, 1) == 0 and repBar.alpha == 1)

local core = io.open(dir .. "/Tracker/Core.lua"):read("a")
check("Core: the row joins the fixed strip before the Quests header",
	(core:find("ns.api.layoutTrackedReputation, ghost, pinned", 1, true) or 1e9)
		< (core:find("pinned = pinned + pinQuestsHeader(pickFollower(), pinned)", 1, true) or 0))
check("on by default", core:find("repTrack = true", 1, true) ~= nil)
check("the scrolling sections move down by its room (R106-77: the top quest was cut off)",
	core:find("pinned = pinned + room; drop = drop + room", 1, true) ~= nil)
local toc = io.open(dir .. "/RXPForeverTracker.toc"):read("a")
check("in the toc", toc:find("Tracker/Reputation.lua", 1, true) ~= nil)
local cfg = io.open(dir .. "/Tracker/Config.lua"):read("a")
check("its option", cfg:find('"Tracked reputation at the top"', 1, true) ~= nil)

-- R106-71: reward colours from the item's own quality
local ex = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local q = ex:match("(local function qualityHex.-\napi.itemQuality = itemQuality)")
check("the quality helpers found", q ~= nil)
if q then
	local qenv = setmetatable({ api = {}, isSecret = function() return false end,
		ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { hex = "|cff0070dd" } },
		C_Item = { GetItemQualityByID = function(id) return id == 7 and 3 or nil end } }, { __index = _G })
	load(q, "q", "t", qenv)()
	check("the game's colour code used", qenv.api.qualityHex(3) == "|cff0070dd")
	check("built from r, g, b when the table has no code", qenv.api.qualityHex(2) == "|cff1fff00")
	check("the item's own quality wins over the reward function's", qenv.api.itemQuality(7, nil, 1) == 3)
	check("no item data: the reward function's quality", qenv.api.itemQuality(8, nil, 2) == 2)
	check("an unknown quality (-1): no colour", qenv.api.qualityHex(-1) == nil)
end
check("reward lines use the item's quality", ex:find("itemLine(name, texture, count, itemQuality(id, link, quality), value)", 1, true) ~= nil)
-- R106-73: Ctrl + right-click
check("Ctrl + right-click on a quest puts its reward links in chat",
	ex:find('frame:HookScript("OnMouseUp", function(_, button) onQuestMouseUp(block, button) end)', 1, true) ~= nil
	and ex:find('if button ~= "RightButton" or not (IsControlKeyDown and IsControlKeyDown()) then return end', 1, true) ~= nil)

-- R106-72: surnames in the party lines
local party = io.open(dir .. "/Tracker/Party.lua"):read("a")
local fn = party:match("(local function separator%(%).-\napi.partyFullName = fullName)")
check("the surname helpers found", fn ~= nil)
if fn then
	local names = { player = { "Ana", "Smith" }, party1 = { "Bo", "Stone" } }
	local penv = setmetatable({ api = {}, isSecret = function() return false end,
		UnitName = function(u) return names[u][1], names[u][2] end }, { __index = _G })
	load(fn, "p", "t", penv)()
	local full, first = penv.api.partyFullName("party1")
	check("Forever: the party member with the surname (" .. tostring(full) .. ")", full == "Bo Stone" and first == "Bo")
end
-- R106-75: the Questie chain's reward items in their rarity's colour; not loaded yet: asked for, plain meanwhile
do
	local qs = io.open(dir .. "/Tracker/Questie.lua"):read("a")
	local body = qs:match("(local waitingItems = {}\nlocal function itemText%(item%).-\nend\n)")
	check("the chain item text found", body ~= nil)
	if body then
		local asked
		local tenv = setmetatable({ api = { itemQuality = function(id) return id == 1 and 3 or nil end,
			qualityHex = function(q) return q == 3 and "|cff0070dd" or nil end },
			C_Item = { GetItemInfo = function(id) return id == 1 and "Windreaper" or nil end,
				RequestLoadItemDataByID = function(id) asked = id end },
			get = function(_, id) return id == 2 and "Dancing Silver" or nil end }, { __index = _G })
		local itemText = load(body .. "\nreturn itemText", "i", "t", tenv)()
		check("a loaded item in its colour", itemText(1) == "|cff0070ddWindreaper|r")
		check("not loaded: Questie's name, the item asked for", itemText(2) == "Dancing Silver" and asked == 2)
	end
	check("the open tooltip drawn again when the item arrives", qs:find("if waitingItems[key] then", 1, true) ~= nil)
end
-- R106-78: the attunement star: the friends list's favourite star, the raid star as fallback
check("the star is our own sharp image (Textures/Star.tga), the raid star as fallback (R106-80)",
	ex:find([[local STAR_ICON = { file = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Star",]], 1, true) ~= nil)
do -- the image: 64x64, see-through corners, a solid centre
	local f = io.open(dir .. "/Textures/Star.tga", "rb"); local data = f and f:read("a"); if f then f:close() end
	local function alpha(x, y) return data:byte(18 + (y * 64 + x) * 4 + 4) end
	check("Star.tga: 64x64, see-through corner, solid centre", data ~= nil and #data == 18 + 64 * 64 * 4
		and alpha(0, 0) == 0 and alpha(32, 34) == 255)
end
print(pass and "PASS" or "FAILED")
