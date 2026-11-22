-- 3.1.1 rebrand: ForeverTrackerPlus takes the settings of RXPForeverTracker (its old name) once, stands down while the
-- old copy still runs, and turns the old copy off for the next /reload (Bootstrap.lua).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function run(loadedSet)
	local disabled, said, root = {}, {}, {}
	local env = setmetatable({
		C_AddOns = { IsAddOnLoaded = function(n) return loadedSet[n] or false end,
			DisableAddOn = function(n) disabled[#disabled + 1] = n end },
		C_Timer = { After = function(_, f) f() end },
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) said[#said + 1] = t end },
	}, { __index = _G })
	env._G = env
	return env, root, disabled, said, function() assert(loadfile(dir .. "/Bootstrap.lua", "t", env))("ForeverTrackerPlus", root) end
end

-- the old addon is still installed and on
local env, root, disabled, said, go = run({ RXPForeverTracker = true })
env.RXPForeverTrackerDB = { scale = 1.2, minimap = { hide = true } }
env.RXPForeverTrackerGuideDB = { steps = 5 }
go()
check("tracker settings copied", type(env.ForeverTrackerPlusDB) == "table" and env.ForeverTrackerPlusDB.scale == 1.2
	and env.ForeverTrackerPlusDB.minimap.hide == true)
check("a copy, not the same table", env.ForeverTrackerPlusDB ~= env.RXPForeverTrackerDB)
check("guide settings copied", env.ForeverTrackerPlusGuideDB and env.ForeverTrackerPlusGuideDB.steps == 5)
check("stands down this session", root.disabledAll == true)
check("old addon turned off for the next reload", disabled[1] == "RXPForeverTracker")
check("tells the player", said[1] and said[1]:find("/reload", 1, true) ~= nil)

-- settings already there: never overwritten
env, root, disabled, said, go = run({ RXPForeverTracker = true })
env.RXPForeverTrackerDB = { scale = 1.2 }
env.ForeverTrackerPlusDB = { scale = 0.8 }
go()
check("own settings kept", env.ForeverTrackerPlusDB.scale == 0.8)

-- old addon gone: runs normally
env, root, disabled, said, go = run({})
go()
check("no old addon: runs", not root.disabledAll and #disabled == 0 and #said == 0)

print(pass and "ALL OK" or "SOME FAILED")
