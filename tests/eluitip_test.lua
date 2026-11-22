-- 3.1.1: EllesmereUI's flight map time (no switch) is rewritten with ours: one line, our time (Helpers.lua)
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local env
local afters, showHooks, eluiHasRoute = {}, {}, true
local tip = { lines = {}, shown = true, owner = nil }
local function line(t) local fs = { text = t }; function fs:GetText() return self.text end; function fs:SetText(v) self.text = v end
	function fs:SetTextColor() end; return fs end
function tip:IsShown() return self.shown end
function tip:GetOwner() return self.owner end
function tip:GetName() return "GameTooltip" end
function tip:NumLines() return #self.lines end
function tip:AddLine(t) self.lines[#self.lines + 1] = line(t); rawset(env, "GameTooltipTextLeft" .. #self.lines, self.lines[#self.lines]) end
function tip:Show() for _, h in ipairs(showHooks) do h(self) end end
env = setmetatable({
	CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
	C_Timer = { NewTicker = function() return {} end, After = function(_, f) afters[#afters + 1] = f end },
	UIParent = {}, StaticPopupDialogs = {}, GameTooltip = tip,
	C_AddOns = { IsAddOnLoaded = function(n) return n == "EllesmereUIForeverEssentials" end },
	EllesmereUI = { Lf = function(s) return s end },
	hooksecurefunc = function(t, name, fn) if t == tip and name == "Show" then showHooks[#showHooks + 1] = fn end end,
	NumTaxiNodes = function() return 2 end,
	TaxiNodeName = function(i) return ({ "Here", "There" })[i] end,
	TaxiNodeGetType = function(i) return i == 1 and "CURRENT" or "REACHABLE" end,
}, { __index = _G })
env._G = env
local ns = { api = {}, onLogin = {}, db = { flightLog = { ["Here > There"] = { t = 95, n = 1 } } } }
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do pcall(fn) end
local button = { GetID = function() return 2 end }
local function eluiAdds() tip:AddLine("Flight time: 1:40"); tip:Show() end
local function hover(eluiFirst)
	tip.lines, tip.owner, afters = {}, button, {}
	tip:AddLine("There")
	if eluiFirst and eluiHasRoute then eluiAdds() end
	ns.api.flightTipEnter(button)
	if not eluiFirst and eluiHasRoute then eluiAdds() end
	for _, f in ipairs(afters) do f() end
end
local function texts() local o = {}; for _, l in ipairs(tip.lines) do o[#o + 1] = l.text end return table.concat(o, " | ") end

hover(true)
check("EllesmereUI first: its line now has our time", #tip.lines == 2 and tip.lines[2].text:find("Flight time:") and not tip.lines[2].text:find("1:40"))
hover(false)
check("ours first: its line is rewritten when it shows", #tip.lines == 2 and not texts():find("1:40"))
eluiHasRoute = false
hover(false)
check("EllesmereUI has no line: ours is added", #tip.lines == 2 and tip.lines[2].text:find("Flight time:") ~= nil)
print(pass and "ALL OK" or "SOME FAILED")
