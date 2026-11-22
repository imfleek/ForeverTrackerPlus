-- Font choice (Settings window > Font): one font for the quest tracker, the RestedXP Tracker (guide) and the settings
-- window. "Game default" leaves every font as the game and RestedXP set it.
--
-- The quest tracker draws with Blizzard's shared font objects; their font file is replaced and their size and
-- outline kept, and the originals are restored for "Game default". The guide reads api.fontPath() through
-- ns.textStyle (Objectives/rxp/Readers.lua), the settings window through applyFonts (Config.lua), zone headers
-- through styleLabel (ZoneSort.lua).
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

-- Blizzard's quest tracker font objects (only those this client has are touched)
local OBJECTS = { "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont", "ObjectiveFont", "ObjectiveTrackerFont12",
	"ObjectiveTrackerFont13", "ObjectiveTrackerFont14", "ObjectiveTrackerFont15", "ObjectiveTrackerFont16",
	"ObjectiveTrackerFont17", "ObjectiveTrackerFont18", "ObjectiveTrackerFont19", "ObjectiveTrackerFont20" }

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

local originals = {}
local function applyTrackerFont()
	local path = api.fontPath()
	for _, name in ipairs(OBJECTS) do
		local object = _G[name]
		if object and object.GetFont and object.SetFont then
			local file, size, flags = object:GetFont()
			if file and size then
				if not originals[name] then originals[name] = file end
				local want = path or originals[name]
				if file ~= want then pcall(object.SetFont, object, want, size, flags or "") end
			end
		end
	end
end

-- CONSTRAINT: on Forever the quest titles and objective lines are not drawn with the font objects above (user report,
-- 2.6.1: only the Quests header, zone headers and the guide changed). A shared object they might use (GameFont...)
-- would restyle the whole game, so the chosen font is set on the tracker's own text instead: section headers, quest
-- titles, objective lines and dashes, after every tracker update (Blizzard may reset text it reuses). Each text's
-- original font is remembered for "Game default"; sizes and outlines are kept.
local original = setmetatable({}, { __mode = "k" }) -- the font the game gave each text
local ours = setmetatable({}, { __mode = "k" })     -- the font we last put on it (nil: none)
-- R106-48: Quest titles > "Outline titles" (db.titleOutline), Objectives > "Outline objectives" (db.objectiveOutline):
-- "OUTLINE" added to the text's own flags, kept like the font (at once when Blizzard sets its own); off: the game's.
local originalFlags = setmetatable({}, { __mode = "k" }) -- the flags the game gave each text
local oursFlags = setmetatable({}, { __mode = "k" })     -- the flags we last put on it
local kindOf = setmetatable({}, { __mode = "k" })        -- "title" or "line" (objective text and its dash)
local function outlined(kind)
	local db = ns.db
	if not db then return false end
	return (kind == "title" and db.titleOutline) or (kind == "line" and db.objectiveOutline) or false
end
-- anything to do on tracker text: a font chosen, an outline on, or something of ours to put back
local function fontActive()
	local db = ns.db
	return api.fontPath() ~= nil or (db and (db.titleOutline or db.objectiveOutline)) or next(original) ~= nil
		or next(originalFlags) ~= nil
end
api.trackerFontActive = function() return fontActive() and true or false end
local function withOutline(flags, on)
	flags = flags or ""
	if not on or flags:find("OUTLINE", 1, true) then return flags end
	return flags == "" and "OUTLINE" or (flags .. ",OUTLINE")
end
local keepFont -- below
local function applyTo(fs, path, kind)
	if not (fs and fs.GetFont and fs.SetFont) then return false end
	if kind then kindOf[fs] = kind end
	kind = kindOf[fs]
	if keepFont and (path or outlined(kind)) then keepFont(fs) end -- from now on kept at once (R106-43)
	local file, size, flags = fs:GetFont()
	if not (file and size) then return false end
	flags = flags or ""
	-- anything but our own font was set by the game (first time, or Blizzard reset reused text): that is the original
	if ours[fs] == nil or file ~= ours[fs] then original[fs] = file end
	if oursFlags[fs] == nil or flags ~= oursFlags[fs] then originalFlags[fs] = flags end
	local want = path or original[fs]
	local wantFlags = withOutline(originalFlags[fs], outlined(kind))
	ours[fs] = path
	oursFlags[fs] = wantFlags ~= originalFlags[fs] and wantFlags or nil
	if file == want and flags == wantFlags then return false end
	pcall(fs.SetFont, fs, want, size, wantFlags)
	return true
end

-- R106-43: a tracker text keeps the chosen font the moment Blizzard sets its own (SetFontObject / SetFont when a block
-- or line is reused), not on the next frame: the game's font showed for a frame on every tracker update, and the
-- text, its wrap and the bars changed size back and forth (user: "it's fighting for what font to use"). Hooked once
-- per text (titles and objective lines: Extras.lua's hooks; the rest: applyBlockFonts).
local fontHooked = setmetatable({}, { __mode = "k" })
local keeping = false
function keepFont(fs, kind)
	if not (fs and fs.GetFont and fs.SetFont) then return end
	if kind then kindOf[fs] = kind end
	if fontHooked[fs] then return end
	fontHooked[fs] = true
	local function again(self)
		if keeping then return end
		if not fontActive() then return end -- the game's font and flags, never changed: nothing to do
		keeping = true
		pcall(applyTo, self, api.fontPath())
		keeping = false
	end
	for _, method in ipairs({ "SetFontObject", "SetFont" }) do
		if type(fs[method]) == "function" then hooksecurefunc(fs, method, again) end
	end
	again(fs)
end
api.keepTrackerFont = keepFont

function api.applyBlockFonts()
	local tracker = ObjectiveTrackerFrame
	if not tracker then return false end
	local path = api.fontPath()
	if not fontActive() then return false end -- never changed anything: nothing to restore
	local changed = false
	for _, module in ipairs(tracker.modules or {}) do
		if module.Header and applyTo(module.Header.Text, path) then changed = true end
		for _, byId in pairs(type(module.usedBlocks) == "table" and module.usedBlocks or {}) do
			for _, block in pairs(type(byId) == "table" and byId or {}) do
				if type(block) == "table" then
					if applyTo(block.HeaderText, path, "title") then changed = true end
					for _, line in pairs(type(block.usedLines) == "table" and block.usedLines or {}) do
						if type(line) == "table" then
							if applyTo(line.Text, path, "line") then changed = true end
							if applyTo(line.Dash, path, "line") then changed = true end
						end
					end
				end
			end
		end
	end
	if tracker.Header and applyTo(tracker.Header.Text, path) then changed = true end
	return changed
end

-- after Blizzard lays the tracker out: new or reused text gets the font; heights are measured again when it changed
local reapplying, lastRelayout = false, 0
local afterUpdateSoon -- below
local function afterUpdate()
	if reapplying then return end
	if api.applyBlockFonts() and GetTime() - lastRelayout > 1 then -- at most once a second, should Blizzard reset text every update
		lastRelayout = GetTime()
		reapplying = true
		local tracker = ObjectiveTrackerFrame
		if tracker and tracker.MarkDirty then pcall(securecallfunction, tracker.MarkDirty, tracker) end
		reapplying = false
	end
end
api.afterTrackerUpdateFonts = afterUpdate
-- once on the next frame however often the tracker updates in this one (and nothing at all with the game's font)
local soon = false
local function afterUpdateFired() soon = false; afterUpdate() end
function afterUpdateSoon()
	if soon or not fontActive() then return end
	soon = true
	C_Timer.After(0, afterUpdateFired)
end

-- Apply the choice everywhere: tracker, guide, zone headers, More quests, settings window.
function api.applyFont()
	applyTrackerFont()
	afterUpdate()
	local relayout = root.objectives.relayout
	if relayout then pcall(relayout) end
	if root.objectives.invalidateText then pcall(root.objectives.invalidateText) end
	if api.applyZoneHeaders then api.applyZoneHeaders() end
	if api.rebuildMoreQuests then api.rebuildMoreQuests() end
	if api.applyConfigFonts then api.applyConfigFonts() end
	local tracker = ObjectiveTrackerFrame
	if tracker and tracker.MarkDirty then pcall(securecallfunction, tracker.MarkDirty, tracker) end
	if api.applyLayout then api.applyLayout() end
end

function api.setFont(key)
	ns.db.font = key or "default"
	api.applyFont()
end

ns.onLogin[#ns.onLogin + 1] = function()
	if api.fontPath() then applyTrackerFont() end
	local tracker = ObjectiveTrackerFrame
	if tracker and type(tracker.Update) == "function" then
		hooksecurefunc(tracker, "Update", afterUpdateSoon)
	elseif ObjectiveTrackerContainerMixin and ObjectiveTrackerContainerMixin.Update then
		hooksecurefunc(ObjectiveTrackerContainerMixin, "Update", afterUpdateSoon)
	end
	C_Timer.After(1, afterUpdate)
	-- Blizzard re-applies its text size to the font objects when the tracker's text size changes
	if ObjectiveTrackerManager and ObjectiveTrackerManager.SetTextSize then
		hooksecurefunc(ObjectiveTrackerManager, "SetTextSize", function() if api.fontPath() then applyTrackerFont() end end)
	end
end

-- /qt fontlog (R106-44): for 10 s, every font change on the quest tracker's text and the code that made it, then a
-- summary in chat (user: the tracker's text "fights for what font to use" with the world map open; the video showed
-- titles, lines, the yards and the bar counts switching between two looks several times a second). Records:
-- SetFont / SetFontObject on the quest titles and objective lines shown, SetFont on Blizzard's tracker font objects,
-- ObjectiveTrackerManager:SetTextSize, and (sampled every 0.05 s) a font that changed with no call seen.
local logging, logStart = false, 0
local logCounts, logOrder = {}, {}
local logHooked = setmetatable({}, { __mode = "k" })
local function shortFont(file, size, flags)
	file = type(file) == "string" and (file:match("([^\\/]+)$") or file) or tostring(file)
	return ("%s %s %s"):format(file, type(size) == "number" and ("%g"):format(math.floor(size * 10 + 0.5) / 10) or "?",
		(flags and flags ~= "") and flags or "-")
end
local function caller()
	local stack = debugstack and debugstack(2, 12, 0) or ""
	for line in stack:gmatch("[^\n]+") do
		if not line:find("Fonts.lua", 1, true) and not line:find("^%[C%]") and not line:find("[C]:", 1, true)
			and not line:find("hooksecurefunc", 1, true) then
			local where = line:match("AddOns[\\/](.-:%d+)") or line:match("Interface[\\/](.-:%d+)") or line:match("^(.-:%d+)")
			if where then return where end
		end
	end
	return "unknown"
end
local function note(what, fs)
	if not logging then return end
	if GetTime() - logStart > 10 then return end
	local result = fs and fs.GetFont and shortFont(fs:GetFont()) or ""
	local key = what .. " | " .. caller() .. " | " .. result
	if not logCounts[key] then logCounts[key] = 0; logOrder[#logOrder + 1] = key end
	logCounts[key] = logCounts[key] + 1
end
local function logHook(fs, kind)
	if not fs or logHooked[fs] then return end
	logHooked[fs] = true
	for _, method in ipairs({ "SetFont", "SetFontObject" }) do
		if type(fs[method]) == "function" then
			hooksecurefunc(fs, method, function(self) note(kind .. ":" .. method, self) end)
		end
	end
end
local sampled = {}
local sampler -- made on the first /qt fontlog
local sinceSample = 0
local function samples()
	local list = {}
	local module = _G.QuestObjectiveTracker
	for _, byId in pairs(module and type(module.usedBlocks) == "table" and module.usedBlocks or {}) do
		for _, block in pairs(type(byId) == "table" and byId or {}) do
			if type(block) == "table" and block.HeaderText then
				list[#list + 1] = { "title", block.HeaderText }
				for _, line in pairs(type(block.usedLines) == "table" and block.usedLines or {}) do
					if type(line) == "table" and line.Text then list[#list + 1] = { "line", line.Text } end
				end
			end
		end
	end
	return list
end
local function onSample(_, elapsed)
	if not logging then return end
	if GetTime() - logStart > 10 then
		logging = false
		local say = ns.say or print
		say(("fontlog: %d different font changes in 10 s (count | what | code | font after):"):format(#logOrder))
		table.sort(logOrder, function(a, b) return logCounts[a] > logCounts[b] end)
		for i, key in ipairs(logOrder) do
			if i > 15 then say(("  ... %d more"):format(#logOrder - 15)) break end
			say(("  %dx %s"):format(logCounts[key], key))
		end
		if #logOrder == 0 then say("  none: the font never changed") end
		say(("font chosen: %s"):format(tostring(api.fontPath() or "Game default")))
		return
	end
	sinceSample = sinceSample + elapsed
	if sinceSample < 0.05 then return end
	sinceSample = 0
	for _, entry in ipairs(samples()) do
		local fs = entry[2]
		logHook(fs, entry[1])
		local now = shortFont(fs:GetFont())
		if sampled[fs] and sampled[fs] ~= now then
			local key = entry[1] .. ": changed with no call seen | " .. sampled[fs] .. " -> " .. now
			if not logCounts[key] then logCounts[key] = 0; logOrder[#logOrder + 1] = key end
			logCounts[key] = logCounts[key] + 1
		end
		sampled[fs] = now
	end
end
local objectsHooked = false
function api.fontLog(say)
	if not sampler then
		sampler = CreateFrame("Frame")
		sampler:SetScript("OnUpdate", onSample)
	end
	if not objectsHooked then
		objectsHooked = true
		for _, name in ipairs(OBJECTS) do
			local object = _G[name]
			if object and object.SetFont then
				hooksecurefunc(object, "SetFont", function(self) note("font object " .. name .. ":SetFont", self) end)
			end
		end
		if ObjectiveTrackerManager and ObjectiveTrackerManager.SetTextSize then
			hooksecurefunc(ObjectiveTrackerManager, "SetTextSize", function() note("ObjectiveTrackerManager:SetTextSize") end)
		end
	end
	wipe(logCounts); wipe(logOrder); wipe(sampled)
	for _, entry in ipairs(samples()) do logHook(entry[2], entry[1]) end
	logStart, logging = GetTime(), true
	say("fontlog: recording for 10 s. Open the world map now (and close it again). The result comes in chat.")
end
