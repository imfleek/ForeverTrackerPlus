-- 3.1.1: flight times for routes not flown yet: route length from the flight map's stops / a speed that learned
-- flights correct (Helpers.lua)
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
		local f = {}
		function f:SetScript(k, fn) if k == "OnEvent" then handlers[#handlers + 1] = fn end end
		return setmetatable(f, { __index = function() return function() end end })
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
	C_Map = { GetWorldPosFromMapPos = function(_, v)
		return 1, { GetXY = function() return v.x * 1000, v.y * 1000 end } end },
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do pcall(fn) end
local api = ns.api

local e2, e3 = api.flightEstimate(2), api.flightEstimate(3)
check("one-stop route: 500 yd at the start speed", e2 and math.abs(e2 - 500 / 28) < 0.01)
check("two-stop route: both legs counted", e3 and math.abs(e3 - 1000 / 28) < 0.01)
check("no route there: no estimate", api.flightEstimate(1) == nil)
local function enter(slot)
	tip.lines = {}
	hooks.TaxiNodeOnButtonEnter({ GetID = function() return slot end })
	return tip.lines[1] or ""
end
check("tooltip of a route not flown: an 'about' time", enter(3):find("about") ~= nil)

local function fire(ev) for _, h in ipairs(handlers) do pcall(h, nil, ev) end end
-- fly to Middle in 25 s (500 yd: 20 yd/s)
hooks.TakeTaxiNode(2)
taxi = true; fire("PLAYER_CONTROL_LOST")
now = 25; taxi = false; fire("PLAYER_CONTROL_GAINED")
check("flight learned: real time kept", api.flightTime("Here", "Middle") and math.abs(api.flightTime("Here", "Middle") - 25) < 0.01)
check("speed corrected by the flight", math.abs((ns.db.flightSpeed or 0) - 20) < 0.01)
check("route not flown now uses the new speed", math.abs(api.flightEstimate(3) - 1000 / 20) < 0.01)
check("tooltip of a learned route: no 'about'", enter(2):find("about") == nil and enter(2):find("Flight time") ~= nil)

-- R311-8: the game's path data: exact lengths by node ID (slot 1 = node 10, 2 = node 20, 3 = node 30)
ns.flightPathYards = { [100020] = 600, [200030] = 900 }
ns.flightPathWaits = { [200030] = 5 }
env.C_TaxiMap = { GetAllTaxiNodes = function() return { { slotIndex = 1, nodeID = 10 }, { slotIndex = 2, nodeID = 20 }, { slotIndex = 3, nodeID = 30 } } end }
now = 100
local t2, close2 = api.flightEstimate(2)
check("path data: exact length at the start path speed, marked about", math.abs(t2 - 600 / 30.5) < 0.01 and not close2)
local t3 = api.flightEstimate(3)
check("path data: both paths and the wait counted", math.abs(t3 - (1500 / 30.5 + 5)) < 0.01)
ns.flightPathYards[200030] = nil
check("a path missing from the data: the map estimate is used", math.abs(api.flightEstimate(3) - 1000 / 20) < 0.01)
ns.flightPathYards[200030] = 900
-- fly to Far (1500 yd, 5 s wait) in 55 s: path speed 30 yd/s
now = 200; hooks.TakeTaxiNode(3)
taxi = true; fire("PLAYER_CONTROL_LOST")
now = 255; taxi = false; fire("PLAYER_CONTROL_GAINED")
check("a flight on path data corrects the path speed (wait left out)", math.abs((ns.db.flightPathSpeed or 0) - 30) < 0.01)
check("the map speed is not changed by it", math.abs(ns.db.flightSpeed - 20) < 0.01)
local _, closeNow = api.flightEstimate(2)
check("after that flight, path data times are no longer 'about'", closeNow == true)

print(pass and "ALL OK" or "SOME FAILED")
