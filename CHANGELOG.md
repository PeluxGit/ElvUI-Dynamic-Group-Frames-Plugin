# Changelog

## [2026-02-13]

### Changed

- Bump TOC

## 1.0.1 - Fix raid display stagger on reload

- Force-refresh the active group on login and when `/edgf` is used to prevent display issues after `/reload`.

## 1.0.0 - Initial release

- Dynamic switching between Party / Raid1 / Raid2 / Raid3 **group unit frames** based on actual group size.
- Bucket sliders (Party, Raid1, Raid2); anything above Raid2 uses Raid3.
- Out-of-combat safeguards for raid-wide sorting and related knobs.
- `/edgf` command to apply immediately (queues if in combat).
