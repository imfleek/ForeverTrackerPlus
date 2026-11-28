local _, root = ...; local ns = root.objectives
if not ns.rxp then return end

local NO_ENTRIES = {}

local module, snapshot, grantedLast, foldedLast
-- true while our frame has no guide slot yet (draw)
local paused = false

function ns.paused()
	return paused
end

local function entries()
	return snapshot and snapshot.entries or NO_ENTRIES
end

-- The guide lives in our own tracker's guide slot (Tracker/Own/Frame.lua api.ownGuideHost), or in its own window.
-- Nothing here touches Blizzard's tracker. It shows in battlegrounds and arenas too.
-- 3.2 (user: "Delete the old tracker's code"): the placement inside Blizzard's tracker was removed.
local function trackerApi() return root.tracker and root.tracker.api end
local function ownHost()
	local api = trackerApi()
	return api and api.ownGuideHost and api.ownGuideHost() or nil
end
local function guideFactorEarly()
	local tdb = root.tracker and root.tracker.db
	local value = tdb and tonumber(tdb.guideScale) or 1
	return math.min(math.max(value, 0.5), 1.5)
end

-- the room our frame gives the guide (its own window: the screen)
local function grantedHeight()
	if ns.detached and ns.detached() then return UIParent:GetHeight() end
	local api = trackerApi()
	return api and api.ownGuideRoom and api.ownGuideRoom() / guideFactorEarly() or 0
end

local function trackerDb()
	return root.tracker and root.tracker.db
end

-- /qt Tracker settings: "Own window": the RXP Tracker leaves the quest tracker for a window of its own that you drag
-- by its bar; the quests close up, and make room again when it goes back.
local function detached()
	local tdb = trackerDb()
	return tdb and tdb.guideDetached and true or false
end
ns.detached = detached

local function trackerFolded()
	if detached() then return false end -- in its own window the quest tracker's collapse does not fold it
	local api = trackerApi()
	return api and api.ownGuideCollapsed and api.ownGuideCollapsed() or false
end

-- CONSTRAINT: stands in for the container: Blizzard's module code also reads parentContainer:IsCollapsed(), and
-- module.MarkDirty is replaced below because the proxy has no MarkDirty.
local proxy = {IsCollapsed = trackerFolded}

-- The "RestedXP Tracker scale" setting (tracker half, db.guideScale): a factor on top of the tracker's own scale.
-- The module is ours, so its width is set to the tracker's width divided by that factor: on screen it stays exactly as
-- wide as the tracker at any scale.
local function guideFactor()
	local trackerDb = root.tracker and root.tracker.db
	local value = trackerDb and tonumber(trackerDb.guideScale) or 1
	return math.min(math.max(value, 0.5), 1.5)
end

-- The window: an anchor you move by the bar along the top of the RXP Tracker. The position is saved (UIParent units,
-- top-left corner) in the tracker settings; the first time it opens to the left of the quest tracker.
local GRIP_H = 12
local window, grip
local function savePosition()
	local tdb = trackerDb()
	if tdb and window:GetLeft() then tdb.guideWindowPos = { window:GetLeft(), window:GetTop() } end
end

local function placeWindow()
	local tdb = trackerDb()
	local pos = tdb and type(tdb.guideWindowPos) == "table" and tdb.guideWindowPos
	window:ClearAllPoints()
	if pos and tonumber(pos[1]) and tonumber(pos[2]) then
		window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
	else
		local tapi = trackerApi()
		local tracker = tapi and tapi.ownTrackerFrame and tapi.ownTrackerFrame()
		local left, top = tracker and tracker:GetLeft(), tracker and tracker:GetTop()
		local width = module:GetWidth() * ns.relativeScale(module)
		if left and top then
			window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(left - width - 20, 0), top - GRIP_H)
		else
			window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
	end
end

local function buildWindow()
	window = CreateFrame("Frame", "ForeverTrackerPlusGuideWindow", UIParent)
	window:SetSize(1, 1)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	placeWindow()
	grip = CreateFrame("Button", nil, UIParent)
	grip:SetHeight(GRIP_H)
	grip:RegisterForDrag("LeftButton")
	local bg = grip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.45)
	local dots = grip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dots:SetPoint("CENTER")
	dots:SetText("RXP Tracker")
	grip.dots = dots
	grip:SetAlpha(0.35)
	grip:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("RXP Tracker", 1, 0.82, 0)
		GameTooltip:AddLine("Drag to move. /ftp > Tracker settings > Own window puts it back in the quest tracker.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function(self)
		self:SetAlpha(0.35)
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	-- The window follows the cursor through SetPoint while the button is held (as the quest tracker's drag bar does):
	-- the game's StartMoving does not move frames here in Forever.
	local dragOffset
	local function cursor()
		local s = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		return x / s, y / s
	end
	local function stopDrag()
		if not dragOffset then return end
		dragOffset = nil
		grip:SetScript("OnUpdate", nil)
		savePosition()
		placeWindow()
		ns.relocate()
	end
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		if InCombatLockdown() and module:IsProtected() then return end
		local left, top = window:GetLeft(), window:GetTop()
		if not (left and top) then return end
		local cx, cy = cursor()
		dragOffset = { left - cx, top - cy }
		grip:SetScript("OnUpdate", function()
			if not IsMouseButtonDown("LeftButton") or (InCombatLockdown() and module:IsProtected()) then stopDrag() return end
			local x, y = cursor()
			window:ClearAllPoints()
			window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + dragOffset[1], y + dragOffset[2])
		end)
	end)
	grip:SetScript("OnMouseUp", stopDrag)
	grip:SetScript("OnDragStop", stopDrag)
	grip:SetScript("OnHide", stopDrag)
end

-- the bar sits just above the module, as wide as it, at the module's strata
local function placeGrip(show)
	if not grip then return end
	if not show then grip:Hide() return end
	grip:ClearAllPoints()
	grip:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, 0)
	grip:SetWidth(math.max(module:GetWidth() * ns.relativeScale(module), 40))
	grip:SetFrameStrata(module:GetFrameStrata())
	grip:SetFrameLevel(module:GetFrameLevel() + 5)
	grip:SetShown(module:IsShown())
end

-- the module in our guide slot (or its own window), scaled by the guide scale on top of our frame's scale; it tells
-- our frame how tall it is
local function place()
	local host = ownHost()
	local api = trackerApi()
	local factor = guideFactor()
	local own = detached()
	if own then
		if not window then buildWindow() end
		if module:GetParent() ~= UIParent then module:SetParent(UIParent) end
		local ourFrame = api.ownTrackerFrame and api.ownTrackerFrame()
		local scale = (ourFrame and ourFrame.inner and ns.relativeScale(ourFrame.inner) or 1) * factor
		if math.abs(module:GetScale() - scale) > 1e-4 then module:SetScale(scale) end
		module:ClearAllPoints()
		module:SetPoint("TOPLEFT", window, "TOPLEFT", module.leftMargin or 0, 0)
		if api.ownSetGuideHeight then api.ownSetGuideHeight(0) end
	else
		if module:GetParent() ~= host then module:SetParent(host) end
		if math.abs(module:GetScale() - factor) > 1e-4 then module:SetScale(factor) end
		module:ClearAllPoints()
		module:SetPoint("TOPLEFT", host, "TOPLEFT", module.leftMargin or 0, 0)
		local h = module:IsShown() and (module:GetContentsHeight() or 0) * factor or 0
		if api.ownSetGuideHeight then api.ownSetGuideHeight(h) end
	end
	local width = (host:GetWidth() or 0) / factor
	if width > 0 and math.abs(module:GetWidth() - width) > 0.5 and not ns.protectedInCombat(module) then
		module:SetWidth(width)
		ns.relayout() -- the rows are laid out from the module's width
	end
	-- 3.2 (user: "Are you sure you didn't miss anything?"): "RXP Tracker opacity" (db.guideAlpha). In our frame the
	-- general opacity is already on the frame; in its own window (on UIParent) the guide needs both
	if api.guideTrackerAlpha then
		local both = api.guideTrackerAlpha()
		local general = api.trackerAlpha and api.trackerAlpha() or 1
		local a = own and both or (general > 0 and both / general or 1)
		if math.abs(module:GetAlpha() - a) > 1e-3 then module:SetAlpha(a) end
	end
	placeGrip(own)
end

-- CONSTRAINT: a protected frame anchored to the module (another add-on's frame after ours) makes it wait in combat.
local function locked()
	return ns.protectedInCombat(module)
end

local function layoutModule()
	if locked() then return true end
	grantedLast, foldedLast = grantedHeight(), trackerFolded()
	module:Update(grantedLast, false)
	place()
	ns.bindLive()
	ns.sync()
	return true
end

local function createModule()
	module = CreateFrame("Frame", nil, UIParent, "ObjectiveTrackerModuleTemplate")
	module.parentContainer = proxy
	module.MarkDirty = ns.relayout
	ns.attachRows(module, entries)
	ns.buildHeaders(module)
	-- the wheel anywhere over the guide scrolls its upcoming steps, never the camera (Rows.lua ns.guideWheel)
	module:EnableMouseWheel(true)
	module:SetScript("OnMouseWheel", function(_, delta) if ns.guideWheel then ns.guideWheel(nil, delta) end end)
	-- CONSTRAINT: slot movers: our placement and RestedXP (reorders its target buttons).
	hooksecurefunc(module, "SetPoint", ns.relocate)
	ns.hookRxp(ns.rxp.targeting, "UpdateTargetFrame", ns.invalidate, "RXP.targeting.UpdateTargetFrame")
	module:HookScript("OnShow", ns.relocate)
	module:HookScript("OnHide", ns.relocate)
end

-- CONSTRAINT: paused, the module hides out of combat only: the circles on its rows are secure buttons that ns.sync
-- cannot hide in combat, so rows and circles leave together once it ends (ns.relayout).
local function draw()
	local tapi = trackerApi()
	-- our frame changed size, scale or collapse: it asks the guide to lay itself out again (set here: the tracker
	-- half loads after this file)
	if tapi and not tapi.ownGuideChanged then tapi.ownGuideChanged = function() ns.relayout() end end
	-- paused only without our frame yet. It shows in battlegrounds and arenas too (user, 2026-11-26): it lives in our
	-- frame and lays out only our frames, never Blizzard's scenario section, where the secret-aura error came from.
	-- If that error returns there, pause it with tapi.trackerSecretWorld().
	local held = not ownHost()
	if held ~= paused then
		paused = held
		ns.pauseChanged()
	end
	ns.updateIndicator(paused)
	if paused then
		ns.setWantedUnits(nil)
		if module and not InCombatLockdown() then
			module:Hide()
			ns.sync()
		end
		if tapi and tapi.ownSetGuideHeight then tapi.ownSetGuideHeight(0) end
		return true
	end
	ns.setWantedUnits(snapshot and snapshot.entries)
	if not module then createModule() end
	if not module:IsShown() and not InCombatLockdown() then module:Show() end
	ns.updateHeaders(snapshot)
	return layoutModule()
end

-- /qt Tracker settings: Own window on or off (out of combat: the module may hold secure step buttons)
function ns.setDetached(on)
	local tdb = trackerDb()
	if not tdb then return false end
	on = on and true or false
	if (tdb.guideDetached and true or false) == on then return true end
	if InCombatLockdown() then
		ns.say("the RXP Tracker can move to or from its own window after combat.")
		return false
	end
	tdb.guideDetached = on
	if module then
		if on then
			if window then placeWindow() end
		else
			if grip then grip:Hide() end
		end
	end
	ns.relayout()
	return true
end

function ns.resetWindowPosition()
	local tdb = trackerDb()
	if tdb then tdb.guideWindowPos = nil end
	if window and module then placeWindow(); ns.relocate() end
end

function ns.drawn()
	return snapshot
end

function ns.render(snap)
	snapshot = snap
	return draw()
end
