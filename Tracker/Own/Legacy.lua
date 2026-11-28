-- ForeverTrackerPlus: our own tracker, phase 5 (OWN_TRACKER_PLAN.md): tracked Legacy Challenges.
--
-- WoW Forever has Legacy Challenges, not achievements (user), and the game has no way to track one (user: "No track
-- option. Can we add option to?"). So we keep our own list: click a challenge on the Guides > Legacy page to track
-- it (Guides.lua), and Frame.lua draws the tracked ones in their own block above the quests: the name and its open
-- steps, with counts.
--
--   store     db.legacyTracked[<name-realm>] = { id, id, ... } (per character, in the order you tracked them), at
--             most MAX. A challenge you finish leaves the list by itself.
--   data      GetAchievementInfo / GetAchievementNumCriteria / GetAchievementCriteriaInfo (a Legacy Challenge is an
--             achievement with the legacy flag underneath; Guides.lua reads them the same way).
--   clicks    left: the Guides > Legacy page. Shift+left: stop tracking. Right: a menu with both.
--
-- RULE (tests/own_tracker_rules_test.lua): nothing here touches Blizzard's tracker; reads only.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
-- 3.2: the character key with the surname (Core.lua api.playerKey); without it (tests) "Name-Realm"
local function playerKey(...)
	if ns.api.playerKey then return ns.api.playerKey(...) end
	local name, realm = UnitName and UnitName("player"), GetRealmName and GetRealmName()
	if type(name) ~= "string" or (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then return nil end
	return name .. "-" .. tostring(realm or "")
end
local api = ns.api

local MAX, MAX_LINES = 10, 6
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function who() return playerKey() or "?" end -- 3.2: with the surname
local function store()
	local db = ns.db
	if not db then return {} end
	db.legacyTracked = type(db.legacyTracked) == "table" and db.legacyTracked or {}
	local k = who()
	if type(db.legacyTracked[k]) ~= "table" then db.legacyTracked[k] = {} end
	return db.legacyTracked[k]
end
local function changed()
	if api.ownLegacyChanged then api.ownLegacyChanged() end
	if api.legacyRefreshBoxes then api.legacyRefreshBoxes() end -- the Track boxes in Blizzard's window (below)
end

function api.legacyIsTracked(id)
	for _, v in ipairs(store()) do if v == id then return true end end
	return false
end
-- on: true / false; answers false (and says why) when the list is full
function api.legacySetTracked(id, on)
	local list = store()
	for i, v in ipairs(list) do
		if v == id then
			if on then return true end
			table.remove(list, i)
			changed()
			return true
		end
	end
	if not on then return true end
	if #list >= MAX then
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(("|cff33ff99ForeverTrackerPlus|r: you can track %d Legacy Challenges at once. Stop tracking one first."):format(MAX))
		end
		return false
	end
	list[#list + 1] = id
	changed()
	return true
end

local function try(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

-- { { id, name, desc, icon, have, need, lines = { { text, done } } } }; finished ones leave the list
function api.ownLegacy()
	local out = {}
	local list = store()
	local i = 1
	while i <= #list do
		local id = list[i]
		local ok, aid, name, _, done, _, _, _, desc, _, icon = try(GetAchievementInfo, id)
		if ok and aid and done then
			table.remove(list, i)
		else
			i = i + 1
			if ok and aid and type(name) == "string" and not isSecret(name) then
				local a = { id = id, name = name, desc = type(desc) == "string" and desc or nil, icon = icon,
					have = 0, need = 0, lines = {} }
				local okN, n = try(GetAchievementNumCriteria, id)
				local open = 0
				for k = 1, okN and tonumber(n) or 0 do
					local okC, cname, _, cdone, qty, req = try(GetAchievementCriteriaInfo, id, k)
					if okC then
						a.need = a.need + 1
						if cdone then
							a.have = a.have + 1
						else
							open = open + 1
							if open <= MAX_LINES then
								local text = (type(cname) == "string" and cname ~= "" and not isSecret(cname)) and cname or a.desc or "?"
								qty, req = tonumber(qty), tonumber(req)
								if req and req > 1 and qty then text = ("%d/%d %s"):format(math.min(qty, req), req, text) end
								a.lines[#a.lines + 1] = { text = text }
							end
						end
					end
				end
				if open > MAX_LINES then a.lines[#a.lines + 1] = { text = ("and %d more"):format(open - MAX_LINES), more = true } end
				if a.need == 0 and a.desc then a.lines[1] = { text = a.desc } end
				out[#out + 1] = a
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Clicks and tooltips
local function openPage()
	if api.openConfigTab then api.openConfigTab("legacy") end
end
local function onClick(self, button)
	if not self.legacyID then return end
	if button == "LeftButton" then
		if IsShiftKeyDown and IsShiftKeyDown() then api.legacySetTracked(self.legacyID, false) else openPage() end
		return
	end
	if button == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
		local id, title = self.legacyID, self.title
		MenuUtil.CreateContextMenu(self, function(_, menu)
			menu:CreateTitle(title or "")
			menu:CreateButton("Open Legacy Challenges", openPage)
			menu:CreateButton("Stop tracking", function() api.legacySetTracked(id, false) end)
		end)
	end
end
api.ownLegacyClick = onClick -- for tests
local function onEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(self.title or "", 1, 1, 1, 1, true)
	if self.desc then GameTooltip:AddLine(self.desc, 1, 0.82, 0, true) end
	if self.need and self.need > 0 then
		GameTooltip:AddLine(("%d of %d steps done."):format(self.have or 0, self.need), 0.85, 0.85, 0.85, true)
	end
	GameTooltip:AddLine("Click: open Legacy Challenges. Shift-click: stop tracking. Right-click: its menu.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end
local function onLeave(self)
	if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end

local clickers, used = {}, 0
function api.ownLegacyClicker(parent, fs, a)
	used = used + 1
	local b = clickers[used]
	if not b then
		b = CreateFrame("Button", nil, parent)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", onEnter)
		b:SetScript("OnLeave", onLeave)
		clickers[used] = b
	end
	b.legacyID, b.title, b.desc, b.have, b.need = a.id, a.name, a.desc, a.have, a.need
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", fs, "TOPLEFT")
	b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT")
	b:Show()
	return b
end
function api.ownLegacyClickersReset() used = 0 end
function api.ownLegacyClickersDone() for i = used + 1, #clickers do clickers[i]:Hide() end end

---------------------------------------------------------------------------------------------------------------------
-- 3.2 (user: "Add a checkboxes to challenges on blizzard's legacy challenges window to be able track them"): a
-- "Track" box on each open challenge card in Blizzard's Legacy Challenges window (LegacySystemFrame, from the
-- load-on-demand Blizzard_LegacySystem). Its cards use LegacyChallengeTemplateMixin; their Init sets card.id (the
-- challenge) and card.completed, as achievement buttons do. We post-hook that Init (hooksecurefunc, before any card
-- is made: the cards copy the mixin when the window first shows) and give the card our own box, a child of the card.
-- Nothing of Blizzard's is changed; Blizzard's own Tracked box (it feeds Blizzard's tracker, which ours replaces) is
-- left alone.
local cards = {}
local function refreshBox(card)
	local box = card.ftpTrack
	if not box then return end
	local id = card.id
	local open = type(id) == "number" and not isSecret(id) and not card.completed
	box:SetShown(open and true or false)
	if open then box:SetChecked(api.legacyIsTracked(id)) end
end
local function boxClick(self)
	local card = self:GetParent()
	local id = card and card.id
	if type(id) ~= "number" or isSecret(id) then return end
	local want = self:GetChecked() and true or false
	if not api.legacySetTracked(id, want) then self:SetChecked(false) end
	if PlaySound and SOUNDKIT then
		local _ = (root.playSound or pcall)(PlaySound, want and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
end
local function boxEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Track in ForeverTrackerPlus", 1, 1, 1, 1, true)
	GameTooltip:AddLine("Shows this challenge and its open steps above your quests.", 1, 0.82, 0, true)
	GameTooltip:Show()
end
local function decorate(card)
	if type(card) ~= "table" or type(card.GetObjectType) ~= "function" then return end
	if not card.ftpTrack then
		local box = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
		box:SetSize(24, 24)
		box:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 10)
		box:SetFrameLevel(card:GetFrameLevel() + 12)
		local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("RIGHT", box, "LEFT", -2, 1)
		label:SetText("Track")
		box.ftpLabel = label
		box:SetHitRectInsets(-((label:GetStringWidth() or 30) + 4), 0, 0, 0) -- the word clicks too
		box:SetScript("OnClick", boxClick)
		box:SetScript("OnEnter", boxEnter)
		box:SetScript("OnLeave", onLeave)
		card.ftpTrack = box
		cards[#cards + 1] = card
	end
	refreshBox(card)
end
api.legacyDecorateCard = decorate -- for tests
function api.legacyRefreshBoxes() for _, card in ipairs(cards) do refreshBox(card) end end

local hooked = false
local function hookLegacyWindow()
	if hooked then return true end
	local mixin = rawget(_G, "LegacyChallengeTemplateMixin")
	if type(mixin) ~= "table" or type(mixin.Init) ~= "function" then return false end
	hooked = true
	hooksecurefunc(mixin, "Init", function(card) pcall(decorate, card) end)
	return true
end
api.legacyHookWindow = hookLegacyWindow -- for tests
if not hookLegacyWindow() and CreateFrame then
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:SetScript("OnEvent", function(self, _, name)
		if name == "Blizzard_LegacySystem" and hookLegacyWindow() then self:UnregisterEvent("ADDON_LOADED") end
	end)
end
