local AddOnName, NS        = ...
local E, L, V, P, G        = unpack(ElvUI)
local EP                   = LibStub and LibStub("LibElvUIPlugin-1.0", true)
local UF -- filled on init

-- Module registration
local EDGF                 = E:NewModule("EDGF", "AceEvent-3.0")

-- Constants: party/raid sizes and default bucket caps
local MAX_PARTY_SIZE   = 5
local DEFAULT_RAID1MAX = 20
local DEFAULT_RAID2MAX = 30
local MAX_RAID_SIZE    = 40

-- Expose constants to other files via shared namespace
NS.EDGF_CONST = {
  MAX_PARTY_SIZE   = MAX_PARTY_SIZE,
  DEFAULT_RAID1MAX = DEFAULT_RAID1MAX,
  DEFAULT_RAID2MAX = DEFAULT_RAID2MAX,
  MAX_RAID_SIZE    = MAX_RAID_SIZE,
}

-- ElvUI profile defaults for this module
P.EDGF                     = {
  enable   = true,
  useParty = true, -- allow skipping Party frames (start at Raid1 from 1 player)
  buckets  = { partyMax = MAX_PARTY_SIZE, raid1Max = DEFAULT_RAID1MAX, raid2Max = DEFAULT_RAID2MAX },
}

-- Internal timings and startup behavior
local DELAYS               = { debounce = 0.20, enforce = 0.05 }
local ENFORCE_ALL_ON_LOGIN = true

-- Values we always enforce on raid headers (not exposed in UI)
local ENFORCE_VALUES       = {
  raidWideSorting    = true,
  groupFilter        = "1,2,3,4,5,6,7,8",
  keepGroupsTogether = false,
}

-- Returns the unitframe units DB table or nil
local function units_db()
  return E and E.db and E.db.unitframe and E.db.unitframe.units
end

-- Prints via ElvUI if available; falls back to print
local function safe_print(msg)
  if E and E.Print then E:Print(msg) else print(msg) end
end

-- pcall wrapper that logs errors via safe_print
function EDGF:_safe_call(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if not ok and err then safe_print("|cff88ccffEDGF|r error: "..tostring(err)) end
end

-- Retrieves and caches ElvUI UnitFrames module (handles race conditions)
function EDGF:get_uf()
  if not UF and E and E.GetModule then
    local ok, mod = pcall(E.GetModule, E, "UnitFrames")
    if ok then UF = mod end
  end
  return UF
end

-- Hooks UF header rebuilds to re-enforce minimal settings on the active header
local function hook_uf()
  if not EDGF:get_uf() or EDGF._hooked then return end
  EDGF:_safe_call(hooksecurefunc, UF, "CreateAndUpdateHeaderGroup", function(_, unit)
    if unit and unit == EDGF._currentHeaderKey then
      C_Timer.After(DELAYS.enforce, function()
        if InCombatLockdown() then
          EDGF._needEnforce = unit
        else
          EDGF:enforce_minimal(unit)
        end
      end)
    end
  end)
  EDGF._hooked = true
end

-- Retries until UnitFrames is available, then installs the hook
function EDGF:ensure_uf_hook()
  if self._hooked then return end
  local tries = 0
  local function attempt()
    tries = tries + 1
    hook_uf()
    if not EDGF._hooked and tries < 20 then
      C_Timer.After(0.25, attempt)
    end
  end
  attempt()
end

-- Debounces apply_all + normalize_all after options changes
function EDGF:schedule_reapply_normalize(delay)
  delay = delay or 0.25
  if self._optTimer then self._optTimer:Cancel() end
  self._optTimer = C_Timer.NewTimer(delay, function()
    if InCombatLockdown() then
      self._pending = true
      self._normalizePending = true
      return
    end
  self:apply_all()
  self:normalize_all()
  end)
end

-- Clamps/normalizes bucket caps to maintain ascending order; respects useParty
local function normalize_bucket_bounds()
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

-- Returns managed header keys based on whether party usage is enabled
local function get_managed_keys()
  local db = E.db and E.db.EDGF
  local useParty = db and (db.useParty ~= false)
  if useParty then
    return { "party", "raid1", "raid2", "raid3" }
  else
    return { "raid1", "raid2", "raid3" } -- party excluded
  end
end

-- Maps group size to a visibility bucket: party, raid1, raid2, or raid3
local function get_bucket(db, size)
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

-- Sets visibility for a single active header and hides the others; returns true if any change
local function set_header_visibility(units, showKey, keys)
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

-- Enforces core knobs and minimum numGroups for a given header (respects combat lockdown)
function EDGF:enforce_minimal(headerKey)
  if not headerKey or InCombatLockdown() then return end
  local units = units_db(); if not units then return end
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
    if changed and UF then self:_safe_call(UF.CreateAndUpdateHeaderGroup, UF, "party") end
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
    self:_safe_call(UF.CreateAndUpdateHeaderGroup, UF, headerKey)
  end
end

-- Enforces minimal settings on all managed headers
function EDGF:normalize_all()
  if InCombatLockdown() then
    self._normalizePending = true
    return
  end
  local units = units_db(); if not units then return end
  for _, key in ipairs(get_managed_keys()) do
    self:enforce_minimal(key)
  end
end

-- Applies visibility based on current group size and schedules enforcement
function EDGF:apply_all()
  if not E.db.EDGF.enable then return end
  if InCombatLockdown() then
    self._pending = true; return
  end

  local units = units_db(); if not units then return end
  local size    = IsInRaid() and GetNumGroupMembers()
      or (IsInGroup() and (GetNumSubgroupMembers() + 1))
      or 1

  local bucket  = get_bucket(E.db.EDGF, size)
  local showKey = bucket

  -- If party is disabled, ensure it's hidden/disabled in DB
  if E.db.EDGF and (E.db.EDGF.useParty == false) and units.party then
    units.party.visibility = "hide"
    units.party.enable = false
  end

  if set_header_visibility(units, showKey, get_managed_keys()) then
    for _, key in ipairs({ "party", "raid1", "raid2", "raid3" }) do
      if units[key] and UF then self:_safe_call(UF.CreateAndUpdateHeaderGroup, UF, key) end
    end
  end

  self._currentHeaderKey = showKey
  C_Timer.After(DELAYS.enforce, function()
    if InCombatLockdown() then
      self._needEnforce = showKey
    else
      self:enforce_minimal(showKey)
    end
  end)
end

-- Manually applies and immediately enforces the active header; queues if in combat
function EDGF:apply_now()
  if InCombatLockdown() then
    self._pending = true
    safe_print("|cff88ccffEDGF|r: in combat — queued; will run after combat.")
    return
  end
  self:apply_all()
  local key = self._currentHeaderKey
  if key then self:enforce_minimal(key) end
  safe_print("|cff88ccffEDGF|r: applied.")
end

-- hook_uf moved above; used to re-enforce after UF rebuilds the active header

-- Flushes pending work after combat ends; runs normalize/enforce if queued
function EDGF:PLAYER_REGEN_ENABLED()
  if self._pending then
    self._pending = false; self:apply_all(); safe_print("|cff88ccffEDGF|r: applied after combat.")
  end
  if self._normalizePending then
    self._normalizePending = false; self:normalize_all()
  end
  if self._needEnforce then
    local k = self._needEnforce; self._needEnforce = nil; self:enforce_minimal(k)
  end
end

-- Debounced roster update handler; reapplies after short delay
function EDGF:GROUP_ROSTER_UPDATE()
  if InCombatLockdown() then
    self._pending = true; return
  end
  if self._debounce then self._debounce:Cancel() end
  self._debounce = C_Timer.NewTimer(DELAYS.debounce, function() self:apply_all() end)
end

-- On login/zone load: normalize once (out of combat) and apply
function EDGF:PLAYER_ENTERING_WORLD()
  normalize_bucket_bounds()
  if ENFORCE_ALL_ON_LOGIN and not self._normalized and not InCombatLockdown() then
    self:normalize_all()
    self._normalized = true
  end
  self:apply_all()
end

-- Registers the /edgf slash command to trigger apply_now
local function register_slash()
  SLASH_EDGF1 = "/edgf"
  SlashCmdList.EDGF = function(msg)
    EDGF:apply_now()
  end
end

-- Module initialization: hooks UF, registers events, wires options, schedules initial apply
function EDGF:Initialize()
  self:get_uf()
  self:ensure_uf_hook()

  self:RegisterEvent("GROUP_ROSTER_UPDATE")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")

  register_slash()

  if EP then
    EP:RegisterPlugin(AddOnName, function()
      NS.InsertOptions()
    end)
  end

  C_Timer.After(0.1, function() EDGF:apply_all() end)

  -- Best-effort profile change support (depends on ElvUI/AceDB)
  local function onProfileEvent()
    EDGF:schedule_reapply_normalize(0.1)
  end
  if E and E.data and E.data.RegisterCallback then
    -- Try both callback signatures safely
    self:_safe_call(function() E.data:RegisterCallback("OnProfileChanged", onProfileEvent) end)
    self:_safe_call(function() E.data:RegisterCallback("OnProfileCopied", onProfileEvent) end)
    self:_safe_call(function() E.data:RegisterCallback("OnProfileReset", onProfileEvent) end)
  end
end

-- Reset bucket values to default, enforce normalization
function EDGF:reset_to_defaults()
  if InCombatLockdown() then
    safe_print("|cffe74c3cEDGF|r: Cannot reset during combat."); return
  end
  if not P.EDGF then P.EDGF = {} end
  P.EDGF.useParty = true
  P.EDGF.party_max_size = MAX_PARTY_SIZE
  P.EDGF.raid1_max_size = DEFAULT_RAID1MAX
  P.EDGF.raid2_max_size = DEFAULT_RAID2MAX
  P.EDGF.raid3_max_size = MAX_RAID_SIZE
  normalize_bucket_bounds()
  self:apply_all()
  safe_print("|cff88ccffEDGF|r: Reset to defaults.")
end

E:RegisterModule(EDGF:GetName())