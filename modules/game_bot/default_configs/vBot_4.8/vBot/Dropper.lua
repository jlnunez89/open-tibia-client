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
    !text: tr('Dropper')

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
  height: 250
    
  Label
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Trash:

  BotContainer
    id: TrashItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

  Label
    anchors.top: prev.bottom
    margin-top: 5
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Use:

  BotContainer
    id: UseItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

  Label
    id: capLabel
    anchors.top: prev.bottom
    margin-top: 7
    margin-left: 3
    anchors.left: parent.left
    text-align: left
    text: Drop if below cap:

  SpinBox
    id: capThreshold
    anchors.verticalCenter: capLabel.verticalCenter
    anchors.right: parent.right
    margin-right: 4
    width: 60
    height: 17
    minimum: 0
    maximum: 99999
    step: 10
    text-align: center
    tooltip: Items in the bottom slot are dropped only while your free capacity is below this value.

  BotContainer
    id: CapItems
    anchors.top: capLabel.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 2
    height: 32

  CheckBox
    id: dropFromPlayerContainers
    anchors.top: CapItems.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    margin-left: 3
    margin-right: 3
    text: Drop from player-held containers
    tooltip: When checked, items inside containers you are carrying (and worn equipment) are dropped/used. Uncheck both this and the ground option to disable dropping entirely.

  CheckBox
    id: dropFromGroundContainers
    anchors.top: dropFromPlayerContainers.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    margin-left: 3
    margin-right: 3
    text: Drop from non-player-held containers
    tooltip: When checked, items inside ground containers (corpses, depots, etc.) are dropped/used. Uncheck both this and the player-held option to disable dropping entirely.

  CheckBox
    id: randomizeDrop
    anchors.top: dropFromGroundContainers.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    margin-left: 3
    margin-right: 3
    text: Randomize drop location
    tooltip: Drop onto a random one of the 8 tiles around you (only walkable tiles with movable items, avoiding stairs/holes/water/lava) instead of always the tile below you.
]])
edit:hide()

if not storage.dropper then
    storage.dropper = {
      enabled = false,
      trashItems = { 283, 284, 285 },
      useItems = { 21203, 14758 },
      capItems = { 21175 },
      capThreshold = 150,
      dropFromPlayerContainers = true,
      dropFromGroundContainers = true,
      randomizeDrop = false
    }
end

local config = storage.dropper
-- migrate old/partial configs
if config.capThreshold == nil then config.capThreshold = 150 end
if config.randomizeDrop == nil then config.randomizeDrop = false end
-- migrate the old single "only drop from player-held containers" toggle into the
-- new pair of complementary source checkboxes.
if config.dropFromPlayerContainers == nil then
  config.dropFromPlayerContainers = true
end
if config.dropFromGroundContainers == nil then
  -- old onlyPlayerContainers == true meant "ignore ground containers".
  config.dropFromGroundContainers = not config.onlyPlayerContainers
end
config.onlyPlayerContainers = nil

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

edit.capThreshold:setValue(config.capThreshold)
edit.capThreshold.onValueChange = function(widget, value)
  config.capThreshold = value
end

edit.dropFromPlayerContainers:setChecked(config.dropFromPlayerContainers)
edit.dropFromPlayerContainers.onClick = function(widget)
  config.dropFromPlayerContainers = not config.dropFromPlayerContainers
  edit.dropFromPlayerContainers:setChecked(config.dropFromPlayerContainers)
end

edit.dropFromGroundContainers:setChecked(config.dropFromGroundContainers)
edit.dropFromGroundContainers.onClick = function(widget)
  config.dropFromGroundContainers = not config.dropFromGroundContainers
  edit.dropFromGroundContainers:setChecked(config.dropFromGroundContainers)
end

edit.randomizeDrop:setChecked(config.randomizeDrop)
edit.randomizeDrop.onClick = function(widget)
  config.randomizeDrop = not config.randomizeDrop
  edit.randomizeDrop:setChecked(config.randomizeDrop)
end

UI.Container(function()
    config.trashItems = edit.TrashItems:getItems()
    end, true, nil, edit.TrashItems) 
edit.TrashItems:setItems(config.trashItems)

UI.Container(function()
    config.useItems = edit.UseItems:getItems()
    end, true, nil, edit.UseItems) 
edit.UseItems:setItems(config.useItems)

UI.Container(function()
    config.capItems = edit.CapItems:getItems()
    end, true, nil, edit.CapItems) 
edit.CapItems:setItems(config.capItems)

local function properTable(t)
    local r = {}
  
    for _, entry in pairs(t) do
      table.insert(r, entry.id)
    end
    return r
end

-- True when the container is held by the player (a backpack/bag in inventory or
-- nested inside one) rather than sitting on the ground (corpse, depot, etc.).
-- Items inside the player's inventory report a special position with x == 0xFFFF.
local function isPlayerContainer(container)
    local cItem = container:getContainerItem()
    if not cItem then return false end
    local cPos = cItem:getPosition()
    return cPos and cPos.x == 0xFFFF
end

-- Picks where to drop an item. With "Randomize drop location" off this is just
-- the tile below the player (vanilla behaviour). With it on, returns a random
-- one of the 8 surrounding tiles that is safe to drop on: walkable, not a
-- stair/hole (so items don't fall through) and free of any non-moveable
-- obstacle. Falls back to the player's own tile when none qualify.
local function dropDestination()
    if not config.randomizeDrop then return pos() end
    local candidates = {}
    for _, tile in ipairs(getNearTiles(pos())) do
        local tpos = tile:getPosition()
        local minimapColor = g_map.getMinimapColor(tpos)
        local stairs = (minimapColor >= 210 and minimapColor <= 213)
        if tile:isWalkable() and not stairs and not tile:hasCreature() then
            local ground = tile:getGround()
            local groundId = ground and ground:getId() or 0
            local blocked = false
            for _, item in ipairs(tile:getItems()) do
                if item:getId() ~= groundId and item:isNotMoveable() then
                    blocked = true
                    break
                end
            end
            if not blocked then
                table.insert(candidates, tpos)
            end
        end
    end
    if #candidates == 0 then return pos() end
    return candidates[math.random(#candidates)]
end

-- Drop an item onto the chosen destination tile (honours randomize setting).
local function dropDropperItem(item)
    g_game.move(item, dropDestination(), item:getCount())
end

-- Performs the action for a matched item in the given priority pass and reports
-- whether anything was actually done. Pass 1 (cap items) only drops while free
-- capacity is below the threshold; when cap is fine it returns false so the scan
-- keeps going. The old `return cond and A or B` idiom returned false here too,
-- but because it was a `return` it ALSO aborted the whole macro tick -- so a
-- single cap item sitting in a bag (free cap fine) stopped the dropper before it
-- ever reached the use/trash passes or any non-player-held (ground) container.
local function handleDropperItem(pass, item)
    if pass == 1 then
        if freecap() < config.capThreshold then
            dropDropperItem(item)
            return true
        end
        return false
    elseif pass == 2 then
        use(item)
        return true
    else
        dropDropperItem(item)
        return true
    end
end

macro(200, function()
    if not config.enabled then return end
    -- Nothing to do if neither source is enabled.
    if not config.dropFromPlayerContainers and not config.dropFromGroundContainers then return end
    local tables = {properTable(config.capItems), properTable(config.useItems), properTable(config.trashItems)}

    local containers = getContainers()
    for i=1,3 do
        for _, container in pairs(containers) do
            local heldByPlayer = isPlayerContainer(container)
            local allowed = (heldByPlayer and config.dropFromPlayerContainers)
                          or (not heldByPlayer and config.dropFromGroundContainers)
            if allowed then
                for __, item in ipairs(container:getItems()) do
                    for ___, userItem in ipairs(tables[i]) do
                        if item:getId() == userItem then
                            if handleDropperItem(i, item) then return end
                            break
                        end
                    end
                end
            end
        end
        -- Worn inventory slots are player-held, so only scan them when player-held
        -- containers are enabled.
        if config.dropFromPlayerContainers then
            for slot = 1, 10 do
                local item = getInventoryItem(slot)
                if item then
                    for ___, userItem in ipairs(tables[i]) do
                        if item:getId() == userItem then
                            if handleDropperItem(i, item) then return end
                            break
                        end
                    end
                end
            end
        end
    end

end)