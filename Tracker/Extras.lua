-- Quest extras our own tracker (Tracker/Own/Frame.lua) draws with: the reward text after titles, the title icons and
-- the done check, progress bars on objectives, the distance and arrow, the quest tooltip and the reward links.
-- If a reward function does not exist in the client, that part silently does nothing (see /qt debug).
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db
local repRewards

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

-- Classic-style quest functions (GetNumQuestLogRewards, GetQuestLogRewardInfo, ...) read the quest selected in the
-- quest log. The tooltip selects the hovered quest for the duration of the read and puts the old selection back.
local function withSelected(questID, fn)
	local C = C_QuestLog
	if C and C.GetSelectedQuest and C.SetSelectedQuest then
		local old = C.GetSelectedQuest()
		C.SetSelectedQuest(questID)
		local ok, a, b, c2 = pcall(fn)
		if old then C.SetSelectedQuest(old) end
		if ok then return a, b, c2 end
		return
	end
	if GetQuestLogSelection and SelectQuestLogEntry then
		local index = C and C.GetLogIndexForQuestID(questID)
		if not index then return end
		local old = GetQuestLogSelection()
		SelectQuestLogEntry(index)
		local ok, a, b, c2 = pcall(fn)
		SelectQuestLogEntry(old or 0)
		if ok then return a, b, c2 end
	end
end

local ALT = { GetQuestLogRewardMoney = { "GetQuestLogRewardMoney", "GetRewardMoney" }, GetQuestLogRewardXP = { "GetQuestLogRewardXP", "GetRewardXP" } }
local function call(name, questID, allowSelect)
	for _, n in ipairs(ALT[name] or { name }) do
		local fn = (C_QuestLog and C_QuestLog[n]) or _G[n]
		if type(fn) == "function" then
			local ok, value = pcall(fn, questID)
			if ok and type(value) == "number" and not isSecret(value) and value > 0 then return value end
		end
	end
	if allowSelect then -- tooltip only: never from the tracker refresh (selection changes fire quest-log events)
		local fn = _G[name]
		if type(fn) == "function" then
			local value = withSelected(questID, fn)
			if type(value) == "number" and not isSecret(value) then return value end
		end
	end
end

-- Money text: coloured numbers with g / s / c, or with the game's coin icons ("Show coins instead"): "40(s) 43(c)",
-- each icon right against its number, one space after each icon but the last.
-- CONSTRAINT: the coin images have an empty border around the coin, which showed as a gap on both sides of every
-- icon (user screenshot, 2.6.3: "(vendor 40 (s) 43 (c) )"). The image is cropped to the coin: texture coordinates
-- 2..14 of 16 on both axes (a fraction of the image, so its pixel size does not matter), drawn at the text height.
-- R106-47: on quest titles (and More quests) a little smaller than the text, COIN_SCALE of its font size (user: "reduce
-- the coin icon sizes slightly"); size 0 elsewhere (tooltips, the journal): the text height, as before.
local COIN_SCALE = 0.85
local function coin(file, px)
	px = tonumber(px) or 0
	return "|TInterface\\MoneyFrame\\" .. file .. ":" .. px .. ":" .. px .. ":0:0:16:16:2:14:2:14|t"
end
local COIN_FILE = { g = "UI-GoldIcon", s = "UI-SilverIcon", c = "UI-CopperIcon" }
local function coinPx(fontSize)
	fontSize = tonumber(fontSize)
	if not fontSize or fontSize <= 0 then return 0 end
	-- 3.2 (user): "Coin size" slider, 50-200 % (db.coinScale)
	local scale = math.min(math.max(tonumber(db and db.coinScale) or 1, 0.5), 2)
	return math.max(math.floor(fontSize * COIN_SCALE * scale + 0.5), 6)
end
api.coinPx = coinPx
-- coins: true/false to choose; nil follows "Show coins instead" (titles). Tooltips pass db.tooltipCoins.
-- spaced: a space between the number and its coin icon (the Prerequisite Journal)
-- px: the coin icons' size (0 or nil: the text height)
local function gold(copper, coins, spaced, px)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if coins == nil then coins = db and db.goldCoins end
	local function unit(letter) return coins and ("|r" .. (spaced and " " or "") .. coin(COIN_FILE[letter], px)) or (letter .. "|r") end
	local out = {}
	if g > 0 then out[#out + 1] = "|cffffd700" .. g .. unit("g") end
	if s > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. unit("s") end
	if c > 0 then out[#out + 1] = "|cffeda55f" .. c .. unit("c") end
	return table.concat(out, " ")
end
-- the tooltips' own coin setting
local function tipGold(copper)
	return gold(copper, db.tooltipCoins and true or false)
end
api.tipGold = function(copper) return tipGold(copper) end

-- "xp" text or the addon's own experience orb icon ("Show xp orb").
local XP_ORB = "|TInterface\\AddOns\\" .. ADDON .. "\\Textures\\XPOrb:0:0:1:0|t"
-- tooltips: the orb right after the number, no gap
local XP_ORB_TIGHT = "|TInterface\\AddOns\\" .. ADDON .. "\\Textures\\XPOrb:0:0:0:0|t"

local function iconSize() return math.floor(14 * ((db and db.iconScale) or 1) + 0.5) end

---------------------------------------------------------------------------------------------------------------------
-- Title icons (Icon Classifications: Elite+ markers, attunement star, Forever infinity)
---------------------------------------------------------------------------------------------------------------------
-- CONSTRAINT (user: "icon scaling shouldn't impact the formatting"): an icon inside the text (|T or |A) makes the line
-- taller and pushes the title along as it grows. The icons are therefore their own textures, drawn over fixed slots
-- in front of the title: the title is indented by the slots' width at 100 % (SLOT px each), and each icon is centred
-- on its slot at the chosen size. "Icon size" then changes only the icons; the text, line height and the quests
-- below stay where they are (a large icon may overlap its neighbours instead).
local SLOT, SLOT_GAP = 14, 3
-- R106-78/80: the friends list's favourite star (user: SocialUIFrame ... FavoriteDisplay.Icon), drawn as our own
-- 64x64 image (Textures/Star.tga, tests/make_star.py): the game's small atlas was blurry at the icons' size and sat
-- off centre (user). The raid target star when the client cannot load the file.
local STAR_ICON = { file = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Star",
	fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" }

local function attunementIcon(id)
	if db and db.condense and db.attunementStar ~= false and id and api.isAttunement and api.isAttunement(id) then
		return STAR_ICON
	end
end
api.attunementIcon = attunementIcon

-- Quests added in World of Warcraft Forever: the Forever "W" emblem (Textures/ForeverW.tga, made by
-- tests/make_forever.py from the user's picture, its white edge bleeding cleaned and a thin dark outline added; the
-- game's own Glues-WoW-ForeverLogo-Infinity badge was not liked), else the addon's infinity sign (Textures/Infinity.tga)
-- when the client cannot load it, under "Icon Classifications". The game and Questie have no "added in Forever" flag;
-- Forever's new quests use new quest IDs well above every older one (Wowhead's Forever quest list, 2026: about 91,000
-- to 98,000), while quests it only changed keep their old, low IDs. So: ID at or above FOREVER_MIN_QUEST_ID.
local FOREVER_MIN_QUEST_ID = 90000
local FOREVER_ICON = { file = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\ForeverW",
	fallback = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Infinity" }
local function isForeverQuest(id)
	return type(id) == "number" and id >= FOREVER_MIN_QUEST_ID
end
api.isForeverQuest = isForeverQuest
local function foreverIcon(id)
	if db and db.condense and db.foreverIcon ~= false and isForeverQuest(id) then return FOREVER_ICON end
end
api.foreverIcon = foreverIcon


local function applyIcon(tex, desc)
	-- the textures are pooled: a crop from the art drawn before (the PvP badge's 40/64) stays through SetAtlas when the
	-- atlas is a whole file (user: "Sometimes icons in the quest titles are missized"; /qt icons: a Dungeon icon with the
	-- PvP crop), so the crop is reset first; SetAtlas sets its own crop after it when it needs one
	tex:SetTexCoord(0, 1, 0, 1)
	if desc.atlas and tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
		local ok, info = pcall(C_Texture.GetAtlasInfo, desc.atlas)
		if ok and info then tex:SetAtlas(desc.atlas); return end
	end
	-- SetTexture answers false when the client cannot load the file: the icon's own fallback then
	if tex:SetTexture(desc.file) == false and desc.fallback then tex:SetTexture(desc.fallback) end
	local c = desc.coords
	if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) else tex:SetTexCoord(0, 1, 0, 1) end
end

-- A finished quest's check: RestedXP's skip-step tick (UI/V2/Core.lua createElementRow: two rotated strokes in an
-- 11 px box), green, drawn with textures so it stays sharp at any size. It sits on its own left of the title and its
-- icons (anchored to the title's left edge, outside it): it never moves the title. Quest titles > "Checks on
-- finished quests", with its scale and opacity.
local CHECK_TICK = { 0.27, 0.87, 0.47 }
local CHECK_STROKES = {
	{ rotation = -math.pi / 4, w = 3.5, h = 1.25, x = -1.5, y = -0.8 },
	{ rotation = math.pi / 4, w = 6, h = 1.25, x = 1, y = -0.1 },
}
local CHECK_GAP = 2
local ICON_GAP = 2 -- between the title and the icon next to it
-- the outline: the same strokes in black, a little larger, behind (as the zone header's outlined text)
local CHECK_OUTLINE = 0.55 -- in 11 px units
local function checkWidget(fs)
	local w = fs.qtsCheck
	if w then return w end
	w = CreateFrame("Frame", nil, fs:GetParent())
	w:SetFrameLevel((fs:GetParent():GetFrameLevel() or 1) + 2)
	w.strokes, w.outlines = {}, {}
	for i, def in ipairs(CHECK_STROKES) do
		local o = w:CreateTexture(nil, "BORDER")
		o:SetColorTexture(0, 0, 0, 1)
		if o.SetRotation then o:SetRotation(def.rotation) end
		w.outlines[i] = o
		local t = w:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(1, 1, 1, 1)
		if t.SetRotation then t:SetRotation(def.rotation) end
		w.strokes[i] = t
	end
	fs.qtsCheck = w
	return w
end
-- Quest titles > Checks on finished quests: its colour and opacity (false: green, at the old opacity setting)
local function checkColor()
	local c = type(db.completeCheckColor) == "table" and db.completeCheckColor or nil
	if c then return c[1], c[2], c[3], c[4] or 1 end
	return CHECK_TICK[1], CHECK_TICK[2], CHECK_TICK[3], math.min(math.max(tonumber(db.completeCheckAlpha) or 1, 0.1), 1)
end
api.checkColor = checkColor
api.CHECK_GREEN = CHECK_TICK
-- A finished quest's icons in front of its title are faded to 87 % (placeTitleIcons set them to Icon opacity)
local DONE_ICON_ALPHA = 0.87
-- show (complete) or hide the check: on top of the icon next to the title when there is one, else left of the title
local function placeCheck(fs, complete)
	if complete and (fs.qtsIconsWidth or 0) > 0 then
		local iconAlpha = math.min(math.max(tonumber(db and db.iconAlpha) or 1, 0.1), 1)
		for _, tex in ipairs(fs.qtsIcons or {}) do tex:SetAlpha(math.min(iconAlpha, DONE_ICON_ALPHA)) end
	end
	if not (complete and db and db.completeCheck ~= false) then
		if fs.qtsCheck then fs.qtsCheck:Hide() end
		return
	end
	local w = checkWidget(fs)
	local _, fontSize = fs:GetFont()
	local lineH = (type(fontSize) == "number" and fontSize > 0) and fontSize or SLOT
	local size = math.floor(iconSize() * (tonumber(db.completeCheckScale) or 1) + 0.5)
	w:SetSize(size, size)
	w:ClearAllPoints()
	if (fs.qtsIconsWidth or 0) > 0 then
		w:SetPoint("CENTER", fs, "TOPLEFT", fs.qtsNearIconX, -lineH / 2) -- on the icon next to the title
	else
		w:SetPoint("RIGHT", fs, "TOPLEFT", -CHECK_GAP, -lineH / 2)
	end
	local r, g, b, a = checkColor()
	w:SetAlpha(math.min(math.max(a, 0.1), 1))
	local outline = db.completeCheckOutline and true or false
	local unit = size / 11
	for i, def in ipairs(CHECK_STROKES) do
		local t, o = w.strokes[i], w.outlines[i]
		t:SetVertexColor(r, g, b, 1)
		t:SetSize(def.w * unit, def.h * unit)
		t:ClearAllPoints()
		t:SetPoint("CENTER", w, "CENTER", def.x * unit, def.y * unit)
		if outline then
			o:SetSize((def.w + 2 * CHECK_OUTLINE) * unit, (def.h + 2 * CHECK_OUTLINE) * unit)
			o:ClearAllPoints()
			o:SetPoint("CENTER", w, "CENTER", def.x * unit, def.y * unit)
			o:Show()
		else
			o:Hide()
		end
	end
	w:Show()
end
api.placeCheck = placeCheck

-- Puts the icons (descriptors {atlas=, file=, coords=}) left of fs's first line, outside the title, and returns ""
-- (the title needs no room for them). Textures belong to fs's parent and are reused.
local iconTitles = setmetatable({}, { __mode = "k" }) -- titles that drew icons (for /ftp icons)
local function placeTitleIcons(fs, icons)
	if iconTitles then iconTitles[fs] = true end
	fs.qtsIcons = fs.qtsIcons or {}
	local pool = fs.qtsIcons
	local parent = fs:GetParent()
	local _, fontSize = fs:GetFont()
	local lineH = (type(fontSize) == "number" and fontSize > 0) and fontSize or SLOT
	local size = iconSize()
	-- Quest titles > Icon opacity
	local alpha = math.min(math.max(tonumber(db and db.iconAlpha) or 1, 0.1), 1)
	-- drawn on their own left of the title, the last one next to it (they never move the title); a finished quest's
	-- check sits on the one next to the title (placeCheck reads qtsIconsWidth and qtsNearIconX)
	local n = #icons
	for i, desc in ipairs(icons) do
		local tex = pool[i]
		if not tex then tex = parent:CreateTexture(nil, "OVERLAY"); pool[i] = tex end
		applyIcon(tex, desc)
		local drawn = math.floor(size * (tonumber(desc.scale) or 1) + 0.5) -- R106-51: centred on its slot
		tex:SetSize(drawn, drawn)
		tex.qtsDesc, tex.qtsDrawn = desc, drawn
		tex:SetAlpha(alpha)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", fs, "TOPLEFT", -(ICON_GAP + (n - i) * (size + SLOT_GAP) + size / 2), -lineH / 2)
		tex:Show()
	end
	for i = n + 1, #pool do pool[i]:Hide() end
	fs.qtsIconsWidth = n > 0 and (ICON_GAP + n * size + (n - 1) * SLOT_GAP) or 0
	fs.qtsNearIconX = -(ICON_GAP + size / 2) -- the centre of the icon next to the title (the check sits on it)
	return "" -- the title keeps its place (nothing to make room for)
end
api.placeTitleIcons = placeTitleIcons

-- /qt icons: each shown title's icons as drawn (user: "Sometimes icons in the quest titles are missized", classic and
-- the new tracker alike): the art (atlas or file and what the game loaded), the size asked for, the size it has, the
-- crop, so the odd one out can be found
if api.addSlash then api.addSlash("icons", "list the icons on the quest titles with their sizes", function(_, say)
	local n = 0
	for title in pairs(iconTitles) do
		if title:IsVisible() then
			for i, tex in ipairs(title.qtsIcons or {}) do
				if tex:IsShown() then
					n = n + 1
					local d = tex.qtsDesc or {}
					local w, h = tex:GetSize()
					local ok, l, r, t, b = pcall(tex.GetTexCoord, tex)
					say(("%s #%d: %s scale %s; wanted %s, has %.1fx%.1f; atlas %s, texture %s; crop %s"):format(
						tostring(title:GetText()):gsub("|", "||"):sub(1, 30), i, tostring(d.atlas or d.file),
						tostring(d.scale or 1), tostring(tex.qtsDrawn), w or 0, h or 0, tostring(tex.GetAtlas and tex:GetAtlas()),
						tostring(tex:GetTexture()), ok and ("%.2f,%.2f,%.2f,%.2f"):format(l or 0, r or 0, t or 0, b or 0) or "?"))
				end
			end
		end
	end
	say(("icon size setting %s -> %d px slot"):format(tostring(db and db.iconScale), iconSize()))
	if n == 0 then say("no quest title shows an icon") end
end) end
local function hideTitleIcons(fs)
	for _, tex in ipairs(fs and fs.qtsIcons or {}) do tex:Hide() end
	if fs then fs.qtsIconsWidth = 0 end
	if fs and fs.qtsCheck then fs.qtsCheck:Hide() end
end
api.hideTitleIcons = hideTitleIcons

local ICONS = {
	-- R106-51: scale: drawn this much larger than the slot so the visible art matches the Forever W (user: "match the
	-- wow forever icon size"; screenshot: the W 20 px tall, the dungeon portal 18 px in the same 14 px-scaled slot).
	-- The slots and their spacing stay the same; the skull (our own art, 97 % of its image) already matches the W (94 %).
	-- R106-61: dungeon and raid 20 % larger again (user): 1.1 x 1.2
	dungeon = { atlas = "Dungeon", file = "Interface\\Minimap\\Dungeon", scale = 1.32 },
	raid = { atlas = "Raid", file = "Interface\\Minimap\\Raid", scale = 1.32 },
	pvp = { file = "Interface\\TargetingFrame\\UI-PVP-Horde", coords = { 0, 40 / 64, 0, 40 / 64 } },
	-- elite: the addon's own skull (Textures/Skull.tga, from the user's reference art, no square behind it)
	skull = { file = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Skull", scale = 0.85 }, -- R106-61: 15 % smaller (user)
}
local function getIcons()
	-- R106-79: the PvP icon of the player's own faction (it was always the Horde one)
	if not ICONS.pvpFaction and UnitFactionGroup then
		local faction = UnitFactionGroup("player")
		if faction == "Alliance" or faction == "Horde" then
			ICONS.pvpFaction = faction
			ICONS.pvp.file = "Interface\\TargetingFrame\\UI-PVP-" .. faction
		end
	end
	return ICONS
end
local TAG_ID = { group = 1, pvp = 41, raid = 62, dungeon = 81 } -- Classic quest tag IDs, used when no Enum is present

-- R106-79: a battleground quest without the game's PvP tag (user: "Field of Honor: Week 2" under "Warsong Gulch" showed
-- no PvP icon): its quest log header is a battleground. The battlegrounds' names from the game (GetBattlegroundInfo)
-- and from their map areas (Alterac Valley 2597, Warsong Gulch 3277, Arathi Basin 3358, Eye of the Storm 3820,
-- Strand of the Ancients 4384, Isle of Conquest 4710, Forever's Battle for the Darkspear Islands 16606, user), in the
-- client's language; read once.
local BG_AREAS = { 2597, 3277, 3358, 3820, 4384, 4710, 16606 }
local bgNames
local function battlegroundNames()
	if bgNames then return bgNames end
	bgNames = {}
	-- the quest log's own "Battlegrounds" category
	if type(BATTLEGROUNDS) == "string" then bgNames[BATTLEGROUNDS:lower()] = true end
	-- WoW Forever's own battleground, also by its English name (its area 16606 above gives the client's own)
	bgNames["battle for the darkspear islands"] = true
	bgNames["darkspear islands"] = true
	if C_Map and C_Map.GetAreaInfo then
		for _, area in ipairs(BG_AREAS) do
			local ok, name = pcall(C_Map.GetAreaInfo, area)
			if ok and type(name) == "string" and name ~= "" and not isSecret(name) then bgNames[name:lower()] = true end
		end
	end
	local count = GetNumBattlegroundTypes and GetNumBattlegroundTypes() or 0
	for i = 1, (type(count) == "number" and count or 0) do
		local ok, name = pcall(GetBattlegroundInfo, i)
		if ok and type(name) == "string" and name ~= "" and not isSecret(name) then bgNames[name:lower()] = true end
	end
	return bgNames
end
-- the quest log header the quest sits under
local function logHeaderOf(questID)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	for i = (index or 1) - 1, 1, -1 do
		local info = C_QuestLog.GetInfo(i)
		if info and info.isHeader then
			return type(info.title) == "string" and not isSecret(info.title) and info.title or nil
		end
	end
end
local function isBattlegroundQuest(questID)
	local header = logHeaderOf(questID)
	return header ~= nil and battlegroundNames()[header:lower()] == true
end
api.isBattlegroundQuest = isBattlegroundQuest

-- Elite -> skull, group quests -> [+N]; the matching "[Elite]" / "[60+]" tag in the title is tidied.
local function classifier(questID)
	local tag = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
	if type(tag) ~= "table" then
		if isBattlegroundQuest(questID) then return getIcons().pvp, "" end -- R106-79: untagged battleground quests
		return nil
	end
	local name = type(tag.tagName) == "string" and not isSecret(tag.tagName) and tag.tagName or ""
	local lower = name:lower()
	local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	local info = logIndex and C_QuestLog.GetInfo(logIndex)
	local size = info and tonumber(info.suggestedGroup) or 0
	local enum = Enum and Enum.QuestTag or {}
	local id = tag.tagID
	local function is(word, enumKey)
		return lower:find(word, 1, true) ~= nil or (id ~= nil and (id == enum[enumKey] or id == TAG_ID[word]))
	end
	if is("raid", "Raid") then return getIcons().raid, name end
	if is("dungeon", "Dungeon") then return getIcons().dungeon, name end
	if is("pvp", "PvP") or isBattlegroundQuest(questID) then return getIcons().pvp, name end
	local isElite = lower:find("elite", 1, true) ~= nil
		or (Enum and Enum.QuestTag and Enum.QuestTag.Elite and tag.tagID == Enum.QuestTag.Elite)
	local isGroup = lower:find("group", 1, true) ~= nil or size > 1
		or (Enum and Enum.QuestTag and Enum.QuestTag.Group and tag.tagID == Enum.QuestTag.Group)
	if isElite then return getIcons().skull, name end
	if isGroup then return ("|cffff8040[+%s]|r"):format(size > 1 and size or "?"), name end
end
api.questClassifier = classifier -- R106-128: More quests (MoreQuests.lua) shows the same marker

-- What follows a quest title: experience and gold (and rep) as switched on, in their order. Also used by the
-- "More quests" section (MoreQuests.lua). Every part starts with two spaces and a colour code (see baseTitle).
-- Experience and gold as on quest titles (the title settings: xp orb or "xp" in the xp colour, coins or g/s/c), for
-- totals that are not one quest's (the Prerequisite Journal). Nothing for zero.
function api.formatRewardTotals(xp, money, spacedCoins)
	local parts = {}
	if xp and xp > 0 then
		local c = db and db.xpColor or { 0.69, 0.53, 1 }
		local function byte(v) return math.floor((tonumber(v) or 1) * 255 + 0.5) end
		parts[#parts + 1] = ("|c%02x%02x%02x%02x%d%s|r"):format(byte(c[4]), byte(c[1]), byte(c[2]), byte(c[3]),
			math.floor(xp + 0.5), db and db.xpOrb and ("|r" .. XP_ORB) or "xp")
	end
	if money and money > 0 then parts[#parts + 1] = gold(money, nil, spacedCoins) end
	return table.concat(parts, "  ")
end

-- fontSize: the title's font size, for the coin icons' size (R106-47)
function api.rewardSuffix(id, fontSize)
	if not db or not id then return "" end
	local text = ""
	for _, kind in ipairs(api.rewardOrder()) do
		if kind == "xp" then
			local xp = call("GetQuestLogRewardXP", id)
			if xp and xp > 0 then
				local c = db.xpColor or { 0.69, 0.53, 1 }
				-- |cAARRGGBB: the colour's opacity in the alpha byte
				text = text .. ("  |c%02x%02x%02x%02x%d%s|r"):format((tonumber(c[4]) or 1) * 255, c[1] * 255, c[2] * 255, c[3] * 255, xp,
					db.xpOrb and ("|r" .. XP_ORB) or "xp")
			end
		elseif kind == "rep" then
			local reps = repRewards(id)
			if reps[1] then text = text .. ("  |cff4cc2ff+%d rep|r"):format(reps[1].amount) end
		elseif kind == "gold" then
			local money = call("GetQuestLogRewardMoney", id)
			if money and money > 0 then text = text .. "  " .. gold(money, nil, nil, coinPx(fontSize)) end
		end
	end
	return text
end

-- A coin amount in a title ("2" and its gold coin, "Show coins instead") whose coin would wrap onto the next line
-- without its number (user screenshot: "8300xp 2" / "(gold) 49 (silver)"): the whole amount starts the next line
-- instead. The game breaks a line between a number and an inline texture, so this is measured: the title's text up to
-- the number and up to its coin, in a hidden copy of the title (same font, width, word wrap); a coin that lands on a
-- later line than its number moves the amount down ("\n" before its colour code; baseTitle's patterns take it out).
local measureTitle
local function linesOf(fs, text)
	local font, size, flags = fs:GetFont()
	if not font then return nil end
	if not measureTitle then
		measureTitle = UIParent:CreateFontString(nil, "OVERLAY")
		measureTitle:Hide()
	end
	measureTitle:SetFont(font, size, flags)
	measureTitle:SetWidth(fs:GetWidth())
	if measureTitle.SetWordWrap then measureTitle:SetWordWrap(true) end
	if measureTitle.SetMaxLines then measureTitle:SetMaxLines(0) end
	measureTitle:SetText(text)
	return measureTitle.GetNumLines and measureTitle:GetNumLines() or nil
end
local COIN_MARK = "|r|TInterface\\MoneyFrame\\UI-"
local function keepCoinsTogether(fs, text)
	if not (db and db.goldCoins and db.wordWrap) or type(text) ~= "string" or not text:find(COIN_MARK, 1, true) then
		return text
	end
	local width = fs:GetWidth()
	if not width or width <= 20 then return text end
	local from = 1
	for _ = 1, 6 do -- each coin amount at most once
		local s, e = text:find(COIN_MARK, from, true)
		if not s then break end
		local iconEnd = text:find("|t", e, true)
		if not iconEnd then break end
		-- R106-47: the whole money (gold, silver and copper right after each other) is one piece: it starts the next
		-- line together when any part of it would wrap (user: "2 (gold)" on one line, "74 (silver) 56 (copper)" below)
		for _ = 1, 2 do
			local _, numberEnd = text:find("^ |c%x%x%x%x%x%x%x%x%d+", iconEnd + 2)
			if not numberEnd or text:find(COIN_MARK, numberEnd + 1, true) ~= numberEnd + 1 then break end
			local nextEnd = text:find("|t", numberEnd + 1, true)
			if not nextEnd then break end
			iconEnd = nextEnd
		end
		local numberLines, coinLines = linesOf(fs, text:sub(1, s - 1)), linesOf(fs, text:sub(1, iconEnd + 1))
		if numberLines and coinLines and coinLines > numberLines then
			local groupStart = text:sub(1, s - 1):match(".*()|c%x%x%x%x%x%x%x%x%d+$")
			if groupStart and groupStart > 1 then
				local head = text:sub(1, groupStart - 1):gsub("%s+$", "")
				text = head .. "\n" .. text:sub(groupStart)
				iconEnd = #head + 1 + (iconEnd - groupStart + 1)
			end
		end
		from = iconEnd + 2
	end
	return text
end
api.keepCoinsTogether = keepCoinsTogether

-- Experience and gold follow the order in which they were switched on.
local REWARD_KEY = { xp = "showXP", gold = "showGold" }
function api.rewardOrder()
	local order, seen = {}, {}
	for _, kind in ipairs(type(db.rewardOrder) == "table" and db.rewardOrder or {}) do
		if not seen[kind] and REWARD_KEY[kind] and db[REWARD_KEY[kind]] then
			order[#order + 1] = kind; seen[kind] = true
		end
	end
	for _, kind in ipairs({ "xp", "gold" }) do
		if db[REWARD_KEY[kind]] and not seen[kind] then order[#order + 1] = kind end
	end
	return order
end

-- Reputation rewards: Classic-style functions that read the selected quest. Read once per quest and cached, so the
-- tracker refresh does not keep changing the quest-log selection.
local repCache = {}
local function factionName(id)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
		if ok and type(data) == "table" and type(data.name) == "string" then return data.name end
	end
	if GetFactionInfoByID then
		local ok, name = pcall(GetFactionInfoByID, id)
		if ok and type(name) == "string" then return name end
	end
	return "Faction " .. tostring(id)
end
function repRewards(questID)
	local cached = repCache[questID]
	if cached and (#cached > 0 or GetTime() - (cached.time or 0) < 10) then return cached end
	local list = {}
	local numFn, infoFn = _G.GetNumQuestLogRewardFactions, _G.GetQuestLogRewardFactionInfo
	if type(numFn) == "function" and type(infoFn) == "function" then
		withSelected(questID, function()
			local n = numFn()
			for i = 1, (type(n) == "number" and n or 0) do
				local factionID, amount = infoFn(i)
				if type(factionID) == "number" and type(amount) == "number" and not isSecret(amount) then
					-- Blizzard's own quest window divides large values by 100 in some versions
					if amount >= 1000 and amount % 100 == 0 then amount = amount / 100 end
					list[#list + 1] = { name = factionName(factionID), amount = math.floor(amount) }
				end
			end
		end)
	end
	list.time = GetTime()
	repCache[questID] = list
	return list
end
api.repRewards = repRewards
function api.forgetRep(questID) if questID then repCache[questID] = nil else wipe(repCache) end end

function api.setReward(kind, on)
	if REWARD_KEY[kind] then db[REWARD_KEY[kind]] = on and true or false end
	local order = {}
	for _, k in ipairs(api.rewardOrder()) do if k ~= kind then order[#order + 1] = k end end
	if on then order[#order + 1] = kind end
	db.rewardOrder = order
	if api.refreshQuests then api.refreshQuests() end
end

-- Vendor value of an item (sell price x count), when the item's data is loaded; asks the game to load it otherwise,
-- so the next hover shows it.
local function vendorValue(itemID, link, count)
	local key = itemID or link
	if not key then return nil end
	local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if type(getInfo) ~= "function" then return nil end
	local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(getInfo, key)
	if ok and type(price) == "number" and not isSecret(price) then
		return price * math.max(1, tonumber(count) or 1)
	end
	if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

-- R106-71: the colour code of an item quality ("|cff1eff00" for uncommon), from the game's table, else its colour
local function qualityHex(quality)
	if type(quality) ~= "number" or isSecret(quality) or quality < 0 then return nil end
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if q and type(q.hex) == "string" then return q.hex end
	local r, g, b
	if q and q.r then r, g, b = q.r, q.g, q.b
	elseif C_Item and C_Item.GetItemQualityColor then
		local ok, cr, cg, cb = pcall(C_Item.GetItemQualityColor, quality)
		if ok then r, g, b = cr, cg, cb end
	end
	if type(r) ~= "number" then return nil end
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
api.qualityHex = qualityHex

-- R106-71: an item's own quality (user: the rewards in the tooltip in their rarity's colour): the quest reward
-- functions give it as -1 or not at all in some clients, so the item's data decides when it is loaded
local function itemQuality(itemID, link, given)
	if C_Item and C_Item.GetItemQualityByID and (itemID or link) then
		local ok, q = pcall(C_Item.GetItemQualityByID, itemID or link)
		if ok and type(q) == "number" and not isSecret(q) then return q end
	end
	local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if type(getInfo) == "function" and (itemID or link) then
		local ok, _, _, q = pcall(getInfo, itemID or link)
		if ok and type(q) == "number" and not isSecret(q) then return q end
	end
	return given
end
api.itemQuality = itemQuality

local function itemLine(name, texture, count, quality, value)
	local text = name
	local hex = qualityHex(quality)
	if hex then text = hex .. name .. "|r" end
	if texture then text = "|T" .. texture .. ":16:16|t " .. text end
	if type(count) == "number" and count > 1 then text = text .. " x" .. count end
	if value and value > 0 then text = text .. "  |cffaaaaaa(vendor|r " .. tipGold(value) .. "|cffaaaaaa)|r" end
	return text
end

-- the reward lines, and the best vendor value among them ({ value, name }: what selling it brings, its count included)
local function readItems(numName, infoName, id)
	local numFn, infoFn = _G[numName], _G[infoName]
	local list = {}
	local best = { value = 0 }
	if type(numFn) ~= "function" or type(infoFn) ~= "function" then return list, best end
	local linkType = infoName == "GetQuestLogChoiceInfo" and "choice" or "reward"
	local function collect(useID)
		local ok, n = pcall(numFn, useID and id or nil)
		if not ok or type(n) ~= "number" or isSecret(n) then return end
		for i = 1, n do
			local okI, name, texture, count, quality, _, itemID = pcall(infoFn, i, useID and id or nil)
			if okI and type(name) == "string" and not isSecret(name) then
				local link
				if not useID and _G.GetQuestLogItemLink then
					local okL, value = pcall(_G.GetQuestLogItemLink, linkType, i)
					if okL and type(value) == "string" then link = value end
				end
				local id = type(itemID) == "number" and not isSecret(itemID) and itemID or nil
				local value = vendorValue(id, link, count)
				list[#list + 1] = itemLine(name, texture, count, itemQuality(id, link, quality), value)
				if type(value) == "number" and value > best.value then best.value, best.name = value, name end
			end
		end
	end
	collect(true)
	if #list == 0 then withSelected(id, function() collect(false) end) end
	return list, best
end

-- The last tooltip line in the game's small tooltip font; lines changed so go back to the normal font when the tooltip
-- is cleared (the game reuses its line font strings for every tooltip).
local smallened = {}
local function smallLastLine(tip)
	local name = tip.GetName and tip:GetName()
	local n = tip.NumLines and tip:NumLines()
	local fs = name and n and _G[name .. "TextLeft" .. n]
	if not (fs and fs.SetFontObject and _G.GameTooltipTextSmall) then return end
	fs:SetFontObject(_G.GameTooltipTextSmall)
	if not smallened[tip] then
		smallened[tip] = {}
		if tip.HookScript then
			pcall(tip.HookScript, tip, "OnTooltipCleared", function(self)
				local list = smallened[self]
				for i = #list, 1, -1 do
					if _G.GameTooltipText then list[i]:SetFontObject(_G.GameTooltipText) end
					list[i] = nil
				end
			end)
		end
	end
	local list = smallened[tip]
	list[#list + 1] = fs
end

local function addRewards(id)
	local tip = GameTooltip
	local xp = call("GetQuestLogRewardXP", id, true)
	local money = call("GetQuestLogRewardMoney", id, true)
	local items, bestItem = readItems("GetNumQuestLogRewards", "GetQuestLogRewardInfo", id)
	local choices, bestChoice = readItems("GetNumQuestLogChoices", "GetQuestLogChoiceInfo", id)
	if not ((xp and xp > 0) or (money and money > 0) or #items > 0 or #choices > 0) then return end
	tip:AddLine(" ")
	tip:AddLine(REWARDS or "Rewards", 1, 0.82, 0)
	if xp and xp > 0 then tip:AddLine(xp .. (db.tooltipXpOrb and XP_ORB_TIGHT or " experience"), 0.69, 0.53, 1) end
	-- the gold with the vendor value of the most valuable item reward added (what the quest is worth in gold)
	-- (only when the quest gives gold itself: no Gold line just for an item's vendor value)
	local best = bestChoice.value > bestItem.value and bestChoice or bestItem
	local total = (money or 0) + best.value
	if money and money > 0 then
		tip:AddLine("Gold: " .. tipGold(total), 1, 1, 1)
		if best.value > 0 then
			tip:AddLine(("  |cffaaaaaaincludes|r %s |cffaaaaaafrom selling %s|r"):format(tipGold(best.value), tostring(best.name)),
				1, 1, 1)
			smallLastLine(tip)
		end
	end
	if #items > 0 then
		tip:AddLine("You will receive:", 0.8, 0.8, 0.8)
		for _, item in ipairs(items) do tip:AddLine("  " .. item, 1, 1, 1) end
	end
	if #choices > 0 then
		tip:AddLine("Choose one of:", 0.8, 0.8, 0.8)
		for _, item in ipairs(choices) do tip:AddLine("  " .. item, 1, 1, 1) end
	end
end

-- The quest tooltip for any quest in the log: Blizzard's quest blocks (showTip) and the "More quests" section.
-- extra(tip), when given, adds lines before the tooltip is shown. Returns false when tooltips are off.
local lastTip -- the last quest tooltip shown, so it can be drawn again (Ctrl shows the whole chain: Questie.lua)
-- Width lock (seamless Ctrl): the tooltip is as wide as the wider of its two forms (Ctrl held and not), measured when
-- it opens, and that width is set again on every Ctrl redraw. The width is set, not added to: SetMinimumWidth
-- applies to the content (the frame adds its padding), so the content minimum is corrected once by what the frame
-- actually measures, and repeated redraws give the same width every time.
local MIN_DEFAULT = 0
local widthLocked = false
local function lockWidth(tip, target)
	if not (tip.SetMinimumWidth and target and target > 0) then tip:Show() return end
	widthLocked = true
	local guess = math.max(target - 20, 1)
	pcall(tip.SetMinimumWidth, tip, guess)
	tip:Show()
	local got = tip:GetWidth()
	if type(got) == "number" and math.abs(got - target) > 0.5 then
		pcall(tip.SetMinimumWidth, tip, math.max(guess - (got - target), 1))
		tip:Show()
	end
end

local fill -- below: the tooltip's lines
local function questTooltip(owner, id, fallbackTitle, extra, redraw)
	if not db or not db.tooltips or not id then return false end
	local tip = GameTooltip
	if redraw and lastTip and lastTip[1] == owner and lastTip[2] == id then
		-- Ctrl pressed or released: the same tooltip, in place (not re-owned, which hides and re-places it), at the
		-- width measured when it opened; only the lines change
		tip:ClearLines()
		fill(tip, id, fallbackTitle, extra)
		lockWidth(tip, lastTip.width)
		return true
	end
	lastTip = { owner, id, fallbackTitle, extra }
	tip:SetOwner(owner, "ANCHOR_LEFT")
	if tip.SetMinimumWidth then pcall(tip.SetMinimumWidth, tip, MIN_DEFAULT) end
	if api.chainTooltip and api.chainTooltip(id) and api.setChainCtrl then
		-- measure both forms: with the whole chain, then as it is now
		api.setChainCtrl(true)
		fill(tip, id, fallbackTitle, extra)
		api.setChainCtrl(false)
		tip:Show()
		local wide = tip:GetWidth() or 0
		tip:ClearLines()
		fill(tip, id, fallbackTitle, extra)
		tip:Show()
		lastTip.width = math.max(wide, tip:GetWidth() or 0)
		lockWidth(tip, lastTip.width)
	else
		fill(tip, id, fallbackTitle, extra)
		tip:Show()
	end
	return true
end

fill = function(tip, id, fallbackTitle, extra)
	local index = C_QuestLog.GetLogIndexForQuestID(id)
	local info = index and C_QuestLog.GetInfo(index)
	local title = info and info.title
	if type(title) ~= "string" or isSecret(title) then title = fallbackTitle or "Quest" end
	tip:AddLine(title, 1, 1, 1, true)
	if info and tonumber(info.level) and info.level > 0 then tip:AddLine("Level " .. info.level, 0.7, 0.7, 0.7) end
	local textFn = _G.GetQuestLogQuestText
	if index and type(textFn) == "function" then
		local ok, description, objectives = pcall(textFn, index)
		local text = ok and ((type(objectives) == "string" and objectives ~= "" and objectives) or description)
		if type(text) == "string" and text ~= "" and not isSecret(text) then
			tip:AddLine(" ")
			tip:AddLine(text, 0.9, 0.9, 0.9, true)
		end
	end
	if C_QuestLog.GetQuestObjectives then
		local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, id)
		if ok and type(objectives) == "table" and #objectives > 0 then
			tip:AddLine(" ")
			for _, o in ipairs(objectives) do
				if type(o.text) == "string" and not isSecret(o.text) and o.text ~= "" then
					local r, g, b = 1, 1, 1
					if o.finished then r, g, b = 0.5, 0.9, 0.5 end
					tip:AddLine("- " .. o.text, r, g, b, true)
				end
			end
		end
	end
	if api.addQuestieLines then pcall(api.addQuestieLines, tip, id) end -- Questie.lua, only while Questie is used
	if api.addDeadEndLine then pcall(api.addDeadEndLine, tip, id) end -- 3.2 (user idea 35)
	addRewards(id)
	if db.partyProgress ~= false and api.addPartyProgress then api.addPartyProgress(tip, id) end
	if extra then extra(tip) end
end
api.showQuestTooltip = questTooltip

-- the width lock belongs to our quest tooltip only: any other use of the game tooltip starts without it
GameTooltip:HookScript("OnHide", function(self)
	if widthLocked then
		widthLocked = false
		if self.SetMinimumWidth then pcall(self.SetMinimumWidth, self, MIN_DEFAULT) end
	end
end)

-- Draw the quest tooltip again when it is still shown for the same owner (a modifier key changed).
function api.refreshQuestTooltip()
	if not lastTip then return end
	local tip = GameTooltip
	if not tip:IsShown() or tip:GetOwner() ~= lastTip[1] then return end
	questTooltip(lastTip[1], lastTip[2], lastTip[3], lastTip[4], true)
end

-- R106-73: Ctrl + right-click on a quest puts the links of the items it rewards (and its choices) in the chat box
-- (user). GetQuestLogItemLink reads the quest selected in the log, so the quest is selected for the read. The box opens
-- if it is closed; with it open the links go in at the cursor.
local function rewardLinks(id)
	local links = {}
	local linkFn = _G.GetQuestLogItemLink
	if type(linkFn) ~= "function" or type(id) ~= "number" then return links end
	withSelected(id, function()
		for _, kind in ipairs({ { "GetNumQuestLogRewards", "reward" }, { "GetNumQuestLogChoices", "choice" } }) do
			local numFn = _G[kind[1]]
			local ok, n = false, nil
			if type(numFn) == "function" then ok, n = pcall(numFn, id) end
			n = ok and type(n) == "number" and not isSecret(n) and n or 0
			for i = 1, n do
				local okL, link = pcall(linkFn, kind[2], i)
				if okL and type(link) == "string" and not isSecret(link) then links[#links + 1] = link end
			end
		end
	end)
	return links
end
api.questRewardLinks = rewardLinks

local lastLinked = 0
function api.linkQuestRewards(id)
	if GetTime() - lastLinked < 0.2 then return end -- the block and its header button both heard the click
	lastLinked = GetTime()
	local links = rewardLinks(id)
	if #links == 0 then
		if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage("This quest rewards no items.", 1, 0.82, 0) end
		return
	end
	local text = table.concat(links, " ")
	if root.chatInsert then root.chatInsert(text) end -- only into a chat box you opened (Bootstrap.lua)
end

local BAR_BG = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\BarBG"
-- the fill's colour by progress, as the reputation bars' standings (user): red 0-32 %, orange 33-65 %, yellow 66-99 %,
-- green when done; or always the old bars' blue (Quest list > "Blue bars", db.progressBarBlue)
local BAR_FILL = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\BarFill"
local function fillTexture(have, need)
	if db and db.progressBarBlue then return BAR_FILL .. "Blue" end
	if have >= need then return BAR_FILL .. "Green" end
	local percent = math.floor(have / need * 100)
	if percent <= 32 then return BAR_FILL .. "Red" end
	if percent <= 65 then return BAR_FILL .. "Orange" end
	return BAR_FILL .. "Yellow"
end
api.progressFillTexture = fillTexture
-- the bar's size from the line's font size: about 5 characters wide, a little taller than the text
local function barSize(fontSize)
	local size = tonumber(fontSize) or 12
	-- R106-76: 2 px taller than before (user: slightly taller)
	return math.floor(size * 5.5 + 0.5), math.floor(size + 5 + 0.5)
end
api.progressBarSize = barSize

-- "Name: 3/8" (Classic) or "3/8 Name" (Retail) -> name, 3, 8
local function progressParts(text)
	if type(text) ~= "string" or isSecret(text) then return nil end
	local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local name, have, need = plain:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
	if not name then have, need, name = plain:match("^%s*(%d+)%s*/%s*(%d+)%s+(.+)$") end
	have, need = tonumber(have), tonumber(need)
	if not name or name:match("^%s*$") or not need or need <= 0 then return nil end
	return name, have, need
end
api.progressParts = progressParts

-- The look of the reputation frame's bars (user's reference, tests/art/repbar_reference.png): Textures/BarBG.tga and
-- BarFill.tga, drawn by tests/make_bar.py (a bronze-bordered dark box, a round-shaded green fill). Reading the bar live
-- from ReputationFrame found nothing in the Forever client (R106-27, removed).

-- the bar's pieces on a frame: box, fill, count; shared with More quests (MoreQuests.lua)
-- R106-76: drawn in three slices (user: the left and right borders wider than the top and bottom): the bar is much
-- wider than its 128x32 image is for its height, so one stretched image widened the side borders. The two ends
-- (BAR_CAP texels of the image each) keep the image's shape at the bar's height; only the middle, the same in every
-- column, is stretched. The fill sits inside the border (BAR_INSET texels: tests/make_bar.py OUTER + BRONZE + INNER)
-- and shows a middle column of its image, stretched to the progress.
local BAR_TEX_W, BAR_TEX_H, BAR_CAP, BAR_INSET = 128, 32, 8, 6
local function newProgressBar(parent)
	local w = { bg = parent:CreateTexture(nil, "ARTWORK", nil, -1), fill = parent:CreateTexture(nil, "ARTWORK", nil, 1),
		left = parent:CreateTexture(nil, "ARTWORK", nil, 0), right = parent:CreateTexture(nil, "ARTWORK", nil, 0),
		text = parent:CreateFontString(nil, "OVERLAY") }
	w.bg:SetTexture(BAR_BG)
	w.bg:SetTexCoord(BAR_CAP / BAR_TEX_W, 1 - BAR_CAP / BAR_TEX_W, 0, 1)
	w.left:SetTexture(BAR_BG)
	w.left:SetTexCoord(0, BAR_CAP / BAR_TEX_W, 0, 1)
	w.right:SetTexture(BAR_BG)
	w.right:SetTexCoord(1 - BAR_CAP / BAR_TEX_W, 1, 0, 1)
	w.fill:SetTexture(BAR_FILL .. "Green")
	w.text:SetShadowOffset(1, -1)
	w.text:SetShadowColor(0, 0, 0, 1)
	return w
end
api.newProgressBar = newProgressBar

-- show the bar: its TOPLEFT (or `point`) at anchor's relPoint (TOPRIGHT) + x, y (centred on the text's first line
-- by default); bw, bh: its size (default from the font size); the fill cropped to have/need, the count centred
-- fillFile: the fill's image instead of the one by progress (the reputation row: by standing)
local function drawProgressBar(w, anchor, x, font, size, flags, have, need, relPoint, bw, bh, y, point, fillFile)
	local dw, dh = barSize(size)
	bw, bh = bw or dw, bh or dh
	local px = bh / BAR_TEX_H -- one texel of the image, at this height
	local cap = math.min(BAR_CAP * px, bw / 2)
	local inset = BAR_INSET * px
	w.bg:ClearAllPoints()
	w.bg:SetPoint(point or "TOPLEFT", anchor, relPoint or "TOPRIGHT", x, y or (bh - (tonumber(size) or 12)) / 2)
	w.bg:SetSize(bw, bh)
	w.bg:Show()
	if w.left then
		w.left:ClearAllPoints()
		w.left:SetPoint("TOPLEFT", w.bg, "TOPLEFT")
		w.left:SetSize(cap, bh)
		w.left:Show()
		w.right:ClearAllPoints()
		w.right:SetPoint("TOPRIGHT", w.bg, "TOPRIGHT")
		w.right:SetSize(cap, bh)
		w.right:Show()
	end
	local frac = math.min(math.max(have / need, 0), 1)
	w.fill:ClearAllPoints()
	w.fill:SetPoint("TOPLEFT", w.bg, "TOPLEFT", inset, 0)
	w.fill:SetSize(math.max((bw - 2 * inset) * frac, 0.01), bh)
	-- the colour first (setting a texture may reset its coordinates), then a middle column (the same in each)
	local file = fillFile or fillTexture(have, need)
	if w.fillFile ~= file then w.fill:SetTexture(file); w.fillFile = file end
	w.fill:SetTexCoord(0.45, 0.55, 0, 1)
	w.fill:SetShown(frac > 0)
	-- the count a little smaller than the bar is tall
	if font then w.text:SetFont(font, math.max(math.min((tonumber(size) or 12) - 1, bh - 3), 8), flags) end
	w.text:SetTextColor(1, 1, 1, 1)
	w.text:SetText(("%d/%d"):format(have, need))
	w.text:ClearAllPoints()
	w.text:SetPoint("CENTER", w.bg, "CENTER", 0, 0)
	w.text:Show()
	return bw
end
api.drawProgressBar = drawProgressBar

local function hideBar(w)
	if w then
		w.bg:Hide(); w.fill:Hide(); w.text:Hide()
		if w.left then w.left:Hide(); w.right:Hide() end
	end
end
api.hideProgressBar = hideBar


-- "Under the objective" (db.progressBarUnder): the bar on a line of its own under the objective's text. The room for it
-- is an empty last line in the text itself ("\n "), so Blizzard measures it as part of the objective and lays the next
-- line out below it: nothing collides, also with objectives that wrap or several objective lines, and Blizzard's
-- layout is not touched.
-- The last line is an invisible inline texture as tall as the bar and a gap above and below it (UNDER_GAP_TOP,
-- UNDER_GAP_BOTTOM): the game makes that line as tall as the texture, so Blizzard measures the room and moves the next
-- objective, quest title and zone header down by it (user: the bar touched the objective text). The texture is 1 px of
-- a see-through corner of BarFillGreen.tga (texture coordinates 0..1 of its 128x32 pixels).
local UNDER_GAP_TOP, UNDER_GAP_BOTTOM = 3, 2
local function underBarHeight(fontSize) return math.max(math.floor((tonumber(fontSize) or 12) + 2.5), 10) end -- R106-76: +2
local function underLine(fontSize)
	local h = UNDER_GAP_TOP + underBarHeight(fontSize) + UNDER_GAP_BOTTOM
	return "\n|TInterface\\AddOns\\" .. ADDON .. "\\Textures\\BarFillGreen:" .. h .. ":1:0:0:128:32:0:1:0:1|t"
end
api.progressUnderLine = underLine
api.progressUnderGaps = function() return UNDER_GAP_TOP, UNDER_GAP_BOTTOM end
api.progressUnderBarHeight = underBarHeight
local function barUnder() return db and db.progressBarUnder and true or false end
api.progressBarUnder = barUnder

-- Distance and direction after quest titles: how far away the quest is ("120 yds") and a small gold arrow
-- (Textures/DirArrow.tga, drawn by tests/make_dirarrow.py in the look of the waypoint arrow's pointer) that turns to
-- point at it, at the right edge of the title's line. Where the quest is: ZoneSort.lua api.questDirection (Questie's
-- nearest spawn, the turn-in once complete; else the game's next waypoint; else the game's distance, without an
-- arrow). The place is read twice a second, the arrow turns 20 times a second, only while titles show it. Inside an
-- instance (no map position) or on another continent nothing is shown. The title keeps a fixed room for it, so it does
-- not re-wrap as the number changes. Quest list > "Distance and direction after quest titles" (db.questDistance).
-- R106-126: 2 px between a title and its yards (was 6: "40 (silver)" wrapped though it fitted before the yards, user)
local DIST_GAP, DIST_ARROW_GAP = 2, 3
local DIR_ARROW = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\DirArrow"
local distanceShown = setmetatable({}, { __mode = "k" }) -- title FontString -> quest ID

local function distanceText(yards)
	if yards >= 1000 then return ("%.1fk yds"):format(yards / 1000) end
	return ("%d yds"):format(math.floor(yards + 0.5))
end
api.distanceText = distanceText

-- 3.2 "Time to arrive" (db.distanceEta, off by default; an idea from TomTom and WaypointUI): the time to walk there at
-- your speed now, or at your run (or mount) speed while you stand. GetUnitSpeed: current, run, flight, swim (yards/s).
local function etaText(yards)
	if not (db and db.distanceEta) or type(yards) ~= "number" or type(GetUnitSpeed) ~= "function" then return nil end
	local ok, now, run, flight, swim = pcall(GetUnitSpeed, "player")
	if not ok then return nil end
	local speed
	for _, v in ipairs({ now, (IsSwimming and IsSwimming()) and swim or nil, (IsFlying and IsFlying()) and flight or nil, run }) do
		if type(v) == "number" and not isSecret(v) and v > 0.5 then speed = v break end
	end
	speed = speed or 7
	local sec = math.floor(yards / speed + 0.5)
	if sec >= 3600 then return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60) end
	return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end
api.distanceEta = etaText
local function distanceLabel(yards)
	local eta = etaText(yards)
	return eta and (distanceText(yards) .. " " .. eta) or distanceText(yards)
end

-- the arrow's size (the title's font size x "Arrow size", 50-200 %) and opacity ("Arrow opacity", 10-100 %)
local function arrowSize(fontSize)
	local scale = math.min(math.max(tonumber(db and db.distArrowScale) or 1, 0.5), 2)
	return math.floor((tonumber(fontSize) or 12) * scale + 0.5)
end
local function arrowAlpha()
	return math.min(math.max(tonumber(db and db.distArrowAlpha) or 1, 0.1), 1)
end

local measure
-- the room kept at the right of a title in this font: the widest distance text, the arrow at 100 %, the gaps. It does
-- not follow "Arrow size": the yards stay where they are, and a bigger arrow grows to the right (user).
-- R106-60: the yards a little smaller (85 % of the title's size, was 1 pt less) and stacked above the arrow (user):
-- the room is the wider of the two (the widest yards, the arrow at 100 %) and the gap before them
local function distanceTextSize(size) return math.max(math.floor((tonumber(size) or 12) * 0.85 + 0.5), 8) end
api.distanceTextSize = distanceTextSize
-- R106-63: "Show distance" (db.distanceText) and "Show arrow" (db.distanceArrow), both on by default: the room is
-- what is shown (the yards only, the arrow only, or the wider of the two)
local function showYards() return not (db and db.distanceText == false) end
local function showArrow() return not (db and db.distanceArrow == false) end
api.distanceArrowShown, api.distanceYardsShown = showArrow, showYards
-- R106-65: how far the distance column reaches down from the title's top (the yards, 1 px, the arrow), title units
function api.distanceColumnHeight(size)
	local h = 0
	if showYards() then h = h + distanceTextSize(size) + 1 end
	if showArrow() then h = h + arrowSize(size) end
	return h
end
local function distanceReserve(font, size, flags)
	size = tonumber(size) or 12
	local textW = 0
	if showYards() then
		if not measure then measure = UIParent:CreateFontString(nil, "OVERLAY"); measure:Hide() end
		if font then measure:SetFont(font, distanceTextSize(size), flags) end
		measure:SetText((db and db.distanceEta) and "9.9k yds 9:59" or "9.9k yds")
		textW = math.ceil(measure:GetStringWidth() or size * 4)
	end
	local arrowW = showArrow() and math.floor(size + 0.5) or 0
	return math.max(textW, arrowW) + DIST_GAP, textW
end
api.distanceArrowSize = arrowSize
api.questDistanceReserve = distanceReserve

local function hideDistance(fs)
	local w = fs and fs.qtsDistance
	if w then w.text:Hide(); w.arrow:Hide() end
	if fs then distanceShown[fs] = nil end
end
api.hideQuestDistance = hideDistance

-- The room is kept only on titles of quests that show a distance (the rest keep their full width and do not wrap for
-- nothing). Whether one does: the same lookup as the display, with the player's place read at most twice a second.
local meCache, meAt
-- R106-83: quests done inside a dungeon or raid (the game's Dungeon or Raid tag) get no distance or arrow (user):
-- outside, they could only point at the instance's map spot
local function isInstanceQuest(id)
	local getTag = C_QuestLog and C_QuestLog.GetQuestTagInfo
	if not getTag then return false end
	local ok, tag = pcall(getTag, id)
	if not ok or type(tag) ~= "table" then return false end
	local name = type(tag.tagName) == "string" and not isSecret(tag.tagName) and tag.tagName:lower() or ""
	local enum = Enum and Enum.QuestTag or {}
	local tagID = tag.tagID
	if name:find("dungeon", 1, true) or name:find("raid", 1, true) then return true end
	return tagID ~= nil and (tagID == enum.Dungeon or tagID == enum.Raid or tagID == TAG_ID.dungeon
		or tagID == TAG_ID.raid or tagID == enum.Raid10 or tagID == enum.Raid25)
end
api.isInstanceQuest = isInstanceQuest

-- 3.2: only the closest quests show their distance and arrow (user: "only the closest 3 quests"). db.distanceClosest:
-- how many (3 by default, 0 = every quest). Worked out at most once a second from every quest in the log; a quest
-- already in the set counts 30 yards closer, so two quests at about the same distance do not swap back and forth (each
-- swap lays the titles out again).
local nearSet, nearAt = nil, -10
local NEAR_KEEP = 30
local function closestLimit()
	local n = tonumber(db and db.distanceClosest)
	if n == nil then return 3 end
	return math.max(math.floor(n), 0)
end
local function nearQuests(me)
	local limit = closestLimit()
	if limit == 0 or not me then return nil end
	local now = GetTime()
	if nearSet and now - nearAt < 1 then return nearSet end
	local list = {}
	local log = rawget(_G, "C_QuestLog")
	local count = log and log.GetNumQuestLogEntries and log.GetNumQuestLogEntries() or 0
	for i = 1, count do
		local info = log.GetInfo and log.GetInfo(i)
		local id = info and not info.isHeader and not info.isHidden and info.questID
		if type(id) == "number" and not isInstanceQuest(id) then
			local yards = api.questDirection(id, me)
			if type(yards) == "number" then
				if nearSet and nearSet[id] then yards = yards - NEAR_KEEP end
				list[#list + 1] = { id = id, d = yards }
			end
		end
	end
	-- no quest with a place known: no limit (nothing to compare)
	if #list == 0 then nearSet, nearAt = nil, now return nil end
	table.sort(list, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.id < b.id end)
	local set = {}
	for i = 1, math.min(limit, #list) do set[list[i].id] = true end
	nearSet, nearAt = set, now
	return set
end
api.distanceNearSet = nearQuests
local function isNear(id, me)
	local set = nearQuests(me)
	return set == nil or set[id] == true
end

local function hasDistance(id)
	if not (db and db.questDistance ~= false) or type(id) ~= "number" or not api.questDirection then return false end
	if not (showYards() or showArrow()) then return false end -- both hidden: no room kept
	if isInstanceQuest(id) then return false end
	local now = GetTime()
	if not meAt or now - meAt > 0.5 then
		meCache, meAt = api.playerWorldPos and api.playerWorldPos() or nil, now
	end
	return meCache ~= nil and api.questDirection(id, meCache) ~= nil and isNear(id, meCache)
end
api.questHasDistance = hasDistance

local sinceSpot, sinceTurn = 1, 1
-- the yards end at the title's right edge, in the room the title keeps for them (fs.qtsReserve)
local function placeDistanceText(fs, w)
	w.text:ClearAllPoints()
	w.text:SetPoint("TOPRIGHT", fs, "TOPRIGHT", (fs.qtsReserve or DIST_GAP) - DIST_GAP, 0)
end
-- the distance and arrow on a title whose right edge has fs.qtsReserve of room; a title without the room (its quest
-- showed no distance when it was laid out) is still watched, so it gets the room once a distance appears
local function attachDistance(fs, id)
	if not (db and db.questDistance ~= false) or type(id) ~= "number" then hideDistance(fs) return end
	local w = fs.qtsDistance
	if not w then
		local parent = fs:GetParent()
		w = { text = parent:CreateFontString(nil, "OVERLAY"), arrow = parent:CreateTexture(nil, "OVERLAY", nil, 7) }
		-- SetTexture answers false when the file cannot be loaded (a file added since the game started): the game's
		-- own minimap player arrow then, so an arrow always shows
		if w.arrow:SetTexture(DIR_ARROW) == false then
			w.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
			w.arrowFallback = true
		end
		w.text:SetJustifyH("RIGHT")
		w.text:SetShadowOffset(1, -1)
		w.text:SetShadowColor(0, 0, 0, 1)
		w.text:SetTextColor(0.85, 0.85, 0.85)
		fs.qtsDistance = w
	end
	local font, size, flags = fs:GetFont()
	size = tonumber(size) or 12
	if font then w.text:SetFont(font, distanceTextSize(size), flags) end
	w.arrow:SetSize(arrowSize(size), arrowSize(size))
	w.arrow:SetAlpha(arrowAlpha())
	-- the yards at a fixed place (where they end does not depend on the arrow's size); the arrow starts right after
	-- them, centred on them, and a bigger one grows to the right
	w.base = math.floor(size + 0.5)
	placeDistanceText(fs, w)
	w.arrow:ClearAllPoints()
	-- under the yards, centred on them (R106-60); a bigger arrow grows downwards
	if showYards() then
		w.arrow:SetPoint("TOP", w.text, "BOTTOM", 0, -1)
	else
		w.arrow:SetPoint("TOPRIGHT", w.text, "TOPRIGHT", 0, 0) -- the yards hidden: the arrow in their place
	end
	local new = distanceShown[fs] ~= id
	if new then
		distanceShown[fs] = id
		fs.qtsYards, fs.qtsAngle = nil, nil
		sinceSpot = 1 -- measured on the next frame
	end
	if new or not fs.qtsReserve then w.text:Hide(); w.arrow:Hide() end
end
api.attachQuestDistance = attachDistance

-- CONSTRAINT: not Texture:SetRotation: in the Forever client it left the arrow blank (/qt distance: every turned
-- arrow's GetTexture was nil, the unturned ones kept the file). The texture's corners are sampled turned the other way
-- instead (SetTexCoord with the four corners), which turns the image by angle (counter-clockwise, as GetPlayerFacing
-- counts). Only what lies within the image's inscribed circle always shows, so DirArrow.tga keeps its art inside it.
local function turnTexture(tex, angle)
	local c, s = math.cos(angle), math.sin(angle)
	-- a quad corner (x right, y up, from the centre in half sizes) -> the texture point it shows (u right, v down)
	local function at(x, y) return 0.5 + x * c + y * s, 0.5 - (y * c - x * s) end
	local ulu, ulv = at(-0.5, 0.5)
	local llu, llv = at(-0.5, -0.5)
	local uru, urv = at(0.5, 0.5)
	local lru, lrv = at(0.5, -0.5)
	tex:SetTexCoord(ulu, ulv, llu, llv, uru, urv, lru, lrv)
	tex.qtsAngle = angle
end
api.turnTexture = turnTexture

local lastRelayout = 0
local CLOSE_YARDS = 20 -- 3.2 (user): within this the yards glow gold (an animation: off with them)
local function refreshDistances(spot, dt)
	local me = spot and api.playerWorldPos and api.playerWorldPos() or nil
	if spot then meCache, meAt = me, GetTime() end
	local facing = GetPlayerFacing and GetPlayerFacing() or nil
	if facing ~= nil and (isSecret(facing) or type(facing) ~= "number") then facing = nil end
	for fs, id in pairs(distanceShown) do
		local w = fs.qtsDistance
		if w and fs:IsVisible() then
			if spot then
				local yards, angle
				-- (an instance quest has none: R106-83; else its room would be asked for again and again)
				if me and api.questDirection and not isInstanceQuest(id) then yards, angle = api.questDirection(id, me) end
				if yards and not isNear(id, me) then yards, angle = nil, nil end -- 3.2: only the closest quests
				fs.qtsYards, fs.qtsAngle = yards, angle
				-- shown only where the title kept the room for it
				-- 3.2 (user): the number counts toward the new one (Animations.lua animTicker; the ticks below)
				if yards and fs.qtsReserve and showYards() then
					local v = api.animTicker and api.animTicker(fs.qtsShownYards, yards, 0) or yards
					fs.qtsShownYards = v
					w.text:SetText(distanceLabel(v)); w.text:Show()
				else
					fs.qtsShownYards = nil
					w.text:Hide()
				end
				-- found or lost since the title was laid out: its room changes (our frame draws it again)
				if (yards ~= nil) ~= (fs.qtsReserve ~= nil) and GetTime() - lastRelayout > 2 then
					lastRelayout = GetTime()
					if api.refreshQuests then api.refreshQuests() end
				end
			end
			if not spot and fs.qtsYards and fs.qtsShownYards and fs.qtsShownYards ~= fs.qtsYards and api.animTicker
				and w.text:IsShown() then
				local v = api.animTicker(fs.qtsShownYards, fs.qtsYards, dt)
				local was = math.floor(fs.qtsShownYards + 0.5)
				fs.qtsShownYards = v
				if math.floor(v + 0.5) ~= was then w.text:SetText(distanceLabel(v)) end
			end
			-- no facing from the game (restricted there): the arrow points the map's way (north up), as a map would
			if fs.qtsYards and fs.qtsAngle and fs.qtsReserve and showArrow() then
				-- the image went empty (seen in Forever, cause unknown): set it again before showing the arrow
				if w.arrow.GetTexture and w.arrow:GetTexture() == nil then
					w.arrowResets = (w.arrowResets or 0) + 1
					if w.arrow:SetTexture(w.arrowFallback and "Interface\\Minimap\\MinimapArrow" or DIR_ARROW) == false then
						w.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
						w.arrowFallback = true
					end
				end
				-- turned only when the angle moved (most frames it does not): lighter on the frame rate
				local angle = fs.qtsAngle - (facing or 0)
				-- 3.2: turned a little each frame toward the new angle (Animations.lua), not in one jump
				if api.animArrowAngle then angle = api.animArrowAngle(w.arrow.qtsAngle, angle, dt) end
				local moved = w.arrow.qtsAngle and math.abs((angle - w.arrow.qtsAngle + math.pi) % (2 * math.pi) - math.pi)
				if not moved or moved > 0.02 then turnTexture(w.arrow, angle) end
				w.arrow:Show()
			else
				w.arrow:Hide()
			end
			-- close by: the yards glow gold and breathe
			local close = fs.qtsYards and fs.qtsYards < CLOSE_YARDS and api.animOn and api.animOn("close")
			if close then
				w.text:SetTextColor(1, 0.82, 0.25)
				w.text:SetAlpha(0.75 + 0.25 * math.sin(GetTime() * 5))
				w.closeGlow = true
			elseif w.closeGlow then
				w.text:SetTextColor(0.85, 0.85, 0.85)
				w.text:SetAlpha(1)
				w.closeGlow = nil
			end
		end
	end
end
api.refreshQuestDistances = refreshDistances

-- /qt distance: why a title shows or hides its arrow (the place, the direction, the facing, the texture)
function api.distanceReport(say)
	local facing = GetPlayerFacing and GetPlayerFacing() or nil
	local me = api.playerWorldPos and api.playerWorldPos() or nil
	say(("distance: option %s, facing %s, position %s"):format(tostring(db and db.questDistance ~= false),
		facing and ("%.2f"):format(facing) or "none (restricted here: arrows point north-up)",
		me and ("map %s"):format(tostring(me.map)) or "none (instance or no map position)"))
	local n = 0
	for fs, id in pairs(distanceShown) do
		local w = fs.qtsDistance
		if w and fs:IsVisible() then
			n = n + 1
			local yards, angle
			if me and api.questDirection then yards, angle = api.questDirection(id, me) end
			local tex = w.arrow.GetTexture and w.arrow:GetTexture()
			-- the arrow itself: size, opacity, whether it is really on screen, where, its texture coordinates
			local a = w.arrow
			local aw, ah = a:GetSize()
			local ul1, ul2 = a:GetTexCoord()
			local left, top = a:GetLeft(), a:GetTop()
			say(("    arrow: size %sx%s, alpha %.2f, visible %s, at %s,%s, texcoord UL %s,%s, image re-set %d time(s), angle %s"):format(
				tostring(aw and math.floor(aw + 0.5)), tostring(ah and math.floor(ah + 0.5)), a:GetAlpha() or -1,
				tostring(a:IsVisible()), tostring(left and math.floor(left)), tostring(top and math.floor(top)),
				ul1 and ("%.2f"):format(ul1) or "nil", ul2 and ("%.2f"):format(ul2) or "nil", w.arrowResets or 0,
				a.qtsAngle and ("%.2f"):format(a.qtsAngle) or "none"))
			say(("  quest %d: %s, direction %s, room %s, arrow %s, texture %s"):format(id,
				yards and distanceText(yards) or "no place", angle and ("%.2f"):format(angle) or "none (distance only)",
				fs.qtsReserve and "yes" or "no", w.arrow:IsShown() and "shown" or "hidden",
				tostring(tex) .. (w.arrowFallback and " (DirArrow.tga not found: the game's minimap arrow)" or "")))
		end
	end
	if n == 0 then say("  no quest title shows a distance") end
	say("A texture added since the game started (Textures\\DirArrow.tga) is found only after a full game restart, not /reload.")
end

local SPOT_EVERY, TURN_EVERY = 0.5, 0.1
local distanceClock = CreateFrame("Frame")
distanceClock:SetScript("OnUpdate", function(_, elapsed)
	if not next(distanceShown) then return end
	sinceSpot, sinceTurn = sinceSpot + elapsed, sinceTurn + elapsed
	-- 3.2: with animations on the arrows turn smoothly, so they are drawn more often
	local every = api.animOn and api.animOn("arrow") and 0.03 or TURN_EVERY
	if sinceTurn < every then return end
	local dt = sinceTurn
	sinceTurn = 0
	local spot = sinceSpot >= SPOT_EVERY
	if spot then sinceSpot = 0 end
	refreshDistances(spot, dt)
end)

-- 3.2 (user: "Delete the old tracker's code"): the settings below reach our own tracker (Own/Frame.lua hooks
-- applyExtras and applyWrap and redraws). Nothing here touches Blizzard's tracker any more.
function api.applyExtras() end
function api.applyWrap() end
function api.applyQuestDistance() api.applyExtras() end
function api.applyProgressBars() api.applyExtras() end
-- Quest list > "Quests" header colour and the line under it: our Quests header (Own/Frame.lua headerLook)
function api.applyQuestsHeaderLook()
	if api.ownApplyHeaderLook then api.ownApplyHeaderLook() end
end

function api.extrasDebug(say)
	say(("rewards: xp=%s gold=%s; spacing=%s; XP function: %s, gold function: %s"):format(
		tostring(db.showXP), tostring(db.showGold), tostring(db.spacing),
		tostring((C_QuestLog and C_QuestLog.GetQuestLogRewardXP) or _G.GetQuestLogRewardXP ~= nil),
		tostring((C_QuestLog and C_QuestLog.GetQuestLogRewardMoney) or _G.GetQuestLogRewardMoney ~= nil)))
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	-- 2.9.3: the two attunement-star options became one
	if db.attuneStar == false then db.attunementStar = false end
	db.attuneStar = nil
	db.ahValue = nil -- 3.0.1: auction house prices removed
	local frame = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED" }) do pcall(frame.RegisterEvent, frame, e) end
	frame:SetScript("OnEvent", function(_, _, questID)
		api.forgetRep(type(questID) == "number" and questID or nil)
	end)
end
