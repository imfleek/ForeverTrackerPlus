-- R106-99: hover an NPC's name, or an object to pick up or use: a panel beside the tracker with its name and a 3D model
-- that turns slowly (user: "the same kind of panel" as the Journeys addon's step hover, hero-preview.mp4: an NPC's
-- name, title, level and type over its full-body model; an object's name over its model, e.g. the Taillasher Eggs).
-- User: no 3D model to show, no panel at all. Items have no models: not shown (R106-111: an item that is not picked up
-- from an object shows its icon instead). Vague or misspelt pick-up names: the step's quest objects, then a near spelling here.
--   * RestedXP guide steps: the names RestedXP colours as friendly / enemy NPCs or as objects to pick up (RXP_PICK_;
--     Objectives/tracker/Rows.lua makes each one a link, "rxpftnpc:<kind>:<name>"); always on.
--   * Quest tracker: an objective line that names one of the quest's NPCs or objects (Questie's quest objectives);
--     option "Hover an objective: show its 3D model" (db.npcPanelQuests, on by default).
-- Models: an NPC by its npc id (PlayerModel:SetCreature); ids from the objectives side's lookup (units seen, then
-- Questie's name index; Objectives/circle/Models.lua) or, in the quest tracker, Questie's objective ids. An object by
-- its model file (Model:SetModel(fileID)): the game has no lookup from an object to its model, so the file comes from
-- ns.objectModels ([objectId] = model file id, a data file); object ids by name from Questie's object name index.
-- NPC level, title, rank: Questie; creature type: the unit when it was last in sight (db.npcTypes, by npc id).
-- With no model yet nothing shows; while the name stays hovered it looks again twice a second (Questie's name indexes
-- are built a slice per frame on first need) and the panel opens once one is found.
-- CONSTRAINT: Forever's PlayerModel declares SetCreature, SetPortraitZoom, SetCamDistanceScale, SetFacing and (Model)
-- SetModel (wow-api-widget, forever); each call is guarded. The model turns from the panel's OnUpdate, which runs only
-- while the panel is shown; while a quest is hovered, a 0.05 s check finds the line under the mouse.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api
local db

local WIDTH, MODEL_H, PAD, GAP = 210, 250, 10, 8
local RETRIES = 20
local TURN_SPEED = 0.6 -- radians a second
local INDEX_SLICE = 250
local RANKS = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local COLOR = { enemy = { 1, 0.35, 0.2 }, friendly = { 0.2, 1, 0.3 }, pick = { 0.86, 0.18, 0.94 } }
local TOKEN = { enemy = "RXP_ENEMY_", friendly = "RXP_FRIENDLY_", pick = "RXP_PICK_" }
local GOLD = { 1, 0.82, 0 }
local ICON = 36

ns.objectModels = ns.objectModels or {}

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function isObject(kind) return kind == "pick" or kind == "object" end

local function npcIdOf(guid)
	if type(guid) ~= "string" or isSecret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

-- RestedXP's colour for a kind of word, as {r, g, b}; ours when it has none
local function kindColor(kind)
	if kind == "object" then kind = "pick" end
	local rxp = root.objectives and root.objectives.rxp
	local colors = type(rxp) == "table" and rxp.guideTextColors
	local hex = TOKEN[kind] and type(colors) == "table" and colors[TOKEN[kind]]
	if type(hex) == "string" and #hex == 8 and hex:match("^%x+$") then
		return { tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255 }
	end
	return COLOR[kind] or GOLD
end

local function lookupNpc(name)
	local obj = root.objectives
	local find = type(obj) == "table" and obj.npcIdFor
	if type(find) ~= "function" or type(name) ~= "string" then return nil end
	local ok, id = pcall(find, name)
	return ok and tonumber(id) or nil
end

-- Questie's object and item name indexes, each built a slice per frame on first need (as Models.lua does for NPCs)
local indexes, building = {}, {} -- [kind] = the entity (ready) or false (none); building[kind] while a build runs
local function questieEntity(kind)
	local lib = _G.LibQuestieDB
	local entity = type(lib) == "table" and lib[kind]
	if type(entity) ~= "table" or type(entity.IdsByName) ~= "function" or type(entity.BuildNameIndexAsync) ~= "function" then
		return nil
	end
	if api.questieOn and not api.questieOn() then return nil end
	return entity
end
local function buildIndex(kind)
	if indexes[kind] ~= nil or building[kind] then return end
	local entity = questieEntity(kind)
	if not entity then return end
	building[kind] = true
	local job = coroutine.create(function() entity.BuildNameIndexAsync(INDEX_SLICE) end)
	local function step()
		local ok, err = coroutine.resume(job)
		if not ok then
			building[kind], indexes[kind] = nil, false
			geterrorhandler()(err)
		elseif coroutine.status(job) == "dead" then
			building[kind], indexes[kind] = nil, entity
		else
			C_Timer.After(0, step)
		end
	end
	step()
end
local function idsByName(kind, name)
	if indexes[kind] == nil then buildIndex(kind) end
	local index = indexes[kind]
	if not index then return {} end
	local ok, ids = pcall(index.IdsByName, name)
	return ok and type(ids) == "table" and ids or {}
end

-- the game map you are on and the map around it (a cave inside a zone)
local function playerMaps()
	local maps = {}
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if type(map) ~= "number" then return nil end
	maps[map] = true
	local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	if type(info) == "table" and info.parentMapID and info.parentMapID > 0 then maps[info.parentMapID] = true end
	return maps
end

-- R106-112: the model for a name, from every object of that name that has one (an object with no model of its own,
-- often a new Forever or SoD copy of an old one, takes the look its namesakes share). Strict: all copies must share
-- one model, else only the copies that spawn where you are; when those differ too, none (a test on 10,565 known
-- objects: right 92% with this rule, 71% taking any copy).
local function sharedModel(ids)
	local list, one, many = {}, nil, false
	for _, id in ipairs(ids) do
		local file = ns.objectModels[id]
		if file then
			list[#list + 1] = id
			if one and one ~= file then many = true end
			one = one or file
		end
	end
	if not many then return one end
	local here = playerMaps()
	if not (here and api.questieObjectMaps) then return nil end
	local found
	for _, id in ipairs(list) do
		for map in pairs(api.questieObjectMaps(id)) do
			if here[map] then
				local file = ns.objectModels[id]
				if found and found ~= file then return nil end
				found = file
				break
			end
		end
	end
	return found
end
api.npcPanelSharedModel = sharedModel

local function lookupObjectModel(name)
	if type(name) ~= "string" or not next(ns.objectModels) then return nil end
	return sharedModel(idsByName("Object", name))
end

-- R106-108: an item picked up from an object ("Un'Goro Soil" from an "Un'Goro Dirt Pile"): the first object it comes
-- from (Questie's Item.objectDrops) that has a model; its model file and the object's name
local function lookupItemSource(name)
	if type(name) ~= "string" or not next(ns.objectModels) or not api.itemObjectSources then return nil end
	for _, itemId in ipairs(idsByName("Item", name)) do
		for _, source in ipairs(api.itemObjectSources(itemId)) do
			if ns.objectModels[source.objectId] then return ns.objectModels[source.objectId], source.name end
		end
	end
	return nil
end

-- 3.2 (user: "Handful of Cattails" showed no model; it is new in Forever, picked from a "Cattail"): an object whose
-- name is a part of the item's name ("Cattail" in "Handful of Cattails", "Speargrass" in "Speargrass Cuttings"),
-- longest part first, also without a plural s; for items Questie does not link to their object
local SMALL = { ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true, ["and"] = true }
local function lookupNameInside(name)
	if type(name) ~= "string" or not next(ns.objectModels) then return nil end
	local w = {}
	for word in name:gmatch("%S+") do w[#w + 1] = word end
	for len = #w - 1, 1, -1 do
		for i = 1, #w - len + 1 do
			local first, last = w[i], w[i + len - 1]
			if not SMALL[first:lower()] and not SMALL[last:lower()] then
				local part = table.concat(w, " ", i, i + len - 1)
				for _, try in ipairs({ part, (part:gsub("es$", "")), (part:gsub("s$", "")) }) do
					if #try >= 4 then
						local file = lookupObjectModel(try)
						if file then return file, try end
					end
				end
			end
		end
	end
	return nil
end
api.npcPanelNameInside = lookupNameInside -- (tests)

-- R106-111: a name the guide spells wrong ("Loost Dirt", "Clliffspring Chest"): the object names a letter or two off
-- (Levenshtein distance, cut short past the limit); nil when farther
local function distance(a, b, max)
	local la, lb = #a, #b
	if math.abs(la - lb) > max then return nil end
	local prev = {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		local cur, best, ca = { [0] = i }, i, a:byte(i)
		for j = 1, lb do
			local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca == b:byte(j) and 0 or 1))
			cur[j] = v
			if v < best then best = v end
		end
		if best > max then return nil end
		prev = cur
	end
	return prev[lb] <= max and prev[lb] or nil
end
api.npcPanelDistance = distance
local MIN_TYPO_LEN = 6
local function maxTypos(low) return #low >= 10 and 2 or 1 end

-- the one closest candidate ({ name, low, file }) to any of the names; nil when none is close or two models tie
local function closest(names, candidates, accept)
	local bestD, best, tie
	for _, n in ipairs(names) do
		local low = n:lower()
		if #low >= MIN_TYPO_LEN then
			for _, c in ipairs(candidates) do
				local d = distance(low, c.low, maxTypos(low))
				if d and (not bestD or d <= bestD) and (not accept or accept(c)) then
					if not bestD or d < bestD then bestD, best, tie = d, c, false
					elseif c.file ~= best.file then tie = true end
				end
			end
		end
	end
	if best and not tie then return best end
	return nil
end

-- the objects with a model that the step's quests use
local function questCandidates(quests)
	local out = {}
	if type(quests) ~= "table" or not api.questObjects then return out end
	for _, q in ipairs(quests) do
		for _, o in ipairs(api.questObjects(q)) do
			local file = ns.objectModels[o.objectId]
			if file then out[#out + 1] = { name = o.name, low = o.name:lower(), file = file } end
		end
	end
	return out
end

-- R106-111: a vague name ("Chest", "Crate") or a misspelt one on a quest's step: the quest's own object whose name
-- holds that word ("Battered Chest"), else the one a letter or two off; only when it points at one model
local function words(s) return " " .. s:lower():gsub("[^%w']+", " ") .. " " end
local function lookupQuestObject(names, quests)
	local list = questCandidates(quests)
	if #list == 0 then return nil end
	for _, n in ipairs(names) do
		local word = words(n)
		local hit, many
		if word:match("%w") then
			for _, c in ipairs(list) do
				if words(c.name):find(word, 1, true) then
					if hit and hit.file ~= c.file then many = true end
					hit = hit or c
				end
			end
		end
		if hit and not many then return hit end
	end
	-- 3.2 (user: "make it easier for item names to match with their object names"): the other way round, the
	-- quest's object named inside the item's name, also as a plural ("Cattail" in "Handful of Cattails")
	for _, n in ipairs(names) do
		local word = words(n)
		local hit, many
		for _, c in ipairs(list) do
			local core = words(c.name):sub(1, -2)
			if #core > 3 and (word:find(core .. " ", 1, true) or word:find(core .. "s ", 1, true) or word:find(core .. "es ", 1, true)) then
				if hit and hit.file ~= c.file then many = true end
				hit = hit or c
			end
		end
		if hit and not many then return hit end
	end
	return closest(names, list)
end

-- every object with a model, by name (built a slice per frame on first need); modeledByLen: the same, by name length,
-- so a near-spelling search reads only the names a letter or two longer or shorter (3.2, user: a lag spike on an item
-- with no model: the search read all ~10,000 names, twice a second)
local modeled, modeledBuilding, modeledByLen
local MODELED_SLICE = 1000
local function buildModeled()
	if modeled or modeledBuilding or not api.questieObjectName then return end
	if api.questieOn and not api.questieOn() then return end
	modeledBuilding = true
	local ids, list, at = {}, {}, 0
	for id in pairs(ns.objectModels) do ids[#ids + 1] = id end
	local function step()
		local stop = math.min(at + MODELED_SLICE, #ids)
		for k = at + 1, stop do
			local id = ids[k]
			local name = api.questieObjectName(id)
			if type(name) == "string" and not isSecret(name) then
				list[#list + 1] = { id = id, name = name, low = name:lower(), file = ns.objectModels[id] }
			end
		end
		at = stop
		if at < #ids and C_Timer and C_Timer.After then C_Timer.After(0, step) return end
		local byLen = {}
		for _, c in ipairs(list) do
			local b = byLen[#c.low]
			if not b then b = {}; byLen[#c.low] = b end
			b[#b + 1] = c
		end
		modeled, modeledByLen, modeledBuilding = list, byLen, nil
	end
	step()
end

-- a misspelt name with no quest to go by: the object a letter or two off that spawns where you are
local function lookupTypoHere(names)
	if not modeled then buildModeled() end
	if not modeled then return nil end
	local here = playerMaps()
	if not (here and api.questieObjectMaps) then return nil end
	local near, seen = {}, {}
	for _, n in ipairs(names) do
		local len = #n
		if len >= MIN_TYPO_LEN then
			local max = maxTypos(n:lower())
			for l = len - max, len + max do
				if not seen[l] then
					seen[l] = true
					for _, c in ipairs(modeledByLen[l] or {}) do near[#near + 1] = c end
				end
			end
		end
	end
	if #near == 0 then return nil end
	return closest(names, near, function(c)
		for map in pairs(api.questieObjectMaps(c.id)) do if here[map] then return true end end
		return false
	end)
end

-- R106-111: an item with no object to show (it is not picked up from one): its icon
local function lookupItemIcon(names)
	local item = C_Item
	for _, n in ipairs(names) do
		for _, id in ipairs(idsByName("Item", n)) do
			local icon = item and item.GetItemIconByID and item.GetItemIconByID(id) or (GetItemIcon and GetItemIcon(id))
			if icon then return icon end
		end
		if item and item.GetItemInfoInstant then
			local ok, id, _, _, _, icon = pcall(item.GetItemInfoInstant, n)
			if ok and id and icon then return icon end
		end
	end
	return nil
end

-- still building a name list that could find a model
local function stillLooking() return building.Object or building.Item or modeledBuilding end

local panel, model, stage, texts, iconTex

-- R106-115: the hovered line still on screen and under the mouse (user: the panel "stays open, and shows for quests it
-- isn't relevant to"): a line the tracker hides or hands to another quest never sends OnLeave
local function stillHovered(owner)
	if type(owner) ~= "table" then return true end
	if owner.IsVisible and not owner:IsVisible() then return false end
	if owner.IsMouseOver and not owner:IsMouseOver() then return false end
	return true
end
local scene, actor -- R106-113: objects in a ModelScene, framed to their size

-- R106-113: the camera distance that shows a model of that radius whole: the narrower side of the stage holds its
-- bounding sphere, with a small margin (fov: the camera's field of view, radians)
local FIT_MARGIN = 1.08
function api.npcPanelFitDistance(radius, fov, w, h)
	local half = fov / 2
	if w and h and w > 0 and h > 0 and w < h then half = math.atan(math.tan(half) * w / h) end
	return radius / math.sin(half) * FIT_MARGIN
end
local SCENE_FOV = 0.7
local RELOAD_EVERY, RELOAD_TRIES = 0.5, 10
local reload, loadedKey -- R106-120: the NPC model being set again until it loads; the model key last loaded
local FIT_TIMEOUT = 1.5 -- seconds: an object not framed by then goes back to the PlayerModel
local START_DISTANCE = 6 -- the camera before the size is known
-- what the scene did, for /qt debug (user: "It never loads the object model")
local sceneLog = { framed = 0, fellBack = 0 }
local sceneFailed = {} -- [model file] = true: shown in the PlayerModel
local shown -- what is hovered: { name, id, modelFile, kind, owner, forms }; the panel is up only once it has a model
local retryTicker

local function build()
	if panel then return panel end
	panel = CreateFrame("Frame", "ForeverTrackerPlusNpcPanel", UIParent, "BackdropTemplate")
	panel:SetFrameStrata("TOOLTIP")
	panel:SetClampedToScreen(true)
	panel:SetWidth(WIDTH)
	panel:EnableMouse(false)
	if panel.SetBackdrop then
		panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		panel:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
		panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	end
	texts = {}
	local fonts = { "GameFontNormalLarge", "GameFontHighlightSmall", "GameFontHighlight", "GameFontHighlightSmall" }
	for i, font in ipairs(fonts) do
		local fs = panel:CreateFontString(nil, "OVERLAY", font)
		fs:SetJustifyH("LEFT")
		fs:SetWidth(WIDTH - 2 * PAD)
		if fs.SetWordWrap then fs:SetWordWrap(true) end
		texts[i] = fs
	end
	-- the model's stage: a dark box under the text
	stage = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
	stage:SetColorTexture(0, 0, 0, 0.45)
	-- R106-111: an item with no model: its icon beside the name
	iconTex = panel:CreateTexture(nil, "ARTWORK")
	iconTex:SetSize(ICON, ICON)
	iconTex:Hide()
	local ok, m = pcall(CreateFrame, "PlayerModel", nil, panel)
	if ok and type(m) == "table" and (type(m.SetCreature) == "function" or type(m.SetModel) == "function") then
		model = m
		if model.SetKeepModelOnHide then pcall(model.SetKeepModelOnHide, model, true) end
		if model.EnableMouse then model:EnableMouse(false) end
		model.facing = 0
		-- a model file (an object) is framed once it has loaded: the camera fitted to it again
		if model.HasScript and model:HasScript("OnModelLoaded") then
			model:SetScript("OnModelLoaded", function(self)
				loadedKey = self.key
				if self.SetPosition then pcall(self.SetPosition, self, 0, 0, 0) end
				if self.SetCamDistanceScale then pcall(self.SetCamDistanceScale, self, 1) end
				if self.RefreshCamera then pcall(self.RefreshCamera, self) end
			end)
		end
	end
	-- R106-113: objects go in a ModelScene: its actor tells the model's size (GetActiveBoundingBox), so the camera
	-- is set back far enough to show all of it (a PlayerModel's own camera cuts big ones off)
	local okS, sc = pcall(CreateFrame, "ModelScene", nil, panel)
	if okS and type(sc) == "table" and type(sc.CreateActor) == "function" and type(sc.SetCameraPosition) == "function"
		and type(sc.SetCameraOrientationByAxisVectors) == "function" then
		local okA, a = pcall(sc.CreateActor, sc)
		if okA and type(a) == "table" and type(a.SetModelByFileID) == "function"
			and type(a.GetActiveBoundingBox) == "function" and type(a.IsLoaded) == "function" then
			scene, actor = sc, a
			if scene.EnableMouse then scene:EnableMouse(false) end
			if scene.SetCameraFieldOfView then pcall(scene.SetCameraFieldOfView, scene, SCENE_FOV) end
			-- the game's own model scenes' default light
			local light = Enum and Enum.ModelLightType and Enum.ModelLightType.Directional or 1
			if scene.SetLightVisible then pcall(scene.SetLightVisible, scene, true) end
			if scene.SetLightType then pcall(scene.SetLightType, scene, light) end
			if scene.SetLightDirection then pcall(scene.SetLightDirection, scene, -0.447, 0.724, -0.525) end
			if scene.SetLightAmbientColor then pcall(scene.SetLightAmbientColor, scene, 0.7, 0.7, 0.7) end
			if scene.SetLightDiffuseColor then pcall(scene.SetLightDiffuseColor, scene, 0.8, 0.8, 0.8) end
			-- it turns about its own middle, which stays at the scene's centre
			if actor.SetUseCenterForOrigin then pcall(actor.SetUseCenterForOrigin, actor, true, true, true) end
			actor.facing = 0
			scene:Hide()
		elseif sc.Hide then
			sc:Hide()
		end
	end
	-- the model turns while the panel is up; an object is framed once it has loaded
	panel:SetScript("OnUpdate", function(_, elapsed)
		if shown and not stillHovered(shown.keepWhile or shown.owner) then api.hideNpcPanel() return end
		if scene and scene:IsShown() then
			if not scene.fitted then
				scene.fitted = api.npcPanelFitScene()
				-- R106-113: not framed in time: this model goes back to the PlayerModel (shown, if too big)
				if not scene.fitted and GetTime and scene.since and GetTime() - scene.since > FIT_TIMEOUT then
					sceneFailed[scene.key or false] = true
					sceneLog.fellBack = sceneLog.fellBack + 1
					scene.key = nil
					scene:Hide()
					if shown then api.npcPanelRender() end
					return
				end
			end
			actor.facing = (actor.facing + (elapsed or 0) * TURN_SPEED) % (2 * math.pi)
			if actor.SetYaw then pcall(actor.SetYaw, actor, actor.facing) end
		end
		if not (model and model:IsShown() and model.SetFacing) then return end
		api.npcPanelReloadCheck()
		model.facing = (model.facing + (elapsed or 0) * TURN_SPEED) % (2 * math.pi)
		pcall(model.SetFacing, model, model.facing)
	end)
	panel:Hide()
	return panel
end

-- what is known of the NPC: Questie's details and the creature type seen
local function npcDetails(name, id)
	local info = id and api.questieNpc and api.questieNpc(id) or nil
	local out = { name = name, subName = info and info.subName, rank = info and info.rank }
	local lo, hi = info and info.minLevel, info and info.maxLevel
	if lo and lo > 0 then out.level = (hi and hi > lo) and (lo .. "-" .. hi) or tostring(lo) end
	out.creatureType = id and db and type(db.npcTypes) == "table" and db.npcTypes[id] or nil
	return out
end

local function levelLine(d)
	local parts = {}
	if d.level then parts[#parts + 1] = "Level " .. d.level end
	if d.rank and RANKS[d.rank] then parts[#parts + 1] = RANKS[d.rank] end
	return #parts > 0 and table.concat(parts, " ") or nil
end

-- R106-113: the camera set back to show the loaded object whole; false until it has loaded
function api.npcPanelFitScene()
	if not (scene and actor) then return false end
	local okL, loaded = pcall(actor.IsLoaded, actor)
	sceneLog.loaded = okL and tostring(loaded) or ("error: " .. tostring(loaded))
	if not (okL and loaded) then return false end
	local ok, a, b, c, d, e, f = pcall(actor.GetActiveBoundingBox, actor)
	sceneLog.box = ok and (type(a) .. "/" .. type(b)) or ("error: " .. tostring(a))
	if not ok then return false end
	local lo, hi
	if type(a) == "table" and type(b) == "table" then lo, hi = a, b
	elseif type(a) == "number" and type(f) == "number" then lo, hi = { x = a, y = b, z = c }, { x = d, y = e, z = f } end
	if not lo then return false end
	local dx, dy, dz = (hi.x or 0) - (lo.x or 0), (hi.y or 0) - (lo.y or 0), (hi.z or 0) - (lo.z or 0)
	local radius = math.sqrt(dx * dx + dy * dy + dz * dz) / 2
	sceneLog.radius = radius
	if not (radius > 0) then return false end
	local okF, fov = pcall(scene.GetCameraFieldOfView or function() return SCENE_FOV end, scene)
	if not (okF and type(fov) == "number" and fov > 0) then fov = SCENE_FOV end
	local dist = api.npcPanelFitDistance(radius, fov, scene:GetWidth(), scene:GetHeight())
	if actor.SetPosition then pcall(actor.SetPosition, actor, 0, 0, 0) end
	-- the camera on the +x side looking back at the centre, z up
	pcall(scene.SetCameraPosition, scene, dist, 0, 0)
	pcall(scene.SetCameraOrientationByAxisVectors, scene, -1, 0, 0, 0, 1, 0, 0, 0, 1)
	if scene.SetCameraNearClip then pcall(scene.SetCameraNearClip, scene, math.max(dist - radius * 2, 0.01)) end
	if scene.SetCameraFarClip then pcall(scene.SetCameraFarClip, scene, dist + radius * 2) end
	sceneLog.framed, sceneLog.distance = sceneLog.framed + 1, dist
	return true
end

-- the camera before the size is known: some distance back, looking at the centre (the model loads while in view)
local function startCamera()
	pcall(scene.SetCameraPosition, scene, START_DISTANCE, 0, 0)
	pcall(scene.SetCameraOrientationByAxisVectors, scene, -1, 0, 0, 0, 1, 0, 0, 0, 1)
	if scene.SetCameraNearClip then pcall(scene.SetCameraNearClip, scene, 0.01) end
	if scene.SetCameraFarClip then pcall(scene.SetCameraFarClip, scene, 1000) end
end

function api.npcPanelDebug(say)
	say(("model panel: ModelScene=%s, objects framed=%d, back to PlayerModel=%d, last: loaded=%s box=%s radius=%s distance=%s file=%s"):format(
		tostring(scene ~= nil), sceneLog.framed, sceneLog.fellBack, tostring(sceneLog.loaded), tostring(sceneLog.box),
		tostring(sceneLog.radius), tostring(sceneLog.distance), tostring(sceneLog.file)))
end

-- an object's model file in the scene; false when it cannot be shown there
local function showInScene(modelFile)
	if not (scene and actor and modelFile) or sceneFailed[modelFile] then return false end
	if model then model:Hide() end
	if scene.key ~= modelFile then
		scene.key, scene.fitted, scene.since = modelFile, false, GetTime and GetTime() or 0
		sceneLog.file, sceneLog.loaded, sceneLog.box, sceneLog.radius, sceneLog.distance = modelFile, nil, nil, nil, nil
		if actor.ClearModel then pcall(actor.ClearModel, actor) end
		startCamera()
		if not pcall(actor.SetModelByFileID, actor, modelFile) then
			scene.key = nil
			scene:Hide()
			return false
		end
		actor.facing = 0
	end
	scene:Show()
	return scene
end

-- R106-120: the NPC's model not loaded yet: set it again (the game has asked the server for it by now)
local function modelLoaded()
	-- its model file once loaded; without that call, the OnModelLoaded mark
	if type(model.GetModelFileID) == "function" then
		local ok, file = pcall(model.GetModelFileID, model)
		return ok and type(file) == "number" and file > 0
	end
	return loadedKey ~= nil and loadedKey == model.key
end
function api.npcPanelReloadCheck()
	local r = reload
	if not (r and model) or not GetTime or GetTime() < r.at then return end
	if modelLoaded() or r.left <= 0 then reload = nil return end
	r.left, r.at = r.left - 1, GetTime() + RELOAD_EVERY
	pcall(model.SetCreature, model, r.id)
	if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
	if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1) end
	if model.SetFacing then pcall(model.SetFacing, model, model.facing or 0) end
end

-- the model for an NPC id or an object's model file: the frame it shows in; false when there is none to show
-- R106-114: scrolls and documents look better in the PlayerModel (user: "For scrolls/documents put them on the old
-- frame"): the scene frames them from the side, small and flat; by a word in the name or the object's name
local PAPER_WORDS = { "scroll", "scrolls", "document", "documents", "letter", "letters", "note", "notes", "parchment",
	"papers", "missive", "orders", "manifest", "page", "pages", "plans", "dossier", "journal", "map" }
local PAPER = {}
for _, w in ipairs(PAPER_WORDS) do PAPER[w] = true end
local function isPaper(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if type(name) == "string" and not isSecret(name) then
			for w in name:lower():gmatch("[%a']+") do if PAPER[w] then return true end end
		end
	end
	return false
end
api.npcPanelIsPaper = isPaper

local function showModel(npcId, modelFile, oldFrame)
	if not npcId and modelFile and not oldFrame then
		local inScene = showInScene(modelFile)
		if inScene then return inScene end
	end
	if scene then scene:Hide() end
	if not model then return false end
	local key = npcId and ("npc:" .. npcId) or modelFile and ("file:" .. tostring(modelFile))
	local setter = npcId and model.SetCreature or modelFile and model.SetModel
	if not (key and setter) then
		model:Hide()
		return false
	end
	if model.key ~= key then
		model.key = key
		if model.ClearModel then pcall(model.ClearModel, model) end
		if not pcall(setter, model, npcId or modelFile) then
			model.key = nil
			model:Hide()
			return false
		end
		model.facing = 0
		-- R106-120: an NPC the game has not seen yet loads blank the first time (user: "First time loading a boss' 3d
		-- tooltip, it stays blank"): set again every half second until it has loaded
		loadedKey = nil
		reload = npcId and { id = npcId, at = (GetTime and GetTime() or 0) + RELOAD_EVERY, left = RELOAD_TRIES } or nil
	end
	if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end -- the whole body
	if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1) end
	if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
	if model.SetFacing then pcall(model.SetFacing, model, model.facing or 0) end
	model:Show()
	return model
end

-- R106-113: the quest tooltip (GameTooltip) when it belongs to the hovered line or a frame it sits in (the quest)
local function questTip(owner)
	local tip = _G.GameTooltip
	if not (owner and tip and tip.IsShown and tip:IsShown() and tip.GetOwner) then return nil end
	local tipOwner = tip:GetOwner()
	if not tipOwner then return nil end
	local f = owner
	for _ = 1, 8 do
		if type(f) ~= "table" then break end
		if f == tipOwner then return tip end
		f = f.GetParent and f:GetParent() or nil
	end
	return nil
end

-- beside the tracker, level with the hovered line: on the left of the tracker, or on its right when the left has no room
local function place(owner, beside)
	panel:ClearAllPoints()
	-- R106-117: a frame to stand beside (the dungeon card for a boss): left of it, level with its top
	local bLeft, bTop = beside and beside.GetLeft and beside:GetLeft(), beside and beside.GetTop and beside:GetTop()
	if bLeft and bTop then
		local ps, bs = panel:GetEffectiveScale() or 1, beside:GetEffectiveScale() or 1
		if ps > 0 then
			panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", bLeft * bs / ps - GAP, bTop * bs / ps)
			return
		end
	end
	-- R106-113: left of the quest tooltip when one is up, if there is room
	local tip = questTip(owner)
	local tipLeft = tip and tip.GetLeft and tip:GetLeft()
	-- R106-117: only a tooltip on the left of the hovered frame (a boss portrait's opens on its right: the panel there
	-- would cover the card)
	local ownLeft = owner.GetLeft and owner:GetLeft()
	if tipLeft and ownLeft and tipLeft * (tip:GetEffectiveScale() or 1) >= ownLeft * (owner:GetEffectiveScale() or 1) then
		tipLeft = nil
	end
	if tipLeft then
		local ps, tps = panel:GetEffectiveScale() or 1, tip:GetEffectiveScale() or 1
		local tipTop = tip.GetTop and tip:GetTop()
		-- R106-115: a fixed place beside it, not tied to it (the game moves GameTooltip for whatever it shows next)
		if ps > 0 and tipTop and tipLeft * tps / ps - GAP - WIDTH >= 0 then
			panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", tipLeft * tps / ps - GAP, tipTop * tps / ps)
			return
		end
	end
	-- beside our tracker's frame
	local tracker = api.ownTrackerFrame and api.ownTrackerFrame()
	local s = panel:GetEffectiveScale() or 1
	local top = owner and owner.GetTop and owner:GetTop()
	local left = tracker and tracker.GetLeft and tracker:GetLeft()
	local right = tracker and tracker.GetRight and tracker:GetRight()
	if not (top and left and right and s > 0) then
		if owner then panel:SetPoint("TOPRIGHT", owner, "TOPLEFT", -GAP, PAD) else panel:SetPoint("CENTER") end
		return
	end
	local os, ts = owner:GetEffectiveScale() or 1, tracker:GetEffectiveScale() or 1
	local y = top * os / s + PAD
	local l, r = left * ts / s, right * ts / s
	if l - GAP - WIDTH >= 0 then
		panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l - GAP, y)
	else
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r + GAP, y)
	end
end

-- the panel drawn for what is hovered; false (and nothing shown) when it has no model
local function render()
	local cur = shown
	if not cur then return false end
	local hasModel -- the frame the model shows in
	if isObject(cur.kind) then hasModel = showModel(nil, cur.modelFile, isPaper(cur.name, cur.source)) else hasModel = showModel(cur.id, nil) end
	local iconOnly = not hasModel and isObject(cur.kind) and cur.icon ~= nil
	if not (hasModel or iconOnly) then
		panel:Hide()
		return false
	end
	local lines
	if iconOnly then
		lines = { { cur.name, kindColor(cur.kind) }, { "Item (no 3D model)", { 0.75, 0.75, 0.75 } }, {}, {} }
	elseif isObject(cur.kind) then
		-- an item's object under the item's name: "<Un'Goro Dirt Pile>"
		local from = cur.source and cur.source ~= cur.name and ("<" .. cur.source .. ">") or nil
		lines = { { cur.name, kindColor(cur.kind) }, { from, { 0.75, 0.75, 0.75 } }, {}, {} }
	else
		local d = npcDetails(cur.name, cur.id)
		lines = {
			{ d.name, kindColor(cur.kind) },
			{ d.subName and ("<" .. d.subName .. ">"), { 0.75, 0.75, 0.75 } },
			{ levelLine(d), { 1, 1, 1 } },
			{ d.creatureType, { 0.75, 0.75, 0.75 } },
		}
	end
	local y = -PAD
	local x = iconOnly and (PAD + ICON + 8) or PAD
	if iconOnly then
		iconTex:SetTexture(cur.icon)
		iconTex:ClearAllPoints()
		iconTex:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
		iconTex:Show()
	else
		iconTex:Hide()
	end
	for i, fs in ipairs(texts) do
		local text, color = lines[i][1], lines[i][2]
		fs:ClearAllPoints()
		fs:SetWidth(WIDTH - PAD - x)
		if text then
			fs:SetText(text)
			fs:SetTextColor(color[1], color[2], color[3])
			fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
			fs:Show()
			y = y - (fs:GetStringHeight() or 12) - 2
		else
			fs:SetText("")
			fs:Hide()
		end
	end
	if iconOnly then
		stage:Hide()
		panel:SetHeight(math.max(-y, PAD + ICON) + PAD)
		place(cur.owner, cur.beside)
		panel:Show()
		return true
	end
	y = y - 4
	stage:ClearAllPoints()
	stage:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD - 4, y)
	stage:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD + 4, y)
	stage:SetHeight(MODEL_H)
	stage:Show()
	hasModel:ClearAllPoints()
	hasModel:SetPoint("TOPLEFT", stage, "TOPLEFT")
	hasModel:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT")
	y = y - MODEL_H
	panel:SetHeight(-y + PAD)
	place(cur.owner, cur.beside)
	panel:Show()
	return true
end

api.npcPanelRender = render

local function stopRetry()
	if retryTicker then retryTicker:Cancel() end
	retryTicker = nil
end

-- 3.2 (user: a lag spike on an item with no model): what a name came to, once every name list was ready, so the next
-- hover (and the retries) do not search again. [key] = { modelFile, source } or { icon } or { none = <time> } (a miss is kept 60 s: Questie may still be loading)
local answers = {}
local NONE_KEEP = 60
local function answerKey(cur, names)
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local q = type(cur.quests) == "table" and table.concat(cur.quests, ",") or ""
	return table.concat(names, "|") .. "#" .. q .. "#" .. tostring(map)
end
api.npcPanelAnswers = answers -- (tests)

-- the model for the hovered name (or one of its other spellings); true when found
-- 3.2 (user: "make it easier for item names to match with their object names"): what you looted from an object, learnt
-- at the loot window: db.itemObjects[item name] = object id (any character; not in profiles). Exact, so it is tried first.
local function objectIdOf(guid)
	if type(guid) ~= "string" or isSecret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "GameObject" then return nil end
	return tonumber(id)
end
local function lookupLooted(name)
	local learned = db and type(db.itemObjects) == "table" and db.itemObjects[name]
	local file = learned and ns.objectModels[learned]
	if not file then return nil end
	local from = api.questieObjectName and api.questieObjectName(learned)
	return file, type(from) == "string" and not isSecret(from) and from or nil
end
function api.npcPanelLearnLoot()
	if not db or type(GetNumLootItems) ~= "function" or type(GetLootSourceInfo) ~= "function"
		or type(GetLootSlotInfo) ~= "function" then return end
	local okN, count = pcall(GetNumLootItems)
	local learned = false
	for i = 1, okN and tonumber(count) or 0 do
		local itemSlot = true
		if type(GetLootSlotType) == "function" then
			local okT, slotType = pcall(GetLootSlotType, i)
			local ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
			itemSlot = okT and slotType == ITEM
		end
		local okI, _, name = pcall(GetLootSlotInfo, i)
		local okS, guid = pcall(GetLootSourceInfo, i)
		local id = okS and objectIdOf(guid)
		if itemSlot and okI and id and type(name) == "string" and name ~= "" and not isSecret(name) then
			if type(db.itemObjects) ~= "table" then db.itemObjects = {} end
			if db.itemObjects[name] ~= id then db.itemObjects[name], learned = id, true end
		end
	end
	if learned then for k in pairs(answers) do answers[k] = nil end end -- the kept answers may be out of date now
end

local function resolveObject(cur, names)
	for _, n in ipairs(names) do
		local file, from = lookupLooted(n)
		if file then cur.modelFile, cur.source = file, from or cur.source return true end
	end
	for _, n in ipairs(names) do
		local file = lookupObjectModel(n)
		if file then cur.modelFile = file return true end
	end
	for _, n in ipairs(names) do
		local file, from = lookupItemSource(n)
		if file then cur.modelFile, cur.source = file, from return true end
	end
	-- R106-111: a vague or misspelt name: the step's quest's object, else one a letter or two off here
	local hit = lookupQuestObject(names, cur.quests)
	if hit then cur.modelFile, cur.source = hit.file, hit.name return true end
	if not stillLooking() then
		for _, n in ipairs(names) do
			local file, from = lookupNameInside(n)
			if file then cur.modelFile, cur.source = file, from return true end
		end
	end
	-- the near-spelling search waits until every name list is ready: it runs once, not on each retry
	if not modeled then buildModeled() end
	if stillLooking() then return false end
	hit = lookupTypoHere(names)
	if hit then cur.modelFile, cur.source = hit.file, hit.name return true end
	-- an item that does not come from an object: its icon instead of a model
	cur.icon = lookupItemIcon(names)
	return cur.icon ~= nil
end
local function resolve(cur)
	if isObject(cur.kind) then
		if cur.modelFile or cur.icon then return true end
		if cur.objectId and ns.objectModels[cur.objectId] then
			cur.modelFile = ns.objectModels[cur.objectId]
			return true
		end
		if cur.none then return false end
		local names = { cur.name, unpack(cur.forms or {}) }
		local key = answerKey(cur, names)
		local a = answers[key]
		if a and a.none and not (GetTime and GetTime() - a.none < NONE_KEEP) then a, answers[key] = nil, nil end
		if a then
			if a.none then cur.none = true return false end
			cur.modelFile, cur.icon = a.modelFile, a.icon
			cur.source = a.source or cur.source
			return true
		end
		local found = resolveObject(cur, names)
		if found then
			answers[key] = { modelFile = cur.modelFile, source = cur.source, icon = cur.icon }
		elseif not stillLooking() then
			answers[key] = { none = GetTime and GetTime() or 0 }
			cur.none = true
		end
		return found
	end
	if cur.id then return true end
	for _, n in ipairs({ cur.name, unpack(cur.forms or {}) }) do
		local id = lookupNpc(n)
		if id then cur.id = id return true end
	end
	return false
end

-- name: as the text shows it; opts: id (an NPC's) or objectId, kind ("friendly" / "enemy" for an NPC; "pick" /
-- "object" for an object), owner (the hovered line), forms (other spellings to look it up by, e.g. a singular).
-- Shows the panel only when there is a model; until then it keeps looking while the name stays hovered.
function api.showNpcPanel(name, opts)
	if type(name) ~= "string" or name == "" or isSecret(name) then return end
	opts = opts or {}
	build()
	stopRetry()
	shown = { name = name, id = tonumber(opts.id), objectId = tonumber(opts.objectId), kind = opts.kind,
		owner = opts.owner, beside = opts.beside, keepWhile = opts.keepWhile, forms = opts.forms, quests = opts.quests, source = type(opts.source) == "string" and opts.source or nil }
	if resolve(shown) and render() then return end
	panel:Hide()
	if shown.none then return end -- nothing to show, and nothing still loading: no retries
	if C_Timer and C_Timer.NewTicker then
		local tries = 0
		retryTicker = C_Timer.NewTicker(0.5, function()
			tries = tries + 1
			local cur = shown
			if not cur or tries > RETRIES or cur.none then stopRetry() return end
			if not stillHovered(cur.keepWhile or cur.owner) then api.hideNpcPanel() return end
			if resolve(cur) then
				stopRetry()
				render()
			end
		end)
	end
end

-- owner given: hidden only when the panel is up (or waiting) for it
function api.hideNpcPanel(owner)
	if not panel then return end
	if owner and shown and shown.owner ~= owner then return end
	stopRetry()
	shown = nil
	panel:Hide()
end

function api.npcPanelShown() return shown end

-- Quest tracker: while a quest is hovered, the objective line under the mouse names one of its NPCs or objects
local function plainText(t)
	if type(t) ~= "string" or isSecret(t) then return nil end
	return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1"))
end

local function npcOnLine(text, npcs)
	text = plainText(text)
	if not text then return nil end
	local low = text:lower()
	for _, n in ipairs(npcs) do
		for _, label in ipairs({ n.text or false, n.name or false }) do
			if type(label) == "string" and label ~= "" and low:find(label:lower(), 1, true) then return n end
		end
	end
end
api.npcPanelLineMatch = npcOnLine

-- the panel for an objective's NPC or object (from questObjectiveNpcs), beside the hovered line
local function showFound(found, owner)
	if found.objectId then
		api.showNpcPanel(found.item or found.name or found.text, { objectId = found.objectId, kind = "object", owner = owner,
			source = found.item and found.name or nil })
	else
		api.showNpcPanel(found.name or found.text, { id = found.id, kind = "enemy", owner = owner })
	end
end

local function enabled() return db and db.npcPanelQuests ~= false end
api.npcPanelQuestsOn = enabled

-- R106-127: a "More quests" objective line (MoreQuests.lua: quests past the game's tracking limit, drawn by us) has
-- its own hover button: hovering it shows the model of the NPC or object the line names, as on the tracked quests
function api.npcLineHover(owner, questId, text)
	if not (enabled() and type(owner) == "table" and questId) then return end
	local found = npcOnLine(text, api.questObjectiveNpcs and api.questObjectiveNpcs(questId) or {})
	if found then showFound(found, owner) end
end

-- the creature type of each unit seen (target, mouseover), by npc id
local function seen(unit)
	if not (db and UnitExists and UnitExists(unit)) then return end
	if UnitIsPlayer and UnitIsPlayer(unit) then return end
	local id = npcIdOf(UnitGUID(unit))
	local kind = id and UnitCreatureType and UnitCreatureType(unit)
	if type(kind) ~= "string" or isSecret(kind) or kind == "" then return end
	if type(db.npcTypes) ~= "table" then db.npcTypes = {} end
	if db.npcTypes[id] ~= kind then db.npcTypes[id] = kind end
end

-- R106-117: a left click on one of DungeonJournal's boss portraits on the dungeon card (or the click-to-target button
-- over it) opens the boss's 3D model left of the card (user: "Not on hover. On left click, put the 3d tooltip to the
-- left of the dungeon card"); a second click on the same boss closes it; it also closes when the mouse leaves the card.
-- The portrait holds its boss (owner.boss, or owner.portrait.boss on a target button): { name, npcID or portraitNpcID }.
-- The frames are DungeonJournal's, made when it needs them: each is hooked the first time its tooltip shows (a
-- post-hook on GameTooltip:Show); OnMouseUp is hooked (the target button's own click, a secure action, is untouched),
-- never in combat.
local function bossOf(owner)
	if type(owner) ~= "table" then return nil end
	local boss = rawget(owner, "boss")
	if type(boss) ~= "table" then
		local portrait = rawget(owner, "portrait")
		boss = type(portrait) == "table" and rawget(portrait, "boss") or nil
	end
	return type(boss) == "table" and type(boss.name) == "string" and boss or nil
end
local function cardOf() return _G.ForeverTrackerPlusDungeonCard end
function api.npcPanelBossClick(owner, button)
	if button ~= "LeftButton" then return end
	local boss = bossOf(owner)
	if not boss or isSecret(boss.name) then return end
	if shown and shown.boss == boss then api.hideNpcPanel() return end
	local card = cardOf()
	local onCard = card and card.IsShown and card:IsShown() and card or nil
	api.showNpcPanel(boss.name, { id = tonumber(boss.npcID) or tonumber(boss.portraitNpcID), kind = "enemy", owner = owner,
		beside = onCard, keepWhile = onCard or owner })
	if shown then shown.boss = boss end
end
local hookedBoss = setmetatable({}, { __mode = "k" })
-- R106-118: the hint "Left-click to show 3D" in the portrait's tooltip, above DungeonJournal's own gold hint at its end
-- ("Click to show loot") when there is one, else at the end.
-- R106-119: a rare not seen yet: DungeonJournal's grey line under the name ("not found"; "not killed" on the target
-- button, which does not know) becomes "Rare not found (yet?)" at the very bottom (user).
-- The tooltip's lines are read and written back in the new order on each Show (DungeonJournal adds lines after its
-- first Show); a guard keeps our own Show from coming back here.
local HINT = "Left-click to show 3D"
local NOT_FOUND = "Rare not found (yet?)"
local GOLDISH = 0.05
local addingHint
local function lineFs(tip, side, i)
	local name = tip.GetName and tip:GetName()
	return name and _G[name .. "Text" .. side .. i]
end
local function readLine(tip, i)
	local l, r = lineFs(tip, "Left", i), lineFs(tip, "Right", i)
	local e = { text = l and l.GetText and l:GetText() }
	if l and l.GetTextColor then e.c = { l:GetTextColor() } end
	local rt = r and r.IsShown and r:IsShown() and r.GetText and r:GetText()
	if type(rt) == "string" and rt ~= "" then e.right = rt; e.rc = r.GetTextColor and { r:GetTextColor() } or nil end
	return e
end
local function isGold(e)
	local c = e.c or {}
	return math.abs((c[1] or 0) - 1) < GOLDISH and math.abs((c[2] or 0) - 0.82) < GOLDISH and (c[3] or 1) < GOLDISH
end
local function writeLine(tip, i, e)
	local l, r = lineFs(tip, "Left", i), lineFs(tip, "Right", i)
	if l then
		l:SetText(e.text or "")
		local c = e.c or { 1, 1, 1 }
		if l.SetTextColor then l:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
		if l.Show then l:Show() end
	end
	if r then
		if e.right then
			r:SetText(e.right)
			local c = e.rc or { 1, 1, 1 }
			if r.SetTextColor then r:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
			if r.Show then r:Show() end
		elseif r.Hide then
			r:Hide()
		end
	end
end
-- the portrait (not the target button over it): its isRare and notFound
local function portraitOf(owner)
	if type(owner) ~= "table" then return nil end
	if type(rawget(owner, "boss")) == "table" then return owner end
	local p = rawget(owner, "portrait")
	return type(p) == "table" and p or nil
end
local function arrange(tip, owner)
	if addingHint then return end
	local n = tip.NumLines and tip:NumLines() or 0
	if n < 1 then return end
	local p = portraitOf(owner)
	local notFound = p and rawget(p, "isRare") and rawget(p, "notFound") and true or false
	local lines, hadHint, hadNF = {}, false, false
	for i = 2, n do
		local e = readLine(tip, i)
		if e.text == HINT then hadHint = true
		elseif e.text == NOT_FOUND then hadNF = true
		else lines[#lines + 1] = e end
	end
	-- DungeonJournal's grey line under the name, the first time
	if notFound and not hadNF and lines[1] and not lines[1].right and not isGold(lines[1]) then table.remove(lines, 1) end
	local hint = { text = HINT, c = { 1, 0.82, 0 } }
	if lines[#lines] and isGold(lines[#lines]) then table.insert(lines, #lines, hint) else lines[#lines + 1] = hint end
	if notFound then lines[#lines + 1] = { text = NOT_FOUND, c = { 0.75, 0.72, 0.66 } } end
	-- unchanged: nothing to write (DungeonJournal's later Show calls come back here)
	local same = #lines + 1 == n
	if same then
		for i, e in ipairs(lines) do
			local cur = readLine(tip, i + 1)
			if cur.text ~= e.text or cur.right ~= e.right then same = false break end
		end
	end
	if same then return end
	addingHint = true
	while (tip:NumLines() or 0) < #lines + 1 do tip:AddLine(" ") end
	for i, e in ipairs(lines) do writeLine(tip, i + 1, e) end
	tip:Show()
	addingHint = false
end
api.npcPanelBossHint = arrange

local function onTooltipShow(tip)
	local owner = tip.GetOwner and tip:GetOwner()
	if not bossOf(owner) then return end
	if not addingHint then pcall(arrange, tip, owner) addingHint = false end
	if hookedBoss[owner] or not owner.HookScript then return end
	if InCombatLockdown and InCombatLockdown() then return end
	hookedBoss[owner] = true
	owner:HookScript("OnMouseUp", function(self, button) api.npcPanelBossClick(self, button) end)
end
api.npcPanelBossTooltip = onTooltipShow

ns.onLogin[#ns.onLogin + 1] = function()
	db = ns.db
	if _G.GameTooltip and hooksecurefunc then
		hooksecurefunc(_G.GameTooltip, "Show", onTooltipShow)
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	f:RegisterEvent("LOOT_OPENED")
	f:SetScript("OnEvent", function(_, event)
		if event == "LOOT_OPENED" then pcall(api.npcPanelLearnLoot) return end
		seen(event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover")
	end)
end
