-- 3.2: flight times come from RestedXP's flight time list (RXP.FPDB), the bar closes on landing (Helpers.lua)
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

-- flight map: slot 1 = here (0,0), slot 2 = (0.3,0.4) [500 yd], slot 3 = (0.6,0.8) [another 500 yd]; route to 3 goes via 2
local P = { [1] = { 0, 0 }, [2] = { 0.3, 0.4 }, [3] = { 0.6, 0.8 } }
local HOPS = { [2] = { { 1, 2 } }, [3] = { { 1, 2 }, { 2, 3 } } }
local hooks, now, taxi, handlers = {}, 0, false, {}
local ns = { api = {}, onLogin = {}, db = {} }
local tip = { lines = {} }
function tip:IsShown() return true end
function tip:AddLine(t) self.lines[#self.lines + 1] = t end
function tip:Show() end
local env = setmetatable({
	CreateFrame = function()
		local function stub() return setmetatable({}, { __index = function() return function() return stub() end end }) end
		local f = {}
		function f:SetScript(k, fn) if k == "OnEvent" then handlers[#handlers + 1] = fn end end
		return setmetatable(f, { __index = function() return function() return stub() end end })
	end,
	C_Timer = { NewTicker = function() return {} end, After = function(_, f) f() end },
	UIParent = {}, StaticPopupDialogs = {}, GameTooltip = tip,
	GetTime = function() return now end,
	UnitOnTaxi = function() return taxi end,
	hooksecurefunc = function(name, fn) if type(name) == "string" then hooks[name] = fn end end,
	TakeTaxiNode = function() end, TaxiNodeOnButtonEnter = function() end,
	NumTaxiNodes = function() return 3 end,
	TaxiNodeName = function(i) return ({ "Here", "Middle", "Far" })[i] end,
	TaxiNodeGetType = function(i) return i == 1 and "CURRENT" or "REACHABLE" end,
	GetNumRoutes = function(i) return HOPS[i] and #HOPS[i] or 0 end,
	TaxiGetNodeSlot = function(i, h, src) local hop = HOPS[i][h]; return src and hop[1] or hop[2] end,
	TaxiNodePosition = function(s) return P[s][1], P[s][2] end,
	GetTaxiMapID = function() return 1414 end,
	CreateVector2D = function(x, y) return { x = x, y = y } end,
	TaxiGetDestX = function(i, h) return 0 end, TaxiGetDestY = function(i, h) return 0 end,
	RXP = { player = { faction = "Alliance" },
		-- node IDs: here 11, middle 12, far 13; Middle listed one way only (far > here is not listed, so legs)
		FPDB = { Alliance = { [12] = { [11] = 40 }, [13] = { [12] = 70 } } },
		flightInfo = { currentFP = 11, nodeHash = { [2] = 12, [3] = 13 } },
		GetFlightHash = function(i, level) if level then return HOPS[i][level][2] end return i end,
		settings = { profile = { showFlightTimers = false } } },
	C_Map = { GetWorldPosFromMapPos = function(_, v)
		return 1, { GetXY = function() return v.x * 1000, v.y * 1000 end } end },
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do pcall(fn) end

local api = ns.api
local rxp = env.RXP
check("listed the other way: RestedXP's time", api.rxpFlightTime(2) == 40)
check("not listed: the legs added up", api.rxpFlightTime(3) == 110)
check("no route: no time", api.rxpFlightTime(1) == nil)

tip.lines = {}
api.flightTipEnter({ GetID = function() return 3 end })
check("map tooltip: RestedXP's time", tip.lines[1] == "Flight time: 1:50" or (tip.lines[1] or ""):find("Flight time:", 1, true) == 1)
env.C_AddOns = { IsAddOnLoaded = function(n) return n == "RXPGuides" end }
tip.lines = {}
api.flightTipEnter({ GetID = function() return 3 end })
check("RXPGuides installed: no flight map line of ours", #tip.lines == 0)
env.C_AddOns = nil

-- a flight: the bar closes on landing even when UnitOnTaxi is still true at PLAYER_CONTROL_GAINED
local after = {}
env.C_Timer.After = function(_, f) after[#after + 1] = f end
hooks.TakeTaxiNode(2)
check("flight started: RestedXP's time kept", api.flightNow() and api.flightNow().total == 40)
taxi = true
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_LOST") end
for _, f in ipairs(after) do f() end
after = {}
now = 40
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_GAINED") end
check("still on the taxi at the event: a recheck is set", #after > 0)
taxi = false
for _, f in ipairs(after) do f() end
check("off the taxi: flight closed", api.flightNow() == nil)
local src = io.open(dir .. "/Tracker/Helpers.lua"):read("a")
check("bar closes in OnUpdate once off the taxi", src:find('UnitOnTaxi and not UnitOnTaxi("player") then api.flightLanded() return end', 1, true) ~= nil)
check("40 s on an 18 s route (too long): not learned", not (ns.db.flightLog and ns.db.flightLog["Here > Middle"]))
env.RXP = nil
check("no RestedXP: no time from its list", api.rxpFlightTime(2) == nil)

-- without RXPGuides: path data estimate, then the learned time
local e2, close2 = api.flightEstimate(2)
check("no path data: map estimate marked about", e2 and math.abs(e2 - 500 / 28) < 0.01 and close2 == false)
tip.lines = {}
api.flightTipEnter({ GetID = function() return 2 end })
check("no RXPGuides: our flight map line, about", (tip.lines[1] or ""):find("about", 1, true) ~= nil)
ns.api.flightNow()
after = {}
now = 100
hooks.TakeTaxiNode(2)
check("no RXPGuides: bar uses our estimate", api.flightNow() and math.abs(api.flightNow().total - 500 / 28) < 0.01)
taxi = true
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_LOST") end
for _, f in ipairs(after) do f() end
after = {}
now = 118
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_GAINED") end
now = 200; taxi = false
for _, f in ipairs(after) do f() end
local log = ns.db.flightLog and ns.db.flightLog["Here > Middle"]
check("landing time is the event's time, not the recheck's", log and math.abs(log.t - 18) < 0.01)
tip.lines = {}
api.flightTipEnter({ GetID = function() return 2 end })
check("learned route: no about", tip.lines[1] and not tip.lines[1]:find("about", 1, true))
-- a flight with ground time counted: not learned
after = {}
now = 300
hooks.TakeTaxiNode(2)
taxi = true
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_LOST") end
for _, f in ipairs(after) do f() end
after = {}
now = 300 + 828
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_GAINED") end
taxi = false
for _, f in ipairs(after) do f() end
check("an 828 s flight on an 18 s route is not learned", math.abs(ns.db.flightLog["Here > Middle"].t - 18) < 0.01)
check("bad old data cleared once", ns.db.flightFix32 == true)

-- druid flight from Moonglade (chat option of Bunthen Plainswind, no TakeTaxiNode)
ns.flightPathYards = ns.flightPathYards or {}
ns.flightPathYards[630022] = 3030
env.UnitGUID = function() return "Creature-0-1-2-3-4-11798-0000" end
env.UnitName = function() return "Bunthen Plainswind" end
after = {}
now = 1000; taxi = false
for _, h in ipairs(handlers) do pcall(h, nil, "GOSSIP_SHOW") end
now = 1005; taxi = true
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_LOST") end
for _, f in ipairs(after) do f() end
local df = api.flightNow()
check("druid flight: bar started to Thunder Bluff", df and df.started and df.to == "Thunder Bluff, Mulgore")
check("druid flight: time from the path data", df and math.abs(df.total - 3030 / 30.3) < 0.01 and df.close)
after = {}
now = 1105
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_GAINED") end
taxi = false
for _, f in ipairs(after) do f() end
check("druid flight: closed and learned", api.flightNow() == nil and ns.db.flightLog["Nighthaven, Moonglade > Thunder Bluff, Mulgore"] ~= nil)
-- another NPC's chat, then a taxi: no druid flight
env.UnitGUID = function() return "Creature-0-1-2-3-4-12345-0000" end
env.UnitName = function() return "Someone" end
for _, h in ipairs(handlers) do pcall(h, nil, "GOSSIP_SHOW") end
taxi = true
for _, h in ipairs(handlers) do pcall(h, nil, "PLAYER_CONTROL_LOST") end
check("other NPC: no flight bar", api.flightNow() == nil)
taxi = false

-- Mount Hyjal: paths to or from Tainted Foothills (node 3242) fly at 48 yd/s
ns.flightPathYards[32420559] = 1849
env.GetTaxiMapID = function() return 1 end
env.C_TaxiMap = { GetAllTaxiNodes = function() return { { slotIndex = 1, nodeID = 3242 }, { slotIndex = 2, nodeID = 559 } } end }
env.GetTime = function() return 5000 end -- a fresh node list
local hy, hyClose = api.flightEstimate(2)
check("Hyjal path: 1849 yd at 48 yd/s (38 s, RestedXP 38 s)", hy and math.abs(hy - 1849 / 48) < 0.01 and hyClose)
env.C_TaxiMap = nil

-- flight log
local log = ns.db.flightHistory
check("flight log: landed flights saved, newest first", type(log) == "table" and #log >= 3 and log[1].to == "Thunder Bluff, Mulgore")
check("flight log: druid flight has our time and the real time", log[1].ours == math.floor(3030 / 30.3 + 0.5) and log[1].real == 100 and log[1].stops == 0)
local bad
for _, e in ipairs(log) do if e.real == 828 then bad = e end end
check("flight log: a time not learned is still logged", bad ~= nil and not bad.learned)
local lines = api.flightLogLines()
check("flight log text: one line per flight", #lines == 3 + #log and lines[4]:find("Thunder Bluff, Mulgore  stops 0  ours 100  rxp -  real 100  diff +0", 1, true) ~= nil)
for i = 1, 60 do api.logFlight({ from = "A", to = "B", guess = 10 }, 10, true) end
check("flight log: keeps the last 50", #ns.db.flightHistory == 50)
ns.db.flightHistoryOff = true
api.logFlight({ from = "C", to = "D" }, 10, true)
check("flight log off: nothing saved", ns.db.flightHistory[1].from == "A")

print(pass and "ALL OK" or "SOME FAILED")
