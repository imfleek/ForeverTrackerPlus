-- 3.1 On-screen quest help (Settings > Helpers > On screen). The ideas come from Questline (its quest item bar,
-- progress toasts and party announcements); the code is our own. Each part has its own switch:
--   db.itemBar        (on)  a bar with one button per usable quest item in the log (the item the game gives a quest,
--                           GetQuestLogSpecialItemInfo). The focused quest's item comes first. Shift+drag moves the
--                           bar (db.itemBarPos). Key Bindings > AddOns > ForeverTrackerPlus: "Use the first quest item"
--   db.toasts         (on)  quest progress in large letters in the upper middle of the screen ("Wolves slain: 3/8"),
--                           and "Ready to turn in" when a quest is done
--   db.toastsHideGame (on)  while the big messages are on: the game's small yellow quest progress line at the top
--                           ("Verdant Leaves: 11/12") is left out. UIErrorsFrame stops listening to UI_INFO_MESSAGE;
--                           our frame listens instead and hands every other info message to UIErrorsFrame's own
--                           OnEvent, so they show as before. Turning the option off gives the event back.
--   db.partyDone      (off) in a party: "[RXPFT] <quest> is ready to turn in" in party chat
--   db.partyChatSteps (off) in a party: each objective step in party chat (not db.partyProgress: that is the
--                           party progress in the quest tooltip, Party.lua)
-- CONSTRAINT: the item buttons are secure (SecureActionButtonTemplate, attribute type "item"); a secure button cannot be
-- made, moved, shown, hidden or changed in combat, so every bar change waits for PLAYER_REGEN_ENABLED. Objective texts
-- are checked with issecretvalue before use.
local ADDON, root = ...; local ns = root.tracker
local timed = root.timed or function(_, fn, ...) return fn(...) end -- /qt lag (Bootstrap.lua)
if ns.disabled then return end
local api = ns.api
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function opt(key) return db and db[key] ~= false end
local function optOn(key) return db and db[key] == true end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function onEvents(list, handler)
	local f = CreateFrame("Frame")
	for _, e in ipairs(list) do pcall(f.RegisterEvent, f, e) end
	f:SetScript("OnEvent", function(_, event, ...)
		local ok, err = pcall(handler, event, ...)
		if not ok then geterrorhandler()(err) end
	end)
	return f
end

-- every quest in the log: { id, title, index }
local function logQuests()
	local out = {}
	local count = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
		or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
	for i = 1, tonumber(count) or 0 do
		local info = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID and type(info.title) == "string" and not isSecret(info.title) then
			out[#out + 1] = { id = info.questID, title = info.title, index = i }
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Quest item bar
---------------------------------------------------------------------------------------------------------------------
local MAX_ITEMS = 8
local SIZE = 36
local bar, keyButton
local buttons = {}
local pending = false

local function questItems()
	local list = {}
	if type(GetQuestLogSpecialItemInfo) ~= "function" then return list end
	local focus = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	for _, q in ipairs(logQuests()) do
		local ok, link, icon, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, q.index)
		if ok and type(link) == "string" and not isSecret(link) then
			local itemID = tonumber(link:match("item:(%d+)"))
			local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.id)
			if itemID and (not complete or showWhenComplete) then
				list[#list + 1] = { quest = q.id, title = q.title, link = link, icon = icon, itemID = itemID,
					first = q.id == focus, order = #list + 1 }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.first ~= b.first then return a.first end
		return a.order < b.order
	end)
	return list
end

local function savePos()
	if not bar then return end
	local p, _, rp, x, y = bar:GetPoint(1)
	db.itemBarPos = { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }
end
local function placeBar()
	bar:ClearAllPoints()
	local pos = type(db.itemBarPos) == "table" and db.itemBarPos
	if pos and pos[1] then bar:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
	else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230) end
end

local function makeButton(i)
	local b = CreateFrame("Button", "RXPFTQuestItem" .. i, bar, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "item")
	b:SetAttribute("shift-type1", "rxpftnone") -- Shift+click: move the bar, do not use the item
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local kit = api.themeKit
	if kit then kit.border(b, { 0.55, 0.43, 0.18 }, 1, "OVERLAY") end
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.9, 0.6, 0.15)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function() if IsShiftKeyDown() and not inCombat() then bar:StartMoving() end end)
	b:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); savePos() end)
	b:SetScript("OnEnter", function(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(self.title or "", 1, 0.82, 0)
		GameTooltip:AddLine("Shift+drag: move the bar", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function buildBar()
	if bar then return end
	bar = CreateFrame("Frame", "RXPFTQuestItemBar", UIParent)
	bar:SetSize(SIZE, SIZE)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	placeBar()
	for i = 1, MAX_ITEMS do buttons[i] = makeButton(i) end
	-- the key binding clicks this hidden button; it always holds the bar's first item
	keyButton = CreateFrame("Button", "RXPFTQuestItemKey", UIParent, "SecureActionButtonTemplate")
	keyButton:RegisterForClicks("AnyUp", "AnyDown")
	keyButton:SetAttribute("type", "item")
	keyButton:SetSize(1, 1)
	keyButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	keyButton:Show()
end

local function itemCount(id)
	local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id))
	return tonumber(n) or 0
end
local function updateCooldowns()
	if not bar then return end
	local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	for _, b in ipairs(buttons) do
		if b:IsShown() and b.itemID then
			local count = itemCount(b.itemID)
			b.count:SetText(count > 1 and tostring(count) or "")
			if getCD then
				local ok, start, duration, enable = pcall(getCD, b.itemID)
				if ok and start and duration and duration > 0 and enable ~= 0 then b.cd:SetCooldown(start, duration)
				else b.cd:Clear() end
			end
		end
	end
end

local function refreshBar()
	if inCombat() then pending = true return end
	pending = false
	local list = opt("itemBar") and questItems() or {}
	if #list == 0 and not bar then return end
	buildBar()
	local shown = 0
	for i, b in ipairs(buttons) do
		local e = list[i]
		if e then
			-- 3.1.1 speed: a button whose item did not change is left as it is
			if b.itemID ~= e.itemID or not b:IsShown() then
				b:SetAttribute("item", "item:" .. e.itemID)
				b.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				if not b.placed then
					b.placed = true
					b:ClearAllPoints()
					b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (SIZE + 4), 0)
				end
				b:Show()
			end
			b.link, b.title, b.itemID = e.link, e.title, e.itemID
			shown = i
		elseif b.itemID or b:IsShown() then
			b.link, b.itemID = nil, nil
			b:SetAttribute("item", nil)
			b:Hide()
		end
	end
	local first = list[1] and ("item:" .. list[1].itemID) or nil
	if keyButton.rxpftItem ~= first then keyButton.rxpftItem = first; keyButton:SetAttribute("item", first) end
	if bar.shownCount ~= shown then
		bar.shownCount = shown
		bar:SetWidth(math.max(shown * (SIZE + 4) - 4, SIZE))
		bar:SetShown(shown > 0)
	end
	updateCooldowns()
end
api.refreshItemBar = refreshBar
function api.resetItemBar()
	db.itemBarPos = nil
	if bar and not inCombat() then placeBar() end
end

---------------------------------------------------------------------------------------------------------------------
-- Progress toasts and party messages
---------------------------------------------------------------------------------------------------------------------
local toast
local seen -- [questID] = { [objective index] = text, done = bool }; nil until the first scan
local function buildToast()
	if toast then return toast end
	toast = CreateFrame("Frame", nil, UIParent)
	toast:SetSize(600, 60)
	toast:SetPoint("TOP", UIParent, "TOP", 0, -150)
	toast:SetFrameStrata("HIGH")
	toast.main = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	toast.main:SetPoint("TOP")
	toast.main:SetShadowOffset(2, -2)
	toast.sub = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toast.sub:SetPoint("TOP", toast.main, "BOTTOM", 0, -4)
	toast.sub:SetTextColor(0.85, 0.8, 0.7)
	local anim = toast:CreateAnimationGroup()
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.2); fadeIn:SetOrder(1)
	local hold = anim:CreateAnimation("Alpha")
	hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(2.2); hold:SetOrder(2)
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.6); fadeOut:SetOrder(3)
	anim:SetScript("OnFinished", function() toast:Hide() end)
	toast.anim = anim
	toast:Hide()
	return toast
end
local function showToast(main, sub, done)
	local t = buildToast()
	t.main:SetText(main)
	if done then t.main:SetTextColor(0.45, 0.95, 0.45) else t.main:SetTextColor(1, 0.82, 0.25) end
	t.sub:SetText(sub or "")
	t.anim:Stop()
	t:SetAlpha(1)
	t:Show()
	t.anim:Play()
end
api.questToast = showToast

local lastParty = 0
local function party(text)
	if not (IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid())) then return end
	if type(SendChatMessage) ~= "function" then return end
	if GetTime() - lastParty < 1 then
		C_Timer.After(1.1, function() party(text) end)
		return
	end
	lastParty = GetTime()
	pcall(SendChatMessage, "[RXPFT] " .. text, "PARTY")
end

local function objectives(q)
	local out = {}
	if not (GetNumQuestLeaderBoards and GetQuestLogLeaderBoard) then return out end
	for j = 1, GetNumQuestLeaderBoards(q.index) or 0 do
		local text, _, finished = GetQuestLogLeaderBoard(j, q.index)
		if type(text) == "string" and not isSecret(text) then out[j] = { text = text, finished = finished and true or false } end
	end
	return out
end

local function scanProgress()
	-- 3.1.1 speed: nothing to say: no reading of every quest's steps (the next scan starts fresh)
	if not (opt("toasts") or optOn("partyChatSteps") or optOn("partyDone")) then seen = nil return end
	local first = seen == nil
	local now = {}
	for _, q in ipairs(logQuests()) do
		local objs = objectives(q)
		local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.id) and true or false
		local rec = { done = complete }
		for j, o in ipairs(objs) do rec[j] = o.text end
		now[q.id] = rec
		local old = not first and seen[q.id]
		if old then
			for j, o in ipairs(objs) do
				if old[j] and old[j] ~= o.text and (o.text:find("%d") or o.finished) then
					if opt("toasts") and not complete then showToast(o.text, q.title, o.finished) end
					if optOn("partyChatSteps") then party(q.title .. ": " .. o.text) end
				end
			end
			if complete and not old.done then
				if opt("toasts") then showToast("Ready to turn in", q.title, true) end
				if optOn("partyDone") then party(q.title .. " is ready to turn in") end
			end
		end
	end
	seen = now
end

---------------------------------------------------------------------------------------------------------------------
-- The game's small yellow progress line
---------------------------------------------------------------------------------------------------------------------
-- a game format string ("%s slain: %d/%d") as a Lua pattern
local function formatPattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local pat = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	pat = pat:gsub("%%%%%d?%$?s", ".+"):gsub("%%%%%d?%$?d", "%%d+")
	return "^" .. pat .. "$"
end
local progressPatterns
local function isQuestProgress(msg)
	if type(msg) ~= "string" or isSecret(msg) then return false end
	if not progressPatterns then
		progressPatterns = { "^.+: %d+/%d+$" }
		for _, name in ipairs({ "ERR_QUEST_ADD_KILL_SII", "ERR_QUEST_ADD_ITEM_SII", "ERR_QUEST_ADD_FOUND_SII",
			"ERR_QUEST_ADD_PLAYER_KILL_SII", "ERR_QUEST_OBJECTIVE_COMPLETE_S", "ERR_QUEST_UNKNOWN_COMPLETE" }) do
			local pat = formatPattern(rawget(_G, name))
			if pat then progressPatterns[#progressPatterns + 1] = pat end
		end
	end
	for _, pat in ipairs(progressPatterns) do if msg:find(pat) then return true end end
	return false
end
api.isQuestProgressMessage = isQuestProgress

local relay, takenOver = nil, false
local function onInfo(_, event, ...)
	local messageType, message = ...
	if type(messageType) == "string" and message == nil then message = messageType end -- older payload: the text only
	if opt("toasts") and opt("toastsHideGame") and isQuestProgress(message) then return end
	local handler = UIErrorsFrame and UIErrorsFrame.GetScript and UIErrorsFrame:GetScript("OnEvent")
	if handler then
		local ok, err = pcall(handler, UIErrorsFrame, event, ...)
		if not ok then geterrorhandler()(err) end
	end
end
local function applyHideGame()
	local want = opt("toasts") and opt("toastsHideGame")
	if not (UIErrorsFrame and UIErrorsFrame.UnregisterEvent) or want == takenOver then return end
	if want then
		if not (UIErrorsFrame.IsEventRegistered and UIErrorsFrame:IsEventRegistered("UI_INFO_MESSAGE")) then return end
		relay = relay or CreateFrame("Frame")
		if not pcall(relay.RegisterEvent, relay, "UI_INFO_MESSAGE") then return end
		relay:SetScript("OnEvent", onInfo)
		UIErrorsFrame:UnregisterEvent("UI_INFO_MESSAGE")
		takenOver = true
	else
		relay:UnregisterEvent("UI_INFO_MESSAGE")
		UIErrorsFrame:RegisterEvent("UI_INFO_MESSAGE")
		takenOver = false
	end
end
api.applyToastsHideGame = applyHideGame

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	applyHideGame()
	local scanQueued, barQueued = false, false
	onEvents({ "QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "SUPER_TRACKING_CHANGED",
		"BAG_UPDATE_COOLDOWN", "PLAYER_ENTERING_WORLD" }, function(event)
		if event == "BAG_UPDATE_COOLDOWN" then updateCooldowns() return end
		if event == "PLAYER_REGEN_ENABLED" and not pending then return end
		if event == "QUEST_LOG_UPDATE" and not scanQueued then
			scanQueued = true
			C_Timer.After(0.2, function() scanQueued = false; pcall(timed, "progress check", scanProgress) end)
		end
		-- 3.1.1 speed: a burst of quest log and bag changes rebuilds the bar once, 0.2 s later
		if event == "QUEST_LOG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
			if inCombat() then pending = true return end -- rebuilt once combat ends
			if not barQueued then
				barQueued = true
				C_Timer.After(0.2, function() barQueued = false; timed("quest item bar", refreshBar) end)
			end
			return
		end
		refreshBar()
	end)
	C_Timer.After(2, function() pcall(scanProgress); refreshBar() end)
end

-- the key binding's names (Bindings.xml)
_G.BINDING_HEADER_RXPFTRACKER = "ForeverTrackerPlus"
_G["BINDING_NAME_CLICK RXPFTQuestItemKey:LeftButton"] = "Use the first quest item"

---------------------------------------------------------------------------------------------------------------------
-- Settings > Helpers > On screen (declared by Config.lua: api.declareScreenPage(kit))
---------------------------------------------------------------------------------------------------------------------
function api.declareScreenPage(k)
	k.page("onscreen", "quests", "On screen")
	k.heading("Quest items")
	k.check("Quest item bar", function() return db.itemBar ~= false end,
		function(v) db.itemBar = v and true or false; refreshBar() end)
	k.help("one button per usable quest item; Shift+drag to move. Set a key: Key Bindings > AddOns")
	k.buttons("Reset the bar's position", {
		{ "Reset the bar's position", function() api.resetItemBar() end, 200 },
	})
	k.heading("Progress")
	k.check("Big progress messages", function() return db.toasts ~= false end,
		function(v) db.toasts = v and true or false; applyHideGame() end)
	k.help("quest progress in large letters at the top of the screen, like \"Wolves slain: 3/8\"")
	k.check("Hide the game's small yellow progress text", function() return db.toastsHideGame ~= false end,
		function(v) db.toastsHideGame = v and true or false; applyHideGame() end,
		function() return db.toasts ~= false end)
	k.help("only the quest progress line; other yellow messages still show")
	k.buttons("Show an example", {
		{ "Show an example", function() showToast("Wolves slain: 3/8", "An example quest") end, 160 },
	})
	k.heading("World marker")
	k.check("Marker in the world", function() return db.worldMarker ~= false end,
		function(v) db.worldMarker = v and true or false; if api.refreshWorldMarker then api.refreshWorldMarker() end end)
	k.help("over your tracked quest's spot in the world: its name, next step, distance and a light beam")
	k.check("Hide the marker in combat", function() return db.markerCombatHide ~= false end,
		function(v) db.markerCombatHide = v and true or false; if api.refreshWorldMarker then api.refreshWorldMarker() end end)
	k.help("keeps your screen clear while you fight")
	k.check("Track the nearest quest by itself", function() return db.markerAuto == true end,
		function(v) db.markerAuto = v and true or false end)
	k.help("a quest you pick yourself, or a map waypoint, is kept until it is done")
	k.heading("Party chat", true)
	k.check("Say in party chat when a quest is done", function() return db.partyDone == true end,
		function(v) db.partyDone = v and true or false end)
	k.help("\"[RXPFT] <quest> is ready to turn in\", only in a party (not a raid)")
	k.check("Say each quest step in party chat", function() return db.partyChatSteps == true end,
		function(v) db.partyChatSteps = v and true or false end)
	k.help("every objective step, like \"Wolves slain: 3/8\"; this can be a lot of chat")
	k.pageByKey.onscreen.reset = k.reset
end
