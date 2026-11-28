-- ForeverTrackerPlus 3.2 (user): the big quest item button. When the closest tracked quest with a quest item is
-- near (you stand where the item is used), one large button with that item shows at the bottom middle of the screen,
-- in the Forever look (dark brown frame, gold edge, gold light to each side). Ctrl+right-drag moves it.
--
--   which quest  the tracked quests (api.ownQuestIDs) that are not complete and have an item (api.questItemFor);
--                the closest of them by api.questDirection (Questie's spawns, the quest's map marker, the game's own
--                distance). Shown while it is within db.questActionRange yards (default 100). Not on a flight path,
--                not inside an instance (no map position there).
--   settings     Helpers > On screen > Quest items: db.questAction (on), db.questActionRange, db.questActionPos.
--   key          Key Bindings > AddOns: "Use the nearby quest item" (Bindings.xml).
--
-- CONSTRAINT: the button is secure (SecureActionButtonTemplate, type "item"): it cannot be shown, hidden, moved or
-- changed in combat. In combat a button that is no longer wanted goes to opacity 0, and every change waits for
-- PLAYER_REGEN_ENABLED. Ctrl+right-click is "rxpftnone" (no type), so a move never uses the item.
-- PERFORMANCE: the quest list is read again only after a quest log or watch change; a timer (0.5 s) only measures
-- the distance to those quests, and does nothing when none has an item.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api
local db

local SIZE = 46
local NAME = "ForeverTrackerPlusQuestAction"
local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local GOLD = { 0.788, 0.635, 0.29 }
local GOLD_LIGHT = { 1, 0.8, 0.38 }
local DARK = { 0.086, 0.071, 0.055 }
local EDGE = { 0.29, 0.243, 0.184 }

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function on() return db and db.questAction ~= false end
local function range()
	local r = tonumber(db and db.questActionRange) or 100
	return math.min(math.max(r, 30), 300)
end
api.questActionRange = range

local button
local pending = false
local candidates, dirty = {}, true

---------------------------------------------------------------------------------------------------------------------
-- The look
local function solid(parent, layer, c, a, sub)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetColorTexture(c[1], c[2], c[3], a or 1)
	return t
end
-- a thin gold line that fades out away from the button (side: "LEFT" or "RIGHT")
local function streak(b, side, y)
	local t = b:CreateTexture(nil, "BACKGROUND", nil, 2)
	t:SetSize(110, 1.5)
	if side == "LEFT" then t:SetPoint("RIGHT", b, "LEFT", 2, y) else t:SetPoint("LEFT", b, "RIGHT", -2, y) end
	t:SetColorTexture(1, 1, 1, 1)
	local strong, faint = CreateColor and CreateColor(GOLD_LIGHT[1], GOLD_LIGHT[2], GOLD_LIGHT[3], 0.9),
		CreateColor and CreateColor(GOLD[1], GOLD[2], GOLD[3], 0)
	local ok = strong and t.SetGradient and pcall(t.SetGradient, t, "HORIZONTAL",
		side == "LEFT" and faint or strong, side == "LEFT" and strong or faint)
	if not ok then t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5) end
	return t
end
-- the light to one side, like wings (our own glow texture, stretched and added)
local function wing(b, side)
	local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	t:SetTexture(TEX .. "MarkerGlow")
	t:SetBlendMode("ADD")
	t:SetVertexColor(GOLD_LIGHT[1], GOLD_LIGHT[2], GOLD_LIGHT[3], 0.8)
	t:SetSize(120, 36)
	if side == "LEFT" then t:SetPoint("RIGHT", b, "CENTER", -8, 0) else t:SetPoint("LEFT", b, "CENTER", 8, 0) end
	return t
end

local function savePos()
	if not button then return end
	local p, _, rp, x, y = button:GetPoint(1)
	if not p then return end
	db.questActionPos = { p, rp, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
end
local function placeButton()
	button:ClearAllPoints()
	local pos = type(db.questActionPos) == "table" and db.questActionPos
	if pos and pos[1] then button:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
	else button:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 290) end
end

local function build()
	if button then return button end
	local b = CreateFrame("Button", NAME, UIParent, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetMovable(true)
	b:SetClampedToScreen(true)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "item")
	b:SetAttribute("ctrl-type2", "rxpftnone") -- Ctrl+right: move, never use the item
	-- the light behind: a soft glow (pulses, Animations.lua), the two wings and two thin gold lines each side
	b.flare = b:CreateTexture(nil, "BACKGROUND", nil, 0)
	b.flare:SetTexture(TEX .. "MarkerGlow")
	b.flare:SetBlendMode("ADD")
	b.flare:SetVertexColor(GOLD_LIGHT[1], GOLD_LIGHT[2], GOLD_LIGHT[3], 1)
	b.flare:SetPoint("CENTER")
	b.flare:SetSize(SIZE * 2.2, SIZE * 2.2)
	b.wings = { wing(b, "LEFT"), wing(b, "RIGHT") }
	b.streaks = { streak(b, "LEFT", 5), streak(b, "LEFT", -5), streak(b, "RIGHT", 5), streak(b, "RIGHT", -5) }
	-- the frame: dark brown, a gold edge, a thin dark line inside it
	b.back = solid(b, "BORDER", DARK, 1)
	b.back:SetPoint("TOPLEFT", -4, 4); b.back:SetPoint("BOTTOMRIGHT", 4, -4)
	b.edges = {}
	-- the edge around the dark back: 2 px gold, then a 1 px dark line inside at the top and bottom
	local function edge(p1, rel1, x1, y1, p2, rel2, x2, y2, c, a)
		local t = solid(b, "BORDER", c, a or 1, 2)
		t:SetPoint(p1, b.back, rel1, x1, y1)
		t:SetPoint(p2, b.back, rel2, x2, y2)
		b.edges[#b.edges + 1] = t
		return t
	end
	edge("TOPLEFT", "TOPLEFT", -2, 2, "BOTTOMRIGHT", "TOPRIGHT", 2, 0, GOLD)
	edge("TOPLEFT", "BOTTOMLEFT", -2, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 2, -2, GOLD)
	edge("TOPLEFT", "TOPLEFT", -2, 0, "BOTTOMRIGHT", "BOTTOMLEFT", 0, 0, GOLD)
	edge("TOPLEFT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 2, 0, GOLD)
	edge("TOPLEFT", "TOPLEFT", 3, -3, "BOTTOMRIGHT", "TOPRIGHT", -3, -4, EDGE)
	edge("TOPLEFT", "BOTTOMLEFT", 3, 4, "BOTTOMRIGHT", "BOTTOMRIGHT", -3, 3, EDGE)
	-- a small gold diamond on the top and bottom edge (our MarkerDiamond)
	for i, side in ipairs({ "TOP", "BOTTOM" }) do
		local d = b:CreateTexture(nil, "OVERLAY", nil, 2)
		d:SetTexture(TEX .. "MarkerDiamond")
		d:SetVertexColor(GOLD_LIGHT[1], GOLD_LIGHT[2], GOLD_LIGHT[3], 1)
		d:SetSize(10, 10)
		d:SetPoint("CENTER", b.back, side, 0, i == 1 and 1 or -1)
		b["gem" .. side] = d
	end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("TOPLEFT", 2, -2)
	b.count:SetTextColor(0.953, 0.875, 0.659)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.9, 0.6, 0.18)
	b:RegisterForDrag("RightButton")
	b:SetScript("OnDragStart", function(self)
		if IsControlKeyDown and IsControlKeyDown() and not inCombat() then self:StartMoving() self.moving = true end
	end)
	b:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving = nil
		self:StopMovingOrSizing()
		savePos()
	end)
	b:SetScript("OnEnter", function(self)
		if self:GetAlpha() == 0 then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if self.link then pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) else GameTooltip:SetText("Quest item button") end
		if self.title then GameTooltip:AddLine(self.title, 1, 0.82, 0) end
		GameTooltip:AddLine("Ctrl+right-drag: move this button", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
	b:Hide()
	button = b
	placeButton()
	return b
end

local function updateCount()
	if not (button and button:IsShown() and button.itemID) then return end
	local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
	local ok, n = false, nil
	if getCount then ok, n = pcall(getCount, button.itemID) end
	n = ok and tonumber(n) or 0
	button.count:SetText(n > 0 and tostring(n) or "")
	local getCd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	if getCd then
		local okCd, start, duration, enable = pcall(getCd, button.itemID)
		if okCd and type(start) == "number" and type(duration) == "number" and duration > 0 and enable ~= 0 and enable ~= false then
			button.cd:SetCooldown(start, duration)
		elseif button.cd.Clear then
			button.cd:Clear()
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Which quest
local function readCandidates()
	for k in pairs(candidates) do candidates[k] = nil end
	dirty = false
	for _, id in ipairs(api.ownQuestIDs and api.ownQuestIDs() or {}) do
		local complete = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
		local item = not complete and api.questItemFor and api.questItemFor(id)
		if item then
			local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
			candidates[#candidates + 1] = { id = id, item = item, title = type(title) == "string" and title or nil }
		end
	end
end

-- the closest tracked quest with an item, when you stand within range of where it is done; nil else
local function pick()
	if not on() then return nil end
	if dirty then readCandidates() end
	if #candidates == 0 then return nil end
	if UnitOnTaxi and UnitOnTaxi("player") then return nil end
	local me = api.playerWorldPos and api.playerWorldPos()
	if not (me and api.questDirection) then return nil end
	local best, bestD
	for _, c in ipairs(candidates) do
		local ok, d = pcall(api.questDirection, c.id, me)
		if ok and type(d) == "number" and (not bestD or d < bestD) then best, bestD = c, d end
	end
	if best and bestD <= range() then return best, bestD end
	return nil, bestD
end
api.questActionPick = pick

local preview = false
local function apply(c)
	if inCombat() then
		pending = true
		if button and button:IsShown() then
			button:SetAlpha(c and button.itemID == c.item.itemID and 1 or 0)
		end
		return
	end
	pending = false
	if not c then
		if button and button:IsShown() then
			button:Hide()
			if api.animQuestAction then api.animQuestAction(button.flare, false) end
		end
		return
	end
	build()
	if button.itemID ~= c.item.itemID then
		button:SetAttribute("item", "item:" .. c.item.itemID)
		button.icon:SetTexture(c.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		button.itemID = c.item.itemID
	end
	button.link, button.title, button.questID = c.item.link, c.title, c.id
	button:SetAlpha(1)
	if not button:IsShown() then
		button:Show()
		if api.animQuestAction then api.animQuestAction(button.flare, true) end
	end
	updateCount()
end

local function refresh()
	if preview then return end
	apply((pick()))
end
api.refreshQuestAction = refresh
function api.questActionButton() return button end -- (tests)
function api.questActionDirty() dirty = true end

-- Settings: show the button for 15 s (with a sample icon, no item) so you can move it
function api.questActionPreview()
	if inCombat() then return end
	build()
	preview = true
	button:SetAttribute("item", nil)
	button.itemID, button.link, button.title = nil, nil, "Ctrl+right-drag to move it"
	button.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
	button.count:SetText("")
	button:SetAlpha(1)
	button:Show()
	if api.animQuestAction then api.animQuestAction(button.flare, true) end
	if C_Timer and C_Timer.After then C_Timer.After(15, function() preview = false; refresh() end) end
end
function api.resetQuestAction()
	db.questActionPos = nil
	if button and not inCombat() then placeButton() end
end

---------------------------------------------------------------------------------------------------------------------
-- Events and the timer
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		dirty = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then refresh() end
	else -- BAG_UPDATE_COOLDOWN, BAG_UPDATE_DELAYED
		updateCount()
	end
end)
ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
		"BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }) do
		pcall(events.RegisterEvent, events, e)
	end
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(0.5, function()
			if not on() then
				if button and button:IsShown() and not preview then apply(nil) end
				return
			end
			if not dirty and #candidates == 0 and not (button and button:IsShown()) then return end
			local ok, err = pcall(refresh)
			if not ok and geterrorhandler then geterrorhandler()(err) end
		end)
	end
end

-- the key binding's name (Bindings.xml)
_G["BINDING_NAME_CLICK " .. NAME .. ":LeftButton"] = "Use the nearby quest item"

-- Settings > Helpers > On screen > Quest items (Questing.lua's page calls this)
function api.declareQuestActionSettings(k)
	k.check("Big quest item button", function() return db.questAction ~= false end,
		function(v) db.questAction = v and true or false; refresh() end)
	k.help("near the place your closest tracked quest's item is used, a big button with it shows at the bottom middle. "
		.. "Ctrl+right-drag to move it. Key: Key Bindings > AddOns")
	if k.slider then
		k.slider("Show it within (yards)", 30, 300, 10, "%d", function() return range() end,
			function(v) db.questActionRange = v; refresh() end, function() return db.questAction ~= false end, 24)
	end
	k.buttons("Show it to move it", {
		{ "Show it to move it", function() api.questActionPreview() end, 160 },
		{ "Reset its position", function() api.resetQuestAction() end, 160 },
	})
end
