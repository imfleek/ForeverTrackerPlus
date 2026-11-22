-- 3.1.2 Run analysis "Where the time went": eating/drinking, looting, loading screens, casting, falling (apart from
-- jumping), map/quest log while standing, NPC time by window (a dropdown, closed by default) and the dungeon tile.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local handlers, buttons = {}, {}
local function frame(kind)
	local f = {}
	return setmetatable(f, { __index = function(t, k)
		if k == "SetScript" then return function(_, name, fn)
			if name == "OnEvent" then handlers[#handlers + 1] = fn else rawset(t, "on" .. name, fn) end
		end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return frame() end end
		if k == "IsEventRegistered" then return function() return true end end
		return function() end
	end })
end
local now, wall = 1000, 5000000
local tickers, hooks = {}, {}
local st = { speed = 0, fall = false, level = 20, cast = nil, buffs = {}, inst = false }
local senv
senv = setmetatable({
	CreateFrame = function(kind) local f = frame(kind); if kind == "Button" then buttons[#buttons + 1] = f end return f end,
	GetTime = function() return now end, time = function() return wall end,
	C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn return { Cancel = function() end } end, After = function() end },
	UnitName = function() return "Jugo" end, GetRealmName = function() return "Realm" end,
	UnitClass = function() return "Warlock", "WARLOCK" end,
	UnitLevel = function() return st.level end, UnitXP = function() return 0 end, UnitXPMax = function() return 1000 end,
	UnitIsDeadOrGhost = function() return false end, UnitOnTaxi = function() return false end,
	UnitAffectingCombat = function() return false end, UnitIsAFK = function() return false end,
	GetUnitSpeed = function() return st.speed end, IsMounted = function() return false end,
	IsSwimming = function() return false end, IsFalling = function() return st.fall end,
	UnitCastingInfo = function() if st.cast then return table.unpack(st.cast) end end,
	UnitChannelInfo = function() end,
	C_Spell = { GetSpellInfo = function(id) if id == 433 then return { name = "Essen" } end end },
	C_UnitAuras = { GetBuffDataByIndex = function(_, i) local n = st.buffs[i]; if n then return { name = n } end end },
	IsInInstance = function() if st.inst then return true, "party" end return false, "none" end,
	GetMoney = function() return 0 end, GetNumLootItems = function() return 0 end,
	GetMaxPlayerLevel = function() return 60 end, JumpOrAscendStart = function() end,
	hooksecurefunc = function(a, b, c) if type(a) == "string" then hooks[a] = b else hooks[b] = c end end,
	RequestTimePlayed = function() end, GetRealZoneText = function() return "Elwynn Forest" end,
	C_QuestLog = {}, DEFAULT_CHAT_FRAME = { AddMessage = function() end }, NUM_CHAT_WINDOWS = 0,
	StaticPopupDialogs = {}, wipe = function(t) for k in pairs(t) do t[k] = nil end end,
}, { __index = _G })
senv._G = senv
local sns = { api = {}, onLogin = {}, db = {} }
assert(loadfile(dir .. "/Tracker/Stats.lua", "t", senv))("ForeverTrackerPlus", { tracker = sns })
local sapi = sns.api
for _, fn in ipairs(sns.onLogin) do fn() end
local function fire(e, ...) for _, h in ipairs(handlers) do h(nil, e, ...) end end
local function tick(n) for _ = 1, n do now = now + 1; for _, t in ipairs(tickers) do pcall(t) end end end
local function show(name, on) rawset(senv, name, on and { IsShown = function() return true end } or nil) end

tick(1)
st.buffs = { "Mark of the Wild", "Food" }; tick(3); st.buffs = {}
st.buffs = { "Essen" }; tick(2); st.buffs = {}
fire("LOOT_OPENED"); tick(2); fire("LOOT_CLOSED")
st.cast = { "Hearthstone", "", 0, 0, 0, false, 1, false, 8690 }; tick(3); st.cast = nil
st.fall = true; tick(3); st.fall = false
hooks.JumpOrAscendStart(); st.fall = true; tick(1); st.fall = false
show("WorldMapFrame", true); tick(2)
st.speed = 7; tick(1); st.speed = 0 -- moving with the map open is running
show("WorldMapFrame", false)
show("QuestLogFrame", true); tick(1); show("QuestLogFrame", false)
show("MerchantFrame", true); tick(4); show("MerchantFrame", false)
show("MailFrame", true); tick(2); show("MailFrame", false)
show("GossipFrame", true); tick(1); show("GossipFrame", false)
fire("LOADING_SCREEN_ENABLED"); now = now + 20; tick(1); fire("LOADING_SCREEN_DISABLED"); tick(1)
fire("LOADING_SCREEN_ENABLED"); now = now + 900; fire("LOADING_SCREEN_DISABLED")
st.inst = true; tick(5); st.inst = false

local rec = sapi.statsRun().levels[20]
local t = rec.t
local function s(v) return math.floor((v or 0) + 0.5) end
check("eating: a Food buff, and the game's own name for it", s(t.eat) == 5)
check("looting while a loot window is open", s(t.loot) == 2)
check("casting out of combat", s(t.cast) == 3)
check("falling apart from jumping", s(t.fall) == 3 and s(t.jump) == 1)
check("map or quest log open while standing", s(t.map) == 3 and s(t.walk) == 1)
check("NPC time stays one state", s(t.npc) == 7)
check("NPC time by window", s(rec.npc.vendor) == 4 and s(rec.npc.mail) == 2 and s(rec.npc.quest) == 1)
check("loading screens: the whole time, at most 5 minutes, no ticks meanwhile", s(t.load) == 21 + 300 or print(t.load))
check("dungeon time on top of the state", s(rec.dungeon) == 5 and s(t.idle) >= 5)

local bars = sapi.statsTimeBars()
local names, npcRow = {}, nil
for i, b in ipairs(bars) do names[i] = b[1]; if b.key == "npc" then npcRow = b end end
local joined = table.concat(names, ",")
for _, want in ipairs({ "Eating/drinking", "Looting", "Casting", "Falling", "Map/quest log", "Loading screens" }) do
	check("bar: " .. want, joined:find(want, 1, true) ~= nil)
end
check("NPCs row has a dropdown of windows", npcRow and #npcRow.kids == 3 and npcRow.kids[1][1] == "Vendors"
	and npcRow.kids[1][3] > 0.5 and npcRow.kids[1][3] < 0.6)
local run = sapi.statsRunTiles()
check("an In dungeons tile", run[#run][3] == "In dungeons" and run[#run][2] == "0:05")
check("discord text: dungeon time", sapi.statsDiscordText():find("0:05 in dungeons", 1, true) ~= nil)

-- older NPC time with no split
sapi.statsRun().levels[19] = { t = { npc = 60 } }
for _, b in ipairs(sapi.statsTimeBars()) do if b.key == "npc" then npcRow = b end end
check("old NPC time shows as not split", npcRow.kids[#npcRow.kids][1]:find("Not split", 1, true) ~= nil)

-- the widget: the dropdown is closed until its row is clicked
local declared = {}
local kit = { page = function() end, heading = function() end, check = function() end, help = function() end,
	note = function() end, buttons = function() end, choice = function() end, input = function() end,
	custom = function(label, make) declared[#declared + 1] = { label, make } end,
	pageByKey = setmetatable({}, { __index = function(tt, k) local p = {}; rawset(tt, k, p) return p end }),
	declared = { {} }, reset = function() end }
local refreshed = 0
kit.refresh = function() refreshed = refreshed + 1 end
sapi.declareStatsPages(kit)
local make
for _, d in ipairs(declared) do if d[1]:find("vendors", 1, true) then make = d[2] end end
check("the bars widget is declared", make ~= nil)
local C = setmetatable({}, { __index = function() return { 1, 1, 1 } end })
local themeKit = { C = C, ts = function() return 1 end, text = function() return frame() end, solid = function() return frame() end,
	hGradient = function() end, arrow = function() return frame() end, refreshFonts = function() end }
buttons = {}
local w = make(frame(), themeKit)
local closedH = w.draw(400)
check("one toggle button for NPCs", #buttons == 1)
buttons[1].onOnClick()
check("a click lays the page out again", refreshed == 1)
local openH = w.draw(400)
check("open: the window rows add height", openH > closedH)
buttons[1].onOnClick()
check("a second click closes it", w.draw(400) == closedH)

-- Level splits: tiles and bars
local r = sapi.statsRun()
r.reached = { [17] = 1000, [18] = 1600, [19] = 1900, [20] = 2800 }
r.played = 3000
sns.db.statsCompare = "Other-Realm"
sns.db.statsRuns["Other-Realm"] = { reached = { [17] = 0, [18] = 500, [19] = 1000, [20] = 1500 }, levels = {} }
local st2 = sapi.statsSplitTiles()
local function tileBy(label) for _, x in ipairs(st2) do if x[3]:find(label, 1, true) then return x end end end
check("splits: Played tile", tileBy("Played") ~= nil)
check("splits: fastest and slowest level", tileBy("Fastest: level 18") and tileBy("Slowest: level 19") and true or false)
check("splits: average level", tileBy("Average level")[2] == "10:00")
check("splits: behind the compared run, in red", tileBy("Behind") and tileBy("Behind")[2]:find("+5:00", 1, true) ~= nil)
local rows = sapi.statsSplitRows()
check("splits: newest level first, marked now", rows[1][1]:find("Level 20", 1, true) and rows[1][1]:find("now", 1, true) and rows[1][6] == true)
local r19
for _, x in ipairs(rows) do if x[1] == "Level 19" then r19 = x end end
check("splits: the slowest level fills its bar, red with a diff", r19 and r19[3] == 1 and r19[5] ~= nil and r19[2]:find("+6:40", 1, true) ~= nil)
check("splits: the compared run as a second bar", r19 and r19[4] and r19[4] > 0.5 and r19[4] < 0.6)
local splitMake
for _, d in ipairs(declared) do if d[1] == "Level splits" then splitMake = d[2] end end
check("splits widget draws", splitMake and splitMake(frame(), themeKit).draw(400) > 40)

print(pass and "ALL OK" or "SOME FAILED")
