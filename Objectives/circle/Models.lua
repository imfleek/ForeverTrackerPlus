local _, root = ...; local ns = root.objectives
if not ns.rxp then return end

local db = ns.db

-- Target circles show the unit's picture before it has been seen. A portrait texture (SetPortraitTexture) needs the
-- unit in sight (target, mouseover, a nameplate: Circle.lua onUnitSighting); until then a circle shows the creature's
-- model, framed on its face, from its NPC id:
--   * ids seen: every wanted unit sighted once (any unit token) leaves its npc id, kept across sessions (db.npcIds);
--   * Questie's database (LibQuestieDB Npc.IdsByName, its name index built a slice per frame, once, on first need).
-- A real portrait replaces the model as soon as one is drawn; with no id the "unseen" mark stays, as before.
-- CONSTRAINT: Forever 1.60.1 (wow-ui-source forever 3d8abb1d, FrameAPICharacterModelBaseDocumentation.lua) declares
-- SetCreature(creatureID, displayID), SetPortraitZoom, SetCamDistanceScale, SetKeepModelOnHide on PlayerModel; each
-- call is checked and guarded, so a client without one keeps the old behaviour.
-- CONSTRAINT: a model cannot take a texture mask; it is sized to the square inside the round icon so it never covers
-- the ring. One model per circle that needs one, reused; nothing runs per frame.

local INSIDE = 0.71 -- side of the square inscribed in the round icon
local INDEX_SLICE = 250 -- Questie ids per frame while its name index is built

if type(db.npcIds) ~= "table" then db.npcIds = {} end
local npcIds = db.npcIds
local wantedNames = {} -- names a circle asked a model for

-- npc id from a creature GUID ("Creature-0-server-instance-zone-npcID-spawn"); nil for players, pets, secrets
local function npcIdOf(guid)
	if type(guid) ~= "string" or ns.isSecret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end
ns.npcIdOf = npcIdOf

-- Questie's npc name index, built in slices; nil until ready, false when there is none
local questieIndex
local building = false
local pendingModels = {}
local refreshModels

local function questieNpc()
	local lib = _G.LibQuestieDB
	local npc = type(lib) == "table" and lib.Npc
	if type(npc) ~= "table" or type(npc.IdsByName) ~= "function" or type(npc.BuildNameIndexAsync) ~= "function" then
		return nil
	end
	local trackerApi = root.tracker and root.tracker.api
	if trackerApi and trackerApi.questieOn and not trackerApi.questieOn() then return nil end
	return npc
end

local function buildQuestieIndex()
	if questieIndex ~= nil or building then return end
	local npc = questieNpc()
	if not npc then return end
	building = true
	local job = coroutine.create(function() npc.BuildNameIndexAsync(INDEX_SLICE) end)
	local function step()
		local ok, err = coroutine.resume(job)
		if not ok then
			building, questieIndex = false, false
			geterrorhandler()(err)
		elseif coroutine.status(job) == "dead" then
			building, questieIndex = false, npc
			refreshModels()
		else
			C_Timer.After(0, step)
		end
	end
	step()
end

function ns.npcIdFor(name)
	if type(name) ~= "string" then return nil end
	local id = npcIds[name]
	if id then return id end
	if questieIndex then
		local ok, ids = pcall(questieIndex.IdsByName, name)
		id = ok and type(ids) == "table" and tonumber(ids[1]) or nil
		if id then return id end
	elseif questieIndex == nil then
		buildQuestieIndex()
	end
	return nil
end

-- a wanted unit in sight: remember its id
local function unitSeen(token)
	if not token or not UnitExists(token) then return end
	local name = ns.rxp.GetUnitName and ns.rxp.GetUnitName(token)
	if not (name and wantedNames[name]) or ns.isSecret(name) then return end
	local id = npcIdOf(UnitGUID(token))
	if id and npcIds[name] ~= id then
		npcIds[name] = id
		refreshModels()
	end
end
ns.onUnitSighting(unitSeen)

local shelf = CreateFrame("Frame", nil, UIParent)
shelf:Hide()
local free = {}

local function newModel()
	local model = table.remove(free)
	if model then return model end
	local ok
	ok, model = pcall(CreateFrame, "PlayerModel", nil, shelf)
	if not ok or type(model) ~= "table" or type(model.SetCreature) ~= "function" then return nil end
	if model.SetKeepModelOnHide then pcall(model.SetKeepModelOnHide, model, true) end
	if model.EnableMouse then model:EnableMouse(false) end
	-- CONSTRAINT: an uncached creature draws nothing until its model loads; where the client reports the load, the
	-- unseen mark stays until then (model.loaded false), else it goes at once (model.loaded nil).
	if model.HasScript and model:HasScript("OnModelLoaded") then
		model:SetScript("OnModelLoaded", function(self)
			self.loaded = true
			local button = self.button
			if button and button.model == self then ns.setMark(button, button.use, button.portrait) end
		end)
		model.watchesLoad = true
	end
	return model
end

local function sizeModel(button)
	local model, icon = button.model, button.icon
	if not (model and icon) then return end
	local side = (icon:GetWidth() or 0) * INSIDE
	model:SetSize(side, side)
end
ns.sizeCircleModel = sizeModel

local function showCreature(model, id)
	if model.npcId == id then return end
	model.npcId = id
	if model.watchesLoad then model.loaded = false end
	if model.ClearModel then pcall(model.ClearModel, model) end
	pcall(model.SetCreature, model, id)
	if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 1) end
	if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1) end
end

function ns.hideCircleModel(button)
	local model = button.model
	if not model then return end
	model:Hide()
	model:SetParent(shelf)
	model.name, model.button = nil, nil
	button.model = nil
	free[#free + 1] = model
end

-- The model for a unit circle with no portrait; true when one is shown. `parent` holds it (the button, or its art).
function ns.showCircleModel(button, name, parent)
	if not name then
		ns.hideCircleModel(button)
		return false
	end
	wantedNames[name] = true
	local id = ns.npcIdFor(name)
	if not id then
		pendingModels[button] = { name = name, parent = parent }
		ns.hideCircleModel(button)
		return false
	end
	pendingModels[button] = nil
	local model = button.model or newModel()
	if not model then return false end
	button.model = model
	if model:GetParent() ~= parent then model:SetParent(parent) end
	model:ClearAllPoints()
	model:SetPoint("CENTER", button.icon, "CENTER")
	model:SetFrameLevel(parent:GetFrameLevel() + 1)
	model.name, model.button = name, button
	sizeModel(button)
	model:Show()
	showCreature(model, id)
	return true
end

-- ids that became known (a sighting, Questie's index): circles that waited for one get their model
function refreshModels()
	for button, want in pairs(pendingModels) do
		pendingModels[button] = nil
		if button:IsShown() and not button.portrait and button.use and button.use.name == want.name then
			if ns.showCircleModel(button, want.name, want.parent) then ns.setMark(button, button.use, nil) end
		end
	end
end
