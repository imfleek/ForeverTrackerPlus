-- R106-49: Quest list > "Keep the Quests header at the top": the header leaves the scrolling list for a holder just
-- above the clip edge, the fixed strip grows by its room, and it goes back when switched off or not first.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local src = io.open(dir .. "/Tracker/Core.lua"):read("a")
local body = src:match("(local headerHolder\n.-\nfunction ns%.api%.setPinQuestsHeader)")
check("the pin code found in Core.lua", body ~= nil)
if not body then print("FAILED") return end
body = body:gsub("\nfunction ns%.api%.setPinQuestsHeader$", "\n")

local function frame(name, top, bottom, left, width)
	local f = { name = name, top = top, bottom = bottom, left = left, width = width or 200, points = {}, shown = true, scale = 1 }
	function f:GetTop() return self.top end
	function f:GetBottom() return self.bottom end
	function f:GetLeft() return self.left end
	function f:GetRight() return self.left + self.width end
	function f:GetChildren() return table.unpack(self.children or {}) end
	function f:GetWidth() return self.width end
	function f:GetEffectiveScale() return self.scale end
	function f:IsShown() return self.shown end
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false end
	function f:SetParent(p) self.parent = p end
	function f:GetParent() return self.parent end
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(p, rel, rp, x, y) self.points[#self.points + 1] = { p, rel, rp, x, y } end
	function f:GetNumPoints() return #self.points end
	function f:GetPoint(i) local p = self.points[i]; return p[1], p[2], p[3], p[4], p[5] end
	function f:SetScale(s) self.setScale = s end
	function f:SetFrameStrata() end
	function f:GetFrameStrata() return "MEDIUM" end
	function f:SetFrameLevel() end
	function f:GetFrameLevel() return 1 end
	function f:SetAlpha() end
	function f:SetSize(w, h) self.w, self.h = w, h end
	return f
end
local module = frame("quests", 500, 100, 20)
module.GetContentsHeight = function() return 300 end
local header = frame("header", 500, 475, 20)
header.parent = module
header:SetPoint("TOPLEFT", module, "TOPLEFT", 0, 0)
module.Header = header
-- R106-54: the first quest hangs on the header (TOP at its BOTTOM, 4 px lower), as Blizzard chains them
local block = frame("block", 470, 420, 20)
block:SetPoint("TOP", header, "BOTTOM", 0, -4)
module.usedBlocks = { quest = { [101] = block } }
local ghost = frame("ghost", 520, 0, 10)
local hooks = {}
local db = { pinQuestsHeader = true }
local combat = false
local env = setmetatable({
	db = db, ns = { api = {} }, guard = false, tracker = frame("tracker", 520, 0, 10), ghost = ghost,
	guarded = function(fn) fn() end, withAlpha = function(f) return f end,
	CreateFrame = function() return frame("holder", 0, 0, 0) end, UIParent = frame("ui", 0, 0, 0),
	toScreen = function(_, v) return v end,
	moduleVisible = function(m) return m:IsShown() and m:GetContentsHeight() > 0 end,
	trackerAlpha = function() return 1 end, questAlpha = function() return 1 end,
	InCombatLockdown = function() return combat end,
	hooksecurefunc = function(t, name, fn) hooks[#hooks + 1] = { t, name, fn } end,
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
	QuestObjectiveTracker = module,
}, { __index = _G })
_G.QuestObjectiveTracker = module
local pin = load(body .. "\nreturn pinQuestsHeader, unpinQuestsHeader", "pin", "t", env)()

local collapsed = 0
module.ToggleCollapsed = function(self) if self == module then collapsed = collapsed + 1 end end
local room = pin(module, 20)
check("on, quests first: the header's room (25 px) joins the strip", room == 25)
check("the header moved to the holder", header.parent ~= module and header.parent ~= nil and header.parent.name == "holder")
local holder = header.parent
check("the holder sits at the strip's old bottom, at the section's left", holder.points[1][2] == ghost
	and holder.points[1][4] == 10 and holder.points[1][5] == -20)
check("the header anchored to the holder, not its section", header.points[1][2] == holder)
-- R106-56: the collapse button calls self:GetParent():ToggleCollapsed() on the holder: passed on to the section
header:GetParent():ToggleCollapsed()
check("collapsing while pinned: the section collapses (no nil call)", collapsed == 1)
check("the holder's own frame methods are kept", holder.SetPoint ~= nil and holder.Show ~= nil)
check("/qt: its room reported for the divider", env.ns.api.questsHeaderPinnedPx() == 25)
-- Blizzard anchors the header to its section again while it is pinned
local hook
for _, h in ipairs(hooks) do if h[1] == header and h[2] == "SetPoint" then hook = h[3] end end
header:SetPoint("TOPLEFT", module, "TOPLEFT", 0, 0)
if hook then hook(header, "TOPLEFT", module, "TOPLEFT", 0, 0) end
check("Blizzard anchoring it to its section again: back on the holder", header.points[#header.points][2] == holder)
check("pinned again: the same room", pin(module, 20) == 25)
-- R106-54: the quest hanging on the header now hangs on the same place in its section, so it scrolls
local bp = block.points[#block.points]
check("the first quest re-anchored to its section where the header's bottom was (centre x 100, y -25-4)",
	bp[1] == "TOP" and bp[2] == module and bp[3] == "TOPLEFT" and bp[4] == 100 and bp[5] == -29)
local blockHook
for _, h in ipairs(hooks) do if h[1] == block and h[2] == "SetPoint" then blockHook = h[3] end end
block:SetPoint("TOP", header, "BOTTOM", 0, -6)
if blockHook then blockHook(block, "TOP", header, "BOTTOM", 0, -6) end
bp = block.points[#block.points]
check("Blizzard chaining it to the header again: on its section at once", bp[2] == module and bp[5] == -31)
-- another section first (a campaign quest above the quests)
check("another section first: back in its section, no room", pin(frame("campaign", 0, 0, 0), 20) == 0
	and header.parent == module and header.points[1][2] == module and not holder.shown)
bp = block.points[#block.points]
check("unpinned: the quest hangs on the header again, as Blizzard set it", bp[2] == header and bp[3] == "BOTTOM" and bp[5] == -6)
pin(module, 20)
db.pinQuestsHeader = false
check("switched off: back in its section, scrolls again", pin(module, 20) == 0 and header.parent == module)
db.pinQuestsHeader = true
combat = true
check("in combat: not pinned (refresh waits for the end)", pin(module, 20) == 0 and header.parent == module)
combat = false
local cfg = io.open(dir .. "/Tracker/Config.lua"):read("a")
check("the option in Quest list", cfg:find('check("Keep the \\"Quests\\" header at the top"', 1, true) ~= nil)
check("refresh adds the header's room to the strip", src:find("pinned = pinned + pinQuestsHeader(pickFollower(), pinned)", 1, true) ~= nil)
print(pass and "PASS" or "FAILED")
