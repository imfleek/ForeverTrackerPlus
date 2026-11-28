-- 3.2 What's new (user: "a changelog window after an update, in the CurseForge styling, with Ok and Do not show
-- me changes in future"). After an update (the toc's Version is not db.whatsNewSeen) a window lists this version's
-- changes: headings with an icon (the game's fonts have no emoji, so icons stand in for CurseForge's emoji) and
-- bullets. Not on a fresh install (no db.setupDone yet: the setup shows everything). It waits for the setup window.
--   Ok                          : seen; it opens again on the next update
--   Do not show me changes ...  : db.whatsNewOff (also Settings > Basics), seen
-- /qt news opens it by hand. db.whatsNewSeen and db.whatsNewOff are not in profiles.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db
ns.onLogin[#ns.onLogin + 1] = function() db = ns.db end

local ICON = "Interface\\Icons\\"
-- a version's notes: { "h", icon, heading } a heading, { "b", text } a bullet, { "p", text } a line of text
local NOTES = {
	["3.2"] = {
		{ "p", "Thanks for updating! Here is what changed." },
		{ "h", ICON .. "INV_Misc_Map_01", "Our own tracker" },
		{ "b", "A new tracker in its own frame, now the only one. Blizzard's tracker is hidden, so no more \"secret auras\" errors in instances." },
		{ "b", "Battleground timers, Professions, Legacy Challenges (with icons) and the reputation bar in it." },
		{ "h", ICON .. "INV_Misc_Bag_10", "Big quest item button" },
		{ "b", "Near the place your closest tracked quest's item is used, a big button with it shows at the bottom middle. Ctrl+right-drag moves it (Helpers > On screen)." },
		{ "h", ICON .. "Spell_Holy_Resurrection", "Animations and helpers" },
		{ "b", "Flashes, slides, glows and a level-up banner. Each one has a switch on GENERAL > Animations." },
		{ "b", "Corpse run helper, a run summary for dungeons, a dead-end alert and a bug report button." },
		{ "b", "A LayerSwap button on the Quests header (with LayerSwap installed)." },
		{ "b", "One switch for all sounds (Basics > Main), and less lag." },
		{ "h", ICON .. "INV_Misc_Spyglass_02", "Distance on your 3 closest quests" },
		{ "b", "Only the 3 quests closest to you show the yards and the arrow (Quest titles > Distance)." },
		{ "b", "Optional: how long it takes to get there." },
		{ "h", ICON .. "INV_Misc_Book_11", "Reminders" },
		{ "b", "New trainer spells and unspent talent points, at the top of the tracker." },
		{ "b", "An alert when you loot an item that starts a quest." },
		{ "h", ICON .. "INV_Misc_Gift_01", "Better rewards" },
		{ "b", "A green arrow on upgrades, a disenchant icon, and an optional auto pick." },
		{ "h", ICON .. "INV_Misc_Key_03", "Dungeon card" },
		{ "b", "Boss splits, your party's quests, a share button and the next boss's abilities." },
		{ "h", ICON .. "INV_Scroll_03", "New guide pages" },
		{ "b", "Attunements, class quests and profession quests." },
		{ "b", "Legacy Challenges: search, progress, category and sort filters. \"Only challenges this character can do\" now hides other classes' challenges. Blizzard's Legacy Challenges window has a Track box on each open challenge." },
		{ "b", "Secrets: each one folds, with a line between them, and a switch for the other faction's secrets. The Cozy Sleeping Bag has its steps too." },
		{ "b", "Library books: every book with its place and a hint, the librarian and your next reward, and the level 60 books. No Questie needed." },
		{ "h", ICON .. "INV_Misc_PocketWatch_01", "Run analysis" },
		{ "b", "Time in dungeons, raids and battlegrounds." },
		{ "b", "\"Where the time went\" in groups (Fighting, Travel, NPCs and windows, Doing things, Downtime). Change the order with \"Change the order\"." },
		{ "b", "Camp and rest time, and a session summary at login." },
		{ "b", "Copy for Discord has your character's surname." },
		{ "h", ICON .. "Ability_DualWield", "Also new" },
		{ "b", "Fade or hide the tracker in combat or in a raid, hide done objectives, more sorting, kill counts in tooltips and your path on the map." },
		{ "b", "Hover a setting in /ftp: a tooltip with what it does." },
		{ "b", "RestedXP's NPC automation while it is hidden now only covers what we do not do ourselves." },
	},
}

local function version()
	local fn = C_AddOns and C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
	local ok, v = pcall(fn, ADDON, "Version")
	return ok and type(v) == "string" and v or nil
end
-- the notes for v: its own, else the ones for its major.minor ("3.2.1" -> "3.2")
local function notesFor(v)
	if not v then return nil end
	return NOTES[v] or NOTES[v:match("^(%d+%.%d+)")]
end
api.whatsNewNotes = notesFor -- (tests)

local frame
local function build()
	local kit = api.themeKit
	if not kit then return nil end
	local C = kit.C
	local f = CreateFrame("Frame", "ForeverTrackerPlusWhatsNew", UIParent)
	f:SetSize(520, 460)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "ForeverTrackerPlusWhatsNew") end
	kit.solid(f, "BACKGROUND", C.window, 0.98):SetAllPoints()
	kit.border(f, C.edge, 2, "BORDER")
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", 2, -2)
	bar:SetPoint("TOPRIGHT", -2, -2)
	bar:SetHeight(32)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	kit.gradient(barBg, C.titleTop, C.titleBottom)
	f.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local font = GameFontNormal and GameFontNormal:GetFont() or STANDARD_TEXT_FONT
	if font then f.title:SetFont(font, 16, "") end
	f.title:SetPoint("CENTER")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -3, -4)

	-- the notes scroll (mouse wheel), between the title bar and the buttons
	local scroll = CreateFrame("ScrollFrame", nil, f)
	scroll:SetPoint("TOPLEFT", 22, -46)
	scroll:SetPoint("BOTTOMRIGHT", -22, 58)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(476, 10)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = self:GetVerticalScrollRange() or 0
		self:SetVerticalScroll(math.min(math.max((self:GetVerticalScroll() or 0) - delta * 40, 0), max))
	end)
	f.scroll, f.child, f.parts = scroll, child, {}

	f.ok = kit.makeButton(f, "Ok", 110, function()
		if db then db.whatsNewSeen = version() end
		f:Hide()
	end)
	f.ok:SetPoint("BOTTOMRIGHT", -20, 16)
	f.never = kit.makeButton(f, "Do not show me changes in future", 260, function()
		if db then db.whatsNewOff = true; db.whatsNewSeen = version() end
		if api.refreshConfig then pcall(api.refreshConfig) end
		f:Hide()
	end)
	f.never:SetPoint("BOTTOMLEFT", 20, 16)
	-- closed with the X or Escape: seen, as Ok
	f:SetScript("OnHide", function() if db then db.whatsNewSeen = version() end end)

	function f.fill(v, notes)
		f.title:SetText("|cffffd100Forever|r|cfff0cf86TrackerPlus|r  |cffb0a99cWhat's new in " .. tostring(v or "") .. "|r")
		for _, p in ipairs(f.parts) do p:Hide() end
		local used, y, width = 0, 0, 476
		local function part(kind)
			used = used + 1
			local p = f.parts[used]
			if not p then
				p = CreateFrame("Frame", nil, child)
				p.icon = p:CreateTexture(nil, "ARTWORK")
				p.text = kit.text(p, "GameFontHighlight", 1.1, C.label)
				p.text:SetJustifyH("LEFT")
				p.text:SetJustifyV("TOP")
				p.text:SetWordWrap(true)
				f.parts[used] = p
			end
			p:Show()
			return p
		end
		for _, n in ipairs(notes or {}) do
			local p = part(n[1])
			p.icon:Hide()
			p.text:ClearAllPoints()
			if n[1] == "h" then
				y = y + (y > 0 and 14 or 0)
				p.icon:SetTexture(n[2])
				p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				p.icon:SetSize(22, 22)
				p.icon:ClearAllPoints()
				p.icon:SetPoint("TOPLEFT", 0, 0)
				p.icon:Show()
				p.text:SetPoint("TOPLEFT", 30, -3)
				p.text:SetWidth(width - 30)
				p.text:SetText("|cffffd100" .. n[3] .. "|r")
			elseif n[1] == "b" then
				p.text:SetPoint("TOPLEFT", 14, 0)
				p.text:SetWidth(width - 14)
				p.text:SetText("|cffffd100\226\128\162|r  " .. n[2])
			else
				p.text:SetPoint("TOPLEFT", 0, 0)
				p.text:SetWidth(width)
				p.text:SetText(n[2])
			end
			p.text:SetHeight(0)
			local h = math.max(n[1] == "h" and 24 or 0, math.ceil(tonumber(p.text:GetStringHeight()) or 14) + (n[1] == "h" and 3 or 0))
			p:ClearAllPoints()
			p:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
			p:SetSize(width, h)
			y = y + h + 6
		end
		child:SetHeight(math.max(y, 10))
		scroll:SetVerticalScroll(0)
	end
	f:Hide()
	frame = f
	return f
end

-- force: /qt news (shows even when turned off or seen)
function api.showWhatsNew(force)
	local v = version()
	local notes = notesFor(v)
	if not notes then
		if force then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r no notes for this version.") end
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		local wait = CreateFrame("Frame")
		wait:RegisterEvent("PLAYER_REGEN_ENABLED")
		wait:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); api.showWhatsNew(force) end)
		return
	end
	if not frame and not build() then return end
	frame.fill(v, notes)
	frame:Show()
	if db then db.whatsNewRead = v end -- 3.2: read (the settings' What's new button stops glowing)
	if api.refreshConfig then pcall(api.refreshConfig) end
end

-- after an update: once, not on a fresh install, not while the setup window is open
function api.whatsNewDue()
	if not db then return false end
	local v = version()
	if not v then return false end
	if db.whatsNewSeen == nil and not db.setupDone then
		db.whatsNewSeen = v -- a fresh install: the setup shows everything
		db.whatsNewRead = v
		return false
	end
	if db.whatsNewSeen == v then return false end
	if db.whatsNewOff then db.whatsNewSeen = v return false end
	return notesFor(v) ~= nil
end
-- 3.2 (user): this version's notes not opened yet (the What's new button glows; Animations.lua animNewsGlow)
function api.whatsNewUnread()
	if not db then return false end
	local v = version()
	return v ~= nil and db.whatsNewRead ~= v and notesFor(v) ~= nil
end
local function showWhenFree()
	if not api.whatsNewDue() then return end
	local setup = rawget(_G, "ForeverTrackerPlusSetup")
	if setup and setup:IsShown() then
		if not setup.qtWhatsNewHooked then
			setup.qtWhatsNewHooked = true
			setup:HookScript("OnHide", function() C_Timer.After(0.5, showWhenFree) end)
		end
		return
	end
	api.showWhatsNew(false)
end
ns.onLogin[#ns.onLogin + 1] = function()
	-- the setup opens 4 s after login; this a little later, so it can wait for it
	C_Timer.After(6, showWhenFree)
end

if api.addSlash then api.addSlash("news", "what is new in this version", function() api.showWhatsNew(true) end) end
