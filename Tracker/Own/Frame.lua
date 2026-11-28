-- ForeverTrackerPlus: our own tracker (OWN_TRACKER_PLAN.md). Since 3.2 the only tracker: the old one (Blizzard's
-- tracker in our scroll window) was removed (user: "Delete the old tracker's code").
--
-- Why: moving, sizing and writing fields on Blizzard's ObjectiveTrackerFrame tainted Blizzard's own layout in
-- battlegrounds ("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted"). Here we draw our own list
-- in our own frame and only READ quest data. Blizzard's tracker stays shown at opacity 0 with its mouse off (never
-- Hide: see "Blizzard's tracker" below). Nothing else of ours moves, sizes or hooks Blizzard's tracker.
--
-- LAYOUT (phase 2), inside frame.inner (scaled by db.scale):
--   main header    "All Objectives" with Blizzard's header art (Look.lua api.ownMirror) and a collapse button
--   quests header  "Quests", the quest log count (db.questCount), a collapse button; db.questsPadY below it
--   scroll         the quest list (Data.lua api.ownBuild); mouse wheel (db.step), scrollbar (db.scrollbar, width,
--                  mouseover only, on the left when the right side is off screen), background (db.background)
-- Settings: db.pos, db.height, db.scale, db.widthExtra, db.layer, the opacities and the combat and raid fades (Core's
-- api.trackerAlpha, db.questAlpha), db.spacing, db.zoneHeaderPadY, db.zoneHeaderY, fonts (Look.lua). A setting
-- changed in the settings window reaches us through Core's api setters (hooked below).
--
-- RULE (tests/own_tracker_rules_test.lua): on Blizzard's tracker, its modules, blocks and headers this file calls
-- only SetAlpha, EnableMouse(false), hooksecurefunc and reads. No Hide, Show, SetPoint, SetSize, SetScale, SetParent,
-- field writes, Update or MarkDirty.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api
local blizz = _G.ObjectiveTrackerFrame

local db
local frame, inner, mainHeader, questsHeader, scroll, child, handle, bar, thumb, background
local guideHost, guideH = nil, 0 -- phase 4: the RestedXP guide section's slot, under the main header (Objectives/tracker/Tracker.lua)
local cardHost, cardH = nil, 0 -- phase 4b: the dungeon card's slot, above the guide (Dungeon.lua)
local repHeader -- the "Reputation" header over the tracked reputation bar in that slot (user)
local GUIDE_GAP, QUESTS_MIN = 4, 80
-- CONSTRAINT: the guide's rows carry secure buttons (the circles), so our frame and the guide's slot are protected
-- in combat while the guide shows: no move, size or hide of them then; it waits for the fight to end.
local pendingLayout = false -- a layout that waited for the end of combat
local function lockedNow() return InCombatLockdown and InCombatLockdown() and frame and frame:IsProtected() end
local rows = {} -- pooled FontStrings
local marks = {} -- pooled left-column markers: { icon = Texture, text = FontString }
local MARK_W, SUPER_W = 20, 10 -- the marker column left of the titles, and the focus arrow left of it
local dirty = false
local PAD, ROW_GAP, OBJ_INDENT = 6, 2, 10
-- the quest list reaches this far left of the header bars (user: room for titles and their icons moved left); the
-- list's x 0 is there, so every x below adds it
local LEFT_ROOM = 40
local HEADER_H, QUESTS_H = 26, 24

function api.ownTrackerFrame() return frame end
local function clamp(v, lo, hi, d) v = tonumber(v) or d; return math.min(math.max(v, lo), hi) end

---------------------------------------------------------------------------------------------------------------------
-- Blizzard's tracker: opacity 0 and click-through, never hidden.
-- CONSTRAINT (user: the secret-aura error came back with Hide): Hide() from our code runs Blizzard's hide handlers,
-- which mark the tracker's container for a new layout under our taint; that layout reaches the scenario module and
-- the secret aura read is blocked. EllesmereUI's notes (its Forever custom tracker) found the same and use alpha plus
-- mouse off. So: SetAlpha(0), kept at 0 by a post-hook (Edit Mode and managed frames set it back), and the mouse
-- off on the named click parts of each block (EnableMouse runs no script and writes no Lua field). The scenario and
-- UI widget sections share the game's widget pool with tooltips: only their fixed blocks, never pooled widgets.
local muted = false
local mouseOff = setmetatable({}, { __mode = "k" }) -- frames we switched off (never switched back: a reload is needed)
local laterOff = {} -- protected frames met in combat: switched off after it
local function noMouse(f)
	if type(f) ~= "table" or not f.EnableMouse or not f.IsMouseEnabled or mouseOff[f] then return end
	if not f:IsMouseEnabled() then return end
	if InCombatLockdown() and f.IsProtected and f:IsProtected() then laterOff[#laterOff + 1] = f return end
	mouseOff[f] = true
	f:EnableMouse(false)
end
local function blockNoMouse(block)
	if type(block) ~= "table" then return end
	noMouse(block)
	noMouse(block.HeaderButton)
	noMouse(block.ItemButton)
	noMouse(block.poiButton)
	if type(block.usedLines) == "table" then
		for _, line in pairs(block.usedLines) do noMouse(line) end
	end
	if type(block.addedRegions) == "table" then
		for region in pairs(block.addedRegions) do
			noMouse(region)
			if type(region) == "table" then noMouse(region.Bar) end
		end
	end
end
local MODULES = { "ScenarioObjectiveTracker", "UIWidgetObjectiveTracker", "CampaignQuestObjectiveTracker",
	"QuestObjectiveTracker", "AdventureObjectiveTracker", "AchievementObjectiveTracker",
	"MonthlyActivitiesObjectiveTracker", "ProfessionsRecipeTracker", "BonusObjectiveTracker",
	"WorldQuestObjectiveTracker", "InitiativeTasksObjectiveTracker" }
local function sharesWidgets(module)
	return module == _G.ScenarioObjectiveTracker or module == _G.UIWidgetObjectiveTracker
end
local function eachModule(fn)
	local seen = {}
	local list = blizz and (blizz.modules or blizz.MODULES)
	for _, m in ipairs(type(list) == "table" and list or {}) do
		if type(m) == "table" and not seen[m] then seen[m] = true; fn(m) end
	end
	for _, name in ipairs(MODULES) do
		local m = _G[name]
		if type(m) == "table" and not seen[m] then seen[m] = true; fn(m) end
	end
end
-- Phase 5 starts with a check in game (plan): which of Blizzard's sections Forever's tracker has, and which hold
-- something now. Reads only (fields and Get/Is calls), nothing is changed on Blizzard's tracker.
local function moduleName(m)
	for _, name in ipairs(MODULES) do if _G[name] == m then return name end end
	local ok, n = pcall(m.GetName, m)
	return ok and n or tostring(m)
end
local function blockCount(m)
	local n = 0
	if type(m.usedBlocks) == "table" then
		for _, byTemplate in pairs(m.usedBlocks) do
			if type(byTemplate) == "table" then for _ in pairs(byTemplate) do n = n + 1 end end
		end
	end
	return n
end
function api.ownSectionsReport(say)
	local n = 0
	eachModule(function(m)
		n = n + 1
		local okS, shown = pcall(m.IsShown, m)
		local okH, h = pcall(m.GetHeight, m)
		local header = m.Header and m.Header.Text
		local okT, title = header and pcall(header.GetText, header)
		say(("%s: title %s; blocks %d; has contents %s; shown %s; height %d"):format(moduleName(m),
			okT and tostring(title) or "-", blockCount(m), tostring(m.hasContents),
			okS and tostring(shown) or "?", okH and math.floor(tonumber(h) or 0) or 0))
	end)
	if n == 0 then say("no Blizzard tracker sections found") end
	for _, name in ipairs(MODULES) do
		if _G[name] == nil then say(name .. ": not in this client") end
	end
end
if api.addSlash then
	api.addSlash("sections", "list Blizzard's tracker sections in this client and what they hold now",
		function(_, say) api.ownSectionsReport(say) end)
end
local addHooked = setmetatable({}, { __mode = "k" })
local function moduleNoMouse(m)
	if m.Header then noMouse(m.Header.MinimizeButton) end
	if sharesWidgets(m) then
		if m == _G.ScenarioObjectiveTracker then
			blockNoMouse(m.ObjectivesBlock)
			if m.StageBlock then noMouse(m.StageBlock); noMouse(m.StageBlock.findGroupButton) end
			noMouse(m.ProvingGroundsBlock)
			if m.MawBuffsBlock then noMouse(m.MawBuffsBlock.Container) end
		end
		return
	end
	if type(m.usedBlocks) == "table" then
		for _, byTemplate in pairs(m.usedBlocks) do
			if type(byTemplate) == "table" then
				for _, block in pairs(byTemplate) do blockNoMouse(block) end
			end
		end
	end
	if not addHooked[m] and type(m.AddBlock) == "function" then
		addHooked[m] = true
		hooksecurefunc(m, "AddBlock", function(_, block) if muted then blockNoMouse(block) end end)
	end
end
local function sweep()
	if not muted then return end
	if blizz and blizz.Header then noMouse(blizz.Header.MinimizeButton); noMouse(blizz.Header.FilterButton) end
	eachModule(moduleNoMouse)
end
api.ownMouseOffCount = function() local n = 0 for _ in pairs(mouseOff) do n = n + 1 end return n end -- for tests
local sweepQueued = false
local function sweepSoon()
	if sweepQueued then return end
	sweepQueued = true
	C_Timer.After(0, function() sweepQueued = false; sweep() end)
end
local regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function()
	local list = laterOff
	laterOff = {}
	for _, f in ipairs(list) do noMouse(f) end
	sweep()
end)
local function startHiding()
	if muted or not blizz then return end
	muted = true
	blizz:SetAlpha(0)
	hooksecurefunc(blizz, "SetAlpha", function(self, a) if muted and a ~= 0 then self:SetAlpha(0) end end)
	sweep()
	-- blocks Blizzard hands out later: the AddBlock hooks, and a sweep after each of its updates (next frame)
	if ObjectiveTrackerContainerMixin and ObjectiveTrackerContainerMixin.Update then
		hooksecurefunc(ObjectiveTrackerContainerMixin, "Update", function(container)
			if container == blizz then sweepSoon() end
		end)
	end
	pcall(regen.RegisterEvent, regen, "PLAYER_REGEN_ENABLED")
end

---------------------------------------------------------------------------------------------------------------------
-- Sizes and look values
local function width()
	local w = blizz and blizz:GetWidth() or 0
	if not w or w < 50 then w = 260 end
	return math.max(w, 150) + (tonumber(db.widthExtra) or 0)
end
local function barWidth() return clamp(db.scrollbarWidth, 2, 30, 10) end
-- the gap between two quests: Blizzard's own (read) changed by "Space between quests" (db.spacing), as Extras did
local function questGap()
	local module = _G.QuestObjectiveTracker
	local base = module and tonumber(module.fromBlockOffsetY) or -10
	return math.max(base * -1 + (tonumber(db.spacing) or 0), 0)
end
api.ownQuestGap = function() return questGap() end -- for tests
local function zoneColor()
	local c = type(db.zoneHeaderColor) == "table" and db.zoneHeaderColor or { 0.2, 0.85, 0.55 }
	return c[1] or 0.2, c[2] or 0.85, c[3] or 0.55, tonumber(c[4]) or 1
end
local function questAlpha() return clamp(db.questAlpha, 0.1, 1, 1) end
local function frameAlpha() return api.trackerAlpha and api.trackerAlpha() or 1 end

-- the classifier's marker (Extras.lua): a string ("[+3]") or an icon { atlas, file, scale } -> inline text (used for
-- tests and text markers; the list draws icons as textures in their own column, user: "they shouldn't push quest
-- titles over to be misaligned with others")
local function markerText(m)
	if type(m) == "string" then return m ~= "" and m or nil end
	if type(m) ~= "table" then return nil end
	local size = math.floor(14 * (tonumber(m.scale) or 1) + 0.5)
	if m.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(m.atlas) then
		return ("|A:%s:%d:%d|a"):format(m.atlas, size, size)
	end
	if m.file then return ("|T%s:%d:%d|t"):format(m.file, size, size) end
	return nil
end
api.ownMarkerText = markerText -- for tests

-- the quest log count on the Quests header, coloured by how full the log is (as MoreQuests' count)
local function countColor(count, max)
	if count >= max then return 1, 0.2, 0.2 end
	if count >= math.floor(max * 37 / 40 + 0.5) then return 1, 0.55, 0.1 end
	if count >= math.floor(max * 27 / 40 + 0.5) then return 1, 0.9, 0.2 end
	return 0.3, 0.9, 0.3
end
local function updateCount()
	local text = questsHeader and questsHeader.count
	if not text then return end
	local ok, _, quests = pcall(C_QuestLog.GetNumQuestLogEntries)
	local max = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 40
	if db.questCount == false or not ok or type(quests) ~= "number" or type(max) ~= "number" or max <= 0
		or (issecretvalue and issecretvalue(quests)) then
		text:SetText("")
		return
	end
	local file, size, flags = api.ownFontSpec("header")
	local own = tonumber(db.questCountSize) or 0
	pcall(text.SetFont, text, file, own > 0 and own or size, flags)
	text:SetText(("%d/%d"):format(quests, max))
	local saved = type(db.questCountColor) == "table" and db.questCountColor or nil
	local alpha = saved and saved[4] or 1
	if db.questCountCustom and saved then text:SetTextColor(saved[1], saved[2], saved[3], alpha)
	else local r, g, b = countColor(quests, max); text:SetTextColor(r, g, b, alpha) end
	if api.animCount then api.animCount(text, quests, max) end
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing the list
-- a title's extras live on the list, not on the row: icons, the check and the distance hide with the row (user: icons,
-- checks and distances stayed on screen with the quests collapsed)
local function clearExtras(fs)
	if api.hideTitleIcons then api.hideTitleIcons(fs) end
	if api.hideQuestDistance then api.hideQuestDistance(fs) end
	if fs.qtsCheck then fs.qtsCheck:Hide() end
	fs.qtsReserve = nil
end
local function row(i)
	local fs = rows[i]
	if not fs then
		fs = child:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("LEFT")
		rows[i] = fs
	end
	fs:SetWordWrap(db.wordWrap ~= false)
	fs:ClearAllPoints()
	-- pooled: a row was a title before (icons, check, distance) or an objective (none of those)
	clearExtras(fs)
	fs:SetAlpha(1) -- an animation (Animations.lua) may have faded this row for another quest
	fs:Show()
	return fs
end

-- progress bars on objectives (Extras.lua's bar, as on Blizzard's quests and More quests)
local bars, barUsed = {}, 0
local BAR_GAP = 6
local function progressBar()
	barUsed = barUsed + 1
	local b = bars[barUsed]
	if not b then
		b = api.newProgressBar(child)
		bars[barUsed] = b
	end
	return b
end
api.ownBarsForTests = function() return bars, barUsed end

-- the room the title icons take left of a title (Extras.lua placeTitleIcons: 2 px gap, icons 3 px apart)
local function iconsWidth(n)
	if n <= 0 then return 0 end
	local size = math.floor(14 * (tonumber(db.iconScale) or 1) + 0.5)
	return 2 + n * size + (n - 1) * 3
end

local updateScrollbar, layoutBackground -- below
local listLeft = 0 -- how far the drawn list reaches left of the headers (rebuild), for the background
-- phase 5 (user: "Yes, start"): our zone headers by zone name, for the tags on them (Rares.lua's rare, Chains.lua's
-- "Explored 7/12"); ZoneSort.lua api.zoneLabelFor asks here with our own tracker
local zoneLabels = {}
function api.ownZoneLabelFor(zone)
	local fs = type(zone) == "string" and zoneLabels[zone]
	if fs and fs:IsShown() then return fs end
end
local markDirty, styleButton, makeHeader -- below
local function rebuild()
	dirty = false
	if not frame then return end
	local listW = width() - PAD * 2 + LEFT_ROOM
	child:SetWidth(listW)
	local n, y = 0, 0
	local markN = 0
	barUsed = 0
	if api.animBegin then api.animBegin() end
	if api.ownClickersReset then api.ownClickersReset() end
	if api.ownItemsReset then api.ownItemsReset(child, scroll) end
	for k in pairs(zoneLabels) do zoneLabels[k] = nil end
	-- a quest's text marker ("[+3]") and focus arrow in the column left of its title (left of its icons, iconsW),
	-- centred on the title's first line; icon markers are drawn with the title icons (placeTitleIcons)
	local function drawMark(fs, m, super, lineH, iconsW)
		iconsW = iconsW or 0
		if type(m) == "table" then m = nil end
		if not m and not super then return end
		markN = markN + 1
		local k = marks[markN]
		if not k then
			k = { icon = child:CreateTexture(nil, "OVERLAY"), text = child:CreateFontString(nil, "OVERLAY"),
				super = child:CreateFontString(nil, "OVERLAY") }
			k.text:SetJustifyH("RIGHT")
			marks[markN] = k
		end
		k.icon:Hide(); k.text:Hide(); k.super:Hide()
		if type(m) == "string" and m ~= "" then
			k.text:SetFontObject(api.ownFont("line"))
			k.text:SetText(m)
			k.text:ClearAllPoints()
			k.text:SetPoint("RIGHT", fs, "TOPLEFT", -2 - iconsW, -lineH / 2)
			k.text:Show()
		end
		if super then
			k.super:SetFontObject(api.ownFont("title"))
			k.super:SetText(">")
			k.super:SetTextColor(1, 0.82, 0)
			k.super:ClearAllPoints()
			k.super:SetPoint("RIGHT", fs, "TOPLEFT", -2 - iconsW - (m and MARK_W + 2 or 0), -lineH / 2)
			k.super:Show()
		end
		api.ownLastMark = k -- for tests
	end
	local function line(font, x, text, r, g, b, a, rightPad)
		n = n + 1
		local fs = row(n)
		fs:SetFontObject(font)
		fs:SetWidth(math.max(listW - x - (rightPad or 0), 20))
		fs:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
		-- a coin amount whose coin would wrap without its number starts the next line (Extras.lua)
		if api.keepCoinsTogether then text = api.keepCoinsTogether(fs, text) end
		fs:SetText(text)
		fs:SetTextColor(r or 1, g or 0.82, b or 0, a or 1)
		y = y + fs:GetStringHeight() + ROW_GAP
		return fs
	end
	local data = api.ownBuild and api.ownBuild() or { groups = {}, count = 0 }
	updateCount()
	local titleFont, lineFont, zoneFont = api.ownFont("title"), api.ownFont("line"), api.ownFont("zone")
	local zx = tonumber(db.zoneHeaderX) or 4
	local qx = (tonumber(db.questTitleX) or 0) + (data.groups[1] and data.groups[1].zone and 8 or 0)
	-- a negative offset (zoneHeaderX -9, user setting) had room left of Blizzard's blocks; our scroll area clips at 0,
	-- so the whole list moves right until nothing starts left of the edge (user: zone headers cut off on the left)
	-- the column left of the titles: the type marker (skull, dungeon, [+3]) and the focus arrow, so every title starts
	-- at the same x whether it has a marker or not
	-- per quest: its title icons (the Forever infinity furthest out, the attunement star, the type icon next to the
	-- title, as Extras.lua) and the slots they take (a finished quest's check takes one when it has no icon)
	local leftNeed = 0
	for _, g in ipairs(data.groups) do
		for _, q in ipairs(g.quests) do
			local icons = {}
			local forever = api.foreverIcon and api.foreverIcon(q.id)
			if forever then icons[#icons + 1] = forever end
			local star = api.attunementIcon and api.attunementIcon(q.id)
			if star then icons[#icons + 1] = star end
			if db.condense ~= false and type(q.marker) == "table" then icons[#icons + 1] = q.marker end
			-- 3.2 (user idea 35): a crossed icon on a dead-end quest (DeadEnd.lua)
			local dead = db.condense ~= false and api.deadEndIcon and api.deadEndIcon(q.id)
			if dead then icons[#icons + 1] = dead end
			q.icons = icons
			local slots = #icons
			if slots == 0 and q.complete and db.completeCheck ~= false then slots = 1 end
			q.iconsW = iconsWidth(slots)
			local textMark = db.condense ~= false and type(q.marker) == "string" and q.marker ~= ""
			local need = q.iconsW + (textMark and MARK_W + 2 or 0) + (q.superTracked and SUPER_W or 0)
			if need > leftNeed then leftNeed = need end
		end
	end
	-- the objective lines start from where the titles would be with the title slider at 0 (user: the title slider moved
	-- the objectives once the title passed the icon column)
	-- a negative zone header X moves the whole list right; the icon column moves only the titles and lines (user: the
	-- title slider moved the zone headers below -14 px)
	-- the list starts LEFT_ROOM left of the headers: a title can go that far left with its icons (user). Past that the
	-- titles stop, a zone header X past it moves the whole list right.
	local indent = data.groups[1] and data.groups[1].zone and 8 or 0
	local base = LEFT_ROOM + math.max(0, -(zx + LEFT_ROOM))
	local ox = math.max(indent + base, leftNeed)
	zx, qx = zx + base, math.max(qx + base, leftNeed)
	-- how far the drawing reaches left of the headers: the background reaches as far
	local leftmost = math.min(zx, qx - leftNeed, ox + OBJ_INDENT + math.min(tonumber(db.objectiveX) or 0, 0))
	listLeft = math.max(0, LEFT_ROOM - math.max(leftmost, 0))
	api.ownOffsets = { zone = zx - LEFT_ROOM, quest = qx - LEFT_ROOM, left = listLeft } -- for tests, from the headers' edge
	local gap, zonePad, zoneY = questGap(), tonumber(db.zoneHeaderPadY) or 6, tonumber(db.zoneHeaderY) or 0

	-- 3.2 (user idea 34): "(N turn-ins)" on a zone where two or more of your finished quests are taken in
	local turnins = api.turnInBundles and api.turnInBundles(data.groups) or {}
	for _, g in ipairs(data.groups) do
		if g.zone then
			if y > 0 then y = y + zonePad end
			local zr, zg, zb, za = zoneColor()
			y = y - zoneY
			local bundle = turnins[g.zone] and ("  |cff44ff44(%d turn-ins)|r"):format(turnins[g.zone]) or ""
			zoneLabels[g.zone] = line(zoneFont, zx, (g.folded and "+ " or "") .. g.zone .. ((g.folded and (" (%d)"):format(#g.quests)) or "") .. bundle, zr, zg, zb, za)
			y = y + zoneY + 2
		end
		if g.zone and api.animZone then api.animZone(g.zone, g.folded, g.quests) end
		if not g.folded then
			for _, q in ipairs(g.quests) do
				local tFile, tSize, tFlags = api.ownFontSpec("title")
				local text = q.level and ("[%d] %s"):format(q.level, q.title) or q.title
				-- rewards after the title (XP, gold, items: Extras.lua, "Quest titles" settings)
				if api.rewardSuffix then
					local ok, suffix = pcall(api.rewardSuffix, q.id, tSize)
					if ok and type(suffix) == "string" then text = text .. suffix end
				end
				-- room at the right edge for the distance and arrow, only on a quest that shows a distance
				local reserve = api.questHasDistance and api.questHasDistance(q.id) and api.questDistanceReserve
					and api.questDistanceReserve(tFile, tSize, tFlags) or nil
				local titleY = y
				local fs = line(titleFont, qx, text, q.r, q.g, q.b, nil, reserve and (4 + reserve) or nil)
				local lineH = tonumber(tSize) or 12
				if #q.icons > 0 and api.placeTitleIcons then api.placeTitleIcons(fs, q.icons) end
				if api.placeCheck then api.placeCheck(fs, q.complete) end
				drawMark(fs, db.condense ~= false and q.marker or nil, q.superTracked, lineH, q.iconsW)
				if api.animTitle then api.animTitle(q, fs) end
				fs.qtsReserve = reserve
				if api.attachQuestDistance then api.attachQuestDistance(fs, q.id) end
				-- the distance column reaches below the title: the lines beside it keep its room
				local distBottom = reserve and (titleY + (api.distanceColumnHeight and api.distanceColumnHeight(tSize) or lineH)) or nil
				if api.ownClicker then api.ownClicker(child, fs, q.id, text) end
				-- Objectives horizontal position (db.objectiveX, user): its own slider, not the title's; never left of the
				-- list's edge
				local lx = math.max(ox + OBJ_INDENT + (tonumber(db.objectiveX) or 0), 0)
				-- the item button (user): always left of the quest's first objective line (under the title when it has none)
				local item = api.ownItemFor and api.ownItemFor(q.id)
				local itemPlace = item and api.ownItemAdd and api.ownItemAdd(fs, item)
				local function firstLine(lfs)
					if type(itemPlace) == "table" and not itemPlace.anchor then itemPlace.anchor = lfs end
				end
				local lFile, lSize, lFlags = api.ownFontSpec("line")
				local curIndex, curDone -- the objective being drawn, for the animations
				local function objective(textLine, r, g, b, objectiveText)
					local pad = (distBottom and y < distBottom) and (4 + reserve) or nil
					local name, have, need
					if db.progressBars ~= false and api.progressParts and api.drawProgressBar then
						name, have, need = api.progressParts(textLine)
					end
					local lineFs
					if name then
						local bar = progressBar()
						if api.progressBarUnder and api.progressBarUnder() then
							-- under the objective: the bar on its own line, from the text's left to the right edge
							lineFs = line(lineFont, lx, "- " .. name, r, g, b, nil, pad)
							local top, bottom = api.progressUnderGaps()
							local bh = api.progressUnderBarHeight(lSize)
							y = y - ROW_GAP
							api.drawProgressBar(bar, child, lx, lFile, lSize, lFlags, have, need, "TOPLEFT",
								math.max(listW - lx - 4, 20), bh, -(y + top))
							if api.animBar then api.animBar(q.id, curIndex, bar, have, need) end
							y = y + top + bh + bottom + ROW_GAP
						else
							local room = api.progressBarSize(lSize) + BAR_GAP
							lineFs = line(lineFont, lx, "- " .. name, r, g, b, nil, (pad or 0) + 4 + room)
							api.drawProgressBar(bar, lineFs, BAR_GAP, lFile, lSize, lFlags, have, need)
							if api.animBar then api.animBar(q.id, curIndex, bar, have, need) end
						end
					else
						lineFs = line(lineFont, lx, "- " .. textLine, r, g, b, nil, pad)
					end
					firstLine(lineFs)
					lineFs.qtsHasBar = name and true or nil
					if api.animLine and curIndex then api.animLine(q, curIndex, curDone, lineFs, objectiveText) end
					if api.ownClicker then api.ownClicker(child, lineFs, q.id, text, objectiveText) end
				end
				if q.complete and #q.objectives == 0 then
					local fsDone = line(lineFont, lx, QUEST_WATCH_QUEST_READY or "Ready for turn-in", 0.2, 1, 0.2)
					firstLine(fsDone)
					if api.ownClicker then api.ownClicker(child, fsDone, q.id, text) end
				end
				for i, o in ipairs(q.objectives) do
					curIndex, curDone = i, o.done
					if o.done then objective(o.text, 0.6, 0.6, 0.6, o.text)
					else objective(o.text, 0.85, 0.85, 0.85, o.text) end
				end
				if distBottom and y < distBottom then y = distBottom + ROW_GAP end
				y = y + gap
			end
		end
	end
	for i = n + 1, #rows do rows[i]:Hide(); clearExtras(rows[i]) end
	for i = markN + 1, #marks do marks[i].icon:Hide(); marks[i].text:Hide(); marks[i].super:Hide() end
	for i = barUsed + 1, #bars do if api.hideProgressBar then api.hideProgressBar(bars[i]) end end
	if api.ownClickersDone then api.ownClickersDone() end
	if api.animEnd then api.animEnd() end
	child:SetHeight(math.max(y, 1))
	api.ownContentHeight = y -- for tests and the background
	local max = math.max(y - scroll:GetHeight(), 0)
	if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end
	updateScrollbar()
	layoutBackground()
	if api.ownPlaceItems then api.ownPlaceItems() end
	-- the tags on our zone headers follow the new rows (a pooled row may now be a quest title)
	if api.refreshExploredTag then pcall(api.refreshExploredTag) end
	if api.refreshRares then pcall(api.refreshRares) end
end
api.ownRebuild = rebuild
api.ownRowsForTests = function() return rows end

function markDirty()
	if dirty or not frame then return end
	dirty = true
	C_Timer.After(0, rebuild) -- one rebuild per frame, however many events came
end

---------------------------------------------------------------------------------------------------------------------
-- Scrolling
local function scrollMax() return math.max((child and child:GetHeight() or 0) - (scroll and scroll:GetHeight() or 0), 0) end
local lastActive = 0
local function setOffset(v)
	lastActive = GetTime and GetTime() or 0
	scroll:SetVerticalScroll(math.min(math.max(v, 0), scrollMax()))
	updateScrollbar()
end
-- 3.2 (user): with animations on, the wheel glides to its new place (Animations.lua animScrollStep)
local glider, glideTo
local function onWheel(_, delta)
	local from = glideTo or scroll:GetVerticalScroll()
	local to = math.min(math.max(from - delta * (tonumber(db.step) or 40), 0), scrollMax())
	if not (api.animOn and api.animOn("scroll")) then glideTo = nil; setOffset(to) return end
	glideTo = to
	if not glider then
		glider = CreateFrame("Frame", nil, scroll)
		glider:SetScript("OnUpdate", function(self, elapsed)
			if not glideTo then self:Hide() return end
			local v = api.animScrollStep(scroll:GetVerticalScroll(), glideTo, elapsed)
			setOffset(v)
			if v == glideTo then glideTo = nil; self:Hide() end
		end)
	end
	glider:Show()
end
api.ownScrollBy = function(delta) onWheel(nil, delta) end -- for tests
api.ownScrollState = function() return scroll:GetVerticalScroll(), scrollMax(), scroll:IsShown(), questsHeader:IsShown() end -- for tests

local function barOnLeft()
	local right = frame and frame:GetRight()
	return right ~= nil and (right + barWidth() + 4 > (UIParent:GetWidth() or 0))
end
local function layoutBar()
	if not bar then return end
	bar:ClearAllPoints()
	if barOnLeft() then
		bar:SetPoint("TOPRIGHT", scroll, "TOPLEFT", -2 - PAD, 0)
		bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMLEFT", -2 - PAD, 0)
	else
		bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2 + PAD, 0)
		bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2 + PAD, 0)
	end
	bar:SetWidth(barWidth())
	thumb:SetWidth(barWidth())
end
function updateScrollbar()
	if not bar then return end
	local max = scrollMax()
	local show = db.scrollbar ~= false and max > 0 and scroll:IsShown()
	bar:SetShown(show and true or false)
	if not show then return end
	local trackH, viewH = bar:GetHeight(), scroll:GetHeight()
	if not trackH or trackH <= 0 then return end
	local thumbH = math.min(math.max(viewH / (viewH + max) * trackH, 24), trackH)
	thumb:SetHeight(thumbH)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOP", bar, "TOP", 0, -(scroll:GetVerticalScroll() / max) * (trackH - thumbH))
end
-- "Show on mouseover only": visible while the mouse is over the list or the bar, or while scrolling, then fades
local FADE_DELAY, FADE_TIME = 2, 0.4
local dragging
local function fadeStep(_, elapsed)
	if not bar then return end
	-- (performance) this runs each frame: the alpha is set only when it changes
	if not db.scrollbarMouseover then if bar:GetAlpha() ~= 1 then bar:SetAlpha(1) end return end
	local now = GetTime()
	if dragging or bar:IsMouseOver() or (frame and frame:IsMouseOver()) then lastActive = now end
	local target = (now - lastActive < FADE_DELAY) and 1 or 0
	local alpha = bar:GetAlpha()
	if alpha == target then return end
	local step = (elapsed or 0) / FADE_TIME
	if alpha < target then alpha = math.min(target, alpha + step) elseif alpha > target then alpha = math.max(target, alpha - step) end
	bar:SetAlpha(alpha)
end
local function cursorY()
	local _, y = GetCursorPosition()
	return y / UIParent:GetEffectiveScale()
end
local function makeScrollbar()
	bar = CreateFrame("Frame", nil, inner)
	bar:EnableMouse(true)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", onWheel)
	thumb = CreateFrame("Frame", nil, bar)
	thumb:EnableMouse(true)
	if root.scrollSkin and root.scrollSkin.bar then root.scrollSkin.bar(bar, thumb, function(dir) onWheel(nil, -dir) end) end
	bar:SetScript("OnMouseDown", function()
		local max, trackH, thumbH = scrollMax(), bar:GetHeight(), thumb:GetHeight()
		if max <= 0 or trackH <= thumbH then return end
		local s = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local fraction = ((bar:GetTop() * s - cursorY()) / s - thumbH / 2) / (trackH - thumbH)
		setOffset(math.min(math.max(fraction, 0), 1) * max)
	end)
	thumb:SetScript("OnMouseDown", function()
		dragging = { y = cursorY(), offset = scroll:GetVerticalScroll() }
		thumb:SetScript("OnUpdate", function()
			local max, trackH, thumbH = scrollMax(), bar:GetHeight(), thumb:GetHeight()
			if not dragging or max <= 0 or trackH <= thumbH then return end
			local s = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
			setOffset(dragging.offset + (dragging.y - cursorY()) / s * max / (trackH - thumbH))
		end)
	end)
	thumb:SetScript("OnMouseUp", function() dragging = nil; thumb:SetScript("OnUpdate", nil) end)
	bar:SetScript("OnUpdate", fadeStep)
	bar:Hide()
end

-- the background ("Background behind the tracker"): from the top of the headers to the end of the list (at most the
-- bottom of the window), db.backgroundPad around it
function layoutBackground()
	if not background then return end
	if not db.background then background:Hide() return end
	local pad = tonumber(db.backgroundPad) or 6
	local listH = math.min(api.ownContentHeight or 0, scroll:GetHeight() or 0)
	if not scroll:IsShown() then listH = 0 end
	local top = (mainHeader:IsShown() and mainHeader:GetHeight() or 0)
	local h = top + (questsHeader:IsShown() and (questsHeader:GetHeight() + (tonumber(db.questsPadY) or 0)) or 0) + listH
	local c = type(db.backgroundColor) == "table" and db.backgroundColor or { 0, 0, 0, 0.4 }
	background:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, tonumber(c[4]) or 0.4)
	background:ClearAllPoints()
	background:SetPoint("TOPLEFT", inner, "TOPLEFT", -pad - listLeft, pad)
	background:SetPoint("TOPRIGHT", inner, "TOPRIGHT", pad, pad)
	background:SetHeight(h + 2 * pad)
	background:Show()
end

---------------------------------------------------------------------------------------------------------------------
-- Headers: Blizzard's art, our text and buttons
local function headerText(src, fallback)
	local t = src and src.Text and src.Text.GetText and src.Text:GetText()
	if type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then return t end
	return fallback
end
local applyCollapse -- below
function makeHeader(src, height, fallback, key, parent, textSrc)
	local h = CreateFrame("Frame", nil, parent or inner)
	local sh = src and src.GetHeight and src:GetHeight()
	h:SetHeight(sh and sh > 4 and sh or height)
	local skip = {}
	if src and src.Text then skip[src.Text] = true end
	h.art = api.ownMirror and api.ownMirror(src, h, skip)
	h.srcHeader = src
	h.text = h:CreateFontString(nil, "OVERLAY")
	h.text:SetFontObject(api.ownFont("header"))
	h.text:SetPoint("LEFT", h, "LEFT", 6, 0)
	h.text:SetText(headerText(textSrc or src, fallback))
	local button = CreateFrame("Button", nil, h)
	button:SetPoint("RIGHT", h, "RIGHT", -2, 0)
	button:SetSize(16, 16)
	h.button, h.src, h.key = button, src and src.MinimizeButton, key
	button:SetScript("OnClick", function()
		-- 3.2 (user): the part folds up from its top edge, and rolls down when it opens (Animations.lua animRoll)
		local closing = not db[key]
		local parts = key == "ownQuestsCollapsed" and { scroll } or { questsHeader, scroll, guideHost }
		if key ~= "ownQuestsCollapsed" and api.ownBlocksForTests then
			for _, b in ipairs(api.ownBlocksForTests()) do parts[#parts + 1] = b.host end
		end
		if closing and api.animRoll and api.animOn and api.animOn("roll") then
			api.animRoll(parts, false, function()
				for _, f in ipairs(parts) do if f.qtsRoll then f.qtsRoll:Stop() end end
				db[key] = true
				applyCollapse()
			end)
			return
		end
		db[key] = not db[key] or nil
		applyCollapse()
		if not closing and api.animRoll then api.animRoll(parts, true) end
	end)
	h.count = h:CreateFontString(nil, "OVERLAY")
	h.count:SetJustifyH("RIGHT")
	h.count:SetPoint("RIGHT", button, "LEFT", -6, 0)
	return h
end
-- phase 6: the "Quests" header's colours (Settings > Tracker look: db.questsHeaderColor, db.questsLineColor) on our
-- Quests header, as Extras.lua does on Blizzard's: the line is the header's art (not the Shine / Glow flashes), the
-- colour is the text's and the collapse button's
local function tintTexture(t, c)
	if not t then return end
	if c then
		if not t.qtsTinted then t.qtsAlpha = t:GetAlpha() end
		t:SetVertexColor(c[1], c[2], c[3])
		t:SetAlpha(c[4] or 1)
		t.qtsTinted = true
	elseif t.qtsTinted then
		t:SetVertexColor(1, 1, 1)
		t:SetAlpha(t.qtsAlpha or 1)
		t.qtsTinted = nil
	end
end
local function headerLook(h)
	if not (h and db) then return end
	local line = type(db.questsLineColor) == "table" and db.questsLineColor or nil
	local text = type(db.questsHeaderColor) == "table" and db.questsHeaderColor or nil
	local src = h.srcHeader
	local flash = {}
	if src and h.art and h.art.map then
		if src.Shine and h.art.map[src.Shine] then flash[h.art.map[src.Shine]] = true end
		if src.Glow and h.art.map[src.Glow] then flash[h.art.map[src.Glow]] = true end
	end
	for _, t in ipairs(h.art and h.art.textures or {}) do
		if not flash[t] then tintTexture(t, line) end
	end
	if text then
		h.text:SetTextColor(text[1], text[2], text[3], text[4] or 1)
		h.qtsTextTinted = true
	elseif h.qtsTextTinted then
		h.qtsTextTinted = nil
		local fo = h.text:GetFontObject()
		if fo and fo.GetTextColor then h.text:SetTextColor(fo:GetTextColor()) end
	end
	tintTexture(h.button:GetNormalTexture(), text)
	tintTexture(h.button:GetPushedTexture(), text)
end
function api.ownApplyHeaderLook() if questsHeader then headerLook(questsHeader) end end
function styleButton(h)
	local collapsed = db[h.key] and true or false
	if not (api.ownMirrorButton and api.ownMirrorButton(h.src, h.button, collapsed)) then
		h.button:SetNormalFontObject(GameFontNormal)
		h.button:SetText(collapsed and "+" or "-")
	end
	if h == questsHeader then headerLook(h) end
end
-- Phase 5: blocks above the Quests header, each with its own header and collapse button, not in the quest list
-- (collapsing Quests leaves them alone):
--   Professions (Recipes.lua): tracked recipes and their reagents (user: "the tracked recipes should show above the
--     questlist separately")
--   Legacy Challenges (Legacy.lua): the ones you track from the Guides > Legacy page (user: Forever has Legacy
--     Challenges, not achievements, and no way to track them)
-- A block: { key, name, read = fn() -> entries, clicker, reset, done, host, header, rows, h }. An entry: { title,
-- item = what its clicker gets, lines = { { text, dim, more, extra = the clicker's extra argument } } }.
local function professionEntries()
	local out = {}
	for _, r in ipairs(api.ownRecipes and api.ownRecipes() or {}) do
		local e = { title = r.recraft and (r.name .. " (" .. (PROFESSIONS_RECRAFTING or "Recrafting") .. ")") or r.name,
			item = r, lines = {} }
		for _, g in ipairs(r.reagents) do
			e.lines[#e.lines + 1] = { text = ("%d/%d %s"):format(math.min(g.have, g.need), g.need, g.name),
				dim = g.have >= g.need, extra = g.itemID }
		end
		out[#out + 1] = e
	end
	return out
end
local function legacyEntries()
	local out = {}
	for _, a in ipairs(api.ownLegacy and api.ownLegacy() or {}) do
		local e = { title = a.need > 0 and ("%s (%d/%d)"):format(a.name, a.have, a.need) or a.name, item = a, lines = {},
			icon = a.icon } -- 3.2 (user): the challenge's icon left of its name
		for _, l in ipairs(a.lines) do e.lines[#e.lines + 1] = { text = l.text, more = l.more } end
		out[#out + 1] = e
	end
	return out
end
local blocks = {
	{ key = "ownProfCollapsed", frameName = "ForeverTrackerPlusOwnProfessions", textSrc = "ProfessionsRecipeTracker",
		name = PROFESSIONS_TRACKER_HEADER_PROFESSION or "Professions", read = professionEntries,
		clicker = function(...) if api.ownRecipeClicker then api.ownRecipeClicker(...) end end,
		reset = function() if api.ownRecipeClickersReset then api.ownRecipeClickersReset() end end,
		done = function() if api.ownRecipeClickersDone then api.ownRecipeClickersDone() end end },
	{ key = "ownLegacyCollapsed", frameName = "ForeverTrackerPlusOwnLegacy", name = "Legacy Challenges", read = legacyEntries,
		clicker = function(parent, fs, item) if api.ownLegacyClicker then api.ownLegacyClicker(parent, fs, item) end end,
		reset = function() if api.ownLegacyClickersReset then api.ownLegacyClickersReset() end end,
		done = function() if api.ownLegacyClickersDone then api.ownLegacyClickersDone() end end },
	-- Battlegrounds (Battleground.lua, user): in a battleground, its timer bars (start, nodes, flags)
	{ key = "ownBgCollapsed", frameName = "ForeverTrackerPlusOwnBattlegrounds", name = "Battleground",
		read = function() return api.ownBattleground and api.ownBattleground() or {} end,
		clicker = function(...) if api.ownBgClicker then api.ownBgClicker(...) end end,
		reset = function() if api.ownBgClickersReset then api.ownBgClickersReset() end end,
		done = function() if api.ownBgClickersDone then api.ownBgClickersDone() end end },
}
for _, b in ipairs(blocks) do b.rows, b.h = {}, 0 end
local profBlock = blocks[1]
local function blocksHeight()
	local h = 0
	for _, b in ipairs(blocks) do if b.h > 0 then h = h + b.h + GUIDE_GAP end end
	return h
end
local function drawBlock(b, show)
	local entries = show and b.read() or {}
	b.reset()
	local n, y, ic = 0, 0, 0
	local host, header, rowsB = b.host, b.header, b.rows
	b.icons = b.icons or {}
	if #entries > 0 then
		host:Show()
		styleButton(header)
		y = (header:GetHeight() or QUESTS_H) + 2
		if not db[b.key] then
			local hw = host:GetWidth()
			if not hw or hw <= 0 then hw = width() end
			local titleFont, lineFont = api.ownFont("title"), api.ownFont("line")
			local function line(font, x, text, r, g, bl)
				n = n + 1
				local fs = rowsB[n]
				if not fs then
					fs = host:CreateFontString(nil, "OVERLAY")
					fs:SetJustifyH("LEFT")
					rowsB[n] = fs
				end
				fs:SetFontObject(font)
				fs:SetWordWrap(db.wordWrap ~= false)
				fs:ClearAllPoints()
				fs:SetWidth(math.max(hw - x - PAD, 20))
				fs:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
				fs:SetText(text)
				fs:SetTextColor(r, g, bl, 1)
				fs:SetAlpha(1) -- a timer bar hides its row's own text (Battleground.lua)
				fs:Show()
				y = y + fs:GetStringHeight() + ROW_GAP
				return fs
			end
			for i, e in ipairs(entries) do
				if i > 1 then y = y + questGap() end
				-- an entry's icon (a Legacy Challenge's, user) left of its title, as the quest title icons: the title stays
				-- where it is (user: "shouldn't push the name to the right"); the icon sits in the room left of it
				local icon = e.icon
				if icon ~= nil and (type(icon) ~= "number" and type(icon) ~= "string" or (issecretvalue and issecretvalue(icon))) then icon = nil end
				local iconW = math.floor(14 * (tonumber(db.iconScale) or 1) + 0.5)
				local fs = line(titleFont, PAD, e.title, 1, 0.82, 0)
				if icon then
					ic = ic + 1
					local t = b.icons[ic]
					if not t then t = host:CreateTexture(nil, "ARTWORK"); b.icons[ic] = t end
					t:SetSize(iconW, iconW)
					t:ClearAllPoints()
					t:SetPoint("TOPRIGHT", fs, "TOPLEFT", -2, 1)
					t:SetTexture(icon)
					t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
					t:Show()
				end
				b.clicker(host, fs, e.item)
				for _, l in ipairs(e.lines) do
					local c = (l.dim or l.more) and 0.6 or 0.85
					local lineFs = line(lineFont, math.max(PAD + OBJ_INDENT + (tonumber(db.objectiveX) or 0), 0), (l.more and "" or "- ") .. l.text, c, c, c)
					b.clicker(host, lineFs, e.item, l.extra)
					if l.bar then y = y + 6 end -- a timer bar (the reputation bar's look) is taller than its line
				end
			end
			y = y + 2
		end
	else
		host:Hide()
	end
	for i = n + 1, #rowsB do rowsB[i]:Hide() end
	for i = ic + 1, #b.icons do b.icons[i]:Hide() end
	b.done()
	b.h = y
	host:SetHeight(math.max(y, 1))
	return y
end
api.ownProfRowsForTests = function() return profBlock.rows, profBlock.host, profBlock.header end
api.ownBlocksForTests = function() return blocks end
api.ownRepHeaderForTests = function() return repHeader end

function applyCollapse()
	if not frame then return end
	local all, quests = db.ownAllCollapsed and true or false, db.ownQuestsCollapsed and true or false
	-- Phase 4b: the dungeon card (Dungeon.lua) at the very top, in a dungeon or raid (WoW Forever has no scenarios: the
	-- card is its instance section). The card sits on UIParent at our slot's place and holds nothing protected, so it
	-- is drawn in combat too; only our slot's height waits for the end of a fight (the guide's slot hangs under it).
	-- Phase 5: the tracked reputation bar (Reputation.lua) and the reminders row (Reminders.lua) under the card, in the
	-- same slot, as on the classic tracker. Each takes the room above it as its base (UIParent units).
	local base = 0
	local s = (cardHost:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	if s <= 0 then s = 1 end
	for _, name in ipairs({ "layoutDungeonCard", "layoutTrackedReputation", "layoutReminders" }) do
		local layout = api[name]
		local anchor = (not all) and cardHost or nil
		-- the tracked reputation under its own "Reputation" header, which folds it away (user)
		if name == "layoutTrackedReputation" and repHeader then
			local shows = anchor and api.trackedReputationShown and api.trackedReputationShown()
			repHeader:SetShown(shows and true or false)
			if shows then
				repHeader:ClearAllPoints()
				repHeader:SetPoint("TOPLEFT", cardHost, "TOPLEFT", 0, -base / s)
				repHeader:SetPoint("TOPRIGHT", cardHost, "TOPRIGHT", 0, -base / s)
				styleButton(repHeader)
				base = base + ((repHeader:GetHeight() or QUESTS_H) + 4) * s
				if db.ownRepCollapsed then anchor = nil end
			end
		end
		if layout then
			local ok, r = pcall(layout, anchor, base, frameAlpha())
			if ok and type(r) == "number" and r > 0 then base = base + r end
		end
	end
	local room = base > 0 and base / s or 0
	if lockedNow() then pendingLayout = true return end
	cardH = room
	cardHost:SetHeight(math.max(room, 1))
	local top, topGap = room > 0 and cardHost or mainHeader, room > 0 and -GUIDE_GAP or -2
	questsHeader:SetShown(not all)
	scroll:SetShown(not all and not quests)
	-- the guide's slot: as tall as the guide (it tells us), nothing when collapsed or without a guide
	local showGuide = not all and guideH > 0
	guideHost:SetShown(showGuide)
	guideHost:SetHeight(showGuide and guideH or 1)
	guideHost:ClearAllPoints()
	guideHost:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, topGap)
	guideHost:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, topGap)
	questsHeader:ClearAllPoints()
	local above, gap = top, topGap
	if showGuide then above, gap = guideHost, -GUIDE_GAP end
	for _, b in ipairs(blocks) do
		b.host:ClearAllPoints()
		b.host:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, gap)
		b.host:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, gap)
		if drawBlock(b, not all) > 0 then above, gap = b.host, -GUIDE_GAP end
	end
	questsHeader:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, gap)
	questsHeader:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, gap)
	styleButton(mainHeader)
	styleButton(questsHeader)
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", questsHeader, "BOTTOMLEFT", PAD - LEFT_ROOM, -(tonumber(db.questsPadY) or 0) - 2)
	scroll:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -PAD, PAD)
	updateScrollbar()
	layoutBackground()
end
api.ownApplyCollapse = function() if frame then applyCollapse() end end

-- Phase 4: the guide section (Objectives/tracker/Tracker.lua) lives in guideHost. The guide asks how much room it has
-- (the frame less the headers and QUESTS_MIN for the quests) and says how tall it drew itself.
function api.ownGuideHost() return guideHost end
api.ownHeadersForTests = function() return mainHeader, questsHeader end
function api.ownGuideRoom()
	if not inner then return 0 end
	return math.max((inner:GetHeight() or 0) - HEADER_H - cardH - blocksHeight() - QUESTS_H - GUIDE_GAP - QUESTS_MIN, 0)
end
function api.ownCardHost() return cardHost end
-- the Quests header, for the dungeon card's header (same width, height and line: Dungeon.lua)
function api.ownQuestsHeaderFrame() return questsHeader end
function api.ownGuideCollapsed() return db and db.ownAllCollapsed and true or false end
function api.ownSetGuideHeight(h)
	h = math.max(tonumber(h) or 0, 0)
	if math.abs(h - guideH) < 0.5 then return end
	guideH = h
	if frame then applyCollapse() end
end
-- the main header's parts, for the guide's buttons (settings, guides) and its paused indicator (Header.lua)
function api.ownMainHeader()
	if not mainHeader then return nil end
	return { frame = mainHeader, Text = mainHeader.text, MinimizeButton = mainHeader.button }
end

---------------------------------------------------------------------------------------------------------------------
-- Frame: at the saved spot (db.pos), with the saved height, scale, layer, opacity and lock.
local function place()
	frame:ClearAllPoints()
	local pos = type(db.pos) == "table" and db.pos or { "CENTER", "CENTER", 0, 0 }
	frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	local s = clamp(db.scale, 0.3, 3, 1)
	local h = (tonumber(db.height) and db.height > 0) and db.height or 500
	h = math.min(h, UIParent:GetHeight() or h)
	frame:SetSize(width() * s, h)
	inner:SetScale(s)
	inner:SetSize(width(), h / s)
	layoutBar()
end
local function applyLevel()
	local strata, level = "LOW", 1
	if api.layerFromValue and db.layer then strata, level = api.layerFromValue(db.layer) end
	frame:SetFrameStrata(strata)
	frame:SetFrameLevel(level)
end
local function applyAlpha()
	frame:SetAlpha(frameAlpha())
	child:SetAlpha(questAlpha())
end
-- every setting at once (fonts, place, layer, opacity, collapse, list)
local function refresh()
	if not frame then return end
	if api.ownApplyFonts then api.ownApplyFonts() end
	if lockedNow() then
		-- in combat with the guide's secure buttons inside: opacity and the list now, the rest after the fight
		pendingLayout = true
	else
		pendingLayout = false
		place()
		applyLevel()
		applyCollapse()
	end
	applyAlpha()
	markDirty()
	-- the guide section lays itself out again in its slot (its width and room may have changed)
	if api.ownGuideChanged then api.ownGuideChanged() end
end
api.ownRefresh = refresh
api.ownPlace = refresh

local function makeHandle()
	handle = CreateFrame("Frame", nil, frame)
	handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
	handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
	handle:SetHeight(18)
	local bg = handle:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.5, 0.9, 0.5)
	local label = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText("Quest tracker")
	handle:EnableMouse(true)
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetText("Quest tracker", 1, 0.82, 0)
		GameTooltip:AddLine("Drag to move. Right-click to lock it in place.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
	-- the frame follows the cursor through SetPoint (StartMoving is restricted in Forever, see Core.lua)
	local offset
	local function cursor()
		local s = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		return x / s, y / s
	end
	handle:SetScript("OnMouseDown", function(_, button)
		if button == "RightButton" then if api.setLocked then api.setLocked(true) end return end
		if button ~= "LeftButton" or InCombatLockdown() then return end
		local left, top = frame:GetLeft(), frame:GetTop()
		if not (left and top) then return end
		local cx, cy = cursor()
		offset = { left - cx, top - cy }
		handle:SetScript("OnUpdate", function()
			local x, y = cursor()
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + offset[1], y + offset[2])
		end)
	end)
	handle:SetScript("OnMouseUp", function()
		if not handle:GetScript("OnUpdate") then return end
		handle:SetScript("OnUpdate", nil)
		local left, top = frame:GetLeft(), frame:GetTop()
		if left and top then db.pos = { "TOPLEFT", "BOTTOMLEFT", left, top } end
		layoutBar()
	end)
	handle:SetShown(not db.locked)
end
function api.ownLockChanged() if handle then handle:SetShown(not db.locked) end end

local function build()
	if api.ownApplyFonts then api.ownApplyFonts() end
	frame = CreateFrame("Frame", "ForeverTrackerPlusOwn", UIParent)
	frame:SetClampedToScreen(false)
	inner = CreateFrame("Frame", nil, frame)
	inner:SetPoint("TOPLEFT")
	frame.inner = inner
	background = inner:CreateTexture(nil, "BACKGROUND", nil, -8)
	background:Hide()

	mainHeader = makeHeader(blizz and blizz.Header, HEADER_H, "All Objectives", "ownAllCollapsed")
	mainHeader:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
	mainHeader:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, 0)
	local qmod = _G.QuestObjectiveTracker
	questsHeader = makeHeader(qmod and qmod.Header, QUESTS_H, "Quests", "ownQuestsCollapsed")
	questsHeader:SetPoint("TOPLEFT", mainHeader, "BOTTOMLEFT", 0, -2)
	questsHeader:SetPoint("TOPRIGHT", mainHeader, "BOTTOMRIGHT", 0, -2)
	-- phase 4: the guide's slot between the main header and the Quests header (as Blizzard's tracker had it: the
	-- guide module right after the scenario, above the quests)
	-- phase 4b: the dungeon card's slot at the very top (as on the classic tracker: the card above the guide)
	cardHost = CreateFrame("Frame", "ForeverTrackerPlusOwnCard", inner)
	cardHost:SetPoint("TOPLEFT", mainHeader, "BOTTOMLEFT", 0, -2)
	cardHost:SetPoint("TOPRIGHT", mainHeader, "BOTTOMRIGHT", 0, -2)
	cardHost:SetHeight(1)
	-- the "Reputation" header over the tracked reputation bar (user), the Quests header's art, its own collapse
	repHeader = makeHeader(qmod and qmod.Header, QUESTS_H, REPUTATION or "Reputation", "ownRepCollapsed", cardHost, {})
	repHeader:Hide()
	guideHost = CreateFrame("Frame", "ForeverTrackerPlusOwnGuide", inner)
	guideHost:SetPoint("TOPLEFT", mainHeader, "BOTTOMLEFT", 0, -2)
	guideHost:SetPoint("TOPRIGHT", mainHeader, "BOTTOMRIGHT", 0, -2)
	guideHost:SetHeight(1)
	guideHost:Hide()
	-- phase 5 blocks: the Quests header's art (user: the line under Professions to match the other headers; Blizzard's
	-- Professions header art is narrower), each section's own header text when Blizzard has one
	for _, b in ipairs(blocks) do
		b.host = CreateFrame("Frame", b.frameName, inner)
		b.host:SetPoint("TOPLEFT", mainHeader, "BOTTOMLEFT", 0, -2)
		b.host:SetPoint("TOPRIGHT", mainHeader, "BOTTOMRIGHT", 0, -2)
		b.host:SetHeight(1)
		b.host:Hide()
		local src = b.textSrc and _G[b.textSrc]
		b.header = makeHeader(qmod and qmod.Header, QUESTS_H, b.name, b.key, b.host, src and src.Header or {})
		b.header:SetPoint("TOPLEFT", b.host, "TOPLEFT", 0, 0)
		b.header:SetPoint("TOPRIGHT", b.host, "TOPRIGHT", 0, 0)
	end

	scroll = CreateFrame("ScrollFrame", nil, inner)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", onWheel)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)

	makeScrollbar()
	makeHandle()
	refresh()
end

---------------------------------------------------------------------------------------------------------------------
-- Events and settings
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
	"SUPER_TRACKING_CHANGED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_ENABLED",
	"TRACKED_RECIPE_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", -- Professions (phase 5)
	"CRITERIA_UPDATE", "CRITERIA_COMPLETE", "ACHIEVEMENT_EARNED" } -- Legacy Challenges (phase 5)
-- "by zone" sorts by distance: re-read every 15 s while you move (as ZoneSort does), not while standing still
local MOVE_CHECK = 15
local lastX, lastY
local function moveCheck()
	if not (frame and db and db.zoneSort) or not frame:IsShown() then return end
	local x, y = api.playerWorldPos and api.playerWorldPos()
	if type(x) == "table" then x, y = x.x, x.y end
	if x and lastX and (x - lastX) ^ 2 + (y - lastY) ^ 2 < 400 then return end
	lastX, lastY = x, y
	markDirty()
end
local profQueued = false
-- the blocks above the quests, laid out again once on the next frame (in combat after it, as the rest)
local function blocksSoon()
	if profQueued then return end
	profQueued = true
	C_Timer.After(0, function()
		profQueued = false
		if lockedNow() then pendingLayout = true elseif frame then applyCollapse() end
	end)
end
api.ownLegacyChanged = blocksSoon -- Legacy.lua: tracked or untracked
api.ownBgChanged = blocksSoon -- Battleground.lua: into or out of a battleground, a timer started or ended
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingLayout then refresh() end
		return
	end
	-- Professions (phase 5): its own block, laid out on its own (item names arrive one by one: only while it shows)
	if event == "TRACKED_RECIPE_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
		-- (performance) bag and item events only matter while the Professions block shows
		if event ~= "TRACKED_RECIPE_UPDATE" and profBlock.h <= 0 then return end
		blocksSoon()
		return
	end
	-- Legacy Challenges (phase 5): progress and finished ones (criteria change often: once per frame at most)
	if event == "CRITERIA_UPDATE" or event == "ACHIEVEMENT_EARNED" or event == "CRITERIA_COMPLETE" then
		if event == "CRITERIA_UPDATE" and blocks[2].h <= 0 then return end
		blocksSoon()
		return
	end
	if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		if lockedNow() then pendingLayout = true else place() end
	end
	-- a new zone (into or out of a battleground): the guide checks whether it pauses
	if (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA") and api.ownGuideChanged then
		api.ownGuideChanged()
	end
	markDirty()
end)

-- Core's setters the settings window calls: after each, our frame takes the new values
local SETTERS = { "applyLayout", "applyExtras", "applyZoneHeaders", "applyProgressBars", "setTrackerAlpha",
	"applySituationAlpha", "applyBackground", "applyFont", "setFont", "setScrollbarWidth", "setScrollbarShown",
	"setScrollbarMouseover", "applyWrap", "applyWidth", "applyScale", "applyQuestsPad", "applyQuestScale", "applyLevel",
	"setMode", "setZoneFilter", "setZoneOrder", "sortNow", "resetPosition", "refreshQuests", "resetDefaults",
	"loadProfile" }
api.ownSetters = SETTERS -- for tests
local function hookSetters()
	for _, name in ipairs(SETTERS) do
		if type(api[name]) == "function" then hooksecurefunc(api, name, function() refresh() end) end
	end
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	startHiding()
	build()
	hookSetters()
	for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
	if C_Timer.NewTicker then C_Timer.NewTicker(MOVE_CHECK, moveCheck) end
	markDirty()
end
