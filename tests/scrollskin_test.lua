-- ScrollSkin.lua: every scrollbar drawn in the Forever look (the game's minimal-scrollbar atlases when the client has
-- them all, else the same look in plain colours), arrows that scroll, no arrows on very thin bars, and the native
-- UIPanelScrollFrameTemplate bar reskinned.
local A = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function region(kind)
	local r = { kind = kind, points = {}, shown = true, alpha = 1 }
	function r:GetObjectType() return self.kind end
	function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function r:ClearAllPoints() self.points = {} end
	function r:SetAllPoints() self.all = true end
	function r:SetHeight(h) self.h = h end
	function r:SetWidth(w) self.w = w end
	function r:SetSize(w, h) self.w, self.h = w, h end
	function r:GetWidth() return self.w or 0 end
	function r:SetAtlas(name) self.atlas = name end
	function r:SetColorTexture(...) self.color = { ... } end
	function r:SetTexture(t) self.texture = t end
	function r:SetTexCoord() end
	function r:SetDesaturated(v) self.desaturated = v end
	function r:SetVertexColor(...) self.vertex = { ... } end
	function r:SetBlendMode(m) self.blend = m end
	function r:SetAlpha(a) self.alpha = a end
	function r:SetShown(v) self.shown = v and true or false end
	function r:Show() self.shown = true end
	function r:Hide() self.shown = false end
	return r
end
local function frame(kind)
	local f = region(kind or "Frame")
	f.textures, f.children, f.scripts, f.hooks = {}, {}, {}, {}
	function f:CreateTexture(_, layer)
		local t = region("Texture")
		t.layer = layer
		self.textures[#self.textures + 1] = t
		return t
	end
	function f:GetRegions() return table.unpack(self.textures) end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	function f:HookScript(k, fn) self.hooks[k] = fn end
	function f:RegisterForClicks() end
	function f:SetFrameLevel() end
	return f
end
_G.CreateFrame = function(kind, _, parent)
	local f = frame(kind)
	if parent then parent.children[#parent.children + 1] = f end
	return f
end

local atlases = true
_G.C_Texture = { GetAtlasInfo = function(name) return atlases and name:find("^minimal%-scrollbar") and {} or nil end }

local function load()
	local root = {}
	assert(loadfile(A .. "/ScrollSkin.lua"))("x", root)
	return root.scrollSkin
end

-- with the game's atlases
local skin = load()
local track, thumb = frame(), nil
track.w = 8
thumb = CreateFrame("Frame", nil, track)
local steps = {}
local arrows = skin.bar(track, thumb, function(dir) steps[#steps + 1] = dir end)
local atlasNames = {}
for _, t in ipairs(track.textures) do if t.atlas then atlasNames[t.atlas] = true end end
for _, t in ipairs(thumb.textures) do if t.atlas then atlasNames[t.atlas] = true end end
check("track drawn from the minimal-scrollbar track atlases", atlasNames["minimal-scrollbar-track-top"]
	and atlasNames["minimal-scrollbar-track-middle"] and atlasNames["minimal-scrollbar-track-bottom"])
check("thumb drawn from the gold minimal-scrollbar thumb atlases", atlasNames["minimal-scrollbar-thumb-top"]
	and atlasNames["minimal-scrollbar-thumb-middle"] and atlasNames["minimal-scrollbar-thumb-bottom"])
check("an arrow above and one below", #arrows == 2 and arrows[1].textures[1].atlas == "minimal-scrollbar-arrow-top"
	and arrows[2].textures[1].atlas == "minimal-scrollbar-arrow-bottom")
arrows[1].scripts.OnClick(); arrows[2].scripts.OnClick()
check("the arrows scroll up and down", steps[1] == -1 and steps[2] == 1)
check("arrows shown on an 8 px bar", arrows[1].shown and arrows[2].shown)
track.w = 3
track.hooks.OnSizeChanged()
check("no arrows on a 3 px bar", not arrows[1].shown and not arrows[2].shown)

-- a texture thumb (upcoming steps, /qt lists): the texture only places the art
local bar2 = frame()
bar2.w = 3
local texThumb = bar2:CreateTexture(nil, "ARTWORK")
skin.bar(bar2, texThumb)
check("a texture thumb is made see-through, the art drawn over it", texThumb.color and texThumb.color[4] == 0)
local noStep = bar2.children[1]
check("without a step the arrows are drawn only (no buttons)", noStep.kind == "Frame" and noStep.scripts.OnClick == nil)

-- without the atlases: the same look in plain colours
atlases = false
skin = load()
local track3 = frame(); track3.w = 8
local thumb3 = CreateFrame("Frame", nil, track3)
local arrows3 = skin.bar(track3, thumb3)
local anyAtlas = false
for _, t in ipairs(track3.textures) do anyAtlas = anyAtlas or t.atlas ~= nil end
for _, t in ipairs(thumb3.textures) do anyAtlas = anyAtlas or t.atlas ~= nil end
local gold = false
for _, t in ipairs(thumb3.textures) do
	local c = t.color
	if c and c[1] > 0.8 and c[2] > 0.5 and c[3] < 0.3 then gold = true end
end
check("no atlases: no atlas used, a gold thumb drawn", not anyAtlas and gold)
check("no atlases: grey arrow art", arrows3[1].textures[1].texture ~= nil and arrows3[1].textures[1].desaturated)

-- the native template bar
atlases = true
skin = load()
local native = CreateFrame("Slider")
local templateArt = native:CreateTexture(nil, "ARTWORK")
local nativeThumb = native:CreateTexture(nil, "OVERLAY")
function native:GetThumbTexture() return nativeThumb end
function native:GetName() return nil end
local function button()
	local b = frame("Button")
	local n, p, d, h = region("Texture"), region("Texture"), region("Texture"), region("Texture")
	function b:GetNormalTexture() return n end
	function b:GetPushedTexture() return p end
	function b:GetDisabledTexture() return d end
	function b:GetHighlightTexture() return h end
	return b
end
native.ScrollUpButton, native.ScrollDownButton = button(), button()
skin.native(native)
check("native: the template's own art hidden", templateArt.alpha == 0)
check("native: thumb gold, 8 px wide", nativeThumb.atlas == "minimal-scrollbar-thumb-middle" and nativeThumb.w == 8)
check("native: up / down buttons show the arrows", native.ScrollUpButton:GetNormalTexture().atlas == "minimal-scrollbar-arrow-top"
	and native.ScrollDownButton:GetNormalTexture().atlas == "minimal-scrollbar-arrow-bottom")
local count = #native.textures
skin.native(native)
check("native: skinned once only", #native.textures == count)

-- R106-26: the art copied from the character pane's scrollbar (CharacterStatsPaneScrollBox's bar), read live
local function artTex(name, h)
	local t = region("Texture")
	t.liveAtlas, t.h = name, h
	function t:GetAtlas() return self.liveAtlas end
	function t:GetHeight() return self.h end
	return t
end
local function liveButton(name)
	local b = frame("Button")
	b.Texture = artTex(name)
	b.h = 9
	function b:GetHeight() return self.h end
	return b
end
local charBar = { Track = { Begin = artTex("char-track-top", 5), Middle = artTex("char-track-mid"), End = artTex("char-track-bot", 5),
	Thumb = { Begin = artTex("char-thumb-top", 4), Middle = artTex("char-thumb-mid"), End = artTex("char-thumb-bot", 4) } },
	Back = liveButton("char-arrow-up"), Forward = liveButton("char-arrow-down") }
atlases = true
skin = load() -- before the character pane's bar exists: the minimal-scrollbar atlases
local early = frame(); early.w = 8
local earlyThumb = CreateFrame("Frame", nil, early)
local earlyArrows = skin.bar(early, earlyThumb, function() end)
check("no character pane bar yet: the default atlases", early.textures[1].atlas == "minimal-scrollbar-track-top")
local box = { GetParent = function() return { ScrollBar = charBar } end }
_G.CharacterStatsPaneScrollBox = box
check("the character pane's bar is found", skin.characterBar() == charBar)
check("refresh (login / the pane opening): redrawn", skin.refresh() == true)
check("track: the character pane's art", early.textures[1].atlas == "char-track-top" and early.textures[2].atlas == "char-track-mid"
	and early.textures[3].atlas == "char-track-bot")
check("thumb: the character pane's art", earlyThumb.textures[1].atlas == "char-thumb-top"
	and earlyThumb.textures[2].atlas == "char-thumb-mid" and earlyThumb.textures[3].atlas == "char-thumb-bot")
check("arrows: the character pane's art", earlyArrows[1].textures[1].atlas == "char-arrow-up"
	and earlyArrows[2].textures[1].atlas == "char-arrow-down")
check("its caps' and arrows' heights", early.textures[1].h == 5 and earlyThumb.textures[1].h == 4 and earlyArrows[1].h == 9)
check("the colours' 1 px sides hidden with the game's art", early.textures[4].shown == false and early.textures[5].shown == false)
local later = frame(); later.w = 8
skin.bar(later, CreateFrame("Frame", nil, later))
check("a bar skinned later: the character pane's art at once", later.textures[1].atlas == "char-track-top")
charBar.Back = nil
skin = load()
local partial = frame(); partial.w = 8
skin.bar(partial, CreateFrame("Frame", nil, partial))
check("a piece missing on that bar: the default atlases (all or nothing)", partial.textures[1].atlas == "minimal-scrollbar-track-top")
_G.CharacterStatsPaneScrollBox = nil
print(pass and "PASS" or "FAILED")
