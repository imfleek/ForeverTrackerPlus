-- R106-100: the dungeon card's instance line (user picked NovaInstanceTracker's idea): new instances entered this hour
-- against the game's hourly limit, when the next one frees up, and the saved lockout of the dungeon you are in:
--   "Instances this hour: 3/5 · Saved 2/5, resets 2d 4h"     (red count and "next in 12m" once at the limit)
-- Hover: the instances counted, newest first. Option: Dungeon card > "Instances this hour and saved lockout"
-- (db.instanceCap, on by default).
-- Count: our own log (3.2: NovaInstanceTracker is no longer read, user)
-- (db.instanceRuns, account-wide like the limit): a run starts on entering a dungeon or raid, unless it is the same
-- copy as the last run (same map, no reset message since, the same creature zone id seen); it counts for the hour from
-- the time it was left (or now, while inside). Limit: 5 an hour (3.2, user: "Wow forever updated so it's only 5
-- instances per hour now"; it was 10).
-- CONSTRAINT: GetNumSavedInstances / GetSavedInstanceInfo / RequestRaidInfo are the old global API (not in the
-- generated Forever docs; NovaInstanceTracker calls them on Forever): each is type-checked and pcall'd.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local LIMIT = 5
local HOUR, DAY = 3600, 86400

local function now() return (GetServerTime and GetServerTime()) or time() end
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function enabled() return db and db.instanceCap ~= false end
api.instanceCapOn = enabled

local function runs()
	if type(db.instanceRuns) ~= "table" then db.instanceRuns = {} end
	return db.instanceRuns
end

local function prune()
	local list, cut = runs(), now() - DAY
	for i = #list, 1, -1 do
		local r = list[i]
		if type(r) ~= "table" or ((r.left or r.entered or 0) < cut) then table.remove(list, i) end
	end
end

local function current()
	local list = runs()
	local last = list[#list]
	if last and not last.left then return last end
end

local function startRun(name, mapID)
	local list = runs()
	list[#list + 1] = { name = name, mapID = mapID, entered = now() }
	prune()
end

-- entering or leaving a dungeon / raid
local function onWorld()
	if not db then return end
	local inside, kind = IsInInstance()
	if inside and (kind == "party" or kind == "raid") then
		local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
		if isSecret(name) or isSecret(mapID) then return end
		local list = runs()
		local last = list[#list]
		if last and last.mapID == mapID and not last.reset then
			last.left = nil -- back into the same copy: still that run
		else
			if last and not last.left then last.left = now() end
			startRun(name, mapID)
		end
	else
		local cur = current()
		if cur then cur.left = now() end
	end
end

-- the copy's zone id from a creature's GUID (Creature-0-server-instance-zoneUID-npcID-spawn): a different one in the
-- same dungeon means a new copy (reset by the group leader, no message to us)
local function onCreature(guid)
	local cur = current()
	if not cur or type(guid) ~= "string" or isSecret(guid) then return end
	local kind, _, _, _, zoneUID = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return end
	zoneUID = tonumber(zoneUID)
	if not zoneUID then return end
	if not cur.zoneUID then
		cur.zoneUID = zoneUID
	elseif cur.zoneUID ~= zoneUID then
		cur.left = now()
		startRun(cur.name, cur.mapID)
		current().zoneUID = zoneUID
	end
end

-- "<dungeon> has been reset.": its earlier runs are other copies
local resetPattern
local function onSystem(text)
	if type(text) ~= "string" or isSecret(text) then return end
	if not resetPattern then
		local fmt = _G.INSTANCE_RESET_SUCCESS or "%s has been reset."
		resetPattern = "^" .. fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
	end
	local name = text:match(resetPattern)
	if not name then return end
	for _, r in ipairs(runs()) do
		if r.name == name then r.reset = true end
	end
end

-- count, limit, seconds until the next instance frees up (nil while under the limit), the source, the runs counted
function api.instanceCap()
	local t, count, oldest, counted = now(), 0, nil, {}
	for i = #runs(), 1, -1 do
		local r = runs()[i]
		local at = r.left or t
		if at > t - HOUR then
			count = count + 1
			counted[#counted + 1] = r
			if not oldest or at < oldest then oldest = at end
		end
	end
	local wait = (count >= LIMIT and oldest) and math.max(HOUR - (t - oldest), 0) or nil
	return count, LIMIT, wait, ADDON, counted
end

-- the saved lockout of a dungeon by name: { progress, total, reset (seconds) } or nil
function api.savedLockout(name)
	if type(name) ~= "string" or type(GetNumSavedInstances) ~= "function" or type(GetSavedInstanceInfo) ~= "function" then
		return nil
	end
	local okN, n = pcall(GetNumSavedInstances)
	for i = 1, (okN and tonumber(n) or 0) do
		local ok, sName, _, reset, _, locked, _, _, _, _, _, total, progress = pcall(GetSavedInstanceInfo, i)
		if ok and sName == name and locked then
			return { progress = tonumber(progress) or 0, total = tonumber(total) or 0, reset = tonumber(reset) or 0 }
		end
	end
end

local function short(seconds)
	seconds = math.max(math.floor(seconds or 0), 0)
	local d, h, m = math.floor(seconds / DAY), math.floor(seconds % DAY / HOUR), math.floor(seconds % HOUR / 60)
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %dm"):format(h, m) end
	return ("%dm"):format(math.max(m, 1))
end
api.instanceTimeShort = short

-- the card's line for the dungeon you are in
function api.instanceCapText(name)
	local count, limit, wait = api.instanceCap()
	local full = count >= limit
	local text = ("Instances this hour: %s%d/%d|r"):format(full and "|cffff4040" or "|cffffffff", count, limit)
	if full and wait then text = text .. (" · next in %s"):format(short(wait)) end
	local saved = api.savedLockout(name)
	if saved and saved.total > 0 then
		text = text .. (" · Saved %d/%d, resets %s"):format(saved.progress, saved.total, short(saved.reset))
	end
	return text
end

-- its tooltip: what was counted
function api.instanceCapTooltip(tip)
	local count, limit, wait, source, counted = api.instanceCap()
	tip:AddLine(("Instances this hour: %d of %d"):format(count, limit), 1, 0.82, 0)
	if wait then tip:AddLine("The next one frees up in " .. short(wait) .. ".", 1, 0.4, 0.4, true) end
	if type(counted) == "table" then
		local t = now()
		for _, r in ipairs(counted) do
			local ago = r.left and ("left " .. short(t - r.left) .. " ago") or "you are in it"
			tip:AddDoubleLine(r.name or "?", ago, 1, 1, 1, 0.7, 0.7, 0.7)
		end
	end
	tip:AddLine("Counted by " .. (source == ADDON and "ForeverTrackerPlus" or source) .. ".", 0.6, 0.6, 0.6)
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	prune()
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM", "PLAYER_TARGET_CHANGED",
		"UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "UPDATE_INSTANCE_INFO" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function(_, event, arg)
		if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
			onWorld()
			if type(RequestRaidInfo) == "function" then pcall(RequestRaidInfo) end
		elseif event == "CHAT_MSG_SYSTEM" then
			onSystem(arg)
		elseif event == "UPDATE_INSTANCE_INFO" then
			if api.applyLayout and api.dungeonInstance and api.dungeonInstance() then api.applyLayout() end
		else
			local unit = event == "PLAYER_TARGET_CHANGED" and "target" or event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or arg
			if unit and UnitExists(unit) then onCreature(UnitGUID(unit)) end
		end
	end)
end
