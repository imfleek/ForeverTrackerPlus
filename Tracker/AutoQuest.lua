-- 3.1.1 Quest automation (Settings > Helpers > NPCs). The idea comes from Questline (auto accept, auto turn-in, skip
-- the chat); the code is our own. Every switch is off until you turn it on:
--   db.autoAccept      talking to an NPC opens its quests one by one and accepts them
--   db.autoTurnIn      talking to an NPC turns in finished quests. A reward choice of two or more is left to you
--                      (the best reward marker still shows); a turn-in that costs money is left to you
--   db.autoGossip      an NPC with no quest for you and only one plain chat option: that option is picked
--                      (only the speech-bubble kind, never a vendor, trainer, flight, bank or other service)
--   db.autoRepeatable  also repeatable and daily quests (off: several of them often share the same items)
--   db.autoTrivial     also grey (very low level) quests
--   db.autoInDungeon   also inside a dungeon or raid (off: an escort could start before the group is ready)
-- Hold Shift while you talk to the NPC: nothing is automatic that time.
-- Gossip: C_GossipInfo.GetActiveQuests / GetAvailableQuests / GetOptions (GossipQuestUIInfo: questID, isComplete,
-- isTrivial, frequency, repeatable; GossipOptionUIInfo: gossipOptionID, icon, status, flags), SelectActiveQuest /
-- SelectAvailableQuest / SelectOption. The quest window: QUEST_GREETING, QUEST_DETAIL, QUEST_PROGRESS,
-- QUEST_COMPLETE with the old global functions (AcceptQuest, CompleteQuest, GetQuestReward, ...), each type-checked
-- before use. None of them is protected.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local CHAT_ICON = 132053 -- Interface\GossipFrame\GossipGossipIcon: a plain chat option
local function on(key) return db and db[key] == true end
local function call(name, ...)
	local fn = rawget(_G, name)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e = pcall(fn, ...)
	if ok then return a, b, c, d, e end
	return nil
end

local function inInstance()
	local inside, kind = IsInInstance()
	return inside and (kind == "party" or kind == "raid")
end
-- nothing automatic: Shift held, or inside a dungeon or raid without the dungeon switch
local function paused()
	if IsShiftKeyDown and IsShiftKeyDown() then return true end
	if inInstance() and not on("autoInDungeon") then return true end
	return false
end
api.autoQuestPaused = paused

local repeatable = {} -- questIDs the gossip window said are repeatable or daily
local function isRepeat(q) return q.repeatable or (tonumber(q.frequency) or 0) > 0 end
local function allowed(q)
	if q.isTrivial and not on("autoTrivial") then return false end
	if isRepeat(q) and not on("autoRepeatable") then return false end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The gossip window
---------------------------------------------------------------------------------------------------------------------
local lastOption, lastOptionAt = nil, -10
local function onGossip()
	local G = C_GossipInfo
	if not G or paused() then return end
	local active = G.GetActiveQuests and G.GetActiveQuests() or {}
	local available = G.GetAvailableQuests and G.GetAvailableQuests() or {}
	for _, q in ipairs(active) do if q.questID and isRepeat(q) then repeatable[q.questID] = true end end
	for _, q in ipairs(available) do if q.questID and isRepeat(q) then repeatable[q.questID] = true end end
	if on("autoTurnIn") then
		for _, q in ipairs(active) do
			if q.isComplete and q.questID and allowed(q) then G.SelectActiveQuest(q.questID) return "turnin" end
		end
	end
	if on("autoAccept") then
		for _, q in ipairs(available) do
			if q.questID and allowed(q) then G.SelectAvailableQuest(q.questID) return "accept" end
		end
	end
	if on("autoGossip") and #available == 0 and G.GetOptions and G.SelectOption then
		local options = G.GetOptions() or {}
		local only = #options == 1 and options[1]
		local anyDone = false
		for _, q in ipairs(active) do if q.isComplete then anyDone = true end end
		if only and not anyDone and (only.icon == CHAT_ICON or only.overrideIconID == CHAT_ICON)
			and (only.status == nil or only.status == 0) and only.gossipOptionID then
			-- never the same option twice within 2 s: a chat that leads back to itself would loop
			if only.gossipOptionID == lastOption and GetTime() - lastOptionAt < 2 then return nil end
			lastOption, lastOptionAt = only.gossipOptionID, GetTime()
			G.SelectOption(only.gossipOptionID)
			return "chat"
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The quest window (an NPC with only quests, no chat)
---------------------------------------------------------------------------------------------------------------------
local function onGreeting()
	if paused() then return end
	if on("autoTurnIn") then
		for i = 1, call("GetNumActiveQuests") or 0 do
			local _, isComplete = call("GetActiveTitle", i)
			local id = call("GetActiveQuestID", i)
			if isComplete and not (id and repeatable[id] and not on("autoRepeatable")) then
				call("SelectActiveQuest", i) return "turnin"
			end
		end
	end
	if on("autoAccept") then
		for i = 1, call("GetNumAvailableQuests") or 0 do
			local isTrivial, frequency, isRepeatable, _, questID = call("GetAvailableQuestInfo", i)
			if questID and (isRepeatable or (tonumber(frequency) or 0) > 0) then repeatable[questID] = true end
			if allowed({ isTrivial = isTrivial, frequency = frequency, repeatable = isRepeatable }) then
				call("SelectAvailableQuest", i) return "accept"
			end
		end
	end
	return nil
end

local function onDetail()
	if not on("autoAccept") or paused() then return end
	if call("QuestGetAutoAccept") then
		call("AcknowledgeAutoAcceptQuest")
	else
		call("AcceptQuest")
	end
	return "accepted"
end

local function skipRepeat()
	local id = call("GetQuestID")
	return id and repeatable[id] and not on("autoRepeatable")
end
local function onProgress()
	if not on("autoTurnIn") or paused() or skipRepeat() then return end
	if (tonumber(call("GetQuestMoneyToGet")) or 0) > 0 then return end
	if call("IsQuestCompletable") then call("CompleteQuest") return "completed" end
end

local function onComplete(tries)
	if not on("autoTurnIn") or paused() or skipRepeat() then return end
	local choices = tonumber(call("GetNumQuestChoices")) or 0
	if choices > 1 then
		-- 3.2 (Rewards.lua): the best upgrade or the most valuable reward, when switched on
		local mode = db and db.autoReward
		if mode and mode ~= "off" and api.pickReward then
			local pick, pending = api.pickReward(mode)
			if pick then call("GetQuestReward", pick) return "rewarded" end
			if pending and (tries or 0) < 5 and C_Timer then
				C_Timer.After(0.3, function()
					local qf = rawget(_G, "QuestFrame")
					if qf and qf.IsShown and qf:IsShown() then pcall(onComplete, (tries or 0) + 1) end
				end)
			end
		end
		return "choose" -- yours to pick
	end
	call("GetQuestReward", choices == 1 and 1 or nil)
	return "rewarded"
end

-- (tests) the handlers, by event
api.autoQuestHandlers = { GOSSIP_SHOW = onGossip, QUEST_GREETING = onGreeting, QUEST_DETAIL = onDetail,
	QUEST_PROGRESS = onProgress, QUEST_COMPLETE = onComplete }

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	local f = CreateFrame("Frame")
	for event in pairs(api.autoQuestHandlers) do pcall(f.RegisterEvent, f, event) end
	f:SetScript("OnEvent", function(_, event)
		local fn = api.autoQuestHandlers[event]
		if not fn then return end
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Settings > Helpers > NPCs (declared by Config.lua: api.declareAutoQuestPage(kit))
---------------------------------------------------------------------------------------------------------------------
function api.declareAutoQuestPage(k)
	local function sw(label, key, helpText, enabled)
		k.check(label, function() return db[key] == true end, function(v) db[key] = v and true or false end, enabled)
		k.help(helpText)
	end
	local function anyOn() return on("autoAccept") or on("autoTurnIn") or on("autoGossip") end
	k.page("automation", "quests", "NPCs")
	k.note("Hold Shift while you talk to an NPC: nothing is automatic that time.")
	k.heading("Quests")
	sw("Accept quests", "autoAccept", "talking to an NPC accepts its quests for you")
	sw("Turn in finished quests", "autoTurnIn", "finished quests are handed in; if there is a reward choice, you pick")
	k.heading("Chat")
	sw("Skip the chat", "autoGossip", "if an NPC has only one chat option, it is picked for you (never a vendor, trainer, flight master or other service)")
	k.heading("Which quests", true)
	sw("Also repeatable and daily quests", "autoRepeatable", "off: you choose, as these often share items", anyOn)
	sw("Also grey (low level) quests", "autoTrivial", "off: grey quests are left to you", anyOn)
	sw("Also in dungeons and raids", "autoInDungeon", "off: an escort could start before your group is ready", anyOn)
	k.pageByKey.automation.reset = k.reset
end
