-- ForeverTrackerPlus: our own tracker, phase 5 (OWN_TRACKER_PLAN.md): a Battlegrounds section with timer bars.
--
-- User: "add a Battlegrounds section to the tracker, and add timer bars" like the ones other battleground addons show,
-- without needing another addon. Our own code; only game facts (event names, map node art numbers, timer lengths,
-- widget IDs) were looked up.
--
--   battlegrounds  by GetInstanceInfo's instance ID: Warsong Gulch, Arathi Basin, Alterac Valley, Eye of the Storm, and
--                  Darkspear Islands (WoW Forever: Eye of the Storm with other art, so its rules; zone 16606, user)
--   start          START_TIMER, else the "begins in 1 minute / 30 seconds" battleground message: "Battle begins"
--   nodes          AREA_POIS_UPDATED: a map node whose art turns to "taken by Alliance / Horde" starts a bar for the
--                  time until it is captured (Arathi Basin 60 s, Alterac Valley 300 s on Forever); its art changing
--                  again stops it. The first look after you enter only notes the nodes (their start time is unknown).
--   warnings       a node of your side taken: a chat line and a sound, again 10 s before it is lost (db.ownBgWarn)
--   flags          the battleground message "... captured the ...": "Flag respawns" (Warsong Gulch 12 s; Eye of the
--                  Storm and Darkspear Islands 21 s, also on "taken the flag"); who holds each flag, from the
--                  "picked up / taken / dropped / returned / captured" messages (English)
--   queues         each battleground queue: time waited (against the estimate), the time left to enter on an invite
--   score          the score bars at the top of the screen (a double status bar widget) and each side's points per
--                  second: in Arathi Basin from the bases held (widget 1645, fixed points per base count), else
--                  measured over the last 30 s (a flag capture's jump left out); who wins, when, the end score. The
--                  bar is set again only when the bases change or its end moves by more than 3 s
--   time left      a top-of-screen widget whose text holds the time left ("12 min", "4:30")
--   draw           Frame.lua draws the section as a block above the Quests header; each timer line gets a bar here
--                  (faction color, time at the right), moved on by a light ticker while bars run
--   /qt bg         what the game reports here: instance, map, nodes with their art numbers, widgets, timers
--
-- RULE (tests/own_tracker_rules_test.lua): nothing here touches Blizzard's frames; reads and our own frames only.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function now() return GetTime and GetTime() or 0 end
local function try(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

-- instance IDs (GetInstanceInfo's 8th value)
local KINDS = {
	[489] = "wsg", [2106] = "wsg", [726] = "wsg",
	[529] = "ab", [2107] = "ab", [1681] = "ab", [2177] = "ab",
	[30] = "av", [2197] = "av",
	[566] = "eots", [968] = "eots",
	[16606] = "eots", -- Darkspear Islands (user)
}
local NAMES = { ["Darkspear Islands"] = "eots" }
local isRetail = WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
-- seconds from "taken" to "captured" for a node
local function captureTime(kind, id, name)
	if kind == "ab" then return 60 end
	-- 3.2 (user): Darkspear Islands' bases (Cove, Tower, Camp, Ruins) are taken as Arathi Basin's: 60 s
	if id == 16606 or name == "Darkspear Islands" then return 60 end
	if kind == "av" then
		if id == 2197 then return 241 end
		return isRetail and 242 or 300
	end
end
local FLAG_RESPAWN = { wsg = 12, eots = 21 }
-- each bar's icon (game art; which one goes with which bar looked up from Capping, user): a map node's own art for
-- node bars (the map's POI icon sheet, the "taken" art), the flag art from the same sheet, item and spell icons else
local POI_SHEET, FLAG_POI = 136441, 45 -- Interface\Minimap\POIIcons, its flag
local ICON = {
	start = 618859, -- achievement_challengemode_platinum
	time = 134420, -- inv_misc_rune_07
	flag = 134420, -- without the map's icon sheet
	enter = 132327, -- ability_townwatch
	Alliance = 132486, -- inv_bannerpvp_02
	Horde = 132485, -- inv_bannerpvp_01
}
local QUEUE_ICONS = { ["Warsong Gulch"] = 134420, ["Arathi Basin"] = 133282, ["Alterac Valley"] = 133308,
	["Darkspear Islands"] = 237427 }
local function queueIcon(map) return QUEUE_ICONS[map] or 134400 end -- else a question mark
api.bgIcons = ICON -- for tests
-- map node art (textureIndex) that means "taken, being captured": Alliance / Horde pairs (graveyard, tower, mine,
-- lumber mill, blacksmith, farm, stables, workshop, hangar, docks, refinery, market, ruins, shrine)
local CONTESTED = {}
for _, pair in ipairs({ { 4, 14 }, { 9, 12 }, { 17, 19 }, { 22, 24 }, { 27, 29 }, { 32, 34 }, { 37, 39 }, { 137, 139 },
	{ 142, 144 }, { 147, 149 }, { 152, 154 }, { 208, 209 }, { 213, 214 }, { 218, 219 } }) do
	CONTESTED[pair[1]], CONTESTED[pair[2]] = "Alliance", "Horde"
end
api.bgContestedArt = CONTESTED -- for /ftp bg and tests
-- the score bars at the top of the screen (double status bar widgets), the first one shown is used
local SCORE_WIDGETS = { 7467, 1671, 2074, 5153, 1689 }
local SCORE_JUMP = 65 -- a bigger step in one second is a flag capture, not the bases' points


local bg -- { kind, id, name } while in a battleground
local bars = {} -- { key, label, side, start, dur, up = counts up, fill = fixed fill, warn = our node }
local nodes = {} -- node name -> its last art number
local carriers = {} -- "Alliance" / "Horde" flag -> who holds it
local queues = {} -- queue bars, outside the battleground too
local scores = {} -- { t, a, h, da, dh } one per second
local ticker, poller
local lastBases -- "Alliance:Horde" bases held at the last score look
local stepSeen = {} -- side -> { score, at }: when its score last went up (the win timer)
-- 3.2 animations (user): a dropped flag's time, its pop done, each carrier line's font string, the last shake
local dropped, dropPinged, carrierFs, lastShake = {}, {}, {}, {}
local function animOk(kind) return api.animEnabled and api.animEnabled(kind) or false end
local carrierTick, resultTick -- (below)

local function changed()
	if api.ownBgChanged then api.ownBgChanged() end
end
local function db() return ns.db or {} end
local function mySide()
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return (f == "Alliance" or f == "Horde") and f or nil
end

local function find(list, key) for i, b in ipairs(list) do if b.key == key then return b, i end end end
local function stopBar(key)
	local b, i = find(bars, key)
	if b and b.ending then return end -- a captured base flashes out first (the ticker takes it away)
	if i then table.remove(bars, i); changed() end
end
-- 3.2 (user): a base captured: its bar stays 0.8 s, full, and flashes in its side's colour (Animations.lua)
local function endWithFlash(b)
	if not b or b.ending or not b.key:find("^node:") or not animOk("bgcapture") then return false end
	b.ending, b.fill = now(), 1
	changed()
	return true
end
local function startBar(key, label, side, dur, extra)
	if not dur or dur <= 0 then return end
	local _, i = find(bars, key)
	if i then table.remove(bars, i) end
	local b = { key = key, label = label, side = side, start = now(), dur = dur }
	for k, v in pairs(extra or {}) do b[k] = v end
	bars[#bars + 1] = b
	if ticker then ticker:Show() end
	changed()
	return b
end
-- a bar whose end moves (score, time left): kept, its end set again; drawn anew only when it is new
local function setBar(key, label, side, dur, extra)
	local b = find(bars, key)
	if not b then return startBar(key, label, side, dur, extra) end
	local relabel = b.label ~= label or b.side ~= side
	if b.side ~= side and b.side and side ~= "none" then b.swapFrom, b.swapAt = b.side, now() end -- 3.2: the flip
	b.label, b.side, b.start, b.dur = label, side, now(), dur
	for k, v in pairs(extra or {}) do b[k] = v end
	if relabel then changed() end
	return b
end
api.bgStartBar, api.bgStopBar = startBar, stopBar -- for tests

local function left(b) return math.max(b.dur - (now() - b.start), 0) end
local function clock(s)
	s = math.max(math.ceil(s), 0)
	return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function warn(text)
	if db().ownBgWarn == false then return end
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff4040" .. text .. "|r") end
	if PlaySound then (root.playSound or pcall)(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959) end
end
api.bgWarnForTests = warn

---------------------------------------------------------------------------------------------------------------------
-- Where we are
local function readPlace()
	local name, itype, _, _, _, _, _, id
	if GetInstanceInfo then name, itype, _, _, _, _, _, id = GetInstanceInfo() end
	if isSecret(name) then name = nil end
	local kind = (id and KINDS[id]) or (name and NAMES[name])
	if not kind and itype == "pvp" then kind = "other" end
	if not kind then return nil end
	return { kind = kind, id = id, name = type(name) == "string" and name or "Battleground" }
end

local function mapPOIs()
	local out = {}
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local poi = C_AreaPoiInfo
	if not (map and poi and poi.GetAreaPOIForMap and poi.GetAreaPOIInfo) then return out, map end
	local ok, ids = pcall(poi.GetAreaPOIForMap, map)
	if not ok or type(ids) ~= "table" then return out, map end
	for _, pid in ipairs(ids) do
		local okI, info = pcall(poi.GetAreaPOIInfo, map, pid)
		if okI and type(info) == "table" and type(info.name) == "string" and not isSecret(info.name) then
			out[#out + 1] = { id = pid, name = info.name, art = info.textureIndex, atlas = info.atlasName }
		end
	end
	return out, map
end

-- a node's art changed: taken (a bar to its capture) or settled (the bar goes)
local function scanNodes(first)
	if not bg then return end
	local dur = captureTime(bg.kind, bg.id, bg.name)
	if not dur then return end
	local mine = mySide()
	for _, p in ipairs((mapPOIs())) do
		local side = CONTESTED[p.art]
		local before = nodes[p.name]
		if not first and before ~= nil and p.art ~= before then
			if side then
				-- taken by the other side from ours: a warning now and 10 s before it is lost
				local ours = mine and side ~= mine
				startBar("node:" .. p.name, p.name, side, dur, { warn = ours or nil, poi = p.art })
				if ours then warn(("%s is being taken by the %s!"):format(p.name, side)) end
			else
				local nb = find(bars, "node:" .. p.name)
				if not (nb and left(nb) <= 5 and endWithFlash(nb)) then stopBar("node:" .. p.name) end
			end
		elseif not side and before ~= nil then
			stopBar("node:" .. p.name)
		end
		nodes[p.name] = p.art or false
	end
end
api.bgScanNodes = scanNodes -- for tests

local function enter()
	local was = bg and bg.kind
	bg = readPlace()
	if not bg or (was and bg.kind ~= was) then
		for i = #bars, 1, -1 do bars[i] = nil end
		for k in pairs(nodes) do nodes[k] = nil end
		for k in pairs(carriers) do carriers[k] = nil end
		for i = #scores, 1, -1 do scores[i] = nil end
		lastBases = nil
		for k in pairs(stepSeen) do stepSeen[k] = nil end
		for _, t in ipairs({ dropped, dropPinged, carrierFs, lastShake }) do for k in pairs(t) do t[k] = nil end end
	end
	if bg then scanNodes(true) end
	if poller and (bg or #queues > 0) then poller:Show() end
	changed()
end
api.bgEnter = enter -- for tests

-- "The battle for X begins in 1 minute." / "... 30 seconds." (and "2 minutes"): the seconds, or nil
local function countdownFrom(msg)
	local m = msg:lower()
	if not m:find("begin", 1, true) then return nil end
	local n, unit = m:match("(%d+)%s*(%a+)")
	n = tonumber(n)
	if not n then return nil end
	if unit:find("^minute") then return n * 60 end
	if unit:find("^second") then return n end
end
api.bgCountdownFrom = countdownFrom -- for tests

-- which flag a message is about: "Alliance" / "Horde" flag named in it, else (Eye of the Storm) the one flag
local function flagOf(m, event)
	if m:find("alliance flag", 1, true) then return "Alliance" end
	if m:find("horde flag", 1, true) then return "Horde" end
	if bg and bg.kind == "eots" then return "Flag" end
	-- "X captured the flag" without its name: the one the other side held
	if event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then return "Horde" end
	if event == "CHAT_MSG_BG_SYSTEM_HORDE" then return "Alliance" end
end
local function setCarrier(flag, who)
	if flag and who then dropped[flag] = nil end
	if flag and carriers[flag] ~= who then carriers[flag] = who; changed() end
end
-- 3.2 (user): a dropped flag shows "dropped" (its line pops once) until it is picked up or returned
local function setDropped(flag)
	if not flag then return end
	carriers[flag] = nil
	dropped[flag] = now()
	changed()
end

-- 3.2 (user: Darkspear Islands' base timers did not show): a base is also read from the battleground messages,
-- whatever its map art: "X has assaulted the Ruins!", "X claims the Camp!" start its bar (the side: the message's
-- channel), "The Horde has taken the Ruins!" ends it (captured), "X has defended the Tower!" stops it.
-- Its name is the map's name for that base when one matches ("Cove": "Shipwrecked Cove").
local function baseName(text)
	local low = text:lower()
	for name in pairs(nodes) do
		local n = name:lower()
		if n == low or n:find(low, 1, true) or low:find(n, 1, true) then return name end
	end
	return (text:gsub("^%l", string.upper))
end
local function onBaseMessage(event, msg)
	local side = event == "CHAT_MSG_BG_SYSTEM_HORDE" and "Horde" or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" and "Alliance" or nil
	local assault = msg:match("[Aa]ssaulted the (.-)[!%.]") or msg:match("[Cc]laims the (.-)[!%.]")
	local taken = msg:match("[Hh]as taken the (.-)[!%.]")
	local defended = msg:match("[Dd]efended the (.-)[!%.]")
	if taken and taken:lower():find("flag", 1, true) then taken = nil end
	local dur = captureTime(bg.kind, bg.id, bg.name)
	if assault and side and dur then
		local name = baseName(assault)
		if not find(bars, "node:" .. name) then
			local mine = mySide()
			local ours = mine and side ~= mine
			startBar("node:" .. name, name, side, dur, { warn = ours or nil })
			if ours then warn(("%s is being taken by the %s!"):format(name, side)) end
		end
		return true
	end
	if taken or defended then
		local b = find(bars, "node:" .. baseName(taken or defended))
		if b and not (taken and endWithFlash(b)) then stopBar(b.key) end
		return true
	end
end
api.bgBaseMessage = onBaseMessage -- (tests)

local function onSystem(event, msg)
	if not bg or type(msg) ~= "string" or isSecret(msg) then return end
	local m = msg:lower()
	if event ~= "CHAT_MSG_BG_SYSTEM_NEUTRAL" and onBaseMessage(event, msg) then return end
	if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
		local s = countdownFrom(msg)
		if s then startBar("start", "Battle begins", "none", s, { icon = ICON.start })
		elseif m:find("has begun", 1, true) or m:find("let the battle", 1, true) then stopBar("start") end
		if bg.kind == "eots" and m:find("dropped", 1, true) then setDropped("Flag") end
		return
	end
	-- who holds a flag: "Grunt picked up the Alliance flag!", "The Alliance Flag was picked up by Grunt!", "Grunt has
	-- taken the flag!" (Eye of the Storm); "dropped", "returned", "captured" free it
	local who = msg:match("^(.-) picked up the ") or msg:match("[Pp]icked up by (.-)!?$")
		or (bg.kind == "eots" and msg:match("^(.-) has taken the flag"))
	if who and who ~= "" then setCarrier(flagOf(m, event), who) end
	if m:find("dropped", 1, true) then
		setDropped(flagOf(m, event))
	elseif m:find("returned", 1, true) or m:find("captured the", 1, true) then
		local flag = flagOf(m, event)
		if flag then dropped[flag] = nil end
		setCarrier(flag, nil)
	end
	local respawn = FLAG_RESPAWN[bg.kind]
	if respawn and (m:find("captured the", 1, true) or (bg.kind == "eots" and m:find("taken the flag", 1, true)
		and not who)) then
		startBar("flag", "Flag respawns", "none", respawn, { poi = FLAG_POI, icon = ICON.flag })
	end
end
api.bgSystemMessage = onSystem -- for tests

---------------------------------------------------------------------------------------------------------------------
-- Queues (outside the battleground too)
local function readQueues()
	local seen = {}
	local n = (GetMaxBattlefieldID and tonumber((GetMaxBattlefieldID()))) or 0
	for i = 1, n do
		local ok, status, map, _, _, suspended = try(GetBattlefieldStatus, i)
		if ok and type(map) == "string" and not isSecret(map) and not isSecret(status) then
			local key = "queue:" .. i
			if status == "queued" then
				local _, waited = try(GetBattlefieldTimeWaited, i)
				local _, est = try(GetBattlefieldEstimatedWaitTime, i)
				waited, est = (tonumber(waited) or 0) / 1000, (tonumber(est) or 0) / 1000
				local b = find(queues, key)
				if not b or b.up ~= true then
					if b then for j, q in ipairs(queues) do if q == b then table.remove(queues, j) end end end
					b = { key = key, up = true }
					queues[#queues + 1] = b
					changed()
				end
				-- 3.2 (user): a paused queue does not count on; its time stays where it stopped
				if suspended and not isSecret(suspended) then
					b.frozen = b.frozen or waited
					waited = b.frozen
				else
					b.frozen = nil
				end
				local label = map .. " queue" .. (b.frozen and " (paused)" or "")
				if b.label and b.label ~= label then changed() end
				b.label, b.side, b.start, b.dur = label, "queue", now() - waited, est
				b.icon = queueIcon(map)
				seen[key] = true
			elseif status == "confirm" then
				local _, s = try(GetBattlefieldPortExpiration, i)
				s = tonumber(s)
				if s and s > 0 then
					local b = find(queues, key)
					if not b or b.up then
						if b then for j, q in ipairs(queues) do if q == b then table.remove(queues, j) end end end
						b = { key = key }
						queues[#queues + 1] = b
						changed()
					end
					b.label, b.side, b.start, b.dur = "Enter " .. map, "none", now(), s
					b.icon = ICON.enter
					b.confirm = true -- 3.2: it bounces, and pulses red in its last 15 s
					seen[key] = true
				end
			end
		end
	end
	for i = #queues, 1, -1 do
		if not seen[queues[i].key] then table.remove(queues, i); changed() end
	end
	if #queues > 0 and ticker then ticker:Show() end
end
api.bgReadQueues = readQueues -- for tests

---------------------------------------------------------------------------------------------------------------------
-- Score estimate and time left (once a second in a battleground)
local function readScore()
	local w = C_UIWidgetManager
	if not (w and w.GetDoubleStatusBarWidgetVisualizationInfo) then return end
	for _, id in ipairs(SCORE_WIDGETS) do
		local ok, info = pcall(w.GetDoubleStatusBarWidgetVisualizationInfo, id)
		if ok and type(info) == "table" and info.shownState ~= 0 then
			local a, h = tonumber(info.leftBarValue), tonumber(info.rightBarValue)
			local max = tonumber(info.leftBarMax) or tonumber(info.rightBarMax)
			if a and h and max and max > 0 and not isSecret(info.leftBarValue) then return a, h, max, id end
		end
	end
end
-- bases each side holds, from the base icons at the top of the screen (Arathi Basin on Forever: widget 1645, an icon
-- per base, state 2 = held): Alliance, Horde, or nil
local BASES_WIDGET = 1645
local function readBases()
	local w = C_UIWidgetManager
	if not (w and w.GetDoubleStateIconRowVisualizationInfo) then return end
	local ok, info = pcall(w.GetDoubleStateIconRowVisualizationInfo, BASES_WIDGET)
	if not ok or type(info) ~= "table" or info.shownState == 0 then return end
	local function held(icons)
		local n = 0
		for _, i in ipairs(type(icons) == "table" and icons or {}) do if i.iconState == 2 then n = n + 1 end end
		return n
	end
	if type(info.leftIcons) ~= "table" then return end
	return held(info.leftIcons), held(info.rightIcons)
end
-- points per second for 0..5 bases held (Arathi Basin on Forever; a game fact)
local AB_RATE = { [0] = 0, 0.8333, 1.1111, 1.6667, 3.3333, 30 }
local AB_STEP = 10 -- the score goes up 10 at a time (user)
-- 3.2 (user: "the win timer is off by 3 seconds"): the score goes up 10 at a time, once each AB_STEP / rate seconds;
-- the next step comes one interval after the last one seen, not one interval from now. When each side's score last
-- went up is kept (the score is looked at 5 times a second), so the time is to the step, not up to a step too long.
local function noteStep(side, score)
	local s = stepSeen[side]
	-- (the first look: taken as a step now; the next step seen sets it right)
	if not s or s.score ~= score then stepSeen[side] = { score = score, at = now() } end
end
-- seconds to the next step of this side (interval: seconds a step)
local function firstStep(side, interval)
	local s = stepSeen[side]
	if not s or not s.at then return interval end
	local wait = interval - ((now() - s.at) % interval)
	if wait < 1e-6 then return interval end
	return wait
end
api.bgStepSeenForTests = stepSeen
-- the bar is set again only when the bases change or its end moves by more than half a second (Arathi Basin; else
-- 3 s): it counts down steadily
local function showScore(side, secs, fa, fh, fill, force)
	local b = find(bars, "score")
	local slack = (bg and bg.kind == "ab") and 0.5 or 3 -- (an estimate from the last 30 s moves more)
	if b and not force and math.abs(left(b) - secs) <= slack then b.fill = fill return end
	-- 3.2 (user): your side's score on the left ("Alliance wins 1160-2000" for a Horde player)
	local first, second = fa, fh
	if mySide() == "Horde" then first, second = fh, fa end
	setBar("score", ("%s wins %d-%d"):format(side, first, second), side, secs, { fill = fill, icon = ICON[side] })
end
local function scoreTick()
	local a, h, max = readScore()
	if not a then stopBar("score") return end
	-- Arathi Basin: the exact rate from the bases held, at once (user: Capping's estimate is steady, ours jumped)
	local ba, bh = nil, nil
	if bg and bg.kind == "ab" then ba, bh = readBases() end
	if ba and AB_RATE[ba] and AB_RATE[bh] then
		-- the score goes up in steps of 10 (user): the winner needs whole steps, the loser gets only whole steps by then
		local ra, rh = AB_RATE[ba], AB_RATE[bh]
		noteStep("Alliance", a); noteStep("Horde", h)
		local function steps(score) return math.ceil((max - score) / AB_STEP) end
		-- the time of the last step needed: the first step, then one interval each
		local function finish(sideName, score, r)
			if r <= 0 then return math.huge end
			local n, interval = steps(score), AB_STEP / r
			if n <= 0 then return 0 end
			return firstStep(sideName, interval) + (n - 1) * interval
		end
		local ta, th = finish("Alliance", a, ra), finish("Horde", h, rh)
		if ta == math.huge and th == math.huge then stopBar("score") return end
		local side, secs = "Alliance", ta
		if th < ta then side, secs = "Horde", th end
		-- the steps a side gets by then
		local function at(sideName, score, r)
			if r <= 0 then return score end
			local interval = AB_STEP / r
			local first = firstStep(sideName, interval)
			if secs + 1e-6 < first then return score end
			return math.min(max, score + (math.floor((secs - first) / interval + 1e-6) + 1) * AB_STEP)
		end
		local fa, fh = at("Alliance", a, ra), at("Horde", h, rh)
		local key = ba .. ":" .. bh
		showScore(side, secs, fa, fh, (side == "Alliance" and a or h) / max, key ~= lastBases)
		lastBases = key
		return
	end
	local t = now()
	local last = scores[#scores]
	local da, dh = 0, 0
	if last then
		da, dh = a - last.a, h - last.h
		-- a flag capture (or a lost score) is not the bases' rate
		if da > SCORE_JUMP or da < 0 then da = 0 end
		if dh > SCORE_JUMP or dh < 0 then dh = 0 end
	end
	scores[#scores + 1] = { t = t, a = a, h = h, da = da, dh = dh }
	while #scores > 1 and t - scores[1].t > 30 do table.remove(scores, 1) end
	local span = t - scores[1].t
	if span < 10 then return end
	local sa, sh = 0, 0
	for i = 2, #scores do sa, sh = sa + scores[i].da, sh + scores[i].dh end
	local ra, rh = sa / span, sh / span
	local ta = ra > 0 and (max - a) / ra or math.huge
	local th = rh > 0 and (max - h) / rh or math.huge
	if ta == math.huge and th == math.huge then stopBar("score") return end
	local side, secs = "Alliance", ta
	if th < ta then side, secs = "Horde", th end
	local fa = math.min(max, math.floor(a + ra * secs + 0.5))
	local fh = math.min(max, math.floor(h + rh * secs + 0.5))
	local b = find(bars, "score")
	showScore(side, secs, fa, fh, (side == "Alliance" and a or h) / max, b and b.side ~= side)
end
api.bgScoreTick = scoreTick -- for tests

-- "12 min", "4:30", "Time Remaining: 3 minutes": seconds, or nil
local function timeFrom(text)
	if type(text) ~= "string" or isSecret(text) then return nil end
	local m = text:lower()
	local mm, ss = m:match("(%d+):(%d%d)")
	if mm then return tonumber(mm) * 60 + tonumber(ss) end
	local n = tonumber(m:match("(%d+)%s*min"))
	if n then return n * 60 + (tonumber(m:match("(%d+)%s*sec")) or 0) end
	n = tonumber(m:match("(%d+)%s*sec"))
	return n
end
api.bgTimeFrom = timeFrom -- for tests
local function timeTick()
	local w = C_UIWidgetManager
	if not (w and w.GetTopCenterWidgetSetID and w.GetAllWidgetsBySetID and w.GetIconAndTextWidgetVisualizationInfo) then return end
	local okS, set = pcall(w.GetTopCenterWidgetSetID)
	local okW, list = pcall(w.GetAllWidgetsBySetID, okS and set or 0)
	if not okW or type(list) ~= "table" then return end
	for _, wi in ipairs(list) do
		local ok, info = pcall(w.GetIconAndTextWidgetVisualizationInfo, wi.widgetID)
		local s = ok and type(info) == "table" and info.shownState ~= 0 and timeFrom(info.text)
		if s and s > 0 then
			local b = find(bars, "time")
			-- the widget counts in steps (minutes): our bar keeps counting between them
			if not b or math.abs(left(b) - s) > 60 then setBar("time", "Time left", "none", s, { icon = ICON.time }) end
			return
		end
	end
end
api.bgTimeTick = timeTick -- for tests

---------------------------------------------------------------------------------------------------------------------
-- What Frame.lua draws: the battleground (soonest timer first, then who holds the flags) and the queues
-- each kind of bar and line can be turned off on the Battleground settings page (user); the timers keep running
local KIND_SETTING = { start = "bgStart", node = "bgNodes", flag = "bgFlag", score = "bgScore", time = "bgTime" }
local function kindOn(key)
	local setting = KIND_SETTING[key:match("^[^:]+")]
	return not setting or db()[setting] ~= false
end
function api.ownBattleground()
	local out = {}
	if db().ownBg == false then return out end
	if bg then
		local list = {}
		for _, b in ipairs(bars) do if (left(b) > 0 or b.ending) and kindOn(b.key) then list[#list + 1] = b end end
		table.sort(list, function(a, b) return left(a) < left(b) end)
		local e = { title = bg.name, item = bg, lines = {} }
		for _, b in ipairs(list) do e.lines[#e.lines + 1] = { text = b.label, bar = b, extra = b } end
		for _, flag in ipairs({ "Alliance", "Horde", "Flag" }) do
			local name = flag == "Flag" and "Flag" or (flag .. " flag")
			if carriers[flag] and db().bgCarriers ~= false then
				e.lines[#e.lines + 1] = { text = name .. ": " .. carriers[flag], extra = { carrier = flag } }
			elseif dropped[flag] and now() - dropped[flag] < 20 and db().bgCarriers ~= false then
				e.lines[#e.lines + 1] = { text = name .. ": |cffff8080dropped|r", extra = { carrier = flag, dropped = dropped[flag] } }
			end
		end
		if #e.lines == 0 then e.lines[1] = { text = "No timers running", dim = true } end
		out[#out + 1] = e
	end
	if #queues > 0 and db().bgQueues ~= false and not bg then -- 3.2 (user): not while in a battleground
		local e = { title = "Queues", item = {}, lines = {} }
		for _, b in ipairs(queues) do e.lines[#e.lines + 1] = { text = b.label, bar = b, extra = b } end
		out[#out + 1] = e
	end
	return out
end

-- the bar on a timer line (Frame.lua calls it for each line; extra = the timer). The reputation bar's look (user):
-- the bronze-bordered box and shaded fill of Extras.lua's progress bars, the fill in the side's color, the name at the
-- left and the time at the right inside it
local widgets, used = {}, 0
local FILL = { Alliance = "Blue", Horde = "Red", none = "Yellow", queue = "Orange" }
local function frac(b)
	if b.up then return b.dur > 0 and math.min((b.frozen or (now() - b.start)) / b.dur, 1) or 0 end
	return b.fill or (b.dur > 0 and left(b) / b.dur or 0)
end
local function paint(w)
	local b = w.timer
	if not b then return end
	local f = frac(b)
	-- 3.2 animations (user): a captured base flashes out; a base's (10 s) or a ready queue's (15 s) last seconds pulse
	-- red; the win bar flips when the winning side changes; a ready queue's bar turns red in its last 15 s
	local l = left(b)
	if b.ending and w.qtsCapturedFor ~= b and api.animBgCaptured then
		w.qtsCapturedFor = b
		api.animBgCaptured(w, b.side)
	end
	if api.animBgPulse then
		local want = not b.ending and l > 0 and ((b.confirm and l <= 15) or (b.key:find("^node:") ~= nil and l <= 10))
		api.animBgPulse(w, want, b.confirm and "bgqueue" or "bgpulse")
	end
	if b.swapAt and w.qtsSwapFor ~= b.swapAt then
		w.qtsSwapFor = b.swapAt
		if now() - b.swapAt < 1 and api.animBgSwap then api.animBgSwap(w, b.swapFrom) end
	end
	local fillSide = b.side
	if b.confirm and l <= 15 and animOk("bgqueue") then fillSide = "Horde" end -- (the red fill)
	if w.pb and api.drawProgressBar then
		local file = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\BarFill" .. (FILL[fillSide] or "Yellow")
		api.drawProgressBar(w.pb, w, 0, w.fontFile, w.size, w.fontFlags, math.floor(f * 1000 + 0.5), 1000, "TOPLEFT",
			math.max(w:GetWidth() or 0, 20), w.barH, 0, "TOPLEFT", file)
		w.pb.text:Hide()
	end
	w.value = f
	if b.up then
		local waited = b.frozen or (now() - b.start)
		w.time:SetText(b.dur > 0 and (clock(waited) .. " / ~" .. clock(b.dur)) or clock(waited))
	else
		w.time:SetText(clock(left(b)))
	end
	if w.label:GetText() ~= b.label then w.label:SetText(b.label) end
end
-- 3.2 (user): a timer as one chat line: "Farm (Horde): 0:34", "Alliance wins 2000-1160 in 3:12"
function api.bgTimerText(b)
	if type(b) ~= "table" then return nil end
	local label = tostring(b.label or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if b.up then
		local waited = b.frozen or (now() - b.start)
		return ("%s: %s waited%s"):format(label, clock(waited), b.dur > 0 and (" (about " .. clock(b.dur) .. ")") or "")
	end
	local t = clock(left(b))
	if b.key == "score" then return ("%s in %s"):format(label, t) end
	if b.key:find("^node:") then return ("%s (%s): %s"):format(label, tostring(b.side), t) end
	return ("%s: %s"):format(label, t)
end
function api.bgTimerToChat(b)
	local text = api.bgTimerText(b)
	if not text then return end
	if root.chatInsert then root.chatInsert(text) end -- only into a chat box you opened (Bootstrap.lua)
end

function api.ownBgClicker(parent, fs, _, timer)
	if not timer then return end
	-- 3.2: a flag line (no bar): kept for the low health shake; a dropped flag's line pops once
	if timer.carrier then
		carrierFs[timer.carrier] = fs
		if timer.dropped and dropPinged[timer.carrier] ~= timer.dropped then
			dropPinged[timer.carrier] = timer.dropped
			if api.animBgDrop then api.animBgDrop(fs) end
		end
		return
	end
	used = used + 1
	local w = widgets[used]
	if not w then
		w = CreateFrame("Frame", nil, parent)
		w.pb = api.newProgressBar and api.newProgressBar(w)
		w.icon = w:CreateTexture(nil, "OVERLAY", nil, 1)
		w.label = w:CreateFontString(nil, "OVERLAY", nil, 2)
		w.label:SetJustifyH("LEFT")
		w.label:SetWordWrap(false)
		w.label:SetPoint("LEFT", w, "LEFT", 6, 0)
		w.time = w:CreateFontString(nil, "OVERLAY", nil, 2)
		w.time:SetJustifyH("RIGHT")
		w.time:SetPoint("RIGHT", w, "RIGHT", -6, 0)
		w.label:SetPoint("RIGHT", w.time, "LEFT", -4, 0)
		-- 3.2 (user): shift-click puts the timer in the chat box
		w:EnableMouse(true)
		w:SetScript("OnMouseUp", function(self)
			if IsShiftKeyDown and IsShiftKeyDown() and self.timer then api.bgTimerToChat(self.timer) end
		end)
		w:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine(self.timer and self.timer.label or "", 1, 1, 1)
			GameTooltip:AddLine("Shift-click: put it in chat", 0.6, 0.85, 1)
			GameTooltip:Show()
		end)
		w:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		for _, t in ipairs({ w.label, w.time }) do
			t:SetShadowOffset(1, -1)
			t:SetShadowColor(0, 0, 0, 1)
		end
		widgets[used] = w
	end
	local font = fs.GetFontObject and fs:GetFontObject()
	if font then w.label:SetFontObject(font); w.time:SetFontObject(font) end
	-- the bar's own count text needs a font before any text is set (user: "Font not set")
	local ffile, size, fflags = fs:GetFont()
	w.size = type(size) == "number" and size > 0 and size or 12
	w.fontFile = type(ffile) == "string" and ffile ~= "" and ffile or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	w.fontFlags = fflags
	w.barH = api.progressBarSize and select(2, api.progressBarSize(w.size)) or (w.size + 5)
	-- the icon just left of the bar, as the icons left of the quest titles (user): their size (Quest titles > Icon
	-- size), 2 px from the bar, their opacity
	local isz = math.floor(14 * (tonumber(db().iconScale) or 1) + 0.5)
	w.icon:ClearAllPoints()
	w.icon:SetPoint("RIGHT", w, "LEFT", -2, 0)
	w.icon:SetSize(isz, isz)
	w.icon:SetAlpha(math.min(math.max(tonumber(db().iconAlpha) or 1, 0.1), 1))
	local getCoords = (C_Minimap and C_Minimap.GetPOITextureCoords) or GetPOITextureCoords
	local l, r, t, b
	if timer.poi and getCoords then
		local ok
		ok, l, r, t, b = pcall(getCoords, timer.poi)
		if not ok then l = nil end
	end
	if db().bgIcons == false then
		w.icon:Hide() -- Battleground settings: no icons
	elseif l and r and t and b then
		w.icon:SetTexture(POI_SHEET)
		w.icon:SetTexCoord(l, r, t, b)
		w.icon:Show()
	elseif timer.icon then
		w.icon:SetTexture(timer.icon)
		w.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- an item or spell icon: its frame cut off
		w.icon:Show()
	else
		w.icon:Hide()
	end
	w.label:SetText(timer.label)
	w.label:SetTextColor(1, 1, 1, 1)
	w.time:SetTextColor(1, 1, 1, 1)
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", fs, "TOPLEFT", -2, 2)
	w:SetPoint("TOPRIGHT", fs, "TOPRIGHT", 0, 2)
	w:SetHeight(w.barH)
	if w.timer ~= timer and not timer.ending and api.animBgReset then api.animBgReset(w) end
	w.timer = timer
	fs:SetAlpha(0) -- the bar shows the text
	paint(w)
	w:Show()
	if timer.confirm and not timer.bounced then
		timer.bounced = true
		if api.animBgBounce then api.animBgBounce(w) end
	end
	return w
end
function api.ownBgClickersReset() used = 0 end
function api.ownBgClickersDone()
	for i = used + 1, #widgets do widgets[i].timer = nil; widgets[i]:Hide() end
end
api.ownBgWidgetsForTests = function() return widgets, used end

-- 3.2 (user): a flag carrier's health under 35 %: their line shakes (again every 2 s while it stays low). Health is
-- known for your group, your target, focus and name plates only.
local function healthOf(name)
	if type(name) ~= "string" then return nil end
	local units = { "target", "focus" }
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
	for _, u in ipairs(units) do
		local ok, n = pcall(UnitName, u)
		-- a secret name (another player, in some places) is not compared: that errors (user: BugSack)
		if ok and type(n) == "string" and not isSecret(n) and n == name then
			local okH, h, m = pcall(function() return UnitHealth(u), UnitHealthMax(u) end)
			if okH and not isSecret(h) and not isSecret(m) and type(h) == "number" and type(m) == "number" and m > 0 then
				return h / m
			end
		end
	end
end
api.bgHealthOf = healthOf -- (tests)
carrierTick = function()
	if not animOk("bgcarrier") or not api.animBgCarrier then return end
	for flag, who in pairs(carriers) do
		local fs = carrierFs[flag]
		local h = fs and fs.IsShown and fs:IsShown() and healthOf(who)
		if h and h < 0.35 and now() - (lastShake[flag] or -10) >= 2 then
			lastShake[flag] = now()
			api.animBgCarrier(fs)
		end
	end
end
-- 3.2 (user): the battleground ended: a gold (won) or red (lost) banner (LevelBanner.lua)
resultTick = function()
	if not bg or bg.resultShown or not GetBattlefieldWinner then return end
	local ok, winner = pcall(GetBattlefieldWinner)
	if not ok or winner == nil or isSecret(winner) then return end
	bg.resultShown = true
	if not (animOk("bgresult") and api.showResultBanner) then return end
	local side = winner == 1 and "Alliance" or winner == 0 and "Horde" or nil
	local mine = mySide()
	local a, h = readScore()
	local score = a and (mine == "Horde" and ("%d-%d"):format(h, a) or ("%d-%d"):format(a, h)) or nil
	local sub = (side and (side .. " wins " .. bg.name) or bg.name) .. (score and ("  " .. score) or "")
	api.showResultBanner(side == nil and "draw" or (side == mine and "won" or "lost"), sub, side)
end
api.bgResultTick = function() resultTick() end -- (tests)

-- moves the bars on; a finished timer leaves and the section is drawn again; our node 10 s from lost: a warning
ticker = CreateFrame("Frame")
ticker:Hide()
local acc = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	acc = acc + (elapsed or 0)
	if acc < 0.1 then return end
	acc = 0
	for i = 1, used do paint(widgets[i]) end
	local gone = false
	for i = #bars, 1, -1 do
		local b = bars[i]
		local l = left(b)
		if b.warn and not b.warned and l <= 10 and l > 0 then
			b.warned = true
			warn(("%s falls in 10 seconds!"):format(b.label))
		end
		if l <= 0 then
			if not endWithFlash(b) and (not b.ending or now() - b.ending > 0.8) then table.remove(bars, i); gone = true end
		end
	end
	if gone then changed() end
	if #bars == 0 and #queues == 0 then
		for i = 1, used do if api.animBgPulse then api.animBgPulse(widgets[i], false) end end
		self:Hide()
	end
end)
api.bgTickForTests = function() local f = ticker:GetScript("OnUpdate"); f(ticker, 1) end

-- once a second in a battleground or a queue: queues, score, time left
poller = CreateFrame("Frame")
poller:Hide()
local pacc, sacc = 0, 0
poller:SetScript("OnUpdate", function(self, elapsed)
	pacc = pacc + (elapsed or 0)
	-- 3.2: the score 5 times a second, so the time of each score step is known closely (the win timer)
	sacc = sacc + (elapsed or 0)
	if bg and sacc >= 0.2 and pacc < 1 then sacc = 0; scoreTick() end
	if pacc < 1 then return end
	pacc, sacc = 0, 0
	readQueues()
	if bg then scoreTick(); timeTick(); carrierTick(); resultTick() end
	if not bg and #queues == 0 then self:Hide() end
end)

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "AREA_POIS_UPDATED", "START_TIMER",
	"CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE",
	"UPDATE_BATTLEFIELD_STATUS" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		enter()
	elseif event == "AREA_POIS_UPDATED" then
		scanNodes(false)
	elseif event == "UPDATE_BATTLEFIELD_STATUS" then
		readQueues()
		if #queues > 0 then poller:Show() end
	elseif event == "START_TIMER" then
		-- timerType, timeRemaining, totalTime
		local s = tonumber(a2)
		if bg and s and not isSecret(a2) and s > 0 then startBar("start", "Battle begins", "none", s, { icon = ICON.start }) end
	else
		onSystem(event, a1)
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- /qt bg: what the game reports here (user: to learn a new battleground's numbers)
if api.addSlash then api.addSlash("bg", "list what the game reports in a battleground (instance, map, nodes, widgets, timers)", function(_, say)
	local name, itype, _, _, _, _, _, id
	if GetInstanceInfo then name, itype, _, _, _, _, _, id = GetInstanceInfo() end
	local p = readPlace()
	say(("instance %s, type %s, ID %s: %s"):format(tostring(name), tostring(itype), tostring(id),
		p and ("battleground kind " .. p.kind) or "not a known battleground"))
	local list, map = mapPOIs()
	say(("map %s, %d nodes"):format(tostring(map), #list))
	for _, n in ipairs(list) do
		say(("  %s (POI %s) art %s%s%s"):format(n.name, tostring(n.id), tostring(n.art),
			n.atlas and (" atlas " .. tostring(n.atlas)) or "", CONTESTED[n.art] and (" = taken by " .. CONTESTED[n.art]) or ""))
	end
	local a, h, max, wid = readScore()
	say(a and ("score widget %s: Alliance %d, Horde %d of %d"):format(wid, a, h, max) or "no score widget found")
	local ba, bh = readBases()
	say(ba and ("bases widget %d: Alliance %d, Horde %d held"):format(BASES_WIDGET, ba, bh) or "no bases widget found")
	local w = C_UIWidgetManager
	if w and w.GetTopCenterWidgetSetID and w.GetAllWidgetsBySetID then
		local okS, set = pcall(w.GetTopCenterWidgetSetID)
		local okW, wl = pcall(w.GetAllWidgetsBySetID, okS and set or 0)
		for _, wi in ipairs(okW and type(wl) == "table" and wl or {}) do
			local text = ""
			if w.GetIconAndTextWidgetVisualizationInfo then
				local ok, info = pcall(w.GetIconAndTextWidgetVisualizationInfo, wi.widgetID)
				if ok and type(info) == "table" and type(info.text) == "string" then text = " text \"" .. info.text .. "\"" end
			end
			say(("  widget %s type %s%s"):format(tostring(wi.widgetID), tostring(wi.widgetType), text))
		end
	end
	for flag, who in pairs(carriers) do say(("  %s held by %s"):format(flag, who)) end
	if #bars == 0 and #queues == 0 then say("no timers running") end
	for _, b in ipairs(bars) do say(("  timer %s (%s): %s left"):format(b.label, b.side, clock(left(b)))) end
	for _, b in ipairs(queues) do say(("  queue %s: %s"):format(b.label, b.up and ("waited " .. clock(now() - b.start)) or (clock(left(b)) .. " to enter"))) end
end) end
