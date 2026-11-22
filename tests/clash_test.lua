-- 3.1.1: OneForAll's reward coin or EllesmereUI's Flight Timer on as well as ours: the player is asked which to keep
-- (Helpers.lua). "Use ours" turns the other addon's switch off; "Keep theirs" turns ours off.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local on, shown, said = {}, {}, {}
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
	C_AddOns = { IsAddOnLoaded = function(n) return on[n] or false end },
	C_Timer = { NewTicker = function() return {} end, After = function() end },
	UIParent = {}, StaticPopupDialogs = {},
	StaticPopup_Show = function(which, text, _, data) shown[#shown + 1] = { which = which, text = text, data = data } end,
	DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end },
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("RXPForeverTracker", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do pcall(fn) end
local api, popup = ns.api, env.StaticPopupDialogs.RXPFT_ADDON_CLASH
local function click(button) local s = table.remove(shown, 1); if button == 1 then popup.OnAccept(nil, s.data) else popup.OnCancel(nil, s.data, "clicked") end end

api.checkAddonClashes()
check("no other addon: nothing asked", #shown == 0)
on.OneForAll, on.EllesmereUIForeverEssentials = true, true
env.OneForAllDB = { qol = {} }
env.EllesmereUIDB = {}
api.checkAddonClashes()
check("both on: the coin is asked first", #shown == 1 and shown[1].text:find("OneForAll") ~= nil)
check("popup has the right buttons", popup.button1 == "Use ours" and popup.button2 == "Keep theirs")
click(1)
check("Use ours: OneForAll's coin off, ours still on", env.OneForAllDB.qol.questSellCoin == false and ns.db.rewardHint ~= false)
check("then the flight timer is asked", #shown == 1 and shown[1].text:find("EllesmereUI") ~= nil)
click(2)
check("Keep theirs: our flight times off, theirs untouched", ns.db.flightTimes == false and env.EllesmereUIDB.flightTimer == nil)
api.checkAddonClashes()
check("asked again later: nothing (one of each pair is off)", #shown == 0)
ns.db.flightTimes = true
api.checkAddonClashes("flightTimes")
check("our switch turned on again: asked again", #shown == 1)
popup.OnCancel(nil, table.remove(shown, 1).data, "override")
check("popup closed some other way: nothing changes", ns.db.flightTimes == true and env.EllesmereUIDB.flightTimer == nil)
env.OneForAllDB = "broken"
check("odd saved data: no error", pcall(api.checkAddonClashes))

print(pass and "ALL OK" or "SOME FAILED")
