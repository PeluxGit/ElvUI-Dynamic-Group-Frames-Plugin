local AddOnName, NS        = ...
local E, L, V, P, G        = unpack(ElvUI)
local EP                   = LibStub and LibStub("LibElvUIPlugin-1.0", true)
local UF -- filled on init

-- Module
local EDGF                 = E:NewModule("EDGF", "AceEvent-3.0")

-- ==============================
-- Defaults (profile)
-- ==============================
P.EDGF                     = {
  enable   = true,
  useParty = true, -- allow skipping Party frames (start at Raid1 from 1 player)
  buckets  = { partyMax = 5, raid1Max = 15, raid2Max = 25 },
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

-- Normalize/clamp bucket bounds to keep ordering coherent
local function NormalizeBucketBounds()
  local db = E.db and E.db.EDGF
  local b  = db and db.buckets
  if not b then return end

  local useParty = (db.useParty ~= false)

  local partyMax = tonumber(b.partyMax) or 5
  local raid1Max = tonumber(b.raid1Max) or 15
  local raid2Max = tonumber(b.raid2Max) or 25

  if useParty then
    partyMax = 5
    raid1Max = math.max(partyMax + 1, math.min(raid1Max, raid2Max - 1)) -- ≥ 6
  else
    raid1Max = math.max(1, math.min(raid1Max, raid2Max - 1))
  end
  raid2Max = math.max(raid1Max + 1, math.min(raid2Max, 40))

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
    if size <= (b.partyMax or 5) then
      return "party"
    elseif size <= (b.raid1Max or 15) then
      return "raid1"
    elseif size <= (b.raid2Max or 25) then
      return "raid2"
    else
      return "raid3"
    end
  else
    if size <= (b.raid1Max or 15) then
      return "raid1"
    elseif size <= (b.raid2Max or 25) then
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
    if changed then UF:CreateAndUpdateHeaderGroup("party") end
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

  if changed then
    UF:CreateAndUpdateHeaderGroup(headerKey)
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
      if units[key] then UF:CreateAndUpdateHeaderGroup(key) end
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
    print("|cff88ccffEDGF|r: in combat — queued; will run after combat.")
    return
  end
  self:ApplyAll()
  local key = self._currentHeaderKey
  if key then self:EnforceMinimal(key) end
  print("|cff88ccffEDGF|r: applied.")
end

-- After UF rebuilds our active group, re-enforce minimal
local function HookUF()
  if UF and not EDGF._hooked then
    hooksecurefunc(UF, "CreateAndUpdateHeaderGroup", function(_, unit)
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
end

-- ==============================
-- Events
-- ==============================
function EDGF:PLAYER_REGEN_ENABLED()
  if self._pending then
    self._pending = false; self:ApplyAll(); print("|cff88ccffEDGF|r: applied after combat.")
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
  UF = E:GetModule("UnitFrames")
  HookUF()

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
end

E:RegisterModule(EDGF:GetName())
