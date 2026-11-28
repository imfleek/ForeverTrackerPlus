-- ForeverTrackerPlus: the level-up banner (3.2, user: "a level up animation in the middle of the screen ... within
-- our Forever artstyle", "top middle of screen"; the idea from Guildy's max-level banner, drawn our own way).
-- At the top middle of the screen, where the battleground resurrect timer window shows (user; the game's first popup,
-- StaticPopup1: its place is read once and copied, the banner is not anchored to it): a dark band that fades out at both ends, closed by two gold hairlines. Our gold
-- diamond (Textures/MarkerDiamond) sits on the upper line with the new level in it and a gold burst behind it; under it
-- "LEVEL 23" in large gold capitals and a cream line: how long the last level took and your time played.
-- The diamond drops in, the burst rings out, the lines grow outward from it, then the texts rise into place. It stays
-- 4 seconds and fades. No sound of its own (the game plays its level-up sound). Never takes the mouse.
-- Option: Statistics > Options > "Level-up banner" (db.levelBanner, on by default). /ftp levelup shows a test one.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local WIDTH, HEIGHT, SEAL = 720, 118, 60
local ENTER, HOLD, FADE = 1.1, 4, 1
local GOLD = { 1, 0.82, 0.3 }
local CREAM = { 0.93, 0.88, 0.76 }

local banner

local function gradient(t, r, g, b, a1, a2)
	t:SetColorTexture(1, 1, 1, 1)
	local ok = t.SetGradient and CreateColor and pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
	if not ok then t:SetColorTexture(r, g, b, math.max(a1, a2) * 0.6) end
end
-- 0..1 between start and finish, fast at first, slow at the end
local function ease(t, start, finish)
	if t <= start then return 0 end
	if t >= finish then return 1 end
	local p = (t - start) / (finish - start)
	return 1 - (1 - p) ^ 3
end

local function place(self, t)
	local seal = ease(t, 0, 0.4)
	self.seal:SetAlpha(seal)
	self.seal:SetScale(1.7 - 0.7 * seal)
	local burst = ease(t, 0.1, 0.9)
	self.burst:SetSize(SEAL * (1 + 3 * burst), SEAL * (1 + 3 * burst))
	self.burst:SetAlpha(0.9 * (1 - burst))
	local lines = ease(t, 0.2, 0.95)
	self.band:SetAlpha(lines)
	for _, l in ipairs(self.lines) do l:SetWidth(math.max(1, l.full * lines)) end
	local title = ease(t, 0.35, 0.95)
	self.title:SetAlpha(title)
	self.title:SetPoint("TOP", self, "TOP", 0, -(SEAL / 2 + 10) - 14 * (1 - title))
	self.sub:SetAlpha(ease(t, 0.55, ENTER))
end

local function onUpdate(self, elapsed)
	self.t = self.t + elapsed
	local t = self.t
	if t >= ENTER + HOLD + FADE then self:Hide() return end
	if t <= ENTER + 0.1 then place(self, t) end
	self:SetAlpha(t < ENTER + HOLD and 1 or 1 - (t - ENTER - HOLD) / FADE)
end

local function build()
	if banner then return banner end
	banner = CreateFrame("Frame", "ForeverTrackerPlusLevelBanner", UIParent)
	banner:SetSize(WIDTH, HEIGHT)
	-- where the battleground resurrect timer window shows: the game's first popup (StaticPopup1), its top read once
	-- (not anchored to it); the game's own place for it (135 below the top) when it cannot be read
	local y = -135
	local popup = rawget(_G, "StaticPopup1")
	local ok, py = pcall(function() return popup:GetTop() end)
	local top = UIParent:GetTop()
	if ok and type(py) == "number" and top then
		local scale = (popup:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
		y = py * scale - top
	end
	banner:SetPoint("TOP", UIParent, "TOP", 0, math.min(y, -20))
	banner:SetFrameStrata("HIGH")
	banner:EnableMouse(false)
	banner:Hide()
	-- the band: dark in the middle, gone at both ends, on a frame under the rest
	banner.band = CreateFrame("Frame", nil, banner)
	banner.band:SetAllPoints()
	local left = banner.band:CreateTexture(nil, "BACKGROUND")
	left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMRIGHT", banner.band, "BOTTOM")
	gradient(left, 0.03, 0.025, 0.02, 0, 0.78)
	local right = banner.band:CreateTexture(nil, "BACKGROUND")
	right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMLEFT", banner.band, "BOTTOM")
	gradient(right, 0.03, 0.025, 0.02, 0.78, 0)
	local content = CreateFrame("Frame", nil, banner)
	content:SetAllPoints()
	content:SetFrameLevel(banner.band:GetFrameLevel() + 1)
	-- the hairlines: the top two start at the diamond's sides, the bottom two at the middle; each grows outward
	banner.lines = {}
	local function line(point, relPoint, x, full, a1, a2)
		local l = content:CreateTexture(nil, "ARTWORK")
		gradient(l, GOLD[1], GOLD[2], GOLD[3], a1, a2)
		l:SetHeight(2)
		l:SetPoint(point, banner, relPoint, x, 0)
		l.full, l.a1, l.a2 = full, a1, a2
		banner.lines[#banner.lines + 1] = l
	end
	local side = SEAL / 2 + 4
	line("RIGHT", "TOP", -side, WIDTH / 2 - side, 0, 1)
	line("LEFT", "TOP", side, WIDTH / 2 - side, 1, 0)
	line("RIGHT", "BOTTOM", 0, WIDTH / 2 - 80, 0, 0.6)
	line("LEFT", "BOTTOM", 0, WIDTH / 2 - 80, 0.6, 0)
	-- the burst behind the diamond, then the diamond with the level
	banner.burst = content:CreateTexture(nil, "BORDER")
	banner.burst:SetTexture(TEX .. "MarkerGlow")
	banner.burst:SetBlendMode("ADD")
	banner.burst:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	banner.burst:SetPoint("CENTER", banner, "TOP")
	banner.seal = CreateFrame("Frame", nil, content)
	banner.seal:SetSize(SEAL, SEAL)
	banner.seal:SetPoint("CENTER", banner, "TOP")
	local glow = banner.seal:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(TEX .. "MarkerGlow")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
	glow:SetSize(SEAL * 1.8, SEAL * 1.8)
	glow:SetPoint("CENTER")
	banner.glow = glow
	local diamond = banner.seal:CreateTexture(nil, "ARTWORK")
	diamond:SetTexture(TEX .. "MarkerDiamond")
	diamond:SetAllPoints()
	banner.level = banner.seal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	banner.level:SetPoint("CENTER", 0, 0)
	local font = GameFontNormalLarge and GameFontNormalLarge:GetFont()
	if font then banner.level:SetFont(font, 20, "OUTLINE") end
	banner.level:SetTextColor(1, 0.95, 0.8)
	-- 3.2: the battleground result shows the winner's banner icon in the diamond instead of a level
	banner.icon = banner.seal:CreateTexture(nil, "OVERLAY")
	banner.icon:SetSize(SEAL * 0.5, SEAL * 0.5)
	banner.icon:SetPoint("CENTER")
	banner.icon:Hide()
	banner.title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	local huge = GameFontNormalHuge and GameFontNormalHuge:GetFont() or font
	if huge then banner.title:SetFont(huge, 38, "") end
	banner.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	banner.title:SetShadowOffset(2, -2)
	banner.title:SetShadowColor(0, 0, 0, 0.9)
	banner.title:SetJustifyH("CENTER")
	banner.sub = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	local large = GameFontHighlightLarge and GameFontHighlightLarge:GetFont() or font
	if large then banner.sub:SetFont(large, 15, "") end
	banner.sub:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
	banner.sub:SetShadowOffset(1, -1)
	banner.sub:SetShadowColor(0, 0, 0, 1)
	banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 0, -6)
	banner.sub:SetJustifyH("CENTER")
	banner:SetScript("OnUpdate", onUpdate)
	return banner
end

-- the banner's colour: gold for a level and a win, red for a loss (3.2)
local function tint(b, c)
	for _, l in ipairs(b.lines) do gradient(l, c[1], c[2], c[3], l.a1, l.a2) end
	b.burst:SetVertexColor(c[1], c[2], c[3], 1)
	if b.glow then b.glow:SetVertexColor(c[1], c[2], c[3], 0.7) end
	b.title:SetTextColor(c[1], c[2], c[3])
end
local function play(b)
	b.t = 0
	place(b, 0)
	b:SetAlpha(1)
	b:Show()
end

-- 3.2 (user): the battleground ended. result: "won", "lost" or "draw"; sub: the line under it; side: the winner
local RED, ICONS = { 1, 0.3, 0.22 }, { Alliance = 132486, Horde = 132485 }
function api.showResultBanner(result, sub, side)
	local b = build()
	tint(b, result == "lost" and RED or result == "draw" and CREAM or GOLD)
	b.level:SetText("")
	b.icon:SetTexture(ICONS[side] or 132485)
	b.icon:SetShown(ICONS[side] ~= nil)
	b.title:SetText(result == "won" and "VICTORY" or result == "lost" and "DEFEAT" or "DRAW")
	b.sub:SetText(sub or "")
	play(b)
end

-- show it for `level`; sub: the line under it (or nil)
function api.showLevelBanner(level, sub)
	local db = ns.db
	if not db or db.levelBanner == false or type(level) ~= "number" then return end
	local b = build()
	tint(b, GOLD)
	b.icon:Hide()
	b.level:SetText(tostring(level))
	b.title:SetText(("LEVEL %d"):format(level))
	b.sub:SetText(sub or "")
	play(b)
end
api.levelBanner = function() return banner end -- (tests)

if api.addSlash then
	api.addSlash("bgbanner", "show the battleground victory banner (a test)", function()
		api.showResultBanner("won", "A test of the victory banner", UnitFactionGroup and UnitFactionGroup("player"))
	end)
	api.addSlash("levelup", "show the level-up banner (a test)", function()
		local level = UnitLevel and UnitLevel("player") or 1
		local was = ns.db and ns.db.levelBanner
		if ns.db then ns.db.levelBanner = nil end
		api.showLevelBanner(level, "A test of the level-up banner")
		if ns.db then ns.db.levelBanner = was end
	end)
end
