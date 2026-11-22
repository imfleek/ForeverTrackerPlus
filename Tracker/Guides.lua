-- 3.1 Guides (Settings > Guides). The ideas come from Questline (its Legacy Challenges tab, library books and
-- sleeping bag guide); the code and the data are our own: everything is read live from the game and from Questie.
--   legacy   WoW Forever's Legacy Challenges: every achievement with the legacy flag (0x8000000 in
--            GetAchievementInfo's flags), by category, with its criteria done/total; the tooltip lists the open ones.
--            db.legacyShowDone shows finished ones too.
--            3.1.2 db.legacyOnlyMine: only the ones this character can do. A challenge is left out when one of its open
--            steps cannot be done here (the game's criteria "eligible" is false, or a quest step is for another race
--            or class in Questie), or when it needs a profession this character has not learned (the profession is
--            named in the challenge, or a step is a skill level of it); db.legacyWithProfs keeps that second kind.
--   books    (Questie) the library book quests (api.questieGuideData finds them: a quest that starts at a librarian
--            and at the book itself). Done, in your bags, or open; click for a waypoint to the book.
--            3.1.2: a "?" for a book Questie hides (not in the game) or has no place for; db.booksShowDone (on) keeps
--            the books already turned in.
--   bedroll  (Questie) the Cozy Sleeping Bag chain: its first quest is found by name (or by its known IDs), the rest
--            by Questie's prerequisite links. Done, in the log, or open; click for a waypoint to the next step's giver.
--            3.1.2: the last quest (or every step) done: only "You have completed this questchain.", Questie or not.
-- Every achievement call is in pcall; a page whose data is not there says so.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local LEGACY_FLAG = 0x8000000
local BEDROLL_START = "... and that note you found"
-- the chain in Questie's Forever data: "... and that note you found" (79007 Horde, 79008 Alliance), Stepping Stones,
-- Scramble, Wet Job, Eagle's Fist, This Must Be The Place (79976, the last)
local BEDROLL_FIRST = { 79007, 79008 }
local BEDROLL_LAST = 79976
local BEDROLL_NOTE = "From level 14. Do the steps in order; click a step for a waypoint to its giver. Needs Questie."
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_OPEN = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_LOG = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_BAG = "Interface\\Icons\\INV_Misc_Bag_08"
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local GOLD = { 1, 0.82, 0.25 }
local GREEN = { 0.45, 0.9, 0.45 }
local GREY = { 0.6, 0.6, 0.6 }
local ORANGE = { 1, 0.6, 0.25 }
local RED = { 1, 0.42, 0.32 }

local function try(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end
local function questDone(id)
	return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
end
local function questInLog(id)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
	return index ~= nil and index > 0
end
local function waypoint(map, x, y, label)
	if not (map and x and y and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(map) and UiMapPoint) then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r no map spot for " .. (label or "this"))
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
	DEFAULT_CHAT_FRAME:AddMessage(("|cff33ff99ForeverTrackerPlus|r waypoint: %s (%.1f, %.1f)"):format(label or "", x * 100, y * 100))
end

---------------------------------------------------------------------------------------------------------------------
-- A clickable list in the settings window's look. rows() -> { { icon, text, right, color, onClick, tip = {lines},
-- header = bool, note = bool } }; a tip line is a string (white) or { text, r, g, b }; a note row is grey and wraps
---------------------------------------------------------------------------------------------------------------------
local function rowList(rows, emptyText, maxRows)
	return function(holder, kit)
		local C = kit.C
		local list = {}
		local function line(i)
			if list[i] then return list[i] end
			local r = CreateFrame("Button", nil, holder)
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.text = kit.text(r, "GameFontHighlight", 1.08, C.value)
			r.text:SetJustifyH("LEFT")
			r.text:SetWordWrap(false)
			r.right = kit.text(r, "GameFontHighlight", 1.0, C.label)
			r.right:SetJustifyH("RIGHT")
			r.right:SetWordWrap(false)
			local hl = r:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 0.9, 0.6, 0.06)
			r:SetScript("OnClick", function(self) if self.data and self.data.onClick then pcall(self.data.onClick) end end)
			r:SetScript("OnEnter", function(self)
				local d = self.data
				if not (d and (d.tip or d.onClick)) then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(d.text or "", 1, 0.82, 0)
				for _, t in ipairs(d.tip or {}) do
					if type(t) == "table" then GameTooltip:AddLine(t[1], t[2], t[3], t[4], true)
					else GameTooltip:AddLine(t, 1, 1, 1, true) end
				end
				if d.onClick then GameTooltip:AddLine("Click: waypoint", 0.6, 0.85, 1) end
				GameTooltip:Show()
			end)
			r:SetScript("OnLeave", function() GameTooltip:Hide() end)
			list[i] = r
			return r
		end
		local w = {}
		function w.draw(width)
			local k = kit.ts()
			local data = rows() or {}
			if #data == 0 then data = { { nil, emptyText or "Nothing here." } } end
			local made = #list
			for i = 1, math.min(#data, maxRows or 120) do line(i) end
			if #list > made then kit.refreshFonts() end
			local rowH = math.floor(22 * k + 0.5)
			local is = math.floor(16 * k + 0.5)
			local y = 0
			for i, r in ipairs(list) do
				local d = i <= (maxRows or 120) and data[i] or nil
				r.data = d
				r:SetShown(d ~= nil)
				if d then
					if d.header and i > 1 then y = y + math.floor(6 * k) end
					r:ClearAllPoints()
					r:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r:SetSize(width, rowH)
					r.icon:SetShown(d[1] ~= nil)
					r.icon:SetTexture(d[1])
					r.icon:SetSize(is, is)
					r.icon:ClearAllPoints()
					r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
					r.text:ClearAllPoints()
					local h = rowH
					if d.note then
						-- a paragraph: wraps over the whole width, the row as tall as its text
						r.text:SetWordWrap(true)
						r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -3)
						r.text:SetWidth(math.max(width - 6, 40))
					else
						r.text:SetWordWrap(false)
						r.text:SetPoint("LEFT", r, "LEFT", d[1] and (is + 8) or 2, 0)
						r.text:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
					end
					r.text:SetText(d[2] or "")
					local c = d.header and GOLD or d[4] or d.note and C.label or C.value
					r.text:SetTextColor(c[1], c[2], c[3])
					if d.note then
						h = math.max(rowH, math.ceil(tonumber(r.text:GetStringHeight()) or 0) + 8)
						r:SetSize(width, h)
					end
					r.right:ClearAllPoints()
					r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
					r.right:SetWidth(math.floor(width * 0.4))
					r.right:SetText(d[3] or "")
					r:EnableMouse(d.onClick ~= nil or d.tip ~= nil)
					y = y + h
				end
			end
			return math.max(y, 1)
		end
		w.refresh = function() end
		return w
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Legacy Challenges
---------------------------------------------------------------------------------------------------------------------
local legacyCache, legacyAt = nil, -100
local function isLegacy(flags) return type(flags) == "number" and math.floor(flags / LEGACY_FLAG) % 2 == 1 end

-- professions: skill line ID -> English name (also what a challenge's text is searched for)
local PROFESSIONS = { [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
	[182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning", [197] = "Tailoring",
	[185] = "Cooking", [356] = "Fishing", [129] = "First Aid", [755] = "Jewelcrafting", [773] = "Inscription" }
-- criteria types whose asset is a skill line: reach a skill level, learn a skill line, learn its spells, learn a rank
local SKILL_CRITERIA = { [7] = true, [40] = true, [75] = true, [112] = true }
local QUEST_CRITERIA = 27
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
-- the professions this character has learned: { [skill line ID] = true, [lower-case name] = true }
local function knownSkills()
	local out = {}
	local function add(name, id, rank)
		if isSecret(name) or (rank ~= nil and (tonumber(rank) or 0) <= 0) then return end
		if type(name) == "string" and name ~= "" then out[name:lower()] = true end
		if tonumber(id) then out[tonumber(id)] = true end
	end
	local si = C_SkillInfo
	if si and type(si.GetSkillLineInfoByID) == "function" then
		for id in pairs(PROFESSIONS) do
			local ok, info = pcall(si.GetSkillLineInfoByID, id)
			if ok and type(info) == "table" then add(info.name, info.skillID or id, info.rank) end
		end
	end
	if si and type(si.GetNumSkillLines) == "function" and type(si.GetSkillLineInfo) == "function" then
		local ok, n = pcall(si.GetNumSkillLines)
		for i = 1, ok and tonumber(n) or 0 do
			local okI, info = pcall(si.GetSkillLineInfo, i)
			if okI and type(info) == "table" and not info.isHeader then add(info.name, info.skillID, info.rank) end
		end
	elseif type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
		local ok, n = pcall(GetNumSkillLines)
		for i = 1, ok and tonumber(n) or 0 do
			local okI, name, header, _, rank = pcall(GetSkillLineInfo, i)
			if okI and not header then add(name, nil, rank) end
		end
	end
	return out
end
api.guideKnownSkills = knownSkills -- (tests)
local function hasProfession(known, id) return known[id] or known[PROFESSIONS[id]:lower()] or false end
-- the professions a text names, as skill line IDs into set
local function professionsIn(text, set)
	if type(text) ~= "string" or text == "" or isSecret(text) then return end
	local lower = " " .. text:lower():gsub("[^%a ]", " ") .. " "
	for id, name in pairs(PROFESSIONS) do
		if lower:find(" " .. name:lower() .. " ", 1, true) then set[id] = true end
	end
end

local function legacyData()
	if legacyCache and GetTime() - legacyAt < 10 then return legacyCache end
	local out = { categories = {}, done = 0, total = 0 }
	local ok, cats = try(GetCategoryList)
	if not ok or type(cats) ~= "table" then legacyCache, legacyAt = out, GetTime() return out end
	local known = knownSkills()
	local questieOn = api.questieOn and api.questieOn() and api.questieForPlayer
	for _, cid in ipairs(cats) do
		local okN, count = try(GetCategoryNumAchievements, cid, true)
		local cat
		for i = 1, okN and tonumber(count) or 0 do
			local okI, id, name, _, done, _, _, _, desc, flags = try(GetAchievementInfo, cid, i)
			if okI and id and isLegacy(flags) then
				if not cat then
					local okC, title = try(GetCategoryInfo, cid)
					cat = { name = okC and type(title) == "string" and title or "Legacy", list = {} }
					out.categories[#out.categories + 1] = cat
				end
				local a = { id = id, name = name, done = done and true or false, desc = desc, have = 0, need = 0, open = {},
					category = cat.name, needs = {}, blocked = {} }
				local profs = {}
				professionsIn(name, profs)
				professionsIn(desc, profs)
				local okK, n = try(GetAchievementNumCriteria, id)
				for k = 1, okK and tonumber(n) or 0 do
					local okR, cname, ctype, cdone, _, _, _, _, asset, _, _, eligible = try(GetAchievementCriteriaInfo, id, k)
					if okR then
						a.need = a.need + 1
						if cdone then a.have = a.have + 1
						else
							if type(cname) == "string" and cname ~= "" then a.open[#a.open + 1] = cname end
							professionsIn(cname, profs)
							if SKILL_CRITERIA[ctype] and PROFESSIONS[asset] then profs[asset] = true end
							if eligible == false then
								a.blocked[#a.blocked + 1] = "The game says this character cannot do: " .. tostring(cname or "a step")
							elseif ctype == QUEST_CRITERIA and tonumber(asset) and questieOn and not api.questieForPlayer(asset) then
								a.blocked[#a.blocked + 1] = "A quest for another race or class: " .. tostring(cname or asset)
							end
						end
					end
				end
				for pid in pairs(profs) do
					if not hasProfession(known, pid) then a.needs[#a.needs + 1] = PROFESSIONS[pid] end
				end
				table.sort(a.needs)
				cat.list[#cat.list + 1] = a
				out.total = out.total + 1
				if a.done then out.done = out.done + 1 end
			end
		end
	end
	legacyCache, legacyAt = out, GetTime()
	return out
end
local function legacyRows()
	local data = legacyData()
	local rows = {}
	local showDone = db and db.legacyShowDone == true
	local onlyMine = db and db.legacyOnlyMine == true
	local withProfs = db and db.legacyWithProfs == true
	local function canDo(a)
		if a.done or not onlyMine then return true end
		if #a.blocked > 0 then return false end
		return #a.needs == 0 or withProfs
	end
	for _, cat in ipairs(data.categories) do
		local list = {}
		for _, a in ipairs(cat.list) do if canDo(a) then list[#list + 1] = a end end
		local open = 0
		for _, a in ipairs(list) do if not a.done then open = open + 1 end end
		if #list > 0 and (showDone or open > 0) then
			rows[#rows + 1] = { nil, cat.name, ("%d of %d done"):format(#list - open, #list), header = true,
				tip = { ("%d Legacy Challenges in this category: %d done, %d still open."):format(#list, #list - open, open) } }
			for _, a in ipairs(list) do
				if showDone or not a.done then
					local tip = {}
					if a.desc and a.desc ~= "" then tip[1] = a.desc end
					if a.done then
						tip[#tip + 1] = { "Done.", GREEN[1], GREEN[2], GREEN[3] }
					elseif a.need > 0 then
						tip[#tip + 1] = { ("%d of %d steps done."):format(a.have, a.need), GOLD[1], GOLD[2], GOLD[3] }
					end
					if not a.done then
						if #a.needs > 0 then
							tip[#tip + 1] = { "Needs a profession you have not learned: " .. table.concat(a.needs, ", "),
								ORANGE[1], ORANGE[2], ORANGE[3] }
						end
						for _, why in ipairs(a.blocked) do tip[#tip + 1] = { why, RED[1], RED[2], RED[3] } end
					end
					if #a.open > 0 then
						tip[#tip + 1] = " "
						tip[#tip + 1] = "Still to do:"
						for i = 1, math.min(#a.open, 15) do tip[#tip + 1] = "  " .. a.open[i] end
						if #a.open > 15 then tip[#tip + 1] = ("  and %d more"):format(#a.open - 15) end
					end
					local icon = a.done and ICON_DONE or (#a.blocked > 0 and ICON_NO) or ICON_OPEN
					local color = a.done and GREEN or (#a.blocked > 0 or #a.needs > 0) and GREY or nil
					rows[#rows + 1] = { icon, a.name,
						a.need > 0 and ("%d / %d"):format(a.have, a.need) or (a.done and "done" or ""),
						color, tip = tip }
				end
			end
		end
	end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Library books and the sleeping bag chain (Questie)
---------------------------------------------------------------------------------------------------------------------
local function itemCount(id)
	if not id then return 0 end
	local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id))
	return tonumber(n) or 0
end
local refreshPage = function() end
local function onGuideReady() refreshPage() end
local function guideData() return api.questieGuideData and api.questieGuideData({ BEDROLL_START }, onGuideReady) end

local function bookRows()
	if not (api.questieOn and api.questieOn()) then return { { nil, "Needs Questie." } } end
	local data = guideData()
	if not data then return { { nil, "Reading Questie's quests ..." } } end
	local rows, done, total = {}, 0, 0
	local showDone = not (db and db.booksShowDone == false)
	for _, b in ipairs(data.books) do
		local isDone = questDone(b.quest)
		total = total + 1
		if isDone then done = done + 1 end
		local map, x, y, zone = api.questieSpot("Object", b.object)
		local inBag = not isDone and itemCount(b.item) > 0
		local hidden = not isDone and api.questieHidden and api.questieHidden(b.quest)
		local unknown = not isDone and not inBag and (hidden or not map)
		local librarian = b.librarian or (api.questieLibrarian and api.questieLibrarian(b.quest))
		local tip = {}
		if isDone then
			tip[#tip + 1] = { "Turned in. This book is in the library.", GREEN[1], GREEN[2], GREEN[3] }
		elseif inBag then
			tip[#tip + 1] = { "In your bags: take it to " .. (librarian or "the librarian") .. ".", GOLD[1], GOLD[2], GOLD[3] }
		elseif hidden then
			tip[#tip + 1] = { "Status unknown: Questie marks this book's quest as not in the game.", ORANGE[1], ORANGE[2], ORANGE[3] }
			tip[#tip + 1] = "It may have been taken out, or it may not be in the game yet. You may not be able to get it."
		elseif not map then
			tip[#tip + 1] = { "Status unknown: Questie does not know where this book is.", ORANGE[1], ORANGE[2], ORANGE[3] }
			tip[#tip + 1] = "It may not be in the game, or it may drop or show up somewhere Questie does not list."
		else
			tip[#tip + 1] = ("Lies in %s (%.1f, %.1f)."):format(zone or "?", (x or 0) * 100, (y or 0) * 100)
			tip[#tip + 1] = "Pick it up, then take it to " .. (librarian or "the librarian") .. "."
		end
		if showDone or not isDone then
			rows[#rows + 1] = { isDone and ICON_DONE or inBag and ICON_BAG or unknown and ICON_UNKNOWN or ICON_OPEN, b.name,
				isDone and "turned in" or inBag and "in your bags" or unknown and "status unknown" or (zone or ""),
				isDone and GREEN or unknown and GREY or nil,
				onClick = not isDone and not hidden and map and function() waypoint(map, x, y, b.name) end or nil,
				tip = tip }
		end
	end
	if total == 0 then return { { nil, "Questie lists no library books for this character." } } end
	if #rows == 0 then rows[1] = { ICON_DONE, "Every book is turned in.", nil, GREEN } end
	table.insert(rows, 1, { nil, "Library books", ("%d of %d turned in"):format(done, total), header = true })
	return rows
end

local function giverSpot(quest)
	local by = api.questieGet("Quest", quest, "startedBy")
	local npc = type(by) == "table" and type(by[1]) == "table" and by[1][1]
	if npc then
		local map, x, y, zone = api.questieSpot("Npc", npc)
		local name = api.questieGet("Npc", npc, "name")
		return map, x, y, zone, type(name) == "string" and name or nil
	end
	local object = type(by) == "table" and type(by[2]) == "table" and by[2][1]
	if object then
		local map, x, y, zone = api.questieSpot("Object", object)
		return map, x, y, zone, api.questieObjectName(object)
	end
end
local function bedrollChain()
	local data = guideData()
	if not data then return nil end
	local starts, have = {}, {}
	for _, q in ipairs(data.named[BEDROLL_START] or {}) do starts[#starts + 1] = q; have[q] = true end
	for _, q in ipairs(BEDROLL_FIRST) do if not have[q] then starts[#starts + 1] = q end end
	local first
	for _, q in ipairs(starts) do if questDone(q) then first = q break end end
	if not first then
		for _, q in ipairs(starts) do
			if api.questieGet("Quest", q, "name") ~= nil and api.questieForPlayer(q) then first = q break end
		end
	end
	if not first then return {} end
	local chain, seen, frontier = {}, { [first] = true }, { first }
	chain[1] = first
	for _ = 1, 8 do
		local nextFrontier = {}
		for _, q in ipairs(frontier) do
			local after = api.questieNextQuests(q)
			if after == nil then return nil end
			for _, n in ipairs(after) do
				if not seen[n] then seen[n] = true; chain[#chain + 1] = n; nextFrontier[#nextFrontier + 1] = n end
			end
		end
		if #nextFrontier == 0 then break end
		frontier = nextFrontier
	end
	return chain
end
local function bedrollDoneRows()
	return { { ICON_DONE, "You have completed this questchain.", nil, GREEN,
		tip = { { "Every step of the Cozy Sleeping Bag chain is done.", GREEN[1], GREEN[2], GREEN[3] } } } }
end
local function bedrollRows()
	if questDone(BEDROLL_LAST) then return bedrollDoneRows() end
	local note = { nil, BEDROLL_NOTE, note = true }
	if not (api.questieOn and api.questieOn()) then return { note, { nil, "Needs Questie." } } end
	local chain = bedrollChain()
	if not chain then return { note, { nil, "Reading Questie's quests ..." } } end
	if #chain == 0 then return { note, { nil, "Questie does not list this chain for this character." } } end
	local allDone = true
	for _, q in ipairs(chain) do if not questDone(q) then allDone = false break end end
	if allDone then return bedrollDoneRows() end
	local rows, done = { note }, 0
	local nextShown = false
	for _, q in ipairs(chain) do
		local isDone, inLog = questDone(q), questInLog(q)
		if isDone then done = done + 1 end
		local name = api.questieGet("Quest", q, "name")
		name = type(name) == "string" and name or ("Quest " .. q)
		local map, x, y, zone, giver = giverSpot(q)
		local right = isDone and "done" or inLog and "in your log" or (zone or "")
		local tip = giver and { "Starts at: " .. giver .. (zone and (", " .. zone) or "") } or nil
		local isNext = not isDone and not inLog and not nextShown
		if isNext then nextShown = true; right = "next: " .. right end
		rows[#rows + 1] = { isDone and ICON_DONE or inLog and ICON_LOG or ICON_OPEN, name, right, isDone and GREEN or nil,
			onClick = not isDone and map and function() waypoint(map, x, y, giver or name) end or nil, tip = tip }
	end
	table.insert(rows, 2, { nil, "Cozy Sleeping Bag", ("%d of %d done"):format(done, #chain), header = true })
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Settings > Guides (declared by Config.lua: api.declareGuidePages(kit))
---------------------------------------------------------------------------------------------------------------------
api.guideLegacyRows, api.guideBookRows, api.guideBedrollRows = legacyRows, bookRows, bedrollRows -- (tests)
function api.declareGuidePages(k)
	refreshPage = function() if k.refresh then pcall(k.refresh) end end
	k.page("legacy", "quests", "Legacy Challenges")
	k.pageByKey.legacy.cardTitle = "WoW Forever's Legacy Challenges"
	k.check("Show finished challenges", function() return db.legacyShowDone == true end,
		function(v) db.legacyShowDone = v and true or false; legacyAt = -100; refreshPage() end)
	k.help("hover a challenge to see what is still to do")
	k.check("Only challenges this character can do", function() return db.legacyOnlyMine == true end,
		function(v) db.legacyOnlyMine = v and true or false; refreshPage() end)
	k.help("hides challenges for another race, class or faction, and ones that need a profession you have not learned")
	k.check("Include professions you have not learned", function() return db.legacyWithProfs == true end,
		function(v) db.legacyWithProfs = v and true or false; refreshPage() end,
		function() return db.legacyOnlyMine == true end, 24)
	k.help("keeps challenges that need a profession this character could still learn")
	k.custom("Legacy challenges dungeon explorer achievements", rowList(legacyRows,
		"No Legacy Challenges found (or all are done).", 160), true)

	k.page("books", "quests", "Library books")
	k.pageByKey.books.cardTitle = "Books for the library"
	k.note("Find each book and take it to the librarian. Click a book for a waypoint; hover it for more. A ? means its status is unknown. Needs Questie.")
	k.check("Show collected books", function() return db.booksShowDone ~= false end,
		function(v) db.booksShowDone = v and true or false; refreshPage() end)
	k.help("books you have already turned in")
	k.custom("Library books friend of the library", rowList(bookRows, nil, 60), true)

	k.page("bedroll", "quests", "Sleeping bag")
	k.pageByKey.bedroll.cardTitle = "The Cozy Sleeping Bag quest chain"
	k.custom("Cozy sleeping bag bedroll chain", rowList(bedrollRows, nil, 20), true)
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local f = CreateFrame("Frame")
	pcall(f.RegisterEvent, f, "ACHIEVEMENT_EARNED")
	pcall(f.RegisterEvent, f, "CRITERIA_UPDATE")
	pcall(f.RegisterEvent, f, "SKILL_LINES_CHANGED")
	f:SetScript("OnEvent", function() legacyAt = -100 end)
end
