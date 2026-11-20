-- Quest Tracker scale must never write fields on the scenario module (or any module outside SCALED_MODULES): its
-- layout reads them, runs tainted, and then fails on secret auras in dungeons (Blizzard_MawBuffs ShouldShowMawBuffs ->
-- GetAuraDataByIndex "Auras cannot be accessed when secret while tainted by 'RXPForeverTracker'").
local src = io.open(arg[1] .. "/Tracker/Core.lua"):read("a")
local widths = src:match("(local WIDTH_FIELDS = .-\nlocal function applyModuleWidths%(%).-\n\treturn changed\nend\n)")
local scales = src:match("(local function applyModuleScales%(%).-\n\treturn changed\nend\n)")
assert(widths and scales, "Quest Tracker scale code not found in Tracker/Core.lua")

local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

-- a module records every field written on it after setup (rawset through a proxy)
local function module(width)
	local fields, writes = { lineWidth = width - 20, blockWidth = width }, {}
	local m = { w = width, s = 1 }
	m.GetWidth = function() return m.w end
	m.SetWidth = function(_, v) m.w = v end
	m.GetScale = function() return m.s end
	m.SetScale = function(_, v) m.s = v end
	return setmetatable({}, {
		__index = function(_, k) if fields[k] ~= nil then return fields[k] end return m[k] end,
		__newindex = function(_, k, v) fields[k] = v; writes[k] = true end,
	}), writes, m
end
local quest, questWrites, questFrame = module(240)
local scenario, scenarioWrites, scenarioFrame = module(240)
local widget, widgetWrites = module(240)
_G.QuestObjectiveTracker, _G.ScenarioObjectiveTracker, _G.UIWidgetObjectiveTracker = quest, scenario, widget

local qs = 1.25
local env = setmetatable({
	ns = { api = {} }, tracker = { modules = { scenario, widget, quest } },
	questScale = function() return qs end, guarded = function(f) f() end,
	InCombatLockdown = function() return false end,
}, { __index = _G })
local run = load(widths .. scales .. "\nreturn applyModuleWidths, applyModuleScales, ns.api", "core", "t", env)
local applyWidths, applyScales, api = run()

applyScales(); applyWidths()
check("quest module scaled, with its width fields", questFrame.s == qs and questWrites.lineWidth and questWrites.blockWidth)
check("scenario module: no field written (no taint in its layout)", next(scenarioWrites) == nil)
check("scenario module: scale 1, width its own", scenarioFrame.s == 1 and scenarioFrame.w == 240)
check("widget module: no field written", next(widgetWrites) == nil)
check("an unknown module is not scaled", not api.scaledModule({}))
qs = 1
applyScales(); applyWidths()
check("scale back to 100%: scenario still untouched", next(scenarioWrites) == nil and scenarioFrame.s == 1)
print(pass and "PASS" or "FAILED")
