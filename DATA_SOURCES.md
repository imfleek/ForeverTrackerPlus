# Data sources (dev only, not in the zip)

Addons and files this addon takes data or ideas from. Use it for the "check my addons for updates" job:
compare the version in each addon's `.toc` (`## Version:`) with the "Checked" column, then look at what changed.

Addons folder: `D:\BattleNet\World of Warcraft\_forever_\Interface\AddOns`

## Copied facts (our own list in our code; re-check when the addon updates)

| Addon | Checked | What we took | Where in our code | License |
|---|---|---|---|---|
| Library Books (Taraezor) | 4.08 (2026-11-27) | Book quests, places, hints, librarians, friend quests | `Tracker/Guides.lua` BOOKS, BOOKS_60, BOOKS_NOT_IN_GAME, LIBRARIANS | facts only |
| ForeverSecrets | 1.1.68 (2026-11-27) | Secrets steps and spots (Cozy Sleeping Bag chain), book spots | `Tracker/Guides.lua` SECRETS; our book list has all 22 of its books + 18 more | no license: facts only |
| SecretChecklist | 2.2.2 (2026-11-27) | The Forever secrets list, ideas (TomTom arrow) | `Tracker/Guides.lua` SECRETS | facts and ideas only |
| Capping | v12.1.17 (2026-11-27) | Battleground timer facts (start, captures, respawns), which icon goes with which bar | `Tracker/Own/Battleground.lua` | no license, no API: facts only |

## Game files (re-run the script after playing in new areas)

| Source | What | How |
|---|---|---|
| `_forever_\Cache\WDB\enUS\gameobjectcache.wdb` | Objects the game has seen, with display ids (1,146 on 2026-11-27) | `python -I tests/make_object_models.py` (keeps the current list, adds new ones) |
| Game CASC files (GameObjectDisplayInfo) | Display id -> model file | `tests/casc_read.py`, used by the script above |
| CMaNGOS classic-db dump (GPL-3.0) | 10,565 object display ids | kept at `C:\Users\Dawson\Desktop\claude stuff\CMaNGOS\ClassicDB_1_12_1_z2815.sql.gz` (github.com/cmangos/classic-db, Full_DB); the script uses the newest file there |

## Read live in game (an update can break us: check these names still exist)

| Addon | Checked | Names we read | Where |
|---|---|---|---|
| QuestieDB / Questie | QuestieDB 1.1.6 | `LibQuestieDB`, `QuestieLoader`, `Questie.db` | `Tracker/Questie.lua`, `Tracker/NpcPanel.lua` |
| RXPGuides (RestedXP) | v4.11.40 | `RXP`, `RXPData.questNames`, `RXPCData.questNameCache`, guide elements (`questId`, `title`, `text`, `tag`) | `Objectives/rxp/*`, `Objectives/tracker/Rows.lua` |
| ForeverDungeonJournal | 2.1.7 | `ForeverDungeonJournal_NS.UpdateRunTracker`, `ForeverDungeonJournalRunTracker`, `...BossTarget`, `...RareTarget`, `...CharacterDB`, `ForeverDungeonJournal_OnAddonCompartmentClick` | `Tracker/Dungeon.lua` |
| OneForAll | 6.3.0 | `OneForAllDB` (reward coin clash) | `Tracker/Helpers.lua` |
| EllesmereUI | 9.9.6 | `EllesmereUI`, `EllesmereUIDB` (clashes, quest tracker) | `Tracker/Helpers.lua`, `Tracker/Conflicts.lua` |
| OpenMap (MIT) | v0.8.13 | `OpenMapAPI.IsStitched`, `.WorldFromMap`, `.MapFromWorld`, `.ArtTopLevel`, callback `OpenMap_StitchedChanged` | `Tracker/Journal.lua` (path dots) |
| Blizzard_LegacySystem | client | `LegacyChallengeTemplateMixin.Init` | `Tracker/Own/Legacy.lua` |
| Blizzard_GroupFinder_VanillaStyle | client | `LFGVanilla_ShowFrame`, `LFGListingFrame` (Blizzard's own, not "LFG - How It Should Be") | `Tracker/GroupFinder.lua` |

Quick check of the live names (Git Bash, from the AddOns folder):

    grep -rl "UpdateRunTracker" ForeverDungeonJournal

## No longer read (2026-11-27, user)

NovaInstanceTracker (we count instances ourselves; limit 5 an hour), LegacyForever (zone areas from the game's Explore achievement).

## Ideas only (no data taken)

RareScanner (rares near quests), Questline (GPL-3.0: ideas only), WaypointUI (time to arrive; the world marker's look: size by distance, pop in, hover fade, beam), Guildy (the level-up banner's idea: a dark band, gold hairlines growing out of a seal, texts rising in; drawn our own way in `Tracker/LevelBanner.lua`) and TomTom (time to arrive),
NovaInstanceTracker (hourly instance cap), DungeonJournal (dungeon card look).
3.2 ideas: SpecBisTooltip (All rights reserved: only read live from the item tooltip it fills, nothing copied; `Tracker/DungeonLoot.lua`), DungeonJournal (loot lists and favourites, read live), BugSack / !BugGrabber (our errors for the bug report, read live), Details and NovaInstanceTracker (the run summary's idea), Leatrix Plus and EllesmereUI (how they hook the quest log: QuestLogQuests_Update).
Animation ideas (3.2, `Tracker/Animations.lua`, our own code): BigWigs (screen edge flash: failed quest), EllesmereUI (pulsing dot: the card's run light; chat tab flash: the What's new glow), Details (new record popup: NEW BEST on the card).

## Looked at, not used yet (2026-11-27)

| Addon | License | Could give us |
|---|---|---|
| NpcAbilities 0.1.1 | All rights reserved | NPC abilities; we could read it live when loaded (not copy) for the 3D model panel |
| GatherLite 8.4.18 | MIT | **Not useful** (checked 2026-11-27): only herb / ore node object ids and spawns (`scripts/nodes.lua`, `plugins/database`). Herb and ore items already match their node by name; it has no quest objects (e.g. Cattail). Do not check again unless it adds quest objects |
| SkillUpForever 1.15.3 | GPL-3.0 | Recipe skill-up colours: ideas only |
| CozyFire 0.10.5 | none | Campfire spots: idea for Rekindle / cooking steps |
| SpecBisTooltip 1.2.3 | All rights reserved | Best specs per dungeon: idea only |
| LayerSwap | All rights reserved | Quests header button (`Tracker/LayerSwapButton.lua`): only calls its public LayerSwap_SwapKey() and its /ls on and /ls off, reads its Swap layer button text, its mini bar text, its saved Host setting (LayerSwapDB.hosting), and makes its mini bar invisible (alpha and mouse only) and shows its logo from its own folder at runtime; no code or textures copied |
| LayerSwap Stealth 1.0.5 | No licence file | Idea only: it showed that LayerSwap's Host is LayerSwapDB.hosting and /ls on / off; nothing read or called from it |
