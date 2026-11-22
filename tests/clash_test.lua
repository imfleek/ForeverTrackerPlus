-- 3.1.1: our reward coin and flight display step aside when OneForAll or EllesmereUI already shows them (Helpers.lua)
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local on = {}
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
	C_AddOns = { IsAddOnLoaded = function(n) return on[n] or false end },
	C_Timer = { NewTicker = function() return {} end, After = function() end },
	UIParent = {}, StaticPopupDialogs = {},
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("RXPForeverTracker", { tracker = ns })
local other = ns.api.helperOtherAddon

check("no other addon: ours shows", not other("rewardHint") and not other("flightBar") and not other("flightTip"))
on.OneForAll = true
check("OneForAll, coin not set (its default on): ours steps aside", other("rewardHint") == "OneForAll")
env.OneForAllDB = { qol = { questSellCoin = false } }
check("OneForAll coin switched off: ours shows", other("rewardHint") == nil)
env.OneForAllDB.qol.questSellCoin = true
check("OneForAll coin on: ours steps aside", other("rewardHint") == "OneForAll")
on.EllesmereUIForeverEssentials = true
check("EllesmereUI loaded, timer not set (its default on): our bar steps aside", other("flightBar") == "EllesmereUI")
env.EllesmereUIDB = { flightTimer = { enabled = false } }
check("EllesmereUI timer off: our bar shows", other("flightBar") == nil)
check("EllesmereUI map time is always on: our tooltip line steps aside", other("flightTip") == "EllesmereUI")
env.EllesmereUIDB = "broken"
check("odd saved data: no error", other("flightBar") == "EllesmereUI")

print(pass and "ALL OK" or "SOME FAILED")
