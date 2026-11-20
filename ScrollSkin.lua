-- Every scrollbar in RXP ForeverTracker drawn like the game's own: the art (track, thumb, arrows) is copied from the
-- character pane's scrollbar (the bar of CharacterStatsPaneScrollBox, /fstack; user's choice), read live from the
-- client, so it is exactly the game's look in every client and version. Until that bar can be read (or when a piece is
-- missing) the game's minimal-scrollbar atlases are used, else the same look in plain colours. Each owner keeps its own
-- scrolling logic; this file only draws.
--   root.scrollSkin.bar(track, thumb, step)  track: a Frame (the rail); thumb: a Frame or Texture inside it, placed
--                                            by its owner; step(dir): optional, -1 up / 1 down, makes the arrows
--                                            buttons (without it they are drawn only).
--   root.scrollSkin.native(scrollBar)        a UIPanelScrollFrameTemplate scroll bar (Slider with up / down buttons)
--   root.scrollSkin.refresh()                read the character pane's bar again and redraw every skinned bar
local _, root = ...

local KEYS = { "trackTop", "trackMiddle", "trackBottom", "thumbTop", "thumbMiddle", "thumbBottom", "arrowUp", "arrowDown" }
local ATLAS = {
	trackTop = "minimal-scrollbar-track-top", trackMiddle = "minimal-scrollbar-track-middle",
	trackBottom = "minimal-scrollbar-track-bottom",
	thumbTop = "minimal-scrollbar-thumb-top", thumbMiddle = "minimal-scrollbar-thumb-middle",
	thumbBottom = "minimal-scrollbar-thumb-bottom",
	arrowUp = "minimal-scrollbar-arrow-top", arrowDown = "minimal-scrollbar-arrow-bottom",
}
local TRACK = { 0.11, 0.11, 0.11, 0.95 }
local TRACK_EDGE = { 0.3, 0.3, 0.3, 1 }
local THUMB = { 0.9, 0.58, 0.16, 1 }
local THUMB_EDGE = { 0.5, 0.29, 0.06, 1 }
local ARROW = { 0.62, 0.62, 0.62, 1 }
local ARROW_TEX = { [-1] = "Interface\\Buttons\\Arrow-Up-Up", [1] = "Interface\\Buttons\\Arrow-Down-Up" }
local CAP = 3          -- height of the rounded ends of the track and the thumb (the character pane's own when read)
local ARROW_H = 6      -- height of each arrow
local ARROW_MIN_W = 5  -- narrower bars (the upcoming steps' 1-4 px) get no arrows

---------------------------------------------------------------------------------------------------------------------
-- The art: { key = { atlas = name } or { file = id, coords = {...} } }, or nil for plain colours
---------------------------------------------------------------------------------------------------------------------
local function artOf(region)
	if type(region) ~= "table" or not region.GetObjectType or region:GetObjectType() ~= "Texture" then return nil end
	local atlas = region.GetAtlas and region:GetAtlas()
	if type(atlas) == "string" and atlas ~= "" then return { atlas = atlas } end
	local file = region.GetTexture and region:GetTexture()
	if file then return { file = file, coords = { region:GetTexCoord() } } end
end

local function buttonArt(button)
	if type(button) ~= "table" then return nil end
	local art = artOf(button.Texture) or artOf(button.GetNormalTexture and button:GetNormalTexture())
	if art then return art end
	for _, region in ipairs(button.GetRegions and { button:GetRegions() } or {}) do
		art = artOf(region)
		if art then return art end
	end
end

-- the character pane's scrollbar: the ScrollBox's bar (CharacterStatsPaneScrollBar, or the pane's / box's .ScrollBar)
local function characterBar()
	local box = _G.CharacterStatsPaneScrollBox
	local pane = box and box.GetParent and box:GetParent() or _G.CharacterStatsPane
	local bar = _G.CharacterStatsPaneScrollBar or (pane and pane.ScrollBar) or (box and box.ScrollBar)
	return type(bar) == "table" and bar or nil
end

-- its art, when every piece can be read (all or nothing, so the pieces match); also its caps' and arrows' heights
local function readCharacterBar()
	local bar = characterBar()
	if not bar then return nil end
	local track = bar.Track
	local thumb = track and track.Thumb or bar.Thumb
	local art = {
		trackTop = artOf(track and track.Begin), trackMiddle = artOf(track and track.Middle),
		trackBottom = artOf(track and track.End),
		thumbTop = artOf(thumb and thumb.Begin), thumbMiddle = artOf(thumb and thumb.Middle),
		thumbBottom = artOf(thumb and thumb.End),
		arrowUp = buttonArt(bar.Back), arrowDown = buttonArt(bar.Forward),
	}
	for _, key in ipairs(KEYS) do
		if not art[key] then return nil end
	end
	local function height(region, fallback)
		local h = region and region.GetHeight and region:GetHeight()
		return (type(h) == "number" and h >= 1 and h <= 12) and h or fallback
	end
	art.trackCap = height(track.Begin, CAP)
	art.thumbCap = height(thumb.Begin, CAP)
	art.arrowH = height(bar.Back, ARROW_H)
	art.live = true
	return art
end

local function defaultArt()
	if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
	local art = {}
	for _, key in ipairs(KEYS) do
		if not C_Texture.GetAtlasInfo(ATLAS[key]) then return nil end
		art[key] = { atlas = ATLAS[key] }
	end
	art.trackCap, art.thumbCap, art.arrowH = CAP, CAP, ARROW_H
	return art
end

-- read once; refresh() (login, the character pane opening) reads again
local current, resolved = nil, false
local function art()
	if not resolved then
		current, resolved = readCharacterBar() or defaultArt(), true
	end
	return current
end

local function color(t, c)
	t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- one piece of art on a texture (the colours' tints undone first)
local function paint(t, desc)
	if t.SetDesaturated then t:SetDesaturated(false) end
	if t.SetVertexColor then t:SetVertexColor(1, 1, 1, 1) end
	if desc.atlas then
		t:SetAtlas(desc.atlas)
	else
		t:SetTexture(desc.file)
		local c = desc.coords
		if c and #c == 8 then t:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
		elseif c and #c >= 4 then t:SetTexCoord(c[1], c[2], c[3], c[4])
		else t:SetTexCoord(0, 1, 0, 1) end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Every skinned piece, so the art can be applied again when the character pane's bar can be read later
---------------------------------------------------------------------------------------------------------------------
local pieces = {}  -- { tex, key, fill colour, kind ("cap", "middle", "line", "arrow", "glow"), dir, part }
local holders = {} -- arrow holders: their height follows the art

local function applyPiece(p)
	local a = art()
	local t = p.tex
	if p.kind == "line" then -- the colours' 1 px sides: only without art
		t:SetShown(a == nil)
		return
	end
	if p.kind == "cap" then
		local cap = a and (p.part == "thumb" and a.thumbCap or a.trackCap) or CAP
		t:SetHeight(cap)
	end
	if a then
		paint(t, a[p.key])
	elseif p.kind == "arrow" or p.kind == "glow" then
		t:SetTexture(ARROW_TEX[p.dir])
		t:SetDesaturated(true)
		t:SetVertexColor(ARROW[1], ARROW[2], ARROW[3], ARROW[4])
	else
		color(t, p.fill)
	end
end

local function add(tex, key, fill, kind, dir, part)
	local p = { tex = tex, key = key, fill = fill, kind = kind, dir = dir, part = part }
	pieces[#pieces + 1] = p
	applyPiece(p)
	return tex
end

-- a rail of three pieces (top end, middle, bottom end) over region, drawn on owner; part: "track" or "thumb"
local function slices(owner, layer, region, part, fill, edge)
	local a, b, c = owner:CreateTexture(nil, layer), owner:CreateTexture(nil, layer), owner:CreateTexture(nil, layer)
	a:SetPoint("TOPLEFT", region, "TOPLEFT"); a:SetPoint("TOPRIGHT", region, "TOPRIGHT")
	c:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT"); c:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
	b:SetPoint("TOPLEFT", a, "BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT", c, "TOPRIGHT")
	add(a, part .. "Top", edge, "cap", nil, part)
	add(b, part .. "Middle", fill, "middle", nil, part)
	add(c, part .. "Bottom", edge, "cap", nil, part)
	-- a 1 px darker side on each edge (the colours' bevel), hidden with the game's art
	for _, side in ipairs({ "LEFT", "RIGHT" }) do
		local line = owner:CreateTexture(nil, layer, nil, 1)
		line:SetPoint("TOP" .. side, a, "BOTTOM" .. side)
		line:SetPoint("BOTTOM" .. side, c, "TOP" .. side)
		line:SetWidth(1)
		color(line, edge)
		add(line, nil, edge, "line")
	end
end

-- an arrow just above (dir -1) or below (dir 1) the rail; a button when step is given
local function arrow(track, dir, step)
	local holder = CreateFrame(step and "Button" or "Frame", nil, track)
	local a = art()
	holder:SetHeight(a and a.arrowH or ARROW_H)
	holders[#holders + 1] = holder
	if dir < 0 then
		holder:SetPoint("BOTTOMLEFT", track, "TOPLEFT", 0, 1)
		holder:SetPoint("BOTTOMRIGHT", track, "TOPRIGHT", 0, 1)
	else
		holder:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -1)
		holder:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -1)
	end
	local key = dir < 0 and "arrowUp" or "arrowDown"
	local tex = holder:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	add(tex, key, nil, "arrow", dir)
	if step then
		holder:RegisterForClicks("LeftButtonUp")
		holder:SetScript("OnClick", function() step(dir) end)
		holder:SetScript("OnMouseDown", function() tex:SetAlpha(0.6) end)
		holder:SetScript("OnMouseUp", function() tex:SetAlpha(1) end)
		local glow = holder:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		add(glow, key, nil, "glow", dir)
		glow:SetBlendMode("ADD")
		glow:SetAlpha(0.4)
	end
	return holder
end

local skin = {}

function skin.bar(track, thumb, step)
	local thumbOwner = thumb.CreateTexture and thumb or track
	slices(track, "BACKGROUND", track, "track", TRACK, TRACK_EDGE)
	slices(thumbOwner, "OVERLAY", thumb, "thumb", THUMB, THUMB_EDGE)
	if thumb.SetColorTexture then thumb:SetColorTexture(0, 0, 0, 0) end -- a texture thumb now only places the art
	local arrows = { arrow(track, -1, step), arrow(track, 1, step) }
	-- no arrows on very thin bars; checked again whenever the rail changes width
	local function fit()
		local wide = (track:GetWidth() or 0) >= ARROW_MIN_W
		for _, a in ipairs(arrows) do a:SetShown(wide) end
	end
	track:HookScript("OnSizeChanged", fit)
	fit()
	return arrows
end

local function skinButton(button, dir)
	if not button then return end
	local a = art()
	button:SetSize(8, a and a.arrowH or ARROW_H)
	holders[#holders + 1] = button
	local key = dir < 0 and "arrowUp" or "arrowDown"
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
		local t = button[getter] and button[getter](button)
		if t then
			t:ClearAllPoints()
			t:SetAllPoints()
			t:SetTexCoord(0, 1, 0, 1)
			add(t, key, nil, getter == "GetHighlightTexture" and "glow" or "arrow", dir)
			if getter == "GetPushedTexture" then t:SetAlpha(0.6) end
			if getter == "GetDisabledTexture" then t:SetAlpha(0.35) end
			if getter == "GetHighlightTexture" then t:SetBlendMode("ADD"); t:SetAlpha(0.4) end
		end
	end
end

function skin.native(bar)
	if not bar or bar.qtsSkinned then return end
	bar.qtsSkinned = true
	local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
	for _, region in ipairs({ bar:GetRegions() }) do
		if region ~= thumb and region.SetAlpha and region.GetObjectType and region:GetObjectType() == "Texture" then
			region:SetAlpha(0)
		end
	end
	bar:SetWidth(8)
	if thumb then
		thumb:SetSize(8, 24)
		add(thumb, "thumbMiddle", THUMB, "middle", nil, "thumb")
		local top, bottom = bar:CreateTexture(nil, "OVERLAY"), bar:CreateTexture(nil, "OVERLAY")
		top:SetPoint("BOTTOMLEFT", thumb, "TOPLEFT"); top:SetPoint("BOTTOMRIGHT", thumb, "TOPRIGHT")
		bottom:SetPoint("TOPLEFT", thumb, "BOTTOMLEFT"); bottom:SetPoint("TOPRIGHT", thumb, "BOTTOMRIGHT")
		add(top, "thumbTop", THUMB_EDGE, "cap", nil, "thumb")
		add(bottom, "thumbBottom", THUMB_EDGE, "cap", nil, "thumb")
	end
	slices(bar, "BACKGROUND", bar, "track", TRACK, TRACK_EDGE)
	local name = bar.GetName and bar:GetName()
	skinButton(bar.ScrollUpButton or (name and _G[name .. "ScrollUpButton"]), -1)
	skinButton(bar.ScrollDownButton or (name and _G[name .. "ScrollDownButton"]), 1)
end

-- read the character pane's bar again; when its art changed, every skinned bar is drawn again
function skin.refresh()
	local before = current
	resolved = false
	local now = art()
	if now == before then return false end
	for _, p in ipairs(pieces) do applyPiece(p) end
	for _, h in ipairs(holders) do
		if h.SetHeight then h:SetHeight(now and now.arrowH or ARROW_H) end
	end
	return true
end
skin.characterBar = characterBar

-- the character pane may build its bar after this addon loads: read it at login and whenever it opens
if CreateFrame then
	local watcher = CreateFrame("Frame")
	if watcher.RegisterEvent then watcher:RegisterEvent("PLAYER_LOGIN") end
	if watcher.SetScript then
		watcher:SetScript("OnEvent", function()
			skin.refresh()
			local frame = _G.CharacterFrame
			if type(frame) == "table" and frame.HookScript and not skin.hookedCharacterFrame then
				skin.hookedCharacterFrame = true
				frame:HookScript("OnShow", function() if not (current and current.live) then skin.refresh() end end)
			end
		end)
	end
end

root.scrollSkin = skin
