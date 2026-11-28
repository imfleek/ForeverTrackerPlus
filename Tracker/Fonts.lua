-- Font choice (Settings window > Font): one font for our tracker, the RestedXP Tracker (guide) and the settings
-- window. "Game default" leaves every font as the game and RestedXP set it.
--
-- Our tracker reads api.fontPath() through its own font objects (Tracker/Own/Look.lua), the guide through
-- ns.textStyle (Objectives/rxp/Readers.lua), the settings window through applyFonts (Config.lua).
-- 3.2 (user: "Delete the old tracker's code"): Blizzard's tracker fonts are no longer changed.
local ADDON, root = ...; local ns = root.tracker
if ns.disabled then return end
local api = ns.api

local BUILT_IN = {
	{ "default", "Game default" },
	{ "friz", "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ "arial", "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ "morpheus", "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ "skurri", "Skurri", path = "Fonts\\SKURRI.TTF" },
}


-- The choices: the built-in ones, then LibSharedMedia's fonts when that library is loaded (by another addon).
function api.fontOptions()
	local list = {}
	for _, f in ipairs(BUILT_IN) do list[#list + 1] = { f[1], f[2], path = f.path } end
	local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
	if lsm and lsm.HashTable then
		local ok, fonts = pcall(lsm.HashTable, lsm, "font")
		if ok and type(fonts) == "table" then
			local names = {}
			for name, path in pairs(fonts) do
				if type(name) == "string" and type(path) == "string" then names[#names + 1] = name end
			end
			table.sort(names)
			local known = {}
			for _, f in ipairs(BUILT_IN) do if f.path then known[f.path:lower()] = true end end
			for _, name in ipairs(names) do
				local path = fonts[name]
				if not known[path:lower()] then list[#list + 1] = { "lsm:" .. name, name, path = path } end
			end
		end
	end
	return list
end

-- The chosen font file, or nil for "Game default".
function api.fontPath()
	local key = ns.db and ns.db.font
	if not key or key == "default" then return nil end
	for _, option in ipairs(api.fontOptions()) do
		if option[1] == key then return option.path end
	end
	return nil
end


-- Apply the choice everywhere: our tracker, the guide, the settings window.
function api.applyFont()
	local relayout = root.objectives.relayout
	if relayout then pcall(relayout) end
	if root.objectives.invalidateText then pcall(root.objectives.invalidateText) end
	if api.applyZoneHeaders then api.applyZoneHeaders() end
	if api.refreshQuests then api.refreshQuests() end
	if api.applyConfigFonts then api.applyConfigFonts() end
	if api.applyLayout then api.applyLayout() end
end

function api.setFont(key)
	ns.db.font = key or "default"
	api.applyFont()
end
