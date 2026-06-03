setDefaultTab("Tools")

-- Auto Fish
--
-- Picks a water tile adjacent to (or near) the player and uses a fishing rod
-- on it. Tile classification is by ground item id, because the "you see the
-- silvery movement of fish" message only fires when literally standing on
-- the next tile, which is not workable for a passive macro.
--
--   Fishable water (has fish):  ids 4597-4602
--   Plain water (no fish):      ids 4609-4614
--
-- Selection is weighted: by default 75% of casts target fish tiles and 25%
-- target plain water tiles, so the activity profile looks like a human who
-- occasionally guesses wrong rather than an aimbot that always hits the
-- exact "best" tile.
--
-- UI follows the Stack Items panel pattern: BotSwitch title + Edit button
-- that expands/collapses an options sub-panel.

if type(storage.autoFish) ~= "table" then storage.autoFish = {} end
local config = storage.autoFish
if config.enabled       == nil then config.enabled       = false end
if config.rodId         == nil then config.rodId         = 3483  end
if config.minDelayMs    == nil then config.minDelayMs    = 2500  end
if config.maxDelayMs    == nil then config.maxDelayMs    = 5500  end
if config.fishWeightPct == nil then config.fishWeightPct = 75    end
if config.minCap        == nil then config.minCap        = 5.2   end
config.maxDistance = nil  -- removed: search box is hardcoded to dx=+-7, dy=+-5.

-- Hardcoded search rectangle around the player. Asymmetric (wider than tall)
-- matches the typical Tibia viewport aspect.
local SEARCH_DX = 7
local SEARCH_DY = 5

-- Tile fail TTL: when the server replies "You cannot throw there." we
-- blacklist the most recently targeted tile for this many ms. Short enough
-- to recover when the player moves; long enough to avoid re-spamming the
-- same unreachable tile every tick.
local FAIL_TTL_MS = 8000

-- Exponential backoff bounds when the search box contains no fish/water at
-- all (e.g. player walked away from the lake). Doubles each tick from
-- BACKOFF_MIN_MS up to BACKOFF_MAX_MS, resets to 0 on the next successful
-- cast.
local BACKOFF_MIN_MS = 5000
local BACKOFF_MAX_MS = 5 * 60 * 1000

local WATER_WITH_FISH_IDS = {
  [618] = true,                                 
  [853] = true, [854] = true, [855] = true, [856] = true, [857] = true, [858] = true, [859] = true, [860] = true, [861] = true, [862] = true, [863] = true, [864] = true, 
  [4597] = true, [4598] = true, [4599] = true, [4600] = true, [4601] = true, [4602] = true,
  [4809] = true, [4810] = true, [4811] = true, [4812] = true, [4813] = true, [4814] = true, 
}

local WATER_WITHOUT_FISH_IDS = {
  [619] = true, [620] = true, [621] = true, [622] = true,
  [865] = true, [866] = true, [867] = true, [868] = true, [869] = true, 
  [4603] = true, [4604] = true, [4605] = true, [4606] = true, [4607] = true, [4608] = true, [4609] = true, [4610] = true, [4611] = true, [4612] = true, [4613] = true, [4614] = true,
  [4653] = true, [4654] = true, [4655] = true, 
}

local function isFishWaterId(id)
  return WATER_WITH_FISH_IDS[id] ~= nil
end
local function isPlainWaterId(id)
  return WATER_WITHOUT_FISH_IDS[id] ~= nil
end

------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Auto Fish')

  Button
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Edit
]])

local edit = setupUI([[
Panel
  height: 195

  Label
    id: rodLabel
    anchors.top: parent.top
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Rod item id:
    width: 100

  BotTextEdit
    id: rodId
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    margin-right: 3
    width: 50

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Cast delay (ms):

  BotTextEdit
    id: minDelay
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 2
    margin-left: 3
    width: 50

  Label
    id: castDelayTo
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    text: to

  BotTextEdit
    id: maxDelay
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    width: 50

  Label
    anchors.top: minDelay.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Minimum capacity:
    width: 100
    tooltip: Do not cast when free capacity is below this value (oz).

  BotTextEdit
    id: minCap
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    margin-right: 3
    width: 50

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Fish-tile bias %:
    width: 100
    tooltip: Chance a cast targets a known fish tile (4597-4602) instead of plain water (4609-4614).

  SpinBox
    id: fishWeight
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    width: 50
    height: 17
    minimum: 0
    maximum: 100
    step: 5
    text-align: center
]])
edit:hide()

local showEdit = false
ui.edit.onClick = function(widget)
  showEdit = not showEdit
  if showEdit then edit:show() else edit:hide() end
end

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  ui.title:setOn(config.enabled)
end

edit.rodId:setText(tostring(config.rodId))
edit.rodId.onTextChange = function(widget, text)
  local n = tonumber(text); if n then config.rodId = n end
end

edit.minDelay:setText(tostring(config.minDelayMs))
edit.minDelay.onTextChange = function(widget, text)
  local n = tonumber(text); if n then config.minDelayMs = math.max(500, n) end
end

edit.maxDelay:setText(tostring(config.maxDelayMs))
edit.maxDelay.onTextChange = function(widget, text)
  local n = tonumber(text); if n then config.maxDelayMs = math.max(config.minDelayMs, n) end
end

edit.minCap:setText(tostring(config.minCap))
edit.minCap.onTextChange = function(widget, text)
  local n = tonumber(text); if n then config.minCap = math.max(0, n) end
end

edit.fishWeight:setValue(config.fishWeightPct)
edit.fishWeight.onValueChange = function(widget, value)
  config.fishWeightPct = value
end

------------------------------------------------------------------------------
-- Casting macro
------------------------------------------------------------------------------

local nextCastAt = 0
local failedTiles = {}      -- key "x,y,z" -> expiresAtMs
local lastTargetKey = nil
local backoffMs = 0

local function tileKey(pos)
  return pos.x .. "," .. pos.y .. "," .. pos.z
end

-- Server replies "You cannot throw there." when the rod target is
-- unreachable (out of LOS, blocked, etc.). Blacklist the last targeted tile
-- for FAIL_TTL_MS so we don't keep slamming it.
onTextMessage(function(mode, text)
  if not text then return end
  if not lastTargetKey then return end
  if string.find(string.lower(text), "you cannot throw there") then
    failedTiles[lastTargetKey] = now + FAIL_TTL_MS
    lastTargetKey = nil
  end
end)

-- Classify a tile by its ground item id. Returns "fish", "water", or nil.
local function classifyTile(tile)
  if not tile then return nil end
  local ground = tile:getGround()
  if not ground then return nil end
  local id = ground:getId()
  if isFishWaterId(id)  then return "fish"  end
  if isPlainWaterId(id) then return "water" end
  return nil
end

-- Always-on macro driven by config.enabled (not a named macro) because the
-- BotSwitch above already owns the visual ON/OFF state and persistence.
macro(250, function()
  if not config.enabled then return end
  if now < nextCastAt then return end
  if not config.rodId or config.rodId <= 0 then return end
  local freeCap = player:getFreeCapacity()
  -- player:getFreeCapacity() reports capacity in 1/100 oz (e.g. 1000 = 10.00 oz
  -- in client). Divide minCap (which the user enters in display oz) by 100 to
  -- match the same unit before comparing.
  if freeCap and freeCap < ((config.minCap or 0) / 100) then return end
  local rod = findItem(config.rodId)
  if not rod then return end

  local pPos = player:getPosition()
  local fishTiles  = {}
  local waterTiles = {}
  for dx = -SEARCH_DX, SEARCH_DX do
    for dy = -SEARCH_DY, SEARCH_DY do
      if not (dx == 0 and dy == 0) then
        local pos  = {x = pPos.x + dx, y = pPos.y + dy, z = pPos.z}
        local key = tileKey(pos)
        local failUntil = failedTiles[key]
        if failUntil and failUntil <= now then
          failedTiles[key] = nil
          failUntil = nil
        end
        if not failUntil then
          local tile = g_map.getTile(pos)
          local kind = classifyTile(tile)
          if     kind == "fish"  then table.insert(fishTiles,  {tile=tile, pos=pos})
          elseif kind == "water" then table.insert(waterTiles, {tile=tile, pos=pos}) end
        end
      end
    end
  end

  if #fishTiles == 0 and #waterTiles == 0 then
    -- Exponential backoff: nothing in sight. Wait progressively longer
    -- before scanning again (up to BACKOFF_MAX_MS).
    backoffMs = (backoffMs > 0) and math.min(backoffMs * 2, BACKOFF_MAX_MS) or BACKOFF_MIN_MS
    nextCastAt = now + backoffMs
    return
  end

  local pool
  local bias = config.fishWeightPct or 75
  if #fishTiles > 0 and (#waterTiles == 0 or math.random(1, 100) <= bias) then
    pool = fishTiles
  else
    pool = waterTiles
  end
  local pick   = pool[math.random(1, #pool)]
  local tile   = pick.tile
  local target = tile:getTopUseThing() or tile:getGround()
  if not target then return end

  lastTargetKey = tileKey(pick.pos)
  backoffMs = 0
  g_game.useWith(rod, target)
  nextCastAt = now + math.random(config.minDelayMs, config.maxDelayMs)
end)
