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
--     3.2 (user) also ah (money from an auction mail, or with the auction house open), mail (other mail money; before
--     dev-91 it held auction sales too), vendor (a vendor
--     open: selling), trade (a trade window open, or up to 2 s after it closed) and spent (every copper that went out,
--     anywhere). Money coming in some other way (a quest reward, which QUEST_TURNED_IN counts) is not counted twice.
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
-- 3.2: the character key with the surname (Core.lua api.playerKey); without it (tests) "Name-Realm"
local function playerKey(...)
	if api.playerKey then return api.playerKey(...) end
	local name, realm = UnitName and UnitName("player"), GetRealmName and GetRealmName()
	if type(name) ~= "string" or (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then return nil end
	return name .. "-" .. tostring(realm or "")
end

local KIND_NAMES = { combat = "Combat", walk = "Running", mount = "Mounted", flight = "Flight", npc = "NPCs", dead = "Dead",
	afk = "AFK", idle = "Standing", swim = "Swimming", jump = "Jumping", craft = "Crafting/gathering",
	eat = "Eating/drinking", loot = "Looting", cast = "Casting", fall = "Falling", map = "Map/quest log",
	load = "Loading screens", camp = "At a campfire" }
-- Run analysis (bars and the Discord text): every state
local BAR_KINDS = { "combat", "walk", "mount", "swim", "jump", "fall", "craft", "eat", "loot", "cast", "flight", "npc",
	"map", "load", "dead", "afk", "idle", "camp" }
-- 3.2 (user: "make it make sense, and reorderable"): the bars in groups; each state is in one group.
-- db.timeGroupOrder / db.timeKindOrder keep the order the player picked (Run analysis > "Change the order").
local TIME_GROUPS = {
	{ "fight", "Fighting", { "combat", "dead" } },
	{ "travel", "Travel", { "walk", "mount", "flight", "swim", "jump", "fall" } },
	{ "windows", "NPCs and windows", { "npc", "map" } },
	{ "actions", "Doing things", { "loot", "cast", "craft", "eat" } },
	{ "downtime", "Downtime", { "idle", "afk", "load", "camp" } },
}
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
local session = { start = nil, quests = 0, xp = 0, jumps = 0, goldQuests = 0, goldLoot = 0, deaths = 0, kills = 0 }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function on() return db and db.statsOn ~= false end
local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r " .. text) end

---------------------------------------------------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------------------------------------------------
-- 4:05, 1:02:03 (api.statsClock: the dungeon run timer and the flight time keep this look)
local function colonClock(sec)
	sec = math.max(math.floor((tonumber(sec) or 0) + 0.5), 0)
	local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end
-- 3.2 (user: "show as d, h, m, s like the Time Played tile"): every time on the Statistics pages, in the Discord text
-- and the level-up line, as its two largest parts: 2d 3h, 5h 12m, 4m 5s, 45s
local function clock(sec)
	sec = math.max(math.floor((tonumber(sec) or 0) + 0.5), 0)
	local d, h, m, s = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60, sec % 60
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %dm"):format(h, m) end
	if m > 0 then return ("%dm %ds"):format(m, s) end
	return ("%ds"):format(s)
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
api.statsClock, api.statsLong, api.statsShort, api.statsMoney = colonClock, long, short, money
api.statsTime = clock -- (tests)

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
-- 3.2: "Ana Smith-Realm" with the surname (api.playerKey); a record saved under the first name moves over when its
-- class is ours
local function charKey()
	local _, class = UnitClass("player")
	return playerKey(db and db.statsRuns, function(old)
		return type(old) == "table" and (old.class == nil or old.class == class)
	end)
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
	g.mail, g.vendor, g.trade, g.spent = tonumber(g.mail) or 0, tonumber(g.vendor) or 0, tonumber(g.trade) or 0, tonumber(g.spent) or 0
	g.ah = tonumber(g.ah) or 0
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
	r.name, r.realm, r.class = (api.playerName and (api.playerName()) or UnitName("player")), GetRealmName and GetRealmName() or "", class
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

-- 3.2 periods (user: a "< This session >" switcher on Overview and Run analysis: This session, Last session, This
-- week, This month, All-time). All-time is the record above. The others need the same numbers by time, so each is
-- also added to a bucket for today (r.days["2026-11-27"], kept 40 days) and one for this session (r.session; the one
-- before is r.sessionLast). A bucket: { t = { [state] = s }, npc = { [window] = s }, quests, questXP, xp, deaths,
-- jumps, dungeon, raid, pvp, rested, goldQuests, goldLoot, abandoned, timeSum, timed, zones = { [zone] = n } }.
-- A session goes on through a /reload: a login less than 5 minutes after the last tick keeps the bucket.
-- Before 3.2 nothing was kept by day or session, so those periods start empty.
local KEEP_DAYS, SESSION_GAP = 40, 300
local function today(at) return date("%Y-%m-%d", at) end
local function newBucket() return { t = {}, npc = {}, zones = {} } end
local function fixBucket(b)
	if type(b) ~= "table" then return nil end
	b.t = type(b.t) == "table" and b.t or {}
	b.npc = type(b.npc) == "table" and b.npc or {}
	b.zones = type(b.zones) == "table" and b.zones or {}
	return b
end
local dayCache
local function periodBuckets()
	local r = ensure()
	if not r or type(date) ~= "function" then return nil end
	r.days = type(r.days) == "table" and r.days or {}
	local key = today()
	if not dayCache or dayCache.key ~= key or r.days[key] ~= dayCache.b then
		local b = fixBucket(r.days[key]) or newBucket()
		r.days[key] = b
		dayCache = { key = key, b = b }
		-- days older than KEEP_DAYS go (keys sort as dates)
		local oldest = today(time() - KEEP_DAYS * 86400)
		for k in pairs(r.days) do if type(k) ~= "string" or k < oldest then r.days[k] = nil end end
	end
	r.session = fixBucket(r.session) or newBucket()
	return dayCache.b, r.session
end
-- add n to a field of today's and this session's buckets (sub: a table field such as t, npc or zones)
local function addPeriod(field, n, sub)
	if not n or n == 0 then return end
	local day, sess = periodBuckets()
	if not day then return end
	for _, b in ipairs({ day, sess }) do
		if sub then b[sub][field] = (tonumber(b[sub][field]) or 0) + n
		else b[field] = (tonumber(b[field]) or 0) + n end
	end
	sess.seen = time()
end
-- at login: go on with the session after a /reload, or start a new one (the old one becomes the last session)
local function startSession()
	local r = ensure()
	if not r then return end
	local cur = fixBucket(r.session)
	if cur and tonumber(cur.seen) and time() - cur.seen < SESSION_GAP then return end
	if cur and next(cur.t) then r.sessionLast = cur end
	r.session = newBucket()
	r.session.started = time()
	dayCache = nil
end
api.statsStartSession = startSession -- (tests)

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
-- 3.2: at a campfire (Camp Benefits / Campfire nearby) and Well Rested, by spell ID or name; time counted on top of
-- the state, as the dungeon time
local CAMP_IDS = { [1229741] = "camp", [429959] = "rested" }
local CAMP_NAMES = { ["camp benefits"] = "camp", ["campfire nearby"] = "camp", ["well rested"] = "rested" }
local function campBuffs()
	local byData = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
	if type(byData) ~= "function" then return false, false end
	local camp, rested = false, false
	for i = 1, 40 do
		local d = byData("player", i)
		if type(d) ~= "table" then break end
		local kind
		if d.spellId and not isSecret(d.spellId) then kind = CAMP_IDS[d.spellId] end
		if not kind and type(d.name) == "string" and not isSecret(d.name) then kind = CAMP_NAMES[d.name:lower()] end
		if kind == "camp" then camp = true elseif kind == "rested" then rested = true end
	end
	return camp, rested
end
api.statsCampBuffs = campBuffs
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

-- 3.1.2 dungeons; 3.2 raids and battlegrounds apart: IsInInstance's type is party, raid, pvp or arena.
-- the record field for the instance you are in ("dungeon", "raid", "pvp"), or nil
local INSTANCE_FIELD = { party = "dungeon", raid = "raid", pvp = "pvp", arena = "pvp" }
local function instanceField()
	if type(IsInInstance) ~= "function" then return nil end
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or isSecret(inside) or isSecret(kind) or not inside then return nil end
	return INSTANCE_FIELD[kind]
end

local lastTick
local CAMP_STATES = { idle = true, afk = true, eat = true, map = true }
local function tick()
	local now = GetTime()
	local dt = lastTick and math.min(now - lastTick, MAX_TICK) or 0
	lastTick = now
	if loadStart or not on() or dt <= 0 then return end -- a loading screen counts as a whole when it ends
	local rec = levelRec()
	if not rec then return end
	local state, sub = stateNow()
	-- 3.2 (user): a campfire is a state of its own (Downtime): resting there (standing, AFK, eating or drinking, map)
	-- counts as "At a campfire" instead, so each second is in one bar. Well Rested is not a state: it stays on while you
	-- run, fight and shop, so it is counted apart and not in the total
	local ok, camp, rested = pcall(campBuffs)
	if ok and camp and CAMP_STATES[state] then state = "camp" end
	rec.t[state] = (tonumber(rec.t[state]) or 0) + dt
	addPeriod(state, dt, "t")
	if sub then
		rec.npc = type(rec.npc) == "table" and rec.npc or {}
		rec.npc[sub] = (tonumber(rec.npc[sub]) or 0) + dt
		addPeriod(sub, dt, "npc")
	end
	local field = instanceField()
	if field then rec[field] = (tonumber(rec[field]) or 0) + dt; addPeriod(field, dt) end
	-- 3.2 (user): always counted, no switch
	if ok and rested then rec.rested = (tonumber(rec.rested) or 0) + dt; addPeriod("rested", dt) end
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
	if rec and d > 0 then rec.t.load = (tonumber(rec.t.load) or 0) + d; addPeriod("load", d, "t") end
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
-- 3.2: money that comes in up to 2 s after a trade window closed is trade money; up to 2 s after a quest
-- turn-in it is the reward (QUEST_TURNED_IN counts it)
local tradeUntil, questUntil = -100, -100
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
	questUntil = GetTime() + 2 -- its money may come just before or after this event
	if gold > 0 then
		r.gold.quests = r.gold.quests + gold
		session.goldQuests = session.goldQuests + gold
		addPeriod("goldQuests", gold)
	end
	local q = r.quests
	q.done = q.done + 1
	q.xp = q.xp + xp
	local zone = GetRealZoneText and GetRealZoneText()
	if type(zone) == "string" and zone ~= "" and not isSecret(zone) then
		q.zones[zone] = (tonumber(q.zones[zone]) or 0) + 1
		addPeriod(zone, 1, "zones")
	end
	addPeriod("quests", 1)
	addPeriod("questXP", xp)
	local rec = levelRec()
	rec.quests = (tonumber(rec.quests) or 0) + 1
	rec.questXP = (tonumber(rec.questXP) or 0) + xp
	session.quests = session.quests + 1
	local acc = id and r.accepted[id]
	if type(acc) == "table" and tonumber(acc.at) then
		local t = time() - acc.at
		if t > 0 and t < MAX_QUEST_TIME then
			q.timeSum, q.timed = q.timeSum + t, q.timed + 1
			addPeriod("timeSum", t)
			addPeriod("timed", 1)
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
	if r then r.quests.abandoned = r.quests.abandoned + 1; addPeriod("abandoned", 1) end
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
-- 3.2: where money that came in came from (nil: not counted here)
-- (tradeUntil, questUntil: declared before onTurnedIn)
local GOLD_WINDOWS = {
	{ "ah", { "AuctionFrame", "AuctionHouseFrame" } },
	{ "mail", { "MailFrame" } },
	{ "vendor", { "MerchantFrame" } },
	{ "trade", { "TradeFrame" } },
}
-- 3.2 (user: "separate Gold from AH and Gold from mail"): the mail whose money was just taken (TakeInboxMoney, or
-- AutoLootMailItem: one mail or "Open All", also from mail addons) says where its money comes from: an auction invoice
-- (GetInboxInvoiceInfo) or the sender "Auction House" is the auction house, anything else is mail
local mailKind, mailUntil = nil, -100
local function auctionMail(index)
	if type(GetInboxInvoiceInfo) == "function" then
		local ok, invoice = pcall(GetInboxInvoiceInfo, index)
		if ok and type(invoice) == "string" and not isSecret(invoice) and invoice ~= "" then return true end
	end
	if type(GetInboxHeaderInfo) == "function" then
		local ok, _, _, sender = pcall(GetInboxHeaderInfo, index)
		if ok and type(sender) == "string" and not isSecret(sender) then
			local name = rawget(_G, "AUCTION_HOUSE_MAIL_SENDER") or "Auction House"
			if sender == name or sender:find("Auction House", 1, true) then return true end
		end
	end
	return false
end
local function onMailTaken(index)
	mailKind = auctionMail(index) and "ah" or "mail"
	mailUntil = GetTime() + 5
end
api.statsOnMailTaken = onMailTaken -- (tests)
local function moneySource()
	if lootFromMob and GetTime() <= lootUntil then return "loot" end
	if GetTime() <= questUntil or shown("QuestFrame") then return nil end -- a quest reward: QUEST_TURNED_IN counts it
	if mailKind and GetTime() <= mailUntil then return mailKind end
	for _, w in ipairs(GOLD_WINDOWS) do
		for _, name in ipairs(w[2]) do if shown(name) then return w[1] end end
	end
	if GetTime() <= tradeUntil then return "trade" end
	return nil
end
local PERIOD_GOLD = { loot = "goldLoot", ah = "goldAH", mail = "goldMail", vendor = "goldVendor", trade = "goldTrade" }
local function onMoney()
	local now = readMoney()
	if not now then return end
	local before = lastMoney
	lastMoney = now
	if not (before and on()) then return end
	local r = ensure()
	if not r then return end
	local change = now - before
	if change < 0 then
		r.gold.spent = r.gold.spent + -change
		addPeriod("goldSpent", -change)
		return
	end
	local source = change > 0 and moneySource()
	if not source then return end
	r.gold[source] = (tonumber(r.gold[source]) or 0) + change
	addPeriod(PERIOD_GOLD[source], change)
	if source == "loot" then session.goldLoot = session.goldLoot + change end
end
api.statsOnTradeClosed = function() tradeUntil = GetTime() + 2 end
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
	addPeriod("jumps", 1)
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
			addPeriod("xp", gained)
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
-- 3.2 (user: "a dropdown to the statistics sections to choose a character to view"): db.statsView is the key of the
-- record the pages show (nil or "me": this character). Recording always goes to this character's own record.
local function viewKey()
	ensure()
	local key = db and db.statsView
	if type(key) ~= "string" or key == "me" or key == runKey then return runKey end
	if not (type(db.statsRuns) == "table" and type(db.statsRuns[key]) == "table") then return runKey end
	return key
end
local function viewed()
	local key = viewKey()
	if key == runKey then return ensure() end
	return fill(db.statsRuns[key])
end
local function isMe() return viewKey() == runKey end
api.statsViewed, api.statsViewKey = viewed, viewKey
-- the name of a record's key: "Ana Smith-Realm (previous)" -> "Ana Smith (previous)"
local function keyName(k)
	local prev = k:find(" %(previous%)$") and " (previous)" or ""
	local base = prev ~= "" and k:sub(1, -12) or k
	return (base:match("^(.*)%-[^%-]*$") or base) .. prev
end
local function topLevel(r)
	local top = 0
	for l in pairs(type(r) == "table" and type(r.reached) == "table" and r.reached or {}) do top = math.max(top, tonumber(l) or 0) end
	for l in pairs(type(r) == "table" and type(r.levels) == "table" and r.levels or {}) do top = math.max(top, tonumber(l) or 0) end
	return top
end
-- { { key, label }, ... }: this character first, then every other record by name
function api.statsViewOptions()
	ensure()
	local me = runKey and keyName(runKey) or "?"
	local out = { { "me", ("This character (%s)"):format(me) } }
	local keys = {}
	for k, r in pairs(db and type(db.statsRuns) == "table" and db.statsRuns or {}) do
		if k ~= runKey and type(k) == "string" and type(r) == "table" then keys[#keys + 1] = k end
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local top = topLevel(db.statsRuns[k])
		out[#out + 1] = { k, top > 0 and ("%s (level %d)"):format(keyName(k), top) or keyName(k) }
	end
	return out
end
-- every other recorded run, for "Compare with": { { key, label }, ... }
function api.statsCompareOptions()
	local out = { { "none", "None" } }
	ensure()
	local keys = {}
	for k in pairs(db and type(db.statsRuns) == "table" and db.statsRuns or {}) do
		if k ~= viewKey() then keys[#keys + 1] = k end
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
	if not key or key == "none" or key == viewKey() then return nil end
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
	local rested, raid, pvp = 0, 0, 0
	for _, rec in pairs(r and r.levels or {}) do
		if type(rec) == "table" then
			rested = rested + (tonumber(rec.rested) or 0)
			raid, pvp = raid + (tonumber(rec.raid) or 0), pvp + (tonumber(rec.pvp) or 0)
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
	return out, total, { deaths = deaths, quests = quests, questXP = questXP, xp = xp, jumps = jumps, dungeon = dungeon, npc = npc,
		rested = rested, raid = raid, pvp = pvp }
end

-- 3.2 periods: the switcher's choices, and the sums of one period in one shape:
-- t, total, sums = { quests, questXP, xp, deaths, jumps, dungeon, raid, pvp, rested, npc, goldQuests, goldLoot,
-- abandoned, timeSum, timed, zones, questsDone, questXPDone } (questsDone / questXPDone: All-time takes them from the
-- quest record, as before 3.2; the buckets have one count)
local PERIODS = { { "session", "This session" }, { "last", "Last session" }, { "week", "This week" },
	{ "month", "This month" }, { "all", "All-time" } }
local PERIOD_FIELD = { overview = "statsPeriodOverview", run = "statsPeriodRun" }
local function periodOf(page)
	local v = db and db[PERIOD_FIELD[page]]
	for _, p in ipairs(PERIODS) do if p[1] == v then return v end end
	return "session"
end
local function periodName(id)
	for _, p in ipairs(PERIODS) do if p[1] == id then return p[2] end end
	return id
end
-- step the page's period one back (-1) or on (1), round
local function stepPeriod(page, dir)
	local cur = periodOf(page)
	for i, p in ipairs(PERIODS) do
		if p[1] == cur then db[PERIOD_FIELD[page]] = PERIODS[(i - 1 + dir) % #PERIODS + 1][1]; return end
	end
end
api.statsPeriodOf, api.statsStepPeriod, api.statsPeriodName = periodOf, stepPeriod, periodName

local NUM_FIELDS = { "quests", "questXP", "xp", "deaths", "jumps", "dungeon", "raid", "pvp", "rested", "goldQuests",
	"goldLoot", "goldAH", "goldMail", "goldVendor", "goldTrade", "goldSpent", "abandoned", "timeSum", "timed" }
local function addBucket(into, b)
	if type(b) ~= "table" then return end
	for _, f in ipairs(NUM_FIELDS) do into[f] = into[f] + (tonumber(b[f]) or 0) end
	for _, sub in ipairs({ "t", "npc", "zones" }) do
		for k, v in pairs(type(b[sub]) == "table" and b[sub] or {}) do into[sub][k] = (into[sub][k] or 0) + (tonumber(v) or 0) end
	end
end
-- the first day of this week (Monday) or month, as "2026-11-23"
local function periodStart(id)
	local now = time()
	if id == "month" then return date("%Y-%m-01", now) end
	local weekday = tonumber(date("%w", now)) or 1 -- 0 Sunday
	return date("%Y-%m-%d", now - ((weekday + 6) % 7) * 86400)
end
api.statsPeriodStart = periodStart -- (tests)
-- 3.2 (user: "a checkbox to both to show all characters"): db.statsAllOverview / db.statsAllRun. Every character's
-- record of this account adds in, except the "(previous)" runs (an older run of a name). This session is still this
-- login's (no other character can be in it); Last session is the account's last one: the session that was seen last,
-- of any character, apart from this one.
local ALL_FIELD = { overview = "statsAllOverview", run = "statsAllRun" }
local function allOf(page) return db and db[ALL_FIELD[page]] == true or false end
api.statsAllOf = allOf
local function records(all)
	local mine = ensure()
	if not all then return { viewed() } end
	local out = { mine }
	for k, r in pairs(db and type(db.statsRuns) == "table" and db.statsRuns or {}) do
		if type(r) == "table" and r ~= mine and type(k) == "string" and not k:find(" %(previous%)$") then out[#out + 1] = fill(r) end
	end
	return out
end
function api.statsPeriodTotals(id, all)
	local r = ensure()
	if not r then return {}, 0, nil end
	if not all then r = viewed() end
	local list = records(all)
	local sums = { t = {}, npc = {}, zones = {} }
	for _, f in ipairs(NUM_FIELDS) do sums[f] = 0 end
	if id == "all" then
		sums.questsDone, sums.questXPDone = 0, 0
		for _, rec in ipairs(list) do
			local t, _, s = api.statsTotals(rec)
			s.t, s.goldQuests, s.goldLoot = t, rec.gold.quests, rec.gold.loot
			s.goldMail, s.goldVendor, s.goldTrade, s.goldSpent = rec.gold.mail, rec.gold.vendor, rec.gold.trade, rec.gold.spent
			s.goldAH = rec.gold.ah
			s.abandoned, s.timeSum, s.timed, s.zones = rec.quests.abandoned, rec.quests.timeSum, rec.quests.timed, rec.quests.zones
			addBucket(sums, s)
			sums.questsDone, sums.questXPDone = sums.questsDone + rec.quests.done, sums.questXPDone + rec.quests.xp
		end
	else
		if id == "session" then
			if r == run then periodBuckets() end
			addBucket(sums, r.session)
		elseif id == "last" then
			local best = r.sessionLast
			if all then
				for _, rec in ipairs(list) do
					for _, b in ipairs({ rec.session, rec.sessionLast }) do
						if type(b) == "table" and b ~= r.session and (tonumber(b.seen) or 0) > (type(best) == "table" and tonumber(best.seen) or 0) then best = b end
					end
				end
			end
			addBucket(sums, best)
		elseif type(date) == "function" then
			local from = periodStart(id)
			for _, rec in ipairs(list) do
				for day, b in pairs(type(rec.days) == "table" and rec.days or {}) do
					if type(day) == "string" and day >= from then addBucket(sums, b) end
				end
			end
		end
		sums.questsDone, sums.questXPDone = sums.quests, sums.questXP
	end
	local total = 0
	for _, v in pairs(sums.t) do total = total + v end
	local t = sums.t
	sums.t = nil
	return t, total, sums
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
	local period = periodOf("run")
	local t, total, sums = api.statsPeriodTotals(period, allOf("run"))
	local _, class = UnitClass("player")
	local lines = {}
	-- 3.2: the character's surname on Forever ("Ana Smith"); the character chosen to view, when it is not this one
	local who, level = api.playerName and api.playerName() or UnitName("player"), UnitLevel("player") or 0
	if not isMe() and not allOf("run") then
		local v = viewed()
		who, class, level = keyName(viewKey()), v.class, topLevel(v)
	end
	lines[#lines + 1] = ("**%s** - level %d %s - ForeverTrackerPlus run analysis (%s%s)"):format(type(who) == "string" and who or "?",
		level, (tostring(class or ""):lower():gsub("^%l", string.upper)), periodName(period), allOf("run") and ", all characters" or "")
	lines[#lines + 1] = ("Recorded %s | %d quests | %d%% XP from quests | %d deaths | %d jumps"):format(clock(total), sums.quests,
		sums.xp > 0 and math.floor(sums.questXP / sums.xp * 100 + 0.5) or 0, sums.deaths, sums.jumps)
		.. (sums.dungeon >= 1 and (" | %s in dungeons"):format(clock(sums.dungeon)) or "")
		.. (sums.raid >= 1 and (" | %s in raids"):format(clock(sums.raid)) or "")
		.. (sums.pvp >= 1 and (" | %s in battlegrounds"):format(clock(sums.pvp)) or "")
	lines[#lines + 1] = "```"
	local function pct(v) return total > 0 and math.floor(v / total * 100 + 0.5) or 0 end
	for _, g in ipairs(api.statsTimeGroups(t)) do
		lines[#lines + 1] = ("%-20s %9s %3d%%"):format(g[2], clock(g[3]), pct(g[3]))
		for _, m in ipairs(g[4]) do
			lines[#lines + 1] = ("  %-18s %9s %3d%%"):format(KIND_NAMES[m[1]], clock(m[2]), pct(m[2]))
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
	dayCache = nil
	ensure()
	startSession()
	lastAsk = -60
	requestPlayed()
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local EVENTS = { "TIME_PLAYED_MSG", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
	"PLAYER_DEAD", "PLAYER_MONEY", "LOOT_OPENED", "LOOT_CLOSED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "TRADE_CLOSED" }
events:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "TIME_PLAYED_MSG" then onPlayed(a, b)
	elseif event == "QUEST_ACCEPTED" then onAccepted(a, b)
	elseif event == "QUEST_TURNED_IN" then onTurnedIn(a, b, c)
	elseif event == "PLAYER_MONEY" then onMoney()
	elseif event == "LOOT_OPENED" then onLootOpened()
	elseif event == "LOOT_CLOSED" then onLootClosed()
	elseif event == "TRADE_CLOSED" then api.statsOnTradeClosed()
	elseif event == "LOADING_SCREEN_ENABLED" then onLoadStart()
	elseif event == "LOADING_SCREEN_DISABLED" then onLoadEnd()
	elseif event == "PLAYER_XP_UPDATE" then onXP()
	elseif event == "PLAYER_LEVEL_UP" then
		onXP()
		announceLevel = tonumber(a)
		-- 3.2: the level-up banner (LevelBanner.lua): the last level's time from our clock, and the time played
		if api.showLevelBanner and announceLevel then
			local r = on() and ensure()
			local took = r and api.statsLevelTime(r, announceLevel - 1)
			local parts = {}
			if took and took > 0 then parts[#parts + 1] = ("Level %d took %s"):format(announceLevel - 1, clock(took)) end
			if r and tonumber(r.played) then parts[#parts + 1] = ("%s played"):format(clock(r.played)) end
			pcall(api.showLevelBanner, announceLevel, table.concat(parts, "  \194\183  "))
		end
		lastAsk = -60
		C_Timer.After(1.5, requestPlayed)
	elseif event == "PLAYER_DEAD" then
		session.deaths = session.deaths + 1
		if on() then local rec = levelRec(); if rec then rec.deaths = (tonumber(rec.deaths) or 0) + 1; addPeriod("deaths", 1) end end
	elseif event == "PLAYER_LOGOUT" then
		local r = on() and ensure()
		if r then r.lastSession = api.statsSessionSummary() end
	end
end)

-- 3.2 session summary: this session so far (/qt session), kept at logout and shown at the next login
function api.statsSessionSummary()
	local t = session.start and (GetTime() - session.start) or 0
	return { t = t, quests = session.quests, xp = session.xp, gold = session.goldQuests + session.goldLoot,
		deaths = session.deaths, kills = (api.killSessionCount and api.killSessionCount()) or session.kills,
		levels = (UnitLevel("player") or 0) - (session.startLevel or UnitLevel("player") or 0), at = time and time() or nil }
end
local function summaryText(s)
	if type(s) ~= "table" then return nil end
	local parts = { long(s.t), ("%d quests"):format(tonumber(s.quests) or 0) }
	if (tonumber(s.xp) or 0) > 0 then parts[#parts + 1] = short(s.xp) .. " xp" end
	if (tonumber(s.levels) or 0) > 0 then parts[#parts + 1] = ("%d level%s"):format(s.levels, s.levels == 1 and "" or "s") end
	if (tonumber(s.gold) or 0) > 0 then parts[#parts + 1] = money(s.gold) end
	if (tonumber(s.kills) or 0) > 0 then parts[#parts + 1] = ("%d kills"):format(s.kills) end
	if (tonumber(s.deaths) or 0) > 0 then parts[#parts + 1] = ("%d deaths"):format(s.deaths) end
	return table.concat(parts, ", ")
end
api.statsSummaryText = summaryText
if api.addSlash then
	api.addSlash("session", "what you did this session", function()
		say("This session: " .. (summaryText(api.statsSessionSummary()) or "-") .. ".")
	end)
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	session.start = GetTime()
	session.startLevel = UnitLevel("player")
	pcall(events.RegisterEvent, events, "PLAYER_LOGOUT")
	C_Timer.After(8, function()
		local r = on() and db.sessionSummary ~= false and ensure()
		local text = r and summaryText(r.lastSession)
		if text and (tonumber(r.lastSession.t) or 0) >= 60 then say("Last session: " .. text .. ".") end
	end)
	for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
	ensure()
	startSession()
	lastXP, lastMax = readXP()
	lastLevel = UnitLevel("player")
	lastMoney = readMoney()
	if hooksecurefunc then
		if type(JumpOrAscendStart) == "function" then jumpHooked = pcall(hooksecurefunc, "JumpOrAscendStart", onJump) end
		if type(AbandonQuest) == "function" then pcall(hooksecurefunc, "AbandonQuest", onAbandon) end
		for _, fn in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
			if type(rawget(_G, fn)) == "function" then pcall(hooksecurefunc, fn, onMailTaken) end
		end
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
	dungeon = "Interface\\Icons\\INV_Misc_Key_03", raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	pvp = "Interface\\Icons\\INV_BannerPVP_02", slow = "Interface\\Icons\\Spell_Nature_TimeStop",
	compare = "Interface\\Icons\\Ability_Warrior_Challange",
}

-- 3.2 (user): a money tile's icon is the coin of its largest part: gold, silver or copper
local COIN_ICONS = { gold = "Interface\\Icons\\INV_Misc_Coin_01", silver = "Interface\\Icons\\INV_Misc_Coin_03",
	copper = "Interface\\Icons\\INV_Misc_Coin_05" }
local function coinIcon(c)
	c = tonumber(c) or 0
	if c >= 10000 then return COIN_ICONS.gold end
	if c >= 100 then return COIN_ICONS.silver end
	return COIN_ICONS.copper
end
api.statsCoinIcon = coinIcon
local function earned(g) return g.goldQuests + g.goldLoot + g.goldAH + g.goldMail + g.goldVendor + g.goldTrade end

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
		-- 3.2 (user): the tiles count up from 0 each time their page opens (Animations.lua)
		if holder.HookScript then holder:HookScript("OnShow", function() holder.qtsCountUp = true end) end
		holder.qtsCountUp = true
		function w.draw(width)
			local k = kit.ts()
			local data = rows() or {}
			local countUp = holder.qtsCountUp
			holder.qtsCountUp = nil
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
					if api.animCountUp then api.animCountUp(t.value, d[2], countUp) end
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

-- bars(rows): rows() -> { { label, valueText, fraction, key = k, kids = { rows }, open = default, move = fn(dir) }, ... }
-- 3.2: kids fold at any depth (a group, then NPCs by window); open = true starts a fold open; move(-1 / 1) with
-- showMove() true draws up and down buttons on the row.
local bars
do
	local UP = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up"
	local DOWN = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"
	bars = function(rows, maxRows, onToggle, showMove)
		return function(holder, kit)
			local C = kit.C
			local list, open = {}, {}
			local function isOpen(d)
				if open[d.key] == nil then return d.open and true or false end
				return open[d.key]
			end
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
				r.moves = {}
				list[i] = r
				return r
			end
			-- up and down buttons (3.2), made the first time "Change the order" shows them
			local function makeMoves(r)
				if #r.moves > 0 then return r.moves end
				for j, tex in ipairs({ UP, DOWN }) do
					local m = CreateFrame("Button", nil, holder)
					m:SetNormalTexture(tex)
					m:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight", "ADD")
					m:SetFrameLevel((holder:GetFrameLevel() or 1) + 5)
					m.dir = j == 1 and -1 or 1
					m:SetScript("OnClick", function(self)
						if self.fn then self.fn(self.dir) end
						if onToggle then onToggle() end
					end)
					m:SetScript("OnEnter", function(self)
						if not GameTooltip then return end
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:SetText(self.dir < 0 and "Move up" or "Move down")
						GameTooltip:Show()
					end)
					m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
					m:Hide()
					r.moves[j] = m
				end
				return r.moves
			end
			-- the dropdown's arrow and the click area over its row
			local toggles = {}
			local function toggle(d)
				local key = d.key
				if toggles[key] then return toggles[key] end
				local b = CreateFrame("Button", nil, holder)
				local hl = b:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(1, 0.9, 0.6, 0.08)
				if kit.arrow then b.arrow = kit.arrow(holder, false, 12) end
				b:SetScript("OnClick", function(self)
					open[key] = not isOpen(self.d)
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
				local function add(d, depth)
					flat[#flat + 1] = { d, depth }
					if d.kids and d.key and isOpen(d) then
						for _, kid in ipairs(d.kids) do add(kid, depth + 1) end
					end
				end
				for _, d in ipairs(rows() or {}) do add(d, 0) end
				local made = #list
				for i = 1, #flat do row(i) end
				if #list > made and kit.refreshFonts then kit.refreshFonts() end
				for _, b in pairs(toggles) do b:Hide(); if b.arrow then b.arrow:Hide() end end
				local moving = showMove and showMove()
				local y = 0
				local rowH = math.floor(18 * k + 0.5)
				local arrowW = math.floor(16 * k + 0.5)
				local moveW = math.floor(16 * k + 0.5)
				for i, r in ipairs(list) do
					local d, depth = flat[i] and flat[i][1], flat[i] and flat[i][2] or 0
					local show = d ~= nil
					r.label:SetShown(show); r.value:SetShown(show); r.track:SetShown(show); r.fill:SetShown(show)
					for _, m in ipairs(r.moves) do m:Hide() end
					if show then
						local indent = depth * (arrowW + math.floor(8 * k))
						local x = indent
						local top = y
						if d.kids and d.key then
							local b = toggle(d)
							b.d = d
							b:ClearAllPoints()
							b:SetPoint("TOPLEFT", holder, "TOPLEFT", indent, -top)
							b:SetSize(math.max(width - indent, 1), rowH + 7)
							b:Show()
							if b.arrow then
								b.arrow:ClearAllPoints()
								b.arrow:SetPoint("CENTER", holder, "TOPLEFT", indent + arrowW / 2, -top - rowH / 2)
								if b.arrow.SetRotation then pcall(b.arrow.SetRotation, b.arrow, isOpen(d) and -math.pi / 2 or 0) end
								b.arrow:Show()
							end
							x = indent + arrowW
						end
						local right = 150
						if moving and d.move then
							for j, m in ipairs(makeMoves(r)) do
								m.fn = d.move
								m:ClearAllPoints()
								m:SetSize(moveW, moveW)
								m:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -150 - (2 - j) * (moveW + 2), -top + 1)
								m:Show()
							end
							right = 150 + 2 * (moveW + 2) + 4
						end
						r.label:SetText(d[1])
						r.value:SetText(d[2] or "")
						r.label:ClearAllPoints()
						r.label:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
						r.label:SetPoint("RIGHT", holder, "TOPRIGHT", -right, 0)
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
			r.mid:SetWordWrap(false) -- 3.2 (user): "Alterac Mountains" wrapped in its fixed 110 px
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
					r.right:SetText(d[3] or "")
					r.mid:SetText(d[2] or "")
					r.mid:ClearAllPoints()
					r.mid:SetPoint("TOPLEFT", holder, "TOPLEFT", leftW, -y)
					-- the middle text takes the room up to the right text (at least midW)
					local rightUsed = (d[3] or "") ~= "" and (r.right:GetStringWidth() or 0) + math.floor(10 * k) or 0
					r.mid:SetWidth(math.max(width - leftW - rightUsed, midW))
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

api.statsLines = lines -- 3.2: Statistics > Dungeon runs (DungeonRuns.lua)

---------------------------------------------------------------------------------------------------------------------
-- The pages (declared by Config.lua: api.declareStatsPages(kit))
---------------------------------------------------------------------------------------------------------------------
local GREEN, RED = { 0.35, 0.85, 0.45 }, { 1, 0.42, 0.32 }

-- 3.2: the numbers of the period picked on the page ("< This session >"); before, all-time and two session tiles
local function overviewTiles()
	local _, total, q = api.statsPeriodTotals(periodOf("overview"), allOf("overview"))
	if not q then return {} end
	local avg = q.timed > 0 and clock(q.timeSum / q.timed) or "-"
	-- 3.1.2: no "Fastest quest"; at the level cap no experience tiles
	local maxed = atMaxLevel()
	local out = { { ICONS.check, short(q.questsDone), "Completed quests" } }
	if not maxed then out[#out + 1] = { ICONS.star, short(q.questXPDone), "Experience from quests" } end
	out[#out + 1] = { ICONS.clock, avg, "Avg. quest time" }
	out[#out + 1] = { ICONS.trash, tostring(q.abandoned), "Abandoned" }
	if not maxed then out[#out + 1] = { ICONS.xp, short(q.xp), "Experience gained" } end
	out[#out + 1] = { ICONS.session, total >= 1 and long(total) or "-", "Time played" }
	return out
end

-- 3.1.2 gold: from quests and off mobs, this run and this session
local function goldTiles()
	local _, _, g = api.statsPeriodTotals(periodOf("overview"), allOf("overview"))
	if not g then return {} end
	local function tile(c, label) return { coinIcon(c), money(c), label } end
	return {
		tile(g.goldQuests, "Gold from quests"),
		tile(g.goldLoot, "Gold from mobs"),
		tile(g.goldAH, "Gold from AH"),
		tile(g.goldMail, "Gold from mail"),
		tile(g.goldVendor, "Gold from vendors"),
		tile(g.goldTrade, "Gold from trades"),
		tile(earned(g), "Gold in total"),
		tile(g.goldSpent, "Gold spent"),
	}
end

local function levelBar()
	if not isMe() then
		local r = viewed()
		return { { ("Level %d"):format(math.max(topLevel(r), 1)), r and r.name and tostring(r.name) or "", 0 } }
	end
	local xp, max = readXP()
	local level = UnitLevel("player") or 1
	-- 3.1.2: at the level cap there is no next level: a full bar, no experience numbers
	if atMaxLevel() then return { { ("Level %d"):format(level), "maximum level", 1 } } end
	if not (xp and max and max > 0) then return { { ("Level %d"):format(level), "", 0 } } end
	local fmt = BreakUpLargeNumbers or tostring
	return { { ("Level %d"):format(level), ("%s / %s"):format(fmt(xp), fmt(max)), xp / max } }
end

local function zoneBars()
	local _, _, sums = api.statsPeriodTotals(periodOf("overview"), allOf("overview"))
	if not sums then return {} end
	local list = {}
	for zone, n in pairs(sums.zones) do list[#list + 1] = { zone, tonumber(n) or 0 } end
	table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	local top = list[1] and list[1][2] or 1
	local out = {}
	for i = 1, math.min(6, #list) do out[i] = { list[i][1], tostring(list[i][2]), list[i][2] / top } end
	return out
end

local function runTiles()
	local _, total, sums = api.statsPeriodTotals(periodOf("run"), allOf("run"))
	if not sums then return {} end
	return {
		{ ICONS.clock, clock(total), "Recorded" },
		{ ICONS.check, tostring(sums.quests), "Completed quests" },
		{ ICONS.star, sums.xp > 0 and ("%d%%"):format(math.floor(sums.questXP / sums.xp * 100 + 0.5)) or "-", "XP from quests" },
		-- 3.1.2: gold from quests and off mobs, the whole run
		{ coinIcon(earned(sums)), money(earned(sums)), "Gold acquired" },
		{ ICONS.deaths, tostring(sums.deaths), "Deaths" },
		{ ICONS.jump, short(sums.jumps), "Jumps" },
		-- 3.1.2: time inside a dungeon; 3.2 raids and battlegrounds (they overlap the bars: combat, running and so on in there)
		{ ICONS.dungeon, sums.dungeon >= 1 and clock(sums.dungeon) or "-", "In dungeons" },
		{ ICONS.raid, sums.raid >= 1 and clock(sums.raid) or "-", "In raids" },
		{ ICONS.pvp, sums.pvp >= 1 and clock(sums.pvp) or "-", "In battlegrounds" },
	}
end

local function pctText(v, total)
	return ("%s  %d%%"):format(clock(v), total > 0 and math.floor(v / total * 100 + 0.5) or 0)
end
-- 3.2: the saved order of ids, with new ids (not saved yet) at their default place at the end
local function ordered(defaults, saved)
	local out, seen, valid = {}, {}, {}
	for _, id in ipairs(defaults) do valid[id] = true end
	for _, id in ipairs(type(saved) == "table" and saved or {}) do
		if valid[id] and not seen[id] then out[#out + 1] = id; seen[id] = true end
	end
	for _, id in ipairs(defaults) do
		if not seen[id] then out[#out + 1] = id; seen[id] = true end
	end
	return out
end
local function groupIds()
	local ids = {}
	for _, g in ipairs(TIME_GROUPS) do ids[#ids + 1] = g[1] end
	return ordered(ids, db and db.timeGroupOrder)
end
local function kindIds()
	local ids = {}
	for _, g in ipairs(TIME_GROUPS) do for _, kind in ipairs(g[3]) do ids[#ids + 1] = kind end end
	return ordered(ids, db and db.timeKindOrder)
end
-- swap id with its nearest shown neighbour (dir -1 up, 1 down) in the saved list
local function moveId(field, all, shown, id, dir)
	local pos
	for i, v in ipairs(shown) do if v == id then pos = i end end
	local other = pos and shown[pos + dir]
	if not other then return end
	local list = {}
	for i, v in ipairs(all) do list[i] = v end
	local a, b
	for i, v in ipairs(list) do
		if v == id then a = i elseif v == other then b = i end
	end
	if a and b then list[a], list[b] = list[b], list[a] end
	db[field] = list
end
-- the groups in the player's order, each with its states (only those with time), as
-- { id, name, seconds, { { kind, seconds }, ... } }
local function timeGroups(t)
	local kinds = kindIds()
	local rank = {}
	for i, kind in ipairs(kinds) do rank[kind] = i end
	local byId = {}
	for _, g in ipairs(TIME_GROUPS) do byId[g[1]] = g end
	local out = {}
	for _, id in ipairs(groupIds()) do
		local g = byId[id]
		local members, sum = {}, 0
		for _, kind in ipairs(g[3]) do
			local v = tonumber(t[kind]) or 0
			if v >= 1 then members[#members + 1] = { kind, v }; sum = sum + v end
		end
		table.sort(members, function(x, y) return rank[x[1]] < rank[y[1]] end)
		if sum >= 1 then out[#out + 1] = { id, g[2], sum, members } end
	end
	return out, kinds
end
api.statsTimeGroups = timeGroups
api.statsMoveTime = moveId

local function timeBars()
	local t, total, sums = api.statsPeriodTotals(periodOf("run"), allOf("run"))
	if not sums then return {} end
	local groups, kinds = timeGroups(t)
	local shownGroups = {}
	for _, g in ipairs(groups) do shownGroups[#shownGroups + 1] = g[1] end
	local allGroups = groupIds()
	local out = {}
	for _, g in ipairs(groups) do
		local gid = g[1]
		local row = { g[2], pctText(g[3], total), total > 0 and g[3] / total or 0, key = "g:" .. gid, open = true, kids = {} }
		row.move = function(dir) moveId("timeGroupOrder", allGroups, shownGroups, gid, dir) end
		local shownKinds = {}
		for _, m in ipairs(g[4]) do shownKinds[#shownKinds + 1] = m[1] end
		for _, m in ipairs(g[4]) do
			local k, v = m[1], m[2]
			local d = { KIND_NAMES[k], pctText(v, total), total > 0 and v / total or 0 }
			d.move = function(dir) moveId("timeKindOrder", kinds, shownKinds, k, dir) end
			-- NPCs: a dropdown by window; the percent and bar are of the NPC time
			if k == "npc" then
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
			row.kids[#row.kids + 1] = d
		end
		out[#out + 1] = row
	end
	-- 3.2 (user): Well Rested is the last line of Downtime, not in its sum and not moved with its lines: it stays on
	-- while you run, fight and shop, so this time is also in the other lines. (At a campfire is a normal state.)
	local rested = tonumber(sums.rested) or 0
	if rested >= 1 then
		local down
		for _, row in ipairs(out) do if row.key == "g:downtime" then down = row end end
		if not down then
			down = { "Downtime", pctText(0, total), 0, key = "g:downtime", open = true, kids = {} }
			out[#out + 1] = down
		end
		if rested >= 1 then down.kids[#down.kids + 1] = { "Well Rested", pctText(rested, total), total > 0 and rested / total or 0 } end
	end
	if #out == 0 then out[1] = { periodOf("run") == "all" and "Nothing recorded yet" or "Nothing recorded in this period yet", "", 0 } end
	return out
end
api.statsTimeBars = timeBars -- (tests)

local function worthALook()
	local r = viewed()
	if not r then return {} end
	local period = periodOf("run")
	local t, total = api.statsPeriodTotals(period, allOf("run"))
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
	if period ~= "all" or allOf("run") then return out end
	-- the slowest finished level, against its neighbours (All-time of this character: levels are not kept by period)
	local slowest, slowT
	for level in pairs(r.levels) do
		local took, now = api.statsLevelTime(r, level)
		if took and not now and (not slowT or took > slowT) then slowest, slowT = level, took end
	end
	if slowest then out[#out + 1] = { ("Lv %d"):format(slowest), clock(slowT), "your slowest level so far" } end
	return out
end

local function levelLines()
	local r = viewed()
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
	local r = viewed()
	if not r then return { rows = {} } end
	local other = compareRun()
	local rows, top, maxT = {}, isMe() and UnitLevel("player") or math.max(topLevel(r), 1), 0
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

-- 3.2 the period switcher: "<  This session  >" in a control box; a click on an arrow (or the name: on) steps
local function periodSwitch(page, onChange)
	return function(holder, kit)
		local C = kit.C
		local box = CreateFrame("Frame", nil, holder)
		kit.controlBg(box)
		local label = kit.text(box, "GameFontHighlight", 1.1, C.value)
		label:SetPoint("CENTER")
		local function arrowButton(dir)
			local b = CreateFrame("Button", nil, box)
			b.arrow = kit.arrow(b, dir < 0, 12)
			b.arrow:SetPoint("CENTER")
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 0.9, 0.6, 0.10)
			b:SetScript("OnClick", function()
				stepPeriod(page, dir)
				if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then (root.playSound or pcall)(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
				if onChange then onChange() end
			end)
			b:SetScript("OnEnter", function(self)
				if not GameTooltip then return end
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(dir < 0 and "Previous period" or "Next period")
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			return b
		end
		local left, right = arrowButton(-1), arrowButton(1)
		left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
		right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
		local w = {}
		function w.draw(width)
			local k = kit.ts()
			local h = math.floor(26 * k + 0.5)
			local bw = math.min(math.floor(230 * k + 0.5), math.max(width, 120))
			box:ClearAllPoints()
			box:SetPoint("TOP", holder, "TOP", 0, 0)
			box:SetSize(bw, h)
			left:SetWidth(h); right:SetWidth(h)
			label:SetText(periodName(periodOf(page)))
			return h
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
		k.help("another character on this account, or this character's previous run under the same name")
	end
	local function viewChoice(page)
		k.choice("Character", function() return api.statsViewOptions() end,
			function() return viewKey() == runKey and "me" or viewKey() end,
			refreshAfter(function(v) db.statsView = v end),
			page and function() return not allOf(page) end or nil)
		k.help("whose statistics these pages show; recording is always for the character you play")
	end

	k.page("statsoverview", "stats", "Overview")
	k.pageByKey.statsoverview.cardTitle = "Your quests in numbers"
	k.custom("Period this session last session this week this month all-time", periodSwitch("overview", k.refresh), true)
	viewChoice("overview")
	k.check("All characters", function() return db.statsAllOverview == true end,
		function(v) db.statsAllOverview = v and true or false; k.refresh() end)
	k.help("adds up every character on this account (older runs of a re-rolled name are left out)")
	k.custom("Completed quests experience quest time session abandoned", tiles(overviewTiles, 8), true)
	k.heading("Gold")
	k.custom("Gold from quests mobs auction house ah mail vendors trades spent money total", tiles(goldTiles, 8), true)
	k.heading("Level progress")
	k.custom("Level progress", bars(levelBar, 1), true)
	k.heading("Top quest zones")
	k.custom("Top quest zones", lines(function()
		local list = zoneBars()
		local out = {}
		for i, d in ipairs(list) do out[i] = { tostring(i) .. ".", d[1], d[2] } end
		return out
	end, "Hand in a quest in this period and its zone shows here.", 6), true)

	k.page("statsoptions", "stats", "Options")
	k.check("Record statistics", function() return db.statsOn ~= false end,
		function(v) db.statsOn = v and true or false end)
	k.help("quests, experience, deaths and where your time goes, per character")
	k.check("Level-up line in chat", function() return db.levelAnnounce ~= false end,
		function(v) db.levelAnnounce = v and true or false end)
	k.help("on a new level: how long the last level took and your total time played (only you see it)")
	-- 3.2 (user)
	k.check("Level-up banner", function() return db.levelBanner ~= false end,
		function(v) db.levelBanner = v and true or false end)
	k.help("a gold banner at the top of the screen on a new level (/ftp levelup: a test)")
	-- 3.2
	k.check("Session summary at login", function() return db.sessionSummary ~= false end,
		function(v) db.sessionSummary = v and true or false end)
	k.help("a chat line at login with what you did last time (/ftp session: this session)")
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
	k.custom("Period this session last session this week this month all-time", periodSwitch("run", k.refresh), true)
	viewChoice("run")
	k.check("All characters", function() return db.statsAllRun == true end,
		function(v) db.statsAllRun = v and true or false; k.refresh() end)
	k.help("adds up every character on this account (older runs of a re-rolled name are left out)")
	k.custom("Recorded completed quests xp from quests deaths jumps in dungeons raids battlegrounds", tiles(runTiles, 12), true)
	k.heading("Where the time went")
	k.check("Change the order", function() return db.timeReorder == true end,
		function(v) db.timeReorder = v and true or false; k.refresh() end)
	k.help("up and down buttons on each group and line; the order is kept, also for Copy for Discord")
	k.buttons("Reset the order", {
		{ "Reset the order", function() db.timeGroupOrder, db.timeKindOrder = nil, nil; k.refresh() end, 140 },
	})
	k.custom("Fighting travel windows doing things downtime camp and rest campfire well rested combat running mounted swimming jumping falling crafting gathering eating drinking looting casting flight npcs "
		.. "vendors trainers bank mailbox auction map quest log loading screens dead afk standing",
		bars(timeBars, #BAR_KINDS + #TIME_GROUPS + 3, function() k.refresh() end, function() return db.timeReorder == true end), true)
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
	viewChoice()
	compareChoice()
	k.custom("Played average level fastest slowest ahead behind", tiles(splitTiles, 5), true)
	k.heading("Each level")
	k.custom("Level splits", splitBars("Level up once and the first split shows here."), true)
end
