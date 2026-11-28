-- ForeverTrackerPlus: our own tracker, phase 3 (OWN_TRACKER_PLAN.md): what you can do with a quest row.
--
--   clicks    a hover button over each title and objective line (pooled). Left: open the quest in the quest log.
--             Shift+left: stop tracking it. Ctrl+left: find a group (when that setting is on). Right: the quest menu
--             (Focus, Open in quest log, Share). Ctrl+right: link the rewards in chat. The same handler as More quests
--             (QuestClicks.lua api.questClick).
--   tooltip   the quest tooltip of the tracked quests (Extras.lua api.showQuestTooltip: overview, objectives, rewards,
--             party); an objective line also shows the 3D model of what it names (NpcPanel.lua).
--   items     the quest's item button (GetQuestLogSpecialItemInfo), left of the objectives (or right of the list with
--             "Quest items on the left" off, db.itemsLeft).
--
-- CONSTRAINT: an item button is secure (SecureActionButtonTemplate, type "item"). In combat it cannot be made, moved,
-- shown or hidden, and a frame it is anchored to cannot move either. So the buttons sit on UIParent at a place worked
-- out from the title (our list stays free to scroll in combat). In combat a button whose title moved goes to opacity 0
-- (SetAlpha is allowed) and is placed again when the fight ends. A button whose title is scrolled out of view hides.
--
-- RULE (tests/own_tracker_rules_test.lua): nothing here touches Blizzard's tracker.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------------------------------------------------
-- Clicks and tooltips
local clickers, clickUsed = {}, 0

local function onClick(self, button)
	local id = self.questID
	if not id then return end
	if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
		-- as on Blizzard's tracker: Shift-click stops tracking the quest
		if C_QuestLog.RemoveQuestWatch then pcall(C_QuestLog.RemoveQuestWatch, id) end
		return
	end
	if api.questClick then api.questClick(self, button) end
end
api.ownRowClick = onClick -- for tests

local function onEnter(self)
	if self.fs and not self.objective and api.animHover then api.animHover(self, self.fs, true) end
	if not (api.showQuestTooltip and api.showQuestTooltip(self, self.questID, self.title)) then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.title or "", 1, 1, 1, 1, true)
		GameTooltip:AddLine("Click: open in the quest log. Shift-click: stop tracking. Right-click: its menu.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end
	if self.objective and api.npcLineHover then pcall(api.npcLineHover, self, self.questID, self.objective) end
end
local function onLeave(self)
	if self.fs and api.animHover then api.animHover(self, self.fs, false) end
	if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	if api.hideNpcPanel then pcall(api.hideNpcPanel, self) end
end

-- a hover button over fs (a title or an objective line) for questID
function api.ownClicker(parent, fs, questID, title, objective)
	clickUsed = clickUsed + 1
	local b = clickers[clickUsed]
	if not b then
		b = CreateFrame("Button", nil, parent)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", onClick)
		-- the quest the right-click menu is for (QuestMenu.lua reads it)
		b:SetScript("OnMouseDown", function(self)
			local map = _G.WorldMapFrame
			api.lastQuestPressed = { id = self.questID, at = GetTime(), mapOpen = map and map:IsShown() or false }
		end)
		b:SetScript("OnEnter", onEnter)
		b:SetScript("OnLeave", onLeave)
		clickers[clickUsed] = b
	end
	b.questID, b.title, b.objective, b.fs = questID, title or fs:GetText(), objective, fs
	if b.qtsHover then b.qtsHover:SetAlpha(0) end
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", fs, "TOPLEFT")
	b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT")
	b:Show()
	return b
end
function api.ownClickersReset() clickUsed = 0 end
function api.ownClickersDone() for i = clickUsed + 1, #clickers do clickers[i]:Hide() end end
api.ownClickersForTests = function() return clickers, clickUsed end

---------------------------------------------------------------------------------------------------------------------
-- Quest item buttons
local ITEM_SIZE = 26 * 0.875 -- the game's quest item button, 12.5 % smaller (as Extras and More quests)
local buttons, places, dirty = {}, {}, false
local list, viewport -- our scroll child's frame and the scroll frame (set by Frame.lua)

function api.ownItemFor(questID)
	if api.questItemFor then return api.questItemFor(questID) end
	return nil
end

local function itemButton(i)
	local b = buttons[i]
	if b then return b end
	b = CreateFrame("Button", "ForeverTrackerPlusOwnItem" .. i, UIParent, "SecureActionButtonTemplate")
	b:SetSize(ITEM_SIZE, ITEM_SIZE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "item")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if api.themeKit then api.themeKit.border(b, { 0.55, 0.43, 0.18 }, 1, "OVERLAY") end
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.count:SetPoint("BOTTOMRIGHT", -1, 1)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	-- 3.2 (user): a sparkle when a real cooldown (not the global one) ends (Animations.lua)
	b.cd:HookScript("OnCooldownDone", function()
		if (b.qtsCdLength or 0) > 2 and api.animSparkle then api.animSparkle(b) end
	end)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.9, 0.6, 0.15)
	b:SetScript("OnEnter", function(self)
		if not self.link or self:GetAlpha() == 0 then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
	b:Hide()
	buttons[i] = b
	return b
end

local function updateCooldowns()
	local getCd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
	for _, b in ipairs(buttons) do
		if b:IsShown() and b.itemID then
			if getCd then
				local ok, start, duration, enable = pcall(getCd, b.itemID)
				if ok and start and duration and not isSecret(duration) and duration > 0 and enable ~= 0 and enable ~= false then
					b.cd:SetCooldown(start, duration)
					b.qtsCdLength = duration
				elseif b.cd.Clear then
					b.cd:Clear()
				end
			end
			local ok, n = false, nil
			if getCount then ok, n = pcall(getCount, b.itemID) end
			b.count:SetText(ok and type(n) == "number" and not isSecret(n) and n > 1 and tostring(n) or "")
		end
	end
end
api.ownItemCooldowns = updateCooldowns

-- where a quest's button goes (user): left of the line it belongs to (p.anchor: the title when nothing is drawn left of
-- it, else the first objective line), its middle on that line's first text line. Right of the list (TOPLEFT) with
-- the "right" side. No anchor (no line drawn): under the title's left, as before.
local function spot(p)
	local fs = p.fs
	if api.itemSide and api.itemSide() == "right" then
		local right, top = viewport and viewport:GetRight(), fs:GetTop()
		if right and top then return "TOPLEFT", right + 4, top end
		return nil
	end
	local a = p.anchor
	if a and a.IsVisible and a:IsVisible() then
		local left, top = a:GetLeft(), a:GetTop()
		local _, size = a:GetFont()
		size = type(size) == "number" and size > 0 and size or 12
		if left and top then return "RIGHT", left - 4, top - size / 2 end
	end
	local left, bottom = fs:GetLeft(), fs:GetBottom()
	if left and bottom then return "TOPRIGHT", left - 4, bottom - 1 end
end
local function anchorOf(p) return p.anchor or p.fs end

local function place()
	local shown = list and list:IsVisible()
	if inCombat() then
		dirty = true
		for _, b in ipairs(buttons) do
			if b:IsShown() then
				local fs = b.placedFs
				local moved = not shown or not fs or not fs:IsVisible() or fs:GetTop() ~= b.placedTop
					or fs:GetLeft() ~= b.placedLeft
				b:SetAlpha(moved and 0 or (list:GetEffectiveAlpha() or 1))
			end
		end
		return
	end
	dirty = false
	local s = list and list:GetEffectiveScale() or 1
	local vTop, vBottom
	if viewport and viewport:GetTop() then
		local vs = viewport:GetEffectiveScale()
		vTop, vBottom = viewport:GetTop() * vs, viewport:GetBottom() * vs
	end
	for i = 1, math.max(#places, #buttons) do
		local p = shown and places[i] or nil
		local point, x, y
		if p and p.fs:IsVisible() then point, x, y = spot(p) end
		if point and vTop then
			local mid = (point == "RIGHT" and y or y - ITEM_SIZE / 2) * s
			if mid > vTop or mid < vBottom then point = nil end -- scrolled out of view
		end
		if point then
			local b = itemButton(i)
			if b.itemID ~= p.item.itemID then
				b:SetAttribute("item", "item:" .. p.item.itemID)
				b.icon:SetTexture(p.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				b.itemID = p.item.itemID
			end
			b.link = p.item.link
			local scale = s / UIParent:GetEffectiveScale()
			if math.abs(b:GetScale() - scale) > 1e-4 then b:SetScale(scale) end
			b:ClearAllPoints()
			b:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
			local top = list:GetParent() and list:GetParent():GetParent() or list
			b:SetFrameStrata(top:GetFrameStrata())
			b:SetFrameLevel(top:GetFrameLevel() + 20)
			b:SetAlpha(list:GetEffectiveAlpha() or 1)
			local a = anchorOf(p)
			b.placedFs, b.placedTop, b.placedLeft = a, a:GetTop(), a:GetLeft()
			b:Show()
		elseif buttons[i] then
			local b = buttons[i]
			b.placedFs, b.placedTop, b.placedLeft = nil, nil, nil
			if b:IsShown() then b:Hide() end
		end
	end
	updateCooldowns()
end
api.ownPlaceItems = place

-- Frame.lua: the list starts again (places cleared), then each title with an item is added
function api.ownItemsReset(listFrame, scrollFrame)
	list, viewport = listFrame, scrollFrame
	for k in pairs(places) do places[k] = nil end
end
-- Frame.lua sets the place's anchor (the title, or the first objective line when icons are left of the title)
function api.ownItemAdd(fs, item)
	local p = { fs = fs, item = item }
	places[#places + 1] = p
	return p
end
api.ownItemPlacesForTests = function() return places, buttons end

-- the first title moved (a scroll, a new layout, the quest titles slider: user, the buttons stayed when the titles
-- moved left): placed again. Also when the list is hidden or shown: a collapsed Quests header (user: the buttons
-- stayed) hides the list, but a hidden title keeps its place, so its top does not change
local lastTop, lastLeft, lastShown
local watch = CreateFrame("Frame")
watch:SetScript("OnUpdate", function()
	local p = places[1]
	-- (performance) this runs each frame: no item buttons and nothing placed before, so nothing to do
	if not p and lastTop == nil and lastLeft == nil then return end
	local a = p and anchorOf(p)
	local top = a and a:GetTop() or nil
	local left = a and a:GetLeft() or nil
	local shown = list and list:IsVisible() and true or false
	if top ~= lastTop or left ~= lastLeft or shown ~= lastShown then
		lastTop, lastLeft, lastShown = top, left, shown
		place()
	end
end)
watch:RegisterEvent("PLAYER_REGEN_ENABLED")
watch:RegisterEvent("BAG_UPDATE_COOLDOWN")
watch:RegisterEvent("BAG_UPDATE_DELAYED")
watch:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if dirty then place() end
	else
		updateCooldowns()
	end
end)
