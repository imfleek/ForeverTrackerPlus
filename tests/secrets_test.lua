-- 3.1.2 Guides > Secrets: steps tick themselves, a later step ticks the ones before, faction-only secrets, the found
-- counter (with the sleeping bag and the library), waypoint clicks through several spots, the chat line once.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local function obj() return setmetatable({}, { __index = function() return function() end end }) end

local done, bags, toys = {}, {}, {}
local faction = "Horde"
local chat, waypoints, afters = {}, {}, {}
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return obj() end,
	GetTime = function() return 100 end,
	C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end, GetLogIndexForQuestID = function() return nil end },
	C_Item = { GetItemCount = function(id) return bags[id] or 0 end, GetItemIconByID = function(id) return "icon" .. id end },
	C_Map = { CanSetUserWaypointOnMap = function() return true end, SetUserWaypoint = function(p) waypoints[#waypoints + 1] = p end },
	UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end },
	PlayerHasToy = function(id) return toys[id] == true end,
	UnitFactionGroup = function() return faction end,
	C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end },
	DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) chat[#chat + 1] = t end }, GameTooltip = obj(),
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Guides.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do fn() end
local api = ns.api

local function rows() return api.guideSecretRows() end
local function find(text) for i, r in ipairs(rows()) do if r[2] and r[2]:find(text, 1, true) then return r, i end end end

local head = rows()[1]
check("header: the counter, Chicken Egg left out for the Horde", head.header and head[3] == "0 of 8 found")
local egg = find("Chicken Egg")
check("Chicken Egg: Alliance only, grey, no steps", egg and egg[3] == "Alliance only" and not find("CLUCK!"))
faction = "Alliance"
check("Alliance: 9 secrets", rows()[1][3] == "0 of 9 found")
check("Alliance: the egg's steps show", find("CLUCK!") ~= nil)

-- self-ticking steps
local alcaz = find("Alcaz Operative Insignia")
check("Alcaz: a toy, 0 of 4 steps", alcaz[3] == "Toy, 0 of 4 steps")
bags[274041] = 1
local box = find("State Secrets")
check("an item for a quest step: in your bags, turn it in", box[3] == "in your bags: turn it in")
bags[279450] = 6
check("6 insignia: that step and every one before it done", find("Alcaz Operative Insignia")[3] == "Toy, 4 of 4 steps"
	and find("Free Mason Connery")[3] == "done")
bags[279450] = 5
check("5 insignia: not done", find("Collect 6 Fractured Insignia")[3] ~= "done")
toys[279471] = true
check("the toy known: found, one green line", find("Alcaz Operative Insignia")[3] == "found" and not find("Free Mason Connery"))
check("counter counts it", rows()[1][3] == "1 of 9 found")
local foundRow = find("Alcaz Operative Insignia")
check("found: it keeps its own icon and its gold name (user)", not tostring(foundRow[1]):find("ReadyCheck", 1, true)
	and type(foundRow[4]) == "table" and foundRow[4][1] == 1 and foundRow[4][2] == 0.82)

-- optional steps do not count, unordered echoes do not tick each other
check("Traveler's Symbols: optional steps not counted", find("Traveler's Symbols")[3] == "Toy, 0 of 3 steps")
check("optional marked", find("Premo's Poise"))
bags[215425] = 1
check("an echo alone ticks no other echo", find("Swamp Echo")[3] == "done" and find("Graveyard Echo")[3] ~= "done")
bags[278030] = 1
check("Scarlet Banner held: found", find("Scarlet Banner")[3] == "found")

-- mysteries: unsolved never found
done[93161] = true
local dawn = find("Dawn Waker")
check("Dawn Waker: unsolved, earlier steps ticked by a later one", dawn[3]:find("unsolved", 1, true)
	and find("Ancient Heirloom ring")[3] == "done" and find("The hilt and Altairus")[3] == "unsolved")
for _, id in ipairs({ 282404, 282548, 282547, 282431, 282699, 282707, 283387 }) do bags[id] = 1 end
check("every known Dawn Waker step done: still not found", find("Dawn Waker")[3] ~= "found")

-- the other two secrets count
done[79976] = true; done[82208] = true
check("sleeping bag and library in the counter", rows()[1][3] == "4 of 9 found")

-- several spots: each click the next
local guard = find("Find the slain Night Watch Guard")
check("six spots", guard[3] == "6 spots" and guard.onClick ~= nil)
guard.onClick(); guard.onClick()
check("each click: the next spot", #waypoints == 2 and (waypoints[1][2] ~= waypoints[2][2] or waypoints[1][3] ~= waypoints[2][3]))
check("chat says which spot", chat[#chat]:find("(2 of 6)", 1, true) ~= nil)

-- hide found ones
ns.db.secretsShowFound = false
check("found secrets hidden", not find("Alcaz Operative Insignia") and find("Night Watchman's Torch") ~= nil)

-- the chat line: old finds stay quiet, a new one is said once
chat = {}
api.guideAnnounceSecrets()
check("first look: no chat line for old finds", #chat == 0)
done[98372] = true
api.guideAnnounceSecrets(); api.guideAnnounceSecrets()
local said = 0
for _, t in ipairs(chat) do if t:find("Secret found: Night Watchman's Torch", 1, true) then said = said + 1 end end
check("a new find: said once", said == 1)

-- the page
local pages = {}
local kit = { page = function(key) pages[#pages + 1] = key end, heading = function() end, check = function() end,
	help = function() end, note = function() end, custom = function() end, buttons = function() end, input = function() end, choice = function() end,
	pageByKey = setmetatable({}, { __index = function(t, k) local p = {}; rawset(t, k, p) return p end }), refresh = function() end }
api.declareGuidePages(kit)
check("a Secrets page", table.concat(pages, ","):find("secrets", 1, true) ~= nil)
check("no Sleeping bag page: it is part of Secrets (user)", not table.concat(pages, ","):find("bedroll", 1, true))
ns.db.secretsShowFound = true
local bedRow
for _, r in ipairs(api.guideSecretRows()) do if r[2] == "Cozy Sleeping Bag" then bedRow = r end end
check("Secrets lists the Cozy Sleeping Bag chain", bedRow ~= nil)
do
	local list, names = api.guideSecretRows(), {}
	for _, r in ipairs(list) do if not r.header and r.split ~= nil or r[2] == "Cozy Sleeping Bag" then names[#names + 1] = r[2] end end
	check("order (user): Cozy Sleeping Bag first, Chicken Egg last", list[2][2] == "Cozy Sleeping Bag" and names[#names] == "Chicken Egg")
end

print(pass and "ALL OK" or "SOME FAILED")
