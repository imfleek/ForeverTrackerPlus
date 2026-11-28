# Plan: our own tracker (branch `dev-own-tracker`)

## Why

- Error in instances: "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'ForeverTrackerPlus'".
- Cause: we move, size, scale and re-parent Blizzard's `ObjectiveTrackerFrame` and write fields on its modules
  (`fromBlockOffsetY`, `blockOffsetX`, `fromHeaderOffsetY`, `lineWidth`, `blockWidth`). Blizzard's next layout reads
  those values, runs tainted, reaches the scenario module (`ShouldShowMawBuffs`), and the game blocks the aura read.
- Two fixes (no forced re-layout in instances, no geometry writes in instances) did not stop it. They broke the look.
- What other addons do (EllesmereUI Quest Tracker custom mode, Questie): draw their own list in their own frame,
  make Blizzard's tracker invisible (`SetAlpha(0)`, mouse off), and only READ quest data.

## The rule for the new tracker

Never on Blizzard's tracker or its modules, blocks, headers:

- no `SetPoint`, `ClearAllPoints`, `SetSize`, `SetHeight`, `SetWidth`, `SetScale`, `SetParent` (also not the `Base` versions)
- no field writes, no method replacement
- no `Update`, `MarkDirty` (also not through `securecallfunction`)
- allowed: `SetAlpha` and mouse off (Questie and EllesmereUI do this), `hooksecurefunc` that only reads

A test (`tests/own_tracker_rules_test.lua`) scans the source for these calls on Blizzard's names.

## Decisions (made)

1. **Dungeon, battleground and scenario objectives: we draw them in our list** (user, 2026-11-26: "Hide Blizzard's
   section and put it in our list"). Blizzard's tracker is always invisible (alpha 0, mouse off). WoW Forever has
   no scenarios (user, 2026-11-26): its instance section is our dungeon card (Tracker/Dungeon.lua), so that goes in
   our frame. The scenario rows built first (C_ScenarioInfo) were removed.
   **Every section Blizzard's tracker has in WoW Forever is in our list** (user, 2026-11-26): bonus objectives,
   world quests, tracked achievements, monthly activities, and any other. Phase 5 starts with a check in game of
   which sections Forever's tracker has.
   **Battleground widgets are an option** (user, 2026-11-26): "Show battleground scores" draws flags, bases and
   capture timers in our list, from `C_UIWidgetManager` (read only). Off: the top-of-screen widgets still show.
2. **The old tracker stays as a permanent setting.** It steps aside in instances: Blizzard's tracker is Blizzard's
   there, ours hides, and it comes back when you leave (done in 3.2, `Tracker/Core.lua` stepAside / takeBack).
3. **Opt-in beta first** (user, 2026-11-26). The new tracker ships in 3.x as an opt-in setting. Classic stays the
   default. The new tracker becomes the default in 4.0, after players test it.
4. **Same look as now** (user, 2026-11-26). Copy Blizzard's look: fonts, spacing, headers, colours. Players see no
   change. The current style settings keep working on the new tracker.
5. **First in-game test: quests and the guide only** (user, 2026-11-26). Quest rows, clicks, item buttons and the
   RestedXP guide section. The other sections come after.

## Phases

Each phase ends with tests passing, the dev zip rebuilt, and an in-game check by you.

### 0. Spike (small, proves the idea) - built 2026-11-26. dev-27: the error came back on entering a battleground (user): Core trackerRelayout (called by Fonts, Extras, ZoneSort) marked Blizzard's tracker dirty from our code; now it does nothing with our own tracker, and Fonts.lua leaves Blizzard's rows alone (dev-28). In game: no error in a battleground or a dungeon (user; the error was only ever in battlegrounds). The error came back in phase 2 from Hide() on Blizzard's tracker; now opacity 0 and mouse off, never Hide (dev-14): no error on /reload inside a battleground or on entering one (user).
- New `Tracker/Own/Frame.lua`: our frame with a `ScrollFrame`, at the ghost's place (Core's position, drag, lock).
- Blizzard's tracker: alpha 0, mouse off. Hook `SetAlpha` to keep it 0.
- A plain list: watched quest titles and objectives from `C_QuestLog`.
- Check in game: a battleground and a dungeon with the taint log on. No error = go on.

### 1. Data (read only) - built 2026-11-26 (Tracker/Own/Data.lua), Checked in game 2026-11-27 (user: good)
- Quest list: watched quests, and all quests for "Track all quests" (no watch-list cap: More quests merges in).
- Per quest: title, level, colour, objectives, progress, complete, zone, campaign, type (classifier from Extras).
- Zone groups and sort (ZoneSort's grouping and orders, closest-3 distance), filters, track mode.
- Events: `QUEST_LOG_UPDATE`, `QUEST_WATCH_LIST_CHANGED`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, `UNIT_QUEST_LOG_CHANGED`,
  zone events, `SUPER_TRACKING_CHANGED`. One throttled rebuild per frame.

### 2. Frame and layout - built 2026-11-26 (Tracker/Own/Look.lua, Frame.lua), Checked in game 2026-11-27 (user: good). The guide strip comes with phase 4.
- Header strip ("All Objectives", collapse), the guide strip, scrollbar (width, mouseover, side), scroll wheel.
- Size, scale, Quest Tracker scale, layer, opacity, combat and raid fade, width extra, spacing and padding sliders
  (now our own numbers, not Blizzard fields).
- Fonts (Fonts.lua applies to our font objects, not Blizzard's).

### 3. Quest rows - built 2026-11-26 (Frame.lua rows, Tracker/Own/Rows.lua clicks and item buttons), Checked in game 2026-11-27 (user: good). Party progress is in the quest tooltip (as on the classic tracker).
- Title (level, colour, outline, title X), objectives (dash, colours, word wrap, condense), progress bars.
- Icons and classifiers, complete check, rewards (XP, gold, items), distance text and arrow, party progress.
- Tooltips, left and right clicks (focus, map, menu, share, Wowhead, reward links, group finder).
- Quest item buttons: secure, pooled, combat-safe (reuse More quests' buttons).
- Watch out: opening the map or quest menu from addon code taints (EllesmereUI uses a secure overlay button).

### 4. Guide section (AllObjectives RXP) - built 2026-11-26: the guide module in our frame's guide slot (Frame.lua api.ownGuideHost), Tracker.lua placeOwn, Header.lua buttons on our header. It shows in battlegrounds and arenas too (user). In game (dev-19): no error in a battleground with the guide shown (user).
- `Objectives/tracker/Tracker.lua` places its module as a proxy inside Blizzard's list. Move it into our frame.
  Rows.lua, Header.lua and SkipBox.lua mostly draw their own frames already.

**First in-game test (beta 1) is here: phases 0 to 4.**

### 4b. Instance section: the dungeon card in our frame - built 2026-11-26 (Frame.lua card slot api.ownCardHost; Dungeon.lua reads our slot and Quests header), waits for the in-game check.
- WoW Forever has no scenarios (user, 2026-11-26), so no scenario rows (built first, then removed).
- The dungeon card (Tracker/Dungeon.lua: name, party, deaths, DungeonJournal's run tracker, splits, party quests,
  boss abilities) gets its own slot in our frame, at the top, as on the classic tracker.
- Check in game: a dungeon and a raid with the taint log on. No error = go on.

### 5. Other sections
- Step 1 - built 2026-11-26: the reputation bar and the reminders row in the top slot under the dungeon card; `/qt sections` lists Blizzard's sections in the client and what they hold (the in-game check). Checked in game 2026-11-27 (user: good).
- Step 2 - built 2026-11-26: the Professions section (tracked recipes and reagents, Tracker/Own/Recipes.lua) in its own block above the Quests header (user). Checked in game 2026-11-27 (user: good).
- `/qt sections` (user, 2026-11-27): all 11 of Blizzard's sections exist in Forever; only Quests holds anything. Forever has Legacy Challenges, not achievements, and no way to track them.
- Step 4 - built 2026-11-27: a Battlegrounds block with our own timer bars (Tracker/Own/Battleground.lua): start, node captures, flag respawn; `/qt bg`. Facts from Capping (no license, no API), our own code. Then (user's picks): queues, score estimate, time left, flag carriers, warnings on our nodes. Checked in game 2026-11-27 (user: good).
- Step 3 - built 2026-11-27: Legacy Challenges tracked from the Guides > Legacy page (Tracker/Own/Legacy.lua, our own list), in their own block under Professions. Checked in game 2026-11-27 (user: good).
- Blizzard's sections, drawn by us: bonus objectives, world quests, tracked achievements, monthly activities, and
  any other section Forever's tracker has. Then the "Show battleground scores" option (flags, bases, capture timers).
- Our sections: More quests (merged into the main list), Professions, Achievements, Reputation, Rares, Reminders,
  Chains, Orphans, NPC panel, Instance cap. Each now anchors to our frame.
- Step 5 - built 2026-11-27 (user: "Yes, start"): the rest of our sections. Rares' tag and Chains' "Explored 7/12"
  find our zone headers (Frame.lua api.ownZoneLabelFor, asked by ZoneSort.lua api.zoneLabelFor; both tags redrawn
  after each rebuild); the rare tag sits at our list's right edge; the NPC panel opens beside our frame. Orphans is a
  settings page (nothing in the tracker); Instance cap is a line on the dungeon card (already in our frame);
  Achievements: Forever has none (Legacy Challenges, step 3). Waits for the in-game check.

### 6. Switch over
- A setting picks the tracker: "Classic" (default in 3.x: Blizzard's tracker in our scroll window, as now, stepping
  aside in instances) or "Our own tracker (beta)". In 4.0 "Our own tracker" becomes the default. With Our own, Core's scroll and hook code, Extras' block hooks, ZoneSort's
  block decoration and Fonts' Blizzard re-layout do not load; switching needs a /reload.
- Settings: keep the same db keys where they mean the same; migrate the rest once.
- Update tests (many read Core's old code), REQUIREMENTS.md, CHANGELOG.md, CURSEFORGE.md.
- Version: the beta ships in a 3.x release; the default switch is 4.0.
- Built 2026-11-27 (user: "Start phase 6"): the switch was already there (Settings > Main, a reload; with our own
  tracker Core never takes Blizzard's tracker and whenTrackerFree never runs, so Extras', ZoneSort's and Fonts'
  hooks never go on it). Settings: the same db keys; nothing to migrate. The "Quests" header colours
  (questsHeaderColor, questsLineColor) colour our Quests header (Frame.lua headerLook, Extras.lua
  applyQuestsHeaderLook hands over). Greyed with our own tracker (Config.lua classicOnly): Keep the Quests header at
  the top (ours always is), Professions beside the quest tracker and its position and scrollbar (ours has its own
  section), List quests past the tracking limit (ours lists every quest). CURSEFORGE.md and CHANGELOG.md say so.
  Left for 4.0: our own tracker becomes the default. Waits for the in-game check.
- Done in 3.2 (user: "Make our tracker the default, and only tracker"): our own tracker is always on, the switch and
  the classic-only settings are gone. The classic window's code (Core's scroll window, MoreQuests, the Professions
  box, the pinned header, the battleground reload) stays but never runs. Waits for the in-game check.
- Done in 3.2 (user: "Delete the old tracker's code"): the classic window's code was removed. Tracker/QuestClicks.lua
  keeps the quest clicks and menu from MoreQuests. Kept: ZoneSort's watch-list sort, Dungeon.lua's Quests header art
  copy, Core's empty setters (our frame redraws after them). A backup of the old addon: ForeverTrackerPlusBU in the
  AddOns folder. Waits for the in-game check.

## Risks

- Size: Core, Extras, ZoneSort and Fonts (about 6000 lines) lean on Blizzard's tracker. Most of it is rewritten.
- Other addons that skin Blizzard's tracker (EllesmereUI) will skin an invisible frame. Fine, but say it.
- Blizzard's tracker still runs its own layout while invisible. It is never tainted by us, so no error.
- Performance: we rebuild on quest events. Pool frames; throttle; no work while hidden.
