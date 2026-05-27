--[[
  Hazard Pathfinding Fix for 7.7x (Protocol 772)
  
  Ensures the C++ pathfinder correctly avoids hazardous tiles by
  patching ThingType flags when the DAT file is missing isNotPathable.
  
  Reference: objects.srv items with Avoid + MagicField flags,
  plus non-field hazards (searing fire, lava, pitfalls, campfires).
]]

-- All item IDs that should be avoided by pathfinding.
-- Sourced from objects.srv: items with Avoid flag that are dangerous to walk on.
local hazardousIds = {
  -- Magic field fires (rune-created and permanent)
  2118,  -- fire (big, rune-created, dmg=fire)
  2119,  -- fire (medium, fading, dmg=fire)
  2123,  -- fire (big, permanent, dmg=fire)
  2124,  -- fire (medium, permanent, dmg=fire)
  -- Magic field poison
  2121,  -- poison gas (rune-created, dmg=earth)
  2127,  -- poison gas (permanent, dmg=earth)
  -- Magic field energy
  2122,  -- energy field (rune-created, dmg=energy)
  2126,  -- energy field (permanent, dmg=energy)
  -- Fire bomb / poison bomb / energy bomb fields
  2131,  -- fire bomb big (dmg=fire)
  2132,  -- fire bomb medium (dmg=fire)
  2134,  -- poison bomb (dmg=earth)
  2135,  -- energy bomb (dmg=energy)
  -- Searing fire / fire (non-MagicField but still dangerous)
  2137,  -- searing fire
  2138,  -- fire (fading searing)
  2139,  -- fire (fading searing)
  2141,  -- searing fire
  2142,  -- searing fire
  2149,  -- searing fire
  2150,  -- fire
  2151,  -- fire
  -- Lava (ground tile, damaging)
  2144,  -- lava
  -- Campfires (damaging if stepped on)
  1998,  -- campfire
  1999,  -- campfire
  2000,  -- campfire
  -- Pitfalls (floor change hazards)
  294,   -- pitfall (open)
  1067,  -- pitfall (jungle)
}

local fixed = 0
for _, id in ipairs(hazardousIds) do
  local thingType = g_things.getThingType(id, ThingCategoryItem)
  if thingType and not thingType:isNotPathable() then
    thingType:setPathable(false)
    fixed = fixed + 1
  end
end

if fixed > 0 then
  info("Hazard fix: patched " .. fixed .. " item types as non-pathable")
end
