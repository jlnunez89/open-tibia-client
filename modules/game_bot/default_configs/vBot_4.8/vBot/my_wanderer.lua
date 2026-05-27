setDefaultTab("Main")

--[[
  Wander Script (7.7x compatible)
  Walks to a random safe adjacent tile every 1-3 seconds.
  Avoids hazardous tiles (fields, magic walls, wild growth)
  and floor-changing tiles (stairs, holes, ladders).

  Uses tile:isWalkable() which reads item attributes from the
  DAT file — works on any Tibia version without hardcoded IDs.
]]

-- Direction offsets: N, NE, E, SE, S, SW, W, NW
local dirOffsets = {
  [North]     = { 0, -1},
  [NorthEast] = { 1, -1},
  [East]      = { 1,  0},
  [SouthEast] = { 1,  1},
  [South]     = { 0,  1},
  [SouthWest] = {-1,  1},
  [West]      = {-1,  0},
  [NorthWest] = {-1, -1}
}

-- Minimap colors 210-213 indicate stairs/holes/ramps/ladders
local function isFloorChange(tilePos)
  local color = g_map.getMinimapColor(tilePos)
  return color >= 210 and color <= 213
end

local wanderDelay = 0
local lastActivity = now
local idleThreshold = 10000 -- 10 seconds of idle before wandering

-- Reset idle timer on any player activity
onKeyPress(function() lastActivity = now end)
onTalk(function(name) if name == player:getName() then lastActivity = now end end)
onAttackingCreatureChange(function() lastActivity = now end)
onPlayerPositionChange(function() lastActivity = now end)
onUse(function() lastActivity = now end)
onUseWith(function() lastActivity = now end)

macro(200, "Wander", function()
  if now < wanderDelay then return end
  if now - lastActivity < idleThreshold then return end
  if g_game.isAttacking() then lastActivity = now return end

  local myPos = player:getPosition()
  local safeDirs = {}

  for dir, offset in pairs(dirOffsets) do
    local destPos = {x = myPos.x + offset[1], y = myPos.y + offset[2], z = myPos.z}
    local tile = g_map.getTile(destPos)
    if tile
      and tile:isWalkable()
      and not tile:hasCreature()
      and not isFloorChange(destPos)
    then
      table.insert(safeDirs, dir)
    end
  end

  if #safeDirs == 0 then return end

  local dir = safeDirs[math.random(#safeDirs)]
  walk(dir)

  -- Random delay between 1-3 seconds before next step
  wanderDelay = now + math.random(1000, 3000)
end)
