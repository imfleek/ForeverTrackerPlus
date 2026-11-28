-- ForeverTrackerPlus: "Loot you want" on the dungeon card (3.2, user: "use SpecBisTooltip & DungeonJournal").
-- The items of this dungeon's bosses come from DungeonJournal (ForeverDungeonJournal_NS.DB[dungeon].bosses[i].loot:
-- { itemID, name, slot, quality }). An item is wanted when it is one of your DungeonJournal favourites
-- (FDJ.IsFavouriteItem), or when SpecBisTooltip marks it best in slot (or pre-best in slot) for your spec.
-- SpecBisTooltip keeps its lists to itself, so its own words are read: our hidden tooltip shows the item, SpecBisTooltip
-- adds its lines to it (it adds them to every item tooltip), and the first of its lines about your spec is read (its
-- lines end with its icon; your spec's line has no ":"; green: best in slot, yellow: pre-best in slot, red: not).
-- Nothing of SpecBisTooltip is copied. Read again when your talents change. Only what the game has loaded is read;
-- the rest is asked for and read when it comes.
-- Option: Dungeons > "Loot you want" (db.dungeonLoot, on by default).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local GREEN, YELLOW = "|cff90ee90", "|cffffff4b" -- SpecBisTooltip's own colours for best in slot and pre-best
local verdicts = {} -- itemID -> "bis", "pre", false (read), nil (not yet)
local scanTip, sbtIcon
local sparkled = {} -- "dungeon:run start" -> true (the line sparkled for that run)
function api.dungeonLootSparkled(key) if key then sparkled[key] = true end end

local function g(name) local v = rawget(_G, name); return v end
local function sbtLoaded()
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("SpecBisTooltip") or false
end
local function iconOfSbt()
	if sbtIcon ~= nil then return sbtIcon end
	sbtIcon = false
	local meta = C_AddOns and C_AddOns.GetAddOnMetadata
	local ok, v = pcall(meta or function() end, "SpecBisTooltip", "IconTexture")
	if ok and v and v ~= "" then sbtIcon = "|T" .. tostring(v) end
	return sbtIcon
end

-- what SpecBisTooltip says about the item for your spec: "bis", "pre", false, or nil (not loaded yet)
local function readSbt(id)
	if not sbtLoaded() then return false end
	local icon = iconOfSbt()
	if not icon then return false end
	if C_Item and C_Item.GetItemInfoInstant then
		local ok, _, _, _, equip = pcall(C_Item.GetItemInfoInstant, id)
		if ok and (equip == nil or equip == "") then return false end
	end
	if GetItemInfo and not GetItemInfo(id) then
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		return nil
	end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "ForeverTrackerPlusLootScan", UIParent, "GameTooltipTemplate")
	end
	scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip:ClearLines()
	local ok = pcall(scanTip.SetItemByID, scanTip, id)
	if not ok then scanTip:Hide() return false end
	local verdict = false
	for i = 1, scanTip:NumLines() do
		local l, r = _G["ForeverTrackerPlusLootScanTextLeft" .. i], _G["ForeverTrackerPlusLootScanTextRight" .. i]
		local lt, rt = l and l:GetText(), r and r:GetText()
		if type(rt) == "string" and rt:find(icon, 1, true) and type(lt) == "string" and not lt:find(":", 1, true) then
			if lt:find(GREEN, 1, true) then verdict = "bis" elseif lt:find(YELLOW, 1, true) then verdict = "pre" end
			break
		end
	end
	scanTip:Hide()
	return verdict
end
api.dungeonLootReadSbt = readSbt -- (tests)

-- the wanted items of this dungeon: { { id, name, boss, why } }
local function wanted(dungeon)
	local fdj = g("ForeverDungeonJournal_NS")
	local d = fdj and type(fdj.DB) == "table" and fdj.DB[dungeon]
	local out, waiting = {}, false
	if type(d) ~= "table" or type(d.bosses) ~= "table" then return out, false end
	for _, boss in ipairs(d.bosses) do
		for _, item in ipairs(type(boss) == "table" and type(boss.loot) == "table" and boss.loot or {}) do
			local id = type(item) == "table" and tonumber(item[1])
			if id then
				local why
				if type(fdj.IsFavouriteItem) == "function" then
					local ok, fav = pcall(fdj.IsFavouriteItem, id)
					if ok and fav then why = "favourite" end
				end
				if verdicts[id] == nil then
					local v = readSbt(id)
					if v == nil then waiting = true else verdicts[id] = v end
				end
				if verdicts[id] then why = why and (why .. ", " .. (verdicts[id] == "bis" and "best in slot" or "pre-best in slot"))
					or (verdicts[id] == "bis" and "best in slot" or "pre-best in slot") end
				if why then out[#out + 1] = { id = id, name = tostring(item[2] or id), boss = tostring(boss.name or "?"), why = why } end
			end
		end
	end
	return out, waiting
end
api.dungeonWantedLoot = wanted

-- the dungeon DungeonJournal knows this instance as (its run, else the instance's name)
local function dungeonName(name)
	local fdj = g("ForeverDungeonJournal_NS")
	local run = fdj and type(fdj.RunLogGetCurrentRun) == "function" and select(2, pcall(fdj.RunLogGetCurrentRun)) or nil
	if type(run) == "table" and type(run.dungeon) == "string" then return run.dungeon end
	local t = g("ForeverDungeonJournalRunTracker")
	if type(t) == "table" and type(t.run) == "table" and type(t.run.dungeon) == "string" then return t.run.dungeon end
	return name
end

local function colourOf(id)
	local _, link, quality = nil, nil, nil
	if GetItemInfo then _, link, quality = GetItemInfo(id) end
	return link, quality
end

-- the card's line (DungeonPlus.lua entries)
function api.dungeonLootEntry(name)
	local db = ns.db
	if not db or db.dungeonLoot == false or not g("ForeverDungeonJournal_NS") then return nil end
	local list = wanted(dungeonName(name))
	if #list == 0 then return nil end
	local first = colourOf(list[1].id) or list[1].name
	-- 3.2 (user): the line sparkles once each time you go in (Animations.lua animLootSparkle, DungeonPlus.lua)
	local run = api.dungeonRunForTests and api.dungeonRunForTests()
	local key = tostring(name) .. ":" .. tostring(run and run.start or 0)
	local more = #list > 1 and ("  +%d"):format(#list - 1) or ""
	return { sparkle = not sparkled[key] and key or nil, text = ("Loot you want: %s|cffaaaaaa%s|r"):format(first, more), tip = function()
		local tip = { { "Loot you want here", 1, 0.82, 0 } }
		for _, it in ipairs(list) do
			tip[#tip + 1] = { ("%s  |cffaaaaaa%s, %s|r"):format(colourOf(it.id) or it.name, it.boss, it.why), 1, 1, 1 }
		end
		tip[#tip + 1] = { "From your DungeonJournal favourites and SpecBisTooltip's best in slot for your spec.", 0.6, 0.6, 0.6 }
		return tip
	end }
end

-- talents changed: SpecBisTooltip's answers change; an item came in: read it now
local events = CreateFrame("Frame")
for _, e in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do
	pcall(events.RegisterEvent, events, e)
end
local pending
events:SetScript("OnEvent", function(_, event)
	if event ~= "GET_ITEM_INFO_RECEIVED" then wipe(verdicts) end
	if pending or not (C_Timer and C_Timer.After) then return end
	pending = true
	C_Timer.After(1, function()
		pending = nil
		if api.applyLayout and not (InCombatLockdown and InCombatLockdown()) then api.applyLayout() end
	end)
end)
