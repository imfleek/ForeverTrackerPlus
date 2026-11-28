-- ForeverTrackerPlus: dead-end alert (3.2, user idea 35; rules picked by the user: 1 and 2, "small reward" = grey).
-- A quest in your log is a dead end when all of these are true:
--   * it is grey for you (the game's green range, or "grey at N levels below you": db.greyLevels);
--   * it leads to no quest you can take: Questie has no follow-up (nextQuestInChain) and no quest that needs it
--     (the unlock index: preQuestSingle / preQuestGroup), or each of them is for another race or class (rule 2);
--   * it gives no item (reward or choice) and no reputation.
-- It then gets a crossed icon in front of its title, a line in its tooltip, and a chat line when you accept it.
-- Unknown (Questie off, its unlock index still building, rewards not read): not a dead end.
-- Option: Quest titles > Lines, "Dead-end alert" (db.deadEnd, on by default).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local ICON = { file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", fallback = "Interface\\Buttons\\UI-StopButton" }
local rewardCache = {} -- quest id -> true (it gives an item or reputation), false (it gives neither)

local function isGrey(level)
	if type(level) ~= "number" or level <= 0 then return false end
	local me = UnitLevel and UnitLevel("player")
	if type(me) ~= "number" then return false end
	local db = ns.db
	local n = tonumber(db and db.greyLevels) or 0
	if n > 0 then return me - level >= n end
	local ok, range = pcall(function() return GetQuestGreenRange and GetQuestGreenRange() end)
	return me - level > ((ok and tonumber(range)) or 8)
end
api.deadEndIsGrey = isGrey -- (tests)

local function questLevel(id)
	local index = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
	local info = index and C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
	local lv = info and (info.level or info.difficultyLevel)
	if type(lv) ~= "number" and api.questieGet then lv = tonumber(api.questieGet("Quest", id, "questLevel")) end
	return lv
end

-- true: it leads on for you; false: it does not; nil: not known yet
local function leadsOn(id)
	local forMe = api.questieForPlayer or function() return true end
	local nxt = api.questieGet and api.questieGet("Quest", id, "nextQuestInChain")
	if type(nxt) == "number" and nxt > 0 and forMe(nxt) then return true end
	local opens = api.questieNextQuests and api.questieNextQuests(id)
	if opens == nil then return nil end
	return #opens > 0
end

local function givesSomething(id)
	if rewardCache[id] ~= nil then return rewardCache[id] end
	local links = api.questRewardLinks and api.questRewardLinks(id) or {}
	local rep = api.repRewards and api.repRewards(id) or {}
	local v = #links > 0 or #rep > 0
	rewardCache[id] = v
	return v
end

-- why the quest is a dead end (a short text), or nil
function api.deadEndReason(id)
	local db = ns.db
	if not db or db.deadEnd == false or type(id) ~= "number" then return nil end
	if not (api.questieOn and api.questieOn()) then return nil end
	local level = questLevel(id)
	if not isGrey(level) then return nil end
	if leadsOn(id) ~= false then return nil end
	if givesSomething(id) then return nil end
	return "grey, leads to no other quest, no item or reputation"
end

function api.deadEndIcon(id)
	if api.deadEndReason(id) then return ICON end
end

function api.addDeadEndLine(tip, id)
	local why = api.deadEndReason(id)
	if why and tip then
		tip:AddLine(" ")
		tip:AddLine("Dead end: " .. why, 1, 0.45, 0.35, true)
	end
end

-- a chat line when you accept one
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "QUEST_ACCEPTED")
events:SetScript("OnEvent", function(_, event, a, b)
	local id = type(b) == "number" and b or a
	if not (C_Timer and C_Timer.After) then return end
	C_Timer.After(1, function()
		local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
		if api.deadEndReason(id) and DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(("|cff33ff99ForeverTrackerPlus|r |cffff7359Dead end:|r %s (%s). You can abandon it."):format(
				tostring(title or id), api.deadEndReason(id)))
		end
	end)
end)
api.deadEndEventForTests = events:GetScript("OnEvent")
