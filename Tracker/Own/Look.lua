-- ForeverTrackerPlus: our own tracker, phase 2 (OWN_TRACKER_PLAN.md): the look.
--
-- Same look as Blizzard's tracker (user, 2026-11-26), read from it, never written to it:
--   fonts    our own font objects, copied from Blizzard's (ObjectiveTrackerHeaderFont, ObjectiveTrackerLineFont), then
--            the chosen font (api.fontPath), the outlines (db.titleOutline, db.objectiveOutline) and the Quest Tracker
--            scale (db.questScale) applied to OUR objects only. Zone headers: GameFontNormalSmall's size *
--            db.zoneHeaderScale, as ZoneSort's styleLabel.
--   headers  api.ownMirror(src, dst): every texture and text of a Blizzard header (the "All Objectives" header and
--            the Quests header) drawn again on our frame: same atlas or file, size, anchors, layer, colour.
--
-- RULE: on Blizzard's frames and font objects only Get* reads (tests/own_tracker_rules_test.lua).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function clamp(v, lo, hi, d) v = tonumber(v) or d; return math.min(math.max(v, lo), hi) end

---------------------------------------------------------------------------------------------------------------------
-- Fonts
local fonts = {} -- kind -> our font object
local SOURCES = {
	title = { "ObjectiveTrackerHeaderFont", "GameFontNormal" },
	line = { "ObjectiveTrackerLineFont", "GameFontHighlightSmall" },
	header = { "ObjectiveTrackerHeaderFont", "GameFontNormal" },
	zone = { "GameFontNormalSmall" },
}
local function source(kind)
	for _, name in ipairs(SOURCES[kind]) do
		local o = _G[name]
		if o and o.GetFont then
			local file, size, flags = o:GetFont()
			if file and size then return file, size, flags or "" end
		end
	end
	return "Fonts\\FRIZQT__.TTF", 12, ""
end
local function withOutline(flags, on)
	if not on or flags:find("OUTLINE", 1, true) then return flags end
	return flags == "" and "OUTLINE" or (flags .. ",OUTLINE")
end

-- the font each kind of our text uses now: file, size, flags
function api.ownFontSpec(kind)
	local db = ns.db or {}
	local file, size, flags = source(kind)
	file = (api.fontPath and api.fontPath()) or file
	local qs = clamp(db.questScale, 0.5, 2, 1)
	if kind == "title" then
		size, flags = size * qs, withOutline(flags, db.titleOutline)
	elseif kind == "line" then
		size, flags = size * qs, withOutline(flags, db.objectiveOutline)
	elseif kind == "zone" then
		size = size * clamp(db.zoneHeaderScale, 0.5, 3, 1) * qs
		flags = db.zoneHeaderOutline and withOutline(flags, true) or flags
	end
	return file, size, flags
end

function api.ownFont(kind)
	local o = fonts[kind]
	if not o then
		o = CreateFont("ForeverTrackerPlusOwn_" .. kind)
		fonts[kind] = o
	end
	local file, size, flags = api.ownFontSpec(kind)
	pcall(o.SetFont, o, file, size, flags)
	local c = kind == "header" and _G.ObjectiveTrackerHeaderFont
	if c and c.GetTextColor then
		local r, g, b = c:GetTextColor()
		if r and not isSecret(r) then o:SetTextColor(r, g, b) end
	end
	o:SetShadowOffset(1, -1)
	o:SetShadowColor(0, 0, 0, 1)
	return o
end
function api.ownApplyFonts() for kind in pairs(SOURCES) do api.ownFont(kind) end end

---------------------------------------------------------------------------------------------------------------------
-- Header art: copy a Blizzard frame's textures and texts onto our frame (read only on theirs)
local function copyTexture(src, dst)
	local atlas = src.GetAtlas and src:GetAtlas()
	if atlas and not isSecret(atlas) then
		dst:SetAtlas(atlas, false)
	else
		local tex = src:GetTexture()
		if tex and not isSecret(tex) then dst:SetTexture(tex) end
		local ok, a, b, c, d, e, f, g, h = pcall(src.GetTexCoord, src)
		if ok and a then dst:SetTexCoord(a, b, c, d, e, f, g, h) end
	end
	local r, g, b, a = src:GetVertexColor()
	if r then dst:SetVertexColor(r, g, b, a) end
	if src.GetBlendMode then pcall(dst.SetBlendMode, dst, src:GetBlendMode()) end
end

-- map: Blizzard region -> our copy; points relative to src (or a copied region) are remapped, others go to dst
local function copyPoints(srcRegion, dstRegion, src, dst, map)
	dstRegion:ClearAllPoints()
	local n = srcRegion:GetNumPoints() or 0
	if n == 0 then dstRegion:SetAllPoints(dst) return end
	for i = 1, n do
		local point, rel, relPoint, x, y = srcRegion:GetPoint(i)
		if point and not isSecret(x) then
			local target = (rel == src or rel == nil) and dst or map[rel] or dst
			dstRegion:SetPoint(point, target, relPoint, x, y)
		end
	end
end

-- returns { textures = {...}, texts = {...}, map }; skip: Blizzard regions not to copy (its own title text we replace)
function api.ownMirror(src, dst, skip)
	local out = { textures = {}, texts = {}, map = {} }
	if not (src and dst and src.GetRegions) then return out end
	local regions = { src:GetRegions() }
	for _, r in ipairs(regions) do
		if not (skip and skip[r]) and r.IsObjectType then
			if r:IsObjectType("Texture") then
				local layer, sub = r:GetDrawLayer()
				local t = dst:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
				copyTexture(r, t)
				local w, h = r:GetSize()
				if w and h and w > 0 and h > 0 then t:SetSize(w, h) end
				t:SetAlpha(r:GetAlpha() or 1)
				t:SetShown(r:IsShown())
				out.map[r] = t
				out.textures[#out.textures + 1] = t
			end
		end
	end
	for r, t in pairs(out.map) do copyPoints(r, t, src, dst, out.map) end
	return out
end

-- a Blizzard minimize button's art on our button; expand: the "+" look (the atlas name with collapse -> expand)
function api.ownMirrorButton(src, dst, expand)
	if not (src and dst) then return false end
	local any = false
	for _, kind in ipairs({ "Normal", "Pushed", "Highlight" }) do
		local s = src["Get" .. kind .. "Texture"] and src["Get" .. kind .. "Texture"](src)
		if s then
			local atlas = s.GetAtlas and s:GetAtlas()
			if atlas and not isSecret(atlas) then
				if expand then
					local other = atlas:gsub("[Cc]ollapse", "expand")
					if other ~= atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(other) then atlas = other end
				end
				dst["Set" .. kind .. "Atlas"](dst, atlas)
				any = true
			else
				local tex = s:GetTexture()
				if tex and not isSecret(tex) then dst["Set" .. kind .. "Texture"](dst, tex); any = true end
			end
		end
	end
	local w, h = src:GetSize()
	if w and h and w > 0 then dst:SetSize(w, h) end
	return any
end
