<div align="center">

# 🧭 ForeverTrackerPlus

**A scrollable, smarter quest tracker for WoW Forever, with your RestedXP guide built right in.**

[![Latest release](https://img.shields.io/github/v/release/imfleek/ForeverTrackerPlus?label=release&color=c9a24a)](https://github.com/imfleek/ForeverTrackerPlus/releases/latest)
![WoW Forever](https://img.shields.io/badge/WoW_Forever-16001-8b1a10)
[![License: MIT](https://img.shields.io/badge/license-MIT-4c7a3d)](LICENSE)

</div>

---

## 📦 How to Install

1. Download **`ForeverTrackerPlus.zip`** from the [latest release](https://github.com/imfleek/ForeverTrackerPlus/releases/latest) or from [CurseForge](https://www.curseforge.com/wow/addons/forevertrackerplus).
2. Extract the `ForeverTrackerPlus` folder into:

   ```
   BattleNet/World of Warcraft/_forever_/Interface/AddOns/
   ```

3. Log in. A short **first-time setup** walks you through every feature, with an on/off switch for each.

## ✨ What's new in 3.2

- 🧭 **Our own tracker**: a new tracker in its own frame, now the only one. Blizzard's tracker is hidden and never touched, so no more "secret auras" errors in instances.
- 🎯 **Big quest item button**: near the place your closest tracked quest's item is used, a big button with it shows at the bottom middle. Ctrl+right-drag moves it.
- ✨ **Animations**: finished objectives flash, quests slide in and fade out, bars grow, a level-up banner, and more. Each one has its own switch.
- 🏰 **Dungeons**: boss splits, a run summary with **Copy for Discord**, your party's quests, a share button and loot you want.
- 👻 **Corpse run helper**: an arrow to your corpse, the yards and when you can come back.
- 🔀 **LayerSwap button** on the Quests header (with LayerSwap installed).
- 🎓 **Reminders**: new trainer spells and unspent talent points.
- 🎁 **Better rewards**: an upgrade arrow, a disenchant icon and an optional auto pick.
- 🔇 **One switch for all sounds**, and less lag.

**Also new in 3.1:** quest item bar, big progress messages, a world marker and Guides. **Since 3.0:** a new settings window and statistics.


See the [changelog](CHANGELOG.md) for everything.

## 🌟 Features

### Quest tracker
- 🖱️ **Our own scrollable tracker**, with an optional scrollbar. Long quest lists never run off the screen. Blizzard's tracker stays hidden.
- 🗺️ **Zone sorting**: quests under zone headers, the closest quest first. Distance arrows on each quest.
- 💰 **Rewards at a glance**: experience and gold after each title, progress bars, a check on finished quests, and tooltips with objectives and rewards.
- 🏷️ **Icons**: elite, group, dungeon, raid, PvP and new-in-Forever quests.
- 🧊 **3D model panel**: hover an objective that names an NPC or object to see its model.
- 🏰 **Dungeon card**: in a dungeon or raid, its name, party, deaths, instances this hour, your lockout, boss splits and your party's quests. A run summary when you leave.
- ⛔ **Dead-end alert**: a cross on a grey quest that leads nowhere and gives nothing you need.
- 🏳️ **Battleground timers**, Professions, Legacy Challenges and the reputation bar in the tracker.
- ⭐ **Rares near your quests** on the zone header, with distance and a waypoint.
- 👥 **Find a group**: Ctrl+click a quest to post LFM or list it in Looking For Group.
- 🔗 **Wowhead link**: right-click a quest for its WoW Forever Wowhead URL.

### Helpers
- 🎒 Quest item bar, and quest items marked in your bags (with a warning if you sell or delete one).
- 🎯 **Big quest item button** at the bottom middle, near the place the item is used. Ctrl+right-drag moves it.
- 👻 Corpse run helper, ⬆️ level-up banner, and reminders for trainer spells and talent points.
- 🔀 LayerSwap button on the Quests header (with LayerSwap installed).
- 🪙 A gold coin on the quest reward that sells for the most.
- 📍 World marker, and an option to track the nearest quest by itself.
- 📣 Big progress messages, and optional party chat lines.
- 🔎 A card when a quest you can take is close by (Questie). Breadcrumb quests you do not need are left out.
- 🤝 **Talking to NPCs** (off until you turn it on): accept quests, turn in finished ones, skip a one-option chat. Hold Shift to pause it.
- 🫧 Breath warning, and ✈️ flight times for every route (from the game's own flight path data).

### Guides
- 🏆 **Legacy Challenges**: every challenge, with what is still to do.
- 📖 **Library books**: done, in your bags or open; click for a waypoint (Questie).
- 🛏️ **Cozy Sleeping Bag** chain, from level 14; click a step for a waypoint.
- 🔍 **Secrets**: hidden toys, quests and mysteries, step by step.
- 📜 **Attunements, class quests and profession quests**.

### Statistics
- 📊 **Overview**: quests done, experience from quests, quest times, quests per hour, top zones.
- ⏱️ **Run analysis**: where your time went (combat, running, mounted, flying, NPCs, dead, AFK, standing) and time per level.
- 📈 **Level splits**: time per level from /played, compared with another character.
- 💬 **Copy for Discord**, and a level-up line in chat.
- 👥 **Any character**: pick a character on your account, or add up all of them. Periods: this session, last session, week, month or all-time.

### RestedXP guide (needs RestedXP Guides)
- 📜 The current and upcoming steps in the tracker, with click-to-use item and spell buttons, a waypoint arrow, and back / restart / forward buttons.
- 📖 **Prerequisite Journal** (with Questie): the prerequisites you are missing for quests ahead in your guide.
- ❓ **"Why did guide skip?"** (`/ftp why`): every guide and step move, who made it and why.
- 🧹 **Orphaned quest cleanup**: quests your guide no longer uses.

> **Optional addons:**
> - **RestedXP Guides**: guide steps in the tracker
> - **Questie**: quest locations, chains, party progress, closest-quest sorting, nearby quests, library books, the sleeping bag chain
> - **DungeonJournal**: extra lines on the dungeon card

## ⚙️ Settings: `/ftp`

| Group | Sections |
| --- | --- |
| **General** | Basics (lock, minimap button, run the setup again) · Look (text, size, background) |
| **Quests** | Quest list · Quest lines · Tracking · Helpers (quest helpers, on screen, world) · Guides (Legacy Challenges, library books, sleeping bag) |
| **RestedXP** | Guide · Arrow |
| **Statistics** | Overview · Run analysis · Level splits |
| **Addon** | Profiles (save, load, import, export) |

> 💡 **Tips**
> - The search box finds any setting.
> - Each section has tabs at the top; cards fold open and closed.
> - **Shift+right-click** the guide in the tracker to open this window; **right-click** opens the guide menu.
> - Set the quest item keys in **Key Bindings > AddOns > ForeverTrackerPlus**.
> - **GENERAL > Animations** turns each animation on or off. **Basics > Main > Sounds** mutes every sound.

## Commands

<details>
<summary><b>Show all commands</b></summary>

Type `/ftp help` in game for this list.

### Quest tracker

| Command | What it does |
| --- | --- |
| `/ftp` | Opens or closes the settings window. |
| `/ftp config` | The same as `/ftp`. |
| `/ftp setup` | Opens the first-time setup again. |
| `/ftp stats` | Opens the statistics overview. |
| `/ftp run` | Opens the run analysis. |
| `/ftp guide` | Opens the settings window at the guide (RestedXP) settings. |
| `/ftp quests` | Opens the settings window at the quest tracker settings. |
| `/ftp orphan` | Opens the settings window at Orphaned quests. |
| `/ftp height <px>` | Sets how tall the quest list is (`0` = automatic). |
| `/ftp scale <0.5-1.5>` | Sets the tracker's size. |
| `/ftp step <px>` | Sets how far one turn of the mouse wheel scrolls. |
| `/ftp zone` | Turns sorting quests by zone on or off. |
| `/ftp sort` | Sorts the quests now. |
| `/ftp lock` | Locks the tracker in place. |
| `/ftp unlock` | Unlocks the tracker so you can drag it. |
| `/ftp distance` | Tells why a quest shows or hides its distance arrow. |
| `/ftp bags` | Shows what the quest marks in your bags see (open your bags first). |
| `/ftp reset` | Scrolls the tracker back to the top. |
| `/ftp on` / `/ftp off` | Turns the quest tracker on or off (then type `/reload`). |
| `/ftp debug` | Opens the tracker's layout details in a window, to copy into a bug report. |
| `/ftp bug` | Makes a bug report to copy: version, addons, our errors and changed settings. |
| `/ftp news` | Shows what is new in this version. |
| `/ftp session` | Shows what you did this session. |
| `/ftp flights` | The flight log: your last flights with their times. |
| `/ftp share` | Shares every quest you can with your party. |
| `/ftp party` | Shows which party member has which quest. |
| `/ftp runcard` | Shows the summary of your last dungeon run. |

### RestedXP guide (needs RestedXP Guides)

| Command | What it does |
| --- | --- |
| `/ftp toggle` | Shows the guide steps in the tracker, or brings back RestedXP's own windows. |
| `/ftp <0-100>` or `/ftp all` | Sets how many upcoming steps are shown. |
| `/ftp steps` | Shows the current number of upcoming steps. |
| `/ftp arrow` | Turns the waypoint arrow as the step's button on or off. |
| `/ftp satellites` | Turns the small objective buttons around the arrow on or off. |
| `/ftp badge` | Collapses two or more of those buttons into one +N badge that opens on hover. |
| `/ftp status` | Prints the current state to chat. |
| `/ftp welcome` | Opens the guide chooser. |
| `/ftp restart` | Starts the current guide again from its first step. |
| `/ftp why` | Opens "Why did guide skip?": the latest guide and step moves and what caused them. |

</details>

## 🙏 Credits

Some feature ideas come from the **QuestMaster** and **Questline** addons. All code here is our own. Quest data is read live from **Questie** when it is installed.
