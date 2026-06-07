setDefaultTab("Tools")

--[[
  Thrown Weapon Manager
  ---------------------
  Dedicated helper for Paladins (or anyone) using thrown weapons (spears,
  throwing knives, etc.). It does two jobs every cycle:

    1. REFILL: when the weapon hand runs low (or empty) it tops the hand back
       up from a stack in your backpacks, so attacking never pauses.

    2. RETRIEVE: it picks thrown weapons back up off the ground.

  Because thrown weapons are stackable and free capacity fluctuates while you
  fight, pickup is capacity-aware: you tell it how much one item weighs and it
  will only grab as many as you can carry -- splitting a ground stack and
  taking a partial amount when the whole pile would be too heavy.

  Default item is the 7.7 spear (id 3277, 20.00 oz, throw range 7).
]]

-- OTClient inventory slot numbers
local SLOT_RIGHT = 5
local SLOT_LEFT  = 6   -- weapon hand (where quiver_manager puts the bow)
local SLOT_AMMO  = 10

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Thrown Weapon')

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
  height: 216

  Label
    id: itemLabel
    anchors.top: parent.top
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Thrown weapon:

  BotItem
    id: weaponItem
    anchors.verticalCenter: itemLabel.verticalCenter
    anchors.right: parent.right
    margin-right: 4
    tooltip: The thrown weapon to manage (default: spear).

  Label
    id: handLabel
    anchors.top: itemLabel.bottom
    anchors.left: parent.left
    margin-top: 10
    margin-left: 3
    text: Refill to:

  ComboBox
    id: handPick
    anchors.verticalCenter: handLabel.verticalCenter
    anchors.left: handLabel.right
    anchors.right: parent.right
    margin-left: 6
    margin-right: 4
    height: 17
    tooltip: Which slot to refill. "Auto" detects where the weapon already is, otherwise uses an empty hand (left preferred). Pick a specific hand to force it.

  Label
    id: weightLabel
    anchors.top: handLabel.bottom
    anchors.left: parent.left
    margin-top: 9
    margin-left: 3
    text: Weight per item (oz):

  SpinBox
    id: unitWeight
    anchors.verticalCenter: weightLabel.verticalCenter
    anchors.right: parent.right
    margin-right: 4
    width: 55
    height: 17
    minimum: 1
    maximum: 1000
    step: 1
    text-align: center
    tooltip: Weight of a single item in ounces. A spear is 20 oz. Used to decide how many you can carry.

  Label
    id: refillLabel
    anchors.top: weightLabel.bottom
    anchors.left: parent.left
    margin-top: 9
    margin-left: 3
    text: Refill when count <=:

  SpinBox
    id: refillAt
    anchors.verticalCenter: refillLabel.verticalCenter
    anchors.right: parent.right
    margin-right: 4
    width: 55
    height: 17
    minimum: 0
    maximum: 99
    step: 1
    text-align: center
    tooltip: When the weapon hand has this many or fewer, top it back up from your backpacks.

  Label
    id: bufferLabel
    anchors.top: refillLabel.bottom
    anchors.left: parent.left
    margin-top: 9
    margin-left: 3
    text: Free cap buffer (oz):

  SpinBox
    id: capBuffer
    anchors.verticalCenter: bufferLabel.verticalCenter
    anchors.right: parent.right
    margin-right: 4
    width: 55
    height: 17
    minimum: 0
    maximum: 10000
    step: 10
    text-align: center
    tooltip: Reserve this much capacity. Pickup stops once free cap drops to this buffer (0 = use all capacity).

  Label
    id: rangeLabel
    anchors.top: bufferLabel.bottom
    anchors.left: parent.left
    margin-top: 9
    margin-left: 3
    text: Pickup range (tiles):

  SpinBox
    id: pickupRange
    anchors.verticalCenter: rangeLabel.verticalCenter
    anchors.right: parent.right
    margin-right: 4
    width: 55
    height: 17
    minimum: 1
    maximum: 10
    step: 1
    text-align: center
    tooltip: How far away (in tiles) the script will look for thrown weapons to retrieve.

  CheckBox
    id: walkToRetrieve
    anchors.top: rangeLabel.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 10
    margin-left: 3
    margin-right: 3
    text: Walk to retrieve distant
    tooltip: When checked, the character will walk to thrown weapons that are out of reach. May fight with CaveBot/TargetBot movement, so leave off if you only want to grab items right next to you.

  Label
    id: delayLabel
    anchors.top: walkToRetrieve.bottom
    anchors.left: parent.left
    margin-top: 10
    margin-left: 3
    text: Action delay (ms):
    tooltip: Random pause after each pickup/refill action. A new value between these limits is rolled each time to avoid a robotic fixed cadence.

  SpinBox
    id: delayMin
    anchors.top: delayLabel.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 3
    width: 55
    height: 17
    minimum: 0
    maximum: 10000
    step: 50
    text-align: center

  Label
    id: delayToLabel
    anchors.verticalCenter: delayMin.verticalCenter
    anchors.left: delayMin.right
    margin-left: 6
    text: to

  SpinBox
    id: delayMax
    anchors.verticalCenter: delayToLabel.verticalCenter
    anchors.left: delayToLabel.right
    margin-left: 6
    width: 55
    height: 17
    minimum: 0
    maximum: 10000
    step: 50
    text-align: center
]])
edit:hide()

if not storage.thrownWeapon then
  storage.thrownWeapon = {
    enabled = false,
    itemId = 3277,        -- spear (7.7)
    unitWeight = 20,      -- oz per item (spear = 20.00 oz)
    refillAt = 5,
    capBuffer = 0,
    pickupRange = 7,      -- spear throw range is 7
    walkToRetrieve = false,
    handSlot = "Auto",    -- Auto / Left / Right / Ammo
    delayMin = 200,
    delayMax = 500
  }
end

local config = storage.thrownWeapon
-- migrate old/partial configs
if config.itemId == nil then config.itemId = 3277 end
if config.unitWeight == nil then config.unitWeight = 20 end
if config.refillAt == nil then config.refillAt = 5 end
if config.capBuffer == nil then config.capBuffer = 0 end
if config.pickupRange == nil then config.pickupRange = 7 end
if config.walkToRetrieve == nil then config.walkToRetrieve = false end
if config.handSlot == nil then config.handSlot = "Auto" end
if config.delayMin == nil then config.delayMin = 200 end
if config.delayMax == nil then config.delayMax = 500 end

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

edit.weaponItem:setItemId(config.itemId)
edit.weaponItem.onItemChange = function(widget)
  config.itemId = widget:getItemId()
end

for _, opt in ipairs({ "Auto", "Left", "Right", "Ammo" }) do
  edit.handPick:addOption(opt)
end
edit.handPick:setOption(config.handSlot or "Auto")
edit.handPick.onOptionChange = function(widget)
  config.handSlot = widget:getCurrentOption().text
end

edit.unitWeight:setValue(config.unitWeight)
edit.unitWeight.onValueChange = function(widget, value) config.unitWeight = value end

edit.refillAt:setValue(config.refillAt)
edit.refillAt.onValueChange = function(widget, value) config.refillAt = value end

edit.capBuffer:setValue(config.capBuffer)
edit.capBuffer.onValueChange = function(widget, value) config.capBuffer = value end

edit.pickupRange:setValue(config.pickupRange)
edit.pickupRange.onValueChange = function(widget, value) config.pickupRange = value end

edit.walkToRetrieve:setChecked(config.walkToRetrieve)
edit.walkToRetrieve.onClick = function(widget)
  config.walkToRetrieve = not config.walkToRetrieve
  edit.walkToRetrieve:setChecked(config.walkToRetrieve)
end

edit.delayMin:setValue(config.delayMin)
edit.delayMin.onValueChange = function(widget, value) config.delayMin = value end

edit.delayMax:setValue(config.delayMax)
edit.delayMax.onValueChange = function(widget, value) config.delayMax = value end

-- How many of the weapon we can still pick up given current free capacity.
-- freecap() and the configured weights are both in whole ounces.
local function affordableCount()
  local unitW = math.max(1, config.unitWeight)
  local usable = freecap() - (config.capBuffer or 0)
  if usable < unitW then return 0 end
  return math.floor(usable / unitW)
end

-- Random throttle rolled fresh after each action (avoids a robotic cadence).
local function randomDelay()
  local lo = config.delayMin or 0
  local hi = config.delayMax or lo
  if hi < lo then hi = lo end
  if hi <= 0 then return 0 end
  return math.random(lo, hi)
end

-- Find the slot to refill. When the user forces a specific hand we always use
-- it (returning its current weapon count, or 0 when empty/holding something
-- else). In "Auto" mode we use the slot the weapon already occupies, otherwise
-- fall back to an empty hand (left preferred) so we never unequip other gear.
local function findWeaponSlot()
  local forced = ({ Left = SLOT_LEFT, Right = SLOT_RIGHT, Ammo = SLOT_AMMO })[config.handSlot]
  if forced then
    local it = getSlot(forced)
    if it and it:getId() ~= config.itemId then return nil, 0 end  -- occupied by other gear
    return forced, (it and it:getCount()) or 0
  end

  -- Auto
  for _, s in ipairs({ SLOT_LEFT, SLOT_RIGHT, SLOT_AMMO }) do
    local it = getSlot(s)
    if it and it:getId() == config.itemId then
      return s, it:getCount()
    end
  end
  if not getSlot(SLOT_LEFT) then return SLOT_LEFT, 0 end
  if not getSlot(SLOT_RIGHT) then return SLOT_RIGHT, 0 end
  return nil, 0
end

-- Where to put retrieved weapons. Preference order:
--   1. a container already holding the weapon (so it stacks)
--   2. a non-loot container with room
--   3. ANY container with room (last resort, so pickup never silently fails)
local function pickupDestination()
  local nonLootFallback = nil
  local anyFallback = nil
  for _, container in pairs(getContainers()) do
    local cname = container:getName():lower()
    local hasRoom = container:getItemsCount() < container:getCapacity()
    -- existing stack of the weapon: best target
    for slot, item in ipairs(container:getItems()) do
      if item:getId() == config.itemId and item:getCount() < 100 then
        return container:getSlotPosition(slot - 1)
      end
    end
    if hasRoom then
      if not anyFallback then
        anyFallback = container:getSlotPosition(container:getItemsCount())
      end
      if not nonLootFallback and not cname:find("loot") then
        nonLootFallback = container:getSlotPosition(container:getItemsCount())
      end
    end
  end
  return nonLootFallback or anyFallback
end

-- Move weapons from backpacks into the weapon hand when it runs low.
local function refillHand()
  local slot, handCount = findWeaponSlot()
  if not slot then return false end          -- both hands hold other gear
  if handCount > config.refillAt then return false end
  if handCount >= 100 then return false end

  local space = 100 - handCount
  for _, container in pairs(getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == config.itemId then
        local amount = math.min(item:getCount(), space)
        if amount >= 1 then
          g_game.move(item, { x = 65535, y = slot, z = 0 }, amount)
          return true
        end
      end
    end
  end
  return false
end

-- Pick thrown weapons back up off the ground (capacity-aware, partial stacks).
local function retrieve()
  local maxAffordable = affordableCount()
  if maxAffordable < 1 then return false end  -- too heavy to carry even one

  local playerPos = pos()
  local best = nil
  for _, tile in ipairs(g_map.getTiles(posz())) do
    local tp = tile:getPosition()
    local dist = math.max(math.abs(playerPos.x - tp.x), math.abs(playerPos.y - tp.y))
    if dist <= config.pickupRange then
      for _, item in ipairs(tile:getItems()) do
        if item:getId() == config.itemId and not item:isNotMoveable() then
          if not best or dist < best.dist then
            best = { item = item, tp = tp, dist = dist, count = item:getCount() }
          end
          break
        end
      end
    end
  end

  if not best then return false end

  if best.dist <= 1 then
    local dest = pickupDestination()
    if not dest then return false end
    -- take the whole pile, or only what we can carry (partial stack)
    local toPick = math.min(best.count, maxAffordable)
    g_game.move(best.item, dest, toPick)
    return true
  elseif config.walkToRetrieve then
    local path = findPath(playerPos, best.tp, 20, { ignoreNonPathable = false, precision = 1 })
    if path then
      autoWalk(best.tp, 20, { ignoreNonPathable = false, precision = 1 })
      return true
    end
  end
  return false
end

macro(200, function()
  if not config.enabled then return end
  if not config.itemId or config.itemId <= 100 then return end

  -- Keep the hand stocked first so attacking never stalls...
  if refillHand() then
    delay(randomDelay())
    return
  end
  -- ...then go reclaim what we have thrown.
  if retrieve() then
    delay(randomDelay())
  end
end)
