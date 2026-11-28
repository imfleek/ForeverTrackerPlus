-- 3.2 Guide pages (Settings > Guides) and the zone's exploration on its header:
--   Attunements: the raid attunement chains (our own list of quest IDs, each a fact of the game), step by step.
--   Class quests: every quest for your class (Questie's requiredClasses), grouped into chains (nextQuestInChain).
--   Profession quests: quests that need a profession rank (Questie's requiredSkill), by profession, with your rank.
--   Zone header (db.zoneExplored, Quest list > Zone headers): "Explored 7/12" after your zone's name (the zone's
--     "Explore" achievement; 3.2: LegacyForever is no longer read, user); hover it for the areas not found yet (user). The Unexplored areas page is gone (user).
-- Click a step: a waypoint to where it starts (Questie). Questie is needed for the class and profession pages.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_OPEN = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_LOG = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_MAP = "Interface\\Icons\\INV_Misc_Map_01"
local GREEN = { 0.45, 0.9, 0.45 }
local GREY = { 0.6, 0.6, 0.6 }

local refreshPage = function() end
local function done(id) return api.guideQuestDone and api.guideQuestDone(id) or false end
local function inLog(id) return api.guideQuestInLog and api.guideQuestInLog(id) or false end
local function qget(id, field)
	if not api.questieGet then return nil end
	local ok, v = pcall(api.questieGet, "Quest", id, field)
	return ok and v or nil
end
local function questName(id)
	local n = qget(id, "name")
	if type(n) == "string" then return n end
	local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if type(t) == "string" and not isSecret(t) and t ~= "" then return t end
	return "Quest " .. tostring(id)
end
local function questLevel(id) return tonumber(qget(id, "questLevel")) or tonumber(qget(id, "requiredLevel")) or 0 end
local function questieReady() return api.questieOn and api.questieOn() end
-- one quest as a row: done / in your log / open; click: waypoint to its giver
local function stepRow(id, extraRight, isNext)
	local d, l = done(id), inLog(id)
	local map, x, y, zone, giver
	if api.guideGiverSpot and questieReady() then map, x, y, zone, giver = api.guideGiverSpot(id) end
	local level = questLevel(id)
	local right = d and "done" or l and "in your log" or (zone or "")
	if isNext and not d and not l then right = "next: " .. right end
	if extraRight then right = extraRight .. (right ~= "" and ("  " .. right) or "") end
	return { d and ICON_DONE or l and ICON_LOG or ICON_OPEN, (level > 0 and ("[%d] "):format(level) or "") .. questName(id),
		right, d and GREEN or nil,
		onClick = not d and map and function() api.guideWaypoint(map, x, y, giver or questName(id)) end or nil,
		tip = giver and { "Starts at: " .. giver .. (zone and (", " .. zone) or "") } or nil }
end
local function folded(key) return db and type(db.chainsClosed) == "table" and db.chainsClosed[key] == true end
local function toggleFold(key)
	db.chainsClosed = type(db.chainsClosed) == "table" and db.chainsClosed or {}
	db.chainsClosed[key] = not db.chainsClosed[key] or nil
	refreshPage()
end
-- a chain: a header that folds, then its steps (the first open step marked "next")
local function addChain(rows, key, title, ids, showDone)
	local n = 0
	for _, id in ipairs(ids) do if done(id) then n = n + 1 end end
	if n == #ids and not showDone then return end
	local closed = folded(key)
	rows[#rows + 1] = { nil, title, ("%d of %d done"):format(n, #ids), n == #ids and GREEN or nil, header = true,
		fold = closed, onClick = function() toggleFold(key) end, clickHint = "Click: open or close" }
	if closed then return end
	local nextShown = false
	for _, id in ipairs(ids) do
		local isNext = not nextShown and not done(id) and not inLog(id)
		if isNext then nextShown = true end
		rows[#rows + 1] = stepRow(id, nil, isNext)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Attunements
---------------------------------------------------------------------------------------------------------------------
local ATTUNEMENTS = {
	{ key = "mc", name = "Molten Core", quests = { 7848 } },
	{ key = "onyh", name = "Onyxia's Lair", faction = "Horde",
		quests = { 4903, 4941, 4974, 6566, 6567, 6568, 6569, 6570, 6584, 6582, 6583, 6585, 6601, 6602 } },
	{ key = "onya", name = "Onyxia's Lair", faction = "Alliance",
		quests = { 4182, 4183, 4184, 4185, 4186, 4223, 4224, 4241, 4242, 4264, 4282, 4322, 6402, 6403, 6501, 6502 } },
	{ key = "bwl", name = "Blackwing Lair", quests = { 7761 } },
	{ key = "naxx", name = "Naxxramas", any = { 9121, 9122, 9123 } },
}
api.chainsAttunements = ATTUNEMENTS -- (tests)
local function attunementRows()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local rows = { { nil, "The raids that need an attunement. Click a step for a waypoint to its giver (Questie).", note = true } }
	for _, a in ipairs(ATTUNEMENTS) do
		if not a.faction or a.faction == faction then
			if a.any then
				local d = false
				for _, id in ipairs(a.any) do if done(id) then d = true end end
				rows[#rows + 1] = { nil, a.name, d and "attuned" or "one of these, by your Argent Dawn standing",
					d and GREEN or nil, header = true }
				if not d then for _, id in ipairs(a.any) do rows[#rows + 1] = stepRow(id) end end
			else
				addChain(rows, "att:" .. a.key, a.name, a.quests, true)
			end
		end
	end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Class quests
---------------------------------------------------------------------------------------------------------------------
local function classBit()
	local _, _, id = UnitClass("player")
	return tonumber(id)
end
local function chainsOf(list)
	local set, isNext = {}, {}
	for _, id in ipairs(list) do set[id] = true end
	for _, id in ipairs(list) do
		local n = tonumber(qget(id, "nextQuestInChain"))
		if n and set[n] then isNext[n] = true end
	end
	local chains, used = {}, {}
	for _, id in ipairs(list) do
		if not isNext[id] and not used[id] then
			local chain, cursor, guard = {}, id, 0
			while cursor and set[cursor] and not used[cursor] and guard < 40 do
				guard = guard + 1
				used[cursor] = true
				chain[#chain + 1] = cursor
				cursor = tonumber(qget(cursor, "nextQuestInChain"))
			end
			chains[#chains + 1] = chain
		end
	end
	for _, id in ipairs(list) do if not used[id] then chains[#chains + 1] = { id } end end -- loops
	local function minLevel(c)
		local m = 999
		for _, id in ipairs(c) do local l = questLevel(id); if l > 0 and l < m then m = l end end
		return m
	end
	table.sort(chains, function(a, b)
		local la, lb = minLevel(a), minLevel(b)
		if la ~= lb then return la < lb end
		return a[1] < b[1]
	end)
	return chains
end
api.chainsOf = chainsOf -- (tests)
local classChains
local function classRows()
	if not questieReady() then return { { nil, "Needs Questie." } } end
	local bit = _G.bit and _G.bit.band
	local me = classBit()
	local list = api.questieScan and api.questieScan("class", function(id, get)
		local classes = tonumber(get("Quest", id, "requiredClasses"))
		if not (classes and classes > 0 and me and bit) or bit(classes, 2 ^ (me - 1)) == 0 then return false end
		return not api.questieForPlayerQuest or api.questieForPlayerQuest(id)
	end, function() classChains = nil; refreshPage() end)
	if not list then return { { nil, "Reading Questie's quests ..." } } end
	classChains = classChains or chainsOf(list)
	local rows = {}
	local showDone = db.chainsShowDone == true
	for _, c in ipairs(classChains) do
		local first = c[1]
		addChain(rows, "class:" .. first, questName(c[#c]) .. (#c > 1 and (" (%d steps)"):format(#c) or ""), c, showDone)
	end
	if #rows == 0 then rows[1] = { nil, "Every class quest is done." } end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Profession quests
---------------------------------------------------------------------------------------------------------------------
local function skillRanks()
	local out = {}
	local names = api.guideProfessions or {}
	local function add(name, rank)
		if type(name) ~= "string" or isSecret(name) then return end
		for id, n in pairs(names) do if n:lower() == name:lower() then out[id] = tonumber(rank) or 0 end end
	end
	if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
		local ok, n = pcall(GetNumSkillLines)
		for i = 1, ok and tonumber(n) or 0 do
			local okI, name, header, _, rank = pcall(GetSkillLineInfo, i)
			if okI and not header then add(name, rank) end
		end
	end
	return out
end
local profList
local function profRows()
	if not questieReady() then return { { nil, "Needs Questie." } } end
	local list = api.questieScan and api.questieScan("profession", function(id, get)
		local skill = get("Quest", id, "requiredSkill")
		if not (type(skill) == "table" and tonumber(skill[1])) then return false end
		return not api.questieForPlayerQuest or api.questieForPlayerQuest(id)
	end, function() profList = nil; refreshPage() end)
	if not list then return { { nil, "Reading Questie's quests ..." } } end
	if not profList then
		profList = {}
		for _, id in ipairs(list) do
			local skill = qget(id, "requiredSkill")
			local sid, value = tonumber(skill[1]), tonumber(skill[2]) or 0
			profList[sid] = profList[sid] or {}
			table.insert(profList[sid], { id = id, value = value })
		end
		for _, l in pairs(profList) do table.sort(l, function(a, b) if a.value ~= b.value then return a.value < b.value end return a.id < b.id end) end
	end
	local ranks = skillRanks()
	local names = api.guideProfessions or {}
	local ids = {}
	for sid in pairs(profList) do if names[sid] and (ranks[sid] or db.profShowAll) then ids[#ids + 1] = sid end end
	table.sort(ids, function(a, b) return names[a] < names[b] end)
	local rows = {}
	local showDone = db.chainsShowDone == true
	for _, sid in ipairs(ids) do
		local rank = ranks[sid]
		local key = "prof:" .. sid
		local closed = folded(key)
		local open = 0
		for _, q in ipairs(profList[sid]) do if not done(q.id) then open = open + 1 end end
		rows[#rows + 1] = { nil, names[sid], (rank and ("your rank %d  "):format(rank) or "not learned  ") .. open .. " open",
			nil, header = true, fold = closed, onClick = function() toggleFold(key) end, clickHint = "Click: open or close" }
		if not closed then
			for _, q in ipairs(profList[sid]) do
				if showDone or not done(q.id) then
					local r = stepRow(q.id, ("needs %d"):format(q.value))
					if rank and rank < q.value and not done(q.id) then r[4] = GREY end
					rows[#rows + 1] = r
				end
			end
		end
	end
	if #rows == 0 then rows[1] = { nil, "No profession quests for the professions you know." } end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Exploration
---------------------------------------------------------------------------------------------------------------------
local exploreIndex -- [zone name lower] = achievement ID
local function try(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end
local function buildExploreIndex()
	if exploreIndex then return exploreIndex end
	exploreIndex = {}
	local ok, cats = try(GetCategoryList)
	if not ok or type(cats) ~= "table" then return exploreIndex end
	for _, cid in ipairs(cats) do
		local okN, count = try(GetCategoryNumAchievements, cid, true)
		for i = 1, okN and tonumber(count) or 0 do
			local okI, id, name = try(GetAchievementInfo, cid, i)
			if okI and id and type(name) == "string" and not isSecret(name) then
				local zone = name:match("^Explore (.+)$")
				if zone then exploreIndex[zone:lower()] = id end
			end
		end
	end
	return exploreIndex
end
local function playerMap()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if type(map) ~= "number" or isSecret(map) then return nil end
	-- the zone, not a city or cave inside it
	local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	local guard = 0
	while info and info.mapType and Enum and Enum.UIMapType and info.mapType > Enum.UIMapType.Zone and info.parentMapID
		and info.parentMapID > 0 and guard < 5 do
		guard = guard + 1
		map = info.parentMapID
		info = C_Map.GetMapInfo(map)
	end
	return map, info and info.name
end
-- this zone's areas: done, total, { { name, done, criteriaID } }, achievement ID
function api.zoneExploration()
	local map, zone = playerMap()
	if not map then return nil end
	local ach = zone and buildExploreIndex()[zone:lower()]
	local list, d, t = {}, 0, 0
	if ach then
		local okK, n = try(GetAchievementNumCriteria, ach)
		for k = 1, okK and tonumber(n) or 0 do
			local okR, cname, _, cdone, _, _, _, _, _, _, cid = try(GetAchievementCriteriaInfo, ach, k)
			if okR and type(cname) == "string" and not isSecret(cname) then
				t = t + 1
				if cdone then d = d + 1 end
				list[#list + 1] = { cname, cdone and true or false, cid }
			end
		end
	end
	if t == 0 then return nil end
	return d, t, list, ach, map, zone
end
-- the areas of this zone not found yet: the zone's "Explore" achievement
local function unexploredNames()
	local d, t, list, _, map, zone = api.zoneExploration()
	local names, seen = {}, {}
	for _, a in ipairs(list or {}) do
		if not a[2] and not seen[a[1]] then seen[a[1]] = true; names[#names + 1] = a[1] end
	end
	return names, d, t, zone
end
api.unexploredNames = unexploredNames -- for tests

-- the tag after your zone's name on its header; hover it: the areas still to find (user)
local tag, hover
local placeHover -- below
local function hideTag()
	if tag then tag:Hide() end
	if hover then hover:Hide() end
end
local function showTip(self)
	local ok, names, d, t, zone = pcall(unexploredNames)
	if not ok then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(tostring(zone or "This zone"), 1, 0.82, 0)
	if d and t then GameTooltip:AddLine(("%d of %d areas explored"):format(d, t), 0.85, 0.85, 0.85) end
	if #names > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Not found yet:", 1, 1, 1)
		for _, n in ipairs(names) do GameTooltip:AddLine("- " .. n, 0.8, 0.8, 0.8) end
	elseif d and t and d < t then
		GameTooltip:AddLine("Walk around: the names show once the game lists them.", 0.6, 0.6, 0.6, true)
	else
		GameTooltip:AddLine("Every area found.", 0.2, 1, 0.2)
	end
	GameTooltip:Show()
end
api.exploredTipForTests = showTip
-- placed by screen position, never anchored to the tag: the tracker can be protected in combat (our own tracker with
-- the guide's buttons), and a frame anchored into it would be too; in combat it stays where it is
function placeHover()
	if not (hover and tag) or (InCombatLockdown and InCombatLockdown()) then return end
	local l, t, r, b = tag:GetLeft(), tag:GetTop(), tag:GetRight(), tag:GetBottom()
	if not (l and t and r and b) or not tag:IsVisible() then hover:Hide() return end
	local parent = tag:GetParent()
	local k = (tag:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	hover:SetFrameStrata(parent and parent.GetFrameStrata and parent:GetFrameStrata() or "MEDIUM")
	hover:SetFrameLevel((parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 10)
	hover:ClearAllPoints()
	hover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * k - 2, t * k + 2)
	hover:SetSize((r - l) * k + 4, (t - b) * k + 4)
	hover:Show()
end
local function refreshTag()
	if not (db and db.zoneExplored ~= false) then hideTag() return end
	local ok, d, t, _, _, _, zone = pcall(api.zoneExploration)
	local label = ok and d and zone and api.zoneLabelFor and api.zoneLabelFor(zone)
	if not label then
		local realName = GetRealZoneText and GetRealZoneText()
		label = ok and d and api.zoneLabelFor and type(realName) == "string" and api.zoneLabelFor(realName) or nil
	end
	if not label then hideTag() return end
	if not tag then
		tag = UIParent:CreateFontString(nil, "OVERLAY")
		tag:SetShadowOffset(1, -1)
		tag:SetShadowColor(0, 0, 0, 1)
	end
	local file, size, flags = label:GetFont()
	if file then tag:SetFont(file, math.max((size or 12) - 1, 8), flags) end
	tag:SetParent(label:GetParent())
	tag:SetDrawLayer("OVERLAY", 7)
	tag:SetText(("|cffaaaaaaExplored %d/%d|r"):format(d, t))
	tag:ClearAllPoints()
	tag:SetPoint("BOTTOMLEFT", label, "BOTTOMLEFT", (label:GetStringWidth() or 0) + 8, 0)
	tag:Show()
	-- a small frame of our own over the tag for the tooltip (on UIParent: nothing is added to Blizzard's frames)
	if not hover then
		hover = CreateFrame("Frame", nil, UIParent)
		hover:EnableMouse(true)
		hover:SetScript("OnEnter", showTip)
		hover:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
		-- follows the tag while the list scrolls or moves
		local acc = 0
		hover:SetScript("OnUpdate", function(_, elapsed)
			acc = acc + (elapsed or 0)
			if acc < 0.2 then return end
			acc = 0
			placeHover()
		end)
	end
	placeHover()
end
api.refreshExploredTag = refreshTag

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "CRITERIA_UPDATE", "ACHIEVEMENT_EARNED", "QUEST_TURNED_IN" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function(_, event)
		if event == "QUEST_TURNED_IN" then classChains = nil end
		C_Timer.After(0.5, function() pcall(refreshTag) end)
	end)
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(3, function() pcall(refreshTag) end) end
end

---------------------------------------------------------------------------------------------------------------------
-- Settings: Guides
---------------------------------------------------------------------------------------------------------------------
api.pageDeclarers = api.pageDeclarers or {}
api.pageDeclarers[#api.pageDeclarers + 1] = function(k)
	refreshPage = function() if k.refresh then pcall(k.refresh) end end
	local rowList = api.guideRowList
	if not rowList then return end
	k.page("attunements", "quests", "Attunements")
	k.pageByKey.attunements.cardTitle = "Raid attunement chains"
	k.custom("Attunements molten core onyxia blackwing lair naxxramas", rowList(attunementRows, nil, 60), true)

	k.page("classquests", "quests", "Class quests")
	k.pageByKey.classquests.cardTitle = "Quests for your class"
	k.note("Every quest only your class can do, in chains, lowest level first. Click a chain to open or close it. Needs Questie.")
	k.check("Show finished chains", function() return db.chainsShowDone == true end,
		function(v) db.chainsShowDone = v and true or false; refreshPage() end)
	k.custom("Class quests chains", rowList(classRows, nil, 200), true)

	k.page("profquests", "quests", "Profession quests")
	k.pageByKey.profquests.cardTitle = "Quests that need a profession rank"
	k.note("Grey: your rank is too low for it yet. Needs Questie.")
	k.check("Also professions you have not learned", function() return db.profShowAll == true end,
		function(v) db.profShowAll = v and true or false; refreshPage() end)
	k.custom("Profession quests blacksmithing tailoring alchemy engineering cooking fishing first aid", rowList(profRows, nil, 200), true)

end
