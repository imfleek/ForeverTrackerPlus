-- ForeverTrackerPlus: our own tracker, phase 1 (OWN_TRACKER_PLAN.md): the quest data, read only.
--
-- api.ownBuild() returns the list our frame draws:
--   { groups = { { zone = "Elwynn Forest" or nil, folded = bool, quests = { quest, ... } }, ... }, count = n }
--   quest = { id, title, level, r, g, b, complete, failed, superTracked, zone, campaign, marker, tagName,
--             progress (0-1), objectives = { { text, done, have, need }, ... } }
--
-- Which quests: "Track all quests" (db.trackMode "all") is every quest in the log (no watch-list cap, so More quests
-- is not needed here); the other modes are the watched quests. "Show quests in my zone" (db.zoneFilter) keeps only the
-- quests of your zone (the super-tracked one stays). Order: with "by zone" (db.zoneSort) ZoneSort's order (zones by
-- distance or A to Z, quests by distance, level or progress) in zone groups; "Expand current zone only" folds the other
-- zones. Without "by zone": the watch order (or the log order), one group with no header.
--
-- RULE: only C_QuestLog / C_SuperTrack / C_CampaignInfo reads and our own helpers; nothing on Blizzard's tracker.
-- The watch list is never changed here (Track.lua and ZoneFilter.lua do that, as before).
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function clean(v) if v ~= nil and not isSecret(v) then return v end return nil end

local function superTracked()
	local id = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	return clean(id)
end

-- the quest IDs to show, in their base order (watch order, or log order for "Track all quests")
local function questIDs(db)
	local ids, seen = {}, {}
	local function add(id)
		id = clean(id)
		if type(id) == "number" and id > 0 and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
	end
	if not C_QuestLog then return ids end
	if db.trackMode == "all" and C_QuestLog.GetNumQuestLogEntries then
		-- watched ones first (the order you gave them), then the rest of the log
		for i = 1, (C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()) or 0 do
			add(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
		end
		for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and not info.isHidden and not info.isTask and not info.isBounty then add(info.questID) end
		end
	elseif C_QuestLog.GetNumQuestWatches then
		for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do add(C_QuestLog.GetQuestIDForQuestWatchIndex(i)) end
	end
	return ids
end

local function questData(id, db)
	local q = { id = id, objectives = {} }
	q.title = clean(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or ("Quest " .. id)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
	local info = index and C_QuestLog.GetInfo(index)
	q.level = info and clean(info.level or info.difficultyLevel)
	if type(q.level) ~= "number" or q.level <= 0 then q.level = nil end -- level 0: no level (user: "[0] Argent Arbiter")
	q.campaign = info and clean(info.campaignID) and true or false
	q.complete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)) and true or false
	q.failed = (C_QuestLog.IsFailed and C_QuestLog.IsFailed(id)) and true or false
	q.zone = api.questZoneName and api.questZoneName(id) or nil
	if q.zone == "" then q.zone = nil end
	if api.questClassifier then
		local ok, marker, tagName = pcall(api.questClassifier, id)
		if ok then q.marker, q.tagName = marker, tagName end
	end
	-- colour: complete green, failed red, else the level's difficulty colour (Core's, with "grey levels")
	if q.complete then q.r, q.g, q.b = 0.2, 1, 0.2
	elseif q.failed then q.r, q.g, q.b = 1, 0.2, 0.2
	elseif q.level and api.questDifficultyRGB then q.r, q.g, q.b = api.questDifficultyRGB(q.level)
	end
	if type(q.r) ~= "number" or type(q.g) ~= "number" or type(q.b) ~= "number" then q.r, q.g, q.b = 1, 0.82, 0 end
	local sum, n = 0, 0
	local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
	for _, o in ipairs(type(objs) == "table" and objs or {}) do
		local text = clean(o.text)
		local have, need = tonumber(clean(o.numFulfilled)), tonumber(clean(o.numRequired))
		n = n + 1
		if o.finished then sum = sum + 1 elseif have and need and need > 0 then sum = sum + math.min(have / need, 1) end
		if type(text) == "string" and text ~= "" and not (db.hideDoneObjectives and o.finished) then
			q.objectives[#q.objectives + 1] = { text = text, done = o.finished and true or false, have = have, need = need }
		end
	end
	q.progress = q.complete and 1 or (n > 0 and sum / n or 0)
	return q
end

function api.ownBuild()
	local db = ns.db or {}
	local sup = superTracked()
	local ids = questIDs(db)
	-- "Show quests in my zone"
	if db.zoneFilter and api.inCurrentZone then
		local keep = {}
		for _, id in ipairs(ids) do if id == sup or api.inCurrentZone(id) then keep[#keep + 1] = id end end
		ids = keep
	end
	local quests = {}
	for i, id in ipairs(ids) do
		local q = questData(id, db)
		q.superTracked = id == sup
		q.index = i
		quests[#quests + 1] = q
	end
	local out = { groups = {}, count = #quests }
	if not db.zoneSort then
		out.groups[1] = { quests = quests }
		return out
	end
	if api.orderQuests then
		local ok, sorted = pcall(api.orderQuests, quests) -- reads q.id, q.zone, q.index; returns a new list
		if ok and type(sorted) == "table" then quests = sorted end
	end
	local fold = db.expandCurrentZone and api.isCurrentZoneName
	local byZone = {}
	for _, q in ipairs(quests) do
		local key = q.zone or ""
		local g = byZone[key]
		if not g then
			g = { zone = q.zone, quests = {} }
			g.folded = fold and q.zone and not api.isCurrentZoneName(q.zone) or false
			byZone[key] = g
			out.groups[#out.groups + 1] = g
		end
		g.quests[#g.quests + 1] = q
	end
	-- the super-tracked quest's zone is never folded
	for _, g in ipairs(out.groups) do
		for _, q in ipairs(g.quests) do if q.superTracked then g.folded = false end end
	end
	return out
end
api.ownQuestIDs = function() return questIDs(ns.db or {}) end
api.ownQuestData = function(id) return questData(id, ns.db or {}) end
