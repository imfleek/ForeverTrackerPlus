-- R106-83: quests done inside a dungeon or raid get no distance or arrow
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local function isInstanceQuest%(id%).-\napi.isInstanceQuest = isInstanceQuest)")
check("the instance check found", body ~= nil)
if body then
	local tags = {
		[1] = { tagName = "Dungeon", tagID = 81 }, [2] = { tagName = "Raid", tagID = 62 },
		[3] = { tagName = "Elite", tagID = 1 }, [4] = nil, [5] = { tagName = "", tagID = 85 },
	}
	local env = setmetatable({ api = {}, isSecret = function() return false end, TAG_ID = { dungeon = 81, raid = 62 },
		Enum = { QuestTag = { Dungeon = 85, Raid = 62 } },
		C_QuestLog = { GetQuestTagInfo = function(id) return tags[id] end } }, { __index = _G })
	load(body, "i", "t", env)()
	local is = env.api.isInstanceQuest
	check("a dungeon quest: none", is(1) == true)
	check("a raid quest: none", is(2) == true)
	check("by the game's Enum tag alone", is(5) == true)
	check("an elite quest: shown", is(3) == false)
	check("an untagged quest: shown", is(4) == false)
end
check("no room kept for it", src:find("if isInstanceQuest(id) then return false end", 1, true) ~= nil)
check("no yards measured for it (no repeated re-layouts)",
	src:find("if me and api.questDirection and not isInstanceQuest(id) then yards, angle", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
