-- 3.2 (user): Tracker/Animations.lua: objective flash, check pop, title shine, slide in, fade out, bar growth, the
-- settings window and the tab mark; the on/off setting and combat
local root = arg[1] or ".."
local fails = 0
local function check(name, ok) print((ok and "ok   " or "FAIL ") .. name); if not ok then fails = fails + 1 end end

local clock, combat = 100, false
local function obj(kind)
	local o = { kind = kind, shown = kind ~= "Frame", alpha = 1, scale = 1, w = 100, h = 12, points = {}, scripts = {}, text = "" }
	return setmetatable(o, { __index = function(t, k)
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
local function methods(o)
	function o:SetScript(n, f) self.scripts[n] = f end
	function o:Show() self.shown = true end
	function o:Hide() self.shown = false end
	function o:SetShown(v) self.shown = v and true or false end
	function o:IsShown() return self.shown end
	function o:SetAlpha(a) self.alpha = a end
	function o:GetAlpha() return self.alpha end
	function o:SetScale(s) self.scale = s end
	function o:SetPoint(...) self.points[1] = { ... } end
	function o:ClearAllPoints() self.points = {} end
	function o:GetPoint(i) local p = self.points[i or 1]; if p then return table.unpack(p) end end
	function o:SetWidth(w) self.w = w end
	function o:GetWidth() return self.w end
	function o:SetSize(w, h) self.w, self.h = w, h end
	function o:GetStringWidth() return self.w end
	function o:GetStringHeight() return self.h end
	function o:GetParent() return self.parent end
	function o:SetText(t) self.text = t end
	function o:GetText() return self.text end
	function o:GetFont() return "font", 12, "" end
	function o:GetTextColor() return 1, 1, 1, 1 end
	function o:SetTextScale(v) self.textScale = v end
	function o:SetRotation(r) self.rotation = r end
	function o:SetFont() end
	function o:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
	function o:CreateTexture() local t = methods(obj("Texture")); t.parent = self; t.shown = true; return t end
	function o:CreateFontString() local t = methods(obj("FontString")); t.parent = self; t.shown = true; return t end
	function o:CreateAnimationGroup()
		local g = { played = 0 }
		function g:CreateAnimation() return setmetatable({}, { __index = function() return function() end end }) end
		function g:Stop() end
		function g:Play() self.played = self.played + 1 end
		return g
	end
	return o
end
local frames = {}
local env = setmetatable({
	CreateFrame = function(kind) local f = methods(obj(kind)); frames[#frames + 1] = f; return f end,
	GetTime = function() return clock end,
	InCombatLockdown = function() return combat end,
}, { __index = _G })
local db = {}
local ns = { api = {}, db = db }
local chunk = assert(loadfile(root .. "/Tracker/Animations.lua", "t", env))
chunk("ForeverTrackerPlus", { tracker = ns })
local api = ns.api
local driver, events = frames[1], frames[2]
local function run(t) clock = clock + t; driver.scripts.OnUpdate() end

local parent = methods(obj("Frame"))
local function row(x, y) local fs = parent:CreateFontString(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); return fs end
local function rebuild(quests)
	api.animBegin()
	local out = {}
	for _, q in ipairs(quests) do
		local t = row(10, -0)
		t.qtsCheck = q.complete and methods(obj("Frame")) or nil
		if t.qtsCheck then t.qtsCheck.shown = true; t.qtsCheck:SetPoint("RIGHT", t, "TOPLEFT", -4, -6) end
		api.animTitle(q, t)
		local lines = {}
		for i, o in ipairs(q.objectives) do
			lines[i] = row(20, -14)
			api.animLine(q, i, o.done, lines[i])
			if o.bar then
				o.bar.fill:SetWidth(100 * o.have / o.need)
				api.animBar(q.id, i, o.bar, o.have, o.need)
			end
		end
		out[q.id] = { title = t, lines = lines }
	end
	api.animEnd()
	return out
end
local function effectsOf(prefix)
	local n = 0
	for k in pairs(api.animEffects()) do if k:find(prefix, 1, true) == 1 then n = n + 1 end end
	return n
end

-- first rebuild: nothing animates
local bar = { fill = methods(obj("Texture")) }
local q = { id = 1, complete = false, objectives = { { done = false, bar = bar, have = 2, need = 8 }, { done = false } } }
rebuild({ q })
check("first rebuild: no effects", next(api.animEffects()) == nil)

-- 4. a bar grows
q.objectives[1].have = 6
rebuild({ q })
check("bar: an effect starts", effectsOf("bar:1:1") == 1)
check("bar: starts at the old value", math.abs(bar.fill:GetWidth() - 25) < 0.01)
run(0.25)
check("bar: in between", bar.fill:GetWidth() > 25 and bar.fill:GetWidth() < 75)
run(1)
check("bar: ends at the new value", math.abs(bar.fill:GetWidth() - 75) < 0.01 and effectsOf("bar:") == 0)

-- 1. an objective is done: the line flashes
q.objectives[2].done = true
rebuild({ q })
check("objective done: the line flashes", effectsOf("flash:1:2") == 1)
run(1)
check("flash ends", effectsOf("flash:") == 0)

-- 1 and 2. the quest is finished: the check pops and the title shines
q.objectives[1].done, q.complete = true, true
local drawn = rebuild({ q })
check("quest finished: check pops", effectsOf("pop:1") == 1)
check("quest finished: title shines", effectsOf("shine:1") == 1)
run(0.1)
check("pop: the check grows", drawn[1].title.qtsCheck.scale > 1)
drawn = rebuild({ q })
check("a rebuild during the effect: it follows the new row", api.animEffects()["shine:1"].fs == drawn[1].title)
run(1)
check("pop: the check is back to its size", drawn[1].title.qtsCheck.scale == 1 and effectsOf("pop:") == 0)

-- 3. a new quest slides in
events.scripts.OnEvent(events, "QUEST_ACCEPTED", 2)
local q2 = { id = 2, complete = false, objectives = { { done = false } } }
drawn = rebuild({ q, q2 })
check("accepted quest: it slides in", effectsOf("slide:2") == 1)
check("slide: starts hidden and left", drawn[2].title.alpha == 0 and select(4, drawn[2].title:GetPoint(1)) < 10)
check("slide: its lines too", drawn[2].lines[1].alpha == 0)
run(0.2)
check("slide: in between", drawn[2].title.alpha > 0 and drawn[2].title.alpha < 1)
drawn = rebuild({ q, q2 })
check("slide: a rebuild keeps it going on the new rows", drawn[2].title.alpha > 0 and drawn[2].title.alpha < 1)
run(1)
check("slide: ends in place", drawn[2].title.alpha == 1 and select(4, drawn[2].title:GetPoint(1)) == 10)

-- 3. a quest leaves the log: a copy of its title fades out
drawn[2].title:SetText("[12] Some quest")
events.scripts.OnEvent(events, "QUEST_REMOVED", 2)
check("removed quest: a ghost fades out", effectsOf("ghost:") == 1)
run(1)
check("ghost ends", effectsOf("ghost:") == 0)

-- off, and combat
db.animations = false
q.objectives[1].have = 7
local q3 = { id = 3, complete = false, objectives = { { done = false } } }
rebuild({ q3 }); q3.objectives[1].done = true; rebuild({ q3 })
check("off: no flash", effectsOf("flash:") == 0)
db.animations = nil
combat = true
q3.objectives[1].done = false; rebuild({ q3 }); q3.objectives[1].done = true; rebuild({ q3 })
check("in combat: no flash", effectsOf("flash:") == 0)
combat = false

-- 6. the settings window and the tab mark
local win = methods(obj("Frame"))
api.animWindowOpen(win)
check("window: the open animation plays", win.qtsOpenAnim and win.qtsOpenAnim.played == 1)
local tabRow = methods(obj("Frame"))
local mark = tabRow:CreateTexture()
api.animTabMark(mark, 10, 50)
check("tab mark: first place without a glide", effectsOf("tabmark") == 0 and select(4, mark:GetPoint(1)) == 10)
api.animTabMark(mark, 90, 40)
check("tab mark: glides to the new tab", effectsOf("tabmark") == 1)
run(0.1)
local x = select(4, mark:GetPoint(1))
check("tab mark: in between", x > 10 and x < 90)
run(1)
check("tab mark: ends under the new tab", select(4, mark:GetPoint(1)) == 90 and mark:GetWidth() == 40)

-- second set
-- a count goes up: the line glows; a bar's count bounces
local q4 = { id = 4, complete = false, objectives = { { done = false } } }
local function rb4(text)
	api.animBegin()
	local t = row(10, 0); api.animTitle(q4, t)
	local l = row(20, -14); api.animLine(q4, 1, false, l, text)
	api.animEnd()
	return l
end
rb4("Boar Meat: 2/8"); rb4("Boar Meat: 3/8")
check("count up: the line glows", effectsOf("tint:4:1") == 1)
run(1)
local bar2 = { fill = methods(obj("Texture")), text = parent:CreateFontString() }
local q5 = { id = 5, complete = false, objectives = { { done = false, bar = bar2, have = 1, need = 4 } } }
rebuild({ q5 }); q5.objectives[1].have = 2; rebuild({ q5 })
check("bar count bounces", effectsOf("bounce:bar:5:1") == 1)
run(0.17)
check("bounce: bigger in the middle", (bar2.text.textScale or 1) > 1.2)
run(1)
check("bounce: back to size", bar2.text.textScale == 1)

-- the quest counter pulses when a quest is added to an almost full log
local counter = parent:CreateFontString()
api.animCount(counter, 36, 40); api.animCount(counter, 37, 40)
check("almost full log: the counter pulses", effectsOf("count") == 1)
run(2)
api.animCount(counter, 10, 40); api.animCount(counter, 11, 40)
check("a roomy log: no pulse", effectsOf("count") == 0)

-- zones: unfold slides the quests in, fold fades their titles out
local q6 = { id = 6, complete = false, objectives = {} }
local function rbz(folded)
	api.animBegin()
	api.animZone("Elwynn", folded, { q6 })
	if not folded then local t = row(10, 0); api.animTitle(q6, t) end
	api.animEnd()
end
rbz(false); rbz(true)
check("zone folds: its title fades out", effectsOf("ghost:") == 1)
run(1)
rbz(false)
check("zone opens: its quests slide in", effectsOf("slide:6") == 1)
run(1)

-- the arrow turns a part of the way, the short way round
local a1 = api.animArrowAngle(0, 1, 0.03)
check("arrow: a part of the way", a1 > 0 and a1 < 1)
local a2 = api.animArrowAngle(0.1, 2 * math.pi - 0.1, 0.03)
check("arrow: the short way round", a2 < 0.1)
db.animations = false
check("arrow: off jumps", api.animArrowAngle(0, 1, 0.03) == 1)
db.animations = nil

-- count up: numbers grow, escapes stay
check("count up: half", api.animScaledText("10 quests", 0.5) == "5 quests")
check("count up: texture escapes untouched", api.animScaledText("|TCoin_01:14:14|t 20", 0.5) == "|TCoin_01:14:14|t 10")
check("count up: colour codes untouched", api.animScaledText("|cff112233 40|r", 0.25) == "|cff112233 10|r")
local tileText = parent:CreateFontString()
api.animCountUp(tileText, "100", true)
check("count up: starts at 0", tileText:GetText() == "0")
run(1)
check("count up: ends at the value", tileText:GetText() == "100")

-- settings: rows fade in, the arrow turns
local rowA = methods(obj("Frame"))
api.animFadeIn("cardfade", { rowA })
check("card rows start faded", rowA.alpha == 0)
run(1)
check("card rows end shown", rowA.alpha == 1)
local chev = parent:CreateTexture()
api.animRotate(chev, 0); api.animRotate(chev, -math.pi / 2)
run(0.05)
check("chevron turns in steps", chev.rotation < 0 and chev.rotation > -math.pi / 2)
run(1)
check("chevron ends turned", math.abs(chev.rotation + math.pi / 2) < 1e-6)

-- hover and the strike
local hb, hfs = methods(obj("Frame")), parent:CreateFontString()
api.animHover(hb, hfs, true); run(1)
check("hover: the title lights up", hb.qtsHover.alpha > 0.3)
api.animHover(hb, hfs, false); run(1)
check("hover: the light goes", hb.qtsHover.alpha == 0)
local sb = methods(obj("Frame")); sb.text = sb:CreateFontString(); sb.text.w = 80
api.animStrike(sb); run(0.1)
check("strike: draws across", sb.qtsStrike:GetWidth() > 1 and sb.qtsStrike:GetWidth() < 80)
run(1)
check("strike: through the whole name", sb.qtsStrike:GetWidth() == 80)

-- third set
-- sort glide: a quest drawn lower than before glides down from its old place
local qa, qb = { id = 20, complete = false, objectives = {} }, { id = 21, complete = false, objectives = {} }
local function rbOrder(list)
	api.animBegin()
	for i, q in ipairs(list) do local t = row(10, -(i - 1) * 20); api.animTitle(q, t) end
	api.animEnd()
end
rbOrder({ qa, qb }); rbOrder({ qb, qa })
check("order change: the moved quests glide", effectsOf("glide:20") == 1 and effectsOf("glide:21") == 1)
run(1)
check("glide ends", effectsOf("glide:") == 0)

-- smooth scroll steps toward the target
local sv = api.animScrollStep(0, 100, 0.016)
check("scroll: a part of the way", sv > 0 and sv < 100)
check("scroll: snaps when close", api.animScrollStep(99.8, 100, 0.016) == 100)

-- item sparkle, arrival, arrow ring, slider glow
local btn = methods(obj("Frame")); btn.w = 26
api.animSparkle(btn); run(0.27)
check("item sparkle shows", btn.qtsSparkle.alpha > 0.5)
run(1)
check("item sparkle ends", btn.qtsSparkle.alpha == 0)
local body = methods(obj("Frame"))
api.animArrive(body, body:CreateTexture(), 34); run(0.1)
check("arrival ring grows", body.qtsArrive.w > 34)
run(1)
local anchorF = methods(obj("Frame")); anchorF.shown = true
api.animArrowPulse(anchorF)
check("arrow pulse starts", effectsOf("arrowpulse") == 1)
run(1)
local vb = methods(obj("Frame"))
api.animSliderDone(vb); run(0.2)
check("slider value glows", vb.qtsGlow.alpha > 0.5)
run(1)

-- switch knob slides
local sw = methods(obj("Frame"))
local knob = sw:CreateTexture()
api.animKnob(knob, sw, 3)
check("knob: first place is instant", select(4, knob:GetPoint(1)) == 3)
api.animKnob(knob, sw, 25)
run(0.05)
local kx = select(4, knob:GetPoint(1))
check("knob: slides", kx > 3 and kx < 25)
api.animKnob(knob, sw, 25) -- a redraw during the slide keeps it going
check("knob: a redraw keeps the slide", effectsOf("knob:") == 1)
run(1)
check("knob: ends on the other side", select(4, knob:GetPoint(1)) == 25)

-- roll: done() runs when animations are off
db.animations = false
local rolled = false
api.animRoll({ methods(obj("Frame")) }, false, function() rolled = true end)
check("roll off: folds at once", rolled)
db.animations = nil

-- 3.2 (user): each animation has its own switch (db.animOff[kind]), listed in api.animKinds for the settings page
local keys = {}
for _, k in ipairs(api.animKinds or {}) do if k.key then keys[k.key] = true end end
check("kinds: every switch is listed", keys.flash and keys.knob and keys.steps and keys.strike and keys.countup)
db.animOff = { flash = true }
check("kind off: that one is off", api.animOn("flash") == false)
check("kind off: the others stay on", api.animOn("knob") == true)
check("kind off: no kind asked is on", api.animOn() == true)
local q4 = { id = 4, complete = false, objectives = { { done = false } } }
rebuild({ q4 }); q4.objectives[1].done = true; rebuild({ q4 })
check("flash off: no flash", effectsOf("flash:") == 0)
db.animOff = nil
db.animations = false
check("all off: every kind is off", api.animOn("knob") == false)
db.animations = nil

-- the fourth set (3.2, user): RestedXP, the dungeon card, the settings
combat = false
local swiped = false
api.animSwipe(methods(obj("Frame")), function() swiped = true end) -- no animation groups here: done at once
check("swipe: done() runs", swiped)
check("ticker: counts toward the new number", (function() local v = api.animTicker(100, 50, 0.1); return v < 100 and v > 50 end)())
check("ticker: a big jump is at once", api.animTicker(2000, 50, 0.1) == 50)
check("ticker: first number at once", api.animTicker(nil, 80, 0) == 80)
db.animOff = { ticker = true }
check("ticker off: at once", api.animTicker(100, 50, 0.1) == 50)
db.animOff = nil
local got
api.animResetSweep("x", 10, 30, function(v) got = v end)
run(0.1)
check("reset sweep: on the way", got and got > 10 and got < 30)
run(1)
check("reset sweep: ends on the default", got == 30)
db.animOff = { reset = true }
api.animResetSweep("x", 10, 40, function(v) got = v end)
check("reset sweep off: at once", got == 40)
db.animOff = nil
local ctrl = methods(obj("Frame")); ctrl.parent = parent
api.animSaved(ctrl)
check("saved check: shows", ctrl.qtsSaved and ctrl.qtsSaved.shown)
run(2)
check("saved check: goes away", not ctrl.qtsSaved.shown)
local sfs = parent:CreateFontString()
api.animSearchGlow(sfs)
check("search glow: runs", effectsOf("search:") == 1)
run(1)
check("search glow: ends", effectsOf("search:") == 0)
local light = parent:CreateTexture()
light.shown = false
api.animRowLight(light, true)
run(0.5)
check("row light: in", light.shown and light.alpha == 1)
api.animRowLight(light, false)
run(0.5)
check("row light: out", not light.shown)
local body = methods(obj("Frame"))
api.animCleared(body)
check("cleared: the stamp shows", body.qtsCleared and body.qtsCleared.stamp.text == "CLEARED")
run(4)
check("cleared: then hides", not body.qtsCleared.shown)
local stepRow = methods(obj("Frame")); stepRow.h = 40
function stepRow:GetHeight() return self.h end
api.animSweep(stepRow)
check("sweep: the light runs", effectsOf("sweep:") == 1)
run(1)
check("sweep: ends", effectsOf("sweep:") == 0)
local keys2 = {}
for _, k in ipairs(api.animKinds) do if k.key then keys2[k.key] = true end end
check("kinds: the fourth set has switches", keys2.skip and keys2.sweep and keys2.ticker and keys2.bossrows and keys2.bosskill
	and keys2.cleared and keys2.search and keys2.saved and keys2.reset and keys2.dropdown and keys2.rowhover)

-- the fifth set (3.2, user)
local dfs = parent:CreateFontString(); dfs:SetPoint("RIGHT", parent, "LEFT", -6, 0)
api.animDeath(dfs)
run(0.1)
check("death: shakes", select(4, dfs:GetPoint(1)) ~= -6)
run(1)
check("death: back in place", select(4, dfs:GetPoint(1)) == -6)
local pfs = parent:CreateFontString()
api.animPartyBump(pfs)
run(0.2)
check("party: bumps", (pfs.textScale or 1) > 1)
run(1)
check("party: back", pfs.textScale == 1)
local repRow = methods(obj("Frame"))
api.animFloat(repRow, parent:CreateFontString(), "+250")
check("rep float: shows the gain", repRow.qtsFloat and repRow.qtsFloat.text == "+250")
run(2)
check("rep float: goes away", not repRow.qtsFloat.shown)
local closed = false
db.animOff = { window = true }
api.animWindowClose(methods(obj("Frame")), function() closed = true end)
check("window close off: hides at once", closed)
db.animOff = nil
local keys3 = {}
for _, k in ipairs(api.animKinds) do if k.key then keys3[k.key] = true end end
check("kinds: the fifth set has switches", keys3.deaths and keys3.party and keys3.cap and keys3.repfloat and keys3.abandon and keys3.tilt)

-- the sixth set (3.2, user)
api.animFailFlash()
check("fail flash: runs", effectsOf("failflash") == 1)
run(2)
check("fail flash: ends", effectsOf("failflash") == 0)
local nb = methods(obj("Frame"))
api.animNewBest(nb, "NEW BEST  -0:12")
check("new best: shows the time saved", nb.qtsNewBest and nb.qtsNewBest.text.text == "NEW BEST  -0:12")
run(3)
check("new best: then hides", not nb.qtsNewBest.shown)
local dot = parent:CreateTexture()
api.animRunLight(dot, true)
check("run light: shows while the run goes on", dot.shown)
api.animRunLight(dot, false)
check("run light: hides after", not dot.shown)
db.animOff = { runlight = true }
api.animRunLight(dot, true)
check("run light off: hidden", not dot.shown)
db.animOff = nil
combat = true
api.animRunLight(dot, true)
check("run light: also in combat", dot.shown)
combat = false
local keys4 = {}
for _, k in ipairs(api.animKinds) do if k.key then keys4[k.key] = true end end
check("kinds: the sixth set has switches", keys4.failflash and keys4.runlight and keys4.newbest and keys4.newsglow)

-- set 7 (3.2, user): battlegrounds, corpse, run summary, loot
local keys5 = {}
for _, k in ipairs(api.animKinds) do if k.key then keys5[k.key] = true end end
check("kinds: the seventh set has switches", keys5.bgcapture and keys5.bgpulse and keys5.bgswap and keys5.bgcarrier
	and keys5.bgdrop and keys5.bgqueue and keys5.bgresult and keys5.corpse and keys5.summary and keys5.lootsparkle)
combat = true
local bar = methods(obj("Frame"))
check("bg capture flash: runs in combat", api.animBgCaptured(bar, "Horde") == true and effectsOf("bgcapture") == 1)
run(1)
check("bg capture flash: the bar faded out", effectsOf("bgcapture") == 0 and bar.alpha == 0)
api.animBgReset(bar)
check("bg capture: a reused bar is seen again", bar.alpha == 1)
api.animBgPulse(bar, true)
check("bg last seconds: the red glow shows", bar.qtsLast and bar.qtsLast.shown)
api.animBgPulse(bar, false)
check("bg last seconds: then hides", not bar.qtsLast.shown)
local line = methods(obj("FontString"))
line:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -5)
api.animBgCarrier(line)
run(1)
check("bg carrier shake: back in place", select(4, line:GetPoint(1)) == 10)
api.animBgDrop(line)
run(1)
check("bg drop ping: text back to its size", line.textScale == 1)
combat = false
local num = methods(obj("FontString"))
api.animCountFrom(num, 100, 500, function(v) return tostring(v) end)
check("summary count-up: starts at the last value", num.text == "100")
run(1)
check("summary count-up: ends at the new value", num.text == "500")
db.animOff = { summary = true }
api.animCountFrom(num, 100, 700, function(v) return tostring(v) end)
check("summary count-up off: the number at once", num.text == "700")
db.animOff = nil

if fails > 0 then print("SOME FAILED") else print("ALL OK") end
