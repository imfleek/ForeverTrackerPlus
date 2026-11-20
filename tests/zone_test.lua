local dir = arg[1]
local maps = {
	[947] = { name = "Azeroth", parentMapID = 0 },
	[12] = { name = "Kalimdor", parentMapID = 947 }, [13] = { name = "Eastern Kingdoms", parentMapID = 947 },
	[71] = { name = "Tanaris", parentMapID = 12, mapType = 3, c = { 12, 100, 100 } },
	[66] = { name = "Desolace", parentMapID = 12, mapType = 3, c = { 12, 300, 300 } },
	[15] = { name = "Badlands", parentMapID = 13, mapType = 3, c = { 13, 50, 50 } },
	[219] = { name = "Zul'Farrak", parentMapID = 71, mapType = 4 },
}
_G.Enum = { UIMapType = { Zone = 3 } }
_G.CreateVector2D = function(x, y) return { x = x, y = y } end
_G.C_Map = {
	GetBestMapForUnit = function() return 71 end,
	GetMapInfo = function(id) local m = maps[id]; return m and { name = m.name, parentMapID = m.parentMapID, mapType = m.mapType } end,
	GetMapChildrenInfo = function(root) local out = {}; for id, m in pairs(maps) do if id ~= root then out[#out + 1] = { mapID = id, name = m.name, mapType = m.mapType } end end; return out end,
	GetWorldPosFromMapPos = function(id, v) local m = maps[id]; if not (m and m.c) then return nil end; return m.c[1], { x = m.c[2] + (v.x - 0.5) * 20, y = m.c[3] + (v.y - 0.5) * 20 } end,
	GetPlayerMapPosition = function() return { x = 0.6, y = 0.6 } end,
}
_G.GetRealZoneText = function() return "Tanaris" end
_G.GetTime = function() return 0 end
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
_G.hooksecurefunc = function() end
_G.C_QuestLog = {}
local api = {}
local ns = { api = api, onLogin = {}, db = { zoneSort = true, enabled = true } }
assert(loadfile(dir .. "/Tracker/ZoneSort.lua"))("x", { tracker = ns })
ns.onLogin[1]()
local zones = { "Riverglades", "Badlands", "Desolace", "Zul'Farrak", "Tanaris" }
-- the same sort the tracker uses, via the module's sorted()
-- an upvalue found by name anywhere below fn (depth-first through function upvalues)
local function findUp(fn, name, seen)
	seen = seen or {}
	if seen[fn] then return nil end
	seen[fn] = true
	for i = 1, 200 do
		local n, v = debug.getupvalue(fn, i)
		if not n then break end
		if n == name then return v end
		if type(v) == "function" then
			local found = findUp(v, name, seen)
			if found then return found end
		end
	end
end
local sorted = findUp(api.sortNow, "sorted")
local sortWatches = findUp(api.sortNow, "sortWatches")
local list = {}
for i, z in ipairs(zones) do list[i] = { id = i, zone = z, index = i } end
local out = sorted(list)
local names = {}
for _, q in ipairs(out) do names[#names + 1] = q.zone end
print("tracked quest zones, closest first: " .. table.concat(names, ", "))
local mo = api.orderQuests({ { id = 1, zone = "Badlands", index = 1 }, { id = 2, zone = "Tanaris", index = 2 } }); print("More quests order:", mo[1].zone, mo[2].zone)

-- "Track all quests" + zone sort: the closest quests are the tracked ones (up to the game's limit), the rest go to
-- More quests, so the two read as one list sorted by distance
local function check(l, c) print((c and "ok   " or "FAIL ") .. l) end
_G.Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 2 } }
_G.InCombatLockdown = function() return false end
local log = { { isHeader = true, title = "Badlands" }, { questID = 11 }, { questID = 12 },
	{ isHeader = true, title = "Tanaris" }, { questID = 21 }, { questID = 22 } }
local zoneOf = { [11] = "Badlands", [12] = "Badlands", [21] = "Tanaris", [22] = "Tanaris" }
local watches = { 11, 12 } -- "Track all" filled the list in quest-log order: far-away Badlands first
C_QuestLog.GetNumQuestLogEntries = function() return #log end
C_QuestLog.GetInfo = function(i) return log[i] end
C_QuestLog.GetLogIndexForQuestID = function(id) for i, e in ipairs(log) do if e.questID == id then return i end end end
C_QuestLog.GetNumQuestWatches = function() return #watches end
C_QuestLog.GetQuestIDForQuestWatchIndex = function(i) return watches[i] end
C_QuestLog.GetQuestWatchType = function(id) for _, w in ipairs(watches) do if w == id then return 0 end end end
C_QuestLog.RemoveQuestWatch = function(id) for i, w in ipairs(watches) do if w == id then table.remove(watches, i) return end end end
C_QuestLog.AddQuestWatch = function(id) watches[#watches + 1] = id end
ns.db.trackMode = "all"
sortWatches(true)
local tracked = {}
for _, id in ipairs(watches) do tracked[#tracked + 1] = zoneOf[id] end
check("track all: the closest zone's quests are the tracked ones (" .. table.concat(tracked, ", ") .. ")",
	#watches == 2 and zoneOf[watches[1]] == "Tanaris" and zoneOf[watches[2]] == "Tanaris")
ns.db.trackMode = "manual"
watches = { 11, 12 }
sortWatches(true)
check("manual tracking: only re-ordered, the same quests stay tracked", #watches == 2
	and zoneOf[watches[1]] == "Badlands" and zoneOf[watches[2]] == "Badlands")

-- R106-37: calmer sorting while moving: quests swap only when one is clearly (100 yd) closer, re-checked every 15 s
local zsrc = io.open(dir .. "/Tracker/ZoneSort.lua"):read("a")
local bucketBody = zsrc:match("(local BUCKET = %d+\n.-\nend\n)")
local bucket = load(bucketBody .. "\nreturn bucket", "x", "t", setmetatable({ FAR = 1e12 }, { __index = _G }))()
check("quests 60 yd apart in the same 100 yd step count as equal (the current order stays)", bucket(110 * 110) == bucket(170 * 170))
check("quests 150 yd apart do not", bucket(40 * 40) ~= bucket(190 * 190))
check("re-checked every 15 s while moving (was 4)", zsrc:find("local MOVE_CHECK = 15", 1, true) ~= nil
	and zsrc:find("C_Timer.NewTicker(MOVE_CHECK", 1, true) ~= nil)
check("a new zone still sorts at once", zsrc:find('"ZONE_CHANGED_NEW_AREA" })', 1, true) ~= nil)

-- R106-38: the game's own sort (SortQuestWatches on QUEST_POI_UPDATE: opening the world map, a new zone) is put back
-- at once inside its post-hook, not 0.2 s later (its order showed for a moment: the jitter)
do
	local hooks, timers = {}, {}
	_G.hooksecurefunc = function(t, name, fn) if t == C_QuestLog then hooks[name] = fn end end
	_G.C_Timer = { After = function(d, f) timers[#timers + 1] = f end, NewTicker = function() end }
	_G.Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 4 } }
	C_QuestLog.SortQuestWatches = function() watches = { 11, 12, 21, 22 } end -- the game: its own order
	local api2 = {}
	local ns2 = { api = api2, onLogin = {}, db = { zoneSort = true, enabled = true, trackMode = "manual" } }
	assert(loadfile(dir .. "/Tracker/ZoneSort.lua"))("x", { tracker = ns2 })
	ns2.onLogin[1]()
	check("the game's sort is hooked", type(hooks.SortQuestWatches) == "function")
	local allBack = true
	for _ = 1, 6 do -- more than the 4 that other re-orders get in 10 s
		C_QuestLog.SortQuestWatches()
		hooks.SortQuestWatches()
		if not (zoneOf[watches[1]] == "Tanaris" and zoneOf[watches[2]] == "Tanaris") then allBack = false end
	end
	check("the game's order is put back at once, before any timer runs (6 times in a row)", allBack)
	local says = {}
	api2.zoneDebug(function(s) says[#says + 1] = s end)
	check("/qt debug counts the re-sorts", table.concat(says, "\n"):find("6 after the game's own sort", 1, true) ~= nil)
end

-- R106-40: the place last found is kept for a moment when every source finds none (the arrows went away with the
-- world map open / after a zone change)
do
	local now = 100
	_G.GetTime = function() return now end
	local waypoint = true
	C_QuestLog.GetNextWaypoint = function() if waypoint then return 71, 0.9, 0.9 end end
	C_QuestLog.GetDistanceSqToQuest = function() return 3000 * 3000, true end
	local me = { continent = 12, x = 100, y = 100, map = 71 }
	me.markers = {}
	local y1, a1 = api.questDirection(555, me)
	check("a direction from the game's waypoint", y1 ~= nil and a1 ~= nil)
	waypoint = false
	now = 110
	local me2 = { continent = 12, x = 101, y = 100, map = 71, markers = {} }
	local y2, a2 = api.questDirection(555, me2)
	check("the waypoint gone for a moment: the last place still gives yards and a direction", y2 ~= nil and a2 ~= nil
		and math.abs(y2 - y1) < 2)
	now = 200
	local y3, a3 = api.questDirection(555, { continent = 12, x = 101, y = 100, map = 71, markers = {} })
	check("after 60 s without a place: only the game's distance (no arrow)", a3 == nil and y3 ~= nil)
	_G.GetTime = function() return 0 end
end
-- R106-42: zone headers wait while a shown quest has no place yet
check("zone headers wait for every shown quest's place", zsrc:find("if api.retryZoneHeaders then api.retryZoneHeaders() end", 1, true) ~= nil)
check("zone header text set only when it differs", zsrc:find("if label:GetText() ~= w.header then label:SetText(w.header) end", 1, true) ~= nil)
