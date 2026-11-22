-- 3.0 First-time setup: a short walk through every feature, each with an on/off switch, in the settings window's
-- look (api.themeKit). It opens by itself once per account for 3.0 (db.setupDone holds the version it was finished
-- or skipped on), a few seconds after login and out of combat; /qt setup and Settings > Basics open it again.
-- The switches read and change the very settings the settings window shows, so the setup starts from what is set
-- now and every choice applies at once. Nothing is changed by only opening or skipping it.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local SETUP_VERSION = 3

local frame, steps, stepIndex

local function db() return ns.db end
local function guide() return root.objectives and root.objectives.settings end
local function rxpLoaded() return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RXPGuides") and guide() ~= nil end
local function questieLoaded() return api.questieLoaded and api.questieLoaded() end
local function call(fn, ...) if type(fn) == "function" then local ok, err = pcall(fn, ...); if not ok then geterrorhandler()(err) end end end

-- a switch row: { label, help, get, set } (only = false leaves it out)
local function row(label, helpText, get, set, only)
	if only == false then return nil end
	return { label = label, help = helpText, get = get, set = set }
end
local function list(...)
	local out = {}
	for i = 1, select("#", ...) do local r = select(i, ...); if r then out[#out + 1] = r end end
	return out
end

local function buildSteps()
	local d = db()
	local g = guide()
	local out = {}
	out[#out + 1] = { title = "Welcome to ForeverTrackerPlus 3.1", text =
		"This short setup shows every feature and lets you turn each one on or off. It takes about a minute.\n\n" ..
		"Every choice applies at once. You can change all of it later: type |cffffd100/qt|r or click the minimap button.\n\n" ..
		"Press |cffffd100Next|r to start, or |cffffd100Skip setup|r to keep everything as it is." }
	out[#out + 1] = { title = "Your quest list", text = "How the quest tracker lists your quests.", rows = list(
		row("Zone headers and sorting", "quests grouped under their zone, the closest zone first",
			function() return d.zoneSort and true or false end,
			function(v) if api.setMode then api.setMode(d.trackMode or "all", v) end end),
		row("Distance arrows", "how far each quest is, with an arrow that points at it",
			function() return d.questDistance ~= false end,
			function(v) d.questDistance = v; call(api.applyQuestDistance); call(api.rebuildMoreQuests) end),
		row("Experience reward", "the experience a quest gives, after its title",
			function() return d.showXP and true or false end, function(v) call(api.setReward, "xp", v) end),
		row("Gold reward", "the money a quest gives, after its title",
			function() return d.showGold and true or false end, function(v) call(api.setReward, "gold", v) end),
		row("Lock the tracker", "off: drag the tracker to move it",
			function() return d.locked and true or false end, function(v) call(api.setLocked, v) end)
	) }
	out[#out + 1] = { title = "Quest lines", text = "What each quest line shows.", rows = list(
		row("Progress bars", "a small bar with the count on each objective",
			function() return d.progressBars ~= false end,
			function(v) d.progressBars = v; call(api.applyProgressBars); call(api.rebuildMoreQuests) end),
		row("Icons", "elite, group, dungeon, raid, PvP and new-in-Forever icons on titles",
			function() return d.condense and true or false end,
			function(v) d.condense = v; call(api.applyExtras) end),
		row("Checks on finished quests", "a green tick left of a finished quest's title",
			function() return d.completeCheck ~= false end,
			function(v) d.completeCheck = v; call(api.applyExtras); call(api.rebuildMoreQuests) end),
		row("Dungeon card", "in a dungeon or raid: its name, group, deaths and lockout at the top",
			function() return d.dungeonCard ~= false end, function(v) call(api.setDungeonCard, v) end),
		row("Tracked reputation", "the faction you watch, with its bar, above the quests",
			function() return d.repTrack ~= false end, function(v) call(api.setRepTrack, v) end),
		row("Tooltips on quests", "hover a quest: overview, gold and rewards",
			function() return d.tooltips and true or false end, function(v) d.tooltips = v end)
	) }
	if g then
		out[#out + 1] = { title = "RestedXP guide", text = rxpLoaded()
			and "RestedXP Guides is loaded. Its steps can show right in the tracker."
			or "RestedXP Guides is not loaded. These settings apply once it is.", rows = list(
			row("RestedXP steps in the tracker", "off: RestedXP's own windows come back",
				function() return g.get("enabled") and true or false end, function(v) call(g.setEnabled, v) end),
			row("Arrow as the objective button", "click RestedXP's arrow to use the step's item or target",
				function() return g.get("arrowButton") and true or false end, function(v) call(g.setFlag, "arrowButton", v) end),
			row("Ping what you target", "the step's target buttons ping the unit for your group",
				function() return g.get("targetPing") ~= false end, function(v) call(g.setFlag, "targetPing", v) end)
		) }
	end
	out[#out + 1] = { title = "Helpers", text = "Small helpers while you quest.", rows = list(
		row("Quest items in your bags", "a quest sign on items a quest needs, and a warning if you sell or delete one",
			function() return d.bagMarks ~= false end, function(v) d.bagMarks = v; call(api.repaintBagMarks) end),
		row("Best reward to sell", "a gold coin on the quest reward that sells for the most (asks if OneForAll's coin is on too)",
			function() return d.rewardHint ~= false end, function(v) d.rewardHint = v; if v then call(api.checkAddonClashes, "rewardHint") end end),
		row("Quest close by", "a card when a quest you can take is near (needs Questie)",
			function() return d.nearbyCard ~= false end, function(v) d.nearbyCard = v end, questieLoaded() and true or false),
		row("Leave out breadcrumb quests", "a quest that only sends you to a quest you already did or have",
			function() return d.breadcrumbHide ~= false end, function(v) d.breadcrumbHide = v end, questieLoaded() and true or false),
		row("Rares near your quests", "a rare in your zone shows on the zone header",
			function() return d.rareAlert ~= false end, function(v) call(api.setRareAlert, v) end),
		row("Ctrl+click a quest: find a group", "LFM in General chat or a Looking For Group listing",
			function() return d.questGroupFinder ~= false end, function(v) d.questGroupFinder = v end),
		row("3D model on hover", "hover an objective: the NPC or object it names",
			function() return d.npcPanelQuests ~= false end, function(v) d.npcPanelQuests = v end)
	) }
	out[#out + 1] = { title = "On screen", text = "Quest help on your screen.", rows = list(
		row("Quest item bar", "one button per usable quest item; set a key in Key Bindings > AddOns",
			function() return d.itemBar ~= false end, function(v) d.itemBar = v; call(api.refreshItemBar) end),
		row("Big progress messages", "quest progress in large letters, like \"Wolves slain: 3/8\"",
			function() return d.toasts ~= false end, function(v) d.toasts = v; call(api.applyToastsHideGame) end),
		row("Marker in the world", "your tracked quest's name, next step and distance over its spot",
			function() return d.worldMarker ~= false end, function(v) d.worldMarker = v; call(api.refreshWorldMarker) end),
		row("Track the nearest quest by itself", "the marker moves on to the closest quest",
			function() return d.markerAuto == true end, function(v) d.markerAuto = v end),
		row("Say in party chat when a quest is done", "only in a party",
			function() return d.partyDone == true end, function(v) d.partyDone = v end)
	) }
	out[#out + 1] = { title = "Talking to NPCs", text = "Let the addon click through quest NPCs for you. All off unless you turn them on.\n\nHold |cffffd100Shift|r while you talk to an NPC: nothing is automatic that time. More choices: Settings > Helpers > NPCs.", rows = list(
		row("Accept quests", "talk to an NPC: its quests are accepted for you",
			function() return d.autoAccept == true end, function(v) d.autoAccept = v end),
		row("Turn in finished quests", "when you can pick a reward, you still pick",
			function() return d.autoTurnIn == true end, function(v) d.autoTurnIn = v end),
		row("Skip the chat", "an NPC with only one chat option: it is picked for you",
			function() return d.autoGossip == true end, function(v) d.autoGossip = v end)
	) }
	out[#out + 1] = { title = "World", text = "Helpers out in the world.", rows = list(
		row("Breath warning", "red screen edges when breath or fatigue runs low",
			function() return d.breathWarn ~= false end, function(v) d.breathWarn = v end),
		row("Flight times", "a time for every route, from the game's flight path data, and the time left while flying (asks if EllesmereUI's Flight Timer is on too)",
			function() return d.flightTimes ~= false end, function(v) d.flightTimes = v; if v then call(api.checkAddonClashes, "flightTimes") end end),
		row("Minimap button", "left-click opens the settings",
			function() return not (d.minimap and d.minimap.hide) end, function(v) call(api.setMinimapShown, v) end)
	) }
	out[#out + 1] = { title = "Guides", text = "Settings > Guides has three lists:\n\n" ..
		"|cffffd100Legacy Challenges|r: WoW Forever's challenges and what is still to do.\n" ..
		"|cffffd100Library books|r: every book for the library; click one for a waypoint.\n" ..
		"|cffffd100Sleeping bag|r: the Cozy Sleeping Bag quest chain, from level 14.\n\n" ..
		(questieLoaded() and "" or "The books and the sleeping bag chain need Questie.\n\n"), rows = list(
		row("Show finished challenges", "off: Legacy Challenges lists only the ones still to do",
			function() return d.legacyShowDone == true end, function(v) d.legacyShowDone = v end),
		row("Only challenges this character can do", "hides Legacy Challenges for another race, class or faction, or for a profession you have not learned",
			function() return d.legacyOnlyMine == true end, function(v) d.legacyOnlyMine = v end)
	) }
	out[#out + 1] = { title = "Statistics", text = "Your run in numbers: Settings > Statistics.", rows = list(
		row("Record statistics", "quests, experience, deaths and where your time goes, per level",
			function() return d.statsOn ~= false end, function(v) d.statsOn = v end),
		row("Level-up line in chat", "how long the last level took, and your time played",
			function() return d.levelAnnounce ~= false end, function(v) d.levelAnnounce = v end)
	) }
	out[#out + 1] = { title = "All set", text =
		"That is everything. Have a good run!\n\n" ..
		"|cffffd100/qt|r opens the settings, where every feature has more choices.\n" ..
		"|cffffd100/qt setup|r opens this setup again.", final = true }
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------------------------
local MAX_ROWS = 6
local function finish()
	local d = db()
	if d then d.setupDone = SETUP_VERSION end
	if frame then frame:Hide() end
end

local function build()
	local kit = api.themeKit
	if not kit then return nil end
	local C = kit.C
	local f = CreateFrame("Frame", "ForeverTrackerPlusSetup", UIParent)
	frame = f
	f:SetSize(560, 470)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ForeverTrackerPlusSetup")
	kit.solid(f, "BACKGROUND", C.window, 0.98):SetAllPoints()
	kit.border(f, C.edge, 2, "BORDER")
	-- title bar
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", 2, -2)
	bar:SetPoint("TOPRIGHT", -2, -2)
	bar:SetHeight(32)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	kit.gradient(barBg, C.titleTop, C.titleBottom)
	local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local font = GameFontNormal and GameFontNormal:GetFont() or STANDARD_TEXT_FONT
	if font then title:SetFont(font, 16, "") end
	title:SetText("|cfff2e6c8RXP|r |cffffd100Forever|r|cfff0cf86Tracker|r  |cffb0a99cSetup|r")
	title:SetPoint("CENTER")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -3, -4)
	close:HookScript("OnClick", finish)
	-- progress: a dot per step
	f.dots = {}
	-- the step
	f.stepTitle = kit.text(f, "GameFontHighlightLarge", 1.25, C.pageTitle)
	f.stepTitle:SetPoint("TOPLEFT", 26, -58)
	f.stepTitle:SetPoint("RIGHT", -26, 0)
	f.stepTitle:SetJustifyH("LEFT")
	f.stepText = kit.text(f, "GameFontHighlight", 1.1, C.label)
	f.stepText:SetPoint("TOPLEFT", f.stepTitle, "BOTTOMLEFT", 0, -10)
	f.stepText:SetPoint("RIGHT", -26, 0)
	f.stepText:SetJustifyH("LEFT")
	f.stepText:SetJustifyV("TOP")
	f.stepText:SetWordWrap(true)
	f.rows = {}
	for i = 1, MAX_ROWS do
		local r = CreateFrame("Frame", nil, f)
		r:SetHeight(44)
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		kit.gradient(bg, { 0.09, 0.075, 0.06 }, { 0.055, 0.045, 0.036 })
		kit.border(r, C.panelEdge, 1, "BORDER")
		r.label = kit.text(r, "GameFontHighlight", 1.12, C.value)
		r.label:SetPoint("TOPLEFT", 12, -7)
		r.label:SetPoint("RIGHT", -70, 0)
		r.label:SetJustifyH("LEFT")
		r.help = kit.text(r, "GameFontDisableSmall", 1.05)
		r.help:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -2)
		r.help:SetPoint("RIGHT", -70, 0)
		r.help:SetJustifyH("LEFT")
		r.help:SetWordWrap(false)
		r.switch = kit.makeSwitch(r, 22, function() return r.def and r.def.get() end, function(v)
			if r.def then
				local ok, err = pcall(r.def.set, v)
				if not ok then geterrorhandler()(err) end
				if api.refreshConfig then api.refreshConfig() end
			end
		end)
		r.switch:SetPoint("RIGHT", -14, 0)
		f.rows[i] = r
	end
	-- buttons
	f.skip = kit.makeButton(f, "Skip setup", 120, finish)
	f.skip:SetPoint("BOTTOMLEFT", 20, 16)
	f.next = kit.makeButton(f, "Next", 110, function()
		if steps[stepIndex] and steps[stepIndex].final then finish() return end
		f.show(stepIndex + 1)
	end)
	f.next:SetPoint("BOTTOMRIGHT", -20, 16)
	f.back = kit.makeButton(f, "Back", 110, function() f.show(stepIndex - 1) end)
	f.back:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
	f.settings = kit.makeButton(f, "Open settings", 140, function()
		finish()
		if api.openConfigTab then api.openConfigTab("main") end
	end)
	f.settings:SetPoint("RIGHT", f.back, "LEFT", -8, 0)

	f.show = function(i)
		stepIndex = math.min(math.max(i, 1), #steps)
		local s = steps[stepIndex]
		f.stepTitle:SetText(s.title)
		f.stepText:SetText(s.text or "")
		f.stepText:SetHeight(0)
		local y = 58 + (f.stepTitle:GetStringHeight() or 20) + 10 + (f.stepText:GetStringHeight() or 14) + 16
		for n, r in ipairs(f.rows) do
			local def = s.rows and s.rows[n]
			r.def = def
			if def then
				r.label:SetText(def.label)
				r.help:SetText(def.help or "")
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -y)
				r:SetPoint("RIGHT", f, "RIGHT", -22, 0)
				r.switch.redraw()
				r:Show()
				y = y + 48
			else
				r:Hide()
			end
		end
		for n = #f.dots + 1, #steps do
			local dot = f:CreateTexture(nil, "ARTWORK")
			dot:SetSize(8, 8)
			f.dots[n] = dot
		end
		local dotsW = #steps * 14
		for n, dot in ipairs(f.dots) do
			dot:ClearAllPoints()
			dot:SetPoint("BOTTOMLEFT", f, "BOTTOM", -dotsW / 2 + (n - 1) * 14, 52)
			local c = n == stepIndex and C.on or (n < stepIndex and { 0.55, 0.43, 0.18 } or C.off)
			dot:SetColorTexture(c[1], c[2], c[3], 1)
			dot:SetShown(n <= #steps)
		end
		f.back:SetShown(stepIndex > 1)
		f.next:SetText(s.final and "Finish" or (stepIndex == 1 and "Start" or "Next"))
		f.skip:SetShown(not s.final)
		f.settings:SetShown(s.final and true or false)
		f:SetHeight(math.max(y + 80, 300))
	end
	f:Hide()
	return f
end

-- force: opened by hand (/qt setup, the button); otherwise only when not done for this version yet
function api.showSetup(force)
	local d = db()
	if not d then return end
	if not force and (tonumber(d.setupDone) or 0) >= SETUP_VERSION then return end
	if InCombatLockdown and InCombatLockdown() then
		if force then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r the setup opens after combat.") end
		local wait = CreateFrame("Frame")
		wait:RegisterEvent("PLAYER_REGEN_ENABLED")
		wait:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); api.showSetup(force) end)
		return
	end
	if not frame and not build() then return end
	steps = buildSteps()
	frame.show(1)
	frame:Show()
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
end

ns.onLogin[#ns.onLogin + 1] = function()
	C_Timer.After(4, function() api.showSetup(false) end)
end
