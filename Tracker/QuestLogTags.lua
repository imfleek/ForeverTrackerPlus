-- ForeverTrackerPlus: our tags in Blizzard's quest log (3.2, user idea 10).
-- Each quest line of the quest log (QuestScrollFrame.titleFramePool, rebuilt by QuestLogQuests_Update) gets a small
-- tag of our own at its right side: the Forever W, the attunement star, the type marker (Extras.lua, as the tracker
-- shows them) and the quest's level in its difficulty colour.
-- CONSTRAINT: Blizzard's own text and buttons are not changed (no taint): the tag is our own font string, a child of
-- the button, made once and only shown, hidden or given new text after Blizzard's update (hooksecurefunc).
-- Option: Quest titles > Quest log (db.questLogTags, on by default; db.questLogLevels for the level).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local SIZE = 13
local function iconText(m)
	if type(m) == "string" then return m ~= "" and m or nil end
	if type(m) ~= "table" then return nil end
	local size = math.floor(SIZE * (tonumber(m.scale) or 1) + 0.5)
	if m.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(m.atlas) then
		return ("|A:%s:%d:%d|a"):format(m.atlas, size, size)
	end
	local file = m.file or m.fallback
	if file then return ("|T%s:%d:%d|t"):format(file, size, size) end
end

local function level(id)
	local index = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
	local info = index and C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
	local lv = info and (info.level or info.difficultyLevel)
	if type(lv) ~= "number" or lv <= 0 then return nil end
	return lv
end

-- the tag's text for one quest ("" when it has nothing)
local function tagText(id)
	local db = ns.db
	if type(id) ~= "number" or not db then return "" end
	local parts = {}
	for _, m in ipairs({ api.foreverIcon and api.foreverIcon(id), api.attunementIcon and api.attunementIcon(id) }) do
		local t = iconText(m)
		if t then parts[#parts + 1] = t end
	end
	if api.questClassifier then
		local ok, marker = pcall(api.questClassifier, id)
		local t = ok and iconText(marker)
		if t then parts[#parts + 1] = t end
	end
	if db.questLogLevels ~= false then
		local lv = level(id)
		if lv then
			local r, g, b = 1, 0.82, 0
			if api.questDifficultyRGB then r, g, b = api.questDifficultyRGB(lv) end
			parts[#parts + 1] = ("|cff%02x%02x%02x[%d]|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), lv)
		end
	end
	return table.concat(parts, " ")
end
api.questLogTagText = tagText -- (tests)

local function tag(button)
	if type(button) ~= "table" or not button.CreateFontString then return nil end
	if not button.qtsLogTag then
		local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPRIGHT", button, "TOPRIGHT", -24, -2)
		fs:SetJustifyH("RIGHT")
		button.qtsLogTag = fs
	end
	return button.qtsLogTag
end

local function update()
	local db = ns.db
	local frame = rawget(_G, "QuestScrollFrame")
	local pool = type(frame) == "table" and frame.titleFramePool
	if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
	local on = db and db.questLogTags ~= false
	pcall(function()
		for button in pool:EnumerateActive() do
			local fs = tag(button)
			if fs then
				local text = on and tagText(button.questID) or ""
				fs:SetText(text)
				fs:SetShown(text ~= "")
			end
		end
	end)
end
api.updateQuestLogTags = update

ns.onLogin[#ns.onLogin + 1] = function()
	if type(rawget(_G, "QuestLogQuests_Update")) == "function" and hooksecurefunc then
		hooksecurefunc("QuestLogQuests_Update", update)
	end
end

api.pageDeclarers = api.pageDeclarers or {}
api.pageDeclarers[#api.pageDeclarers + 1] = function(k)
	local db = ns.db
	k.page("questlogtags", "quests", "Quest log")
	k.pageByKey.questlogtags.cardTitle = "In Blizzard's quest log"
	k.check("Our tags in the quest log", function() return db.questLogTags ~= false end,
		function(v) db.questLogTags = v and true or false; update() end)
	k.help("the Forever W, the attunement star and the type marker at the right of each quest, as on the tracker")
	k.check("Quest level", function() return db.questLogLevels ~= false end,
		function(v) db.questLogLevels = v and true or false; update() end, function() return db.questLogTags ~= false end, 16)
	k.help("[level] in the colour of how hard the quest is for you")
end
