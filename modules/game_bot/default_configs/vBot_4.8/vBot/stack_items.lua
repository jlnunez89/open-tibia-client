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
    !text: tr('Stack Items')

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
  height: 175

  CheckBox
    id: stackAll
    anchors.top: parent.top
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Stack all stackable items
    width: 200

  CheckBox
    id: anyContainer
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Stack across all containers
    width: 200
    tooltip: Off = only within player-held containers. On = any open container.

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Interval (s):
    width: 70

  SpinBox
    id: intervalMin
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    width: 45
    height: 17
    minimum: 1
    maximum: 30
    step: 1
    text-align: center

  Label
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    text: to
    width: 14

  SpinBox
    id: intervalMax
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    width: 45
    height: 17
    minimum: 1
    maximum: 60
    step: 1
    text-align: center

  Label
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    text: s
    width: 10

  Label
    anchors.top: intervalMin.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Items to stack (if not 'all'):

  BotContainer
    id: StackItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 64
]])
edit:hide()

if not storage.stacker then
  storage.stacker = {
    enabled = false,
    stackAll = false,
    anyContainer = false,
    intervalMin = 2,
    intervalMax = 5,
    items = {}
  }
end

local config = storage.stacker
-- migrate old configs missing new fields
if config.intervalMin == nil then config.intervalMin = 2 end
if config.intervalMax == nil then config.intervalMax = 5 end

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

edit.stackAll:setChecked(config.stackAll)
edit.stackAll.onClick = function(widget)
  config.stackAll = not config.stackAll
  edit.stackAll:setChecked(config.stackAll)
end

edit.anyContainer:setChecked(config.anyContainer)
edit.anyContainer.onClick = function(widget)
  config.anyContainer = not config.anyContainer
  edit.anyContainer:setChecked(config.anyContainer)
end

edit.intervalMin:setValue(config.intervalMin)
edit.intervalMin.onValueChange = function(widget, value)
  config.intervalMin = value
  if config.intervalMax < value then
    config.intervalMax = value
    edit.intervalMax:setValue(value)
  end
end

edit.intervalMax:setValue(config.intervalMax)
edit.intervalMax.onValueChange = function(widget, value)
  config.intervalMax = value
  if config.intervalMin > value then
    config.intervalMin = value
    edit.intervalMin:setValue(value)
  end
end

UI.Container(function()
  config.items = edit.StackItems:getItems()
end, true, nil, edit.StackItems)
edit.StackItems:setItems(config.items)

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

local function wantItem(itemId, wantedIds, stackAll)
  if stackAll then return true end
  for _, id in ipairs(wantedIds) do
    if id == itemId then return true end
  end
  return false
end

-- Inventory slots that can hold stackable items (ammo, left hand for throwing weapons)
local stackableSlots = { SlotAmmo, SlotLeft }

local nextRun = 0
macro(200, function()
  if not config.enabled then return end
  if now < nextRun then return end
  local minMs = (config.intervalMin or 2) * 1000
  local maxMs = (config.intervalMax or 5) * 1000
  nextRun = now + math.random(minMs, maxMs)

  local wantedIds = properTable(config.items)
  if not config.stackAll and #wantedIds == 0 then return end

  -- Build a table of partial stacks: itemId -> { pos, spaceLeft, containerIndex }
  -- We track the first partial stack found per item, then try to merge subsequent ones into it.
  local toStack = {}  -- itemId -> { pos = position, space = int, cIndex = containerIndex }

  -- Phase 1: Check player inventory slots for partial stacks
  for _, slot in ipairs(stackableSlots) do
    local slotItem = getInventoryItem(slot)
    if slotItem and slotItem:isStackable() and slotItem:getCount() < 100 then
      local id = slotItem:getId()
      if wantItem(id, wantedIds, config.stackAll) and not toStack[id] then
        toStack[id] = {
          pos = { x = 65535, y = slot, z = 0 },
          space = 100 - slotItem:getCount(),
          cIndex = -1  -- sentinel: inventory slot
        }
      end
    end
  end

  -- Phase 2: Scan containers
  local containers = g_game.getContainers()
  for index, container in pairs(containers) do
    if not container.lootContainer then
      for i, item in ipairs(container:getItems()) do
        if item:isStackable() and item:getCount() < 100 then
          local id = item:getId()
          if wantItem(id, wantedIds, config.stackAll) then
            local existing = toStack[id]
            if existing then
              -- Check container safety: if anyContainer is off, only stack within
              -- player-held containers (same index or both are player containers)
              local safe = config.anyContainer or (existing.cIndex == index) or (existing.cIndex == -1)
              if safe then
                g_game.move(item, existing.pos, math.min(existing.space, item:getCount()))
                return
              end
            else
              toStack[id] = {
                pos = container:getSlotPosition(i - 1),
                space = 100 - item:getCount(),
                cIndex = index
              }
            end
          end
        end
      end
    end
  end
end)
