-- R106-95: Ctrl+left-click a quest: a General message, a Looking For Group listing, "inv" whispers invited
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function frame(name)
	local f = { scripts = {}, events = {}, shown = true, name = name }
	local m = {
		SetScript = function(self, k, fn) self.scripts[k] = fn end,
		RegisterEvent = function(self, e) self.events[e] = true end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		CreateFontString = function() return frame("fs") end,
	}
	return setmetatable(f, { __index = function(_, k) return m[k] or function() end end })
end
local frames = {}
local now = 100
local sent, said, created, updated, invited = {}, {}, nil, nil, {}
local roles = { tank = false, healer = false, dps = false }
local rolesSet
local loadedUi, _G_env
local timers = {}
local comment = { EditBox = { SetText = function(self, t) self.text = t end } }
local acts = {
	[1] = { fullName = "The Deadmines", shortName = "Deadmines", categoryID = 2, minLevel = 15 },
	[2] = { fullName = "Westfall", shortName = "Westfall", categoryID = 1, minLevel = 9 },
	[3] = { fullName = "Warsong Gulch", shortName = "Warsong Gulch", categoryID = 3, minLevel = 10 },
	[4] = { fullName = "Custom", shortName = "Custom", categoryID = 6, minLevel = 1 },
	[5] = { fullName = "Stormwind Stockade", shortName = "Stockade", categoryID = 2, minLevel = 20 },
}
local cats = { [1] = "Quests & Zones", [2] = "Dungeons", [3] = "Battlegrounds", [6] = "Custom" }
-- the quest log: header, quest
local log = {
	{ isHeader = true, title = "The Deadmines" }, { questID = 214 },
	{ isHeader = true, title = "Westfall" }, { questID = 22 },
	{ isHeader = true, title = "Warsong Gulch" }, { questID = 7 },
	{ isHeader = true, title = "Seasonal" }, { questID = 9 },
	{ isHeader = true, title = "The Stockade" }, { questID = 386 },
}
local titles = { [214] = "Red Silk Bandanas", [22] = "Goretusk Liver Pie", [7] = "Fight for Warsong", [9] = "A Party", [386] = "What Comes Around..." }
local inGroup, leader, members = false, false, 1
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function(_, name) local f = frame(name); frames[#frames + 1] = f; if name then _G_env[name] = f end return f end,
	UIParent = frame("UIParent"), UISpecialFrames = {},
	C_AddOns = { IsAddOnLoaded = function() return false end,
		LoadAddOn = function(n) loadedUi = n; _G_env.LFGListingComment = comment; return true end },
	GetTime = function() return now end, issecretvalue = function() return false end,
	DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) said[#said + 1] = t end },
	GENERAL = "General", CUSTOM = "Custom",
	GetChannelList = function() return 2, "Trade", false, 1, "General", false end,
	SendChatMessage = function(text, kind, _, number) sent[#sent + 1] = { text = text, kind = kind, number = number } end,
	GetQuestLink = function(id) return "|cffffff00|Hquest:" .. id .. ":20|h[" .. titles[id] .. "]|h|r" end,
	C_QuestLog = {
		GetTitleForQuestID = function(id) return titles[id] end,
		GetLogIndexForQuestID = function(id) for i, e in ipairs(log) do if e.questID == id then return i end end end,
		GetInfo = function(i) return log[i] end,
	},
	C_LFGList = {
		GetAvailableActivities = function() return { 1, 2, 3, 4, 5 } end,
		GetActivityInfoTable = function(id) return acts[id] end,
		GetLfgCategoryInfo = function(id) return { name = cats[id] } end,
		HasActiveEntryInfo = function() return created ~= nil end,
		CreateListing = function(d) listedByAddon = d; return true end,
		UpdateListing = function(d) updated = d; return true end,
	},
	C_LFGListRoles = { GetRoles = function() return roles end, SetRoles = function(r) rolesSet = r; return true end },
	Enum = { LFGEntryGeneralPlaystyle = { FunRelaxed = 2 } },
	UnitLevel = function() return 25 end,
	IsInGroup = function() return inGroup end, IsInRaid = function() return false end,
	UnitIsGroupLeader = function() return leader end, GetNumGroupMembers = function() return members end,
	C_PartyInfo = { InviteUnit = function(n) invited[#invited + 1] = n end },
	-- R106-122: Blizzard's Group Finder: the addon opens it with the activity picked (its "List Group" lists)
	LFGListFrame = { EntryCreation = { Description = { EditBox = { SetText = function(self, t) self.text = t end } } },
		baseFilters = 1 }, LFGListPVEStub = "stub",
	PVEFrame_ShowFrame = function(a, b) shownFrame = { a, b } end,
	LFGListEntryCreation_Show = function(ec, base, cat, filters) ec.showCat = cat end,
	LFGListEntryCreation_Select = function(ec, filters, cat, group, aid) created = { activityIDs = { aid }, cat = cat } end,
	LFGListUtil_OpenBestWindow = function() openedBest = true end,
	-- R106-124: Forever's Vanilla-style window (the one used when it is there)
	LFGListingFrame = {
		ActivityView = { Comment = { EditBox = { SetText = function(self, t) self.text = t end,
			GetText = function(self) return self.text end } } },
		SetCategorySelection = function(self, cat) self.cat = cat; self.activities = {} end,
		SetActivity = function(self, aid, sel, allowCreate, userInput)
			self.activities[aid] = sel; self.dirty = userInput; created = { activityIDs = { aid }, cat = self.cat }
		end,
	},
	LFGPARENT_LISTING_TAB_INDEX = 1,
	LFGVanilla_ShowFrame = function(tab) vanillaTab = tab; openedBest = true end,
	LFGListingActivityView_UpdateActivities = function(view) view.redrawn = true end,
	LFGListingActivityView_OnPlayStyleSelectedInternal = function(view, ps) view.generalPlaystyle = ps end,
	C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
}, { __index = _G })
env._G = env
_G_env = env
assert(loadfile(dir .. "/Tracker/GroupFinder.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
local api = ns.api
ns.onLogin[1]()
local events = frames[#frames]
-- R106-104: the click opens the prompt; its buttons post
local function prompt() return env.ForeverTrackerPlusGroupPrompt end
local function choose(id, how)
	api.findGroupForQuest(id)
	local f = prompt()
	if f and f.shown and f.questID == id then f.buttons[how].scripts.OnClick(f.buttons[how]) end
end

api.findGroupForQuest(214)
check("the click: the prompt, nothing posted yet", prompt() and prompt().shown and #sent == 0 and created == nil
	and prompt().buttons.chat and prompt().buttons.lfg and prompt().buttons.both)
check("Escape closes it", env.UISpecialFrames[1] == "ForeverTrackerPlusGroupPrompt")
prompt().buttons.both.scripts.OnClick(prompt().buttons.both)
check("a button closes the prompt", not prompt().shown)
check("General: \"LFM [quest] - whisper 'inv' to join.\" on its channel number",
	sent[1] and sent[1].kind == "CHANNEL" and sent[1].number == 1
	and sent[1].text == "LFM |cffffff00|Hquest:214:20|h[Red Silk Bandanas]|h|r - whisper 'inv' to join.")
check("told: posted, then searching for the quest", said[1]:find("Recruitment posted to General.", 1, true)
	and said[#said]:find("Searching for players for |cffffff00|Hquest:214", 1, true))
check("listed under its dungeon (its quest-log header)", created and created.activityIDs[1] == 1)
check("R106-122: the addon does not list itself (the game blocks it from the prompt)", listedByAddon == nil)
check("R106-124: the Vanilla-style window opened on its Listing tab, the activity's category, the activity picked",
	vanillaTab == 1 and env.LFGListingFrame.cat == created.cat and env.LFGListingFrame.activities[1] == true
	and env.LFGListingFrame.dirty == true and shownFrame == nil)
check("R106-122: told to click List Group", said[#said - 1]:find("Click its List Group button", 1, true) ~= nil)
-- R106-105: an addon's text in "More details" makes the game block the listing: never written
check("R106-123: the quest's title in More details",
	env.LFGListingFrame.ActivityView.Comment.EditBox.text == "Red Silk Bandanas" and loadedUi == nil)
check("R106-125: the activity list redrawn (its check box shows the pick)", env.LFGListingFrame.ActivityView.redrawn == true)
check("R106-125: playstyle Relaxed", env.LFGListingFrame.ActivityView.generalPlaystyle == 2)
do
	local edit = env.LFGListingFrame.ActivityView.Comment.EditBox
	edit.text = "" -- something cleared it after
	local n0 = #said
	for _, fn in ipairs(timers) do fn() end
	check("R106-125: written again on the next frame", edit.text == "Red Silk Bandanas" and #said == n0)
	local realSet = edit.SetText
	edit.SetText = function() end -- the game refuses it
	edit.text = ""
	for _, fn in ipairs(timers) do fn() end
	check("R106-125: refused: told to type it", said[#said]:find("type it there yourself", 1, true) ~= nil)
	edit.SetText = realSet
	timers = {}
end
check("no roles picked: DPS", rolesSet and rolesSet.dps == true and not rolesSet.tank and not rolesSet.healer)
events.scripts.OnEvent(events, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
check("told when listed", said[#said]:find("Listed in Looking For Group: The Deadmines", 1, true) ~= nil)

-- "inv" whispers: invited while recruiting
events.scripts.OnEvent(events, "CHAT_MSG_WHISPER", " INV ", "Seoux-Realm")
events.scripts.OnEvent(events, "CHAT_MSG_WHISPER", "hi, can I join?", "Other")
check("a whisper of just \"inv\": invited; other whispers not", #invited == 1 and invited[1] == "Seoux-Realm")
now = now + 16 * 60
events.scripts.OnEvent(events, "CHAT_MSG_WHISPER", "inv", "Late")
check("15 minutes later: no more invites", #invited == 1)

-- a zone quest, a battleground quest, a quest with no activity (Custom); roles already picked: kept
roles = { tank = false, healer = true, dps = false }
rolesSet = nil
created = nil
now = now + 5
choose(22, "both")
check("a zone quest: Quests & Zones (its zone)", created and created.activityIDs[1] == 2)
check("roles picked in Looking For Group: kept", rolesSet == nil)
-- R106-106: already listed: no UpdateListing (the game blocks it for addons), told instead
now = now + 5
choose(7, "both")
check("already listed: not updated, its window opened, told to change it there", updated == nil and openedBest
	and said[#said - 1]:find("already listed", 1, true) ~= nil)
created = nil
now = now + 5
choose(7, "both")
check("a battleground quest: its battleground", created and created.activityIDs[1] == 3)
created = nil
now = now + 5
choose(9, "both")
check("nothing fits: Custom", created and created.activityIDs[1] == 4)
created = nil
now = now + 5
choose(386, "both")
check("a name a little different (The Stockade / Stormwind Stockade)", created and created.activityIDs[1] == 5)

-- only chat / only LFG
created = nil
local ns0 = #sent
now = now + 5
choose(214, "chat")
check("LFM in chat: posted, no listing", #sent == ns0 + 1 and created == nil)
now = now + 5
choose(214, "lfg")
check("List in LFG: listed, nothing posted", #sent == ns0 + 1 and created and created.activityIDs[1] == 1)

-- the click twice (block and header button): once
local n = #sent
choose(22, "both")
check("the same click heard twice: posted once", #sent == n)
-- in a group, not its leader: nothing
inGroup, leader = true, false
now = now + 5
choose(22, "both")
check("in a group but not its leader: nothing posted", #sent == n and said[#said]:find("only the group leader", 1, true))
-- off: nothing
inGroup = false
ns.db.questGroupFinder = false
now = now + 5
choose(22, "both")
check("switched off: nothing", #sent == n)

local extras = io.open(dir .. "/Tracker/Extras.lua"):read("a")
check("Extras: Ctrl+left-click calls it", extras:find('button == "LeftButton" and api.findGroupForQuest', 1, true) ~= nil)
check("in the toc", io.open(dir .. "/ForeverTrackerPlus.toc"):read("a"):find("Tracker/GroupFinder.lua", 1, true) ~= nil)
check("its option", io.open(dir .. "/Tracker/Config.lua"):read("a"):find('"Ctrl+click a quest: find a group"', 1, true) ~= nil)
check("on by default", io.open(dir .. "/Tracker/Core.lua"):read("a"):find("questGroupFinder = true", 1, true) ~= nil)

-- R106-124: the button posts first, then hides the prompt
local order = {}
local f = prompt()
local realHide = f.Hide
f.Hide = function(self) order[#order + 1] = "hide"; realHide(self) end
local realPost = api.postGroupForQuest
api.postGroupForQuest = function(...) order[#order + 1] = "post"; return realPost(...) end
f.questID = 214
f.buttons.chat.scripts.OnClick(f.buttons.chat)
check("R106-124: the post runs before the prompt hides", order[1] == "post" and order[2] == "hide")
api.postGroupForQuest = realPost

-- R106-122: no Vanilla-style window: the retail one
env.LFGListingFrame, created, shownFrame, db_off = nil, nil, nil, nil
ns.db.questGroupFinder = true
now = now + 5
choose(214, "lfg")
check("R106-122: no Vanilla-style window: retail Group Finder at Start a Group",
	shownFrame and shownFrame[1] == "GroupFinderFrame" and created and env.LFGListFrame.EntryCreation.showCat == created.cat
	and env.LFGListFrame.EntryCreation.Description.EditBox.text == "Red Silk Bandanas")
print(pass and "PASS" or "FAILED")
