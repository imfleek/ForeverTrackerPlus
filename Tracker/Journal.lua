-- 3.2 Journal: kill counts for each mob (in its tooltip) and your path on the world map for this level.
--
-- Kill counts (db.killCounts, on by default): ForeverTrackerPlusDB.killLog["Name-Realm"][npcID] = kills.
--   CONSTRAINT: COMBAT_LOG_EVENT_UNFILTERED is forbidden on Forever (Rares.lua, forever_test). A kill is a mob we saw
--   fight us (target, focus, mouseover or a nameplate in combat, tapped by us or our group) that then shows as dead,
--   or whose GUID comes with UNIT_DIED. A GUID or name that is secret is skipped.
-- Path map (db.pathMap, on by default): ForeverTrackerPlusDB.pathLog["Name-Realm"][level] = { { map, x, y }, ... },
--   a point when you moved far enough (every 3 s at most, at most 1500 points a level). The world map shows the
--   points of this level on the map it shows, as small dots.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db
-- 3.2: the character key with the surname (Core.lua api.playerKey); without it (tests) "Name-Realm"
local function playerKey(...)
	if api.playerKey then return api.playerKey(...) end
	local name, realm = UnitName and UnitName("player"), GetRealmName and GetRealmName()
	if type(name) ~= "string" or (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then return nil end
	return name .. "-" .. tostring(realm or "")
end

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function charKey() -- 3.2: with the surname; logs saved under the first name move over
	if db then playerKey(db.killLog); playerKey(db.pathLog) end
	return playerKey()
end

---------------------------------------------------------------------------------------------------------------------
-- Kill counts
---------------------------------------------------------------------------------------------------------------------
local fought, counted = {}, {} -- guid -> npcID ; guid -> true
local sessionKills = 0
local function npcIdOf(guid)
	if type(guid) ~= "string" or isSecret(guid) then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end
api.journalNpcId = npcIdOf
local function killBook()
	if not db then return nil end
	local key = charKey()
	if not key then return nil end
	db.killLog = type(db.killLog) == "table" and db.killLog or {}
	db.killLog[key] = type(db.killLog[key]) == "table" and db.killLog[key] or {}
	return db.killLog[key]
end
function api.killCount(npcID)
	local book = killBook()
	return book and tonumber(book[npcID]) or 0
end
function api.killSessionCount() return sessionKills end
local function countKill(guid)
	if counted[guid] then return end
	local id = fought[guid]
	if not id then return end
	counted[guid] = true
	fought[guid] = nil
	local book = killBook()
	if not book then return end
	book[id] = (tonumber(book[id]) or 0) + 1
	sessionKills = sessionKills + 1
end
api.journalCountKill = countKill -- (tests)

local function flag(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	return ok and not isSecret(v) and v and true or false
end
local function look(unit)
	if not flag(UnitExists, unit) then return end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or type(guid) ~= "string" or isSecret(guid) then return end
	local id = npcIdOf(guid)
	if not id then return end
	if flag(UnitIsDead, unit) then
		countKill(guid)
		return
	end
	if counted[guid] then return end
	if flag(UnitIsTapDenied, unit) then return end -- another player's mob
	if flag(UnitAffectingCombat, unit) and flag(UnitCanAttack, "player", unit) then fought[guid] = id end
end
api.journalLook = look -- (tests)
local UNITS = { "target", "focus", "mouseover" }
for i = 1, 40 do UNITS[#UNITS + 1] = "nameplate" .. i end
local sinceScan = 0
local function scan()
	if not (db and db.killCounts ~= false) then return end
	for _, unit in ipairs(UNITS) do look(unit) end
end
local fightCount = 0
local function trimFought()
	fightCount = fightCount + 1
	if fightCount < 50 then return end
	fightCount = 0
	local n = 0
	for _ in pairs(fought) do n = n + 1 end
	if n > 300 then wipe(fought) end
	n = 0
	for _ in pairs(counted) do n = n + 1 end
	if n > 2000 then wipe(counted) end
end

-- the unit tooltip: "Killed: 12"
local tipHooked = false
local function addKillLine(tip, unit)
	if not (db and db.killCounts ~= false) then return end
	if type(unit) ~= "string" and tip.GetUnit then
		local ok, _, u = pcall(tip.GetUnit, tip)
		unit = ok and u or nil
	end
	if type(unit) ~= "string" or isSecret(unit) then return end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok then return end
	local id = npcIdOf(guid)
	if not id then return end
	local n = api.killCount(id)
	if n > 0 then tip:AddLine(("Killed: |cffffffff%d|r"):format(n), 0.75, 0.75, 0.75) end
end
local function hookTooltip()
	if tipHooked then return end
	tipHooked = true
	local proc = rawget(_G, "TooltipDataProcessor")
	local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
	if type(proc) == "table" and type(proc.AddTooltipPostCall) == "function" and kind then
		pcall(proc.AddTooltipPostCall, kind, function(tip)
			if tip == GameTooltip then pcall(addKillLine, tip) end
		end)
	elseif GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tip) pcall(addKillLine, tip) end)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Path map
---------------------------------------------------------------------------------------------------------------------
local MAX_POINTS, STEP = 1500, 0.004 -- map coordinates (0-1): about 15-30 yards in a zone
local function pathBook(level)
	if not db then return nil end
	local key = charKey()
	if not key then return nil end
	db.pathLog = type(db.pathLog) == "table" and db.pathLog or {}
	local mine = type(db.pathLog[key]) == "table" and db.pathLog[key] or {}
	db.pathLog[key] = mine
	-- only this level and the one before are kept (the map shows this level)
	for l in pairs(mine) do if type(l) == "number" and level and l < level - 1 then mine[l] = nil end end
	mine[level] = type(mine[level]) == "table" and mine[level] or {}
	return mine[level]
end
local lastMap, lastX, lastY
local function where()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
	if not okM or type(map) ~= "number" or isSecret(map) then return nil end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not okP or not pos then return nil end
	local okX, x, y = pcall(pos.GetXY, pos)
	if not okX or type(x) ~= "number" or isSecret(x) or isSecret(y) or (x == 0 and y == 0) then return nil end
	return map, x, y
end
local function record()
	if not (db and db.pathMap ~= false) then return end
	if flag(UnitOnTaxi, "player") then return end
	local map, x, y = where()
	if not map then return end
	if map == lastMap and math.abs(x - lastX) < STEP and math.abs(y - lastY) < STEP then return end
	lastMap, lastX, lastY = map, x, y
	local list = pathBook(UnitLevel("player") or 1)
	if not list then return end
	if #list >= MAX_POINTS then table.remove(list, 1) end
	list[#list + 1] = { map, math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000 }
end
api.journalRecord = record -- (tests)
function api.journalPath(level)
	local key = charKey()
	local mine = db and type(db.pathLog) == "table" and key and db.pathLog[key]
	return type(mine) == "table" and type(mine[level or UnitLevel("player") or 1]) == "table"
		and mine[level or UnitLevel("player") or 1] or {}
end

-- 3.2 (user: "I dont see gold dots of where I've went"): a point is drawn on whatever map is shown, not only the
-- exact map it was taken on (the zone's parent, the continent): through its place in the world (C_Map world
-- positions). With OpenMap's stitched map up (OpenMapAPI, MIT, read when loaded): through its own world space onto
-- the map its view sits on (WorldFromMap, then MapFromWorld; points past that map's edges show too).
local function openMap()
	local om = rawget(_G, "OpenMapAPI")
	if type(om) ~= "table" or type(om.IsStitched) ~= "function" then return nil end
	local ok, on = pcall(om.IsStitched)
	return ok and on and om or nil
end
local function project(src, x, y, shownId, om)
	if om then
		local okU, u, v = pcall(om.WorldFromMap, src, x, y)
		if not okU or not u then return nil end
		local okM, px, py = pcall(om.MapFromWorld, shownId, u, v)
		if okM and type(px) == "number" and type(py) == "number" then return px, py end
		return nil
	end
	if src == shownId then return x, y end
	if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
	local okW, continent, world = pcall(C_Map.GetWorldPosFromMapPos, src, CreateVector2D(x, y))
	if not okW or not world then return nil end
	local okP, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, shownId)
	if not okP or not pos then return nil end
	local px, py = pos:GetXY()
	if type(px) ~= "number" or isSecret(px) or isSecret(py) or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
	return px, py
end
api.journalProject = project -- (tests)

local layer, dots = nil, {}
local function drawPath()
	local map = _G.WorldMapFrame
	if not (map and map.ScrollContainer and map.ScrollContainer.Child) then return end
	local canvas = map.ScrollContainer.Child
	if not layer then
		layer = CreateFrame("Frame", nil, canvas)
		layer:SetAllPoints(canvas)
	end
	local om = openMap()
	local top = om and type(om.ArtTopLevel) == "function" and tonumber((select(2, pcall(om.ArtTopLevel)))) or 0
	layer:SetFrameLevel(math.max((canvas:GetFrameLevel() or 1) + 5, top + 1))
	local shown = 0
	local id = map.GetMapID and map:GetMapID()
	if db and db.pathMap ~= false and type(id) == "number" then
		local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
		local size = math.max(w / 220, 3)
		for _, p in ipairs(api.journalPath()) do
			local px, py
			if w > 0 then px, py = project(p[1], p[2], p[3], id, om) end
			if px then
				shown = shown + 1
				local dot = dots[shown]
				if not dot then
					dot = layer:CreateTexture(nil, "OVERLAY")
					dot:SetTexture("Interface\\Buttons\\WHITE8x8")
					dot:SetVertexColor(1, 0.82, 0.1, 0.85)
					dots[shown] = dot
				end
				dot:SetSize(size, size)
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", layer, "TOPLEFT", px * w, -py * h)
				dot:Show()
			end
		end
	end
	for i = shown + 1, #dots do dots[i]:Hide() end
end
api.journalDrawPath = drawPath
local mapHooked = false
local function hookMap()
	local map = _G.WorldMapFrame
	if mapHooked or not map then return end
	mapHooked = true
	if map.HookScript then pcall(map.HookScript, map, "OnShow", drawPath) end
	if type(map.OnMapChanged) == "function" then pcall(hooksecurefunc, map, "OnMapChanged", drawPath) end
	-- OpenMap switched between its stitched map and Blizzard's own: drawn again
	local om = rawget(_G, "OpenMapAPI")
	if type(om) == "table" and type(om.RegisterCallback) == "function" then
		pcall(om.RegisterCallback, ADDON .. "Path", "OpenMap_StitchedChanged", function()
			if map:IsShown() then drawPath() end
		end)
	end
end
function api.clearPath()
	local key = charKey()
	if db and type(db.pathLog) == "table" and key then db.pathLog[key] = nil end
	lastMap = nil
	drawPath()
end

---------------------------------------------------------------------------------------------------------------------
-- Events, ticker
---------------------------------------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a)
	if event == "UNIT_DIED" then
		if type(a) == "string" and not isSecret(a) then countKill(a) end
	elseif event == "PLAYER_TARGET_CHANGED" then look("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then look("mouseover")
	elseif event == "PLAYER_LEVEL_UP" then lastMap = nil; if WorldMapFrame and WorldMapFrame:IsShown() then drawPath() end
	end
end)

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	for _, e in ipairs({ "UNIT_DIED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_LEVEL_UP" }) do
		pcall(events.RegisterEvent, events, e)
	end
	hookTooltip()
	hookMap()
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(0.5, function()
			sinceScan = sinceScan + 0.5
			if flag(UnitAffectingCombat, "player") then scan(); trimFought() end
			if sinceScan >= 3 then sinceScan = 0; record() end
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Settings: Helpers > Reminders (the page itself is Reminders.lua's; these rows are added there)
---------------------------------------------------------------------------------------------------------------------
function api.declareJournalRows(k)
	k.heading("Kills and path")
	k.check("Kill count in mob tooltips", function() return db.killCounts ~= false end,
		function(v) db.killCounts = v and true or false end)
	k.help("hover a mob to see how many this character has killed (counted since 3.2)")
	k.check("Your path on the world map", function() return db.pathMap ~= false end,
		function(v) db.pathMap = v and true or false; drawPath() end)
	k.help("small gold dots where you went during this level")
	k.buttons("Clear path", { { "Clear path", function() api.clearPath() end, 120 } })
end
