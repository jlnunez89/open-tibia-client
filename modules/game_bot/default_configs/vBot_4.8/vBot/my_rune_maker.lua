setDefaultTab("Main")
UI.Separator()

local blankRuneId = 3147

-- ── UI: toggle + setup button ────────────────────────────────
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Rune Maker')

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Edit
]])

-- ── Config persistence ───────────────────────────────────────
if not storage.runeMaker then
  storage.runeMaker = {
    enabled = false,
    spellWords = "ad ura vita",
    manaCost = 100,
    spellRuneId = 3160,
    weaponId = 3305
  }
end

local config = storage.runeMaker

-- ── Bind toggle ──────────────────────────────────────────────
ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

-- ── Popup setup window ───────────────────────────────────────
local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local rmWindow = UI.createWindow('RuneMakerWindow', rootWidget)
  rmWindow:hide()

  ui.setup.onClick = function(widget)
    rmWindow:show()
    rmWindow:raise()
    rmWindow:focus()
  end

  rmWindow.closeButton.onClick = function(widget)
    rmWindow:hide()
  end

  rmWindow.spellWords:setText(config.spellWords)
  rmWindow.spellWords.onTextChange = function(widget, text)
    config.spellWords = text
  end

  rmWindow.manaCost:setText(tostring(config.manaCost))
  rmWindow.manaCost.onTextChange = function(widget, text)
    local val = tonumber(text)
    if val and val >= 1 then
      config.manaCost = val
    end
  end

  rmWindow.spellRune.onItemChange = function(widget)
    config.spellRuneId = widget:getItemId()
  end
  rmWindow.spellRune:setItemId(config.spellRuneId)

  rmWindow.weapon.onItemChange = function(widget)
    config.weaponId = widget:getItemId()
  end
  rmWindow.weapon:setItemId(config.weaponId)
end

-- ── Helper: move rune to player-held container ───────────────
local function moveRuneToBackpack(runeId)
    if not getLeft() or getLeft():getId() ~= runeId then return false end

    local backItem = getBack()
    if not backItem then return false end
    local backId = backItem:getId()

    local allContainers = getContainers()
    if not allContainers then return false end

    -- Build lookup by container item ID
    local byItemId = {}
    for index, container in pairs(allContainers) do
        local cid = container:getContainerItem():getId()
        if not byItemId[cid] then byItemId[cid] = {} end
        table.insert(byItemId[cid], { index = index, container = container })
    end

    -- BFS from back-slot to find player-held containers
    local playerContainers = {}
    local visited = {}
    local queue = {}

    if byItemId[backId] then
        for _, entry in ipairs(byItemId[backId]) do
            if not visited[entry.index] then
                visited[entry.index] = true
                playerContainers[entry.index] = entry.container
                table.insert(queue, entry.index)
            end
        end
    end

    local head = 1
    while head <= #queue do
        local idx = queue[head]
        head = head + 1
        for _, item in ipairs(playerContainers[idx]:getItems()) do
            if item:isContainer() then
                local subId = item:getId()
                if byItemId[subId] then
                    for _, entry in ipairs(byItemId[subId]) do
                        if not visited[entry.index] then
                            visited[entry.index] = true
                            playerContainers[entry.index] = entry.container
                            table.insert(queue, entry.index)
                        end
                    end
                end
            end
        end
    end

    -- Find a player container with room
    for _, container in pairs(playerContainers) do
        if not container.lootContainer and container:getItemsCount() < container:getCapacity() then
            g_game.move(getLeft(), container:getSlotPosition(container:getItemsCount()), getLeft():getCount())
            return true
        end
    end
    return false
end

-- ── Macro ────────────────────────────────────────────────────
local stuckCount = 0

macro(3000, function()
    if not config.enabled then return end
    if config.spellRuneId == 0 or config.weaponId == 0 then return end
    if config.spellWords == "" then return end

    local spellRuneId = config.spellRuneId
    local weaponId    = config.weaponId
    local manaCost    = config.manaCost
    local spellWords  = config.spellWords

    local leftItem    = getLeft()
    local emptyLeft   = leftItem == nil
    local leftIsBlank = not emptyLeft and leftItem:getId() == blankRuneId
    local leftIsRune  = not emptyLeft and leftItem:getId() == spellRuneId
    local blankRune   = findItem(blankRuneId)
    local readyToMake = mana() >= manaCost and (blankRune ~= nil or leftIsBlank)

    -- If a finished rune is still in hand, move it out first
    if leftIsRune then
        if not moveRuneToBackpack(spellRuneId) then
            stuckCount = stuckCount + 1
            if stuckCount >= 3 then
                warn("Rune Maker: all containers full, dropping rune to ground")
                g_game.move(leftItem, pos(), leftItem:getCount())
                stuckCount = 0
            end
        else
            stuckCount = 0
        end
        return
    end

    if not readyToMake then
        if emptyLeft then
            local weapon = findItem(weaponId)
            if weapon then
                moveToSlot(weapon, SlotLeft, weapon:getCount())
            end
        end
        return
    end

    -- Move blank rune to left hand if needed
    if not leftIsBlank then
        if blankRune then
            moveToSlot(blankRune, SlotLeft, blankRune:getCount())
        end
    end

    -- Sanity check: blank must be in hand to cast
    if not getLeft() or getLeft():getId() ~= blankRuneId then
        return
    end

    say(spellWords)

    -- Move the finished rune to backpack after a short delay
    schedule(math.random(1000, 2000), function() moveRuneToBackpack(spellRuneId) end)
end)
