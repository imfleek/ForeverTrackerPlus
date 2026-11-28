-- ForeverTrackerPlus: a LayerSwap button on the tracker's "Quests" header (3.2, user: "a button to the right of
-- Quests in the Quests header that will use LayerSwap's swap layer button").
-- LayerSwap (by Adam5288, all rights reserved) is only used, never copied: a click calls its own public key binding
-- function LayerSwap_SwapKey() (Bindings.xml "LAYERSWAP_SWAP"), which presses its "Swap layer" button with all its
-- own rules (combat, groups, flying, the hourly limit). The tooltip reads that button's text live (LayerSwapPanel
-- .swapButton) to say what a click does now. The icon is LayerSwap's own logo from its folder.
-- A click while LayerSwap's button is off (combat, dead, a group, the wait) is kept: the moment its button is on
-- again, the icon glows, a sound plays and a chat line says so - you click once more to swap. It cannot press for
-- you: LayerSwap's request is a chat message, which the game sends only from a real click or key press.
-- Right of the icon: LayerSwap's mini bar text, its two lines on top of each other ("Arathi Basin" over "No layers
-- here"; a one-line mini bar: that line), read from its own frame (LayerSwapMini .text / .status) twice a second. LayerSwap paints that bar only while
-- it is shown, so with its mini bar hidden the text is the last it showed. Option: "LayerSwap text" (db.layerSwapText).
-- Shown only with LayerSwap loaded and our own tracker. Option: Quest list > "LayerSwap button" (db.layerSwapButton).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local LOGO = "Interface\\AddOns\\LayerSwap\\Media\\logo"
local button

local function loaded()
	local f = C_AddOns and C_AddOns.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
	local ok, v = pcall(f or function() end, "LayerSwap")
	return ok and v and type(rawget(_G, "LayerSwap_SwapKey")) == "function" or false
end
api.layerSwapLoaded = loaded

-- what LayerSwap's own button says now ("Swap layer", "In combat", "Wait 4:10", ...) and whether it is on
local function swapState()
	local panel = rawget(_G, "LayerSwapPanel")
	local b = type(panel) == "table" and panel.swapButton
	if type(b) ~= "table" or not b.GetText then return nil end
	local ok, text = pcall(b.GetText, b)
	local okE, on = pcall(b.IsEnabled, b)
	return ok and text or nil, okE and on
end
api.layerSwapState = swapState -- (tests)

-- LayerSwap's mini bar lines (its name line, then its status line), or nil
local function miniText()
	local m = rawget(_G, "LayerSwapMini")
	if type(m) ~= "table" then return nil end
	local parts = {}
	for _, fs in ipairs({ m.text, m.status }) do
		if type(fs) == "table" and fs.GetText then
			local ok, t = pcall(fs.GetText, fs)
			if ok and issecretvalue and issecretvalue(t) then
				-- a secret text (in a battleground the place name can be one): it cannot be read or changed, but a
				-- FontString can still show it, so it is passed on as it is
				parts[#parts + 1] = t
				parts.secret = true
			elseif ok and type(t) == "string" then
				t = t:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
				if t ~= "" then parts[#parts + 1] = t end
			end
		end
	end
	return #parts > 0 and parts or nil
end
api.layerSwapMiniText = miniText -- (tests)
-- 3.2 (user: "turn on mini-bar, but you set that window to invisible"): LayerSwap fills its mini bar's text only
-- while the bar is shown. So with the bar on, we make it see-through (alpha 0) and let the mouse pass through it,
-- and copy its text here. LayerSwap never sets the bar's alpha or mouse itself. Option: "Hide LayerSwap's mini bar"
-- (db.layerSwapHideMini, on by default); off, or our button hidden: the bar as LayerSwap draws it.
local function hideMini(hide)
	local m = rawget(_G, "LayerSwapMini")
	if type(m) ~= "table" or not m.SetAlpha then return end
	hide = hide and true or false
	if m.ftpHidden == hide then return end
	m.ftpHidden = hide
	pcall(m.SetAlpha, m, hide and 0 or 1)
	for _, f in ipairs({ m, m.logo }) do
		if type(f) == "table" and f.EnableMouse then pcall(f.EnableMouse, f, not hide) end
	end
end
local function wantHidden()
	return ns.db and ns.db.layerSwapHideMini ~= false and ns.db.layerSwapText ~= false and ns.db.layerSwapButton ~= false
end
-- 3.2 (user: "if the LayerSwap dial is on, make sure LayerSwap's mini bar is also on"): with our button, its text
-- and the hiding on, a mini bar that is off is turned on through LayerSwap's own /ls mini (a switch, so only while
-- it is off; LayerSwap saves it). It is invisible (hideMini), so nothing new shows on screen.
local function ensureMini()
	if not wantHidden() then return end
	local m = rawget(_G, "LayerSwapMini")
	if type(m) == "table" and m.IsShown and m:IsShown() then return end
	local cmd = type(SlashCmdList) == "table" and SlashCmdList["LAYERSWAP"]
	if type(cmd) ~= "function" then return end
	local ok, err = pcall(cmd, "mini")
	if not ok and geterrorhandler then geterrorhandler()(err) end
end
api.layerSwapEnsureMini = ensureMini -- (tests)
api.layerSwapHideMini = function() hideMini(wantHidden() and button ~= nil and button:IsShown()) end

-- 3.2 (user): the two lines on top of each other, right of the icon; one line alone is centred on it
local function paintText(b)
	local top, bottom = b.label, b.label2
	if not (top and bottom) then return end
	local lines = ns.db and ns.db.layerSwapText ~= false and miniText() or nil
	local one, two = lines and lines[1] or "", lines and lines[2] or ""
	if lines and lines.secret then
		b.labelText, b.labelText2 = false, false -- a secret cannot be compared: drawn each time
	else
		if b.labelText == one and b.labelText2 == two then return end
		b.labelText, b.labelText2 = one, two
	end
	top:ClearAllPoints()
	-- the right edge is pinned at the same height as the left one: a BOTTOMLEFT with a RIGHT gave the line no
	-- height, and nothing showed (user: "now there's no layer text")
	local hasTwo = lines and lines[2] ~= nil
	if hasTwo then
		top:SetPoint("BOTTOMLEFT", b, "RIGHT", 4, 0)
		if b.labelRight then top:SetPoint("BOTTOMRIGHT", b.labelRight, "LEFT", -6, 0) end
	else
		top:SetPoint("LEFT", b, "RIGHT", 4, 0)
		if b.labelRight then top:SetPoint("RIGHT", b.labelRight, "LEFT", -6, 0) end
	end
	top:SetText(one)
	bottom:SetText(two)
	bottom:SetShown(hasTwo and true or false)
end

-- 3.2 (user, fix 1): the icon goes grey while LayerSwap's own button is off (combat, a group, the wait, ...)
local WAIT_FOR = 15 * 60 -- a kept click is dropped after 15 minutes
local function clock() return GetTime and GetTime() or 0 end
local function say(text)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r: " .. text) end
end
local function setReady(b, ready)
	b.ready = ready and true or nil
	if api.animLayerSwapReady then api.animLayerSwapReady(b.glow, ready) elseif b.glow then b.glow:SetShown(ready) end
end
local function shade(b)
	local _, on = swapState()
	local off = on == false
	-- a kept click: its swap can be asked now
	local waiting = type(b.waiting) == "number"
	if waiting and on == true then
		b.waiting = nil
		setReady(b, true)
		if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then (root.playSound or pcall)(PlaySound, SOUNDKIT.READY_CHECK) end
		say("LayerSwap is ready. Click the LayerSwap icon on the Quests header to swap.")
	elseif waiting and clock() - b.waiting > WAIT_FOR then
		b.waiting = nil
	end
	if b.ready == true and off then setReady(b, false) end -- blocked again before you clicked
	if rawget(b, "off") == off then return end
	b.off = off
	if b.icon.SetDesaturated then b.icon:SetDesaturated(off) end
	b.icon:SetAlpha(off and 0.5 or 1)
end
api.layerSwapShade = shade -- (tests)

-- 3.2 (user): LayerSwap's Host (other players can swap through you): its state, and a right-click turns it on or off
-- through LayerSwap's own /ls on and /ls off. LayerSwap keeps it in LayerSwapDB.hosting (nil: on). LayerSwap Stealth
-- (another addon) still turns it off at the next login unless you logged out with it on.
function api.layerSwapHosting()
	local db = rawget(_G, "LayerSwapDB")
	if type(db) ~= "table" then return nil end
	return db.hosting ~= false
end
function api.layerSwapHostToggle()
	local cmd = type(SlashCmdList) == "table" and SlashCmdList["LAYERSWAP"]
	local on = api.layerSwapHosting()
	if type(cmd) ~= "function" or on == nil then return false end
	local ok, err = pcall(cmd, on and "off" or "on")
	if not ok and geterrorhandler then geterrorhandler()(err) end
	return ok
end

function api.layerSwapClick()
	local fn = rawget(_G, "LayerSwap_SwapKey")
	if type(fn) == "function" then
		local ok, err = pcall(fn)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

local function place()
	local header = api.ownQuestsHeaderFrame and api.ownQuestsHeaderFrame()
	local want = header and loaded() and ns.db and ns.db.layerSwapButton ~= false
	if not want then
		if button then button:Hide() end
		hideMini(false)
		return header ~= nil
	end
	if not button then
		button = CreateFrame("Button", "ForeverTrackerPlusLayerSwap", header)
		button:SetSize(16, 16)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		if icon:SetTexture(LOGO) == false then icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran") end
		button.icon = icon
		local hl = button:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetTexture(LOGO)
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0.4)
		local glow = button:CreateTexture(nil, "OVERLAY")
		glow:SetPoint("CENTER")
		glow:SetSize(30, 30)
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(1, 0.85, 0.3)
		glow:Hide()
		button.glow = glow
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then
				api.layerSwapHostToggle()
				if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
				return
			end
			local _, on = swapState()
			if on == false then
				-- blocked now: keep the click (a second click lets it go)
				if type(self.waiting) == "number" then
					self.waiting = nil
					say("LayerSwap: no longer waiting.")
				else
					self.waiting = clock()
					say("LayerSwap is blocked now. You get a sign when you can swap.")
				end
			else
				self.waiting = nil
				setReady(self, false)
				api.layerSwapClick()
			end
			if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
		end)
		button:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("LayerSwap", 1, 0.82, 0)
			local text, on = swapState()
			if text then
				GameTooltip:AddLine("Click: " .. text, on == false and 0.6 or 1, on == false and 0.6 or 1, on == false and 0.6 or 1)
			else
				GameTooltip:AddLine("Click: Swap layer", 1, 1, 1)
			end
			if type(self.waiting) == "number" then
				GameTooltip:AddLine("Waiting: you get a sign when you can swap. Click to stop.", 0.6, 0.85, 1)
			elseif on == false then
				GameTooltip:AddLine("Click: get a sign when you can swap", 0.6, 0.85, 1)
			end
			local host = api.layerSwapHosting()
			if host ~= nil then
				GameTooltip:AddLine("Host: " .. (host and "|cff40ff40on|r" or "|cff999999off|r"), 1, 1, 1)
				GameTooltip:AddLine("Right-click: turn Host " .. (host and "off" or "on"), 0.6, 0.85, 1)
			end
			GameTooltip:AddLine("Uses LayerSwap's own Swap layer button", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		-- LayerSwap's button is read twice a second while ours shows
		local since = 0
		button:SetScript("OnUpdate", function(self, elapsed)
			since = since + (tonumber(elapsed) or 0)
			if since < 0.5 then return end
			since = 0
			shade(self)
			ensureMini()
			hideMini(wantHidden())
			paintText(self)
		end)
		local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		button.label = label
		local label2 = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label2:SetJustifyH("LEFT")
		label2:SetWordWrap(false)
		button.label2 = label2
	end
	button:SetParent(header)
	button:ClearAllPoints()
	-- right after the word "Quests"
	if header.text then button:SetPoint("LEFT", header.text, "RIGHT", 5, 0) else button:SetPoint("LEFT", header, "LEFT", 60, 0) end
	button:SetFrameLevel((header:GetFrameLevel() or 1) + 3)
	button.labelRight = header.count
	button.label2:ClearAllPoints()
	button.label2:SetPoint("TOPLEFT", button, "RIGHT", 4, -1)
	-- it stops short of the quest count on the right
	if header.count then button.label2:SetPoint("TOPRIGHT", header.count, "LEFT", -6, -1) end
	button:Show()
	shade(button)
	button.labelText = false
	ensureMini()
	hideMini(wantHidden())
	paintText(button)
	return true
end
api.applyLayerSwapButton = place

ns.onLogin[#ns.onLogin + 1] = function()
	-- the header is made with our tracker: tried again for a while if it is not there yet
	local tries = 0
	local function try()
		tries = tries + 1
		if not place() and tries < 20 and C_Timer and C_Timer.After then C_Timer.After(1, try) end
	end
	try()
end

-- /ftp layerswap: what the button reads from LayerSwap and what it shows (user: "I don't see the two lines")
if api.addSlash then
	api.addSlash("layerswap", "what the LayerSwap button reads and shows", function(_, say)
		local function show(v)
			if issecretvalue and issecretvalue(v) then return "secret" end
			if type(v) == "string" then return '"' .. v:gsub("|", "||") .. '"' end
			return tostring(v)
		end
		local function text(fs)
			if type(fs) ~= "table" or not fs.GetText then return "none" end
			local ok, t = pcall(fs.GetText, fs)
			return ok and show(t) or "error"
		end
		local function size(f)
			if type(f) ~= "table" or not f.GetWidth then return "?" end
			local okW, w = pcall(f.GetWidth, f)
			local okH, h = pcall(f.GetHeight, f)
			return ("%s x %s"):format(okW and show(w) or "?", okH and show(h) or "?")
		end
		local m = rawget(_G, "LayerSwapMini")
		say(("LayerSwap loaded: %s; mini bar: %s, shown %s"):format(tostring(loaded()), type(m) == "table" and "yes" or "no",
			type(m) == "table" and m.IsShown and tostring(m:IsShown()) or "-"))
		if type(m) == "table" then say(("mini bar lines: %s / %s"):format(text(m.text), text(m.status))) end
		if type(m) == "table" then say(("mini bar made invisible by us: %s"):format(m.ftpHidden and "yes" or "no")) end
		if type(m) ~= "table" or not (m.IsShown and m:IsShown()) then
			say("LayerSwap fills its text only while its mini bar is on: turn it on (/ls, the Mini bar button). We make it invisible and show its text here.")
		end
		say(("setting LayerSwap text: %s"):format(ns.db and ns.db.layerSwapText == false and "off" or "on"))
		if not button then say("our button: not made (no Quests header yet?)") return end
		say(("our button: shown %s, visible %s, size %s"):format(tostring((button:IsShown())), tostring((button:IsVisible())), size(button)))
		for i, fs in ipairs({ button.label, button.label2 }) do
			local np = fs and fs.GetNumPoints and fs:GetNumPoints() or 0
			say(("line %d: %s, shown %s, size %s, %d points"):format(i, text(fs), fs and tostring((fs:IsShown())) or "-", size(fs), np))
		end
	end)
end
