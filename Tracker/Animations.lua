-- ForeverTrackerPlus: short animations (3.2, user: "Do 1, 2, 3, 4, 6, and the on/off").
--   1. an objective is done: its line flashes gold; when that finishes the quest, its check pops
--   2. a quest is ready to turn in: a light sweeps over its title
--   3. a quest is accepted: its title and lines slide in and fade in; a quest leaves the log: its title fades out
--   4. a progress bar grows to its new value instead of jumping
--   6. the settings window fades and grows in when it opens; the gold mark under the open tab slides to a new tab
-- 3.2 (user picked more): zone groups slide open and fade shut; a count that goes up ("3/8") bounces; the quest
-- counter pulses red when the log is almost full; the distance arrow turns smoothly and the yards glow gold within
-- 20 yards (Extras.lua); a new rare pulses on its zone header (Rares.lua, with a message in the middle of the screen);
-- a killed boss is struck through on the dungeon card (DungeonPlus.lua); the statistics tiles count up when their
-- page opens (Stats.lua); settings cards fade their rows in when they unfold and turn their arrow (Config.lua); a quest
-- title brightens under the mouse (Own/Rows.lua).
-- One setting turns them all off (db.animations), and each has a switch of its own (db.animOff[kind]): both on the
-- Animations page under GENERAL (Config.lua), which lists api.animKinds. A new animation gets a kind in that list.
-- Nothing new starts in combat, and every effect is less than a second long.
--
-- The tracker's rows are pooled and drawn again on every quest log change (Own/Frame.lua rebuild), so an effect never
-- keeps a row: it is kept by a key (the quest, or quest and objective), and every rebuild tells this file which row now
-- shows that key (animBegin, animTitle, animLine, animBar, animEnd). One hidden frame runs the effects (OnUpdate only
-- while one is running).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local GLOW = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\MarkerGlow"
local GOLD = { 1, 0.82, 0.25 }

-- 3.2 (user): every animation has its own switch on the Animations page; the list is drawn from this table, so a new
-- animation is a new row here and an on("kind") where it starts
api.animKinds = {
	{ area = "Quest tracker" },
	{ key = "flash", label = "Objective done flash", sub = "a finished objective's line flashes gold" },
	{ key = "turnin", label = "Ready to turn in", sub = "a light sweeps over the title and the check pops" },
	{ key = "slide", label = "New quests slide in", sub = "a quest you accept slides and fades in" },
	{ key = "fadeout", label = "Removed quests fade out", sub = "a quest that leaves the log fades away" },
	{ key = "glide", label = "Quests glide to a new place", sub = "when the order changes" },
	{ key = "bar", label = "Progress bars grow", sub = "the bar grows to its new value, its number bounces" },
	{ key = "count", label = "Counts glow when they go up", sub = "\"3/8\" to \"4/8\" glows gold for a moment" },
	{ key = "counter", label = "Quest counter pulse", sub = "the quest count pulses when the log is almost full" },
	{ key = "zone", label = "Zone groups slide", sub = "zone groups slide open and fade shut" },
	{ key = "roll", label = "Headers roll", sub = "the tracker rolls up and down when you fold a header" },
	{ key = "scroll", label = "Smooth scrolling", sub = "the mouse wheel glides the list" },
	{ key = "hover", label = "Title light under the mouse" },
	{ key = "sparkle", label = "Item ready sparkle", sub = "a quest item sparkles when its cooldown ends" },
	{ key = "questaction", label = "Big quest item glow", sub = "the light behind the big quest item button pulses" },
	{ key = "rare", label = "New rare pulse", sub = "the rare's tag pulses on its zone header" },
	{ key = "abandon", label = "Abandoned quests shake", sub = "a quest you abandon shakes before it fades" },
	{ key = "failflash", label = "Failed quest flash", sub = "the screen's edges flash red when a quest fails" },
	{ key = "repfloat", label = "Reputation gains float up", sub = "\"+250\" rises from the reputation bar" },
	{ area = "Arrow and map" },
	{ key = "arrow", label = "Smooth distance arrow", sub = "the arrow turns smoothly, not in steps" },
	{ key = "close", label = "Close by glow", sub = "the yards glow gold within 20 yards" },
	{ key = "ticker", label = "Yards count down smoothly", sub = "the yards number counts, it does not jump" },
	{ key = "arrive", label = "World marker arrival", sub = "a gold burst when you reach the marker" },
	{ key = "corpse", label = "Corpse close glow", sub = "the corpse arrow glows when you are close enough to come back" },
	{ key = "layerswap", label = "LayerSwap ready glow", sub = "the LayerSwap icon glows when a swap you waited for can be asked" },
	{ area = "RestedXP" },
	{ key = "steps", label = "Steps slide up", sub = "the step list slides up when a step is done" },
	{ key = "rxparrow", label = "Arrow pulse", sub = "the guide arrow pulses when it points to a new place" },
	{ key = "skip", label = "Done steps swipe away", sub = "a step you mark done moves right and fades" },
	{ key = "sweep", label = "Current step light", sub = "a gold light goes down the new current step" },
	{ area = "Dungeons" },
	{ key = "strike", label = "Killed boss strike-through", sub = "on the dungeon card's \"Next:\" line" },
	{ key = "bossrows", label = "Bosses drop in", sub = "the boss portraits drop in when the card opens" },
	{ key = "bosskill", label = "Killed boss check", sub = "the portrait turns over and a gold check shows" },
	{ key = "cleared", label = "Cleared stamp", sub = "after the last boss: the card flashes and says CLEARED" },
	{ key = "deaths", label = "Death shake", sub = "the deaths number shakes and shows red" },
	{ key = "party", label = "Party bump", sub = "the players number bumps when someone joins or leaves" },
	{ key = "cap", label = "Instance limit shake", sub = "the instance line shakes when you reach the hourly limit" },
	{ key = "runlight", label = "Run light", sub = "a red dot pulses on the card while the run goes on" },
	{ key = "newbest", label = "New best time", sub = "\"NEW BEST\" flashes when a boss dies faster than ever" },
	{ key = "lootsparkle", label = "Loot you want sparkle", sub = "the \"Loot you want\" line sparkles once when you enter" },
	{ key = "summary", label = "Run summary counts up", sub = "gold and experience count up from the last card's numbers" },
	{ area = "Battlegrounds" },
	{ key = "bgcapture", label = "Base captured flash", sub = "a base bar flashes in its side's colour, then fades" },
	{ key = "bgpulse", label = "Last 10 seconds pulse", sub = "a base bar pulses red in its last 10 seconds" },
	{ key = "bgswap", label = "Win bar flips", sub = "the win bar flips over when the winning side changes" },
	{ key = "bgcarrier", label = "Flag carrier low health", sub = "the carrier's line shakes when their health is low" },
	{ key = "bgdrop", label = "Flag dropped ping", sub = "a dropped flag's line pops once" },
	{ key = "bgqueue", label = "Queue ready bounce", sub = "the \"Enter\" bar bounces, and pulses red in its last 15 seconds" },
	{ key = "bgresult", label = "Victory or defeat banner", sub = "a gold or red banner when the battleground ends" },
	{ area = "Statistics" },
	{ key = "countup", label = "Tiles count up", sub = "the numbers count up when the page opens" },
	{ area = "Settings window" },
	{ key = "window", label = "Window opens and closes", sub = "the window fades in and out" },
	{ key = "tilt", label = "Section icons tilt", sub = "a section's icon tilts under the mouse" },
	{ key = "newsglow", label = "What's new glow", sub = "the What's new button glows until you read the notes" },
	{ key = "tab", label = "Tab mark slides", sub = "the gold mark slides to the tab you pick" },
	{ key = "cards", label = "Cards unfold", sub = "rows fade in and the arrow turns" },
	{ key = "knob", label = "Switch knobs slide" },
	{ key = "slider", label = "Slider glow", sub = "the value glows and bounces when you let go" },
	{ key = "search", label = "Search glow", sub = "settings that match your search flash once" },
	{ key = "saved", label = "Saved check", sub = "a small check shows next to a setting you change" },
	{ key = "reset", label = "Defaults slide back", sub = "after Defaults, sliders slide back to their default" },
	{ key = "dropdown", label = "Dropdowns unfold", sub = "a dropdown list opens downward" },
	{ key = "rowhover", label = "Row light under the mouse" },
}

-- kind: one of api.animKinds (nil: any animation)
local function on(kind)
	local db = ns.db
	if not db or db.animations == false then return false end
	if kind and type(db.animOff) == "table" and db.animOff[kind] then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	return true
end
api.animOn = on

local function now() return GetTime and GetTime() or 0 end
local function easeOut(t) return 1 - (1 - t) ^ 3 end

---------------------------------------------------------------------------------------------------------------------
-- The runner
---------------------------------------------------------------------------------------------------------------------
local effects = {} -- key -> { start, dur, apply(e, p), finish(e) }
local driver = CreateFrame("Frame")
driver:Hide()
local function finish(key)
	local e = effects[key]
	if not e then return end
	effects[key] = nil
	if e.finish then pcall(e.finish, e) end
end
local function step()
	local t, any = now(), false
	for key, e in pairs(effects) do
		local p = e.dur > 0 and math.min((t - e.start) / e.dur, 1) or 1
		local ok = pcall(e.apply, e, p)
		if p >= 1 or not ok then finish(key) else any = true end
	end
	if not any then driver:Hide() end
end
driver:SetScript("OnUpdate", step)
local function start(key, e)
	finish(key)
	e.start = now()
	effects[key] = e
	pcall(e.apply, e, 0) -- the first look now, not one frame later
	driver:Show()
	return e
end
api.animStep = step -- (tests)
api.animEffects = function() return effects end -- (tests)

-- textures we draw with, reused per parent
local pool = {}
local function texture(parent, layer)
	for _, t in ipairs(pool) do
		if t.free and t:GetParent() == parent then t.free = false; return t end
	end
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(GLOW)
	t:SetBlendMode("ADD")
	pool[#pool + 1] = t
	return t
end
local function release(t) if t then t:Hide(); t:ClearAllPoints(); t.free = true end end

---------------------------------------------------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------------------------------------------------
-- 1. a gold flash behind a line: up fast, out slow
local function flash(key, fs)
	local t = texture(fs:GetParent(), "BACKGROUND")
	t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	return start(key, { dur = 0.7, fs = fs, tex = t,
		apply = function(e, p)
			local f = e.fs
			if not (f and f:IsShown()) then e.tex:Hide() return end
			e.tex:ClearAllPoints()
			e.tex:SetPoint("TOPLEFT", f, "TOPLEFT", -8, 4)
			e.tex:SetSize((f:GetStringWidth() or 100) + 24, (f:GetStringHeight() or 12) + 8)
			e.tex:SetAlpha(0.75 * (p < 0.2 and p / 0.2 or 1 - (p - 0.2) / 0.8))
			e.tex:Show()
		end,
		finish = function(e) release(e.tex) end })
end

-- 1. the check grows and settles back, with a soft gold burst behind it
local function pop(key, fs)
	local t = texture(fs:GetParent(), "OVERLAY")
	t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	return start(key, { dur = 0.45, fs = fs, tex = t,
		apply = function(e, p)
			local w = e.fs and e.fs.qtsCheck
			if not (w and w:IsShown()) then e.tex:Hide() return end
			if not e.anchor then e.anchor = { w:GetPoint(1) } end
			local s = p < 0.3 and 1 + 0.6 * (p / 0.3) or 1 + 0.6 * (1 - easeOut((p - 0.3) / 0.7))
			local a = e.anchor
			w:SetScale(s)
			if a[1] then w:ClearAllPoints(); w:SetPoint(a[1], a[2], a[3], (a[4] or 0) / s, (a[5] or 0) / s) end
			local size = (w:GetWidth() or 12) * (1 + 2 * p)
			e.tex:ClearAllPoints()
			e.tex:SetPoint("CENTER", w, "CENTER")
			e.tex:SetSize(size * s, size * s)
			e.tex:SetAlpha(0.8 * (1 - p))
			e.tex:Show()
		end,
		finish = function(e)
			local w = e.fs and e.fs.qtsCheck
			if w then
				w:SetScale(1)
				local a = e.anchor
				if a and a[1] then w:ClearAllPoints(); w:SetPoint(a[1], a[2], a[3], a[4], a[5]) end
			end
			release(e.tex)
		end })
end

-- 2. a band of light sweeps over the title, left to right
local function shine(key, fs)
	local t = texture(fs:GetParent(), "OVERLAY")
	t:SetVertexColor(1, 0.95, 0.75, 1)
	return start(key, { dur = 0.9, fs = fs, tex = t,
		apply = function(e, p)
			local f = e.fs
			if not (f and f:IsShown()) then e.tex:Hide() return end
			local w, h = f:GetStringWidth() or 100, (f:GetStringHeight() or 12)
			local band = math.max(h * 2.2, 26)
			local x = -band + (w + band) * easeOut(p)
			e.tex:ClearAllPoints()
			e.tex:SetPoint("LEFT", f, "TOPLEFT", x, -h / 2)
			e.tex:SetSize(band, h + 10)
			e.tex:SetAlpha(0.9 * math.sin(math.pi * p))
			e.tex:Show()
		end,
		finish = function(e) release(e.tex) end })
end

-- 3. the quest's rows slide in from the left and fade in
local SLIDE = 16
local function placeRow(fs, a, dx, dy)
	if not fs.qtsAnimPoint then fs.qtsAnimPoint = { fs:GetPoint(1) } end
	local pt = fs.qtsAnimPoint
	if a then fs:SetAlpha(a) end
	if pt[1] then fs:SetPoint(pt[1], pt[2], pt[3], (pt[4] or 0) - (dx or 0), (pt[5] or 0) + (dy or 0)) end
end
-- 3.2 (user: "quests glide to their new place when the order changes"): a quest drawn lower or higher than the last
-- rebuild drew it starts where it was and glides to its new place (its title and lines together)
local function glide(key, dy)
	return start(key, { dur = 0.3, rows = {}, dy = dy,
		apply = function(e, p)
			for _, fs in ipairs(e.rows) do placeRow(fs, nil, 0, e.dy * (1 - easeOut(p))) end
		end,
		finish = function(e)
			for _, fs in ipairs(e.rows) do placeRow(fs, nil, 0, 0); fs.qtsAnimPoint = nil end
		end })
end
local function slideIn(key)
	return start(key, { dur = 0.4, rows = {},
		apply = function(e, p)
			local a = easeOut(p)
			for _, fs in ipairs(e.rows) do placeRow(fs, a, SLIDE * (1 - a)) end
		end,
		finish = function(e)
			for _, fs in ipairs(e.rows) do placeRow(fs, 1, 0); fs.qtsAnimPoint = nil end
		end })
end

-- 3. a quest left the log: a copy of its title fades out, drifting right
local ghosts = {}
-- what a title row shows now (the row is reused by the next rebuild)
local function snapshot(fs)
	local font, size, flags = fs:GetFont()
	return { parent = fs:GetParent(), font = font, size = size, flags = flags, text = fs:GetText() or "",
		color = { fs:GetTextColor() }, width = fs:GetWidth() or 200, pt = { fs:GetPoint(1) } }
end
local function ghost(snap, shaken)
	if snap and snap.GetFont then snap = snapshot(snap) end
	if not (snap and snap.pt and snap.pt[1]) then return end
	local parent = snap.parent
	local g
	for _, x in ipairs(ghosts) do if x.free and x:GetParent() == parent then g = x break end end
	if not g then g = parent:CreateFontString(nil, "OVERLAY"); ghosts[#ghosts + 1] = g end
	g.free = false
	if snap.font then g:SetFont(snap.font, snap.size, snap.flags) end
	g:SetJustifyH("LEFT")
	g:SetWidth(snap.width)
	g:SetText(snap.text)
	g:SetTextColor(snap.color[1] or 1, snap.color[2] or 1, snap.color[3] or 1, snap.color[4] or 1)
	g:SetShadowColor(0, 0, 0, 1)
	g:SetShadowOffset(1, -1)
	local pt = snap.pt
	g:ClearAllPoints()
	g:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
	g:Show()
	-- 3.2 (user): an abandoned quest shakes red first (the first 60 %), then fades out as the others
	local dur = shaken and 1 or 0.45
	if shaken then g:SetTextColor(1, 0.35, 0.3, 1) end
	start("ghost:" .. tostring(g), { dur = dur, g = g, pt = pt,
		apply = function(e, p)
			if shaken and p < 0.6 then
				local q = p / 0.6
				e.g:SetAlpha(1)
				e.g:SetPoint(e.pt[1], e.pt[2], e.pt[3], (e.pt[4] or 0) + math.sin(q * math.pi * 6) * 5 * (1 - q), e.pt[5] or 0)
				return
			end
			if shaken then p = (p - 0.6) / 0.4 end
			e.g:SetAlpha(1 - easeOut(p))
			e.g:SetPoint(e.pt[1], e.pt[2], e.pt[3], (e.pt[4] or 0) + 20 * easeOut(p), e.pt[5] or 0)
		end,
		finish = function(e) e.g:Hide(); e.g.free = true end })
end

-- 4. a bar's fill grows from the old value to the new one
local function barKey(id, index) return "bar:" .. tostring(id) .. ":" .. tostring(index) end
local barShown = {} -- key -> the fraction shown last

---------------------------------------------------------------------------------------------------------------------
-- What the tracker's rebuild tells us (Own/Frame.lua)
---------------------------------------------------------------------------------------------------------------------
local seen, current = {}, {} -- quest id -> { complete, done = { [index] = bool } }, from the last and this rebuild
local titles = {} -- quest id -> the title row of the last rebuild
local accepted = {} -- quest id -> when it was accepted
local primed = false -- after the first rebuild: nothing animates on the first one (login, reload)
local before = {} -- quest id -> snapshot of its title as the last rebuild drew it
local zoneFolded = {} -- zone -> folded at the last rebuild

function api.animBegin()
	current = {}
	before = {}
	for k, fs in pairs(titles) do
		if fs:IsShown() then before[k] = snapshot(fs) end
		titles[k] = nil
	end
	for _, e in pairs(effects) do
		if e.rows then
			for _, fs in ipairs(e.rows) do fs.qtsAnimPoint = nil end
			e.rows = {}
		end
		if e.fs and not e.keepFs then e.fs = nil end
	end
end

-- a rebuild drew row `fs` for key: a running effect follows the new row
local function follow(key, fs)
	local e = effects[key]
	if e and e.fs == nil then e.fs = fs end
end

function api.animTitle(q, fs)
	if type(q) ~= "table" or not q.id or not fs then return end
	local id = q.id
	titles[id] = fs
	current[id] = { complete = q.complete and true or false, failed = q.failed and true or false, done = {} }
	follow("shine:" .. id, fs)
	follow("pop:" .. id, fs)
	local slide = effects["slide:" .. id] or effects["glide:" .. id]
	if slide then
		slide.rows[#slide.rows + 1] = fs
		pcall(slide.apply, slide, math.min((now() - slide.start) / slide.dur, 1))
	end
	if not on() or not primed then return end
	local was = seen[id]
	-- 3.2 (user): failed since the last rebuild: the screen's edges flash red
	if was and current[id].failed and not was.failed and api.animFailFlash then api.animFailFlash() end
	-- moved since the last rebuild: glide from the old place (not while it slides in)
	local old = before[id]
	local _, _, _, _, newY = fs:GetPoint(1)
	if on("glide") and was and old and old.pt[5] and newY and not effects["slide:" .. id] and not effects["glide:" .. id] then
		local dy = old.pt[5] - newY
		if math.abs(dy) > 2 and math.abs(dy) < 600 then
			local g = glide("glide:" .. id, dy)
			g.rows[1] = fs
			g.apply(g, 0)
		end
	end
	if not was and accepted[id] and now() - accepted[id] < 10 and on("slide") then
		accepted[id] = nil
		slide = slideIn("slide:" .. id)
		slide.rows[1] = fs
		placeRow(fs, 0, SLIDE)
	elseif was and current[id].complete and not was.complete and on("turnin") then
		shine("shine:" .. id, fs)
		pop("pop:" .. id, fs)
	end
end

local counts = {} -- "id:index" -> the count it showed last ("3/8" -> 3)
function api.animLine(q, index, done, fs, text)
	if type(q) ~= "table" or not q.id or not fs then return end
	local id = q.id
	local cur = current[id]
	if cur then cur.done[index] = done and true or false end
	local key = "flash:" .. id .. ":" .. index
	follow(key, fs)
	local slide = effects["slide:" .. id] or effects["glide:" .. id]
	if slide then
		slide.rows[#slide.rows + 1] = fs
		pcall(slide.apply, slide, math.min((now() - slide.start) / slide.dur, 1))
	end
	if not on() or not primed then return end
	local was = seen[id]
	if done and was and was.done[index] == false and on("flash") then flash(key, fs) end
	-- the count went up (not done yet): the line glows gold for a moment
	local have = type(text) == "string" and tonumber(text:match("(%d+)%s*/%s*%d+"))
	local ck = id .. ":" .. index
	local old = counts[ck]
	counts[ck] = have
	if have and old and have > old and not done and was and not fs.qtsHasBar then api.animTint("tint:" .. ck, fs) end
end

-- the bar was just drawn at have/need: start it from the value shown last
function api.animBar(id, index, bar, have, need)
	if not (bar and bar.fill and need and need > 0) then return end
	local key = barKey(id, index)
	local frac = math.min(math.max(have / need, 0), 1)
	local old = barShown[key]
	barShown[key] = frac
	local e = effects[key]
	local full = frac > 0 and (bar.fill:GetWidth() or 0) / frac or 0
	if e then
		-- a rebuild during the growth: the new bar, the new end
		e.bar, e.to, e.full = bar, frac, full > 0 and full or e.full
		pcall(e.apply, e, math.min((now() - e.start) / e.dur, 1))
		return
	end
	if not (on("bar") and primed and old and frac > old and full > 0) then return end
	if bar.text then api.animBounce("bounce:" .. key, bar.text) end
	start(key, { dur = 0.5, bar = bar, from = old, to = frac, full = full,
		apply = function(e2, p)
			local v = e2.from + (e2.to - e2.from) * easeOut(p)
			e2.bar.fill:SetWidth(math.max(e2.full * v, 0.01))
			e2.bar.fill:SetShown(v > 0)
		end,
		finish = function(e2)
			e2.bar.fill:SetWidth(math.max(e2.full * e2.to, 0.01))
			e2.bar.fill:SetShown(e2.to > 0)
		end })
end

function api.animEnd()
	seen = current
	primed = true
	-- effects whose quest is not drawn now stop
	for key, e in pairs(effects) do
		if e.fs == nil and (key:find("^flash:") or key:find("^shine:") or key:find("^pop:")) then
			if e.tex then e.tex:Hide() end
		end
	end
end

-- 3.2 (user): the quest you are abandoning (the game asks for it with SetAbandonQuest before AbandonQuest)
local abandoning
local function noteAbandon()
	local id
	if C_QuestLog and C_QuestLog.GetAbandonQuest then
		local ok, v = pcall(C_QuestLog.GetAbandonQuest)
		if ok and type(v) == "number" and v > 0 then id = v end
	end
	if id then abandoning = { id = id, at = now() } end
end
if hooksecurefunc then
	if C_QuestLog and C_QuestLog.SetAbandonQuest then pcall(hooksecurefunc, C_QuestLog, "SetAbandonQuest", noteAbandon) end
	if rawget(_G, "SetAbandonQuest") then pcall(hooksecurefunc, "SetAbandonQuest", noteAbandon) end
end
api.animAbandoning = function() return abandoning end -- (tests)
-- events: a new quest slides in when it is drawn; a quest that leaves the log fades out from where it was
local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:SetScript("OnEvent", function(_, event, a, b)
	-- QUEST_ACCEPTED: (questID) on newer clients, (logIndex, questID) on older ones
	local id = event == "QUEST_ACCEPTED" and (type(b) == "number" and b or a) or a
	if type(id) ~= "number" then return end
	if event == "QUEST_ACCEPTED" then
		accepted[id] = now()
	else
		local fs = titles[id]
		titles[id] = nil
		local shaken = abandoning and abandoning.id == id and now() - abandoning.at < 10 and on("abandon")
		if shaken then abandoning = nil end
		if fs and fs:IsShown() and primed and (shaken or on("fadeout")) then pcall(ghost, fs, shaken) end
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- 6. The settings window (Config.lua)
---------------------------------------------------------------------------------------------------------------------
-- fades in from 0 and grows from 96 %
function api.animWindowOpen(f)
	if not (f and on("window")) then return end
	if not f.qtsOpenAnim then
		local g = f:CreateAnimationGroup()
		local a = g:CreateAnimation("Alpha")
		a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.18); a:SetSmoothing("OUT")
		local s = g:CreateAnimation("Scale")
		if s.SetScaleFrom then s:SetScaleFrom(0.96, 0.96); s:SetScaleTo(1, 1) else s:SetScale(1 / 0.96, 1 / 0.96) end
		s:SetDuration(0.18); s:SetSmoothing("OUT")
		if s.SetOrigin then s:SetOrigin("CENTER", 0, 0) end
		f.qtsOpenAnim = g
	end
	f.qtsClosing = nil
	if f.qtsCloseAnim then f.qtsCloseAnim:Stop() end
	f.qtsOpenAnim:Stop()
	f.qtsOpenAnim:Play()
end

-- the mark under the open tab glides from the last tab to this one (x and width)
function api.animTabMark(mark, x, w)
	if not mark then return end
	local from = mark.qtsAt
	mark.qtsAt = { x, w }
	if not (from and on("tab")) or (from[1] == x and from[2] == w) then
		finish("tabmark")
		mark:SetPoint("BOTTOMLEFT", mark:GetParent(), "BOTTOMLEFT", x, -6)
		mark:SetWidth(w)
		return
	end
	start("tabmark", { dur = 0.22, from = from, to = { x, w },
		apply = function(e, p)
			local v = easeOut(p)
			mark:SetPoint("BOTTOMLEFT", mark:GetParent(), "BOTTOMLEFT", e.from[1] + (e.to[1] - e.from[1]) * v, -6)
			mark:SetWidth(math.max(e.from[2] + (e.to[2] - e.from[2]) * v, 1))
		end,
		finish = function(e)
			mark:SetPoint("BOTTOMLEFT", mark:GetParent(), "BOTTOMLEFT", e.to[1], -6)
			mark:SetWidth(e.to[2])
		end })
end

---------------------------------------------------------------------------------------------------------------------
-- More effects (3.2, the second set)
---------------------------------------------------------------------------------------------------------------------
-- text grows and settles back (SetTextScale; a client without it: nothing)
function api.animBounce(key, fs, big)
	if not (fs and fs.SetTextScale and on()) then return end
	big = big or 0.35
	start(key, { dur = 0.35, fs = fs, keepFs = true,
		apply = function(e, p) e.fs:SetTextScale(1 + big * math.sin(math.pi * p)) end,
		finish = function(e) e.fs:SetTextScale(1) end })
end

-- a line glows gold for a moment (its count went up)
function api.animTint(key, fs)
	if not (fs and on("count")) then return end
	local t = texture(fs:GetParent(), "BACKGROUND")
	t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	start(key, { dur = 0.5, fs = fs, tex = t,
		apply = function(e, p)
			local f = e.fs
			if not (f and f:IsShown()) then e.tex:Hide() return end
			e.tex:ClearAllPoints()
			e.tex:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 3)
			e.tex:SetSize((f:GetStringWidth() or 100) + 16, (f:GetStringHeight() or 12) + 6)
			e.tex:SetAlpha(0.45 * math.sin(math.pi * p))
			e.tex:Show()
		end,
		finish = function(e) release(e.tex) end })
end

-- the quest counter on the Quests header: a quest added while the log is almost full pulses it red, twice
local lastCount
function api.animCount(fs, count, max)
	if type(count) ~= "number" or type(max) ~= "number" then return end
	local old = lastCount
	lastCount = count
	if not (fs and old and count > old and count >= math.floor(max * 37 / 40 + 0.5) and on("counter")) then return end
	local t = texture(fs:GetParent(), "BACKGROUND")
	t:SetVertexColor(1, 0.15, 0.1, 1)
	start("count", { dur = 1.0, fs = fs, keepFs = true, tex = t,
		apply = function(e, p)
			local wave = math.abs(math.sin(2 * math.pi * p)) -- two beats
			if e.fs.SetTextScale then e.fs:SetTextScale(1 + 0.3 * wave) end
			local w = (e.fs:GetStringWidth() or 30) + 22
			e.tex:ClearAllPoints()
			e.tex:SetPoint("CENTER", e.fs, "CENTER")
			e.tex:SetSize(w, w * 0.8)
			e.tex:SetAlpha(0.7 * wave)
			e.tex:Show()
		end,
		finish = function(e)
			if e.fs.SetTextScale then e.fs:SetTextScale(1) end
			release(e.tex)
		end })
end

-- 1. a zone group opens: its quests slide in; it folds: its titles fade out from where they were
function api.animZone(zone, folded, quests)
	if type(zone) ~= "string" then return end
	local was = zoneFolded[zone]
	zoneFolded[zone] = folded and true or false
	if not (primed and on("zone")) or was == nil or was == (folded and true or false) then return end
	for _, q in ipairs(quests or {}) do
		if type(q) == "table" and q.id then
			if folded then
				if before[q.id] then pcall(ghost, before[q.id]) end
			else
				accepted[q.id] = now()
				seen[q.id] = nil
			end
		end
	end
end

-- 4. the distance arrow turns toward its new angle instead of jumping: the angle to draw this frame
function api.animArrowAngle(current, target, dt)
	if not (current and on("arrow")) then return target end
	local d = (target - current + math.pi) % (2 * math.pi) - math.pi
	return current + d * math.min(1, (dt or 0.1) * 12)
end

-- 6. a rare's tag on its zone header pulses three times (an Alpha animation on its frame)
function api.animPulse(frame)
	if not (frame and frame.CreateAnimationGroup and on("rare")) then return end
	if not frame.qtsPulse then
		local g = frame:CreateAnimationGroup()
		local a = g:CreateAnimation("Alpha")
		a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.25); a:SetSmoothing("IN_OUT")
		local b = g:CreateAnimation("Alpha")
		b:SetFromAlpha(0.25); b:SetToAlpha(1); b:SetDuration(0.25); b:SetSmoothing("IN_OUT")
		if b.SetStartDelay then b:SetStartDelay(0.25) end
		if b.SetOrder then a:SetOrder(1); b:SetOrder(2) end
		if g.SetLooping then g:SetLooping("REPEAT") end
		g:SetScript("OnLoop", function(self)
			self.loops = (self.loops or 0) + 1
			if self.loops >= 3 then self:Stop(); self.loops = 0 end
		end)
		frame.qtsPulse = g
	end
	frame.qtsPulse.loops = 0
	frame.qtsPulse:Stop()
	frame.qtsPulse:Play()
end

-- 7. a red line draws through a killed boss's name, left to right
function api.animStrike(b)
	if not (b and b.text and on("strike")) then return end
	if not b.qtsStrike then
		b.qtsStrike = b:CreateTexture(nil, "OVERLAY", nil, 7)
		b.qtsStrike:SetColorTexture(1, 0.25, 0.2, 0.95)
		b.qtsStrike:SetHeight(2)
	end
	local line = b.qtsStrike
	start("strike:" .. tostring(b), { dur = 0.5, b = b,
		apply = function(e, p)
			local w = math.min(e.b.text:GetStringWidth() or 60, e.b:GetWidth() or 200)
			line:ClearAllPoints()
			line:SetPoint("LEFT", e.b.text, "LEFT", 0, 0)
			line:SetWidth(math.max(w * easeOut(p), 1))
			line:Show()
		end,
		finish = function(e) end })
end
function api.animStrikeClear(b) if b and b.qtsStrike then b.qtsStrike:Hide() end end

-- 9. a statistic counts up from 0: every number in the text (not inside |T..|t, |A..|a or colour codes) grows
local function scaledText(text, p)
	local out, pos = {}, 1
	while pos <= #text do
		local s, e = text:find("|[TA].-|[ta]", pos)
		local c1, c2 = text:find("|c%x%x%x%x%x%x%x%x", pos)
		if c1 and (not s or c1 < s) then s, e = c1, c2 end
		local plain = text:sub(pos, (s or #text + 1) - 1)
		out[#out + 1] = plain:gsub("%d[%d,]*", function(num)
			local v = tonumber((num:gsub(",", "")))
			if not v then return num end
			local n = math.floor(v * p + 0.5)
			if num:find(",", 1, true) and BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
			return tostring(n)
		end)
		if not s then break end
		out[#out + 1] = text:sub(s, e)
		pos = e + 1
	end
	return table.concat(out)
end
api.animScaledText = scaledText -- (tests)
function api.animCountUp(fs, text, startNew)
	if not (fs and type(text) == "string") then return end
	local key = "countup:" .. tostring(fs)
	local e = effects[key]
	if e then e.text = text; pcall(e.apply, e, math.min((now() - e.start) / e.dur, 1)) return end
	if not (startNew and on("countup")) then return end
	start(key, { dur = 0.7, fs = fs, keepFs = true, text = text,
		apply = function(e2, p) e2.fs:SetText(scaledText(e2.text, easeOut(p))) end,
		finish = function(e2) e2.fs:SetText(e2.text) end })
end

-- 10. settings: a card's rows fade in as it unfolds; its arrow turns
function api.animFadeIn(key, frames)
	if not (frames and #frames > 0 and on("cards")) then return end
	start(key, { dur = 0.25, list = frames,
		apply = function(e, p) for _, f in ipairs(e.list) do f:SetAlpha(easeOut(p)) end end,
		finish = function(e) for _, f in ipairs(e.list) do f:SetAlpha(1) end end })
end
function api.animRotate(tex, to)
	if not (tex and tex.SetRotation) then return end
	local from = tex.qtsAngle
	tex.qtsAngle = to
	local key = "rotate:" .. tostring(tex)
	if not (from and from ~= to and on("cards")) then finish(key); pcall(tex.SetRotation, tex, to) return end
	start(key, { dur = 0.18, from = from, to = to,
		apply = function(e, p) pcall(tex.SetRotation, tex, e.from + (e.to - e.from) * easeOut(p)) end,
		finish = function(e) pcall(tex.SetRotation, tex, e.to) end })
end

-- 11. a quest title brightens under the mouse: a soft light over it fades in, and out on leave
function api.animHover(b, fs, inside)
	if not (b and fs) then return end
	if not b.qtsHover then
		b.qtsHover = b:CreateTexture(nil, "OVERLAY")
		b.qtsHover:SetTexture(GLOW)
		b.qtsHover:SetBlendMode("ADD")
		b.qtsHover:SetVertexColor(1, 0.9, 0.6, 1)
		b.qtsHover:SetAlpha(0)
	end
	local t = b.qtsHover
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", fs, "TOPLEFT", -6, 3)
	t:SetSize((fs:GetStringWidth() or 100) + 16, math.min(fs:GetStringHeight() or 12, 16) + 6)
	local key = "hover:" .. tostring(b)
	if not on("hover") then finish(key); t:SetAlpha(0) return end
	local from = t:GetAlpha() or 0
	local to = inside and 0.35 or 0
	t:Show()
	start(key, { dur = 0.15, from = from, to = to,
		apply = function(e, p) t:SetAlpha(e.from + (e.to - e.from) * p) end,
		finish = function(e) t:SetAlpha(e.to) end })
end

---------------------------------------------------------------------------------------------------------------------
-- The third set (3.2, user: 3, 4, 5, 6, 7, 10, 11, 12, 13)
---------------------------------------------------------------------------------------------------------------------
-- 3. a quest item's cooldown ended: a gold sparkle over its button (Own/Rows.lua; only after a real cooldown)
function api.animSparkle(button)
	if not (button and on("sparkle")) then return end
	if not button.qtsSparkle then
		local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetVertexColor(1, 0.9, 0.5, 1)
		t:SetPoint("CENTER")
		t:SetAlpha(0)
		button.qtsSparkle = t
	end
	local t = button.qtsSparkle
	local size = (button:GetWidth() or 26)
	start("sparkle:" .. tostring(button), { dur = 0.55,
		apply = function(e, p)
			local s = size * (0.8 + 1.4 * easeOut(p))
			t:SetSize(s, s)
			t:SetAlpha(math.sin(math.pi * p))
			t:Show()
		end,
		finish = function() t:SetAlpha(0) end })
end

-- 5. the tracker list scrolls smoothly: returns the offset to show this frame, gliding to `target`
function api.animScrollStep(current, target, elapsed)
	if not on("scroll") then return target end
	local d = target - current
	if math.abs(d) < 0.5 then return target end
	return current + d * math.min(1, (elapsed or 0.016) * 14)
end

-- 6. a part of the tracker rolls up (down = false) or down (down = true) from its top edge; done() after a roll up
function api.animRoll(frames, down, done)
	local list = {}
	for _, f in ipairs(frames or {}) do if f and f.CreateAnimationGroup and f:IsShown() then list[#list + 1] = f end end
	if #list == 0 or not on("roll") then if done then done() end return end
	local called = false
	for i, f in ipairs(list) do
		local g = f.qtsRoll
		if not g then
			g = f:CreateAnimationGroup()
			g.scale = g:CreateAnimation("Scale")
			g.alpha = g:CreateAnimation("Alpha")
			if g.scale.SetOrigin then g.scale:SetOrigin("TOP", 0, 0) end
			f.qtsRoll = g
		end
		g:Stop()
		local from, to = down and 0.05 or 1, down and 1 or 0.05
		if g.scale.SetScaleFrom then g.scale:SetScaleFrom(1, from); g.scale:SetScaleTo(1, to)
		elseif g.scale.SetFromScale then g.scale:SetFromScale(1, from); g.scale:SetToScale(1, to) end
		g.scale:SetDuration(0.2); g.scale:SetSmoothing(down and "OUT" or "IN")
		g.alpha:SetFromAlpha(down and 0 or 1); g.alpha:SetToAlpha(down and 1 or 0); g.alpha:SetDuration(0.2)
		g:SetScript("OnFinished", (i == 1 and done) and function()
			if not called then called = true; done() end
		end or nil)
		g:Play()
	end
	-- a fallback: done() even if the game never reports the end
	if done and C_Timer and C_Timer.After then
		C_Timer.After(0.35, function() if not called then called = true; done() end end)
	end
end

-- 7. the world marker: you arrived; a gold ring bursts out of the diamond (WorldMarker.lua)
function api.animArrive(parent, anchor, size)
	if not (parent and anchor and on("arrive")) then return end
	local t = parent.qtsArrive
	if not t then
		t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetVertexColor(1, 0.85, 0.35, 1)
		parent.qtsArrive = t
	end
	t:ClearAllPoints()
	t:SetPoint("CENTER", anchor, "CENTER")
	start("arrive", { dur = 0.8,
		apply = function(e, p)
			local s = (size or 34) * (1 + 4 * easeOut(p))
			t:SetSize(s, s)
			t:SetAlpha(1 - p)
			t:Show()
		end,
		finish = function() t:Hide() end })
end

-- 10. the RestedXP steps: the list moves up into place and the new current step fades in (Objectives/tracker/Rows.lua)
function api.animStepRows(rows, rise)
	if not (rows and on("steps")) then return end
	for _, r in ipairs(rows) do
		local f, fade = r[1], r[2]
		if f and f.CreateAnimationGroup then
			local g = f.qtsStepAnim
			if not g then
				g = f:CreateAnimationGroup()
				g.down = g:CreateAnimation("Translation"); g.down:SetDuration(0); g.down:SetOrder(1)
				g.up = g:CreateAnimation("Translation"); g.up:SetDuration(0.35); g.up:SetSmoothing("OUT"); g.up:SetOrder(2)
				g.alpha = g:CreateAnimation("Alpha"); g.alpha:SetDuration(0.35); g.alpha:SetOrder(2)
				f.qtsStepAnim = g
			end
			g:Stop()
			g.down:SetOffset(0, -rise)
			g.up:SetOffset(0, rise)
			g.alpha:SetFromAlpha(fade and 0 or 1); g.alpha:SetToAlpha(1)
			g:Play()
		end
	end
end

-- 11. the RestedXP arrow has a new target: a gold ring pulses out from it once
local arrowRing
function api.animArrowPulse(anchor)
	if not (anchor and anchor.IsShown and anchor:IsShown() and on("rxparrow")) then return end
	if not arrowRing then
		arrowRing = CreateFrame("Frame", nil, UIParent)
		arrowRing:SetFrameStrata("MEDIUM")
		arrowRing.t = arrowRing:CreateTexture(nil, "OVERLAY")
		arrowRing.t:SetTexture(GLOW)
		arrowRing.t:SetBlendMode("ADD")
		arrowRing.t:SetVertexColor(1, 0.85, 0.4, 1)
		arrowRing.t:SetAllPoints()
		arrowRing:EnableMouse(false)
	end
	local size = math.max(anchor:GetWidth() or 40, 24)
	arrowRing:ClearAllPoints()
	arrowRing:SetPoint("CENTER", anchor, "CENTER")
	arrowRing:Show()
	start("arrowpulse", { dur = 0.6,
		apply = function(e, p)
			local s = size * (0.9 + 1.2 * easeOut(p))
			arrowRing:SetSize(s, s)
			arrowRing:SetAlpha(0.9 * (1 - p))
		end,
		finish = function() arrowRing:Hide() end })
end

-- 12. a settings switch: its knob slides across. Places the knob now (at `x` from the switch's left), gliding there
-- when it was somewhere else
function api.animKnob(knob, sw, x)
	if not (knob and sw) then return end
	local key = "knob:" .. tostring(knob)
	local e = effects[key]
	if e and e.to == x then
		pcall(e.apply, e, math.min((now() - e.start) / e.dur, 1))
		return
	end
	local from = knob.qtsX
	knob.qtsX = x
	if not (from and from ~= x and on("knob")) then
		finish(key)
		knob:ClearAllPoints(); knob:SetPoint("LEFT", sw, "LEFT", x, 0)
		return
	end
	start(key, { dur = 0.16, from = e and e.cur or from, to = x,
		apply = function(e2, p)
			e2.cur = e2.from + (e2.to - e2.from) * easeOut(p)
			knob:ClearAllPoints(); knob:SetPoint("LEFT", sw, "LEFT", e2.cur, 0)
		end,
		finish = function(e2) knob:ClearAllPoints(); knob:SetPoint("LEFT", sw, "LEFT", e2.to, 0) end })
end

-- 13. a slider was let go: its value glows gold and its text bounces
function api.animSliderDone(valueBox)
	if not (valueBox and on("slider")) then return end
	if not valueBox.qtsGlow then
		local t = valueBox:CreateTexture(nil, "OVERLAY")
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetVertexColor(1, 0.82, 0.3, 1)
		t:SetPoint("TOPLEFT", -6, 4); t:SetPoint("BOTTOMRIGHT", 6, -4)
		t:SetAlpha(0)
		valueBox.qtsGlow = t
	end
	local t = valueBox.qtsGlow
	start("sliderdone:" .. tostring(valueBox), { dur = 0.4,
		apply = function(e, p)
			t:SetAlpha(0.7 * math.sin(math.pi * p))
			if valueBox.SetTextScale then valueBox:SetTextScale(1 + 0.25 * math.sin(math.pi * p)) end
		end,
		finish = function()
			t:SetAlpha(0)
			if valueBox.SetTextScale then valueBox:SetTextScale(1) end
		end })
end

---------------------------------------------------------------------------------------------------------------------
-- The fourth set (3.2, user picked 1, 2, 5, 6, 7, 8, 10, 11, 12, 13 and 14: RestedXP, the dungeon card, the settings)
---------------------------------------------------------------------------------------------------------------------
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

-- 1. a RestedXP step you mark done: its row moves right and fades, then done() (at once when this is off)
function api.animSwipe(frame, done)
	if not (frame and frame.CreateAnimationGroup and frame.IsShown and frame:IsShown() and on("skip")) then
		if done then done() end
		return
	end
	local g = frame.qtsSwipe
	if not g then
		g = frame:CreateAnimationGroup()
		g.move = g:CreateAnimation("Translation"); g.move:SetDuration(0.25); g.move:SetSmoothing("IN")
		g.alpha = g:CreateAnimation("Alpha"); g.alpha:SetDuration(0.25)
		g.alpha:SetFromAlpha(1); g.alpha:SetToAlpha(0.15)
		frame.qtsSwipe = g
	end
	g:Stop()
	g.move:SetOffset(60, 0)
	local called = false
	local function after()
		if called then return end
		called = true
		if done then pcall(done) end
		g:Stop()
	end
	g:SetScript("OnFinished", after)
	g:Play()
	if C_Timer and C_Timer.After then C_Timer.After(0.4, after) end -- a fallback: done() even with no end reported
end

-- 2. the new current RestedXP step: a gold light goes down it once
function api.animSweep(frame)
	if not (frame and frame.CreateTexture and on("sweep")) then return end
	local t = frame.qtsSweep
	if not t then
		t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		frame.qtsSweep = t
	end
	start("sweep:" .. tostring(frame), { dur = 0.7,
		apply = function(e, p)
			local h = frame:GetHeight() or 30
			local y = -(h * easeOut(p)) + 9
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", -10, y)
			t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 10, y)
			t:SetHeight(18)
			t:SetAlpha(0.6 * math.sin(math.pi * p))
			t:Show()
		end,
		finish = function() t:Hide() end })
end

-- 5. the yards number: from the one shown toward the new one, a little each tick (Extras.lua); a big jump at once
function api.animTicker(shown, target, dt)
	if type(target) ~= "number" then return target end
	if type(shown) ~= "number" or not on("ticker") or math.abs(target - shown) > 500 then return target end
	local v = shown + (target - shown) * math.min(1, (dt or 0) * 3)
	if math.abs(target - v) < 0.5 then v = target end
	return v
end

-- 6. the dungeon card opens: the boss portraits drop in one after another
function api.animDropIn(frames)
	if not (frames and on("bossrows")) then return end
	for i, f in ipairs(frames) do
		if f and f.CreateAnimationGroup then
			local g = f.qtsDrop
			if not g then
				g = f:CreateAnimationGroup()
				g.up = g:CreateAnimation("Translation"); g.up:SetDuration(0); g.up:SetOrder(1); g.up:SetOffset(0, 12)
				g.hide = g:CreateAnimation("Alpha"); g.hide:SetDuration(0); g.hide:SetOrder(1)
				g.hide:SetFromAlpha(0); g.hide:SetToAlpha(0)
				g.down = g:CreateAnimation("Translation"); g.down:SetDuration(0.25); g.down:SetOrder(2)
				g.down:SetOffset(0, -12); g.down:SetSmoothing("OUT")
				g.alpha = g:CreateAnimation("Alpha"); g.alpha:SetDuration(0.25); g.alpha:SetOrder(2)
				g.alpha:SetFromAlpha(0); g.alpha:SetToAlpha(1)
				f.qtsDrop = g
			end
			g:Stop()
			local delay = (i - 1) * 0.06
			g.down:SetStartDelay(delay); g.alpha:SetStartDelay(delay)
			g:Play()
		end
	end
end

-- 7. a boss is killed: its portrait turns over and a gold check pops up on it, then fades
function api.animBossKill(portrait)
	if not (portrait and portrait.CreateAnimationGroup and on("bosskill")) then return end
	local g = portrait.qtsFlip
	if not g then
		g = portrait:CreateAnimationGroup()
		g.a = g:CreateAnimation("Scale"); g.a:SetDuration(0.15); g.a:SetOrder(1); g.a:SetSmoothing("IN")
		g.b = g:CreateAnimation("Scale"); g.b:SetDuration(0.15); g.b:SetOrder(2); g.b:SetSmoothing("OUT")
		if g.a.SetScaleFrom then
			g.a:SetScaleFrom(1, 1); g.a:SetScaleTo(0.05, 1); g.b:SetScaleFrom(0.05, 1); g.b:SetScaleTo(1, 1)
		elseif g.a.SetFromScale then
			g.a:SetFromScale(1, 1); g.a:SetToScale(0.05, 1); g.b:SetFromScale(0.05, 1); g.b:SetToScale(1, 1)
		end
		portrait.qtsFlip = g
	end
	g:Stop()
	g:Play()
	local holder = portrait.qtsCheck
	if not holder then
		holder = CreateFrame("Frame", nil, portrait:GetParent() or portrait)
		holder.t = holder:CreateTexture(nil, "OVERLAY", nil, 7)
		holder.t:SetTexture(CHECK)
		holder.t:SetAllPoints()
		holder.glow = holder:CreateTexture(nil, "OVERLAY", nil, 6)
		holder.glow:SetTexture(GLOW)
		holder.glow:SetBlendMode("ADD")
		holder.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		holder.glow:SetPoint("CENTER")
		holder:EnableMouse(false)
		portrait.qtsCheck = holder
	end
	holder:SetFrameLevel((portrait.GetFrameLevel and portrait:GetFrameLevel() or 1) + 8)
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", portrait, "CENTER")
	local size = math.max((portrait.GetWidth and portrait:GetWidth() or 38) * 0.7, 16)
	start("bosskill:" .. tostring(portrait), { dur = 1.8,
		apply = function(e, p)
			local s = p < 0.18 and 0.3 + 1 * easeOut(p / 0.18) or (p < 0.28 and 1.3 - 0.3 * ((p - 0.18) / 0.1) or 1)
			holder:SetSize(size * s, size * s)
			holder.glow:SetSize(size * 2.4, size * 2.4)
			holder.glow:SetAlpha(p < 0.4 and 0.8 * (1 - p / 0.4) or 0)
			holder:SetAlpha(p < 0.17 and 0 or (p > 0.7 and 1 - (p - 0.7) / 0.3 or 1))
			holder:Show()
		end,
		finish = function() holder:Hide() end })
end

-- 8. the last boss is killed: the card's edge flashes gold and a "CLEARED" stamp drops onto it, then fades
function api.animCleared(body)
	if not (body and body.CreateTexture and on("cleared")) then return end
	local c = body.qtsCleared
	if not c then
		c = CreateFrame("Frame", nil, body)
		c:SetAllPoints()
		c:EnableMouse(false)
		c.glow = c:CreateTexture(nil, "OVERLAY", nil, 6)
		c.glow:SetTexture(GLOW)
		c.glow:SetBlendMode("ADD")
		c.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		c.glow:SetPoint("TOPLEFT", -14, 10); c.glow:SetPoint("BOTTOMRIGHT", 14, -10)
		c.stamp = c:CreateFontString(nil, "OVERLAY")
		local font = GameFontNormalHuge and GameFontNormalHuge:GetFont() or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
		c.stamp:SetFont(font, 24, "OUTLINE")
		c.stamp:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		c.stamp:SetShadowOffset(2, -2)
		c.stamp:SetShadowColor(0, 0, 0, 1)
		c.stamp:SetText("CLEARED")
		c.stamp:SetPoint("CENTER", c, "CENTER", 0, 0)
		body.qtsCleared = c
	end
	c:SetFrameLevel((body.GetFrameLevel and body:GetFrameLevel() or 1) + 30)
	c:Show()
	start("cleared", { dur = 3.2,
		apply = function(e, p)
			c.glow:SetAlpha(p < 0.25 and 0.7 * math.sin(math.pi * p / 0.25) or 0)
			local s = p < 0.08 and 2.2 - 1.2 * easeOut(p / 0.08) or 1
			if c.stamp.SetTextScale then c.stamp:SetTextScale(s) end
			c.stamp:SetAlpha(p < 0.08 and p / 0.08 or (p > 0.75 and 1 - (p - 0.75) / 0.25 or 1))
		end,
		finish = function() c:Hide() end })
end

-- 10. the settings search: a matching setting's name flashes once
function api.animSearchGlow(fs)
	if not (fs and fs.GetParent and on("search")) then return end
	local parent = fs:GetParent()
	local t = fs.qtsSearchGlow
	if not t then
		t = parent:CreateTexture(nil, "BACKGROUND", nil, -3)
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		fs.qtsSearchGlow = t
	end
	start("search:" .. tostring(fs), { dur = 0.8,
		apply = function(e, p)
			if not fs:IsShown() then t:Hide() return end
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", fs, "TOPLEFT", -10, 5)
			t:SetSize((fs:GetStringWidth() or 100) + 26, (fs:GetStringHeight() or 12) + 10)
			t:SetAlpha(0.7 * (p < 0.2 and p / 0.2 or 1 - (p - 0.2) / 0.8))
			t:Show()
		end,
		finish = function() t:Hide() end })
end

-- 11. a setting was changed: a small check fades in right of its control, then away
function api.animSaved(ctrl)
	if not (ctrl and ctrl.GetParent and on("saved")) then return end
	local t = ctrl.qtsSaved
	if not t then
		t = ctrl:GetParent():CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(CHECK)
		ctrl.qtsSaved = t
	end
	t:ClearAllPoints()
	t:SetPoint("LEFT", ctrl, "RIGHT", 6, 0)
	start("saved:" .. tostring(ctrl), { dur = 1.3,
		apply = function(e, p)
			local s = p < 0.12 and 0.5 + 0.7 * (p / 0.12) or (p < 0.2 and 1.2 - 0.2 * ((p - 0.12) / 0.08) or 1)
			t:SetSize(14 * s, 14 * s)
			t:SetAlpha(p < 0.12 and p / 0.12 or (p > 0.6 and 1 - (p - 0.6) / 0.4 or 1))
			t:Show()
		end,
		finish = function() t:Hide() end })
end

-- 12. "Defaults": a value slides back to its default; set(v) draws it (at once when this is off)
function api.animResetSweep(key, from, to, set)
	if type(from) ~= "number" or type(to) ~= "number" or from == to or not on("reset") then set(to) return end
	start("reset:" .. tostring(key), { dur = 0.45, from = from, to = to,
		apply = function(e, p) set(e.from + (e.to - e.from) * easeOut(p)) end,
		finish = function(e) set(e.to) end })
end

-- 13. a settings dropdown opens: it unfolds from the box (down, or up when it opens above it)
function api.animUnfold(popup, up)
	if not (popup and popup.CreateAnimationGroup and on("dropdown")) then return end
	local g = popup.qtsUnfold
	if not g then
		g = popup:CreateAnimationGroup()
		g.scale = g:CreateAnimation("Scale"); g.scale:SetDuration(0.14); g.scale:SetSmoothing("OUT")
		g.alpha = g:CreateAnimation("Alpha"); g.alpha:SetDuration(0.14)
		g.alpha:SetFromAlpha(0); g.alpha:SetToAlpha(1)
		if g.scale.SetScaleFrom then g.scale:SetScaleFrom(1, 0.1); g.scale:SetScaleTo(1, 1)
		elseif g.scale.SetFromScale then g.scale:SetFromScale(1, 0.1); g.scale:SetToScale(1, 1) end
		popup.qtsUnfold = g
	end
	g:Stop()
	if g.scale.SetOrigin then g.scale:SetOrigin(up and "BOTTOM" or "TOP", 0, 0) end
	g:Play()
end

-- 14. the settings row under the mouse: a soft light fades in behind it, and out when the mouse leaves
function api.animRowLight(tex, inside)
	if not tex then return end
	local key = "rowlight:" .. tostring(tex)
	if not on("rowhover") then finish(key); tex:SetAlpha(0); tex:Hide() return end
	local from, to = tex:GetAlpha() or 0, inside and 1 or 0
	if not tex:IsShown() then from = 0 end
	tex:Show()
	start(key, { dur = 0.15,
		apply = function(e, p) tex:SetAlpha(from + (to - from) * p) end,
		finish = function() tex:SetAlpha(to); if to == 0 then tex:Hide() end end })
end

---------------------------------------------------------------------------------------------------------------------
-- The fifth set (3.2, user picked 1, 2, 3, 4, 5, 8 and 9)
---------------------------------------------------------------------------------------------------------------------
-- a shake left and right that dies down; region keeps its first point (put back at the end). red: tint the text red
-- and back to white
local function shake(key, region, kind, amount, red)
	if not (region and region.GetPoint and on(kind)) then return end
	local e0 = effects[key]
	local pt = e0 and e0.pt or { region:GetPoint(1) }
	if not pt[1] then return end
	start(key, { dur = 0.5, pt = pt,
		apply = function(e, p)
			local x = math.sin(p * math.pi * 6) * (amount or 4) * (1 - p)
			region:SetPoint(e.pt[1], e.pt[2], e.pt[3], (e.pt[4] or 0) + x, e.pt[5] or 0)
			if red and region.SetTextColor then region:SetTextColor(1, 0.25 + 0.75 * p, 0.25 + 0.75 * p) end
		end,
		finish = function(e)
			region:SetPoint(e.pt[1], e.pt[2], e.pt[3], e.pt[4] or 0, e.pt[5] or 0)
			if red and region.SetTextColor then region:SetTextColor(1, 1, 1) end
		end })
end
-- 1. the dungeon card's deaths went up: the number shakes and shows red for a moment (the skull goes with it)
function api.animDeath(fs) shake("deaths", fs, "deaths", 4, true) end
-- 3. the hourly instance limit is reached: the card's instance line shakes
function api.animCapShake(fs) shake("cap", fs, "cap", 5) end

-- 2. the number of players changed: the banner's number bumps
function api.animPartyBump(fs)
	if not (fs and fs.SetTextScale and on("party")) then return end
	start("party", { dur = 0.4,
		apply = function(e, p) fs:SetTextScale(1 + 0.5 * math.sin(math.pi * p)) end,
		finish = function() fs:SetTextScale(1) end })
end

-- 4. reputation gained: "+250" rises from the reputation bar and fades
function api.animFloat(parent, anchor, text)
	if not (parent and anchor and text and on("repfloat")) then return end
	local fs = parent.qtsFloat
	if not fs then
		fs = parent:CreateFontString(nil, "OVERLAY")
		local font = GameFontNormal and GameFontNormal:GetFont() or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
		fs:SetFont(font, 13, "OUTLINE")
		fs:SetTextColor(0.45, 1, 0.45)
		parent.qtsFloat = fs
	end
	fs:SetText(text)
	start("repfloat", { dur = 1.4,
		apply = function(e, p)
			fs:ClearAllPoints()
			fs:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2 + 18 * easeOut(p))
			fs:SetAlpha(p < 0.1 and p / 0.1 or (p > 0.6 and 1 - (p - 0.6) / 0.4 or 1))
			fs:Show()
		end,
		finish = function() fs:Hide() end })
end

-- 8. a settings section's icon tilts a little and back when the mouse comes on it
function api.animTilt(tex)
	if not (tex and tex.CreateAnimationGroup and on("tilt")) then return end
	local g = tex.qtsTilt
	if not g then
		g = tex:CreateAnimationGroup()
		local function turn(order, deg, dur)
			local r = g:CreateAnimation("Rotation")
			r:SetDegrees(deg); r:SetDuration(dur); r:SetOrder(order)
			if r.SetOrigin then r:SetOrigin("CENTER", 0, 0) end
			return r
		end
		turn(1, 10, 0.08); turn(2, -18, 0.14); turn(3, 8, 0.1)
		tex.qtsTilt = g
	end
	g:Stop()
	g:Play()
end

-- 9. the settings window closes: it fades and grows a little smaller, then done() hides it (at once when off)
function api.animWindowClose(f, done)
	if not (f and f.CreateAnimationGroup and on("window")) then done() return end
	if f.qtsClosing then return end
	local g = f.qtsCloseAnim
	if not g then
		g = f:CreateAnimationGroup()
		local a = g:CreateAnimation("Alpha")
		a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(0.15); a:SetSmoothing("IN")
		local s = g:CreateAnimation("Scale")
		if s.SetScaleFrom then s:SetScaleFrom(1, 1); s:SetScaleTo(0.96, 0.96) else s:SetScale(0.96, 0.96) end
		s:SetDuration(0.15); s:SetSmoothing("IN")
		if s.SetOrigin then s:SetOrigin("CENTER", 0, 0) end
		f.qtsCloseAnim = g
	end
	local token = {}
	f.qtsClosing = token
	local function after()
		if f.qtsClosing ~= token then return end -- opened again meanwhile
		f.qtsClosing = nil
		pcall(done)
		g:Stop()
	end
	g:SetScript("OnFinished", after)
	g:Stop()
	g:Play()
	if C_Timer and C_Timer.After then C_Timer.After(0.25, after) end
end

---------------------------------------------------------------------------------------------------------------------
-- The sixth set (3.2, user picked 2, 3, 4 and 8 of the ideas from other addons: BigWigs' screen flash, EllesmereUI's
-- pulsing dot, Details' new record, EllesmereUI's chat tab flash)
---------------------------------------------------------------------------------------------------------------------
-- on, also in combat (for what keeps showing, not for a new effect): the switches only
local function enabled(kind)
	local db = ns.db
	if not db or db.animations == false then return false end
	return not (type(db.animOff) == "table" and db.animOff[kind])
end
api.animEnabled = enabled

-- 2. a quest failed: the edges of the screen flash red twice
local edges
function api.animFailFlash()
	if not on("failflash") then return end
	if not edges then
		edges = CreateFrame("Frame", nil, UIParent)
		edges:SetAllPoints(UIParent)
		edges:SetFrameStrata("FULLSCREEN")
		edges:EnableMouse(false)
		local function side(p1, p2, horizontal, size, a1, a2)
			local t = edges:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(1, 1, 1, 1)
			t:SetPoint(p1); t:SetPoint(p2)
			if horizontal then t:SetHeight(size) else t:SetWidth(size) end
			local ok = t.SetGradient and CreateColor and pcall(t.SetGradient, t, horizontal and "VERTICAL" or "HORIZONTAL",
				CreateColor(0.9, 0.05, 0.05, a1), CreateColor(0.9, 0.05, 0.05, a2))
			if not ok then t:SetColorTexture(0.9, 0.05, 0.05, 0.25) end
		end
		side("TOPLEFT", "TOPRIGHT", true, 90, 0, 0.7)      -- top: strong at the edge
		side("BOTTOMLEFT", "BOTTOMRIGHT", true, 90, 0.7, 0)
		side("TOPLEFT", "BOTTOMLEFT", false, 110, 0.7, 0)
		side("TOPRIGHT", "BOTTOMRIGHT", false, 110, 0, 0.7)
	end
	edges:SetAlpha(0)
	edges:Show()
	start("failflash", { dur = 1.2,
		apply = function(e, p) edges:SetAlpha(math.abs(math.sin(p * math.pi * 2)) * (1 - 0.3 * p)) end,
		finish = function() edges:Hide() end })
end

-- 3. the dungeon card's run light: a small red dot that pulses while the run goes on (shown: wanted and switched on)
function api.animRunLight(tex, want)
	if not tex then return end
	if not (want and enabled("runlight")) then
		if type(tex.qtsPulse) == "table" then tex.qtsPulse:Stop() end
		tex:Hide()
		return
	end
	tex:Show()
	if not tex.CreateAnimationGroup then return end
	local g = type(tex.qtsPulse) == "table" and tex.qtsPulse or nil
	if not g then
		g = tex:CreateAnimationGroup()
		if not (type(g) == "table" and g.SetLooping) then return end -- no animations here: the dot stays still
		g:SetLooping("BOUNCE")
		local a = g:CreateAnimation("Alpha")
		a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.8); a:SetSmoothing("IN_OUT")
		tex.qtsPulse = g
	end
	if not g:IsPlaying() then g:Play() end
end

-- 4. a boss died faster than your best: "NEW BEST" and the time saved flash on the card, in green
function api.animNewBest(body, text)
	if not (body and body.CreateFontString and on("newbest")) then return end
	local c = body.qtsNewBest
	if not c then
		c = CreateFrame("Frame", nil, body)
		c:SetAllPoints()
		c:EnableMouse(false)
		c.glow = c:CreateTexture(nil, "OVERLAY", nil, 6)
		c.glow:SetTexture(GLOW)
		c.glow:SetBlendMode("ADD")
		c.glow:SetVertexColor(0.3, 1, 0.4, 1)
		c.text = c:CreateFontString(nil, "OVERLAY")
		local font = GameFontNormalLarge and GameFontNormalLarge:GetFont() or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
		c.text:SetFont(font, 16, "OUTLINE")
		c.text:SetTextColor(0.45, 1, 0.5)
		c.text:SetShadowOffset(1, -1)
		c.text:SetShadowColor(0, 0, 0, 1)
		c.text:SetPoint("BOTTOM", c, "BOTTOM", 0, 8)
		c.glow:SetPoint("CENTER", c.text, "CENTER")
		body.qtsNewBest = c
	end
	c.text:SetText(text or "NEW BEST")
	c:SetFrameLevel((body.GetFrameLevel and body:GetFrameLevel() or 1) + 29)
	c:Show()
	start("newbest", { dur = 2.6,
		apply = function(e, p)
			local w = (c.text:GetStringWidth() or 100) + 60
			c.glow:SetSize(w, 40)
			c.glow:SetAlpha(p < 0.3 and 0.8 * math.sin(math.pi * p / 0.3) or 0)
			if c.text.SetTextScale then c.text:SetTextScale(p < 0.1 and 1.6 - 0.6 * easeOut(p / 0.1) or 1) end
			c.text:SetAlpha(p < 0.1 and p / 0.1 or (p > 0.75 and 1 - (p - 0.75) / 0.25 or 1))
		end,
		finish = function() c:Hide() end })
end

-- 8. the "What's new" button glows softly, over and over, until you open the notes (want: not read yet)
function api.animNewsGlow(button, want)
	if not button then return end
	local t = type(button.qtsNews) == "table" and button.qtsNews or nil
	if not (want and enabled("newsglow")) then
		if t then t.g:Stop(); t:Hide() end
		return
	end
	if not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		t:SetPoint("TOPLEFT", -10, 8); t:SetPoint("BOTTOMRIGHT", 10, -8)
		local g = t.CreateAnimationGroup and t:CreateAnimationGroup()
		if type(g) == "table" and g.SetLooping then
			t.g = g
			t.g:SetLooping("BOUNCE")
			local a = t.g:CreateAnimation("Alpha")
			a:SetFromAlpha(0.15); a:SetToAlpha(0.75); a:SetDuration(0.9); a:SetSmoothing("IN_OUT")
		else
			t.g = { Play = function() end, Stop = function() end, IsPlaying = function() return true end }
			t:SetAlpha(0.5)
		end
		button.qtsNews = t
	end
	t:Show()
	if not t.g:IsPlaying() then t.g:Play() end
end

---------------------------------------------------------------------------------------------------------------------
-- Set 7 (3.2, user: 1, 2, 3, 5, 6, 7, 8, 9, 11, 12). Battleground effects run in combat too (enabled, not on): they
-- only touch our own frames.
---------------------------------------------------------------------------------------------------------------------
local SIDE_RGB = { Alliance = { 0.25, 0.55, 1 }, Horde = { 1, 0.2, 0.15 } }

-- a glow texture over a frame, kept on it
local function overlay(frame, field)
	local t = type(frame[field]) == "table" and frame[field] or nil
	if not t then
		t = frame:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetPoint("TOPLEFT", -8, 6); t:SetPoint("BOTTOMRIGHT", 8, -6)
		t:SetAlpha(0)
		frame[field] = t
	end
	return t
end
-- a looping soft pulse on a texture (want: on)
local function loopPulse(t, want, from, to, dur)
	if not want then
		if type(t.qtsLoop) == "table" then t.qtsLoop:Stop() end
		t:Hide()
		return
	end
	t:Show()
	local g = type(t.qtsLoop) == "table" and t.qtsLoop or nil
	if not g then
		g = t.CreateAnimationGroup and t:CreateAnimationGroup()
		if type(g) == "table" and g.SetLooping then
			g:SetLooping("BOUNCE")
			local a = g:CreateAnimation("Alpha")
			a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetSmoothing("IN_OUT")
		else
			g = { Play = function() end, Stop = function() end, IsPlaying = function() return true end }
			t:SetAlpha((from + to) / 2)
		end
		t.qtsLoop = g
	end
	if not g:IsPlaying() then g:Play() end
end
api.animLoopPulse = loopPulse

-- 1. a base is captured: its bar flashes in the side's colour and fades out (Battleground.lua keeps it 0.8 s)
function api.animBgCaptured(w, side)
	if not (w and w.CreateTexture and enabled("bgcapture")) then return false end
	local t = overlay(w, "qtsCapture")
	local c = SIDE_RGB[side] or GOLD
	t:SetVertexColor(c[1], c[2], c[3], 1)
	t:Show()
	start("bgcapture:" .. tostring(w), { dur = 0.8,
		apply = function(e, p)
			t:SetAlpha(p < 0.25 and p / 0.25 or 1 - (p - 0.25) / 0.75)
			w:SetAlpha(p < 0.35 and 1 or 1 - (p - 0.35) / 0.65)
		end,
		finish = function() t:SetAlpha(0); t:Hide() end })
	return true
end
-- a bar widget used for another timer: no capture fade left on it
function api.animBgReset(w)
	if not w then return end
	finish("bgcapture:" .. tostring(w))
	if w.SetAlpha then w:SetAlpha(1) end
end

-- 2 and 7. a bar's last seconds: a red glow pulses on it (want: in its last seconds)
function api.animBgPulse(w, want, kind)
	if not (w and w.CreateTexture) then return end
	local t = overlay(w, "qtsLast")
	t:SetVertexColor(1, 0.15, 0.1, 1)
	loopPulse(t, want and enabled(kind or "bgpulse"), 0.1, 0.7, 0.45)
end

-- 3. the winning side changed: the old side's colour folds away to the middle, the new bar shows behind it
function api.animBgSwap(w, fromSide)
	if not (w and w.CreateTexture and enabled("bgswap")) then return end
	local t = type(w.qtsSwap) == "table" and w.qtsSwap or nil
	if not t then
		t = w:CreateTexture(nil, "OVERLAY", nil, 5)
		w.qtsSwap = t
	end
	local c = SIDE_RGB[fromSide] or GOLD
	t:SetColorTexture(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8, 1)
	local glint = overlay(w, "qtsSwapGlint")
	glint:SetVertexColor(1, 1, 1, 1)
	start("bgswap:" .. tostring(w), { dur = 0.5,
		apply = function(e, p)
			local h = (w:GetHeight() or 14) * (1 - easeOut(p))
			t:ClearAllPoints()
			t:SetPoint("LEFT", w, "LEFT", 0, 0); t:SetPoint("RIGHT", w, "RIGHT", 0, 0)
			t:SetHeight(math.max(h, 0.5))
			t:SetShown(h > 0.5)
			glint:Show()
			glint:SetAlpha(0.8 * math.sin(math.pi * p))
		end,
		finish = function() t:Hide(); glint:SetAlpha(0) end })
end

-- 5. a flag carrier's health is low: the line shakes red
function api.animBgCarrier(fs)
	if not (fs and fs.GetPoint and enabled("bgcarrier")) then return end
	local key = "bgcarrier:" .. tostring(fs)
	local e0 = effects[key]
	local pt = e0 and e0.pt or { fs:GetPoint(1) }
	if not pt[1] then return end
	start(key, { dur = 0.5, pt = pt,
		apply = function(e, p)
			local x = math.sin(p * math.pi * 6) * 3 * (1 - p)
			fs:SetPoint(e.pt[1], e.pt[2], e.pt[3], (e.pt[4] or 0) + x, e.pt[5] or 0)
			if fs.SetTextColor then fs:SetTextColor(1, 0.3 + 0.55 * p, 0.3 + 0.55 * p) end
		end,
		finish = function(e)
			fs:SetPoint(e.pt[1], e.pt[2], e.pt[3], e.pt[4] or 0, e.pt[5] or 0)
			if fs.SetTextColor then fs:SetTextColor(0.85, 0.85, 0.85) end
		end })
end

-- 6. a flag was dropped: its line pops out and back once
function api.animBgDrop(fs)
	if not (fs and fs.SetTextScale and enabled("bgdrop")) then return end
	start("bgdrop:" .. tostring(fs), { dur = 0.45,
		apply = function(e, p) fs:SetTextScale(1 + 0.35 * math.sin(math.pi * p)) end,
		finish = function() fs:SetTextScale(1) end })
end

-- 7. a queue is ready: the "Enter" bar bounces up twice
function api.animBgBounce(w)
	if not (w and w.GetPoint and enabled("bgqueue")) then return end
	local p1, p2 = { w:GetPoint(1) }, { w:GetPoint(2) }
	if not p1[1] then return end
	start("bgbounce:" .. tostring(w), { dur = 0.7,
		apply = function(e, p)
			local y = math.abs(math.sin(p * math.pi * 2)) * 6 * (1 - p)
			w:SetPoint(p1[1], p1[2], p1[3], p1[4] or 0, (p1[5] or 0) + y)
			if p2[1] then w:SetPoint(p2[1], p2[2], p2[3], p2[4] or 0, (p2[5] or 0) + y) end
		end,
		finish = function()
			w:SetPoint(p1[1], p1[2], p1[3], p1[4] or 0, p1[5] or 0)
			if p2[1] then w:SetPoint(p2[1], p2[2], p2[3], p2[4] or 0, p2[5] or 0) end
		end })
end

-- 9. the corpse is close enough: a gold glow pulses behind the corpse arrow
function api.animCorpseGlow(tex, want)
	if not tex then return end
	loopPulse(tex, want and enabled("corpse"), 0.2, 0.9, 0.6)
end

-- 3.2 (user): the LayerSwap icon glows when a swap you clicked for while it was blocked can be asked now
function api.animLayerSwapReady(tex, want)
	if not tex then return end
	loopPulse(tex, want and enabled("layerswap"), 0.15, 1, 0.5)
end

-- 3.2 (user): the light behind the big quest item button (QuestAction.lua) pulses; still and soft when switched off
function api.animQuestAction(tex, want)
	if not tex then return end
	if want and not enabled("questaction") then
		loopPulse(tex, false)
		tex:SetAlpha(0.6)
		tex:Show()
		return
	end
	loopPulse(tex, want, 0.35, 1, 0.9)
end

-- 11. the run summary: a number counts from the last card's value to this one (fmt(value) -> text)
function api.animCountFrom(fs, from, to, fmt)
	if not (fs and fmt) then return end
	from, to = tonumber(from), tonumber(to) or 0
	if not from or from == to or not enabled("summary") then fs:SetText(fmt(to)) return end
	start("countfrom:" .. tostring(fs), { dur = 0.9,
		apply = function(e, p) fs:SetText(fmt(math.floor(from + (to - from) * easeOut(p) + 0.5))) end,
		finish = function() fs:SetText(fmt(to)) end })
end

-- 12. the "Loot you want" line: a gold light runs along it once
function api.animLootSparkle(line)
	if not (line and line.CreateTexture and enabled("lootsparkle")) then return end
	local t = type(line.qtsLootGlint) == "table" and line.qtsLootGlint or nil
	if not t then
		t = line:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(GLOW)
		t:SetBlendMode("ADD")
		t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		line.qtsLootGlint = t
	end
	local w, h = line:GetWidth() or 150, line:GetHeight() or 14
	start("lootsparkle:" .. tostring(line), { dur = 1.1,
		apply = function(e, p)
			t:ClearAllPoints()
			t:SetPoint("CENTER", line, "LEFT", w * easeOut(p), 0)
			t:SetSize(h * 3, h * 2)
			t:SetAlpha(math.sin(math.pi * p))
			t:Show()
		end,
		finish = function() t:Hide() end })
end
