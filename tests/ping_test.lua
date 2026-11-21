-- R106-87: the RXP Tracker's target buttons /ping what they target
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local core = io.open(dir .. "/Objectives/Core.lua"):read("a")
local body = core:match("(function ns%.pingLine%(%).-\nend)")
check("the ping line found", body ~= nil)
local db = {}
local env = setmetatable({ ns = {}, db = db, SLASH_PING1 = "/ping" }, { __index = _G })
env._G = env
load(body, "p", "t", env)()
local pingLine = env.ns.pingLine
check("the client's /ping on the target", pingLine() == "/ping [@target]")
env.SLASH_PING1 = "/anpingen"
check("a localized client: its own word", pingLine() == "/anpingen [@target]")
env.SLASH_PING1 = nil
check("no /ping in the client: no line", pingLine() == nil)
env.SLASH_PING1 = "/ping"
db.targetPing = false
check("option off: no line", pingLine() == nil)
db.targetPing = nil
check("on by default", core:find("targetPing = true,", 1, true) ~= nil)

-- the target button: the line after RestedXP's targeting, once, within the 255-character limit
local action = io.open(dir .. "/Objectives/circle/Action.lua"):read("a")
local block = action:match("(\t\tlocal ping = ns%.pingLine and ns%.pingLine%(%).-\n\t\tend\n)")
check("the button's ping found", block ~= nil)
if block then
	local function run(macro)
		local attrs = { macrotext = macro }
		local button = { GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end }
		local benv = setmetatable({ ns = { pingLine = pingLine }, button = button }, { __index = _G })
		load(block, "b", "t", benv)()
		return attrs.macrotext
	end
	local got = run("/cleartarget\n/targetexact Kobold Miner")
	check("after the targeting", got == "/cleartarget\n/targetexact Kobold Miner\n/ping [@target]")
	check("a redraw does not add a second one", run(got) == got)
	local long = string.rep("x", 245)
	check("a macro near 255 characters: left as it was", run(long) == long)
end
check("its option", io.open(dir .. "/Tracker/Config.lua"):read("a"):find('"Ping what you target"', 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
