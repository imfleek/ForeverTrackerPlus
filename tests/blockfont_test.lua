local dir = arg[1]
local function fs(file, size, flags)
	local o = { f = file, s = size, fl = flags }
	o.GetFont = function(self) return self.f, self.s, self.fl end
	o.SetFont = function(self, f, s, fl) self.f, self.s, self.fl = f, s, fl end
	return o
end
local title, line, dash, header = fs("Fonts\\FRIZQT__.TTF", 13, ""), fs("Fonts\\FRIZQT__.TTF", 12, "OUTLINE"), fs("Fonts\\FRIZQT__.TTF", 12, "OUTLINE"), fs("Fonts\\FRIZQT__.TTF", 14, "")
local block = { HeaderText = title, usedLines = { a = { Text = line, Dash = dash } } }
local dirty = 0
_G.ObjectiveTrackerFrame = { modules = { { Header = { Text = header }, usedBlocks = { x = { [123] = block } } } },
	MarkDirty = function() dirty = dirty + 1 end, Update = function() end }
_G.hooksecurefunc = function() end
_G.securecallfunction = function(f, ...) return f(...) end
_G.GetTime = function() return 100 end
_G.C_Timer = { After = function() end }
_G.LibStub = nil
local api = {}
local ns = { api = api, onLogin = {}, db = { font = "default" } }
assert(loadfile(dir .. "/Tracker/Fonts.lua"))("x", { tracker = ns, objectives = {} })
api.setFont("arial")
print("Arial: title", title:GetFont(), "| objective", line.f, line.s, line.fl, "| dash", dash.f, "| relayouts", dirty)
title.f = "Fonts\\FRIZQT__.TTF" -- Blizzard reuses the block and resets its title
api.afterTrackerUpdateFonts()
print("after Blizzard reset + update: title", title.f)
api.setFont("default")
print("Game default: title", title:GetFont(), "| objective", line.f, line.s, line.fl)

-- R106-43: Blizzard setting its own font on a tracker text: ours again at once (in the hook), not on the next frame
do
	local hooks = {}
	_G.hooksecurefunc = function(t, name, fn)
		if type(t) == "table" and type(name) == "string" and fn then
			hooks[t] = hooks[t] or {}
			hooks[t][name] = fn
		end
	end
	local function check(l, c) print((c and "ok   " or "FAIL ") .. l) end
	local FRIZ, ARIAL = [[Fonts\FRIZQT__.TTF]], [[Fonts\ARIALN.TTF]]
	local t2 = fs(FRIZ, 13, "")
	t2.SetFontObject = function(self) self.f = FRIZ end
	local api2 = {}
	local ns2 = { api = api2, onLogin = {}, db = { font = "arial" } }
	assert(loadfile(dir .. "/Tracker/Fonts.lua"))("x", { tracker = ns2, objectives = {} })
	api2.keepTrackerFont(t2)
	check("kept text: the chosen font at once", t2.f == ARIAL and t2.s == 13)
	t2:SetFontObject() -- Blizzard reuses the line
	check("Blizzard's font set again: hooked", hooks[t2] and hooks[t2].SetFontObject ~= nil)
	hooks[t2].SetFontObject(t2)
	check("Blizzard's font set again: ours at once, size kept", t2.f == ARIAL and t2.s == 13)
	ns2.db.font = "default"
	hooks[t2].SetFont(t2)
	check("back to Game default: the game's own font", t2.f == FRIZ)
end

-- R106-44: /qt fontlog records font changes and who made them, then prints a summary after 10 s
do
	local function check(l, c) print((c and "ok   " or "FAIL ") .. l) end
	local hooks, onUpdate = {}, nil
	_G.hooksecurefunc = function(t, name, fn) hooks[#hooks + 1] = { t, name, fn } end
	_G.CreateFrame = function() return { SetScript = function(_, _, f) onUpdate = f end } end
	_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	_G.debugstack = function() return "Interface/AddOns/SomeAddon/Thing.lua:42: in function <x>\n" end
	local now = 0
	_G.GetTime = function() return now end
	local line = fs("A", 12, "OUTLINE")
	_G.QuestObjectiveTracker = { usedBlocks = { x = { [1] = { HeaderText = fs("A", 13, ""), usedLines = { a = { Text = line } } } } } }
	local api3 = {}
	local said = {}
	local ns3 = { api = api3, onLogin = {}, db = { font = "default" }, say = function(m) said[#said + 1] = m end }
	assert(loadfile(dir .. "/Tracker/Fonts.lua"))("x", { tracker = ns3, objectives = {} })
	api3.fontLog(ns3.say)
	for _, h in ipairs(hooks) do if h[1] == line and h[2] == "SetFont" then line.f = "B"; h[3](line) end end
	now = 1; onUpdate(nil, 0.1)
	line.f = "C" -- changed with no call seen
	now = 2; onUpdate(nil, 0.1)
	now = 11; onUpdate(nil, 0.1)
	local text = table.concat(said, "\n")
	check("fontlog: a SetFont call is counted with the code that made it", text:find("line:SetFont | SomeAddon/Thing.lua:42 | B 12 OUTLINE", 1, true) ~= nil)
	check("fontlog: a change with no call is counted", text:find("changed with no call seen | B 12 OUTLINE -> C 12 OUTLINE", 1, true) ~= nil)
end

-- R106-48: "Outline quest titles" / "Outline quest objectives": OUTLINE added, kept when Blizzard resets, removed when off
do
	local function check(l, c) print((c and "ok   " or "FAIL ") .. l) end
	local hooks = {}
	_G.hooksecurefunc = function(t, name, fn) hooks[t] = hooks[t] or {}; hooks[t][name] = fn end
	local t4, l4 = fs("F", 13, ""), fs("F", 12, "")
	_G.ObjectiveTrackerFrame = { modules = { { usedBlocks = { x = { [7] = { HeaderText = t4, usedLines = { a = { Text = l4 } } } } } } },
		MarkDirty = function() end }
	local api4 = {}
	local ns4 = { api = api4, onLogin = {}, db = { font = "default", titleOutline = true } }
	assert(loadfile(dir .. "/Tracker/Fonts.lua"))("x", { tracker = ns4, objectives = {} })
	api4.applyBlockFonts()
	check("outline titles on: the title gets OUTLINE, font and size kept", t4.fl == "OUTLINE" and t4.f == "F" and t4.s == 13)
	check("objectives outline off: the objective is untouched", l4.fl == "")
	t4.fl = "" -- Blizzard resets the title's font
	hooks[t4].SetFont(t4)
	check("Blizzard resets the title: outlined again at once", t4.fl == "OUTLINE")
	ns4.db.objectiveOutline = true
	api4.applyBlockFonts()
	check("outline objectives on: the objective gets OUTLINE", l4.fl == "OUTLINE")
	ns4.db.titleOutline, ns4.db.objectiveOutline = false, false
	api4.applyBlockFonts()
	check("both off: the game's own flags back", t4.fl == "" and l4.fl == "")
	local t5 = fs("F", 13, "THICKOUTLINE")
	_G.ObjectiveTrackerFrame.modules[1].usedBlocks.x[8] = { HeaderText = t5, usedLines = {} }
	ns4.db.titleOutline = true
	api4.applyBlockFonts()
	check("a title the game already outlines: left as it is", t5.fl == "THICKOUTLINE")
end
