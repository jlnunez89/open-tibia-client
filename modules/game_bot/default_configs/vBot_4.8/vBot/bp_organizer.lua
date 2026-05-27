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
    !text: tr('BP Organizer')

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
  height: 145

  CheckBox
    id: keepFreeSlot
    anchors.top: parent.top
    anchors.left: parent.left
    margin-top: 3
    margin-left: 3
    text: Keep 1 free slot (incomplete BPs)
    width: 220
    tooltip: Leave one empty slot in backpacks that are not yet complete (20 matching items).

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Money items:
    width: 180

  BotContainer
    id: MoneyItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    margin-left: 3
    text: Blank rune:
    width: 180

  BotContainer
    id: BlankRune
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32
]])
edit:hide()

if not storage.bpOrganizer then
  storage.bpOrganizer = {
    enabled = false,
    keepFreeSlot = true,
    moneyItems = { { id = 3031, count = 1 }, { id = 3035, count = 1 }, { id = 3043, count = 1 } },
    blankRune = { { id = 3147, count = 1 } }
  }
end

local config = storage.bpOrganizer
if config.keepFreeSlot == nil then config.keepFreeSlot = true end

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

edit.keepFreeSlot:setChecked(config.keepFreeSlot)
edit.keepFreeSlot.onClick = function(widget)
  config.keepFreeSlot = not config.keepFreeSlot
  edit.keepFreeSlot:setChecked(config.keepFreeSlot)
end

UI.Container(function()
  config.moneyItems = edit.MoneyItems:getItems()
end, true, nil, edit.MoneyItems)
edit.MoneyItems:setItems(config.moneyItems)

UI.Container(function()
  config.blankRune = edit.BlankRune:getItems()
end, true, nil, edit.BlankRune)
edit.BlankRune:setItems(config.blankRune)

-- Helper: extract id list from container config
local function idSet(configItems)
  local s = {}
  for _, entry in pairs(configItems) do
    if type(entry) == "number" then
      s[entry] = true
    elseif type(entry) == "table" and entry.id then
      s[entry.id] = true
    end
  end
  return s
end

-- Collect player-held containers by walking the back-slot inventory.
-- Returns a map of containerIndex -> container for containers reachable
-- from the player's equipped backpack, or nil if no backpack equipped.
local function getPlayerContainers()
  local backItem = getBack()
  if not backItem then return nil end
  local backId = backItem:getId()

  local allContainers = getContainers()
  if not allContainers then return nil end

  -- Build a lookup: containerItemId -> list of {index, container}
  local byItemId = {}
  for index, container in pairs(allContainers) do
    local cid = container:getContainerItem():getId()
    if not byItemId[cid] then byItemId[cid] = {} end
    table.insert(byItemId[cid], { index = index, container = container })
  end

  -- BFS from back-slot item ID.  We find containers whose containerItem
  -- matches the back slot, then scan their contents for sub-containers
  -- that are also in the open container list.
  local result = {}  -- index -> container
  local visited = {} -- index -> true
  local queue = {}   -- list of container indices to explore

  -- Seed: all open containers whose item ID matches the back slot
  if byItemId[backId] then
    for _, entry in ipairs(byItemId[backId]) do
      if not visited[entry.index] then
        visited[entry.index] = true
        result[entry.index] = entry.container
        table.insert(queue, entry.index)
      end
    end
  end

  -- BFS: for each queued container, look at its items for sub-containers
  local head = 1
  while head <= #queue do
    local idx = queue[head]
    head = head + 1
    local container = result[idx]
    for _, item in ipairs(container:getItems()) do
      if item:isContainer() then
        local subId = item:getId()
        if byItemId[subId] then
          for _, entry in ipairs(byItemId[subId]) do
            if not visited[entry.index] then
              visited[entry.index] = true
              result[entry.index] = entry.container
              table.insert(queue, entry.index)
            end
          end
        end
      end
    end
  end

  return result
end

-- Detect the "role" of each container based on majority non-money, non-blank contents.
-- Returns: roles table, mainIndex
local function detectRoles(containers, moneySet, blankSet)
  local roles = {}
  local mainIndex = nil

  -- Main backpack = lowest container index (first opened from back slot)
  for index, _ in pairs(containers) do
    if mainIndex == nil or index < mainIndex then
      mainIndex = index
    end
  end

  for index, container in pairs(containers) do
    if index == mainIndex then
      roles[index] = { role = "main", affinityId = nil }
    else
      -- Tally non-money, non-blank items (ignore sub-containers too)
      local tally = {}
      for _, item in ipairs(container:getItems()) do
        local id = item:getId()
        if not moneySet[id] and not blankSet[id] and not item:isContainer() then
          tally[id] = (tally[id] or 0) + 1
        end
      end

      -- Find majority item
      local bestId = nil
      local bestCount = 0
      for id, count in pairs(tally) do
        if count > bestCount then
          bestCount = count
          bestId = id
        end
      end

      if bestId then
        roles[index] = { role = "rune_" .. bestId, affinityId = bestId }
      else
        roles[index] = { role = "mixed", affinityId = nil }
      end
    end
  end

  return roles, mainIndex
end

-- Check if a container is "complete": every slot holds the affinity item (no blanks, no junk).
local function isComplete(container, affinityId, blankSet)
  local cap = container:getCapacity()
  local count = container:getItemsCount()
  if count < cap then return false end
  for _, item in ipairs(container:getItems()) do
    local id = item:getId()
    if id ~= affinityId and not item:isContainer() then
      return false
    end
  end
  return true
end

-- Find a stackable slot in a container for the given item id.
-- Returns 0-based slot index, or nil.
local function findStackSlot(container, itemId)
  for slot, cItem in ipairs(container:getItems()) do
    if cItem:getId() == itemId and cItem:isStackable() and cItem:getCount() < 100 then
      return slot - 1
    end
  end
  return nil
end

-- Check if a container can physically accept an item.
local function hasRoom(container, itemId, keepFreeSlot, affinityId, blankSet)
  if findStackSlot(container, itemId) then return true end

  local cap = container:getCapacity()
  local count = container:getItemsCount()
  local freeSlots = cap - count
  if freeSlots <= 0 then return false end

  if not keepFreeSlot or not affinityId then return true end

  if freeSlots >= 2 then return true end

  -- freeSlots == 1 with keepFreeSlot: only allow if filling completes the container
  if itemId == affinityId then
    -- Count how many non-affinity, non-blank items remain (just the one free slot scenario)
    local nonAffinity = 0
    for _, cItem in ipairs(container:getItems()) do
      local id = cItem:getId()
      if id ~= affinityId and not (blankSet and blankSet[id]) and not cItem:isContainer() then
        nonAffinity = nonAffinity + 1
      end
    end
    if nonAffinity == 0 then return true end -- filling last slot = all affinity + blanks
  end
  return false
end

-- Move an item into a target container, using the correct slot.
local function moveToContainer(item, targetContainer)
  local id = item:getId()

  local stackSlot = findStackSlot(targetContainer, id)
  if stackSlot then
    g_game.move(item, targetContainer:getSlotPosition(stackSlot), item:getCount())
    return true
  end

  local count = targetContainer:getItemsCount()
  if count < targetContainer:getCapacity() then
    g_game.move(item, targetContainer:getSlotPosition(count), item:getCount())
    return true
  end

  return false
end

-- Find the best target container for an item.
-- Returns containerIndex or nil.
-- onlyIfSourceFull: for blank runes, only propose a move if the source is full
local function findTargetContainer(itemId, sourceIndex, roles, mainIndex, containers, moneySet, blankSet, keepFreeSlot, onlyIfSourceFull)
  -- Blank runes: only move them out if the source container is at capacity
  if blankSet[itemId] then
    local sourceContainer = containers[sourceIndex]
    if not onlyIfSourceFull or not sourceContainer then return nil end
    if sourceContainer:getItemsCount() < sourceContainer:getCapacity() then return nil end
    -- Find another non-complete rune container with room
    for index, role in pairs(roles) do
      if role.affinityId and index ~= sourceIndex and index ~= mainIndex then
        local container = containers[index]
        if not isComplete(container, role.affinityId, blankSet) and hasRoom(container, itemId, keepFreeSlot, role.affinityId, blankSet) then
          return index
        end
      end
    end
    -- Fallback to main
    if sourceIndex ~= mainIndex and hasRoom(containers[mainIndex], itemId, false, nil, nil) then
      return mainIndex
    end
    return nil
  end

  -- Money always goes to main
  if moneySet[itemId] then
    if sourceIndex == mainIndex then return nil end
    if hasRoom(containers[mainIndex], itemId, false, nil, nil) then
      return mainIndex
    end
    return nil
  end

  -- If already in a container with matching affinity, stay put
  local sourceRole = roles[sourceIndex]
  if sourceRole and sourceRole.affinityId == itemId then return nil end

  -- Find a non-complete container with matching affinity
  for index, role in pairs(roles) do
    if role.affinityId == itemId and index ~= sourceIndex then
      local container = containers[index]
      if hasRoom(container, itemId, keepFreeSlot, role.affinityId, blankSet) then
        return index
      end
    end
  end

  -- No matching affinity container: item belongs in main
  if sourceIndex ~= mainIndex and hasRoom(containers[mainIndex], itemId, false, nil, nil) then
    return mainIndex
  end
  return nil
end

macro(1000, function()
  if not config.enabled then return end

  local containers = getPlayerContainers()
  if not containers then return end

  local containerCount = 0
  for _ in pairs(containers) do containerCount = containerCount + 1 end
  if containerCount < 2 then return end

  local moneySet = idSet(config.moneyItems)
  local blankSet = idSet(config.blankRune)
  local keepFreeSlot = config.keepFreeSlot

  local roles, mainIndex = detectRoles(containers, moneySet, blankSet)
  if not mainIndex then return end

  -- Skip complete containers entirely (don't touch them at all)
  local skipContainers = {}
  for index, role in pairs(roles) do
    if role.affinityId and index ~= mainIndex then
      if isComplete(containers[index], role.affinityId, blankSet) then
        skipContainers[index] = true
      end
    end
  end

  -- PHASE 1: Evacuate misplaced items from non-complete affinity containers.
  for index, container in pairs(containers) do
    if not skipContainers[index] then
      local role = roles[index]
      if role and role.affinityId and index ~= mainIndex then
        for _, item in ipairs(container:getItems()) do
          local id = item:getId()
          -- Skip: affinity items and sub-containers
          if id ~= role.affinityId and not item:isContainer() then
            local targetIndex = findTargetContainer(id, index, roles, mainIndex, containers, moneySet, blankSet, keepFreeSlot, blankSet[id])
            if targetIndex and not skipContainers[targetIndex] then
              local targetContainer = containers[targetIndex]
              if targetContainer and moveToContainer(item, targetContainer) then
                return
              end
            end
          end
        end
      end
    end
  end

  -- PHASE 2: Move items from main/mixed into their correct affinity containers.
  for index, container in pairs(containers) do
    if not skipContainers[index] then
      for _, item in ipairs(container:getItems()) do
        if not item:isContainer() then
          local id = item:getId()
          local targetIndex = findTargetContainer(id, index, roles, mainIndex, containers, moneySet, blankSet, keepFreeSlot, blankSet[id])
          if targetIndex and not skipContainers[targetIndex] then
            local targetContainer = containers[targetIndex]
            if targetContainer and moveToContainer(item, targetContainer) then
              return
            end
          end
        end
      end
    end
  end
end)
