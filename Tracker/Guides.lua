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
--   secrets  3.1.2 hidden toys, quests and mysteries (SECRETS below), with a found counter.
-- Every achievement call is in pcall; a page whose data is not there says so.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db
local refreshPage = function() end -- lays the open page out again (api.declareGuidePages sets it)

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
	-- 3.1.2 (an idea from SecretChecklist): TomTom's arrow too, when TomTom is loaded
	local tt = rawget(_G, "TomTom")
	if type(tt) == "table" and type(tt.AddWaypoint) == "function" then
		pcall(tt.AddWaypoint, tt, map, x, y, { title = label, from = "ForeverTrackerPlus" })
	end
	DEFAULT_CHAT_FRAME:AddMessage(("|cff33ff99ForeverTrackerPlus|r waypoint: %s (%.1f, %.1f)"):format(label or "", x * 100, y * 100))
end

---------------------------------------------------------------------------------------------------------------------
-- A clickable list in the settings window's look. rows() -> { { icon, text, right, color, onClick, tip = {lines},
-- header = bool, note = bool, fold = bool (folded), clickHint } }; a tip line is a string (white) or { text, r, g, b };
-- a note row is grey and wraps
---------------------------------------------------------------------------------------------------------------------
local function rowList(rows, emptyText, maxRows)
	return function(holder, kit)
		local C = kit.C
		local list, arrows = {}, {}
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
				if d.onClick then GameTooltip:AddLine(d.clickHint or "Click: waypoint", 0.6, 0.85, 1) end
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
					-- 3.1.2 a row that folds (fold = true): an arrow in the icon's place, pointing down while open
					if d.fold ~= nil and not arrows[r] and kit.arrow then arrows[r] = kit.arrow(r, false, 12) end
					local arrow = arrows[r]
					if arrow then
						arrow:SetShown(d.fold ~= nil)
						if d.fold ~= nil then
							arrow:ClearAllPoints()
							arrow:SetPoint("CENTER", r, "LEFT", 2 + is / 2, 0)
							if arrow.SetRotation then pcall(arrow.SetRotation, arrow, d.fold and 0 or -math.pi / 2) end
						end
					end
					r.text:ClearAllPoints()
					local h = rowH
					if d.note then
						-- a paragraph: wraps over the whole width, the row as tall as its text
						r.text:SetWordWrap(true)
						r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -3)
						r.text:SetWidth(math.max(width - 6, 40))
					else
						r.text:SetWordWrap(false)
						r.text:SetPoint("LEFT", r, "LEFT", (d[1] or d.fold ~= nil) and (is + 8) or 2, 0)
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

-- 3.1.2 PvP: the PvP category is shown as "PVP Ranking", and a challenge for a PvP rank gets that rank's title for
-- this character's faction. The rank is a number in its name or text ("Rank 6"), or a title of either faction in it.
local PVP_TITLES = {
	Alliance = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major", "Knight", "Knight-Lieutenant",
		"Knight-Captain", "Knight-Champion", "Lieutenant Commander", "Commander", "Marshal", "Field Marshal", "Grand Marshal" },
	Horde = { "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant", "Stone Guard", "Blood Guard", "Legionnaire",
		"Centurion", "Champion", "Lieutenant General", "General", "Warlord", "High Warlord" },
}
local function isPvpCategory(name)
	if type(name) ~= "string" or isSecret(name) then return false end
	local l = name:lower()
	return l:find("pvp", 1, true) or l:find("player vs", 1, true) or l:find("honor", 1, true) or l:find("rank", 1, true) or false
end
-- the rank (1-14) a text names
local function pvpRank(text)
	if type(text) ~= "string" or isSecret(text) then return nil end
	local n = tonumber(text:match("[Rr]ank%s*(%d+)") or text:match("^%s*(%d+)%s*$") or text:match("[Rr](%d+)%f[%D]"))
	if n and n >= 1 and n <= 14 then return n end
	-- a title: the longest that is in the text (so "Senior Sergeant" before "Sergeant", "Knight-Champion" before "Champion")
	local best, bestLen
	local lower = " " .. text:lower() .. " "
	for _, list in pairs(PVP_TITLES) do
		for i, t in ipairs(list) do
			local s = t:lower()
			local at = lower:find(s, 1, true)
			if at then
				local before, after = lower:sub(at - 1, at - 1), lower:sub(at + #s, at + #s)
				if not before:find("[%a%-]") and not after:find("[%a%-]") and (not bestLen or #s > bestLen) then best, bestLen = i, #s end
			end
		end
	end
	return best
end
local function pvpTitle(rank)
	local f = UnitFactionGroup and UnitFactionGroup("player")
	local list = PVP_TITLES[f] or nil
	return rank and list and list[rank] or nil
end
api.guidePvpRank, api.guidePvpTitle = pvpRank, pvpTitle -- (tests)

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
			local okI, id, name, _, done, _, _, _, desc, flags, icon = try(GetAchievementInfo, cid, i)
			if okI and id and isLegacy(flags) then
				if not cat then
					local okC, title = try(GetCategoryInfo, cid)
					title = okC and type(title) == "string" and title or "Legacy"
					local pvp = isPvpCategory(title)
					cat = { name = pvp and "PVP Ranking" or title, list = {}, pvp = pvp }
					out.categories[#out.categories + 1] = cat
				end
				local a = { id = id, name = name, done = done and true or false, desc = desc, have = 0, need = 0, open = {},
					category = cat.name, needs = {}, blocked = {}, icon = (type(icon) == "number" or type(icon) == "string") and icon or nil,
					rank = cat.pvp and (pvpRank(name) or pvpRank(desc)) or nil }
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
			-- 3.1.2: each category folds; open until you close it (db.legacyClosed[category name], kept)
			local isOpen = not (db and type(db.legacyClosed) == "table" and db.legacyClosed[cat.name] == true)
			local catName = cat.name
			rows[#rows + 1] = { nil, cat.name, ("%d of %d done"):format(#list - open, #list), header = true, fold = not isOpen,
				clickHint = isOpen and "Click: close" or "Click: open",
				onClick = function()
					if not db then return end
					db.legacyClosed = type(db.legacyClosed) == "table" and db.legacyClosed or {}
					db.legacyClosed[catName] = isOpen or nil
					refreshPage()
				end,
				tip = { ("%d Legacy Challenges in this category: %d done, %d still open."):format(#list, #list - open, open) } }
			for _, a in ipairs(isOpen and list or {}) do
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
					-- 3.1.2: an open challenge shows its own icon (not the "!")
					local icon = a.done and ICON_DONE or (#a.blocked > 0 and ICON_NO) or a.icon or ICON_OPEN
					local color = a.done and GREEN or (#a.blocked > 0 or #a.needs > 0) and GREY or nil
					local title = pvpTitle(a.rank)
					if title then tip[#tip + 1] = { "PvP title: " .. title, GOLD[1], GOLD[2], GOLD[3] } end
					-- (not again when the name already is this title)
					if title and type(a.name) == "string" and a.name:lower():find(title:lower(), 1, true) then title = nil end
					rows[#rows + 1] = { icon, title and (a.name .. "  |cffffd100" .. title .. "|r") or a.name,
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
-- (refreshPage: declared at the top, set by declareGuidePages)
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
-- 3.1.2 Secrets: WoW Forever's hidden toys, quests and mysteries. The idea comes from SecretChecklist (its Forever
-- list, its self-ticking steps, waypoints and found counter); the code and the wording are our own. The facts (IDs,
-- map spots) are the community's findings.
--   A step is done when its quest is turned in (quest, or any of quests), or its item is in your bags or worn (item,
--   count; with a quest too, the item in your bags only means "turn it in"). A step with neither is text: done only
--   when a later step is done. Every step before a done step counts as done too (except optional ones and
--   unordered = true). A secret is found when its toy is known or in your bags (toy), its quest is done (quest), or,
--   for a mystery, its last step is done; unsolved = true: the community has not solved it yet.
--   spots: a click on the step sets a waypoint at the next spot in turn (map is a uiMapID; x, y 0-1).
--   faction: for only one faction (the other sees it grey, with no steps).
-- A secret found for the first time says so in the chat (db.secretsFound["Name-Realm"][id]; not in profiles).
---------------------------------------------------------------------------------------------------------------------
local SECRETS = {
	{ id = "alcaz", name = "Alcaz Operative Insignia", kind = "Toy", toy = 279471, icon = 279471,
		about = "A toy from the Alcaz Prison story in Westfall.",
		steps = {
			{ "Free Mason Connery in Alcaz Prison", tip = "Leave The Questioner for last, then kill him for the key." },
			{ "More Valuable Than Gold", quest = 96337, tip = "Moonbrook inn, top floor. It gives you a Document Box.",
				spots = { { 1436, 0.434, 0.678, "Moonbrook inn" } } },
			{ "State Secrets: hand in the Document Box", item = 274041, quests = { 96376, 96377, 96379 },
				tip = "Horde: Rix Xizzix in Booty Bay. Alliance: Renzik \"The Shiv\" in Old Town, Stormwind." },
			{ "Collect 6 Fractured Insignia", item = 279450, count = 6, tip = "Put the six together to learn the toy." },
		} },
	{ id = "torch", name = "Night Watchman's Torch", kind = "Quest", quest = 98372, icon = 280612,
		about = "A slain Night Watch guard in Duskwood. Any level, both factions.",
		steps = {
			{ "Find the slain Night Watch Guard", tip = "He can be at any of six places. Click again for the next one.",
				spots = { { 1431, 0.210, 0.320, "Raven Hill Cemetery, top" }, { 1431, 0.209, 0.344, "Raven Hill Cemetery" },
					{ 1431, 0.459, 0.783, "Duskwood, south" }, { 1431, 0.478, 0.594, "Duskwood, middle" },
					{ 1431, 0.170, 0.540, "Duskwood, west" }, { 1431, 0.300, 0.674, "Duskwood, south-west" } } },
			{ "An Unfortunate End", quest = 98372, item = 280612, tip = "Turn it in at once at the guard." },
		} },
	{ id = "egg", name = "Chicken Egg", kind = "Quest", quest = 3861, icon = 11110, faction = "Alliance",
		about = "The CLUCK! quest. Alliance only.",
		steps = {
			{ "/chicken at a farm chicken until it offers CLUCK!", tip = "Keep doing /chicken at it. Hillsbrad farms work well.",
				spots = { { 1424, 0.504, 0.546, "Hillsbrad farms" } } },
			{ "Buy Special Chicken Feed", item = 11109, tip = "From Farmer Saldean in Westfall.",
				spots = { { 1436, 0.560, 0.312, "Farmer Saldean" } } },
			{ "CLUCK!", quest = 3861, item = 11110, tip = "Give the feed to the chicken." },
		} },
	{ id = "symbols", name = "Traveler's Symbols", kind = "Toy", toy = 221315, icon = 221315,
		about = "A jumping puzzle in Blackrock Depths. Level 60.",
		steps = {
			{ "Go to the platform east of the Ring of Law", tip = "Take the bridge north, over the lava." },
			{ "Clear the Blazing Fireguards and Shadowforge Dwarves on the bridge" },
			{ "Jump to the hidden spot and take the symbols", item = 221315 },
			{ "Premo's Poise-Demanding Uniform", item = 221316, optional = true },
			{ "Student Fodder", item = 216619, optional = true, tip = "Keep it. If you eat it, this step is open again." },
		} },
	{ id = "banner", name = "Scarlet Banner", kind = "Mystery", item = 278030, icon = 278030,
		about = "Four echoes for the statues in the Scarlet Monastery library. Level 28+.",
		steps = {
			{ "Graveyard Echo", item = 215426, tip = "Scarlet Monastery, Graveyard.", unordered = true },
			{ "Arathi Echo", item = 215427, tip = "Go'shek Farm.", unordered = true, spots = { { 1417, 0.620, 0.540, "Go'shek Farm" } } },
			{ "Theramore Echo", item = 215428, tip = "A grave in Dustwallow Marsh.", unordered = true,
				spots = { { 1445, 0.637, 0.425, "Dustwallow grave" } } },
			{ "Swamp Echo", item = 215425, tip = "Swamp of Sorrows.", unordered = true, spots = { { 1435, 0.168, 0.538, "Swamp of Sorrows" } } },
			{ "Give the echoes to the library statues", tip = "Warrior: Swamp. Mage: Arathi. Paladin: Theramore. Priest: Graveyard. Have a campfire near." },
			{ "Scarlet Banner", item = 278030 },
		} },
	{ id = "dawn", name = "Dawn Waker", kind = "Mystery", unsolved = true, icon = 264908,
		about = "A long Highborne chain that starts on Zephras Isle. The last step is not solved yet.",
		steps = {
			{ "Ancient Heirloom ring", item = 264908, tip = "Top floor, Zephras Isle (Ailee Farheart, Skyborne only). Wear it for the later steps.",
				spots = { { 2521, 0.417, 0.234, "The ring" }, { 2521, 0.4283, 0.2345, "Ailee Farheart" } } },
			{ "Night Watchman's Torch", quest = 98372, item = 280612, tip = "See the Night Watchman's Torch secret." },
			{ "The Ancient Hilt", quest = 93161, tip = "Ruins of Ban'aethal.", spots = { { 2521, 0.5813, 0.2406, "Ruins of Ban'aethal" } } },
			{ "Eluvi'ana", quest = 97029, item = 276188, tip = "The Ancient Skyborne Blade can be at four places. Then see Ealaane Nimbuswalker.",
				spots = { { 2521, 0.4894, 0.7268, "Blade spot 1" }, { 2521, 0.5040, 0.4430, "Blade spot 2" },
					{ 2521, 0.6625, 0.4315, "Blade spot 3" }, { 2521, 0.5990, 0.8220, "Blade spot 4" },
					{ 2521, 0.6594, 0.7437, "Ealaane Nimbuswalker" } } },
			{ "Befouled Water Globe", item = 282337, tip = "About level 22. Horde: Baron Aquanis in Blackfathom Deeps, then Je'neu at Zoram'gar. Alliance: 20 Mathystra Amulet Fragments, use the amulet at the Darkshore water ruin, Baron Marinous, then Onu.",
				spots = { { 1440, 0.116, 0.342, "Horde: Zoram'gar" }, { 1439, 0.436, 0.764, "Alliance: Grove of the Ancients" } } },
			{ "Speak to the Highborne Spirit on Zoram Strand", tip = "Wear the ring, have the globe in your bags.",
				spots = { { 1440, 0.1568, 0.1933, "Highborne Spirit" } } },
			{ "Narassin's Tome", item = 282404, tip = "Tower of Althalaxx: kill Narassin for the Azsharan Key, open the strongbox.",
				spots = { { 1439, 0.564, 0.265, "Tower of Althalaxx" } } },
			{ "Show the hilt, Eluvi'ana and the tome to Mordent Evenshade", spots = { { 2652, 0.3505, 0.4649, "Mordent Evenshade" } } },
			{ "Star of Elune", item = 282548, unordered = true, tip = "Shen'dralar Vault, Feralas. Five players: four switches, the fifth opens it. Needs the ring's buff.",
				spots = { { 1444, 0.585, 0.716, "Shen'dralar Vault" } } },
			{ "Abyssal Mote", item = 282547, unordered = true, tip = "An Abyssal Chest under the water in Azshara. Needs the chain that ends with Azsharite.",
				spots = { { 1447, 0.660, 0.541, "Abyssal Chest" } } },
			{ "Tears of Anguish", item = 282431, unordered = true, tip = "Drops from Anguished and Suffering Highborne at Lake Kel'theril. Not every time.",
				spots = { { 1452, 0.536, 0.432, "Lake Kel'theril" } } },
			{ "Cleansed Water Globe", item = 282699, tip = "Shrine of Coalescence, Hyjal.", spots = { { 2482, 0.727, 0.372, "Shrine of Coalescence" } } },
			{ "Speak to Prince Tortheldrin in Dire Maul" },
			{ "Arcanum of Binding", item = 282707, tip = "Made from the Libram of Binding (Dire Maul): a Pristine Black Diamond, 2 Large Brilliant Shards and an Arcane Crystal." },
			{ "Scrawled Note from Tortheldrin", item = 283387 },
			{ "The hilt and Altairus", unsolved = true, tip = "Nobody has solved this step yet." },
		} },
	{ id = "hunt", name = "Manual Scavenger Hunt", kind = "Mystery", unsolved = true, unordered = true, icon = 281358,
		about = "Stashes all over the world. Not solved yet; some things have moved.",
		steps = {
			{ "Night Watchman's Torch", quest = 98372, item = 280612, tip = "You need it as a tool." },
			{ "Keystone Fragment", items = { 281350, 284092, 284093 }, tip = "A barrel in the Undercity sewers.",
				spots = { { 1458, 0.2286, 0.3619, "Undercity sewers" } } },
			{ "Stone Key", item = 281358, tip = "Riverglades.", spots = { { 2548, 0.2656, 0.4558, "Riverglades" } } },
			{ "Burnt Page (Dreadmaul Hold)", item = 281356, tip = "Needs the Stone Key.", spots = { { 1419, 0.4519, 0.1647, "Dreadmaul Hold" } } },
			{ "Burnt Page (Thoradin's Wall)", spots = { { 1417, 0.2269, 0.2417, "Thoradin's Wall" } } },
			{ "Brittle Key", item = 221324, tip = "A hidden stash in Stonetalon.", spots = { { 1442, 0.4071, 0.5275, "Stonetalon stash" } } },
			{ "Torn Page", item = 281347, tip = "The Traveler's Cache in Stranglethorn.", spots = { { 1434, 0.1443, 0.2715, "Traveler's Cache" } } },
			{ "Ancient Runestone", item = 281352, tip = "A stash in Alterac.", spots = { { 1416, 0.556, 0.483, "Alterac stash" } } },
			{ "Ringo's cave", tip = "Un'Goro Crater.", spots = { { 1449, 0.5216, 0.4964, "Ringo's cave" } } },
			{ "Skeletal Chest", tip = "Under the water in the Western Plaguelands.", spots = { { 1422, 0.616, 0.728, "Skeletal Chest" } } },
			{ "Other finds", tip = "A note in Stormwind, an orc in Redridge, a snake in the Deadmines.",
				spots = { { 1453, 0.6720, 0.8253, "Stormwind note" } } },
		} },
}
-- the counter also has the two secrets with pages of their own
local OTHER_SECRETS = {
	{ id = "bedroll", name = "Cozy Sleeping Bag", quests = { BEDROLL_LAST } },
	{ id = "library", name = "Greater Friend of the Library", quests = { 79536, 82208, 84394 } },
}

local function anyDone(list)
	for _, q in ipairs(list or {}) do if questDone(q) then return true end end
	return false
end
local function stepItems(s)
	if s.items then return s.items end
	return s.item and { s.item } or nil
end
local function itemsHeld(s)
	local need = s.count or 1
	for _, id in ipairs(stepItems(s) or {}) do if itemCount(id) >= need then return true end end
	return false
end
local function hasToy(id)
	local fn = rawget(_G, "PlayerHasToy")
	if type(fn) == "function" then
		local ok, v = pcall(fn, id)
		if ok and v == true then return true end
	end
	return itemCount(id) > 0
end
local function playerFaction()
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return type(f) == "string" and f or nil
end

-- every step: "done", "bag" (the item is here, the quest to turn in) or "open"
local function secretState(e)
	local states = {}
	for i, s in ipairs(e.steps) do
		local quests = s.quests or (s.quest and { s.quest })
		if quests then
			states[i] = anyDone(quests) and "done" or itemsHeld(s) and "bag" or "open"
		elseif stepItems(s) then
			states[i] = itemsHeld(s) and "done" or "open"
		else
			states[i] = "open"
		end
	end
	local found
	if e.toy then found = hasToy(e.toy)
	elseif e.quest then found = questDone(e.quest)
	elseif e.item then found = itemCount(e.item) > 0
	else found = false end
	-- a later done step: the ones before it are done (not optional ones, not unordered ones)
	if not e.unordered then
		local last = 0
		for i, s in ipairs(e.steps) do if states[i] == "done" and not s.optional then last = i end end
		if found then last = #e.steps end
		for i = 1, last do
			local s = e.steps[i]
			if not s.optional and not s.unordered and not s.unsolved then states[i] = "done" end
		end
	end
	if e.unsolved then found = false end
	return states, found
end

local function secretFound(e)
	if e.steps then local _, found = secretState(e) return found end
	return anyDone(e.quests)
end
local function secretsCount()
	local found, total = 0, 0
	for _, list in ipairs({ SECRETS, OTHER_SECRETS }) do
		for _, e in ipairs(list) do
			if not (e.faction and playerFaction() and e.faction ~= playerFaction()) then
				total = total + 1
				if secretFound(e) then found = found + 1 end
			end
		end
	end
	return found, total
end
api.guideSecretsCount = secretsCount

-- a click: the next spot of the step in turn
local spotTurn = {}
local function spotClick(key, spots)
	return function()
		local i = (spotTurn[key] or 0) % #spots + 1
		spotTurn[key] = i
		local p = spots[i]
		waypoint(p[1], p[2], p[3], #spots > 1 and ("%s (%d of %d)"):format(p[4], i, #spots) or p[4])
	end
end

local function itemIcon(id)
	local fn = C_Item and C_Item.GetItemIconByID or GetItemIcon
	local ok, icon = try(fn, id)
	return ok and icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function secretRows()
	local rows = {}
	local found, total = secretsCount()
	rows[#rows + 1] = { nil, "Secrets", ("%d of %d found"):format(found, total), header = true,
		tip = { "Counts the secrets on this page and the Cozy Sleeping Bag and Greater Friend of the Library." } }
	local showFound = not (db and db.secretsShowFound == false)
	local faction = playerFaction()
	for _, e in ipairs(SECRETS) do
		local states, isFound = secretState(e)
		local other = e.faction and faction and e.faction ~= faction
		local stepsDone, stepsAll = 0, 0
		for i, s in ipairs(e.steps) do
			if not s.optional then stepsAll = stepsAll + 1; if states[i] == "done" then stepsDone = stepsDone + 1 end end
		end
		local right = other and (e.faction .. " only") or isFound and "found"
			or ("%s, %d of %d steps%s"):format(e.kind, stepsDone, stepsAll, e.unsolved and ", unsolved" or "")
		if showFound or not isFound then
			rows[#rows + 1] = { isFound and ICON_DONE or other and ICON_NO or itemIcon(e.icon), e.name, right,
				isFound and GREEN or other and GREY or GOLD,
				tip = { e.about, e.unsolved and { "Not solved yet: these are the steps found so far.", ORANGE[1], ORANGE[2], ORANGE[3] } or nil } }
			if not isFound and not other then
				for i, s in ipairs(e.steps) do
					local st = states[i]
					local text = "    " .. s[1] .. (s.optional and "  |cff999999(optional)|r" or "")
					local r = st == "done" and "done" or st == "bag" and "in your bags: turn it in" or s.unsolved and "unsolved"
						or (s.spots and (#s.spots > 1 and (#s.spots .. " spots") or "waypoint")) or ""
					local tip = {}
					if s.tip then tip[#tip + 1] = s.tip end
					if s.spots and #s.spots > 1 then tip[#tip + 1] = { "Each click: the next spot.", GREY[1], GREY[2], GREY[3] } end
					if not (s.quest or s.quests or stepItems(s)) and not s.unsolved then
						tip[#tip + 1] = { "Ticks itself when a later step is done.", GREY[1], GREY[2], GREY[3] }
					end
					rows[#rows + 1] = { st == "done" and ICON_DONE or st == "bag" and ICON_BAG or s.unsolved and ICON_UNKNOWN or ICON_OPEN,
						text, r, st == "done" and GREEN or s.unsolved and ORANGE or nil,
						onClick = st ~= "done" and s.spots and spotClick(e.id .. i, s.spots) or nil,
						tip = #tip > 0 and tip or nil }
				end
			end
		end
	end
	return rows
end

-- the chat line when a secret is found for the first time
local function announceFound()
	if not db then return end
	local who = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
	db.secretsFound = type(db.secretsFound) == "table" and db.secretsFound or {}
	local mine = type(db.secretsFound[who]) == "table" and db.secretsFound[who] or {}
	db.secretsFound[who] = mine
	local seen = mine.seen
	for _, list in ipairs({ SECRETS, OTHER_SECRETS }) do
		for _, e in ipairs(list) do
			if not mine[e.id] and secretFound(e) then
				mine[e.id] = true
				-- the first look only learns what was found before (no chat line for old finds)
				if seen then
					DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r |cffffd100Secret found: " .. e.name .. "!|r")
					if PlaySound and SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then pcall(PlaySound, SOUNDKIT.UI_EPICLOOT_TOAST) end
				end
			end
		end
	end
	mine.seen = true
end
api.guideAnnounceSecrets = announceFound -- (tests)

---------------------------------------------------------------------------------------------------------------------
-- Settings > Guides (declared by Config.lua: api.declareGuidePages(kit))
---------------------------------------------------------------------------------------------------------------------
api.guideLegacyRows, api.guideBookRows, api.guideBedrollRows = legacyRows, bookRows, bedrollRows -- (tests)
api.guideSecretRows = secretRows -- (tests)
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
	-- 3.1.2: open or close every category at once (a click on a category opens or closes just that one)
	k.buttons("Open all close all categories", {
		{ "Open all", function() db.legacyClosed = {}; refreshPage() end, 110 },
		{ "Close all", function()
			db.legacyClosed = {}
			for _, cat in ipairs(legacyData().categories) do db.legacyClosed[cat.name] = true end
			refreshPage()
		end, 110 },
	})
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

	k.page("secrets", "quests", "Secrets")
	k.pageByKey.secrets.cardTitle = "WoW Forever's hidden toys, quests and mysteries"
	k.note("Steps tick themselves when you have the item or the quest is done. Click a step for a waypoint; hover it for more. Ideas from SecretChecklist.")
	k.check("Show found secrets", function() return db.secretsShowFound ~= false end,
		function(v) db.secretsShowFound = v and true or false; refreshPage() end)
	k.help("a found secret is one green line")
	k.custom("Secrets toys mysteries alcaz insignia night watchman torch chicken egg traveler symbols scarlet banner dawn waker scavenger hunt",
		rowList(secretRows, nil, 120), true)
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local f = CreateFrame("Frame")
	pcall(f.RegisterEvent, f, "ACHIEVEMENT_EARNED")
	pcall(f.RegisterEvent, f, "CRITERIA_UPDATE")
	pcall(f.RegisterEvent, f, "SKILL_LINES_CHANGED")
	f:SetScript("OnEvent", function() legacyAt = -100 end)
	-- secrets: a found one says so in the chat (looked at a moment after a quest, a bag or a toy change)
	local s = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "TOYS_UPDATED", "NEW_TOY_ADDED" }) do pcall(s.RegisterEvent, s, e) end
	local after = C_Timer and C_Timer.After
	if type(after) ~= "function" then return end
	local pending = false
	s:SetScript("OnEvent", function()
		if pending then return end
		pending = true
		after(2, function() pending = false; pcall(announceFound) end)
	end)
	after(8, function() pcall(announceFound) end)
end
