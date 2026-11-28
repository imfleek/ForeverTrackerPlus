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
--   Timer), the player is asked which one to keep (CLASHES below). EllesmereUI's flight map time has no switch, so its
--   tooltip line is rewritten with our time while that addon is loaded.
-- CONSTRAINT: secure hooks only (hooksecurefunc runs after the game's function and cannot taint it); every event is
-- registered in a pcall (an unknown event errors on Forever) and every global is checked before use.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r " .. text) end
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
	text = "|cff33ff99ForeverTrackerPlus|r\n\n%s", button1 = "Use ours", button2 = "Keep theirs",
	OnAccept = function(_, c)
		local ok, done = pcall(c.theirsOff)
		if ok and done then say("turned off the same feature in " .. c.addon .. ". Ours is on.") end
		askNext()
	end,
	OnCancel = function(_, c, reason)
		if reason == "clicked" and db then db[c.key] = false; say("kept " .. c.addon .. "'s version. Ours is off (/ftp to turn it on again).") end
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
-- EllesmereUI's flight map time is always on (it has no switch): while that addon is loaded its tooltip line is
-- rewritten with our time (one line, ours), see onNodeEnter
local function eluiMapTime() return loaded("EllesmereUIForeverEssentials") end
-- the start of EllesmereUI's line ("Flight time: " in the player's language)
local function eluiPrefix()
	local eui = rawget(_G, "EllesmereUI")
	local ok, t = pcall(function() return eui.Lf("Flight time: %s") end)
	local prefix = ok and type(t) == "string" and t:match("^(.-)%%s")
	return prefix and prefix ~= "" and prefix or "Flight time: "
end
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
-- item name -> quest title, for every "item" objective in the log. A finished one (12/12) counts too: the items are
-- still needed to turn the quest in (3.1.1, user screenshot: no mark on a 12/12 quest item).
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
				if kind == "item" and type(text) == "string" and not isSecret(text) then
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
local OTHER_BAGS = { { frame = "EUI_Bags", method = "RefreshInventory" }, { frame = "EUI_BagsReagent", method = "RefreshInventory" } }
-- an item slot: a button with an ID, an icon or the game's item button methods, in a parent that has an ID (the bag)
local BUTTON_TYPES = { ItemButton = true, Button = true, CheckButton = true }
local function isItemButton(f)
	if type(f) ~= "table" or type(f.GetID) ~= "function" then return false end
	if f.SetItemButtonTexture ~= nil or f.GetBagID ~= nil then return true end
	local ok, kind = pcall(function() return f:GetObjectType() end)
	if not (ok and BUTTON_TYPES[kind]) then return false end
	if kind == "ItemButton" then return true end
	return (f.icon or f.Icon or f.IconBorder) ~= nil
end
local bagStats -- filled while /ftp bags looks (nil otherwise)
local hookedFrames = {}
local function paintTree(frame, depth)
	if not (frame and frame.GetChildren) then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if isItemButton(child) then
			if child:IsShown() then
				local parent = child.GetParent and child:GetParent()
				local okB, bagId = pcall(function() return child.GetBagID and child:GetBagID() end)
				local bag = okB and bagId or (parent and parent.GetID and parent:GetID())
				local slot = child:GetID()
				paint(child, bag, slot)
				if bagStats then
					bagStats.buttons = bagStats.buttons + 1
					if bag and slot and slotItemId(bag, slot) then bagStats.withItem = bagStats.withItem + 1 end
					if child.rxpftQuestMark and child.rxpftQuestMark:IsShown() then bagStats.marked = bagStats.marked + 1 end
					if #bagStats.sample < 3 and bag and slot and slotItemId(bag, slot) then
						bagStats.sample[#bagStats.sample + 1] = ("bag %s slot %s: %s"):format(tostring(bag), tostring(slot), tostring(itemName(slotItemId(bag, slot))))
					end
				end
			end
		elseif depth < 6 then
			paintTree(child, depth + 1)
		end
	end
end
-- EllesmereUI Bags' own way for other addons (EUI_Bags.RegisterItemOverlayIcon, the way Peddler draws its coin): it
-- calls our painter for every slot it draws, with the slot's bag and slot. The mark goes on the slot's text layer
-- (btn._textOverlay), above EllesmereUI's slot art; a mark on the button itself is drawn under that art.
local euiMarks = setmetatable({}, { __mode = "k" })
local euiRegistered = false
local function paintEuiSlot(btn, data)
	if type(btn) ~= "table" then return end
	local bag, slot = type(data) == "table" and tonumber(data.bag), type(data) == "table" and tonumber(data.slot)
	local quest = opt("bagMarks") and bag and slot and bag >= 0 and slot > 0 and slotQuest(bag, slot)
	local mark = euiMarks[btn]
	if quest and not mark then
		local host = btn._textOverlay or btn
		if not host.CreateTexture then return end
		mark = host:CreateTexture(nil, "OVERLAY", nil, 7)
		mark:SetTexture(QUEST_SIGN)
		mark:SetSize(15, 15)
		mark:SetPoint("TOPLEFT", host, "TOPLEFT", -1, 1)
		euiMarks[btn] = mark
	end
	if mark then mark:SetShown(quest and true or false) end
end
local function registerEui()
	if euiRegistered then return true end
	local eui = rawget(_G, "EUI_Bags")
	if type(eui) ~= "table" or type(eui.RegisterItemOverlayIcon) ~= "function" then return false end
	euiRegistered = pcall(eui.RegisterItemOverlayIcon, "ForeverTrackerPlus", function(btn, data) pcall(paintEuiSlot, btn, data) end)
	if euiRegistered and eui.IsVisible and eui:IsVisible() and eui.RefreshInventory then pcall(eui.RefreshInventory, eui) end
	return euiRegistered
end
local function usesEuiOverlay(name) return euiRegistered and (name == "EUI_Bags" or name == "EUI_BagsReagent") end
local function paintOtherBags()
	for _, o in ipairs(OTHER_BAGS) do
		local f = rawget(_G, o.frame)
		if not usesEuiOverlay(o.frame) and type(f) == "table" and f.IsShown and f:IsShown() then pcall(paintTree, f, 0) end
	end
end
-- the quests' needed items changed: EllesmereUI redraws its slots (it calls our painter); nothing while they are the same
local lastNeeded
local function neededKey()
	local names = {}
	for name, quest in pairs(neededItems()) do names[#names + 1] = name .. "=" .. quest end
	table.sort(names)
	return table.concat(names, ";")
end
local function refreshEuiIfNeeded()
	if not euiRegistered then return end
	local key = neededKey()
	if key == lastNeeded then return end
	local first = lastNeeded == nil -- (EllesmereUI drew with these when we registered)
	lastNeeded = key
	if first then return end
	local eui = rawget(_G, "EUI_Bags")
	if eui and eui.IsVisible and eui:IsVisible() and eui.RefreshInventory then pcall(eui.RefreshInventory, eui) end
end

local function repaintBags()
	neededCache = nil
	refreshEuiIfNeeded()
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

-- /qt bags: what the bag marks see (open your bags first)
function api.bagReport(out)
	neededCache = nil
	local needed, n = neededItems(), 0
	local names = {}
	for name in pairs(needed) do n = n + 1; if #names < 6 then names[#names + 1] = name end end
	out(("bag marks %s. Items your quests still need: %d%s"):format(opt("bagMarks") and "on" or "off", n,
		n > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))
	if euiRegistered then
		local shown, total = 0, 0
		for _, m in pairs(euiMarks) do total = total + 1; if m:IsShown() then shown = shown + 1 end end
		out(("EllesmereUI Bags: drawn through its overlay hook, marks shown %d (of %d made)"):format(shown, total))
	end
	for _, o in ipairs(OTHER_BAGS) do
		local f = rawget(_G, o.frame)
		if type(f) == "table" and not usesEuiOverlay(o.frame) then
			bagStats = { buttons = 0, withItem = 0, marked = 0, sample = {} }
			if f.IsShown and f:IsShown() then pcall(paintTree, f, 0) end
			out(("%s: %s, hooked %s, slots found %d, with an item %d, marked %d"):format(o.frame,
				f.IsShown and f:IsShown() and "open" or "closed", hookedFrames[o.frame] and "yes" or "no",
				bagStats.buttons, bagStats.withItem, bagStats.marked))
			for _, line in ipairs(bagStats.sample) do out("  " .. line) end
			bagStats = nil
		end
	end
	local box = rawget(_G, "ContainerFrameContainer")
	out(("game bags: %s"):format(box and "new style" or (rawget(_G, "ContainerFrame1") and "old style" or "none")))
end

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
	registerEui()
	for _, o in ipairs(OTHER_BAGS) do
		local f = rawget(_G, o.frame)
		if not usesEuiOverlay(o.frame) and type(f) == "table" and not hookedFrames[o.frame] and type(f[o.method]) == "function" then
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
	card = CreateFrame("Button", "ForeverTrackerPlusNearbyQuest", UIParent)
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
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then (root.playSound or pcall)(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN) end
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
			if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then (root.playSound or pcall)(PlaySound, SOUNDKIT.RAID_WARNING) end
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
-- 3.1.1 (R311-8): with the game's own path data (Tracker/FlightData.lua: each path's flown length, curves included) a
-- route's length is exact: its hops' node IDs (C_TaxiMap.GetAllTaxiNodes) pick the paths. Its own speed
-- (db.flightPathSpeed) starts at PATH_SPEED and is corrected by every flight on such a route; the map estimate above is
-- left for a route the data does not have (a path the game added after the data was made).
local DEFAULT_SPEED = 28 -- yards per second along the straight lines between the stops
-- 3.2: 30.3 fits 274 real single-hop flight times within about 3 s on average (checked with tests/flight_fit.lua)
local PATH_SPEED = 30.3 -- yards per second along the flown path
-- 3.2 (user: "fix Hyjal"): every path to or from Tainted Foothills (node 3242, Mount Hyjal) flies faster: 45 to 49
-- yards per second against RestedXP's times for all 6 of them (Riverglades' new paths fly at the normal speed)
local NODE_SPEED = { [3242] = 48 }
local slotNodes, slotNodesAt = nil, -1
local function nodeIdOf(slot)
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then return nil end
	if not slotNodes or GetTime() - slotNodesAt > 2 then
		slotNodes, slotNodesAt = {}, GetTime()
		local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
		for _, n in ipairs(ok and type(list) == "table" and list or {}) do
			if type(n) == "table" and n.slotIndex and n.nodeID then slotNodes[n.slotIndex] = n.nodeID end
		end
	end
	return slotNodes[slot]
end
-- exact flown yards and waits of the route to slot `index`, from the path data; nil if a hop is missing
local function pathYards(index, hops)
	local yards, waits = rawget(ns, "flightPathYards"), rawget(ns, "flightPathWaits") or {}
	if type(yards) ~= "table" then return nil end
	local total, wait = 0, 0
	for h = 1, hops do
		local okA, a = pcall(TaxiGetNodeSlot, index, h, true)
		local okB, b = pcall(TaxiGetNodeSlot, index, h, false)
		local na, nb = okA and nodeIdOf(a), okB and nodeIdOf(b)
		local len = na and nb and yards[na * 10000 + nb]
		if not len then return nil end
		-- a faster path counts as fewer yards at PATH_SPEED, so the time comes out right
		local fast = NODE_SPEED[na] or NODE_SPEED[nb]
		if fast then len = len * PATH_SPEED / fast end
		total, wait = total + len, wait + (tonumber(waits[na * 10000 + nb]) or 0)
	end
	return total > 0 and total or nil, wait
end
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
	local exact, wait = pathYards(index, hops)
	if exact then return exact, true, wait end
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
	return total > 0 and total or nil, false, 0
end
-- 3.2: the speed is fixed, not learned any more (a flight logged with time on the ground, 828 s for a 100 s route,
-- had pulled the saved speed down to 24 and every estimate with it)
local function flightSpeed(exact) return exact and PATH_SPEED or DEFAULT_SPEED end
-- seconds, and whether it is close (the game's path data) or "about" (straight lines on the flight map)
local function estimate(index)
	local yards, exact, wait = routeYards(index)
	if not yards then return nil end
	return yards / flightSpeed(exact) + (wait or 0), exact and true or false
end
api.flightEstimate = estimate
-- 3.2 (user: "The clockring is right. Our bar is way off ... Just always use restedxp's list"): the time shown is
-- RestedXP's own flight time list (RXP.FPDB, the list its clock ring uses), looked up the way RestedXP does it
-- (Timers.lua GetFlightTime): from here (flightInfo.currentFP) to the node (flightInfo.nodeHash[GetFlightHash]), or the
-- other way, or the sum of the legs. Read only: nothing of RestedXP's is changed. No time there: nil.
local function rxpFlightTime(index)
	local rxp = rawget(_G, "RXP")
	if type(rxp) ~= "table" then return nil end
	local info = rxp.flightInfo
	local faction = type(rxp.player) == "table" and rxp.player.faction
	local list = type(rxp.FPDB) == "table" and faction and rxp.FPDB[faction]
	if not (type(info) == "table" and type(list) == "table" and type(info.nodeHash) == "table"
		and type(rxp.GetFlightHash) == "function") then return nil end
	local function leg(a, b)
		if not (a and b) then return nil end
		return type(list[a]) == "table" and tonumber(list[a][b]) or type(list[b]) == "table" and tonumber(list[b][a]) or nil
	end
	local ok, hash = pcall(rxp.GetFlightHash, index)
	local src = info.currentFP
	local t = ok and leg(src, info.nodeHash[hash])
	if t then return t end
	if type(GetNumRoutes) ~= "function" then return nil end
	local total = 0
	for i = 1, GetNumRoutes(index) or 0 do
		local okLeg, h = pcall(rxp.GetFlightHash, index, i)
		local dest = okLeg and info.nodeHash[h]
		local part = leg(src, dest)
		if not part then return nil end
		total, src = total + part, dest
	end
	return total > 0 and total or nil
end
api.rxpFlightTime = rxpFlightTime
-- 3.2 (user: "If the user has enabled our flighttracker, disable the clockring"): the RXP Tracker's clock ring skips
-- RestedXP's flight bar while ours is on (Objectives/rxp/Readers.lua activeTimer)
function api.flightTrackerOn() return opt("flightTimes") end
function api.flightNow() return flight end -- (tests)
-- 3.2 (user: "should work even if the user doesn't have RXPGuides installed"): the time of the route to `index`:
-- RestedXP's list when RXPGuides is loaded, else the time you flew it (db.flightLog), else the estimate from the
-- game's path data. Returns seconds and whether it is close (false = "about").
local function routeTime(index, from, to)
	local t = rxpFlightTime(index)
	if t then return t, true end
	t = known(from, to)
	if t then return t, true end
	return estimate(index)
end
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
		-- 3.2: landed (PLAYER_CONTROL_GAINED can come while UnitOnTaxi is still true): close
		if gone > 3 and UnitOnTaxi and not UnitOnTaxi("player") then api.flightLanded() return end
		local clock = api.statsClock or function(s) return tostring(math.floor(s)) end
		local total = flight.total
		if total then
			self.text:SetText((flight.close and "Flight to %s: %s left" or "Flight to %s: about %s left"):format(flight.to,
				clock(math.max(total - gone, 0))))
		else
			self.text:SetText(("Flight to %s: %s"):format(flight.to, clock(gone)))
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
		local total, close = routeTime(index, from, to)
		local okHops, hops = pcall(GetNumRoutes, index)
		flight = { from = from, to = to, chosen = GetTime(), total = total, close = close, guess = estimate(index),
			stops = okHops and type(hops) == "number" and math.max(hops - 1, 0) or nil, rxp = rxpFlightTime(index) }
	end
end
-- 3.2 (user): the druid flights from Moonglade start from a chat option of their own NPC, not from the flight map
-- (no TakeTaxiNode). The game's path data has them: TaxiPath 316 (node 63 > 22, Thunder Bluff) and 315 (62 > 27,
-- Rut'theran Village). GOSSIP_SHOW remembers the NPC; the next taxi start within 60 s is that flight.
local DRUID_FLIGHTS = {
	{ id = 11798, name = "Bunthen Plainswind", from = "Nighthaven, Moonglade", to = "Thunder Bluff, Mulgore", a = 63, b = 22 },
	{ id = 11800, name = "Silva Fil'naveth", from = "Nighthaven, Moonglade", to = "Rut'theran Village, Teldrassil", a = 62, b = 27 },
}
local lastGossip
local function druidFlight(id, name)
	for _, d in ipairs(DRUID_FLIGHTS) do
		if (id and id == d.id) or (name and name == d.name) then return d end
	end
end
local function onGossipShow()
	local guid = UnitGUID and UnitGUID("npc")
	local id = type(guid) == "string" and not isSecret(guid) and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
	local name = UnitName and UnitName("npc")
	if isSecret(name) then name = nil end
	local d = druidFlight(id, name)
	lastGossip = d and { route = d, at = GetTime() } or nil
end
-- seconds of a druid flight: RestedXP's list (with RXPGuides), else the time you flew it, else the path data
local function druidTime(d)
	local rxp = rawget(_G, "RXP")
	local faction = type(rxp) == "table" and type(rxp.player) == "table" and rxp.player.faction
	local list = faction and type(rxp.FPDB) == "table" and rxp.FPDB[faction]
	local t = type(list) == "table" and (type(list[d.a]) == "table" and tonumber(list[d.a][d.b])
		or type(list[d.b]) == "table" and tonumber(list[d.b][d.a]))
	local rxpT = t
	local yards = type(rawget(ns, "flightPathYards")) == "table" and ns.flightPathYards[d.a * 10000 + d.b]
	local waits = rawget(ns, "flightPathWaits") or {}
	local guess = yards and yards / PATH_SPEED + (tonumber(waits[d.a * 10000 + d.b]) or 0)
	if rxpT then return rxpT, true, guess, rxpT end
	t = known(d.from, d.to)
	if t then return t, true, guess end
	return guess, guess ~= nil, guess
end
api.druidFlightTime = druidTime -- (tests)
local function startDruidFlight()
	if not (lastGossip and GetTime() - lastGossip.at < 60 and opt("flightTimes")) then return end
	local d = lastGossip.route
	lastGossip = nil
	local total, close, guess, rxpT = druidTime(d)
	flight = { from = d.from, to = d.to, chosen = GetTime(), total = total, close = close, guess = guess, stops = 0,
		rxp = rxpT }
end
-- the flight is over: learn its time (only a sane one: 10 s to 30 min, and within 0.6 to 1.6 times the path data
-- estimate when there is one), close the bar
function api.flightLanded()
	local f = flight
	flight = nil
	if flightBar then flightBar:Hide() end
	if not (f and f.started and db) then return end
	local took = (f.landed or GetTime()) - f.started
	local sane = took > 10 and took < 1800 and not f.early
	if sane and f.guess then sane = took > f.guess * 0.6 and took < f.guess * 1.6 end
	api.logFlight(f, took, sane)
	if not sane then return end
	db.flightLog = type(db.flightLog) == "table" and db.flightLog or {}
	local key = routeKey(f.from, f.to)
	local e = db.flightLog[key]
	local n = type(e) == "table" and tonumber(e.n) or 0
	local t = type(e) == "table" and tonumber(e.t) or took
	db.flightLog[key] = { t = (t * n + took) / (n + 1), n = math.min(n + 1, 5) }
end
-- 3.2 flight log (user: "Add it"): every flight you land, newest first, the last LOG_MAX: route, stops, our time from
-- the game's path data (what we show without RXPGuides), RestedXP's time, and the real time. /qt flights shows it as
-- text to copy, so wrong routes can be found and fixed. db.flightHistory (account-wide); off: db.flightHistoryOff.
local LOG_MAX = 50
function api.logFlight(f, took, learned)
	if not db or db.flightHistoryOff then return end
	db.flightHistory = type(db.flightHistory) == "table" and db.flightHistory or {}
	local log = db.flightHistory
	local function round(v) return v and math.floor(v + 0.5) or nil end
	table.insert(log, 1, { from = f.from, to = f.to, stops = f.stops, ours = round(f.guess), rxp = round(f.rxp),
		real = round(took), early = f.early or nil, learned = learned or nil, at = type(time) == "function" and time() or nil })
	for i = #log, LOG_MAX + 1, -1 do log[i] = nil end
end
function api.flightLogLines()
	local log = db and type(db.flightHistory) == "table" and db.flightHistory or {}
	local lines = { "ForeverTrackerPlus flight log, newest first. Times in seconds.",
		"ours = from the game's flight path data; rxp = RestedXP's list; real = how long you flew; diff = ours - real.", "" }
	if #log == 0 then lines[#lines + 1] = "No flights yet. Take a flight and land." return lines end
	for _, e in ipairs(log) do
		local when = e.at and type(date) == "function" and date("%Y-%m-%d %H:%M", e.at) or "?"
		local diff = e.ours and e.real and ("%+d"):format(e.ours - e.real) or "-"
		lines[#lines + 1] = ("%s  %s > %s  stops %s  ours %s  rxp %s  real %s  diff %s%s"):format(when,
			tostring(e.from), tostring(e.to), e.stops and tostring(e.stops) or "?", e.ours and tostring(e.ours) or "-",
			e.rxp and tostring(e.rxp) or "-", tostring(e.real), diff, e.early and "  (landed early)" or "")
	end
	return lines
end
if api.addSlash then
	api.addSlash("flights", "the flight log: your last flights with our time, RestedXP's time and the real time", function()
		if api.showDebugWindow then api.showDebugWindow(api.flightLogLines(), "Flight log")
		else for _, l in ipairs(api.flightLogLines()) do say(l) end end
	end)
end
local function onFlightEvent(event)
	if event == "GOSSIP_SHOW" then onGossipShow() return end
	if event == "PLAYER_CONTROL_LOST" and not (flight and not flight.started) then startDruidFlight() end
	if not flight then return end
	if event == "PLAYER_CONTROL_LOST" then
		C_Timer.After(0.5, function()
			if flight and not flight.started and UnitOnTaxi and UnitOnTaxi("player") and GetTime() - flight.chosen < 15 then
				flight.started = GetTime()
				if opt("flightTimes") then buildFlightBar():Show() end
			end
		end)
	elseif event == "PLAYER_CONTROL_GAINED" then
		-- 3.2 (user: "After landing, our flight bar did not close"): UnitOnTaxi can still be true at this event. The
		-- landing time is this event's time; the flight closes once off the taxi (now, 1 s or 3 s later, or the bar's
		-- OnUpdate). Before, the flight stayed open and the next control event logged the time on the ground too.
		if not flight.started then return end
		flight.landed = GetTime()
		local function land()
			if flight and flight.landed and not (UnitOnTaxi and UnitOnTaxi("player")) then api.flightLanded() end
		end
		land()
		C_Timer.After(1, land)
		C_Timer.After(3, land)
	end
end
local function ourFlightText(button)
	local t, close = routeTime(button:GetID(), currentNode(), nodeName(button:GetID()))
	if not t then return nil end
	return (close and "Flight time: %s" or "Flight time: about %s"):format(api.statsClock and api.statsClock(t) or math.floor(t))
end
-- EllesmereUI's line in the shown tooltip: rewritten with ours. true when it was there.
local tipButton, tipText
local function rewriteElui()
	if not (tipButton and tipText and GameTooltip:IsShown()) then return false end
	if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= tipButton then tipButton = nil return false end
	local prefix = eluiPrefix()
	local name = GameTooltip.GetName and GameTooltip:GetName() or "GameTooltip"
	for i = 1, (GameTooltip.NumLines and GameTooltip:NumLines() or 0) do
		local fs = rawget(_G, name .. "TextLeft" .. i)
		local text = fs and fs.GetText and fs:GetText()
		if type(text) == "string" and not isSecret(text) and text:sub(1, #prefix) == prefix then
			if text ~= tipText then
				fs:SetText(tipText)
				fs:SetTextColor(0.6, 0.85, 1)
				GameTooltip:Show()
			end
			return true
		end
	end
	return false
end
local tipHooked = false
local function onNodeEnter(button)
	if not (opt("flightTimes") and button and button.GetID and GameTooltip:IsShown()) then return end
	-- 3.2 (user): flight map times only when RXPGuides is not installed (RestedXP shows its own there). With RestedXP's
	-- flight timers on, EllesmereUI's line (it has no switch) is blanked, so one time shows (user: "two flight times")
	local text
	if loaded("RXPGuides") then
		local rxp = rawget(_G, "RXP")
		local profile = type(rxp) == "table" and type(rxp.settings) == "table" and rxp.settings.profile
		if not (eluiMapTime() and type(profile) == "table" and profile.showFlightTimers) then return end
		text = ""
	else
		text = ourFlightText(button)
		if not text then return end
	end
	if not eluiMapTime() then
		GameTooltip:AddLine(text, 0.6, 0.85, 1)
		GameTooltip:Show()
		return
	end
	-- EllesmereUI adds its line in its own hook of the same function, before or after this one: rewrite it now if it is
	-- there, else when its GameTooltip:Show() comes; a route it has no line for gets ours a frame later
	tipButton, tipText = button, text
	if not tipHooked and hooksecurefunc then
		tipHooked = true
		hooksecurefunc(GameTooltip, "Show", function() if tipButton then pcall(rewriteElui) end end)
	end
	if rewriteElui() then return end
	C_Timer.After(0, function()
		if tipButton ~= button or not GameTooltip:IsShown() then return end
		if not rewriteElui() then
			tipButton = nil
			if text == "" then return end -- blanking only: EllesmereUI has no line for this route
			GameTooltip:AddLine(text, 0.6, 0.85, 1)
			GameTooltip:Show()
		end
	end)
end
api.flightTipEnter = onNodeEnter -- (tests)

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
local repaintQueued = false
ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	-- 3.2: learned flights and speeds before this were wrong (time on the ground counted): cleared once
	if db and not db.flightFix32 then
		db.flightLog, db.flightSpeed, db.flightPathSpeed, db.flightFix32 = nil, nil, nil, true
	end
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
			-- 3.1.1 speed: a burst of quest log and bag changes repaints the bags once, 0.2 s later
			if not repaintQueued then
				repaintQueued = true
				C_Timer.After(0.2, function() repaintQueued = false; hookBags(); repaintBags() end)
			end
		end
	end)
	onEvents({ "QUEST_COMPLETE", "GET_ITEM_INFO_RECEIVED", "QUEST_FINISHED" }, function(event)
		if event == "QUEST_FINISHED" then clearRewardMarks()
		elseif event == "QUEST_COMPLETE" or pendingReward then scheduleReward() end
	end)
	onEvents({ "MIRROR_TIMER_START", "MIRROR_TIMER_PAUSE", "MIRROR_TIMER_STOP" }, onMirror)
	onEvents({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "GOSSIP_SHOW" }, onFlightEvent)
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
	k.help("a quest sign on items that a quest in your log needs; a warning if you sell or delete one")
	k.heading("Rewards")
	k.check("Mark the best reward to sell", function() return db.rewardHint ~= false end,
		function(v) db.rewardHint = v and true or false; if v then checkClashes("rewardHint") end end)
	k.help("a gold coin on the reward choice that sells for the most. If OneForAll's coin is also on, you are asked which to keep")
	k.heading("Nearby quests")
	k.check("Card for a quest close by", function() return db.nearbyCard ~= false end,
		function(v) db.nearbyCard = v and true or false; if not v and card then card:Hide() end end,
		function() return api.questieLoaded and api.questieLoaded() end)
	k.help("needs Questie. A card at the top of the screen for a quest you can take within 70 yards; click it for a waypoint")
	k.check("Leave out breadcrumb quests you do not need", function() return db.breadcrumbHide ~= false end,
		function(v) db.breadcrumbHide = v and true or false end,
		function() return api.questieLoaded and api.questieLoaded() end)
	k.help("a breadcrumb only leads to another quest; hidden once you have done or picked up that quest")
	k.pageByKey.helpers.reset = k.reset

	k.page("world", "quests", "World")
	k.heading("Swimming")
	k.check("Breath warning", function() return db.breathWarn ~= false end,
		function(v) db.breathWarn = v and true or false; breathCheck() end)
	k.help("red pulsing screen edges when breath or fatigue has 10 seconds or less left")
	k.heading("Flights")
	k.check("Flight times", function() return db.flightTimes ~= false end,
		function(v) db.flightTimes = v and true or false; if not v and flightBar then flightBar:Hide() end; if v then checkClashes("flightTimes") end end)
	k.help("the time left while you fly, and on the flight map. Uses RXPGuides' flight times, else your own flights or the game's flight data. If EllesmereUI's Flight Timer is on, you are asked which to keep")
	k.check("Keep a flight log", function() return not db.flightHistoryOff end,
		function(v) db.flightHistoryOff = not v or nil end)
	k.help("saves your last 50 flights with our time, RestedXP's time and the real time; /ftp flights shows them to copy")
	k.pageByKey.world.reset = k.reset
end
