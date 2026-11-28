-- R106-84: the dungeon card at the top of the quest tracker, in the look of Blizzard's Delves card (user's reference):
--   a header "Dungeon" or "Raid" (Blizzard's tracker header, with its collapse button), then a dark card with the
--   instance's name, a banner at its top right with the number of players in the party, a skull with the party's
--   deaths in this instance, and under them DungeonJournal's run tracker window (time, gold, the bosses' portraits)
--   moved inside the card, without its own frame, title, close button and size grip.
-- Shown inside a dungeon or raid. Quest list > "Dungeon card at the top" (db.dungeonCard, on by default).
--
-- DungeonJournal (ForeverDungeonJournal): its tracker is ForeverDungeonJournalRunTracker, redrawn every second by
-- ForeverDungeonJournal_NS.UpdateRunTracker, which decides when it shows. Its click-to-target areas are separate
-- buttons on UIParent that it puts back over the portraits every second out of combat, so the window itself holds
-- nothing protected and can be moved into the card (its own comment: "the tracker can always be moved, in combat too").
-- Switched off (or the addon gone), the window goes back where it was, with its look.
--
-- The deaths: DungeonJournal counts only the player's own; the card counts every party member's, from the units
-- (dead or a ghost, not feigning) twice a second while inside, kept per run (DungeonJournal's run, else the
-- instance) so a /reload keeps the count.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local CARD = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\DelveCard"
local BANNER = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\DelveBanner"
local SKULL = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Skull"
-- R106-98: the addon's own book (tests/make_book.py), in the look of DungeonJournal's icon (INV_Misc_Book_09) but on a
-- see-through background (user: the game icon's dark square showed around it)
local BOOK = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Book"
local ADDON_DJ = "ForeverDungeonJournal"
local BANNER_W, BANNER_H = 24, 36            -- DelveBanner.tga is 32x48 (R106-88: shorter)
local ICON_SIZE = 18 -- R106-89: the book, the reset button and the eye, all the same size
local EYE_OPEN = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\EyeOpen"
local EYE_CLOSED = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\EyeClosed"
local CARD_TEX, CARD_CORNER = 64, 16       -- DelveCard.tga's size and its nine-slice corner (tests/make_delve.py)
local PAD, ROW_GAP = 10, 6
local FDJ_TOP = 26                          -- DungeonJournal's title bar: its content starts below it
local FDJ_WIDTH = 236

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function enabled() return db and db.dungeonCard ~= false end

-- R106-93: the eye is DungeonJournal's own Options > Dungeon Tracker > "Hide Tracker" (user): ticked = its tracker
-- hidden (by DungeonJournal itself: FDJ.SetTrackerHidden, as its X and its checkbox do)
local function fdjHidden()
	local ns2 = _G.ForeverDungeonJournal_NS
	if not (ns2 and type(ns2.TrackerOption) == "function") then return false end
	local ok, on = pcall(ns2.TrackerOption, "hide")
	return ok and on == true
end
local function setFdjHidden(on)
	local ns2 = _G.ForeverDungeonJournal_NS
	if ns2 and type(ns2.SetTrackerHidden) == "function" then pcall(ns2.SetTrackerHidden, on and true or false) end
end

-- inside a dungeon or raid: its kind and name
local function instance()
	if not IsInInstance then return nil end
	local inside, kind = IsInInstance()
	if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
	local name, _, _, _, _, _, _, id = GetInstanceInfo()
	if isSecret(name) then name = nil end
	return kind, name, id
end
api.dungeonInstance = instance

local function fdj() return _G.ForeverDungeonJournal_NS end
local function fdjRun()
	local ns2 = fdj()
	local log = ns2 and ns2.RunLog
	local ok, run = pcall(function() return log and log.Current and log.Current() end)
	return ok and type(run) == "table" and run or nil
end

-- deaths ---------------------------------------------------------------------------------------------------------
local deadNow = {} -- [name] = true while that member is dead
local function deathKey()
	local run = fdjRun()
	if run and run.id then return "run:" .. tostring(run.id) end
	local kind, name, id = instance()
	return kind and ("instance:" .. tostring(id or name)) or nil
end
local function deathStore()
	db.dungeonDeaths = type(db.dungeonDeaths) == "table" and db.dungeonDeaths or {}
	return db.dungeonDeaths
end
local function groupUnits()
	local list = { "player" }
	if IsInRaid and IsInRaid() then
		list = {}
		for i = 1, 40 do list[#list + 1] = "raid" .. i end
	else
		for i = 1, 4 do list[#list + 1] = "party" .. i end
	end
	return list
end
local function countDeaths()
	local key = deathKey()
	if not key then wipe(deadNow) return end
	local store = deathStore()
	if store.key ~= key then store.key, store.count = key, 0; wipe(deadNow) end
	local changed = false
	for _, unit in ipairs(groupUnits()) do
		if UnitExists(unit) then
			local name = UnitName(unit)
			if type(name) == "string" and not isSecret(name) then
				local okD, dead = pcall(UnitIsDeadOrGhost, unit)
				local okF, feign = pcall(function() return UnitIsFeignDeath and UnitIsFeignDeath(unit) end)
				dead = okD and dead and not isSecret(dead) and not (okF and feign) and true or false
				if dead and not deadNow[name] then store.count = (store.count or 0) + 1; changed = true end
				deadNow[name] = dead or nil
			end
		end
	end
	return changed
end
function api.dungeonDeaths()
	local store = db and type(db.dungeonDeaths) == "table" and db.dungeonDeaths
	return store and store.key == deathKey() and store.count or 0
end

-- the card ---------------------------------------------------------------------------------------------------------
local card, header, body, title, banner, bannerText, skull, deathText, capText
local slices = {}

-- the card's art in nine slices: the corners keep their size, the edges and the middle stretch
local function layoutSlices(w, h)
	local c = math.min(CARD_CORNER, w / 2, h / 2)
	local t = CARD_CORNER / CARD_TEX
	local cols = { { 0, c, 0, t }, { c, w - 2 * c, t, 1 - t }, { w - c, c, 1 - t, 1 } }
	local rows = { { 0, c, 0, t }, { c, h - 2 * c, t, 1 - t }, { h - c, c, 1 - t, 1 } }
	for r = 1, 3 do
		for col = 1, 3 do
			local tex = slices[(r - 1) * 3 + col]
			local cx, cy = cols[col], rows[r]
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", body, "TOPLEFT", cx[1], -cy[1])
			tex:SetSize(math.max(cx[2], 0.01), math.max(cy[2], 0.01))
			tex:SetTexCoord(cx[3], cx[4], cy[3], cy[4])
		end
	end
end

local function fontOf(objectName, fallbackSize)
	local object = _G[objectName]
	if object and object.GetFont then
		local file, size, flags = object:GetFont()
		if file and size then return file, size, flags end
	end
	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fallbackSize, ""
end

-- The header in the look of the tracker's "Quests" header (Blizzard's section header): its background, text and
-- collapse button are copied from it (atlas or file, texture coordinates), not made from Blizzard's template (its
-- scripts expect a tracker section). Without the Quests header: a gold line under the text.
local function copyTexture(src, dst)
	if not (src and dst and src.GetAtlas) then return false end
	local atlas = src:GetAtlas()
	if atlas then dst:SetAtlas(atlas) return true end
	local file = src.GetTexture and src:GetTexture()
	if not file then return false end
	dst:SetTexture(file)
	if src.GetTexCoord then dst:SetTexCoord(src:GetTexCoord()) end
	return true
end
-- the button's art collapsed or not: Blizzard's atlases name it ("...collapse" / "...expand")
local function buttonArt(tex, collapsed)
	local atlas = tex and tex.GetAtlas and tex:GetAtlas()
	if not atlas then return end
	local want = collapsed and atlas:gsub("[Cc]ollapse", "expand") or atlas:gsub("[Ee]xpand", "collapse")
	if want ~= atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(want) then tex:SetAtlas(want) end
end

local function setCollapsed(on)
	db.dungeonCollapsed = on and true or nil
	if api.applyLayout then api.applyLayout() end
end

-- R106-97: the Quests header's art (its background and the line under it) copied piece by piece: each texture of the
-- header frame (not its Shine / Glow flashes), with its draw layer, size, points (moved from the Quests header to this
-- one), colour and opacity, so the line under "Dungeon" is the one under "Quests" (user: it was missing; only the
-- Background was copied, stretched over the whole header). Re-copied on each layout: Quest list > the line's colour
-- (Extras.lua applyQuestsHeaderLook) tints the Quests header's pieces, and this one follows.
local function mirrorHeaderArt(h)
	local quests = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not (quests and quests.GetRegions) then return false end
	h.art = type(h.art) == "table" and h.art or {}
	local sources, mine = {}, {}
	for _, r in ipairs({ quests:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "Texture" and r ~= quests.Shine and r ~= quests.Glow then
			sources[#sources + 1] = r
		end
	end
	for i, src in ipairs(sources) do
		local t = h.art[i] or h:CreateTexture(nil, "BACKGROUND")
		h.art[i] = t
		mine[src] = t
	end
	for i, src in ipairs(sources) do
		local t = h.art[i]
		local layer, sub = src:GetDrawLayer()
		if layer then pcall(t.SetDrawLayer, t, layer, sub) end
		if not copyTexture(src, t) then t:SetColorTexture(0, 0, 0, 0) end
		if src.GetVertexColor then t:SetVertexColor(src:GetVertexColor()) end
		t:SetAlpha(src:GetAlpha() or 1)
		if src.GetBlendMode and src:GetBlendMode() then pcall(t.SetBlendMode, t, src:GetBlendMode()) end
		t:ClearAllPoints()
		local n = src:GetNumPoints() or 0
		for p = 1, n do
			local point, rel, relPoint, x, y = src:GetPoint(p)
			if rel == quests or rel == nil or not mine[rel] then rel = h else rel = mine[rel] end
			t:SetPoint(point, rel, relPoint, x or 0, y or 0)
		end
		if n == 0 then t:SetAllPoints(h) end
		local w, ht = src:GetSize()
		if n < 2 and w and w > 0 then t:SetSize(w, ht) end
		t:SetShown(src:IsShown())
	end
	for i = #sources + 1, #h.art do h.art[i]:Hide() end
	return #sources > 0
end

local function createHeader(parent)
	local h = CreateFrame("Frame", nil, parent)
	local quests = _G.QuestObjectiveTracker and _G.QuestObjectiveTracker.Header
	if not mirrorHeaderArt(h) then
		h.Background = h:CreateTexture(nil, "BACKGROUND")
		h.Background:SetColorTexture(0.75, 0.61, 0, 0.6)
		h.Background:SetHeight(1)
		h.Background:SetPoint("BOTTOMLEFT", 0, 0)
		h.Background:SetPoint("BOTTOMRIGHT", 0, 0)
	end
	h.Text = h:CreateFontString(nil, "OVERLAY")
	local qText = quests and quests.Text
	local file, size, flags = fontOf("ObjectiveTrackerHeaderFont", 14)
	if qText and qText.GetFont and qText:GetFont() then file, size, flags = qText:GetFont() end
	h.Text:SetFont(file, size, flags)
	if qText and qText.GetTextColor then h.Text:SetTextColor(qText:GetTextColor()) else h.Text:SetTextColor(1, 0.82, 0) end
	h.Text:SetShadowOffset(1, -1)
	h.Text:SetShadowColor(0, 0, 0, 1)
	h.Text:SetPoint("LEFT", h, "LEFT", 4, 1)
	-- the collapse button, as the Quests header's
	local qButton = quests and quests.MinimizeButton
	local b = CreateFrame("Button", nil, h)
	b:SetSize(16, 16)
	b:SetPoint("RIGHT", h, "RIGHT", -2, 0)
	b:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up") -- replaced below by the Quests button's art
	local copied = false
	if qButton then
		local w, bh = qButton:GetSize()
		if w and w > 0 then b:SetSize(w, bh) end
		copied = copyTexture(qButton.GetNormalTexture and qButton:GetNormalTexture(), b:GetNormalTexture())
		if qButton.GetPushedTexture and qButton:GetPushedTexture() then
			b:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
			copyTexture(qButton:GetPushedTexture(), b:GetPushedTexture())
		end
		if qButton.GetHighlightTexture and qButton:GetHighlightTexture() then
			b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
			copyTexture(qButton:GetHighlightTexture(), b:GetHighlightTexture())
		end
	end
	if not copied then
		b:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
		b:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
		b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	end
	b:SetScript("OnClick", function() setCollapsed(not db.dungeonCollapsed) end)
	h.MinimizeButton = b
	h.SetCollapsed = function(self, collapsed)
		local nt, pt = b:GetNormalTexture(), b:GetPushedTexture()
		if copied then
			buttonArt(nt, collapsed); buttonArt(pt, collapsed)
		else
			local state = collapsed and "Plus" or "Minus"
			b:SetNormalTexture("Interface\\Buttons\\UI-" .. state .. "Button-Up")
			b:SetPushedTexture("Interface\\Buttons\\UI-" .. state .. "Button-Down")
		end
	end
	h:EnableMouse(true)
	h:SetScript("OnMouseUp", function(_, mouse) if mouse == "LeftButton" then setCollapsed(not db.dungeonCollapsed) end end)
	return h
end

local function createCard()
	card = CreateFrame("Frame", "ForeverTrackerPlusDungeonCard", UIParent)
	header = createHeader(card)
	header:SetHeight(26)
	body = CreateFrame("Frame", nil, card)
	for i = 1, 9 do
		local tex = body:CreateTexture(nil, "BACKGROUND")
		tex:SetTexture(CARD)
		slices[i] = tex
	end
	title = body:CreateFontString(nil, "OVERLAY")
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	title:SetTextColor(0.95, 0.92, 0.85)
	title:SetShadowOffset(1, -1)
	title:SetShadowColor(0, 0, 0, 1)
	banner = body:CreateTexture(nil, "ARTWORK")
	banner:SetTexture(BANNER)
	bannerText = body:CreateFontString(nil, "OVERLAY")
	bannerText:SetTextColor(1, 0.86, 0.45)
	bannerText:SetShadowOffset(1, -1)
	bannerText:SetShadowColor(0, 0, 0, 1)
	-- R106-88: DungeonJournal's book after the name (click: its journal), its reset button after the book
	body.book = CreateFrame("Button", nil, body)
	body.book:SetSize(ICON_SIZE, ICON_SIZE)
	body.book.icon = body.book:CreateTexture(nil, "ARTWORK")
	-- R106-91 / R106-98: the whole button; the book in Book.tga has its own margin (about 14 of the 18 px, as the
	-- reset button's and the eye's art)
	body.book.icon:SetAllPoints()
	body.book.icon:SetTexture(BOOK)
	body.book:SetScript("OnClick", function()
		local open = _G.ForeverDungeonJournal_OnAddonCompartmentClick
		if type(open) == "function" then pcall(open, ADDON_DJ, "LeftButton") end
	end)
	body.book:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Dungeon Journal")
		GameTooltip:AddLine("Click to open it.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	body.book:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- R106-89: the eye: DungeonJournal's part of the card (bosses, time, gold) shown (open) or hidden (closed)
	body.eye = CreateFrame("Button", nil, body)
	body.eye:SetSize(ICON_SIZE, ICON_SIZE)
	body.eye.icon = body.eye:CreateTexture(nil, "ARTWORK")
	body.eye.icon:SetAllPoints()
	body.eye.icon:SetTexture(EYE_OPEN)
	body.eye:SetHighlightTexture(EYE_OPEN, "ADD")
	body.eye:SetScript("OnClick", function()
		db.dungeonJournalHidden = nil -- (R106-89's own setting, no longer used)
		setFdjHidden(not fdjHidden())
		if api.applyLayout then api.applyLayout() end
	end)
	body.eye:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		local hidden = fdjHidden()
		GameTooltip:SetText(hidden and "Dungeon tracker hidden" or "Dungeon tracker shown")
		GameTooltip:AddLine(hidden and "Click to show the bosses, time and gold."
			or "Click to hide the bosses, time and gold.", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("DungeonJournal's \"Hide Tracker\" option.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	body.eye:SetScript("OnLeave", function() GameTooltip:Hide() end)
	skull = body:CreateTexture(nil, "ARTWORK")
	skull:SetTexture(SKULL)
	-- 3.2 (user): the run light, left of the skull: a small red dot that pulses while the run goes on
	body.runLight = body:CreateTexture(nil, "OVERLAY")
	body.runLight:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\MarkerGlow")
	body.runLight:SetVertexColor(1, 0.15, 0.1, 1)
	body.runLight:SetSize(12, 12)
	body.runLight:Hide()
	deathText = body:CreateFontString(nil, "OVERLAY")
	deathText:SetTextColor(1, 1, 1)
	deathText:SetShadowOffset(1, -1)
	deathText:SetShadowColor(0, 0, 0, 1)
	-- the banner and the skull explain themselves on hover
	local function tip(owner, text)
		owner:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(text())
			GameTooltip:Show()
		end)
		owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	body.bannerHit = CreateFrame("Frame", nil, body)
	body.bannerHit:SetAllPoints(banner)
	body.bannerHit:EnableMouse(true)
	tip(body.bannerHit, function() return "Players in the group: " .. (bannerText:GetText() or "1") end)
	body.skullHit = CreateFrame("Frame", nil, body)
	body.skullHit:EnableMouse(true)
	tip(body.skullHit, function() return "Deaths in the group this run: " .. (deathText:GetText() or "0") end)
	-- R106-100: instances this hour and the saved lockout (InstanceCap.lua), under the name
	capText = body:CreateFontString(nil, "OVERLAY")
	capText:SetJustifyH("LEFT")
	capText:SetTextColor(0.8, 0.8, 0.8)
	capText:SetShadowOffset(1, -1)
	capText:SetShadowColor(0, 0, 0, 1)
	if capText.SetWordWrap then capText:SetWordWrap(false) end
	body.capHit = CreateFrame("Frame", nil, body)
	body.capHit:SetAllPoints(capText)
	body.capHit:EnableMouse(true)
	body.capHit:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if api.instanceCapTooltip then api.instanceCapTooltip(GameTooltip) end
		GameTooltip:Show()
	end)
	body.capHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- DungeonJournal's window inside the card --------------------------------------------------------------------------
local adopted -- its window while it is in the card
local forcedOn -- the card turned DungeonJournal's "show the tracker" on (given back on release)
-- DungeonJournal's per-character tracker settings (ForeverDungeonJournalCharacterDB.runTracker)
local function fdjTrackerDB()
	local cdb = _G.ForeverDungeonJournalCharacterDB
	return type(cdb) == "table" and type(cdb.runTracker) == "table" and cdb.runTracker or nil
end
-- R106-88: its window wanted in the card even where it would not show by itself (solo; user: no bosses, no time or
-- gold in the card): its "show the tracker" setting is turned on while the card is (as its own /dj tracker does;
-- given back on release), and before the first kill, when it has no run yet, its fresh-run state for this dungeon
-- (every boss alive, 0:00: its own reset button's state, until the first kill) is started. Its "Never track
-- dungeons" option is left alone.
local function wakeFdj()
	local ns2 = fdj()
	if not ns2 then return end
	local rt = fdjTrackerDB()
	if rt and not rt.on then rt.on = true; forcedOn = true end
	if rt then rt.dismissedRun = nil end
	local log = ns2.RunLog
	local hasRun = (log and log.Current and log.Current()) or (rt and rt.blankRun)
	if not hasRun and ns2.StartBlankRun and ns2.CurrentDungeon then
		local ok, key = pcall(ns2.CurrentDungeon)
		local _, name, id = instance()
		if ok and key then pcall(ns2.StartBlankRun, { dungeon = key, map = id, instanceName = name }) end
	end
	if ns2.UpdateRunTracker then pcall(ns2.UpdateRunTracker) end
end
local saved   -- what to give back: { parent, points, scale, backdrop colours }
local function fdjWindow() return _G.ForeverDungeonJournalRunTracker end

-- its own frame, title bar and buttons hidden (re-done after each of its redraws: it shows its buttons again)
local function hideChrome(t)
	for _, key in ipairs({ "logo", "title", "close", "grip", "sizeText" }) do
		local r = t[key]
		if type(r) == "table" and r.Hide then r:Hide() end
	end
	if t.SetBackdropColor then pcall(t.SetBackdropColor, t, 0, 0, 0, 0) end
	if t.SetBackdropBorderColor then pcall(t.SetBackdropBorderColor, t, 0, 0, 0, 0) end
	if type(t.line) == "table" and t.line.SetAlpha then t.line:SetAlpha(0.6) end
	if type(t.handle) == "table" and t.handle.EnableMouse then t.handle:EnableMouse(false) end -- no dragging it out of the card
	-- R106-91: its window takes no clicks (its top, under its hidden title bar, lies over the card's name line and took
	-- the book's and the eye's clicks); its portraits and reset button are their own frames and still take theirs
	if t.EnableMouse then t:EnableMouse(false) end
	-- its reset button right of the book after the card's name (R106-88; it shows it only while a run can be reset)
	local reset = t.reset
	if type(reset) == "table" and reset.SetPoint and body and body.book then
		reset:ClearAllPoints()
		reset:SetPoint("LEFT", body.book, "RIGHT", 3, 0)
		reset:SetSize(ICON_SIZE, ICON_SIZE)
		if type(reset.Icon) == "table" then reset.Icon:SetSize(9, 9) end
	end
end

local function adopt(t)
	if adopted == t then return end
	saved = { parent = t:GetParent(), points = {}, scale = t:GetScale(), movable = t:IsMovable() }
	for i = 1, t:GetNumPoints() do saved.points[i] = { t:GetPoint(i) } end
	if t.GetBackdropColor then saved.bg = { t:GetBackdropColor() } end
	if t.GetBackdropBorderColor then saved.border = { t:GetBackdropBorderColor() } end
	adopted = t
	t:SetMovable(false)
	t:SetParent(body)
	t:SetScale(1)
	hideChrome(t)
end

local function release()
	-- its "show the tracker" setting as it was before the card asked for it
	local rt = fdjTrackerDB()
	if rt and forcedOn then rt.on = nil end
	forcedOn = nil
	local t = adopted
	if not t then return end
	adopted = nil
	t:SetParent(saved.parent or UIParent)
	t:SetScale(saved.scale or 1)
	t:SetMovable(saved.movable ~= false)
	t:ClearAllPoints()
	for _, p in ipairs(saved.points) do t:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
	if #saved.points == 0 then t:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -220) end
	if saved.bg and t.SetBackdropColor then t:SetBackdropColor(unpack(saved.bg)) end
	if saved.border and t.SetBackdropBorderColor then t:SetBackdropBorderColor(unpack(saved.border)) end
	if type(t.handle) == "table" and t.handle.EnableMouse then t.handle:EnableMouse(true) end
	if t.EnableMouse then t:EnableMouse(true) end
	for _, key in ipairs({ "logo", "title" }) do if type(t[key]) == "table" then t[key]:Show() end end
	-- the reset button back after its own title, at its own size (DungeonJournal's 27, icon 13)
	if type(t.reset) == "table" and t.reset.SetPoint and type(t.title) == "table" then
		t.reset:ClearAllPoints()
		t.reset:SetPoint("LEFT", t.title, "RIGHT", 4, 0)
		t.reset:SetSize(27, 27)
		if type(t.reset.Icon) == "table" then t.reset.Icon:SetSize(13, 13) end
	end
	saved = nil
	-- its own redraw puts the buttons back
	local ns2 = fdj()
	if ns2 and ns2.UpdateRunTracker then pcall(ns2.UpdateRunTracker) end
end

-- R106-90: the rares among the bosses, in the journal's order, each with a silver star at its portrait's bottom right
-- (user), instead of DungeonJournal's own "Rare" row under them. Done after each of its redraws (it places them every
-- second): its portraits (t.portraits; a rare has isRare) are put again on its own grid (5 a row, 38 px, 6 apart),
-- ordered by their place in its journal (FDJ.DB[dungeon].bosses; a group by its first member), its "Rare" label hidden,
-- an open group's row moved under them and its height set. Its click-to-target areas follow the portraits: out of
-- combat they are put on them again at once (its own RunLogPlaceOnScreen).
local PER_ROW, PORTRAIT, PORTRAIT_GAP = 5, 38, 6
local SILVER_STAR = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\SilverStar"
local function mergeRares(t)
	local ns2 = fdj()
	local run = t.run
	local list = {}
	for i, f in ipairs(type(t.portraits) == "table" and t.portraits or {}) do
		if f:IsShown() then list[#list + 1] = { f = f, i = i } end
	end
	if #list == 0 then return end
	-- where its grid starts: the first portrait's place (the bosses come first in its layout)
	local first = t.portraits[1]
	local _, _, _, _, y0 = first:GetPoint(1)
	y0 = -(tonumber(y0) or -78)
	local at = {}
	local d = run and run.dungeon and ns2 and ns2.DB and ns2.DB[run.dungeon]
	for i, b in ipairs(d and d.bosses or {}) do
		if type(b) == "table" and type(b.name) == "string" and at[b.name] == nil then at[b.name] = i end
	end
	local function place(e)
		local f = e.f
		local g = type(f.group) == "table" and f.group
		local b = (g and g.members and g.members[1]) or (g and g.boss) or f.boss
		return (type(b) == "table" and at[b.name]) or (1000 + e.i)
	end
	table.sort(list, function(a, b)
		local pa, pb = place(a), place(b)
		if pa ~= pb then return pa < pb end
		return a.i < b.i
	end)
	local width = t.GetWidth and t:GetWidth() or FDJ_WIDTH
	local rowWidth = PER_ROW * PORTRAIT + (PER_ROW - 1) * PORTRAIT_GAP
	local left = math.floor((width - rowWidth) / 2)
	for n, e in ipairs(list) do
		local f = e.f
		local col, row = (n - 1) % PER_ROW, math.floor((n - 1) / PER_ROW)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", t, "TOPLEFT", left + col * (PORTRAIT + PORTRAIT_GAP), -(y0 + row * (PORTRAIT + PORTRAIT_GAP)))
		f.fdjX = left + col * (PORTRAIT + PORTRAIT_GAP)
		-- the silver star on a rare. R106-94: on its own small frame on DungeonJournal's window, not on the portrait:
		-- a rare not found yet has its portrait faded (alpha 0.45) and grey, and the star faded with it (user: the
		-- star full and silver always)
		if f.isRare then
			if not f.qtsStar then
				local holder = CreateFrame("Frame", nil, t)
				holder:SetSize(16, 16)
				holder.tex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
				holder.tex:SetAllPoints()
				holder.tex:SetTexture(SILVER_STAR)
				f.qtsStar = holder
			end
			local star = f.qtsStar
			star:SetFrameLevel((f.GetFrameLevel and f:GetFrameLevel() or 1) + 5)
			star:ClearAllPoints()
			star:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
			star:Show()
		elseif f.qtsStar then
			f.qtsStar:Hide()
		end
	end
	-- a portrait not shown this time: its star hidden too (it no longer goes with the portrait)
	for _, f in ipairs(t.portraits) do
		if f.qtsStar and not f:IsShown() then f.qtsStar:Hide() end
	end
	if type(t.raresLabel) == "table" and t.raresLabel.Hide then t.raresLabel:Hide() end
	local y = y0 + math.ceil(#list / PER_ROW) * (PORTRAIT + PORTRAIT_GAP)
	local groupRow = t.groupRow
	if type(groupRow) == "table" and groupRow.IsShown and groupRow:IsShown() then
		local gw = groupRow:GetWidth() or 0
		groupRow:ClearAllPoints()
		groupRow:SetPoint("TOPLEFT", t, "TOPLEFT", math.max(4, math.floor((width - gw) / 2)), -(y + 2))
		y = y + 2 + (groupRow:GetHeight() or 0) + PORTRAIT_GAP
	end
	t:SetHeight(y - PORTRAIT_GAP + 4)
	-- its click areas onto the portraits' new places (out of combat: they are protected buttons)
	if not InCombatLockdown() and ns2 and type(ns2.RunLogPlaceOnScreen) == "function" then
		for _, prefix in ipairs({ "ForeverDungeonJournalBossTarget", "ForeverDungeonJournalRareTarget" }) do
			for i = 1, 40 do
				local b = _G[prefix .. i]
				if not b then break end
				if b.portrait and b:IsShown() then pcall(ns2.RunLogPlaceOnScreen, b, b.portrait) end
			end
		end
	end
end

local fdjHooked, lastFdjH, lastFdjShown, lastResetShown
local wokeFor -- DungeonJournal asked to show for this stay inside
local function hookFdj()
	local ns2 = fdj()
	if fdjHooked or not (ns2 and type(ns2.UpdateRunTracker) == "function") then return end
	fdjHooked = true
	hooksecurefunc(ns2, "UpdateRunTracker", function()
		local t = adopted
		-- its window made for the first time (it is built on its first showing): into the card
		if not t then
			if card and card:IsShown() and fdjWindow() and api.applyLayout then api.applyLayout() end
			return
		end
		hideChrome(t)
		pcall(mergeRares, t)
		-- its height or whether it shows changed: the card and the quests under it move
		-- R106-103: also when its reset button shows or hides (a run starts or ends): it goes where the eye was, so the
		-- eye moves right of it (user: the eye was not visible until the card was redrawn)
		local h, shown = math.floor((t:GetHeight() or 0) + 0.5), t:IsShown()
		local resetShown = type(t.reset) == "table" and t.reset.IsShown and t.reset:IsShown() and true or false
		if h ~= lastFdjH or shown ~= lastFdjShown or resetShown ~= lastResetShown then
			lastFdjH, lastFdjShown, lastResetShown = h, shown, resetShown
			if api.applyLayout then api.applyLayout() end
		end
	end)
end

-- the card's texts and fonts
local function fill(kind, name)
	local hFile, hSize, hFlags = fontOf("ObjectiveTrackerHeaderFont", 14)
	local lFile, lSize, lFlags = fontOf("ObjectiveTrackerLineFont", 12)
	if header.Text then
		header.Text:SetText(kind == "raid" and (_G.LFG_TYPE_RAID or RAID or "Raid") or (_G.LFG_TYPE_DUNGEON or "Dungeon"))
	end
	title:SetFont(hFile, hSize + 1, hFlags)
	title:SetText(name or "")
	local players = (GetNumGroupMembers and GetNumGroupMembers()) or 0
	bannerText:SetFont(hFile, hSize + 1, "OUTLINE")
	bannerText:SetText(tostring(math.max(players, 1)))
	deathText:SetFont(lFile, lSize + 1, lFlags)
	local deaths = api.dungeonDeaths()
	deathText:SetText(tostring(deaths))
	-- 3.2 (user): more deaths: the number shakes red; another number of players: it bumps (Animations.lua)
	if type(deaths) == "number" and type(body.qtsDeaths) == "number" and deaths > body.qtsDeaths and api.animDeath then
		api.animDeath(deathText)
	end
	body.qtsDeaths = deaths
	local count = math.max(players, 1)
	if type(body.qtsPlayers) == "number" and body.qtsPlayers ~= count and api.animPartyBump then api.animPartyBump(bannerText) end
	body.qtsPlayers = count
	return hSize, lSize
end

function api.layoutDungeonCard(anchor, base, alpha)
	local kind, name = instance()
	local on = enabled() and kind ~= nil and anchor ~= nil and anchor.IsShown and anchor:IsShown()
	local t = fdjWindow()
	if not on then
		release()
		wokeFor = nil
		if card then card:Hide() end
		if body then body.qtsFdjWas = nil end
		return 0
	end
	if not card then createCard() end
	hookFdj()
	-- our tracker's top slot (Own/Frame.lua api.ownCardHost) and its Quests header: width, scale, left edge and header
	-- height come from them
	local module = anchor
	local ui = UIParent:GetEffectiveScale()
	local s = (module and module.GetEffectiveScale and module:GetEffectiveScale() or anchor:GetEffectiveScale()) / ui
	local width = module and module.GetWidth and module:GetWidth() or 260
	local mLeft, aLeft = module and module.GetLeft and module:GetLeft(), anchor:GetLeft()
	local dx = (mLeft and aLeft) and ((mLeft * module:GetEffectiveScale() - aLeft * anchor:GetEffectiveScale()) / ui) or 0
	card:SetScale(s)
	card:SetFrameStrata(anchor:GetFrameStrata())
	card:SetFrameLevel(anchor:GetFrameLevel() + 5)
	card:SetAlpha(alpha or 1)
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", anchor, "TOPLEFT", dx / s, -base / s)
	-- R106-97: the Quests header's width, left edge, height and art (the line under it), so both lines match
	local questsHeader = api.ownQuestsHeaderFrame and api.ownQuestsHeaderFrame()
	local qw = questsHeader and questsHeader.GetWidth and questsHeader:GetWidth()
	local qLeft = questsHeader and questsHeader.GetLeft and questsHeader:GetLeft()
	header:ClearAllPoints()
	if qw and qw > 0 and qLeft and mLeft then
		local hx = (qLeft * questsHeader:GetEffectiveScale() - mLeft * module:GetEffectiveScale()) / ui / s
		header:SetPoint("TOPLEFT", card, "TOPLEFT", hx, 0)
		header:SetWidth(qw * questsHeader:GetEffectiveScale() / ui / s)
	else
		header:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
		header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
	end
	-- R106-116: the "Dungeon" header and the line under it can be hidden (Dungeon card > "Dungeon header and its
	-- line", db.dungeonHeader). Hidden, its room stays (user: turning it off and on must not move the tracker): the card
	-- and all under it keep their places; the card is never collapsed then (its collapse button is in the header)
	local headerOn = db.dungeonHeader ~= false
	header:SetShown(headerOn)
	local qh = questsHeader and questsHeader.GetHeight and questsHeader:GetHeight()
	if qh and qh > 0 then header:SetHeight(qh * questsHeader:GetEffectiveScale() / ui / s) end
	if type(header.art) == "table" then pcall(mirrorHeaderArt, header) end
	if header.SetCollapsed then pcall(header.SetCollapsed, header, db.dungeonCollapsed and true or false) end
	local hSize, lSize = fill(kind, name)
	local headerH = header:GetHeight() or 26
	local height = headerH + 4
	local collapsed = headerOn and db.dungeonCollapsed
	-- DungeonJournal's window stays in the card, also collapsed (it hides with the card's body)
	if fdj() and not wokeFor then wokeFor = true; wakeFdj(); t = fdjWindow() end
	if t and fdj() then adopt(t) end
	if collapsed then
		if api.hideDungeonExtras then api.hideDungeonExtras() end
		body.qtsFdjWas = nil
		body:Hide()
		-- its click-to-target areas follow the portraits' places (DungeonJournal puts them there every second): the
		-- portraits off the screen, so no unseen click area stays where the card's body was
		if adopted then
			adopted:ClearAllPoints()
			adopted:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -4000, 0)
		end
	else
		-- R106-89: one line: the name, the book, the reset button and the eye; then the skull and the deaths left of
		-- the banner, level with the name; under them DungeonJournal's window, unless the eye hid it
		local nameH = hSize + 3
		-- R106-100: the instance line under the name (InstanceCap.lua), when on
		local capOn = api.instanceCapOn and api.instanceCapOn() and api.instanceCapText
		local capH = capOn and (lSize + 4) or 0
		-- 3.2 (DungeonPlus.lua): splits, the party's quests here, share, boss abilities; lines under the instance line
		if api.layoutDungeonExtras then
			local okX, extraH = pcall(api.layoutDungeonExtras, body, PAD, PAD + nameH + capH + 2,
				width - 2 * PAD - BANNER_W - 6, lSize, name)
			if okX and type(extraH) == "number" then capH = capH + extraH end
		end
		local contentTop = math.max(PAD + nameH + capH + ROW_GAP, BANNER_H + 2)
		local cardH = math.max(PAD + nameH + capH + PAD, BANNER_H + 4)
		if capOn then
			local lFile, _, lFlags = fontOf("ObjectiveTrackerLineFont", 12)
			capText:SetFont(lFile, lSize, lFlags)
			capText:SetText(api.instanceCapText(name))
			capText:ClearAllPoints()
			capText:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(PAD + nameH + 2))
			-- 3.2 (user): the hourly limit just reached: the line shakes (Animations.lua animCapShake)
			local okC, count, limit = pcall(api.instanceCap)
			local full = okC and type(count) == "number" and type(limit) == "number" and count >= limit or false
			if full and body.qtsCapFull == false and api.animCapShake then api.animCapShake(capText) end
			body.qtsCapFull = full
			capText:SetWidth(width - 2 * PAD - BANNER_W - 6)
			capText:Show()
			body.capHit:Show()
		else
			capText:Hide()
			body.capHit:Hide()
		end
		-- (the eye's "Hide Tracker": DungeonJournal hides its window itself, so the card only holds the name line)
		if adopted then
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", body, "TOPLEFT", math.floor((width - FDJ_WIDTH) / 2), -contentTop + FDJ_TOP)
			if t:IsShown() then cardH = contentTop + math.max((t:GetHeight() or FDJ_TOP) - FDJ_TOP, 0) + 4 end
		end
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
		body:SetSize(width, cardH)
		layoutSlices(width, cardH)
		banner:SetSize(BANNER_W, BANNER_H)
		banner:ClearAllPoints()
		banner:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, 1)
		-- the number in the middle of the banner (its notch left out)
		bannerText:ClearAllPoints()
		bannerText:SetPoint("CENTER", banner, "CENTER", 0, 2)
		-- the deaths left of the banner, on the name's line
		local skullSize = math.max(lSize + 2, 14)
		deathText:ClearAllPoints()
		deathText:SetPoint("RIGHT", banner, "LEFT", -6, 0)
		deathText:SetPoint("TOP", body, "TOP", 0, -(PAD + math.max(nameH - (lSize + 1), 0) / 2))
		skull:SetSize(skullSize, skullSize)
		skull:ClearAllPoints()
		skull:SetPoint("RIGHT", deathText, "LEFT", -3, 0)
		body.runLight:ClearAllPoints()
		body.runLight:SetPoint("RIGHT", skull, "LEFT", -3, 0)
		if api.animRunLight then
			api.animRunLight(body.runLight, api.dungeonRunActive and api.dungeonRunActive() or false)
		end
		body.skullHit:ClearAllPoints()
		body.skullHit:SetPoint("TOPLEFT", skull, "TOPLEFT")
		body.skullHit:SetPoint("BOTTOMRIGHT", deathText, "BOTTOMRIGHT")
		-- the name, then its buttons right after it; the name cut short only when they need the room
		local resetShown = adopted and type(adopted.reset) == "table" and adopted.reset:IsShown()
		local buttonsW = (ICON_SIZE + 4) + (resetShown and (ICON_SIZE + 3) or 0) + (adopted and (ICON_SIZE + 3) or 0)
		local deathsW = skullSize + 3 + (deathText:GetStringWidth() or 10) + 6
		local room = width - 2 * PAD - BANNER_W - deathsW - buttonsW - 4
		title:ClearAllPoints()
		title:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -PAD)
		title:SetWidth(0)
		local full = title.GetUnboundedStringWidth and title:GetUnboundedStringWidth() or title:GetStringWidth() or 0
		title:SetWidth(math.max(math.min(full + 1, room), 20))
		body.book:SetSize(ICON_SIZE, ICON_SIZE)
		body.book:ClearAllPoints()
		body.book:SetPoint("LEFT", title, "RIGHT", 4, 0)
		body.book:SetShown(fdj() ~= nil)
		-- the eye after the reset button (or the book while there is no reset): open while DungeonJournal's part shows
		body.eye:ClearAllPoints()
		body.eye:SetPoint("LEFT", resetShown and adopted.reset or body.book, "RIGHT", 3, 0)
		body.eye:SetShown(adopted ~= nil)
		-- R106-91: the book and the eye above DungeonJournal's window (its own strata, MEDIUM, may be over the card's)
		if adopted and adopted.GetFrameStrata then
			for _, b in ipairs({ body.book, body.eye }) do
				b:SetFrameStrata(adopted:GetFrameStrata())
				b:SetFrameLevel(adopted:GetFrameLevel() + 20)
			end
		end
		body.eye.icon:SetTexture(fdjHidden() and EYE_CLOSED or EYE_OPEN)
		-- 3.2 (user): the bosses' portraits drop in when they come into view (the card opens, the eye opens)
		local fdjOn = adopted ~= nil and t:IsShown() and true or false
		if fdjOn and not body.qtsFdjWas and api.animDropIn and type(t.portraits) == "table" then
			local list = {}
			for _, f in ipairs(t.portraits) do if f.IsShown and f:IsShown() then list[#list + 1] = f end end
			pcall(table.sort, list, function(a, b)
				local _, _, _, ax, ay = a:GetPoint(1)
				local _, _, _, bx, by = b:GetPoint(1)
				ax, ay, bx, by = tonumber(ax) or 0, tonumber(ay) or 0, tonumber(bx) or 0, tonumber(by) or 0
				if ay ~= by then return ay > by end
				return ax < bx
			end)
			pcall(api.animDropIn, list)
		end
		body.qtsFdjWas = fdjOn
		body:Show()
		height = height + cardH + 8
	end
	card:SetSize(width, height)
	card:Show()
	return height * s
end

-- 3.2 (user): a boss died faster than your best (DungeonPlus.lua): "NEW BEST" on the card
function api.dungeonCardNewBest(text)
	if body and body:IsShown() and api.animNewBest then api.animNewBest(body, text) end
end

-- 3.2 (user): a boss was killed (DungeonPlus.lua): its portrait turns over and shows a check (Animations.lua
-- animBossKill); the last boss (cleared): the card flashes and says CLEARED (animCleared)
function api.dungeonCardKill(bossName, cleared)
	local t = adopted
	if t and type(t.portraits) == "table" and api.animBossKill then
		for _, f in ipairs(t.portraits) do
			local b, grp = f.boss, type(f.group) == "table" and f.group
			local match = type(b) == "table" and b.name == bossName
			if not match and grp and type(grp.members) == "table" then
				for _, m in ipairs(grp.members) do if type(m) == "table" and m.name == bossName then match = true end end
			end
			if match and f.IsShown and f:IsShown() then api.animBossKill(f) break end
		end
	end
	if cleared and body and body:IsShown() and api.animCleared then api.animCleared(body) end
end

function api.setDungeonCard(on)
	db.dungeonCard = on and true or false
	if not db.dungeonCard then release() end
	if api.applyLayout then api.applyLayout() end
end

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local frame = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_DEAD",
		"PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
		pcall(frame.RegisterEvent, frame, e)
	end
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
			if api.applyLayout then api.applyLayout() end
		end
		if card and card:IsShown() then
			countDeaths()
			if event == "GROUP_ROSTER_UPDATE" and bannerText then
				bannerText:SetText(tostring(math.max((GetNumGroupMembers and GetNumGroupMembers()) or 0, 1)))
			end
			if deathText then deathText:SetText(tostring(api.dungeonDeaths())) end
		end
	end)
	-- twice a second while inside: the party's deaths
	local ticker = CreateFrame("Frame")
	local acc, capAcc = 0, 0
	ticker:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc < 0.5 then return end
		acc = 0
		if not (enabled() and instance()) then return end
		if countDeaths() and deathText then deathText:SetText(tostring(api.dungeonDeaths())) end
		-- R106-100: the instance line's times, every 30 s
		capAcc = capAcc + 0.5
		if capAcc >= 30 and capText and capText:IsShown() and api.instanceCapText then
			capAcc = 0
			local _, name = instance()
			capText:SetText(api.instanceCapText(name))
		end
	end)
end
