-- 3.2 world marker new look (Tracker/WorldMarker.lua; art from tests/make_marker.py): the diamond's symbol and colour
-- per target, size by distance, the game's own icon made see-through while ours shows, ours hidden at the screen edge,
-- the beam dimmed when you are there, the hover fade, and no error on a client without animations.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local noop = function() end

local function fake(withAnims)
	local f = { shown = true, alpha = 1, scripts = {}, mouse = false }
	return setmetatable(f, { __index = function(_, k)
		if k == "Show" then return function(self) self.shown = true end
		elseif k == "Hide" then return function(self) self.shown = false end
		elseif k == "SetShown" then return function(self, v) self.shown = v and true or false end
		elseif k == "IsShown" then return function(self) return self.shown end
		elseif k == "SetAlpha" then return function(self, a) self.alpha = a end
		elseif k == "GetAlpha" then return function(self) return self.alpha end
		elseif k == "SetScale" then return function(self, s) self.scale = s end
		elseif k == "SetText" then return function(self, t) self.text = t end
		elseif k == "SetTexture" then return function(self, t) self.tex = t end
		elseif k == "SetVertexColor" then return function(self, r, g, b) self.color = { r, g, b } end
		elseif k == "IsMouseOver" then return function(self) return self.mouse end
		elseif k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end
		elseif k == "RegisterEvent" then return function() return true end
		elseif k == "CreateFontString" or k == "CreateTexture" then return function() return fake(withAnims) end
		elseif k == "CreateAnimationGroup" then
			if not withAnims then return nil end
			return function() return fake(withAnims) end
		elseif k == "CreateAnimation" then return function() return fake(withAnims) end end
		if type(k) == "string" and k:match("^%u") then return noop end
	end })
end

local function run(withAnims)
	local frames = {}
	local nav, yards, clamped, quest, complete = nil, 500, false, 5, false
	local game = { Icon = fake(), DistanceText = fake(), Time = fake() }
	local env = setmetatable({
		CreateFrame = function(_, name) local f = fake(withAnims); frames[#frames + 1] = f; if name then frames[name] = f end; return f end,
		UIParent = fake(), SuperTrackedFrame = game,
		C_Navigation = { GetFrame = function() return nav end, GetDistance = function() return yards end,
			WasClampedToScreen = function() return clamped end },
		C_SuperTrack = { GetSuperTrackedQuestID = function() return quest end, IsSuperTrackingUserWaypoint = function() return quest == 0 end },
		C_QuestLog = { GetTitleForQuestID = function() return "Wolves" end, GetLogIndexForQuestID = function() return 1 end,
			IsComplete = function() return complete end },
		GetNumQuestLeaderBoards = function() return 1 end,
		GetQuestLogLeaderBoard = function() return "Wolf Pelt: 2/6", "item", false end,
		InCombatLockdown = function() return false end, geterrorhandler = function() return function(e) error(e, 0) end end,
		C_Timer = { NewTicker = function() return {} end, After = noop },
	}, { __index = _G })
	env._G = env
	local ns = { api = {}, onLogin = {}, db = {} }
	assert(loadfile(dir .. "/Tracker/WorldMarker.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	for _, fn in ipairs(ns.onLogin) do fn() end
	local m = frames.RXPFTWorldMarker
	local clock = frames[2] -- the marker, its body, then the clock
	for _, f in ipairs(frames) do if f.scripts.OnUpdate then clock = f end end
	local function tick(n) for _ = 1, n or 1 do clock.scripts.OnUpdate(clock, 0.6) end end
	nav = fake(); ns.api.refreshWorldMarker()
	tick()
	return { m = m, tick = tick, game = game, ns = ns,
		set = function(k, v) if k == "yards" then yards = v elseif k == "clamped" then clamped = v
			elseif k == "quest" then quest = v elseif k == "complete" then complete = v end end }
end

for _, withAnims in ipairs({ true, false }) do
	local tag = withAnims and "" or " (no animations)"
	local t = run(withAnims)
	local m = t.m
	check("shown with the quest's name and next step" .. tag, m.alpha == 1 and m.title.text == "Wolves" and m.goal.text == "Wolf Pelt: 2/6")
	check("an objective: the gem, no ?" .. tag, m.gem.shown and not m.mark.shown)
	check("the diamond and the beam use our textures" .. tag, m.diamond.tex:find("MarkerDiamond") and m.beam.tex:find("MarkerBeam") and true)
	check("the game's icon and yards see-through while ours shows" .. tag, t.game.Icon.alpha == 0 and t.game.DistanceText.alpha == 0)
	check("far away (500 yd): small (0.7)" .. tag, math.abs(m.scale - 0.7) < 0.001)
	t.set("yards", 10); t.tick()
	check("close: big (1.15)" .. tag, math.abs(m.scale - 1.15) < 0.001)
	check("there: the beam dims" .. tag, m.beam.alpha < 1)
	t.set("complete", true); t.tick()
	check("turn in: a ? in the diamond" .. tag, m.mark.shown and not m.gem.shown and m.goal.text == "Turn in")
	m.body.mouse = true; t.tick(6)
	check("the mouse over it: it fades" .. tag, m.body.alpha <= 0.31)
	m.body.mouse = false; t.tick(6)
	check("the mouse gone: back" .. tag, m.body.alpha == 1)
	t.set("clamped", true); t.tick()
	check("at the screen edge: ours hides, the game's icon is back" .. tag, m.alpha == 0 and t.game.Icon.alpha == 1)
	t.set("clamped", false); t.set("quest", 0); t.tick()
	check("a map waypoint: shown, blue" .. tag, m.alpha == 1 and m.title.text == "Waypoint" and m.glow.color[3] == 1 and m.glow.color[1] < 1)
	t.ns.db.worldMarker = false; t.ns.api.refreshWorldMarker()
	check("switched off: hidden, the game's icon is back" .. tag, m.alpha == 0 and t.game.Icon.alpha == 1)
end
print(pass and "ALL OK" or "SOME FAILED")
