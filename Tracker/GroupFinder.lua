-- R106-95: Ctrl+left-click a quest in the quest tracker: look for players for it (user's references).
--   1. A message in the General channel: "LFM [quest link] - whisper 'inv' to join." For 15 minutes after it, a
--      whisper of just "inv" gets an invite (until the group is full).
--   2. A listing in Looking For Group, under the quest's dungeon or raid, its zone (Quests & Zones) or its
--      battleground: the activity named as the quest's quest-log header. With none of these: Custom.
--      Roles: the ones picked in Looking For Group, else DPS. No comment: an addon may not write it (the game
--      blocks the listing then; R106-105; R106-123 tries it again with Blizzard's button). R106-122: Blizzard's Group Finder opens with the activity picked; its own
--      "List Group" button lists (the game blocks the addon's listing from the prompt).
--   3. Two lines in the chat frame for you: "Recruitment posted to General." and "Searching for players for [quest]."
--   R106-104: a prompt first asks which: "LFM in chat" (1), "List in LFG" (2) or "Both".
-- Quest list > "Ctrl+click a quest: find a group" (db.questGroupFinder, on by default).
--
-- Sending to General and creating a listing need a real mouse click: both run straight from the click (the quest
-- block's OnMouseUp, Extras.lua), never from a timer. In a group, only its leader can do this.
-- Blizzard's own left-click opens the quest on the map; a Ctrl+left-click closes the map again when it was closed.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local PREFIX = "|cff33ccffForeverTrackerPlus:|r "
local INVITE_WINDOW = 15 * 60 -- seconds the "inv" whispers are answered
local MAX_PARTY = 5

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function say(text)
	local frame = DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then frame:AddMessage(PREFIX .. text) end
end
local function enabled() return db and db.questGroupFinder ~= false end
api.questGroupFinderOn = enabled

-- the quest ----------------------------------------------------------------------------------------------------------
local function questTitle(id)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if type(title) == "string" and not isSecret(title) and title ~= "" then return title end
	return nil
end
local function questLink(id, title)
	local link = GetQuestLink and GetQuestLink(id)
	if type(link) == "string" and not isSecret(link) and link ~= "" then return link end
	return title and ("[" .. title .. "]") or nil
end
-- the quest-log header above the quest: its zone, dungeon, raid or battleground
local function questHeader(id)
	local log = C_QuestLog
	if not (log and log.GetLogIndexForQuestID and log.GetInfo) then return nil end
	local index = log.GetLogIndexForQuestID(id)
	if type(index) ~= "number" then return nil end
	for i = index, 1, -1 do
		local info = log.GetInfo(i)
		if type(info) == "table" and info.isHeader then
			local title = info.title
			return type(title) == "string" and not isSecret(title) and title or nil
		end
	end
	return nil
end
api.questLogHeader = questHeader

-- the General channel ------------------------------------------------------------------------------------------------
local function generalChannel()
	local want = string.lower(_G.GENERAL or "General")
	if not GetChannelList then return nil end
	local list = { GetChannelList() } -- number, name, disabled; number, name, disabled; ...
	for i = 1, #list, 3 do
		local number, name = list[i], list[i + 1]
		if type(number) == "number" and type(name) == "string" and string.lower(name):find(want, 1, true) == 1 then
			return number
		end
	end
	return nil
end
local function send(text, number)
	local sendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if not sendChat then return false end
	return pcall(sendChat, text, "CHANNEL", nil, number)
end

-- Looking For Group --------------------------------------------------------------------------------------------------
local function norm(s)
	if type(s) ~= "string" then return "" end
	return (s:lower():gsub("^the ", ""):gsub("[^%w]", ""))
end
local function activities(categoryID)
	local lfg = C_LFGList
	if not (lfg and lfg.GetAvailableActivities) then return {} end
	local ok, ids = pcall(lfg.GetAvailableActivities, categoryID)
	return ok and type(ids) == "table" and ids or {}
end
local function activityInfo(id)
	local lfg = C_LFGList
	if not (lfg and lfg.GetActivityInfoTable) then return nil end
	local ok, info = pcall(lfg.GetActivityInfoTable, id)
	return ok and type(info) == "table" and info or nil
end
local function categoryName(id)
	local lfg = C_LFGList
	if not (lfg and lfg.GetLfgCategoryInfo and id) then return nil end
	local ok, info = pcall(lfg.GetLfgCategoryInfo, id)
	return ok and type(info) == "table" and type(info.name) == "string" and info.name or nil
end
-- the activity named as the quest's header (dungeon, raid, zone or battleground): an exact name first, then one name
-- inside the other ("The Stockade" / "Stormwind Stockade"); one the player's level fits first
local function activityFor(header)
	local wanted = norm(header)
	if wanted == "" then return nil end
	local level = UnitLevel and UnitLevel("player") or 0
	local best, bestScore
	for _, aid in ipairs(activities()) do
		local info = activityInfo(aid)
		if info then
			local score
			for _, n in ipairs({ norm(info.fullName), norm(info.shortName) }) do
				if n ~= "" then
					if n == wanted then score = math.max(score or 0, 2)
					elseif #wanted >= 5 and (n:find(wanted, 1, true) or wanted:find(n, 1, true)) then score = math.max(score or 0, 1) end
				end
			end
			if score then
				if (tonumber(info.minLevel) or 0) <= level then score = score + 0.5 end
				if not bestScore or score > bestScore then best, bestScore = aid, score end
			end
		end
	end
	return best
end
-- Custom: the first activity of the category named "Custom"
local function customActivity()
	local want = norm(_G.CUSTOM or "Custom")
	local seen = {}
	for _, aid in ipairs(activities()) do
		local info = activityInfo(aid)
		local cat = info and info.categoryID
		if cat and not seen[cat] then
			seen[cat] = true
			if norm(categoryName(cat)) == want then return aid end
		end
	end
	return nil
end

local function ensureRoles()
	local roles = C_LFGListRoles
	if not (roles and roles.GetRoles) then return end
	local ok, picked = pcall(roles.GetRoles)
	if ok and type(picked) == "table" and (picked.tank or picked.healer or picked.dps) then return end
	if roles.SetRoles then pcall(roles.SetRoles, { tank = false, healer = false, dps = true }) end
end

-- R106-105: the "More details about your group (optional)" box is left alone: text an addon puts there marks the
-- listing as the addon's, and the game then blocks C_LFGList.CreateListing (ADDON_ACTION_BLOCKED, user's error; it
-- listed fine before the text was set). The quest's name goes in the General message instead.
-- R106-122: the game also blocks CreateListing from the prompt's own button (ADDON_ACTION_BLOCKED at the call, user's
-- error; it listed from the quest block's click before the prompt). So the addon does not list: it opens Blizzard's
-- Group Finder at "Start a Group" with the activity picked, and Blizzard's own "List Group" button lists it.
-- R106-123: the quest's title goes in its "More details" box (a test: R106-105).
local pending -- the listing asked for: { name = what it is listed under }
-- R106-124: Forever's Looking For Group window is the "Vanilla style" one (Blizzard_GroupFinder_VanillaStyle:
-- LFGParentFrame, its Listing tab LFGListingFrame, its "List Group" button calls LFGListingFrame:CreateOrUpdateListing);
-- R106-122's retail window (LFGListFrame.EntryCreation) is not there (user: it "did not open the LFG window").
-- The retail one stays as a fallback.
local function vanilla()
	if not _G.LFGListingFrame and C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_GroupFinder_VanillaStyle")
	end
	local lf = _G.LFGListingFrame
	if lf and lf.SetCategorySelection and lf.SetActivity and _G.LFGVanilla_ShowFrame then return lf end
	return nil
end
local function retail()
	if not _G.LFGListFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_GroupFinder") end
	local lf = _G.LFGListFrame
	if lf and lf.EntryCreation and _G.PVEFrame_ShowFrame and _G.LFGListEntryCreation_Show
		and _G.LFGListEntryCreation_Select then return lf end
	return nil
end
-- R106-123: the quest's title in "More details" (user: "Try it"; R106-105 saw the game block the addon's own listing
-- with text there; with Blizzard's button listing it is a test)
-- R106-125: written again on the next frame (the window may still be setting itself up); when the box still does not
-- hold it, the game did not allow it, and the player is told (user: the box stayed empty)
local function writeComment(box, title)
	local edit = box and (box.EditBox or box)
	if not (title and edit and edit.SetText) then return end
	edit:SetText(title)
	if not (C_Timer and C_Timer.After) then return end
	C_Timer.After(0, function()
		if edit.GetText and edit:GetText() ~= title then pcall(edit.SetText, edit, title) end
		if edit.GetText and edit:GetText() ~= title then
			say("the game did not allow the quest's name in the More details box: type it there yourself if you want it.")
		end
	end)
end
-- R106-125: playstyle Relaxed in the Vanilla-style window (user), as a pick in its dropdown
local function pickRelaxed(view)
	local relaxed = Enum and Enum.LFGEntryGeneralPlaystyle and Enum.LFGEntryGeneralPlaystyle.FunRelaxed
	if not (view and relaxed) then return end
	if _G.LFGListingActivityView_OnPlayStyleSelectedInternal then
		_G.LFGListingActivityView_OnPlayStyleSelectedInternal(view, relaxed)
	else
		view.generalPlaystyle = relaxed
	end
	local dd = view.PlayStyleDropdown
	if dd and dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end
end
local function list(title, header)
	local lfg = C_LFGList
	if not lfg then return end
	local van, ret = vanilla(), nil
	if not van then ret = retail() end
	if not (van or ret) then say("the Looking For Group window was not found.") return end
	-- already listed: the game blocks an addon's UpdateListing (R106-106); the window shows that listing
	if lfg.HasActiveEntryInfo and lfg.HasActiveEntryInfo() then
		if van then pcall(_G.LFGVanilla_ShowFrame, _G.LFGPARENT_LISTING_TAB_INDEX or 1)
		elseif _G.LFGListUtil_OpenBestWindow then pcall(_G.LFGListUtil_OpenBestWindow) end
		say("you are already listed in Looking For Group. Change or remove that listing in its window first.")
		return
	end
	local aid = activityFor(header) or customActivity()
	if not aid then say("no fitting Looking For Group activity was found.") return end
	local info = activityInfo(aid)
	if not (info and info.categoryID) then say("no fitting Looking For Group activity was found.") return end
	ensureRoles()
	local ok, err = pcall(function()
		if van then
			_G.LFGVanilla_ShowFrame(_G.LFGPARENT_LISTING_TAB_INDEX or 1)
			van:SetCategorySelection(info.categoryID) -- clears the activities: the one is picked after it
			van:SetActivity(aid, true, true, true) -- as a click on it: the listing is marked changed (dirty)
			local view = van.ActivityView
			-- R106-125: the list redrawn, so its check box shows the pick (it reads the picks only when drawn)
			if view and _G.LFGListingActivityView_UpdateActivities then
				pcall(_G.LFGListingActivityView_UpdateActivities, view)
			end
			pickRelaxed(view)
			writeComment(view and view.Comment or _G.LFGListingComment, title)
		else
			_G.PVEFrame_ShowFrame("GroupFinderFrame", _G.LFGListPVEStub)
			local ec = ret.EntryCreation
			_G.LFGListEntryCreation_Show(ec, ret.baseFilters, info.categoryID, info.filters)
			_G.LFGListEntryCreation_Select(ec, info.filters, info.categoryID, info.groupFinderActivityGroupID, aid)
			writeComment(ec.Description, title) -- after Show, which clears it
		end
	end)
	if not ok then
		say("could not open the Looking For Group window (" .. tostring(err) .. ").")
		return
	end
	pending = { name = info.fullName or header or title }
	say(("Looking For Group is open for %s. Click its List Group button to list."):format(tostring(pending.name)))
end

-- invites --------------------------------------------------------------------------------------------------------------
local recruitUntil = 0
local function groupFull()
	if IsInRaid and IsInRaid() then return true end
	return ((GetNumGroupMembers and GetNumGroupMembers()) or 0) >= MAX_PARTY
end
local function invite(name)
	local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	if fn then pcall(fn, name) end
end

-- the post ---------------------------------------------------------------------------------------------------------------
-- how: "chat" (LFM in General), "lfg" (a Looking For Group listing) or "both"; run from a real click (the prompt's
-- buttons), as sending to a channel and listing need one
function api.postGroupForQuest(id, how)
	if type(id) ~= "number" then return end
	local title = questTitle(id)
	if not title then return end
	local link = questLink(id, title)
	if how == "chat" or how == "both" then
		local number = generalChannel()
		if number and send(("LFM %s - whisper 'inv' to join."):format(link), number) then
			say("Recruitment posted to General.")
			recruitUntil = GetTime() + INVITE_WINDOW
		else
			say("the General channel was not found: nothing posted.")
		end
	end
	if how == "lfg" or how == "both" then list(title, questHeader(id)) end
	say(("Searching for players for %s."):format(link))
end

-- R106-104: the prompt: post LFM in chat, list in Looking For Group, or both (user)
local prompt
local function buildPrompt()
	if prompt then return prompt end
	local f = CreateFrame("Frame", "ForeverTrackerPlusGroupPrompt", UIParent, "BackdropTemplate")
	f:SetSize(300, 96)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	end
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.text:SetPoint("TOP", f, "TOP", 0, -16)
	f.text:SetWidth(270)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.buttons = {}
	for i, b in ipairs({ { "chat", "LFM in chat" }, { "lfg", "List in LFG" }, { "both", "Both" } }) do
		local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		btn:SetSize(86, 24)
		btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14 + (i - 1) * 92, 14)
		btn:SetText(b[2])
		btn.how = b[1]
		-- R106-124: the post runs first, the prompt hides after it (user: "LFM in chat" was blocked too, with the
		-- prompt hidden before the post)
		btn:SetScript("OnClick", function(self)
			api.postGroupForQuest(f.questID, self.how)
			f:Hide()
		end)
		f.buttons[b[1]] = btn
	end
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ForeverTrackerPlusGroupPrompt") end
	f:Hide()
	prompt = f
	return f
end

-- the click ------------------------------------------------------------------------------------------------------------
local lastAsked = 0
function api.findGroupForQuest(id)
	if not enabled() or type(id) ~= "number" or isSecret(id) then return end
	if GetTime() - lastAsked < 1 then return end -- the block and its header button both heard the click
	lastAsked = GetTime()
	if IsInGroup and IsInGroup() and not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then
		say("only the group leader can look for more players.")
		return
	end
	if groupFull() then say("your group is already full.") return end
	local title = questTitle(id)
	if not title then return end
	local f = buildPrompt()
	f.questID = id
	f.text:SetText(("Find a group for %s:"):format(questLink(id, title)))
	f:Show()
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local frame = CreateFrame("Frame")
	for _, e in ipairs({ "CHAT_MSG_WHISPER", "LFG_LIST_ACTIVE_ENTRY_UPDATE", "ADDON_ACTION_BLOCKED",
		"ADDON_ACTION_FORBIDDEN" }) do
		pcall(frame.RegisterEvent, frame, e)
	end
	frame:SetScript("OnEvent", function(_, event, a1, a2)
		if event == "CHAT_MSG_WHISPER" then
			if GetTime() > recruitUntil or isSecret(a1) or isSecret(a2) or type(a1) ~= "string" then return end
			if a1:lower():match("^%s*(.-)%s*$") ~= "inv" or type(a2) ~= "string" then return end
			if groupFull() then recruitUntil = 0 return end
			invite(a2)
		elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
			if pending then
				say(("Listed in Looking For Group: %s."):format(tostring(pending.name)))
				pending = nil
			end
		elseif a1 == ADDON and pending then
			pending = nil
			say("the game did not allow the Looking For Group listing. Use the Looking For Group window.")
		end
	end)
end
