-- Sort all quests by zone: the order (orderQuests) and the zone names (questZoneName) our own tracker groups by
-- (Tracker/Own/Data.lua), the quest distances and directions, and the game's watch list in the same order.
--
-- SORT: Blizzard lists tracked quests in the order they were watched. When the option is on, the watch list is
-- rebuilt (RemoveQuestWatch + AddQuestWatch, keeping each quest's watch type) whenever the order is wrong: zones by
-- their closest quest, quests inside a zone closest first, so the closest quest/objective is at the very top. Re-checked
-- every 15 s while you move and after the game's own SortQuestWatches; out of combat only, never while the order is
-- already right, at most 4 re-orders per 10 s (so it cannot loop). With "Track all quests" the rebuild also picks WHICH
-- quests are watched: the closest ones, up to the game's limit (the map shows them).
-- 3.2 (user: "Delete the old tracker's code"): the zone headers drawn on Blizzard's tracker were removed; our own
-- tracker draws its own (Own/Frame.lua api.ownZoneLabelFor).
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

local function headerTitle(questID)
	-- with Questie data on: the zone where the quest is done (Questie.lua), not the quest log's header
	local questieZone = api.questieZone and api.questieZone(questID)
	if questieZone then return questieZone end
	local index = C_QuestLog.GetLogIndexForQuestID(questID)
	if not index then return nil end
	local headerIndex
	if C_QuestLog.GetHeaderIndexForQuest then
		local ok, value = pcall(C_QuestLog.GetHeaderIndexForQuest, questID)
		if ok then headerIndex = value end
	end
	if not headerIndex then
		for i = index, 1, -1 do
			local info = C_QuestLog.GetInfo(i)
			if info and info.isHeader then headerIndex = i break end
		end
	end
	local info = headerIndex and C_QuestLog.GetInfo(headerIndex)
	local title = info and info.title
	if type(title) == "string" and not isSecret(title) then return title end
end

api.questZoneName = headerTitle -- 3.2 beta: our own tracker's zone groups (Tracker/Own/Data.lua)

local function watched()
	local list = {}
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if id then list[#list + 1] = { id = id, zone = headerTitle(id) or "", index = i } end
	end
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Zone distance: the closest zone to the player first
---------------------------------------------------------------------------------------------------------------------
-- Quest-log headers are zone (or dungeon) names. Names are matched to map IDs once from the game's own map tree
-- (C_Map.GetMapChildrenInfo of the top map, all descendants); a zone's position is the world position of its map's
-- centre (C_Map.GetWorldPosFromMapPos), a map without world coordinates (a dungeon) uses its parent zone's. The
-- player's position is C_Map.GetPlayerMapPosition on their best map (its centre when the position is not available,
-- in an instance for example). Order: the player's own zone, then the same continent by distance, then other
-- continents and unknown names; ties alphabetical.
local zoneMaps, centers = nil, {}
local function buildZoneMaps()
	zoneMaps = {}
	local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local root, guard = map, 0
	while root and guard < 10 do
		local info = C_Map.GetMapInfo(root)
		if not info or not info.parentMapID or info.parentMapID == 0 then break end
		root, guard = info.parentMapID, guard + 1
	end
	if not root then zoneMaps = nil return end
	local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
	for _, info in ipairs(ok and type(children) == "table" and children or {}) do
		local name = type(info.name) == "string" and not isSecret(info.name) and info.name:lower()
		-- prefer zones over other map types sharing the name
		if name and (not zoneMaps[name] or (Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone)) then
			zoneMaps[name] = info.mapID
		end
	end
end

local function worldPos(mapID, x, y, depth)
	if not mapID or (depth or 0) > 4 then return nil end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if ok and continent and pos then
		local px, py = pos.x, pos.y
		if pos.GetXY then px, py = pos:GetXY() end
		if type(px) == "number" and type(py) == "number" and not isSecret(px) then return continent, px, py end
	end
	local info = C_Map.GetMapInfo(mapID)
	if info and info.parentMapID and info.parentMapID ~= 0 then return worldPos(info.parentMapID, 0.5, 0.5, (depth or 0) + 1) end
end

api.mapToWorld = worldPos -- 3.2: map position -> continent, world x, y (CorpseRun.lua)

local function center(mapID)
	if centers[mapID] == nil then
		local continent, x, y = worldPos(mapID, 0.5, 0.5)
		centers[mapID] = continent and { continent, x, y } or false
	end
	return centers[mapID] or nil
end

-- Inside a dungeon, raid or scenario: its name (lower case), else nil. The game gives no map position there, so the
-- distances of quests outside cannot be compared with it; the dungeon's own quests come first instead.
-- withPvp: a battleground or an arena counts too (the sort: user, in Warsong Gulch: "The Warsong Gulch quests I
-- have should appear at the top"); the distance arrows still work there (api.playerWorldPos asks without it).
-- Returns the name and whether it is a battleground or arena.
local function instanceName(withPvp)
	if not IsInInstance then return nil end
	local inside, kind = IsInInstance()
	local pvp = kind == "pvp" or kind == "arena"
	if not inside or not (kind == "party" or kind == "raid" or kind == "scenario" or (withPvp and pvp)) then return nil end
	local name = GetInstanceInfo and GetInstanceInfo()
	if type(name) ~= "string" or name == "" or isSecret(name) then name = GetRealZoneText and GetRealZoneText() end
	return type(name) == "string" and name ~= "" and name:lower() or nil, pvp
end

-- "The Deadmines" and "Deadmines" are the same place
local function bareName(name) return (name:lower():gsub("^the%s+", "")) end

-- the quest log's zone header names the dungeon you are in
local isDungeonQuest -- below playerPlace's helpers
local function isInstanceZone(place, zoneName)
	if not (place and place.instance and zoneName and zoneName ~= "") then return false end
	local zone = bareName(zoneName)
	if zone == bareName(place.instance) then return true end
	return place.zone ~= nil and zone == bareName(place.zone)
end

local lastOutdoor -- the last place with a position: inside a dungeon the other zones are ordered from there
-- Questie: are this quest's objectives (its open ones; the turn-in once complete) inside the dungeon you are in?
-- Matched by the game map of Questie's area, or else by the area's name.
-- per area of Questie, whether it is the dungeon you are in: worked out once per dungeon visit, not on every sort
local areaInside, areaFor = {}, nil
function isDungeonQuest(id, place)
	local points = api.questiePoints and api.questiePoints(id)
	if not points then return false end
	local visit = tostring(place.instance) .. "#" .. tostring(place.map)
	if areaFor ~= visit then wipe(areaInside); areaFor = visit end
	local instance = bareName(place.instance)
	for _, p in ipairs(points) do
		local area = p[1]
		local inside = areaInside[area]
		if inside == nil then
			inside = (place.map ~= nil and api.questieUiMap ~= nil and api.questieUiMap(area) == place.map) or false
			if not inside then
				local name = api.questieZoneName and api.questieZoneName(area)
				inside = type(name) == "string" and bareName(name) == instance
			end
			areaInside[area] = inside
		end
		if inside then return true end
	end
	return false
end

local function playerPlace()
	local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	-- no map (inside many dungeons): no position, but the zone and the dungeon's name still order the list
	if not map then
		local zone = GetRealZoneText and GetRealZoneText() or nil
		if isSecret(zone) then zone = nil end
		local place = { name = zone and zone:lower() or nil, zone = zone }
		place.instance, place.pvp = instanceName(true)
		if lastOutdoor then place.continent, place.x, place.y = lastOutdoor.continent, lastOutdoor.x, lastOutdoor.y end
		return place
	end
	local here = C_Map.GetMapInfo(map)
	local name = here and type(here.name) == "string" and not isSecret(here.name) and here.name:lower() or nil
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	local x, y
	if ok and pos then
		x, y = pos.x, pos.y
		if pos.GetXY then x, y = pos:GetXY() end
	end
	if type(x) ~= "number" or isSecret(x) then x, y = 0.5, 0.5 end
	local continent, wx, wy = worldPos(map, x, y)
	local place = { name = name, zone = GetRealZoneText and GetRealZoneText() or nil, continent = continent, x = wx, y = wy,
		map = map }
	place.instance, place.pvp = instanceName(true)
	if continent and not place.instance then
		lastOutdoor = place
	elseif not continent and lastOutdoor then
		place.continent, place.x, place.y = lastOutdoor.continent, lastOutdoor.x, lastOutdoor.y
	end
	return place
end

local FAR, UNKNOWN = 1e12, 2e12
local function distanceFrom(place, zoneName)
	if db and db.zoneOrder == "alpha" then return 0 end -- "Alphabetical": every zone equal, names decide
	if not zoneName or zoneName == "" then return UNKNOWN end
	local lower = zoneName:lower()
	if place and (lower == place.name or (place.zone and lower == place.zone:lower())) then return -1 end
	if not zoneMaps then buildZoneMaps() end
	local mapID = zoneMaps and zoneMaps[lower]
	local c = mapID and center(mapID)
	if not (c and place and place.continent) then return UNKNOWN end
	if c[1] ~= place.continent then return FAR end
	local dx, dy = c[2] - place.x, c[3] - place.y
	return dx * dx + dy * dy
end

-- the player's place, read at most once a second
local placeCache, placeAt
local function currentPlace()
	if not placeCache or GetTime() - (placeAt or 0) > 1 then placeCache, placeAt = playerPlace(), GetTime() end
	return placeCache
end

---------------------------------------------------------------------------------------------------------------------
-- Quest distance: the closest quest / objective to the player first
---------------------------------------------------------------------------------------------------------------------
-- Per quest, the squared world distance from the player to the nearest place it is done:
--   1. Questie on: the nearest spawn of its objectives (the turn-in once complete), Questie.lua api.questiePoints,
--      areas mapped to game maps with Questie's ZoneDB, positions with C_Map.GetWorldPosFromMapPos
--   2. the game's own C_QuestLog.GetDistanceSqToQuest (quest POI data)
--   3. C_QuestLog.GetNextWaypoint
--   4. the centre of the quest's zone (as before)
-- Another continent counts as far away (FAR + its zone distance), unknown after everything known.
local worldCache = {} -- questID -> { complete = bool, points = { {continent, x, y}, ... } }
local function questWorldPoints(id)
	local points = api.questiePoints and api.questiePoints(id)
	if not points then return nil end
	local entry = worldCache[id]
	if entry and entry.source == points then return entry.points end
	local out, mapOf = {}, {}
	for _, p in ipairs(points) do
		local area = p[1]
		if mapOf[area] == nil then mapOf[area] = api.questieUiMap and api.questieUiMap(area) or false end
		local map = mapOf[area]
		if map then
			local continent, x, y = worldPos(map, p[2] / 100, p[3] / 100)
			if continent then out[#out + 1] = { continent, x, y } end
		end
	end
	worldCache[id] = { source = points, points = out }
	return out
end

local function clientDistance(id)
	if C_QuestLog.GetDistanceSqToQuest then
		local ok, d, onContinent = pcall(C_QuestLog.GetDistanceSqToQuest, id)
		if ok and type(d) == "number" and not isSecret(d) and d >= 0 then
			if onContinent == false then return FAR + d end
			return d
		end
	end
end

local function waypointDistance(id, place)
	if not (C_QuestLog.GetNextWaypoint and place and place.continent) then return nil end
	local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, id)
	if not (ok and type(map) == "number" and type(x) == "number" and type(y) == "number") or isSecret(x) then return nil end
	local continent, wx, wy = worldPos(map, x, y)
	if not continent then return nil end
	if continent ~= place.continent then return FAR end
	local dx, dy = wx - place.x, wy - place.y
	return dx * dx + dy * dy
end

-- The distance and direction after quest titles (Extras.lua, "Distance and direction after quest titles").
-- api.playerWorldPos(): the player's own world position now (continent, x, y in yards; nil inside an instance or
-- without a map position, never the centre-of-map guess the sort uses). The world vector's x runs north and y west
-- (C_Map.GetWorldPosFromMapPos), as GetPlayerFacing counts: 0 = north, turning left (counter-clockwise).
function api.playerWorldPos()
	if instanceName() then return nil end
	local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not map then return nil end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not (ok and pos) then return nil end
	local x, y = pos.x, pos.y
	if pos.GetXY then x, y = pos:GetXY() end
	if type(x) ~= "number" or type(y) ~= "number" or isSecret(x) then return nil end
	local continent, wx, wy = worldPos(map, x, y)
	if not continent then return nil end
	return { continent = continent, x = wx, y = wy, map = map }
end

-- The quest markers the world map shows on the player's map (C_QuestLog.GetQuestsOnMap, QuestPOIMapInfo: questID, x,
-- y), read once per position reading (me) and kept on it: where a quest in this zone is, also without Questie.
local function mapMarker(me, id)
	if me.markers == nil then
		me.markers = {}
		if me.map and C_QuestLog.GetQuestsOnMap then
			local ok, list = pcall(C_QuestLog.GetQuestsOnMap, me.map)
			for _, info in ipairs(ok and type(list) == "table" and list or {}) do
				local qid, x, y = info.questID, info.x, info.y
				if type(qid) == "number" and type(x) == "number" and type(y) == "number" and not isSecret(x)
					and not me.markers[qid] then
					me.markers[qid] = { x, y }
				end
			end
		end
	end
	return me.markers[id]
end

-- api.questDirection(id, me): yards to the nearest place the quest is done and its world angle (atan2 of west over
-- north, as GetPlayerFacing). The place: Questie's spawns (the turn-in once complete); else the quest's marker on the
-- player's map (GetQuestsOnMap; also C_QuestLog.GetNextWaypointForMap); else the game's next waypoint (it gives one
-- only for a quest in another zone). Only the yards from the game's own distance when no place is known (no arrow).
-- nil on another continent or when unknown.
local function toward(me, map, x, y)
	local continent, wx, wy = worldPos(map, x, y)
	if continent ~= me.continent then return nil end
	local dx, dy = wx - me.x, wy - me.y
	return dx * dx + dy * dy, dx, dy
end
local lastTarget, TARGET_KEEP = {}, 60 -- quest ID -> the last place found (world), kept 60 s
function api.questDirection(id, me)
	if not me then return nil end
	local best, bx, by
	for _, p in ipairs(questWorldPoints(id) or {}) do
		if p[1] == me.continent then
			local dx, dy = p[2] - me.x, p[3] - me.y
			local d = dx * dx + dy * dy
			if not best or d < best then best, bx, by = d, dx, dy end
		end
	end
	if not best and me.map then
		local marker = mapMarker(me, id)
		if not marker and C_QuestLog.GetNextWaypointForMap then
			local ok, x, y = pcall(C_QuestLog.GetNextWaypointForMap, id, me.map)
			if ok and type(x) == "number" and type(y) == "number" and not isSecret(x) then marker = { x, y } end
		end
		if marker then best, bx, by = toward(me, me.map, marker[1], marker[2]) end
	end
	if not best and C_QuestLog.GetNextWaypoint then
		local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, id)
		if ok and type(map) == "number" and type(x) == "number" and type(y) == "number" and not isSecret(x) then
			local continent, wx, wy = worldPos(map, x, y)
			if continent == me.continent then
				bx, by = wx - me.x, wy - me.y
				best = bx * bx + by * by
			end
		end
	end
	-- R106-40: the place last found is kept (TARGET_KEEP s) and used while every source above finds none for a moment
	-- (user: with the world map open or after a zone change the arrows went away and the yards jumped, image: only the
	-- game's distance, no direction); the yards and the angle are still from where you stand now
	if best then
		lastTarget[id] = { continent = me.continent, x = me.x + bx, y = me.y + by, time = GetTime() }
	else
		local t = lastTarget[id]
		if t and t.continent == me.continent and GetTime() - t.time < TARGET_KEEP then
			bx, by = t.x - me.x, t.y - me.y
			best = bx * bx + by * by
		end
	end
	if best then return math.sqrt(best), (math.atan2 or math.atan)(by, bx) end
	local d = clientDistance(id)
	if d and d < FAR then return math.sqrt(d), nil end
end

local lastSource = {}
local function questDistance(id, zone, place)
	-- in a dungeon its quests are the closest (ahead of every distance)
	if isInstanceZone(place, zone) then lastSource[id] = "instance" return -1 end
	-- a quest done in this dungeon but filed under another zone (Questie): its zone right after the dungeon's
	if place and place.instance and isDungeonQuest(id, place) then lastSource[id] = "instance (Questie)" return -0.5 end
	-- in a battleground: a quest named after it ("Warsong Gulch Victory") with it, then the other battleground
	-- quests (the log's "Battlegrounds" header)
	if place and place.pvp and place.instance then
		local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
		if type(title) == "string" and not isSecret(title) and title:lower():find(bareName(place.instance), 1, true) then
			lastSource[id] = "battleground" return -1
		end
		local bg = _G.BATTLEGROUNDS
		if zone and type(bg) == "string" and zone:lower() == bg:lower() then lastSource[id] = "battleground" return -0.5 end
	end
	local points = questWorldPoints(id)
	if points and #points > 0 and place and place.continent then
		local best
		for _, p in ipairs(points) do
			if p[1] == place.continent then
				local dx, dy = p[2] - place.x, p[3] - place.y
				local d = dx * dx + dy * dy
				if not best or d < best then best = d end
			end
		end
		lastSource[id] = "questie"
		return best or (FAR + 1)
	end
	local d = clientDistance(id)
	if d then lastSource[id] = "game" return d end
	d = waypointDistance(id, place)
	if d then lastSource[id] = "waypoint" return d end
	lastSource[id] = "zone"
	local z = distanceFrom(place, zone)
	if z == -1 then return 0 end
	return z
end


-- Distances closer together than this (yards) count as equal, so the list does not swap two quests back and forth
-- while you walk between them; the current order then decides. 100 (was 30): a quest has to become clearly closer to
-- move up, so the list stays still while you run about (user: the titles moved around, "calmer sorting").
local BUCKET = 100
local function bucket(d)
	if d < 0 then return d end -- the dungeon you are in
	if d >= FAR then return d end
	return math.floor(math.sqrt(d) / BUCKET)
end

-- Sorts entries { id, zone, index } (index: the current position). "closest": zones by their closest quest, quests
-- inside a zone by distance; "alpha": zones A to Z, quests inside a zone by distance.
-- 3.2: inside a zone, quests by distance (default), by level (low first) or by how done they are (most done first)
local function questLevel(id)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
	local info = index and C_QuestLog.GetInfo(index)
	local level = info and (info.level or info.difficultyLevel)
	if type(level) ~= "number" or (issecretvalue and issecretvalue(level)) then return 999 end
	return level
end
local function questProgress(id)
	if C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then return 1 end
	local list = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
	if type(list) ~= "table" or #list == 0 then return 0 end
	local sum = 0
	for _, o in ipairs(list) do
		local have, need = tonumber(o.numFulfilled), tonumber(o.numRequired)
		if o.finished then sum = sum + 1
		elseif have and need and need > 0 then sum = sum + math.min(have / need, 1) end
	end
	return sum / #list
end
local function innerKeys(out, qd)
	local mode = db and db.questOrder
	if mode ~= "level" and mode ~= "progress" then return qd end
	local keys = {}
	for _, q in ipairs(out) do
		if mode == "level" then keys[q.id] = questLevel(q.id)
		else keys[q.id] = -math.floor(questProgress(q.id) * 20 + 0.5) end -- 5 % steps: calm
	end
	return keys
end
api.questProgressFraction = questProgress

local function orderQuests(list, place)
	local out = {}
	for i, q in ipairs(list) do out[i] = q end
	place = place or playerPlace()
	local qd, zd = {}, {}
	for _, q in ipairs(out) do
		local d = bucket(questDistance(q.id, q.zone, place))
		qd[q.id] = d
		local key = q.zone or ""
		if zd[key] == nil or d < zd[key] then zd[key] = d end
	end
	local alpha = db and db.zoneOrder == "alpha"
	local inner = innerKeys(out, qd)
	table.sort(out, function(a, b)
		local za, zb = a.zone or "", b.zone or ""
		if za ~= zb then
			if za == "" or zb == "" then return zb == "" end -- quests without a zone last
			if not alpha and zd[za] ~= zd[zb] then return zd[za] < zd[zb] end
			return za:lower() < zb:lower()
		end
		if inner[a.id] ~= inner[b.id] then return inner[a.id] < inner[b.id] end
		if inner ~= qd and qd[a.id] ~= qd[b.id] then return qd[a.id] < qd[b.id] end
		return a.index < b.index
	end)
	return out
end
api.orderQuests = function(list) return orderQuests(list) end

local function sorted(list) return orderQuests(list) end

-- "Track all quests": the game tracks at most MAX_QUEST_WATCHES quests (20 seen on Forever). The closest ones (by the
-- same order) are the watched ones (our own tracker lists the rest too). Other modes only re-order what is tracked.
local function maxWatches()
	return (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25
end
local function candidates(list)
	if db.trackMode ~= "all" then return list end
	local all, seen = {}, {}
	for _, q in ipairs(list) do all[#all + 1] = q; seen[q.id] = true end
	local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and info.questID
		-- not hidden, world or bonus tasks, or hidden by the zone filter
		if id and not isSecret(id) and not seen[id] and not info.isHidden and not info.isTask and not info.isBounty
			and not (db.zoneHidden and db.zoneHidden[id]) then
			seen[id] = true
			all[#all + 1] = { id = id, zone = headerTitle(id) or "", index = #list + i }
		end
	end
	return all
end
local function wantedWatches(list)
	local want = sorted(candidates(list))
	-- R106-86: "Expand current zone only": only the quests of the player's zone are watched. The super-tracked quest stays.
	if db.expandCurrentZone and db.trackMode == "all" and api.inCurrentZone then
		local sup = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
		local keep = {}
		for _, q in ipairs(want) do
			if q.id == sup or api.inCurrentZone(q.id) then keep[#keep + 1] = q end
		end
		want = keep
	end
	local limit = maxWatches()
	if db.trackMode == "all" then
		for i = #want, limit + 1, -1 do want[i] = nil end
	end
	return want
end

local busy = false
local reversedAdd = false -- this client puts a newly watched quest first instead of last
local recent = {}         -- times of our recent reorders
local function sameOrder(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i].id ~= b[i].id then return false end end
	return true
end
local function rewatch(list, want, reverse)
	for _, q in ipairs(list) do C_QuestLog.RemoveQuestWatch(q.id) end
	local first, last, step = 1, #want, 1
	if reverse then first, last, step = #want, 1, -1 end
	for i = first, last, step do
		local q = want[i]
		if q.type ~= nil then C_QuestLog.AddQuestWatch(q.id, q.type) else C_QuestLog.AddQuestWatch(q.id) end
	end
end
-- afterGame: right after the game's own SortQuestWatches (opening the world map, a new zone: QUEST_POI_UPDATE). That
-- one is put back each time (up to 20 in 10 s); anything else that keeps re-ordering is fought at most 4 times.
local sortCounts = { game = 0, ours = 0, held = 0 }
local function sortWatches(force, afterGame)
	if not db or not db.zoneSort or not db.enabled or InCombatLockdown() or busy then return end
	local now = GetTime()
	local keep = {}
	for _, t in ipairs(recent) do if now - t < 10 then keep[#keep + 1] = t end end
	recent = keep
	if #recent >= (afterGame and 20 or 4) then sortCounts.held = sortCounts.held + 1 return end
	local list = watched()
	local want = wantedWatches(list)
	if sameOrder(list, want) then return end
	recent[#recent + 1] = now
	if afterGame then sortCounts.game = sortCounts.game + 1 else sortCounts.ours = sortCounts.ours + 1 end
	busy = true
	for _, q in ipairs(want) do q.type = C_QuestLog.GetQuestWatchType(q.id) end
	local ok, err = pcall(function()
		rewatch(list, want, reversedAdd)
		local got = watched()
		if not sameOrder(got, want) then
			-- the client added in the other direction: learn it and redo once
			local reversed = #got == #want
			for i = 1, #got do if got[i].id ~= want[#want - i + 1].id then reversed = false break end end
			if reversed then
				reversedAdd = not reversedAdd
				rewatch(got, want, reversedAdd)
			end
		end
	end)
	busy = false
	if not ok then geterrorhandler()(err) end
end

-- our zone header's text for a zone (Rares.lua's rare tag and Chains.lua's "Explored 7/12" sit on it)
function api.zoneLabelFor(zone)
	if type(zone) ~= "string" then return nil end
	return api.ownZoneLabelFor and api.ownZoneLabelFor(zone) or nil
end

local timer
local sortRequested = false
local function schedule(delay, doSort)
	if doSort then sortRequested = true end
	if timer then return end
	timer = true
	C_Timer.After(delay or 0.3, function()
		timer = nil
		xpcall(function()
			if sortRequested then sortRequested = false; sortWatches(true) end
		end, geterrorhandler())
	end)
end

function api.setZoneSort(enabled)
	db.zoneSort = enabled and true or false
	if db.zoneSort and db.trackMode and api.setTrackMode then api.setTrackMode(nil) end
	schedule(0, true)
	if api.refreshConfig then api.refreshConfig() end
end

function api.applyZoneHeaders()
	if api.refreshQuests then api.refreshQuests() end -- our zone headers take the new look
end

function api.sortNow() schedule(0, true) end

-- "Sort zones": "closest" (closest zone to you first, the default) or "alpha" (A to Z)
function api.setZoneOrder(order)
	db.zoneOrder = order == "alpha" and "alpha" or "closest"
	schedule(0, true)
	if api.refreshQuests then api.refreshQuests() end
end

function api.zoneDebug(say)
	local zones = {}
	for _, q in ipairs(watched()) do zones[#zones + 1] = (q.zone ~= "" and q.zone or "?") end
	say(("sort by zone=%s, tracked quest zones in order: %s"):format(tostring(db.zoneSort), table.concat(zones, ", ")))
	local place = playerPlace()
	say(("you are in %s (continent %s); zone maps known: %s"):format(tostring(place and (place.zone or place.name)),
		tostring(place and place.continent), tostring(zoneMaps and next(zoneMaps) ~= nil)))
	local place2 = currentPlace()
	for i, q in ipairs(orderQuests(watched(), place2)) do
		if i > 12 then break end
		local d = questDistance(q.id, q.zone, place2)
		local yards = d >= FAR and "far" or ("%d yd"):format(math.floor(math.sqrt(d)))
		say(("  %d. %s [%s] %s (%s)"):format(i, tostring(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q.id) or q.id),
			q.zone ~= "" and q.zone or "?", yards, tostring(lastSource[q.id])))
	end
	say(("watch insert reversed: %s"):format(tostring(reversedAdd)))
	say(("re-sorts: %d after the game's own sort (at once), %d of ours, %d held back"):format(sortCounts.game,
		sortCounts.ours, sortCounts.held))
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local frame = CreateFrame("Frame")
	-- ZONE_CHANGED_NEW_AREA: the closest zones change when you travel
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_REGEN_ENABLED",
		"ZONE_CHANGED_NEW_AREA" }) do
		pcall(frame.RegisterEvent, frame, e)
	end
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then wipe(worldCache) end
		-- entering or leaving a dungeon (a loading screen) or a new zone: read the player's place again
		if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then placeCache = nil end
		schedule(1, true)
	end)
	-- the game's own proximity sort (C_QuestLog.SortQuestWatches, run by Blizzard's tracker) would undo ours: put
	-- ours back right after it.
	-- CONSTRAINT: at once, inside the post-hook, not 0.2 s later: the game sorts on QUEST_POI_UPDATE (opening the world
	-- map, a new zone), and with the delay its order showed for a moment and then ours (user: the tracker jitters when
	-- the map opens or the zone changes; icons flash, coins jump lines). Done before the tracker draws, only one order
	-- is ever seen. The 0.1 s pass after still places the zone headers.
	if C_QuestLog.SortQuestWatches then
		hooksecurefunc(C_QuestLog, "SortQuestWatches", function()
			if busy then return end
			local ok, err = pcall(sortWatches, true, true)
			if not ok then geterrorhandler()(err) end
		end)
	end
	-- you move: re-check every MOVE_CHECK s (15, was 4: "calmer sorting", user) and only re-orders when a different quest
	-- has become clearly closer (BUCKET). Only after you moved 20 yards or more since the last check (or every 30 s at
	-- the latest), so standing still costs nothing; a new zone and quest events re-sort on their own (above).
	local MOVE_CHECK = 15
	local lastPlace, idle = nil, 0
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(MOVE_CHECK, function()
		if not (db and db.zoneSort and db.enabled) or InCombatLockdown() then return end
		local here = playerPlace()
		idle = idle + 1
		if lastPlace and here and here.continent == lastPlace.continent and here.x and lastPlace.x and idle < 2 then
			local dx, dy = here.x - lastPlace.x, here.y - lastPlace.y
			if dx * dx + dy * dy < 400 then return end
		end
		lastPlace, idle = here, 0
		schedule(0, true)
	end) end
end
