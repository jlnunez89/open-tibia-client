setDefaultTab("Main")

-- securing storage namespace
local panelName = "extras"
if not storage[panelName] then
  storage[panelName] = {}
end
local settings = storage[panelName]

-- basic elements
extrasWindow = UI.createWindow('ExtrasWindow', rootWidget)
extrasWindow:hide()
extrasWindow.closeButton.onClick = function(widget)
  extrasWindow:hide()
end

extrasWindow.onGeometryChange = function(widget, old, new)
  if old.height == 0 then return end
  
  settings.height = new.height
end

extrasWindow:setHeight(settings.height or 360)

-- available options for dest param
local rightPanel = extrasWindow.content.right
local leftPanel = extrasWindow.content.left

-- objects made by Kondrah - taken from creature editor, minor changes to adapt
local addCheckBox = function(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget('ExtrasCheckBox', dest)
  widget.onClick = function()
    widget:setOn(not widget:isOn())
    settings[id] = widget:isOn()
    if id == "checkPlayer" then
      local label = rootWidget.newHealer.targetSettings.vocations.title
      if not widget:isOn() then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! \nTurn on check players in extras to use this feature!")
      else
          label:setColor("#dfdfdf")
          label:setTooltip("")
      end
    end
  end
  widget:setText(title)
  widget:setTooltip(tooltip)
  if settings[id] == nil then
    widget:setOn(defaultValue)
  else
    widget:setOn(settings[id])
  end
  settings[id] = widget:isOn()
end

local addItem = function(id, title, defaultItem, dest, tooltip)
  local widget = UI.createWidget('ExtrasItem', dest)
  widget.text:setText(title)
  widget.text:setTooltip(tooltip)
  widget.item:setTooltip(tooltip)
  widget.item:setItemId(settings[id] or defaultItem)
  widget.item.onItemChange = function(widget)
    settings[id] = widget:getItemId()
  end
  settings[id] = settings[id] or defaultItem
end

local addTextEdit = function(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget('ExtrasTextEdit', dest)
  widget.text:setText(title)
  widget.textEdit:setText(settings[id] or defaultValue or "")
  widget.text:setTooltip(tooltip)
  widget.textEdit.onTextChange = function(widget,text)
    settings[id] = text
  end
  settings[id] = settings[id] or defaultValue or ""
end

local addScrollBar = function(id, title, min, max, defaultValue, dest, tooltip)
  local widget = UI.createWidget('ExtrasScrollBar', dest)
  widget.text:setTooltip(tooltip)
  widget.scroll.onValueChange = function(scroll, value)
    widget.text:setText(title .. ": " .. value)
    if value == 0 then
      value = 1
    end
    settings[id] = value
  end
  widget.scroll:setRange(min, max)
  widget.scroll:setTooltip(tooltip)
  if max-min > 1000 then
    widget.scroll:setStep(100)
  elseif max-min > 100 then
    widget.scroll:setStep(10)
  end
  widget.scroll:setValue(settings[id] or defaultValue)
  widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
end

UI.Button("vBot Settings and Scripts", function()
  extrasWindow:show()
  extrasWindow:raise()
  extrasWindow:focus()
end)
UI.Separator()

---- to maintain order, add options right after another:
--- add object
--- add variables for function (optional)
--- add callback (optional)
--- optionals should be addionaly sandboxed (if true then end)

-- Tibia 7.72 default tool ids: rope=3003, shovel=3457, machete=3308, scythe=3453.
addItem("rope", "Rope Item", 3003, leftPanel, "This item will be used in various bot related scripts as default rope item.")
addItem("shovel", "Shovel Item", 3457, leftPanel, "This item will be used in various bot related scripts as default shovel item.")
addItem("machete", "Machete Item", 3308, leftPanel, "This item will be used in various bot related scripts as default machete item.")
addItem("scythe", "Scythe Item", 3453, leftPanel, "This item will be used in various bot related scripts as default scythe item.")
addCheckBox("pathfinding", "CaveBot Pathfinding", true, leftPanel, "Cavebot will automatically search for first reachable waypoint after missing 10 goto's.")
addScrollBar("talkDelay", "Global NPC Talk Delay", 0, 2000, 1000, leftPanel, "Breaks between each talk action in cavebot (time in miliseconds).")
addScrollBar("looting", "Max Loot Distance", 0, 50, 40, leftPanel, "Every loot corpse futher than set distance (in sqm) will be ignored and forgotten.")
addScrollBar("lootDelay", "Loot Delay", 0, 1000, 200, leftPanel, "Wait time for loot container to open. Lower value means faster looting. \n WARNING if you are having looting issues(e.g. container is locked in closing/opnening), increase this value.")
addScrollBar("lootContainerClose", "Close Looted Corpse After", 0, 120, 30, leftPanel, "Seconds to wait before auto-closing an already looted corpse container. Prevents corpses from piling up while standing still. The server still closes them when you walk away.")
addScrollBar("huntRoutes", "Hunting Rounds Limit", 0, 300, 50, leftPanel, "Round limit for supply check, if character already made more rounds than set, on next supply check will return to city.")
addScrollBar("killUnder", "Kill monsters below", 0, 100, 1, leftPanel, "Force TargetBot to kill added creatures when they are below set percentage of health - will ignore all other TargetBot settings.")
addScrollBar("gotoMaxDistance", "Max GoTo Distance", 0, 127, 30, leftPanel, "Maximum distance to next goto waypoint for the bot to try to reach.")
addCheckBox("lootLast", "Start loot from last corpse", true, leftPanel, "Looting sequence will be reverted and bot will start looting newest bodies.")
addCheckBox("joinBot", "Join TargetBot and CaveBot", false, leftPanel, "Cave and Target tabs will be joined into one.")
addCheckBox("reachable", "Target only pathable mobs", false, leftPanel, "Ignore monsters that can't be reached.")

addCheckBox("title", "Custom Window Title", true, rightPanel, "Personalize OTCv8 window name according to character specific.")
if true then
  local vocText = ""

  if voc() == 1 or voc() == 11 then
      vocText = "- EK"
  elseif voc() == 2 or voc() == 12 then
      vocText = "- RP"
  elseif voc() == 3 or voc() == 13 then
      vocText = "- MS"
  elseif voc() == 4 or voc() == 14 then
      vocText = "- ED"
  end

  macro(5000, function()
    if settings.title then
      if hppercent() > 0 then
          g_window.setTitle("Tibia - " .. name() .. " - " .. lvl() .. "lvl " .. vocText)
      else
          g_window.setTitle("Tibia - " .. name() .. " - DEAD")
      end
    else
      g_window.setTitle("Tibia - " .. name())
    end
  end)
end

addCheckBox("separatePm", "Open PM's in new Window", false, rightPanel, "PM's will be automatically opened in new tab after receiving one.")
if true then
  onTalk(function(name, level, mode, text, channelId, pos)
    if mode == 4 and settings.separatePm then
        local g_console = modules.game_console
        local privateTab = g_console.getTab(name)
        if privateTab == nil then
            privateTab = g_console.addTab(name, true)
            g_console.addPrivateText(g_console.applyMessagePrefixies(name, level, text), g_console.SpeakTypesSettings['private'], name, false, name)
        end
        return
    end
  end)
end

addTextEdit("useAll", "Use All Hotkey", "space", rightPanel, "Set hotkey for universal actions - rope, shovel, scythe, use, open doors")
if true then
  -- Tibia 7.72 ids. Doors/ladders are too many to enumerate; useId covers
  -- common interactables (levers + ladder up). Tile-feature ids are the ones
  -- that actually accept the matching tool useWith().
  local useId = { 1945, 1946, 1948 }       -- levers (down/up), ladder up
  local shovelId = { 231, 351 }              -- sandy spot, small dirt pile
  local ropeId = { 384, 386, 394 }           -- rope holes / grates
  local macheteId = { 2782 }                 -- jungle grass
  local scytheId = { 2739 }                  -- wheat

  setDefaultTab("Tools")
  -- script
  if settings.useAll and settings.useAll:len() > 0 then
    hotkey(settings.useAll, function()
        for _, tile in pairs(g_map.getTiles(posz())) do
            if distanceFromPlayer(tile:getPosition()) < 2 then
                for _, item in pairs(tile:getItems()) do
                    -- use
                    if table.find(useId, item:getId()) then
                        use(item)
                        return
                    elseif table.find(shovelId, item:getId()) then
                        useWith(settings.shovel, item)
                        return
                    elseif table.find(ropeId, item:getId()) then
                        useWith(settings.rope, item) 
                        return
                    elseif table.find(macheteId, item:getId()) then
                        useWith(settings.machete, item)
                        return
                    elseif table.find(scytheId, item:getId()) then
                        useWith(settings.scythe, item)
                        return
                    end
                end
            end
        end
    end)
  end
end


addCheckBox("timers", "MW & WG Timers", true, rightPanel, "Show times for Magic Walls and Wild Growths.")
if true then
  local activeTimers = {}

  onAddThing(function(tile, thing)
    if not settings.timers then return end
    if not thing:isItem() then
      return
    end
    local timer = 0
    if thing:getId() == 2129 then -- mwall id
      timer = 20000 -- mwall time
    elseif thing:getId() == 2130 then -- wg id
      timer = 45000 -- wg time
    else
      return
    end

    local pos = tile:getPosition().x .. "," .. tile:getPosition().y .. "," .. tile:getPosition().z
    if not activeTimers[pos] or activeTimers[pos] < now then    
      activeTimers[pos] = now + timer
    end
    tile:setTimer(activeTimers[pos] - now)
  end)

  onRemoveThing(function(tile, thing)
    if not settings.timers then return end
    if not thing:isItem() then
      return
    end
    if (thing:getId() == 2129 or thing:getId() == 2130) and tile:getGround() then
      local pos = tile:getPosition().x .. "," .. tile:getPosition().y .. "," .. tile:getPosition().z
      activeTimers[pos] = nil
      tile:setTimer(0)
    end  
  end)
end


addCheckBox("antiKick", "Anti - Kick", true, rightPanel, "Turn every 10 minutes to prevent kick.")
if true then
  macro(600*1000, function()
    if not settings.antiKick then return end
    local dir = player:getDirection()
    turn((dir + 1) % 4)
    schedule(50, function() turn(dir) end)
  end)
end


-- removed for 7.7: "Skin Monsters" (post-7.7 corpse ids / skinning mechanics)


-- removed for 7.7: "Auto Reply Oberon" (Grand Master Oberon is post-7.7 content)


addCheckBox("autoOpenDoors", "Auto Open Doors", true, rightPanel, "Open doors when trying to step on them.")
if true then
  local doorsIds = { 5007, 8265, 1629, 1632, 5129, 6252, 6249, 7715, 7712, 7714, 
                     7719, 6256, 1669, 1672, 5125, 5115, 5124, 17701, 17710, 1642, 
                     6260, 5107, 4912, 6251, 5291, 1683, 1696, 1692, 5006, 2179, 5116, 
                     1632, 11705, 30772, 30774, 6248, 5735, 5732, 5120, 23873, 5736,
                     6264, 5122, 30049, 30042, 7727 }

  function checkForDoors(pos)
    local tile = g_map.getTile(pos)
    if tile then
      local useThing = tile:getTopUseThing()
      if useThing and table.find(doorsIds, useThing:getId()) then
        g_game.use(useThing)
      end
    end
  end

  onKeyPress(function(keys)
    local wsadWalking = modules.game_walking.wsadWalking
    if not settings.autoOpenDoors then return end
    local pos = player:getPosition()
    if keys == 'Up' or (wsadWalking and keys == 'W') then
      pos.y = pos.y - 1
    elseif keys == 'Down' or (wsadWalking and keys == 'S') then
      pos.y = pos.y + 1
    elseif keys == 'Left' or (wsadWalking and keys == 'A') then
      pos.x = pos.x - 1
    elseif keys == 'Right' or (wsadWalking and keys == 'D') then
      pos.x = pos.x + 1
    elseif wsadWalking and keys == "Q" then
      pos.y = pos.y - 1
      pos.x = pos.x - 1
    elseif wsadWalking and keys == "E" then
      pos.y = pos.y - 1
      pos.x = pos.x + 1
    elseif wsadWalking and keys == "Z" then
      pos.y = pos.y + 1
      pos.x = pos.x - 1
    elseif wsadWalking and keys == "C" then
      pos.y = pos.y + 1
      pos.x = pos.x + 1
    end
    checkForDoors(pos)
  end)
end


-- removed for 7.7: "Buy bless at login" (!bless command does not exist on 7.7)


addCheckBox("reUse", "Keep Crosshair", false, rightPanel, "Keep crosshair after using with item")
if true then
  local excluded = {268, 237, 238, 23373, 266, 236, 239, 7643, 23375, 7642, 23374, 5908, 5942} 

  onUseWith(function(pos, itemId, target, subType)
    if settings.reUse and not table.find(excluded, itemId) then
      schedule(50, function()
        item = findItem(itemId)
        if item then
          modules.game_interface.startUseWith(item)
        end
      end)
    end
  end)
end


addCheckBox("suppliesControl", "TargetBot off if low supply", false, leftPanel, "Turn off TargetBot if either one of supply amount is below 50% of minimum.")
if true then
  macro(500, function()
    if not settings.suppliesControl then return end
    if TargetBot.isOff() then return end
    if CaveBot.isOff() then return end
    if type(hasSupplies()) == 'table' then
        TargetBot.setOff()
    end
  end)
end

-- removed for 7.7: "Hold MW/WG" + Magic Wall / Wild Growth hotkeys
-- (no marker rune support / WG (3156) is post-7.7).

addCheckBox("checkPlayer", "Check Players", true, rightPanel, "Auto look on players and mark level and vocation on character model")
-- How long (in minutes) before we re-look a player we've already seen. Player
-- names are unique, so once we've identified someone we can remember them for a
-- long time; the only reason to re-look is to catch a level up / promotion, and
-- we don't need that to be fresh. Higher = fewer looks = stickier marks.
addScrollBar("checkPlayerTTL", "Look Again (minutes)", 30, 300, 30, rightPanel, "How long to remember a player before looking at them again to refresh their level/vocation. Higher values mean fewer, stickier looks.")
if true then
  local found
  -- Players we've already looked at, keyed by player NAME -> timestamp of the
  -- look. Names are unique, so keying by name (instead of the volatile creature
  -- id, which changes whenever a player leaves and re-enters our view) means we
  -- remember someone across re-encounters and don't keep re-looking them. This
  -- prevents the constant look spam (an obvious bot tell). We only refresh after
  -- the configurable TTL in case they leveled up or got promoted.
  local lookedAt = {}
  local function relookMs()
    return (tonumber(settings.checkPlayerTTL) or 30) * 60000
  end

  -- The vanilla 7.72 client renders a 15x11 tile viewport with the player
  -- centred, so a player is only actually on our screen when within 7 columns
  -- and 5 rows. Looking at anyone outside that box sends a look for a creature
  -- we can't really see - a dead giveaway - so we hard-limit to the viewport.
  local VIEW_X = 7
  local VIEW_Y = 5

  local function vocSuffix(t)
    -- t is the lowercased look text. Promoted names contain the base name, so
    -- the promoted form MUST be tested first.
    if t:find("master sorcerer") then return "MS"
    elseif t:find("sorcerer")     then return "S"
    elseif t:find("elder druid")  then return "ED"
    elseif t:find("druid")        then return "D"
    elseif t:find("elite knight") then return "EK"
    elseif t:find("knight")       then return "K"
    elseif t:find("royal paladin") then return "RP"
    elseif t:find("paladin")      then return "P"
    end
    return "" -- "has no vocation"
  end

  local function nextUnchecked()
    local ppos = player:getPosition()
    for i, spec in ipairs(getSpectators()) do
      if spec:isPlayer() and spec ~= player then
        local pos = spec:getPosition()
        if pos.z == ppos.z
            and math.abs(pos.x - ppos.x) <= VIEW_X
            and math.abs(pos.y - ppos.y) <= VIEW_Y then
          local last = lookedAt[spec:getName()]
          if not last or now - last > relookMs() then
            return spec
          end
        end
      end
    end
    return nil
  end

  macro(1000, function()
    if not settings.checkPlayer then return end
    -- Drop stale entries so the table stays bounded and players naturally get a
    -- refreshed look once the TTL has elapsed.
    local ttl = relookMs()
    for name, ts in pairs(lookedAt) do
      if now - ts > ttl then lookedAt[name] = nil end
    end
    local spec = nextUnchecked()
    if spec then
      g_game.look(spec)
      lookedAt[spec:getName()] = now -- record regardless of parse success
      found = now
    end
  end)

  local regex = [[You see ([^\(]*) \(Level ([0-9]*)\)((?:.)* of the ([\w ]*),|)]]
  onTextMessage(function(mode, text)
    if not settings.checkPlayer then return end

    local re = regexMatch(text, regex)
    if #re ~= 0 then
        local name = re[1][2]
        local level = re[1][3]
        local guild = re[1][5] or ""

        if guild:len() > 10 then
          guild = guild:sub(1,10) -- change to proper (last) values
          guild = guild.."..."
        end
        local voc = vocSuffix(text:lower())
        local creature = getCreatureByName(name)
        if creature then
            creature:setText("\n"..level..voc.."\n"..guild)
        end
        if found and now - found < 500 then
          modules.game_textmessage.clearMessages()
        end
    end
  end)
end

addCheckBox("nextBackpack", "Open Next Loot Container", true, leftPanel, "Auto open next loot container if full - has to have the same ID.")
  local function openNextLootContainer()
    if not settings.nextBackpack then return end
    local containers = getContainers()
    local lootCotaniersIds = CaveBot.GetLootContainers()

    for i, container in ipairs(containers) do
      local cId = container:getContainerItem():getId()
      if containerIsFull(container) then
        if table.find(lootCotaniersIds, cId) then
          for _, item in ipairs(container:getItems()) do
            if item:getId() == cId then
              return g_game.open(item, container)
            end
          end
        end
      end
    end
  end
if true then
  onContainerOpen(function(container, previousContainer)
    schedule(100, function()
      openNextLootContainer()
    end)
  end)

  onAddItem(function(container, slot, item, oldItem)
    schedule(100, function()
      openNextLootContainer()
    end)
  end)
end

addCheckBox("highlightTarget", "Highlight Current Target", true, rightPanel, "Additionaly hightlight current target with red glow")
if true then
  local function forceMarked(creature)
    if target() == creature then
        creature:setMarked("red")
        return schedule(333, function() forceMarked(creature) end)
    end
  end

  onAttackingCreatureChange(function(newCreature, oldCreature)
    if not settings.highlightTarget then return end
      if oldCreature then
          oldCreature:setMarked('')
      end
      if newCreature then
          forceMarked(newCreature)
      end
  end)
end