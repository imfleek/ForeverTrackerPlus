-- 3.2 (user): the LayerSwap button on the Quests header (Tracker/LayerSwapButton.lua).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local function frame(name)
	local f = { name = name, shown = false, scripts = {}, points = {} }
	local methods = {
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end, SetShown = function(self, v) self.shown = v and true or false end,
		SetScript = function(self, k, fn) self.scripts[k] = fn end, GetScript = function(self, k) return self.scripts[k] end,
		CreateTexture = function() return frame("tex") end, CreateFontString = function() return frame("text") end,
		SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
		ClearAllPoints = function(self) self.points = {} end,
		GetFrameLevel = function() return 5 end, IsMouseOver = function() return false end,
		SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
		IsEnabled = function(self) return self.enabled end,
	}
	return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

local swapped, loadedLS, made = 0, true, nil
local api = {}
local slashes = {}
api.addSlash = function(name, _, fn) slashes[name] = fn end
local ns = { api = api, onLogin = {}, db = {} }
local header = frame("header"); header.text = frame("Quests"); header.count = frame("count")
api.ownQuestsHeaderFrame = function() return header end
local env = setmetatable({
	CreateFrame = function(_, name) local f = frame(name); made = f; return f end,
	C_AddOns = { IsAddOnLoaded = function(n) return n == "LayerSwap" and loadedLS end },
	C_Timer = { After = function() end },
	GameTooltip = setmetatable({ lines = {} }, { __index = function(t, k)
		if k == "AddLine" then return function(self, s) self.lines[#self.lines + 1] = s end end
		return function() end end }),
}, { __index = _G })
env._G = env
env.LayerSwap_SwapKey = function() swapped = swapped + 1 end
assert(loadfile(dir .. "/Tracker/LayerSwapButton.lua", "t", env))("ForeverTrackerPlus", { tracker = ns })

ns.onLogin[1]()
check("made on login and shown", made and made.shown)
check("right of \"Quests\"", made and made.points[1] and made.points[1][1] == "LEFT" and made.points[1][2] == header.text
	and made.points[1][3] == "RIGHT")
made.scripts.OnEnter(made)
check("tooltip: LayerSwap and Click: Swap layer", env.GameTooltip.lines[1] == "LayerSwap" and env.GameTooltip.lines[2] == "Click: Swap layer")
made.scripts.OnClick(made)
check("clicking the button calls LayerSwap_SwapKey", swapped == 1)
local placed = api.layerSwapLoaded()
check("LayerSwap loaded: yes", placed == true)
api.layerSwapClick()
check("api.layerSwapClick calls it too", swapped == 2)
env.LayerSwapPanel = { swapButton = frame("swap") }
env.LayerSwapPanel.swapButton.text, env.LayerSwapPanel.swapButton.enabled = "Wait 0:30", false
local text, on = api.layerSwapState()
check("the state is LayerSwap's button text", text == "Wait 0:30" and on == false)
local alpha
made.icon.SetAlpha = function(_, a) alpha = a end
made.scripts.OnUpdate(made, 0.6)
check("LayerSwap's button off: our icon goes grey", made.off == true and alpha == 0.5)
env.LayerSwapPanel.swapButton.enabled = true
made.scripts.OnUpdate(made, 0.2)
check("read only twice a second", made.off == true)
made.scripts.OnUpdate(made, 0.4)
check("LayerSwap's button on again: full colour", made.off == false and alpha == 1)
-- a click while blocked waits; the sign comes when LayerSwap's button is on; then a click swaps
local said, sounds = {}, 0
env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) said[#said + 1] = s end }
env.PlaySound, env.SOUNDKIT = function() sounds = sounds + 1 end, { READY_CHECK = 8960 }
env.GetTime = function() return 1000 end
env.LayerSwapPanel.swapButton.enabled = false
made.scripts.OnUpdate(made, 0.6)
local before = swapped
made.scripts.OnClick(made)
check("blocked: a click waits and does not swap", rawget(made, "waiting") == 1000 and swapped == before and said[1]:find("blocked", 1, true))
env.LayerSwapPanel.swapButton.enabled = true
made.scripts.OnUpdate(made, 0.6)
check("ready: glow, sound and a chat line", rawget(made, "ready") and made.glow.shown == true and sounds == 1 and said[2]:find("ready", 1, true)
	and not rawget(made, "waiting"))
made.scripts.OnClick(made)
check("a click when ready swaps and stops the glow", swapped == before + 1 and not rawget(made, "ready") and not made.glow.shown == true)
env.LayerSwapPanel.swapButton.enabled = false
made.scripts.OnUpdate(made, 0.6)
made.scripts.OnClick(made); made.scripts.OnClick(made)
check("a second click stops the waiting", rawget(made, "waiting") == nil and said[#said]:find("no longer", 1, true))
made.scripts.OnClick(made)
env.GetTime = function() return 1000 + 16 * 60 end
made.scripts.OnUpdate(made, 0.6)
check("a wait is dropped after 15 minutes", rawget(made, "waiting") == nil)
env.LayerSwapPanel.swapButton.enabled = true
made.scripts.OnUpdate(made, 0.6)
check("a dropped wait gives no sign", not rawget(made, "ready") and sounds == 1)
-- LayerSwap's mini bar text right of the icon
local function fs(t) local f = frame("fs"); f.text = t; return f end
env.LayerSwapMini = { text = fs("Arathi Basin"), status = fs("|cff999999No layers here|r") }
made.scripts.OnUpdate(made, 0.6)
check("mini bar text: its two lines on top of each other (user)", made.label.text == "Arathi Basin"
	and made.label2.text == "|cff999999No layers here|r" and made.label2.shown)
check("the top line above the icon's middle, the bottom one below", made.label.points[1][1] == "BOTTOMLEFT"
	and made.label.points[1][2] == made and made.label2.points[1][1] == "TOPLEFT")
-- both edges pinned at one height: a BOTTOMLEFT with a RIGHT gave the line no height in game (user: no text)
local function sameHeight(fs)
	local a, b = fs.points[1] and fs.points[1][1], fs.points[2] and fs.points[2][1]
	local function v(pt) return pt and (pt:find("TOP") and "top" or pt:find("BOTTOM") and "bottom" or "mid") end
	return a ~= nil and (b == nil or v(a) == v(b))
end
check("the lines' left and right edges at one height", sameHeight(made.label) and sameHeight(made.label2))
env.LayerSwapMini = { text = fs("Layer C   Next swap 4:10"), status = fs("") }
made.scripts.OnUpdate(made, 0.6)
check("one-line mini bar: its line, centred on the icon", made.label.text == "Layer C   Next swap 4:10"
	and made.label.points[1][1] == "LEFT" and not made.label2.shown)
ns.db.layerSwapText = false
made.scripts.OnUpdate(made, 0.6)
check("LayerSwap text switched off: empty", made.label.text == "")
ns.db.layerSwapText = nil
env.LayerSwapMini = nil
made.scripts.OnUpdate(made, 0.6)
check("no mini bar: empty", made.label.text == "")
-- the mini bar on: made invisible and click-through; back as LayerSwap draws it when the option is off
local mini = frame("mini"); mini.logo = frame("logo")
local alphaM, mouse = nil, {}
mini.SetAlpha = function(_, a) alphaM = a end
mini.EnableMouse = function(_, on) mouse.bar = on end
mini.logo.EnableMouse = function(_, on) mouse.logo = on end
mini.text, mini.status = fs("Darkspear Islands"), fs("No layers here")
env.LayerSwapMini = mini
made.scripts.OnUpdate(made, 0.6)
check("mini bar on: it is invisible and the mouse passes through", alphaM == 0 and mouse.bar == false and mouse.logo == false)
check("its text shows in our header", made.label.text == "Darkspear Islands" and made.label2.text == "No layers here")
ns.db.layerSwapHideMini = false
made.scripts.OnUpdate(made, 0.6)
check("option off: the mini bar as LayerSwap draws it", alphaM == 1 and mouse.bar == true and mouse.logo == true)
ns.db.layerSwapHideMini = nil
made.scripts.OnUpdate(made, 0.6)
ns.db.layerSwapButton = false
api.applyLayerSwapButton()
check("our button off: the mini bar comes back", alphaM == 1 and mouse.bar == true)
-- the mini bar off while our dial is on: turned on through /ls mini, once
local minis = 0
mini.shown = false
env.SlashCmdList = { LAYERSWAP = function(msg) if msg == "mini" then minis = minis + 1; mini.shown = not mini.shown end end }
ns.db.layerSwapButton = nil
api.applyLayerSwapButton()
made.scripts.OnUpdate(made, 0.6)
made.scripts.OnUpdate(made, 0.6)
check("dial on, mini bar off: /ls mini turns it on, once", minis == 1 and mini.shown == true)
ns.db.layerSwapButton = false
api.applyLayerSwapButton()
mini.shown = false
api.layerSwapEnsureMini()
check("dial off: the mini bar is left as it is", minis == 1 and mini.shown == false)
env.SlashCmdList = nil
ns.db.layerSwapButton = nil
env.LayerSwapMini = nil
api.applyLayerSwapButton()
made.scripts.OnUpdate(made, 0.6)
-- a secret text (a battleground's name can be one): shown as it is, not dropped
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
env.issecretvalue = function(v) return v == SECRET end
env.LayerSwapMini = { text = fs(SECRET), status = fs("No layers here") }
env.LayerSwapMini.text.GetText = function() return SECRET end
made.scripts.OnUpdate(made, 0.6)
check("a secret name line is still shown", made.label.text == SECRET and made.label2.text == "No layers here" and made.label2.shown)
local out = {}
slashes.layerswap(nil, function(t) out[#out + 1] = t end)
local all = table.concat(out, "\n")
check("/ftp layerswap: says what it reads and shows", all:find("mini bar: yes", 1, true) and all:find("secret", 1, true)
	and all:find("line 2: \"No layers here\"", 1, true))
env.issecretvalue, env.LayerSwapMini = nil, nil
made.scripts.OnUpdate(made, 0.6)
-- Host: its state in the tooltip, a right-click turns it on or off through /ls on and /ls off
local sent
env.LayerSwapDB = {}
env.SlashCmdList = { LAYERSWAP = function(msg) sent = msg; env.LayerSwapDB.hosting = (msg == "on") end }
check("Host: nil in LayerSwap's save means on", api.layerSwapHosting() == true)
env.GameTooltip.lines = {}
made.scripts.OnEnter(made)
local hostLine
for _, l in ipairs(env.GameTooltip.lines) do if l:find("Host:", 1, true) then hostLine = l end end
check("tooltip: Host on", hostLine and hostLine:find("on", 1, true))
local swapsBefore = swapped
made.scripts.OnClick(made, "RightButton")
check("right-click: /ls off, Host off, no swap", sent == "off" and api.layerSwapHosting() == false and swapped == swapsBefore)
made.scripts.OnClick(made, "RightButton")
check("right-click again: /ls on", sent == "on" and api.layerSwapHosting() == true)
env.LayerSwapDB, env.SlashCmdList = nil, nil
check("no LayerSwap save: no Host state, right-click does nothing", api.layerSwapHosting() == nil and api.layerSwapHostToggle() == false)
env.LayerSwap_SwapKey = function() error("boom") end
local errs = 0
env.geterrorhandler = function() return function() errs = errs + 1 end end
api.layerSwapClick()
check("an error in LayerSwap is reported, not thrown", errs == 1)
env.LayerSwap_SwapKey = nil
check("no LayerSwap: not loaded", api.layerSwapLoaded() == false)
check("no LayerSwap: the button hides", api.applyLayerSwapButton() == true and not made.shown)
env.LayerSwap_SwapKey = function() swapped = swapped + 1 end
ns.db.layerSwapButton = false
check("switched off: the button hides", api.applyLayerSwapButton() == true and not made.shown)
ns.db.layerSwapButton = nil
check("switched on again: it shows", api.applyLayerSwapButton() == true and made.shown)

print(pass and "ALL OK" or "SOME FAILED")
