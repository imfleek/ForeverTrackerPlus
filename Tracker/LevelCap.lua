-- R106-58: at level 60 (the level cap), ask once per character whether to disable the separate RXPGuides addon
-- entirely (user). Asked when the character reaches 60 (PLAYER_LEVEL_UP), and on login for a character that is
-- already 60 and was never asked. Choices: disable RXPGuides (the UI reloads), "Not now" (asked again on the next
-- login), "Don't ask again" (this character). Only while RXPGuides is loaded; never in combat (waits for its end).
-- Without RXPGuides the RXP Tracker part of this addon has no guide to show; the quest tracker keeps working.
local _, root = ...; local ns = root.tracker
-- 3.2: the character key with the surname (Core.lua api.playerKey); without it (tests) "Name-Realm"
local function playerKey(...)
	if ns.api.playerKey then return ns.api.playerKey(...) end
	local name, realm = UnitName and UnitName("player"), GetRealmName and GetRealmName()
	if type(name) ~= "string" or (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then return nil end
	return name .. "-" .. tostring(realm or "")
end

local LEVEL_CAP = 60
local DELAY = 8 -- seconds after login, so the popup does not land in the loading-screen rush

local function charKey() return playerKey(ns.db and ns.db.levelCapAsked) or "?" end -- 3.2: with the surname

local function rxpLoaded()
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RXPGuides") and true or false
end

local function answered(db)
	return type(db.levelCapAsked) == "table" and db.levelCapAsked[charKey()] == true
end

local pending = false
local function ask()
	local db = ns.db
	if not db or not rxpLoaded() or answered(db) then return end
	if InCombatLockdown() then pending = true return end
	pending = false
	StaticPopupDialogs.FOREVERTRACKERPLUS_LEVEL_CAP = {
		text = root.BRAND .. ": you reached level " .. LEVEL_CAP .. ".\n\nWould you like to disable the RestedXP Guides "
			.. "addon (RXPGuides) entirely now? The quest tracker keeps working; the RXP Tracker has no guide to show "
			.. "without it. You can turn it on again in the AddOns list. The UI reloads.",
		button1 = "Disable RXPGuides",
		button2 = "Not now",
		button3 = "Don't ask again",
		OnAccept = function()
			db.levelCapAsked = type(db.levelCapAsked) == "table" and db.levelCapAsked or {}
			db.levelCapAsked[charKey()] = true
			pcall(C_AddOns.DisableAddOn, "RXPGuides")
			ReloadUI()
		end,
		OnAlt = function()
			db.levelCapAsked = type(db.levelCapAsked) == "table" and db.levelCapAsked or {}
			db.levelCapAsked[charKey()] = true
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("FOREVERTRACKERPLUS_LEVEL_CAP")
end
ns.api = ns.api or {}
ns.api.askLevelCap = ask

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "PLAYER_LEVEL_UP" then
		if tonumber(arg1) and tonumber(arg1) >= LEVEL_CAP then C_Timer.After(2, ask) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then ask() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if arg1 == false and arg2 == false then return end -- a zone change, not a login or reload
		C_Timer.After(DELAY, function()
			local level = UnitLevel and UnitLevel("player")
			if type(level) == "number" and level >= LEVEL_CAP then ask() end
		end)
	end
end)
