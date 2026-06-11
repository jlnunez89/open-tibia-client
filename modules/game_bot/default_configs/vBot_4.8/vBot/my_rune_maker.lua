setDefaultTab("Tools")
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
-- New format stores multiple named profiles so one client can hold a separate
-- rune-making setup per character (different words/mana/rune/weapon). Exactly
-- one profile is "active" (rm.active = index) and the macro always follows it.
local function defaultProfile(name)
  return {
    name = name or "Default",
    spellWords = "ad ura vita",
    manaCost = 100,
    spellRuneId = 3160,
    weaponId = 3305,
  }
end

-- Migrate the old single-config format (flat spellWords/manaCost/... on
-- storage.runeMaker) into a one-profile list, preserving the user's settings.
if storage.runeMaker and storage.runeMaker.profiles == nil then
  local old = storage.runeMaker
  storage.runeMaker = {
    enabled = old.enabled or false,
    active = 1,
    profiles = {
      {
        name = "Default",
        spellWords = old.spellWords or "ad ura vita",
        manaCost = old.manaCost or 100,
        spellRuneId = old.spellRuneId or 3160,
        weaponId = old.weaponId or 3305,
      },
    },
  }
end

if not storage.runeMaker then
  storage.runeMaker = { enabled = false, active = 1, profiles = { defaultProfile() } }
end

local runeMaker = storage.runeMaker

-- Always keep at least one profile and a valid active index.
if not runeMaker.profiles[1] then
  runeMaker.profiles = { defaultProfile() }
end
if type(runeMaker.active) ~= "number"
   or runeMaker.active < 1
   or runeMaker.active > #runeMaker.profiles then
  runeMaker.active = 1
end

-- Returns the currently active profile (the one the macro follows). Self-heals
-- a bad active index so callers never get nil.
local function activeProfile()
  local p = runeMaker.profiles[runeMaker.active]
  if not p then
    runeMaker.active = 1
    p = runeMaker.profiles[1]
  end
  return p
end

-- ── Bind toggle ──────────────────────────────────────────────
ui.title:setOn(runeMaker.enabled)
ui.title.onClick = function(widget)
  runeMaker.enabled = not runeMaker.enabled
  widget:setOn(runeMaker.enabled)
end

-- ── Popup setup window ───────────────────────────────────────
local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local rmWindow = UI.createWindow('RuneMakerWindow', rootWidget)
  rmWindow:hide()

  -- A readable one-line summary used as the list-row label.
  local function profileSummary(p)
    return (p.name ~= "" and p.name or "(unnamed)")
  end

  -- Load the active profile's values into the edit fields.
  local loadingFields = false
  local function loadFields()
    local p = activeProfile()
    loadingFields = true
    rmWindow.profileName:setText(p.name)
    rmWindow.spellWords:setText(p.spellWords)
    rmWindow.manaCost:setText(tostring(p.manaCost))
    rmWindow.spellRune:setItemId(p.spellRuneId)
    rmWindow.weapon:setItemId(p.weaponId)
    loadingFields = false
  end

  -- Rebuild the profile list; the active profile's row is focused/highlighted.
  local function refreshList()
    rmWindow.profileList:destroyChildren()
    for index, p in ipairs(runeMaker.profiles) do
      local row = UI.createWidget("RuneMakerProfileEntry", rmWindow.profileList)
      row:setText(profileSummary(p))
      row.onClick = function()
        runeMaker.active = index
        loadFields()
        rmWindow.profileList:focusChild(row)
      end
      if index == runeMaker.active then
        rmWindow.profileList:focusChild(row)
      end
    end
  end

  -- Keep the focused list row's label in sync while the name is edited.
  local function refreshActiveRowText()
    local row = rmWindow.profileList:getFocusedChild()
    if row then
      row:setText(profileSummary(activeProfile()))
    end
  end

  ui.setup.onClick = function(widget)
    refreshList()
    loadFields()
    rmWindow:show()
    rmWindow:raise()
    rmWindow:focus()
  end

  rmWindow.closeButton.onClick = function(widget)
    rmWindow:hide()
  end

  rmWindow.newButton.onClick = function(widget)
    table.insert(runeMaker.profiles, defaultProfile("Profile " .. (#runeMaker.profiles + 1)))
    runeMaker.active = #runeMaker.profiles
    refreshList()
    loadFields()
  end

  rmWindow.deleteButton.onClick = function(widget)
    if #runeMaker.profiles <= 1 then
      warn("Rune Maker: at least one profile must remain")
      return
    end
    table.remove(runeMaker.profiles, runeMaker.active)
    if runeMaker.active > #runeMaker.profiles then
      runeMaker.active = #runeMaker.profiles
    end
    refreshList()
    loadFields()
  end

  rmWindow.profileName.onTextChange = function(widget, text)
    if loadingFields then return end
    activeProfile().name = text
    refreshActiveRowText()
  end

  rmWindow.spellWords.onTextChange = function(widget, text)
    if loadingFields then return end
    activeProfile().spellWords = text
  end

  rmWindow.manaCost.onTextChange = function(widget, text)
    if loadingFields then return end
    local val = tonumber(text)
    if val and val >= 1 then
      activeProfile().manaCost = val
    end
  end

  rmWindow.spellRune.onItemChange = function(widget)
    if loadingFields then return end
    activeProfile().spellRuneId = widget:getItemId()
  end

  rmWindow.weapon.onItemChange = function(widget)
    if loadingFields then return end
    activeProfile().weaponId = widget:getItemId()
  end
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
    if not runeMaker.enabled then return end

    local config = activeProfile()
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
