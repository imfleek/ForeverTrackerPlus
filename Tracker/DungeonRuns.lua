-- ForeverTrackerPlus: run summary and run history (3.2, user ideas 14 and 16).
-- DungeonPlus.lua keeps the run ({ key, name, start, left, kills }); this file adds to it what the run gave you: gold
-- (GetMoney at the start), experience (PLAYER_XP_UPDATE, also over a level-up), deaths (Dungeon.lua's count, read
-- once a second while inside) and the number of bosses (the Encounter Journal list).
-- When you leave: the run goes into db.dungeonRuns (account wide, the last 200), and a card shows what you did, with a
-- "Copy for Discord" line. A run you go back into within 30 minutes is the same run: its record is updated.
-- Statistics > Dungeon runs: each dungeon's best time, runs and average, then your last runs.
-- Options: Dungeons > "Run summary when you leave" (db.runSummary), "Keep a run history" (db.runHistory).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local MAX = 200
local function clock(sec)
	sec = math.floor((tonumber(sec) or 0) + 0.5)
	if sec >= 3600 then return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60) end
	return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end
local function gold(copper)
	copper = math.floor(tonumber(copper) or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
	if g > 0 then return ("%s%dg %ds"):format(sign, g, s) end
	return ("%s%ds %dc"):format(sign, s, copper % 100)
end
api.runClock, api.runGold = clock, gold -- (tests)

local function history()
	local db = ns.db
	if not db then return {} end
	db.dungeonRuns = type(db.dungeonRuns) == "table" and db.dungeonRuns or {}
	return db.dungeonRuns
end
local function me()
	local name = UnitName and UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or ""
	return tostring(name) .. (realm ~= "" and ("-" .. realm) or "")
end

-- the run as one record
local function record(run)
	local last = run.kills[#run.kills]
	return {
		char = me(), name = run.name, at = run.epoch or (time and time()) or 0,
		dur = math.floor(((run.left or GetTime()) - run.start) + 0.5),
		lastKill = last and math.floor(last[2] + 0.5) or nil,
		kills = #run.kills, bosses = run.bosses or 0, deaths = run.deaths or 0,
		money = (GetMoney and run.money) and (GetMoney() - run.money) or 0, xp = run.xp or 0,
		cleared = run.cleared and true or nil,
	}
end

-- the Discord line: one line, so it fits the copy box
local function discordText(r)
	local parts = { ("%s %s"):format(r.name, r.cleared and "cleared" or "run"), clock(r.cleared and r.lastKill or r.dur) }
	parts[#parts + 1] = ("%d/%d bosses"):format(r.kills, math.max(r.bosses, r.kills))
	parts[#parts + 1] = ("%d death%s"):format(r.deaths, r.deaths == 1 and "" or "s")
	if r.money ~= 0 then parts[#parts + 1] = gold(r.money) end
	if r.xp > 0 then parts[#parts + 1] = ("%s xp"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(r.xp) or tostring(r.xp)) end
	if r.newBest then parts[#parts + 1] = "new best!" end
	return table.concat(parts, " | ") .. " (ForeverTrackerPlus)"
end
api.runDiscordText = discordText

-- the summary card -----------------------------------------------------------------------------------------------
local card
local function build()
	local kit = api.themeKit
	if not kit then return nil end
	local C = kit.C
	local f = CreateFrame("Frame", "ForeverTrackerPlusRunSummary", UIParent)
	f:SetSize(340, 236)
	f:SetPoint("TOP", 0, -140)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "ForeverTrackerPlusRunSummary") end
	kit.solid(f, "BACKGROUND", C.window, 0.98):SetAllPoints()
	kit.border(f, C.edge, 2, "BORDER")
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", 2, -2)
	bar:SetPoint("TOPRIGHT", -2, -2)
	bar:SetHeight(30)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	kit.gradient(barBg, C.titleTop, C.titleBottom)
	f.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("CENTER")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -3, -3)
	f.rows = {}
	for i = 1, 6 do
		local l = kit.text(f, "GameFontHighlight", 1.05, C.label)
		l:SetPoint("TOPLEFT", 22, -42 - (i - 1) * 22)
		l:SetJustifyH("LEFT")
		local v = kit.text(f, "GameFontHighlight", 1.05, C.value)
		v:SetPoint("TOPRIGHT", -22, -42 - (i - 1) * 22)
		v:SetJustifyH("RIGHT")
		f.rows[i] = { l, v }
	end
	f.copy = kit.makeButton(f, "Copy for Discord", 150, function()
		if f.record and api.showCopyURL then api.showCopyURL(discordText(f.record), "Copy for Discord (Ctrl+C)") end
	end)
	f.copy:SetPoint("BOTTOMLEFT", 20, 14)
	f.ok = kit.makeButton(f, "Close", 110, function() f:Hide() end)
	f.ok:SetPoint("BOTTOMRIGHT", -20, 14)
	close:SetScript("OnClick", function() f:Hide() end)
	f:Hide()
	card = f
	return f
end

local function showSummary(r)
	if not card and not build() then return end
	card.record = r
	card.title:SetText(("%s  %s"):format(r.name, r.cleared and "|cff44ff44cleared|r" or "run"))
	local rows = {
		{ "Time", clock(r.dur) .. (r.cleared and r.lastKill and ("  (last boss %s)"):format(clock(r.lastKill)) or "") },
		{ "Bosses", ("%d of %d"):format(r.kills, math.max(r.bosses, r.kills)) },
		{ "Deaths", tostring(r.deaths) },
		{ "Gold", gold(r.money) },
		{ "Experience", BreakUpLargeNumbers and BreakUpLargeNumbers(r.xp) or tostring(r.xp) },
		{ r.newBest and "|cffffd100New best time|r" or "Best time", r.best and clock(r.best) or "-" },
	}
	for i, row in ipairs(card.rows) do
		row[1]:SetText(rows[i][1]); row[2]:SetText(rows[i][2])
	end
	-- 3.2 (user): gold and experience count up from the numbers the card showed last time (Animations.lua)
	local db = ns.db
	local last = db and type(db.runSummaryLast) == "table" and db.runSummaryLast or {}
	if api.animCountFrom then
		api.animCountFrom(card.rows[4][2], last.money or 0, r.money, gold)
		api.animCountFrom(card.rows[5][2], last.xp or 0, r.xp, function(v)
			return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v)
		end)
	end
	if db then db.runSummaryLast = { money = r.money, xp = r.xp } end
	card:Show()
	if api.animWindowOpen then pcall(api.animWindowOpen, card) end
end
api.showRunSummary = showSummary -- (tests, /ftp runcard)

-- best time of a dungeon: the cleared runs' time to the last boss
local function bestOf(name, except)
	local best
	for _, r in ipairs(history()) do
		if r ~= except and r.name == name and r.cleared and r.lastKill and (not best or r.lastKill < best) then best = r.lastKill end
	end
	return best
end

-- DungeonPlus.lua calls these -------------------------------------------------------------------------------------
function api.dungeonRunStarted(run)
	run.money = GetMoney and GetMoney() or 0
	run.xp, run.deaths, run.bosses = 0, 0, 0
	run.epoch = time and time() or 0
	run.lastXP = UnitXP and UnitXP("player") or 0
	run.lastXPMax = UnitXPMax and UnitXPMax("player") or 0
end
function api.dungeonRunLeft(run)
	local db = ns.db
	if not db or not run or #run.kills == 0 then return end
	local r = record(run)
	if db.runHistory ~= false then
		local list = history()
		if run.histRecord and list[run.histIndex] == run.histRecord then
			list[run.histIndex] = r
		else
			list[#list + 1] = r
			while #list > MAX do table.remove(list, 1) end
		end
		run.histIndex, run.histRecord = #list, r
		for i, x in ipairs(list) do if x == r then run.histIndex = i end end
	end
	local before = bestOf(r.name, r)
	r.best = r.cleared and r.lastKill and (before and math.min(before, r.lastKill) or r.lastKill) or before
	r.newBest = r.cleared and r.lastKill and before and r.lastKill < before or nil
	if db.runSummary ~= false and C_Timer and C_Timer.After then
		C_Timer.After(2, function()
			if InCombatLockdown and InCombatLockdown() then return end
			showSummary(r)
		end)
	end
end

-- while inside: experience, deaths, bosses
local function current() return api.dungeonRunForTests and api.dungeonRunForTests() end
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "PLAYER_XP_UPDATE")
events:SetScript("OnEvent", function()
	local run = current()
	if not run or run.left or not run.lastXP then return end
	local xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
	local gain = xp - run.lastXP
	if gain < 0 then gain = (run.lastXPMax - run.lastXP) + xp end -- a level-up
	if gain > 0 then run.xp = (run.xp or 0) + gain end
	run.lastXP, run.lastXPMax = xp, max
end)
api.dungeonRunsXPEvent = events:GetScript("OnEvent") -- (tests)
ns.onLogin[#ns.onLogin + 1] = function()
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(1, function()
			local run = current()
			if not run or run.left or not run.lastXP then return end
			if api.dungeonDeaths then
				local n = tonumber(api.dungeonDeaths()) or 0
				if n > (run.deaths or 0) then run.deaths = n end
			end
			local list = api.dungeonEncounters and api.dungeonEncounters() or {}
			if #list > (run.bosses or 0) then run.bosses = #list end
		end)
	end
	if api.addSlash then
		api.addSlash("runcard", "show the summary of your last dungeon run", function()
			local list = history()
			local r = list[#list]
			if r then showSummary(r) else DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r no dungeon run yet.") end
		end)
	end
end

-- Statistics > Dungeon runs -----------------------------------------------------------------------------------------
local function perDungeon()
	local by, order = {}, {}
	for _, r in ipairs(history()) do
		local d = by[r.name]
		if not d then d = { name = r.name, n = 0, sum = 0 }; by[r.name] = d; order[#order + 1] = d end
		d.n = d.n + 1
		d.sum = d.sum + (r.dur or 0)
		if r.cleared and r.lastKill and (not d.best or r.lastKill < d.best) then d.best = r.lastKill end
	end
	table.sort(order, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
	local rows = {}
	for _, d in ipairs(order) do
		rows[#rows + 1] = { d.best and clock(d.best) or "-", d.name,
			("%d run%s, average %s"):format(d.n, d.n == 1 and "" or "s", clock(d.sum / d.n)) }
	end
	return rows
end
local function lastRuns()
	local rows, list = {}, history()
	for i = #list, math.max(1, #list - 29), -1 do
		local r = list[i]
		local when = date and date("%d %b", r.at or 0) or ""
		rows[#rows + 1] = { clock(r.dur), r.name, ("%s  %d/%d  %s%s"):format(when, r.kills, math.max(r.bosses or 0, r.kills),
			(tostring(r.char):match("^([^-]+)") or "?"), r.cleared and "  |cff44ff44cleared|r" or "") }
	end
	return rows
end
api.dungeonRunRows, api.dungeonLastRunRows = perDungeon, lastRuns -- (tests)

api.pageDeclarers = api.pageDeclarers or {}
api.pageDeclarers[#api.pageDeclarers + 1] = function(k)
	local db = ns.db
	if not api.statsLines then return end
	k.page("statsdungeons", "stats", "Dungeon runs")
	k.pageByKey.statsdungeons.cardTitle = "Your dungeon runs"
	k.custom("Each dungeon best time runs average", api.statsLines(perDungeon, "Finish a dungeon run: it shows here.", 40), true)
	k.heading("Last runs")
	k.custom("Last runs date bosses cleared", api.statsLines(lastRuns, "No run yet.", 30), true)
	k.heading("Options")
	k.check("Run summary when you leave", function() return db.runSummary ~= false end,
		function(v) db.runSummary = v and true or false end)
	k.help("a card with your time, bosses, deaths, gold and experience, and a Copy for Discord line (/ftp runcard: the last one)")
	k.check("Keep a run history", function() return db.runHistory ~= false end, function(v) db.runHistory = v and true or false end)
	k.help("the last 200 runs of all your characters, for this page")
	k.buttons("Forget run history", { { "Forget run history", function() db.dungeonRuns = nil; k.refresh() end, 160 } })
end
