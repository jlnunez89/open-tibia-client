setDefaultTab("Tools")

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Scavenge Items')

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
  height: 260

  CheckBox
    id: consolidate
    anchors.top: parent.top
    anchors.left: parent.left
    margin-top: 3
    margin-left: 3
    text: Consolidate (drop heaviest pile)
    width: 220
    tooltip: When backpack is full, drop the heaviest pile from the drop list to the ground and skip that spot.

  CheckBox
    id: dropFromScavenge
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 3
    text: Use scavenge list as drop list
    width: 220
    tooltip: When checked, the consolidate feature will drop from the scavenge item list instead of the separate drop list below.

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Skip duration (s):
    width: 95

  SpinBox
    id: skipTTL
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    width: 60
    height: 17
    minimum: 5
    maximum: 600
    step: 5
    text-align: center

  Label
    anchors.top: skipTTL.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Items to scavenge:

  BotContainer
    id: ScavengeItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 64

  Label
    id: dropLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Items to drop (consolidate):

  BotContainer
    id: DropItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32
]])
edit:hide()

if not storage.scavenge then
  storage.scavenge = {
    enabled = false,
    consolidate = false,
    dropFromScavenge = true,
    skipTTL = 30,
    items = {},
    dropItems = {}
  }
end

local config = storage.scavenge
-- migrate old configs missing new fields
if config.skipTTL == nil then config.skipTTL = 30 end
if config.consolidate == nil then config.consolidate = false end
if config.dropFromScavenge == nil then config.dropFromScavenge = true end
if config.dropItems == nil then config.dropItems = {} end

local showEdit = false
ui.edit.onClick = function(widget)
  showEdit = not showEdit
  if showEdit then
    edit:show()
  else
    edit:hide()
  end
end

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  ui.title:setOn(config.enabled)
end

edit.consolidate:setChecked(config.consolidate)
edit.consolidate.onClick = function(widget)
  config.consolidate = not config.consolidate
  edit.consolidate:setChecked(config.consolidate)
end

edit.skipTTL:setValue(config.skipTTL)
edit.skipTTL.onValueChange = function(widget, value)
  config.skipTTL = value
end

edit.dropFromScavenge:setChecked(config.dropFromScavenge)
local function updateDropListVisibility()
  local hidden = config.dropFromScavenge
  if hidden then
    edit.dropLabel:hide()
    edit.DropItems:hide()
  else
    edit.dropLabel:show()
    edit.DropItems:show()
  end
end
edit.dropFromScavenge.onClick = function(widget)
  config.dropFromScavenge = not config.dropFromScavenge
  edit.dropFromScavenge:setChecked(config.dropFromScavenge)
  updateDropListVisibility()
end
updateDropListVisibility()

UI.Container(function()
  config.items = edit.ScavengeItems:getItems()
end, true, nil, edit.ScavengeItems)
edit.ScavengeItems:setItems(config.items)

UI.Container(function()
  config.dropItems = edit.DropItems:getItems()
end, true, nil, edit.DropItems)
edit.DropItems:setItems(config.dropItems)

local function properTable(t)
  local r = {}
  for _, entry in pairs(t) do
    if type(entry) == "number" then
      table.insert(r, entry)
    elseif type(entry) == "table" and entry.id then
      table.insert(r, entry.id)
    end
  end
  return r
end

local function findLootContainer()
  for _, container in pairs(getContainers()) do
    if container:getItemsCount() < container:getCapacity() then
      return container
    end
  end
  return nil
end

-- Track items we failed to pick up (too heavy / not possible) so we skip them temporarily
local skipList = {}  -- key = "x,y,z,itemId" -> expiry timestamp

local function skipDurationMs()
  return (config.skipTTL or 30) * 1000
end

local function itemKey(tilePos, itemId)
  return tilePos.x .. "," .. tilePos.y .. "," .. tilePos.z .. "," .. itemId
end

local function posKey(tilePos)
  return tilePos.x .. "," .. tilePos.y .. "," .. tilePos.z
end

local function isSkipped(tilePos, itemId)
  local key = itemKey(tilePos, itemId)
  if skipList[key] and skipList[key] > now then
    return true
  end
  skipList[key] = nil
  return false
end

-- Weight index: itemId -> weight per single unit (in oz * 100, i.e. hundredths)
-- Built dynamically by looking at items and parsing the server response.
local weightIndex = {}      -- itemId -> weight per unit (number, e.g. 1500 = 15.00 oz)
local pendingLookId = nil   -- the itemId we're currently waiting for a look response
local pendingLookCount = 1  -- the count of the item we looked at (to derive per-unit weight)

local pendingPickup = nil -- tracks the item we're currently trying to pick up
local consolidateNeeded = false -- set true when a pickup fails due to weight/cap

onTextMessage(function(mode, text)
  if not config.enabled then return end

  -- Parse weight from look messages: "It weighs 15.00 oz."
  -- The server returns TOTAL weight for the stack, so divide by count to get per-unit.
  if pendingLookId then
    local w = text:match("weighs (%d+%.?%d*) oz")
    if w then
      local totalHundredths = math.floor(tonumber(w) * 100 + 0.5)
      local perUnit = math.floor(totalHundredths / (pendingLookCount or 1) + 0.5)
      weightIndex[pendingLookId] = perUnit
      pendingLookId = nil
      pendingLookCount = 1
      return
    end
  end

  -- Handle failed pickup
  if not pendingPickup then return end
  if text:find("too heavy") or
     text == "Sorry, not possible." or
     text == "You cannot put more objects in this container." or
     text == "There is not enough room." then
    skipList[pendingPickup] = now + skipDurationMs()
    pendingPickup = nil
    -- Signal consolidate on next cycle if it was a weight problem
    if config.consolidate and text:find("too heavy") then
      consolidateNeeded = true
    end
  end
end)

-- Periodically look at items in backpacks to learn their weight
local lastLookTime = 0
local LOOK_COOLDOWN = 1200  -- ms between look requests (avoid spamming server)

local function tryLearnWeights(itemIds)
  if now - lastLookTime < LOOK_COOLDOWN then return end
  -- If a previous look is still pending and stale (>3s), clear it
  if pendingLookId and now - lastLookTime > 3000 then
    pendingLookId = nil
  end
  if pendingLookId then return end

  -- Find a scavenge-target item in our backpacks whose weight we don't know yet
  for _, container in pairs(getContainers()) do
    for _, item in ipairs(container:getItems()) do
      local id = item:getId()
      if not weightIndex[id] then
        for _, wantedId in ipairs(itemIds) do
          if id == wantedId then
            pendingLookId = id
            pendingLookCount = item:getCount()
            lastLookTime = now
            g_game.look(item)
            return
          end
        end
      end
    end
  end
end

-- Find the heaviest cumulative scavenge-target pile in backpacks and drop it.
-- Uses weight index when available; falls back to count (highest total count wins).
local function dropHeaviestPile(itemIds)
  local wantedSet = {}
  for _, id in ipairs(itemIds) do wantedSet[id] = true end

  -- Tally: itemId -> { totalCount, totalWeight, entries = {{item}, ...} }
  local tally = {}
  for _, container in pairs(getContainers()) do
    for _, item in ipairs(container:getItems()) do
      local id = item:getId()
      if wantedSet[id] then
        if not tally[id] then
          tally[id] = { totalCount = 0, totalWeight = 0, entries = {} }
        end
        local count = item:getCount()
        tally[id].totalCount = tally[id].totalCount + count
        local unitWeight = weightIndex[id] or 0
        tally[id].totalWeight = tally[id].totalWeight + (unitWeight * count)
        table.insert(tally[id].entries, { item = item })
      end
    end
  end

  -- Pick the item type with the highest cumulative weight.
  -- If no weights are known yet, fall back to highest total count.
  local bestId = nil
  local bestScore = 0
  local hasAnyWeight = false
  for id, data in pairs(tally) do
    if data.totalWeight > 0 then hasAnyWeight = true end
  end
  for id, data in pairs(tally) do
    local score = hasAnyWeight and data.totalWeight or data.totalCount
    if score > bestScore then
      bestScore = score
      bestId = id
    end
  end

  if not bestId or not tally[bestId] then return false end

  -- Drop the first stack of this item to the player's tile
  local entry = tally[bestId].entries[1]
  if not entry then return false end

  local playerPos = pos()
  local dropPos = playerPos  -- default: player's own tile

  -- Try to find a reachable adjacent tile with an existing pile of the same item to stack onto
  if entry.item:isStackable() then
    for dx = -1, 1 do
      for dy = -1, 1 do
        local candidatePos = { x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z }
        local tile = g_map.getTile(candidatePos)
        if tile and tile:isWalkable() then
          for _, tileItem in ipairs(tile:getItems()) do
            if tileItem:getId() == bestId and tileItem:getCount() < 100 then
              dropPos = candidatePos
              goto foundTile
            end
          end
        end
      end
    end
    ::foundTile::
  end

  g_game.move(entry.item, dropPos, entry.item:getCount())

  -- Skip this tile+item so we don't immediately re-pick it up
  skipList[itemKey(dropPos, bestId)] = now + skipDurationMs()
  return true
end

macro(500, function()
  if not config.enabled then return end
  if TargetBot and TargetBot.isActive() then return end

  local itemIds = properTable(config.items)
  if #itemIds == 0 then return end

  -- Resolve drop list: either the scavenge list or the separate drop list
  local dropIds = config.dropFromScavenge and itemIds or properTable(config.dropItems)

  -- Passively learn item weights by looking at items in our backpacks
  if config.consolidate and #dropIds > 0 then
    tryLearnWeights(dropIds)
  end

  local playerPos = pos()
  local container = findLootContainer()

  -- Consolidate: when a pickup failed due to weight ("too heavy"),
  -- drop the heaviest scavenge-target pile from backpacks to ground to free cap.
  if config.consolidate and consolidateNeeded and #dropIds > 0 then
    consolidateNeeded = false
    if dropHeaviestPile(dropIds) then
      return  -- one action per cycle; freed cap, next cycle can try pickup again
    end
  end

  -- Estimate pickup weight for scoring: lower = better chance of success.
  -- Uses weight index if known, otherwise falls back to count as proxy.
  local function estimateWeight(item)
    local id = item:getId()
    local count = item:getCount()
    local unitW = weightIndex[id]
    if unitW and unitW > 0 then
      return unitW * count  -- hundredths of oz
    end
    return count * 10000  -- unknown weight: use count as proxy (scaled so it sorts after known)
  end

  -- Collect candidates: adjacent (dist <= 1) and distant
  local adjacentCandidates = {}  -- { item, tilePos, weight }
  local distantCandidates = {}   -- { item, tilePos, dist, weight }
  local NEARBY_RADIUS = 5  -- within this range, prefer lighter items over closer ones

  for _, tile in ipairs(g_map.getTiles(posz())) do
    local tilePos = tile:getPosition()
    local dist = math.max(math.abs(playerPos.x - tilePos.x), math.abs(playerPos.y - tilePos.y))

    for _, item in ipairs(tile:getItems()) do
      if item:isNotMoveable() then goto nextItem end

      local id = item:getId()
      for _, wantedId in ipairs(itemIds) do
        if id == wantedId and not isSkipped(tilePos, id) then
          if dist <= 1 then
            table.insert(adjacentCandidates, { item = item, tilePos = tilePos, weight = estimateWeight(item) })
          else
            local path = findPath(playerPos, tilePos, 20, { ignoreNonPathable = false, precision = 1 })
            if path then
              table.insert(distantCandidates, { item = item, tilePos = tilePos, dist = dist, weight = estimateWeight(item) })
            end
          end
          break  -- matched; no need to check remaining wantedIds
        end
      end

      ::nextItem::
    end
  end

  -- Pick up adjacent items: lightest first (most likely to succeed, avoids "too heavy")
  if #adjacentCandidates > 0 and container then
    table.sort(adjacentCandidates, function(a, b) return a.weight < b.weight end)
    local pick = adjacentCandidates[1]
    local item = pick.item
    local id = item:getId()
    pendingPickup = itemKey(pick.tilePos, id)
    -- Try stacking into an existing pile first
    local targetPos = nil
    if item:isStackable() then
      for slot, cItem in ipairs(container:getItems()) do
        if cItem:getId() == id and cItem:getCount() < 100 then
          targetPos = container:getSlotPosition(slot - 1)
          break
        end
      end
    end
    if not targetPos then
      targetPos = container:getSlotPosition(container:getItemsCount())
    end
    g_game.move(item, targetPos, item:getCount())
    return
  end

  -- Walk toward a distant item: nearby = lightest first, far = closest first
  if #distantCandidates > 0 then
    -- Sort: items within NEARBY_RADIUS by weight ascending, then by distance ascending
    table.sort(distantCandidates, function(a, b)
      local aNear = a.dist <= NEARBY_RADIUS
      local bNear = b.dist <= NEARBY_RADIUS
      if aNear and bNear then
        return a.weight < b.weight  -- both nearby: prefer lighter
      elseif aNear then
        return true  -- a is nearby, b is far: prefer a
      elseif bNear then
        return false -- b is nearby, a is far: prefer b
      else
        return a.dist < b.dist  -- both far: prefer closer
      end
    end)
    autoWalk(distantCandidates[1].tilePos, 20, { ignoreNonPathable = false, precision = 1 })
  end
end)
