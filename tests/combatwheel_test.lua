-- R106-50: the mouse wheel scrolls the quest tracker in combat (only a protected section waits)
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Core.lua"):read("a")
local canMoveBody = src:match("(local function canMove%(frame%).-\nend)")
local wheelBody = src:match("(local function onWheel%(_, delta, onBar%).-\nend)")
check("the wheel code found", canMoveBody ~= nil and wheelBody ~= nil)
local combat, protected, moved = true, false, nil
local follower = { IsProtected = function() return protected end }
local env = setmetatable({
	InCombatLockdown = function() return combat end, follower = follower, wheelEvents = 0, offset = 100,
	db = { step = 40 }, scrollMax = function() return 500 end, nearerGuide = function() return false end,
	setOffset = function(v) moved = v end,
}, { __index = _G })
local onWheel = load(canMoveBody .. "\n" .. wheelBody .. "\nreturn onWheel", "w", "t", env)()
onWheel(nil, -1)
check("in combat: one notch down scrolls (offset 100 -> 140)", moved == 140)
moved = nil
protected = true
onWheel(nil, -1)
check("in combat, a protected section: waits", moved == nil)
combat = false
onWheel(nil, 1)
check("out of combat: scrolls as before (100 -> 60)", moved == 60)
print(pass and "PASS" or "FAILED")
