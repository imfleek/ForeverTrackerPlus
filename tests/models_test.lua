-- Target circles show the creature's model before the unit is seen: npc id from a sighting (kept) or Questie's name index
local A = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local timers = {}
_G.C_Timer = { After = function(_, f) timers[#timers + 1] = f end }
local function run() local n = 0 while #timers > 0 and n < 1000 do n = n + 1; table.remove(timers, 1)() end end
_G.strsplit = function(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
	return table.unpack(out)
end
_G.geterrorhandler = function() return print end

local function newFrame(kind)
	local f = { kind = kind, shown = true, scripts = {}, level = 1, w = 0, h = 0 }
	function f:Hide() self.shown = false end
	function f:Show() self.shown = true end
	function f:IsShown() return self.shown end
	function f:SetParent(p) self.parent = p end
	function f:GetParent() return self.parent end
	function f:ClearAllPoints() end
	function f:SetPoint() end
	function f:SetSize(w, h) self.w, self.h = w, h end
	function f:SetFrameLevel(l) self.level = l end
	function f:GetFrameLevel() return self.level end
	function f:EnableMouse() end
	if kind == "PlayerModel" then
		function f:SetCreature(id) self.creature = id; self.creatureCalls = (self.creatureCalls or 0) + 1 end
		function f:SetPortraitZoom(z) self.zoom = z end
		function f:SetKeepModelOnHide() end
		function f:ClearModel() self.creature = nil end
		function f:HasScript(name) return name == "OnModelLoaded" end
		function f:SetScript(name, fn) self.scripts[name] = fn end
	end
	return f
end
local created = 0
_G.CreateFrame = function(kind, _, parent)
	if kind == "PlayerModel" then created = created + 1 end
	local f = newFrame(kind); f.parent = parent; return f
end
_G.UIParent = newFrame("Frame")

local units = {}
_G.UnitExists = function(t) return units[t] ~= nil end
_G.UnitGUID = function(t) return units[t] and units[t].guid end
local sighting
local marks = {}
local ns = { db = {}, isSecret = function() return false end,
	onUnitSighting = function(f) sighting = f end,
	setMark = function(button) marks[#marks + 1] = button end }
ns.rxp = { GetUnitName = function(t) return units[t] and units[t].name end }
local root = { objectives = ns }

-- Questie's database, name index built in slices (a coroutine that yields)
local built, slices = false, 0
_G.LibQuestieDB = { Npc = {
	BuildNameIndexAsync = function(n) for _ = 1, 3 do slices = slices + 1; coroutine.yield() end built = true end,
	IdsByName = function(name) assert(built, "index read before built"); return name == "Kobold Vermin" and { 6 } or nil end,
} }
assert(loadfile(A .. "/Objectives/circle/Models.lua"))("x", root)
check("loaded with a sighting listener and a saved id table", sighting ~= nil and type(ns.db.npcIds) == "table")

local function newButton(name)
	local b = newFrame("Button")
	b.icon = newFrame("Texture"); b.icon.GetWidth = function() return 40 end
	b.use = { type = "unit", name = name }
	return b
end

local b1 = newButton("Kobold Vermin")
check("unknown id: no model yet, Questie index started", ns.showCircleModel(b1, "Kobold Vermin", b1) == false
	and b1.model == nil and slices == 1)
check("index built a slice per frame, not at once", not built and #timers == 1)
run()
check("index done: the waiting circle gets its model", built and b1.model ~= nil and b1.model.creature == 6
	and b1.model.zoom == 1 and b1.model:IsShown())
check("model inside the round icon", math.abs(b1.model.w - 40 * 0.71) < 0.01)
check("model not drawn yet: mark kept (loaded false)", b1.model.loaded == false)
b1.model.scripts.OnModelLoaded(b1.model)
check("model loaded: mark updated", b1.model.loaded == true and marks[#marks] == b1)

-- a sighting remembers the id (saved), and beats Questie
local b2 = newButton("Garrick Padfoot")
check("not in Questie: no model", ns.showCircleModel(b2, "Garrick Padfoot", b2) == false)
units.nameplate1 = { name = "Garrick Padfoot", guid = "Creature-0-1-0-12-103-0000ABCD" }
sighting("nameplate1")
check("nameplate sighting: id saved and model shown", ns.db.npcIds["Garrick Padfoot"] == 103 and b2.model
	and b2.model.creature == 103)
units.target = { name = "Garrick Padfoot", guid = "Player-1-0ABC" }
sighting("target")
check("a player of the same name is not taken", ns.db.npcIds["Garrick Padfoot"] == 103)
units.mouseover = { name = "Someone Else", guid = "Creature-0-1-0-12-999-0" }
sighting("mouseover")
check("units no circle wants are not saved", ns.db.npcIds["Someone Else"] == nil)

-- reuse
local model = b2.model
local calls = model.creatureCalls
ns.showCircleModel(b2, "Garrick Padfoot", b2)
check("same creature again: no reload", model.creatureCalls == calls and b2.model == model)
ns.hideCircleModel(b2)
check("hidden: model back on the shelf", b2.model == nil and not model:IsShown())
local before = created
local b3 = newButton("Kobold Vermin")
ns.showCircleModel(b3, "Kobold Vermin", b3)
check("a freed model is reused", created == before and b3.model == model and model.creature == 6)

-- no PlayerModel support: old behaviour, no error
_G.CreateFrame = function(kind, _, parent) local f = newFrame("Frame"); f.parent = parent; return f end
local ns2 = { db = {}, isSecret = function() return false end, onUnitSighting = function() end, setMark = function() end,
	rxp = ns.rxp }
_G.LibQuestieDB = nil
assert(loadfile(A .. "/Objectives/circle/Models.lua"))("x", { objectives = ns2 })
ns2.db.npcIds["Kobold Vermin"] = 6
local b4 = newButton("Kobold Vermin")
check("client without PlayerModel.SetCreature: no model, no error", ns2.showCircleModel(b4, "Kobold Vermin", b4) == false
	and b4.model == nil)
print(pass and "PASS" or "FAILED")
