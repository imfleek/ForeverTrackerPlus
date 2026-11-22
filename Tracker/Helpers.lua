-- 3.0 Helpers (Settings > Helpers). The ideas come from QuestMaster (its quest bag marks and item guard, reward hint,
-- "While you're here" card, breath warning and flight times); the code is our own. Each one has its own switch, on
-- by default:
--   db.bagMarks     a small quest sign on bag slots whose item a quest in your log still needs; a warning in chat when
--                   such an item is sold, and a line in the game's delete question naming the quest
--   db.rewardHint   on a quest's reward choice: a gold coin on the reward that sells for the most
--   db.nearbyCard   (Questie) a card at the top of the screen when a quest you can take is close: left-click sets a
--                   map waypoint, right-click puts it away; once per quest and session, not in combat, an instance or
--                   a flight, never a grey quest
--   db.breathWarn   red pulsing screen edges when breath or fatigue has 10 seconds or less left
--   db.flightTimes  learns how long each flight takes (account-wide, db.flightLog) and shows the time left while
--                   flying, and the time on the flight map's tooltip; a route not flown yet gets an estimate from the
--                   flight map ("about"), and every learned flight makes the estimates better (db.flightSpeed)
-- 3.1.1: when another addon shows the same thing (OneForAll's reward coin, EllesmereUI Forever Essentials' Flight
--   Timer), the player is asked which one to keep (CLASHES below). EllesmereUI's flight map time has no switch, so our
--   tooltip line steps aside while that addon is loaded.
-- CONSTRAINT: secure hooks only (hooksecurefunc runs after the game's function and cannot taint it); every event is
-- registered in a pcall (an unknown event errors on Forever) and every global is checked before use.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RXP ForeverTracker|r " .. text) end
local function opt(key) return db and db[key] ~= false end

local function loaded(name)
	local f = C_AddOns and C_AddOns.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
	return type(f) == "function" and f(name) and true or false
end
local function tbl(t, k) return type(t) == "table" and type(t[k]) == "table" and t[k] or nil end
-- Two addons showing the same thing: the player is asked once at login (and when our switch is turned on) whether to
-- turn the other addon's feature off and use ours. "Use ours" writes the other addon's own saved switch (both read it
-- live); "Keep theirs" turns our switch off. Nothing is asked again while one of the two is off.
local CLASHES = {
	{ key = "rewardHint", addon = "OneForAll",
		text = "OneForAll also puts a gold coin on the best quest reward. You see two coins.\n\nTurn off OneForAll's coin and use ours?",
		theirsOn = function()
			local d = tbl(rawget(_G, "OneForAllDB"), "qol")
			return not d or d.questSellCoin ~= false
		end,
		theirsOff = function()
			local t = rawget(_G, "OneForAllDB")
			if type(t) ~= "table" then return false end
			t.qol = type(t.qol) == "table" and t.qol or {}
			t.qol.questSellCoin = false
			return true
		end },
	{ key = "flightTimes", addon = "EllesmereUIForeverEssentials",
		text = "EllesmereUI's Flight Timer also shows a bar while you fly. You see two bars.\n\nTurn off EllesmereUI's Flight Timer and use ours?",
		theirsOn = function()
			local c = tbl(rawget(_G, "EllesmereUIDB"), "flightTimer")
			return not c or c.enabled ~= false
		end,
		theirsOff = function()
			local t = rawget(_G, "EllesmereUIDB")
			if type(t) ~= "table" then return false end
			t.flightTimer = type(t.flightTimer) == "table" and t.flightTimer or {}
			t.flightTimer.enabled = false
			return true
		end },
}
local function clashOn(c)
	if not (opt(c.key) and loaded(c.addon)) then return false end
	local ok, on = pcall(c.theirsOn)
	return ok and on and true or false
end
local clashQueue, asking = {}, false
local function askNext()
	asking = false
	local c = table.remove(clashQueue, 1)
	while c and not clashOn(c) do c = table.remove(clashQueue, 1) end
	if not c or type(StaticPopup_Show) ~= "function" then return end
	asking = true
	StaticPopup_Show("RXPFT_ADDON_CLASH", c.text, nil, c)
end
StaticPopupDialogs["RXPFT_ADDON_CLASH"] = {
	text = "|cff33ff99RXP ForeverTracker|r\n\n%s", button1 = "Use ours", button2 = "Keep theirs",
	OnAccept = function(_, c)
		local ok, done = pcall(c.theirsOff)
		if ok and done then say("turned off the same feature in " .. c.addon .. ". Ours is on.") end
		askNext()
	end,
	OnCancel = function(_, c, reason)
		if reason == "clicked" and db then db[c.key] = false; say("kept " .. c.addon .. "'s version. Ours is off (/qt to turn it on again).") end
		askNext()
	end,
	timeout = 0, whileDead = 1, hideOnEscape = false, preferredIndex = 3,
}
-- ask about every clash that shows now (key: only that one)
local function checkClashes(key)
	for _, c in ipairs(CLASHES) do
		if (not key or c.key == key) and clashOn(c) then
			local queued = false
			for _, q in ipairs(clashQueue) do if q == c then queued = true end end
			if not queued then clashQueue[#clashQueue + 1] = c end
		end
	end
	if not asking then askNext() end
end
api.checkAddonClashes = checkClashes
api.addonClashOn = function(key) for _, c in ipairs(CLASHES) do if c.key == key then return clashOn(c) end end return false end
-- EllesmereUI's flight map time is always on (it has no switch), so our tooltip line steps aside while it is loaded
local function eluiMapTime() return loaded("EllesmereUIForeverEssentials") end
local QUEST_SIGN = "Interface\\GossipFrame\\AvailableQuestIcon"

local function onEvents(list, handler)
	local f = CreateFrame("Frame")
	for _, e in ipairs(list) do pcall(f.RegisterEvent, f, e) end
	f:SetScript("OnEvent", function(_, event, ...)
		local ok, err = pcall(handler, event, ...)
		if not ok then geterrorhandler()(err) end
	end)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- Quest items in the bags
---------------------------------------------------------------------------------------------------------------------
local neededCache
-- item name -> quest title, for every unfinished "item" objective in the log
local function neededItems()
	if neededCache then return neededCache end
	local out = {}
	local count = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
		or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
	for i = 1, tonumber(count) or 0 do
		local title, isHeader
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			if info then title, isHeader = info.title, info.isHeader end
		elseif GetQuestLogTitle then
			local t, _, _, header = GetQuestLogTitle(i)
			title, isHeader = t, header
		end
		if title and not isHeader and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
			for j = 1, GetNumQuestLeaderBoards(i) or 0 do
				local text, kind, finished = GetQuestLogLeaderBoard(j, i)
				if kind == "item" and not finished and type(text) == "string" and not isSecret(text) then
					local name = text:match("^(.-):%s*%d+%s*/%s*%d+") or text:match("^%d+%s*/%s*%d+%s+(.+)$")
					if name and name ~= "" then out[name] = title end
				end
			end
		end
	end
	neededCache = out
	return out
end

local function itemName(id)
	if not id then return nil end
	if C_Item and C_Item.GetItemNameByID then
		local ok, name = pcall(C_Item.GetItemNameByID, id)
		if ok and type(name) == "string" then return name end
	end
	if GetItemInfo then
		local name = GetItemInfo(id)
		if type(name) == "string" then return name end
	end
	return nil
end

local function slotItemId(bag, slot)
	if C_Container and C_Container.GetContainerItemID then
		local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
		if ok and type(id) == "number" then return id end
	end
	if C_Container and C_Container.GetContainerItemInfo then
		local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(info) == "table" then return info.itemID end
	end
	return nil
end

-- the quest that needs this slot's item, or nil
local function slotQuest(bag, slot)
	local id = slotItemId(bag, slot)
	if not id then return nil end
	local name = itemName(id)
	local needed = neededItems()
	if name and needed[name] then return needed[name] end
	if C_Container and C_Container.GetContainerItemQuestInfo then
		local ok, info = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
		if ok and type(info) == "table" and info.isQuestItem and info.questID and info.isActive then
			local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(info.questID)
			return type(title) == "string" and title or "a quest"
		end
	end
	return nil
end

local function paint(button, bag, slot)
	if type(button) ~= "table" or not button.CreateTexture then return end
	local quest = opt("bagMarks") and bag and slot and slotQuest(bag, slot)
	local mark = button.rxpftQuestMark
	if quest and not mark then
		mark = button:CreateTexture(nil, "OVERLAY", nil, 7)
		mark:SetTexture(QUEST_SIGN)
		mark:SetSize(15, 15)
		mark:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
		button.rxpftQuestMark = mark
	end
	if mark then mark:SetShown(quest and true or false) end
end

local function buttonBagSlot(button, frameBag)
	local bag = button.GetBagID and button:GetBagID() or frameBag
	local slot = button.GetID and button:GetID()
	return bag, slot
end
local function paintNewFrame(frame)
	if not (frame and frame.EnumerateValidItems) then return end
	for _, button in frame:EnumerateValidItems() do
		local bag, slot = buttonBagSlot(button)
		paint(button, bag, slot)
	end
end
local function paintOldFrame(frame)
	if not (frame and frame.GetName and frame.GetID) or frame.EnumerateValidItems then return end
	local name, bag = frame:GetName(), frame:GetID()
	if not name then return end
	for i = 1, tonumber(frame.size) or 36 do
		local button = rawget(_G, name .. "Item" .. i)
		if not button then break end
		paint(button, bag, button:GetID())
	end
end
-- Bag addons with their own windows built from the game's item slot template (ContainerFrameItemButtonTemplate): a
-- slot's ID is its slot and its parent's ID its bag. EllesmereUI Bags: the frame EUI_Bags (EUI_MainBagFrame), redrawn
-- by EUI_Bags:RefreshInventory (EllesmereUIBags/EUI_Bags_Refresh.lua, Grid.lua, List.lua).
local OTHER_BAGS = { { frame = "EUI_Bags", method = "RefreshInventory" } }
local function isItemButton(f)
	return type(f) == "table" and (f.SetItemButtonTexture ~= nil or (f.GetObjectType and f:GetObjectType() == "ItemButton"))
end
local function paintTree(frame, depth)
	if not (frame and frame.GetChildren) then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if isItemButton(child) then
			if child:IsShown() then
				local parent = child.GetParent and child:GetParent()
				local bag = child.GetBagID and child:GetBagID() or (parent and parent.GetID and parent:GetID())
				paint(child, bag, child.GetID and child:GetID())
			end
		elseif depth < 6 then
			paintTree(child, depth + 1)
		end
	end
end
local function paintOtherBags()
	for _, o in ipairs(OTHER_BAGS) do
		local f = rawget(_G, o.frame)
		if type(f) == "table" and f.IsShown and f:IsShown() then pcall(paintTree, f, 0) end
	end
end

local function repaintBags()
	neededCache = nil
	paintOtherBags()
	local box = rawget(_G, "ContainerFrameContainer")
	for _, f in ipairs(box and box.ContainerFrames or {}) do if f:IsShown() then pcall(paintNewFrame, f) end end
	local combined = rawget(_G, "ContainerFrameCombinedBags")
	if combined and combined:IsShown() then pcall(paintNewFrame, combined) end
	for n = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = rawget(_G, "ContainerFrame" .. n)
		if f and f:IsShown() then pcall(paintOldFrame, f) end
	end
end
api.repaintBagMarks = repaintBags

local hookedFrames = {}
local function hookBags()
	if not hooksecurefunc then return end
	local box = rawget(_G, "ContainerFrameContainer")
	local frames = {}
	for _, f in ipairs(box and box.ContainerFrames or {}) do frames[#frames + 1] = f end
	if rawget(_G, "ContainerFrameCombinedBags") then frames[#frames + 1] = ContainerFrameCombinedBags end
	for _, f in ipairs(frames) do
		if not hookedFrames[f] and type(f.UpdateItems) == "function" then
			hookedFrames[f] = true
			hooksecurefunc(f, "UpdateItems", function(self) pcall(paintNewFrame, self) end)
		end
	end
	for _, o in ipairs(OTHER_BAGS) do
		local f = rawget(_G, o.frame)
		if type(f) == "table" and not hookedFrames[o.frame] and type(f[o.method]) == "function" then
			hookedFrames[o.frame] = true
			hooksecurefunc(f, o.method, function() neededCache = nil; paintOtherBags() end)
			if f.HookScript then f:HookScript("OnShow", function() hookBags(); repaintBags() end) end
		end
	end
	if not hookedFrames.old and type(rawget(_G, "ContainerFrame_Update")) == "function" then
		hookedFrames.old = true
		hooksecurefunc("ContainerFrame_Update", function(self) pcall(paintOldFrame, self) end)
	end
end

-- sold at a vendor: the needed items' counts before, compared after each bag change while the merchant is open
local merchantCounts
local function neededCounts()
	local out = {}
	local needed = neededItems()
	if not (C_Container and C_Container.GetContainerNumSlots) then return out end
	for bag = 0, 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local id = slotItemId(bag, slot)
			local name = id and itemName(id)
			if name and needed[name] then
				local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
				out[name] = (out[name] or 0) + (type(info) == "table" and tonumber(info.stackCount) or 1)
			end
		end
	end
	return out
end
local function checkSold()
	if not merchantCounts then return end
	local now = neededCounts()
	local needed = neededItems()
	for name, before in pairs(merchantCounts) do
		if (now[name] or 0) < before then
			local text = ("|cffff5a3cYou sold %s. \"%s\" still needs it: buy it back on the merchant's Buyback tab.|r"):format(name, needed[name] or "a quest")
			say(text)
			if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.35, 0.24) end
		end
	end
	merchantCounts = now
end

-- deleting: the game's question names the quest
local DELETE_DIALOGS = { DELETE_ITEM = true, DELETE_GOOD_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local function onPopup(which)
	if not (DELETE_DIALOGS[which] and opt("bagMarks") and GetCursorInfo) then return end
	local kind, id = GetCursorInfo()
	if kind ~= "item" or type(id) ~= "number" then return end
	neededCache = nil
	local quest = neededItems()[itemName(id) or ""]
	if not quest then return end
	local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
	local fs = dialog and (dialog.text or dialog.Text or (dialog.GetName and dialog:GetName() and rawget(_G, dialog:GetName() .. "Text")))
	if not (fs and fs.GetText and fs.SetText) then return end
	local before = fs:GetStringHeight() or 0
	fs:SetText((fs:GetText() or "") .. "\n\n|cffffd100Still needed for \"" .. quest .. "\"|r")
	local after = fs:GetStringHeight() or before
	if dialog.SetHeight and after > before then dialog:SetHeight((dialog:GetHeight() or 0) + after - before) end
end

---------------------------------------------------------------------------------------------------------------------
-- The reward that sells for the most
---------------------------------------------------------------------------------------------------------------------
local rewardMarks = {}
local function rewardButton(i)
	local frame = rawget(_G, "QuestInfoRewardsFrame")
	if frame and type(frame.RewardButtons) == "table" then
		for _, b in ipairs(frame.RewardButtons) do
			if b.type == "choice" and b.GetID and b:GetID() == i and b:IsShown() then return b end
		end
	end
	local b = rawget(_G, "QuestInfoRewardsFrameQuestInfoItem" .. i)
	if b and (b.type == nil or b.type == "choice") then return b end
	return nil
end
local function clearRewardMarks() for _, m in pairs(rewardMarks) do m:Hide() end end
local pendingReward
local function markReward()
	clearRewardMarks()
	pendingReward = nil
	if not opt("rewardHint") then return end
	if type(GetNumQuestChoices) ~= "function" or type(GetQuestItemLink) ~= "function" then return end
	local n = GetNumQuestChoices() or 0
	if n < 2 then return end
	local best, bestValue = nil, 0
	for i = 1, n do
		local link = GetQuestItemLink("choice", i)
		local count = 1
		if type(GetQuestItemInfo) == "function" then count = select(3, GetQuestItemInfo("choice", i)) or 1 end
		local price = link and GetItemInfo and select(11, GetItemInfo(link))
		if link and price == nil then pendingReward = true end
		local value = (tonumber(price) or 0) * math.max(tonumber(count) or 1, 1)
		if value > bestValue then best, bestValue = i, value end
	end
	if not best then return end
	local button = rewardButton(best)
	if not button then return end
	local mark = rewardMarks[button]
	if not mark then
		mark = CreateFrame("Frame", nil, button)
		mark:SetAllPoints()
		mark:SetFrameLevel(button:GetFrameLevel() + 5)
		local coin = mark:CreateTexture(nil, "OVERLAY")
		coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
		coin:SetSize(14, 14)
		coin:SetPoint("TOPRIGHT", mark, "TOPRIGHT", -2, -2)
		local glow = mark:CreateTexture(nil, "ARTWORK")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 0.82, 0, 0.12)
		mark:EnableMouse(false)
		rewardMarks[button] = mark
	end
	mark:Show()
end
local function scheduleReward() C_Timer.After(0.05, function() pcall(markReward) end) end

---------------------------------------------------------------------------------------------------------------------
-- A quest close by (Questie)
---------------------------------------------------------------------------------------------------------------------
local NEAR_YARDS = 70
local card, cardQuest
local seenQuests = {}
local function inInstance()
	if not IsInInstance then return false end
	local inside, kind = IsInInstance()
	return inside and kind ~= "none"
end
local function buildCard()
	local kit = api.themeKit
	if card or not kit then return card end
	local C = kit.C
	card = CreateFrame("Button", "RXPForeverTrackerNearbyQuest", UIParent)
	card:SetSize(300, 50)
	card:SetPoint("TOP", UIParent, "TOP", 0, -110)
	card:SetFrameStrata("MEDIUM")
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local bg = card:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	kit.gradient(bg, C.titleTop, C.titleBottom)
	kit.border(card, { 0.55, 0.43, 0.18 }, 1, "BORDER")
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(QUEST_SIGN)
	icon:SetSize(26, 26)
	icon:SetPoint("LEFT", 10, 0)
	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
	card.title:SetPoint("RIGHT", -10, 0)
	card.title:SetJustifyH("LEFT")
	card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.sub:SetPoint("RIGHT", -10, 0)
	card.sub:SetJustifyH("LEFT")
	card.sub:SetTextColor(C.label[1], C.label[2], C.label[3])
	local hl = card:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.9, 0.6, 0.06)
	card:SetScript("OnClick", function(self, button)
		if button == "LeftButton" and cardQuest and cardQuest.map and C_Map.CanSetUserWaypointOnMap
			and C_Map.CanSetUserWaypointOnMap(cardQuest.map) and UiMapPoint then
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(cardQuest.map, cardQuest.x, cardQuest.y))
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		end
		self:Hide()
	end)
	card:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("A quest close by", 1, 0.82, 0)
		GameTooltip:AddLine("Left-click: map waypoint to its giver", 1, 1, 1)
		GameTooltip:AddLine("Right-click: put this away", 1, 1, 1)
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function() GameTooltip:Hide() end)
	card:Hide()
	return card
end
local cardShownAt = 0
local function nearbyTick()
	if card and card:IsShown() and GetTime() - cardShownAt > 25 then card:Hide() end
	if not (opt("nearbyCard") and api.questieAvailableNear and api.playerWorldPos) then return end
	if (card and card:IsShown()) or inInstance() or InCombatLockdown() then return end
	if UnitOnTaxi and UnitOnTaxi("player") then return end
	local me = api.playerWorldPos()
	if not me then return end
	local found = api.questieAvailableNear(me, NEAR_YARDS, seenQuests)
	if not found then return end
	seenQuests[found.id] = true
	buildCard()
	if not card then return end
	cardQuest = found
	card.title:SetText(("Quest nearby: %s%s"):format(found.title or "?", found.level and (" (" .. found.level .. ")") or ""))
	card.sub:SetText(("%s, %d yd. Click: waypoint. Right-click: close."):format(found.giver or "Quest giver", math.floor(found.d + 0.5)))
	card:SetWidth(math.max(300, math.min(460, (card.title:GetStringWidth() or 200) + 60)))
	card:Show()
	cardShownAt = GetTime()
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN) end
end

---------------------------------------------------------------------------------------------------------------------
-- Breath and fatigue
---------------------------------------------------------------------------------------------------------------------
local WARN_AT = 10
local timers = {}
local edge, breathTicker
local function buildEdge()
	if edge then return edge end
	edge = CreateFrame("Frame", nil, UIParent)
	edge:SetAllPoints(UIParent)
	edge:SetFrameStrata("BACKGROUND")
	edge:EnableMouse(false)
	local size = 60
	local function strip(p1, p2, w, h, orient, a1, a2)
		local t = edge:CreateTexture(nil, "BACKGROUND")
		t:SetPoint(p1)
		t:SetPoint(p2)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		t:SetColorTexture(1, 1, 1, 1)
		if t.SetGradient and CreateColor then
			pcall(t.SetGradient, t, orient, CreateColor(0.9, 0.05, 0.05, a1), CreateColor(0.9, 0.05, 0.05, a2))
		else
			t:SetColorTexture(0.9, 0.05, 0.05, 0.3)
		end
	end
	strip("TOPLEFT", "BOTTOMLEFT", size, nil, "HORIZONTAL", 0.55, 0)
	strip("TOPRIGHT", "BOTTOMRIGHT", size, nil, "HORIZONTAL", 0, 0.55)
	strip("TOPLEFT", "TOPRIGHT", nil, size, "VERTICAL", 0, 0.55)
	strip("BOTTOMLEFT", "BOTTOMRIGHT", nil, size, "VERTICAL", 0.55, 0)
	local pulse = edge:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.25)
	a:SetDuration(0.6)
	edge.pulse = pulse
	edge:Hide()
	return edge
end
local function timeLeft(t)
	if t.paused then return t.value end
	return t.value + (t.scale or -1) * (GetTime() - t.at)
end
local function breathCheck()
	local low
	for _, t in pairs(timers) do
		local left = timeLeft(t)
		if (t.scale or -1) < 0 and (not low or left < low) then low = left end
	end
	local warn = low and low <= WARN_AT and opt("breathWarn")
	if warn then
		buildEdge()
		if not edge:IsShown() then
			edge:Show()
			edge.pulse:Play()
			if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
		end
	elseif edge and edge:IsShown() then
		edge.pulse:Stop()
		edge:Hide()
	end
	if not low and breathTicker then breathTicker:Cancel(); breathTicker = nil end
end
local function onMirror(event, name, value, _, scale, paused)
	if name ~= "BREATH" and name ~= "EXHAUSTION" then return end
	if event == "MIRROR_TIMER_START" then
		timers[name] = { value = (tonumber(value) or 0) / 1000, scale = tonumber(scale) or -1, at = GetTime(),
			paused = (tonumber(paused) or 0) > 0 }
		if not breathTicker and C_Timer.NewTicker then breathTicker = C_Timer.NewTicker(0.25, breathCheck) end
	elseif event == "MIRROR_TIMER_PAUSE" then
		local t = timers[name]
		if t then t.value, t.at, t.paused = timeLeft(t), GetTime(), (tonumber(value) or 0) > 0 end
	elseif event == "MIRROR_TIMER_STOP" then
		timers[name] = nil
	end
	breathCheck()
end

---------------------------------------------------------------------------------------------------------------------
-- Flight times
---------------------------------------------------------------------------------------------------------------------
local flight, flightBar
local function nodeName(i)
	if type(TaxiNodeName) ~= "function" then return nil end
	local name = TaxiNodeName(i)
	return type(name) == "string" and not isSecret(name) and name or nil
end
local function currentNode()
	if type(NumTaxiNodes) ~= "function" or type(TaxiNodeGetType) ~= "function" then return nil end
	for i = 1, NumTaxiNodes() or 0 do
		if TaxiNodeGetType(i) == "CURRENT" then return nodeName(i) end
	end
	return nil
end
local function routeKey(from, to) return from and to and (from .. " > " .. to) or nil end
local function known(from, to)
	local log = db and type(db.flightLog) == "table" and db.flightLog
	local e = log and log[routeKey(from, to) or ""]
	return type(e) == "table" and tonumber(e.t) or nil
end
api.flightTime = known
-- A route not flown yet: its stops on the flight map (GetNumRoutes, TaxiGetNodeSlot, TaxiNodePosition) give its length
-- in yards (C_Map.GetWorldPosFromMapPos on GetTaxiMapID's map); time = length / speed. The speed starts at
-- DEFAULT_SPEED and every flight learned corrects it (db.flightSpeed, account-wide). A learned time always wins.
local DEFAULT_SPEED = 28 -- yards per second along the straight lines between the stops
local function slotPos(slot)
	local ok, x, y = pcall(TaxiNodePosition, slot)
	if not (ok and type(x) == "number" and type(y) == "number") or isSecret(x) or isSecret(y) then return nil end
	local map = type(GetTaxiMapID) == "function" and GetTaxiMapID()
	if not (map and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local ok2, _, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not (ok2 and type(pos) == "table" and pos.GetXY) then return nil end
	local wx, wy = pos:GetXY()
	if type(wx) ~= "number" or type(wy) ~= "number" then return nil end
	return wx, wy
end
local function routeYards(index)
	if type(GetNumRoutes) ~= "function" or type(TaxiGetNodeSlot) ~= "function" or type(TaxiNodePosition) ~= "function" then return nil end
	local ok, hops = pcall(GetNumRoutes, index)
	if not ok or type(hops) ~= "number" or hops < 1 or hops > 30 then return nil end
	local total = 0
	for h = 1, hops do
		local okA, a = pcall(TaxiGetNodeSlot, index, h, true)
		local okB, b = pcall(TaxiGetNodeSlot, index, h, false)
		if not (okA and okB and type(a) == "number" and type(b) == "number") then return nil end
		local x1, y1 = slotPos(a)
		local x2, y2 = slotPos(b)
		if not (x1 and x2) then return nil end
		total = total + math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	end
	return total > 0 and total or nil
end
local function flightSpeed()
	local v = db and tonumber(db.flightSpeed)
	return v and v > 5 and v < 100 and v or DEFAULT_SPEED
end
local function estimate(index)
	local yards = routeYards(index)
	return yards and yards / flightSpeed() or nil
end
api.flightEstimate = estimate
local function buildFlightBar()
	if flightBar then return flightBar end
	local kit = api.themeKit
	flightBar = CreateFrame("Frame", nil, UIParent)
	flightBar:SetSize(260, 26)
	flightBar:SetPoint("TOP", UIParent, "TOP", 0, -80)
	local bg = flightBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if kit then kit.gradient(bg, kit.C.titleTop, kit.C.titleBottom); kit.border(flightBar, { 0.55, 0.43, 0.18 }, 1, "BORDER")
	else bg:SetColorTexture(0, 0, 0, 0.6) end
	flightBar.text = flightBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	flightBar.text:SetPoint("CENTER")
	flightBar:SetScript("OnUpdate", function(self, elapsed)
		self.wait = (self.wait or 0) + elapsed
		if self.wait < 0.5 then return end
		self.wait = 0
		if not flight or not flight.started then self:Hide() return end
		local gone = GetTime() - flight.started
		local learned = known(flight.from, flight.to)
		local total = learned or flight.estimate
		if total then
			self.text:SetText((learned and "Flight to %s: %s left" or "Flight to %s: about %s left"):format(flight.to, api.statsClock and api.statsClock(math.max(total - gone, 0)) or math.floor(total - gone)))
		else
			self.text:SetText(("Flight to %s: learning this flight (%s)"):format(flight.to, api.statsClock and api.statsClock(gone) or math.floor(gone)))
		end
		self:SetWidth(math.max(260, (self.text:GetStringWidth() or 200) + 30))
	end)
	flightBar:Hide()
	return flightBar
end
local function onTakeNode(index)
	if not opt("flightTimes") then return end
	local to, from = nodeName(index), currentNode()
	if to and from then
		local yards = routeYards(index)
		flight = { from = from, to = to, chosen = GetTime(), yards = yards, estimate = yards and yards / flightSpeed() or nil }
	end
end
local function onFlightEvent(event)
	if not flight then return end
	if event == "PLAYER_CONTROL_LOST" then
		C_Timer.After(0.5, function()
			if flight and not flight.started and UnitOnTaxi and UnitOnTaxi("player") and GetTime() - flight.chosen < 15 then
				flight.started = GetTime()
				if opt("flightTimes") then buildFlightBar():Show() end
			end
		end)
	elseif event == "PLAYER_CONTROL_GAINED" then
		if flight.started and not (UnitOnTaxi and UnitOnTaxi("player")) then
			local took = GetTime() - flight.started
			if took > 10 and took < 1800 and not flight.early then
				db.flightLog = type(db.flightLog) == "table" and db.flightLog or {}
				local key = routeKey(flight.from, flight.to)
				local e = db.flightLog[key]
				local n = type(e) == "table" and tonumber(e.n) or 0
				local t = type(e) == "table" and tonumber(e.t) or took
				db.flightLog[key] = { t = (t * n + took) / (n + 1), n = math.min(n + 1, 5) }
				if flight.yards then
					local measured = flight.yards / took
					if measured > 5 and measured < 100 then
						local old = tonumber(db.flightSpeed)
						db.flightSpeed = old and (old * 0.7 + measured * 0.3) or measured
					end
				end
			end
			flight = nil
			if flightBar then flightBar:Hide() end
		end
	end
end
local function onNodeEnter(button)
	if not (opt("flightTimes") and button and button.GetID and GameTooltip:IsShown()) or eluiMapTime() then return end
	local t = known(currentNode(), nodeName(button:GetID()))
	local about = false
	if not t then t, about = estimate(button:GetID()), true end
	if t then
		GameTooltip:AddLine((about and "Flight time: about %s" or "Flight time: %s"):format(api.statsClock and api.statsClock(t) or math.floor(t)), 0.6, 0.85, 1)
		GameTooltip:Show()
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	if C_Timer and C_Timer.After then C_Timer.After(8, function() checkClashes() end) end
	hookBags()
	onEvents({ "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_OPEN" }, function(event)
		if event == "MERCHANT_SHOW" then
			neededCache = nil
			merchantCounts = opt("bagMarks") and neededCounts() or nil
		elseif event == "MERCHANT_CLOSED" then
			merchantCounts = nil
		elseif event == "BAG_UPDATE_DELAYED" and merchantCounts then
			checkSold()
		end
		if event == "QUEST_LOG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "BAG_OPEN" then
			hookBags()
			repaintBags()
		end
	end)
	onEvents({ "QUEST_COMPLETE", "GET_ITEM_INFO_RECEIVED", "QUEST_FINISHED" }, function(event)
		if event == "QUEST_FINISHED" then clearRewardMarks()
		elseif event == "QUEST_COMPLETE" or pendingReward then scheduleReward() end
	end)
	onEvents({ "MIRROR_TIMER_START", "MIRROR_TIMER_PAUSE", "MIRROR_TIMER_STOP" }, onMirror)
	onEvents({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }, onFlightEvent)
	if hooksecurefunc then
		if StaticPopup_Show then hooksecurefunc("StaticPopup_Show", function(which) pcall(onPopup, which) end) end
		if type(rawget(_G, "QuestInfo_ShowRewards")) == "function" then hooksecurefunc("QuestInfo_ShowRewards", scheduleReward) end
		if type(rawget(_G, "TakeTaxiNode")) == "function" then hooksecurefunc("TakeTaxiNode", function(i) pcall(onTakeNode, i) end) end
		if type(rawget(_G, "TaxiRequestEarlyLanding")) == "function" then
			hooksecurefunc("TaxiRequestEarlyLanding", function() if flight then flight.early = true end end)
		end
		if type(rawget(_G, "TaxiNodeOnButtonEnter")) == "function" then
			hooksecurefunc("TaxiNodeOnButtonEnter", function(b) pcall(onNodeEnter, b) end)
		end
	end
	if C_Timer.NewTicker then C_Timer.NewTicker(3, function() pcall(nearbyTick) end) end
end

---------------------------------------------------------------------------------------------------------------------
-- Settings > Helpers (declared by Config.lua: api.declareHelperPages(kit))
---------------------------------------------------------------------------------------------------------------------
function api.declareHelperPages(k)
	k.page("helpers", "quests", "Quest helpers")
	k.heading("Bags")
	k.check("Mark quest items in your bags", function() return db.bagMarks ~= false end,
		function(v) db.bagMarks = v and true or false; repaintBags() end)
	k.help("a quest sign on items a quest still needs; a warning if you sell or delete one")
	k.heading("Rewards")
	k.check("Mark the best reward to sell", function() return db.rewardHint ~= false end,
		function(v) db.rewardHint = v and true or false; if v then checkClashes("rewardHint") end end)
	k.help("on a quest's reward choice, a gold coin on the reward that sells for the most. If OneForAll's coin is on too, you are asked which one to keep")
	k.heading("Nearby quests")
	k.check("Card for a quest close by", function() return db.nearbyCard ~= false end,
		function(v) db.nearbyCard = v and true or false; if not v and card then card:Hide() end end,
		function() return api.questieLoaded and api.questieLoaded() end)
	k.help("needs Questie. A quest you can take within 70 yards: a card at the top of the screen; click it for a waypoint")
	k.check("Leave out breadcrumb quests you do not need", function() return db.breadcrumbHide ~= false end,
		function(v) db.breadcrumbHide = v and true or false end,
		function() return api.questieLoaded and api.questieLoaded() end)
	k.help("a breadcrumb only sends you to another quest; hidden once you did that quest or have it")
	k.pageByKey.helpers.reset = k.reset

	k.page("world", "quests", "World")
	k.heading("Swimming")
	k.check("Breath warning", function() return db.breathWarn ~= false end,
		function(v) db.breathWarn = v and true or false; breathCheck() end)
	k.help("red pulsing screen edges when breath or fatigue has 10 seconds or less left")
	k.heading("Flights")
	k.check("Flight times", function() return db.flightTimes ~= false end,
		function(v) db.flightTimes = v and true or false; if not v and flightBar then flightBar:Hide() end; if v then checkClashes("flightTimes") end end)
	k.help("every route has a time from the start: an estimate from the flight map (\"about\") until you fly it, then the real time. Shows the time left while flying, and the time on the flight map. If EllesmereUI's Flight Timer is on too, you are asked which one to keep")
	k.statusBox("Flights learned", function()
		local n = 0
		for _ in pairs(db and type(db.flightLog) == "table" and db.flightLog or {}) do n = n + 1 end
		return { { "Learned", tostring(n) .. (n == 1 and " flight" or " flights") } }
	end)
	k.pageByKey.world.reset = k.reset
end
