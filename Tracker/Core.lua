-- RXP ForeverTracker (tracker half): mouse-wheel scrolling (with a scrollbar) for Blizzard's default objective tracker.
--
-- Blizzard modules are only post-hooked and moved with SetPoint, nothing of Blizzard's is replaced or written to.
--
-- LAYOUT (top to bottom):
--   ghost     invisible frame at the position Blizzard (Edit Mode) gives the tracker, or where the user dragged it.
--             The tracker stays anchored to it and never moves.
--   strip     header of the tracker ("All Objectives" + collapse button) and the AllObjectives RXP guide: always visible.
--   viewport  clipping frame under the strip; the quest modules are drawn inside it.
--   scrolling the first module under the strip is moved up/down by changing its own TOP anchor: every module after it is
--             anchored to the previous one (ObjectiveTrackerContainerMixin:Update, mirrored by AllObjectives RXP), so the
--             whole quest list follows and the viewport clips it.
--   tracker   made EXTRA pixels taller than Blizzard wants (it lives inside the viewport, so this is never visible), so
--             Blizzard lays out every module instead of truncating those that do not fit; grows if still truncated.
local ADDON, root = ...; local ns = root.tracker
ns.api, ns.onLogin = {}, {}
local tracker = _G.ObjectiveTrackerFrame
if not tracker or root.disabledAll then ns.disabled = true return end

-- CONSTRAINT: Edit Mode replaces the tracker's SetPoint / ClearAllPoints / SetScale / SetParent with its own Lua
-- versions and keeps the plain ones as <name>Base. Calling the Edit Mode versions from here ran Edit Mode's own
-- bookkeeping (anchor-changed flags) as addon code, so it was tainted, and Edit Mode's next layout pass ran tainted:
-- InvokeOnAnyEditModeSystemAnchorChanged -> GetAuraDataByIndex "Auras cannot be accessed when secret while tainted by
-- 'RXPForeverTracker'". The tracker is moved, scaled and parented here only through the plain methods (Base where
-- Edit Mode has them); Edit Mode is not told, and the hooks below still see each call.
local function plain(method)
	local f = tracker[method .. "Base"]
	if type(f) ~= "function" then f = tracker[method] end
	return f
end
local function moveTracker(method, ...)
	return plain(method)(tracker, ...)
end
ns.api.moveTracker = moveTracker

local EXTRA, MAX_EXTRA = 3000, 8000
local GUIDE_SLOT = 1.5 -- AllObjectives RXP puts its module after uiOrder 1 (Scenario)
local BAR_WIDTH = 10 -- default; /qt Quest list "Scrollbar width" (db.scrollbarWidth)
local DEFAULTS = { enabled = true, step = 40, height = 500, scale = 1, locked = true, zoneSort = true, zoneFilter = false, spacing = 0, zoneHeaderScale = 1, zoneHeaderOutline = false, guideDetached = false, scrollbarWidth = 10, questCount = true, questCountSize = 0, questCountCustom = false, questCountColor = { 1, 1, 1, 1 }, questsHeaderColor = false, questsLineColor = false, zoneHeaderX = 4, zoneHeaderY = 0, questTitleX = 0, zoneHeaderColor = { 0.2, 0.85, 0.55 }, tooltips = true, widthExtra = 0, condense = true, progressBars = true, progressBarUnder = false, progressBarBlue = false, titleOutline = false, objectiveOutline = false, pinQuestsHeader = false, distanceText = true, distanceArrow = true, dungeonCard = true, dungeonHeader = true, questGroupFinder = true, npcPanelQuests = true, instanceCap = true, rareAlert = true, expandCurrentZone = false, repTrack = true, profAbove = true, profScrollbar = true, profScrollbarMouseover = false, profScrollbarWidth = 10, profX = 0, profY = 0, questDistance = true, distArrowScale = 1, distArrowAlpha = 1, showXP = true, wordWrap = true, showGold = true, scrollbar = true, scrollbarMouseover = false, zoneHeaderPadY = 6, xpColor = { 0.69, 0.53, 1 }, trackMode = "all", partyProgress = true, configTextSize = 1.15, rewardOrder = { "xp", "gold" }, iconScale = 1, iconAlpha = 1, completeCheck = true, completeCheckScale = 1, completeCheckAlpha = 1, completeCheckColor = false, completeCheckOutline = false, orphanSort = "level", orphanReverse = false, layer = 1, goldCoins = false, xpOrb = false, itemsLeft = true, guideScale = 1, questScale = 1, moreQuests = true, tooltipCoins = false,
	tooltipXpOrb = false, zoneOrder = "closest", font = "default", questsPadY = 0, questie = true,
	questieChain = true, questieChainReward = true, questieUnlocks = true, attunementStar = true,
	background = false, backgroundColor = { 0, 0, 0, 0.4 }, backgroundPad = 6, trackerAlpha = 1, guideAlpha = 1, questAlpha = 1 }
local db
local function barWidth()
	local w = db and tonumber(db.scrollbarWidth)
	return w and math.min(math.max(math.floor(w + 0.5), 2), 30) or BAR_WIDTH
end

local ghost, viewport, strip, handle, bar, thumb

-- General opacity (/qt Advanced): every frame of the tracker (quests, RXP guide, header strip, background, divider,
-- drag handle, scrollbar, More quests, the step buttons); never the settings windows.
local function trackerAlpha()
	local a = tonumber(db and db.trackerAlpha) or 1
	return math.min(math.max(a, 0.1), 1)
end
-- RXP Tracker opacity and Quest Tracker opacity: each a factor on the general opacity (as the two scales)
local function factor(key)
	local a = tonumber(db and db[key]) or 1
	return math.min(math.max(a, 0.1), 1)
end
local function guideAlpha() return factor("guideAlpha") end
local function questAlpha() return factor("questAlpha") end
local applyQuestAlpha
local alphaFrames = {}
local isForeign -- below: the guide modules (foreign) versus the game's quest modules
-- the game's own sections (quests, campaign, bonus objectives, ...) at the Quest Tracker opacity; the viewport gives
-- the general one
function applyQuestAlpha()
	local a = questAlpha()
	for _, module in ipairs(tracker and tracker.modules or {}) do
		if not (isForeign and isForeign(module)) and module.SetAlpha then module:SetAlpha(a) end
	end
end
local pinnedAlpha = {} -- guide modules pinned above the viewport (parented to UIParent)
local function withAlpha(frame)
	if frame then
		alphaFrames[frame] = true
		frame:SetAlpha(trackerAlpha())
	end
	return frame
end
ns.api.trackerAlpha = trackerAlpha
-- what the RXP guide's step buttons and the More quests list (both on UIParent) are drawn at
function ns.api.guideTrackerAlpha() return trackerAlpha() * guideAlpha() end
function ns.api.questTrackerAlpha() return trackerAlpha() * questAlpha() end
local recordHome, homePosition -- defined with the anchor capture
local naturalW, naturalH = 0, 0   -- the size Blizzard wants for the tracker (tracker units)
local anchors = {}                -- the tracker's anchors as Blizzard set them
local offset = 0                  -- scroll position in screen pixels
local extraNow = EXTRA
local guard, depth = false, 0     -- true while this addon itself moves frames (ignore our own hooks)
local foreign = {}                -- modules from other addons (AllObjectives RXP)
function isForeign(module)
	for _, other in ipairs(foreign) do if other == module then return true end end
	return false
end
local guide                       -- the visible foreign module, if any
local pinGuide = false            -- guide sits directly under the header and stays fixed
local pinned = 0                  -- height of the fixed strip (header + guide), screen pixels
local follower                    -- first visible module under the strip: the one that is moved to scroll
local guideShift = 0              -- R106-92: the pinned guide moved down by the dungeon card above it, screen pixels
local profHeld                    -- R106-57: the Professions section while it sits in its own box above the tracker
local placeProf                   -- (below) puts it at its scroll position in that box
local layoutProfessions           -- (below) the box: place, height for 2 recipes, scrollbar
local bases = setmetatable({}, { __mode = "k" }) -- module -> { [point] = {rel, relPoint, x, y} } as its owner anchored it
local hooked = {}
local fitCap                      -- window height limit so it never runs off the bottom of the screen
local wheelEvents = 0
local needsLayout = false         -- a layout change arrived during combat or from a hook; handled in refresh
local warned = false
local dragging

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RXP ForeverTracker|r " .. msg) end
ns.say = say

local function guarded(fn)
	depth = depth + 1
	guard = true
	local ok, err = pcall(fn)
	depth = depth - 1
	guard = depth > 0
	if not ok then geterrorhandler()(err) end
end

local function scale() return db.scale or 1 end
-- The RestedXP Tracker and Quest Tracker scales multiply the general scale (which scales the whole tracker frame):
-- the quest modules are children of the tracker, and the guide module is scaled to the tracker's scale times its own
-- factor (Objectives/tracker/Tracker.lua place()).
local SCALE_MIN, SCALE_MAX = 0.5, 1.5
local function factor(value) return math.min(math.max(tonumber(value) or 1, SCALE_MIN), SCALE_MAX) end
local function questScale() return factor(db and db.questScale) end

local function toScreen(frame, value)
	return value * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function markDirty()
	if tracker.MarkDirty then pcall(securecallfunction, tracker.MarkDirty, tracker) end
end

local function moduleVisible(module)
	return module:IsShown() and (module.GetContentsHeight == nil or module:GetContentsHeight() > 0)
end

-- Remember where Blizzard anchored the tracker (anything not anchored to our ghost frame is Blizzard's).
-- CONSTRAINT: Blizzard may anchor the tracker to another frame, such as the right-hand managed-frame container, whose
-- own position depends on the tracker's height. The tracker is EXTRA pixels taller here, so following such an anchor
-- moved the window by about half of that, off the bottom of the screen (/qt debug: window top 815 -> -884). An anchor
-- to anything but UIParent is therefore turned into a fixed screen position, read while the tracker still has
-- Blizzard's own height; once it is taller, such an anchor is ignored and the last fixed position is kept.
local blizzardAnchor = "none" -- for /qt debug
local function inflated()
	return viewport ~= nil and tracker:GetHeight() > naturalH + 1
end
-- The default spot is the middle of the screen: on screen at every resolution and UI scale, for first use and set-up.
local DEFAULT_ANCHOR = { "CENTER", UIParent, "CENTER", 0, 0 }
-- "Reset position" puts the window where Blizzard had the tracker at login, saved like a dragged position.
-- CONSTRAINT: with no saved position the window follows Blizzard's anchor live, and after "Reset position" (which used
-- to clear the saved position) it disappeared and reappeared in a loop (user report, 2.5.1). A saved position does not
-- depend on Blizzard's re-anchoring, so the reset now saves one: the tracker's top left as read at login, before it is
-- re-parented or made taller (on screen), else the default spot below the minimap.
local home
function recordHome()
	if home then return end
	local left, top = tracker:GetLeft(), tracker:GetTop()
	if not (left and top) then return end
	left, top = toScreen(tracker, left), toScreen(tracker, top)
	local screenH, screenW = UIParent:GetHeight(), UIParent:GetWidth()
	if screenH and screenW and top >= 60 and top <= screenH + 2 and left >= -20 and left <= screenW - 40 then
		home = { "TOPLEFT", "BOTTOMLEFT", left, top }
	end
end
-- 2.5.3: the default (first use, Reset position, Reset to defaults, the off-screen safety net) is the middle of the
-- screen, saved like a dragged position; the login spot above is kept for /qt debug only.
function homePosition()
	return { "CENTER", "CENTER", 0, 0 }
end
local function keepOrDefault()
	if #anchors == 0 then anchors = { DEFAULT_ANCHOR } end
	return true
end
local function capture()
	local found, foreignRel = {}, nil
	for i = 1, tracker:GetNumPoints() do
		local point, rel, relPoint, x, y = tracker:GetPoint(i)
		if rel ~= ghost then
			found[#found + 1] = { point, rel or UIParent, relPoint, x, y }
			if rel and rel ~= UIParent then foreignRel = rel end
			local okName, relName = pcall(function() return rel and rel.GetName and rel:GetName() end)
			blizzardAnchor = ("%s to %s %s (%.1f, %.1f)"):format(tostring(point), okName and tostring(relName or "UIParent") or "?",
				tostring(relPoint), tonumber(x) or 0, tonumber(y) or 0)
		end
	end
	if #found == 0 then return false end
	if not foreignRel then
		anchors = found
		return true
	end
	if inflated() then return keepOrDefault() end -- cannot be read now: keep the last fixed position
	local left, top = tracker:GetLeft(), tracker:GetTop()
	if not (left and top) then return keepOrDefault() end
	left, top = toScreen(tracker, left), toScreen(tracker, top)
	local screenH, screenW = UIParent:GetHeight(), UIParent:GetWidth()
	if screenH and screenW and (top < 60 or top > screenH + 2 or left < -20 or left > screenW - 40) then
		return keepOrDefault() -- read mid-layout or off screen: not a usable spot
	end
	anchors = { { "TOPLEFT", UIParent, "BOTTOMLEFT", left, top } }
	blizzardAnchor = blizzardAnchor .. " -> fixed at " .. ("%.0f, %.0f"):format(anchors[1][4], anchors[1][5])
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------------------------------------------------
-- Total window height: db.height (0 = Blizzard's own tracker height), at most the screen height.
local function windowHeight()
	local h = db.height or 0
	if h > 0 then
		h = math.min(h, UIParent:GetHeight() or h)
	else
		h = naturalH * scale()
	end
	if fitCap then h = math.min(h, fitCap) end
	return math.max(h, 100)
end

local movingGhost = false -- true while the Edit Mode overlay is dragged: nothing else may re-anchor the window meanwhile
local schedule, watchStrip -- defined further down
local scheduleScreenCheck -- defined after layoutGhost
local screenSettled = false -- set a few seconds after the tracker is set up: positions read earlier are not final
local function layoutGhost()
	if movingGhost then return end
	ghost:ClearAllPoints()
	local pos = db.pos
	if pos then
		ghost:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		for _, a in ipairs(anchors) do ghost:SetPoint(a[1], a[2], a[3], a[4], a[5]) end
	end
	ghost:SetSize(math.max((naturalW + (db.widthExtra or 0)) * scale(), 1), windowHeight())
	if screenSettled then scheduleScreenCheck() end
end

-- Safety net: a window whose top stays off the screen (a saved spot from another resolution, an anchor that moved)
-- goes back to the top right, below the minimap, where Blizzard keeps its tracker.
-- CONSTRAINT: during and right after a loading screen frame positions are not final, and every layout pass then looked
-- off screen (2.2.2 printed its message on each pass for ~10 s after /reload). The check therefore starts only a few
-- seconds after setup, runs on a timer rather than inside each layout, acts only when two checks 1.5 s apart both find
-- the window off screen, and says so at most once per session.
local SCREEN_CHECK_DELAY, SETTLE_DELAY = 1.5, 5
local screenCheckPending, offScreenSeen, warnedOffScreen = false, 0, false
local function offScreen()
	local top, left, right = ghost:GetTop(), ghost:GetLeft(), ghost:GetRight()
	local screenH, screenW = UIParent:GetHeight(), UIParent:GetWidth()
	return top and left and right and screenH and screenW and screenH > 0
		and (top < 60 or top > screenH + 2 or right < 40 or left > screenW - 40) or false
end
local function checkOnScreen()
	screenCheckPending = false
	if not ghost or movingGhost or InCombatLockdown() then return end
	if not offScreen() then offScreenSeen = 0 return end
	offScreenSeen = offScreenSeen + 1
	if offScreenSeen < 2 then scheduleScreenCheck() return end
	offScreenSeen = 0
	db.pos = homePosition()
	anchors = { DEFAULT_ANCHOR }
	fitCap = nil
	guarded(layoutGhost)
	schedule()
	if not warnedOffScreen then
		warnedOffScreen = true
		say("the quest tracker was off the screen and has been moved to the middle of the screen. /qt unlock lets you drag it.")
	end
end
scheduleScreenCheck = function()
	if screenCheckPending then return end
	screenCheckPending = true
	C_Timer.After(SCREEN_CHECK_DELAY, checkOnScreen)
end

-- Module widths under Quest Tracker scale: a module scaled by qs gets 1/qs of its width (and of its line-width
-- fields, which Blizzard sizes quest text from) so it covers the same width on screen. Extra width widens only the
-- tracker's window (background, scrollbar side), not the quest text: whether long text is cut off or wraps is up to
-- "Word wrap titles and objectives".
local WIDTH_FIELDS = { "lineWidth", "blockWidth" }
-- CONSTRAINT: Quest Tracker scale (scale and width fields) applies to these quest-list modules only. A field written
-- here is one Blizzard's layout reads, so that module's layout runs tainted; a module that reads secret data there then
-- fails: the scenario module in dungeons (Blizzard_MawBuffs ShouldShowMawBuffs -> GetAuraDataByIndex: "Auras cannot be
-- accessed when secret while tainted by 'RXPForeverTracker'"). Every other module (scenario, widgets, bonus objectives,
-- world quests, other addons') stays at scale 1 with Blizzard's own fields, untouched.
local SCALED_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "AchievementObjectiveTracker",
	"AdventureObjectiveTracker", "ProfessionsRecipeTracker", "MonthlyActivitiesObjectiveTracker" }
local function scaledModule(module)
	for _, name in ipairs(SCALED_MODULES) do
		if _G[name] == module then return true end
	end
	return false
end
ns.api.scaledModule = scaledModule
local function applyModuleWidths()
	if InCombatLockdown() then return false end
	local qs = questScale()
	local changed = false
	for _, module in ipairs(tracker.modules or {}) do
		if scaledModule(module) then
			if not module.qtsBaseW then module.qtsBaseW = module:GetWidth() * (module:GetScale() or 1) end
			-- module units: a module scaled by qs needs 1/qs of the width to cover the same width on screen
			local want = module.qtsBaseW / qs
			if module.qtsBaseW > 0 and math.abs(module:GetWidth() - want) > 0.5 then
				guarded(function() module:SetWidth(want) end)
				changed = true
			end
			module.qtsBaseFields = module.qtsBaseFields or {}
			for _, field in ipairs(WIDTH_FIELDS) do
				local current = module[field]
				if type(current) == "number" then
					if module.qtsBaseFields[field] == nil then module.qtsBaseFields[field] = current end
					local wantField = module.qtsBaseFields[field] / qs
					if current ~= wantField then module[field] = wantField; changed = true end
				end
			end
		end
	end
	return changed
end

-- Right-click on the guide in the tracker opens the "change guide" menu (Objectives/features/GuideMenu.lua). With the
-- separate AllObjectives RXP addon running instead, RestedXP's own guide selection menu is used.
local clickHooked = setmetatable({}, { __mode = "k" })
local function openGuideMenu(anchor)
	local showGuideMenu = root.objectives.showGuideMenu
	if showGuideMenu then
		local ok, err = pcall(showGuideMenu, anchor)
		if not ok then geterrorhandler()(err) end
		return
	end
	local ace = LibStub and LibStub("AceAddon-3.0", true)
	local rxp = ace and ace:GetAddon("RXPGuides", true)
	if rxp and rxp.v2 and rxp.v2.ShowGuideSelectionMenu then
		pcall(rxp.v2.ShowGuideSelectionMenu, rxp.v2)
	else
		say("RestedXP's guide list was not found.")
	end
end
local guideModuleOf = setmetatable({}, { __mode = "k" }) -- clicked frame -> its guide module (the menu opens beside it)
-- Right-click on the guide: the "change guide" menu. Shift+right-click: the settings window (/qt), on its
-- Quest Tracker tab; again closes it. Ctrl+right-click: the Prerequisite Journal.
local function onGuideMouseUp(frame, button)
	if button ~= "RightButton" then return end
	-- Ctrl+right-click: the Prerequisite Journal (Prereqs.lua)
	if IsControlKeyDown() and ns.api.togglePrereqs then
		ns.api.togglePrereqs()
		return
	end
	if IsShiftKeyDown() and ns.api.openConfigTab then
		local window = _G.RXPForeverTrackerConfig
		if window and window:IsShown() and db.configTab == "quests" and ns.api.toggleConfig then
			ns.api.toggleConfig()
		else
			ns.api.openConfigTab("quests")
		end
		return
	end
	openGuideMenu(guideModuleOf[frame] or frame)
end
local function hookGuideClicks(module)
	if InCombatLockdown() then return end
	if not clickHooked[module] then
		clickHooked[module] = true
		guideModuleOf[module] = module
		if not module:IsMouseEnabled() then module:EnableMouse(true) end
		module:HookScript("OnMouseUp", onGuideMouseUp)
	end
	local contents = module.ContentsFrame
	if contents and contents.GetChildren then
		for _, row in ipairs({ contents:GetChildren() }) do
			if not clickHooked[row] and row.IsMouseEnabled and row:IsMouseEnabled() then
				clickHooked[row] = true
				guideModuleOf[row] = module
				row:HookScript("OnMouseUp", onGuideMouseUp)
			end
		end
	end
end

-- Quest Tracker scale: Blizzard's modules (quests, campaign, ...) get db.questScale on top of the general scale.
-- Their width follows in applyModuleWidths, and scrolling converts with each module's effective scale, so a scaled
-- section scrolls and clips like the rest. Out of combat only (modules may hold secure item buttons); refresh runs it
-- again when combat ends.
local function applyModuleScales()
	if InCombatLockdown() then needsLayout = true return false end
	local qs = questScale()
	local changed = false
	for _, module in ipairs(tracker.modules or {}) do
		local want = scaledModule(module) and qs or 1 -- the others: Blizzard's scale (SCALED_MODULES)
		if module.SetScale and math.abs((module:GetScale() or 1) - want) > 1e-4 then
			guarded(function() module:SetScale(want) end)
			changed = true
		end
	end
	return changed
end

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }
-- Layer slider value 1..100: four strata of 25 levels each. The minimap sits in its own strata, so only a different
-- strata (not just a lower level) puts the tracker behind it.
local function layerFromValue(v)
	v = math.min(math.max(math.floor(v or 1), 1), 100)
	return STRATA[math.floor((v - 1) / 25) + 1], ((v - 1) % 25) + 1
end
ns.api.layerFromValue = layerFromValue

local function currentLayerValue()
	local strata = tracker.qtsStrata or "MEDIUM"
	for i, name in ipairs(STRATA) do
		if name == strata then return (i - 1) * 25 + math.min(math.max(tracker.qtsLevel or 1, 1), 25) end
	end
	return 51
end
ns.api.currentLayerValue = currentLayerValue

local function applyLevel()
	if InCombatLockdown() then return end
	local strata, level
	if db.layer then
		strata, level = layerFromValue(db.layer)
	else
		strata, level = tracker.qtsStrata, tracker.qtsLevel
	end
	if not strata then return end
	for _, frame in ipairs({ viewport, strip, bar }) do
		if frame then frame:SetFrameStrata(strata) end
	end
	if guide and pinGuide and guide.SetFrameStrata then guide:SetFrameStrata(strata) end
	if viewport then viewport:SetFrameLevel(level) end
	if strip then strip:SetFrameLevel(level + 3) end
	if bar then bar:SetFrameLevel(level + 4) end
	if guide and pinGuide and guide.SetFrameLevel then guide:SetFrameLevel(level + 2) end
end

local function layoutTracker()
	local s = scale()
	if not InCombatLockdown() then
		if math.abs(tracker:GetScale() - s) > 1e-4 then moveTracker("SetScale", s) end
		if strip then strip:SetScale(s) end
	end
	moveTracker("ClearAllPoints")
	moveTracker("SetPoint", "TOPLEFT", ghost, "TOPLEFT", 0, 0)
	moveTracker("SetPoint", "TOPRIGHT", ghost, "TOPRIGHT", 0, 0)
	tracker:SetHeight(naturalH + extraNow)
end

-- The scrollbar goes right of the list unless there is no room on screen; quest item buttons go on the other side.
-- When the items are on the left they sit just outside the tracker, so the clipping area is widened by ITEM_PAD there.
local ITEM_PAD = 36
local function barOnLeft()
	local right = ghost and ghost:GetRight()
	return right ~= nil and (right + barWidth() + 4 > (UIParent:GetWidth() or 0))
end
-- "Usable quest items on left side": on (default) = left of the list, off = Blizzard's own place on the right.
function ns.api.itemSide() return (db.itemsLeft == false) and "right" or "left" end
function ns.api.setItemsLeft(on)
	db.itemsLeft = on and true or false
	-- schedule() is declared further down this file, so it is reached through the API table here
	if ns.api.applyLayout then ns.api.applyLayout() end
	if ns.api.placeItems then ns.api.placeItems() end
end

local function layoutViewport()
	viewport:ClearAllPoints()
	viewport:SetPoint("TOPLEFT", ghost, "TOPLEFT", ns.api.itemSide() == "left" and -ITEM_PAD or 0, -pinned)
	viewport:SetPoint("TOPRIGHT", ghost, "TOPRIGHT", 0, -pinned)
	viewport:SetHeight(math.max(ghost:GetHeight() - pinned, 50))
end

local function layoutBar()
	if not bar then return end
	bar:ClearAllPoints()
	if barOnLeft() then
		bar:SetPoint("TOPRIGHT", viewport, "TOPLEFT", -2, 0)
		bar:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMLEFT", -2, 0)
	else
		bar:SetPoint("TOPLEFT", viewport, "TOPRIGHT", 2, 0)
		bar:SetPoint("BOTTOMLEFT", viewport, "BOTTOMRIGHT", 2, 0)
	end
	bar:SetWidth(barWidth())
	if thumb then thumb:SetWidth(barWidth()) end
end

-- Height of the fixed strip: from the top of the window to the bottom of the guide (plus the divider gap), or to the
-- bottom of the header.
-- CONSTRAINT: the guide module's own bottom is not the bottom of what it shows: its last step's text and use circles
-- can reach below it (Objectives/tracker/Rows.lua trims the module by BOTTOM_TRIM and anchors the circles outside the
-- lines), so the scrolling quests, clipped from that bottom, slid over the last step. The lowest visible point of the
-- guide's rows, lines and circles is used, and the quests start DIVIDER_GAP below it, with a divider line in the gap.
local DIVIDER_GAP = 12 -- screen pixels between the last step and the scrolling quests (the divider sits in the middle)
local function lowestShown(frame, depth, lowest)
	if not frame:IsShown() then return lowest end
	local b = frame:GetBottom()
	if b then
		b = toScreen(frame, b)
		if not lowest or b < lowest then lowest = b end
	end
	-- a step's text that wraps past the bottom of its line counts too (a very long current step)
	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsShown() then
				local text = region.GetText and region:GetText()
				local rb = text and text ~= "" and region:GetBottom()
				if rb then
					rb = toScreen(region, rb)
					if not lowest or rb < lowest then lowest = rb end
				end
			end
		end
	end
	if depth > 0 and frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do lowest = lowestShown(child, depth - 1, lowest) end
	end
	return lowest
end
local function guideBottom()
	if not (pinGuide and guide and guide:IsVisible()) then return nil end
	local bottom = guide:GetBottom()
	bottom = bottom and toScreen(guide, bottom)
	local contents = guide.ContentsFrame
	if contents then bottom = lowestShown(contents, 3, bottom) end -- rows > lines > circles
	return bottom
end
-- drop: how far the first scrolling section is pushed down so that it starts at the clip edge, below the gap (it is
-- chained to the guide frame's bottom, which is above the clip edge now).
local drop = 0
-- the "Quests" header's Y-axis padding (settings, -50 to 40 px) adds to the gap under the last step; negative values
-- pull the Quests header up towards (or over) the last step
local function questsPad() return math.min(math.max(tonumber(db and db.questsPadY) or 0, -50), 60) end
local function measurePinned()
	drop = 0
	local top = ghost:GetTop()
	if not top then return 0 end
	local bottom = guideBottom()
	if bottom then
		bottom = bottom - DIVIDER_GAP - questsPad()
	else
		bottom = top - (tracker.topModulePadding or 0) * scale()
	end
	-- however long the current step is, the quests (and their "Quests" header) start below it: no cap here, the
	-- quest list keeps at least 50 px (layoutViewport) and is pushed down past the window's bottom if need be
	local height = math.max(top - bottom, 0)
	if bottom and guideBottom() then
		local frameBottom = guide:GetBottom()
		-- negative when the padding pulls the Quests header above where it is chained (the guide frame's bottom)
		if frameBottom then drop = toScreen(guide, frameBottom) - (top - height) end
	end
	return height
end

-- The divider between the last step and the quests: in the middle of the gap, shown while the guide is fixed on top.
local divider
local function layoutDivider()
	-- hidden once the padding leaves no room for it between the last step and the quests
	local shown = guideBottom() ~= nil and tracker:IsShown() and pinned > DIVIDER_GAP + questsPad()
		and DIVIDER_GAP + questsPad() >= 6
	if not shown then
		if divider then divider:Hide() end
		return
	end
	if not divider then
		divider = withAlpha(CreateFrame("Frame", nil, UIParent))
		divider.line = divider:CreateTexture(nil, "ARTWORK")
		divider.line:SetAllPoints()
		local ok = pcall(divider.line.SetAtlas, divider.line, "UI-World-Quest-golden-line", false)
		if not ok then divider.line:SetColorTexture(0.85, 0.65, 0.2, 0.8) end
	end
	divider:SetFrameStrata(tracker:GetFrameStrata())
	divider:SetFrameLevel(tracker:GetFrameLevel() + 3)
	divider:ClearAllPoints()
	local inset = 8
	-- just under the last step; the padding goes below the line, above the Quests header
	local lineY = pinned - (ns.api.questsHeaderPinnedPx and ns.api.questsHeaderPinnedPx() or 0) - questsPad() - DIVIDER_GAP / 2
	divider:SetPoint("TOPLEFT", ghost, "TOPLEFT", inset, -lineY + 2)
	divider:SetPoint("TOPRIGHT", ghost, "TOPRIGHT", -inset, -lineY + 2)
	divider:SetHeight(4)
	divider:Show()
end

-- R106-49: Quest list > "Keep the Quests header at the top" (db.pinQuestsHeader; off: it scrolls with the quests, as
-- before). While the quests are the first section, their "Quests" header (QuestObjectiveTracker.Header) is lifted out
-- of the scrolling list into a holder just above the clip edge, at its own place and size, and the fixed strip grows by
-- its height. The tracker is anchored to the ghost frame, not to the clip area, so the header's old room in the list
-- then sits above the clip edge and the first quest starts right under the pinned header. Put back when switched off,
-- when another section is first, or when the quests hide. Not in combat (refresh waits for its end).
-- (its own block: Core.lua is near Lua's 200-locals limit of one chunk)
local pinQuestsHeader
do
local headerHolder
local headerHeld        -- the header while it is in the holder
local headerModule      -- its own section (where it goes back)
local headerPoints = {} -- its anchors as Blizzard set them (to the section)
local headerPx = 0      -- the pinned header's room in the fixed strip, UIParent units
local headerHooked = setmetatable({}, { __mode = "k" })
function ns.api.questsHeaderPinnedPx() return headerHeld and headerPx or 0 end

local function anchorHeaderToHolder(header)
	header:ClearAllPoints()
	local any = false
	for _, p in ipairs(headerPoints) do
		local rel = (p[2] == headerModule or p[2] == nil) and headerHolder or p[2]
		header:SetPoint(p[1], rel, p[3], p[4], p[5])
		any = true
	end
	if not any then header:SetPoint("TOPLEFT", headerHolder, "TOPLEFT", 0, 0) end
end

-- R106-54: the quests are chained to the header (the first quest's TOP at the header's BOTTOM, fromHeaderOffsetY; each
-- next quest at the one above it), so with the header pinned they stayed with it and did not scroll until far down
-- (user: "the top of the list is still shown when the scrollbar is halfway down"). While it is pinned, every point
-- anchored to the header is anchored to the same place in its section instead (which scrolls): the header's point
-- measured from the section's TOPLEFT where the header was (headerGeom, section units). Put back when unpinned.
local headerGeom      -- { gap above the header, its left from the section's left, its width, its height }
local rechained = setmetatable({}, { __mode = "k" }) -- frame -> { {point, relPoint, x, y} as Blizzard set them }
local chainHooked = setmetatable({}, { __mode = "k" })
local function headerPointInModule(relPoint)
	local g = headerGeom
	relPoint = relPoint or "TOPLEFT"
	local x = relPoint:find("LEFT") and g[2] or relPoint:find("RIGHT") and (g[2] + g[3]) or (g[2] + g[3] / 2)
	local y = relPoint:find("TOP") and -g[1] or relPoint:find("BOTTOM") and -(g[1] + g[4]) or -(g[1] + g[4] / 2)
	return x, y
end
local function rechainPoint(frame, point, relPoint, x, y)
	local px, py = headerPointInModule(relPoint)
	rechained[frame] = rechained[frame] or {}
	local list = rechained[frame]
	for i = #list, 1, -1 do if list[i][1] == point then table.remove(list, i) end end
	list[#list + 1] = { point, relPoint or point, x or 0, y or 0 }
	guarded(function() frame:SetPoint(point, headerModule, "TOPLEFT", (x or 0) + px, (y or 0) + py) end)
end
local function hookChain(frame)
	if chainHooked[frame] or type(frame) ~= "table" or not frame.SetPoint then return end
	chainHooked[frame] = true
	hooksecurefunc(frame, "SetPoint", function(self, point, rel, relPoint, x, y)
		if guard or not headerHeld or type(point) ~= "string" then return end
		if type(rel) == "number" then return end -- (point, x, y): to its parent, not the header
		if type(relPoint) == "number" then x, y, relPoint = relPoint, x, nil end
		if type(rel) == "string" then rel = _G[rel] end
		if rel == headerHeld then rechainPoint(self, point, relPoint, x, y) end
	end)
end
-- the section's frames that may hang on the header: its blocks and the children of the section and its contents
local function chainCandidates(module)
	local list = {}
	for _, byId in pairs(type(module.usedBlocks) == "table" and module.usedBlocks or {}) do
		for _, block in pairs(type(byId) == "table" and byId or {}) do list[#list + 1] = block end
	end
	for _, parent in ipairs({ module, module.ContentsFrame }) do
		if type(parent) == "table" and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do list[#list + 1] = child end
		end
	end
	return list
end
local function rechainAll(module)
	for _, frame in ipairs(chainCandidates(module)) do
		if frame ~= headerHeld and type(frame) == "table" and frame.GetNumPoints then
			hookChain(frame)
			for i = frame:GetNumPoints(), 1, -1 do
				local point, rel, relPoint, x, y = frame:GetPoint(i)
				if point and rel == headerHeld then rechainPoint(frame, point, relPoint, x, y) end
			end
		end
	end
end
local function unchainAll(header)
	for frame, list in pairs(rechained) do
		for _, p in ipairs(list) do
			guarded(function() frame:SetPoint(p[1], header, p[2], p[3], p[4]) end)
		end
	end
	wipe(rechained)
end

local function unpinQuestsHeader()
	local header, module = headerHeld, headerModule
	if not header then return end
	headerHeld = nil
	guarded(function()
		header:SetParent(module)
		header:ClearAllPoints()
		for _, p in ipairs(headerPoints) do header:SetPoint(p[1], p[2] or module, p[3], p[4], p[5]) end
	end)
	unchainAll(header)
	if headerHolder then headerHolder:Hide() end
	headerPx = 0
end

-- first: the section that will be first under the fixed strip; base: the strip's height without the header.
-- Returns the header's room (UIParent units) to add to the strip, 0 when not pinned.
function pinQuestsHeader(first, base)
	local module = _G.QuestObjectiveTracker
	local header = module and module.Header
	local want = db.pinQuestsHeader and header ~= nil and first == module and moduleVisible(module) and header:IsShown()
		and not InCombatLockdown()
	if not want then unpinQuestsHeader() return 0 end
	if not headerHeld then
		-- measured where Blizzard put it, inside its section (the gap above it and its height)
		local mTop, hTop, hBottom = module:GetTop(), header:GetTop(), header:GetBottom()
		local mLeft0, hLeft, hRight = module:GetLeft(), header:GetLeft(), header:GetRight()
		if not (mTop and hTop and hBottom and mLeft0 and hLeft and hRight) then return 0 end
		headerModule = module
		-- section units (the header is the section's child, same scale)
		headerGeom = { mTop - hTop, hLeft - mLeft0, hRight - hLeft, hTop - hBottom }
		wipe(headerPoints)
		for i = 1, header:GetNumPoints() do
			local point, rel, relPoint, x, y = header:GetPoint(i)
			if point then headerPoints[#headerPoints + 1] = { point, rel, relPoint, x or 0, y or 0 } end
		end
		headerPx = math.max(toScreen(module, mTop) - toScreen(header, hBottom), 0)
		if not headerHolder then
			headerHolder = withAlpha(CreateFrame("Frame", nil, UIParent))
		end
		-- R106-56: the header calls its parent for its own work (the collapse button: self:GetParent():ToggleCollapsed();
		-- user: "attempt to call a nil value" collapsing Quests while pinned). While it sits in the holder, every
		-- function of its section the holder does not have itself is passed on to the section.
		if headerHolder.qtsForwards ~= module then
			headerHolder.qtsForwards = module
			for key, fn in pairs(module) do
				if type(key) == "string" and type(fn) == "function" and headerHolder[key] == nil then
					headerHolder[key] = function(_, ...) return fn(module, ...) end
				end
			end
		end
		-- Blizzard anchoring the header again (to its section) while it is pinned: back to the holder at once
		if not headerHooked[header] then
			headerHooked[header] = true
			hooksecurefunc(header, "SetPoint", function(self, point, rel, relPoint, x, y)
				if guard or self ~= headerHeld then return end
				if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil
				elseif type(relPoint) == "number" then x, y, relPoint = relPoint, x, nil end
				if rel ~= nil and rel ~= headerModule and rel ~= headerHolder then return end
				guarded(function() anchorHeaderToHolder(self) end)
			end)
		end
		-- a block the section takes later (GetBlock, before Blizzard anchors it): watched at once
		if not chainHooked[module] and type(module.GetBlock) == "function" then
			chainHooked[module] = true
			hooksecurefunc(module, "GetBlock", function(self)
				if not headerHeld then return end
				for _, frame in ipairs(chainCandidates(self)) do hookChain(frame) end
			end)
		end
		headerHeld = header
		guarded(function() header:SetParent(headerHolder) end)
	end
	-- the holder: the section's scale and width, at the section's left, its top at the window's top less the strip
	local s = module:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local holder = headerHolder
	holder:SetScale(s)
	holder:SetFrameStrata(tracker:GetFrameStrata())
	holder:SetFrameLevel(tracker:GetFrameLevel() + 5)
	holder:SetAlpha(trackerAlpha() * questAlpha())
	local mLeft, gLeft = module:GetLeft(), ghost:GetLeft()
	local dx = (mLeft and gLeft) and (toScreen(module, mLeft) - toScreen(ghost, gLeft)) or 0
	holder:ClearAllPoints()
	holder:SetPoint("TOPLEFT", ghost, "TOPLEFT", dx / s, -base / s)
	holder:SetSize(module:GetWidth(), headerPx / s)
	guarded(function() anchorHeaderToHolder(headerHeld) end)
	rechainAll(module) -- the quests hanging on the header scroll with their section (R106-54)
	holder:Show()
	return headerPx
end

function ns.api.setPinQuestsHeader(on)
	db.pinQuestsHeader = on and true or false
	if ns.api.applyLayout then ns.api.applyLayout() end
end
end -- the pinned header block

---------------------------------------------------------------------------------------------------------------------
-- Modules: guide detection, scrolling anchor
---------------------------------------------------------------------------------------------------------------------
-- Other addons' tracker modules: parented to UIParent, built from ObjectiveTrackerModuleTemplate, not in tracker.modules.
local function scanForeign()
	-- the built-in AllObjectives RXP part, or a separately installed copy
	if not (root.objectives.rxp or C_AddOns.IsAddOnLoaded("AllObjectivesRXP")) then return end
	local known = {}
	for _, module in ipairs(tracker.modules or {}) do known[module] = true end
	wipe(foreign)
	for _, parent in ipairs({ UIParent, viewport }) do
		for _, frame in ipairs({ parent:GetChildren() }) do
			if not known[frame] and frame ~= viewport and frame ~= tracker and frame ~= ghost and frame ~= handle
				and frame ~= strip and frame ~= bar
				and type(frame.parentContainer) == "table" and frame.parentContainer ~= tracker
				and frame.ContentsFrame and frame.GetContentsHeight then
				foreign[#foreign + 1] = frame
			end
		end
	end
end

-- In combat only protected frames are locked; Blizzard's tracker modules are not protected in Forever (/qt debug), so
-- the scroll position can be kept through a fight too.
local function canMove(frame)
	return not InCombatLockdown() or not (frame.IsProtected and frame:IsProtected())
end
local setAnchorOffset

-- The first section after Blizzard's quests (Professions, Achievements, ...) moves down below the last quest entry and
-- "More quests" (pushSectionsAfterQuests, below): those sections stay at the very bottom, below every quest.
local pushed, pushPx = nil, 0
local cbTime, cbBase -- contentBottom's per-frame cache (below); a push clears it
-- a section's anchor offset in screen pixels: the scroll position on the first section, the push on the pushed one
local function anchorOffsetFor(module)
	local px = 0
	if module == follower then px = px + (offset - drop) end
	if module == pushed then px = px - pushPx end
	if module == guide and pinGuide then px = px - guideShift end
	return px
end

local function hookModule(module)
	if hooked[module] then return end
	hooked[module] = true
	-- A section can change height without a full tracker update (the RestedXP guide advances a step when you cast a
	-- spell, for example). The fixed strip and the clipping area are measured from those heights, so re-measure then;
	-- before, the list stayed shifted until the next full update.
	if module.HookScript then
		module:HookScript("OnSizeChanged", function() if not guard then schedule() end end)
		-- A section above the guide that shows for a moment (when your buffs change, for example) un-pins the guide;
		-- without these the layout stayed un-pinned - and looked shrunk - after that section hid again.
		module:HookScript("OnShow", function() if not guard then schedule() end end)
		module:HookScript("OnHide", function() if not guard then schedule() end end)
	end
	-- Every anchor point is recorded, not only TOP: AllObjectives RXP anchors its guide by TOPLEFT and TOPRIGHT, and
	-- adding a separate TOP point on top of those (as before) distorted the guide.
	local record = {}
	for i = 1, module:GetNumPoints() do
		local point, rel, relPoint, x, y = module:GetPoint(i)
		if point then record[point] = { rel or module:GetParent(), relPoint or point, x or 0, y or 0 } end
	end
	bases[module] = record
	hooksecurefunc(module, "SetPoint", function(self, point, rel, relPoint, x, y)
		if guard or type(point) ~= "string" then return end
		if type(rel) == "number" then -- SetPoint(point, x, y)
			x, y, rel, relPoint = rel, relPoint, nil, nil
		elseif type(relPoint) == "number" then -- SetPoint(point, relativeTo, x, y)
			x, y, relPoint = relPoint, x, nil
		end
		if type(rel) == "string" then rel = _G[rel] end
		-- R106-57: the Professions section in its own box: Blizzard's place is only remembered (to put it back), it
		-- stays in the box; a section Blizzard chains to it takes its place in the tracker instead
		if profHeld then
			if self == profHeld then
				bases[self] = bases[self] or {}
				bases[self][point] = { rel or self:GetParent(), relPoint or point, x or 0, y or 0 }
				if placeProf then placeProf() end
				return
			end
			if rel == profHeld then
				local pb = bases[profHeld]
				local b = pb and (pb.TOP or pb.TOPLEFT or pb.TOPRIGHT)
				if b then
					rel, relPoint, y = b[1], b[2], (b[4] or 0) + (y or 0)
					local r, rp, xx, yy = rel, relPoint, x or 0, y
					guarded(function() self:SetPoint(point, r, rp, xx, yy) end)
				end
			end
		end
		bases[self] = bases[self] or {}
		bases[self][point] = { rel or self:GetParent(), relPoint or point, x or 0, y or 0 }
		-- Blizzard re-anchors its modules on every tracker update (zone changes, quest and aura events...). Re-apply the
		-- scroll offset in the same frame, so the list never shows one frame at the unscrolled position (the flicker).
		local px = (self == follower or self == pushed or self == guide) and anchorOffsetFor(self) or 0
		if px ~= 0 and canMove(self) then setAnchorOffset(self, px) end
	end)
	if module.parentContainer == tracker then
		hooksecurefunc(module, "SetWidth", function(self, w)
			if guard or type(w) ~= "number" then return end
			self.qtsBaseW = w
		end)
	end
	hooksecurefunc(module, "ClearAllPoints", function(self)
		if not guard then bases[self] = {} end
	end)
end

function setAnchorOffset(module, pixels)
	local b = bases[module]
	if not b or not next(b) or not canMove(module) then return end
	-- offsets are in the module's own scale
	local units = pixels * UIParent:GetEffectiveScale() / module:GetEffectiveScale()
	guarded(function()
		for point, a in pairs(b) do module:SetPoint(point, a[1], a[2], a[3], a[4] + units) end
	end)
end

-- Guide above the quests: fixed when nothing else is above it, otherwise it scrolls with everything (inside the viewport).
local unpinnedBy -- for /qt debug: the section that sat above the guide the last time it was un-pinned
local function detectMode()
	guide = nil
	-- in its own window (Tracker settings > Own window) the RXP Tracker is not part of the quest tracker at all: no
	-- fixed strip, no scrolling, the quests start under the header
	local own = db.guideDetached
	for _, module in ipairs(foreign) do
		if not own and moduleVisible(module) then guide = module break end
	end
	local before = false
	unpinnedBy = nil
	for _, module in ipairs(tracker.modules or {}) do
		if (module.uiOrder or math.huge) <= GUIDE_SLOT and moduleVisible(module) then
			before = true
			unpinnedBy = tostring(module:GetName() or module.uiOrder)
			break
		end
	end
	pinGuide = guide ~= nil and not before
	if InCombatLockdown() then return end
	local want = (pinGuide or own) and UIParent or viewport
	for _, module in ipairs(foreign) do
		if module:GetParent() ~= want then guarded(function() module:SetParent(want) end) end
		-- inside the viewport the guide takes the general opacity from there; pinned on top (UIParent) it needs it here
		pinnedAlpha[module] = want == UIParent or nil
		module:SetAlpha((want == UIParent and trackerAlpha() or 1) * guideAlpha())
	end
	applyQuestAlpha()
end

local function pickFollower()
	local best, bestOrder
	for _, module in ipairs(tracker.modules or {}) do
		if moduleVisible(module) and module ~= profHeld then -- (the Professions box scrolls on its own)
			local order = module.uiOrder or math.huge
			if not bestOrder or order < bestOrder then best, bestOrder = module, order end
		end
	end
	-- a scrolling guide is the first thing in the chain unless a Blizzard module sits above it
	if guide and not pinGuide and (not bestOrder or GUIDE_SLOT < bestOrder) then return guide end
	return best
end

local function setFollower(module)
	if module == follower then return end
	local old = follower
	follower = module
	if old then setAnchorOffset(old, anchorOffsetFor(old)) end -- keeps its push, if it is the pushed section
end

-- move module (nil: none) down by px (UIParent units), and put the one moved before back
function ns.api.pushBelowMoreQuests(module, px)
	px = module and math.max(tonumber(px) or 0, 0) or 0
	if module == pushed and math.abs(px - pushPx) < 0.5 then return end
	local old = pushed
	pushed, pushPx = module, px
	if old and old ~= module then setAnchorOffset(old, anchorOffsetFor(old)) end
	if module then setAnchorOffset(module, anchorOffsetFor(module)) end
	cbTime = nil -- the content's bottom moved
end

---------------------------------------------------------------------------------------------------------------------
-- Scrolling
---------------------------------------------------------------------------------------------------------------------
-- CONSTRAINT: a Blizzard section's frame does not end where its quests end (user video, 2.4.0: the quest entries ran
-- on below the section's bottom edge, and "More quests" anchored to that edge was drawn over them). The bottom of a
-- section is the lowest shown entry inside it (blocks, their lines), in UIParent units; the frame edge only when it
-- has no shown entry.
local function moduleContentBottom(module)
	local contents = type(module.ContentsFrame) == "table" and module.ContentsFrame or module
	local lowest
	for _, child in ipairs({ contents:GetChildren() }) do lowest = lowestShown(child, 2, lowest) end
	if not lowest then
		local b = module:GetBottom()
		lowest = b and toScreen(module, b)
	end
	return lowest
end
ns.api.moduleContentBottom = moduleContentBottom

-- Within one frame the content only moves with the scroll offset (its bottom minus the offset stays the same), so the
-- scan of every block (scrollMax, the scrollbar and the background each need it) runs once per frame; refresh starts
-- a new scan. (cbTime, cbBase: declared with the push, above)
local function contentBottom()
	local now = GetTime()
	if cbTime == now and cbBase then return cbBase + offset end
	local lowest
	for _, module in ipairs(tracker.modules or {}) do
		if moduleVisible(module) and module ~= profHeld then -- (above the tracker, in its own box)
			local b = moduleContentBottom(module)
			if b and (not lowest or b < lowest) then lowest = b end
		end
	end
	-- the "More quests" section below Blizzard's quests (Tracker/MoreQuests.lua)
	local more = ns.api.moreQuestsBottom and ns.api.moreQuestsBottom()
	if more and (not lowest or more < lowest) then lowest = more end
	if lowest then cbTime, cbBase = now, lowest - offset else cbTime = nil end
	return lowest
end

local function scrollMax()
	if not follower or not viewport then return 0 end
	local vb, lb = viewport:GetBottom(), contentBottom()
	if not vb or not lb then return 0 end
	local pad = (tracker.bottomModulePadding or 0) * scale() + 12
	return math.max(0, offset + (vb - (lb - pad)))
end

-- Background (Settings Window > Background): one plain texture behind the RXP Tracker and the quest list, from the
-- top of the window down to the last quest shown (or the window's bottom when the list is longer), in the chosen
-- colour and opacity, with some space around. Below the tracker's frame level, so it never covers anything.
local background
local function updateBackground()
	local show = db.enabled and db.background and viewport and ghost and tracker:IsShown()
	if not show then
		if background then background:Hide() end
		return
	end
	-- the left edge: just left of the zone headers (the usable quest items sit further left, outside it)
	local top, vb, left, right = ghost:GetTop(), viewport:GetBottom(), ghost:GetLeft(), ghost:GetRight()
	if not (top and vb and left and right) then
		if background then background:Hide() end
		return
	end
	if not background then
		background = withAlpha(CreateFrame("Frame", "RXPForeverTrackerBackground", UIParent))
		background.tex = background:CreateTexture(nil, "BACKGROUND")
		background.tex:SetAllPoints()
		background:EnableMouse(false)
	end
	background:SetFrameStrata(tracker:GetFrameStrata())
	background:SetFrameLevel(math.max((viewport:GetFrameLevel() or 1) - 1, 0))
	local pad = tonumber(db.backgroundPad) or 6
	-- "Space around the trackers" on every side: above, right, below and left. On the left it is measured from the
	-- zone headers (2 px before them at 0), else from the window's edge, so a large value can reach the item buttons.
	local labelsLeft = ns.api.zoneLabelsLeft and ns.api.zoneLabelsLeft()
	local leftEdge = (labelsLeft and (labelsLeft - 2) or left) - pad
	local bottom = vb
	local lb = contentBottom()
	if lb then
		local listEnd = lb - (tracker.bottomModulePadding or 0) * scale()
		if listEnd > vb then bottom = listEnd end
	end
	local c = db.backgroundColor or { 0, 0, 0, 0.4 }
	background.tex:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, tonumber(c[4]) or 0.4)
	background:ClearAllPoints()
	background:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftEdge, top + pad)
	background:SetSize(math.max(right + pad - leftEdge, 1), math.max(top - bottom + 2 * pad, 1))
	background:Show()
end
ns.api.applyBackground = function() updateBackground() end

local function updateScrollbar()
	updateBackground()
	if not bar then return end
	local max = scrollMax()
	local show = db.scrollbar and max > 0 and tracker:IsShown()
	bar:SetShown(show and true or false)
	if not show then return end
	local trackH = bar:GetHeight()
	local viewH = viewport:GetHeight()
	if not trackH or trackH <= 0 then return end
	local thumbH = math.min(math.max(viewH / (viewH + max) * trackH, 24), trackH)
	thumb:SetHeight(thumbH)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOP", bar, "TOP", 0, -(offset / max) * (trackH - thumbH))
end

-- "Show on mouseover only": the bar is visible while the mouse is over the list or the bar, while scrolling or
-- dragging, and fades out 2 seconds after the last of those.
local BAR_ALPHA, FADE_DELAY, FADE_TIME = 1, 2, 0.4 -- the Forever art at full strength (ScrollSkin.lua)
local lastActive = 0
local fader = CreateFrame("Frame")
local function fadeStep(_, elapsed)
	if not bar then return end
	if not db.scrollbarMouseover then
		bar:SetAlpha(BAR_ALPHA * trackerAlpha())
		fader:SetScript("OnUpdate", nil)
		return
	end
	local now = GetTime()
	if dragging or bar:IsMouseOver() or (viewport and viewport:IsMouseOver()) then lastActive = now end
	local full = BAR_ALPHA * trackerAlpha()
	local target = (now - lastActive < FADE_DELAY) and full or 0
	local alpha = bar:GetAlpha()
	local stepSize = full * elapsed / FADE_TIME
	if alpha < target then alpha = math.min(target, alpha + stepSize) elseif alpha > target then alpha = math.max(target, alpha - stepSize) end
	bar:SetAlpha(alpha)
end
local function updateFader()
	if db.scrollbarMouseover then fader:SetScript("OnUpdate", fadeStep) else fadeStep(nil, 0) end
end
-- key: "trackerAlpha" (general), "guideAlpha" (RXP Tracker) or "questAlpha" (Quest Tracker)
function ns.api.setTrackerAlpha(value, key)
	if not db then return end
	db[key or "trackerAlpha"] = math.min(math.max(tonumber(value) or 1, 0.1), 1)
	local a = trackerAlpha()
	for frame in pairs(alphaFrames) do frame:SetAlpha(a) end
	for _, module in ipairs(foreign) do module:SetAlpha((pinnedAlpha[module] and a or 1) * guideAlpha()) end
	applyQuestAlpha()
	if ns.api.applyMoreQuestsAlpha then ns.api.applyMoreQuestsAlpha() end
	if bar then fadeStep(nil, 0) end
	-- the step buttons (Objectives/circle/Action.lua) take it on their next placement
	local guide = root.objectives
	if guide and guide.relocate then guide.relocate() end
end

function ns.api.setScrollbarWidth(value)
	db.scrollbarWidth = math.min(math.max(math.floor((tonumber(value) or BAR_WIDTH) + 0.5), 2), 30)
	layoutBar()
	ns.api.applyLayout() -- the bar may now need the other side of the list
end

function ns.api.setScrollbarMouseover(on)
	db.scrollbarMouseover = on and true or false
	lastActive = GetTime()
	updateFader()
end

local function setOffset(value)
	lastActive = GetTime()
	local max = scrollMax()
	offset = math.min(math.max(value, 0), max)
	setAnchorOffset(follower, anchorOffsetFor(follower))
	updateScrollbar()
end

-- A frame's rectangle in screen pixels, cut to the viewport's (nil when none of it is in view)
local function screenRect(frame, clip)
	local ok, l, b, w, h = pcall(frame.GetRect, frame)
	if not (ok and l and w and w > 0 and h > 0) then return nil end
	local sc = frame:GetEffectiveScale()
	l, b, w, h = l * sc, b * sc, w * sc, h * sc
	local r, t = l + w, b + h
	if clip then
		l, b, r, t = math.max(l, clip[1]), math.max(b, clip[2]), math.min(r, clip[3]), math.min(t, clip[4])
		if r <= l or t <= b then return nil end
	end
	return { l, b, r, t }
end

local function distanceTo(rect, x, y)
	local dx = math.max(rect[1] - x, 0, x - rect[3])
	local dy = math.max(rect[2] - y, 0, y - rect[4])
	return dx * dx + dy * dy
end

-- Is the cursor nearer the RXP Tracker (the guide) than the quests in view? Then the wheel leaves the quests alone.
-- With no quest in view the quests scroll as before (a guide filling the view can still be scrolled past).
local function nearerGuide()
	if not (guide and moduleVisible(guide)) then return false end
	local x, y = GetCursorPosition()
	if not (x and y) then return false end
	local view = screenRect(viewport)
	local guideRect = screenRect(guide, not pinGuide and view or nil)
	if not guideRect then return false end
	local nearestQuest
	local function consider(frame)
		local rect = view and frame and frame:IsShown() and screenRect(frame, view)
		if rect then
			local d = distanceTo(rect, x, y)
			if not nearestQuest or d < nearestQuest then nearestQuest = d end
		end
	end
	for _, module in ipairs(tracker.modules or {}) do
		if not isForeign(module) and moduleVisible(module) then consider(module) end
	end
	consider(_G.RXPForeverTrackerMoreQuests)
	if not nearestQuest then return false end
	return distanceTo(guideRect, x, y) < nearestQuest
end

local function onWheel(_, delta, onBar)
	wheelEvents = wheelEvents + 1
	-- R106-50: the wheel scrolls in combat too (user). Blizzard's tracker sections are not protected in Forever (/qt
	-- debug), so they move in combat, as the scrollbar and Blizzard's own re-anchoring already did; only a section that
	-- is protected (canMove) waits, as the scroll position would not reach it.
	if InCombatLockdown() and follower and not canMove(follower) then return end
	if scrollMax() <= 0 then return end
	if not onBar and nearerGuide() then return end
	setOffset(offset - delta * db.step)
end

-- the guide's upcoming steps hand the wheel on at either end of their list (Objectives/tracker/Rows.lua)
function ns.api.trackerWheel(delta)
	if db.guideDetached then return end -- in its own window it has nothing to hand the wheel to
	onWheel(nil, delta)
end

local function anyTruncated()
	for _, module in ipairs(tracker.modules or {}) do
		if module.IsTruncated and module:IsTruncated() then return true end
	end
	return false
end

-- Blizzard's tracker is "clamped to screen". The tracker is taller than the screen (it holds the whole list), and a
-- clamped frame that is too tall is pulled back to the top edge every time it is moved.
local function unclamp()
	if InCombatLockdown() then return end
	if tracker.IsClampedToScreen and tracker:IsClampedToScreen() then
		guarded(function() tracker:SetClampedToScreen(false) end)
	end
end

-- If the bottom of the window is below the screen edge, shrink it so the end of the list stays reachable.
local function fitToScreen()
	local bottom = viewport:GetBottom()
	if db.pos then return end -- the user placed it: do not shrink it
	if bottom and bottom < 10 then
		local wanted = math.max(100, ghost:GetHeight() - (10 - bottom))
		if not fitCap or math.abs(fitCap - wanted) > 1 then
			fitCap = wanted
			guarded(layoutGhost)
			guarded(layoutViewport)
		end
	end
end

-- The fixed strip (header + RestedXP guide) can grow or move without anything resizing the guide itself: the
-- guide's header gets taller when a step changes (casting a spell), pushing the guide - and the quests chained below
-- it - down while the clipping area stayed put (the "shift" in /qt debug: guide bottom moved, strip height did not).
-- A probe spans from the top of the window to the bottom of the guide (or of the header): its height IS the strip
-- height, so any such change resizes it and the layout is re-measured at once.
local stripProbe
function watchStrip()
	local target = (pinGuide and guide) or tracker.Header
	if not target or not ghost then return end
	if not stripProbe then
		stripProbe = CreateFrame("Frame", nil, UIParent)
		stripProbe:SetScript("OnSizeChanged", function() if not guard then schedule() end end)
	end
	if stripProbe.target ~= target then
		stripProbe.target = target
		stripProbe:ClearAllPoints()
		stripProbe:SetPoint("TOPLEFT", ghost, "TOPLEFT", 0, 0)
		stripProbe:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
	end
end

-- Sections after Blizzard's quests (tracked profession recipes, achievements, ...) go below every quest. Blizzard
-- anchors the first of them to the quests section's frame, but its last entries can run past that frame's bottom (zone
-- headers and titles that wrap add room after Blizzard measured), and "More quests" (MoreQuests.lua) sits under those
-- entries: so that section moves down by how far the lowest quest entry (or More quests) reaches below the frame.
-- Blizzard anchors each section to the one before it, so the ones after follow. Measured only on things above the
-- moved section, so moving it never changes the measure.
local function pushSectionsAfterQuests()
	local q = _G.QuestObjectiveTracker
	local after
	if q and moduleVisible(q) and not (q.IsCollapsed and q:IsCollapsed()) then
		local seen = false
		for _, module in ipairs(tracker.modules or {}) do
			if seen and moduleVisible(module) and module ~= profHeld then after = module break end
			if module == q then seen = true end
		end
	end
	local frameBottom = after and q:GetBottom()
	local lowest = after and moduleContentBottom(q)
	local more = after and ns.api.moreQuestsBottom and ns.api.moreQuestsBottom()
	if more and (not lowest or more < lowest) then lowest = more end
	if not (frameBottom and lowest) then ns.api.pushBelowMoreQuests(nil) return end
	ns.api.pushBelowMoreQuests(after, math.max(toScreen(q, frameBottom) - lowest, 0))
end
ns.api.pushSectionsAfterQuests = pushSectionsAfterQuests

local function refresh()
	if not viewport then return end
	-- Moving, resizing or re-parenting frames that hold secure buttons is blocked in combat (EnableMouseWheel, SetPoint
	-- and SetSize are protected functions); everything waits for PLAYER_REGEN_ENABLED.
	if InCombatLockdown() then needsLayout = true return end
	cbTime = nil -- the layout may change below: measure the content again
	if needsLayout then
		needsLayout = false
		capture()
		fitCap = nil
	end
	unclamp()
	if tracker:GetParent() ~= viewport then guarded(function() moveTracker("SetParent", viewport) end) end
	if #foreign == 0 then scanForeign() end
	for _, module in ipairs(tracker.modules or {}) do hookModule(module) end
	for _, module in ipairs(foreign) do hookModule(module) end

	-- Blizzard still cuts modules off: give the layout more room (bounded).
	if anyTruncated() and extraNow < MAX_EXTRA then
		extraNow = math.min(extraNow * 2, MAX_EXTRA)
		markDirty()
	end

	guarded(function() layoutGhost(); layoutTracker() end)
	detectMode()
	watchStrip()
	-- the Professions section in its own box above the tracker (R106-57), before the first section is picked
	if layoutProfessions then layoutProfessions() end
	-- the dungeon card at the very top (R106-84, Dungeon.lua), then the tracked reputation (R106-74,
	-- Reputation.lua): their room joins the fixed strip, and the scrolling sections move down by it (R106-77).
	-- R106-92: above the RXP guide too (user): a pinned guide is moved down by the card's room (its anchor offset, as
	-- the scroll offset), so the strip measured under it already holds the card, and the sections chained under the
	-- guide move with it. Without a pinned guide the card goes where the strip ends, as before.
	local cardRoom, cardOverGuide = 0, pinGuide and guide ~= nil
	if ns.api.layoutDungeonCard then
		local base = cardOverGuide and 0 or measurePinned()
		local ok, room = pcall(ns.api.layoutDungeonCard, ghost, base, trackerAlpha() * questAlpha())
		if ok and type(room) == "number" then cardRoom = room end
	end
	-- R106-102: the guide may already sit below the strip's top by itself (a section above it, the tracker's top
	-- padding): it moves down only by the part of the card's room it does not already have (user: empty space under
	-- the card). Its own place = where it is now, less the shift it has now.
	local shift = 0
	if cardOverGuide and cardRoom > 0 then
		local own = 0
		local top, gTop = ghost:GetTop(), guide:IsVisible() and guide:GetTop()
		if top and gTop then own = math.max(top - toScreen(guide, gTop) - guideShift, 0) end
		shift = math.max(cardRoom - own, 0)
	end
	if shift ~= guideShift or cardOverGuide then
		guideShift = shift
		if guide then setAnchorOffset(guide, anchorOffsetFor(guide)) end
	end
	pinned = measurePinned()
	if not cardOverGuide then pinned = pinned + cardRoom; drop = drop + cardRoom end
	if ns.api.layoutTrackedReputation then
		local ok, room = pcall(ns.api.layoutTrackedReputation, ghost, pinned, trackerAlpha() * questAlpha())
		-- R106-77: the scrolling sections move down by the same room (user: the top quest was cut off: it stayed
		-- where it was, under the strip that grew over it)
		if ok and type(room) == "number" then pinned = pinned + room; drop = drop + room end
	end
	-- the Quests header kept at the top (R106-49): its room joins the fixed strip
	pinned = pinned + pinQuestsHeader(pickFollower(), pinned)
	guarded(layoutViewport)
	fitToScreen()
	layoutBar()
	layoutDivider()
	if ns.api.layoutMoreQuests then pcall(ns.api.layoutMoreQuests) end
	pushSectionsAfterQuests()
	if strip then strip:SetShown(tracker:IsShown()) end

	if applyModuleWidths() then markDirty() end
	for _, module in ipairs(foreign) do hookGuideClicks(module) end
	if applyModuleScales() then
		applyModuleWidths()
		markDirty()
	end
	applyLevel()
	setFollower(pickFollower())
	local max = scrollMax()
	offset = math.min(math.max(offset, 0), max)
	setAnchorOffset(follower, anchorOffsetFor(follower))
	updateScrollbar()

	if not warned and tracker.GetAvailableHeight then
		local available = tracker:GetAvailableHeight()
		if available < naturalH + extraNow * 0.5 then
			warned = true
			say(("Blizzard's tracker did not use the extra height (available %d, expected about %d). Run /qt debug and send me the output."):format(available, naturalH + extraNow))
		end
	end
end

local pending
function schedule()
	if pending then return end
	pending = true
	C_Timer.After(0, function() pending = nil; refresh() end)
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local function savePosition()
	local point, _, relPoint, x, y = ghost:GetPoint(1)
	if point then db.pos = { point, relPoint, x, y } end
	fitCap = nil
	schedule()
end

-- Unlocked ("Lock tracker position" off): the tracker looks like a frame in Blizzard's Edit Mode (the selected look: a
-- see-through yellow panel with a yellow edge over the whole tracker, its name in the middle) and is dragged by it.
-- The game's own Edit Mode art is used when the client has it (NineSliceUtil, layout "EditModeSystemSelectionLayout",
-- texture kit "editmode-actionbar-selected"); otherwise the same look is drawn in plain colours. Right-click locks.
local EDIT_FILL, EDIT_EDGE = { 1, 0.82, 0, 0.22 }, { 1, 0.82, 0, 0.95 }
local function editModeArt(frame)
	local util = NineSliceUtil
	if util and type(util.ApplyLayoutByName) == "function" and C_Texture and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo("editmode-actionbar-selected-nineslice-corner") then
		local ok = pcall(util.ApplyLayoutByName, frame, "EditModeSystemSelectionLayout", "editmode-actionbar-selected")
		if ok and frame.TopLeftCorner then return true end
	end
	local fill = frame:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(EDIT_FILL[1], EDIT_FILL[2], EDIT_FILL[3], EDIT_FILL[4])
	local E = 2
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, E }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, E },
		{ "TOPLEFT", "BOTTOMLEFT", E, nil }, { "TOPRIGHT", "BOTTOMRIGHT", E, nil } }) do
		local line = frame:CreateTexture(nil, "BORDER")
		line:SetPoint(side[1]); line:SetPoint(side[2])
		if side[3] then line:SetWidth(side[3]) else line:SetHeight(side[4]) end
		line:SetColorTexture(EDIT_EDGE[1], EDIT_EDGE[2], EDIT_EDGE[3], EDIT_EDGE[4])
	end
	return false
end

local function createHandle()
	handle = withAlpha(CreateFrame("Frame", nil, UIParent))
	handle:SetPoint("TOPLEFT", ghost, "TOPLEFT", -4, 4)
	handle:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", 4, -4)
	handle:SetFrameStrata("HIGH")
	handle.nativeArt = editModeArt(handle)
	local text = handle:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(_G.GameFontHighlightHuge or _G.GameFontHighlightLarge or _G.GameFontHighlight)
	text:SetPoint("CENTER")
	text:SetShadowOffset(2, -2)
	text:SetShadowColor(0, 0, 0, 1)
	text:SetText("Objective Tracker")
	handle.label = text
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetText("Objective Tracker", 1, 0.82, 0)
		GameTooltip:AddLine("Drag to move. Right-click to lock it in place.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	-- The window follows the cursor through SetPoint every frame instead of StartMoving: the game's built-in frame
	-- dragging did nothing here (AllObjectives RXP notes StartMoving is restricted in Forever), and the tracker's
	-- re-layouts, which now run in the same frame as Blizzard's, would have snapped a StartMoving drag back anyway.
	local dragOffset
	local function cursor()
		local s = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		return x / s, y / s
	end
	local function stopDrag()
		if not movingGhost then return end
		handle:SetScript("OnUpdate", nil)
		movingGhost = false
		local left, top = ghost:GetLeft(), ghost:GetTop()
		if left and top then db.pos = { "TOPLEFT", "BOTTOMLEFT", left, top } end
		fitCap = nil
		schedule()
	end
	handle:SetScript("OnMouseDown", function(_, button)
		if button == "RightButton" then ns.api.setLocked(true) return end
		if button ~= "LeftButton" then return end
		if InCombatLockdown() then say("cannot move the tracker in combat") return end
		local left, top = ghost:GetLeft(), ghost:GetTop()
		if not left or not top then return end
		local cx, cy = cursor()
		dragOffset = { left - cx, top - cy }
		movingGhost = true
		handle:SetScript("OnUpdate", function()
			if InCombatLockdown() then stopDrag() return end
			-- let go of the button: the drag ends there, wherever the cursor is (OnMouseUp does not always reach the
			-- bar once the game has started a drag on it, which left it stuck to the cursor until a second click)
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then stopDrag() return end
			local x, y = cursor()
			ghost:ClearAllPoints()
			ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + dragOffset[1], y + dragOffset[2])
		end)
	end)
	handle:SetScript("OnMouseUp", stopDrag)
	handle:SetScript("OnDragStop", stopDrag)
	handle:SetScript("OnHide", stopDrag)
	handle:SetShown(not db.locked)
end

local function cursorY()
	local _, y = GetCursorPosition()
	return y / UIParent:GetEffectiveScale()
end

local function createScrollbar()
	bar = CreateFrame("Frame", nil, UIParent)
	bar:SetFrameStrata(tracker:GetFrameStrata())
	bar:SetFrameLevel(tracker:GetFrameLevel() + 4)
	bar:SetWidth(barWidth())
	bar:SetAlpha(BAR_ALPHA * trackerAlpha())
	bar:EnableMouse(true)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", function(self, delta) onWheel(self, delta, true) end) -- the scrollbar always scrolls
	thumb = CreateFrame("Frame", nil, bar)
	thumb:SetWidth(barWidth())
	thumb:EnableMouse(true)
	-- Forever look (ScrollSkin.lua); the arrows scroll one wheel notch
	root.scrollSkin.bar(bar, thumb, function(dir) onWheel(nil, -dir, true) end)

	-- click on the track: jump there
	bar:SetScript("OnMouseDown", function()
		local max = scrollMax()
		local trackH, thumbH = bar:GetHeight(), thumb:GetHeight()
		if max <= 0 or trackH <= thumbH then return end
		local fraction = (bar:GetTop() - cursorY() - thumbH / 2) / (trackH - thumbH)
		setOffset(math.min(math.max(fraction, 0), 1) * max)
	end)
	-- drag the thumb
	thumb:SetScript("OnMouseDown", function()
		dragging = { y = cursorY(), offset = offset }
		thumb:SetScript("OnUpdate", function()
			local max = scrollMax()
			local trackH, thumbH = bar:GetHeight(), thumb:GetHeight()
			if not dragging or max <= 0 or trackH <= thumbH then return end
			setOffset(dragging.offset + (dragging.y - cursorY()) * max / (trackH - thumbH))
		end)
	end)
	thumb:SetScript("OnMouseUp", function()
		dragging = nil
		thumb:SetScript("OnUpdate", nil)
	end)
	bar:Hide()
end

---------------------------------------------------------------------------------------------------------------------
-- R106-57: the Professions section above the quest tracker (user); R106-64: left of it, beside the Quests header. Blizzard's ProfessionsRecipeTracker leaves the
-- tracker for a box of its own just above the window (Quest list > Professions: "Professions above the quest
-- tracker", db.profAbove, on by default). The box is as tall as its first PROF_ROWS recipes; more scroll in it (the
-- wheel over it, and a scrollbar with the quest list's options of its own: shown, only on mouseover, width).
-- Blizzard's own place for it is remembered (the SetPoint hook in hookModule) and given back when switched off; a
-- section Blizzard chains to it takes its place in the tracker. Not moved in combat (refresh waits).
---------------------------------------------------------------------------------------------------------------------
do -- its own block (Lua's 200-locals limit)
local PROF_GAP, PROF_ROWS = 6, 2
local profBox, profBar, profThumb
local profOffset, profMax, profView = 0, 0, 0
local profDragging, profActive = nil, 0
local profParent
local profRetries = 0
local profFader = CreateFrame("Frame")

local function profBarWidth()
	local w = db and tonumber(db.profScrollbarWidth)
	return w and math.min(math.max(math.floor(w + 0.5), 2), 30) or BAR_WIDTH
end

function placeProf()
	local m = profHeld
	if not (m and profBox) then return end
	local units = profOffset * UIParent:GetEffectiveScale() / m:GetEffectiveScale()
	guarded(function()
		m:ClearAllPoints()
		m:SetPoint("TOPLEFT", profBox, "TOPLEFT", 0, units)
		m:SetPoint("TOPRIGHT", profBox, "TOPRIGHT", 0, units)
	end)
end

-- its whole height and the height of its first PROF_ROWS recipes (header included), UIParent units
local function profHeights(m)
	local top = m:GetTop()
	if not top then return nil end
	top = toScreen(m, top)
	local lowest = moduleContentBottom(m)
	if not lowest then return nil end
	local full = math.max(top - lowest, 0)
	local blocks = {}
	for _, byId in pairs(type(m.usedBlocks) == "table" and m.usedBlocks or {}) do
		for _, block in pairs(type(byId) == "table" and byId or {}) do
			if type(block) == "table" and block.IsShown and block:IsShown() and block:GetTop() then blocks[#blocks + 1] = block end
		end
	end
	table.sort(blocks, function(a, b) return a:GetTop() > b:GetTop() end)
	local view = full
	if #blocks > PROF_ROWS then
		local cut = lowestShown(blocks[PROF_ROWS], 2, nil)
		if cut then view = math.min(full, math.max(top - cut, 0)) end
	end
	return full, view
end

local function updateProfBar()
	if not profBar then return end
	local show = db.profScrollbar ~= false and profMax > 0 and profBox and profBox:IsShown()
	profBar:SetShown(show and true or false)
	if not show then return end
	profBar:SetWidth(profBarWidth())
	profThumb:SetWidth(profBarWidth())
	profBar:ClearAllPoints()
	-- R106-64: on the box's outer (left) side, away from the quest list and its own scrollbar
	profBar:SetPoint("TOPRIGHT", profBox, "TOPLEFT", -2, 0)
	profBar:SetPoint("BOTTOMRIGHT", profBox, "BOTTOMLEFT", -2, 0)
	local trackH = profBar:GetHeight()
	if not trackH or trackH <= 0 then return end
	local thumbH = math.min(math.max(profView / (profView + profMax) * trackH, 24), trackH)
	profThumb:SetHeight(thumbH)
	profThumb:ClearAllPoints()
	profThumb:SetPoint("TOP", profBar, "TOP", 0, -(profOffset / profMax) * (trackH - thumbH))
end

local function profFadeStep(_, elapsed)
	if not profBar then return end
	if not db.profScrollbarMouseover then
		profBar:SetAlpha(BAR_ALPHA * trackerAlpha())
		profFader:SetScript("OnUpdate", nil)
		return
	end
	local now = GetTime()
	if profDragging or profBar:IsMouseOver() or (profBox and profBox:IsMouseOver()) then profActive = now end
	local full = BAR_ALPHA * trackerAlpha()
	local target = (now - profActive < FADE_DELAY) and full or 0
	local alpha = profBar:GetAlpha()
	local stepSize = full * elapsed / FADE_TIME
	if alpha < target then alpha = math.min(target, alpha + stepSize) elseif alpha > target then alpha = math.max(target, alpha - stepSize) end
	profBar:SetAlpha(alpha)
end
local function updateProfFader()
	if db.profScrollbarMouseover then profFader:SetScript("OnUpdate", profFadeStep) else profFadeStep(nil, 0) end
end

local function setProfOffset(value)
	profActive = GetTime()
	profOffset = math.min(math.max(value, 0), profMax)
	placeProf()
	updateProfBar()
end

local function createProfBox()
	profBox = withAlpha(CreateFrame("Frame", "RXPForeverTrackerProfessions", UIParent))
	profBox:SetClipsChildren(true)
	profBox:EnableMouseWheel(true) -- once, out of combat (protected)
	profBox:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() and profHeld and not canMove(profHeld) then return end
		setProfOffset(profOffset - delta * db.step)
	end)
	profBar = CreateFrame("Frame", nil, UIParent)
	profBar:EnableMouse(true)
	profBar:EnableMouseWheel(true)
	profBar:SetScript("OnMouseWheel", function(_, delta) setProfOffset(profOffset - delta * db.step) end)
	profThumb = CreateFrame("Frame", nil, profBar)
	profThumb:EnableMouse(true)
	root.scrollSkin.bar(profBar, profThumb, function(dir) setProfOffset(profOffset + dir * db.step) end)
	profBar:SetScript("OnMouseDown", function()
		local trackH, thumbH = profBar:GetHeight(), profThumb:GetHeight()
		if profMax <= 0 or trackH <= thumbH then return end
		local fraction = (profBar:GetTop() - cursorY() - thumbH / 2) / (trackH - thumbH)
		setProfOffset(math.min(math.max(fraction, 0), 1) * profMax)
	end)
	profThumb:SetScript("OnMouseDown", function()
		profDragging = { y = cursorY(), offset = profOffset }
		profThumb:SetScript("OnUpdate", function()
			local trackH, thumbH = profBar:GetHeight(), profThumb:GetHeight()
			if not profDragging or profMax <= 0 or trackH <= thumbH then return end
			setProfOffset(profDragging.offset + (profDragging.y - cursorY()) * profMax / (trackH - thumbH))
		end)
	end)
	profThumb:SetScript("OnMouseUp", function()
		profDragging = nil
		profThumb:SetScript("OnUpdate", nil)
	end)
	profBar:Hide()
	profBox:Hide()
end

local function releaseProfessions()
	local m = profHeld
	if not m then return end
	profHeld = nil
	guarded(function()
		m:SetParent(profParent or tracker)
		m:ClearAllPoints()
		for point, a in pairs(bases[m] or {}) do m:SetPoint(point, a[1], a[2], a[3], a[4]) end
	end)
	if profBox then profBox:Hide() end
	if profBar then profBar:Hide() end
	profOffset = 0
	markDirty()
end

function layoutProfessions()
	local m = _G.ProfessionsRecipeTracker
	if not (db.profAbove ~= false and m and ghost) then releaseProfessions() return end
	if InCombatLockdown() then return end
	if not profBox then createProfBox() end
	if profHeld ~= m then
		profParent = m:GetParent()
		profHeld = m
		guarded(function() m:SetParent(profBox) end)
		markDirty() -- the tracker closes the gap it leaves
	end
	local s = scale()
	profBox:SetScale(s)
	profBox:SetFrameStrata(tracker:GetFrameStrata())
	profBox:SetFrameLevel(tracker:GetFrameLevel())
	profBar:SetFrameStrata(tracker:GetFrameStrata())
	profBar:SetFrameLevel(tracker:GetFrameLevel() + 4)
	profBox:ClearAllPoints()
	-- R106-64: left of the quest list, its top level with the "Quests" header (the clip area's top, under the fixed
	-- strip), as wide as the list; moved by Quest list > "Professions horizontal / vertical position" (db.profX, profY)
	local px = math.min(math.max(tonumber(db.profX) or 0, -400), 400)
	local py = math.min(math.max(tonumber(db.profY) or 0, -400), 400)
	profBox:SetPoint("TOPRIGHT", viewport, "TOPLEFT", (px - PROF_GAP) / s, py / s)
	profBox:SetWidth(math.max(ghost:GetWidth() * (ghost:GetEffectiveScale() / profBox:GetEffectiveScale()), 50))
	if not (m:IsShown() and tracker:IsShown()) then
		profBox:Hide()
		updateProfBar()
		return
	end
	-- R106-62: shown before it is measured: inside a hidden box the section has no place, so it was never measured
	-- and the box never showed (user: no Professions header and no recipes after R106-57). Without a place yet it
	-- stays open a header tall and is measured again on the next frame (a few times at most).
	if not profBox:IsShown() then profBox:SetHeight(math.max(profBox:GetHeight() or 0, 30 / s)) end
	profBox:Show()
	placeProf()
	local full, view = profHeights(m)
	if not full then
		profRetries = profRetries + 1
		if profRetries <= 5 and C_Timer then C_Timer.After(0, ns.api.applyLayout) end
		return
	end
	profRetries = 0
	profView = view
	profMax = math.max(full - view, 0)
	profOffset = math.min(profOffset, profMax)
	profBox:SetHeight(math.max(view + 2, 1) / s)
	placeProf()
	profBox:Show()
	updateProfBar()
	updateProfFader()
end

function ns.api.setProfessionsAbove(on)
	db.profAbove = on and true or false
	if not db.profAbove then releaseProfessions() end
	ns.api.applyLayout()
end
function ns.api.setProfessionsPosition(x, y)
	if x ~= nil then db.profX = math.floor((tonumber(x) or 0) + 0.5) end
	if y ~= nil then db.profY = math.floor((tonumber(y) or 0) + 0.5) end
	if not InCombatLockdown() then layoutProfessions() end
end
function ns.api.setProfScrollbarShown(on) db.profScrollbar = on and true or false; updateProfBar() end
function ns.api.setProfScrollbarMouseover(on)
	db.profScrollbarMouseover = on and true or false
	profActive = GetTime()
	updateProfFader()
end
function ns.api.setProfScrollbarWidth(value)
	db.profScrollbarWidth = math.min(math.max(math.floor((tonumber(value) or BAR_WIDTH) + 0.5), 2), 30)
	updateProfBar()
end
end -- the Professions block

---------------------------------------------------------------------------------------------------------------------
-- API used by the config window, the minimap button and the slash commands
---------------------------------------------------------------------------------------------------------------------
function ns.api.applyLayout()
	if not viewport then return end
	fitCap = nil
	schedule()
end

-- Tracker settings > Own window: the RXP Tracker in a window of its own, or back in the quest tracker
function ns.api.setGuideDetached(on)
	local guideNs = root.objectives
	if not (guideNs and guideNs.setDetached) then return false end
	local ok = guideNs.setDetached(on)
	if ok then
		detectMode()
		ns.api.applyLayout()
		markDirty()
	end
	return ok
end

function ns.api.resetGuideWindow()
	local guideNs = root.objectives
	if guideNs and guideNs.resetWindowPosition then guideNs.resetWindowPosition() end
end

function ns.api.applyScale()
	ns.api.applyLayout()
	markDirty() -- lets AllObjectives RXP re-read the tracker's scale
end

function ns.api.setLocked(locked)
	db.locked = locked and true or false
	if handle then handle:SetShown(not db.locked) end
	if ns.api.refreshConfig then ns.api.refreshConfig() end
end

function ns.api.setScrollbarShown(shown)
	db.scrollbar = shown and true or false
	updateScrollbar()
end

function ns.api.applyQuestsPad()
	if viewport then needsLayout = true; schedule() end
end

function ns.api.applyQuestScale()
	if not viewport then return end
	needsLayout = true
	schedule()
end

function ns.api.applyGuideScale()
	local relayout = root.objectives.relayout
	if relayout then pcall(relayout) end -- the guide re-reads its factor when it is placed
	if viewport then needsLayout = true; schedule() end
end

local function copyDefault(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = v end
	return copy
end

-- keys: only these settings (the /qt page whose Defaults was clicked); nil: every quest tracker setting
function ns.api.resetDefaults(keys, label)
	if InCombatLockdown() then say("cannot reset in combat") return end
	local all = keys == nil
	local function wanted(key) return all or keys[key] end
	if all and ns.api.restoreZone then ns.api.restoreZone() end
	local wasDetached = db.guideDetached and true or false
	for key, value in pairs(DEFAULTS) do
		if wanted(key) then db[key] = copyDefault(value) end
	end
	if all then db.pos = homePosition() end
	if wanted("rewardOrder") then db.rewardOrder = { "xp", "gold" } end
	if (wanted("trackMode") or wanted("zoneSort")) and ns.api.setMode then
		ns.api.setMode(DEFAULTS.trackMode, DEFAULTS.zoneSort)
	end
	if handle then handle:SetShown(false) end
	offset = 0
	fitCap = nil
	needsLayout = true
	if ns.api.applyZoneHeaders then ns.api.applyZoneHeaders() end
	if ns.api.applyExtras then ns.api.applyExtras() end
	-- the title / objective outlines back to the game's (R106-48)
	if (wanted("titleOutline") or wanted("objectiveOutline")) and ns.api.afterTrackerUpdateFonts then
		pcall(ns.api.afterTrackerUpdateFonts)
	end
	if ns.api.applyQuestsHeaderLook then pcall(ns.api.applyQuestsHeaderLook) end
	if ns.api.updateQuestCount then pcall(ns.api.updateQuestCount) end
	ns.api.applyGuideScale()
	if ns.api.applyLevel then ns.api.applyLevel() end
	if wanted("minimap") and type(db.minimap) == "table" then
		db.minimap.hide = false
		if ns.api.setMinimapShown then ns.api.setMinimapShown(true) end
	end
	-- back into the quest tracker: setDetached acts only on a change, so it sees the window as it was
	if wanted("guideDetached") and wasDetached and ns.api.setGuideDetached then
		db.guideDetached = true
		pcall(ns.api.setGuideDetached, false)
	end
	schedule()
	markDirty()
	if ns.api.refreshConfig then ns.api.refreshConfig() end
	say((label and (label .. " ") or "") .. "settings reset to defaults")
end

-- The tracker's width without Extra width (tracker units): the RXP Tracker takes this, so Extra width does not
-- move its divider lines (Upcoming Steps header, the line between steps)
function ns.api.naturalWidth()
	return naturalW and naturalW > 0 and naturalW or nil
end

-- The quest list scrollbar's column, left and right edge in screen pixels (nil before it exists): the RXP Tracker's
-- upcoming-steps scrollbar lines up with it
function ns.api.questBarColumn()
	if not bar then return nil end
	local left, right = bar:GetLeft(), bar:GetRight()
	if not (left and right) then return nil end
	local scale = bar:GetEffectiveScale()
	return left * scale, right * scale
end

function ns.api.applyWidth()
	if not viewport then return end
	fitCap = nil
	applyModuleWidths()
	markDirty()
	if tracker.Update then pcall(securecallfunction, tracker.Update, tracker, true) end -- re-lay out the text now
	schedule()
end

function ns.api.applyLevel()
	if viewport then applyLevel() end
end

function ns.api.resetPosition()
	db.pos = homePosition()
	fitCap = nil
	offset = 0
	schedule()
end

function ns.api.scrollToTop()
	if viewport then setOffset(0) end
end

function ns.api.relayout()
	needsLayout = true
	schedule()
end

---------------------------------------------------------------------------------------------------------------------
local function enable()
	ghost = CreateFrame("Frame", "RXPForeverTrackerAnchor", UIParent)
	ghost:SetMovable(true)
	ghost:SetClampedToScreen(false) -- the tracker may be dragged partly off screen

	viewport = withAlpha(CreateFrame("Frame", "RXPForeverTrackerViewport", UIParent))
	viewport:SetClipsChildren(true)
	viewport:SetFrameStrata(tracker:GetFrameStrata())
	viewport:SetFrameLevel(tracker:GetFrameLevel())
	viewport:SetScript("OnMouseWheel", onWheel)
	viewport:EnableMouseWheel(true) -- once, out of combat: it is a protected function, so it is never toggled later

	naturalW, naturalH = tracker:GetWidth(), tracker:GetHeight()
	tracker.qtsLevel = tracker:GetFrameLevel()
	tracker.qtsStrata = tracker:GetFrameStrata()
	extraNow = EXTRA
	if not capture() then
		-- Blizzard has not anchored the tracker yet; try again shortly.
		viewport, ghost = nil, nil
		C_Timer.After(1, enable)
		return
	end
	recordHome()

	-- The header (and the guide's header buttons, which hang on it) must stay visible above the clipped viewport.
	strip = withAlpha(CreateFrame("Frame", nil, UIParent))
	strip:SetFrameStrata(tracker:GetFrameStrata())
	strip:SetFrameLevel(tracker:GetFrameLevel() + 3)
	strip:SetShown(tracker:IsShown())

	unclamp()
	guarded(function()
		layoutGhost()
		moveTracker("SetParent", viewport)
		if tracker.Header and tracker.Header.SetParent then tracker.Header:SetParent(strip) end
		layoutTracker()
		layoutViewport()
	end)
	createHandle()
	createScrollbar()
	C_Timer.After(SETTLE_DELAY, function() screenSettled = true; scheduleScreenCheck() end)
	updateFader()
	tracker:HookScript("OnShow", function() if strip then strip:SetShown(true) end; schedule() end)
	tracker:HookScript("OnHide", function() if strip then strip:SetShown(false) end; schedule() end)

	-- Blizzard moves or resizes the tracker (Edit Mode, managed frames, text size): follow it.
	-- Both hooks put our anchor / height back in the same frame Blizzard changed them, instead of one frame later: the
	-- one-frame gap was visible as flicker (leaving a building) and jumps (casting on yourself).
	local function onAnchor()
		if guard then return end
		if canMove(tracker) then
			capture()
			guarded(function()
				moveTracker("ClearAllPoints")
				moveTracker("SetPoint", "TOPLEFT", ghost, "TOPLEFT", 0, 0)
				moveTracker("SetPoint", "TOPRIGHT", ghost, "TOPRIGHT", 0, 0)
			end)
		else
			needsLayout = true
		end
		schedule()
	end
	hooksecurefunc(tracker, "SetPoint", onAnchor)
	local function onSize()
		if guard then return end
		local w, h = tracker:GetWidth(), tracker:GetHeight()
		-- While the tracker hangs between the window's two top corners its width is the window's, i.e. ours (natural
		-- width + Extra width): only a width it has on its own (Blizzard anchored it elsewhere) is Blizzard's natural
		-- one. Taking the window's width as natural made Extra width pile up (the drag bar and everything sized from
		-- the window stayed wide after setting it back to 0, until /reload).
		local _, rel = tracker:GetPoint(1)
		local ownWidth = rel ~= ghost
		local widthOff = ownWidth and math.abs(w - naturalW) > 0.5
		if math.abs(h - (naturalH + extraNow)) > 0.5 or widthOff then
			if ownWidth then naturalW = w end
			naturalH = h
			if canMove(tracker) then
				guarded(function() tracker:SetHeight(naturalH + extraNow) end)
			else
				needsLayout = true
			end
			schedule()
		end
	end
	hooksecurefunc(tracker, "SetHeight", onSize)
	hooksecurefunc(tracker, "SetWidth", onSize)
	hooksecurefunc(tracker, "SetSize", onSize)
	hooksecurefunc(tracker, "SetClampedToScreen", function(_, clamped)
		if clamped and not guard then schedule() end
	end)
	-- Same frame, too: a scale or parent change was visible as the tracker shrinking until the next full update.
	local function onScale()
		if guard then return end
		if math.abs(tracker:GetScale() - scale()) > 1e-4 and canMove(tracker) then
			guarded(function() moveTracker("SetScale", scale()) end)
		end
		schedule()
	end
	hooksecurefunc(tracker, "SetScale", onScale)
	-- When your buffs change, Blizzard's managed-frame layout (the column that stacks the tracker under the buffs on
	-- the right side of the screen) can take the tracker back into its own, smaller-scaled container. That is the
	-- "casting Rejuvenation on myself makes it slightly smaller" in the video: the tracker kept our anchor but not our
	-- parent. Put it straight back into our clipping frame.
	local function onParent()
		if guard or tracker:GetParent() == viewport then return end
		if canMove(tracker) then
			guarded(function() moveTracker("SetParent", viewport) end)
		else
			needsLayout = true
		end
		schedule()
	end
	hooksecurefunc(tracker, "SetParent", onParent)

	-- The managed-frame layout that runs when your buffs change (Rejuvenation, Cat Form - the video shows the flicker
	-- in the same frame the buff row changes) places the tracker through the "Base" originals of these methods, which a
	-- hook on SetPoint / SetScale / SetParent does not see; the tracker was then fixed only on the next frame (the
	-- one-frame shrink). Hook the Base methods too, so the same-frame fix covers them.
	local baseHooks = {
		SetPointBase = onAnchor, ClearAllPointsBase = onAnchor,
		SetScaleBase = onScale, SetParentBase = onParent,
	}
	for method, handler in pairs(baseHooks) do
		if type(tracker[method]) == "function" then hooksecurefunc(tracker, method, handler) end
	end
	hooksecurefunc(tracker, "ClearAllPoints", function()
		-- an anchor-less tracker that nobody re-anchors in the same call would vanish for a frame
		if not guard and tracker:GetNumPoints() == 0 then onAnchor() end
	end)

	-- Runs after Blizzard (and after AllObjectives RXP, which hooks the same method and loads first).
	hooksecurefunc(ObjectiveTrackerContainerMixin, "Update", function(self)
		if self == tracker then schedule() end
	end)

	-- Make Blizzard lay out with the inflated height right away.
	markDirty()
	schedule()
end

-- Change log for /qt debug: while recording (60 s after /qt debug), every frame a few numbers of the tracker, the
-- guide and our frames are compared with the last frame; changes are kept (last 30). A one-frame flicker shows up here
-- as a change and its change back. It does not run otherwise (it built a table and strings every frame).
local changeLog, frameNo, lastSeen = {}, 0, {}
local function snapshot()
	local s = {}
	local function put(key, value) s[key] = value end
	local function num(v) return v and math.floor(v * 10 + 0.5) / 10 or "nil" end
	put("tracker.parent", tracker:GetParent() == viewport and "ours" or tostring(tracker:GetParent() and tracker:GetParent():GetName()))
	put("tracker.scale", num(tracker:GetEffectiveScale() * 100))
	put("tracker.left", num(tracker:GetLeft())); put("tracker.top", num(tracker:GetTop()))
	if ghost then put("window.left", num(ghost:GetLeft())); put("window.top", num(ghost:GetTop())) end
	if viewport then put("clip.top", num(viewport:GetTop())); put("clip.left", num(viewport:GetLeft())) end
	if strip then put("header.scale", num(strip:GetEffectiveScale() * 100)) end
	local g = foreign[1]
	if g then
		put("guide.scale", num(g:GetEffectiveScale() * 100)); put("guide.left", num(g:GetLeft())); put("guide.top", num(g:GetTop()))
		put("guide.parent", g:GetParent() == viewport and "clip" or "UIParent")
		put("guide.points", g:GetNumPoints())
	end
	local q = _G.QuestObjectiveTracker
	if q then put("quests.scale", num(q:GetEffectiveScale() * 100)); put("quests.top", num(q:GetTop())) end
	return s
end
local watcher = CreateFrame("Frame")
watcher:Hide()
local RECORD_SECONDS = 60
local recordUntil = 0
watcher:SetScript("OnUpdate", function(self)
	if not viewport or GetTime() > recordUntil then self:Hide() return end
	frameNo = frameNo + 1
	local now = snapshot()
	local changed = {}
	for key, value in pairs(now) do
		if lastSeen[key] ~= nil and lastSeen[key] ~= value then
			changed[#changed + 1] = ("%s %s>%s"):format(key, tostring(lastSeen[key]), tostring(value))
		end
	end
	lastSeen = now
	if #changed > 0 then
		table.sort(changed)
		changeLog[#changeLog + 1] = ("frame %d: %s"):format(frameNo, table.concat(changed, ", "))
		if #changeLog > 30 then table.remove(changeLog, 1) end
	end
end)

-- /qt debug: the layout state as lines (say is the collector), shown in a window (Tracker/DebugWindow.lua) to copy
local function debugLines(say)
	say(("enabled=%s step=%s extra=%s height=%s scale=%s locked=%s zoneSort=%s scrollbar=%s offset=%.0f"):format(
		tostring(db.enabled), db.step, extraNow, tostring(db.height), tostring(db.scale), tostring(db.locked),
		tostring(db.zoneSort), tostring(db.scrollbar), offset))
	if not viewport then say("viewport not created") return end
	local parent = tracker:GetParent()
	say(("tracker parent=%s, scale=%.3f, effective scale=%.3f (UI %.3f)"):format(
		parent == viewport and "our clipping frame" or tostring(parent and (parent.GetName and parent:GetName()) or parent),
		tracker:GetScale(), tracker:GetEffectiveScale(), UIParent:GetEffectiveScale()))
	say(("guide un-pinned by section above it=%s"):format(tostring(unpinnedBy)))
	say(("window %.0fx%.0f, viewport %.0fx%.0f, fixed strip %.0f px (guide fixed=%s), tracker %.0fx%.0f, Blizzard natural %.0fx%.0f"):format(
		ghost:GetWidth(), ghost:GetHeight(), viewport:GetWidth(), viewport:GetHeight(), pinned, tostring(pinGuide),
		tracker:GetWidth(), tracker:GetHeight(), naturalW, naturalH))
	local okWheel, wheelOn = pcall(viewport.IsMouseWheelEnabled, viewport)
	say(("wheel enabled=%s, wheel events received=%d, mouse over viewport=%s, in combat=%s"):format(
		tostring(okWheel and wheelOn), wheelEvents, tostring(viewport:IsMouseOver()), tostring(InCombatLockdown())))
	say("Blizzard anchor: " .. blizzardAnchor .. (db.pos and " (your own position is used)" or ""))
	say(("viewport top=%s bottom=%s screen height=%s fitCap=%s tracker clamped=%s"):format(tostring(viewport:GetTop()),
		tostring(viewport:GetBottom()), tostring(UIParent:GetHeight()), tostring(fitCap),
		tostring(tracker.IsClampedToScreen and tracker:IsClampedToScreen())))
	say(("scrollMax=%.0f anyTruncated=%s scrolling module=%s (anchor recorded: %s)"):format(scrollMax(), tostring(anyTruncated()),
		tostring(follower and (follower:GetName() or follower.uiOrder)), tostring(follower and bases[follower] ~= nil and next(bases[follower]) ~= nil)))
	for _, module in ipairs(tracker.modules or {}) do
		if module:IsShown() then
			say(("  module %s contents=%s bottom=%s truncated=%s"):format(tostring(module:GetName() or module.uiOrder),
				tostring(module.GetContentsHeight and module:GetContentsHeight()), tostring(module:GetBottom()),
				tostring(module.IsTruncated and module:IsTruncated())))
		end
	end
	say(("header parent is strip: %s, foreign modules (RXP guide): %d"):format(
		tostring(tracker.Header and tracker.Header:GetParent() == strip), #foreign))
	for _, module in ipairs(foreign) do
		say(("  parent is %s shown=%s bottom=%s"):format(module:GetParent() == viewport and "viewport" or "UIParent",
			tostring(module:IsShown()), tostring(module:GetBottom())))
		say(("    guide scale=%.3f effective=%.3f width=%.0f left=%s top=%s"):format(
			module:GetScale(), module:GetEffectiveScale(),
			module:GetWidth(), tostring(module:GetLeft()), tostring(module:GetTop())))
		for i = 1, module:GetNumPoints() do
			local p, rel, rp, x, y = module:GetPoint(i)
			say(("    guide point %d: %s to %s %s (%.1f, %.1f)"):format(i, tostring(p),
				tostring(rel and (rel.GetName and rel:GetName() or (rel == tracker.Header and "tracker header") or "unnamed frame")),
				tostring(rp), x or 0, y or 0))
		end
	end
	say(("last %d changes (scales x100, positions in UI units; now frame %d):"):format(#changeLog, frameNo))
	for _, line in ipairs(changeLog) do say("  " .. line) end
	-- record the next minute, for the next /qt debug
	recordUntil = GetTime() + RECORD_SECONDS
	lastSeen = {}
	watcher:Show()
	say(("Recording layout changes for %d s: /qt debug again to see them."):format(RECORD_SECONDS))
	if ns.api.zoneDebug then ns.api.zoneDebug(say) end
	if ns.api.extrasDebug then ns.api.extrasDebug(say) end
	local q = _G.QuestObjectiveTracker
	if q then
		say(("quest module width=%.0f (Blizzard %s) lineWidth=%s blockWidth=%s"):format(q:GetWidth(), tostring(q.qtsBaseW),
			tostring(q.lineWidth), tostring(q.blockWidth)))
	end
	say(("scale=%s, layer=%s (tracker default %s %s), extra width=%s"):format(tostring(db.scale), tostring(db.layer), tostring(tracker.qtsStrata), tostring(tracker.qtsLevel), tostring(db.widthExtra)))
	say("RXP guide: " .. (root.objectives.rxp and "built-in copy" or root.standaloneObjectives and "separate addon (disable it to use the built-in copy)" or "inactive (RestedXP not available)"))
end

_G.SLASH_ALLTRACKERRXP1 = "/qt"
_G.SLASH_ALLTRACKERRXP2 = "/rxpft"
_G.SLASH_ALLTRACKERRXP3 = "/qtrxp"
-- /qt help (and any command /qt does not know): every command (debug is left out: it is for bug reports), the quest tracker's first, then the RXP Tracker's
local QT_HELP = {
	{ "", "open or close the settings window" },
	{ "config", "the same as /qt" },
	{ "guide", "open the settings window at the guide page" },
	{ "quests", "open the settings window at the quest tracker page" },
	{ "orphan", "open the settings window at Orphaned quests" },
	{ "height <px>", "visible tracker height (0 = automatic)" },
	{ "scale <0.5-1.5>", "tracker scale" },
	{ "step <px>", "how far one mouse-wheel turn scrolls" },
	{ "zone", "sort quests by zone, on or off" },
	{ "sort", "sort the quests now" },
	{ "lock", "lock the tracker in place" },
	{ "unlock", "unlock the tracker (drag it like a frame in Edit Mode)" },
	{ "distance", "why a quest title shows or hides its distance arrow" },
	{ "fontlog", "record the tracker's font changes for 10 s (open the map meanwhile), then show who made them" },
	{ "reset", "scroll the tracker back to the top" },
	{ "on", "turn the quest tracker on (then /reload)" },
	{ "off", "turn the quest tracker off (then /reload)" },
	{ "help", "this list" },
}
local function printHelp()
	local chat = DEFAULT_CHAT_FRAME
	chat:AddMessage("|cff33ff99RXP ForeverTracker|r quest tracker:")
	for _, entry in ipairs(QT_HELP) do
		chat:AddMessage("|cff33ff99/qt" .. (entry[1] ~= "" and " " .. entry[1] or "") .. "|r  " .. entry[2])
	end
	local guide = root.objectives
	if guide and guide.printHelp then
		guide.printHelp()
	else
		chat:AddMessage("RXP Tracker (needs RestedXP Guides): |cff33ff99/qt toggle|r, |cff33ff99/qt steps|r, |cff33ff99/qt <0-100>|r or |cff33ff99all|r, |cff33ff99/qt arrow|r, |cff33ff99/qt satellites|r, |cff33ff99/qt badge|r, |cff33ff99/qt status|r, |cff33ff99/qt welcome|r, |cff33ff99/qt restart|r, |cff33ff99/qt why|r")
	end
end

SlashCmdList.ALLTRACKERRXP = function(msg)
	local cmd, arg = (msg or ""):match("^(%S*)%s*(%S*)$")
	cmd = (cmd or ""):lower()
	if not db then return end
	if cmd == "" or cmd == "config" then
		if ns.api.toggleConfig then ns.api.toggleConfig() end
	elseif cmd == "guide" or cmd == "quests" then
		if ns.api.openConfigTab then ns.api.openConfigTab(cmd) end
	elseif cmd == "orphan" or cmd == "orphans" then
		local g = root.objectives and root.objectives.settings
		if g and g.orphansAvailable and g.orphansAvailable() and ns.api.openConfigTab then
			ns.api.openConfigTab("orphans")
		else
			say("orphaned quests need RestedXP Guides.")
		end
	elseif cmd == "height" and tonumber(arg) then
		db.height = math.max(0, tonumber(arg)); say("visible height = " .. (db.height == 0 and "auto" or db.height))
		ns.api.applyLayout(); if ns.api.refreshConfig then ns.api.refreshConfig() end
	elseif cmd == "scale" and tonumber(arg) then
		db.scale = math.min(math.max(tonumber(arg), 0.5), 1.5); say("scale = " .. db.scale)
		ns.api.applyScale(); if ns.api.refreshConfig then ns.api.refreshConfig() end
	elseif cmd == "step" and tonumber(arg) then
		db.step = math.max(5, tonumber(arg)); say("step = " .. db.step)
		if ns.api.refreshConfig then ns.api.refreshConfig() end
	elseif cmd == "zone" then
		if ns.api.setZoneSort then ns.api.setZoneSort(not db.zoneSort) end
		say("sort by zone " .. (db.zoneSort and "on" or "off"))
	elseif cmd == "sort" then
		if ns.api.sortNow then ns.api.sortNow() end
	elseif cmd == "lock" then ns.api.setLocked(true); say("tracker locked")
	elseif cmd == "unlock" then ns.api.setLocked(false); say("tracker unlocked: drag it like a frame in Edit Mode")
	elseif cmd == "distance" then
		if ns.api.distanceReport then ns.api.distanceReport(say) end
	elseif cmd == "fontlog" then
		if ns.api.fontLog then ns.api.fontLog(say) end
	elseif cmd == "reset" then ns.api.scrollToTop()
	elseif cmd == "off" then
		db.enabled = false
		say("disabled. Type /reload to restore Blizzard's tracker.")
	elseif cmd == "on" then
		db.enabled = true; say("enabled. Type /reload.")
	elseif cmd == "debug" then
		local lines = {}
		debugLines(function(text) lines[#lines + 1] = tostring(text) end)
		if ns.api.npcPanelDebug then ns.api.npcPanelDebug(function(text) lines[#lines + 1] = tostring(text) end) end
		if ns.api.showDebugWindow then
			ns.api.showDebugWindow(lines)
		else
			for _, text in ipairs(lines) do say(text) end
		end
	else
		-- the RXP Tracker's commands (toggle, 0-100, all, arrow, satellites, badge, status, welcome, restart, why)
		local guide = root.objectives
		if cmd ~= "help" and guide and guide.runCommand and guide.runCommand(msg) then return end
		printHelp()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		RXPForeverTrackerDB = RXPForeverTrackerDB or {}
		db = RXPForeverTrackerDB
		local fresh = next(db) == nil
		for key, value in pairs(DEFAULTS) do
			-- an unset tracking mode is a real choice ("Blizzard's normal tracking") for existing settings
			if db[key] == nil and (fresh or key ~= "trackMode") then db[key] = value end
		end
		db.scrollbarColor = nil -- removed: every scrollbar uses the Forever art (ScrollSkin.lua)
		if type(db.minimap) ~= "table" then db.minimap = { hide = false, angle = 225 } end
		db.extra = nil -- "layout room" is automatic now
		db.guideScrolls = nil -- "Scroll the RestedXP guide with the quests" was removed
		db.guideScale, db.questScale = factor(db.guideScale), factor(db.questScale)
		db.showRep = nil -- "Rep reward after titles" was removed
		-- 3.5.26: word wrap is on by default, and switched on once for existing settings
		if not db.wrapDefaulted then db.wordWrap, db.wrapDefaulted = true, true end
		ns.db = db
		for _, fn in ipairs(ns.onLogin) do xpcall(fn, geterrorhandler()) end
		-- no saved spot yet (first use): the middle of the screen, so the window is on screen from the start
		if type(db.pos) ~= "table" then db.pos = homePosition() end
		if db.enabled then enable() end
		-- the very first time the addon loads, open the settings so the options are found
		if fresh and ns.api.toggleConfig then C_Timer.After(3, ns.api.toggleConfig) end
	elseif viewport then
		if event == "PLAYER_REGEN_ENABLED" then needsLayout = true end
		schedule()
	end
end)
