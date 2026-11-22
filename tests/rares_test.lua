-- R106-101: rares near your quests: a tag on your zone's header, nearest rare first, hover model, click waypoint
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local handlers
local named = {}
local function frame(name)
	local f = { points = {}, scripts = {}, shown = true }
	local m = {
		SetScript = function(self, k, fn) self.scripts[k] = fn; if not name then handlers = fn end end,
		CreateFontString = function() return frame("fs") end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		SetParent = function(self, p) self.parent = p end, GetParent = function(self) return self.parent end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		ClearAllPoints = function(self) self.points = {} end,
		GetFont = function() return "font", 12, "" end, GetFrameLevel = function() return 3 end,
		GetStringWidth = function() return 80 end, GetStringHeight = function() return 12 end,
	}
	if name then named[name] = f end
	return setmetatable(f, { __index = function(_, k) return m[k] or function() end end })
end
local now = 10
local units = {}
local vignettes = {}
local tips = {}
local waypoint, superTrack
local headerParent = frame("block")
local zoneLabel = frame("label")
zoneLabel.parent = headerParent
local ns = { api = {}, onLogin = {}, db = {} }
ns.api.zoneLabelFor = function(z) return z == "Elwynn Forest" and zoneLabel or nil end
ns.api.playerWorldPos = function() return { continent = 0, x = 0, y = 0, map = 1429 } end
local panel
ns.api.showNpcPanel = function(name, o) panel = { name = name, opts = o } end
ns.api.hideNpcPanel = function() panel = nil end
local env = setmetatable({
	CreateFrame = function(_, name) return frame(name) end, UIParent = frame("UIParent"), GetTime = function() return now end,
	C_Map = {
		GetBestMapForUnit = function() return 1429 end, GetMapInfo = function() return { name = "Elwynn Forest" } end,
		GetWorldPosFromMapPos = function(_, v) return 0, { x = v.x * 1000, y = v.y * 1000 } end,
		SetUserWaypoint = function(p) waypoint = p end,
	},
	C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) superTrack = v end },
	UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end },
	CreateVector2D = function(x, y) return { x = x, y = y } end,
	C_VignetteInfo = {
		GetVignettes = function() local l = {} for g in pairs(vignettes) do l[#l + 1] = g end return l end,
		GetVignetteInfo = function(g) return vignettes[g] end,
		GetVignettePosition = function(g) return vignettes[g] and vignettes[g].pos end,
	},
	GetRealZoneText = function() return "Elwynn Forest" end,
	UnitExists = function(u) return units[u] ~= nil end, UnitIsPlayer = function() return false end,
	UnitIsDead = function(u) return units[u] and units[u].dead end,
	UnitClassification = function(u) return units[u].class end, UnitGUID = function(u) return units[u].guid end,
	UnitName = function(u) return units[u].name end,
	strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = p end return table.unpack(out) end,
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
	C_Timer = { NewTicker = function() return { Cancel = function() end } end },
	GameTooltip = setmetatable({ AddLine = function(_, t) tips[#tips + 1] = t end,
		AddDoubleLine = function(_, a, b) tips[#tips + 1] = a .. "|" .. b end }, { __index = function() return function() end end }),
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Rares.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
local api = ns.api
ns.onLogin[1]()
local function fire(e, a) handlers(nil, e, a) end

check("on by default", api.rareAlertOn() == true)
units.target = { class = "elite", guid = "Creature-0-1-0-5-100-1", name = "Not Rare" }
fire("PLAYER_TARGET_CHANGED")
check("a plain elite: no tag", named.ForeverTrackerPlusRareTag == nil or not named.ForeverTrackerPlusRareTag.shown)
vignettes.v1 = { atlasName = "VignetteKill", objectGUID = "Creature-0-1-0-5-61-1", name = "Thuros Lightfingers",
	pos = { x = 0.3, y = 0.4 } }
fire("VIGNETTES_UPDATED")
local tag = named.ForeverTrackerPlusRareTag
check("a kill vignette: the tag shows", tag and tag.shown)
check("on the zone header's block", tag and tag.parent == headerParent)
check("its name and yards", tag and tag.text.text:find("Thuros Lightfingers", 1, true) and tag.text.text:find("500 yd", 1, true))
units.mouseover = { class = "rareelite", guid = "Creature-0-1-0-5-99-1", name = "Mother Fang" }
fire("UPDATE_MOUSEOVER_UNIT")
check("a rare unit you see: first (nearby), '+1' for the other", tag.text.text:find("Mother Fang", 1, true)
	and tag.text.text:find("nearby", 1, true) and tag.text.text:find("+1", 1, true))
tag.scripts.OnEnter(tag)
check("hover: the model panel for it", panel and panel.name == "Mother Fang" and panel.opts.id == 99)
local both = table.concat(tips, "\n")
check("hover: the tooltip lists both", both:find("Mother Fang|nearby", 1, true) and both:find("Thuros Lightfingers|500 yd", 1, true))
tag.scripts.OnLeave(tag)
check("leave: the panel goes", panel == nil)
fire("UNIT_DIED", "Creature-0-1-0-5-99-1")
check("dead: off the list", not tag.text.text:find("Mother Fang", 1, true))
tag.scripts.OnClick(tag)
check("click: a waypoint to the rare, super-tracked", waypoint and waypoint.m == 1429 and waypoint.x == 0.3 and superTrack == true)
now = now + 200
api.refreshRares()
check("unseen for 2 minutes: the tag goes", not tag.shown)
ns.api.zoneLabelFor = function() return nil end
fire("VIGNETTES_UPDATED")
check("zone with no tracked quests (no header): no tag", not tag.shown)
api.setRareAlert(false)
check("option off", api.rareAlertOn() == false and #api.raresSpotted() == 0)
local src = io.open(dir .. "/Tracker/Rares.lua"):read("a")
check("never the combat log event (forbidden for addons on Forever)", not src:find('"COMBAT_LOG_EVENT_UNFILTERED"', 1, true))
local toc = io.open(dir .. "/ForeverTrackerPlus.toc"):read("a")
check("in the toc", toc:find("Tracker/Rares.lua", 1, true) ~= nil)
print(pass and "PASSED" or "FAILED")
