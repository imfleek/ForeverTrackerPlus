-- Clicks on a quest row of our own tracker (Tracker/Own/Rows.lua): left opens the quest log; Ctrl+left looks for a
-- group (GroupFinder.lua); right opens the quest's menu (Blizzard's lines: Focus, Stop tracking, Open in quest log,
-- Show on map, Share quest, Abandon quest, which asks first); Ctrl+right puts its reward links in the chat box.
-- 3.2 (user: "Delete the old tracker's code"): the click part of MoreQuests.lua (its More quests list was removed).
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

local function openQuest(id)
	if QuestMapFrame_OpenToQuestDetails then
		pcall(QuestMapFrame_OpenToQuestDetails, id)
	elseif ToggleQuestLog then
		pcall(ToggleQuestLog)
	end
end

-- R106-128: the right-click menu of a tracked quest, made here (the game makes it only for its own quest blocks). It
-- carries the same tag, MENU_QUEST_OBJECTIVE_TRACKER, so lines other code adds to that menu (QuestMenu.lua: Wowhead
-- URL) show here too. The same lines as Blizzard's tracker menu (user: "missing blizzard's normal options like share
-- quest, abandon quest"): the quest's title, Focus / Stop focusing, Stop tracking (a watched quest), Open in quest log,
-- Show on map, Share quest (in a group, when the quest can be shared), Abandon quest (when it can be abandoned).
-- CONSTRAINT: "Abandon quest" asks in our own box (askAbandon), not the game's StaticPopup: a StaticPopup shown from
-- addon code is tainted and can break later popups. Abandoned the way RestedXP does (select, SetAbandonQuest,
-- AbandonQuest), as the Orphaned quests page (Objectives/Settings.lua).
local function questTitle(id)
	local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if type(t) ~= "string" or isSecret(t) or t == "" then return nil end
	return t
end
local function abandonQuest(id)
	if not (C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)) then return false end
	local setAbandon = (C_QuestLog.SetAbandonQuest) or _G.SetAbandonQuest
	local abandon = (C_QuestLog.AbandonQuest) or _G.AbandonQuest
	if not (C_QuestLog.SetSelectedQuest and setAbandon and abandon) then return false end
	C_QuestLog.SetSelectedQuest(id)
	setAbandon()
	abandon()
	return true
end
api.abandonQuestNow = abandonQuest -- for tests
local confirmBox
local function askAbandon(id)
	if not confirmBox then
		local f = CreateFrame("Frame", "ForeverTrackerPlusAbandonConfirm", UIParent, "BackdropTemplate")
		f:SetSize(320, 96)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(true)
		if f.SetBackdrop then
			f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		end
		f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		f.text:SetPoint("TOP", 0, -20)
		f.text:SetWidth(280)
		local yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		yes:SetSize(110, 22)
		yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
		yes:SetText(ACCEPT or "Accept")
		yes:SetScript("OnClick", function() if f.questID then abandonQuest(f.questID) end; f:Hide() end)
		local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		no:SetSize(110, 22)
		no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
		no:SetText(CANCEL or "Cancel")
		no:SetScript("OnClick", function() f:Hide() end)
		-- Escape closes it (the game's list of frames Escape closes; no keyboard capture of our own)
		if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ForeverTrackerPlusAbandonConfirm") end
		f:Hide()
		confirmBox = f
	end
	confirmBox.questID = id
	confirmBox.text:SetText(("Abandon \"%s\"?"):format(questTitle(id) or ("Quest " .. id)))
	confirmBox:Show()
end
api.askAbandonQuest = askAbandon
local function shareQuest(id)
	if not (C_QuestLog.SetSelectedQuest and QuestLogPushQuest) then return end
	local old = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
	C_QuestLog.SetSelectedQuest(id)
	pcall(QuestLogPushQuest)
	if old then C_QuestLog.SetSelectedQuest(old) end
end
local function showMenu(owner, id)
	local MU = _G.MenuUtil
	if not (MU and MU.CreateContextMenu) then return end
	MU.CreateContextMenu(owner, function(_, root)
		if root.SetTag then root:SetTag("MENU_QUEST_OBJECTIVE_TRACKER") end
		local title = questTitle(id)
		if title and root.CreateTitle then root:CreateTitle(title) end
		local ST = C_SuperTrack
		if ST and ST.SetSuperTrackedQuestID then
			local focused = ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() == id
			root:CreateButton(focused and "Stop focusing" or "Focus", function()
				pcall(ST.SetSuperTrackedQuestID, focused and 0 or id)
			end)
		end
		local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil
		if watched and C_QuestLog.RemoveQuestWatch then
			root:CreateButton(OBJECTIVES_STOP_TRACKING or "Stop tracking", function() pcall(C_QuestLog.RemoveQuestWatch, id) end)
		end
		root:CreateButton("Open in quest log", function() openQuest(id) end)
		if _G.WorldMapFrame and C_Map and C_Map.GetBestMapForUnit then
			root:CreateButton("Show on map", function()
				local mapID = GetQuestUiMapID and GetQuestUiMapID(id)
				if type(mapID) ~= "number" or mapID == 0 then mapID = C_Map.GetBestMapForUnit("player") end
				if OpenWorldMap then pcall(OpenWorldMap, mapID) elseif ToggleWorldMap then pcall(ToggleWorldMap) end
			end)
		end
		local grouped = IsInGroup and IsInGroup()
		local pushable = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(id)
		if grouped and pushable then root:CreateButton(SHARE_QUEST or "Share quest", function() shareQuest(id) end) end
		local canAbandon = true
		if C_QuestLog.CanAbandonQuest then canAbandon = C_QuestLog.CanAbandonQuest(id) and true or false end
		if canAbandon then root:CreateButton(ABANDON_QUEST or "Abandon quest", function() askAbandon(id) end) end
	end)
end
api.questMenu = showMenu

-- R106-128: clicks on our tracked quests (Own/Rows.lua): left opens the quest log; Ctrl+left looks for a group
-- (GroupFinder.lua); right opens the quest's menu; Ctrl+right puts its reward links in the chat box
local function onClick(self, button)
	local id = self.questID
	if not id then return end
	local ctrl = IsControlKeyDown and IsControlKeyDown()
	if button == "RightButton" then
		if ctrl then
			if api.linkQuestRewards then pcall(api.linkQuestRewards, id) end
		else
			showMenu(self, id)
		end
		return
	end
	if ctrl and api.findGroupForQuest and api.questGroupFinderOn and api.questGroupFinderOn() then
		pcall(api.findGroupForQuest, id)
		return
	end
	openQuest(id)
end
api.questClick = onClick

local function itemFor(questID)
	if type(GetQuestLogSpecialItemInfo) ~= "function" then return nil end
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	if not index then return nil end
	local ok, link, icon, _, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, index)
	if not ok or type(link) ~= "string" or isSecret(link) then return nil end
	local itemID = tonumber(link:match("item:(%d+)"))
	if not itemID then return nil end
	if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) and not showWhenComplete then return nil end
	return { itemID = itemID, link = link, icon = icon }
end
api.questItemFor = itemFor
