-- R106-101: rares near your quests (user picked RareScanner's idea): a rare spotted in your zone, while that zone has
-- tracked quests, shows as a tag at the right end of its zone header: "★ Mother Fang 120 yd" (the nearest; "+N" for
-- more). Hover: its 3D model panel (NpcPanel.lua) and a tooltip with every rare spotted; click: a map waypoint to it
-- (when its place is known). Option: Quest list > "Rares near your quests" (db.rareAlert, on by default).
-- Spotted: the map's vignettes (C_VignetteInfo: a "kill" vignette, with its place on the map) and any unit you see
-- (nameplate, target, mouseover) whose classification is rare or rare elite. Gone: dead, or not seen for 2 minutes.
-- RareScanner keeps its data to itself (no public functions), so this needs no other addon.
-- CONSTRAINT: Forever declares C_VignetteInfo.GetVignettes / GetVignetteInfo / GetVignettePosition, VIGNETTES_UPDATED,
-- VIGNETTE_MINIMAP_UPDATED, NAME_PLATE_UNIT_ADDED, UnitClassification, C_Map.SetUserWaypoint and
-- C_SuperTrack.SetSuperTrackedUserWaypoint (wow-api docs, forever); each is checked before use. A once-a-second ticker
-- runs only while a rare is listed. Deaths: UNIT_DIED (its GUID; skipped when secret), never the combat log: an addon
-- may not register COMBAT_LOG_EVENT_UNFILTERED on Forever (HasRestrictions; ADDON_ACTION_FORBIDDEN, user's error).
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local FORGET = 120 -- seconds a rare stays listed after it was last seen
local STAR = "|TInterface\\AddOns\\" .. ADDON .. "\\Textures\\SilverStar:0|t"
local RARE = { rare = true, rareelite = true }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function enabled() return db and db.rareAlert ~= false end
api.rareAlertOn = enabled

local spotted = {} -- [key] = { name, npcId, guid, map, x, y, seen, vignette }
local tag, ticker

local function npcIdOf(guid)
	if type(guid) ~= "string" or isSecret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

local function playerZone()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name, (GetRealZoneText and GetRealZoneText()), map
end

local function remember(key, entry)
	local old = spotted[key]
	if old then
		for k, v in pairs(entry) do old[k] = v end
	else
		spotted[key] = entry
	end
end

-- a unit you see: a rare, alive and not a player's
local function onUnit(unit)
	if not (enabled() and unit and UnitExists(unit)) then return end
	if UnitIsPlayer(unit) or UnitIsDead(unit) then return end
	local class = UnitClassification and UnitClassification(unit)
	if isSecret(class) or not RARE[class] then return end
	local guid = UnitGUID(unit)
	local id = npcIdOf(guid)
	local name = UnitName(unit)
	if not id or isSecret(name) then return end
	local _, _, map = playerZone()
	remember("npc:" .. id, { name = name, npcId = id, guid = guid, seen = GetTime(), map = map, near = true })
end

-- the map's vignettes: the "kill" ones are rares, with their place
local function scanVignettes()
	if not (enabled() and C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
	local _, _, map = playerZone()
	local ok, list = pcall(C_VignetteInfo.GetVignettes)
	if not ok or type(list) ~= "table" then return end
	for _, vguid in ipairs(list) do
		local okI, info = pcall(C_VignetteInfo.GetVignetteInfo, vguid)
		local atlas = okI and type(info) == "table" and info.atlasName
		if type(atlas) == "string" and not isSecret(atlas) and atlas:lower():find("kill") and not info.isDead then
			local id = npcIdOf(info.objectGUID)
			local key = id and ("npc:" .. id) or ("v:" .. tostring(info.vignetteID or vguid))
			local entry = { name = info.name, npcId = id, seen = GetTime(), map = map, vignette = vguid }
			if map and C_VignetteInfo.GetVignettePosition then
				local okP, pos = pcall(C_VignetteInfo.GetVignettePosition, vguid, map)
				if okP and pos then
					local x, y = pos.x, pos.y
					if pos.GetXY then x, y = pos:GetXY() end
					if type(x) == "number" and not isSecret(x) then entry.x, entry.y = x, y end
				end
			end
			if type(entry.name) == "string" and not isSecret(entry.name) then remember(key, entry) end
		end
	end
end

-- dead or long unseen: off the list
local function forget(guid)
	local now = GetTime()
	for key, r in pairs(spotted) do
		if (guid and r.guid == guid) or now - (r.seen or 0) > FORGET then spotted[key] = nil end
	end
end

-- yards from you to a rare with a known place
local function yards(r)
	if not (r.x and r.map and api.playerWorldPos and C_Map.GetWorldPosFromMapPos) then return nil end
	local me = api.playerWorldPos()
	if not me then return nil end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, r.map, CreateVector2D(r.x, r.y))
	if not (ok and pos and continent == me.continent) then return nil end
	local px, py = pos.x, pos.y
	if pos.GetXY then px, py = pos:GetXY() end
	return math.sqrt((px - me.x) ^ 2 + (py - me.y) ^ 2)
end
api.rareYards = yards

-- the rares listed, nearest first ({ entry, yards } pairs)
function api.raresSpotted()
	local list = {}
	for _, r in pairs(spotted) do list[#list + 1] = { r = r, d = yards(r) or (r.near and 0) or nil } end
	table.sort(list, function(a, b)
		if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
		if a.d and b.d and a.d ~= b.d then return a.d < b.d end
		return (a.r.seen or 0) > (b.r.seen or 0)
	end)
	return list
end

local function distanceText(d, r)
	if d and d > 0 then return ("%d yd"):format(math.floor(d + 0.5)) end
	if r.near then return "nearby" end
	return ""
end

local function buildTag()
	if tag then return tag end
	tag = CreateFrame("Button", "RXPForeverTrackerRareTag", UIParent)
	tag:SetSize(10, 14)
	tag.text = tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tag.text:SetPoint("RIGHT")
	tag.text:SetJustifyH("RIGHT")
	tag:RegisterForClicks("LeftButtonUp")
	tag:SetScript("OnEnter", function(self)
		local first = self.list and self.list[1]
		if first and api.showNpcPanel then
			api.showNpcPanel(first.r.name, { id = first.r.npcId, kind = "enemy", owner = self })
		end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine("Rares near your quests", 1, 0.82, 0)
		for _, e in ipairs(self.list or {}) do
			GameTooltip:AddDoubleLine(e.r.name, distanceText(e.d, e.r), 1, 1, 1, 0.8, 0.8, 0.8)
		end
		if first and first.r.x then GameTooltip:AddLine("Click: map waypoint to the nearest.", 0.6, 0.6, 0.6) end
		GameTooltip:Show()
	end)
	tag:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if api.hideNpcPanel then api.hideNpcPanel(self) end
	end)
	tag:SetScript("OnClick", function(self)
		local first = self.list and self.list[1]
		local r = first and first.r
		if not (r and r.x and r.map and C_Map.SetUserWaypoint and UiMapPoint) then return end
		pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(r.map, r.x, r.y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
		end
	end)
	tag:Hide()
	return tag
end

-- the tag on your zone's header (only a zone with tracked quests has one)
local function refresh()
	forget()
	local list = enabled() and api.raresSpotted() or {}
	local label
	if #list > 0 and api.zoneLabelFor then
		local mapName, realName = playerZone()
		label = api.zoneLabelFor(mapName) or api.zoneLabelFor(realName)
	end
	if not label then
		if tag then
			tag:Hide()
			tag.list = nil
		end
	else
		buildTag()
		tag.list = list
		local first = list[1]
		local more = #list > 1 and (" |cffaaaaaa+%d|r"):format(#list - 1) or ""
		local dist = distanceText(first.d, first.r)
		tag.text:SetFont(label:GetFont())
		tag.text:SetText(("%s |cffff5722%s|r%s%s"):format(STAR, first.r.name, dist ~= "" and (" |cffcccccc" .. dist .. "|r") or "", more))
		tag:SetParent(label:GetParent())
		tag:SetFrameLevel((label:GetParent():GetFrameLevel() or 1) + 5)
		tag:ClearAllPoints()
		local module = _G.QuestObjectiveTracker
		tag:SetPoint("BOTTOM", label, "BOTTOM", 0, 0)
		tag:SetPoint("RIGHT", module or label:GetParent(), "RIGHT", -4, 0)
		tag:SetSize(math.max(tag.text:GetStringWidth() or 10, 10), math.max(tag.text:GetStringHeight() or 12, 12))
		tag:Show()
	end
	if ticker and next(spotted) == nil then
		ticker:Cancel()
		ticker = nil
	elseif not ticker and next(spotted) ~= nil and C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(1, refresh)
	end
end
api.refreshRares = refresh

function api.setRareAlert(on)
	db.rareAlert = on and true or false
	if not db.rareAlert then wipe(spotted) end
	refresh()
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED",
		"UPDATE_MOUSEOVER_UNIT", "UNIT_DIED", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function(_, event, arg)
		if not enabled() then return end
		if event == "VIGNETTES_UPDATED" or event == "VIGNETTE_MINIMAP_UPDATED" then
			scanVignettes()
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			onUnit(arg)
		elseif event == "PLAYER_TARGET_CHANGED" then
			onUnit("target")
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			onUnit("mouseover")
		elseif event == "UNIT_DIED" then
			if not next(spotted) or isSecret(arg) then return end
			forget(arg)
		elseif event == "ZONE_CHANGED_NEW_AREA" then
			wipe(spotted)
		end
		refresh()
	end)
end
