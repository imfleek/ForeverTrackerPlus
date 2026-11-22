-- More quests: the quests in the log that the game will not track.
--
-- Blizzard's tracker draws only watched quests, and the game caps the watch list
-- (Constants.QuestWatchConsts.MAX_QUEST_WATCHES; 20 seen on Forever), so with "Track all quests" a full log (up to 40)
-- showed only the first 20. This section lists the rest below Blizzard's quests, in the tracker's fonts: title (with
-- level, in difficulty colour) and objectives. It is anchored below the lowest Blizzard section, so it scrolls with
-- the list, and Core's scroll range includes it (api.moreQuestsBottom). Plain frames only: nothing protected.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local tracker = ObjectiveTrackerFrame
local db

local GAP, INDENT, LINE_GAP, QUEST_GAP = 8, 12, 2, 7
local schedule -- defined at the end
local frame, rows = nil, {}
-- the Quest Tracker opacity (general x Quest Tracker, /qt Advanced): the section is on UIParent, outside the viewport
function api.applyMoreQuestsAlpha()
	if frame and api.questTrackerAlpha then frame:SetAlpha(api.questTrackerAlpha()) end
	if api.placeMoreQuestItems then api.placeMoreQuestItems() end
end
local used = 0

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function clean(v) return type(v) == "string" and not isSecret(v) and v or nil end

local function watchLimit()
	return (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or nil
end

local function font(name, fallback)
	return _G[name] and name or fallback
end

local function wanted()
	return db and db.enabled and db.moreQuests ~= false and db.trackMode == "all"
end

-- One FontString per line, pooled; titles get a click button.
local function row(i)
	local r = rows[i]
	if not r then
		r = frame:CreateFontString(nil, "OVERLAY")
		r:SetJustifyH("LEFT")
		r:SetWordWrap(true)
		rows[i] = r
	end
	return r
end

local function openQuest(id)
	if QuestMapFrame_OpenToQuestDetails then
		pcall(QuestMapFrame_OpenToQuestDetails, id)
	elseif ToggleQuestLog then
		pcall(ToggleQuestLog)
	end
end

-- R106-128: the right-click menu of a tracked quest, made here (the game makes it only for its own quest blocks). It
-- carries the same tag, MENU_QUEST_OBJECTIVE_TRACKER, so lines other code adds to that menu (QuestMenu.lua: Wowhead
-- URL) show here too. Focus, open in the quest log, share (in a group, when the quest can be shared). Not "Abandon":
-- the game's abandon box is a StaticPopup, which addon code can taint; abandon from the quest log.
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
		local ST = C_SuperTrack
		if ST and ST.SetSuperTrackedQuestID then
			local focused = ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() == id
			root:CreateButton(focused and "Stop focusing" or "Focus", function()
				pcall(ST.SetSuperTrackedQuestID, focused and 0 or id)
			end)
		end
		root:CreateButton("Open in quest log", function() openQuest(id) end)
		local grouped = IsInGroup and IsInGroup()
		local pushable = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(id)
		if grouped and pushable then root:CreateButton("Share quest", function() shareQuest(id) end) end
	end)
end
api.moreQuestsMenu = showMenu

-- R106-128: clicks as on tracked quests (Extras.lua): left opens the quest log; Ctrl+left looks for a group
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
api.moreQuestsClick = onClick

local clickers = {}
-- title: the quest's title (an objective line's button shows the quest's tooltip too); objective: the line's text
local function clicker(i, fs, questID, title, objective)
	local b = clickers[i]
	if not b then
		b = CreateFrame("Button", nil, frame)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", onClick)
		-- the quest the right-click menu is for (QuestMenu.lua reads it: the menu does not say)
		b:SetScript("OnMouseDown", function(self)
			local map = _G.WorldMapFrame
			api.lastQuestPressed = { id = self.questID, at = GetTime(), mapOpen = map and map:IsShown() or false }
		end)
		b:SetScript("OnEnter", function(self)
			local limit = watchLimit()
			local function notTracked(tip)
				tip:AddLine(" ")
				tip:AddLine(("Not tracked: the game tracks at most %s quests."):format(limit or "a limited number of"),
					0.8, 0.8, 0.8, true)
				tip:AddLine("Click: open in the quest log. Right-click: its menu.", 0.6, 0.6, 0.6, true)
			end
			-- the same quest tooltip as the tracked quests (overview, objectives, rewards, party), when tooltips are on
			if not (api.showQuestTooltip and api.showQuestTooltip(self, self.questID, self.title, notTracked)) then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:SetText(self.title or "", 1, 1, 1, 1, true)
				notTracked(GameTooltip)
				GameTooltip:Show()
			end
			-- R106-127: an objective line: the 3D model of the NPC or object it names (NpcPanel.lua)
			if self.objective and api.npcLineHover then pcall(api.npcLineHover, self, self.questID, self.objective) end
		end)
		b:SetScript("OnLeave", function(self)
			if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
			if api.hideNpcPanel then pcall(api.hideNpcPanel, self) end
		end)
		clickers[i] = b
	end
	b.questID = questID
	b.title = title or fs:GetText()
	b.objective = objective
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", fs, "TOPLEFT")
	b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT")
	b:Show()
	return b
end

local function difficultyColor(level)
	if GetQuestDifficultyColor and type(level) == "number" then
		local ok, c = pcall(GetQuestDifficultyColor, level)
		if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
	end
	return 1, 0.82, 0
end

-- The quests to list: in the log, not headers, not hidden or world/bonus tasks, not watched, not hidden by the zone
-- filter. Grouped under their quest-log headers, in quest-log order.
local function collect()
	local list, header = {}, nil
	local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				header = clean(info.title)
			elseif info.questID and not isSecret(info.questID) and not info.isHidden and not info.isTask
				and not info.isBounty and C_QuestLog.GetQuestWatchType(info.questID) == nil
				and not (db.zoneHidden and db.zoneHidden[info.questID]) then
				local zone = api.questieZone and api.questieZone(info.questID) or header -- Questie: where it is done
				list[#list + 1] = { id = info.questID, title = clean(info.title) or "?", level = info.level, header = zone,
					order = #list + 1 }
			end
		end
	end
	-- sorting by zone: the same closest-zone-first order as the tracked quests (ZoneSort.lua)
	if db.zoneSort and api.orderQuests then
		local entries = {}
		for i, q in ipairs(list) do entries[i] = { id = q.id, zone = q.header or "", index = q.order, item = q } end
		local ok, ordered = pcall(api.orderQuests, entries)
		if ok and type(ordered) == "table" then
			for i, e in ipairs(ordered) do list[i] = e.item end
		end
	end
	return list
end

-- The Blizzard section whose last shown quest is lowest, and that quest's bottom (UIParent units, from Core).
local function lowestModule()
	local lowest, lowestBottom
	for _, module in ipairs(tracker.modules or {}) do
		if module:IsShown() and (module.GetContentsHeight == nil or module:GetContentsHeight() > 0) then
			local b = api.moduleContentBottom and api.moduleContentBottom(module)
			if b and (not lowestBottom or b < lowestBottom) then lowest, lowestBottom = module, b end
		end
	end
	return lowest, lowestBottom
end

local function questScale()
	return math.min(math.max(tonumber(db.questScale) or 1, 0.5), 1.5)
end

local function hide()
	if frame then frame:Hide() end
end

-- Position, scale and width, every tracker layout pass (Core.lua refresh).
function api.layoutMoreQuests()
	if not frame or used == 0 or not wanted() then hide() return end
	local viewport = _G.ForeverTrackerPlusViewport
	-- the whole tracker collapsed, or the "Quests" section folded with its collapse button: these quests go too
	local questModule = _G.QuestObjectiveTracker
	local questsFolded = questModule and questModule.IsCollapsed and questModule:IsCollapsed()
	-- right under Blizzard's quests; with none of them shown, under the lowest section
	local anchor, contentBottom
	if questModule and questModule:IsShown() and api.moduleContentBottom then
		anchor, contentBottom = questModule, api.moduleContentBottom(questModule)
	end
	if not contentBottom then anchor, contentBottom = lowestModule() end
	if not viewport or not anchor or not tracker:IsShown() or (tracker.IsCollapsed and tracker:IsCollapsed())
		or questsFolded then
		hide()
		return
	end
	if frame:GetParent() ~= viewport then frame:SetParent(viewport) end
	local qs = questScale()
	local scale = tracker:GetEffectiveScale() / viewport:GetEffectiveScale() * qs
	if math.abs(frame:GetScale() - scale) > 1e-4 then frame:SetScale(scale) end
	frame:SetFrameStrata(tracker:GetFrameStrata())
	frame:SetFrameLevel(tracker:GetFrameLevel() + 1)
	local width = tracker:GetWidth() / qs
	if frame.builtWidth and math.abs(frame.builtWidth - width) > 1 then schedule() end -- text wraps at the old width
	-- anchored to the section's top (it moves with the section when the list scrolls), as far down as its last shown
	-- quest; offsets are in this frame's own scale
	local anchorTop = anchor:GetTop()
	if not anchorTop then hide() return end
	local uiScale = UIParent:GetEffectiveScale()
	local down = (anchorTop * anchor:GetEffectiveScale() / uiScale - contentBottom) * uiScale / frame:GetEffectiveScale()
	frame:ClearAllPoints()
	local gap = frame.look and frame.look.blockGap or GAP
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(math.max(down, 0) + gap))
	frame:SetWidth(width)
	frame:Show()
	-- the sections after the quests (tracked recipes, ...) go below this one: Core.lua pushSectionsAfterQuests
end

-- Bottom of the section in UIParent units, for the scroll range.
function api.moreQuestsBottom()
	if not frame or not frame:IsShown() then return nil end
	local b = frame:GetBottom()
	return b and b * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() or nil
end

-- How Blizzard draws a quest, read from one it is showing (QuestObjectiveTracker.usedBlocks): fonts, colours, the
-- title's and the objective lines' horizontal offsets within the section, and the spacing. The section's own fields
-- (fromBlockOffsetY, lineSpacing) give the spacing; fallbacks keep the list usable before any quest was drawn.
local OTC = _G.OBJECTIVE_TRACKER_COLOR
local function colorOf(key, r, g, b)
	local c = OTC and OTC[key]
	if type(c) == "table" and c.r then return c.r, c.g, c.b end
	return r, g, b
end
local function fontOf(fs, fallbackObject)
	if fs and fs.GetFont then
		local file, size, flags = fs:GetFont()
		if file and size then return { file, size, flags } end
	end
	local object = _G[fallbackObject]
	if object and object.GetFont then
		local file, size, flags = object:GetFont()
		if file and size then return { file, size, flags } end
	end
	return { STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "" }
end

local function sample(module)
	local look = {
		headerX = 0, dashX = 0, textX = 12, blockGap = 10, lineGap = 2,
		header = fontOf(nil, "ObjectiveTrackerHeaderFont"), line = fontOf(nil, "ObjectiveTrackerLineFont"),
		headerColor = { colorOf("Header", 0.75, 0.61, 0) },
		normalColor = { colorOf("Normal", 0.8, 0.8, 0.8) },
		completeColor = { colorOf("Complete", 0.6, 0.6, 0.6) },
	}
	if type(module.fromBlockOffsetY) == "number" then look.blockGap = math.abs(module.fromBlockOffsetY) end
	if type(module.lineSpacing) == "number" then look.lineGap = module.lineSpacing end
	local left = module:GetLeft()
	if not left or type(module.usedBlocks) ~= "table" then return look end
	for _, byId in pairs(module.usedBlocks) do
		if type(byId) == "table" then
			for _, block in pairs(byId) do
				local header = type(block) == "table" and block.IsShown and block:IsShown() and block.HeaderText
				if header and header.GetLeft and header:GetLeft() then
					look.headerX = header:GetLeft() - left
					look.header = fontOf(header, "ObjectiveTrackerHeaderFont")
					for _, line in pairs(type(block.usedLines) == "table" and block.usedLines or {}) do
						local text = type(line) == "table" and line.Text
						if text and text.GetLeft and text:GetLeft() then
							look.textX = text:GetLeft() - left
							look.line = fontOf(text, "ObjectiveTrackerLineFont")
							local dash = line.Dash
							look.dashX = (dash and dash.IsShown and dash:IsShown() and dash:GetLeft()) and (dash:GetLeft() - left)
								or look.headerX
							break
						end
					end
					return look
				end
			end
		end
	end
	return look
end

local labels = {}
local function zoneLabel(i)
	local label = labels[i]
	if not label then
		label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetJustifyH("LEFT")
		labels[i] = label
	end
	if api.styleZoneLabel then api.styleZoneLabel(label) end
	return label
end

-- R106-86: "Expand current zone only": the zones other than the player's are folded here (their header with a "+" and
-- how many quests it holds); clicking a header opens or folds it again. Opened zones are remembered until you change
-- zone. Without the option every zone is open, as before.
local openZones = {}
local function folding() return db and db.expandCurrentZone and db.zoneSort and true or false end
local function isFolded(zone)
	if not folding() or not zone or zone == "" then return false end
	if openZones[zone] then return false end
	return not (api.isCurrentZoneName and api.isCurrentZoneName(zone))
end
api.moreQuestsZoneFolded = isFolded
local zoneButtons = {}
local function zoneButton(i, label, zone)
	local b = zoneButtons[i]
	if not b then
		b = CreateFrame("Button", nil, frame)
		b:RegisterForClicks("LeftButtonUp")
		b:SetScript("OnClick", function(self)
			local z = self.zone
			if not z then return end
			if isFolded(z) then openZones[z] = true else openZones[z] = nil end
			-- the player's own zone cannot be folded: it stays open
			if api.rebuildMoreQuests then api.rebuildMoreQuests() end
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(self.zone or "", 1, 1, 1)
			GameTooltip:AddLine(isFolded(self.zone) and "Click to show its quests." or "Click to fold it.", 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
		zoneButtons[i] = b
	end
	b.zone = zone
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", label, "TOPLEFT", -2, 2)
	b:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -2)
	b:Show()
	return b
end

local dashes = {}
local function dashText(i)
	local d = dashes[i]
	if not d then
		d = frame:CreateFontString(nil, "OVERLAY")
		dashes[i] = d
	end
	return d
end

-- What the section would show, as one string: quest log updates come often (every few seconds, on any change of any
-- quest), and most change nothing shown here; then the rows are left as they are. A setting change always redraws.
local lastSignature
local forceBuild = false
local function colorKey(c) return c and ("%.3f,%.3f,%.3f"):format(c[1] or 0, c[2] or 0, c[3] or 0) or "" end

-- Progress on objectives, as on Blizzard's quests (Extras.lua, "Progress bars on objectives"): the same framed bar
-- with the count inside it, at the right edge of the line.
local progressBits, progressUsed = {}, 0
local BAR_GAP = 6
local function progressBit()
	progressUsed = progressUsed + 1
	local b = progressBits[progressUsed]
	if not b then
		b = api.newProgressBar(frame)
		progressBits[progressUsed] = b
	end
	return b
end

---------------------------------------------------------------------------------------------------------------------
-- R106-128: quest item buttons, as on tracked quests (the item the game gives a quest, GetQuestLogSpecialItemInfo):
-- left of the objectives, under the title (or right of the list with the item side set to the right).
-- CONSTRAINT: an item button is secure (SecureActionButtonTemplate, attribute type "item"): in combat it cannot be
-- made, moved, shown, hidden or changed, and a frame it is anchored to cannot move either. So the buttons sit on
-- UIParent at a place worked out from the title (the list itself stays free to move: the wheel scrolls it in combat,
-- R106-50). They are placed again whenever the title moves; in combat a button whose title moved is made see-through
-- (SetAlpha is allowed) and placed when the fight ends. A button whose line is scrolled out of the list is hidden.
---------------------------------------------------------------------------------------------------------------------
local ITEM_SIZE = 26 * 0.875 -- the game's quest item button, 12.5 % smaller (Extras.lua R106-53)
local itemButtons, itemPlaces, itemDirty = {}, {}, false
local function inCombat() return InCombatLockdown and InCombatLockdown() end

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
api.moreQuestsItemFor = itemFor

local function itemButton(i)
	local b = itemButtons[i]
	if b then return b end
	b = CreateFrame("Button", "ForeverTrackerPlusMoreQuestItem" .. i, UIParent, "SecureActionButtonTemplate")
	b:SetSize(ITEM_SIZE, ITEM_SIZE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "item")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if api.themeKit then api.themeKit.border(b, { 0.55, 0.43, 0.18 }, 1, "OVERLAY") end
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.count:SetPoint("BOTTOMRIGHT", -1, 1)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.9, 0.6, 0.15)
	b:SetScript("OnEnter", function(self)
		if not self.link or self:GetAlpha() == 0 then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
	b:Hide()
	itemButtons[i] = b
	return b
end

local function updateItemCooldowns()
	local getCd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
	for _, b in ipairs(itemButtons) do
		if b:IsShown() and b.itemID then
			if getCd then
				local ok, start, duration, enable = pcall(getCd, b.itemID)
				if ok and start and duration and duration > 0 and enable ~= 0 and enable ~= false then
					b.cd:SetCooldown(start, duration)
				elseif b.cd.Clear then
					b.cd:Clear()
				end
			end
			local ok, n = getCount and pcall(getCount, b.itemID)
			b.count:SetText(ok and type(n) == "number" and n > 1 and tostring(n) or "")
		end
	end
end

-- where a quest's button goes (TOPRIGHT, or TOPLEFT with the item side on the right), in the list's own scale
local function itemSpot(fs)
	if api.itemSide and api.itemSide() == "right" then
		local right, top = frame:GetRight(), fs:GetTop()
		if right and top then return "TOPLEFT", right + 4, top end
		return nil
	end
	local left, bottom = fs:GetLeft(), fs:GetBottom()
	if left and bottom then return "TOPRIGHT", left - 4, bottom - 1 end
end

-- the list's visible part (the scroll viewport) in screen pixels
local function visibleSpan()
	local v = _G.ForeverTrackerPlusViewport
	local top, bottom = v and v.GetTop and v:GetTop(), v and v.GetBottom and v:GetBottom()
	if not (top and bottom) then return nil end
	local s = v:GetEffectiveScale()
	return top * s, bottom * s
end

local function placeItemButtons()
	local listShown = frame and frame:IsVisible() and used > 0
	if inCombat() then
		-- nothing secure may change: a button whose title moved (or whose list went) is made see-through until the end
		itemDirty = true -- the list may have changed too: placed again when the fight ends
		for _, b in ipairs(itemButtons) do
			if b:IsShown() then
				local fs = b.placedFs
				local moved = not listShown or not fs or not fs:IsVisible() or fs:GetTop() ~= b.placedTop
				b:SetAlpha(moved and 0 or (frame and frame:GetAlpha() or 1))
			end
		end
		return
	end
	itemDirty = false
	local s = frame and frame:GetEffectiveScale() or 1
	local vTop, vBottom = visibleSpan()
	local count = math.max(#itemPlaces, #itemButtons)
	for i = 1, count do
		local p = listShown and itemPlaces[i] or nil
		local point, x, y
		if p and p.fs:IsVisible() then point, x, y = itemSpot(p.fs) end
		-- hidden when its line is scrolled out of the list's visible part
		if point and vTop then
			local mid = (y - ITEM_SIZE / 2) * s
			if mid > vTop or mid < vBottom then point = nil end
		end
		if point then
			local b = itemButton(i)
			if b.itemID ~= p.item.itemID then
				b:SetAttribute("item", "item:" .. p.item.itemID)
				b.icon:SetTexture(p.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				b.itemID = p.item.itemID
			end
			b.link = p.item.link
			local scale = s / UIParent:GetEffectiveScale()
			if math.abs(b:GetScale() - scale) > 1e-4 then b:SetScale(scale) end
			b:ClearAllPoints()
			b:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
			b:SetFrameStrata(frame:GetFrameStrata())
			b:SetFrameLevel(frame:GetFrameLevel() + 5)
			b:SetAlpha(frame:GetAlpha())
			b.placedFs, b.placedTop = p.fs, p.fs:GetTop()
			b:Show()
		elseif itemButtons[i] then
			local b = itemButtons[i]
			b.placedFs, b.placedTop = nil, nil
			if b:IsShown() then b:Hide() end
		end
	end
	updateItemCooldowns()
end
api.placeMoreQuestItems = placeItemButtons

-- the title under the first button moved (a scroll, a re-layout): placed again
local lastWatchTop
local function watchItems()
	local p = itemPlaces[1]
	if not p then return end
	local top = p.fs:GetTop()
	if top ~= lastWatchTop then
		lastWatchTop = top
		placeItemButtons()
	end
end

local function build()
	if not db then return end
	if not frame then
		frame = CreateFrame("Frame", "ForeverTrackerPlusMoreQuests", UIParent)
		if api.applyMoreQuestsAlpha then api.applyMoreQuestsAlpha() end
		frame:SetSize(200, 10)
		frame:Hide()
		-- R106-128: the item buttons follow the list (they are not in it: see above)
		frame:SetScript("OnUpdate", watchItems)
		frame:SetScript("OnShow", function() lastWatchTop = nil; placeItemButtons() end)
		frame:SetScript("OnHide", function() placeItemButtons() end)
	end
	local function clear()
		for _, r in ipairs(rows) do
			r:Hide()
			if api.hideTitleIcons then api.hideTitleIcons(r) end
			if api.hideQuestDistance then api.hideQuestDistance(r) end
			r.qtsReserve = nil
		end
		for _, b in ipairs(clickers) do b:Hide() end
		for _, l in ipairs(labels) do l:Hide() end
		for _, b in ipairs(zoneButtons) do b:Hide() end
		for _, d in ipairs(dashes) do d:Hide() end
		for _, b in ipairs(progressBits) do api.hideProgressBar(b) end
		for k in pairs(itemPlaces) do itemPlaces[k] = nil end
		lastWatchTop = nil
		progressUsed = 0
		used = 0
		lastSignature = nil
	end
	local list = wanted() and collect() or {}
	local module = _G.QuestObjectiveTracker
	if #list == 0 or not module then
		local had = used > 0
		clear()
		hide()
		placeItemButtons()
		if had and api.applyLayout then api.applyLayout() end
		return
	end

	-- seamless: no heading of its own; Blizzard's fonts, colours, offsets and spacing (sample)
	local look = sample(module)
	local qs = questScale()
	local width = math.max(tracker:GetWidth() / qs, 120)

	-- everything to draw, first as data
	local entries = {}
	local parts = { width, qs, tostring(db.zoneSort), db.zoneHeaderX or 4, tonumber(db.questTitleX) or 0, tonumber(db.zoneHeaderY) or 0,
		tostring(api.lastTrackedZone), tostring(folding()),
		look.header[1], look.header[2], look.line[1], look.line[2], look.headerX, look.dashX, look.textX, look.lineGap,
		look.blockGap, colorKey(look.headerColor), colorKey(look.normalColor), colorKey(look.completeColor) }
	for _, quest in ipairs(list) do
		local title = (type(quest.level) == "number" and quest.level > 0) and ("[%d] %s"):format(quest.level, quest.title)
			or quest.title
		if api.rewardSuffix then title = title .. api.rewardSuffix(quest.id, look.header[2]) end
		-- title icons, as on the tracked quests (Extras.lua): the Forever infinity furthest out, then the star
		local icons = {}
		local forever = api.foreverIcon and api.foreverIcon(quest.id)
		if forever then icons[#icons + 1] = forever end
		local star = api.attunementIcon and api.attunementIcon(quest.id)
		if star then icons[#icons + 1] = star end
		-- R106-128: the type marker next to the title, as on tracked quests ("Icon Classifications", db.condense):
		-- an icon (elite, dungeon, raid, PvP), or "[+N]" for a group quest in front of the title
		local marker = db.condense and api.questClassifier and select(2, pcall(api.questClassifier, quest.id)) or nil
		local markerKey = ""
		if type(marker) == "table" then
			icons[#icons + 1] = marker
			markerKey = tostring(marker.atlas or marker.file or "icon")
		elseif type(marker) == "string" then
			title = marker .. " " .. title
		end
		local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(quest.id) and true or false
		local lines = {}
		if complete then
			lines[1] = { QUEST_WATCH_QUEST_READY or "Ready for turn-in", true }
		else
			local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, quest.id)
			for _, o in ipairs(ok and type(objectives) == "table" and objectives or {}) do
				local text = clean(o.text)
				if text and text ~= "" then lines[#lines + 1] = { text, o.finished and true or false } end
			end
		end
		local item = itemFor(quest.id)
		entries[#entries + 1] = { quest = quest, title = title, icons = icons, complete = complete, lines = lines,
			item = item }
		parts[#parts + 1] = (isFolded(quest.header) and "F" or "") .. quest.id .. "|" .. tostring(quest.header) .. "|" .. title .. (star and "*" or "") .. (forever and "~" or "") .. (complete and "v" or "") .. markerKey
			.. "|" .. tostring(item and item.itemID)
		for _, line in ipairs(lines) do parts[#parts + 1] = (line[2] and "+" or "-") .. line[1] end
	end
	local signature = table.concat(parts, "\n")
	if not forceBuild and signature == lastSignature then
		api.layoutMoreQuests()
		return
	end
	forceBuild = false
	clear()
	lastSignature = signature
	frame.look = look
	frame.builtWidth = tracker:GetWidth() / qs
	local y, click, zones, dashCount = 0, 0, 0, 0
	local function add(text, f, x, color, rightPad, icons)
		used = used + 1
		local fs = row(used)
		fs:SetFont(f[1], f[2], f[3])
		fs:SetWidth(math.max(width - x - (rightPad or 4), 40))
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
		-- icons left of the title, outside it (Extras.lua): they never move the text
		if icons and icons[1] and api.placeTitleIcons then
			text = api.placeTitleIcons(fs, icons) .. text
		elseif api.hideTitleIcons then
			api.hideTitleIcons(fs)
		end
		-- a coin amount whose coin would wrap without its number starts the next line (Extras.lua)
		if api.keepCoinsTogether then text = api.keepCoinsTogether(fs, text) end
		fs:SetText(text)
		fs:SetTextColor(color[1], color[2], color[3])
		fs:Show()
		y = y + (fs:GetStringHeight() or f[2]) + look.lineGap
		return fs
	end

	local lastZone = db.zoneSort and api.lastTrackedZone or nil
	-- R106-86: how many quests each zone holds (shown on a folded zone's header)
	local zoneCount = {}
	for _, entry in ipairs(entries) do
		local z = entry.quest.header
		if z then zoneCount[z] = (zoneCount[z] or 0) + 1 end
	end
	local shownAny = false
	for _, entry in ipairs(entries) do
		local quest = entry.quest
		local folded = isFolded(quest.header)
		if shownAny then y = y + look.blockGap - look.lineGap end
		if db.zoneSort and quest.header and quest.header ~= lastZone then
			lastZone = quest.header
			-- the same room and place as ZoneSort's headers above Blizzard's quests
			y = y + (api.zoneHeaderHeight and api.zoneHeaderHeight() or 14)
			zones = zones + 1
			local label = zoneLabel(zones)
			label:ClearAllPoints()
			label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", look.headerX + (db.zoneHeaderX or 4) - 4 - (tonumber(db.questTitleX) or 0),
				-y + 2 + (tonumber(db.zoneHeaderY) or 0))
			if folding() then
				-- folded: "+ Zone (3)"; open (not the player's zone): "- Zone"
				local own = api.isCurrentZoneName and api.isCurrentZoneName(quest.header)
				label:SetText(folded and ("+ %s (%d)"):format(quest.header, zoneCount[quest.header] or 0)
					or own and quest.header or ("- " .. quest.header))
				if not own then zoneButton(zones, label, quest.header) end
			else
				label:SetText(quest.header)
			end
			label:Show()
			shownAny = true
		end
		if folded then
			-- its quests are not drawn (only the header above)
		else
		shownAny = true
		-- room at the title's right edge for the distance and arrow (Extras.lua), as on Blizzard's quests
		-- (only for a quest that shows a distance, so the other titles keep their full width)
		local reserve = api.questHasDistance and api.questHasDistance(quest.id) and api.questDistanceReserve
			and api.questDistanceReserve(look.header[1], look.header[2], look.header[3]) or nil
		local fs = add(entry.title, look.header, look.headerX, look.headerColor, reserve and (4 + reserve) or nil,
			#entry.icons > 0 and entry.icons or nil)
		fs.qtsReserve = reserve
		if api.attachQuestDistance then api.attachQuestDistance(fs, quest.id) end
		-- a finished quest: the green check on its own, left of the title (Extras.lua)
		if api.placeCheck then api.placeCheck(fs, entry.complete) end
		click = click + 1
		clicker(click, fs, quest.id)
		if entry.item then itemPlaces[#itemPlaces + 1] = { fs = fs, item = entry.item } end
		local lines = {}
		for i, line in ipairs(entry.lines) do
			lines[i] = { line[1], line[2] and look.completeColor or look.normalColor }
		end
		for _, line in ipairs(lines) do
			if look.textX > look.dashX then
				dashCount = dashCount + 1
				local d = dashText(dashCount)
				d:SetFont(look.line[1], look.line[2], look.line[3])
				d:SetText(QUEST_DASH or "- ")
				d:SetTextColor(line[2][1], line[2][2], line[2][3])
				d:ClearAllPoints()
				d:SetPoint("TOPLEFT", frame, "TOPLEFT", look.dashX, -y)
				d:Show()
			end
			local name, have, need, lineFs
			if db.progressBars ~= false and api.progressParts and api.drawProgressBar then
				name, have, need = api.progressParts(line[1])
			end
			if name then
				local b = progressBit()
				if api.progressBarUnder and api.progressBarUnder() then
					-- under the objective: the bar on a line of its own, from the text's left to the right edge
					lineFs = add(name, look.line, look.textX, line[2])
					-- the same gaps above and below as on Blizzard's quests (Extras.lua), the room in this layout
					local top, bottom = api.progressUnderGaps()
					local bh = api.progressUnderBarHeight(look.line[2])
					api.drawProgressBar(b, frame, look.textX, look.line[1], look.line[2], look.line[3], have, need,
						"TOPLEFT", math.max(width - look.textX - 4, 20), bh, -(y + top))
					y = y + top + bh + bottom + look.lineGap
				else
					local reserve = api.progressBarSize(look.line[2]) + BAR_GAP
					lineFs = add(name, look.line, look.textX, line[2], 4 + reserve)
					api.drawProgressBar(b, lineFs, BAR_GAP, look.line[1], look.line[2], look.line[3], have, need)
				end
			else
				lineFs = add(line[1], look.line, look.textX, line[2])
			end
			-- R106-127: a hover button on the line: the quest's tooltip and the 3D model of what the line names
			click = click + 1
			clicker(click, lineFs, quest.id, entry.title, line[1])
		end
		end -- (not folded)
	end
	frame:SetHeight(math.max(y, 1))
	api.layoutMoreQuests()
	placeItemButtons()
	if api.applyLayout then api.applyLayout() end -- the scroll range changed
end

---------------------------------------------------------------------------------------------------------------------
-- Quest count on the "Quests" header: "31/40" left of its collapse button
---------------------------------------------------------------------------------------------------------------------
-- Quests in the log (the second return of GetNumQuestLogEntries counts quests, not headers) out of the log's
-- maximum. Green up to 26, yellow 27-36, orange 37-39, red when full: the same breakpoints scaled to the maximum when
-- it is not 40.
local countText
local function countColor(count, max)
	if count >= max then return 1, 0.2, 0.2 end
	if count >= math.floor(max * 37 / 40 + 0.5) then return 1, 0.55, 0.1 end
	if count >= math.floor(max * 27 / 40 + 0.5) then return 1, 0.9, 0.2 end
	return 0.3, 0.9, 0.3
end
function api.updateQuestCount()
	local module = _G.QuestObjectiveTracker
	local header = module and module.Header
	if not header then return end
	if not countText then
		countText = header:CreateFontString(nil, "OVERLAY")
		countText:SetJustifyH("RIGHT")
	end
	local anchor = header.MinimizeButton or header
	-- the header text's font (whatever addon set it); all three values, or the game's normal font
	local file, size, flags
	if header.Text and header.Text.GetFont then file, size, flags = header.Text:GetFont() end
	if not (file and size) then file, size, flags = GameFontNormal:GetFont() end
	if not (file and size) then return end
	-- Quest list > Quest count: its own text size (0 = the header's)
	local ownSize = tonumber(db and db.questCountSize) or 0
	if ownSize > 0 then size = ownSize end
	countText:SetFont(file, size, flags or "")
	countText:ClearAllPoints()
	countText:SetPoint("RIGHT", anchor, header.MinimizeButton and "LEFT" or "RIGHT", -6, 0)
	local ok, _, quests = pcall(C_QuestLog.GetNumQuestLogEntries)
	local max = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 40
	if not ok or type(quests) ~= "number" or isSecret(quests) or type(max) ~= "number" or max <= 0 then
		countText:SetText("")
		return
	end
	countText:SetText(("%d/%d"):format(quests, max))
	-- a custom colour replaces the green / yellow / orange / red of how full the log is
	-- its opacity always applies (the colour picker's opacity bar)
	local saved = db and type(db.questCountColor) == "table" and db.questCountColor or nil
	local alpha = saved and saved[4] or 1
	local c = db and db.questCountCustom and saved
	if c then
		countText:SetTextColor(c[1], c[2], c[3], alpha)
	else
		local r, g, b = countColor(quests, max)
		countText:SetTextColor(r, g, b, alpha)
	end
	countText:SetShown(db and db.enabled and db.questCount ~= false)
end

local pending
function schedule()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = nil
		xpcall(api.updateQuestCount, geterrorhandler())
		xpcall(build, geterrorhandler())
	end)
end
-- settings and other modules: always redraw (colours, fonts, zone header looks are not in the signature)
api.rebuildMoreQuests = function() forceBuild = true; schedule() end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED",
		"QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN",
		"BAG_UPDATE_DELAYED" }) do
		pcall(events.RegisterEvent, events, e)
	end
	events:SetScript("OnEvent", function(_, event)
		-- a new zone: the zones opened by hand fold again (R106-86)
		if event == "ZONE_CHANGED_NEW_AREA" then wipe(openZones) end
		-- R106-128: item buttons: cooldowns and counts; placed again after a fight
		if event == "BAG_UPDATE_COOLDOWN" then updateItemCooldowns() return end
		if event == "PLAYER_REGEN_ENABLED" then
			if itemDirty then placeItemButtons() end
			return
		end
		if event == "BAG_UPDATE_DELAYED" then updateItemCooldowns() return end
		schedule()
	end)
	schedule()
	-- folding or unfolding the "Quests" section hides or shows these quests at once (the next layout pass places them)
	local questModule = _G.QuestObjectiveTracker
	if hooksecurefunc and questModule and type(questModule.SetCollapsed) == "function" then
		hooksecurefunc(questModule, "SetCollapsed", function()
			C_Timer.After(0, function() pcall(api.layoutMoreQuests) end)
		end)
	end
end
