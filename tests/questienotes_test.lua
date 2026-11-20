-- /qt "Show them on the map (Questie)": Questie's own "hide untracked quest icons" (profile.hideUntrackedQuestsMapIcons),
-- read and changed the other way round, so More quests' quests get their map and minimap markers (Questie.lua).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local toggled = 0
local QuestieQuest = {}
function QuestieQuest:ToggleNotes(show) toggled = toggled + 1; self.lastShow = show end
_G.QuestieLoader = { ImportModule = function(_, name) if name == "QuestieQuest" then return QuestieQuest end return {} end }
_G.LibQuestieDB = { Quest = { Get = function() return nil end } }
_G.Questie = { API = { isReady = true, RegisterOnReady = function() end },
	db = { profile = { hideUntrackedQuestsMapIcons = true, enabled = true } } }
_G.C_AddOns = { IsAddOnLoaded = function(n) return n == "Questie" end }
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
_G.geterrorhandler = function() return function(e) print("ERROR", e) end end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local api = {}
local ns = { api = api, onLogin = {}, db = { questie = true } }
assert(loadfile(dir .. "/Tracker/Questie.lua"))("x", { tracker = ns })
local profile = Questie.db.profile

check("matches Questie: hiding untracked icons -> off", api.questieShowsUntracked() == false)
api.setQuestieShowsUntracked(true)
check("on: Questie's option switched off (untracked quests shown)", profile.hideUntrackedQuestsMapIcons == false)
check("on: Questie draws its markers again", toggled == 1 and QuestieQuest.lastShow == true)
check("matches Questie again", api.questieShowsUntracked() == true)
toggled = 0
api.setQuestieShowsUntracked(true)
check("no change: no redraw", toggled == 0)
api.setQuestieShowsUntracked(false)
check("off: Questie's option switched on again", profile.hideUntrackedQuestsMapIcons == true and toggled == 1)
profile.hideUntrackedQuestsMapIcons = false -- changed in Questie's own options
check("follows a change made in Questie", api.questieShowsUntracked() == true)
profile.enabled = false
toggled = 0
api.setQuestieShowsUntracked(false)
check("Questie's icons switched off: the setting changes, icons not turned on", profile.hideUntrackedQuestsMapIcons == true
	and toggled == 0)
_G.Questie = nil
check("no Questie: off, and nothing changed", api.questieShowsUntracked() == false
	and pcall(api.setQuestieShowsUntracked, true))
print(pass and "PASS" or "FAILED")
