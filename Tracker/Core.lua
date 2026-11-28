-- ForeverTrackerPlus (tracker half): the saved settings, the opacities, the setters the settings window calls and the
-- /qt commands. The tracker itself is our own (Tracker/Own/Frame.lua).
--
-- 3.2 (user: "Delete the old tracker's code"): the classic window (Blizzard's tracker in our scroll window, its
-- scrollbar, header strip, pinned Quests header, Professions box, step aside and battleground reload) was removed.
-- Blizzard's tracker is never moved, sized or parented by us: Own/Frame.lua keeps it at opacity 0 with its mouse off.
-- The setters below only save the value: our frame hooks each one (Own/Frame.lua SETTERS) and redraws.
local ADDON, root = ...; local ns = root.tracker
ns.api, ns.onLogin = {}, {}
-- 3.2 (user: "This addon should always show character surnames"): WoW Forever's characters have a surname.
-- UnitName("player") gives the first name and the surname as two values ("Ana", "Smith"); on other clients the second
-- value is the realm, or empty. api.playerName() is "Ana Smith" (else "Ana"); api.playerKey(saved) is "Ana Smith-Realm",
-- the key for what we save per character, so "Kat Lo" and "Kat Astrofen" no longer share one entry. An entry saved
-- under the first name only ("Ana-Realm", before 3.2) moves to the new key the first time it is read
-- (keep(old) can refuse it, for example when the old entry is of another class).
do
	local function secret(v) return issecretvalue and issecretvalue(v) or false end
	local function realmName()
		local ok, realm = pcall(function() return GetRealmName and GetRealmName() end)
		if not ok or secret(realm) or type(realm) ~= "string" then return "" end
		return realm
	end
	function ns.api.playerName()
		if not UnitName then return nil end
		local ok, first, last = pcall(UnitName, "player")
		if not ok or secret(first) or secret(last) or type(first) ~= "string" or first == "" then return nil, nil end
		local c = Constants and Constants.CharacterNameSeparatorConsts
		local sep = c and type(c.CHARACTERNAME_SURNAME_SEPARATOR) == "string" and c.CHARACTERNAME_SURNAME_SEPARATOR ~= ""
			and c.CHARACTERNAME_SURNAME_SEPARATOR or " "
		if type(last) == "string" and last ~= "" and not secret(last) and last ~= realmName()
			and last ~= (GetNormalizedRealmName and GetNormalizedRealmName()) then
			return first .. sep .. last, first
		end
		return first, first
	end
	function ns.api.playerKey(saved, keep)
		local full, first = ns.api.playerName()
		if not full then return nil end
		local realm = realmName()
		local key, old = full .. "-" .. realm, first .. "-" .. realm
		if type(saved) == "table" and key ~= old and saved[key] == nil and saved[old] ~= nil
			and (not keep or keep(saved[old])) then
			saved[key], saved[old] = saved[old], nil
			if saved[old .. " (previous)"] ~= nil and saved[key .. " (previous)"] == nil then
				saved[key .. " (previous)"], saved[old .. " (previous)"] = saved[old .. " (previous)"], nil
			end
		end
		return key
	end
end
local tracker = _G.ObjectiveTrackerFrame
if not tracker then ns.disabled = true return end

local BAR_WIDTH = 10 -- default; /ftp Quest list "Scrollbar width" (db.scrollbarWidth)
local DEFAULTS = { enabled = true, step = 40, height = 500, scale = 1, locked = true, zoneSort = true, zoneFilter = false, spacing = 0, zoneHeaderScale = 1, zoneHeaderOutline = false, guideDetached = false, scrollbarWidth = 10, questCount = true, questCountSize = 0, questCountCustom = false, questCountColor = { 1, 1, 1, 1 }, questsHeaderColor = false, questsLineColor = false, zoneHeaderX = 4, zoneHeaderY = 0, questTitleX = 0, objectiveX = 0, zoneHeaderColor = { 0.2, 0.85, 0.55 }, tooltips = true, widthExtra = 0, condense = true, progressBars = true, progressBarUnder = false, progressBarBlue = false, titleOutline = false, objectiveOutline = false, distanceText = true, distanceArrow = true, dungeonCard = true, dungeonHeader = true, questGroupFinder = true, npcPanelQuests = true, instanceCap = true, rareAlert = true, expandCurrentZone = false, repTrack = true, questDistance = true, distArrowScale = 1, distArrowAlpha = 1, showXP = true, wordWrap = true, showGold = true, scrollbar = true, scrollbarMouseover = false, zoneHeaderPadY = 6, xpColor = { 0.69, 0.53, 1 }, trackMode = "all", partyProgress = true, configTextSize = 1.15, rewardOrder = { "xp", "gold" }, iconScale = 1, iconAlpha = 1, completeCheck = true, completeCheckScale = 1, completeCheckAlpha = 1, completeCheckColor = false, completeCheckOutline = false, orphanSort = "level", orphanReverse = false, layer = 1, goldCoins = false, xpOrb = false, itemsLeft = true, guideScale = 1, questScale = 1, tooltipCoins = false,
	tooltipXpOrb = false, zoneOrder = "closest", font = "default", questsPadY = 0, questie = true,
	questieChain = true, questieChainReward = true, questieUnlocks = true, attunementStar = true,
	background = false, backgroundColor = { 0, 0, 0, 0.4 }, backgroundPad = 6, trackerAlpha = 1, guideAlpha = 1, questAlpha = 1,
	-- 3.2
	distanceClosest = 3, distanceEta = false, combatFade = "off", combatFadeAlpha = 0.3, raidFade = "off",
	hideDoneObjectives = false, questOrder = "distance", greyLevels = 0,
	killCounts = true, sessionSummary = true, pathMap = true,
	trainerReminder = true, talentReminder = true, rewardArrow = true, rewardDisenchant = true,
	autoReward = "off", questItemAlert = true, itemBarPerRow = 8, itemBarRows = 1,
	dungeonSplits = true, dungeonPartyQuests = true, dungeonShare = true, dungeonAbilities = true,
	zoneExplored = true }
local db

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverTrackerPlus|r " .. msg) end
ns.say = say

-- General opacity (/qt Advanced): our whole tracker and the step buttons; never the settings windows.
-- 3.2: fade or hide the whole tracker in combat or in a raid ("off" / "fade" / "hide")
local fighting = false
local function situationAlpha()
	if not db then return 1 end
	local mode
	if fighting and db.combatFade and db.combatFade ~= "off" then mode = db.combatFade end
	if not mode and db.raidFade and db.raidFade ~= "off" and IsInRaid and IsInRaid() then mode = db.raidFade end
	if mode == "hide" then return 0 end
	if mode == "fade" then return math.min(math.max(tonumber(db.combatFadeAlpha) or 0.3, 0.05), 1) end
	return 1
end
local function trackerAlpha()
	local a = tonumber(db and db.trackerAlpha) or 1
	return math.min(math.max(a, 0.1), 1) * situationAlpha()
end
-- RXP Tracker opacity and Quest Tracker opacity: each a factor on the general opacity (as the two scales)
local function alphaFactor(key)
	local a = tonumber(db and db[key]) or 1
	return math.min(math.max(a, 0.1), 1)
end
local function guideAlpha() return alphaFactor("guideAlpha") end
ns.api.trackerAlpha = trackerAlpha
-- 3.2: a quest's difficulty colour, with "grey at N levels below you" (db.greyLevels; 0: the game's own rule)
function ns.api.questDifficultyRGB(level)
	if type(level) ~= "number" or level <= 0 then return nil end
	local me = UnitLevel and UnitLevel("player") or level
	local n = tonumber(db and db.greyLevels) or 0
	if n > 0 and me - level >= n then return 0.5, 0.5, 0.5 end
	local r, g, b
	if GetQuestDifficultyColor then
		local ok, c = pcall(GetQuestDifficultyColor, level)
		if ok and type(c) == "table" and type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
	end
	if not r then
		local diff = level - me
		if diff >= 5 then r, g, b = 1, 0.1, 0.1
		elseif diff >= 3 then r, g, b = 1, 0.5, 0.25
		elseif diff >= -2 then r, g, b = 1, 1, 0
		else
			local ok, range = pcall(function() return GetQuestGreenRange and GetQuestGreenRange() end)
			if -diff <= ((ok and tonumber(range)) or 8) then r, g, b = 0.25, 0.75, 0.25 else r, g, b = 0.5, 0.5, 0.5 end
		end
	end
	-- the game says grey, but the setting keeps it green until N levels below
	if n > 0 and math.abs(r - g) < 0.05 and math.abs(g - b) < 0.05 and r < 0.8 then return 0.25, 0.75, 0.25 end
	return r, g, b
end
-- what the RXP guide's step buttons (on UIParent) are drawn at
function ns.api.guideTrackerAlpha() return trackerAlpha() * guideAlpha() end

local SCALE_MIN, SCALE_MAX = 0.5, 1.5
local function factor(value) return math.min(math.max(tonumber(value) or 1, SCALE_MIN), SCALE_MAX) end

-- a battleground or an arena (the RXP guide pauses its drawing there: Objectives/tracker/Tracker.lua)
local function secretWorld()
	if type(IsInInstance) ~= "function" then return false end
	local ok, inside, kind = pcall(IsInInstance)
	if not ok then return false end
	if issecretvalue and (issecretvalue(inside) or issecretvalue(kind)) then return true end
	return inside and (kind == "pvp" or kind == "arena") or false
end
ns.api.trackerSecretWorld = secretWorld

-- the default spot (first use, Reset position, Reset to defaults): the middle of the screen
local function homePosition() return { "CENTER", "CENTER", 0, 0 } end

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }
-- Layer slider value 1..100: four strata of 25 levels each. The minimap sits in its own strata, so only a different
-- strata (not just a lower level) puts the tracker behind it.
local function layerFromValue(v)
	v = math.min(math.max(math.floor(v or 1), 1), 100)
	return STRATA[math.floor((v - 1) / 25) + 1], ((v - 1) % 25) + 1
end
ns.api.layerFromValue = layerFromValue

-- the Layer slider's value with none saved: Blizzard's tracker's own strata and level (read once at login)
local blizzStrata, blizzLevel
local function currentLayerValue()
	local strata = blizzStrata or "MEDIUM"
	for i, name in ipairs(STRATA) do
		if name == strata then return (i - 1) * 25 + math.min(math.max(blizzLevel or 1, 1), 25) end
	end
	return 51
end
ns.api.currentLayerValue = currentLayerValue

-- "Usable quest items on the left": on (default) = left of the list, off = on the right
function ns.api.itemSide() return (db.itemsLeft == false) and "right" or "left" end
function ns.api.setItemsLeft(on)
	db.itemsLeft = on and true or false
	if ns.api.applyLayout then ns.api.applyLayout() end
end

---------------------------------------------------------------------------------------------------------------------
-- API used by the config window, the minimap button and the slash commands. Our frame (Own/Frame.lua) hooks these.
---------------------------------------------------------------------------------------------------------------------
local function relocateGuide()
	local guide = root.objectives
	if guide and guide.relocate and not (InCombatLockdown and InCombatLockdown()) then pcall(guide.relocate) end
end
function ns.api.applyLayout() end
function ns.api.applyBackground() end
function ns.api.applyScale() end
function ns.api.applyQuestsPad() end
function ns.api.applyQuestScale() end
function ns.api.applyWidth() end
function ns.api.applyLevel() end
-- a setting that changes how quests are drawn (rewards, checks, distance, fonts, colours): our frame redraws
function ns.api.refreshQuests() end

-- key: "trackerAlpha" (general), "guideAlpha" (RXP Tracker) or "questAlpha" (Quest Tracker)
function ns.api.setTrackerAlpha(value, key)
	if not db then return end
	db[key or "trackerAlpha"] = math.min(math.max(tonumber(value) or 1, 0.1), 1)
	relocateGuide() -- the guide and its step buttons (Objectives/circle/Action.lua) take it on their next placement
end
do -- 3.2: re-apply the opacity when combat or the group changes
	local watch = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		pcall(watch.RegisterEvent, watch, e)
	end
	watch:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then fighting = true
		elseif event == "PLAYER_REGEN_ENABLED" then fighting = false end
		if not db then return end
		if event ~= "PLAYER_REGEN_DISABLED" and event ~= "PLAYER_REGEN_ENABLED"
			and (db.raidFade or "off") == "off" then return end
		if (db.combatFade or "off") == "off" and (db.raidFade or "off") == "off" then return end
		ns.api.setTrackerAlpha(db.trackerAlpha)
	end)
	function ns.api.applySituationAlpha() if db then ns.api.setTrackerAlpha(db.trackerAlpha) end end
end

function ns.api.setScrollbarWidth(value)
	db.scrollbarWidth = math.min(math.max(math.floor((tonumber(value) or BAR_WIDTH) + 0.5), 2), 30)
end
function ns.api.setScrollbarMouseover(on) db.scrollbarMouseover = on and true or false end
function ns.api.setScrollbarShown(shown) db.scrollbar = shown and true or false end

-- Tracker settings > Own window: the RXP Tracker in a window of its own, or back in our tracker
function ns.api.setGuideDetached(on)
	local guideNs = root.objectives
	if not (guideNs and guideNs.setDetached) then return false end
	local ok = guideNs.setDetached(on)
	if ok then ns.api.applyLayout() end
	return ok
end

function ns.api.resetGuideWindow()
	local guideNs = root.objectives
	if guideNs and guideNs.resetWindowPosition then guideNs.resetWindowPosition() end
end

function ns.api.setLocked(locked)
	db.locked = locked and true or false
	if ns.api.ownLockChanged then ns.api.ownLockChanged() end
	if ns.api.refreshConfig then ns.api.refreshConfig() end
end

function ns.api.applyGuideScale()
	local relayout = root.objectives.relayout
	if relayout then pcall(relayout) end -- the guide re-reads its factor when it is placed
end

local function copyDefault(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = v end
	return copy
end

-- keys: only these settings (the /qt page whose Defaults was clicked); nil: every quest tracker setting
function ns.api.resetDefaults(keys, label)
	if InCombatLockdown() then say("cannot reset in combat") return end
	local all = keys == nil
	local function wanted(key) return all or keys[key] end
	if all and ns.api.restoreZone then ns.api.restoreZone() end
	local wasDetached = db.guideDetached and true or false
	for key, value in pairs(DEFAULTS) do
		if wanted(key) then db[key] = copyDefault(value) end
	end
	if all then db.pos = homePosition() end
	if wanted("rewardOrder") then db.rewardOrder = { "xp", "gold" } end
	if (wanted("trackMode") or wanted("zoneSort")) and ns.api.setMode then
		ns.api.setMode(DEFAULTS.trackMode, DEFAULTS.zoneSort)
	end
	if ns.api.applyZoneHeaders then ns.api.applyZoneHeaders() end
	if ns.api.applyExtras then ns.api.applyExtras() end
	if ns.api.applyQuestsHeaderLook then pcall(ns.api.applyQuestsHeaderLook) end
	ns.api.applyGuideScale()
	if ns.api.applyLevel then ns.api.applyLevel() end
	if wanted("minimap") and type(db.minimap) == "table" then
		db.minimap.hide = false
		if ns.api.setMinimapShown then ns.api.setMinimapShown(true) end
	end
	-- back into the quest tracker: setDetached acts only on a change, so it sees the window as it was
	if wanted("guideDetached") and wasDetached and ns.api.setGuideDetached then
		db.guideDetached = true
		pcall(ns.api.setGuideDetached, false)
	end
	ns.api.applyLayout()
	if ns.api.refreshConfig then ns.api.refreshConfig() end
	say((label and (label .. " ") or "") .. "settings reset to defaults")
end

-- The tracker's width without Extra width (tracker units): the RXP Tracker takes this, so Extra width does not

function ns.api.resetPosition() db.pos = homePosition() end

-- /qt debug: a few settings and each part's own report, shown in a window (Tracker/DebugWindow.lua) to copy
local function debugLines(say)
	say(("step=%s height=%s scale=%s locked=%s zoneSort=%s scrollbar=%s layer=%s extra width=%s"):format(
		tostring(db.step), tostring(db.height), tostring(db.scale), tostring(db.locked), tostring(db.zoneSort),
		tostring(db.scrollbar), tostring(db.layer), tostring(db.widthExtra)))
	say(("battleground or arena=%s, in combat=%s"):format(tostring(secretWorld()), tostring(InCombatLockdown())))
	if ns.api.ownSectionsReport then pcall(ns.api.ownSectionsReport, say) end
	if ns.api.zoneDebug then ns.api.zoneDebug(say) end
	if ns.api.extrasDebug then ns.api.extrasDebug(say) end
	say("RXP guide: " .. (root.objectives.rxp and "built-in copy" or "inactive (RestedXP not available)"))
end

-- 3.2 (user): /ftp after the rebrand; /qt still works but is not listed anywhere
_G.SLASH_ALLTRACKERRXP1 = "/ftp"
_G.SLASH_ALLTRACKERRXP4 = "/qt"
_G.SLASH_ALLTRACKERRXP2 = "/rxpft"
_G.SLASH_ALLTRACKERRXP3 = "/qtrxp"
-- /qt help (and any command /qt does not know): every command (debug is left out: it is for bug reports), the quest tracker's first, then the RXP Tracker's
local QT_HELP = {
	{ "", "open or close the settings window" },
	{ "config", "the same as /ftp" },
	{ "guide", "open the settings window at the guide page" },
	{ "quests", "open the settings window at the quest tracker page" },
	{ "orphan", "open the settings window at Orphaned quests" },
	{ "height <px>", "visible tracker height (0 = automatic)" },
	{ "scale <0.5-1.5>", "tracker scale" },
	{ "step <px>", "how far one mouse-wheel turn scrolls" },
	{ "zone", "sort quests by zone, on or off" },
	{ "sort", "sort the quests now" },
	{ "lock", "lock the tracker in place" },
	{ "unlock", "unlock the tracker (drag it like a frame in Edit Mode)" },
	{ "distance", "why a quest title shows or hides its distance arrow" },
	{ "bags", "what the quest marks in your bags see (open your bags first)" },
	{ "setup", "the first-time setup: every feature, on or off" },
	{ "stats", "open the statistics overview" },
	{ "run", "open the run analysis" },
	{ "help", "this list" },
}
ns.api.DEFAULTS = DEFAULTS -- 3.2: the bug report lists the settings not at these (BugReport.lua)
-- 3.2: commands other files add: ns.api.addSlash(name, help, fn(arg, say))
local extraSlash, extraOrder = {}, {}
function ns.api.addSlash(name, helpText, fn)
	if not extraSlash[name] then extraOrder[#extraOrder + 1] = name end
	extraSlash[name] = { helpText, fn }
end
local function printHelp()
	local chat = DEFAULT_CHAT_FRAME
	chat:AddMessage("|cff33ff99ForeverTrackerPlus|r quest tracker:")
	for _, entry in ipairs(QT_HELP) do
		chat:AddMessage("|cff33ff99/ftp" .. (entry[1] ~= "" and " " .. entry[1] or "") .. "|r  " .. entry[2])
	end
	for _, name in ipairs(extraOrder) do chat:AddMessage("|cff33ff99/ftp " .. name .. "|r  " .. extraSlash[name][1]) end
	local guide = root.objectives
	if guide and guide.printHelp then
		guide.printHelp()
	else
		chat:AddMessage("RXP Tracker (needs RestedXP Guides): |cff33ff99/ftp toggle|r, |cff33ff99/ftp steps|r, |cff33ff99/ftp <0-100>|r or |cff33ff99all|r, |cff33ff99/ftp arrow|r, |cff33ff99/ftp satellites|r, |cff33ff99/ftp badge|r, |cff33ff99/ftp status|r, |cff33ff99/ftp welcome|r, |cff33ff99/ftp restart|r, |cff33ff99/ftp why|r")
	end
end

SlashCmdList.ALLTRACKERRXP = function(msg)
	local cmd, arg = (msg or ""):match("^(%S*)%s*(%S*)$")
	cmd = (cmd or ""):lower()
	if not db then return end
	if cmd == "" or cmd == "config" then
		if ns.api.toggleConfig then ns.api.toggleConfig() end
	elseif cmd == "setup" then
		if ns.api.showSetup then ns.api.showSetup(true) end
	elseif cmd == "stats" or cmd == "run" then
		if ns.api.openConfigTab then ns.api.openConfigTab(cmd == "run" and "statsrun" or "statsoverview") end
	elseif cmd == "guide" or cmd == "quests" then
		if ns.api.openConfigTab then ns.api.openConfigTab(cmd) end
	elseif cmd == "orphan" or cmd == "orphans" then
		local g = root.objectives and root.objectives.settings
		if g and g.orphansAvailable and g.orphansAvailable() and ns.api.openConfigTab then
			ns.api.openConfigTab("orphans")
		else
			say("orphaned quests need RestedXP Guides.")
		end
	elseif cmd == "height" and tonumber(arg) then
		db.height = math.max(0, tonumber(arg)); say("visible height = " .. (db.height == 0 and "auto" or db.height))
		ns.api.applyLayout(); if ns.api.refreshConfig then ns.api.refreshConfig() end
	elseif cmd == "scale" and tonumber(arg) then
		db.scale = math.min(math.max(tonumber(arg), 0.5), 1.5); say("scale = " .. db.scale)
		ns.api.applyScale(); if ns.api.refreshConfig then ns.api.refreshConfig() end
	elseif cmd == "step" and tonumber(arg) then
		db.step = math.max(5, tonumber(arg)); say("step = " .. db.step)
		if ns.api.refreshConfig then ns.api.refreshConfig() end
	elseif cmd == "zone" then
		if ns.api.setZoneSort then ns.api.setZoneSort(not db.zoneSort) end
		say("sort by zone " .. (db.zoneSort and "on" or "off"))
	elseif cmd == "sort" then
		if ns.api.sortNow then ns.api.sortNow() end
	elseif cmd == "lock" then ns.api.setLocked(true); say("tracker locked")
	elseif cmd == "unlock" then ns.api.setLocked(false); say("tracker unlocked: drag it like a frame in Edit Mode")
	elseif cmd == "distance" then
		if ns.api.distanceReport then ns.api.distanceReport(say) end
	elseif cmd == "bags" then
		if ns.api.bagReport then ns.api.bagReport(say) end
	elseif extraSlash[cmd] then
		local ok, err = pcall(extraSlash[cmd][2], arg, say)
		if not ok then say(tostring(err)) end
	elseif cmd == "debug" then
		local lines = {}
		debugLines(function(text) lines[#lines + 1] = tostring(text) end)
		if ns.api.npcPanelDebug then ns.api.npcPanelDebug(function(text) lines[#lines + 1] = tostring(text) end) end
		if ns.api.showDebugWindow then
			ns.api.showDebugWindow(lines)
		else
			for _, text in ipairs(lines) do say(text) end
		end
	else
		-- the RXP Tracker's commands (toggle, 0-100, all, arrow, satellites, badge, status, welcome, restart, why)
		local guide = root.objectives
		if cmd ~= "help" and guide and guide.runCommand and guide.runCommand(msg) then return end
		printHelp()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ForeverTrackerPlusDB = ForeverTrackerPlusDB or {}
		db = ForeverTrackerPlusDB
		local fresh = next(db) == nil
		for key, value in pairs(DEFAULTS) do
			-- an unset tracking mode is a real choice ("Blizzard's normal tracking") for existing settings
			if db[key] == nil and (fresh or key ~= "trackMode") then db[key] = value end
		end
		db.scrollbarColor = nil -- removed: every scrollbar uses the Forever art (ScrollSkin.lua)
		if type(db.minimap) ~= "table" then db.minimap = { hide = false, angle = 225 } end
		db.extra = nil -- "layout room" is automatic now
		db.guideScrolls = nil -- "Scroll the RestedXP guide with the quests" was removed
		db.guideScale, db.questScale = factor(db.guideScale), factor(db.questScale)
		db.showRep = nil -- "Rep reward after titles" was removed
		-- 3.5.26: word wrap is on by default, and switched on once for existing settings
		if not db.wrapDefaulted then db.wordWrap, db.wrapDefaulted = true, true end
		-- 3.2: the old tracker's settings (removed with it)
		db.ownTracker, db.instanceReload, db.pinQuestsHeader, db.moreQuests = nil, nil, nil, nil
		db.profAbove, db.profScrollbar, db.profScrollbarMouseover, db.profScrollbarWidth, db.profX, db.profY = nil, nil, nil, nil, nil, nil
		db.enabled = true -- /ftp off was removed with the old tracker
		blizzStrata, blizzLevel = tracker:GetFrameStrata(), tracker:GetFrameLevel() -- reads only
		ns.db = db
		-- no saved spot yet (first use): the middle of the screen, so the window is on screen from the start
		if type(db.pos) ~= "table" then db.pos = homePosition() end
		for _, fn in ipairs(ns.onLogin) do xpcall(fn, geterrorhandler()) end
		-- the very first time the addon loads, the first-time setup opens (Setup.lua, on its own login hook)
	end
end)
