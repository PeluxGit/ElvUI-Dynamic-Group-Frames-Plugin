# ElvUI Dynamic Group Frames (EDGF)

Keep your raid frames consistent, no matter how subgroups are filled.

**EDGF** is an ElvUI plugin that **automatically switches** between the **Party**, **Raid1**, **Raid2**, and **Raid3** **group unit frames** based on the _actual number of players_ in your group/raid (not on whether certain unit “positions” exist). This is ideal when subgroups are **not** filled contiguously (e.g., 10 players spread across 3 subgroups) but you still want a clean **2×5** look.

---

## Highlights

- **Bucketed switching**  
  Configure thresholds for **Party**, **Raid1**, and **Raid2**. Anything above Raid2 uses **Raid3**.
- **Optional Party usage**  
  A **Use Party Frames** toggle lets you skip Party entirely and start at **Raid1** from 1 player.
- **Works with raid-wide sorting**  
  Keeps your layout coherent even when subgroups are uneven.
- **Hands-off safeguards**  
  Internally ensures essential options so layouts behave as expected.
- **Safe in combat**  
  Changes are deferred and applied automatically when you leave combat.

---

## Requirements

- **ElvUI** (Retail)  
  Any modern ElvUI build with Party/Raid **group unit frames** enabled.
- World of Warcraft (Retail).

---

## Install

### Option 1: Addon Manager (recommended)

Install via your addon manager from:

- [CurseForge](https://www.curseforge.com/wow/addons/elvui-dynamic-group-frames)
- [Wago.io](https://addons.wago.io/addons/elvui-dynamic-group-frames)

### Option 2: Manual Install

1. Download the latest release zip from [GitHub Releases](https://github.com/PeluxGit/ElvUI-Dynamic-Group-Frames-Plugin/releases).
2. Extract to:

   ```text
   World of Warcraft/_retail_/Interface/AddOns/ElvUI_DynamicGroupFrames
   ```

3. Restart WoW or `/reload`.

---

## Configure

ElvUI → **UnitFrames** → **Dynamic Group Frames (EDGF)**

- **Enable** — turn the plugin on/off.
- **Use Party Frames** — **ON** by default.
  - **ON:** Party frames are used for 1–5 players. The Party bucket is fixed at **5**.
    - **Raid1** range: **6 … (Raid2 max − 1)**.
    - **Raid2** range: **(Raid1 max + 1) … 40**.
  - **OFF:** Party frames are **hidden/disabled**.
    - **Raid1** range: **1 … (Raid2 max − 1)**.
    - **Raid2** range: **(Raid1 max + 1) … 40**.
- **Buckets** — three sliders (when Party is used, the Party slider is shown as **fixed to 5**):
  - **Party** (fixed to **5** when _Use Party Frames_ is ON; hidden when OFF)
  - **Raid1** (lower bound depends on _Use Party Frames_)
  - **Raid2**
  - Anything above **Raid2** uses **Raid3** automatically.

Click **Apply Now** (or type **`/edgf`**) to force an immediate update out of combat.

> The UI clamps values so **Party < Raid1 < Raid2 ≤ 40** at all times.
> You can still use ElvUI’s settings to style **Party**, **Raid1**, **Raid2**, and **Raid3** **group unit frames** independently (size, fonts, indicators, etc.). EDGF only decides **which group frames are shown** at any time.

---

## How it works

- Detects current group size and selects:
  - (**Use Party = ON**)
    - 1–5 → **Party**
    - 6…Raid1Max → **Raid1**
    - (Raid1Max+1)…Raid2Max → **Raid2**
    - \> Raid2Max → **Raid3**
  - (**Use Party = OFF**)
    - 1…Raid1Max → **Raid1**
    - (Raid1Max+1)…Raid2Max → **Raid2**
    - \> Raid2Max → **Raid3**
- Internally (out of combat) ensures options that keep raid-wide sorting layouts stable:
  - `raidWideSorting = true`
  - `groupFilter     = "1,2,3,4,5,6,7,8"`
  - `keepGroupsTogether = false`
  - **numGroups = 8** for all raid frames (raid1/raid2/raid3) to ensure no players are dropped
  - Party frames enforce a minimum of 1 group when enabled
- **Normalization safeguards**  
  On login and when options change, EDGF clamps bucket values to keep them coherent:
  - With _Use Party Frames = ON_: **Party = 5**, **Raid1 ≥ 6**, **Raid2 > Raid1**, **Raid2 ≤ 40**
  - With _Use Party Frames = OFF_: **Raid1 ≥ 1**, **Raid2 > Raid1**, **Raid2 ≤ 40**
- Changes are throttled and deferred while in combat.

---

## Commands

- **`/edgf`** — Apply immediately (out of combat).  
  If used in combat, it queues and applies after combat ends.

---

## Tips & Known Quirks

- **ElvUI options will show `numGroups = 8`** for raid frames.  
  EDGF enforces this value to ensure all 8 subgroups are always shown, preventing players from being hidden.
- **Visibility input** in ElvUI will be overwritten by EDGF during the next roster change or when you press **Apply Now**.
- **Per-bucket styling** Tweak ElvUI's **Party**, **Raid1**, **Raid2**, **Raid3** pages to scale unit frames appropriately.

---

## Changelog

See [CHANGELOG.md](./CHANGELOG.md).

---

## License

[MIT](./LICENSE)
