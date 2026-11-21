-- R106-85: "Wowhead URL" in the quest tracker's right-click menu (user's reference: a green "Wowhead URL" line in the
-- quest's menu). It opens a small box with the quest's Wowhead link already selected; Ctrl+C copies it and the box
-- closes by itself (Escape or the X close it too).
--
-- The menu is Blizzard's (Menu.ModifyMenu with its tag MENU_QUEST_OBJECTIVE_TRACKER). The menu does not say which quest
-- it is for, so the quest is the block the mouse went down on (Extras.lua records it, api.lastQuestPressed), else the
-- quest block under the mouse (a block knows its section, parentModule, and its quest, id).
-- The link: WoW Forever's own pages on Wowhead, https://www.wowhead.com/forever/quest=<id>.
-- The box is the addon's own frame, not a StaticPopup (an addon's StaticPopup can taint the game's popups).
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api

local URL = "https://www.wowhead.com/forever/quest=%d"
local GREEN = "|cff1eff00"

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function questNumber(v)
	if isSecret(v) or type(v) ~= "number" or v <= 0 or v % 1 ~= 0 then return nil end
	return v
end

function api.wowheadQuestURL(id)
	id = questNumber(id)
	return id and URL:format(id) or nil
end

-- the quest the menu is for
local function menuQuest()
	local pressed = api.lastQuestPressed
	if type(pressed) == "table" and pressed.at and GetTime() - pressed.at < 2 then
		local id = questNumber(pressed.id)
		if id then return id end
	end
	if not GetMouseFoci then return nil end
	for _, focus in ipairs(GetMouseFoci()) do
		local frame = focus
		while frame do
			if frame.IsForbidden and frame:IsForbidden() then break end
			if frame.parentModule then
				local id = questNumber(frame.id)
				if id then return id end
			end
			frame = frame.GetParent and frame:GetParent()
		end
	end
end

-- the copy box ------------------------------------------------------------------------------------------------------
local box
local function createBox()
	box = CreateFrame("Frame", "RXPForeverTrackerCopyURL", UIParent, "BackdropTemplate")
	box:SetSize(360, 92)
	box:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	box:SetFrameStrata("DIALOG")
	box:SetToplevel(true)
	box:EnableMouse(true)
	box:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	box:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
	box:SetBackdropBorderColor(0.75, 0.61, 0.3, 1)
	box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	box.title:SetPoint("TOPLEFT", 14, -12)
	box.title:SetText("Wowhead URL")
	box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.hint:SetPoint("BOTTOMLEFT", 14, 12)
	box.hint:SetTextColor(0.7, 0.7, 0.7)
	box.hint:SetText("Press Ctrl+C to copy. Escape closes.")
	local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() box:Hide() end)
	local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
	edit:SetAutoFocus(false)
	edit:SetSize(326, 22)
	edit:SetPoint("TOPLEFT", 18, -34)
	edit:SetFontObject(ChatFontNormal)
	-- the link cannot be changed: any typing puts it back, selected
	edit:SetScript("OnTextChanged", function(self, user)
		if user and box.url and self:GetText() ~= box.url then
			self:SetText(box.url)
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEscapePressed", function() box:Hide() end)
	edit:SetScript("OnEnterPressed", function() box:Hide() end)
	-- Ctrl+C: the game copies the selection, then the box closes
	edit:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			C_Timer.After(0.05, function() box:Hide() end)
		end
	end)
	edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	box.edit = edit
	box:SetScript("OnHide", function() edit:ClearFocus() end)
	-- Escape closes it with the game's other windows
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RXPForeverTrackerCopyURL") end
	box:Hide()
end

function api.showCopyURL(url, heading)
	if type(url) ~= "string" or url == "" then return end
	if not box then createBox() end
	box.url = url
	box.title:SetText(heading or "Wowhead URL")
	box.edit:SetText(url)
	box:Show()
	box.edit:SetFocus()
	box.edit:HighlightText()
	box.edit:SetCursorPosition(#url)
	box.edit:HighlightText()
end

-- the menu line -------------------------------------------------------------------------------------------------------
local function addWowhead(_, rootDescription)
	local id = menuQuest()
	local url = api.wowheadQuestURL(id)
	if not url or not rootDescription or not rootDescription.CreateButton then return end
	rootDescription:CreateButton(GREEN .. "Wowhead URL|r", function()
		api.showCopyURL(url, "Wowhead URL")
	end)
end
api.addWowheadMenuLine = addWowhead

ns.onLogin[#ns.onLogin + 1] = function()
	if Menu and Menu.ModifyMenu then
		pcall(Menu.ModifyMenu, "MENU_QUEST_OBJECTIVE_TRACKER", addWowhead)
	end
end
