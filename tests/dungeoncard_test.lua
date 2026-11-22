-- R106-84: the dungeon card at the top of the tracker (Delves look): "Dungeon"/"Raid", the instance's name, the
-- group's size on the banner, the group's deaths by the skull, and DungeonJournal's window inside it
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local all = {}
local function frame(name)
	local f = { name = name, points = {}, shown = true, alpha = 1, scale = 1, w = 100, h = 10, scripts = {}, mouse = true,
		movable = true }
	local methods = {
		ClearAllPoints = function(self) self.points = {} end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		GetNumPoints = function(self) return #self.points end,
		GetPoint = function(self, i) return table.unpack(self.points[i]) end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end, SetShown = function(self, v) self.shown = v and true or false end,
		SetAlpha = function(self, a) self.alpha = a end, SetScale = function(self, s) self.scale = s end,
		GetScale = function(self) return self.scale end,
		SetParent = function(self, p) self.parent = p end, GetParent = function(self) return self.parent end,
		EnableMouse = function(self, v) self.mouse = v end,
		SetMovable = function(self, v) self.movable = v end, IsMovable = function(self) return self.movable end,
		SetSize = function(self, w, h) self.w, self.h = w, h end, GetWidth = function(self) return self.w end,
		SetHeight = function(self, h) self.h = h end, GetHeight = function(self) return self.h end,
		GetSize = function(self) return self.w, self.h end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		GetEffectiveScale = function() return 1 end, GetLeft = function() return 100 end,
		GetFrameStrata = function() return "MEDIUM" end, GetFrameLevel = function() return 1 end,
		CreateFontString = function() return frame("text") end, CreateTexture = function() return frame("tex") end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		GetFont = function() return "font", 12, "" end,
		SetBackdropColor = function(self, ...) self.bg = { ... } end, GetBackdropColor = function(self) return table.unpack(rawget(self, "bg") or { 0.07, 0.065, 0.06, 0.88 }) end,
		SetBackdropBorderColor = function(self, ...) self.border = { ... } end,
		GetBackdropBorderColor = function(self) return table.unpack(rawget(self, "border") or { 0.48, 0.40, 0.27, 1 }) end,
	}
	all[#all + 1] = f
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end
local function hasText(t) for _, f in ipairs(all) do if rawget(f, "text") == t then return true end end return false end

-- DungeonJournal's window, where its own code put it
local fdjWin = frame("ForeverDungeonJournalRunTracker")
fdjWin.parent = "UIParent"
fdjWin.points = { { "TOPRIGHT", "UIParent", "TOPRIGHT", -260, -220 } }
fdjWin.h = 160
for _, k in ipairs({ "logo", "title", "reset", "close", "grip", "handle", "line" }) do fdjWin[k] = frame(k) end
local hooks = {}
local blank
local FDJ = { RunLog = { Current = function() return nil end }, UpdateRunTracker = function() end,
	CurrentDungeon = function() return "Deadmines" end, StartBlankRun = function(run) blank = run end }
local cdb = { runTracker = {} }

local inside, kind, members = true, "party", 4
local dead = {}
local units = { player = "Me", party1 = "Ana", party2 = "Bo", party3 = "Cy" }
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function(_, name) return frame(name) end, UIParent = frame("UIParent"),
	IsInInstance = function() return inside, kind end,
	GetInstanceInfo = function() return "The Deadmines", kind, 1, "Normal", 5, 0, false, 36 end,
	GetNumGroupMembers = function() return members end, IsInRaid = function() return false end,
	UnitExists = function(u) return units[u] ~= nil end, UnitName = function(u) return units[u] end,
	UnitIsDeadOrGhost = function(u) return dead[u] or false end, UnitIsFeignDeath = function() return false end,
	ForeverDungeonJournal_NS = FDJ, ForeverDungeonJournalRunTracker = fdjWin, ForeverDungeonJournalCharacterDB = cdb,
	hooksecurefunc = function(t, k, fn) hooks[#hooks + 1] = { t, k, fn } end,
	LFG_TYPE_DUNGEON = "Dungeon", LFG_TYPE_RAID = "Raid", GameTooltip = frame("tip"),
	issecretvalue = function() return false end, unpack = table.unpack,
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
}, { __index = _G })
env._G = env
local chunk = assert(loadfile(dir .. "/Tracker/Dungeon.lua", "t", env))
chunk("ForeverTrackerPlus", { tracker = ns })
local api = ns.api
ns.onLogin[1]()

local ghost = frame("ghost")
local room = api.layoutDungeonCard(ghost, 0, 1)
local card = env.ForeverTrackerPlusDungeonCard
check("inside a dungeon: the card takes room at the top (" .. tostring(room) .. ")", type(room) == "number" and room > 40)
-- find the card's texts: the header says "Dungeon", the title the instance, the banner the group's size
local function texts(f, out)
	out = out or {}
	for k, v in pairs(f) do if type(v) == "table" and v.text ~= nil then out[#out + 1] = v.text end end
	return out
end
check("DungeonJournal's window moved into the card", fdjWin.parent ~= "UIParent" and fdjWin.parent ~= nil)
check("its own frame, title and buttons hidden", fdjWin.logo.shown == false and fdjWin.title.shown == false
	and fdjWin.close.shown == false and fdjWin.grip.shown == false and fdjWin.bg[4] == 0 and fdjWin.border[4] == 0)
check("it cannot be dragged out of the card", fdjWin.handle.mouse == false and fdjWin.movable == false)
check("its content under the card's name and skull row (its title bar's 26 px hidden)",
	fdjWin.points[1][1] == "TOPLEFT" and fdjWin.points[1][5] < 0)

check("the header says Dungeon", hasText("Dungeon"))
-- R106-88: DungeonJournal asked to show in the card (solo too), its fresh run started before the first kill
check("DungeonJournal's tracker turned on for the card", cdb.runTracker.on == true)
check("no run yet: its fresh run for this dungeon started (every boss alive, 0:00)", blank and blank.dungeon == "Deadmines"
	and blank.map == 36)
check("its reset button right of the book, the book's size (R106-89: 18)", fdjWin.reset.points[1][1] == "LEFT" and fdjWin.reset.w == 18)
local bannerFound, bookFound = false, false
for _, f in ipairs(all) do
	if rawget(f, "w") == 24 and rawget(f, "h") == 36 then bannerFound = true end
	if rawget(f, "w") == 18 and rawget(f, "h") == 18 and f.points[1] and f.points[1][1] == "LEFT" and f.points[1][3] == "RIGHT"
		and rawget(f, "scripts") and f.scripts.OnClick and f ~= fdjWin.reset then bookFound = true end
end
check("the banner shorter (24 x 36)", bannerFound)
check("the book right after the name", bookFound)
-- R106-89: the number in the middle of the banner; the deaths left of the banner on the name's line
local centred, deathsLeft = false, false
for _, f in ipairs(all) do
	local p = rawget(f, "points") and f.points[1]
	if p and p[1] == "CENTER" and p[3] == "CENTER" and rawget(f, "text") == "4" then centred = true end
	if p and p[1] == "RIGHT" and p[3] == "LEFT" and p[4] == -6 and rawget(f, "text") == "0" then deathsLeft = true end
end
check("the banner's number in its middle", centred)
check("the deaths left of the banner", deathsLeft)
-- the eye: hides DungeonJournal's part (off the screen) and shows it again
local eye
for _, f in ipairs(all) do
	if rawget(f, "scripts") and f.scripts.OnClick and rawget(f, "icon") and f ~= fdjWin.reset and rawget(f, "w") == 18
		and f.points[1] and (f.points[1][2] == fdjWin.reset or (f.points[1][2] and rawget(f.points[1][2], "icon"))) then eye = f end
end
check("the eye after the reset button", eye ~= nil)
-- R106-91: DungeonJournal's window takes no clicks (it lay over the book and the eye); the book's icon inset (14 px)
check("its window takes no clicks while in the card", fdjWin.mouse == false)
-- R106-98: the addon's own book on a see-through background (Textures/Book.tga, 64x64 32-bit), on the whole button
local src = io.open(dir .. "/Tracker/Dungeon.lua"):read("a")
local tga = io.open(dir .. "/Textures/Book.tga", "rb")
local head = tga and tga:read(18)
if tga then tga:close() end
check("the book: the addon's own picture, no game icon's dark square", src:find([[\\Textures\\Book"]], 1, true) ~= nil
	and not src:find("INV_Misc_Book_09\"", 1, true) and head and head:byte(13) == 64 and head:byte(17) == 32)
if eye then
	-- R106-93: the eye is DungeonJournal's own "Hide Tracker" (FDJ.SetTrackerHidden); DungeonJournal hides its window
	local hideOpt, calls = false, {}
	FDJ.TrackerOption = function(k) return k == "hide" and hideOpt end
	FDJ.SetTrackerHidden = function(on) calls[#calls + 1] = on; hideOpt = on; fdjWin.shown = not on end
	local before = api.layoutDungeonCard(ghost, 0, 1)
	eye.scripts.OnClick(eye)
	local hiddenRoom = api.layoutDungeonCard(ghost, 0, 1)
	check("eye clicked: DungeonJournal's Hide Tracker ticked, the card smaller", calls[1] == true and hideOpt
		and hiddenRoom < before)
	eye.scripts.OnClick(eye)
	check("clicked again: Hide Tracker unticked, shown again", calls[2] == false and not hideOpt
		and api.layoutDungeonCard(ghost, 0, 1) == before)
	check("no own hidden setting any more", ns.db.dungeonJournalHidden == nil)
	-- R106-103: its reset button shows (a run started): the card laid out again, the eye right of the reset button
	local onUpdate
	for _, h in ipairs(hooks) do if h[2] == "UpdateRunTracker" then onUpdate = h[3] end end
	local relayouts = 0
	api.applyLayout = function() relayouts = relayouts + 1 end
	fdjWin.reset.shown = false
	onUpdate(); local base = relayouts
	onUpdate()
	check("nothing changed: no new layout", relayouts == base)
	fdjWin.reset.shown = true
	onUpdate()
	check("its reset button shown: the card laid out again", relayouts == base + 1)
	api.layoutDungeonCard(ghost, 0, 1)
	check("the eye right of the reset button", eye.points[1][2] == fdjWin.reset)
	fdjWin.reset.shown = false
	onUpdate()
	check("hidden again: laid out again", relayouts == base + 2)
	api.applyLayout = nil
end
check("the card's name: the instance", hasText("The Deadmines"))
check("the banner: the group's size (4)", hasText("4"))
-- deaths: the group's, each death counted once, from the twice-a-second check
local ticker
for _, f in ipairs(all) do if rawget(f, "scripts") and f.scripts.OnUpdate then ticker = ticker or f end end
local function tick() ticker.scripts.OnUpdate(ticker, 1) end
check("no deaths yet", api.dungeonDeaths() == 0)
tick()
dead.party1 = true
tick(); tick()
check("Ana died: 1, not counted again while dead", api.dungeonDeaths() == 1)
dead.party1 = nil; tick()
dead.party1 = true; dead.player = true; tick()
check("Ana again and the player: 3", api.dungeonDeaths() == 3)
check("kept in the saved settings (a /reload keeps it)", ns.db.dungeonDeaths and ns.db.dungeonDeaths.count == 3)
FDJ.RunLog.Current = function() return { id = 8 } end
check("a new run: 0 again", api.dungeonDeaths() == 0)
-- a raid
kind = "raid"
api.layoutDungeonCard(ghost, 0, 1)
check("in a raid the header says Raid", hasText("Raid"))
-- collapsed: only the header, the window given back
ns.db.dungeonCollapsed = true
local small = api.layoutDungeonCard(ghost, 0, 1)
check("collapsed: only the header's room (" .. tostring(small) .. ")", small < room and small > 0)
check("collapsed: DungeonJournal's window stays in the card (hidden with it)", fdjWin.parent ~= "UIParent")
check("collapsed: its portraits off the screen (no unseen click areas)", fdjWin.points[1][4] == -4000)
ns.db.dungeonCollapsed = nil
-- R106-116: the header and its line hidden: its room kept (the tracker does not move), never collapsed
local full = api.layoutDungeonCard(ghost, 0, 1)
local function headerFrame()
	for _, f in ipairs(all) do if type(f.Text) == "table" and f.Text.text == "Raid" then return f end end
end
ns.db.dungeonHeader = false
local noHead = api.layoutDungeonCard(ghost, 0, 1)
check("no header: the same room, nothing moves (" .. tostring(noHead) .. " = " .. tostring(full) .. ")", noHead == full)
check("no header: the header hidden", headerFrame() and headerFrame().shown == false)
ns.db.dungeonCollapsed = true
check("no header: collapse ignored (its button is in the header)", api.layoutDungeonCard(ghost, 0, 1) == noHead)
ns.db.dungeonCollapsed, ns.db.dungeonHeader = nil, nil
api.layoutDungeonCard(ghost, 0, 1)
check("header back on: shown", headerFrame().shown == true)
-- outside: no card, the window back
api.layoutDungeonCard(ghost, 0, 1)
inside = false
local outRoom = api.layoutDungeonCard(ghost, 0, 1)
check("outside: DungeonJournal's tracker setting given back", cdb.runTracker.on == nil)
check("outside: its reset button back after its own title at its size", fdjWin.reset.points[1][2] == fdjWin.title
	and fdjWin.reset.w == 27)
check("outside an instance: no room, the window back where it was, with its look", api.layoutDungeonCard(ghost, 0, 1) == 0
	and fdjWin.parent == "UIParent" and fdjWin.points[1][1] == "TOPRIGHT" and fdjWin.points[1][4] == -260
	and fdjWin.logo.shown == true and fdjWin.movable == true)
inside = true
api.setDungeonCard(false)
check("switched off: no room, the window its own", api.layoutDungeonCard(ghost, 0, 1) == 0 and fdjWin.parent == "UIParent"
	and fdjWin.bg[4] == 0.88)
local core = io.open(dir .. "/Tracker/Core.lua"):read("a")
check("Core: the card first in the fixed strip, then the reputation",
	(core:find("ns.api.layoutDungeonCard, ghost, base", 1, true) or 1e9) < (core:find("ns.api.layoutTrackedReputation, ghost, pinned", 1, true) or 0))
-- R106-92: above a pinned RXP guide: the card at the top (base 0), the guide moved down by its room, not the sections
check("Core: the card above a pinned guide, the guide moved down by its room",
	core:find("local base = cardOverGuide and 0 or measurePinned()", 1, true) ~= nil
	and core:find("if module == guide and pinGuide then px = px - guideShift end", 1, true) ~= nil
	and core:find("if not cardOverGuide then pinned = pinned + cardRoom; drop = drop + cardRoom end", 1, true) ~= nil
	and (core:find("guideShift = shift", 1, true) or 1e9) < (core:find("\tpinned = measurePinned()\n\tif not cardOverGuide", 1, true) or 0))
-- R106-102: the guide moved down only by the room it does not already have below the strip's top (no empty space)
check("the guide's own offset taken off its shift", core:find("own = math.max(top - toScreen(guide, gTop) - guideShift, 0)", 1, true)
	~= nil and core:find("shift = math.max(cardRoom - own, 0)", 1, true) ~= nil)
check("on by default", core:find("dungeonCard = true", 1, true) ~= nil)
check("in the toc", io.open(dir .. "/ForeverTrackerPlus.toc"):read("a"):find("Tracker/Dungeon.lua", 1, true) ~= nil)
check("its option", io.open(dir .. "/Tracker/Config.lua"):read("a"):find('"Dungeon card at the top"', 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
