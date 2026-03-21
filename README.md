An advanced, highly-customizable Threat Management and utility assignment Addon built explicitly for World of Warcraft: Wrath of the Lich King (3.3.5a). Designed primarily to help Raid Leaders manage high-threat situations efficiently by assigning Salva, MD, and Tricks through a dynamic network-synced Radial Menu.

---

## 🚀 Features

* **Dynamic Threat Grid:** A minimalist, highly readable grid depicting party/raid members. Colors morph dynamically from a crisp white base to a glowing panic red as players climb the threat tables.
* **Smart Talent Auto-Detection:** Automatically detects the roles (Tank/Healer/DPS) of your raid members based on their actual WotLK talent point investments upon log-in or spec swap.
* **Intelligent Network Range Checking:** If an assigned buffer is out of range of the target, their client securely rejects the ping and automatically re-routes the assignment to the next closest available buffer—all within milliseconds without user interaction.
* **Real-Time Raid Debounce Sync:** Spamming assignments across multiple Raid Leaders is impossible. Assigned buffs are instantly synced and visibly locked out across all other Raid Assistants' radial menus for a configurable interval.
* **Tricks of the Trade Smart Threat Cancel:** Automatically detects when a Rogue legitimately drops *Tricks of the Trade* on a non-Tank (DPS). The addon instantly severs the Threat-transfer aura to prevent DPS threat-rips, while fully preserving the flat 15% Damage Increase buff!
* **Deep Customization:** Modify button widths, hide unneeded layout elements, anchor the grid dynamically to 4 directions, choose between beautifully rendered Radial Rim Themes (`Rogue`, `Paladin`, `Hunter`), and toggle localized Ping-Sounds.
* **Lightweight:** Low memory footprint, optimized for the 3.3.5a client.

---

## 🛠 Installation

1. Download the latest version of the addon from the GitHub Releases page.
2. Extract the folder into your World of Warcraft directory:
   `World of Warcraft/Interface/AddOns/`
3. Ensure the folder name is exactly **SausageThreat** (remove any `-main` or version suffixes).
4. Restart the game or type `/reload` in-game.

---

## 🎮 How to Use

List of available slash commands and key UI element interactions:

* `/sthreat` or `/sausagethreat` - Opens the configuration menu.
* **Minimap Button:** **Shift-Click** to easily open Settings. **Left-Click** to toggle visibility of the grid.
* **Roles Overlay:** The Grid visually outlines identified Tanks (Shield icon) and Healers (Cross icon). **Shift + Left Click** any player on the grid as an RL/RA to manually override their role instantly raid-wide!
* **Ping Assignment:** **Right-click and hold** a player on the grid to open the Radial Menu. Drag your mouse to hover over the desired spell slice (Paladin for Salva, Hunter for MD, Rogue for Tricks) and **release the right-click** to confirm. The addon will pick an available player of that class, display a flashing indicator on their screen, and play an audio alert warning them to cast the spell on that exact target. 
* **Canceling an Assignment:** If you change your mind while holding right-click, simply **Left-Click** anywhere on the screen. The Radial Menu will close immediately without assigning any buff.

---

## 🌐 Community & Support

Join our Discord for other addons, updates, bug reports, support, and suggestions:

**[Join Discord Server](https://discord.com/invite/UMbcfhurew)**

*Created by Sausage Party / Kokotiar*

---

## 📌 Technical Specifications

* **Game Version:** World of Warcraft: Wrath of the Lich King (3.3.5a)
* **Tested On:** Warmane (Onyxia Realm)
