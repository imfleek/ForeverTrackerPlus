-- 3.1.1: quest marks on EllesmereUI Bags' slots (Helpers.lua): its window EUI_Bags is built from the game's item slot
-- template; a slot's ID is the slot, its parent's ID the bag. The marks are painted after EUI_Bags:RefreshInventory.
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local hooks = {}
local function frame(kind)
	local f = { children = {}, id = 0, shown = true, kind = kind or "Frame" }
	function f:GetChildren() return unpack(self.children) end
	function f:GetID() return self.id end
	function f:SetID(v) self.id = v end
	function f:IsShown() return self.shown end
	function f:GetParent() return self.parent end
	function f:GetObjectType() return self.kind end
	function f:HookScript() end
	function f:CreateTexture()
		local t = { shown = false }
		function t:SetTexture() end
		function t:SetSize() end
		function t:SetPoint() end
		function t:SetShown(v) self.shown = v and true or false end
		function t:IsShown() return self.shown end
		return t
	end
	return f
end
local function add(parent, child) child.parent = parent; parent.children[#parent.children + 1] = child; return child end

-- EUI_Bags > grid > slotParent (bag 0) > item buttons (slots 1, 2)
local eui = frame()
eui.RefreshInventory = function() end
local grid = add(eui, frame())
local slotParent = add(grid, frame())
slotParent:SetID(0)
local b1 = add(slotParent, frame("ItemButton")); b1:SetID(1)
local b2 = add(slotParent, frame("ItemButton")); b2:SetID(2)
local items = { [0] = { [1] = 2589, [2] = 1234 } }

local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
	EUI_Bags = eui,
	hooksecurefunc = function(t, name, fn)
		if type(t) == "table" then local old = t[name]; t[name] = function(...) old(...); fn(...) end end
	end,
	C_Container = { GetContainerItemID = function(bag, slot) return items[bag] and items[bag][slot] end },
	C_Item = { GetItemNameByID = function(id) return id == 2589 and "Linen Cloth" or "Rock" end },
	C_QuestLog = { GetNumQuestLogEntries = function() return 1 end,
		GetInfo = function() return { title = "Cloth for the Tailor", isHeader = false } end },
	GetNumQuestLeaderBoards = function() return 1 end,
	GetQuestLogLeaderBoard = function() return "Linen Cloth: 3/10", "item", false end,
	C_Timer = { NewTicker = function() return {} end, After = function() end },
	UIParent = frame(), StaticPopupDialogs = {},
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do fn() end

eui:RefreshInventory()
check("EllesmereUI slot with a quest item: marked", b1.rxpftQuestMark ~= nil and b1.rxpftQuestMark.shown)
check("EllesmereUI slot without one: not marked", not (b2.rxpftQuestMark and b2.rxpftQuestMark.shown))
items[0][1], items[0][2] = 1234, 2589
eui:RefreshInventory()
check("after a re-sort the mark follows the item", not b1.rxpftQuestMark.shown and b2.rxpftQuestMark and b2.rxpftQuestMark.shown)
ns.db.bagMarks = false
eui:RefreshInventory()
check("switch off: no marks", not b2.rxpftQuestMark.shown)

-- a slot the game reports as a plain Button (an icon, no item button methods): still found
ns.db.bagMarks = true
local b3 = add(slotParent, frame("Button")); b3:SetID(3); b3.icon = {}
items[0][3] = 2589
eui:RefreshInventory()
check("a plain Button slot with an icon: marked", b3.rxpftQuestMark ~= nil and b3.rxpftQuestMark.shown)
local lines = {}
ns.api.bagReport(function(t) lines[#lines + 1] = t end)
local all = table.concat(lines, " | ")
check("/qt bags: names the needed item", all:find("Linen Cloth", 1, true) ~= nil)
check("/qt bags: counts EllesmereUI's slots and marks", all:find("EUI_Bags: open, hooked yes, slots found 3, with an item 3, marked 2", 1, true) ~= nil or print(all))

print(pass and "ALL OK" or "SOME FAILED")
