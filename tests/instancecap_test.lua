-- R106-100: the dungeon card's instance line: instances this hour of the limit, the next free one, the saved lockout
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local handlers
local function frame()
	return setmetatable({}, { __index = function(t, k)
		if k == "SetScript" then return function(_, _, fn) handlers = fn end end
		return function() end
	end })
end
local clock = 100000
local inside, kind, iname, imap = false, "none", "The Deadmines", 36
local units = {}
local saved = {}
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = frame, GetServerTime = function() return clock end,
	IsInInstance = function() return inside, kind end,
	GetInstanceInfo = function() return iname, kind, 1, "Normal", 5, 0, false, imap end,
	UnitExists = function(u) return units[u] ~= nil end, UnitGUID = function(u) return units[u] end,
	strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = p end return table.unpack(out) end,
	INSTANCE_RESET_SUCCESS = "%s has been reset.",
	GetNumSavedInstances = function() return #saved end,
	GetSavedInstanceInfo = function(i) local s = saved[i] return s[1], 1, s[2], 1, true, false, false, false, 5, "Normal", s[3], s[4] end,
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/InstanceCap.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
local api = ns.api
ns.onLogin[1]()
local function fire(e, a) handlers(nil, e, a) end
local function enter(name, map) inside, kind, iname, imap = true, "party", name, map; fire("PLAYER_ENTERING_WORLD") end
local function leave() inside, kind = false, "none"; fire("PLAYER_ENTERING_WORLD") end

check("on by default", api.instanceCapOn() == true)
check("nothing yet: 0 of 10", select(1, api.instanceCap()) == 0 and select(2, api.instanceCap()) == 10)
enter("The Deadmines", 36)
check("entering a dungeon: 1 counted", api.instanceCap() == 1)
units.target = "Creature-0-1-36-555-639-0001"
fire("PLAYER_TARGET_CHANGED")
leave(); clock = clock + 60; enter("The Deadmines", 36)
check("back into the same copy: still 1", api.instanceCap() == 1)
units.target = "Creature-0-1-36-777-639-0002"
fire("PLAYER_TARGET_CHANGED")
check("a new copy's creature (other zone id): 2", api.instanceCap() == 2)
leave()
fire("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
clock = clock + 60; enter("The Deadmines", 36)
check("after the reset message: a new run, 3", api.instanceCap() == 3)
leave()
for i = 1, 7 do clock = clock + 30; enter("Dungeon " .. i, 100 + i); leave() end
local count, limit, wait = api.instanceCap()
check("10 of 10: at the limit, a wait given", count == 10 and limit == 10 and type(wait) == "number" and wait > 0)
local text = api.instanceCapText("The Deadmines")
check("the line: red count and 'next in'", text:find("|cffff404010/10|r", 1, true) ~= nil and text:find("next in", 1, true) ~= nil)
clock = clock + 3600
check("an hour later: under the limit again", api.instanceCap() < 10)
saved[1] = { "The Deadmines", 2 * 86400 + 4 * 3600 + 30, 5, 2 }
check("saved lockout in the line", api.instanceCapText("The Deadmines"):find("Saved 2/5, resets 2d 4h", 1, true) ~= nil)
check("no lockout for another dungeon", api.savedLockout("Wailing Caverns") == nil)
-- NovaInstanceTracker loaded: its count wins
env.NIT = { hourlyLimit = 10, getInstanceLockoutInfo = function() return 4, 6, clock - 100, 0 end }
local c2, _, _, src = api.instanceCap()
check("NovaInstanceTracker's count used when loaded", c2 == 4 and src == "NovaInstanceTracker")
env.NIT = nil
clock = clock + 2 * 86400
fire("PLAYER_ENTERING_WORLD")
leave(); enter("Scarlet Monastery", 44)
check("runs older than a day pruned", #ns.db.instanceRuns <= 2)
ns.db.instanceCap = false
check("option off", api.instanceCapOn() == false)
local src2 = io.open(dir .. "/ForeverTrackerPlus.toc"):read("a")
check("in the toc", src2:find("Tracker/InstanceCap.lua", 1, true) ~= nil)
print(pass and "PASSED" or "FAILED")
