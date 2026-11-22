<div align="center">

# 🧭 ForeverTrackerPlus

**A scrollable, smarter quest tracker for WoW Forever, with your RestedXP guide built right in.**

[![Latest release](https://img.shields.io/github/v/release/imfleek/ForeverTrackerPlus?label=release&color=c9a24a)](https://github.com/imfleek/ForeverTrackerPlus/releases/latest)
![WoW Forever](https://img.shields.io/badge/WoW_Forever-16001-8b1a10)
[![License: MIT](https://img.shields.io/badge/license-MIT-4c7a3d)](LICENSE)

</div>

---

## 📦 How to Install

1. Download **`ForeverTrackerPlus.zip`** from the [latest release](https://github.com/imfleek/ForeverTrackerPlus/releases/latest) or from CurseForge.
2. Extract the `ForeverTrackerPlus` folder into:

   ```
   BattleNet/World of Warcraft/_forever_/Interface/AddOns/
   ```

3. Log in. A short **first-time setup** walks you through every feature, with an on/off switch for each.

## ✨ What's new in 3.1

- 🎒 **Quest item bar**: one button for each usable quest item, with a key binding.
- 📣 **Big progress messages**: "Wolves slain: 3/8" in large letters, and "Ready to turn in".
- 📍 **World marker**: your tracked quest's name, next step, distance and a light beam over its spot in the world.
- 📚 **Guides**: Legacy Challenges, library books and the Cozy Sleeping Bag chain.
- ⚙️ **New settings window** (3.0): a sidebar of sections, tabs, folding cards and a help line under most settings.
- 📊 **Statistics** (3.0): an overview, a run analysis, level splits and **Copy for Discord**.

See the [changelog](CHANGELOG.md) for everything.

## 🌟 Features

### Quest tracker
- 🖱️ **Mouse-wheel scrolling** for Blizzard's own tracker, with an optional scrollbar. Long quest lists never run off the screen.
- 🗺️ **Zone sorting**: quests under zone headers, the closest quest first. Distance arrows on each quest.
- 💰 **Rewards at a glance**: experience and gold after each title, progress bars, a check on finished quests, and tooltips with objectives and rewards.
- 🏷️ **Icons**: elite, group, dungeon, raid, PvP and new-in-Forever quests.
- 🧊 **3D model panel**: hover an objective that names an NPC or object to see its model.
- 🏰 **Dungeon card**: in a dungeon or raid, its name, party, deaths, instances this hour and your lockout.
- ⭐ **Rares near your quests** on the zone header, with distance and a waypoint.
- 👥 **Find a group**: Ctrl+click a quest to post LFM or list it in Looking For Group.
- 🔗 **Wowhead link**: right-click a quest for its WoW Forever Wowhead URL.

### Helpers
- 🎒 Quest item bar, and quest items marked in your bags (with a warning if you sell or delete one).
- 🪙 A gold coin on the quest reward that sells for the most.
- 📍 World marker, and an option to track the nearest quest by itself.
- 📣 Big progress messages, and optional party chat lines.
- 🔎 A card when a quest you can take is close by (Questie). Breadcrumb quests you do not need are left out.
- 🤝 **Talking to NPCs** (off until you turn it on): accept quests, turn in finished ones, skip a one-option chat. Hold Shift to pause it.
- 🫧 Breath warning, and ✈️ flight times for every route (from the game's own flight path data).

### Guides
- 🏆 **Legacy Challenges**: every challenge, with what is still to do.
- 📖 **Library books**: done, in your bags or open; click for a waypoint (Questie).
- 🛏️ **Cozy Sleeping Bag** chain, from level 14; click a step for a waypoint (Questie).

### Statistics
- 📊 **Overview**: quests done, experience from quests, quest times, quests per hour, top zones.
- ⏱️ **Run analysis**: where your time went (combat, running, mounted, flying, NPCs, dead, AFK, standing) and time per level.
- 📈 **Level splits**: time per level from /played, compared with another character.
- 💬 **Copy for Discord**, and a level-up line in chat.

### RestedXP guide (needs RestedXP Guides)
- 📜 The current and upcoming steps in the tracker, with click-to-use item and spell buttons, a waypoint arrow, and back / restart / forward buttons.
- 📖 **Prerequisite Journal** (with Questie): the prerequisites you are missing for quests ahead in your guide.
- ❓ **"Why did guide skip?"** (`/qt why`): every guide and step move, who made it and why.
- 🧹 **Orphaned quest cleanup**: quests your guide no longer uses.

> **Optional addons:**
> - **RestedXP Guides**: guide steps in the tracker
> - **Questie**: quest locations, chains, party progress, closest-quest sorting, nearby quests, library books, the sleeping bag chain
> - **DungeonJournal**, **NovaInstanceTracker**: extra lines on the dungeon card

## ⚙️ Settings: `/qt`

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
> - Set the quest item key in **Key Bindings > AddOns > ForeverTrackerPlus**.

## Commands

<details>
<summary><b>Show all commands</b></summary>

Type `/qt help` in game for this list.

### Quest tracker

| Command | What it does |
| --- | --- |
| `/qt` | Opens or closes the settings window. |
| `/qt config` | The same as `/qt`. |
| `/qt setup` | Opens the first-time setup again. |
| `/qt stats` | Opens the statistics overview. |
| `/qt run` | Opens the run analysis. |
| `/qt guide` | Opens the settings window at the guide (RestedXP) settings. |
| `/qt quests` | Opens the settings window at the quest tracker settings. |
| `/qt orphan` | Opens the settings window at Orphaned quests. |
| `/qt height <px>` | Sets how tall the quest list is (`0` = automatic). |
| `/qt scale <0.5-1.5>` | Sets the tracker's size. |
| `/qt step <px>` | Sets how far one turn of the mouse wheel scrolls. |
| `/qt zone` | Turns sorting quests by zone on or off. |
| `/qt sort` | Sorts the quests now. |
| `/qt lock` | Locks the tracker in place. |
| `/qt unlock` | Unlocks the tracker so you can drag it. |
| `/qt distance` | Tells why a quest shows or hides its distance arrow. |
| `/qt bags` | Shows what the quest marks in your bags see (open your bags first). |
| `/qt reset` | Scrolls the tracker back to the top. |
| `/qt on` / `/qt off` | Turns the quest tracker on or off (then type `/reload`). |
| `/qt debug` | Opens the tracker's layout details in a window, to copy into a bug report. |

### RestedXP guide (needs RestedXP Guides)

| Command | What it does |
| --- | --- |
| `/qt toggle` | Shows the guide steps in the tracker, or brings back RestedXP's own windows. |
| `/qt <0-100>` or `/qt all` | Sets how many upcoming steps are shown. |
| `/qt steps` | Shows the current number of upcoming steps. |
| `/qt arrow` | Turns the waypoint arrow as the step's button on or off. |
| `/qt satellites` | Turns the small objective buttons around the arrow on or off. |
| `/qt badge` | Collapses two or more of those buttons into one +N badge that opens on hover. |
| `/qt status` | Prints the current state to chat. |
| `/qt welcome` | Opens the guide chooser. |
| `/qt restart` | Starts the current guide again from its first step. |
| `/qt why` | Opens "Why did guide skip?": the latest guide and step moves and what caused them. |

</details>

## 🙏 Credits

Some feature ideas come from the **QuestMaster** and **Questline** addons. All code here is our own. Quest data is read live from **Questie** when it is installed.
