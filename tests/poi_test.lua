-- R106-46: Blizzard's quest POI buttons always hidden: alpha 0, no mouse, fade-in muted; never :Hide()
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local body = src:match("(local poiMuted = .-\napi%.hidePOI = hidePOI\n)")
check("the POI code found", body ~= nil)
local timers, hooks = {}, {}
local env = setmetatable({ api = {}, ns = {}, C_Timer = { After = function(d, f) timers[#timers + 1] = f end },
	hooksecurefunc = function(t, name, fn) hooks[#hooks + 1] = { t, name, fn } end }, { __index = _G })
load(body, "poi", "t", env)()
local hid = 0
local function button()
	local alphaAnim = { GetObjectType = function() return "Alpha" end, SetToAlpha = function(self, a) self.to = a end }
	local b = { alpha = 1, mouse = true, AddAnim = { GetAnimations = function() return alphaAnim end }, anim = alphaAnim }
	b.SetAlpha = function(self, a) self.alpha = a end
	b.GetAlpha = function(self) return self.alpha end
	b.IsMouseEnabled = function(self) return self.mouse end
	b.EnableMouse = function(self, on) self.mouse = on end
	b.Hide = function() hid = hid + 1 end
	return b
end
local b1 = button()
local block = { poiButton = b1, GetPOIButton = function() end }
env.api.hidePOI(block)
check("shown button: see-through and not clickable", b1.alpha == 0 and b1.mouse == false)
check("its fade-in ends see-through", b1.anim.to == 0)
check("never :Hide() (taint)", hid == 0)
check("the block's GetPOIButton is hooked", #hooks == 1 and hooks[1][1] == block and hooks[1][2] == "GetPOIButton")
local b2 = button()
block.poiButton = b2
hooks[1][3](block) -- Blizzard gives the block a new button
check("a new button taken in the layout: hidden at once", b2.alpha == 0 and b2.mouse == false)
env.api.hidePOI(block)
check("hooked once per block", #hooks == 1)
b2.alpha = 1 -- the fade-in ran anyway
for _, f in ipairs(timers) do f() end
check("set again 0.35 s later", b2.alpha == 0)
local qr = io.open(dir .. "/Objectives/features/QuestReady.lua"):read("a")
check("QuestReady no longer calls :Hide() on the POI button", not qr:find("button:Hide()", 1, true))
print(pass and "PASS" or "FAILED")
