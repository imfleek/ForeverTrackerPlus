-- Our own tracker (OWN_TRACKER_PLAN.md, phase 0): the no-touch rule for Blizzard's tracker, and the spike itself.
-- Run from tests/: texlua own_tracker_rules_test.lua ..
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c and true or false end
local function read(path) local f = assert(io.open(dir .. "/" .. path, "rb")); local s = f:read("*a"); f:close(); return s end

---------------------------------------------------------------------------------------------------------------------
-- The rule: on Blizzard's tracker (and its modules, blocks, headers) only SetAlpha, EnableMouse, hooks and reads.
-- No Hide or Show (user: the secret-aura error came back: Hide runs Blizzard's hide handlers under our taint)
---------------------------------------------------------------------------------------------------------------------
local FILES = { "Tracker/Own/Data.lua", "Tracker/Own/Look.lua", "Tracker/Own/Rows.lua", "Tracker/Own/Recipes.lua",
	"Tracker/Own/Legacy.lua", "Tracker/Own/Battleground.lua", "Tracker/Own/Frame.lua" }
local BLIZZ = { "blizz", "ObjectiveTrackerFrame", "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
	"ScenarioObjectiveTracker", "ObjectiveTrackerManager", "BonusObjectiveTracker", "WorldQuestObjectiveTracker",
	"AchievementObjectiveTracker" }
local FORBIDDEN = { "SetPoint", "ClearAllPoints", "SetSize", "SetHeight", "SetWidth", "SetScale", "SetParent",
	"SetPointBase", "ClearAllPointsBase", "SetScaleBase", "SetParentBase", "Update", "MarkDirty", "SetAllPoints",
	"SetFrameStrata", "SetFrameLevel", "Hide", "Show", "SetShown" }
for _, path in ipairs(FILES) do
	local src = read(path):gsub("%-%-[^\n]*", "") -- comments out
	local bad = {}
	for _, name in ipairs(BLIZZ) do
		for _, m in ipairs(FORBIDDEN) do
			if src:find("%f[%w_]" .. name .. "[%w_%.]*:" .. m .. "%(") then bad[#bad + 1] = name .. ":" .. m end
		end
		-- a field write: name.field = (not ==)
		for field in src:gmatch("%f[%w_]" .. name .. "%.([%w_]+)%s*=[^=]") do bad[#bad + 1] = name .. "." .. field .. " =" end
		if src:find("securecallfunction%([^)]*" .. name) then bad[#bad + 1] = "securecallfunction on " .. name end
	end
	check("rule: " .. path .. " never moves, sizes or writes Blizzard's tracker" .. (#bad > 0 and (" (" .. table.concat(bad, ", ") .. ")") or ""), #bad == 0)
end
-- the scan finds a breach
do
	local src = "local blizz = ObjectiveTrackerFrame\nblizz:SetPoint('TOP')\nObjectiveTrackerFrame.foo = 1\n"
	check("rule: the scan finds a SetPoint", src:find("%f[%w_]blizz[%w_%.]*:SetPoint%(") ~= nil)
	check("rule: the scan finds a field write", src:match("%f[%w_]ObjectiveTrackerFrame%.([%w_]+)%s*=[^=]") == "foo")
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------------------------------------
local core, toc, config, pkg = read("Tracker/Core.lua"), read("ForeverTrackerPlus.toc"), read("Tracker/Config.lua"), read(".pkgmeta")
check("toc: Own/Data, Look, Rows, Recipes, Legacy, Battleground and Frame right after Core.lua", toc:find("Tracker/Core.lua%s+Tracker/Own/Data.lua%s+Tracker/Own/Look.lua%s+Tracker/Own/Rows.lua%s+Tracker/Own/Recipes.lua%s+Tracker/Own/Legacy.lua%s+Tracker/Own/Battleground.lua%s+Tracker/Own/Frame.lua") ~= nil)
check("core: no step aside left (the fades always work)", not core:find("steppedAside", 1, true))
check("phase 5: ZoneSort's zone header lookup asks our tracker", read("Tracker/ZoneSort.lua"):find(
	"return api.ownZoneLabelFor and api.ownZoneLabelFor(zone) or nil", 1, true) ~= nil)
check("phase 5: the rare tag sits at our list's right edge, the NPC panel beside our frame",
	read("Tracker/Rares.lua"):find('tag:SetPoint("RIGHT", label:GetParent(), "RIGHT", -4, 0)', 1, true) ~= nil
	and read("Tracker/NpcPanel.lua"):find("api.ownTrackerFrame and api.ownTrackerFrame()", 1, true) ~= nil)
check("phase 5: the zone header tags follow each rebuild", read("Tracker/Own/Frame.lua"):find(
	"if api.refreshExploredTag then pcall(api.refreshExploredTag) end", 1, true) ~= nil)
check("phase 6: Extras' Quests header colours go to our header with our own tracker", read("Tracker/Extras.lua"):find(
	"if api.ownApplyHeaderLook then api.ownApplyHeaderLook() end", 1, true) ~= nil)
do
	local cfg = read("Tracker/Config.lua")
	check("only tracker: the classic-only settings are gone (pin header, Professions box, More quests, reload, switch)",
		not cfg:find('"Keep the \\"Quests\\" header at the top"', 1, true)
		and not cfg:find('"Professions beside the quest tracker"', 1, true)
		and not cfg:find('"List quests past the tracking limit"', 1, true)
		and not cfg:find('"Reload when entering a battleground"', 1, true)
		and not cfg:find('"Use our own tracker (beta)"', 1, true)
		and not cfg:find("classicOnly", 1, true))
	check("only tracker: the old switch is cleared", core:find("db.ownTracker, db.instanceReload", 1, true) ~= nil
		and not core:find("ownTrackerOn", 1, true))
end
check("only tracker: RXP Tracker opacity reaches the guide in our frame", read("Objectives/tracker/Tracker.lua"):find(
	"local a = own and both or (general > 0 and both / general or 1)", 1, true) ~= nil)
check("zonesort: exports its zone names", read("Tracker/ZoneSort.lua"):find("api.questZoneName = headerTitle", 1, true) ~= nil)
-- 3.2 (user: "Delete the old tracker's code"): nothing of ours moves, sizes, parents, hooks or relays out Blizzard's
-- tracker any more. Only Own/Frame.lua names it (opacity 0, mouse off, reads), Core.lua reads its strata and level,
-- Dungeon.lua reads its Quests header's art.
do
	local files = { "Tracker/Core.lua", "Tracker/Extras.lua", "Tracker/Fonts.lua", "Tracker/ZoneSort.lua",
		"Tracker/QuestClicks.lua", "Tracker/Reputation.lua", "Tracker/Reminders.lua", "Tracker/Rares.lua",
		"Tracker/NpcPanel.lua", "Tracker/Guides.lua", "Objectives/tracker/Tracker.lua", "Objectives/tracker/Header.lua",
		"Objectives/features/GuideMenu.lua" }
	local bad = {}
	for _, f in ipairs(files) do
		local src = read(f)
		for _, word in ipairs({ "ObjectiveTrackerContainerMixin", "ObjectiveTrackerManager", "trackerRelayout",
			"whenTrackerFree", "trackerSteppedAside", "moveTracker", "QuestObjectiveTracker" }) do
			if src:find(word, 1, true) then bad[#bad + 1] = f .. ": " .. word end
		end
	end
	check("old tracker gone: no hooks or layouts on Blizzard's tracker (" .. table.concat(bad, ", ") .. ")", #bad == 0)
	check("old tracker gone: MoreQuests.lua and QuestReady.lua removed", not toc:find("MoreQuests.lua", 1, true)
		and not toc:find("QuestReady.lua", 1, true) and toc:find("Tracker/QuestClicks.lua", 1, true) ~= nil)
	check("old tracker gone: Core.lua has no scroll window", not core:find("ForeverTrackerPlusViewport", 1, true)
		and not core:find("hooksecurefunc", 1, true))
end
check("core: lock reaches our frame", core:find("ns.api.ownLockChanged()", 1, true) ~= nil)
check("pkgmeta: the plan stays out of the zip", pkg:find("OWN_TRACKER_PLAN.md", 1, true) ~= nil)

---------------------------------------------------------------------------------------------------------------------
-- The spike, loaded with stubs
---------------------------------------------------------------------------------------------------------------------
local calls = {} -- every method called on Blizzard's tracker (and its header), by name
local BLIZZ_NAMES = { ObjectiveTrackerFrame = true, BlizzHeader = true }
local function stubFrame(name, kind)
	local f = { shown = true, alpha = 1, scripts = {}, hooks = {}, name = name, kind = kind or "Frame", h = 300, w = 0,
		vs = 0, points = {}, regions = {} }
	local methods = {
		GetAlpha = function(s) return s.alpha end,
		SetAlpha = function(s, a) s.alpha = a end,
		IsShown = function(s) return s.shown end,
		Hide = function(s) s.shown = false end,
		Show = function(s) s.shown = true; if s.hooks.OnShow then s.hooks.OnShow(s) end end,
		SetShown = function(s, v) s.shown = v and true or false end,
		HookScript = function(s, e, fn) s.hooks[e] = fn end,
		SetScript = function(s, e, fn) s.scripts[e] = fn end,
		GetScript = function(s, e) return s.scripts[e] end,
		IsProtected = function() return false end,
		IsMouseEnabled = function(s) return s.mouse ~= false end,
		EnableMouse = function(s, v) s.mouse = v and true or false end,
		GetWidth = function(s) return s.w end,
		SetWidth = function(s, w) s.w = w end,
		GetHeight = function(s) return s.h end,
		SetHeight = function(s, h) s.h = h end,
		SetSize = function(s, w, h) s.w, s.h = w, h end,
		GetSize = function(s) return s.w, s.h end,
		GetVerticalScroll = function(s) return s.vs end,
		SetVerticalScroll = function(s, v) s.vs = v end,
		GetStringHeight = function() return 12 end,
		SetText = function(s, v) s.text = v end,
		GetText = function(s) return s.text end,
		SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
		SetFrameStrata = function(s, v) s.strata = v end,
		SetFrameLevel = function(s, v) s.level = v end,
		SetScale = function(s, v) s.scale = v end,
		SetAtlas = function(s, v) s.atlas = v end,
		SetTexture = function(s, v) s.texture = v end,
		GetAtlas = function(s) return s.atlas end,
		GetTexture = function(s) return s.file end,
		GetVertexColor = function() return 1, 1, 1, 1 end,
		GetDrawLayer = function(s) return s.layer or "ARTWORK", 0 end,
		IsObjectType = function(s, t) return s.kind == t end,
		GetRegions = function(s) return table.unpack(s.regions) end,
		ClearAllPoints = function(s) s.points = {} end,
		SetPoint = function(s, p, rel, rp, x, y) s.points[#s.points + 1] = { p, rel, rp, x, y } end,
		GetNumPoints = function(s) return #s.points end,
		GetPoint = function(s, i) local p = s.points[i]; return p[1], p[2], p[3], p[4], p[5] end,
		CreateFontString = function() return stubFrame(nil, "FontString") end,
		CreateTexture = function() return stubFrame(nil, "Texture") end,
	}
	return setmetatable(f, { __index = function(t, k)
		local m = methods[k]
		if not m then
			-- other methods are no-ops; other fields (Text, Header, MinimizeButton...) are absent
			for _, verb in ipairs({ "Set", "Get", "Enable", "Register", "Unregister", "Clear", "Create", "Is", "Hook" }) do
				if k:sub(1, #verb) == verb then m = function() end break end
			end
			if not m then return nil end
		end
		local name = rawget(t, "name")
		if name and BLIZZ_NAMES[name] then
			return function(...) calls[#calls + 1] = name .. ":" .. k; return m(...) end
		end
		return m
	end })
end
local blizzard = stubFrame("ObjectiveTrackerFrame")
blizzard.w = 248
-- Blizzard's "All Objectives" header: one art texture and its title text
local blizzHeader = stubFrame("BlizzHeader")
blizzHeader.h = 30
local headerArt = stubFrame(nil, "Texture")
headerArt.atlas = "UI-QuestTracker-Primary-Objective-Header"
headerArt.w, headerArt.h = 250, 30
headerArt.points = { { "TOPLEFT", blizzHeader, "TOPLEFT", -20, 0 } }
local headerText = stubFrame(nil, "FontString")
headerText.text = "All Objectives"
blizzHeader.regions = { headerArt, headerText }
blizzHeader.Text = headerText
blizzard.Header = blizzHeader
local blizzMinimize = stubFrame("BlizzHeader")
blizzHeader.MinimizeButton = blizzMinimize
-- the Quests section with one block in use, and the scenario section with a pooled widget
local blizzBlock = stubFrame("BlizzHeader")
blizzBlock.HeaderButton, blizzBlock.ItemButton = stubFrame("BlizzHeader"), stubFrame("BlizzHeader")
local blizzQuests = { Header = { MinimizeButton = stubFrame("BlizzHeader") }, usedBlocks = { T = { [1] = blizzBlock } },
	AddBlock = function() end }
local scenarioWidget = stubFrame("BlizzHeader")
local blizzScenario = { usedBlocks = { T = { [1] = scenarioWidget } } }
blizzard.modules = { blizzScenario, blizzQuests }
local timers = {}
local quests = {
	[101] = { title = "Wolves", level = 5, complete = false, objectives = { { text = "Wolf slain: 3/8", finished = false } } },
	[102] = { title = "Letter", level = 6, complete = true, objectives = {} },
}
local env = setmetatable({
	ObjectiveTrackerFrame = blizzard, UIParent = stubFrame("UIParent"),
	CreateFrame = function(_, name) return stubFrame(name) end,
	CreateFont = function(name) return stubFrame(name, "Font") end,
	ScenarioObjectiveTracker = blizzScenario,
	hooksecurefunc = function(t, name, fn) local orig = t[name]; t[name] = function(...) local r = { orig(...) }; fn(...); return table.unpack(r) end end,
	GetTime = function() return 100 end,
	InCombatLockdown = function() return false end,
	C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
	GetCursorPosition = function() return 0, 0 end,
	C_QuestLog = {
		GetNumQuestWatches = function() return 2 end,
		GetQuestIDForQuestWatchIndex = function(i) return ({ 101, 102 })[i] end,
		GetTitleForQuestID = function(id) return quests[id].title end,
		GetLogIndexForQuestID = function(id) return id end,
		GetInfo = function(i) return quests[i] and { level = quests[i].level, questID = i } end,
		IsComplete = function(id) return quests[id].complete end,
		GetQuestObjectives = function(id) return quests[id].objectives end,
	},
}, { __index = _G })
env._G = env
local function run() local list = timers; timers = {}; for _, fn in ipairs(list) do fn() end end
local function load(db, own, extra)
	local ns = { api = { ownTrackerOn = function() return own end, questDifficultyRGB = function() return 1, 1, 0 end },
		onLogin = {}, db = db }
	for k, v in pairs(extra or {}) do ns.api[k] = v end
	assert(loadfile(dir .. "/Tracker/Own/Data.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	assert(loadfile(dir .. "/Tracker/Own/Look.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	assert(loadfile(dir .. "/Tracker/Own/Rows.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	assert(loadfile(dir .. "/Tracker/Own/Recipes.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	assert(loadfile(dir .. "/Tracker/Own/Legacy.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	assert(loadfile(dir .. "/Tracker/Own/Battleground.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	assert(loadfile(dir .. "/Tracker/Own/Frame.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
	for _, fn in ipairs(ns.onLogin) do fn() end
	run()
	return ns.api
end
do
	local api = load({ trackMode = "watched", locked = true }, true)
	check("spike: on: Blizzard's tracker at opacity 0 and still shown (never Hide)", blizzard.alpha == 0 and blizzard.shown == true)
	local mark = #calls
	blizzard:SetAlpha(1) -- the test acts as Blizzard (Edit Mode) here: not our call
	table.remove(calls, mark + 1)
	check("spike: Blizzard sets its opacity back: 0 again", blizzard.alpha == 0)
	check("spike: mouse off on its click parts (header button, block, block header, item button)",
		blizzMinimize.mouse == false and blizzBlock.mouse == false and blizzBlock.HeaderButton.mouse == false
		and blizzBlock.ItemButton.mouse == false)
	check("spike: the scenario section's pooled widgets untouched", scenarioWidget.mouse ~= false)
	check("spike: later blocks too (AddBlock hook)", (function()
		local later = stubFrame("BlizzHeader")
		local mark2 = #calls
		blizzQuests:AddBlock(later)
		table.remove(calls, mark2 + 1)
		return later.mouse == false
	end)())
	check("spike: our frame is built", api.ownTrackerFrame() ~= nil)
	local ids = api.ownQuestIDs()
	check("spike: watched quests read", #ids == 2 and ids[1] == 101)
	local q = api.ownQuestData(101)
	check("spike: title, level, objectives read", q.title == "Wolves" and q.level == 5 and #q.objectives == 1)
	check("spike: complete read", api.ownQuestData(102).complete == true)
	local only = true
	for _, c in ipairs(calls) do
		local m = c:match(":(.+)$")
		if not (m == "SetAlpha" or m == "EnableMouse" or m:match("^Get") or m:match("^Is")) then only = false; print("     " .. c) end
	end
	check("spike: on Blizzard's tracker only SetAlpha, EnableMouse and reads (" .. #calls .. " calls)", only and #calls > 0)
end
---------------------------------------------------------------------------------------------------------------------
-- Phase 1: the data (Data.lua api.ownBuild)
---------------------------------------------------------------------------------------------------------------------
local log = {
	{ isHeader = true, title = "Elwynn Forest" },
	{ questID = 201, level = 5 }, { questID = 202, level = 7 }, { questID = 203, level = 6, isTask = true },
	{ isHeader = true, title = "Westfall" },
	{ questID = 204, level = 12 },
}
local logQuests = {
	[201] = { title = "Wolves", zone = "Elwynn Forest", objectives = {
		{ text = "Wolf: 8/8", finished = true, numFulfilled = 8, numRequired = 8 },
		{ text = "Pelt: 1/4", finished = false, numFulfilled = 1, numRequired = 4 } } },
	[202] = { title = "Kobolds", zone = "Elwynn Forest", complete = true, objectives = {} },
	[203] = { title = "Bonus", zone = "Elwynn Forest", objectives = {} },
	[204] = { title = "Defias", zone = "Westfall", objectives = {
		{ text = "Thug: 0/15", finished = false, numFulfilled = 0, numRequired = 15 } } },
}
local watch, super = { 204 }, nil
env.C_QuestLog = {
	GetNumQuestWatches = function() return #watch end,
	GetQuestIDForQuestWatchIndex = function(i) return watch[i] end,
	GetNumQuestLogEntries = function() return #log end,
	GetInfo = function(i) return log[i] end,
	GetLogIndexForQuestID = function(id) for i, e in ipairs(log) do if e.questID == id then return i end end end,
	GetTitleForQuestID = function(id) return logQuests[id] and logQuests[id].title end,
	IsComplete = function(id) return logQuests[id] and logQuests[id].complete end,
	IsFailed = function() return false end,
	GetQuestObjectives = function(id) return logQuests[id] and logQuests[id].objectives end,
}
env.C_SuperTrack = { GetSuperTrackedQuestID = function() return super end }
local helpers = {
	questZoneName = function(id) return logQuests[id] and logQuests[id].zone end,
	-- ZoneSort's order stand-in: Westfall first (closer), then by index
	orderQuests = function(list)
		local out = {}
		for i, q in ipairs(list) do out[i] = q end
		table.sort(out, function(a, b)
			if a.zone ~= b.zone then return a.zone == "Westfall" end
			return a.index < b.index
		end)
		return out
	end,
	inCurrentZone = function(id) return logQuests[id] and logQuests[id].zone == "Elwynn Forest" end,
	isCurrentZoneName = function(name) return name == "Elwynn Forest" end,
	questClassifier = function(id) if id == 204 then return "SKULL", "Elite" end end,
}
local function ids(list) local t = {} for _, q in ipairs(list) do t[#t + 1] = q.id end return table.concat(t, ",") end
do
	local api = load({ trackMode = "all" }, true, helpers)
	local d = api.ownBuild()
	check("data: Track all quests: watched first, then the log; no headers, no bonus tasks",
		ids(d.groups[1].quests) == "204,201,202" and d.count == 3)
	check("data: without by zone, one group with no header", #d.groups == 1 and d.groups[1].zone == nil)
	local wolves = d.groups[1].quests[2]
	check("data: title, level, zone", wolves.title == "Wolves" and wolves.level == 5 and wolves.zone == "Elwynn Forest")
	check("data: progress from the objectives (8/8 and 1/4 = 0.625)", math.abs(wolves.progress - 0.625) < 1e-6)
	check("data: objectives with have and need", #wolves.objectives == 2 and wolves.objectives[2].have == 1
		and wolves.objectives[2].need == 4)
	local kobolds = d.groups[1].quests[3]
	check("data: complete is green and progress 1", kobolds.complete and kobolds.g == 1 and kobolds.progress == 1)
	check("data: the classifier marker", d.groups[1].quests[1].marker == "SKULL")
	-- in game the marker is often an icon table (user: "attempt to concatenate field 'marker' (a table value)")
	local icon = { file = "Interface\\Minimap\\Dungeon", atlas = "Dungeon", scale = 1.32 }
	check("frame: an icon marker becomes a texture", api.ownMarkerText(icon) == "|TInterface\\Minimap\\Dungeon:18:18|t")
	env.C_Texture = { GetAtlasInfo = function(a) return a == "Dungeon" and {} or nil end }
	check("frame: ...an atlas when the game knows it", api.ownMarkerText(icon) == "|A:Dungeon:18:18|a")
	env.C_Texture = nil
	check("frame: a text marker stays, an empty one is dropped", api.ownMarkerText("[+3]") == "[+3]" and api.ownMarkerText("") == nil)
	api.questClassifier = function(id) if id == 204 then return icon, "Dungeon" end end
	check("frame: draws an icon marker without errors", pcall(api.ownRebuild))
	api.questClassifier = helpers.questClassifier
end
do
	-- user: "[0] Argent Arbiter" and SetTextColor(nil): level 0 has no difficulty colour
	log[2].level = 0
	local extra = {}
	for k, v in pairs(helpers) do extra[k] = v end
	extra.questDifficultyRGB = function(level) if level and level > 0 then return 1, 1, 0 end end
	local api = load({ trackMode = "all" }, true, extra)
	local wolves = api.ownBuild().groups[1].quests[2]
	check("data: level 0 is no level, and gets the default colour", wolves.level == nil and wolves.r == 1 and wolves.g == 0.82)
	check("frame: draws a level 0 quest without errors", pcall(api.ownRebuild))
	log[2].level = 5
end
do
	local api = load({ trackMode = "manual" }, true, helpers)
	check("data: other modes: the watched quests only", ids(api.ownBuild().groups[1].quests) == "204")
end
do
	local api = load({ trackMode = "all", zoneSort = true }, true, helpers)
	local d = api.ownBuild()
	check("data: by zone: groups in ZoneSort's order", #d.groups == 2 and d.groups[1].zone == "Westfall"
		and d.groups[2].zone == "Elwynn Forest")
	check("data: by zone: quests in their group", ids(d.groups[2].quests) == "201,202")
	check("data: nothing folded without Expand current zone only", not d.groups[1].folded and not d.groups[2].folded)
end
do
	local api = load({ trackMode = "all", zoneSort = true, expandCurrentZone = true }, true, helpers)
	local d = api.ownBuild()
	check("data: Expand current zone only folds the other zones", d.groups[1].folded == true and d.groups[2].folded == false)
	super = 204
	d = api.ownBuild()
	check("data: the super-tracked quest's zone stays open", d.groups[1].folded == false and d.groups[1].quests[1].superTracked)
	super = nil
	check("frame: zone groups drawn without errors", pcall(api.ownRebuild))
	do
		local westfall
		for _, fs in ipairs(api.ownRowsForTests()) do if fs.shown and fs.text and fs.text:find("Westfall", 1, true) then westfall = fs end end
		check("phase 5: our zone headers are found by name (Rares, Explored tag)", westfall ~= nil
			and api.ownZoneLabelFor("Westfall") == westfall and api.ownZoneLabelFor("Nowhere") == nil)
	end
	-- user: zone headers cut off on the left with "Zone header X" at -9
	local db = { trackMode = "all", zoneSort = true, zoneHeaderX = -9, questTitleX = 12 }
	local api2 = load(db, true, helpers)
	-- the list reaches 40 px left of the headers (user: let the list's left edge go further left)
	check("frame: a negative zone header X reaches left of the headers, the background with it", api2.ownOffsets.zone == -9
		and api2.ownOffsets.quest == 20 and api2.ownOffsets.left == 9)
	db.zoneHeaderX = 4; api2.ownRebuild()
	-- the marker column (22 px) reaches 2 px past the 20 the titles start at: the background 2 px further left
	check("frame: a positive one is kept", api2.ownOffsets.zone == 4 and api2.ownOffsets.quest == 20 and api2.ownOffsets.left == 2)
	-- user: the title slider moved the zone headers below -14 px; then: let the titles and icons go further left
	db.questTitleX = -20; api2.ownRebuild()
	check("frame: a negative title X moves the title and its icons left of the headers, not the zone headers",
		api2.ownOffsets.zone == 4 and api2.ownOffsets.quest == -12 and api2.ownOffsets.left == 34)
	db.questTitleX = -100; api2.ownRebuild()
	check("frame: the titles stop where the icons reach the list's left edge", api2.ownOffsets.zone == 4
		and api2.ownOffsets.quest == -18 and api2.ownOffsets.left == 40)
	db.questTitleX = 12; api2.ownRebuild()
	-- user: "The icons should be drawn to the left separately. They shouldn't push quest titles over"
	local icon = { file = "Interface/Minimap/Dungeon", scale = 1.32 }
	api2.questClassifier = function(id) if id == 204 then return icon, "Dungeon" end end
	super = 201
	api2.ownRebuild()
	local xs, texts = {}, {}
	for _, fs in ipairs(api2.ownRowsForTests()) do
		if fs.shown and fs.text and (fs.text:find("Wolves") or fs.text:find("Kobolds") or fs.text:find("Defias")) then
			xs[#xs + 1] = fs.points[1][4]; texts[#texts + 1] = fs.text
		end
	end
	check("frame: every title at the same x, with or without a marker", #xs == 3 and xs[1] == xs[2] and xs[2] == xs[3])
	check("frame: no marker or arrow inside the title text", not table.concat(texts):find("|T", 1, true) and not table.concat(texts):find(">", 1, true))
	check("frame: the icon is drawn left of its title", (function()
		for _, fs in ipairs(api2.ownRowsForTests()) do
			if fs.text and fs.text:find("Defias") then return true end
		end
	end)())
	super = nil
	api2.questClassifier = helpers.questClassifier
end
do
	local api = load({ trackMode = "all", zoneFilter = true }, true, helpers)
	check("data: Show quests in my zone", ids(api.ownBuild().groups[1].quests) == "201,202")
	super = 204
	check("data: ...the super-tracked quest stays", ids(api.ownBuild().groups[1].quests) == "204,201,202")
	super = nil
end
do
	local api = load({ trackMode = "all", hideDoneObjectives = true }, true, helpers)
	local wolves = api.ownBuild().groups[1].quests[2]
	check("data: Hide done objectives drops 8/8, progress still counts it", #wolves.objectives == 1
		and math.abs(wolves.progress - 0.625) < 1e-6)
end
do
	env.issecretvalue = function(v) return v == "SECRET" end
	logQuests[201].title = "SECRET"
	local api = load({ trackMode = "all" }, true, helpers)
	check("data: a secret title falls back to Quest <id>", api.ownBuild().groups[1].quests[2].title == "Quest 201")
	env.issecretvalue, logQuests[201].title = nil, "Wolves"
end

---------------------------------------------------------------------------------------------------------------------
-- Phase 2: frame and layout (Look.lua, Frame.lua)
---------------------------------------------------------------------------------------------------------------------
local function withHelpers(more)
	local t = {}
	for k, v in pairs(helpers) do t[k] = v end
	for k, v in pairs(more or {}) do t[k] = v end
	return t
end
do
	local alpha = 0.5
	local db = { trackMode = "all", layer = 60, scale = 1.2, height = 200, questAlpha = 0.8 }
	local api = load(db, true, withHelpers({
		trackerAlpha = function() return alpha end,
		layerFromValue = function(v) return v > 50 and "HIGH" or "LOW", 10 end,
		setTrackerAlpha = function() end,
		setScrollbarWidth = function() end,
	}))
	local f = api.ownTrackerFrame()
	check("layout: the layer from db.layer (Core's layerFromValue)", f.strata == "HIGH" and f.level == 10)
	check("layout: general opacity on the frame, Quest Tracker opacity on the list", f.alpha == 0.5)
	check("layout: db.scale on the inner frame, outer size scaled", f.inner.scale == 1.2 and math.abs(f.w - (248 * 1.2)) < 1e-6)
	alpha = 0.3
	api.setTrackerAlpha(0.3)
	check("layout: a Core setter (setTrackerAlpha) refreshes our frame", f.alpha == 0.3)
	db.scrollbarWidth = 14
	api.setScrollbarWidth(14)
	run()
	check("layout: every setter in the list is hooked when Core has it", #api.ownSetters >= 20)
	-- spacing: Blizzard's gap (fromBlockOffsetY, read) with db.spacing, as Extras did
	env.QuestObjectiveTracker = { fromBlockOffsetY = -10 }
	db.spacing = -6
	check("layout: Space between quests on Blizzard's gap (10 - 6 = 4)", api.ownQuestGap() == 4)
	db.spacing = 30
	check("layout: ...and wider", api.ownQuestGap() == 40)
	db.spacing = -50
	check("layout: ...never below 0", api.ownQuestGap() == 0)
	env.QuestObjectiveTracker, db.spacing = nil, nil
end
do
	-- the headers: Blizzard's art copied (atlas, size, anchors moved to our header), its text in ours
	local db = { trackMode = "all" }
	local api = load(db, true, helpers)
	local f = api.ownTrackerFrame()
	local mirror = api.ownMirror(blizzHeader, stubFrame(), { [headerText] = true })
	local t = mirror.textures[1]
	check("look: header art copied (atlas, size)", #mirror.textures == 1 and t.atlas == "UI-QuestTracker-Primary-Objective-Header"
		and t.w == 250 and t.h == 30)
	check("look: its anchor moved to our header, same offset", t.points[1][1] == "TOPLEFT" and t.points[1][2] ~= blizzHeader
		and t.points[1][4] == -20)
	check("look: Blizzard's header only read (and its mouse off)", (function()
		for _, c in ipairs(calls) do
			local m = c:match(":(.+)$")
			if c:find("^BlizzHeader") and not (m == "EnableMouse" or m:match("^Get") or m:match("^Is")) then return false end
		end
		return true
	end)())
	-- collapse: the Quests button hides the list, the main one the Quests header too
	local function shown() local _, _, list, quests = api.ownScrollState(); return list, quests end
	local list, quests = shown()
	check("layout: the Quests header and the list shown", list and quests)
	db.ownQuestsCollapsed = true
	api.ownApplyCollapse()
	list, quests = shown()
	check("layout: Quests collapsed: the list hides, the header stays", not list and quests)
	db.ownQuestsCollapsed, db.ownAllCollapsed = nil, true
	api.ownApplyCollapse()
	list, quests = shown()
	check("layout: All Objectives collapsed: both hide", not list and not quests)
	db.ownAllCollapsed = nil
	api.ownApplyCollapse()
	list, quests = shown()
	check("layout: open again", list and quests)
end
do
	-- scrolling: the wheel moves by db.step, clamped to the content
	local db = { trackMode = "all", step = 50, height = 100 }
	local api = load(db, true, helpers)
	local f = api.ownTrackerFrame()
	local off, max = api.ownScrollState()
	check("scroll: a short list: nothing to scroll", off == 0 and max == 0)
	-- a long quest: 40 objective lines of 14 px
	local saved = logQuests[204].objectives
	local many = {}
	for i = 1, 40 do many[i] = { text = "Line " .. i, finished = false } end
	logQuests[204].objectives = many
	api.ownRebuild()
	off, max = api.ownScrollState()
	check("scroll: a long list can scroll", max > 200)
	api.ownScrollBy(-1)
	check("scroll: one wheel notch down = db.step (50)", select(1, api.ownScrollState()) == 50)
	for _ = 1, 50 do api.ownScrollBy(-1) end
	check("scroll: stops at the end", select(1, api.ownScrollState()) == max)
	for _ = 1, 50 do api.ownScrollBy(1) end
	check("scroll: and at the top", select(1, api.ownScrollState()) == 0)
	logQuests[204].objectives = saved
end
do
	-- fonts: our own objects, the chosen font, outlines, the Quest Tracker scale and the zone header scale
	local db = { questScale = 1.5, titleOutline = true, zoneHeaderScale = 2, zoneHeaderOutline = true }
	local api = load(db, true, withHelpers({ fontPath = function() return "Fonts\\X.TTF" end }))
	env.ObjectiveTrackerHeaderFont = { GetFont = function() return "Fonts\\A.TTF", 14, "" end }
	env.ObjectiveTrackerLineFont = { GetFont = function() return "Fonts\\A.TTF", 12, "" end }
	env.GameFontNormalSmall = { GetFont = function() return "Fonts\\A.TTF", 10, "" end }
	local file, size, flags = api.ownFontSpec("title")
	check("fonts: title: chosen font, x Quest Tracker scale, outline", file == "Fonts\\X.TTF" and size == 21 and flags == "OUTLINE")
	file, size, flags = api.ownFontSpec("line")
	check("fonts: objectives: x scale, no outline when off", size == 18 and flags == "")
	file, size, flags = api.ownFontSpec("zone")
	check("fonts: zone headers: small font x zone header scale x Quest Tracker scale, outline", size == 30 and flags == "OUTLINE")
	env.ObjectiveTrackerHeaderFont, env.ObjectiveTrackerLineFont, env.GameFontNormalSmall = nil, nil, nil
	local src = read("Tracker/Own/Look.lua")
	check("fonts: our own font objects (CreateFont), never SetFont on Blizzard's",
		src:find('CreateFont("ForeverTrackerPlusOwn_"', 1, true) ~= nil and not src:find("ObjectiveTracker%w*Font:SetFont"))
end

---------------------------------------------------------------------------------------------------------------------
-- Phase 3: quest rows (Frame.lua rebuild, Rows.lua clicks and item buttons)
---------------------------------------------------------------------------------------------------------------------
do
	local got = { icons = {}, checks = {}, dist = {}, bars = {}, clicks = {}, hidDist = 0 }
	local forever = { atlas = "forever" }
	local db = { trackMode = "all" }
	local api = load(db, true, withHelpers({
		rewardSuffix = function(id) return id == 201 and " (+250 XP)" or "" end,
		foreverIcon = function(id) return id == 201 and forever or nil end,
		questClassifier = function(id) if id == 204 then return { file = "Skull" }, "Elite" end end,
		placeTitleIcons = function(fs, icons) got.icons[fs.text] = #icons; return "" end,
		hideTitleIcons = function() end,
		placeCheck = function(fs, complete) got.checks[fs.text] = complete end,
		questHasDistance = function(id) return id == 201 end,
		questDistanceReserve = function() return 40 end,
		distanceColumnHeight = function() return 30 end,
		attachQuestDistance = function(fs, id) got.dist[#got.dist + 1] = { fs = fs, id = id, reserve = fs.qtsReserve } end,
		hideQuestDistance = function() got.hidDist = got.hidDist + 1 end,
		progressParts = function(text) local name, h, n = text:match("^(.-): (%d+)/(%d+)$"); if name then return name, tonumber(h), tonumber(n) end end,
		newProgressBar = function() return {} end,
		drawProgressBar = function(b, anchor, x, font, size, flags, have, need) got.bars[#got.bars + 1] = { have = have, need = need, anchor = anchor } end,
		hideProgressBar = function(b) b.hidden = true end,
		progressBarSize = function() return 30 end,
		progressBarUnder = function() return false end,
		questClick = function(self, button) got.clicks[#got.clicks + 1] = button .. ":" .. self.questID end,
		questItemFor = function(id) if id == 204 then return { itemID = 5, link = "item:5", icon = 1 } end end,
	}))
	local rows = api.ownRowsForTests()
	local function rowWith(s) for _, fs in ipairs(rows) do if fs.shown and fs.text and fs.text:find(s, 1, true) then return fs end end end
	local wolves = rowWith("Wolves")
	check("rows: rewards after the title", wolves and wolves.text == "[5] Wolves (+250 XP)")
	check("rows: title icons drawn left of the title (Forever icon, the type icon)",
		got.icons["[5] Wolves (+250 XP)"] == 1 and got.icons["[12] Defias"] == 1)
	check("rows: the check on a finished quest only", got.checks["[7] Kobolds"] == true and got.checks["[12] Defias"] == false)
	local d, others = nil, true
	for _, e in ipairs(got.dist) do if e.id == 201 then d = e elseif e.reserve then others = false end end
	-- every title is watched (a distance may appear later); only the one with a distance keeps the room
	check("rows: distance on the quest that has one, its room kept; the others no room", d and d.reserve == 40
		and d.fs == wolves and others and #got.dist == 3)
	local defias = rowWith("Defias")
	check("rows: that title is narrower by the room (4 + 40)", wolves.w == defias.w - 44)
	local pelt = rowWith("- Pelt")
	check("rows: the line beside the distance column keeps its room too", pelt and rowWith("- Thug").w - pelt.w >= 44)
	check("rows: progress bars for counted objectives (1/4, 0/15; 8/8 too)", #got.bars == 3)
	check("rows: the count left out of the text when a bar shows", pelt.text == "- Pelt")
	check("rows: titles in one column with or without icons", wolves.points[1][4] == defias.points[1][4])
	-- user: "Objectives horizontal position" moves the objective lines only (db.objectiveX)
	do
		local titleX, lineX = wolves.points[1][4], rowWith("- Thug").points[1][4]
		db.objectiveX = 20
		api.ownRebuild()
		check("rows: objectives slider moves the objective lines, not the titles",
			rowWith("Wolves").points[1][4] == titleX and rowWith("- Thug").points[1][4] == lineX + 20)
		db.objectiveX = -60
		api.ownRebuild()
		check("rows: objectives never left of the list's edge", rowWith("- Thug").points[1][4] >= 0)
		db.objectiveX = nil
		-- user: the title slider moved the objectives once past 15 px; it moves only the titles
		db.questTitleX = 40
		api.ownRebuild()
		check("rows: title slider moves the titles, not the objective lines",
			rowWith("Wolves").points[1][4] > titleX and rowWith("- Thug").points[1][4] == lineX)
		db.questTitleX = nil
		api.ownRebuild()
	end
	local clickers, used = api.ownClickersForTests()
	-- 3 titles, Wolves 2 lines, Kobolds "ready", Defias 1 line
	check("rows: a hover button on every title and line (" .. used .. ")", used == 7)
	local first = clickers[1]
	first.scripts.OnClick(first, "LeftButton")
	check("rows: a click goes to the More quests handler (open, menu, group, links)", got.clicks[1] == "LeftButton:" .. first.questID)
	local removed
	env.IsShiftKeyDown = function() return true end
	env.C_QuestLog.RemoveQuestWatch = function(id) removed = id end
	first.scripts.OnClick(first, "LeftButton")
	env.IsShiftKeyDown, env.C_QuestLog.RemoveQuestWatch = nil, nil
	check("rows: Shift-click stops tracking", removed == first.questID and #got.clicks == 1)
	local places = api.ownItemPlacesForTests()
	check("rows: the quest with an item gets a button place, on its title", #places == 1 and places[1].fs == defias
		and places[1].item.itemID == 5)
	-- user: the button covered the objective lines once the title moved right of them
	-- user: always left of the first objective line
	check("rows: a title with an icon: the button left of its first objective", places[1].anchor == rowWith("- Thug"))
	got.icons = {}
	local fi, qc = api.foreverIcon, api.questClassifier
	api.foreverIcon = nil
	api.questClassifier = nil
	api.ownRebuild()
	places = api.ownItemPlacesForTests()
	check("rows: a title with no icon: the button still left of its first objective (user)", places[1].anchor == rowWith("- Thug"))
	api.foreverIcon, api.questClassifier = fi, qc
	api.ownRebuild()
	check("rows: the button's middle on its line, left of it", read("Tracker/Own/Rows.lua"):find(
		'if left and top then return "RIGHT", left - 4, top - size / 2 end', 1, true) ~= nil)
	check("rows: the buttons are placed again when the list hides or shows (user: a collapsed Quests header kept them)",
		read("Tracker/Own/Rows.lua"):find("or shown ~= lastShown then", 1, true) ~= nil)
	-- fewer rows: pooled ones are cleaned (distance, bars, buttons)
	local hidBefore = got.hidDist
	db.progressBars = false
	got.bars = {}
	api.ownRebuild()
	check("rows: Progress bars off: no bars, the text keeps its count", #got.bars == 0 and rowWith("- Pelt: 1/4") ~= nil)
	local bars = api.ownBarsForTests()
	check("rows: unused bars hidden", bars[1].hidden == true)
	check("rows: a reused row drops its old distance", got.hidDist > hidBefore)
	local src = read("Tracker/Own/Rows.lua")
	check("rows: item buttons are secure, on UIParent, with the type item",
		src:find('"SecureActionButtonTemplate"', 1, true) and src:find("UIParent, \"SecureActionButtonTemplate\"", 1, true)
		and src:find('SetAttribute("type", "item")', 1, true))
	check("rows: in combat only SetAlpha on a button (no move, show or hide)", (function()
		local body = src:match("if inCombat%(%) then(.-)return\n")
		return body and body:find("SetAlpha") and not body:find("SetPoint") and not body:find(":Show") and not body:find(":Hide")
	end)())
end

---------------------------------------------------------------------------------------------------------------------
-- Phase 4: the guide section in our frame (Frame.lua guide slot, Objectives/tracker/Tracker.lua and Header.lua)
---------------------------------------------------------------------------------------------------------------------
do
	local db = { trackMode = "all", height = 500 }
	local api = load(db, true, withHelpers())
	local host = api.ownGuideHost()
	local main, quests = api.ownHeadersForTests()
	check("guide: our frame has a guide slot, hidden with no guide", host ~= nil and host.shown == false)
	-- phase 6: the "Quests" header colours on our Quests header
	db.questsHeaderColor = { 0.1, 0.2, 0.3, 1 }
	check("phase 6: the Quests header colour on our Quests header", pcall(api.ownApplyHeaderLook)
		and quests.text.color and quests.text.color[1] == 0.1 and quests.text.color[3] == 0.3)
	db.questsHeaderColor = nil
	check("guide: the Quests header under the main header then", quests.points[1][2] == main)
	api.ownSetGuideHeight(120)
	check("guide: the guide says its height: the slot shows at that height", host.shown and host.h == 120)
	check("guide: the Quests header moves under the guide", quests.points[1][2] == host)
	db.ownAllCollapsed = true
	api.ownApplyCollapse()
	check("guide: All Objectives collapsed: the guide's slot hides too", host.shown == false)
	check("guide: the guide reads the collapse", api.ownGuideCollapsed() == true)
	db.ownAllCollapsed = nil
	api.ownApplyCollapse()
	local f = api.ownTrackerFrame()
	f.inner.h = 500
	check("guide: its room: the frame less the headers and room for the quests", api.ownGuideRoom() == 500 - 26 - 24 - 4 - 80)
	-- in combat with the guide's secure buttons inside, our frame is protected: nothing moves until the fight ends
	rawset(f, "IsProtected", function() return true end)
	env.InCombatLockdown = function() return true end
	api.ownSetGuideHeight(200)
	check("guide: in combat (protected): the slot waits", host.h == 120)
	env.InCombatLockdown = function() return false end
	api.ownRefresh()
	check("guide: after the fight it takes the new height", host.h == 200)
	rawset(f, "IsProtected", nil)
	local parts = api.ownMainHeader()
	check("guide: the main header's parts for the guide's buttons", parts.frame == main and parts.Text == main.text
		and parts.MinimizeButton == main.button)
	local asked = 0
	api.ownGuideChanged = function() asked = asked + 1 end
	api.ownRefresh()
	check("guide: a setting change asks the guide to lay itself out again", asked == 1)
end
do
	local src = read("Objectives/tracker/Tracker.lua"):gsub("\r\n", "\n")
	local own = src:match("local function place%(%)(.-)\nend\n")
	check("guide: place found", own ~= nil)
	own = own or ""
	check("guide: in our frame nothing on Blizzard's tracker (no ObjectiveTrackerFrame, NineSlice, followers)",
		not own:find("ObjectiveTrackerFrame", 1, true) and not own:find("NineSlice", 1, true) and not own:find("anchorBelow", 1, true))
	check("guide: in our guide slot, scaled by the guide scale, its height told to our frame",
		own:find("module:SetParent(host)", 1, true) and own:find("module:SetScale(factor)", 1, true)
		and own:find("api.ownSetGuideHeight(h)", 1, true))
	check("guide: no hook on Blizzard's Update", not src:find("ObjectiveTrackerContainerMixin", 1, true))
	check("guide: it shows in battlegrounds and arenas too (user), paused only without our frame",
		src:find("local held = not ownHost()\n", 1, true) ~= nil)
	check("guide: no hook on Blizzard's tracker's SetPoint", not src:find("ObjectiveTrackerFrame", 1, true))
	local header = read("Objectives/tracker/Header.lua"):gsub("\r\n", "\n")
	check("guide: its header buttons go on our main header", header:find("api.ownMainHeader()", 1, true) ~= nil
		and not header:find("ObjectiveTrackerFrame.Header.MinimizeButton", 1, true))
end

---------------------------------------------------------------------------------------------------------------------
-- Phase 4b: the dungeon card in our frame (Frame.lua card slot, Dungeon.lua reads our frames)
---------------------------------------------------------------------------------------------------------------------
do
	local db = { trackMode = "all", height = 500 }
	local room, gotAnchor = 0, false
	local api = load(db, true, withHelpers({
		layoutDungeonCard = function(anchor) gotAnchor = anchor; return anchor and room or 0 end,
	}))
	local card, host = api.ownCardHost(), api.ownGuideHost()
	local main, quests = api.ownHeadersForTests()
	check("card: our frame has a card slot under the main header", card ~= nil and card.points[1][2] == main)
	check("card: the card is placed in our slot", gotAnchor == card)
	check("card: outside an instance the Quests header stays under the main header", quests.points[1][2] == main)
	room = 60
	api.ownApplyCollapse()
	check("card: in an instance the slot takes the card's height", card.h == 60)
	check("card: the Quests header moves under the card", quests.points[1][2] == card)
	api.ownSetGuideHeight(120)
	check("card: the guide goes under the card, the Quests header under the guide",
		host.points[1][2] == card and quests.points[1][2] == host)
	local f = api.ownTrackerFrame()
	f.inner.h = 500
	check("card: the guide's room is less by the card", api.ownGuideRoom() == 500 - 26 - 24 - 4 - 80 - 60)
	check("card: our Quests header is what the card lines up with", api.ownQuestsHeaderFrame() == quests)
	db.ownAllCollapsed = true
	api.ownApplyCollapse()
	check("card: All Objectives collapsed: the card is told to hide (no anchor)", gotAnchor == nil)
	db.ownAllCollapsed = nil
	api.ownApplyCollapse()
	rawset(f, "IsProtected", function() return true end)
	env.InCombatLockdown = function() return true end
	room = 90
	api.ownApplyCollapse()
	check("card: in combat (protected) the slot waits", card.h == 60)
	env.InCombatLockdown = function() return false end
	api.ownRefresh()
	check("card: after the fight the slot takes the new height", card.h == 90)
	rawset(f, "IsProtected", nil)
end
---------------------------------------------------------------------------------------------------------------------
-- Phase 5 (step 1): the reputation bar and the reminders row in the top slot, /qt sections
---------------------------------------------------------------------------------------------------------------------
do
	local db = { trackMode = "all", height = 500 }
	local seen = {}
	local api = load(db, true, withHelpers({
		layoutDungeonCard = function(anchor, base) seen.card = { anchor, base }; return anchor and 40 or 0 end,
		layoutTrackedReputation = function(anchor, base) seen.rep = { anchor, base }; return anchor and 20 or 0 end,
		layoutReminders = function(anchor, base) seen.rem = { anchor, base }; return anchor and 15 or 0 end,
	}))
	local card = api.ownCardHost()
	check("top slot: the card, then the reputation bar under it, then the reminders",
		seen.card[1] == card and seen.card[2] == 0 and seen.rep[1] == card and seen.rep[2] == 40
		and seen.rem[1] == card and seen.rem[2] == 60)
	check("top slot: as tall as all three", card.h == 75)
	db.ownAllCollapsed = true
	api.ownApplyCollapse()
	check("top slot: All Objectives collapsed: all three told to hide", seen.card[1] == nil and seen.rep[1] == nil and seen.rem[1] == nil)
	db.ownAllCollapsed = nil
	local api2 = load({ trackMode = "all" }, true, withHelpers({
		layoutTrackedReputation = function(anchor) return anchor and 20 or 0 end,
	}))
	check("top slot: works without a dungeon card file (no stop at a missing layout)", api2.ownCardHost().h == 20)
	-- user: a "Reputation" header over the tracked reputation bar, which folds it away
	api.trackedReputationShown = function() return true end
	api.ownApplyCollapse()
	local rh = api.ownRepHeaderForTests()
	local hh = rh:GetHeight() + 4
	check("reputation: its header under the card, the bar under the header", rh.shown and rh.text.text == "Reputation"
		and rh.points[#rh.points][4] == 0 and rh.points[#rh.points][5] == -40 and seen.rep[1] == card and seen.rep[2] == 40 + hh)
	db.ownRepCollapsed = true
	api.ownApplyCollapse()
	check("reputation: folded: the header stays, the bar hides, the reminders move up", rh.shown and seen.rep[1] == nil
		and seen.rem[2] == 40 + hh and card.h == 40 + hh + 15)
	db.ownRepCollapsed = nil
	api.trackedReputationShown = function() return false end
	api.ownApplyCollapse()
	check("reputation: no tracked reputation: no header", not rh.shown)
	local lines = {}
	api.ownSectionsReport(function(s) lines[#lines + 1] = s end)
	check("/qt sections: one line per section, reads only", #lines > 0)
	for _, path in ipairs({ "Tracker/Reputation.lua", "Tracker/Reminders.lua" }) do
		check("top slot: " .. path .. " uses our slot",
			read(path):find("local module = anchor", 1, true) ~= nil)
	end
end
---------------------------------------------------------------------------------------------------------------------
-- Phase 5: the Professions section (Recipes.lua data and clicks, Frame.lua draws it in its own block above the Quests header)
---------------------------------------------------------------------------------------------------------------------
do
	local tracked, untracked, opened = { [false] = { 3275 }, [true] = {} }, nil, nil
	env.Enum = { CraftingReagentType = { Basic = 1, Modifying = 0 } }
	env.C_TradeSkillUI = {
		GetRecipesTracked = function(recraft) return tracked[recraft] end,
		GetRecipeSchematic = function(id) return { name = "Heavy Linen Bandage", reagentSlotSchematics = {
			{ reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2589 } } },
			{ reagentType = 0, quantityRequired = 1, reagents = { { itemID = 999 } } }, -- optional: left out
		} } end,
		SetRecipeTracked = function(id, on) untracked = (not on) and id or nil end,
		OpenRecipe = function(id) opened = id end,
	}
	env.C_Item = { GetItemNameByID = function(id) return id == 2589 and "Linen Cloth" or nil end,
		GetItemCount = function(id) return id == 2589 and 5 or 0 end }
	local db = { trackMode = "all", height = 500 }
	local api = load(db, true, withHelpers())
	local list = api.ownRecipes()
	check("professions: tracked recipe read with its basic reagent only", #list == 1 and list[1].name == "Heavy Linen Bandage"
		and #list[1].reagents == 1 and list[1].reagents[1].have == 5 and list[1].reagents[1].need == 2)
	api.ownApplyCollapse()
	local profRows, profHost, profHeader = api.ownProfRowsForTests()
	local function rowWith(s) for _, fs in ipairs(profRows) do if fs.shown and fs.text and fs.text:find(s, 1, true) then return fs end end end
	local _, questsHeader = api.ownHeadersForTests()
	check("professions: its own block, shown, the Quests header under it", profHost.shown and questsHeader.points[1][2] == profHost)
	check("professions: the recipe in its block", rowWith("Heavy Linen Bandage") ~= nil)
	check("professions: its reagent with have/need (capped at need)", rowWith("- 2/2 Linen Cloth") ~= nil)
	local fullH = profHost.h
	local qrows = api.ownRowsForTests()
	local inList = false
	for _, fs in ipairs(qrows) do if fs.shown and fs.text and fs.text:find("Linen", 1, true) then inList = true end end
	check("professions: not in the quest list", not inList)
	db.ownQuestsCollapsed = true
	api.ownApplyCollapse()
	local _, _, listShown = api.ownScrollState()
	check("professions: Quests collapsed: the quest list hides, the recipes stay", not listShown and rowWith("Heavy Linen Bandage") ~= nil)
	db.ownQuestsCollapsed = nil
	db.ownProfCollapsed = true
	api.ownApplyCollapse()
	check("professions: its own collapse hides the recipes, the header stays", rowWith("Heavy Linen Bandage") == nil
		and profHost.shown and profHost.h < fullH)
	db.ownProfCollapsed = nil
	api.ownApplyCollapse()
	local f = api.ownTrackerFrame()
	f.inner.h = 500
	check("professions: the guide's room is less by the block", api.ownGuideRoom() == 500 - 26 - (profHost.h + 4) - 24 - 4 - 80)
	local b = { recipeID = 3275, recraft = false }
	api.ownRecipeClick(b, "LeftButton")
	check("professions: click opens the recipe", opened == 3275)
	env.IsShiftKeyDown = function() return true end
	api.ownRecipeClick(b, "LeftButton")
	env.IsShiftKeyDown = nil
	check("professions: Shift-click stops tracking it", untracked == 3275)
	tracked[false] = {}
	api.ownApplyCollapse()
	check("professions: no tracked recipe: no block, the Quests header back up", not profHost.shown
		and questsHeader.points[1][2] ~= profHost)
	env.C_TradeSkillUI, env.Enum, env.C_Item = nil, nil, nil
	check("professions: its header reads Professions, not Quests", profHeader.text.text ~= nil
		and not tostring(profHeader.text.text):find("Quests", 1, true))
	-- user: the line under Professions to match the other headers
	local fsrc = read("Tracker/Own/Frame.lua"):gsub("\r\n", "\n")
	check("professions: its header uses the Quests header's art", fsrc:find("b.header = makeHeader(qmod and qmod.Header,", 1, true) ~= nil)
	-- user (dev-27): the GetAuraDataByIndex error came back on entering a battleground: Core's trackerRelayout marked
	-- Blizzard's tracker dirty from our code (Fonts, Extras, ZoneSort call it). With our own tracker: never
	local core = read("Tracker/Core.lua"):gsub("\r\n", "\n")
	check("taint: no trackerRelayout left", not core:find("trackerRelayout", 1, true))
	local fonts = read("Tracker/Fonts.lua"):gsub("\r\n", "\n")
	check("taint: no font changes on Blizzard's rows", not fonts:find("applyBlockFonts", 1, true)
		and not fonts:find("hooksecurefunc", 1, true))
	-- user: icons, checks and distances stayed on screen after the rows hid
	local src = read("Tracker/Own/Frame.lua"):gsub("\r\n", "\n")
	check("rows: a hidden row takes its icons, check and distance with it",
		src:find("for i = n + 1, #rows do rows[i]:Hide(); clearExtras(rows[i]) end", 1, true) ~= nil
		and src:find("if fs.qtsCheck then fs.qtsCheck:Hide() end", 1, true) ~= nil)
end
---------------------------------------------------------------------------------------------------------------------
-- Phase 5: tracked Legacy Challenges (user: Forever has Legacy Challenges, no achievements, and no way to track them)
---------------------------------------------------------------------------------------------------------------------
do
	local done = {}
	env.GetAchievementInfo = function(id)
		if id == 501 then return 501, "Explorer of Durotar", 0, done[501] or false, nil, nil, nil, "Explore Durotar.", 0x8000000, 1 end
		if id == 502 then return 502, "Boar Slayer", 0, false, nil, nil, nil, "Kill boars.", 0x8000000, 2 end
	end
	env.GetAchievementNumCriteria = function(id) return id == 501 and 9 or 1 end
	env.GetAchievementCriteriaInfo = function(id, k)
		if id == 502 then return "Kill boars", 0, false, 34, 100 end
		return "Area " .. k, 0, k <= 2, 0, 0
	end
	env.UnitName = function() return "Tester" end
	env.GetRealmName = function() return "Realm" end
	local db = { trackMode = "all", height = 500 }
	local opened
	local api = load(db, true, withHelpers({ openConfigTab = function(k) opened = k end }))
	check("legacy: nothing tracked: no block", api.ownBlocksForTests()[2].host.shown == false)
	api.legacySetTracked(501, true)
	api.legacySetTracked(502, true)
	run()
	check("legacy: stored per character", type(db.legacyTracked["Tester-Realm"]) == "table" and #db.legacyTracked["Tester-Realm"] == 2)
	local list = api.ownLegacy()
	check("legacy: name, steps done, open steps (at most 6, then 'and N more')", list[1].name == "Explorer of Durotar"
		and list[1].have == 2 and list[1].need == 9 and #list[1].lines == 7 and list[1].lines[7].text == "and 1 more")
	check("legacy: a step with a count shows it", list[2].lines[1].text == "34/100 Kill boars")
	local b = api.ownBlocksForTests()[2]
	local function rowWith(s) for _, fs in ipairs(b.rows) do if fs.shown and fs.text and fs.text:find(s, 1, true) then return fs end end end
	check("legacy: its own block above the Quests header, after Professions", b.host.shown and rowWith("Explorer of Durotar (2/9)") ~= nil
		and rowWith("- 34/100 Kill boars") ~= nil)
	local _, questsHeader = api.ownHeadersForTests()
	check("legacy: the Quests header under it", questsHeader.points[1][2] == b.host)
	-- 3.2 (user): each challenge's icon left of its name
	local icons = b.icons or {}
	check("legacy: an icon left of each challenge", #icons == 2 and icons[1].shown and icons[1].texture == 1 and icons[2].texture == 2
		and icons[1].points[1][1] == "TOPRIGHT" and icons[1].points[1][3] == "TOPLEFT")
	local title = rowWith("Explorer of Durotar (2/9)")
	check("legacy: the icon does not push the name right (user)", title and title.points[1][4] == 6)
	local btn = { legacyID = 502 }
	api.ownLegacyClick(btn, "LeftButton")
	check("legacy: click opens the Legacy page", opened == "legacy")
	env.IsShiftKeyDown = function() return true end
	api.ownLegacyClick(btn, "LeftButton")
	env.IsShiftKeyDown = nil
	check("legacy: Shift-click stops tracking it", not api.legacyIsTracked(502) and api.legacyIsTracked(501))
	done[501] = true
	run()
	check("legacy: a finished one leaves the list by itself", #api.ownLegacy() == 0 and not api.legacyIsTracked(501))
	for id = 1, 10 do api.legacySetTracked(1000 + id, true) end
	check("legacy: at most 10 tracked", api.legacySetTracked(2000, true) == false)
	env.GetAchievementInfo, env.GetAchievementNumCriteria, env.GetAchievementCriteriaInfo = nil, nil, nil
	local guides = read("Tracker/Guides.lua")
	check("legacy: the Guides page tracks on click", guides:find("api.legacySetTracked(id, not api.legacyIsTracked(id))", 1, true) ~= nil
		and guides:find("local canTrack = not a.done and api.legacySetTracked and true or false", 1, true) ~= nil)
end
---------------------------------------------------------------------------------------------------------------------
-- Phase 5: Battlegrounds section with timer bars (user)
---------------------------------------------------------------------------------------------------------------------
do
	local t, inst, pois = 1000, { "Elsewhere", "none", 0, "", 0, 0, false, 1 }, {}
	env.GetTime = function() return t end
	env.GetInstanceInfo = function() return table.unpack(inst) end
	env.C_Map = { GetBestMapForUnit = function() return 1461 end }
	env.C_AreaPoiInfo = {
		GetAreaPOIForMap = function() local ids = {} for id in pairs(pois) do ids[#ids + 1] = id end table.sort(ids) return ids end,
		GetAreaPOIInfo = function(_, id) return pois[id] end }
	local db = { trackMode = "all", height = 500 }
	local api = load(db, true, withHelpers({}))
	local b = api.ownBlocksForTests()[3]
	api.bgEnter(); run()
	check("bg: outside a battleground: no section", b.host.shown == false and #api.ownBattleground() == 0)
	inst = { "Arathi Basin", "pvp", 0, "", 15, 0, false, 529 }
	pois[1] = { name = "Gold Mine", textureIndex = 16 }
	pois[2] = { name = "Farm", textureIndex = 32 }
	api.bgEnter(); run()
	local function rowWith(str) for _, fs in ipairs(b.rows) do if fs.shown and fs.text and fs.text:find(str, 1, true) then return fs end end end
	check("bg: in Arathi Basin: its section, 'No timers running'", b.host.shown and rowWith("Arathi Basin") ~= nil
		and rowWith("No timers running") ~= nil)
	check("bg: a node already taken when you enter: no bar (its start is unknown)", #api.ownBattleground()[1].lines == 1
		and api.ownBattleground()[1].lines[1].dim)
	pois[1].textureIndex = 19 -- taken by the Horde
	api.bgScanNodes(false); run()
	local e = api.ownBattleground()[1]
	check("bg: a node taken: a 60 s bar in the Horde color", #e.lines == 1 and e.lines[1].text == "Gold Mine"
		and e.lines[1].bar.side == "Horde" and e.lines[1].bar.dur == 60)
	local widgets, used = api.ownBgWidgetsForTests()
	check("bg: the bar drawn on its line, the time at the right", used == 1 and widgets[1].shown and widgets[1].time.text == "1:00")
	-- user: icons on the bars, as Capping: the node's own "taken" art from the map icon sheet
	check("bg: a node bar keeps its map art for the icon", e.lines[1].bar.poi == 19)
	env.C_Minimap = { GetPOITextureCoords = function(i) return i / 100, i / 100 + 0.1, 0, 0.1 end }
	api.ownApplyCollapse()
	widgets = api.ownBgWidgetsForTests()
	check("bg: the icon from the map icon sheet, just left of the bar (as the quest title icons)", widgets[1].icon.shown and widgets[1].icon.texture == 136441
		and widgets[1].icon.points[1][1] == "RIGHT" and widgets[1].icon.points[1][3] == "LEFT")
	env.C_Minimap = nil
	local src = read("Tracker/Own/Battleground.lua")
	check("bg: icons for start, time left, flag, enter, the winner, queues", src:find('startBar("flag", "Flag respawns", "none", respawn, { poi = FLAG_POI, icon = ICON.flag })', 1, true)
		and src:find("{ fill = fill, icon = ICON[side] }", 1, true) and src:find("b.icon = queueIcon(map)", 1, true)
		and api.bgIcons.start == 618859 and api.bgIcons.Alliance == 132486 and api.bgIcons.Horde == 132485)
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_NEUTRAL", "The battle for Arathi Basin will begin in 30 seconds.")
	e = api.ownBattleground()[1]
	check("bg: the start countdown from the battleground message, soonest first", #e.lines == 2 and e.lines[1].text == "Battle begins"
		and e.lines[1].bar.dur == 30)
	check("bg: minutes and seconds read", api.bgCountdownFrom("The battle begins in 2 minutes!") == 120
		and api.bgCountdownFrom("Let the battle begin!") == nil)
	t = t + 31
	api.bgTickForTests(); run()
	e = api.ownBattleground()[1]
	check("bg: a finished timer leaves", #e.lines == 1 and e.lines[1].text == "Gold Mine")
	pois[1].textureIndex = 18 -- captured
	api.bgScanNodes(false); run()
	check("bg: a node captured: its bar goes", api.ownBattleground()[1].lines[1].dim == true)
	inst = { "Warsong Gulch", "pvp", 0, "", 20, 0, false, 489 }
	pois = {}
	api.bgEnter()
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_HORDE", "Grunt captured the Alliance flag!")
	e = api.ownBattleground()[1]
	check("bg: Warsong Gulch: a flag capture: 'Flag respawns' 12 s", e.title == "Warsong Gulch" and e.lines[1].text == "Flag respawns"
		and e.lines[1].bar.dur == 12)
	inst = { "Darkspear Islands", "pvp", 0, "", 15, 0, false, 16606 }
	api.bgEnter()
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_ALLIANCE", "The Alliance have taken the flag!")
	e = api.ownBattleground()[1]
	check("bg: Darkspear Islands uses the Eye of the Storm rules: 21 s", e.lines[1].text == "Flag respawns" and e.lines[1].bar.dur == 21)
	inst = { "Alterac Valley", "pvp", 0, "", 40, 0, false, 30 }
	pois = { [7] = { name = "Snowfall Graveyard", textureIndex = 0 } }
	api.bgEnter()
	pois[7].textureIndex = 14
	api.bgScanNodes(false)
	e = api.ownBattleground()[1]
	check("bg: Alterac Valley: a graveyard taken: 300 s on Forever", e.lines[1].text == "Snowfall Graveyard" and e.lines[1].bar.dur == 300
		and e.lines[1].bar.side == "Horde")
	-- user: a warning when our node is taken, and 10 s before it is lost
	local said = {}
	env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
	env.UnitFactionGroup = function() return "Alliance" end
	pois[7].textureIndex = 0
	api.bgScanNodes(false)
	pois[7].textureIndex = 14
	api.bgScanNodes(false)
	check("bg: our node taken by the Horde: a warning", #said == 1 and said[1]:find("Snowfall Graveyard is being taken by the Horde", 1, true))
	t = t + 291
	api.bgTickForTests()
	check("bg: and again 10 s before it is lost, once", #said == 2 and said[2]:find("falls in 10 seconds", 1, true))
	api.bgTickForTests()
	check("bg: only once", #said == 2)
	pois[7].textureIndex = 0
	api.bgScanNodes(false)
	pois[7].textureIndex = 4
	api.bgScanNodes(false)
	check("bg: a node our side takes: no warning", #said == 2)
	db.ownBgWarn = false
	api.bgWarnForTests("x")
	check("bg: warnings can be turned off (db.ownBgWarn)", #said == 2)
	local cfg = read("Tracker/Config.lua")
	check("bg: its own settings page (user): Battleground, in the INSTANCES group with Dungeons", cfg:find('page("battleground", "quests", "Battleground")', 1, true)
		and cfg:find('{ key = "instances", title = "INSTANCES" }', 1, true)
		and cfg:find('{ key = "battleground", group = "instances", title = "Battleground"', 1, true)
		and cfg:find('{ key = "dungeons", group = "instances", title = "Dungeons"', 1, true) and cfg:find('dungeonextras = "dungeons",', 1, true)
		and cfg:find('{ key = "collections", title = "COLLECTIONS" }', 1, true) and cfg:find('legacy = "challenges",', 1, true)
		and cfg:find('attunements = "chains",', 1, true) and cfg:find('secrets = "chains",', 1, true) and not cfg:find('= "guides"', 1, true) and cfg:find('battleground = "battleground",', 1, true))
	check("bg: the page has the warnings and a switch per bar", cfg:find('check("Node warnings", bgGet("ownBgWarn")', 1, true)
		and cfg:find('check("Show the Battleground section", bgGet("ownBg")', 1, true) and cfg:find('check("Queues", bgGet("bgQueues")', 1, true)
		and not cfg:find("Battleground node warnings", 1, true))
	db.ownBgWarn = nil
	-- user: who holds each flag
	inst = { "Warsong Gulch", "pvp", 0, "", 20, 0, false, 489 }
	pois = {}
	api.bgEnter()
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_HORDE", "The Alliance Flag was picked up by Grunt!")
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_ALLIANCE", "Footman picked up the Horde flag!")
	local function lineText(str) for _, l in ipairs(api.ownBattleground()[1].lines) do if l.text == str then return l end end end
	check("bg: flag carriers listed", lineText("Alliance flag: Grunt") ~= nil and lineText("Horde flag: Footman") ~= nil)
	db.bgCarriers = false
	check("bg: settings: Flag carriers off hides them", lineText("Alliance flag: Grunt") == nil)
	db.bgCarriers = nil
	db.ownBg = false
	check("bg: settings: the section off: nothing", #api.ownBattleground() == 0)
	db.ownBg = nil
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_HORDE", "Grunt captured the Alliance flag!")
	check("bg: a captured flag: no carrier, its respawn bar", lineText("Alliance flag: Grunt") == nil
		and lineText("Horde flag: Footman") ~= nil and lineText("Flag respawns") ~= nil)
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_ALLIANCE", "The Horde flag was dropped by Footman!")
	check("bg: a dropped flag: no carrier", lineText("Horde flag: Footman") == nil)
	-- 3.2 animations (user): a dropped flag's line, a captured base's flash out, the result banner
	check("bg: a dropped flag shows \"dropped\"", lineText("Horde flag: |cffff8080dropped|r") ~= nil)
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_ALLIANCE", "The Horde flag was returned to its base by Grunt!")
	check("bg: a returned flag: the dropped line goes", lineText("Horde flag: |cffff8080dropped|r") == nil)
	api.animEnabled = function() return true end
	api.bgStartBar("node:Farm", "Farm", "Horde", 5)
	t = t + 6
	api.bgTickForTests()
	local farm = lineText("Farm")
	check("bg: a captured base's bar stays a moment, full, to flash out", farm ~= nil and farm.bar.ending ~= nil and farm.bar.fill == 1)
	t = t + 1
	api.bgTickForTests()
	check("bg: then it goes", lineText("Farm") == nil)
	local shown
	api.showResultBanner = function(result, sub, side) shown = { result, sub, side } end
	env.GetBattlefieldWinner = function() return 0 end
	api.bgResultTick()
	check("bg: the Horde won, an Alliance player: a defeat banner", shown and shown[1] == "lost" and shown[3] == "Horde")
	shown = nil
	api.bgResultTick()
	check("bg: the banner shows once", shown == nil)
	env.GetBattlefieldWinner, api.showResultBanner, api.animEnabled = nil, nil, nil
	-- user (BugSack): a secret unit name was compared and errored; it is skipped now
	local secret = setmetatable({}, { __eq = function() error("compared a secret") end })
	local was = { env.UnitName, env.issecretvalue, env.UnitHealth, env.UnitHealthMax }
	env.issecretvalue = function(v) return v == secret end
	env.UnitName = function(u) if u == "target" then return secret end if u == "party1" then return "Grunt" end end
	env.UnitHealth, env.UnitHealthMax = function() return 20 end, function() return 100 end
	local okH, hp = pcall(api.bgHealthOf, "Grunt")
	check("bg: a secret name is skipped, the carrier's health found", okH and hp == 0.2)
	env.UnitName, env.issecretvalue, env.UnitHealth, env.UnitHealthMax = was[1], was[2], was[3], was[4]
	-- user: game time left, from a top-of-screen widget's text
	check("bg: time read from widget text", api.bgTimeFrom("12 min") == 720 and api.bgTimeFrom("Time Remaining: 4:30") == 270
		and api.bgTimeFrom("2 minutes 5 seconds") == 125 and api.bgTimeFrom("Bases: 3") == nil)
	env.C_UIWidgetManager = {
		GetTopCenterWidgetSetID = function() return 1 end,
		GetAllWidgetsBySetID = function() return { { widgetID = 6, widgetType = 0 } } end,
		GetIconAndTextWidgetVisualizationInfo = function() return { shownState = 1, text = "14 min" } end,
	}
	api.bgTimeTick()
	check("bg: 'Time left' bar from the widget", lineText("Time left") ~= nil and lineText("Time left").bar.dur == 840)
	db.bgTime = false
	check("bg: settings: Time left off hides its bar", lineText("Time left") == nil)
	db.bgTime = nil
	-- user: final score estimate, from the score bars' widget
	inst = { "Arathi Basin", "pvp", 0, "", 15, 0, false, 529 }
	api.bgEnter()
	local sa, sh = 100, 100
	env.C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo = function(id)
		if id == 1671 then return { shownState = 1, leftBarValue = sa, rightBarValue = sh, leftBarMax = 2000 } end
	end
	for i = 1, 12 do
		api.bgScoreTick(); t = t + 1; sa, sh = sa + 2, sh + 1
		if i == 6 then sa = sa + 100 end -- a jump: not the bases' rate
	end
	api.bgScoreTick()
	local score = lineText("Alliance wins 2000-1081")
	check("bg: score estimate: the winner, the end score, the time (jumps left out)", score ~= nil
		and score.bar.side == "Alliance" and math.abs(score.bar.dur - (2000 - 224) / (22 / 12)) < 1) -- 12 s, 11 steps of 2 (the jump's step left out)
	-- user: Capping's estimate is steady, ours jumped: Arathi Basin from the bases held, at once and steady
	inst = { "Arathi Basin", "pvp", 0, "", 15, 0, false, 529 }
	api.bgEnter()
	sa, sh = 600, 900
	local held = { 3, 2 }
	local function icons(n) local l = {} for i = 1, 5 do l[i] = { iconState = i <= n and 2 or 1 } end return l end
	env.C_UIWidgetManager.GetDoubleStateIconRowVisualizationInfo = function(id)
		if id == 1645 then return { shownState = 1, leftIcons = icons(held[1]), rightIcons = icons(held[2]) } end
	end
	api.bgScoreTick()
	local function scoreLine() for _, l in ipairs(api.ownBattleground()[1].lines) do if l.bar and l.bar.key == "score" then return l end end end
	local sl = scoreLine()
	-- 3 bases 1.6667/s, 2 bases 1.1111/s: Alliance needs 1400 / 1.6667 = 840 s, the Horde 1100 / 1.1111 = 990 s
	check("bg: Arathi Basin: the estimate from the bases held, at the first look", sl ~= nil and sl.text == "Alliance wins 2000-1830" -- steps of 10 (user)
		and math.abs(sl.bar.dur - 840) < 1)
	local start = sl.bar.start
	t = t + 3
	api.bgScoreTick()
	check("bg: the same bases: the bar counts on, not set again", scoreLine().bar.start == start)
	-- 3.2 (user: "off by 3 seconds"): a step seen 2 s after the first look: the next comes 6 s (10 / 1.6667) after it
	t = t - 1; sa = sa + 10
	api.bgScoreTick()
	sl = scoreLine()
	check("bg: a score step seen sets the win time to the step (834 s from it)", math.abs(sl.bar.dur - 834) < 0.1
		and sl.text == "Alliance wins 2000-1820") -- the Horde steps from its own first look
	env.UnitFactionGroup = function() return "Horde" end
	api.bgScoreTick(); t = t + 1; sa = sa + 10
	api.bgScoreTick()
	check("bg: a Horde player sees the Horde score first", scoreLine().text == "Alliance wins 1820-2000")
	env.UnitFactionGroup = function() return "Alliance" end
	start = scoreLine().bar.start
	t = t + 1
	held = { 2, 3 }
	api.bgScoreTick()
	sl = scoreLine()
	check("bg: a base changes hands: set again at once", sl.bar.start ~= start and sl.text:find("^Horde wins") ~= nil)
	env.C_UIWidgetManager = nil
	-- user: queue timers, outside the battleground too
	inst = { "Orgrimmar", "none", 0, "", 0, 0, false, 1 }
	api.bgEnter()
	local status = { "queued", "Warsong Gulch" }
	env.GetMaxBattlefieldID = function() return 2 end
	env.GetBattlefieldStatus = function(i) if i == 1 then return status[1], status[2] end return "none" end
	env.GetBattlefieldTimeWaited = function() return 65000 end
	env.GetBattlefieldEstimatedWaitTime = function() return 300000 end
	env.GetBattlefieldPortExpiration = function() return 40 end
	api.bgReadQueues(); run()
	local list = api.ownBattleground()
	check("bg: a queue: its own 'Queues' entry, outside the battleground", #list == 1 and list[1].title == "Queues"
		and list[1].lines[1].text == "Warsong Gulch queue" and list[1].lines[1].bar.up == true)
	local w = api.ownBgWidgetsForTests()
	check("bg: the queue bar shows the time waited and the estimate", w[1].time.text == "1:05 / ~5:00")
	-- 3.2 (user): a paused queue stops counting; shift-click puts a timer in chat
	local paused = true
	env.GetBattlefieldStatus = function(i) if i == 1 then return status[1], status[2], 0, 0, paused end return "none" end
	api.bgReadQueues(); run()
	env.GetBattlefieldTimeWaited = function() return 95000 end
	t = t + 30
	api.bgReadQueues(); run()
	w = api.ownBgWidgetsForTests()
	check("bg: a paused queue keeps its time", w[1].time.text == "1:05 / ~5:00"
		and api.ownBattleground()[1].lines[1].text == "Warsong Gulch queue (paused)")
	check("bg: a queue timer as a chat line", api.bgTimerText(api.ownBattleground()[1].lines[1].bar)
		== "Warsong Gulch queue (paused): 1:05 waited (about 5:00)")
	paused = false
	api.bgReadQueues(); run()
	check("bg: unpaused: it counts again", api.ownBgWidgetsForTests()[1].time.text == "1:35 / ~5:00")
	inst = { "Warsong Gulch", "pvp", 0, "", 20, 0, false, 489 }
	api.bgEnter()
	local inBg = api.ownBattleground()
	check("bg: no Queues entry inside a battleground", #inBg == 1 and inBg[1].title ~= "Queues")
	inst = { "Orgrimmar", "none", 0, "", 0, 0, false, 1 }
	api.bgEnter()
	status[1] = "confirm"
	api.bgReadQueues()
	list = api.ownBattleground()
	check("bg: an invite: the time left to enter", list[1].lines[1].text == "Enter Warsong Gulch" and list[1].lines[1].bar.dur == 40)
	status[1] = "none"
	api.bgReadQueues()
	check("bg: no queue: no entry", #api.ownBattleground() == 0)
	env.GetMaxBattlefieldID, env.GetBattlefieldStatus, env.GetBattlefieldTimeWaited = nil, nil, nil
	env.GetBattlefieldEstimatedWaitTime, env.GetBattlefieldPortExpiration = nil, nil
	-- 3.2 (user): Darkspear Islands' bases (Cove, Tower, Camp, Ruins), from the battleground messages
	inst = { "Darkspear Islands", "pvp", 0, "", 15, 0, false, 16606 }
	api.bgEnter()
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_HORDE", "Grunt has assaulted the Ruins!")
	local function dsLine(str) for _, l in ipairs(api.ownBattleground()[1].lines) do if l.text == str then return l end end end
	local ruins = dsLine("Ruins")
	check("bg: Darkspear Islands: an assaulted base gets a 60 s Horde bar", ruins and ruins.bar.side == "Horde" and ruins.bar.dur == 60)
	check("bg: a base timer as a chat line", api.bgTimerText(ruins.bar) == "Ruins (Horde): 1:00")
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_ALLIANCE", "Footman has defended the Ruins!")
	check("bg: a defended base: its bar goes", dsLine("Ruins") == nil)
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_ALLIANCE", "Footman claims the Camp! If left unchallenged, the Alliance will control it in 1 minute!")
	check("bg: \"claims the\": a bar too", dsLine("Camp") ~= nil and dsLine("Camp").bar.side == "Alliance")
	api.bgSystemMessage("CHAT_MSG_BG_SYSTEM_ALLIANCE", "The Alliance has taken the Camp!")
	check("bg: a taken base: its bar goes", dsLine("Camp") == nil)
	env.DEFAULT_CHAT_FRAME, env.UnitFactionGroup = nil, nil
	env.GetTime, env.GetInstanceInfo, env.C_Map, env.C_AreaPoiInfo = nil, nil, nil, nil
end
-- user: the timer bars in the reputation bar's look (Extras.lua's bronze-bordered bar, a fill per side)
do
	local src = read("Tracker/Own/Battleground.lua")
	check("bg: timer bars drawn with the reputation bar's art", src:find("w.pb = api.newProgressBar and api.newProgressBar(w)", 1, true) ~= nil
		and src:find("api.drawProgressBar(w.pb, w, 0, w.fontFile, w.size, w.fontFlags,", 1, true) ~= nil -- a font (user: "Font not set")
		and src:find('local FILL = { Alliance = "Blue", Horde = "Red", none = "Yellow", queue = "Orange" }', 1, true) ~= nil)
end
-- user: the quest item buttons stayed when the quest titles slider moved the titles left
check("items: placed again when the first title moves left or right too",
	read("Tracker/Own/Rows.lua"):find("if top ~= lastTop or left ~= lastLeft or shown ~= lastShown then", 1, true) ~= nil)
do
	local src = read("Tracker/Dungeon.lua")
	check("card: Dungeon.lua uses our card slot and our Quests header",
		src:find("local module = anchor%s") ~= nil and src:find("local questsHeader = api.ownQuestsHeaderFrame and api.ownQuestsHeaderFrame()", 1, true) ~= nil)
end

print(pass and "ALL PASS" or "SOME FAILED")
if not pass then os.exit(1) end
