-- 3.2 Rewards: on a quest's reward choice
--   a green arrow on each reward that is better than what you wear (db.rewardArrow): its main stat, stamina, armor
--     and weapon damage, weighed for your class (or the stat you pick, db.rewardStat), against the item in the same
--     slot (the weaker one for rings, trinkets and one-hand weapons); armor your class cannot wear is never an upgrade.
--   a disenchant icon on each reward that can be disenchanted (db.rewardDisenchant): green or better armor and
--     weapons; hover the reward: what it most likely disenchants into (the game's well-known level ranges).
--   auto pick (db.autoReward, off by default): with "Turn in finished quests" on (AutoQuest.lua), the best upgrade
--     ("upgrade", the reward that sells for the most when none is better) or the reward that sells for the most
--     ("value") is taken for you. Shift held: you pick, as every automation.
-- CONSTRAINT: GetNumQuestChoices, GetQuestItemLink and GetQuestReward are old globals (not in the Forever ledger):
-- each is checked before use. An item whose data is not loaded yet makes the pick wait (asked again shortly).
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function g(name) local fn = rawget(_G, name); return type(fn) == "function" and fn or nil end
local function itemInfo(link)
	local fn = (C_Item and C_Item.GetItemInfo) or g("GetItemInfo")
	if not fn or not link then return nil end
	local ok, name, _, quality, ilvl, minLevel, _, _, _, equipLoc, _, price, classID, subclassID = pcall(fn, link)
	if not ok or name == nil then return nil end
	return { quality = tonumber(quality) or 0, ilvl = tonumber(ilvl) or 0, minLevel = tonumber(minLevel) or 0,
		equipLoc = equipLoc, price = tonumber(price) or 0, classID = tonumber(classID), subclassID = tonumber(subclassID) }
end
local function itemStats(link)
	local fn = (C_Item and C_Item.GetItemStats) or g("GetItemStats")
	if not fn or not link then return {} end
	local ok, stats = pcall(fn, link)
	return ok and type(stats) == "table" and stats or {}
end

---------------------------------------------------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------------------------------------------------
local CLASS_STAT = { WARRIOR = "str", PALADIN = "str", DEATHKNIGHT = "str", HUNTER = "agi", ROGUE = "agi",
	DRUID = "agi", SHAMAN = "int", PRIEST = "int", MAGE = "int", WARLOCK = "int", MONK = "agi" }
local STAT_KEY = { str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", int = "ITEM_MOD_INTELLECT_SHORT",
	spi = "ITEM_MOD_SPIRIT_SHORT", sta = "ITEM_MOD_STAMINA_SHORT" }
-- the heaviest armor each class wears (Enum.ItemArmorSubclass: 1 cloth, 2 leather, 3 mail, 4 plate), and from what level
local ARMOR = { WARRIOR = { 3, 4, 40 }, PALADIN = { 3, 4, 40 }, DEATHKNIGHT = { 4 }, HUNTER = { 2, 3, 40 },
	SHAMAN = { 2, 3, 40 }, ROGUE = { 2 }, DRUID = { 2 }, MONK = { 2 }, PRIEST = { 1 }, MAGE = { 1 }, WARLOCK = { 1 } }
local SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local SLOTS = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 } }

local function myClass()
	local ok, _, file = pcall(UnitClass, "player")
	return ok and not isSecret(file) and file or "WARRIOR"
end
local function mainStat()
	local pick = db and db.rewardStat
	if pick and pick ~= "auto" and STAT_KEY[pick] then return pick end
	return CLASS_STAT[myClass()] or "str"
end
api.rewardMainStat = mainStat
local function canWear(info)
	if not info then return false end
	if info.classID == 4 then -- armor
		local sub = info.subclassID
		if sub == 6 then return SHIELD_CLASSES[myClass()] == true end
		if sub and sub >= 1 and sub <= 4 then
			local a = ARMOR[myClass()] or { 1 }
			local best = a[1]
			if a[2] and (UnitLevel("player") or 1) >= (a[3] or 1) then best = a[2] end
			return sub <= best
		end
	end
	return true
end
-- main stat 1, stamina 0.6, spirit 0.3 for casters, armor 0.03, weapon damage per second 3
local function score(link)
	local s = itemStats(link)
	local main = mainStat()
	local function v(key) return tonumber(s[key]) or 0 end
	local total = v(STAT_KEY[main]) + v(STAT_KEY.sta) * 0.6 + v("RESISTANCE0_NAME") * 0.03
		+ v("ITEM_MOD_DAMAGE_PER_SECOND_SHORT") * 3
	if main == "int" then total = total + v(STAT_KEY.spi) * 0.3 end
	return total
end
api.rewardScore = score
local function equippedScore(slots)
	local worst
	for _, slot in ipairs(slots) do
		local ok, link = pcall(GetInventoryItemLink, "player", slot)
		local sc = (ok and type(link) == "string") and score(link) or 0
		if worst == nil or sc < worst then worst = sc end
	end
	return worst or 0
end
local DE_GREEN = { { 15, "Strange Dust, Lesser Magic Essence" }, { 20, "Strange Dust, Greater Magic Essence" },
	{ 25, "Strange Dust, Lesser Astral Essence" }, { 30, "Soul Dust, Greater Astral Essence" },
	{ 35, "Soul Dust, Lesser Mystic Essence" }, { 40, "Vision Dust, Greater Mystic Essence" },
	{ 45, "Vision Dust, Lesser Nether Essence" }, { 50, "Dream Dust, Greater Nether Essence" },
	{ 55, "Dream Dust, Lesser Eternal Essence" }, { 999, "Illusion Dust, Greater Eternal Essence" } }
local DE_BLUE = { { 25, "Small Glimmering Shard" }, { 30, "Large Glimmering Shard" }, { 35, "Small Glowing Shard" },
	{ 40, "Large Glowing Shard" }, { 45, "Small Radiant Shard" }, { 50, "Large Radiant Shard" },
	{ 55, "Small Brilliant Shard" }, { 999, "Large Brilliant Shard" } }
local function disenchantText(info)
	if not info or not (info.classID == 2 or info.classID == 4) or info.quality < 2 then return nil end
	local list = info.quality == 2 and DE_GREEN or DE_BLUE
	if info.quality >= 4 then return "Nexus Crystal or a Large Brilliant Shard" end
	for _, r in ipairs(list) do if info.ilvl <= r[1] then return r[2] end end
	return nil
end
api.rewardDisenchantText = disenchantText

-- every reward choice: { link, info, value, gain, upgrade, de }; pending: an item's data is not loaded yet
function api.rewardChoices()
	local out, pending = {}, false
	local num, getLink = g("GetNumQuestChoices"), g("GetQuestItemLink")
	if not (num and getLink) then return out, false end
	local okN, n = pcall(num)
	n = okN and tonumber(n) or 0
	for i = 1, n do
		local ok, link = pcall(getLink, "choice", i)
		link = ok and type(link) == "string" and link or nil
		local info = itemInfo(link)
		if not info then pending = true end
		local count = 1
		local getInfo = g("GetQuestItemInfo")
		if getInfo then local okC, _, _, c = pcall(getInfo, "choice", i); count = okC and tonumber(c) or 1 end
		local r = { index = i, link = link, info = info, value = info and info.price * math.max(count, 1) or 0 }
		local slots = info and SLOTS[info.equipLoc or ""]
		if slots and canWear(info) then
			r.gain = score(link) - equippedScore(slots)
			r.upgrade = r.gain > 0.5
		end
		r.de = disenchantText(info)
		out[i] = r
	end
	return out, pending
end
-- the choice to take: mode "upgrade" (best gain; else the most valuable) or "value"
function api.pickReward(mode)
	local list, pending = api.rewardChoices()
	if #list < 2 then return nil end
	if pending then return nil, true end
	local best
	if mode == "upgrade" then
		for _, r in ipairs(list) do
			if r.upgrade and (not best or r.gain > best.gain) then best = r end
		end
	end
	if not best then
		for _, r in ipairs(list) do if not best or r.value > best.value then best = r end end
	end
	return best and best.index or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Marks on the reward buttons
---------------------------------------------------------------------------------------------------------------------
local marks = {}
local function rewardButton(i)
	local frame = rawget(_G, "QuestInfoRewardsFrame")
	if frame and type(frame.RewardButtons) == "table" then
		for _, b in ipairs(frame.RewardButtons) do
			if b.type == "choice" and b.GetID and b:GetID() == i and b:IsShown() then return b end
		end
	end
	local b = rawget(_G, "QuestInfoRewardsFrameQuestInfoItem" .. i)
	if b and (b.type == nil or b.type == "choice") then return b end
	return nil
end
local function markFor(button)
	local m = marks[button]
	if m then return m end
	m = CreateFrame("Frame", nil, button)
	m:SetAllPoints()
	m:SetFrameLevel(button:GetFrameLevel() + 6)
	m:EnableMouse(false)
	m.arrow = m:CreateTexture(nil, "OVERLAY")
	m.arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
	m.arrow:SetTexCoord(0, 1, 1, 0) -- pointing up
	m.arrow:SetSize(16, 16)
	m.arrow:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", 22, 0)
	m.de = m:CreateTexture(nil, "OVERLAY")
	m.de:SetTexture("Interface\\Icons\\INV_Enchant_Disenchant")
	m.de:SetSize(13, 13)
	m.de:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -1)
	if button.HookScript then
		button:HookScript("OnEnter", function(self)
			local d = marks[self] and marks[self].data
			if not (d and GameTooltip:IsOwned(self)) then return end
			if d.upgrade and db.rewardArrow ~= false then GameTooltip:AddLine("Upgrade for you", 0.3, 1, 0.3) end
			if d.de and db.rewardDisenchant ~= false then GameTooltip:AddLine("Disenchants into: " .. d.de, 0.75, 0.55, 1, true) end
			GameTooltip:Show()
		end)
	end
	marks[button] = m
	return m
end
local function hideMarks() for _, m in pairs(marks) do m:Hide(); m.data = nil end end
local retries = 0
local function markRewards()
	hideMarks()
	if not db or (db.rewardArrow == false and db.rewardDisenchant == false) then return end
	local list, pending = api.rewardChoices()
	for i, r in ipairs(list) do
		local b = rewardButton(i)
		if b then
			local m = markFor(b)
			m.data = r
			m.arrow:SetShown(db.rewardArrow ~= false and r.upgrade == true)
			m.de:SetShown(db.rewardDisenchant ~= false and r.de ~= nil)
			m:Show()
		end
	end
	if pending and retries < 4 then
		retries = retries + 1
		C_Timer.After(0.4, function() pcall(markRewards) end)
	end
end
api.rewardMark = markRewards -- (tests)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "QUEST_COMPLETE" then
		retries = 0
		C_Timer.After(0.05, function() pcall(markRewards) end)
	else
		hideMarks()
	end
end)
ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	for _, e in ipairs({ "QUEST_COMPLETE", "QUEST_FINISHED" }) do pcall(events.RegisterEvent, events, e) end
end

---------------------------------------------------------------------------------------------------------------------
-- Settings: Helpers > Rewards
---------------------------------------------------------------------------------------------------------------------
api.pageDeclarers = api.pageDeclarers or {}
api.pageDeclarers[#api.pageDeclarers + 1] = function(k)
	k.page("rewards", "quests", "Rewards")
	k.pageByKey.rewards.cardTitle = "Picking a quest reward"
	k.heading("Marks")
	k.check("Arrow on upgrades", function() return db.rewardArrow ~= false end,
		function(v) db.rewardArrow = v and true or false end)
	k.help("a green arrow on a reward that is better than what you wear")
	k.choice("Stat to weigh", function()
		return { { "auto", "Your class's" }, { "str", "Strength" }, { "agi", "Agility" }, { "int", "Intellect" },
			{ "spi", "Spirit" }, { "sta", "Stamina" } }
	end, function() return db.rewardStat or "auto" end, function(v) db.rewardStat = v end,
		function() return db.rewardArrow ~= false or (db.autoReward or "off") == "upgrade" end, 24)
	k.check("Disenchant icon", function() return db.rewardDisenchant ~= false end,
		function(v) db.rewardDisenchant = v and true or false end)
	k.help("on rewards that can be disenchanted; hover to see what they most likely give")
	k.heading("Auto pick")
	k.choice("Pick the reward for me", function()
		return { { "off", "Off: I pick" }, { "upgrade", "Best upgrade" }, { "value", "Sells for the most" } }
	end, function() return db.autoReward or "off" end, function(v) db.autoReward = v end)
	k.help("needs \"Turn in finished quests\" (Helpers > NPCs). Picks the best upgrade, else the most valuable reward. Hold Shift to pick yourself.")
	k.pageByKey.rewards.reset = k.reset
end
