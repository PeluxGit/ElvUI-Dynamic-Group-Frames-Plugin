local AddOnName, NS = ...
local E, L, V, P, G = unpack(ElvUI)

-- No widths: let ElvUI/Ace lay out the sliders on one row.

local function rangeOption(name, min, max, step)
  return { type = "range", name = name, min = min, max = max, step = step or 1 }
end

function NS.InsertOptions()
  local opts = E.Options.args
  local UFopts = opts.unitframe and opts.unitframe.args
  if not UFopts then return end

  UFopts.EDGF = {
    order = 9999,
    type = "group",
    name = "Dynamic Group Frames (EDGF)",
    childGroups = "tab",
    args = {
      header1 = { order = 0, type = "header", name = "EDGF" },

      enable = {
        order = 1,
        type = "toggle",
        name = "Enable",
        get = function() return E.db.EDGF.enable end,
        set = function(_, v)
          E.db.EDGF.enable = v; E:GetModule("EDGF"):ApplyAll()
        end
      },

      -- NEW: Use Party Frames
      useParty = {
        order = 2,
        type  = "toggle",
        name  = "Use Party Frames",
        desc  = "If disabled, Party frames are hidden/disabled and Raid1 applies from 1 player upward.",
        get   = function() return E.db.EDGF.useParty end,
        set   = function(_, v)
          E.db.EDGF.useParty = v
          -- Normalize ranges after toggle
          local b = E.db.EDGF.buckets
          if v then
            -- party fixed to 5; ensure Raid1 >= 6
            b.partyMax = 5
            b.raid1Max = math.max(b.partyMax + 1, math.min(b.raid1Max or 15, (b.raid2Max or 25) - 1))
            b.raid2Max = math.max(b.raid1Max + 1, math.min(b.raid2Max or 25, 40))
          else
            -- party ignored; allow Raid1 >= 1
            b.raid1Max = math.max(1, math.min(b.raid1Max or 15, (b.raid2Max or 25) - 1))
            b.raid2Max = math.max(b.raid1Max + 1, math.min(b.raid2Max or 25, 40))
          end
          local mod = E:GetModule("EDGF")
          mod:ApplyAll()
          mod:NormalizeAll()
        end
      },

      -- ===== Buckets (one row) =====
      bucketsGroup = {
        order = 10,
        type = "group",
        name = "Buckets",
        inline = true,
        args = {
          -- Party is fixed to 5 when useParty=true; hide it when useParty=false.
          partyMax = {
            order = 1,
            type = "range",
            name = "Party (fixed to 5)",
            min = 5,
            max = 5,
            step = 1,
            hidden = function() return E.db.EDGF.useParty == false end,
            disabled = true,
            get = function() return 5 end,
            set = function() end,
          },

          -- Raid1: min is dynamic via clamping in set()
          raid1Max = rangeOption("Raid1", 1, 25, 1),

          raid2Max = rangeOption("Raid2", 2, 40, 1),
        },
        get = function(info) return E.db.EDGF.buckets[info[#info]] end,
        set = function(info, val)
          local b = E.db.EDGF.buckets
          local key = info[#info]
          local useParty = E.db.EDGF.useParty ~= false

          if key == "partyMax" then
            -- not editable (disabled), but keep logic here in case of external edits
            b.partyMax = 5
          elseif key == "raid1Max" then
            local minR1 = useParty and (b.partyMax + 1) or 1
            b.raid1Max  = math.min(math.max(minR1, val), (b.raid2Max or 25) - 1)
          else -- raid2Max
            local minR2 = (b.raid1Max or 15) + 1
            b.raid2Max  = math.min(math.max(minR2, val), 40)
          end

          local mod = E:GetModule("EDGF")
          mod:ApplyAll()
          mod:NormalizeAll()
        end,
      },

      -- Info + spacer to separate from the button row
      infoNote = {
        order = 20,
        type = "description",
        width = "full",
        name = "Any group with more players than the Raid2 bucket size will use the Raid3 group frames.",
      },
      spacer = { order = 21, type = "description", width = "full", name = "\n" },

      applyNow = {
        order = 100,
        type = "execute",
        name = "Apply Now",
        func = function() E:GetModule("EDGF"):ApplyNow() end,
      },
    },
  }
end
