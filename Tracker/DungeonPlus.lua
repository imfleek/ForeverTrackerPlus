-- 3.2 Dungeon card extras (lines under the card's instance line, Dungeon.lua):
--   Splits (db.dungeonSplits): the run's time and each boss's kill time from the run's start (ENCOUNTER_END with
--     success), with your best for that boss in that instance (ForeverTrackerPlusDB.splitLog[instance][boss]).
--     A run starts when you enter the instance; it goes on when you come back to the same one within 30 minutes.
--   Quests here (db.dungeonPartyQuests): who in your party has which quest for this dungeon (Questie's zone of the
--     quest is the dungeon), from Party.lua (our party messages, Questie's party sync, IsUnitOnQuest).
--   Share (db.dungeonShare): "Share N quests": every quest of yours for this dungeon that can be shared, one after the
--     other. /qt share: every quest in your log that can be shared.
--   Boss abilities (db.dungeonAbilities): the next boss not killed this run, with its main abilities from the
--     Encounter Journal (hover). Nothing when the client has no journal for the instance.
-- CONSTRAINT: EJ_GetEncounterInfoByIndex, EJ_GetEncounterInfo, EJ_GetSectionInfo and QuestLogPushQuest are old
-- globals (not in the Forever ledger); C_EncounterJournal.GetInstanceForGameMap / GetSectionInfo are. All are
-- checked at run time.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r " .. text) end
local function g(name) local fn = rawget(_G, name); return type(fn) == "function" and fn or nil end
local function clock(sec)
	if api.statsClock then return api.statsClock(sec) end
	sec = math.floor(tonumber(sec) or 0)
	return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

---------------------------------------------------------------------------------------------------------------------
-- The run and its splits
---------------------------------------------------------------------------------------------------------------------
local run -- { key, name, start, left, kills = { { boss, t } } }
local RESUME = 30 * 60
local function inside()
	if api.dungeonInstance then return api.dungeonInstance() end -- (all three values: kind, name, id)
end
local function onEnter()
	local kind, name, id = inside()
	if not kind then
		if run and not run.left then
			run.left = GetTime()
			if api.dungeonRunLeft then pcall(api.dungeonRunLeft, run) end -- 3.2: the summary and history (DungeonRuns.lua)
		end
		return
	end
	local key = tostring(id or name or "?")
	if run and run.key == key and (not run.left or GetTime() - run.left < RESUME) then
		run.left = nil
		return
	end
	run = { key = key, name = name or "?", start = GetTime(), kills = {} }
	if api.dungeonRunStarted then pcall(api.dungeonRunStarted, run) end
end
local function splitBook(name)
	if not db then return {} end
	db.splitLog = type(db.splitLog) == "table" and db.splitLog or {}
	db.splitLog[name] = type(db.splitLog[name]) == "table" and db.splitLog[name] or {}
	return db.splitLog[name]
end
local struck -- 3.2: { name, at } the boss just killed (struck through on the card)
local function onEncounterEnd(_, bossName, _, _, success)
	if not run or isSecret(bossName) or type(bossName) ~= "string" then return end
	if success ~= 1 and success ~= true then return end
	local t = GetTime() - run.start
	run.kills[#run.kills + 1] = { bossName, t }
	local book = splitBook(run.name)
	local best = tonumber(book[bossName])
	-- 3.2 (user): faster than your best: "NEW BEST" on the card (Dungeon.lua, Animations.lua animNewBest)
	if best and t < best and api.dungeonCardNewBest then
		pcall(api.dungeonCardNewBest, ("NEW BEST  -%s"):format(clock(best - t)))
	end
	if db.dungeonSplits ~= false then
		local diff = best and (t - best) or nil
		say(("%s: %s%s"):format(bossName, clock(t), diff and ("  (best %s, %s%s)"):format(clock(best),
			diff <= 0 and "|cff44ff44-" or "|cffff6644+", clock(math.abs(diff)) .. "|r") or "  (first time)"))
	end
	if not best or t < best then book[bossName] = math.floor(t + 0.5) end
	-- 3.2 (user): the killed boss's portrait turns over with a check; the last boss: the card says CLEARED (Dungeon.lua)
	if api.dungeonCardKill then
		local list = api.dungeonEncounters and api.dungeonEncounters() or {}
		local cleared = #list > 0 and api.dungeonNextBoss and api.dungeonNextBoss() == nil
		if cleared then run.cleared = true end
		pcall(api.dungeonCardKill, bossName, cleared and true or false)
	end
	-- 3.2 (user): the "Next:" line keeps the killed boss for a moment while a red line strikes it through
	if api.animOn and api.animOn("strike") then
		struck = { name = bossName, at = GetTime() }
		if C_Timer and C_Timer.After then
			C_Timer.After(1.3, function() struck = nil; if api.applyLayout then api.applyLayout() end end)
		end
	end
	if api.applyLayout then api.applyLayout() end
end
api.dungeonRunForTests = function() return run end
-- 3.2: a run goes on: inside, started, not cleared (the card's run light)
function api.dungeonRunActive() return run ~= nil and not run.left and not run.cleared end
api.dungeonOnEnter, api.dungeonOnEncounterEnd = onEnter, onEncounterEnd -- (tests)

---------------------------------------------------------------------------------------------------------------------
-- Dungeon quests and the party
---------------------------------------------------------------------------------------------------------------------
local zoneOf = {}
local function questZoneName(id)
	if zoneOf[id] ~= nil then return zoneOf[id] or nil end
	local name = false
	if api.questieGet and api.questieZoneName then
		local ok, area = pcall(api.questieGet, "Quest", id, "zoneOrSort")
		if ok and type(area) == "number" and area > 0 then name = api.questieZoneName(area) or false end
	end
	zoneOf[id] = name
	return name or nil
end
local function forDungeon(name)
	local lower = type(name) == "string" and name:lower() or nil
	return function(id)
		local z = lower and questZoneName(id)
		return z ~= nil and z:lower() == lower
	end
end
local function questTitle(id)
	local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if type(t) == "string" and not isSecret(t) and t ~= "" then return t end
	if api.questieGet then
		local ok, n = pcall(api.questieGet, "Quest", id, "name")
		if ok and type(n) == "string" then return n end
	end
	return "Quest " .. tostring(id)
end
function api.dungeonQuestHolders(name)
	if not api.partyQuestHolders then return {} end
	local ok, out = pcall(api.partyQuestHolders, forDungeon(name))
	return ok and out or {}
end

-- sharing: one quest each 0.6 s; your selected quest put back afterwards
local function pushable(id)
	if not (C_QuestLog.IsPushableQuest and g("QuestLogPushQuest")) then return false end
	local ok, v = pcall(C_QuestLog.IsPushableQuest, id)
	return ok and v and true or false
end
local function shareList(ids)
	if not IsInGroup() then say("you are not in a group.") return end
	local list = {}
	for _, id in ipairs(ids) do if pushable(id) then list[#list + 1] = id end end
	if #list == 0 then say("no quest here can be shared.") return end
	local before = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
	local i = 0
	local function nextOne()
		i = i + 1
		local id = list[i]
		if not id then
			if before and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, before) end
			say(("shared %d quest%s."):format(#list, #list == 1 and "" or "s"))
			return
		end
		if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end
		pcall(QuestLogPushQuest)
		C_Timer.After(0.6, nextOne)
	end
	nextOne()
end
local function myQuests(want)
	local out = {}
	for i = 1, (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0) do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID and (not want or want(info.questID)) then out[#out + 1] = info.questID end
	end
	return out
end
api.shareAllQuests = function() shareList(myQuests()) end
api.shareDungeonQuests = function(name) shareList(myQuests(forDungeon(name))) end

---------------------------------------------------------------------------------------------------------------------
-- Boss abilities (Encounter Journal)
---------------------------------------------------------------------------------------------------------------------
local ejCache = {}
local function journalInstance()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if type(map) ~= "number" or isSecret(map) then return nil end
	local fn = (C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap) or g("EJ_GetInstanceForMap")
	if not fn then return nil end
	local ok, id = pcall(fn, map)
	return ok and type(id) == "number" and id > 0 and id or nil
end
local function sectionInfo(id)
	local fn = C_EncounterJournal and C_EncounterJournal.GetSectionInfo
	if fn then
		local ok, info = pcall(fn, id)
		if ok and type(info) == "table" then return info end
	end
	local old = g("EJ_GetSectionInfo")
	if old then
		local ok, title, desc, _, abilityIcon, _, sibling, child = pcall(old, id)
		if ok and title then
			return { title = title, description = desc, abilityIcon = abilityIcon, siblingSectionID = sibling,
				firstChildSectionID = child }
		end
	end
	return nil
end
-- { { name, abilities = { { title, description } } }, ... } for this instance
local function encounters()
	local inst = journalInstance()
	if not inst then return {} end
	if ejCache[inst] then return ejCache[inst] end
	local out = {}
	local byIndex, info = g("EJ_GetEncounterInfoByIndex"), g("EJ_GetEncounterInfo")
	for i = 1, 30 do
		if not byIndex then break end
		local ok, name, _, encounterID, rootSection = pcall(byIndex, i, inst)
		if not ok or not name then break end
		if not rootSection and info and encounterID then
			local ok2, _, _, _, root2 = pcall(info, encounterID)
			if ok2 then rootSection = root2 end
		end
		local e = { name = name, abilities = {} }
		-- the first two levels of the boss's sections: their titles and short descriptions
		local function walk(id, depth)
			local guard = 0
			while id and id > 0 and #e.abilities < 8 and guard < 40 do
				guard = guard + 1
				local s = sectionInfo(id)
				if not s then break end
				if s.title and s.title ~= "" and (s.abilityIcon or depth > 0) then
					local d = type(s.description) == "string" and s.description:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
					if d and #d > 140 then d = d:sub(1, 137) .. "..." end
					e.abilities[#e.abilities + 1] = { s.title, d }
				end
				if depth < 2 and s.firstChildSectionID then walk(s.firstChildSectionID, depth + 1) end
				id = s.siblingSectionID
			end
		end
		if rootSection then pcall(walk, rootSection, 0) end
		out[#out + 1] = e
	end
	ejCache[inst] = out
	return out
end
api.dungeonEncounters = encounters
local function nextBoss()
	local killed = {}
	for _, k in ipairs(run and run.kills or {}) do killed[k[1]] = true end
	for _, e in ipairs(encounters()) do if not killed[e.name] then return e end end
	return nil
end
api.dungeonNextBoss = nextBoss

---------------------------------------------------------------------------------------------------------------------
-- The lines on the card
---------------------------------------------------------------------------------------------------------------------
local lines, parentBody = {}, nil
local function fontOf()
	local o = _G.ObjectiveTrackerLineFont
	if o and o.GetFont then
		local f, s, fl = o:GetFont()
		if f then return f, s, fl end
	end
	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, ""
end
local function line(i, body)
	local b = lines[i]
	if b and b:GetParent() == body then return b end
	b = CreateFrame("Button", nil, body)
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b.text:SetShadowOffset(1, -1)
	b.text:SetShadowColor(0, 0, 0, 1)
	b.text:SetTextColor(0.8, 0.8, 0.8)
	b.text:SetAllPoints()
	b:SetScript("OnClick", function(self) if self.data and self.data.onClick then pcall(self.data.onClick) end end)
	b:SetScript("OnEnter", function(self)
		local d = self.data
		if not (d and d.tip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		local first = true
		for _, t in ipairs(d.tip()) do
			if type(t) == "table" then
				if first then GameTooltip:SetText(t[1], t[2] or 1, t[3] or 1, t[4] or 1) else GameTooltip:AddLine(t[1], t[2] or 1, t[3] or 1, t[4] or 1, true) end
			else
				if first then GameTooltip:SetText(t, 1, 1, 1) else GameTooltip:AddLine(t, 0.85, 0.85, 0.85, true) end
			end
			first = false
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	lines[i] = b
	return b
end
local function runText()
	if not run then return nil end
	local t = GetTime() - run.start
	local n = #run.kills
	return ("Run |cffffffff%s|r  %d boss%s"):format(clock(t), n, n == 1 and "" or "es")
end
-- what the card shows: { { text = fn() or string, tip = fn, onClick = fn } }
local function entries(name)
	local out = {}
	if not db then return out end
	if db.dungeonSplits ~= false and run then
		out[#out + 1] = { text = runText, tip = function()
			local tip = { { "Splits: " .. tostring(run.name), 1, 0.82, 0 } }
			local book = splitBook(run.name)
			for _, k in ipairs(run.kills) do
				local best = tonumber(book[k[1]])
				tip[#tip + 1] = ("%s  %s%s"):format(k[1], clock(k[2]), best and ("  (best %s)"):format(clock(best)) or "")
			end
			for boss, best in pairs(book) do
				local done = false
				for _, k in ipairs(run.kills) do if k[1] == boss then done = true end end
				if not done then tip[#tip + 1] = { ("%s  best %s"):format(boss, clock(best)), 0.6, 0.6, 0.6 } end
			end
			if #tip == 1 then tip[#tip + 1] = "Kill a boss: its time from the run's start shows here." end
			return tip
		end }
	end
	if db.dungeonPartyQuests ~= false or db.dungeonShare ~= false then
		local holders = api.dungeonQuestHolders(name)
		local ids, byWho, mine = {}, {}, 0
		for id, who in pairs(holders) do
			ids[#ids + 1] = id
			for _, w in ipairs(who) do
				byWho[w] = (byWho[w] or 0) + 1
				if w == "You" then mine = mine + 1 end
			end
		end
		table.sort(ids)
		if db.dungeonPartyQuests ~= false and #ids > 0 then
			local parts = {}
			if byWho.You then parts[#parts + 1] = "You " .. byWho.You end
			for w, n in pairs(byWho) do if w ~= "You" then parts[#parts + 1] = (w:match("^(%S+)") or w) .. " " .. n end end
			out[#out + 1] = { text = ("Quests here: |cffffffff%d|r  %s"):format(#ids, table.concat(parts, ", ")), tip = function()
				local tip = { { "Quests for " .. tostring(name), 1, 0.82, 0 } }
				for _, id in ipairs(ids) do tip[#tip + 1] = questTitle(id) .. ": " .. table.concat(holders[id], ", ") end
				return tip
			end }
		end
		if db.dungeonShare ~= false and IsInGroup() and mine > 0 then
			out[#out + 1] = { text = ("|cff66ccffShare %d quest%s|r"):format(mine, mine == 1 and "" or "s"),
				onClick = function() api.shareDungeonQuests(name) end,
				tip = function() return { "Share your quests for this dungeon with the party", { "Click: share", 0.6, 0.85, 1 } } end }
		end
	end
	-- 3.2 (user): the loot you want here (DungeonLoot.lua: DungeonJournal favourites, SpecBisTooltip best in slot)
	if api.dungeonLootEntry then
		local ok, e = pcall(api.dungeonLootEntry, name)
		if ok and e then out[#out + 1] = e end
	end
	if struck and db.dungeonAbilities ~= false then
		out[#out + 1] = { text = ("Next: |cffffffff%s|r"):format(struck.name), strike = struck }
	elseif db.dungeonAbilities ~= false then
		local boss = nextBoss()
		if boss and #boss.abilities > 0 then
			out[#out + 1] = { text = ("Next: |cffffffff%s|r  (hover)"):format(boss.name), tip = function()
				local tip = { { boss.name, 1, 0.82, 0 } }
				for _, a in ipairs(boss.abilities) do
					tip[#tip + 1] = { a[1], 1, 1, 1 }
					if a[2] then tip[#tip + 1] = { a[2], 0.7, 0.7, 0.7 } end
				end
				return tip
			end }
		end
	end
	return out
end
api.dungeonExtraEntries = entries -- (tests)

function api.hideDungeonExtras() for _, b in ipairs(lines) do b:Hide() end end
function api.layoutDungeonExtras(body, x, y, width, lSize, name)
	parentBody = body
	local list = entries(name)
	local file, _, flags = fontOf()
	local lh = math.ceil((lSize or 12) + 4)
	for i, d in ipairs(list) do
		local b = line(i, body)
		b.data = d
		b.text:SetFont(file, lSize or 12, flags)
		b.text:SetText(type(d.text) == "function" and (d.text() or "") or d.text)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(y + (i - 1) * lh))
		b:SetSize(math.max(width, 40), lh)
		b:Show()
		if d.sparkle then -- 3.2 (user): the "Loot you want" line sparkles once a run
			if api.animLootSparkle then api.animLootSparkle(b) end
			if api.dungeonLootSparkled then api.dungeonLootSparkled(d.sparkle) end
			d.sparkle = nil
		end
		if d.strike then
			if b.qtsStruck ~= d.strike and api.animStrike then b.qtsStruck = d.strike; api.animStrike(b) end
		elseif api.animStrikeClear then
			b.qtsStruck = nil
			api.animStrikeClear(b)
		end
	end
	for i = #list + 1, #lines do lines[i]:Hide() end
	return #list * lh
end

---------------------------------------------------------------------------------------------------------------------
-- Events and commands
---------------------------------------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local layoutQueued = false
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ENCOUNTER_END" then onEncounterEnd(...)
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then onEnter()
	elseif event == "GROUP_ROSTER_UPDATE" or event == "QUEST_LOG_UPDATE" then
		-- (performance) these come in bursts: one layout 0.2 s after the first, not one per event
		if not inside() or not api.applyLayout or (InCombatLockdown and InCombatLockdown()) then return end
		if not (C_Timer and C_Timer.After) then api.applyLayout() return end
		if layoutQueued then return end
		layoutQueued = true
		C_Timer.After(0.2, function()
			layoutQueued = false
			if api.applyLayout and not (InCombatLockdown and InCombatLockdown()) then api.applyLayout() end
		end)
	end
end)
ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	for _, e in ipairs({ "ENCOUNTER_END", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE" }) do
		pcall(events.RegisterEvent, events, e)
	end
	onEnter()
	-- the run's clock on the card, once a second (text only)
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(1, function()
			local b = lines[1]
			if b and b:IsShown() and b.data and b.data.text == runText then b.text:SetText(runText() or "") end
		end)
	end
end
if api.addSlash then
	api.addSlash("share", "share every quest you can with your party", function() api.shareAllQuests() end)
	api.addSlash("party", "which party member has which quest", function()
		local holders = api.partyQuestHolders and api.partyQuestHolders(function() return true end) or {}
		local n = 0
		for id, who in pairs(holders) do
			if #who > 1 or who[1] ~= "You" then
				n = n + 1
				if n <= 20 then say(questTitle(id) .. ": " .. table.concat(who, ", ")) end
			end
		end
		if n == 0 then say("no quest of your party members is known (they need this addon or Questie).") end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Settings: Helpers > Dungeons
---------------------------------------------------------------------------------------------------------------------
api.pageDeclarers = api.pageDeclarers or {}
api.pageDeclarers[#api.pageDeclarers + 1] = function(k)
	local function relayout() if api.applyLayout then api.applyLayout() end end
	local function sw(label, key, helpText)
		k.check(label, function() return db[key] ~= false end, function(v) db[key] = v and true or false; relayout() end,
			function() return db.dungeonCard ~= false end)
		k.help(helpText)
	end
	k.page("dungeonextras", "quests", "Dungeons")
	k.pageByKey.dungeonextras.cardTitle = "More on the dungeon card"
	k.note("These lines show on the dungeon card at the top of the tracker (Quest titles > Dungeon card at the top).")
	sw("Splits", "dungeonSplits", "the run time and each boss kill time, with your best; also a chat line on each kill")
	sw("Your party's quests here", "dungeonPartyQuests", "who has which quest for this dungeon (party members need this addon or Questie)")
	sw("Share button", "dungeonShare", "share your quests for this dungeon in one click (/ftp share: all quests)")
	sw("Next boss's abilities", "dungeonAbilities", "hover the line to see the next boss's abilities from the Encounter Journal")
	sw("Loot you want", "dungeonLoot", "items here that are your DungeonJournal favourites, or best in slot for your spec in SpecBisTooltip (needs DungeonJournal)")
	k.buttons("Forget best times", { { "Forget best times", function() db.splitLog = nil end, 160 } })
	k.pageByKey.dungeonextras.reset = k.reset
end
