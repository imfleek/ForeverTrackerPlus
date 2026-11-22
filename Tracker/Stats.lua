-- 3.0 Statistics (Settings > Statistics: Overview, Run analysis, Level splits). The ideas come from QuestMaster's
-- statistics overview, Run Report and Level Splits; the code is our own.
--
-- What is recorded, per character, account-wide in ForeverTrackerPlusDB.statsRuns["Name-Realm"] (so any character can
-- be compared with any other; never part of a profile, Profiles.lua EXCLUDE_TRACKER):
--   levels[level] = { t = { [state] = seconds }, npc = { [window] = seconds }, dungeon, quests, questXP, xp, deaths, jumps }
--     once a second the character is in one state, the first that fits: dead, flight, combat, eat (3.1.2: a Food or
--     Drink buff), craft (3.1.2: a profession window open, or casting a profession or gathering spell), loot (3.1.2:
--     a loot window open), npc (a quest, gossip, vendor, trainer, flight, bank, mail, trade or auction window open;
--     3.1.2: also counted by window in npc, NPC_KINDS), cast (3.1.2: any other cast or channel), afk, swim (3.1.2),
--     jump (3.1.2: in the air up to 2 s after a jump), fall (3.1.2: in the air otherwise), mount (moving mounted),
--     walk (moving on foot), map (3.1.2: standing with the world map or quest log open), idle (standing). That second
--     is added to the current level (a tick is at most 5 s, so a stall is not counted as standing still).
--     3.1.2 load: a loading screen's whole time (LOADING_SCREEN_ENABLED to _DISABLED, at most 5 min); no ticks count
--     meanwhile. dungeon: the seconds inside a dungeon or raid (IsInInstance), on top of the state (a tile, not a bar).
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
-- IsMounted, IsFalling, IsInInstance, C_UnitAuras.GetBuffDataByIndex, LOADING_SCREEN_ENABLED/DISABLED: Forever
-- declares them, wow-api forever.json); a value that is secret counts as unknown.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db, run, runKey

local KIND_NAMES = { combat = "Combat", walk = "Running", mount = "Mounted", flight = "Flight", npc = "NPCs", dead = "Dead",
	afk = "AFK", idle = "Standing", swim = "Swimming", jump = "Jumping", craft = "Crafting/gathering",
	eat = "Eating/drinking", loot = "Looting", cast = "Casting", fall = "Falling", map = "Map/quest log",
	load = "Loading screens" }
-- Run analysis (bars and the Discord text): every state
local BAR_KINDS = { "combat", "walk", "mount", "swim", "jump", "fall", "craft", "eat", "loot", "cast", "flight", "npc",
	"map", "load", "dead", "afk", "idle" }
-- 3.1.2: the NPC time split by window (the Run analysis dropdown under NPCs); the first window that is open counts
local NPC_KINDS = {
	{ "vendor", "Vendors", { "MerchantFrame" } },
	{ "trainer", "Trainers", { "ClassTrainerFrame" } },
	{ "taxi", "Flight masters", { "TaxiFrame" } },
	{ "bank", "Bank", { "BankFrame" } },
	{ "mail", "Mailbox", { "MailFrame" } },
	{ "auction", "Auction house", { "AuctionFrame", "AuctionHouseFrame" } },
	{ "trade", "Trading", { "TradeFrame" } },
	{ "quest", "Quest givers/talking", { "QuestFrame", "GossipFrame" } },
}
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

-- 3.1.2 eating and drinking: a buff named Food, Drink, Food & Drink or Refreshment (or the game's name of spell 433
-- Food / 430 Drink in its language)
local foodNames
local function isFoodName(name)
	if type(name) ~= "string" or isSecret(name) then return false end
	if not foodNames then
		foodNames = { ["Food"] = true, ["Drink"] = true, ["Food & Drink"] = true, ["Refreshment"] = true }
		local get = C_Spell and C_Spell.GetSpellInfo
		if type(get) == "function" then
			for _, id in ipairs({ 433, 430 }) do
				local ok, info = pcall(get, id)
				local n = ok and type(info) == "table" and info.name
				if type(n) == "string" and not isSecret(n) then foodNames[n] = true end
			end
		end
	end
	return foodNames[name] == true
end
local function readFood()
	local byData = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
	local old = rawget(_G, "UnitBuff")
	for i = 1, 40 do
		local name
		if type(byData) == "function" then
			local d = byData("player", i)
			if type(d) ~= "table" then return false end
			name = d.name
		elseif type(old) == "function" then
			name = old("player", i)
			if name == nil then return false end
		else
			return false
		end
		if isFoodName(name) then return true end
	end
	return false
end
-- (in pcall: a secret value only makes it "not eating")
local function eatingNow()
	local ok, v = pcall(readFood)
	return ok and v == true
end

-- 3.1.2 casting: any other cast or channel out of combat (a hearthstone, a buff, a mount)
local function castName(fn)
	if type(fn) ~= "function" then return false end
	local ok, name = pcall(fn, "player")
	return ok and name ~= nil and not isSecret(name) and true or false
end

-- 3.1.2 a loot window is open (LOOT_OPENED to LOOT_CLOSED); a loading screen is on (LOADING_SCREEN_ENABLED/DISABLED)
local lootOpen, loadStart = false, nil
-- 3.1.2 jumping or falling: in the air up to 2 s after a jump (the JumpOrAscendStart hook) is a jump, else a fall
local JUMP_AIR = 2
local lastJumpAt, jumpHooked = -100, false

local function stateNow()
	if flag(UnitIsDeadOrGhost, "player") then return "dead" end
	if flag(UnitOnTaxi, "player") then return "flight" end
	if flag(UnitAffectingCombat, "player") then return "combat" end
	if eatingNow() then return "eat" end
	if craftingNow() then return "craft" end
	if lootOpen then return "loot" end
	for _, n in ipairs(NPC_KINDS) do
		for _, name in ipairs(n[3]) do if shown(name) then return "npc", n[1] end end
	end
	if castName(UnitCastingInfo) or castName(UnitChannelInfo) then return "cast" end
	if flag(UnitIsAFK, "player") then return "afk" end
	if flag(IsSwimming) then return "swim" end
	if flag(IsFalling) then
		if not jumpHooked or GetTime() - lastJumpAt <= JUMP_AIR then return "jump" end
		return "fall"
	end
	local speed = 0
	if type(GetUnitSpeed) == "function" then
		local ok, v = pcall(GetUnitSpeed, "player")
		if ok and type(v) == "number" and not isSecret(v) then speed = v end
	end
	if speed > 0 then return flag(IsMounted) and "mount" or "walk" end
	if shown("WorldMapFrame") or shown("QuestLogFrame") then return "map" end
	return "idle"
end
api.statsStateNow = stateNow

-- 3.1.2 dungeons and raids: IsInInstance's type is party or raid
local function inDungeon()
	if type(IsInInstance) ~= "function" then return false end
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or isSecret(inside) or isSecret(kind) then return false end
	return inside and (kind == "party" or kind == "raid") and true or false
end

local lastTick
local function tick()
	local now = GetTime()
	local dt = lastTick and math.min(now - lastTick, MAX_TICK) or 0
	lastTick = now
	if loadStart or not on() or dt <= 0 then return end -- a loading screen counts as a whole when it ends
	local rec = levelRec()
	if not rec then return end
	local state, sub = stateNow()
	rec.t[state] = (tonumber(rec.t[state]) or 0) + dt
	if sub then
		rec.npc = type(rec.npc) == "table" and rec.npc or {}
		rec.npc[sub] = (tonumber(rec.npc[sub]) or 0) + dt
	end
	if inDungeon() then rec.dungeon = (tonumber(rec.dungeon) or 0) + dt end
end

-- a loading screen: its whole time, at most 5 minutes (a long one is a stall or the game in the background)
local MAX_LOAD = 300
local function onLoadStart() loadStart = GetTime() end
local function onLoadEnd()
	local began = loadStart
	loadStart = nil
	lastTick = GetTime()
	if not (began and on()) then return end
	local d = math.min(GetTime() - began, MAX_LOAD)
	local rec = levelRec()
	if rec and d > 0 then rec.t.load = (tonumber(rec.t.load) or 0) + d end
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
local function onLootOpened() lootFromMob = lootIsMob(); lootUntil = math.huge; lootOpen = true end
local function onLootClosed() lootUntil = GetTime() + 1; lootOpen = false end
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
	lastJumpAt = GetTime()
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
	local deaths, quests, questXP, xp, jumps, dungeon, npc = 0, 0, 0, 0, 0, 0, {}
	for _, rec in pairs(r and r.levels or {}) do
		if type(rec) == "table" then
			for k, v in pairs(type(rec.npc) == "table" and rec.npc or {}) do npc[k] = (npc[k] or 0) + (tonumber(v) or 0) end
			dungeon = dungeon + (tonumber(rec.dungeon) or 0)
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
	return out, total, { deaths = deaths, quests = quests, questXP = questXP, xp = xp, jumps = jumps, dungeon = dungeon, npc = npc }
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
		.. (sums.dungeon >= 1 and (" | %s in dungeons"):format(clock(sums.dungeon)) or "")
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
	"PLAYER_DEAD", "PLAYER_MONEY", "LOOT_OPENED", "LOOT_CLOSED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED" }
events:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "TIME_PLAYED_MSG" then onPlayed(a, b)
	elseif event == "QUEST_ACCEPTED" then onAccepted(a, b)
	elseif event == "QUEST_TURNED_IN" then onTurnedIn(a, b, c)
	elseif event == "PLAYER_MONEY" then onMoney()
	elseif event == "LOOT_OPENED" then onLootOpened()
	elseif event == "LOOT_CLOSED" then onLootClosed()
	elseif event == "LOADING_SCREEN_ENABLED" then onLoadStart()
	elseif event == "LOADING_SCREEN_DISABLED" then onLoadEnd()
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
		if type(JumpOrAscendStart) == "function" then jumpHooked = pcall(hooksecurefunc, "JumpOrAscendStart", onJump) end
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
	dungeon = "Interface\\Icons\\INV_Misc_Key_03", slow = "Interface\\Icons\\Spell_Nature_TimeStop",
	compare = "Interface\\Icons\\Ability_Warrior_Challange",
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

-- bars(rows): rows() -> { { label, valueText, fraction, key = k, kids = { rows } }, ... }
-- 3.1.2: a row with kids has an arrow and opens a dropdown of indented rows (closed by default, not saved); a click
-- calls onToggle so the page lays out again
local function bars(rows, maxRows, onToggle)
	return function(holder, kit)
		local C = kit.C
		local list, open = {}, {}
		local function row(i)
			if list[i] then return list[i] end
			local r = {}
			r.label = kit.text(holder, "GameFontHighlight", 1.1, C.value)
			r.label:SetJustifyH("LEFT")
			r.value = kit.text(holder, "GameFontHighlight", 1.05, C.label)
			r.value:SetJustifyH("RIGHT")
			r.track = kit.solid(holder, "BORDER", C.track)
			r.fill = holder:CreateTexture(nil, "ARTWORK")
			kit.hGradient(r.fill, C.on, 1, 0.75)
			list[i] = r
			return r
		end
		-- the dropdown's arrow and the click area over its row
		local toggles = {}
		local function toggle(key)
			if toggles[key] then return toggles[key] end
			local b = CreateFrame("Button", nil, holder)
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 0.9, 0.6, 0.08)
			if kit.arrow then b.arrow = kit.arrow(holder, false, 12) end
			b:SetScript("OnClick", function()
				open[key] = not open[key]
				if onToggle then onToggle() end
			end)
			toggles[key] = b
			return b
		end
		for i = 1, maxRows or 10 do row(i) end
		local w = {}
		function w.draw(width)
			local k = kit.ts()
			local flat = {}
			for _, d in ipairs(rows() or {}) do
				flat[#flat + 1] = { d, 0 }
				if d.kids and d.key and open[d.key] then
					for _, kid in ipairs(d.kids) do flat[#flat + 1] = { kid, 1 } end
				end
			end
			local made = #list
			for i = 1, #flat do row(i) end
			if #list > made and kit.refreshFonts then kit.refreshFonts() end
			for _, b in pairs(toggles) do b:Hide(); if b.arrow then b.arrow:Hide() end end
			local y = 0
			local rowH = math.floor(18 * k + 0.5)
			local arrowW = math.floor(16 * k + 0.5)
			for i, r in ipairs(list) do
				local d, depth = flat[i] and flat[i][1], flat[i] and flat[i][2]
				local show = d ~= nil
				r.label:SetShown(show); r.value:SetShown(show); r.track:SetShown(show); r.fill:SetShown(show)
				if show then
					local x = depth > 0 and arrowW + math.floor(8 * k) or 0
					local top = y
					if d.kids and d.key then
						local b = toggle(d.key)
						b:ClearAllPoints()
						b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -top)
						b:SetSize(math.max(width, 1), rowH + 7)
						b:Show()
						if b.arrow then
							b.arrow:ClearAllPoints()
							b.arrow:SetPoint("CENTER", holder, "TOPLEFT", arrowW / 2, -top - rowH / 2)
							if b.arrow.SetRotation then pcall(b.arrow.SetRotation, b.arrow, open[d.key] and -math.pi / 2 or 0) end
							b.arrow:Show()
						end
						x = arrowW
					end
					r.label:SetText(d[1])
					r.value:SetText(d[2] or "")
					r.label:ClearAllPoints()
					r.label:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
					r.label:SetPoint("RIGHT", holder, "TOPRIGHT", -150, 0)
					r.value:ClearAllPoints()
					r.value:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
					r.value:SetWidth(150)
					y = y + rowH + 2
					local bx = depth > 0 and x or 0
					local bw = math.max(width - bx, 1)
					r.track:ClearAllPoints()
					r.track:SetPoint("TOPLEFT", holder, "TOPLEFT", bx, -y)
					r.track:SetSize(bw, depth > 0 and 3 or 5)
					local frac = math.min(math.max(tonumber(d[3]) or 0, 0), 1)
					r.fill:ClearAllPoints()
					r.fill:SetPoint("TOPLEFT", holder, "TOPLEFT", bx, -y)
					r.fill:SetSize(math.max(bw * frac, 1), depth > 0 and 3 or 5)
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
		-- 3.1.2: gold from quests and off mobs, the whole run
		{ ICONS.gold, money(r.gold.quests + r.gold.loot), "Gold acquired" },
		{ ICONS.deaths, tostring(sums.deaths), "Deaths" },
		{ ICONS.jump, short(sums.jumps), "Jumps" },
		-- 3.1.2: time inside a dungeon or raid (it overlaps the bars: combat, running and so on in there)
		{ ICONS.dungeon, sums.dungeon >= 1 and clock(sums.dungeon) or "-", "In dungeons" },
	}
end

local function pctText(v, total)
	return ("%s  %d%%"):format(clock(v), total > 0 and math.floor(v / total * 100 + 0.5) or 0)
end
local function timeBars()
	local r = ensure()
	if not r then return {} end
	local t, total, sums = api.statsTotals(r)
	local out = {}
	for _, k in ipairs(BAR_KINDS) do
		local v = t[k] or 0
		local d = { KIND_NAMES[k], pctText(v, total), total > 0 and v / total or 0 }
		-- NPCs: a dropdown by window; the percent and bar are of the NPC time
		if k == "npc" and v > 0 then
			local kids, split = {}, 0
			for _, n in ipairs(NPC_KINDS) do
				local s = sums.npc[n[1]] or 0
				split = split + s
				if s >= 1 then kids[#kids + 1] = { n[2], pctText(s, v), s / v } end
			end
			local rest = v - split
			if rest >= 1 then kids[#kids + 1] = { "Not split (before 3.1.2)", pctText(rest, v), rest / v } end
			if #kids > 0 then d.key, d.kids = "npc", kids end
		end
		out[#out + 1] = d
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

-- 3.1.2 Level splits, fancier: summary tiles over a bar for each level (the slowest level is a full bar; green faster
-- and red slower than the compared run, whose level shows as a thin grey bar under it)
local function hex(c)
	local function b(v) return math.floor(v * 255 + 0.5) end
	return ("|cff%02x%02x%02x"):format(b(c[1]), b(c[2]), b(c[3]))
end
local function signed(d) return (d >= 0 and "+" or "-") .. clock(math.abs(d)) end
local function splitData()
	local r = ensure()
	if not r then return { rows = {} } end
	local other = compareRun()
	local rows, top, maxT = {}, UnitLevel("player") or 1, 0
	local done, sum, fast, slow = 0, 0, nil, nil
	local both, otherBoth = 0, 0
	for level = 1, top do
		local took, now = api.statsLevelTime(r, level)
		local o = other and api.statsLevelTime(other, level)
		if took or o then
			local d = took and o and not now and took - o or nil
			table.insert(rows, 1, { level = level, took = took, now = now, other = o, diff = d })
			maxT = math.max(maxT, took or 0, o or 0)
			if took and not now then
				done, sum = done + 1, sum + took
				if not fast or took < fast[2] then fast = { level, took } end
				if not slow or took > slow[2] then slow = { level, took } end
				if o then both, otherBoth = both + took, otherBoth + o end
			end
		end
	end
	return { rows = rows, maxT = maxT, done = done, sum = sum, fast = fast, slow = slow, other = other,
		ahead = otherBoth > 0 and both - otherBoth or nil, played = tonumber(r.played) }
end

local function splitTiles()
	local s = splitData()
	local out = {
		{ ICONS.clock, s.played and long(s.played) or "-", "Played" },
		{ ICONS.rate, s.done > 0 and clock(s.sum / s.done) or "-", "Average level" },
		{ ICONS.jump, s.fast and clock(s.fast[2]) or "-", s.fast and ("Fastest: level %d"):format(s.fast[1]) or "Fastest level" },
		{ ICONS.slow, s.slow and clock(s.slow[2]) or "-", s.slow and ("Slowest: level %d"):format(s.slow[1]) or "Slowest level" },
	}
	if s.ahead then
		out[#out + 1] = { ICONS.compare, hex(s.ahead > 0 and RED or GREEN) .. signed(s.ahead) .. "|r",
			s.ahead > 0 and "Behind the compared run" or "Ahead of the compared run" }
	end
	return out
end

-- rows: { label, valueText, fraction, otherFraction or nil, fillColour or nil, now }
local function splitRows()
	local s = splitData()
	local out = {}
	for _, d in ipairs(s.rows) do
		local value = d.took and clock(d.took) or "-"
		if d.diff then value = value .. "  " .. hex(d.diff > 0 and RED or GREEN) .. signed(d.diff) .. "|r"
		elseif d.other and not d.took then value = value .. "  |cff999999(" .. clock(d.other) .. ")|r" end
		local colour = d.diff and (d.diff > 0 and RED or GREEN) or nil
		out[#out + 1] = { ("Level %d"):format(d.level) .. (d.now and "  |cff999999now|r" or ""), value,
			s.maxT > 0 and (d.took or 0) / s.maxT or 0, s.other and s.maxT > 0 and (d.other or 0) / s.maxT or nil, colour, d.now }
	end
	return out
end

local function splitBars(emptyText)
	return function(holder, kit)
		local C = kit.C
		local list = {}
		local empty = kit.text(holder, "GameFontHighlight", 1.08, C.label)
		empty:SetJustifyH("LEFT")
		empty:SetText(emptyText)
		local function row(i)
			if list[i] then return list[i] end
			local r = {}
			r.label = kit.text(holder, "GameFontHighlight", 1.1, C.value)
			r.label:SetJustifyH("LEFT")
			r.value = kit.text(holder, "GameFontHighlight", 1.05, C.label)
			r.value:SetJustifyH("RIGHT")
			r.track = kit.solid(holder, "BORDER", C.track)
			r.fill = holder:CreateTexture(nil, "ARTWORK")
			r.other = holder:CreateTexture(nil, "ARTWORK")
			r.other:SetColorTexture(0.6, 0.6, 0.6, 0.55)
			list[i] = r
			return r
		end
		local w = {}
		function w.draw(width)
			local k = kit.ts()
			local data = splitRows()
			local made = #list
			for i = 1, #data do row(i) end
			if #list > made and kit.refreshFonts then kit.refreshFonts() end
			empty:SetShown(#data == 0)
			if #data == 0 then
				empty:ClearAllPoints()
				empty:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
				empty:SetWidth(math.max(width, 40))
				return math.floor(20 * k + 0.5)
			end
			local y = 0
			local rowH = math.floor(18 * k + 0.5)
			for i, r in ipairs(list) do
				local d = data[i]
				local show = d ~= nil
				r.label:SetShown(show); r.value:SetShown(show); r.track:SetShown(show); r.fill:SetShown(show)
				r.other:SetShown(show and d[4] ~= nil)
				if show then
					r.label:SetText(d[1])
					r.label:ClearAllPoints()
					r.label:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r.label:SetPoint("RIGHT", holder, "TOPRIGHT", -170, 0)
					r.value:SetText(d[2])
					r.value:ClearAllPoints()
					r.value:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
					r.value:SetWidth(170)
					y = y + rowH + 2
					r.track:ClearAllPoints()
					r.track:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r.track:SetSize(width, 6)
					local frac = math.min(math.max(d[3] or 0, 0), 1)
					kit.hGradient(r.fill, d[5] or C.on, d[6] and 0.55 or 1, d[6] and 0.35 or 0.75)
					r.fill:ClearAllPoints()
					r.fill:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
					r.fill:SetSize(math.max(width * frac, 1), 6)
					r.fill:SetShown(frac > 0)
					y = y + 6
					if d[4] then
						local of = math.min(math.max(d[4], 0), 1)
						r.other:ClearAllPoints()
						r.other:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y - 2)
						r.other:SetSize(math.max(width * of, 1), 2)
						r.other:SetShown(of > 0)
						y = y + 4
					end
					y = y + math.floor(9 * k + 0.5)
				end
			end
			return math.max(y, 1)
		end
		return w
	end
end

api.statsOverviewTiles, api.statsGoldTiles, api.statsLevelBar, api.statsRunTiles, api.statsTimeBars, api.statsLevelLines =
	overviewTiles, goldTiles, levelBar, runTiles, timeBars, levelLines -- (tests)
api.statsSplitTiles, api.statsSplitRows = splitTiles, splitRows -- (tests)
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
	k.custom("Recorded completed quests xp from quests deaths jumps in dungeons", tiles(runTiles, 6), true)
	k.heading("Where the time went")
	k.custom("Combat running mounted swimming jumping falling crafting gathering eating drinking looting casting flight npcs "
		.. "vendors trainers bank mailbox auction map quest log loading screens dead afk standing",
		bars(timeBars, #BAR_KINDS, function() k.refresh() end), true)
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
	k.custom("Played average level fastest slowest ahead behind", tiles(splitTiles, 5), true)
	k.heading("Each level")
	k.custom("Level splits", splitBars("Level up once and the first split shows here."), true)
end
