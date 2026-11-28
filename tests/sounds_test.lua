-- 3.2 (user): one "Sounds" switch mutes every sound of the addon (Bootstrap.lua root.playSound).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local played = 0
local env = setmetatable({ PlaySound = function() played = played + 1 end }, { __index = _G })
local root = {}
assert(loadfile(dir .. "/Bootstrap.lua", "t", env))("ForeverTrackerPlus", root)
check("no settings yet: a sound plays", (root.playSound(env.PlaySound, 8960)) == true and played == 1)
root.tracker.db = {}
root.playSound(env.PlaySound, 8960)
check("Sounds on (default): it plays", played == 2)
root.tracker.db.sounds = false
root.playSound(env.PlaySound, 8960)
check("Sounds off: nothing plays", played == 2)
root.playSound(nil, 8960)
check("no PlaySound: no error", true)

-- every PlaySound in the addon goes through root.playSound
local files = {}
for line in io.lines(dir .. "/ForeverTrackerPlus.toc") do
	local f = line:match("^%s*([%w_/]+%.lua)%s*$")
	if f and (f:find("^Tracker/") or f:find("^Objectives/")) then files[#files + 1] = dir .. "/" .. f end
end
local raw = {}
for _, f in ipairs(files) do
	local h = io.open(f, "rb")
	local s = h and h:read("a") or ""
	if h then h:close() end
	local n = 0
	for line in s:gmatch("[^\n]+") do
		n = n + 1
		local code = line:gsub("%-%-.*$", "")
		local rest = code:gsub("%(root%.playSound or pcall%)%(PlaySound,", "")
		if rest:find("PlaySound%s*%(") or rest:find("pcall%(%s*PlaySound") then raw[#raw + 1] = f .. ":" .. n end
		-- a line that starts with "(" joins the line above in Lua: the call must not open a line
		if code:find("^%s*%(root%.playSound") then raw[#raw + 1] = f .. ":" .. n .. " (starts with a bracket)" end
	end
end
check("files found", #files > 10)
check("no sound skips the switch" .. (#raw > 0 and (": " .. table.concat(raw, ", ")) or ""), #raw == 0)

-- 3.2 (user's BugSack: SendChatMessage blocked): text goes only into a chat box the player opened
local inserted, errs = nil, {}
env.ChatEdit_GetActiveWindow = function() return nil end
env.UIErrorsFrame = { AddMessage = function(_, t) errs[#errs + 1] = t end }
check("chat box closed: nothing opened, a hint to press Enter", root.chatInsert("Farm (Horde): 0:34") == false
	and errs[1] and errs[1]:find("Press Enter", 1, true))
env.ChatEdit_GetActiveWindow = function() return { Insert = function(_, t) inserted = t end } end
check("chat box open: the text goes in", root.chatInsert("Farm (Horde): 0:34") == true and inserted == "Farm (Horde): 0:34")
local opens = {}
for _, f in ipairs(files) do
	local h = io.open(f, "rb"); local s = h and h:read("a") or ""; if h then h:close() end
	local n = 0
	for line in s:gmatch("[^\n]+") do
		n = n + 1
		if line:gsub("%-%-.*$", ""):find("OpenChat") then opens[#opens + 1] = f .. ":" .. n end
	end
end
check("no file opens the chat box itself" .. (#opens > 0 and (": " .. table.concat(opens, ", ")) or ""), #opens == 0)

print(pass and "ALL OK" or "SOME FAILED")
