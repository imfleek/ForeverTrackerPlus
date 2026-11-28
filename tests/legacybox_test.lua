-- 3.2 (user: "Add a checkboxes to challenges on blizzard's legacy challenges window to be able track them"):
-- a Track box on each open card in Blizzard's Legacy Challenges window (Tracker/Own/Legacy.lua)
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

-- frames: plain tables with the methods the code calls
local made = {}
local function frame(kind, parent)
	local f = { kind = kind, parent = parent, shown = true, checked = false, scripts = {}, level = 5 }
	function f:GetObjectType() return self.kind end
	function f:GetParent() return self.parent end
	function f:SetSize(w, h) self.w, self.h = w, h end
	function f:SetPoint(...) self.point = { ... } end
	function f:SetFrameLevel(l) self.level = l end
	function f:GetFrameLevel() return self.level end
	function f:CreateFontString() local t = { SetPoint = function() end, SetText = function(s, v) s.text = v end,
		GetStringWidth = function() return 30 end } return t end
	function f:SetHitRectInsets(...) self.insets = { ... } end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	function f:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
	function f:UnregisterEvent(e) if self.events then self.events[e] = nil end end
	function f:SetShown(v) self.shown = v end
	function f:SetChecked(v) self.checked = v and true or false end
	function f:GetChecked() return self.checked end
	made[#made + 1] = f
	return f
end
_G.CreateFrame = function(kind, _, parent) return frame(kind, parent) end
_G.hooksecurefunc = function(t, name, fn)
	local orig = t[name]
	t[name] = function(...) local r = { orig(...) }; fn(...); return table.unpack(r) end
end
_G.UnitName = function() return "Me" end
_G.GetRealmName = function() return "Realm" end
_G.GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end, Show = function() end,
	Hide = function() end, GetOwner = function() end }

local ns = { api = {}, db = {} }
assert(loadfile(dir .. "/Tracker/Own/Legacy.lua"))("ForeverTrackerPlus", { tracker = ns })
local api = ns.api

-- Blizzard_LegacySystem not loaded yet: we wait for it
local waiter
for _, f in ipairs(made) do if f.events and f.events.ADDON_LOADED then waiter = f end end
check("waits for Blizzard_LegacySystem to load", waiter ~= nil)
_G.LegacyChallengeTemplateMixin = { Init = function(self, data) self.id = data.id; self.completed = data.completed end }
waiter.scripts.OnEvent(waiter, "ADDON_LOADED", "SomethingElse")
check("another addon loading does nothing", waiter.events.ADDON_LOADED == true)
waiter.scripts.OnEvent(waiter, "ADDON_LOADED", "Blizzard_LegacySystem")
check("hooked once it loads", waiter.events.ADDON_LOADED == nil)

local card = frame("Button")
_G.LegacyChallengeTemplateMixin.Init(card, { id = 501, completed = false })
local box = card.ftpTrack
check("an open card gets a Track box", box ~= nil and box.shown == true and box.ftpLabel.text == "Track"
	and box.point[1] == "BOTTOMRIGHT" and box.point[2] == card)
check("not tracked yet: unticked", box.checked == false)
box.checked = true
box.scripts.OnClick(box)
check("ticked: tracked in our list", api.legacyIsTracked(501))
box.checked = false
box.scripts.OnClick(box)
check("unticked: not tracked", not api.legacyIsTracked(501))

-- tracked elsewhere (the Guides page, a Shift-click in our tracker): the box follows
api.legacySetTracked(501, true)
check("tracked elsewhere: the box ticks itself", box.checked == true)
api.legacySetTracked(501, false)
check("stopped elsewhere: the box unticks itself", box.checked == false)

-- a recycled card shows a finished challenge: no box
_G.LegacyChallengeTemplateMixin.Init(card, { id = 502, completed = true })
check("a finished challenge: no box", card.ftpTrack == box and box.shown == false)
_G.LegacyChallengeTemplateMixin.Init(card, { id = 503, completed = false })
check("recycled to an open one: the box again, one box only", box.shown == true and card.ftpTrack == box)

-- the list is full (10): the box does not stay ticked
for i = 1, 10 do api.legacySetTracked(900 + i, true) end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
box.checked = true
box.scripts.OnClick(box)
check("list full: the box unticks, not tracked", box.checked == false and not api.legacyIsTracked(503))

local src = io.open(dir .. "/Tracker/Own/Legacy.lua"):read("a")
check("only a post-hook on the card mixin, nothing of Blizzard's changed",
	src:find('hooksecurefunc(mixin, "Init"', 1, true) ~= nil and not src:find(".Tracked:", 1, true))
print(pass and "PASS" or "FAILED")
