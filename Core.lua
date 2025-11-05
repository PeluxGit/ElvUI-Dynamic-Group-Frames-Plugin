local AddOnName, NS        = ...
local E, L, V, P, G        = unpack(ElvUI)
local EP                   = LibStub and LibStub("LibElvUIPlugin-1.0", true)
local UF -- filled on init

-- Module
local EDGF                 = E:NewModule("EDGF", "AceEvent-3.0")

-- ==============================
-- Constants
-- ==============================
local MAX_PARTY_SIZE   = 5
local DEFAULT_RAID1MAX = 15
local DEFAULT_RAID2MAX = 25
local MAX_RAID_SIZE    = 40

-- ==============================
-- Defaults (profile)
-- ==============================
P.EDGF                     = {
  enable   = true,
  useParty = true, -- allow skipping Party frames (start at Raid1 from 1 player)
  buckets  = { partyMax = MAX_PARTY_SIZE, raid1Max = DEFAULT_RAID1MAX, raid2Max = DEFAULT_RAID2MAX },
}

-- ==============================
-- Internal constants
-- ==============================
local DELAYS               = { debounce = 0.20, enforce = 0.05 }
local ENFORCE_ALL_ON_LOGIN = true

-- Values we always enforce (documented, not exposed in UI)
local ENFORCE_VALUES       = {
  raidWideSorting    = true,
  groupFilter        = "1,2,3,4,5,6,7,8",
  keepGroupsTogether = false,
  -- numGroups for raid headers is forced to 8 (see EnforceMinimal)
}

-- ==============================
-- Helpers
-- ==============================
local function UnitsDB()
  return E and E.db and E.db.unitframe and E.db.unitframe.units
end

-- Safe printing and pcall wrapper
local function SafePrint(msg)
  if E and E.Print then E:Print(msg) else print(msg) end
end

function EDGF:_safeCall(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if not ok and err then SafePrint("|cff88ccffEDGF|r error: "..tostring(err)) end
end

-- UF getter + deferred hook (handles race conditions)
function EDGF:GetUF()
  if not UF and E and E.GetModule then
    local ok, mod = pcall(E.GetModule, E, "UnitFrames")
    if ok then UF = mod end
  end
  return UF
end

local function HookUF()
  if not EDGF:GetUF() or EDGF._hooked then return end
  EDGF:_safeCall(hooksecurefunc, UF, "CreateAndUpdateHeaderGroup", function(_, unit)
    if unit and unit == EDGF._currentHeaderKey then
      C_Timer.After(DELAYS.enforce, function()
        if InCombatLockdown() then
          EDGF._needEnforce = unit
        else
          EDGF:EnforceMinimal(unit)
        end
      end)
    end
  end)
  EDGF._hooked = true
end

function EDGF:EnsureUFHook()
  if self._hooked then return end
  local tries = 0
  local function attempt()
    tries = tries + 1
    HookUF()
    if not EDGF._hooked and tries < 20 then
      C_Timer.After(0.25, attempt)
    end
  end
  attempt()
end

-- Coalesce rapid option changes into one apply+normalize
function EDGF:ScheduleReapplyNormalize(delay)
  delay = delay or 0.25
  if self._optTimer then self._optTimer:Cancel() end
  self._optTimer = C_Timer.NewTimer(delay, function()
    if InCombatLockdown() then
      self._pending = true
      self._normalizePending = true
      return
    end
    self:ApplyAll()
    self:NormalizeAll()
  end)
end

-- Normalize/clamp bucket bounds to keep ordering coherent
local function NormalizeBucketBounds()
  local db = E.db and E.db.EDGF
  local b  = db and db.buckets
  if not b then return end

  local useParty = (db.useParty ~= false)

  local partyMax = tonumber(b.partyMax) or MAX_PARTY_SIZE
  local raid1Max = tonumber(b.raid1Max) or DEFAULT_RAID1MAX
  local raid2Max = tonumber(b.raid2Max) or DEFAULT_RAID2MAX

  if useParty then
    partyMax = MAX_PARTY_SIZE
    raid1Max = math.max(partyMax + 1, math.min(raid1Max, raid2Max - 1)) -- ≥ 6
  else
    raid1Max = math.max(1, math.min(raid1Max, raid2Max - 1))
  end
  raid2Max = math.max(raid1Max + 1, math.min(raid2Max, MAX_RAID_SIZE))

  b.partyMax = partyMax
  b.raid1Max = raid1Max
  b.raid2Max = raid2Max
end

local function GetManagedKeys()
  local db = E.db and E.db.EDGF
  local useParty = db and (db.useParty ~= false)
  if useParty then
    return { "party", "raid1", "raid2", "raid3" }
  else
    return { "raid1", "raid2", "raid3" } -- party excluded
  end
end

local function GetBucket(db, size)
  local b = db.buckets
  local useParty = (db.useParty ~= false)

  if useParty then
    if size <= (b.partyMax or MAX_PARTY_SIZE) then
      return "party"
    elseif size <= (b.raid1Max or DEFAULT_RAID1MAX) then
      return "raid1"
    elseif size <= (b.raid2Max or DEFAULT_RAID2MAX) then
      return "raid2"
    else
      return "raid3"
    end
  else
    if size <= (b.raid1Max or DEFAULT_RAID1MAX) then
      return "raid1"
    elseif size <= (b.raid2Max or DEFAULT_RAID2MAX) then
      return "raid2"
    else
      return "raid3"
    end
  end
end

local function SetHeaderVisibility(units, showKey, keys)
  local changed = false
  for _, key in ipairs(keys) do
    local conf = units[key]
    if conf then
      local want = (key == showKey) and "show" or "hide"
      if conf.visibility ~= want then
        conf.visibility = want
        changed = true
      end
    end
  end
  return changed
end

-- ==============================
-- Minimal enforcement
-- ==============================
function EDGF:EnforceMinimal(headerKey)
  if not headerKey or InCombatLockdown() then return end
  local units = UnitsDB(); if not units then return end
  local cfg = units[headerKey]; if not cfg then return end

  -- If party disabled globally, make sure it's fully off
  if headerKey == "party" and E.db.EDGF and (E.db.EDGF.useParty == false) then
    local changed = false
    if cfg.visibility ~= "hide" then
      cfg.visibility = "hide"; changed = true
    end
    if cfg.enable ~= false then
      cfg.enable = false; changed = true
    end
    if changed and UF then self:_safeCall(UF.CreateAndUpdateHeaderGroup, UF, "party") end
    return
  end

  local changed = false
  local function setDB(k, v)
    if cfg[k] ~= v then
      cfg[k] = v; changed = true
    end
  end

  if headerKey ~= "party" then
    -- Enforce knobs for raid group frames
    setDB("raidWideSorting", ENFORCE_VALUES.raidWideSorting)
    setDB("groupFilter", ENFORCE_VALUES.groupFilter)
    setDB("keepGroupsTogether", ENFORCE_VALUES.keepGroupsTogether)

    -- IMPORTANT: Always include all 8 subgroups so no one is dropped.
    if tonumber(cfg.numGroups) ~= 8 then
      setDB("numGroups", 8)
    end
  else
    -- Party: ensure enabled (when used) and at least 1 group shown
    if E.db.EDGF and (E.db.EDGF.useParty ~= false) then
      if cfg.enable == false then setDB("enable", true) end
      local current = tonumber(cfg.numGroups) or 0
      if current < 1 then setDB("numGroups", 1) end
    end
  end

  if changed and UF then
    self:_safeCall(UF.CreateAndUpdateHeaderGroup, UF, headerKey)
  end
end

-- Normalize all managed group frames at once
function EDGF:NormalizeAll()
  if InCombatLockdown() then
    self._normalizePending = true
    return
  end
  local units = UnitsDB(); if not units then return end
  for _, key in ipairs(GetManagedKeys()) do
    self:EnforceMinimal(key)
  end
end

-- ==============================
-- Main apply
-- ==============================
function EDGF:ApplyAll()
  if not E.db.EDGF.enable then return end
  if InCombatLockdown() then
    self._pending = true; return
  end

  local units = UnitsDB(); if not units then return end
  local size    = IsInRaid() and GetNumGroupMembers()
      or (IsInGroup() and (GetNumSubgroupMembers() + 1))
      or 1

  local bucket  = GetBucket(E.db.EDGF, size)
  local showKey = bucket

  -- If party is disabled, ensure it's hidden/disabled in DB
  if E.db.EDGF and (E.db.EDGF.useParty == false) and units.party then
    units.party.visibility = "hide"
    units.party.enable = false
  end

  if SetHeaderVisibility(units, showKey, GetManagedKeys()) then
    for _, key in ipairs({ "party", "raid1", "raid2", "raid3" }) do
      if units[key] and UF then self:_safeCall(UF.CreateAndUpdateHeaderGroup, UF, key) end
    end
  end

  self._currentHeaderKey = showKey
  C_Timer.After(DELAYS.enforce, function()
    if InCombatLockdown() then
      self._needEnforce = showKey
    else
      self:EnforceMinimal(showKey)
    end
  end)
end

-- Manual apply with immediate enforcement (used by /edgf)
function EDGF:ApplyNow()
  if InCombatLockdown() then
    self._pending = true
    SafePrint("|cff88ccffEDGF|r: in combat — queued; will run after combat.")
    return
  end
  self:ApplyAll()
  local key = self._currentHeaderKey
  if key then self:EnforceMinimal(key) end
  SafePrint("|cff88ccffEDGF|r: applied.")
end

-- After UF rebuilds our active group, re-enforce minimal
-- (HookUF moved above with safety wrappers)

-- ==============================
-- Events
-- ==============================
function EDGF:PLAYER_REGEN_ENABLED()
  if self._pending then
    self._pending = false; self:ApplyAll(); SafePrint("|cff88ccffEDGF|r: applied after combat.")
  end
  if self._normalizePending then
    self._normalizePending = false; self:NormalizeAll()
  end
  if self._needEnforce then
    local k = self._needEnforce; self._needEnforce = nil; self:EnforceMinimal(k)
  end
end

function EDGF:GROUP_ROSTER_UPDATE()
  if InCombatLockdown() then
    self._pending = true; return
  end
  if self._debounce then self._debounce:Cancel() end
  self._debounce = C_Timer.NewTimer(DELAYS.debounce, function() self:ApplyAll() end)
end

function EDGF:PLAYER_ENTERING_WORLD()
  NormalizeBucketBounds()
  if ENFORCE_ALL_ON_LOGIN and not self._normalized and not InCombatLockdown() then
    self:NormalizeAll()
    self._normalized = true
  end
  self:ApplyAll()
end

-- ==============================
-- Slash command (/edgf)
-- ==============================
local function RegisterSlash()
  SLASH_EDGF1 = "/edgf"
  SlashCmdList.EDGF = function(msg)
    EDGF:ApplyNow()
  end
end

-- ==============================
-- Module init
-- ==============================
function EDGF:Initialize()
  self:GetUF()
  self:EnsureUFHook()

  self:RegisterEvent("GROUP_ROSTER_UPDATE")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")

  RegisterSlash()

  if EP then
    EP:RegisterPlugin(AddOnName, function()
      NS.InsertOptions()
    end)
  end

  C_Timer.After(0.1, function() EDGF:ApplyAll() end)

  -- Best-effort profile change support (depends on ElvUI/AceDB)
  local function onProfileEvent()
    EDGF:ScheduleReapplyNormalize(0.1)
  end
  if E and E.data and E.data.RegisterCallback then
    -- Try both callback signatures safely
    self:_safeCall(function() E.data:RegisterCallback("OnProfileChanged", onProfileEvent) end)
    self:_safeCall(function() E.data:RegisterCallback("OnProfileCopied", onProfileEvent) end)
    self:_safeCall(function() E.data:RegisterCallback("OnProfileReset", onProfileEvent) end)
  end
end

E:RegisterModule(EDGF:GetName())

-- ==============================
-- snake_case aliases (non-breaking)
-- ==============================
function EDGF:apply_all() return self:ApplyAll() end
function EDGF:normalize_all() return self:NormalizeAll() end
function EDGF:enforce_minimal(k) return self:EnforceMinimal(k) end
function EDGF:apply_now() return self:ApplyNow() end

-- ==============================
-- Reset to defaults (for Options UI)
-- ==============================
local function deepcopy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local t = {}
  for k, v in pairs(tbl) do t[k] = deepcopy(v) end
  return t
end

function EDGF:ResetToDefaults()
  if not P or not P.EDGF or not E or not E.db then return end
  E.db.EDGF = deepcopy(P.EDGF)
  NormalizeBucketBounds()
  self:ScheduleReapplyNormalize(0.05)
  SafePrint("|cff88ccffEDGF|r: settings reset to defaults.")
end
