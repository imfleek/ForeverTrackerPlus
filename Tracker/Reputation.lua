-- R106-74: the tracked (watched) reputation at the top of the quest list, and the game's reputation bar hidden while
-- it is shown there (user). Quest list > "Tracked reputation at the top" (db.repTrack, on by default).
--
-- The row: the faction's name and its standing, and under them a progress bar (the objectives' bar, Extras.lua) with
-- the points in this standing. It sits in our tracker's top slot (Own/Frame.lua, under its "Reputation" header).
-- Clicking it opens the reputation window.
--
-- CONSTRAINT: the game's bar is only made see-through and deaf to the mouse (alpha 0, EnableMouse false), never hidden
-- or moved: the status bars sit in Blizzard's own layout (StatusTrackingBarManager in Retail-style clients,
-- ReputationWatchBar in Classic-style ones), and hiding them from an addon fights that layout.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function num(v) return type(v) == "number" and not isSecret(v) and v or nil end
local function str(v) return type(v) == "string" and not isSecret(v) and v ~= "" and v or nil end

local function enabled() return db and db.repTrack ~= false end

-- the watched faction: name, standing label, reaction (1 hated .. 8 exalted), points in this standing and its size;
-- nil when none is watched
local function watched()
	local name, reaction, low, high, value, id
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		local ok, d = pcall(C_Reputation.GetWatchedFactionData)
		if ok and type(d) == "table" then
			name, reaction, id = str(d.name), num(d.reaction), num(d.factionID)
			low, high, value = num(d.currentReactionThreshold), num(d.nextReactionThreshold), num(d.currentStanding)
		end
	end
	if not name and GetWatchedFactionInfo then
		local ok, n, r, mn, mx, v, fid = pcall(GetWatchedFactionInfo)
		if ok then name, reaction, low, high, value, id = str(n), num(r), num(mn), num(mx), num(v), num(fid) end
	end
	if not name then return nil end
	local label = reaction and str(_G["FACTION_STANDING_LABEL" .. reaction]) or nil
	if reaction and GetText then -- the gendered form where the language has one
		local ok, text = pcall(GetText, "FACTION_STANDING_LABEL" .. reaction, UnitSex and UnitSex("player"))
		if ok and str(text) then label = text end
	end
	local paragon = false
	-- friendships (their own ranks) and paragon (points past exalted), where the client has them
	if id and C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
		local ok, f = pcall(C_GossipInfo.GetFriendshipReputation, id)
		if ok and type(f) == "table" and num(f.friendshipFactionID) and f.friendshipFactionID > 0 then
			label = str(f.reaction) or label
			low, value = num(f.reactionThreshold) or low, num(f.standing) or value
			high = num(f.nextThreshold) or value
		end
	end
	if id and C_Reputation and C_Reputation.IsFactionParagon and C_Reputation.GetFactionParagonInfo then
		local okP, isP = pcall(C_Reputation.IsFactionParagon, id)
		if okP and isP then
			local ok, cur, threshold = pcall(C_Reputation.GetFactionParagonInfo, id)
			cur, threshold = ok and num(cur), ok and num(threshold)
			if cur and threshold and threshold > 0 then
				low, value, high, paragon = 0, cur % threshold, threshold, true
			end
		end
	end
	local have, need = 0, 0
	if low and high and value then have, need = value - low, high - low end
	return { name = name, label = label or "", reaction = reaction or 4, have = have, need = need, paragon = paragon,
		value = value }
end
api.watchedReputation = watched

-- the game's reputation bar ---------------------------------------------------------------------------------------
local function isRepBar(bar)
	local mixin = _G.ReputationStatusBarMixin
	return type(bar) == "table" and mixin ~= nil and bar.Update ~= nil and bar.Update == mixin.Update
end

-- every frame to make see-through: Classic's ReputationWatchBar; in Retail-style clients the reputation bar, and its
-- whole container while the reputation bar is the only bar shown in it
local function gameRepFrames()
	local list = {}
	if _G.ReputationWatchBar then list[#list + 1] = _G.ReputationWatchBar end
	local manager = _G.StatusTrackingBarManager
	for _, container in ipairs(manager and type(manager.barContainers) == "table" and manager.barContainers or {}) do
		local rep, others = nil, false
		for _, bar in pairs(type(container.bars) == "table" and container.bars or {}) do
			if isRepBar(bar) then rep = bar
			elseif type(bar) == "table" and bar.IsShown and bar:IsShown() then others = true end
		end
		if rep then
			list[#list + 1] = rep
			if not others then list[#list + 1] = container end
		end
	end
	return list
end

local hidden = {}  -- [frame] = true while we keep it see-through
local hooked = {}
local busy = false
local function keepHidden(frame)
	if busy or not hidden[frame] then return end
	busy = true
	pcall(frame.SetAlpha, frame, 0)
	busy = false
end
local function hideGameBar(on)
	local now = {}
	if on then
		for _, f in ipairs(gameRepFrames()) do now[f] = true end
	end
	for f in pairs(hidden) do
		if not now[f] then
			hidden[f] = nil
			busy = true
			pcall(f.SetAlpha, f, 1)
			if f.EnableMouse and not InCombatLockdown() then pcall(f.EnableMouse, f, true) end
			busy = false
		end
	end
	for f in pairs(now) do
		hidden[f] = true
		if not hooked[f] then
			hooked[f] = true
			hooksecurefunc(f, "SetAlpha", keepHidden)
			if f.Show then hooksecurefunc(f, "Show", keepHidden) end
		end
		keepHidden(f)
		if f.EnableMouse and not InCombatLockdown() then pcall(f.EnableMouse, f, false) end
	end
end

-- the row -----------------------------------------------------------------------------------------------------------
local row, bar, nameText, standingText
local function createRow()
	row = CreateFrame("Frame", "ForeverTrackerPlusReputation", UIParent)
	row:EnableMouse(true)
	row:SetScript("OnMouseUp", function()
		if InCombatLockdown() then return end
		if ToggleCharacter then pcall(ToggleCharacter, "ReputationFrame") end
	end)
	row:SetScript("OnEnter", function(self)
		local w = watched()
		if not w then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(w.name, 1, 1, 1)
		GameTooltip:AddLine(w.label .. (w.need > 0 and ("  %d / %d"):format(w.have, w.need) or ""), 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Click: the reputation window", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	nameText = row:CreateFontString(nil, "OVERLAY")
	nameText:SetJustifyH("LEFT")
	nameText:SetWordWrap(false)
	standingText = row:CreateFontString(nil, "OVERLAY")
	standingText:SetJustifyH("RIGHT")
	for _, fs in ipairs({ nameText, standingText }) do
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 1)
	end
	bar = api.newProgressBar and api.newProgressBar(row)
end

local function fontOf(objectName, fallbackSize)
	local object = _G[objectName]
	if object and object.GetFont then
		local file, size, flags = object:GetFont()
		if file and size then return file, size, flags end
	end
	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fallbackSize, ""
end

local GAP = 3     -- between the name line and the bar
local BOTTOM = 8  -- under the bar, before the quests
local function rowHeight()
	local _, hSize = fontOf("ObjectiveTrackerHeaderFont", 14)
	local _, lSize = fontOf("ObjectiveTrackerLineFont", 12)
	local barH = api.progressBarSize and select(2, api.progressBarSize(lSize)) or (lSize + 3)
	return math.ceil(hSize + GAP + barH + BOTTOM), hSize, lSize, barH
end

-- the texts and the bar from the watched faction (no layout: also safe in combat)
local lastRep -- 3.2: the faction and points shown last (the gain float)
local function fill(w)
	if not row or not w then return end
	local hFile, hSize, hFlags = fontOf("ObjectiveTrackerHeaderFont", 14)
	local lFile, lSize, lFlags = fontOf("ObjectiveTrackerLineFont", 12)
	nameText:SetFont(hFile, hSize, hFlags)
	standingText:SetFont(lFile, lSize, lFlags)
	nameText:SetText(w.name)
	nameText:SetTextColor(1, 0.82, 0)
	standingText:SetText(w.label)
	local c = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[w.reaction]
	if c then standingText:SetTextColor(c.r, c.g, c.b) else standingText:SetTextColor(0.8, 0.8, 0.8) end
	if bar and api.drawProgressBar then
		local width = row:GetWidth() or 200
		local _, _, _, barH = rowHeight()
		local have, need = w.have, w.need
		if need <= 0 then have, need = 1, 1 end -- the last standing: a full bar
		-- the fill in the standing's colour: red while hostile, yellow neutral, green friendly and up, blue past exalted
		local colour = w.paragon and "Blue" or (w.reaction <= 3 and "Red") or (w.reaction == 4 and "Yellow") or "Green"
		local file = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\BarFill" .. colour
		api.drawProgressBar(bar, nameText, 0, lFile, lSize, lFlags, have, need, "BOTTOMLEFT", width, barH, -GAP, "TOPLEFT",
			file)
		bar.text:SetText(w.need > 0 and ("%d / %d"):format(w.have, w.need) or w.label)
		-- 3.2 (user): points gained on the same faction: "+250" rises from the bar (Animations.lua animFloat)
		local last = lastRep
		if last and last.name == w.name and type(w.value) == "number" and type(last.value) == "number"
			and w.value > last.value and api.animFloat then
			api.animFloat(row, bar.text, ("+%d"):format(w.value - last.value))
		end
		lastRep = { name = w.name, value = w.value }
	end
end

local shownFor -- the faction the row was laid out for (a change of shown / not shown lays the tracker out again)

-- Own/Frame.lua: the row's place in our top slot. anchor: the slot, base: the room above it in the slot (UIParent units),
-- alpha: the opacity. Returns the room it takes (UIParent units).
function api.layoutTrackedReputation(anchor, base, alpha)
	local w = enabled() and watched() or nil
	hideGameBar(w ~= nil)
	shownFor = w and w.name or false
	if not w or not anchor or not (anchor.IsShown and anchor:IsShown()) then
		if row then row:Hide() end
		return 0
	end
	if not row then createRow() end
	-- our tracker's top slot (Own/Frame.lua api.ownCardHost)
	local module = anchor
	local ui = UIParent:GetEffectiveScale()
	local s = (module and module.GetEffectiveScale and module:GetEffectiveScale() or anchor:GetEffectiveScale()) / ui
	local width = module and module.GetWidth and module:GetWidth() or (anchor:GetWidth() * anchor:GetEffectiveScale() / ui / s)
	local mLeft, aLeft = module and module.GetLeft and module:GetLeft(), anchor:GetLeft()
	local dx = (mLeft and aLeft) and ((mLeft * module:GetEffectiveScale() - aLeft * anchor:GetEffectiveScale()) / ui) or 0
	local h = rowHeight()
	row:SetScale(s)
	row:SetFrameStrata(anchor:GetFrameStrata())
	row:SetFrameLevel(anchor:GetFrameLevel() + 5)
	row:SetAlpha(alpha or 1)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", anchor, "TOPLEFT", dx / s, -base / s)
	row:SetSize(width, h)
	-- the standing at the right, level with the bottom of the name; the name up to it
	local _, hSize, lSize = rowHeight()
	standingText:ClearAllPoints()
	standingText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -math.max(hSize - lSize, 0))
	nameText:ClearAllPoints()
	nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	nameText:SetPoint("RIGHT", standingText, "LEFT", -6, 0)
	row:Show()
	fill(w)
	return h * s
end

-- our own tracker: whether the row would show (its "Reputation" header shows with it, also while folded away)
function api.trackedReputationShown() return enabled() and watched() ~= nil end

function api.setRepTrack(on)
	db.repTrack = on and true or false
	if not db.repTrack then hideGameBar(false) end
	if api.applyLayout then api.applyLayout() end
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local frame = CreateFrame("Frame")
	for _, e in ipairs({ "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do pcall(frame.RegisterEvent, frame, e) end
	frame:SetScript("OnEvent", function()
		local w = enabled() and watched() or nil
		if (w and w.name or false) ~= shownFor then
			-- a faction watched or unwatched: the strip's height changes
			if api.applyLayout then api.applyLayout() end
		else
			fill(w)
			hideGameBar(w ~= nil)
		end
	end)
	-- the game's bars laid out again: the reputation bar (or its container) see-through again if need be
	local manager = _G.StatusTrackingBarManager
	if manager and type(manager.UpdateBarsShown) == "function" then
		hooksecurefunc(manager, "UpdateBarsShown", function() if shownFor then hideGameBar(true) end end)
	end
end
