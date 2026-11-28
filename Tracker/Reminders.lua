-- 3.2 Reminders: a row at the top of the tracker (under the tracked reputation) with
--   "3 new spells at your trainer" (db.trainerReminder): read from the class trainer's window each visit (every spell
--     it lists that you have not learned, with its level and cost) and where you stood; counted against your level.
--     Click: a waypoint to that trainer. Hover: the spells and their cost.
--   "2 talent points to spend" (db.talentReminder): UnitCharacterPoints or GetUnspentTalentPoints, when the client
--     has them. Click: the talent window (not in combat).
-- and an alert when an item in your bags starts a quest you do not have (db.questItemAlert): C_Container's quest
-- info for each slot, after the bags change; once for each item a session.
-- CONSTRAINT: the trainer functions (GetNumTrainerServices, GetTrainerServiceInfo, ...) are not in the Forever API
-- ledger; each is checked at run time and a missing one means no trainer line. The trainer's filters are not changed.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
-- 3.2: the character key with the surname (Core.lua api.playerKey); without it (tests) "Name-Realm"
local function playerKey(...)
	if api.playerKey then return api.playerKey(...) end
	local name, realm = UnitName and UnitName("player"), GetRealmName and GetRealmName()
	if type(name) ~= "string" or (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then return nil end
	return name .. "-" .. tostring(realm or "")
end
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r " .. text) end
local unpackFn = table.unpack or unpack
local function pack(...) return { n = select("#", ...), ... } end
-- fn(...) in pcall; nil when it fails, is missing or gives a secret value
local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = pack(pcall(fn, ...))
	if not r[1] then return nil end
	for i = 2, r.n do if isSecret(r[i]) then return nil end end
	return unpackFn(r, 2, r.n)
end
api.safeCall = api.safeCall or call
local function charKey() return playerKey(ns.db and ns.db.trainerLog) or "?" end -- 3.2: with the surname
local function myLevel() return tonumber(call(UnitLevel, "player")) or 1 end

---------------------------------------------------------------------------------------------------------------------
-- Trainer
---------------------------------------------------------------------------------------------------------------------
local function trainerBook()
	if not db then return nil end
	db.trainerLog = type(db.trainerLog) == "table" and db.trainerLog or {}
	local key = charKey()
	db.trainerLog[key] = type(db.trainerLog[key]) == "table" and db.trainerLog[key] or {}
	return db.trainerLog[key]
end
local function playerSpot()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local map = call(C_Map.GetBestMapForUnit, "player")
	local pos = map and call(C_Map.GetPlayerMapPosition, map, "player")
	if not pos then return nil end
	local x, y = call(pos.GetXY, pos)
	if not (x and y) then return nil end
	return map, x, y
end
local function scanTrainer()
	if not (db and db.trainerReminder ~= false) then return end
	if call(IsTradeskillTrainer) then return end -- a profession trainer: not the class's spells
	local n = tonumber(call(GetNumTrainerServices))
	if not n or n <= 0 then return end
	local spells = {}
	for i = 1, n do
		local name, rank, category = call(GetTrainerServiceInfo, i)
		if type(name) == "string" and category ~= "used" and category ~= "header" then
			local level = tonumber(call(GetTrainerServiceLevelReq, i)) or 0
			local cost = tonumber(call(GetTrainerServiceCost, i)) or 0
			spells[#spells + 1] = { name = name, rank = type(rank) == "string" and rank or nil, level = level, cost = cost }
		end
	end
	local book = trainerBook()
	if not book then return end
	book.spells = spells
	local map, x, y = playerSpot()
	local npc = call(UnitName, "npc")
	if map then book.trainer = { map = map, x = x, y = y, name = type(npc) == "string" and npc or "Trainer" } end
	book.at = time and time() or nil
	if api.applyLayout then api.applyLayout() end
end
api.remindersScanTrainer = scanTrainer -- (tests)
-- the spells you can learn now: { list, totalCost }
function api.trainerDue()
	local book = trainerBook()
	if not (book and type(book.spells) == "table") then return {}, 0 end
	local level, out, cost = myLevel(), {}, 0
	for _, s in ipairs(book.spells) do
		if (tonumber(s.level) or 0) > 0 and s.level <= level then out[#out + 1] = s; cost = cost + (tonumber(s.cost) or 0) end
	end
	return out, cost
end

---------------------------------------------------------------------------------------------------------------------
-- Talents
---------------------------------------------------------------------------------------------------------------------
function api.unspentTalents()
	local n = call(rawget(_G, "GetUnspentTalentPoints"))
	if type(n) ~= "number" then n = call(rawget(_G, "UnitCharacterPoints"), "player") end
	n = tonumber(n)
	return n and n > 0 and n or 0
end
local function openTalents()
	if InCombatLockdown and InCombatLockdown() then return end
	if type(rawget(_G, "ToggleTalentFrame")) == "function" then pcall(ToggleTalentFrame)
	elseif type(rawget(_G, "PlayerTalentFrame_Toggle")) == "function" then pcall(PlayerTalentFrame_Toggle) end
end

---------------------------------------------------------------------------------------------------------------------
-- The row at the top of the tracker
---------------------------------------------------------------------------------------------------------------------
local row, lines = nil, {}
local function fontOf(objectName, fallback)
	local object = _G[objectName]
	if object and object.GetFont then
		local file, size, flags = object:GetFont()
		if file and size then return file, size, flags end
	end
	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fallback, ""
end
local function money(c)
	if api.statsMoney then return api.statsMoney(c) end
	return tostring(math.floor((tonumber(c) or 0) / 100)) .. "s"
end
-- what the row shows: { { text, onClick, tip = { lines } }, ... }
local function entries()
	local out = {}
	if not db then return out end
	if db.trainerReminder ~= false then
		local due, cost = api.trainerDue()
		if #due > 0 then
			local book = trainerBook()
			local t = book and book.trainer
			local tip = {}
			for i, s in ipairs(due) do
				if i > 12 then tip[#tip + 1] = ("... and %d more"):format(#due - 12) break end
				tip[#tip + 1] = s.name .. (s.rank and (" (" .. s.rank .. ")") or "") .. "  " .. money(s.cost)
			end
			tip[#tip + 1] = "Total: " .. money(cost)
			if t then tip[#tip + 1] = "Click: waypoint to " .. tostring(t.name) end
			out[#out + 1] = { ("|cffffd100%d new spell%s|r at your trainer"):format(#due, #due == 1 and "" or "s"),
				t and function()
					if api.guideWaypoint then api.guideWaypoint(t.map, t.x, t.y, t.name)
					elseif C_Map.SetUserWaypoint and UiMapPoint then
						pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(t.map, t.x, t.y))
					end
				end, tip = tip }
		end
	end
	if db.talentReminder ~= false then
		local n = api.unspentTalents()
		if n > 0 then
			out[#out + 1] = { ("|cff66ccff%d talent point%s|r to spend"):format(n, n == 1 and "" or "s"), openTalents,
				tip = { "Click: the talent window" } }
		end
	end
	return out
end
api.remindersEntries = entries -- (tests)
local function line(i)
	if lines[i] then return lines[i] end
	local b = CreateFrame("Button", nil, row)
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b.text:SetShadowOffset(1, -1)
	b.text:SetShadowColor(0, 0, 0, 1)
	b.text:SetPoint("TOPLEFT")
	b.text:SetPoint("BOTTOMRIGHT")
	b:SetScript("OnClick", function(self) if self.data and self.data[2] then pcall(self.data[2]) end end)
	b:SetScript("OnEnter", function(self)
		local d = self.data
		if not (d and d.tip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		for i2, t in ipairs(d.tip) do
			if i2 == 1 then GameTooltip:SetText(t, 1, 1, 1) else GameTooltip:AddLine(t, 0.85, 0.85, 0.85) end
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	lines[i] = b
	return b
end
local BOTTOM = 6
function api.layoutReminders(anchor, base, alpha)
	local list = entries()
	if #list == 0 or not anchor or not (anchor.IsShown and anchor:IsShown()) then
		if row then row:Hide() end
		return 0
	end
	if not row then
		row = CreateFrame("Frame", "ForeverTrackerPlusReminders", UIParent)
	end
	-- our tracker's top slot (Own/Frame.lua api.ownCardHost)
	local module = anchor
	local ui = UIParent:GetEffectiveScale()
	local s = (module and module.GetEffectiveScale and module:GetEffectiveScale() or anchor:GetEffectiveScale()) / ui
	local width = module and module.GetWidth and module:GetWidth() or (anchor:GetWidth() * anchor:GetEffectiveScale() / ui / s)
	local mLeft, aLeft = module and module.GetLeft and module:GetLeft(), anchor:GetLeft()
	local dx = (mLeft and aLeft) and ((mLeft * module:GetEffectiveScale() - aLeft * anchor:GetEffectiveScale()) / ui) or 0
	local file, size, flags = fontOf("ObjectiveTrackerLineFont", 12)
	local lh = math.ceil(size + 4)
	row:SetScale(s)
	row:SetFrameStrata(anchor:GetFrameStrata())
	row:SetFrameLevel(anchor:GetFrameLevel() + 5)
	row:SetAlpha(alpha or 1)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", anchor, "TOPLEFT", dx / s, -base / s)
	local h = lh * #list + BOTTOM
	row:SetSize(width, h)
	for i, d in ipairs(list) do
		local b = line(i)
		b.data = d
		b.text:SetFont(file, size, flags)
		b.text:SetText(d[1])
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(i - 1) * lh)
		b:SetSize(width, lh)
		b:Show()
	end
	for i = #list + 1, #lines do lines[i]:Hide() end
	row:Show()
	return h * s
end

---------------------------------------------------------------------------------------------------------------------
-- Quest-start items
---------------------------------------------------------------------------------------------------------------------
local alerted = {}
local function questTitle(id)
	local t = C_QuestLog and call(C_QuestLog.GetTitleForQuestID, id)
	if type(t) == "string" and t ~= "" then return t end
	if api.questieGet then
		local ok, name = pcall(api.questieGet, "quest", id, "name")
		if ok and type(name) == "string" then return name end
	end
	return "a quest"
end
local function questDone(id)
	return C_QuestLog and call(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false
end
local function scanBags(quiet)
	if not (db and db.questItemAlert ~= false) then return end
	local info = C_Container and C_Container.GetContainerItemQuestInfo
	local slots = C_Container and C_Container.GetContainerNumSlots
	if type(info) ~= "function" or type(slots) ~= "function" then return end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, tonumber(call(slots, bag)) or 0 do
			local q = call(info, bag, slot)
			local qid = type(q) == "table" and tonumber(q.questID or q.questId)
			if qid and not q.isActive and not alerted[qid] and not questDone(qid) then
				alerted[qid] = true
				local link = C_Container.GetContainerItemLink and call(C_Container.GetContainerItemLink, bag, slot)
				local text = ("%s starts a quest: |cffffd100%s|r"):format(type(link) == "string" and link or "An item", questTitle(qid))
				say(text)
				if not quiet then
					if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.82, 0) end
					if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then (root.playSound or pcall)(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) end
				end
			end
		end
	end
end
api.remindersScanBags = scanBags -- (tests)

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local bagsDirty = false
events:SetScript("OnEvent", function(_, event)
	if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		scanTrainer()
	elseif event == "BAG_UPDATE_DELAYED" then
		if not bagsDirty then
			bagsDirty = true
			C_Timer.After(0.5, function() bagsDirty = false; scanBags(false) end)
		end
	elseif event == "QUEST_ACCEPTED" then
		-- the quest you took from an item: its alert may come again for a second copy only next session
	else -- level, talents, spells learned: the row may change
		if api.applyLayout then api.applyLayout() end
	end
end)
ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP",
		"CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED" }) do
		pcall(events.RegisterEvent, events, e)
	end
	C_Timer.After(10, function() scanBags(true) end)
end

---------------------------------------------------------------------------------------------------------------------
-- Settings: Helpers > Reminders
---------------------------------------------------------------------------------------------------------------------
api.pageDeclarers = api.pageDeclarers or {}
api.pageDeclarers[#api.pageDeclarers + 1] = function(k)
	local function relayout() if api.applyLayout then api.applyLayout() end end
	k.page("reminders", "quests", "Reminders")
	k.pageByKey.reminders.cardTitle = "Little nudges while you level"
	k.heading("At the top of the tracker")
	k.check("New spells at your trainer", function() return db.trainerReminder ~= false end,
		function(v) db.trainerReminder = v and true or false; relayout() end)
	k.help("after one visit to your class trainer, a line shows when new spells wait there; click it for a waypoint")
	k.check("Unspent talent points", function() return db.talentReminder ~= false end,
		function(v) db.talentReminder = v and true or false; relayout() end)
	k.help("a line while you have talent points to spend; click it to open the talent window")
	k.heading("Bags")
	k.check("Alert for items that start a quest", function() return db.questItemAlert ~= false end,
		function(v) db.questItemAlert = v and true or false end)
	k.help("when you loot an item that starts a quest you do not have: a message on screen and in chat")
	if api.declareJournalRows then api.declareJournalRows(k) end
	k.pageByKey.reminders.reset = k.reset
end
