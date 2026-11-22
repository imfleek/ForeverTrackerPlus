-- No jitter while running around: a re-sort rebuilds Blizzard's quest blocks, and their plain text showed for a moment
-- (no icons, no wrap, no room for the distance) until the next pass 0.1 s later re-decorated them. New blocks and their
-- objective lines are hooked as Blizzard takes them, and after every tracker update the decorating runs in the same
-- frame (Extras.lua).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
check("a block the quests section takes is hooked at once (GetBlock post-hook)",
	src:find('hooksecurefunc(questModule, "GetBlock", function()', 1, true) ~= nil)
check("a line a block takes is hooked at once (GetLine post-hook), before AddObjective sets its text",
	src:find('hooksecurefunc(block, "GetLine", function(self, key)', 1, true) ~= nil)
check("both only when the client has those methods", src:find('type(questModule.GetBlock) == "function"', 1, true) ~= nil
	and src:find('type(block.GetLine) == "function"', 1, true) ~= nil)

-- hookObjectiveText: hooks once, follows the line to its new block, never the title
local body = src:match("(local function hookObjectiveText%(fs, block%).-\nend\n)")
check("hookObjectiveText found", body ~= nil)
if body then
	local hooks = 0
	local env = setmetatable({ textHooked = {}, applying = false,
		hooksecurefunc = function() hooks = hooks + 1 end }, { __index = _G })
	local hook = load(body .. "\nreturn hookObjectiveText", "x", "t", env)()
	local function text() local f = function() end; return { SetText = f, SetWidth = f, SetWordWrap = f, SetMaxLines = f } end
	local fs, title = text(), text()
	local blockA, blockB = { HeaderText = title }, { HeaderText = text() }
	hook(fs, blockA)
	-- R106-36: also SetWordWrap and SetMaxLines (Blizzard resetting them after the text showed the plain look)
	check("an objective text: its SetText, SetWidth, SetWordWrap and SetMaxLines hooked", hooks == 4 and fs.qtsBlock == blockA)
	hook(fs, blockB)
	check("taken again by another quest: not hooked twice, follows its new quest", hooks == 4 and fs.qtsBlock == blockB)
	hook(title, blockA)
	check("the quest title: left to the title's own hook", hooks == 4)
end

-- R106-35: no decorating pass and re-layout inside Blizzard's tracker Update post-hook (it made the game lag badly)
check("no same-frame pass on tracker updates", src:find("applyNow", 1, true) == nil
	and src:find('hooksecurefunc(ObjectiveTrackerContainerMixin, "Update", schedule)', 1, true) ~= nil)

-- R106-35: at most 3 re-layouts per 2 s from the decorating pass (a text that keeps changing must not re-lay forever)
local capBody = src:match("(local RELAYOUT_MAX, RELAYOUT_WINDOW = 3, 2\n.-\napi%.cappedRelayout = cappedRelayout\n)")
check("the re-layout limit found", capBody ~= nil)
if capBody then
	local now, relayouts = 0, 0
	local env = setmetatable({ api = {}, GetTime = function() return now end,
		relayout = function() relayouts = relayouts + 1 end }, { __index = _G })
	local capped = load(capBody .. "\nreturn cappedRelayout", "x", "t", env)()
	for _ = 1, 10 do capped() end
	check("ten changes in a row: only 3 re-layouts", relayouts == 3)
	now = 2.5
	check("after 2 s: re-layouts again", capped() == true and relayouts == 4)
end
check("the 0.1 s pass uses the limit", src:find('if timed("tracker extras", apply) then timed("tracker extras: layout", cappedRelayout) end', 1, true) ~= nil)
check("/qt debug shows the re-layouts", src:find("re-layouts from decorating", 1, true) ~= nil)

check("the title: width, word wrap and line limit set again by Blizzard are ours again at once",
	src:find('for _, method in ipairs({ "SetWidth", "SetWordWrap", "SetMaxLines" }) do\n\t\tif type(fs[method]) == "function" then hooksecurefunc(fs, method, reshape) end', 1, true) ~= nil)

-- R106-39: a title's width set again by Blizzard after its text: the coins are measured again at once if it moved
check("the title's late width: coins measured again (render) when it moved since they were",
	src:find([[math.abs((fs:GetWidth() or 0) - (fs.qtsCoinW or 0)) > 1 then
			pcall(render, block)]], 1, true) ~= nil
	and src:find("fs.qtsCoinW = fs:GetWidth()", 1, true) ~= nil)
check("/qt debug says what the late pass fixed", src:find("fixed late: %d title text(s)", 1, true) ~= nil)
-- R106-41: the line's font set after its text: the bar and its count follow at once
check("objective text: SetFont and SetFontObject re-place the bar", src:find('for _, method in ipairs({ "SetFont", "SetFontObject" }) do', 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
