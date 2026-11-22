-- 3.1 Guides (Settings > Guides). The ideas come from Questline (its Legacy Challenges tab, library books and
-- sleeping bag guide); the code and the data are our own: everything is read live from the game and from Questie.
--   legacy   WoW Forever's Legacy Challenges: every achievement with the legacy flag (0x8000000 in
--            GetAchievementInfo's flags), by category, with its criteria done/total; the tooltip lists the open ones.
--            db.legacyShowDone shows finished ones too.
--   books    (Questie) the library book quests (api.questieGuideData finds them: a quest that starts at a librarian
--            and at the book itself). Done, in your bags, or open; click for a waypoint to the book.
--   bedroll  (Questie) the Cozy Sleeping Bag chain: its first quest is found by name, the rest by Questie's
--            prerequisite links. Done, in the log, or open; click for a waypoint to the next step's giver.
-- Every achievement call is in pcall; a page whose data is not there says so.
local ADDON, root = ...; local ns = root.tracker
local hooksecurefunc, CreateFrame, C_Timer = (root.lagWrap or function(_, ...) return ... end)("Guides", hooksecurefunc, CreateFrame, C_Timer) -- /qt lag
if ns.disabled then return end
local api = ns.api
local db

local LEGACY_FLAG = 0x8000000
local BEDROLL_START = "... and that note you found"
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_OPEN = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_LOG = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_BAG = "Interface\\Icons\\INV_Misc_Bag_08"
local GOLD = { 1, 0.82, 0.25 }
local GREEN = { 0.45, 0.9, 0.45 }

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
-- header = bool } }
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
				for _, t in ipairs(d.tip or {}) do GameTooltip:AddLine(t, 1, 1, 1, true) end
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
					r.text:SetPoint("LEFT", r, "LEFT", d[1] and (is + 8) or 2, 0)
					r.text:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
					r.text:SetText(d[2] or "")
					local c = d.header and GOLD or d[4] or C.value
					r.text:SetTextColor(c[1], c[2], c[3])
					r.right:ClearAllPoints()
					r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
					r.right:SetWidth(math.floor(width * 0.4))
					r.right:SetText(d[3] or "")
					r:EnableMouse(d.onClick ~= nil or d.tip ~= nil)
					y = y + rowH
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
local function legacyData()
	if legacyCache and GetTime() - legacyAt < 10 then return legacyCache end
	local out = { categories = {}, done = 0, total = 0 }
	local ok, cats = try(GetCategoryList)
	if not ok or type(cats) ~= "table" then legacyCache, legacyAt = out, GetTime() return out end
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
				local a = { id = id, name = name, done = done and true or false, desc = desc, have = 0, need = 0, open = {} }
				local okK, n = try(GetAchievementNumCriteria, id)
				for k = 1, okK and tonumber(n) or 0 do
					local okR, cname, _, cdone = try(GetAchievementCriteriaInfo, id, k)
					if okR then
						a.need = a.need + 1
						if cdone then a.have = a.have + 1
						elseif type(cname) == "string" and cname ~= "" then a.open[#a.open + 1] = cname end
					end
				end
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
	for _, cat in ipairs(data.categories) do
		local open = 0
		for _, a in ipairs(cat.list) do if not a.done then open = open + 1 end end
		if showDone or open > 0 then
			rows[#rows + 1] = { nil, cat.name, ("%d of %d done"):format(#cat.list - open, #cat.list), header = true }
			for _, a in ipairs(cat.list) do
				if showDone or not a.done then
					local tip = {}
					if a.desc and a.desc ~= "" then tip[1] = a.desc end
					if #a.open > 0 then
						tip[#tip + 1] = " "
						tip[#tip + 1] = "Still to do:"
						for i = 1, math.min(#a.open, 15) do tip[#tip + 1] = "  " .. a.open[i] end
						if #a.open > 15 then tip[#tip + 1] = ("  and %d more"):format(#a.open - 15) end
					end
					rows[#rows + 1] = { a.done and ICON_DONE or ICON_OPEN, a.name,
						a.need > 0 and ("%d / %d"):format(a.have, a.need) or (a.done and "done" or ""),
						a.done and GREEN or nil, tip = tip }
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
	local rows, done = {}, 0
	for _, b in ipairs(data.books) do
		local isDone = questDone(b.quest)
		if isDone then done = done + 1 end
		local map, x, y, zone = api.questieSpot("Object", b.object)
		local inBag = not isDone and itemCount(b.item) > 0
		rows[#rows + 1] = { isDone and ICON_DONE or inBag and ICON_BAG or ICON_OPEN, b.name,
			isDone and "turned in" or inBag and "in your bags" or (zone or ""), isDone and GREEN or nil,
			onClick = not isDone and map and function() waypoint(map, x, y, b.name) end or nil,
			tip = inBag and { "In your bags: take it to the librarian." } or nil }
	end
	if #rows == 0 then return { { nil, "Questie lists no library books for this character." } } end
	table.insert(rows, 1, { nil, "Library books", ("%d of %d turned in"):format(done, #rows), header = true })
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
	local starts = data.named[BEDROLL_START] or {}
	local first
	for _, q in ipairs(starts) do if api.questieForPlayer(q) then first = q break end end
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
local function bedrollRows()
	if not (api.questieOn and api.questieOn()) then return { { nil, "Needs Questie." } } end
	local chain = bedrollChain()
	if not chain then return { { nil, "Reading Questie's quests ..." } } end
	if #chain == 0 then return { { nil, "Questie does not list this chain for this character." } } end
	local rows, done = {}, 0
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
	table.insert(rows, 1, { nil, "Cozy Sleeping Bag", done == #chain and "all done!" or ("%d of %d done"):format(done, #chain),
		header = true })
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
	k.custom("Legacy challenges dungeon explorer achievements", rowList(legacyRows,
		"No Legacy Challenges found (or all are done).", 160), true)

	k.page("books", "quests", "Library books")
	k.pageByKey.books.cardTitle = "Books for the library"
	k.note("Find each book and take it to the librarian. Click a book for a waypoint. Needs Questie.")
	k.custom("Library books friend of the library", rowList(bookRows, nil, 60), true)

	k.page("bedroll", "quests", "Sleeping bag")
	k.pageByKey.bedroll.cardTitle = "The Cozy Sleeping Bag quest chain"
	k.note("From level 14. Do the steps in order; click a step for a waypoint to its giver. Needs Questie.")
	k.custom("Cozy sleeping bag bedroll chain", rowList(bedrollRows, nil, 20), true)
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local f = CreateFrame("Frame")
	pcall(f.RegisterEvent, f, "ACHIEVEMENT_EARNED")
	pcall(f.RegisterEvent, f, "CRITERIA_UPDATE")
	f:SetScript("OnEvent", function() legacyAt = -100 end)
end
