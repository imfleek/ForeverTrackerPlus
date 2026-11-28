-- ForeverTrackerPlus: corpse run helper (3.2, user idea 31).
-- While you are a ghost, a small window shows an arrow to your corpse, the yards and about how long the run takes at
-- your speed now; when you are close, how long until you can come back (GetCorpseRecoveryDelay); and what the spirit
-- healer costs (resurrection sickness from level 11: 1 minute for each level over 10, at most 10; 25 % durability).
-- The corpse: C_DeathInfo.GetCorpseMapPosition on the map you are on; turned to world yards as the quest arrows are
-- (ZoneSort.lua api.mapToWorld, Extras.lua api.turnTexture, the same DirArrow image).
-- Option: Helpers > Corpse run (db.corpseRun, on by default).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local ARROW = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\DirArrow"
local GHOST_SPEED = 7 * 1.25 -- (yards a second, when the game gives none)
local frame

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

local function xy(pos)
	if type(pos) ~= "table" then return nil end
	local x, y = pos.x, pos.y
	if pos.GetXY then x, y = pos:GetXY() end
	if isSecret(x) or isSecret(y) or type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
	return x, y
end

-- where the corpse is from you: yards, world angle (atan2 of west over north, as GetPlayerFacing); nil and why
-- ("you": the game gives no position for you here, "corpse": none for the corpse on your map)
-- 3.2 (user: "it says my corpse is not on the map, but it is", Warsong Gulch): both read on the map you are on and
-- measured with the map's size in yards (C_Map.GetMapWorldSize), which also works in battlegrounds and instances;
-- the world position (ZoneSort.lua api.mapToWorld) only when the size is not known
local function corpseDirection()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not map or isSecret(map) then return nil, "you" end
	local okP, ppos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	local px, py = xy(okP and ppos)
	if not px then return nil, "you" end
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil, "corpse" end
	local okC, cpos = pcall(C_DeathInfo.GetCorpseMapPosition, map)
	local cx, cy = xy(okC and cpos)
	if not cx then return nil, "corpse" end
	local north, west
	local okS, w, h = pcall(function() return C_Map.GetMapWorldSize(map) end)
	if okS and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 and not isSecret(w) then
		north, west = (py - cy) * h, (px - cx) * w -- map x grows east, map y grows south
	elseif api.mapToWorld then
		local c1, x1, y1 = api.mapToWorld(map, px, py)
		local c2, x2, y2 = api.mapToWorld(map, cx, cy)
		if not c1 or c1 ~= c2 then return nil, "corpse" end
		north, west = x2 - x1, y2 - y1
	else
		return nil, "corpse"
	end
	return math.sqrt(north * north + west * west), (math.atan2 or math.atan)(west, north)
end
api.corpseDirection = corpseDirection -- (tests)

-- what the spirit healer costs at your level (one line)
local function healerText(level)
	level = tonumber(level) or 1
	if level < 11 then return "Spirit healer: no sickness below level 11; 25 % durability" end
	local minutes = math.min(level - 10, 10)
	return ("Spirit healer: %d min of resurrection sickness and 25 %% durability"):format(minutes)
end
api.corpseHealerText = healerText -- (tests)

local function runText(yards, speed)
	speed = (type(speed) == "number" and speed > 0) and speed or GHOST_SPEED
	return ("Your corpse: |cffffffff%d yd|r  (about %d s)"):format(math.floor(yards + 0.5), math.ceil(yards / speed))
end
api.corpseRunText = runText -- (tests)

local function build()
	local kit = api.themeKit
	local f = CreateFrame("Frame", "ForeverTrackerPlusCorpseRun", UIParent)
	f:SetSize(300, 82)
	f:SetPoint("TOP", 0, -170)
	f:SetFrameStrata("MEDIUM")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if kit then
		kit.solid(f, "BACKGROUND", kit.C.window, 0.85):SetAllPoints()
		kit.border(f, kit.C.edge, 1, "BORDER")
	end
	f.arrow = f:CreateTexture(nil, "ARTWORK")
	f.arrow:SetSize(44, 44)
	f.arrow:SetPoint("LEFT", 10, 0)
	f.arrow:SetTexture(ARROW)
	-- 3.2 (user): close enough to come back: a gold glow pulses behind the arrow (Animations.lua animCorpseGlow)
	f.glow = f:CreateTexture(nil, "BORDER")
	f.glow:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\MarkerGlow")
	f.glow:SetBlendMode("ADD")
	f.glow:SetVertexColor(1, 0.82, 0.25, 1)
	f.glow:SetSize(76, 76)
	f.glow:SetPoint("CENTER", f.arrow, "CENTER")
	f.glow:Hide()
	f.line1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.line1:SetPoint("TOPLEFT", 62, -12)
	f.line1:SetJustifyH("LEFT")
	f.line2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.line2:SetPoint("TOPLEFT", f.line1, "BOTTOMLEFT", 0, -5)
	f.line2:SetJustifyH("LEFT")
	f.line3 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.line3:SetPoint("TOPLEFT", f.line2, "BOTTOMLEFT", 0, -5)
	f.line3:SetJustifyH("LEFT")
	local since = 1
	f:SetScript("OnUpdate", function(self, dt)
		since = since + (dt or 0)
		if since < 0.1 then return end
		since = 0
		local yards, angle = corpseDirection()
		local why = angle
		if yards then
			local facing = GetPlayerFacing and GetPlayerFacing() or nil
			if facing ~= nil and (isSecret(facing) or type(facing) ~= "number") then facing = nil end
			if api.turnTexture then api.turnTexture(self.arrow, angle - (facing or 0)) end
			self.arrow:Show()
			local speed = GetUnitSpeed and GetUnitSpeed("player")
			self.line1:SetText(runText(yards, speed))
		else
			self.arrow:Hide()
			self.line1:SetText(why == "you" and "The game hides your position here" or "Your corpse is not on this map")
		end
		if api.animCorpseGlow then api.animCorpseGlow(self.glow, yards ~= nil and yards < 40) end
		local delay = GetCorpseRecoveryDelay and GetCorpseRecoveryDelay() or 0
		if type(delay) == "number" and delay > 0 then
			self.line2:SetText(("You can come back in %d s"):format(math.ceil(delay)))
		elseif yards and yards < 40 then
			self.line2:SetText("|cff44ff44Close enough: come back to life|r")
		else
			self.line2:SetText("Run to your corpse to come back to life")
		end
		-- (a battleground has no resurrection sickness: no spirit healer line there)
		local _, kind = IsInInstance and IsInInstance()
		self.line3:SetText((kind == "pvp" or kind == "arena") and "" or healerText(UnitLevel and UnitLevel("player")))
		-- 3.2 (user: "text also exceeds the box"): the box is as wide as its longest line
		local widest = 0
		for _, l in ipairs({ self.line1, self.line2, self.line3 }) do
			local sw = l.GetStringWidth and l:GetStringWidth()
			if type(sw) == "number" and sw > widest then widest = sw end
		end
		local want = math.max(220, math.ceil(widest) + 62 + 16)
		if math.abs((self:GetWidth() or 0) - want) > 1 then self:SetWidth(want) end
		self:SetHeight(self.line3:GetText() == "" and 66 or 82)
	end)
	f:Hide()
	frame = f
	return f
end

local function update()
	local db = ns.db
	local ghost = UnitIsGhost and UnitIsGhost("player")
	if isSecret(ghost) then ghost = false end
	local want = db and db.corpseRun ~= false and ghost and true or false
	if want and not frame then build() end
	if frame then frame:SetShown(want) end
end
api.updateCorpseRun = update

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
	if C_Timer and C_Timer.After then C_Timer.After(0.2, update) else update() end
end)
ns.onLogin[#ns.onLogin + 1] = function()
	for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(events.RegisterEvent, events, e)
	end
	update()
end

-- /ftp corpse: what the game gives here (to learn why no arrow shows)
if api.addSlash then
	api.addSlash("corpse", "what the game reports for the corpse arrow here", function(_, say)
		local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		local function show(v) return isSecret(v) and "secret" or tostring(v) end
		local okP, p = pcall(C_Map.GetPlayerMapPosition, map, "player")
		local okC, c = pcall(function() return C_DeathInfo.GetCorpseMapPosition(map) end)
		local okS, w, h = pcall(function() return C_Map.GetMapWorldSize(map) end)
		say(("map %s; you %s; corpse %s; map size %s x %s"):format(show(map),
			okP and type(p) == "table" and (show(p.x) .. ", " .. show(p.y)) or "none",
			okC and type(c) == "table" and (show(c.x) .. ", " .. show(c.y)) or "none",
			okS and show(w) or "?", okS and show(h) or "?"))
		local yards, why = corpseDirection()
		say(yards and ("corpse %d yards away"):format(yards) or ("no arrow: " .. tostring(why)))
	end)
end

api.pageDeclarers = api.pageDeclarers or {}
api.pageDeclarers[#api.pageDeclarers + 1] = function(k)
	local db = ns.db
	k.page("corpserun", "quests", "Corpse run")
	k.pageByKey.corpserun.cardTitle = "When you die"
	k.check("Corpse run helper", function() return db.corpseRun ~= false end,
		function(v) db.corpseRun = v and true or false; update() end)
	k.help("as a ghost: an arrow to your corpse with the yards and the time, when you can come back, and what the spirit healer costs")
end
