-- 3.2 (user: "This addon should always show character surnames"): api.playerName and api.playerKey (Tracker/Core.lua)
local root = arg[1] or ".."
local fails = 0
local function check(name, ok) print((ok and "ok   " or "FAIL ") .. name); if not ok then fails = fails + 1 end end
local src = assert(io.open(root .. "/Tracker/Core.lua")):read("a")
local block = src:match("(\ndo\n\tlocal function secret.-\nend\n)")
check("helper block found", block ~= nil)
local first, last, realm = "Kat", "Lo", "Realm"
local env = setmetatable({ ns = { api = {} }, pcall = pcall, type = type,
	UnitName = function() return first, last end, GetRealmName = function() return realm end }, { __index = _G })
assert(load(block, "core", "t", env))()
local api = env.ns.api
check("full name with the surname", api.playerName() == "Kat Lo")
local saved = { ["Kat-Realm"] = { class = "MAGE" }, ["Kat-Realm (previous)"] = { x = 1 } }
check("key has the surname", api.playerKey(saved) == "Kat Lo-Realm")
check("old first-name entry moved", saved["Kat Lo-Realm"] and saved["Kat Lo-Realm"].class == "MAGE" and saved["Kat-Realm"] == nil)
check("old previous run moved too", saved["Kat Lo-Realm (previous)"] and saved["Kat-Realm (previous)"] == nil)
local s2 = { ["Kat-Realm"] = { class = "ROGUE" } }
api.playerKey(s2, function(o) return o.class == "MAGE" end)
check("another class keeps its old entry", s2["Kat-Realm"] ~= nil and s2["Kat Lo-Realm"] == nil)
last = realm
check("a realm as second value is not a surname", api.playerName() == "Kat")
last = nil
check("no second value: first name", api.playerName() == "Kat" and api.playerKey() == "Kat-Realm")
if fails > 0 then print("SOME FAILED") else print("ALL OK") end
