-- ForeverTrackerPlus: error report button (3.2, user idea 24).
-- One button (Basics > Main, or /ftp bug) puts all a bug report needs into a box to copy: the addon's version, the
-- game's build, the addons that work with ours (loaded or not), our last errors from BugGrabber (only the ones that
-- name this addon) and the settings that are not the default. Nothing is sent anywhere: you paste it yourself.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local FRIENDS = { "RXPGuides", "Questie", "ForeverDungeonJournal", "DungeonJournal", "SpecBisTooltip", "AtlasLootClassic",
	"EllesmereUI", "EllesmereUIQuestTracker", "ElvUI", "BugSack", "!BugGrabber", "Details", "BigWigs", "Leatrix_Plus" }
local MAX_ERRORS, MAX_SETTINGS = 8, 60

local function meta(name, field)
	local f = C_AddOns and C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
	if not f then return nil end
	local ok, v = pcall(f, name, field)
	return ok and v or nil
end
local function loaded(name)
	local f = C_AddOns and C_AddOns.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
	if not f then return false end
	local ok, v = pcall(f, name)
	return ok and v and true or false
end

local function errors()
	local bg = rawget(_G, "BugGrabber")
	if type(bg) ~= "table" or type(bg.GetDB) ~= "function" then return nil end
	local ok, list = pcall(bg.GetDB, bg)
	if not ok or type(list) ~= "table" then return nil end
	local out = {}
	for i = #list, 1, -1 do
		local e = list[i]
		local text = type(e) == "table" and (tostring(e.message or "") .. "\n" .. tostring(e.stack or "")) or ""
		if text:find(ADDON, 1, true) then
			out[#out + 1] = ("x%d  %s\n%s"):format(tonumber(e.counter) or 1, tostring(e.message or "?"),
				tostring(e.stack or ""):sub(1, 900))
			if #out >= MAX_ERRORS then break end
		end
	end
	return out
end

local function changedSettings()
	local db, defaults = ns.db, api.DEFAULTS
	local out = {}
	if type(db) ~= "table" then return out end
	for key, v in pairs(db) do
		local t = type(v)
		if t == "boolean" or t == "number" or t == "string" then
			local d = type(defaults) == "table" and defaults[key]
			if (d ~= nil and v ~= d) or (d == nil and v == false) then out[#out + 1] = ("%s=%s"):format(key, tostring(v)) end
		end
	end
	table.sort(out)
	while #out > MAX_SETTINGS do table.remove(out) end
	return out
end

function api.bugReportText()
	local lines = { "**ForeverTrackerPlus bug report**" }
	local version = meta(ADDON, "Version") or "?"
	local build, number, _, toc = "?", "?", nil, "?"
	if GetBuildInfo then build, number, _, toc = GetBuildInfo() end
	lines[#lines + 1] = ("Version %s, game %s (%s, toc %s), %s"):format(version, tostring(build), tostring(number),
		tostring(toc), GetLocale and GetLocale() or "?")
	local on, off = {}, {}
	for _, name in ipairs(FRIENDS) do
		if loaded(name) then on[#on + 1] = name .. " " .. tostring(meta(name, "Version") or "") end
	end
	lines[#lines + 1] = "Addons: " .. (#on > 0 and table.concat(on, ", ") or "none of the ones we work with")
	lines[#lines + 1] = ""
	lines[#lines + 1] = "What happened: (write it here)"
	lines[#lines + 1] = ""
	local list = errors()
	if not list then
		lines[#lines + 1] = "Errors: BugSack is not installed (install it to add our errors here)"
	elseif #list == 0 then
		lines[#lines + 1] = "Errors: none of ours"
	else
		lines[#lines + 1] = ("Errors (the last %d of ours):"):format(#list)
		for _, e in ipairs(list) do lines[#lines + 1] = "```\n" .. e .. "\n```" end
	end
	local changed = changedSettings()
	lines[#lines + 1] = "Settings not at the default: " .. (#changed > 0 and table.concat(changed, ", ") or "none")
	return table.concat(lines, "\n")
end

-- the box --------------------------------------------------------------------------------------------------------
local box
local function build()
	local kit = api.themeKit
	if not kit then return nil end
	local C = kit.C
	local f = CreateFrame("Frame", "ForeverTrackerPlusBugReport", UIParent)
	f:SetSize(560, 420)
	f:SetPoint("CENTER", 0, 30)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "ForeverTrackerPlusBugReport") end
	kit.solid(f, "BACKGROUND", C.window, 0.98):SetAllPoints()
	kit.border(f, C.edge, 2, "BORDER")
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", 2, -2)
	bar:SetPoint("TOPRIGHT", -2, -2)
	bar:SetHeight(30)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	kit.gradient(barBg, C.titleTop, C.titleBottom)
	local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("CENTER")
	title:SetText("Bug report: Ctrl+A, then Ctrl+C to copy")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -3, -3)
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 18, -42)
	scroll:SetPoint("BOTTOMRIGHT", -36, 52)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal or GameFontHighlight)
	edit:SetWidth(500)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(edit)
	f.edit = edit
	local again = kit.makeButton(f, "Make it again", 140, function() edit:SetText(api.bugReportText()); edit:HighlightText() end)
	again:SetPoint("BOTTOMLEFT", 18, 14)
	local ok = kit.makeButton(f, "Close", 110, function() f:Hide() end)
	ok:SetPoint("BOTTOMRIGHT", -18, 14)
	f:Hide()
	box = f
	return f
end

function api.showBugReport()
	if not box and not build() then return end
	box.edit:SetText(api.bugReportText())
	box:Show()
	box.edit:SetFocus()
	box.edit:HighlightText()
end

if api.addSlash then
	api.addSlash("bug", "make a bug report to copy (version, addons, our errors, changed settings)", function() api.showBugReport() end)
end
