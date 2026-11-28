# Changelog

All notable changes to ForeverTrackerPlus (called RXP ForeverTracker before 3.1.1). Newest first. Settings window: `/ftp` (`/qt` still works).

## 3.2

### Added
- **Big quest item button.** When you stand near the place your closest tracked quest's item is used, a big button with that item shows at the bottom middle of the screen, with gold light to each side. Ctrl+right-drag moves it. Set it in Helpers > On screen > Quest items. It has a key binding too.
- **Legacy Challenge icons.** Each tracked Legacy Challenge in the tracker shows its icon left of its name. The name stays where it was; the icon sits left of it, as the quest title icons do.
- **One switch for all sounds.** Basics > Main > "Sounds" turns off every sound the addon plays: the alerts (rares, battleground bases, low breath, LayerSwap ready, quest items, secrets) and the clicks.
- **LayerSwap button.** With LayerSwap on, its logo shows right of "Quests" on the tracker's Quests header. A click presses LayerSwap's own "Swap layer" button. The tooltip shows what LayerSwap's button says now, for example "Wait 0:30". The icon goes grey while LayerSwap's button is off. Click it while it is grey, and you get a sign when you can swap: the icon glows, a sound plays and a chat line tells you. Then click again to swap. (The game sends LayerSwap's request only from a real click, so we cannot swap for you.) The glow has its own switch on GENERAL > Animations. Right of the icon: LayerSwap's mini bar text, its two lines on top of each other (switch: "LayerSwap text"). LayerSwap fills that text only while its mini bar is on. So while the LayerSwap button is on, we turn LayerSwap's mini bar on for you, make it invisible and let clicks pass through it (switch: "Hide LayerSwap's mini bar"). The tooltip shows LayerSwap's Host (on or off), and a right-click turns Host on or off. Switch: Quest list > "LayerSwap button".
- **Battleground timers into chat.** Shift-click a battleground timer bar to put it in the chat box, for example "Ruins (Horde): 0:34" or "Alliance wins 2000-1160 in 3:12".
- **Battleground animations.** A captured base's bar flashes in its side's colour and fades out. A base bar pulses red in its last 10 seconds. The win bar flips over when the winning side changes. A flag carrier's line shakes when their health is low (when the game shows it). A dropped flag shows "dropped" and its line pops. The "Enter" bar of a ready queue bounces, then turns red and pulses in its last 15 seconds. A gold VICTORY or red DEFEAT banner shows when the battleground ends (/ftp bgbanner: a test). The corpse arrow glows when you are close enough. The run summary's gold and experience count up from the last card's numbers. The "Loot you want" line sparkles once each run. Each has its own switch on GENERAL > Animations.
- **Dead-end alert.** A cross shows in front of a quest that is grey, leads to no quest you can take, and gives no item or reputation. Its tooltip says why, and a chat line tells you when you accept one. Needs Questie. Switch: Quest titles > Lines > Dead-end alert.
- **Loot you want on the dungeon card.** The card names the items here that are your DungeonJournal favourites or best in slot for your spec in SpecBisTooltip. Hover it for the full list. Needs DungeonJournal. Switch: Dungeons > Loot you want.
- **Run summary and run history.** When you leave a dungeon after a boss kill, a card shows your time, bosses, deaths, gold and experience. "Copy for Discord" gives you one line to paste. STATISTICS > Dungeon runs shows each dungeon's best time and average, and your last runs. /ftp runcard shows the last card again.
- **Tags in the quest log.** Blizzard's quest log shows the Forever W, the attunement star, the type marker and the quest's level. Switch: Quest titles > Quest log.
- **Turn-ins on zone headers.** A zone header says "(3 turn-ins)" when two or more of your finished quests are taken in there. Needs Questie.
- **Corpse run helper.** As a ghost you get an arrow to your corpse, the yards, about how long the run takes, when you can come back, and what the spirit healer costs at your level. Switch: Helpers > Corpse run.
- **Make a bug report.** A button on Basics > Main (or /ftp bug) puts the version, your addons, our last errors (from BugSack) and your changed settings in a box to copy.
- **Animations with ideas from other addons.** The screen's edges flash red when a quest fails (from BigWigs). A red dot pulses on the dungeon card while the run goes on (from EllesmereUI). "NEW BEST" and the time saved flash on the card when a boss dies faster than ever (from Details). The What's new button in the settings glows until you read the notes (from EllesmereUI). Each has its own switch on GENERAL > Animations.
- **Still more animations.** On the dungeon card the deaths number shakes red when someone dies, the players number bumps when someone joins or leaves, and the instance line shakes when you reach the hourly limit. "+250" rises from the reputation bar when you gain reputation. A quest you abandon shakes red before it fades. Settings section icons tilt under the mouse, and the settings window fades out when you close it. Each has its own switch on GENERAL > Animations.
- **Animations for RestedXP, the dungeon card and the settings.** A RestedXP step you mark done moves right and fades, and a gold light goes down the new current step. The yards after a quest title count down smoothly. On the dungeon card the boss portraits drop in, a killed boss's portrait turns over with a gold check, and after the last boss the card flashes and says CLEARED. In the settings, search matches flash, a small check shows next to a setting you change, sliders slide back after Defaults, dropdowns unfold, and the row under the mouse lights up. Each has its own switch on GENERAL > Animations.
- **Animations settings page.** GENERAL > Animations has a switch for every animation, in groups: Quest tracker, Arrow and map, RestedXP, Dungeons, Statistics and Settings window. "All animations" turns them all off. The level-up banner switch is there too. The Animations switch moved here from Basics > Main.
- **Level-up banner.** On a new level a gold banner shows at the top middle of the screen, where the battleground resurrect timer shows: our gold diamond with the level, "LEVEL 23", and how long the last level took. Statistics > Options > "Level-up banner". `/ftp levelup` shows a test.
- **Even more animations.** A quest item sparkles when its cooldown ends. Quests glide to their new place when the order changes. The tracker list scrolls smoothly. The quest list and the whole tracker fold up and roll down. The world marker bursts with light when you arrive. RestedXP steps move up and the new step fades in when you finish one, and the RestedXP arrow pulses when it gets a new target. Settings switches slide, and a slider's value glows and bounces when you let go.
- **More animations.** Zone groups slide open and fade shut. A count that goes up glows, and a bar's count bounces. The quest counter pulses red when a quest fills an almost full log. The distance arrow turns smoothly, and the yards glow gold within 20 yards. A new rare pulses on its zone header, with a raid-warning style message in the middle of the screen (Quest list > "Rare message on screen"). A killed boss is struck through on the dungeon card. Statistics tiles count up when their page opens. Settings cards fade their rows in and turn their arrow. Quest titles light up under the mouse.
- **Animations.** A finished objective flashes gold. A finished quest's check pops and a light sweeps over its title. New quests slide in, and quests that leave the log fade out. Progress bars grow to their new value. The settings window fades in, and a gold mark glides under the open tab. Turn them off in GENERAL > Animations. They never start in combat.
- **Our own tracker, now the only tracker.** A new tracker in its own frame. Blizzard's tracker is hidden and never moved, so it cannot cause the "secret auras" error in instances. It shows your quests with their objectives, in zone groups when you sort by zone. It follows your tracking mode, "Show quests in my zone", "Expand current zone only" and "Hide done objectives". With "Track all quests" it shows every quest, with no limit. It has the same header art as Blizzard's tracker ("All Objectives" and "Quests", with collapse buttons and the quest count), the scrollbar, the background, and your size, scale, layer, opacity, combat and raid fade, spacing and font settings. Quest rows work as on Blizzard's tracker: rewards after the title, the title icons and the check, the distance and arrow, progress bars on objectives, the quest tooltip (with party progress), clicks (open, Shift-click to stop tracking, the right-click menu with Blizzard's lines: Focus, Stop tracking, Open in quest log, Show on map, Share quest and Abandon quest, which asks first; group finder, reward links) and quest item buttons. The RestedXP guide shows at the top of it, under the main header, as in Blizzard's tracker (its own window, scale and collapse work too, and it shows in battlegrounds and arenas too). In dungeons and raids the dungeon card shows at the very top, above the guide. The tracked reputation bar and the reminders (new trainer spells, unspent talent points) show under it. Tracked recipes show in their own Professions section above the quests, with the reagents you have and need (click: open the recipe, Shift-click: stop tracking). Legacy Challenges can be tracked: click one on the Collections > Challenges > Legacy Challenges page, and it shows above the quests with its open steps. Settings > Quest titles has an "Objectives horizontal position" slider: it moves the objective lines left or right of their title. In a battleground, a Battlegrounds section shows timer bars: the battle start, bases and graveyards being captured, and the flag respawn (Warsong Gulch, Arathi Basin, Alterac Valley, Eye of the Storm, Darkspear Islands). It also shows your queues (time waited, time left to enter), who wins and when, the time left in the match, and who holds each flag, and it warns you when one of your side's nodes is being taken. `/qt bg` lists what the game reports there. The Battleground section has its own settings page in `/qt` (each bar, icons, flag carriers, warnings). The settings have two new groups: INSTANCES (Dungeons, Battleground) and COLLECTIONS (Challenges: Legacy; Quest chains: Attunements, Class quests, Profession quests, Library books, Secrets with the Sleeping bag chain), which used to be Guides. The tracked reputation bar has its own "Reputation" header that folds it away. The quest titles slider moves only the titles and their icons, and they can go up to 40 px left of the header bars (the background follows). The rare tag and "Explored 7/12" show on its zone headers, and the 3D model opens beside it. The "Quests" header colours work on it too. It is always on. The settings only the old tracker used were removed: "Use our own tracker (beta)", "Keep the Quests header at the top", "Professions beside the quest tracker" (with its position and scrollbar), "List quests past the tracking limit" and "Reload when entering a battleground". "RXP Tracker opacity" now works on the guide in it. The old tracker's code was removed, so the addon is smaller and loads less. `/qt on`, `/qt off`, `/qt reset` and `/qt fontlog` were removed with it. With no tracker on screen, the guide menu opens at the cursor. The mouse wheel anywhere over the RestedXP guide scrolls its upcoming steps smoothly; it no longer zooms the camera between the rows.
- **Distance only on your 3 closest quests.** Only the 3 quests closest to you show the yards and the arrow. Change the number, or 0 for all: Settings > Quest titles > Distance > "Closest quests with distance".
- **Time to arrive** (off by default): after the yards, how long it takes to get there at your speed, as "1:20". Also on the world marker.
- **Fade or hide the tracker in combat or in a raid** (Settings > Size and layer > Combat and raids). Choose Normal, Fade or Hide for each, and how see-through Fade is.
- **Hide done objectives** (off by default): an objective you finished ("8/8") is taken off the quest.
- **Sort quests in a zone** by distance (as before), by level or by how done they are (Settings > Tracking and sorting).
- **Grey quests from N levels below you** (Settings > Tracking and sorting): sets when a quest turns grey in More quests and the journals. 0 keeps the game's rule.
- **Reminders at the top of the tracker** (Settings > Helpers > Reminders):
  - "3 new spells at your trainer". Visit your class trainer once. Click the line: a waypoint to that trainer. Hover it: the spells and their cost.
  - "2 talent points to spend". Click the line: the talent window.
- **Alert for items that start a quest:** you loot an item that starts a quest you do not have, and a message shows on screen and in chat.
- **Kill count in mob tooltips:** how many of that mob this character killed (counted from 3.2 on).
- **Your path on the world map:** small gold dots where you went during this level. A "Clear path" button.
- **Session summary:** at login, a chat line with what you did last session: time, quests, experience, levels, gold, kills and deaths. `/qt session` shows this session.
- **Run analysis: Camp and rest.** In "Where the time went", Downtime has "At a campfire" (standing, AFK, eating or map time at a campfire; in the total) and "Well Rested" (its last line; not in the total, as it stays on while you do anything else). Always counted.
- **Quest rewards** (Settings > Helpers > Rewards):
  - A green arrow on a reward that is better than what you wear. It weighs your class's main stat (or the stat you pick), stamina, armor and weapon damage. Armor your class cannot wear is never an upgrade.
  - A disenchant icon on rewards that can be disenchanted. Hover the reward: what it most likely disenchants into.
  - Auto pick (off by default): with "Turn in finished quests" on, the best upgrade or the reward that sells for the most is taken for you. Hold Shift to pick yourself.
- **Quest item bar** (Settings > Helpers > On screen): buttons per row, rows (up to 16 buttons), a list of item IDs to always show, and Alt+right-click a button to never show that item again ("Show hidden items again" brings them back).
- **Dungeon card** (Settings > Instances > Dungeons):
  - Splits: the run's time and each boss's kill time from the run's start, with your best time. A chat line on each kill.
  - Your party's quests for this dungeon: who has which one.
  - A "Share N quests" button for your quests for this dungeon. `/qt share` shares every quest you can.
  - The next boss's abilities from the Encounter Journal (hover the line).
  - `/qt party`: which party member has which quest.
- **New guide pages** (Settings > Collections > Quest chains):
  - Attunements: Molten Core, Onyxia's Lair (your faction's chain), Blackwing Lair and Naxxramas, step by step.
  - Class quests: every quest for your class, in chains, lowest level first (needs Questie).
  - Profession quests: quests that need a profession rank, with your rank (needs Questie).
- **"Explored 7/12" on your zone's header** in the tracker (Settings > Quest list > Zone headers). Hover it to see the areas not found yet.
- **First-time setup:** four new "New in 3.2" steps. If you finished the setup before, it opens once with only the new steps.

- **What's new window:** after an update, a window shows what changed. "Ok" closes it until the next update. "Do not show me changes in future" turns it off (Settings > Basics turns it on again). `/qt news` opens it.
- **Tooltips on every setting:** hover a setting's name in /qt to see what it does.
- **Run analysis: raids and battlegrounds.** Time in raids and in battlegrounds, next to the time in dungeons.
- **Legacy Challenges filters:** search, progress (started, not started, almost done), category and sort.
- **Secrets:** each secret folds open and closed, with a line between secrets. A switch shows or hides the other faction's secrets.

### Changed
- **Found secrets keep their look.** On Guides > Secrets, a found secret keeps its own icon and its gold name. "found" on the right says it is done.
- **Character dropdown in statistics.** Overview, Run analysis and Level splits have a "Character" dropdown: pick any character on this account to see their statistics. Recording is always for the character you play.
- **New command: `/ftp`.** It opens the settings, after the rebrand. `/qt` still works.
- **Surnames everywhere.** Your character's full name ("Ana Smith") is used in Copy for Discord and in statistics. Two characters with the same first name no longer share one record.
- **RESTEDXP settings group moves.** With RestedXP Guides on, it is above QUESTS. Without it, it is above ADDON.
- **Shorter setting hints.** The grey hint lines are checked for grammar and made shorter.
- **Settings easier to read:** setting names are a bright cream colour now, also the indented ones. The small hint lines under them stay grey.
- **Gold from AH and Gold from mail are apart:** money from an auction mail (or with the auction house open) is Gold from AH; other mail money is Gold from mail.
- **Settings use the space better:** on a wide settings window, two switches in a row share one line. Two sliders do too on a very wide window. A switch with its own sub-options keeps its own line.
- **Settings page tabs, new look:** the open tab is a gold bar lit from above, with a shine along its top, a soft gold glow and dark engraved text. The other tabs are dark pills that turn gold under the mouse. A thin gold line runs under the tabs.
- **Statistics times as d h m s:** every time on the Statistics pages, in Copy for Discord and in the level-up line now reads like the Time played tile: "2d 3h", "5h 12m", "4m 5s", "45s". The dungeon run timer and the flight time keep "1:02".
- **Statistics periods:** Overview and Run analysis have a "< This session >" switcher. Pick This session, Last session, This week, This month or All-time. Sessions, weeks and months count from this version on. A /reload keeps the session.
- **All characters:** a checkbox on Overview and on Run analysis adds up every character of your account.
- **More gold tiles:** Gold from AH, Gold from mail, Gold from vendors, Gold from trades and Gold spent. "Gold off mobs" is now "Gold from mobs". Each money tile shows a gold, silver or copper coin, by its largest coin.
- **Coin size** (Settings > Quest titles > Rewards): make the coins after quest titles smaller or bigger (50-200 %).
- **New world marker look:** a gold diamond on the spot, with a soft glow and a light beam above it. A "?" shows in the diamond when you can turn the quest in. It grows as you come closer, pops in when the target changes, and fades while your mouse is over it. A map waypoint is blue. The game's own icon on that spot is hidden while ours shows.
- **The old names are gone.** The RXPForeverTracker settings folder no longer ships, and settings are no longer copied from RXP ForeverTracker, AllTracker RXP or AllObjectives RXP. If you still have a **RXPForeverTracker** folder in your AddOns folder, you can delete it.
- The setup window's title says "ForeverTrackerPlus Setup".
- **"Where the time went"** is in groups: Fighting, Travel, NPCs and windows, Doing things and Downtime. States with no time are not shown. "Change the order" shows up and down buttons; the order is kept, also for Copy for Discord.
- **"Only challenges this character can do"** also hides other classes' challenges.
- **Library books:** every book is on the page now, with its zone, map spot and a hint where it lies (facts from the Library Books addon). It no longer needs Questie. The librarian is at the top: click for a waypoint, and see how far you are to the next reward (Friend of the Library at 10, 20 and 25 books). The 8 level 60 books have their own section and librarian. Only "A Luddite's Guide to Caring for Your Demonic Pet" and "The Liminal and the Arcane" are marked "not in the game". "Sanguine Sorcery" is a real book now.
- **Secrets: Cozy Sleeping Bag:** its 6 steps are listed under it, like the other secrets: each with a waypoint and how it goes, plus the optional Rekindle. It no longer needs Questie. A found secret also folds now: click it to see its steps.
- **Legacy Challenges window:** each open challenge in Blizzard's Legacy Challenges window has a "Track" box at its bottom right. Tick it to show the challenge and its open steps in our tracker; untick it to stop. It stays in step with the Guides page and with Shift-click in the tracker.
- **3D model panel:** no more lag spike when you hover an item that has no 3D model. The panel remembers what it found for a name, and it searches for a near spelling only once.
- **3D models for new Forever objects:** 670 more objects have a 3D model, from the game's own object cache (for example the Cattail and the Speargrass). An item named after its object ("Handful of Cattails" from a "Cattail") shows that object's model, also when Questie does not link the two.
- **Items learn their object:** when you loot an item from an object, the 3D model panel remembers which object it came from, on all your characters. The guide step's quest objects also match an item named after them ("Bundle of Cattails" and a "Cattail").
- **Quest tooltips in the guide:** quest names in Upcoming Steps have their tooltip again. RestedXP gives a quest's title only for the current and next step; we now take it from the game, Questie, RestedXP's saved quest names, or the step's own words ("Accept Favorite Food"), and match it in any capitals. A quest the game has not loaded yet shows its name and is asked for.
- **Your path on the world map:** the gold dots now show on every map: the zone, its parent zone and the continent, not only the exact map you were on. They also show on OpenMap's stitched map.
- **3D model list:** rebuilt from the game's own object cache, the CMaNGOS database and an extra list (11,386 objects).
- **Instances this hour:** the limit is now 5 an hour, as in the game. We count them ourselves; NovaInstanceTracker is no longer read.
- **"Explored 7/12" on the zone header** now comes only from the zone's Explore achievement; LegacyForever is no longer read.
- **Copy for Discord** has your character's surname.
- **"RestedXP's other NPC automation while it is hidden"** only covers what we do not do ourselves (chat choices, flights, flight paths, hearthstone, buying, spirit healer, training). Accepting, turning in and chat skipping stay ours.
- **Settings sidebar:** Orphaned quests is under Arrow, with the Prerequisite Journal's book. The Arrow section has RestedXP's purple and blue arrow.
- Overview: no "Quests per hour".

### Fixed
- **Less lag.** The tracker does less work each frame and on busy game events. The scroll bar, the quest item buttons, the Professions block and the dungeon layout no longer repeat work when nothing changed. Old unused code was removed.
- **"Tried to call the protected function" when you sent a chat message.** Shift-click (a battleground timer, quest rewards, a quest name) opened the chat box from addon code, and the game then blocked your own Enter. Now the text goes only into a chat box you opened. If the box is closed, a line tells you to press Enter first.
- **Darkspear Islands base timers.** Cove, Tower, Camp and Ruins now get 60-second base timers. Bases are also read from the battleground messages (assaulted, claims, taken, defended), so a timer shows whatever the map art is.
- **Queues.** The Queues list is hidden while you are in a battleground. A paused queue says "(paused)" and its time stops.
- **Corpse run helper.** It said "Your corpse is not on this map" in battlegrounds. It now measures on the map you are on, so the arrow also works in battlegrounds. The box grows to fit its text, and the spirit healer line is left out in battlegrounds. /ftp corpse shows what the game reports.
- **Battleground error.** The flag carrier health check gave an error when a player's name was hidden by the game. Hidden names are now skipped.
- **Battleground win bar.** A Horde player now sees the Horde score first ("Alliance wins 1160-2000"). In Arathi Basin the win time was up to a few seconds off. It now counts from the last score step it saw.
- Icons left of a quest title were sometimes cut and stretched (most often the dungeon icon after a PvP quest's icon). The icon art now starts fresh each time.
- In a battleground or arena, its quests now sort to the top of the tracker (a quest named after it first, then your other battleground quests), as a dungeon's quests do in a dungeon.
- An error on the Secrets page ("attempt to index local 'states'") when secrets of the other faction were hidden.
- An error on taking a flight (Pin.lua: "attempt to perform arithmetic on local 'start'"): a RestedXP timer with no start time.
- **Flight times fixed.** A flight was saved with the time on the ground counted (one route: 828 s for a 100 s flight), and that pulled every estimate down. Old learned flights are cleared once. Landing now saves the real time, and a time far from the game's path data is not saved. The speed is now fixed to match real flight times (about 3 s off on average).
- **Flight times with or without RXPGuides.** With RXPGuides, the bar uses its flight time list. Without it, the bar uses the time you flew, else the time from the game's path data.
- **Flight map times only without RXPGuides.** RestedXP shows its own there. EllesmereUI's flight map time is hidden then too, so you see one time.
- **Clock ring:** while our flight bar is on, the RXP Tracker's clock ring leaves flights out. Other guide timers stay.
- The flight bar now closes when you land.
- **Guides: more places and steps.**
  - **Library books:** every book now has a map spot, also when Questie has none. Click it for a waypoint. Two books seen in the Swamp of Sorrows with no quest known yet are listed too.
  - **Sleeping bag:** the optional Rekindle campfire in Stonetalon.
  - **Alcaz Operative Insignia:** where Horde and Alliance hand in the Document Box (Nazgrel, Renzik, or Rix Xizzix for both), with waypoints.
  - **Dawn Waker:** two missing steps (the Royal Seal of Eldre'Thalas and Lorekeeper Lydros), the four vault switch spots, and what is known at Altairus.
- **Flight log:** type **/qt flights** to see your last 50 flights: the route, the stops, our time, RestedXP's time and the real time. Copy it to report a wrong flight time. Turn it off in Settings under Flights.
- **Mount Hyjal flight times:** flights to and from Tainted Foothills are faster than other flights. Their times were about 1.6 times too long. Fixed.
- **Druid flights from Moonglade** (Bunthen Plainswind to Thunder Bluff, Silva Fil'naveth to Rut'theran Village) now show the flight bar with its time.
- The "In dungeons" tile in Run analysis did not show (the tile box held only 6 tiles).
- Tooltips in the guide lists had an empty first line.
- RestedXP 4.11.40: the guide did not show in the tracker ("attempt to index field 'activeItemFrame'"). RestedXP renamed its item bar; both names work now.
- Errors in a battleground ("Auras cannot be accessed when secret while tainted by ForeverTrackerPlus"). In a battleground or an arena, the addon no longer forces Blizzard's quest tracker to redraw, and the tracker steps aside: Blizzard's quest tracker is shown in Blizzard's own place and size, and our window, scrollbar, More quests, zone headers and the RestedXP guide hide. Everything comes back when you leave.
- **Clean battlegrounds:** pressing Enter Battle reloads the interface, so the battleground starts with nothing of ours on Blizzard's tracker and no errors there. Settings > Basics > "Reload when entering a battleground" turns it off. Dungeons and raids are not changed.

## 3.1.2

### Added
- **Legacy Challenges: "Only challenges this character can do"** (Settings > Guides > Legacy Challenges, off by default). It hides challenges for another race, class or faction, and challenges that need a profession you have not learned. The box under it, **"Include professions you have not learned"**, keeps the profession ones. Every challenge and category now has a tooltip: what it is, how many steps are done, what is still to do, and why you cannot do it.
- **Library books: a "?"** for a book whose status is unknown: Questie says its quest is not in the game, or Questie does not know where the book is. The tooltip says why. Every book has a tooltip: where it lies, or that it is in your bags or turned in, and who takes it.
- **Library books: "Show collected books"** switch (on). Turn it off to see only the books you still need.
- **Esc > Options > AddOns > ForeverTrackerPlus.** A page with the logo, the version, how to open the settings (/qt) and an "Open Options" button.
- **Guides > Secrets** (new page). WoW Forever's hidden toys, quests and mysteries: Alcaz Operative Insignia, Night Watchman's Torch, Chicken Egg (Alliance), Traveler's Symbols, Scarlet Banner, Dawn Waker and the Manual Scavenger Hunt. Dawn Waker and the Scavenger Hunt are not solved yet: they show the steps found so far. Ideas from the SecretChecklist addon:
  - Steps tick themselves when you have the item or the quest is done. A done step also ticks the steps before it.
  - Click a step for a waypoint. A step with several places (such as the Night Watch guard) goes to the next place on each click. TomTom's arrow gets it too, if you use TomTom.
  - A counter at the top: how many secrets you found, with the Cozy Sleeping Bag and Greater Friend of the Library.
  - A chat line and a sound when you find a secret.
  - "Show found secrets" switch (on).
- **Gold tracker** (Statistics > Overview > Gold): gold from quests, gold off mobs, gold this session and in total.
- **Run analysis: jump tracker.** Time in the air and a count of your jumps. Standing still stays too.
- **Run analysis: swimming** and **crafting/gathering** (a profession window open, or crafting, mining, herb picking, skinning, fishing or disenchanting).
- **Run analysis: more of "Where the time went".** New bars: eating/drinking, looting, casting (out of combat, such as your hearthstone), falling (now apart from jumping), map/quest log (open while you stand still) and loading screens.
- **Run analysis: NPCs by window.** Click the NPCs bar to open a list: vendors, trainers, flight masters, bank, mailbox, auction house, trading and quest givers. It is closed by default.
- **Run analysis: "In dungeons" tile.** The time you spent in dungeons and raids.
- **Run analysis: "Gold acquired" tile**, after "XP from quests": gold from quests and off mobs in the whole run.
- **Level splits has a new look.** Tiles at the top: time played, average level, fastest and slowest level, and how far ahead or behind the compared run you are. Each level has a bar (the longest level fills it). Green is faster and red is slower than the compared run, which shows as a thin grey bar.

### Changed
- **New logo:** a red map pin. It shows on the minimap button and next to the addon in the AddOns list.
- **Settings window (/qt):** the title is now "ForeverTrackerPlus", with the new logo. The version number and the window's opacity slider are at the top left. The search box is at the top right, next to the X. The grey hint line and the Close button at the bottom are gone, so the lists reach further down.
- **RESTEDXP sections:** "Orphaned quests" is a section of its own, with the book icon. "Tracker" has RestedXP's logo, and "Arrow" has RestedXP's arrow.
- **Legacy Challenges fold.** Click a category to open or close it. They start open, and the window remembers which ones you closed. "Open all" and "Close all" buttons do every category at once.
- **Legacy Challenges:** the PvP category is now "PVP Ranking". Each rank shows its PvP title for your faction (such as Knight or Stone Guard). An open challenge shows its own icon, not the "!".
- **Level splits:** no note above the bars.
- **Cozy Sleeping Bag:** a finished chain now shows a green check and "You have completed this questchain.", and nothing else. This works with or without Questie. The chain is also found by its quest IDs when Questie's name search finds nothing.
- **Level progress at the level cap:** no bar to the next level. It shows "maximum level" with a full bar.
- **"Experience from quests"** has an experience icon, not a coin.
- **Overview at the level cap:** "Experience from quests" and "Session experience" are hidden.
- **The RXP Tracker has one look: Forever Style.** RXP Style and the Theme setting are gone. If you used RXP Style, you now get Forever Style. The settings page "Themes and guide" is now "Tracker" (under RESTEDXP).

### Removed
- **"Fastest quest"** tile in Statistics > Overview.

### Changed (speed)
- **Faster when you accept a quest:** the game draws the quest tracker many times then. Our quest title and objective text hooks no longer do their work twice, and the line limit is only set when it changes.

### Fixed
- **3D model in "More quests":** quests past the game's tracking limit now show the 3D model when you hover an objective line, the same as tracked quests.
- **"More quests" works like tracked quests:** the type icon (elite, dungeon, raid, PvP) or "[+N]" next to the title, the right-click menu (Focus, Open in quest log, Share quest, Wowhead URL), Ctrl+right-click for reward links, Ctrl+left-click to look for a group, and the quest item button.

## 3.1.1

### Changed name
- **RXP ForeverTracker is now ForeverTrackerPlus.** All features stay the same, RestedXP guide support too. The addon folder is now `ForeverTrackerPlus`. The CurseForge app updates it for you, and your settings come with it. The zip also has a small `RXPForeverTracker` folder, "ForeverTrackerPlus (old settings)": it only keeps your old settings loading, so leave it on. Installing by hand: delete the old `RXPForeverTracker` folder first, then put both new folders in AddOns.

### Added
- **Quest items in your bags** are now also marked in **EllesmereUI Bags** (bags, reagent bag and bank). The marks use EllesmereUI Bags' own overlay hook, the way Peddler draws its coin, so they show above its slot art.
- **Quest items in your bags** stay marked after the objective is done (12/12), until you turn the quest in. You still need them to turn it in. The sell and delete warnings follow the same rule.
- **/qt bags**: shows what the bag marks see (the items your quests need, the bag slots found and how many are marked), for a bug report.
- **Talking to NPCs** (Settings > Helpers > NPCs, and a new setup step): accept quests, turn in finished quests, and skip an NPC's chat when it has only one plain chat option. All off until you turn them on. A reward choice and a turn-in that costs money are left to you. Repeatable, daily and grey quests, and dungeons and raids, each have their own switch (off). Hold Shift while you talk to an NPC: nothing is automatic that time.

### Changed
- **Big progress messages:** the game's small yellow quest progress line at the top of the screen is now hidden while they are on, so the progress shows once. Other yellow messages still show. Switch: Helpers > On screen > "Hide the game's small yellow progress text".
- **Big progress messages** also show an objective that finishes without a number.
- **Flight times for every route:** the addon now has the exact flown length of every flight path in the game, read from the game's own files, curves and stops included. So every route has a time from the start. After your first flight the speed is set from it, and the times are no longer marked "about". A route you flew shows its own measured time. A route the data does not have yet gets an estimate from the flight map.
- **Two addons, one feature:** if OneForAll's reward coin or EllesmereUI's Flight Timer is on too, a window asks which one to keep. "Use ours" turns off that addon's feature. "Keep theirs" turns off ours. EllesmereUI's flight map time has no switch, so its line on the flight map now shows our time instead. You see one line.
- **Faster:** the world marker does no work while it is off or has nothing to show, and it only changes text that changed. The quest item bar and the quest marks in your bags are redone once per burst of changes, not on each one. The progress check is skipped while big messages and party chat are off. "Quest close by" spreads its first check over a few seconds and looks up only quests close to you.

### Fixed
- **Party switches:** "Say each quest step in party chat" (Helpers > On screen) and "Show party progress" (Quest lines) no longer change each other. They used one saved setting.

## 3.1
New helpers on screen and a Guides section. The ideas come from the Questline addon; the code is our own.

This is the first release since 2.0. It also includes 3.0 (below), which was not released on its own.

### Added
- **Quest item bar:** one button for each usable quest item. The tracked quest's item comes first. Shift+drag moves it. Set a key in Key Bindings > AddOns > RXP ForeverTracker: "Use the first quest item".
- **Big progress messages:** quest progress in large letters at the top of the screen, and "Ready to turn in" when a quest is done.
- **World marker:** over your tracked quest's spot in the world: its name, next step, distance and a light beam. Hidden in combat (a switch). Optional: track the nearest quest by itself.
- **Party chat (off by default):** say when a quest is done, or each quest step.
- **Guides section:** Legacy Challenges (with what is still to do), Library books (done, in your bags or open; click for a waypoint) and the Cozy Sleeping Bag chain (click a step for a waypoint). Books and the chain need Questie.
- **Breadcrumb quests:** the nearby quest card leaves out a quest that only sends you to another quest you already did or have. A switch for it is in Settings > Helpers > Quest helpers.
- The first-time setup has new "On screen" and "Guides" steps, and a breadcrumb switch.

## 3.0
A new settings window, statistics, helpers and a first-time setup.

### Added
- **New settings window:** a sidebar of sections with icons and a short line of what each holds (General, Quests, RestedXP, Statistics, Addon), tabs at the top of each section, and cards that fold. Fine-tune cards (positions, spacing, colours) start folded. Most settings now have a grey help line. Search still finds every setting.
- **First-time setup:** walks through every feature with an on/off switch for each. It opens once on 3.0 (also for existing users, starting from your current settings). Open it again with `/qt setup` or Settings > Basics.
- **Statistics:** an Overview (completed quests, experience from quests, average and fastest quest time, quests per hour, session quests, abandoned, level progress, top quest zones), a **Run analysis** (where the time went: combat, running, mounted, flight, NPCs, dead, AFK, standing; tips; time per level; **Copy for Discord**) and **Level splits** (time per level from /played, compared with another of your characters). `/qt stats`, `/qt run`.
- **Level-up line in chat:** the new level, how long the last level took and your time played.
- **Quest items in your bags** get a quest sign; selling one warns you, and the delete question names the quest.
- **Best reward marker:** a gold coin on the quest reward that sells for the most.
- **Quest close by** (Questie): a card when a quest you can take is within 70 yards. Click: waypoint. Right-click: close.
- **Breath warning:** red pulsing screen edges when breath or fatigue has 10 seconds or less left.
- **Flight times:** learns each flight; shows the time left while flying and the time on the flight map.
- **3D model panel:** hover a quest objective (or a RestedXP step) that names an NPC or object: a panel beside the tracker shows its name and a slowly turning 3D model.
- **Dungeon card:** inside a dungeon or raid, a card at the top of the tracker with the instance name, party size, the party's deaths and DungeonJournal's run tracker (when installed). It also shows instances entered this hour against the hourly limit, and your saved lockout.
- **Find a group:** Ctrl+click a quest to post LFM in General chat, list it in Looking For Group, or both.
- **Rares near your quests:** a rare spotted in your zone shows on the zone header with its distance. Hover for its 3D model; click for a waypoint.
- **Wowhead link:** right-click a quest in the tracker > "Wowhead URL" gives the quest's WoW Forever Wowhead link to copy.

### Changed
- The minimap button and tracker lock moved to Settings > Basics.
- The settings window no longer opens by itself on first use: the setup does.

## 2.0
A big update to the quest tracker. It also includes 1.0.4, which was not released on its own.

### Added
- **Distance and direction:** how far away each quest is ("120 yds") and a gold arrow that points at it, after the quest title. Options for the arrow's size and opacity, and to show or hide the distance and the arrow separately. Objective text keeps clear of the arrow. `/qt distance` explains what it shows.
- **Progress bars on objectives**, in the look of the reputation bars: red, orange, yellow, then green when done (or always blue). They can sit to the right of the objective or under it.
- **Tracked reputation** at the top of the quest list: the faction, your standing and a bar. The game's own reputation bar is hidden while it shows. Click it for the reputation window. Option: Quest list → "Tracked reputation at the top".
- **Icon Classifications:** a skull for elite quests, dungeon, raid and PvP icons (battleground quests too, including Battle for the Darkspear Islands), a star on raid attunement quests, and a Forever "W" on quests new to WoW Forever (with its own on/off option). The PvP icon shows your own faction.
- **Professions** (tracked recipes) in their own box beside the quest tracker, with position sliders and their own scrollbar options.
- **Ctrl + right-click a quest** to put the links of its reward items in chat.
- **Quest tooltips:** rewards in their rarity's colour (also the rewards at the end of a Questie chain), party members' surnames, and (from 1.0.4) hold **Ctrl** to see what finishing the quest or its chain unlocks.
- Options: outline quest titles, outline objectives, keep the "Quests" header at the top.
- At level 60, a popup asks whether to turn off the separate RXPGuides addon.
- Moving the tracker looks like Blizzard's Edit Mode.
- RestedXP: guide steps, the waypoint arrow, the item bar and target frame keep working while RestedXP's own window is hidden. Optional NPC automation (quests, gossip, flights, training) while it is hidden.

### Changed
- Every scrollbar uses the look of the game's character pane scrollbar.
- "More quests" reads as part of one list with the tracked quests, and can show its quests on the map (Questie).
- Quest item buttons sit beside the objectives, 12.5 % smaller, so the title row is free for the icons.
- Coins in quest titles are a little smaller, and gold, silver and copper always stay together on one line.
- Blizzard's quest POI buttons next to quest titles are always hidden.
- The mouse wheel scrolls the quest tracker in combat.

### Fixed
- No more jitter or flicker while running, changing zones or opening the world map.
- If EllesmereUI's Quest Tracker is installed, a popup offers to turn it off (it made the tracker text flicker).
- Collapsing the "Quests" header while it is kept at the top no longer causes an error.
- No taint errors about auras in dungeons or from Edit Mode.

## 1.0.4
### Added
- Quest tooltips (with Questie): hold **Ctrl** to see what finishing the quest unlocks, and what finishing its whole chain unlocks. Each quest it opens shows its level, "starts a new chain of N quests" when it leads on to others, and "also needs: …" when another unfinished quest is required too. Only quests for your race and class that you haven't done are listed, and quests the chain already shows are not repeated. Without Ctrl, the tooltip's hint says when there is something to see. On/off: Settings → Tooltips → "What finishing the quest or its chain unlocks" (on by default).

## 1.0.3
### Added
- First release on CurseForge. Releases now go to GitHub and CurseForge together.
### Changed
- README: "How to Install" comes first, with the full `BattleNet/World of Warcraft/_forever_/Interface/AddOns/` path in a copyable box.

## 1.0.2
### Changed
- A new-look README: badges, a Highlights list of the main features, the optional integrated addons, a download link and copyable install path, the settings categories in a table with tips, and the commands in a collapsible section.

## 1.0.1
### Changed
- README: install path is `_forever_`, every command is listed in two tables (quest tracker, RXP Tracker) with what it does, and the developer-only Layout section is gone.

## 1.0
First release. Everything below 1.0 was a pre-release alpha build.

- **Quest tracker:** Blizzard's tracker made mouse-wheel scrollable (with a scrollbar), quests sorted by zone with the closest quest first, experience and gold after quest titles, finished-quest checks, Elite+ and attunement icons, and detailed quest tooltips with rewards (gold includes the best item's vendor value).
- **RXP Tracker** (with RestedXP Guides): guide steps in the objective tracker with click-to-use buttons, a waypoint arrow, back / restart / forward buttons (Shift+click for the previous or next zone guide), a mark-step-done check, item, spell and quest links, and "Why did guide skip?" (`/qt why`).
- **Prerequisite Journal:** what each quest ahead still needs, where to do it, and which later guide does it on the way.
- **Orphaned quests:** RestedXP's cleanup list in the addon's own style, coloured by difficulty, with zones, sorting, and Abandon per quest or all at once (`/qt orphan`).
- **Settings window** (`/qt`): Forever Style theme by default, search, profiles, per-page Defaults, `/qt help` for every command, and `/qt debug` in a copyable window.

# Pre-release alpha builds

## 3.5.92 (alpha)
### Added
- Orphaned quests: a **Sort by** choice above the list (Difficulty (level), Name (A-Z) or Zone (A-Z)) and a **Reverse the order** checkbox. Ties go by level, then by name. Saved for your account; the page's Defaults button sets them back (Difficulty, not reversed).

## 3.5.91 (alpha)
### Added
- Orphaned quests: each quest's zone is shown to its left, in its own column (the quest log heading the quest is under, so a class or profession quest shows that category).

## 3.5.90 (alpha)
### Added
- `/qt orphan` (or `/qt orphans`) opens the settings window at Orphaned quests. Listed in `/qt help`.
### Changed
- Orphaned quests are sorted by level: low level at the top, high level at the bottom (same level: by name).

## 3.5.89 (alpha)
### Added
- Orphaned quests: each quest is coloured by its difficulty for you (grey, green, yellow, orange or red, as in the quest log). The colours follow your level as you level up.

## 3.5.88 (alpha)
### Changed
- Orphaned quests have their own page in the settings, listed right under Themes & guide in the RXP Tracker group.

## 3.5.87 (alpha)
### Changed
- Orphaned quests show exactly RestedXP's own "Cleanup Orphaned Quests" list again: quests in your log that the current guide does not use and no later guide turns in (finished quests are never listed). The 3.5.86 rule is undone, and the settings note says which list it is.

## 3.5.86 (alpha)
### Changed
- Orphaned quests are now the unfinished quests in your log that neither the current guide (from your step on) nor any **later** guide uses: accepts, turn-ins and every other step that names the quest. Only quests that earlier guides used, or no guide uses, are listed. Later guides are the rest of the current guide's Open World or Dungeon list, the other list from the current guide's level up, and the guide's next-guide chain. RestedXP's own list only looked at turn-ins in later guides.

## 3.5.85 (alpha)
### Removed
- The Questie reputation rewards added in 3.5.84 (tooltip lines, the Prerequisite Journal's "Reputation:" line, Questie's value after quest titles). Reputation works as it did before 3.5.84. Orphaned quests are kept.

## 3.5.84 (alpha)
### Added
- Settings, Themes & guide: **Orphaned quests**. These are quests in your log that no step of the current RestedXP guide uses (RestedXP's own "Cleanup Orphaned Quests" list); finished quests are never listed. Hover a quest to show its **Abandon** button and abandon only that quest. **Cleanup orphaned quests (N)** abandons all of them. Both ask once more (click again within 4 seconds), and each quest is checked again just before it is abandoned. The list follows your quest log while the page is open.
- Reputation rewards from Questie (with Questie's racial and other bonuses):
  - quest tooltips: one line per faction under Rewards ("+250 reputation with Stormwind"; a loss in red), also for quests that give only reputation;
  - Prerequisite Journal: a "Reputation:" line under each quest, added up per faction over the quest and its prerequisites;
  - the "+N rep" after quest titles uses Questie's value when it has one.
  Without Questie, the game's own reputation data is used as before.

## 3.5.83 (alpha)
### Changed
- `/qt debug` opens a "Quest tracker debug" window in the settings window's style instead of printing to chat. The details are plain text, and **Copy all and close** selects all of it; press Ctrl+C and the window closes. Addons are not allowed to write to the clipboard themselves, so the Ctrl+C is yours.
- `/qt debug` is no longer listed in `/qt help` (it still works).
### Removed
- `/qt focus`.

## 3.5.82 (alpha)
### Changed
- `/qt help` lists every command, one per line: the quest tracker's `/qt`, `config`, `guide`, `quests`, `height`, `scale`, `step`, `zone`, `sort`, `lock`, `unlock`, `reset`, `on`, `off`, `debug`, `focus` and `help`, then the RXP Tracker's, now including `steps`.
### Fixed
- `/qt help` showed only the RXP Tracker's commands.

## 3.5.81 (alpha)
### Changed
- All RXP Tracker commands are now typed after `/qt`: `/qt toggle`, `/qt 0-100` or `/qt all`, `/qt arrow`, `/qt satellites`, `/qt badge`, `/qt status`, `/qt welcome`, `/qt restart`, `/qt why`. `/qt help` lists them.
- `/rt` is removed. Help text, chat lines and settings hints now say `/qt`.

## 3.5.80 (alpha)
### Fixed
- RXP Tracker: the "mark step done" check is hidden when the current steps are collapsed. It stayed visible because the collapsed view reused the current step's row.

## 3.5.79 (alpha)
### Changed
- Quest tracker: a finished quest's title icons fade to 87 % opacity (was 35 %).

## 3.5.78 (alpha)
### Changed
- Quest tracker: a quest with both an Elite+ icon and the attunement star shows the Elite+ icon next to the title and the star further left. A finished quest's check sits on the Elite+ icon.

## 3.5.77 (alpha)
### Changed
- Quest tracker: on a finished quest with an Elite+ icon (or another title icon), the check sits directly on top of the icon next to the title instead of further left. That icon fades to 35 % opacity, so the check stands out. Quests without an icon keep the check on its own, left of the title.

## 3.5.76 (alpha)
### Added
- `/qt` → Quest titles, under "Checks on finished quests":
  - "Check colour and opacity": a colour swatch with its opacity bar. It replaces the separate "Check opacity" slider and keeps your earlier opacity.
  - "Outline the check": a thin dark edge around the tick, like the zone header outline.

## 3.5.75 (alpha)
### Changed
- Quest tracker: the icons in front of quest titles (Elite+, group, dungeon, raid, PvP and the attunement star) are drawn on their own, left of the title, like the finished-quest check. The title no longer makes room for them, so it never moves. The icon closest to the title sits right next to it, and the check goes further left of the icons. Icons keep their spacing at any icon size.

## 3.5.74 (alpha)
### Changed
- Quest tracker: the finished-quest check is now just a green tick, with no box or edge. It sits on its own to the left of the title and its icons, so it never moves or touches the title.

### Added
- `/qt` → Quest titles: "Checks on finished quests" (on by default), above "Icons on Elite+ quests", with "Check scale" and "Check opacity" under it.
- `/qt` → Quest titles: "Icon opacity" under "Icon size", for the icons in front of quest titles.

## 3.5.73 (alpha)
### Added
- Quest tracker: a finished quest (ready to hand in) gets a green check left of its title, before any other icon such as Elite+, dungeon or the attunement star. It looks like RestedXP's ticked skip box (a dark box with a thin light edge and a green tick) and is drawn rather than an image, so it stays sharp at any size. It also shows in the More Quests section and goes away if the quest is no longer finished.

## 3.5.72 (alpha)
### Changed
- Quest tracker tooltips: the "includes … from selling …" line uses the game's small tooltip font.

## 3.5.71 (alpha)
### Changed
- Quest tracker tooltips: the vendor value of the best item reward is only added to the "Gold" line when the quest gives gold itself. A quest that gives no gold gets no Gold line.

## 3.5.70 (alpha)
### Changed
- Quest tracker tooltips: the "Gold" reward now adds the vendor value of the quest's most valuable item reward, counting both reward choices and items you always receive. A grey line beneath says how much of it comes from selling that item, for example "includes 45s from selling Sword".

## 3.5.69 (alpha)
### Added
- RXP Tracker: Shift+click `<` or `>` to go to the previous or next zone guide, from anywhere in the current one. Either way the guide opens at its real first step, passing over an opening jump step. The arrows' tooltips name the guide Shift+click takes you to.

## 3.5.68 (alpha)
### Fixed
- RXP Tracker, "mark step done" check: clicking it on the step you're on now moves to the next step straight away. Before, it only ticked off the step's objectives and waited for RestedXP to notice, which didn't always happen. For a step that stays open beside others (sticky), it records the step as finished, the way RestedXP does for those.

## 3.5.67 (alpha)
### Changed
- `/rt why`: the window is now titled "Why did guide skip?".

## 3.5.66 (alpha)
### Changed
- `/rt why` opens a window in the same look as the `/qt` settings window and the Prerequisite Journal, and explains things in plain words:
  - Your guide and step, and your level.
  - RestedXP's two settings that skip steps by themselves (On or Off), what each one does, and where to change them.
  - How many steps of this guide were skipped, and why.
  - What moved your guide, newest first. Each move is a sentence, such as "Passed step 1 on the way to step 9", with the reason and the step's objectives. Moves you made with the tracker's buttons are blue; moves RestedXP made are gold.
  - The list updates while the window is open. Buttons: "Copy for a bug report" (the same as text, ready to copy), "Clear the list" and "Refresh".

## 3.5.65 (alpha)
### Added
- Prerequisite Journal, later guides (marked "later guide, higher level"): after "Guide step N wants this quest." it says which zone guide on the way hands in its missing prerequisites, for example "Its prerequisites are done in 47-48 Tanaris on the way." Each prerequisite also shows "done in <guide>, step N". The guides checked run from your place in the current guide up to the one you're viewing. When no guide on the way does them, it says so and lists what to do first, as before.

## 3.5.64 (alpha)
### Fixed
- RXP Tracker, `<` previous step: it no longer rolls the guide over into its later steps. Some guides open with a step that jumps ahead, for example Swamp of Sorrows' "past level 43, skip ahead". `<` never goes back onto such a step. When it's the only step before you, `<` goes back a zone guide instead. If RestedXP still jumps you past where you were after a step back, the tracker takes you back a zone guide, or back to the step you were on when there is no earlier guide.
- Going back a zone guide now starts that guide at its real first step, passing over an opening jump step the same way as the restart button. Before, you could land halfway through it.

## 3.5.63 (alpha)
### Fixed
- RXP Tracker, restart button: guides that open with a step jumping straight to a later point now start at their real first step. For example, 41-41 Swamp of Sorrows opens with an optional "past level 43, skip ahead" step, so restarting put you halfway through it. The restart now passes over such opening steps, along with sticky, optional, above-your-level and already-skipped ones.

## 3.5.62 (alpha)
### Changed
- RXP Tracker: the restart button between `<` and `>` now matches them. It uses the same square dark button frame, the one the game's spellbook arrows and the quest tracker's own buttons use, with a circular arrow in the arrows' gold. Its size and line-up are the same as theirs. It presses in when clicked, greys out when unusable, and its arrow turns the other way while a way back is waiting.

## 3.5.61 (alpha)
### Added
- RXP Tracker, Forever Style: a round curved-arrow button between `<` and `>`. Click it to go to the first step of the current guide; click it again to go back to the step you were on. While a way back is waiting, its arrow turns the other way, and its tooltip names the step you'll return to. It uses the game's own round rotate button art, the same family as the `<` `>` buttons. Switching to another guide forgets the way back.

## 3.5.60 (alpha)
### Changed
- RXP Tracker, `<` previous step: while RestedXP keeps putting you straight back on the step you left, `<` keeps going one more step back until you stay put, or until there is no earlier step. It still stops at once if RestedXP moves you anywhere else or you click again.

## 3.5.59 (alpha)
### Fixed
- RXP Tracker, `<` previous step: no longer fights RestedXP. It is now one step back, the same as RestedXP's own "Go to step". It only passes steps you or RestedXP skipped, not steps whose objectives look done, since that flag can be out of date. If RestedXP puts you straight back on the step you left, `<` goes one more step back, once. Any other step change by RestedXP, or another click, is left alone. Before, it could keep stepping back for several seconds against RestedXP's own changes.

## 3.5.58 (alpha)
### Fixed
- RXP Tracker, `<` back to the previous guide: if RestedXP fails to open that guide or opens no guide at all, the tracker now goes back to the guide you were on. A chat line names the guide that wouldn't open and why, if RestedXP gave a reason. Before, the guide could unload completely. Guides RestedXP marks internal or disabled are no longer picked as the previous guide.
- Prerequisite Journal: the Guides list shows each guide's display name, as RestedXP's own menu does, for example "41-41 Swamp of Sorrows" instead of "41-400_41-41 Swamp of Sorrows".

## 3.5.57 (alpha)
### Changed
- RXP Tracker: the "mark step done" check's hover is softer: a muted gold fill, a gentler rim and a very faint glow. Its tooltip just says "Mark step N done".

## 3.5.56 (alpha)
### Changed
- RXP Tracker: the "mark step done" check is about a third larger. It now uses the Forever settings window's colours: a muted gold rim with a dark middle and a soft shadow. Hovered, the rim turns pale gold, the middle fills gold and a faint glow shows.

## 3.5.55 (alpha)
### Fixed
- Work-around for a RestedXP error on quest reward windows with two or more choices ("bad argument #1 ... Usage: local itemName, itemLink ..."). It came when a reward item wasn't loaded yet. RestedXP's quest helper now waits a moment until every reward choice has loaded, and those items are asked for. Nothing else in RestedXP is changed.

## 3.5.54 (alpha)
### Changed
- RXP Tracker: the "mark step done" check is a gold outline with an empty middle, and fills gold when you hover over it. It was a green check.

## 3.5.53 (alpha)
### Changed
- RXP Tracker: Shift+left-click on a quest name puts its quest link in chat, the same as item and spell links. Shift+right-click on a step, quest name included, is only for making an upcoming step your current step.

## 3.5.52 (alpha)
### Added
- RXP Tracker, Forever Style: a check to the right of each current step's "Step N" marks the step done. It ticks off every objective that is still open, as if you checked each box, and RestedXP moves on.
- RXP Tracker: quests that upcoming steps accept or turn in are now links with the quest tooltip, like in current steps.
- RXP Tracker: Shift+click a quest name, left or right, in current or upcoming steps to put the game's own quest link in chat. Shift+right-click elsewhere on an upcoming step still makes it your current step.

### Fixed
- RXP Tracker: a quest name is linked even when the same line also links an item.

## 3.5.51 (alpha)
### Changed
- RXP Tracker: an upcoming step becomes your current step with Shift+right-click instead of Shift+click. Left clicks, and Shift+left-click on a link to put it in chat, work as before.

## 3.5.50 (alpha)
### Added
- RXP Tracker: Shift+click a step in the Upcoming Steps list (its heading or its text) to make it your current step. Shift+clicking a link in it still puts the link in chat as before. The step's info icon tooltip mentions it.

## 3.5.49 (alpha)
### Changed
- RXP Tracker, `<` at the first step of a guide: the previous zone guide now opens at its first step instead of its last step (or wherever you last were in it).

## 3.5.48 (alpha) — fourth optimization pass
Same priorities as before: per-frame and per-update CPU first, then memory, then leftovers. Nothing looks or works differently.

### Changed
- Less CPU in the RXP Tracker: each step line's item, spell and quest links are worked out once and again only when its text changes or item data arrives. Before, every line was worked out again on every update.
- Less CPU in the RXP Tracker header: the next guide is looked up once per guide and level instead of on every redraw. Redraws only check whether an earlier step exists, instead of finding which one the back button would pick.
- Less garbage: the waypoint arrow no longer builds a colour string every frame, and the step counter no longer builds a table and a string on every redraw.
- Less CPU in the quest tracker: the "Quests" header colouring does nothing on updates when no custom colour is set.

### Removed
- Leftovers from the removed skip switches and helpers that nothing uses anymore.

## 3.5.47 (alpha)
### Added
- `/qt`: the "Defaults" button has a tooltip. It names the section it resets and says that other sections, the tracker's position and your guide progress are not changed.

## 3.5.46 (alpha)
### Changed
- `/qt`: "Defaults" resets only the settings on the section you are viewing, not every setting in the addon. Other sections, the tracker's position, and your guide progress are left as they are.

### Fixed
- Resetting the RXP Tracker's "Own window" to its default now puts it back into the quest tracker, instead of only switching the setting off.

## 3.5.45 (alpha)
### Changed
- `/qt` → Themes & guide: "Restart this guide" and "Reset all guides" sit to the right of "Choose a guide..." and "Print status to chat", with their description below. A row of buttons now wraps onto a second line when the window is too narrow.

## 3.5.44 (alpha)
### Changed
- `/qt`: "Skip overleveled steps" and "Auto-skip steps" are removed. Those are RestedXP's own settings, so change them in RestedXP's settings. The chat line about passed steps and `/rt why` now name them there.
- `/qt`: "Restart this guide" and "Reset all guides" moved to Themes & guide, with the same description.

## 3.5.43 (alpha)
### Changed
- RXP Tracker, previous step (`<` and the back box): goes back to the nearest earlier step that RestedXP won't finish again on its own. It passes steps whose objectives are already done or skipped, or that RestedXP noted as skipped. If RestedXP still moves straight back to where you were, it goes one more step back, a few times at most.

## 3.5.42 (alpha)
### Added
- `/qt` → Tracker settings → Guide progress: "Restart this guide" starts the current guide again from its first step. "Reset all guides" clears your saved place in every guide for this character (RestedXP's own Reset Guide Progress, after a confirmation). RestedXP returns to your saved place whenever a guide loads, so a guide that once ran to its end keeps opening at its end until it is restarted. `/rt restart` does the same as "Restart this guide".

### Fixed
- RXP Tracker: a book's loose pages (for example [Green Hills of Stranglethorn - Pages]) show the tooltip of its first page.

## 3.5.41 (alpha)
### Changed
- `/rt why` now opens a window you can copy from (Ctrl+A, Ctrl+C) instead of printing to chat. It now logs every step RestedXP lands on or passes, with what it said about the step: marked done, needs a higher level, sticky, waiting on a required step, and each objective's state. It also logs the moment RestedXP decides a step is finished and which objectives made it so, and whether RestedXP or this addon made each move.

### Fixed
- RXP Tracker: common items guides tell you to buy by name only (healing and mana potions, food, water, arrows, a few reagents) now show their tooltip before the game has loaded them. Each is matched by its id only when the icon in front of the name is that item's icon.

## 3.5.40 (alpha)
### Added
- `/qt` → Tracker settings: "Auto-skip steps". This is RestedXP's own "Disable step skips", the other way round. While it is on, RestedXP passes steps by itself: quests you lack the prerequisites for, have already done, or aren't being offered. That can carry a guide straight to its end.
- When a guide you start has steps passed by RestedXP, one chat line counts them by reason (missing prerequisites, above your level, past its level, ...) and names the setting to change.
- `/rt why`: lists the latest guide and step moves, whether RestedXP or this addon made each one, why RestedXP passed steps in the current guide, and the state of both skip settings.
- "Steps shown ahead" and "Steps shown at once" go past 100 to "All". `/rt all` works too.
- `/qt`: the section list on the left has a thin scrollbar when it doesn't fit.

### Fixed
- RXP Tracker: items a guide names in the plural (for example [Superior Healing Potions]) now link to the item and show its tooltip.

### Changed
- Prerequisite Journal: everything under a quest's name is indented beneath it: its notes, its prerequisites, and their objectives.

## 3.5.39 (alpha)
### Added
- RXP Tracker: spells a step casts, uses or trains are now spell links, with the game's spell tooltip on hover. This works with or without brackets around the name.
- RXP Tracker: "Cast" steps start with one general spell icon. The spell's own icon now only appears once, next to its name.

### Fixed
- Item tooltips were missing on steps that use or withdraw items, for example [Hippogryph Muisek Vessel], [A Small Pack], [Draco-Incarcinatrix 900] and every item after the first in a bank list. Those steps' items were never read. Items the game hasn't loaded yet are now matched by the icon in front of their name.

## 3.5.38 (alpha)
### Added
- `/qt` → Tracker settings: "Skip overleveled steps", RestedXP's own setting. While it is on, RestedXP skips every step of a guide that is below your level as soon as the guide starts. That is why starting a lower-level zone guide can jump straight to its end.
- One chat line when a guide you start is skipped for this reason. It says how many steps were skipped and how to follow them anyway.

### Fixed
- The RXP Tracker no longer asks RestedXP for the next guide in a way that can load it. The header and the quest focus look-ahead now work out the next guide by reading only, so the tracker never moves to another guide on its own.

## 3.5.37 (alpha)
### Added
- `/qt` → Waypoint arrow, under Arrow scale:
  - "Custom arrow colour" with a colour picker for the arrow's body; off keeps the theme's colour.
  - "Arrow opacity" (10–100 %) for the arrow and its distance text.

## 3.5.36 (alpha)
### Added
- `/qt` → Waypoint arrow: "Arrow scale" slider (20–200 %). It is RestedXP's own Arrow Scale setting, so the two always
  match; the objective buttons around the arrow follow its size.

## 3.5.35 (alpha)
### Changed
- RXP Tracker item tooltips are more reliable:
  - The item's icon is part of the link, so hovering either the icon or the name shows the tooltip.
  - An item name the step lists no id for (such as [Hearthstone] in a hearth step) is looked up by name in the
    game's item data and linked when the game knows it.
  - Upcoming steps link their items and quests too, with the same tooltips.

## 3.5.34 (alpha)
### Added
- Prerequisite Journal: the Guides dropdown has a scrollbar when its list is longer than the box. Drag its thumb, or
  scroll with the mouse wheel as before.
### Fixed
- RXP Tracker: item tooltips now work. RestedXP writes items in its steps as plain text, not links, so there was
  nothing to hover.
  - The items a step handles (collect, use, buy, equip and the like) now become real item links in its text. Hovering
    one shows the item's tooltip, and shift-click links it in chat.
  - The quest an accept or turn-in step names becomes a quest link with the quest's tooltip.
  - Other bracketed names (such as mob abilities) carry no item or spell id in RestedXP's data and stay plain text.
- RXP Tracker: copy-link, start-a-guide, missing-prerequisites and level-skip lines work through the same kind of link.
  Hovering and clicking them no longer depends on the step lines taking the mouse, and the step's own clicks (right-click
  menu, Ctrl+right-click) are untouched. Tooltips are shown by this addon instead of being handed to RestedXP's hidden
  window, where they did not appear.

## 3.5.33 (alpha)
### Changed
- RXP Tracker: its collapse button now folds only the current step(s). The Upcoming Steps stay, with their own
  collapse button. The folded state is remembered.

## 3.5.32 (alpha)
### Fixed
- Folding the "Quests" section with its collapse button now also hides the quests listed below it from "List quests
  past the tracking limit" (More Quests), and shows them again when you unfold it.

## 3.5.31 (alpha)
### Changed
- RXP Tracker: a step skipped for your level now says "Steps skipped: XP requirements are exceeded" when you hover it
  (RestedXP's own wording was "Step skipped: XP requirements are not met").

## 3.5.30 (alpha)
### Added
- RXP Tracker:
  - A "click here" step that starts a guide (such as "CLICK HERE FOR THE 1-9 SKYBORNE GUIDE") now starts that guide
    when you left-click it. Hovering it says which guide.
  - An accept or turn-in step with missing prerequisites (RestedXP's error icon) lists the missing quests when you
    hover it. Left-clicking it opens the Prerequisite Journal.
  - A step RestedXP skipped for your level says so when you hover it.

## 3.5.29 (alpha)
### Added
- RXP Tracker: item, spell and other links in a step's text show their tooltip when you hover them (clicking one works
  as in chat).
- RXP Tracker: a "click here to copy the link" step opens a box with the address selected when you left-click it;
  press Ctrl+C to copy. Hovering it shows the address.

## 3.5.28 (alpha)
### Fixed
- `/qt` → Quest list → "Line under "Quests" header" now colours the line under "Quests  N/40" (the header's own art,
  whatever the client names it). It no longer colours the line between the RXP Tracker's last step and the quests
  (that was 3.5.26).
### Changed
- `/qt` → Tracker settings: "Steps shown at once" moved under "Steps shown ahead".
### Added
- Prerequisite Journal: an on/off switch left of `<` shows or hides the guides before your current one in the Guides
  list.

## 3.5.27 (alpha)
### Fixed
- Prerequisite Journal: the Guides dropdown now closes with the journal, instead of staying open after the journal was
  closed.

## 3.5.26 (alpha)
### Changed
- `/qt` → Tracker settings: "Shown at once" is now "Steps shown at once".
- `/qt` → Quest list:
  - "Line under "Quests"" is now "Line under "Quests" header", and it now also colours the gold line drawn between
    the RXP Tracker and the quests, which it missed before.
  - The quest count's opacity always applies; its colour still only with "Custom quest count colour" on.
  - "Visible height" is now "Extra length", moved above "Show scrollbar".
- `/qt` → Advanced: Extra width moved here from Quest list. Its note keeps "Extra width widens the tracker's frame"
  and warns to use the scale sliders instead and to turn on "Word wrap titles and objectives".
- "Word wrap titles and objectives" is on by default, and is switched on once for existing settings.
- The RXP Tracker's upcoming-steps scrollbar ("Only on mouseover") now fades away like the quest list's: shown while
  you hover or scroll, then fading out after 2 seconds.
- Prerequisite Journal: the Guides list shows only the list your current guide is in (Open World Guide or Dungeon
  Guide), not both. The next 2 guides after your current one are yellow, the 2 after those orange, and the rest red.

## 3.5.25 (alpha)
### Added
- `/qt` → Tracker settings:
  - A new "Current step(s)" section with scale, horizontal and vertical position sliders for the current step(s).
  - The same three sliders for the upcoming steps, above "Shown at once".
  - Step counter (N/total) in the RXP Tracker's header: on/off, its text size, and an optional custom colour.
- `/qt` → Quest list:
  - Quest count (N/40) on the "Quests" header: on/off (below "Usable quest items on the left"), its text size, and an
    optional custom colour. The settings note that a custom colour replaces the green/yellow/orange/red warning of how
    full your log is.
  - Colour with opacity for the "Quests" header text and its collapse button, and for the line under the header,
    above "Quests" header padding. "Game's header colours" restores the game's own.
### Changed
- Extra width no longer moves the RXP Tracker's divider lines (under "Upcoming Steps" and between steps); the RXP
  Tracker keeps the tracker's normal width.
- The RXP Tracker's upcoming-steps scrollbar sits in the same column as the quest list's scrollbar, so it never runs
  over the steps' text and lines up with it.
- `/qt`: the RXP Tracker pages are greyed out in the category list when RestedXP Guides is not installed, and Zone
  headers is greyed out while Track has no zone headers. Both still open.

## 3.5.24 (alpha)
### Fixed
- `/qt`: category list entries hidden in a short window now come back when you make the window taller again. The
  check ran before the list had its new height. It now runs when the list's own height changes, and once more on the
  next frame. The title's gold lines are fitted the same way.

## 3.5.23 (alpha)
### Fixed
- `/qt` settings window and Prerequisite Journal: dragging the resize corner no longer makes the window snap and jump
  around. The window keeps its top-left corner and follows the cursor while the button is held, staying within its
  minimum and maximum size; it stops when you let go.
- `/qt`: the title's gold lines and the category list's fit now also update while you resize the window (a later
  handler had been replacing them).

## 3.5.22 (alpha)
### Changed
- `/qt`: the grey version and command hint at the bottom now sits under the page, to the right of the category list,
  on one line (shortened with "..." if the window is narrow), so it no longer runs into the list.

## 3.5.21 (alpha)
### Fixed
- `/qt`: when the window is too short for the whole category list, the list no longer runs out of the window. It
  scrolls with the mouse wheel (no scrollbar), and a row that does not fit in full is hidden until it does. This is
  checked when the window is resized, scrolled or laid out again.

## 3.5.20 (alpha)
### Changed
- `/qt`: the window's Opacity slider moved again, to the left above the category list (above "Quest Tracker"), on
  the same line as the search box. The title's gold rules get their full length back.

## 3.5.19 (alpha)
### Fixed
- RXP Tracker: going back to a previous guide with `<` could make the RXP Tracker disappear (the first time that guide
  was loaded in a session) until the next step change. RestedXP had no steps ready yet for a guide it had only just
  loaded, and that empty list was kept. An empty list is no longer kept; the steps are read again shortly (for up to
  5 seconds) until they are there.
- The "Back to the previous guide" chat line and the `<` tooltip use the guide's display name (for example "41-41
  Swamp of Sorrows" instead of "41-400_41-41 Swamp of Sorrows").

## 3.5.18 (alpha)
### Changed
- `/qt`: the window's Opacity slider moved into the title bar, just left of the close button, as in the Prerequisite
  Journal. It was left of the search box. The title's gold rules shorten to make room, and hide when the window is
  narrow.

## 3.5.17 (alpha)
### Changed
- `/qt` window title: a larger two-tone "RXP ForeverTracker" wordmark (cream, gold and pale gold, with a shadow).
  RestedXP's logo sits before it, with a soft gold glow behind and fading gold rules with small diamonds on either
  side. A thin gold line runs under the title bar, in the window's bronze-and-gold Forever palette.

## 3.5.16 (alpha)
### Changed
- `/qt`: the "Tracking and sorting" page is now the last one under Quest Tracker (after Tooltips).

## 3.5.15 (alpha)
### Changed
- `/qt`: "Tracking and sorting" (Track, Sort zones, List quests past the tracking limit) is now its own page under
  Quest Tracker, right after Quest list, instead of a section at the bottom of Quest list.

## 3.5.14 (alpha)
### Fixed
- Prerequisite Journal: an error ("attempt to index local 'o' (a number value)") when a missing prerequisite quest
  had a reputation objective (for example quest 1368). Questie stores that objective as a single faction/amount pair,
  not a list; it now shows as "Earn reputation with <faction>". The other Questie objective readers skip unexpected
  shapes the same way instead of erroring.

## 3.5.13 (alpha)
### Fixed
- Extra width: raising it no longer leaves the drag bar and other parts of the tracker too wide after setting it back
  to 0 (until a /reload). The tracker had been taking its widened size as its normal size.
- "Quest tracker - drag to move" bar: the tracker now drops where you let go of the left mouse button, instead of
  staying stuck to the cursor until a second click.
- RXP Tracker own window: its drag bar moves the same way (follows the cursor while the button is held).
### Changed
- Extra width only widens the tracker's frame. It no longer widens quest text to keep it from being cut off; whether
  long text wraps or is cut off is now up to "Word wrap titles and objectives".
- Prerequisite Journal: a space before each coin icon in the reward totals.

## 3.5.12 (alpha)
### Changed
- Forever Style is now the default theme. It is listed first in `/qt` → Themes & guide. A new install, or Reset to
  defaults, starts in Forever Style. If you already picked RXP Style, it stays selected.

## 3.5.11 (alpha)
### Fixed
- A very long current step in the RXP Tracker no longer runs over the quest tracker. The quests and their "Quests"
  header are pushed down below the step's last line of text, even when the text wraps past its line, and however
  tall the step is. The quest list was previously held to the window's height less 100 px.

## 3.5.10 (alpha)
### Reverted
- The 3.5.9 change to how far the quests start below the RXP Tracker's upcoming steps (wrapped text measuring, and
  scrolling a too-tall RXP Tracker with the quests) is undone; this behaves as in 3.5.8 again. The Questie change
  from 3.5.9 stays.

## 3.5.9 (alpha)
### Fixed
- Long upcoming steps in the RXP Tracker no longer cover the quest tracker's "Quests" header. The quests now start
  below the last line of text, even when a step's text wraps past its line. When the RXP Tracker is taller than the
  window has room for, it scrolls with the quests instead of staying fixed on top, and goes back on top once it fits.
### Changed
- Quest tracker conflict prompt: when Questie's own tracker is on, the choice is now "Turn off Questie's tracker". It
  switches off only Questie's tracker (as Questie's own "Enable Tracker" option does), and the rest of Questie keeps
  working. Other tracker addons are still disabled as before.

## 3.5.8 (alpha)
### Added
- `/qt` → Tracker settings (renamed from "Guide in the tracker"): **Own window** takes the RXP Tracker out of the quest
  tracker into a window of its own. Drag the bar along its top to move it (it remembers where). The quests move up
  into the space it left, and make room again when it goes back. "Reset window position" puts it back beside the quest
  tracker. Switching is done out of combat.
- Scrollbar width sliders: `/qt` → Quest list (quest tracker scrollbar, 2–30 px) and Tracker settings → Upcoming
  steps (RXP Tracker scrollbar, 1–12 px).
### Changed
- Ready for RestedXP updates. Every part of RestedXP this addon uses is checked when it is used:
  - Only a few core parts are required. If a RestedXP update removes one, the guide display stays off with one chat
    line naming it, RestedXP's own windows are used, and the quest tracker works as usual.
  - Everything else (its hooks, helper functions, textures, translations, theme, colours and settings) falls back to
    the game's own or is skipped. `/rt status` lists anything this RestedXP version doesn't have.
  - If RestedXP's guide data changes so that drawing fails three times in a row, the guide display stands down for the
    session with one chat line instead of an error on every update. RestedXP's window takes over, and `/reload` or
    `/rt toggle` tries again.
  - The Prerequisite Journal finds the Dungeon Guide and Open World Guide groups by words in their names, and falls
    back to your current guide's own group if neither is found.

## 3.5.7 (alpha)
### Added
- `/qt` → Zone headers: "Zone header vertical position" slider (−20 to +40 px, up is +), under the horizontal one.
  It moves the zone header text, More Quests' zone headers included. "Space above zone headers" still sets the gap.

## 3.5.6 (alpha)
### Added
- `/qt` → Quest titles: "Quest titles horizontal position" slider (−20 to +150 px, like the zone header one). It moves
  quest titles and their objectives sideways, More Quests included. Zone headers stay where their own slider puts them.
### Changed
- Prerequisite Journal: `<` `>` and Guides sit at the right of the window, always in the same place, on the same line
  as the guide's name (a long name is cut short before them).
- The quest tracker no longer scrolls when the mouse is nearer the RXP Tracker than the quests. The scrollbar
  still always scrolls.
### Fixed
- RXP Tracker: going back to the previous guide with `<` showed that guide's finished steps as current steps, in a
  list that ignored the upcoming-steps limit. Only the step you are at shows now.

## 3.5.5 (alpha)
### Changed
- Prerequisite Journal: the Guides dropdown lists only RestedXP Forever's "Dungeon Guide" and "Open World Guide"
  groups (your faction's, only the guides RestedXP offers your character), each under its own heading, in level order.
- Prerequisite Journal: `<` `>` step through that list, so they no longer grey out while you jump from guide to guide.
  They grey out only at the first or last guide of the list. Before, they followed each guide's next-guide line, which
  often pointed at a guide that is not there for your character.

## 3.5.4 (alpha)
### Changed
- Prerequisite Journal: an earlier guide is labelled "(previous guide)" (was "(not your current guide)").

## 3.5.3 (alpha) — third optimization pass
### Changed
- Forever Style: at the first step of a guide, `<` no longer greys out when there is a guide before it: it goes back
  to that guide (where you left it), and its tooltip names it.
- Less CPU in the Prerequisite Journal: redraws for item data, fonts or resizing reuse the prerequisite plans instead
  of rebuilding them for every quest; whether `<` `>` lead to a guide is worked out once per guide; item-data events
  are only listened to while it is open. Accepting or turning in a quest while it is open now updates it.
- Less CPU in the RXP Tracker: the upcoming-steps scrollbar runs no per-frame check unless "Only on mouseover" is on;
  the Forever Style header doesn't set its name and step count again when they are unchanged.
- Dungeon sorting checks each Questie area once per dungeon visit instead of on every sort.
- Unused leftovers removed.

## 3.5.2 (alpha)
### Changed
- Forever Style: at the last step of a guide, `>` no longer greys out when there is a next guide: it starts that
  guide (RestedXP's own next-guide choice), and its tooltip names it.

## 3.5.1 (alpha)
### Changed
- The RXP Tracker's chat command is now `/rt` (was `/ao`), e.g. `/rt status`, `/rt toggle`.

## 3.5.0 (alpha) — Profiles, scrolling upcoming steps
### Added
- `/qt` > Settings Window > Profiles: save the current settings as a named profile, load (reloads the interface),
  save over, delete (not the active one), export as a copyable string and import one. Starts on "Default" the first
  time. Settings are kept in the active profile as they change; profiles are shared by your characters. Imported
  strings are only read as data, never run.
- RXP Tracker: upcoming steps show 2 at a time; scroll the mouse wheel over them for the rest (at either end the
  wheel scrolls the tracker), with a thin scrollbar. "Guide in the tracker" has a new Upcoming steps section: shown
  at once, scrollbar on/off, only on mouseover, scrollbar colour. "Steps shown ahead" goes up to 20 (was 8).
- Prerequisite Journal: a "Guides" dropdown beside `<` `>` lists the guide's group (RestedXP's guide menu order) to
  pick the guide shown.
- Prerequisite Journal: guides after your current one (later, higher level) are slightly greyed out, in the journal
  and in the Guides list; they can still be viewed.

## 3.4.6 (alpha)
### Changed
- Prerequisite Journal: the top line shows only the guide's name (no ", from step N"), followed by `<` `>` to browse
  the previous and next guide (RestedXP's own next-guide chain) and their missing prerequisites. Your RestedXP guide
  stays as it is; the name says "(current guide)" or "(not your current guide)", and each opening starts at yours.

## 3.4.5 (alpha)
### Changed
- `/qt` Text size: 80-125 % (was up to 160 %); a larger saved size counts as 125 %, here and in the Prerequisite
  Journal.
### Fixed
- `/qt` text running out of the window at large text sizes: the window's smallest size now grows with the text size
  (a smaller window is enlarged, within the screen), and the category list widens with it.

## 3.4.4 (alpha)
### Changed
- In a dungeon, with Questie: zones holding quests whose objectives are inside that dungeon (e.g. Westfall's Deadmines
  quests) come straight after the dungeon's own zone, with those quests first in their zone.

## 3.4.3 (alpha)
### Changed
- Closest-zone sorting in a dungeon (or raid, scenario): the dungeon's quests come first, under its zone header. The
  game gives no map position inside, so the other zones are ordered from where you were before you went in.

## 3.4.2 (alpha)
### Fixed
- `/qt` Text size slider still looping (3.4.1's fix waited for a mouse-down the game doesn't send when the thumb is
  grabbed). Now while the left button is held the size waits and applies on release, read from the button itself.
- Prerequisite Journal text growing on every redraw until it ran out of the window: each redraw scaled the already
  scaled size again. Sizes now always start from the game font's own size.

## 3.4.1 (alpha)
### Fixed
- `/qt` Text size slider jumping while dragged: it resized and moved itself under the cursor on every step. While the
  thumb is dragged only the percentage follows; the new size applies on release. Arrows, mouse wheel and typed values
  still apply at once.

## 3.4.0 (alpha)
### Added
- Prerequisite Journal: the reward items of each quest the guide wants and of its prerequisites, as icons after the
  experience and gold; hover an icon for the item's tooltip. The gold total now adds, for every quest, the vendor
  value of its best-selling reward item.

## 3.3.12 (alpha)
### Removed
- More quests: Alt-click to track a quest, and its line in the tooltip. A click still opens the quest in the quest log.

## 3.3.11 (alpha)
### Changed
- Prerequisite Journal: "Skipping it and these misses the experience and gold shown." is now its own line, below
  "Guide step N wants this quest. Do these first:".

## 3.3.10 (alpha)
### Changed
- More quests: Alt-click tracks a quest (when there is room), instead of Shift-click; the tooltip says so.

## 3.3.9 (alpha)
### Removed
- Forever Style: Shift-click on an upcoming step's `i` no longer jumps the guide to that step; the line is gone from the
  `i` and `?` tooltips. A Shift-click now does the same as a click (quest log or waypoint).

## 3.3.8 (alpha)
### Changed
- Forever Style `!` tooltip: title "RestedXP Guides" without the version; text "Left-click: Browse Guides".
- Journal book tooltip: "Requires Questie." (was "Uses Questie.").
- Forever Style `?` tooltip: the "Shift+right-click: /qt." line removed; the `i` line now says what a click does (the
  quest in the log, or a waypoint; Shift-click goes to the step).

## 3.3.7 (alpha)
### Added
- Forever Style: click the guide name in the header to open or close RestedXP's own guide window, as the logo does in
  RXP Style. Right-clicks on the name still open the guide menu (Shift: `/qt`, Ctrl: Prerequisite Journal).

## 3.3.6 (alpha)
### Changed
- `/qt`: the "Guide" page under RXP Tracker is now called "Themes & guide".

## 3.3.5 (alpha)
### Changed
- `/qt` Advanced: the Layer slider moved to the bottom of the page, under its own heading, with a warning to only
  change it if you know what you're doing.

## 3.3.4 (alpha)
### Changed
- Forever Style header: `!` (browse guides) and `?` (help, settings) moved to the left, before the journal book; in their
  place the step count, e.g. "4/73". Order now: ! ? book, guide name, 4/73, < > and the collapse button.

## 3.3.3 (alpha)
### Fixed
- Lua error spam at login (Core.lua:43 "attempt to call a nil value"), from 3.3.0's Quest Tracker opacity: a function
  was used above the line that defines it.

## 3.3.2 (alpha)
### Added
- Prerequisite Journal: an Opacity slider (10-100 %) just left of its close button; saved. The journal's title moved
  to the left of its title bar to make room.
### Changed
- `/qt` window Opacity slider now goes down to 10 % (was 30 %).

## 3.3.1 (alpha)
### Added
- `/qt`: an Opacity slider for the settings window itself (30-100 %, 10-100 % from 3.3.2), always just left of the Search box; saved.

## 3.3.0 (alpha)
### Added
- `/qt` Advanced: General opacity of the whole tracker (quests, RXP guide, header, background, scrollbar, More quests,
  step buttons; never the settings windows), with RXP Tracker opacity and Quest Tracker opacity under it. Each
  sub-slider multiplies the general one, like the two scales.
- `/qt` dropdowns with long lists (fonts): type to search; the first match is filled in with the rest highlighted,
  Enter picks it, Escape closes.
### Changed
- `/qt` on/off switches and colour swatches redrawn in high definition: a smooth anti-aliased circle shipped with the
  addon (was the game's 64 px mask), a thin edge around each switch, a soft shadow under the knob, a dark gap between
  a swatch's ring and its colour.
- `/qt` typed values (beside sliders): the dark box is always shown, so it reads as typeable; brighter on hover and
  while typing.
### Fixed
- `/qt` colour rows: the Opacity slider no longer overlaps the colour swatches.

## 3.2.6 (alpha)
### Changed
- `/qt`: "Visible height" and "Extra width" moved from Advanced to Quest list, below Scroll speed.
- `/qt`: "Advanced sizing" renamed "Advanced".
- Prerequisite Journal follows the `/qt` Text size and font (text, icons and buttons), also while open.
### Fixed
- `/qt` dropdowns with many choices (fonts) no longer run off the screen: the list is capped, scrolls with the mouse
  wheel, opens on the current choice, and opens upwards when there is no room below.

## 3.2.5 (alpha)
### Added
- Prerequisite Journal: beside each quest the guide wants, the total experience and gold you miss by skipping it and
  its prerequisites, shown as on your quest titles (experience orb or "xp", coins or g/s/c).

## 3.2.4 (alpha)
### Fixed
- The journal button shows a book: Forever's Adventure Guide (journal) button art, not the quest log's "!" scroll.

## 3.2.3 (alpha)
### Fixed
- The back-one-step box (`<` beside the first skip box) shows only in RXP Style; it no longer stays on screen after
  switching to Forever Style.

## 3.2.2 (alpha)
### Changed
- Prerequisite Journal: steps say what to do (Kill, Collect, Buy, Use, Earn reputation) and where, with an icon
  instead of a dash: `!` accept, `?` turn in, sword kill, bag buy, hand collect, cog use. Buy steps name the vendor
  and can be clicked for a waypoint.
- Prerequisite Journal: no scrollbar when everything fits.
- The journal button uses Forever's own quest log button art (the micro menu book).
### Fixed
- Forever Style: "Upcoming Steps" no longer draws over the guide name in the header.

## 3.2.1 (alpha)
### Added
- Journal book icon before the guide name (both styles) opens the Prerequisite Journal.
### Changed
- The missing prerequisites window is now called "Prerequisite Journal".

## 3.2.0 (alpha) — Prerequisite Journal
### Added
- Prerequisite Journal (Ctrl+right-click the RXP Tracker), in the `/qt` window's style: the quests still ahead
  in your guide that you can't accept yet because an earlier quest isn't done, and for each the quests to do first,
  earliest first, with accept / objectives / turn-in steps. Click a step with a pin for a waypoint. Needs Questie.
- Step action buttons: Ctrl+left-drag moves them, Ctrl+right-drag resizes them (out of combat).
  "Reset step buttons" on the Guide in the tracker page of `/qt`.
### Changed
- Forever Style header shows the guide's own name (e.g. "46-47 Feralas/Azshara") instead of its group
  ("Dungeon Guide").

## 3.1.2 (alpha)
### Changed
- Forever Style: the `i` beside an upcoming step opens that step's quest in the quest log when it is in your log
  (complete, then turn-in, then accept); otherwise it puts the game's map pin on the step's location and tracks it.
  Shift-click still goes to the step.
### Fixed
- Forever Style: "Upcoming Steps" no longer overlaps the first upcoming step's heading; "Step N" now sits under it.

## 3.1.1 (alpha)
### Fixed
- Lua error spam ("CreateTexture(): Couldn't find inherited node "0"") when turning on Forever Style.
- If the Upcoming Steps header ever fails to build, the error shows once and the divider line is used instead.

## 3.1.0 (alpha) — Forever Style
### Added
- New RXP Tracker theme "Forever Style", drawn like the game's own quest tracker: the guide name in a native section
  header with `!` (browse guides), `?` (left-click /qt, right-click RestedXP settings), `<` / `>` (back / next step)
  and the collapse button; each step headed "Step N"; the game's dashes on each line; an "Upcoming Steps" section
  header that folds away; an `i` beside each upcoming step that jumps to it.
- Theme dropdown on the Guide page in `/qt`: "RXP Style" (the original look, default) or "Forever Style".
### Notes
- Forever Style has no per-line skip boxes; use `>` to move on and `<` to go back.

## 3.0.10 (alpha)
### Added
- This changelog (`CHANGELOG.md`), shipped with the addon.

## 3.0.9 (alpha)
### Changed
- "Space around the trackers" now grows the background on every side, including left and down.

## 3.0.8 (alpha) — second optimization pass
### Changed
- More quests list is only redrawn when something it shows has changed.
- Quest titles are not re-set when their decorated text is unchanged.
- Party progress is sent only when it changes (plus once on party change or after a loading screen).
- The chosen font is re-applied at most once per frame.

## 3.0.7 (alpha)
### Changed
- The background no longer covers the usable quest item buttons; it starts just left of the zone titles.

## 3.0.6 (alpha)
### Fixed
- Quest tooltip no longer grows wider each time Ctrl is pressed and released.

## 3.0.5 (alpha) — performance pass
### Changed
- Less CPU: the `/qt debug` layout log only records for 60 s after `/qt debug`; content is measured once per frame;
  closest-quest re-sort only after you move 20+ yards; "Track all" stops early when the watch list is full.
- Less memory: the attunement check no longer builds Questie's full quest-name index.
- Removed unused code and duplicate attunement logic; README rewritten.

## 3.0.4 (alpha)
### Added
- Settings Window > Background page: background behind the trackers, colour with opacity, space around the trackers.
- Opacity slider on every colour picker.
- Party tooltips show each member's progress (e.g. "7/12", "done (12/12)"), from this addon or Questie's party sync.
### Changed
- Questie support is future-proof: no built-in quest lists, works with LibQuestieDB or Questie's own database module.
### Fixed
- Settings window hides its scrollbar on pages with nothing to scroll.
- Quest tooltip keeps its size when Ctrl shows the whole chain.
- Removed the transparent black outline around the settings window.

## 3.0.3 (alpha)
### Changed
- "RestedXP Tracker" renamed "RXP Tracker" in the settings window.

## 3.0.2 (alpha)
### Changed
- Cogwheel icon next to "Settings Window" (capital W).

## 3.0.1 (alpha)
### Changed
- RXPGuides is now optional; without it only the quest tracker runs.
### Removed
- Auctionator auction-house prices in tooltips.
- "(guide: /ao)" from the addon list description.

## 3.0.0 (alpha) — new settings window
### Changed
- `/qt` redesigned after WoW Forever's Options window: category sidebar, search box, page title with Defaults button,
  resizable window.
- On/off switches instead of checkboxes; colour swatches plus a custom colour picker.
- "Only quests in my zone" is now a choice in the Track picker.
- New pickers (`< value >` with a list) and sliders with typed values and mouse-wheel steps.

## 2.9.4 (alpha)
### Fixed
- "Icon size" scales only the title icons; titles and lines no longer move.
- A second attunement star could be added to tracked titles.

## 2.9.3 (alpha)
### Changed
- "Size and layering" renamed "Advanced sizing".
### Fixed
- Duplicate "Star on raid attunement quests" setting merged into one.
- Lua error (MoreQuests.lua:334) when turning on More quests.

## 2.9.2 (alpha)
### Fixed
- Closest-quest sorting: the nearest quest or objective is now at the top (per-quest distance from Questie, the game,
  or waypoints; re-checked as you move).

## 2.9.1 (alpha)
### Changed
- "Chain ends with" shows only while Ctrl is held.
- Smoother scrolling in the settings window.

## 2.9.0 (alpha)
### Added
- Star on raid attunement quests (Questie data).
### Changed
- Settings window text no longer gets cut off.
- Shift+right-click on the RXP tracker opens the Quest Tracker page.

## 2.8.1 (alpha)
### Changed
- "Chain total" shows only while Ctrl is held.

## 2.8.0 (alpha) — Questie chains
### Added
- Tooltip follow-up quest and chain position; whole chain while Ctrl is held.
- Chain's final reward and total experience and gold.

## 2.7.0 (alpha) — Questie integration
### Added
- Optional Questie data: quest giver, turn-in and objective locations, quest chain in tooltips; better zone sorting.

## 2.6.4 (alpha)
### Fixed
- Coin spacing in tooltips.

## 2.6.3 (alpha)
### Changed
- "Quests" header padding goes down to -50 px.

## 2.6.2 (alpha)
### Fixed
- Font choice now applies to quest titles and objectives too.

## 2.6.1 (alpha)
### Fixed
- Lua error (MoreQuests.lua:387 SetFont) at login.

## 2.6.0 (alpha)
### Added
- xp/gold after More quests titles; experience orb icon in tooltips.
- "Step X of Y" beside the guide name.
- Quest log count (n/40, coloured) next to the Quests header.
- Scrollbar colour; zone sort choice (alphabetical or closest).
- Prompt when another quest tracker addon is detected.
- Font choice for trackers and settings window; Quests header padding slider.
- RestedXP logo on the guide tab.
### Changed
- More quests blends into the tracker (no heading); minimap button option moved under Settings window.
### Removed
- "Quest list: only this guide's turn-ins".

## 2.5.3 (alpha)
### Changed
- First use places the tracker in the middle of the screen.

## 2.5.2 (alpha)
### Fixed
- "Reset position" no longer loops.

## 2.5.1 (alpha)
### Added
- Shift+right-click on the RXP tracker opens `/qt`.

## 2.5.0 (alpha)
### Added
- Tooltips on More quests; coin icons option in tooltips; closest-zone-first sorting.

## 2.4.1 (alpha)
### Fixed
- More quests drawn after the last tracked quest; scrolling reaches the last quest.

## 2.4.0 (alpha)
### Added
- More quests: lists quests beyond the game's watch limit.

## 2.3.1 (alpha)
### Added
- Divider between the last guide step and the Quests header; quests never scroll over the last step.

## 2.3.0 (alpha)
### Added
- Separate scale sliders for the RXP Tracker and the Quest Tracker.

## 2.2.7 (alpha)
### Fixed
- Duplicate xp on quest titles when hovering quests in the world map list.

## 2.2.6 (alpha)
### Changed
- `/qt` or `/qtrxp` in the login message; Settings window section first.
### Fixed
- Duplicate xp/gold on titles when hovering other quests.

## 2.2.5 (alpha)
### Changed
- Guide right-click menu opens beside the tracker so it doesn't cover the steps.

## 2.2.4 (alpha)
### Changed
- Guide tab renamed "RestedXP Tracker"; command lines removed from its options.

## 2.2.3 (alpha)
### Fixed
- Repeated "moved back" chat messages after `/reload`.

## 2.2.2 (alpha)
### Fixed
- Tracker could end up off screen.

## 2.2.1 (alpha)
### Fixed
- No auction-house values or calls without Auctionator.

## 2.2.0 (alpha)
### Added
- Right-click the guide in the tracker to change guides.

## 2.1.0 (alpha)
### Added
- Renamed to RXP ForeverTracker; settings window with tabs; back-a-step arrow on the guide; auction-house values
  (removed in 3.0.1).

## 2.0.0 (alpha) — merge
### Added
- The RestedXP guide display and the scrollable quest tracker combined into one addon.

## 0.1 – 0.8 (alpha)
- Mouse-wheel scrolling of the default quest tracker with the RestedXP guide steps kept on top.
- Settings window, minimap button, scale/height/scroll speed sliders, lock, scrollbar.
- Sort by zone with zone headers; combat-safe; off-screen clamping fix.
- Native Forever look for the settings window.
