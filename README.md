# WarriorCombatManager (WCM)

WarriorCombatManager is a lightweight timeline helper for TurtleWoW (SuperWoW supported setups) that helps you **plan and execute cooldown stacking** on boss fights.

![1](https://github.com/user-attachments/assets/ed976f63-c528-409d-bf14-e2b0a9b5f941)

It combines:
- **Boss kill time history** (via BigWigs BossRecords when available),
- a **live prediction adjustment** based on the boss HP% drop rate,
- and a clean **timeline UI** that shows **when to press** key cooldowns and usable trinkets, with an optional **Execute-phase zoom**.

This addon does not play the game for you. It just makes it harder to mess up your cooldown timing, which is apparently a full-time hobby for most humans.

---

## Features

### Fight Timing
- **Prediction baseline from BigWigs history** (average of last kills).
- **Fallback prediction** when no history exists (default: 120s).
- **Live prediction adjustment** that continuously refines the predicted kill time using boss HP% drop rate (smoothed and rate-limited).

### Timeline UI
- Timeline bar that represents the fight duration.
- Ability and trinket icons placed on the timeline based on cooldown schedule.
- **Highlight logic**:
  - Bright icon: press now
  - Semi-bright: coming soon
  - Dim: not relevant yet
- Optional **Next Action** icon (always on top) for the most important press “right now”.

### Execute Phase Support
- Execute detection based on boss HP% threshold (default: 20%).
- Optional behavior:
  - Turn the bar red during Execute phase.
  - Zoom into the Execute window so icons do not overlap and the timeline becomes easier to read.
![2](https://github.com/user-attachments/assets/50dd3941-a40e-459d-89ce-3635c679f97d)

### Trinket Intelligence
- Automatically reads your equipped trinkets (slot 13 and 14).
- Displays trinkets **only if they have a Use effect** (detected via item spell or tooltip scanning).
- Uses inventory cooldowns, so it stays accurate even if your trinket cooldown differs.

### Boss Locking (Ignore Adds)
- Optional “Lock to boss” mode.
- Prevents adds from hijacking prediction or execute detection by locking sampling to the engaged boss (by name and, when possible, GUID).

### Usability
- Movable and scalable timeline bar.
- Options window:
  - Movable
  - Always on top
  - Close button (X) and ESC support
- Auto-hide out of combat (optional).
![3](https://github.com/user-attachments/assets/a3b1e6fd-afa5-4bcd-80d6-0c3876d47c48)
![4](https://github.com/user-attachments/assets/456e7cd9-ce41-4463-be52-6548bc2d95d7)

---

## Requirements

- TurtleWoW client
- BigWigs recommended (for best predictions), but not required

> WCM will still run without BigWigs. You just lose the history baseline and rely more on live prediction.

---

## Installation

1. Download or clone this repository.
2. Put the folder in:
   `TurtleWoW/Interface/AddOns/WarriorCombatManager`
3. Make sure the folder name matches the `.toc` name.
4. `/reload`

---

## Quick Start

- Show the timeline:
  - `/wcm show`
- Hide the timeline:
  - `/wcm hide`
- Open options:
  - `/wcm opt`
- Start a manual test (no boss needed):
  - `/wcm start 120`
- Stop manual test:
  - `/wcm stop`

---

## Slash Commands

`/wcm show`  
Shows the timeline bar.

`/wcm hide`  
Hides the timeline bar.

`/wcm opt` or `/wcm options`  
Opens the options window.

`/wcm start [seconds]`  
Starts a manual test timeline (default uses fallback predicted duration if seconds not provided).

`/wcm stop`  
Stops the manual test.

`/wcm hist <bossname>`  
Prints stored history for a boss (if any).

`/wcm diag`  
Prints diagnostics (BigWigs hook status, boss lock status, settings, etc).

---

## Options Explained

### UI
- **Locked**
  - Locks the timeline position (disables dragging).
- **Scale**
  - Changes bar size in real time (no reload needed).
- **Position X / Y**
  - Sliders + edit boxes for pixel-perfect positioning.
- **Auto-hide out of combat**
  - Hides the bar when you are not in combat and WCM is not running.

### Boss / Prediction
- **Enable BigWigs integration**
  - Uses BossRecords history if available.
- **Lock prediction to boss (ignore adds)**
  - Locks sampling to the boss (recommended for fights with adds).
- **Live prediction adjustment**
  - Updates prediction as the boss HP% drops, with smoothing and warmup.

### Execute
- **Execute threshold (%)**
  - Default: 20
- **Execute zoom enabled**
  - Zooms into the execute window for better readability.
- **Zoom by execute percent**
  - Zoom window is derived from the execute threshold percent.
- **Execute makes bar red**
  - Visual cue for execute phase.

### Guidance
- **Strict final stacking window (last 30s)**
  - Prioritizes a “best use now” during the final window.
- **Show Next Action icon**
  - Displays the top-priority press as a large icon on top of everything.

---

## How Prediction Works (Simple Version)

1. When a boss is engaged, WCM sets an initial predicted kill time:
   - If BigWigs history exists: average of recent kills.
   - If not: default fallback (e.g. 120 seconds).

2. During the fight, WCM monitors the boss HP% drop:
   - After a short warmup and minimum HP% drop, it estimates total fight duration from the observed slope.
   - It then **smooths** the predicted value so it does not jump wildly every update.

3. In Execute phase (based on your threshold), WCM can zoom into the last part of the fight for clarity.

---

## Troubleshooting

### “BigWigs hook not working”
- Make sure BigWigs is enabled.
- Make sure the BigWigs BossRecords module is present.
- Run `/wcm diag` and check `hooked=true`.

### “Prediction jumps around”
- Turn on **Lock to boss (ignore adds)**.
- Live prediction needs a few seconds and a few % HP drop before it stabilizes.
- Extremely phase-heavy fights can still cause changes. That is not magic, it is reality.

### “My usable trinket does not appear”
- WCM only shows trinkets with a **Use effect**.
- Some items are “equip proc” only and will be intentionally hidden.
- If the item is a Use trinket and still not shown, try:
  - `/reload`
  - unequip and re-equip the trinket
  - check that it is in slot 13/14

### “The bar moved after reload”
- Position is stored. If your UI scale changed, positions can shift.
- Use Options Position X/Y to correct it, then it will persist.

---

## Roadmap (Planned)

- Per-boss profiles (optional), to account for forced downtime phases.
- Better “status indicator” (locked boss found, adjusting, frozen, etc).
- Settings reset button.
- Trinket use caching (performance improvement).

---

## Credits

Built for TurtleWoW warriors who like big numbers, clean cooldown windows, and fewer mistakes.
