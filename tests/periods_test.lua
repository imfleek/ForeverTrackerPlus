-- 3.2 Statistics (Stats.lua): the "< This session >" period switcher and the "All characters" checkbox on Overview and
-- Run analysis; gold from the auction house, mail, vendors and trades, and gold spent; a money tile's coin icon by its largest coin;
-- and the "Coin size" of the coins on quest titles (Extras.lua coinPx).
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end

local handlers = {}
local function frame()
	return setmetatable({}, { __index = function(t, k)
		if k == "SetScript" then return function(_, name, fn) if name == "OnEvent" then handlers[#handlers + 1] = fn end end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return frame() end end
		if k == "IsEventRegistered" then return function() return true end end
		return function() end
	end })
end
local now, wall = 1000, 1800000000 -- 2027-01-15 (a Friday)
local tickers = {}
local st = { money = 10000 }
local shownFrames = {}
local sns = { api = {}, onLogin = {}, db = {} }
local senv = setmetatable({
	CreateFrame = frame, GetTime = function() return now end, time = function() return wall end,
	date = function(f, t) return os.date(f, t or wall) end,
	C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn return {} end, After = function() end },
	UnitName = function() return "Jugo" end, GetRealmName = function() return "Realm" end,
	UnitClass = function() return "Warlock", "WARLOCK" end,
	UnitLevel = function() return 20 end, UnitXP = function() return 0 end, UnitXPMax = function() return 1000 end,
	UnitIsDeadOrGhost = function() return false end, UnitOnTaxi = function() return false end,
	UnitAffectingCombat = function() return false end, UnitIsAFK = function() return false end,
	GetUnitSpeed = function() return 7 end, IsMounted = function() return false end,
	IsSwimming = function() return false end, IsFalling = function() return false end,
	UnitCastingInfo = function() end, UnitChannelInfo = function() end,
	GetMoney = function() return st.money end, GetNumLootItems = function() return 0 end,
	GetInboxInvoiceInfo = function(i) return st.mails and st.mails[i] and st.mails[i].invoice end,
	GetInboxHeaderInfo = function(i) local m = st.mails and st.mails[i] or {}; return nil, nil, m.sender, "subject", 0 end,
	GetMaxPlayerLevel = function() return 60 end,
	RequestTimePlayed = function() end, GetRealZoneText = function() return "Elwynn Forest" end,
	C_QuestLog = {}, DEFAULT_CHAT_FRAME = { AddMessage = function() end }, NUM_CHAT_WINDOWS = 0,
	StaticPopupDialogs = {}, wipe = function(t) for k in pairs(t) do t[k] = nil end end,
}, { __index = function(_, k)
	if shownFrames[k] then return { IsShown = function() return true end } end
	return _G[k]
end })
senv._G = senv
assert(loadfile(dir .. "/Tracker/Stats.lua", "t", senv))("ForeverTrackerPlus", { tracker = sns })
local api, db = sns.api, sns.db
for _, fn in ipairs(sns.onLogin) do fn() end
local function fire(e, ...) for _, h in ipairs(handlers) do h(nil, e, ...) end end
local function tick(n) for _ = 1, n do now = now + 1; wall = wall + 1; for _, t in ipairs(tickers) do pcall(t) end end end
local function showF(name, on) rawset(senv, name, on and { IsShown = function() return true end } or nil) end
local function money(delta) st.money = st.money + delta; fire("PLAYER_MONEY") end
local function totalOf(period, all) local _, total = api.statsPeriodTotals(period, all); return math.floor(total + 0.5) end
local function sumsOf(period, all) local _, _, s = api.statsPeriodTotals(period, all); return s end

-- periods
tick(1); tick(10)
check("this session counts the time played", totalOf("session") == 10)
check("this week and this month count it too", totalOf("week") == 10 and totalOf("month") == 10)
check("all-time counts it", totalOf("all") == 10)
check("no last session yet", totalOf("last") == 0)
check("the week starts on a Monday", os.date("%w", os.time({ year = tonumber(api.statsPeriodStart("week"):sub(1, 4)),
	month = tonumber(api.statsPeriodStart("week"):sub(6, 7)), day = tonumber(api.statsPeriodStart("week"):sub(9, 10)), hour = 12 })) == "1")
check("the month starts on the 1st", api.statsPeriodStart("month") == os.date("%Y-%m-01", wall))

-- gold by source
showF("MailFrame", true); money(500); showF("MailFrame", false)
showF("AuctionHouseFrame", true); money(250); showF("AuctionHouseFrame", false)
showF("MerchantFrame", true); money(300); money(-120); showF("MerchantFrame", false)
showF("TradeFrame", true); fire("TRADE_CLOSED"); showF("TradeFrame", false)
money(200) -- the trade's money comes just after the window closed
tick(5); money(999) -- later, from nowhere we know: not counted
fire("QUEST_TURNED_IN", 7, 0, 1000); money(1000) -- the reward: counted once, as quest gold
money(-80)
local r = api.statsRun()
check("mail money (mailbox open)", r.gold.mail == 500)
check("auction house money (auction house open)", r.gold.ah == 250)
check("vendor money", r.gold.vendor == 300)
check("trade money, also just after the window closed", r.gold.trade == 200)
check("money from nowhere we know is not counted", r.gold.ah + r.gold.mail + r.gold.vendor + r.gold.trade + r.gold.loot == 1250)
check("a quest reward counts as quest gold, once", r.gold.quests == 1000)
check("gold spent: every copper that went out", r.gold.spent == 200)
local s = sumsOf("session")
check("the session has the gold too", s.goldMail == 500 and s.goldAH == 250 and s.goldVendor == 300 and s.goldTrade == 200 and s.goldSpent == 200 and s.goldQuests == 1000)

-- tiles and coin icons
check("coin icon: copper, silver, gold by the largest coin", api.statsCoinIcon(55):find("Coin_05", 1, true)
	and api.statsCoinIcon(250):find("Coin_03", 1, true) and api.statsCoinIcon(10000):find("Coin_01", 1, true) and true or false)
local gold = api.statsGoldTiles()
local byLabel = {}
for _, t in ipairs(gold) do byLabel[t[3]] = t end
check("gold tiles have the new sources", byLabel["Gold from AH"] and byLabel["Gold from mail"] and not byLabel["Gold from mail/AH"] and byLabel["Gold from vendors"] and byLabel["Gold from trades"]
	and byLabel["Gold spent"] and byLabel["Gold from mobs"] and not byLabel["Gold off mobs"] and true or false)
check("a tile's icon follows its amount", byLabel["Gold from mail"][1]:find("Coin_03", 1, true) -- 5s
	and byLabel["Gold from mobs"][1]:find("Coin_05", 1, true) and true or false) -- 0c
check("gold in total: every source", byLabel["Gold in total"][2] == api.statsMoney(2250))

-- the switcher
check("the default period is This session", api.statsPeriodOf("run") == "session" and api.statsPeriodOf("overview") == "session")
api.statsStepPeriod("run", 1)
check("> goes to Last session", api.statsPeriodOf("run") == "last" and api.statsPeriodOf("overview") == "session")
api.statsStepPeriod("run", -1); api.statsStepPeriod("run", -1)
check("< from This session goes round to All-time", api.statsPeriodOf("run") == "all")
check("the names", api.statsPeriodName("week") == "This week" and api.statsPeriodName("all") == "All-time")
db.statsPeriodRun = "session"
check("the Discord text names the period", api.statsDiscordText():find("(This session)", 1, true) ~= nil)
db.statsPeriodRun = "bogus"
check("an unknown saved period is This session", api.statsPeriodOf("run") == "session")
db.statsPeriodRun = nil

-- a /reload keeps the session; a new login after a while starts a new one
wall = wall + 60; api.statsStartSession(); tick(2)
check("a /reload: the same session goes on", totalOf("session") == 17 and totalOf("last") == 0)
wall = wall + 3600; api.statsStartSession(); tick(3)
check("a new login: a new session", totalOf("session") == 3)
check("and the one before is the last session", totalOf("last") == 17 and sumsOf("last").goldMail == 500 and sumsOf("last").goldAH == 250)
check("the week still has both", totalOf("week") == 20)

-- all characters
local today = os.date("%Y-%m-%d", wall)
db.statsRuns["Other-Realm"] = { levels = { [10] = { t = { walk = 100 } } }, gold = { quests = 7 }, quests = { done = 3 },
	days = { [today] = { t = { walk = 50 }, goldQuests = 7, quests = 3 }, ["2001-01-01"] = { t = { walk = 999 } } },
	session = { t = { walk = 20 }, seen = wall - 10 } }
db.statsRuns["Jugo-Realm (previous)"] = { levels = { [5] = { t = { walk = 5000 } } }, days = { [today] = { t = { walk = 5000 } } } }
check("off: only this character", totalOf("week", false) == 20 and totalOf("all", false) == 20)
check("on: this week adds the other character's days", totalOf("week", true) == 70 and sumsOf("week", true).goldQuests == 1007)
check("on: all-time adds the other character", totalOf("all", true) == 120 and sumsOf("all", true).questsDone == 4)
check("on: an older run of a name is left out", totalOf("all", true) < 5000)
check("on: last session is the account's last one", totalOf("last", true) == 20)
check("on: this session is still this login", totalOf("session", true) == 3)
db.statsAllOverview = true
local tiles = api.statsOverviewTiles()
check("Overview, this session, all characters: only this login (0 quests)", tiles[1][2] == "0")
db.statsPeriodOverview = "week"
tiles = api.statsOverviewTiles()
check("Overview, this week, all characters: 1 + 3 quests", tiles[1][2] == "4")
db.statsAllOverview = false
tiles = api.statsOverviewTiles()
check("Overview, this week, this character: 1 quest", tiles[1][2] == "1")

-- gold from the auction house or mail, by the mail whose money was taken
local before = { ah = r.gold.ah, mail = r.gold.mail }
st.mails = { { invoice = "seller" }, { sender = "Bob" }, { sender = "Auction House" } }
showF("MailFrame", true)
api.statsOnMailTaken(1); money(400)
check("an auction invoice mail: gold from AH", r.gold.ah == before.ah + 400 and r.gold.mail == before.mail)
api.statsOnMailTaken(2); money(100)
check("a player's mail: gold from mail", r.gold.mail == before.mail + 100 and r.gold.ah == before.ah + 400)
api.statsOnMailTaken(3); money(50)
check("the Auction House as sender: gold from AH", r.gold.ah == before.ah + 450)
showF("MailFrame", false)
check("the session splits them too", sumsOf("session").goldAH == 450 and sumsOf("session").goldMail == 100)

-- times as d h m s (3.2, user: "like the Time Played tile"); the dungeon and flight timers keep 1:02
local T = api.statsTime
check("times: 45s, 4m 5s, 5h 12m, 2d 3h", T(45) == "45s" and T(245) == "4m 5s" and T(5 * 3600 + 12 * 60) == "5h 12m"
	and T(2 * 86400 + 3 * 3600 + 59) == "2d 3h" and T(0) == "0s")
check("the timers outside Statistics keep 1:02", api.statsClock(62) == "1:02")

-- the coins' size on quest titles
local src = io.open(dir .. "/Tracker/Extras.lua"):read("a")
local coinBlock = src:match("(local COIN_SCALE = .-\napi%.coinPx = coinPx)")
local cdb = {}
local coinPx = load(coinBlock .. "\nreturn coinPx", "x", "t", setmetatable({ db = cdb, api = {} }, { __index = _G }))()
check("coin size 100 %: as before", coinPx(12) == 10)
cdb.coinScale = 2
check("coin size 200 %: twice as big", coinPx(12) == 20)
cdb.coinScale = 9
check("coin size: at most 200 %", coinPx(12) == 20)
cdb.coinScale = 0.5
check("coin size 50 %: never under 6 px", coinPx(12) == 6)

print(pass and "ALL OK" or "SOME FAILED")
