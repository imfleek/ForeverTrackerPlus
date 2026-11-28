-- 3.1 World marker (Settings > Helpers > On screen). The idea comes from Questline (a marker on the game's navigation
-- frame); the code is our own. The game puts a frame where the super-tracked target stands in the world
-- (C_Navigation.GetFrame; NAVIGATION_FRAME_CREATED / _DESTROYED). We hang a label on it: the quest's name, its next
-- objective (or "Turn in"), the distance (C_Navigation.GetDistance, yards) and a thin light beam above the spot.
-- 3.2 new look (user: "more polished and good looking", ideas from WaypointUI and a reference picture; our own art from
-- tests/make_marker.py): a gold diamond on the spot ("?" in it to turn in, a gem to go there), a soft glow that
-- breathes, a light beam up from it with a spark running up, and the text under it. It grows as you come closer, comes
-- in with a short pop when the target changes, fades while the mouse is over it, and its beam dims when you are there.
-- While it shows, the game's own icon and yards on that spot are made see-through (no double icon); at the screen
-- edge (the target is behind you) ours hides and the game's edge arrow shows.
--   db.worldMarker      (on)  the marker
--   db.markerCombatHide (on)  hidden in combat
--   db.markerAuto       (off) the nearest quest in the log becomes the super-tracked one by itself
--                             (C_QuestLog.GetDistanceSqToQuest). A quest you picked yourself (the map, the tracker, the
--                             focus) or a map waypoint is kept until it is done or leaves the log. Never in combat: a
--                             super-track change in combat makes the map's protected pins refresh.
-- All of C_Navigation / C_SuperTrack is checked before use and called in pcall.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function opt(key) return db and db[key] ~= false end
local function optOn(key) return db and db[key] == true end
local function try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	return nil
end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local GOLD, BLUE = { 1, 0.80, 0.35 }, { 0.55, 0.78, 1 }
local ICON = 34 -- the diamond's size at scale 1

-- an animation, set up only where the client has the calls (each one in pcall)
local function call(obj, method, ...)
	local fn = obj and obj[method]
	if type(fn) == "function" then pcall(fn, obj, ...) end
end
local function newAnim(group, kind)
	local ok, a = pcall(group.CreateAnimation, group, kind)
	return ok and a or nil
end

local marker
local function build()
	if marker then return marker end
	marker = CreateFrame("Frame", "RXPFTWorldMarker", UIParent)
	marker:SetSize(ICON, ICON)
	marker:SetFrameStrata("BACKGROUND")
	-- body: everything we draw; its alpha is the hover fade and the pop in, the marker's own alpha is shown or hidden
	local body = CreateFrame("Frame", nil, marker)
	body:SetAllPoints(marker)
	marker.body = body

	marker.beam = body:CreateTexture(nil, "BACKGROUND")
	marker.beam:SetTexture(TEX .. "MarkerBeam")
	marker.beam:SetBlendMode("ADD")
	marker.beam:SetSize(24, 230)
	marker.beam:SetPoint("BOTTOM", body, "CENTER", 0, 0)
	marker.spark = body:CreateTexture(nil, "BACKGROUND", nil, 1)
	marker.spark:SetTexture(TEX .. "MarkerGlow")
	marker.spark:SetBlendMode("ADD")
	marker.spark:SetSize(12, 28)
	marker.spark:SetPoint("BOTTOM", body, "CENTER", 0, 10)
	marker.glow = body:CreateTexture(nil, "BORDER")
	marker.glow:SetTexture(TEX .. "MarkerGlow")
	marker.glow:SetBlendMode("ADD")
	marker.glow:SetSize(ICON * 2.2, ICON * 2.2)
	marker.glow:SetPoint("CENTER")
	marker.diamond = body:CreateTexture(nil, "ARTWORK")
	marker.diamond:SetTexture(TEX .. "MarkerDiamond")
	marker.diamond:SetSize(ICON, ICON)
	marker.diamond:SetPoint("CENTER")
	marker.gem = body:CreateTexture(nil, "OVERLAY")
	marker.gem:SetTexture(TEX .. "MarkerGem")
	marker.gem:SetSize(ICON * 0.4, ICON * 0.4)
	marker.gem:SetPoint("CENTER")
	marker.mark = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	marker.mark:SetPoint("CENTER", 0, 1)
	marker.mark:SetText("?")
	marker.mark:SetTextColor(1, 0.86, 0.2)
	local font = GameFontNormalLarge and GameFontNormalLarge.GetFont and GameFontNormalLarge:GetFont()
	if font then call(marker.mark, "SetFont", font, 17, "OUTLINE") end

	marker.title = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	marker.title:SetPoint("TOP", marker.diamond, "BOTTOM", 0, -6)
	marker.title:SetTextColor(1, 0.82, 0.25)
	marker.title:SetShadowOffset(1, -1)
	marker.goal = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	marker.goal:SetPoint("TOP", marker.title, "BOTTOM", 0, -2)
	marker.goal:SetTextColor(0.92, 0.88, 0.80)
	marker.goal:SetShadowOffset(1, -1)
	marker.dist = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	marker.dist:SetPoint("TOP", marker.goal, "BOTTOM", 0, -2)
	marker.dist:SetTextColor(0.72, 0.72, 0.72)
	marker.dist:SetShadowOffset(1, -1)

	-- the glow breathes, a spark runs up the beam
	local pulse = body.CreateAnimationGroup and body:CreateAnimationGroup()
	if pulse then
		call(pulse, "SetLooping", "BOUNCE")
		local a = newAnim(pulse, "Alpha")
		if a then call(a, "SetFromAlpha", 0.45); call(a, "SetToAlpha", 0.9); call(a, "SetDuration", 1.4); call(a, "SetSmoothing", "IN_OUT") end
		call(pulse, "SetTarget", marker.glow)
		if a then call(a, "SetTarget", marker.glow) end
		call(pulse, "Play")
	end
	local run = body.CreateAnimationGroup and body:CreateAnimationGroup()
	if run then
		call(run, "SetLooping", "REPEAT")
		local t = newAnim(run, "Translation")
		if t then call(t, "SetOffset", 0, 170); call(t, "SetDuration", 2.4); call(t, "SetTarget", marker.spark) end
		local fadeIn = newAnim(run, "Alpha")
		if fadeIn then call(fadeIn, "SetFromAlpha", 0); call(fadeIn, "SetToAlpha", 0.8); call(fadeIn, "SetDuration", 0.5); call(fadeIn, "SetTarget", marker.spark) end
		local fadeOut = newAnim(run, "Alpha")
		if fadeOut then call(fadeOut, "SetFromAlpha", 0.8); call(fadeOut, "SetToAlpha", 0); call(fadeOut, "SetStartDelay", 1.4)
			call(fadeOut, "SetDuration", 1.0); call(fadeOut, "SetTarget", marker.spark) end
		call(run, "Play")
	end
	-- the pop in: the diamond comes in big and settles (the body fades in with it, in update)
	local pop = body.CreateAnimationGroup and body:CreateAnimationGroup()
	if pop then
		local s = newAnim(pop, "Scale")
		if s then
			call(s, "SetTarget", marker.diamond)
			if s.SetScaleFrom then call(s, "SetScaleFrom", 1.8, 1.8); call(s, "SetScaleTo", 1, 1)
			else call(s, "SetFromScale", 1.8, 1.8); call(s, "SetToScale", 1, 1) end
			call(s, "SetDuration", 0.35); call(s, "SetSmoothing", "OUT")
		end
		marker.pop = pop
	end
	marker:Hide()
	return marker
end

-- gold for quests (a "?" to turn in, a gem to go there), blue for a map waypoint
local function setKind(kind)
	if marker.kind == kind then return end
	marker.kind = kind
	local c = kind == "waypoint" and BLUE or GOLD
	marker.beam:SetVertexColor(c[1], c[2], c[3], 0.9)
	marker.spark:SetVertexColor(c[1], c[2], c[3], 1)
	marker.glow:SetVertexColor(c[1], c[2], c[3], 1)
	if kind == "waypoint" then marker.gem:SetVertexColor(0.65, 0.85, 1) else marker.gem:SetVertexColor(1, 1, 1) end
	marker.gem:SetShown(kind ~= "turnin")
	marker.mark:SetShown(kind == "turnin")
	if kind == "waypoint" then marker.title:SetTextColor(0.7, 0.88, 1) else marker.title:SetTextColor(1, 0.82, 0.25) end
end

-- The game's own icon and yards on the spot: see-through while ours shows there, back when ours is gone.
local gameHidden = false
local function gameParts(hide)
	local f = SuperTrackedFrame
	if type(f) ~= "table" then return end
	local want = hide and 0 or 1
	for _, key in ipairs({ "Icon", "DistanceText", "Time" }) do
		local part = f[key]
		if type(part) == "table" and part.SetAlpha and (not part.GetAlpha or part:GetAlpha() ~= want) then
			pcall(part.SetAlpha, part, want)
		end
	end
	gameHidden = hide
end

-- the super-tracked quest's next objective, or "Turn in"
local function goalOf(questID)
	if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then return "Turn in", "turnin" end
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	if not (index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard) then return "", "quest" end
	for j = 1, GetNumQuestLeaderBoards(index) or 0 do
		local text, _, finished = GetQuestLogLeaderBoard(j, index)
		if not finished and type(text) == "string" and not isSecret(text) then return text, "quest" end
	end
	return "", "quest"
end

local function target()
	local quest = C_SuperTrack and try(C_SuperTrack.GetSuperTrackedQuestID)
	if quest and quest > 0 then
		local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(quest)
		if type(title) == "string" and not isSecret(title) then
			local goal, kind = goalOf(quest)
			return title, goal, kind
		end
	end
	if C_SuperTrack and try(C_SuperTrack.IsSuperTrackingUserWaypoint) then return "Waypoint", "", "waypoint" end
	return nil
end

-- bigger when close (as WaypointUI): 1.15 at 20 yards and under, down to 0.7 at 420 yards and more
local function scaleFor(yards)
	if not yards then return 0.9 end
	return math.max(0.7, math.min(1.15, 1.15 - (yards - 20) / 400 * 0.45))
end

-- 3.1.1 speed: the clock runs only while the marker can show (switch on, a navigation frame, not hidden by combat).
-- Each tick only changes what changed: the anchor when the navigation frame is new, a text when it differs. The quest
-- name and next step are read again only after a quest log or super-track change, or every 0.5 s.
local TICK, TEXT_EVERY = 0.05, 0.5
local clock, anchoredTo
local shownText = {}
local textDirty, sinceText = true, 0
local shownTitle
local function setText(fs, key, text)
	if shownText[key] ~= text then shownText[key] = text; fs:SetText(text) end
end
local function hideMarker()
	if marker and marker:GetAlpha() ~= 0 then marker:SetAlpha(0) end
	if gameHidden then gameParts(false) end
end
local function update(self, elapsed)
	self.wait = (self.wait or 0) + elapsed
	if self.wait < TICK then return end
	local step = self.wait
	sinceText = sinceText + step
	self.wait = 0
	local nav = C_Navigation and try(C_Navigation.GetFrame)
	if not nav or not opt("worldMarker") or (opt("markerCombatHide") and inCombat()) then hideMarker() return end
	if textDirty or sinceText >= TEXT_EVERY then
		textDirty, sinceText = false, 0
		local title, goal, kind = target()
		marker.hasTarget = title and true or false
		if title then
			setText(marker.title, "title", title)
			setText(marker.goal, "goal", goal or "")
			setKind(kind)
			if shownTitle ~= title then -- a new target: the pop in
				shownTitle = title
				marker.fade = 0
				if marker.pop then call(marker.pop, "Stop"); call(marker.pop, "Play") end
			end
		end
	end
	-- at the screen edge the game's arrow points the way; ours would only sit on the edge
	if not marker.hasTarget or try(C_Navigation.WasClampedToScreen) then hideMarker() return end
	if anchoredTo ~= nav then
		anchoredTo = nav
		marker:ClearAllPoints()
		marker:SetPoint("CENTER", nav, "CENTER", 0, 0)
	end
	if marker:GetAlpha() ~= 1 then marker:SetAlpha(1) end
	gameParts(true)
	local yards = try(C_Navigation.GetDistance)
	if yards and isSecret(yards) then yards = nil end
	local eta = yards and api.distanceEta and api.distanceEta(yards) -- 3.2 time to arrive
	setText(marker.dist, "dist", yards and (math.floor(yards + 0.5) .. " yd" .. (eta and ("  \194\183  " .. eta) or "")) or "")
	local scale = scaleFor(yards)
	if not marker.scale or math.abs(marker.scale - scale) > 0.01 then marker.scale = scale; marker:SetScale(scale) end
	local beam = yards and yards < 12 and 0.35 or 1 -- you are there: the beam dims
	-- 3.2 (user): arriving (inside 12 yards after being further than 20) bursts a gold ring out of the diamond
	if yards and yards >= 20 then marker.away = true end
	if yards and yards < 12 and marker.away then
		marker.away = nil
		if api.animArrive then api.animArrive(marker.body, marker.diamond, ICON) end
	end
	if marker.beamAlpha ~= beam then marker.beamAlpha = beam; marker.beam:SetAlpha(beam); marker.spark:SetShown(beam == 1) end
	-- the body's alpha: up to 1 after a pop, 0.3 while the mouse is over it (it never blocks what you look at)
	local want = (marker.body.IsMouseOver and marker.body:IsMouseOver(20, -60, -110, 110)) and 0.3 or 1
	local now = marker.fade or 1
	if now ~= want then
		now = now + (want - now) * math.min(1, step * 8)
		if math.abs(now - want) < 0.02 then now = want end
		marker.fade = now
		marker.body:SetAlpha(now)
	end
end
-- start or stop the clock (events, the settings switches)
local navEvents = false
local function wake()
	if not clock then return end
	textDirty = true
	local can = opt("worldMarker") and not (opt("markerCombatHide") and inCombat())
	-- without the navigation frame events the clock cannot know when a frame comes, so it keeps running while on
	if can and navEvents then can = (C_Navigation and try(C_Navigation.GetFrame)) and true or false end
	if can then clock:Show() else clock:Hide(); hideMarker(); anchoredTo = nil; shownTitle = nil end
end
api.refreshWorldMarker = wake
api.worldMarkerRunning = function() return clock and clock:IsShown() or false end -- (tests)

---------------------------------------------------------------------------------------------------------------------
-- The nearest quest, by itself
---------------------------------------------------------------------------------------------------------------------
local lastAuto
local function autoPick()
	if not (optOn("markerAuto") and C_SuperTrack and C_QuestLog.GetDistanceSqToQuest) or inCombat() then return end
	if try(C_SuperTrack.IsSuperTrackingUserWaypoint) then return end
	local current = try(C_SuperTrack.GetSuperTrackedQuestID) or 0
	local index = current > 0 and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(current)
	local chosenByUser = current > 0 and current ~= lastAuto and index and index > 0
	if chosenByUser then return end
	local best, bestD
	local count = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, count do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local d, onContinent = try(C_QuestLog.GetDistanceSqToQuest, info.questID)
			if d and onContinent and not isSecret(d) and (not bestD or d < bestD) then best, bestD = info.questID, d end
		end
	end
	if best and best ~= current then
		lastAuto = best
		try(C_SuperTrack.SetSuperTrackedQuestID, best)
	end
end
api.markerAutoPick = autoPick -- (tests)

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	if not (C_Navigation and C_Navigation.GetFrame) then return end
	build():Show()
	marker:SetAlpha(0)
	clock = CreateFrame("Frame")
	clock:SetScript("OnUpdate", function(self, elapsed)
		local ok, err = pcall(update, self, elapsed)
		if not ok then self:SetScript("OnUpdate", nil); geterrorhandler()(err) end
	end)
	local events = CreateFrame("Frame")
	navEvents = pcall(events.RegisterEvent, events, "NAVIGATION_FRAME_CREATED")
		and pcall(events.RegisterEvent, events, "NAVIGATION_FRAME_DESTROYED")
	for _, e in ipairs({ "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"PLAYER_ENTERING_WORLD" }) do pcall(events.RegisterEvent, events, e) end
	events:SetScript("OnEvent", function(_, event)
		if event == "QUEST_LOG_UPDATE" then textDirty = true return end
		-- the navigation frame is made or dropped just after its event: look again a moment later
		wake()
		if C_Timer and C_Timer.After then C_Timer.After(0.1, wake) end
	end)
	wake()
	if C_Timer.NewTicker then C_Timer.NewTicker(3, function() pcall(autoPick) end) end
end
