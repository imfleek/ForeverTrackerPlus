-- The tracker is moved only through the plain frame methods (Edit Mode's <name>Base), never Edit Mode's Lua versions:
-- those wrote Edit Mode's bookkeeping as addon code, and its next layout pass ran tainted
-- (InvokeOnAnyEditModeSystemAnchorChanged -> GetAuraDataByIndex "cannot be accessed when secret while tainted").
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

-- no direct call of an Edit Mode-replaced method on the tracker anywhere in the addon
local METHODS = { "SetPoint", "ClearAllPoints", "SetScale", "SetParent", "SetAllPoints" }
local found = {}
local p = io.popen('git -C "' .. arg[1] .. '" ls-files --cached --others --exclude-standard -- Tracker Objectives')
for file in p:lines() do
	if file:match("%.lua$") then
		local n = 0
		for line in io.lines(arg[1] .. "/" .. file) do
			n = n + 1
			for _, m in ipairs(METHODS) do
				if line:find("tracker:" .. m .. "(", 1, true) or line:find("ObjectiveTrackerFrame:" .. m .. "(", 1, true) then
					found[#found + 1] = file .. ":" .. n
				end
			end
		end
	end
end
p:close()
check("no tracker:SetPoint/ClearAllPoints/SetScale/SetParent calls (" .. (found[1] or "none") .. ")", #found == 0)

-- moveTracker picks the Base method when Edit Mode has one, else the frame's own
local src = io.open(arg[1] .. "/Tracker/Core.lua"):read("a")
local body = src:match("(local function plain%(method%).-\nns%.api%.moveTracker = moveTracker\n)")
check("moveTracker found in Tracker/Core.lua", body ~= nil)
if body then
	local calls = {}
	local tracker = {
		SetPoint = function() calls[#calls + 1] = "SetPoint (Edit Mode)" end,
		SetPointBase = function(_, point) calls[#calls + 1] = "SetPointBase " .. point end,
		SetHeight = function(_, h) calls[#calls + 1] = "SetHeight " .. h end,
	}
	local env = setmetatable({ tracker = tracker, ns = { api = {} } }, { __index = _G })
	local move = load(body .. "\nreturn moveTracker", "core", "t", env)()
	move("SetPoint", "TOPLEFT")
	check("Edit Mode's SetPoint not called; SetPointBase is", calls[1] == "SetPointBase TOPLEFT" and #calls == 1)
	move("SetHeight", 100)
	check("a method without a Base one: the frame's own", calls[2] == "SetHeight 100")
end
print(pass and "PASS" or "FAILED")
