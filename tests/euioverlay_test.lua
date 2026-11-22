-- 3.1.1: EllesmereUI Bags' overlay hook (EUI_Bags.RegisterItemOverlayIcon, as Peddler uses): our painter is called per
-- slot with its bag and slot; the mark goes on the slot's text layer, above EllesmereUI's slot art (Helpers.lua)
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function tex()
	local t = { shown = false }
	function t:SetTexture() end; function t:SetSize() end; function t:SetPoint() end
	function t:SetShown(v) self.shown = v and true or false end
	function t:IsShown() return self.shown end
	return t
end
local function layer() local l = { textures = {} }; function l:CreateTexture() local t = tex(); self.textures[#self.textures + 1] = t; return t end; return l end
local painters, refreshes = {}, 0
local eui = { visible = true }
function eui.RegisterItemOverlayIcon(name, fn) painters[name] = fn end
function eui:IsVisible() return self.visible end
function eui:IsShown() return self.visible end
local slots = { { bag = 0, slot = 1 }, { bag = 0, slot = 2 } }
local items = { [0] = { [1] = 2589, [2] = 1234 } }
local buttons = { { _textOverlay = layer() }, { _textOverlay = layer() } }
function eui:RefreshInventory()
	refreshes = refreshes + 1
	for i, b in ipairs(buttons) do for _, fn in pairs(painters) do fn(b, slots[i]) end end
end
local objective = "Linen Cloth: 3/10"
local questsInLog = 1
local ns = { api = {}, onLogin = {}, db = {} }
local env = setmetatable({
	CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
	EUI_Bags = eui,
	hooksecurefunc = function() end,
	C_Container = { GetContainerItemID = function(bag, slot) return items[bag] and items[bag][slot] end },
	C_Item = { GetItemNameByID = function(id) return id == 2589 and "Linen Cloth" or "Rock" end },
	C_QuestLog = { GetNumQuestLogEntries = function() return questsInLog end,
		GetInfo = function() return { title = "Cloth for the Tailor", isHeader = false } end },
	GetNumQuestLeaderBoards = function() return 1 end,
	GetQuestLogLeaderBoard = function() return objective, "item", objective:find("10/10", 1, true) ~= nil end,
	C_Timer = { NewTicker = function() return {} end, After = function(_, f) f() end },
	UIParent = {}, StaticPopupDialogs = {},
}, { __index = _G })
env._G = env
assert(loadfile(dir .. "/Tracker/Helpers.lua", "t", env))("RXPForeverTracker", { tracker = ns })
for _, fn in ipairs(ns.onLogin) do pcall(fn) end

check("registered with EllesmereUI's overlay hook", painters.RXPForeverTracker ~= nil)
check("open bags redrawn once at registration", refreshes >= 1)
local m1 = buttons[1]._textOverlay.textures[1]
check("quest item: mark on the slot's text layer, shown", m1 and m1.shown)
check("other item: no mark", #buttons[2]._textOverlay.textures == 0)
items[0][1], items[0][2] = 1234, 2589
eui:RefreshInventory()
check("after a re-sort the mark follows the item", not m1.shown and buttons[2]._textOverlay.textures[1].shown)
-- the objective is finished (10/10): the items are still needed to turn the quest in, so the mark stays
objective = "Linen Cloth: 10/10"
local before = refreshes
ns.api.repaintBagMarks()
check("finished objective: nothing changed, no redraw", refreshes == before)
eui:RefreshInventory(); before = refreshes
check("finished objective: mark stays until the quest is turned in", buttons[2]._textOverlay.textures[1].shown)
-- turned in: the quest leaves the log, the next repaint asks EllesmereUI to redraw, and the mark goes
questsInLog = 0
ns.api.repaintBagMarks()
check("needed items changed: EllesmereUI redraws", refreshes == before + 1)
check("quest turned in: mark gone", not buttons[2]._textOverlay.textures[1].shown)
ns.api.repaintBagMarks()
check("nothing changed: no extra redraw", refreshes == before + 1)
local lines = {}
ns.api.bagReport(function(t) lines[#lines + 1] = t end)
check("/qt bags says it draws through the overlay hook", table.concat(lines, " | "):find("overlay hook", 1, true) ~= nil)

print(pass and "ALL OK" or "SOME FAILED")
