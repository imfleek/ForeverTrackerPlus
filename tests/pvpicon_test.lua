-- R106-79: battleground quests without the game's PvP tag get the PvP icon (their quest log header is a battleground);
-- the icon is the player's own faction's
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local BG_AREAS = .-\napi.isBattlegroundQuest = isBattlegroundQuest)")
check("the battleground check found", body ~= nil)
if body then
	local log = {
		{ isHeader = true, title = "Ashenvale" }, { title = "Raene's Cleansing", questID = 1 },
		{ isHeader = true, title = "Warsong Gulch" }, { title = "Field of Honor: Week 2", questID = 2 },
		{ isHeader = true, title = "Battle for the Darkspear Islands" }, { title = "A Darkspear quest", questID = 3 },
	}
	local env = setmetatable({ api = {}, isSecret = function() return false end, BATTLEGROUNDS = "Battlegrounds",
		C_Map = { GetAreaInfo = function(id) return ({ [3277] = "Warsong Gulch", [2597] = "Alterac Valley", [16606] = "Bataille des 95bles Sombrelance" })[id] end },
		C_QuestLog = { GetInfo = function(i) return log[i] end,
			GetLogIndexForQuestID = function(id) for i, q in ipairs(log) do if q.questID == id then return i end end end },
	}, { __index = _G })
	load(body, "bg", "t", env)()
	check("a quest under \"Warsong Gulch\": a battleground quest", env.api.isBattlegroundQuest(2) == true)
	check("a quest under Forever's \"Battle for the Darkspear Islands\": a battleground quest", env.api.isBattlegroundQuest(3) == true)
	log[#log + 1] = { isHeader = true, title = "Bataille des 95bles Sombrelance" }
	log[#log + 1] = { title = "Une qu95xte", questID = 4 }
	check("Darkspear Islands by its area 16606, in the client's language", env.api.isBattlegroundQuest(4) == true)
	check("a quest under \"Ashenvale\": not one", env.api.isBattlegroundQuest(1) == false)
end
check("untagged quests are checked too", src:find("if isBattlegroundQuest(questID) then return getIcons().pvp, \"\" end", 1, true) ~= nil)
check("tagged quests: the PvP tag or a battleground header", src:find('if is("pvp", "PvP") or isBattlegroundQuest(questID) then', 1, true) ~= nil)
check("the player's own faction's PvP icon", src:find('ICONS.pvp.file = "Interface\\\\TargetingFrame\\\\UI-PVP-" .. faction', 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
