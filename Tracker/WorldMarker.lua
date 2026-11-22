-- 3.1 World marker (Settings > Helpers > On screen). The idea comes from Questline (a marker on the game's navigation
-- frame); the code is our own. The game puts a frame where the super-tracked target stands in the world
-- (C_Navigation.GetFrame; NAVIGATION_FRAME_CREATED / _DESTROYED). We hang a label on it: the quest's name, its next
-- objective (or "Turn in"), the distance (C_Navigation.GetDistance, yards) and a thin light beam above the spot.
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

local marker
local function build()
	if marker then return marker end
	marker = CreateFrame("Frame", "RXPFTWorldMarker", UIParent)
	marker:SetSize(220, 50)
	marker:SetFrameStrata("BACKGROUND")
	marker.title = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	marker.title:SetPoint("BOTTOM", marker, "BOTTOM", 0, 26)
	marker.title:SetTextColor(1, 0.82, 0.25)
	marker.title:SetShadowOffset(1, -1)
	marker.goal = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	marker.goal:SetPoint("TOP", marker.title, "BOTTOM", 0, -2)
	marker.goal:SetTextColor(0.9, 0.86, 0.78)
	marker.dist = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	marker.dist:SetPoint("TOP", marker.goal, "BOTTOM", 0, -2)
	marker.dist:SetTextColor(0.6, 0.85, 1)
	marker.beam = marker:CreateTexture(nil, "BACKGROUND")
	marker.beam:SetSize(6, 180)
	marker.beam:SetColorTexture(1, 1, 1, 1)
	if marker.beam.SetGradient and CreateColor then
		pcall(marker.beam.SetGradient, marker.beam, "VERTICAL", CreateColor(1, 0.82, 0.35, 0.55), CreateColor(1, 0.82, 0.35, 0))
	else
		marker.beam:SetColorTexture(1, 0.82, 0.35, 0.3)
	end
	marker.beam:SetBlendMode("ADD")
	marker:Hide()
	return marker
end

-- the super-tracked quest's next objective, or "Turn in"
local function goalOf(questID)
	if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then return "Turn in" end
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	if not (index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard) then return "" end
	for j = 1, GetNumQuestLeaderBoards(index) or 0 do
		local text, _, finished = GetQuestLogLeaderBoard(j, index)
		if not finished and type(text) == "string" and not isSecret(text) then return text end
	end
	return ""
end

local function target()
	local quest = C_SuperTrack and try(C_SuperTrack.GetSuperTrackedQuestID)
	if quest and quest > 0 then
		local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(quest)
		if type(title) == "string" and not isSecret(title) then return title, goalOf(quest) end
	end
	if C_SuperTrack and try(C_SuperTrack.IsSuperTrackingUserWaypoint) then return "Waypoint", "" end
	return nil
end

-- 3.1.1 speed: the clock runs only while the marker can show (switch on, a navigation frame, not hidden by combat).
-- Each tick only changes what changed: the anchor when the navigation frame is new, a text when it differs. The quest
-- name and next step are read again only after a quest log or super-track change, or every 0.5 s.
local TICK, TEXT_EVERY = 0.05, 0.5
local clock, anchoredTo
local shownText = {}
local textDirty, sinceText = true, 0
local function setText(fs, key, text)
	if shownText[key] ~= text then shownText[key] = text; fs:SetText(text) end
end
local function hideMarker()
	if marker and marker:GetAlpha() ~= 0 then marker:SetAlpha(0) end
end
local function update(self, elapsed)
	self.wait = (self.wait or 0) + elapsed
	if self.wait < TICK then return end
	sinceText = sinceText + self.wait
	self.wait = 0
	local nav = C_Navigation and try(C_Navigation.GetFrame)
	if not nav or not opt("worldMarker") or (opt("markerCombatHide") and inCombat()) then hideMarker() return end
	if textDirty or sinceText >= TEXT_EVERY then
		textDirty, sinceText = false, 0
		local title, goal = target()
		marker.hasTarget = title and true or false
		if title then
			setText(marker.title, "title", title)
			setText(marker.goal, "goal", goal or "")
		end
	end
	if not marker.hasTarget then hideMarker() return end
	if anchoredTo ~= nav then
		anchoredTo = nav
		marker:ClearAllPoints()
		marker:SetPoint("BOTTOM", nav, "TOP", 0, 6)
		marker.beam:ClearAllPoints()
		marker.beam:SetPoint("BOTTOM", nav, "CENTER", 0, 0)
	end
	if marker:GetAlpha() ~= 1 then marker:SetAlpha(1) end
	local yards = try(C_Navigation.GetDistance)
	setText(marker.dist, "dist", yards and not isSecret(yards) and (math.floor(yards + 0.5) .. " yd") or "")
	local beam = not try(C_Navigation.WasClampedToScreen)
	if marker.beamOn ~= beam then marker.beamOn = beam; marker.beam:SetShown(beam) end
end
-- start or stop the clock (events, the settings switches)
local navEvents = false
local function wake()
	if not clock then return end
	textDirty = true
	local can = opt("worldMarker") and not (opt("markerCombatHide") and inCombat())
	-- without the navigation frame events the clock cannot know when a frame comes, so it keeps running while on
	if can and navEvents then can = (C_Navigation and try(C_Navigation.GetFrame)) and true or false end
	if can then clock:Show() else clock:Hide(); hideMarker(); anchoredTo = nil end
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
function api.toggleMarkerAuto()
	db.markerAuto = not optOn("markerAuto")
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RXP ForeverTracker|r the marker picks the nearest quest: "
		.. (db.markerAuto and "on" or "off"))
	if db.markerAuto then lastAuto = nil; autoPick() end
end

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
