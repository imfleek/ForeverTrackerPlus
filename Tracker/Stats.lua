-- 3.0 Statistics (Settings > Statistics: Overview, Run analysis, Level splits). The ideas come from QuestMaster's
-- statistics overview, Run Report and Level Splits; the code is our own.
--
-- What is recorded, per character, account-wide in ForeverTrackerPlusDB.statsRuns["Name-Realm"] (so any character can
-- be compared with any other; never part of a profile, Profiles.lua EXCLUDE_TRACKER):
--   levels[level] = { t = { [state] = seconds }, quests, questXP, xp, deaths, jumps }
--     once a second the character is in one of eleven states, the first that fits: dead, flight, combat, craft
--     (3.1.2: a profession window open, or casting a profession or gathering spell), npc (a quest, gossip, vendor,
--     trainer, flight, bank, mail, trade or auction window open), afk, swim (3.1.2), jump (3.1.2: in the air),
--     mount (moving mounted), walk (moving on foot), idle (standing). That second is added to the current level (a
--     tick is at most 5 s, so a loading screen or a stall is not counted as standing still).
--     3.1.2 Run analysis adds a jump tracker (the time in the air, and the jumps counted by a hook on
--     JumpOrAscendStart); standing stays, in the bars and in Time per level.
--   gold = { quests, loot } (3.1.2) copper: QUEST_TURNED_IN's money, and money that came in while a loot window of a
--     creature was open (or just closed)
--   reached[level] = /played seconds when that level began: TIME_PLAYED_MSG gives the total and the time on this
--     level, so the start of the current level is exact whenever the addon was installed. Asked at login and after
--     each level up; the game's own chat line for our request is kept out of the chat (the chat frames do not get
--     that one event while we wait for the answer, at most 5 s).
--   quests = { done, xp, abandoned, zones = { [zone] = n }, timeSum, timed, fastest = { t, title } }
--     a quest's time: from QUEST_ACCEPTED to QUEST_TURNED_IN (real time, only when both were seen, under 6 h)
--   played: the last /played total. A total smaller than the one recorded means the name was rolled again: the old
--     record moves to "Name-Realm (previous)", the run a player wants to race.
-- The level-up line in chat (db.levelAnnounce, on by default): the new level, how long the last level took and the
-- time played in total.
-- CONSTRAINT: every Forever call is checked before use (RequestTimePlayed, UnitOnTaxi, GetUnitSpeed, UnitIsAFK,
-- IsMounted: Forever declares them, wow-api forever.json); a value that is secret counts as unknown.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db, run, runKey

local KIND_NAMES = { combat = "Combat", walk = "Running", mount = "Mounted", flight = "Flight", npc = "NPCs", dead = "Dead",
	afk = "AFK", idle = "Standing", swim = "Swimming", jump = "Jumping", craft = "Crafting/gathering" }
-- Run analysis (bars and the Discord text): every state
local BAR_KINDS = { "combat", "walk", "mount", "swim", "jump", "craft", "flight", "npc", "dead", "afk", "idle" }
local MAX_TICK = 5
local MAX_QUEST_TIME = 6 * 3600
local session = { start = nil, quests = 0, xp = 0, jumps = 0, goldQuests = 0, goldLoot = 0 }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function on() return db and db.statsOn ~= false end
local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r " .. text) end

---------------------------------------------------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------------------------------------------------
-- 4:05, 1:02:03
local function clock(sec)
	sec = math.max(math.floor((tonumber(sec) or 0) + 0.5), 0)
	local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end
-- 2d 3h, 5h 12m, 14m
local function long(sec)
	sec = math.max(math.floor(tonumber(sec) or 0), 0)
	local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %dm"):format(h, m) end
	return ("%dm"):format(m)
end
-- 59.8k, 1.2m
local function short(n)
	n = tonumber(n) or 0
	if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
	if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(n)) end
	return tostring(math.floor(n))
end
-- copper as "12g 34s", "5s 6c", "7c" (gold, silver and copper coloured)
local function money(c)
	c = math.max(math.floor(tonumber(c) or 0), 0)
	local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	if g > 0 then return ("%s|cffffd100g|r %d|cffc7c7cfs|r"):format(short(g), s) end
	if s > 0 then return ("%d|cffc7c7cfs|r %d|cffeda55fc|r"):format(s, cp) end
	return ("%d|cffeda55fc|r"):format(cp)
end
api.statsClock, api.statsLong, api.statsShort, api.statsMoney = clock, long, short, money

-- the level cap (the lowest the game reports; 60 when it reports none)
local function maxLevel()
	local best
	for _, name in ipairs({ "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel" }) do
		local fn = _G[name]
		if type(fn) == "function" then
			local ok, v = pcall(fn)
			v = ok and not isSecret(v) and tonumber(v)
			if v and v > 0 and (not best or v < best) then best = v end
		end
	end
	return best or tonumber(rawget(_G, "MAX_PLAYER_LEVEL")) or 60
end
local function atMaxLevel() return (UnitLevel("player") or 1) >= maxLevel() end
api.statsAtMaxLevel = atMaxLevel

---------------------------------------------------------------------------------------------------------------------
-- The record
---------------------------------------------------------------------------------------------------------------------
local function charKey()
	local name = UnitName and UnitName("player")
	if type(name) ~= "string" or isSecret(name) or name == "" then return nil end
	local realm = GetRealmName and GetRealmName() or ""
	if isSecret(realm) then realm = "" end
	return name .. "-" .. tostring(realm or "")
end

local function fill(r)
	r.reached = type(r.reached) == "table" and r.reached or {}
	r.levels = type(r.levels) == "table" and r.levels or {}
	r.accepted = type(r.accepted) == "table" and r.accepted or {}
	local q = type(r.quests) == "table" and r.quests or {}
	q.done, q.xp, q.abandoned = tonumber(q.done) or 0, tonumber(q.xp) or 0, tonumber(q.abandoned) or 0
	q.zones = type(q.zones) == "table" and q.zones or {}
	q.timeSum, q.timed = tonumber(q.timeSum) or 0, tonumber(q.timed) or 0
	r.quests = q
	local g = type(r.gold) == "table" and r.gold or {}
	g.quests, g.loot = tonumber(g.quests) or 0, tonumber(g.loot) or 0
	r.gold = g
	r.jumps = tonumber(r.jumps) or 0
	return r
end

local function ensure()
	if run then return run end
	if not db then return nil end
	if type(db.statsRuns) ~= "table" then db.statsRuns = {} end
	runKey = charKey()
	if not runKey then return nil end
	local r = db.statsRuns[runKey]
	if type(r) ~= "table" then
		r = {}
		db.statsRuns[runKey] = r
	end
	local _, class = UnitClass("player")
	r.name, r.realm, r.class = UnitName("player"), GetRealmName and GetRealmName() or "", class
	run = fill(r)
	return run
end

local function levelRec(level)
	local r = ensure()
	if not r then return nil end
	level = level or UnitLevel("player") or 1
	local rec = r.levels[level]
	if type(rec) ~= "table" then
		rec = { t = {}, quests = 0, questXP = 0, xp = 0, deaths = 0 }
		r.levels[level] = rec
	end
	rec.t = type(rec.t) == "table" and rec.t or {}
	return rec
end

---------------------------------------------------------------------------------------------------------------------
-- The clock: one state a second
---------------------------------------------------------------------------------------------------------------------
local NPC_FRAMES = { "QuestFrame", "GossipFrame", "MerchantFrame", "ClassTrainerFrame", "TaxiFrame", "BankFrame",
	"MailFrame", "TradeFrame", "AuctionFrame", "AuctionHouseFrame" }
local function shown(name)
	local f = rawget(_G, name)
	return type(f) == "table" and f.IsShown and f:IsShown() and true or false
end
local function flag(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	return ok and not isSecret(v) and v and true or false
end
-- crafting and gathering: a profession window open, or a profession cast (the game's isTradeskill), or a gathering
-- spell (by ID, or by the name of one of those IDs in the game's language)
local CRAFT_FRAMES = { "TradeSkillFrame", "CraftFrame", "ProfessionsFrame" }
local GATHER_SPELLS = {
	[2366] = true, [2368] = true, [3570] = true, [11993] = true, [2369] = true, -- Herb Gathering
	[2575] = true, [2576] = true, [3564] = true, [10248] = true, [2580] = true, -- Mining
	[8613] = true, [8617] = true, [8618] = true, [10768] = true, -- Skinning
	[7620] = true, [7731] = true, [7732] = true, [18248] = true, [7738] = true, -- Fishing
	[13262] = true, -- Disenchant
}
local gatherNames
local function gatherName(name)
	if type(name) ~= "string" or isSecret(name) then return false end
	if not gatherNames then
		gatherNames = { ["Herb Gathering"] = true, ["Mining"] = true, ["Skinning"] = true, ["Fishing"] = true,
			["Disenchant"] = true }
		local get = C_Spell and C_Spell.GetSpellInfo
		if type(get) == "function" then
			for id in pairs(GATHER_SPELLS) do
				local ok, info = pcall(get, id)
				local n = ok and type(info) == "table" and info.name
				if type(n) == "string" and not isSecret(n) then gatherNames[n] = true end
			end
		end
	end
	return gatherNames[name] == true
end
local function readCast(fn, tradeAt, spellAt)
	local res = { fn("player") }
	local name, trade, spell = res[1], res[tradeAt], res[spellAt]
	if name == nil or isSecret(name) then return false end
	if not isSecret(trade) and trade == true then return true end
	if not isSecret(spell) and type(spell) == "number" and GATHER_SPELLS[spell] then return true end
	return gatherName(name)
end
-- (in pcall: a secret value that slips through only makes it "not crafting")
local function castIsCraft(fn, tradeAt, spellAt)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(readCast, fn, tradeAt, spellAt)
	return ok and v == true
end
local function craftingNow()
	for _, name in ipairs(CRAFT_FRAMES) do if shown(name) then return true end end
	-- UnitCastingInfo: name, displayName, texture, start, end, isTradeskill (6), castID, notInterruptible, spellID (9)
	-- UnitChannelInfo: name, displayName, texture, start, end, isTradeskill (6), notInterruptible, spellID (8)
	return castIsCraft(UnitCastingInfo, 6, 9) or castIsCraft(UnitChannelInfo, 6, 8)
end

local function stateNow()
	if flag(UnitIsDeadOrGhost, "player") then return "dead" end
	if flag(UnitOnTaxi, "player") then return "flight" end
	if flag(UnitAffectingCombat, "player") then return "combat" end
	if craftingNow() then return "craft" end
	for _, name in ipairs(NPC_FRAMES) do if shown(name) then return "npc" end end
	if flag(UnitIsAFK, "player") then return "afk" end
	if flag(IsSwimming) then return "swim" end
	if flag(IsFalling) then return "jump" end
	local speed = 0
	if type(GetUnitSpeed) == "function" then
		local ok, v = pcall(GetUnitSpeed, "player")
		if ok and type(v) == "number" and not isSecret(v) then speed = v end
	end
	if speed > 0 then return flag(IsMounted) and "mount" or "walk" end
	return "idle"
end
api.statsStateNow = stateNow

local lastTick
local function tick()
	local now = GetTime()
	local dt = lastTick and math.min(now - lastTick, MAX_TICK) or 0
	lastTick = now
	if not on() or dt <= 0 then return end
	local rec = levelRec()
	if not rec then return end
	local state = stateNow()
	rec.t[state] = (tonumber(rec.t[state]) or 0) + dt
end

---------------------------------------------------------------------------------------------------------------------
-- /played
---------------------------------------------------------------------------------------------------------------------
local muted, lastAsk, waiting = {}, -60, false
local announceLevel
local function unmute()
	for _, f in ipairs(muted) do pcall(f.RegisterEvent, f, "TIME_PLAYED_MSG") end
	wipe(muted)
	waiting = false
end
local function requestPlayed()
	if type(RequestTimePlayed) ~= "function" or not on() then return end
	if GetTime() - lastAsk < 10 then return end
	lastAsk = GetTime()
	-- our own question: its answer stays out of the chat (a /played typed meanwhile prints as usual once we have ours)
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local f = rawget(_G, "ChatFrame" .. i)
		if type(f) == "table" and f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG") then
			f:UnregisterEvent("TIME_PLAYED_MSG")
			muted[#muted + 1] = f
		end
	end
	waiting = true
	C_Timer.After(5, unmute)
	pcall(RequestTimePlayed)
end
api.statsRequestPlayed = requestPlayed

local function onPlayed(total, thisLevel)
	if waiting then C_Timer.After(0, unmute) end
	total, thisLevel = tonumber(total), tonumber(thisLevel)
	if not (total and thisLevel) or isSecret(total) or not on() then return end
	local r = ensure()
	if not r then return end
	-- a younger character under the same name: the old record becomes "(previous)"
	if tonumber(r.played) and total + 300 < r.played and runKey then
		db.statsRuns[runKey .. " (previous)"] = r
		run = nil
		db.statsRuns[runKey] = {}
		r = ensure()
	end
	r.played = total
	r.updated = time and time() or nil
	local level = UnitLevel("player") or 1
	r.reached[level] = total - thisLevel
	if announceLevel == level then
		announceLevel = nil
		if db.levelAnnounce ~= false then
			local prev = tonumber(r.reached[level - 1])
			local took = prev and (total - thisLevel - prev) or nil
			say(("|cffffd100Level %d!|r%s Played in total: %s."):format(level,
				took and took > 0 and (" Level %d took %s."):format(level - 1, clock(took)) or "", long(total)))
		end
	end
	if api.refreshConfig then api.refreshConfig() end
end

---------------------------------------------------------------------------------------------------------------------
-- Quests, experience, deaths
---------------------------------------------------------------------------------------------------------------------
local lastXP, lastMax, lastLevel
local function questTitle(id)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
		if ok and type(title) == "string" and not isSecret(title) then return title end
	end
	return nil
end

local function onAccepted(a, b)
	local id = tonumber(b) or tonumber(a)
	local r = ensure()
	if not (id and r) then return end
	r.accepted[id] = { at = time(), title = questTitle(id) }
end

local function onTurnedIn(id, xp, gold)
	if not on() then return end
	local r = ensure()
	if not r then return end
	if isSecret(xp) then xp = 0 end
	if isSecret(gold) then gold = 0 end
	id, xp, gold = tonumber(id), tonumber(xp) or 0, tonumber(gold) or 0
	if gold > 0 then
		r.gold.quests = r.gold.quests + gold
		session.goldQuests = session.goldQuests + gold
	end
	local q = r.quests
	q.done = q.done + 1
	q.xp = q.xp + xp
	local zone = GetRealZoneText and GetRealZoneText()
	if type(zone) == "string" and zone ~= "" and not isSecret(zone) then q.zones[zone] = (tonumber(q.zones[zone]) or 0) + 1 end
	local rec = levelRec()
	rec.quests = (tonumber(rec.quests) or 0) + 1
	rec.questXP = (tonumber(rec.questXP) or 0) + xp
	session.quests = session.quests + 1
	local acc = id and r.accepted[id]
	if type(acc) == "table" and tonumber(acc.at) then
		local t = time() - acc.at
		if t > 0 and t < MAX_QUEST_TIME then
			q.timeSum, q.timed = q.timeSum + t, q.timed + 1
			if not (type(q.fastest) == "table" and tonumber(q.fastest.t) and q.fastest.t <= t) then
				q.fastest = { t = t, title = acc.title or questTitle(id) }
			end
		end
	end
	if id then r.accepted[id] = nil end
end

local lastAbandon = 0
local function onAbandon()
	if not on() or GetTime() - lastAbandon < 0.5 then return end -- the global and C_QuestLog's may both run
	lastAbandon = GetTime()
	local r = ensure()
	if r then r.quests.abandoned = r.quests.abandoned + 1 end
end

-- gold off mobs: money that comes in while a creature's loot window is open (or up to a second after it closed)
local lootFromMob, lootUntil, lastMoney = false, -100, nil
local function readMoney()
	if type(GetMoney) ~= "function" then return nil end
	local ok, v = pcall(GetMoney)
	if not ok or isSecret(v) then return nil end
	return tonumber(v)
end
local function lootIsMob()
	if type(GetNumLootItems) ~= "function" or type(GetLootSourceInfo) ~= "function" then return true end
	local okN, n = pcall(GetNumLootItems)
	n = okN and not isSecret(n) and tonumber(n) or 0
	if n == 0 then return true end
	for i = 1, n do
		local ok, guid = pcall(GetLootSourceInfo, i)
		if ok and type(guid) == "string" and not isSecret(guid) and (guid:find("^Creature") or guid:find("^Vehicle")) then
			return true
		end
	end
	return false
end
local function onLootOpened() lootFromMob = lootIsMob(); lootUntil = math.huge end
local function onLootClosed() lootUntil = GetTime() + 1 end
local function onMoney()
	local now = readMoney()
	if not now then return end
	local before = lastMoney
	lastMoney = now
	if not (before and on() and lootFromMob and GetTime() <= lootUntil) then return end
	local gained = now - before
	local r = ensure()
	if gained > 0 and r then
		r.gold.loot = r.gold.loot + gained
		session.goldLoot = session.goldLoot + gained
	end
end
api.statsOnMoney = onMoney -- (tests)

-- jumps: a hook on the jump key's function (not while on a flight path)
local function onJump()
	if not on() or flag(UnitOnTaxi, "player") then return end
	local r = ensure()
	if not r then return end
	r.jumps = r.jumps + 1
	local rec = levelRec()
	if rec then rec.jumps = (tonumber(rec.jumps) or 0) + 1 end
	session.jumps = session.jumps + 1
end
api.statsOnJump = onJump -- (tests)

local function readXP()
	local xp, max = UnitXP and UnitXP("player"), UnitXPMax and UnitXPMax("player")
	if isSecret(xp) or isSecret(max) then return nil end
	return tonumber(xp), tonumber(max)
end
local function onXP()
	local xp, max = readXP()
	local level = UnitLevel("player")
	if not (xp and max and level) then return end
	if on() and lastXP then
		local gained
		if level == lastLevel then gained = xp - lastXP
		elseif level == (lastLevel or 0) + 1 then gained = (lastMax or 0) - lastXP + xp end
		if gained and gained > 0 then
			local rec = levelRec(lastLevel ~= level and lastLevel or level)
			if rec then rec.xp = (tonumber(rec.xp) or 0) + gained end
			session.xp = session.xp + gained
		end
	end
	lastXP, lastMax, lastLevel = xp, max, level
end

---------------------------------------------------------------------------------------------------------------------
-- What the pages read
---------------------------------------------------------------------------------------------------------------------
function api.statsRun(key)
	if key == nil then return ensure() end
	local r = db and type(db.statsRuns) == "table" and db.statsRuns[key]
	return type(r) == "table" and fill(r) or nil
end
function api.statsRunKey() ensure(); return runKey end
function api.statsSession() return session end
-- every other recorded run, for "Compare with": { { key, label }, ... }
function api.statsCompareOptions()
	local out = { { "none", "None" } }
	ensure()
	local keys = {}
	for k in pairs(db and type(db.statsRuns) == "table" and db.statsRuns or {}) do
		if k ~= runKey then keys[#keys + 1] = k end
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local r = db.statsRuns[k]
		local top = 0
		for l in pairs(type(r) == "table" and type(r.reached) == "table" and r.reached or {}) do top = math.max(top, tonumber(l) or 0) end
		out[#out + 1] = { k, top > 0 and ("%s (level %d)"):format(k, top) or k }
	end
	return out
end
local function compareRun()
	local key = db and db.statsCompare
	if not key or key == "none" or key == runKey then return nil end
	return api.statsRun(key)
end
api.statsCompareRun = compareRun

-- seconds a level took: from /played when both ends are known, else the recorded clock; now: still on it
function api.statsLevelTime(r, level)
	if not r then return nil end
	local a, b = tonumber(r.reached[level]), tonumber(r.reached[level + 1])
	if a and b and b > a then return b - a, false end
	if a and level == (UnitLevel("player") or 0) and r == run and tonumber(r.played) then
		return math.max(r.played - a, 0), true
	end
	local rec = r.levels[level]
	if type(rec) == "table" then
		local sum = 0
		for _, v in pairs(type(rec.t) == "table" and rec.t or {}) do sum = sum + (tonumber(v) or 0) end
		if sum > 0 then return sum, level == (UnitLevel("player") or 0) and r == run end
	end
	return nil
end

-- the whole run's clock: { [state] = seconds }, total
function api.statsTotals(r)
	local out, total = {}, 0
	local deaths, quests, questXP, xp, jumps = 0, 0, 0, 0, 0
	for _, rec in pairs(r and r.levels or {}) do
		if type(rec) == "table" then
			for k, v in pairs(type(rec.t) == "table" and rec.t or {}) do
				out[k] = (out[k] or 0) + (tonumber(v) or 0)
				total = total + (tonumber(v) or 0)
			end
			deaths = deaths + (tonumber(rec.deaths) or 0)
			quests = quests + (tonumber(rec.quests) or 0)
			questXP = questXP + (tonumber(rec.questXP) or 0)
			xp = xp + (tonumber(rec.xp) or 0)
			jumps = jumps + (tonumber(rec.jumps) or 0)
		end
	end
	return out, total, { deaths = deaths, quests = quests, questXP = questXP, xp = xp, jumps = jumps }
end

-- the largest three states of a level: "Standing 65%  NPCs 20%  Running 15%"
local function topStates(t, n)
	local list, total = {}, 0
	for k, v in pairs(t or {}) do
		v = tonumber(v) or 0
		if v > 0 and KIND_NAMES[k] then list[#list + 1] = { k, v }; total = total + v end
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local parts = {}
	for i = 1, math.min(n or 3, #list) do
		parts[#parts + 1] = ("%s %d%%"):format(KIND_NAMES[list[i][1]], math.floor(list[i][2] / total * 100 + 0.5))
	end
	return table.concat(parts, "  ")
end
api.statsTopStates = topStates

-- the run as text to paste in Discord
function api.statsDiscordText()
	local r = ensure()
	if not r then return "" end
	local t, total, sums = api.statsTotals(r)
	local _, class = UnitClass("player")
	local lines = {}
	lines[#lines + 1] = ("**%s** - level %d %s - ForeverTrackerPlus run analysis"):format(UnitName("player") or "?",
		UnitLevel("player") or 0, tostring(class or ""):lower():gsub("^%l", string.upper))
	lines[#lines + 1] = ("Recorded %s | %d quests | %d%% XP from quests | %d deaths | %d jumps"):format(clock(total), sums.quests,
		sums.xp > 0 and math.floor(sums.questXP / sums.xp * 100 + 0.5) or 0, sums.deaths, sums.jumps)
	lines[#lines + 1] = "```"
	for _, k in ipairs(BAR_KINDS) do
		local v = t[k] or 0
		if v > 0 then
			lines[#lines + 1] = ("%-18s %9s %3d%%"):format(KIND_NAMES[k], clock(v), total > 0 and math.floor(v / total * 100 + 0.5) or 0)
		end
	end
	lines[#lines + 1] = "```"
	local other = compareRun()
	lines[#lines + 1] = "```"
	local top = UnitLevel("player") or 1
	for level = top, 1, -1 do
		local took, now = api.statsLevelTime(r, level)
		if took then
			local cmp = ""
			local o = other and api.statsLevelTime(other, level)
			if o and not now then
				local d = took - o
				cmp = ("  %s%s"):format(d >= 0 and "+" or "-", clock(math.abs(d)))
			end
			local rec = r.levels[level]
			lines[#lines + 1] = ("Lv %-3d %9s%s%s  %s"):format(level, clock(took), now and " now" or "", cmp,
				type(rec) == "table" and topStates(rec.t, 3) or "")
		end
	end
	lines[#lines + 1] = "```"
	return table.concat(lines, "\n")
end

-- forget this character's record (Statistics > Options)
function api.statsReset()
	if not (db and runKey and type(db.statsRuns) == "table") then return end
	db.statsRuns[runKey] = {}
	run = nil
	ensure()
	lastAsk = -60
	requestPlayed()
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local EVENTS = { "TIME_PLAYED_MSG", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
	"PLAYER_DEAD", "PLAYER_MONEY", "LOOT_OPENED", "LOOT_CLOSED" }
events:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "TIME_PLAYED_MSG" then onPlayed(a, b)
	elseif event == "QUEST_ACCEPTED" then onAccepted(a, b)
	elseif event == "QUEST_TURNED_IN" then onTurnedIn(a, b, c)
	elseif event == "PLAYER_MONEY" then onMoney()
	elseif event == "LOOT_OPENED" then onLootOpened()
	elseif event == "LOOT_CLOSED" then onLootClosed()
	elseif event == "PLAYER_XP_UPDATE" then onXP()
	elseif event == "PLAYER_LEVEL_UP" then
		onXP()
		announceLevel = tonumber(a)
		lastAsk = -60
		C_Timer.After(1.5, requestPlayed)
	elseif event == "PLAYER_DEAD" then
		if on() then local rec = levelRec(); if rec then rec.deaths = (tonumber(rec.deaths) or 0) + 1 end end
	end
end)

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	session.start = GetTime()
	for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
	ensure()
	lastXP, lastMax = readXP()
	lastLevel = UnitLevel("player")
	lastMoney = readMoney()
	if hooksecurefunc then
		if type(JumpOrAscendStart) == "function" then pcall(hooksecurefunc, "JumpOrAscendStart", onJump) end
		if type(AbandonQuest) == "function" then pcall(hooksecurefunc, "AbandonQuest", onAbandon) end
		if C_QuestLog and type(C_QuestLog.AbandonQuest) == "function" then pcall(hooksecurefunc, C_QuestLog, "AbandonQuest", onAbandon) end
	end
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, tick) end
	C_Timer.After(6, requestPlayed)
end

---------------------------------------------------------------------------------------------------------------------
-- The pages' widgets: tiles, bars and lines, in the settings window's look (api.themeKit from Config.lua)
---------------------------------------------------------------------------------------------------------------------
local ICONS = {
	-- 3.1.2: experience from quests has a light icon (the coin is for the gold tiles now)
	check = "Interface\\RaidFrame\\ReadyCheck-Ready", star = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
	clock = "Interface\\Icons\\INV_Misc_PocketWatch_01", rate = "Interface\\Icons\\INV_Scroll_03",
	session = "Interface\\GossipFrame\\ActiveQuestIcon", trash = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	deaths = "Interface\\Icons\\Ability_Rogue_FeignDeath", xp = "Interface\\Icons\\Spell_Holy_PowerInfusion",
	gold = "Interface\\Icons\\INV_Misc_Coin_02", goldLoot = "Interface\\Icons\\INV_Misc_Coin_04",
	goldSession = "Interface\\Icons\\INV_Misc_Coin_01", jump = "Interface\\Icons\\Ability_Rogue_Sprint",
}

-- tiles(kit, rows): rows() -> { { icon, value, label }, ... }; up to four a line
local function tiles(rows, maxTiles)
	return function(holder, kit)
		local C = kit.C
		local list = {}
		for i = 1, maxTiles or 8 do
			local t = CreateFrame("Frame", nil, holder)
			kit.controlBg(t)
			t.icon = t:CreateTexture(nil, "ARTWORK")
			t.value = kit.text(t, "GameFontHighlightLarge", 1.35, C.pageTitle)
			t.value:SetJustifyH("LEFT")
			t.label = kit.text(t, "GameFontHighlightSmall", 1.05, C.label)
			t.label:SetJustifyH("LEFT")
			t.label:SetWordWrap(false)
			list[i] = t
		end
		local w = {}
		function w.draw(width)
			local k = kit.ts()
			local data = rows() or {}
			local cols = math.max(1, math.min(4, math.floor((width + 8) / (150 * k))))
			local tw = math.floor((width - (cols - 1) * 8) / cols)
			local th = math.floor(60 * k + 0.5)
			local count = math.min(#data, #list)
			for i, t in ipairs(list) do
				local d = data[i]
				if i <= count and d then
					local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (tw + 8), -row * (th + 8))
					t:SetSize(tw, th)
					local is = math.floor(18 * k + 0.5)
					t.icon:SetTexture(d[1])
					t.icon:SetSize(is, is)
					t.icon:ClearAllPoints()
					t.icon:SetPoint("TOPLEFT", 10, -10)
					t.value:SetText(d[2])
					t.value:ClearAllPoints()
					t.value:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
					t.value:SetPoint("RIGHT", t, "RIGHT", -6, 0)
					t.label:SetText(d[3])
					t.label:ClearAllPoints()
					t.label:SetPoint("BOTTOMLEFT", 10, 9)
					t.label:SetPoint("RIGHT", t, "RIGHT", -6, 0)
					t:Show()
				else
					t:Hide()
				end
			end
			local rowsN = math.max(math.ceil(count / cols), 1)
			return count == 0 and 1 or rowsN * th + (rowsN - 1) * 8
		end
		return w
	end
end

-- bars(rows): rows() -> { { label, valueText, fraction }, ... }
local function bars(rows, maxRows)
	return function(holder, kit)
		local C = kit.C
		local list = {}
		for i = 1, maxRows or 10 do
			local r = {}
			r.label = kit.text(holder, "GameFontHighlight", 1.1, C.value)
			r.label:SetJustifyH("LEFT")
			r.value = kit.text(holder, "GameFontHighlight", 1.05, C.label)
			r.value:SetJustifyH("RIGHT")
			r.track = kit.solid(holder, "BORDER", C.track)
			r.fill = holder:CreateTexture(nil, "ARTWORK")
			kit.hGradient(r.fill, C.on, 1, 0.75)
			list[i] = r
		end
		local w = {}
		function w.draw(width)
			local k = kit.ts()
			local data = rows() or {}
			local y = 0
			local rowH = math.floor(18 * k + 0.5)
			for i, r in ipairs(list) do
				local d = data[i]
				local show = d ~= nil
				r.label:SetShown(show); r.value:SetShown(show); r.track:SetShown(show); r.fill:SetShown(show)
				if show then
					r.label:SetText(d[1])
					r.value:SetText(d[2] or "")
					r.label:ClearAllPoints()
					r.label:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r.label:SetPoint("RIGHT", holder, "TOPRIGHT", -150, 0)
					r.value:ClearAllPoints()
					r.value:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
					r.value:SetWidth(150)
					y = y + rowH + 2
					r.track:ClearAllPoints()
					r.track:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r.track:SetSize(width, 5)
					local frac = math.min(math.max(tonumber(d[3]) or 0, 0), 1)
					r.fill:ClearAllPoints()
					r.fill:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r.fill:SetSize(math.max(width * frac, 1), 5)
					r.fill:SetShown(frac > 0)
					y = y + 5 + math.floor(9 * k + 0.5)
				end
			end
			return math.max(y, 1)
		end
		return w
	end
end

-- lines(rows): rows() -> { { left, middle, right, rightColour }, ... }; empty: one grey line (emptyText)
local function lines(rows, emptyText, maxRows)
	return function(holder, kit)
		local C = kit.C
		local list = {}
		local function line(i)
			if list[i] then return list[i] end
			local r = {}
			r.left = kit.text(holder, "GameFontHighlight", 1.08, C.value)
			r.left:SetJustifyH("LEFT")
			r.mid = kit.text(holder, "GameFontHighlight", 1.08, C.label)
			r.mid:SetJustifyH("LEFT")
			r.right = kit.text(holder, "GameFontHighlight", 1.02, C.label)
			r.right:SetJustifyH("RIGHT")
			r.right:SetWordWrap(false)
			list[i] = r
			return r
		end
		for i = 1, math.min(maxRows or 20, 20) do line(i) end
		local w = {}
		function w.draw(width)
			local k = kit.ts()
			local data = rows() or {}
			if #data == 0 and emptyText then data = { { emptyText, "", "" } } end
			local made = #list
			for i = 1, math.min(#data, maxRows or 80) do line(i) end
			if #list > made then kit.refreshFonts() end
			local rowH = math.floor(20 * k + 0.5)
			local leftW, midW = math.floor(70 * k), math.floor(110 * k)
			for i, r in ipairs(list) do
				local d = data[i]
				local show = d ~= nil
				r.left:SetShown(show); r.mid:SetShown(show); r.right:SetShown(show)
				if show then
					local y = (i - 1) * rowH
					r.left:SetText(d[1] or "")
					r.left:ClearAllPoints()
					r.left:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r.left:SetWidth(#data == 1 and d[2] == "" and width or leftW)
					r.mid:SetText(d[2] or "")
					r.mid:ClearAllPoints()
					r.mid:SetPoint("TOPLEFT", holder, "TOPLEFT", leftW, -y)
					r.mid:SetWidth(midW)
					r.right:SetText(d[3] or "")
					r.right:ClearAllPoints()
					r.right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
					r.right:SetWidth(math.max(width - leftW - midW, 40))
					local c = d[4] or C.label
					r.right:SetTextColor(c[1], c[2], c[3])
				end
			end
			return math.max(math.min(#data, #list) * rowH, 1)
		end
		return w
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The pages (declared by Config.lua: api.declareStatsPages(kit))
---------------------------------------------------------------------------------------------------------------------
local GREEN, RED = { 0.35, 0.85, 0.45 }, { 1, 0.42, 0.32 }

local function overviewTiles()
	local r = ensure()
	if not r then return {} end
	local q = r.quests
	local _, total = api.statsTotals(r)
	local avg = q.timed > 0 and clock(q.timeSum / q.timed) or "-"
	local rate = total >= 600 and ("%.1f"):format(q.done / (total / 3600)) or "-"
	-- 3.1.2: no "Fastest quest"; at the level cap no experience tiles
	local maxed = atMaxLevel()
	local out = { { ICONS.check, short(q.done), "Completed quests" } }
	if not maxed then out[#out + 1] = { ICONS.star, short(q.xp), "Experience from quests" } end
	out[#out + 1] = { ICONS.clock, avg, "Avg. quest time" }
	out[#out + 1] = { ICONS.rate, rate, "Quests per hour" }
	out[#out + 1] = { ICONS.session, tostring(session.quests), "Session quests" }
	out[#out + 1] = { ICONS.trash, tostring(q.abandoned), "Abandoned" }
	if not maxed then out[#out + 1] = { ICONS.xp, short(session.xp), "Session experience" } end
	return out
end

-- 3.1.2 gold: from quests and off mobs, this run and this session
local function goldTiles()
	local r = ensure()
	if not r then return {} end
	return {
		{ ICONS.gold, money(r.gold.quests), "Gold from quests" },
		{ ICONS.goldLoot, money(r.gold.loot), "Gold off mobs" },
		{ ICONS.goldSession, money(session.goldQuests + session.goldLoot), "Gold this session" },
		{ ICONS.gold, money(r.gold.quests + r.gold.loot), "Gold in total" },
	}
end

local function levelBar()
	local xp, max = readXP()
	local level = UnitLevel("player") or 1
	-- 3.1.2: at the level cap there is no next level: a full bar, no experience numbers
	if atMaxLevel() then return { { ("Level %d"):format(level), "maximum level", 1 } } end
	if not (xp and max and max > 0) then return { { ("Level %d"):format(level), "", 0 } } end
	local fmt = BreakUpLargeNumbers or tostring
	return { { ("Level %d"):format(level), ("%s / %s"):format(fmt(xp), fmt(max)), xp / max } }
end

local function zoneBars()
	local r = ensure()
	if not r then return {} end
	local list = {}
	for zone, n in pairs(r.quests.zones) do list[#list + 1] = { zone, tonumber(n) or 0 } end
	table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	local top = list[1] and list[1][2] or 1
	local out = {}
	for i = 1, math.min(6, #list) do out[i] = { list[i][1], tostring(list[i][2]), list[i][2] / top } end
	return out
end

local function runTiles()
	local r = ensure()
	if not r then return {} end
	local _, total, sums = api.statsTotals(r)
	return {
		{ ICONS.clock, clock(total), "Recorded" },
		{ ICONS.check, tostring(sums.quests), "Completed quests" },
		{ ICONS.star, sums.xp > 0 and ("%d%%"):format(math.floor(sums.questXP / sums.xp * 100 + 0.5)) or "-", "XP from quests" },
		{ ICONS.deaths, tostring(sums.deaths), "Deaths" },
		{ ICONS.jump, short(sums.jumps), "Jumps" },
	}
end

local function timeBars()
	local r = ensure()
	if not r then return {} end
	local t, total = api.statsTotals(r)
	local out = {}
	for _, k in ipairs(BAR_KINDS) do
		local v = t[k] or 0
		out[#out + 1] = { KIND_NAMES[k], ("%s  %d%%"):format(clock(v), total > 0 and math.floor(v / total * 100 + 0.5) or 0),
			total > 0 and v / total or 0 }
	end
	return out
end

local function worthALook()
	local r = ensure()
	if not r then return {} end
	local t, total = api.statsTotals(r)
	local out = {}
	if total < 300 then return out end
	local away = (t.idle or 0) + (t.afk or 0)
	if away / total >= 0.2 then
		out[#out + 1] = { "Idle or away", clock(away), ("%d%% of the run: standing still or AFK"):format(math.floor(away / total * 100 + 0.5)), RED }
	end
	if (t.dead or 0) / total >= 0.04 then
		out[#out + 1] = { "Dead", clock(t.dead), "time spent dead or running back", RED }
	end
	if (t.npc or 0) / total >= 0.12 then
		out[#out + 1] = { "NPCs", clock(t.npc), "long in vendor and quest windows: RestedXP's automation can help", RED }
	end
	-- the slowest finished level, against its neighbours
	local slowest, slowT
	for level in pairs(r.levels) do
		local took, now = api.statsLevelTime(r, level)
		if took and not now and (not slowT or took > slowT) then slowest, slowT = level, took end
	end
	if slowest then out[#out + 1] = { ("Lv %d"):format(slowest), clock(slowT), "your slowest level so far" } end
	return out
end

local function levelLines()
	local r = ensure()
	if not r then return {} end
	local out = {}
	local top = 0
	for l in pairs(r.levels) do top = math.max(top, tonumber(l) or 0) end
	for l in pairs(r.reached) do top = math.max(top, tonumber(l) or 0) end
	for level = top, 1, -1 do
		local took, now = api.statsLevelTime(r, level)
		if took then
			local rec = r.levels[level]
			out[#out + 1] = { ("Lv %d"):format(level), clock(took) .. (now and "  now" or ""),
				type(rec) == "table" and topStates(rec.t, 3) or "" }
		end
	end
	return out
end

local function splitLines()
	local r = ensure()
	if not r then return {} end
	local other = compareRun()
	local out = {}
	local top = UnitLevel("player") or 1
	local sum, otherSum = 0, 0
	for level = 1, top do
		local took, now = api.statsLevelTime(r, level)
		local o = other and api.statsLevelTime(other, level)
		if took or o then
			local right, colour = "", nil
			if o then
				if took and not now then
					local d = took - o
					sum, otherSum = sum + took, otherSum + o
					right = ("%s  (%s%s)"):format(clock(o), d >= 0 and "+" or "-", clock(math.abs(d)))
					colour = d > 0 and RED or GREEN
				else
					right = clock(o)
				end
			end
			table.insert(out, 1, { ("Lv %d"):format(level), took and (clock(took) .. (now and "  now" or "")) or "-", right, colour })
		end
	end
	if other and otherSum > 0 then
		local d = sum - otherSum
		table.insert(out, 1, { "Total", clock(sum), ("%s  (%s%s)"):format(clock(otherSum), d >= 0 and "+" or "-", clock(math.abs(d))),
			d > 0 and RED or GREEN })
	end
	return out
end

api.statsOverviewTiles, api.statsGoldTiles, api.statsLevelBar, api.statsRunTiles, api.statsTimeBars, api.statsLevelLines =
	overviewTiles, goldTiles, levelBar, runTiles, timeBars, levelLines -- (tests)
function api.declareStatsPages(k)
	local function refreshAfter(fn) return function(...) fn(...); k.refresh() end end
	local function compareChoice()
		k.choice("Compare with", function() return api.statsCompareOptions() end,
			function() return db and db.statsCompare or "none" end,
			refreshAfter(function(v) db.statsCompare = v end))
		k.help("another character of this account, or this one's previous run under the same name")
	end

	k.page("statsoverview", "stats", "Overview")
	k.pageByKey.statsoverview.cardTitle = "Your quests in numbers"
	k.custom("Completed quests experience quest time quests per hour session abandoned", tiles(overviewTiles, 8), true)
	k.heading("Gold")
	k.custom("Gold from quests off mobs money session", tiles(goldTiles, 4), true)
	k.heading("Level progress")
	k.custom("Level progress", bars(levelBar, 1), true)
	k.heading("Top quest zones")
	k.custom("Top quest zones", lines(function()
		local list = zoneBars()
		local out = {}
		for i, d in ipairs(list) do out[i] = { tostring(i) .. ".", d[1], d[2] } end
		return out
	end, "Hand in a quest and its zone shows here.", 6), true)

	k.page("statsoptions", "stats", "Options")
	k.check("Record statistics", function() return db.statsOn ~= false end,
		function(v) db.statsOn = v and true or false end)
	k.help("quests, experience, deaths and where the time goes, for each character")
	k.check("Level-up line in chat", function() return db.levelAnnounce ~= false end,
		function(v) db.levelAnnounce = v and true or false end)
	k.help("on a new level: how long the last level took and your time played (only you see it)")
	k.heading("Reset")
	if StaticPopupDialogs then
		StaticPopupDialogs.RXPFT_RESET_STATS = {
			text = "Forget every statistic of this character? This cannot be undone.",
			button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = 1, hideOnEscape = 1,
			OnAccept = function() api.statsReset(); k.refresh() end,
		}
	end
	k.buttons("Reset this character's statistics", {
		{ "Reset this character's statistics", function() if StaticPopup_Show then StaticPopup_Show("RXPFT_RESET_STATS") end end, 250 },
	})
	k.pageByKey.statsoptions.reset = k.reset

	k.page("statsrun", "stats", "Run analysis")
	k.pageByKey.statsrun.cardTitle = "What the run's time was spent on"
	k.custom("Recorded completed quests xp from quests deaths jumps", tiles(runTiles, 5), true)
	k.heading("Where the time went")
	k.custom("Combat running mounted swimming jumping crafting gathering flight npcs dead afk standing", bars(timeBars, #BAR_KINDS), true)
	k.heading("Worth a look")
	k.custom("Worth a look idle away", lines(worthALook, "Nothing stands out yet.", 6), true)
	k.heading("Time per level")
	k.custom("Time per level", lines(levelLines, "Play a little: each level's time shows here.", 80), true)
	k.heading("Share")
	local discord = ""
	k.buttons("Copy for Discord", {
		{ "Copy for Discord", function() discord = api.statsDiscordText() end, 160 },
	})
	k.input("Press the button, then Ctrl+C to copy", function() return discord end, function() end, 6)
	k.declared[#k.declared].selectAll = true

	k.page("statssplits", "stats", "Level splits")
	k.pageByKey.statssplits.cardTitle = "How long each level took"
	compareChoice()
	k.note("Times come from /played, so time logged out never counts. The middle column is this run; the right one the run you compare with (red: slower, green: faster).")
	k.custom("Level splits", lines(splitLines, "Level up once and the first split shows here.", 80), true)
end
