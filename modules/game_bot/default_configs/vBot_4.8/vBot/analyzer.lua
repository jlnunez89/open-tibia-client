--[[
  Bot-based Tibia 12 features v1.1
  made by Vithrax

  Credits also to:
  - Martín#2318
  - Lee#7725

  Thanks for ideas, graphics, functions, design tips!
  
  br, Vithrax
]]

-- here you can fix incorrect bosses names in cooldown messages
local BOSSES = {
  -- {in message, correct one}
  {"Scarlet Etzel", "Scarlett Etzel"},
  {"Leiden", "Ravenous Hunger"},
  {"Urmahlulu", "Urmahlullu"}
}

vBot.CaveBotData = vBot.CaveBotData or {
  refills = 0,
  rounds = 0,
  time = {},
  lastRefill = os.time(),
  refillTime = {}
}
local lootWorth = 0
local wasteWorth = 0
local balance = 0
local balanceDesc = ""
local hourDesc = ""
local desc = ""
local hour = ""
local launchTime = now
local startExp = exp()
-- Impact Analyzer data sources (all approximate on 7.72 - see the UI section):
local expTable = {}
local totalDmg = 0         -- total damage dealt (approx)
local totalDmgTaken = 0    -- total damage taken
local totalHeal = 0        -- total healing (approx)
local dmgDistribution = {}
-- Attacker breakdown is bounded to the same trailing window as the combat chart
-- (75 rounds x 2s = 150s) so the "top hitters" board stays consistent with it.
local DIST_WINDOW_MS = 150 * 1000
-- Skills Training (approx): bleed-frequency tracking (see the Skills Training panel)
local trainRoundsSinceBlood = 0
local trainMaxStreak = 0
local trainAttackRounds = 0
local trainBloodHits = 0
local trainRoundsLost = 0    -- attack rounds spent at >=10 rounds since blood (wasted)
local trainBloodFlag = false
local trainTargetPos = nil       -- last-known tile of our attack target
local trainTargetPosTime = 0     -- when trainTargetPos was captured (ms)
local first = {l="-", r="0"}
local second = {l="-", r="0"}
local third = {l="-", r="0"}
storage.bestHit = storage.bestHit or 0    -- hardest single hit we dealt (approx)
storage.worstHit = storage.worstHit or 0  -- hardest single hit we took
storage.bestHeal = storage.bestHeal or 0  -- biggest single heal tick (approx)
-- "Max (last ~2.5 min)" labels show the largest single per-round (2s) total seen
-- inside the trailing chart window, so the figure matches the peak the chart
-- itself draws. They are recomputed from these rolling buffers in the graph
-- macro. Declared here (not next to the main loop) so resetAnalyzerSessionData,
-- which is defined earlier in the file, can clear them on "Reset Session".
local GRAPH_CAPACITY = 75   -- keep in sync with AnalyzerGraph capacity (analyzer.otui)
local dmgRounds = {}
local takenRounds = {}
local healRounds = {}
local maxDmgRound = 0
local maxTakenRound = 0
local maxHealRound = 0
local function windowedMax(buf, val)
  buf[#buf + 1] = val
  while #buf > GRAPH_CAPACITY do
    table.remove(buf, 1)
  end
  local m = 0
  for i = 1, #buf do
    if buf[i] > m then m = buf[i] end
  end
  return m
end
-- Cumulative totals captured at the previous graph draw. The combat graphs plot
-- the per-round TOTAL (delta since last draw), so each point reflects ~2s of
-- activity (one attack round).
local lastDmgGraph = 0
local lastTakenGraph = 0
local lastHealGraph = 0
local lootedItems = {}
local useData = {}
local usedItems ={}
local lastDataSend = {0, 0}
local analyzerButton
local killList = {}
local membersData = {}
HuntingSessionStart = os.date('%Y-%m-%d, %H:%M:%S')

if not storage.analyzers then
  storage.analyzers = {
    trackedLoot = {},
    trackedBoss = {},
    outfits = {},
    customPrices = {},
    lootChannel = true,
    rarityFrames = true,
  }
end

storage.analyzers = storage.analyzers or {}
storage.analyzers.trackedLoot = storage.analyzers.trackedLoot or {}
storage.analyzers.trackedBoss = storage.analyzers.trackedBoss or {}
storage.analyzers.outfits = storage.analyzers.outfits or {}
local trackedLoot = storage.analyzers.trackedLoot

--destroy old windows
local windowsTable = {"MainAnalyzerWindow", 
                      "HuntingAnalyzerWindow", 
                      "LootAnalyzerWindow", 
                      "SupplyAnalyzerWindow", 
                      "DamageDealtAnalyzerWindow", 
                      "DamageTakenAnalyzerWindow", 
                      "HealingAnalyzerWindow", 
                      "XPAnalyzerWindow", 
                      "SkillsTrainingAnalyzerWindow", 
                      "PartyAnalyzerWindow", 
                      "DropTracker", 
                      "CaveBotStats",
                      "BossTracker"
                     }

                      for i, window in ipairs(windowsTable) do
  local element = g_ui.getRootWidget():recursiveGetChildById(window)

  if element then
    element:destroy()
  end
end

local mainWindow = UI.createMiniWindow("MainAnalyzerWindow")
mainWindow:hide()
mainWindow:setContentMaximumHeight(290)
local huntingWindow = UI.createMiniWindow("HuntingAnalyzer")
huntingWindow:hide()
local lootWindow = UI.createMiniWindow("LootAnalyzer")
lootWindow:hide()
lootWindow:setContentMaximumHeight(230)
local supplyWindow = UI.createMiniWindow("SupplyAnalyzer")
supplyWindow:hide()
local dealtWindow = UI.createMiniWindow("DamageDealtAnalyzer")
dealtWindow:hide()
dealtWindow:setContentMaximumHeight(220)
local takenWindow = UI.createMiniWindow("DamageTakenAnalyzer")
takenWindow:hide()
takenWindow:setContentMaximumHeight(340)
local healingWindow = UI.createMiniWindow("HealingAnalyzer")
healingWindow:hide()
healingWindow:setContentMaximumHeight(220)
local xpWindow = UI.createMiniWindow("XPAnalyzer")
xpWindow:hide()
xpWindow:setContentMaximumHeight(230)
local skillsTrainingWindow = UI.createMiniWindow("SkillsTrainingAnalyzer")
skillsTrainingWindow:hide()
skillsTrainingWindow:setContentMaximumHeight(320)
local settingsWindow = UI.createWindow("FeaturesWindow")
settingsWindow:hide()
local partyHuntWindow = UI.createMiniWindow("PartyAnalyzerWindow")
partyHuntWindow:hide()
local dropTrackerWindow = UI.createMiniWindow("DropTracker")
dropTrackerWindow:hide()
local statsWindow = UI.createMiniWindow("CaveBotStats")
statsWindow:hide()
local bossWindow = UI.createMiniWindow("BossTracker")
bossWindow:hide()

--f
local toggle = function()
    if mainWindow:isVisible() then
        analyzerButton:setOn(false)
        mainWindow:close()
    else
        analyzerButton:setOn(true)
        mainWindow:open()
    end
end

local drawGraph = function(graph, value)
    graph:addValue(value)
end

local toggleAnalyzer = function(window)
    if window:isVisible() then
        window:hide()
    else
        window:show()
    end
end

local function getSumStats()
  local totalWaste = 0
  local totalLoot = 0

  for k,v in pairs(membersData) do
    totalWaste = totalWaste + v.waste
    totalLoot = totalLoot + v.loot
  end

  local totalBalance = totalLoot - totalWaste

  return totalWaste, totalLoot, totalBalance
end

local function clipboardData()
  local totalWaste, totalLoot, totalBalance = getSumStats()
  local final = ""


  local first = "Session data: From " .. HuntingSessionStart .." to ".. os.date('%Y-%m-%d, %H:%M:%S')
  local second = "Session: " .. sessionTime()
  local third = "Loot Type: Market"
  local fourth = "Loot " .. format_thousand(totalLoot, true)
  local fifth = "Supplies " .. format_thousand(totalWaste, true)
  local six = "Balance " .. format_thousand(totalBalance, true)

  local t = {first, second, third, fourth, fifth, six}
  for i, string in ipairs(t) do
    final = final.. "\n"..string
  end

  --user data now
  for k,v in pairs(membersData) do
    final = final.. "\n".. k

    final = final.. "\n\tLoot "..v.loot
    final = final.. "\n\tSupplies "..v.waste
    final = final.. "\n\tBalance "..v.balance
    final = final.. "\n\tDamage "..v.damage
    final = final.. "\n\tHealing "..v.heal
  end

  g_window.setClipboardText(final)
end

-- create analyzers button
analyzerButton = modules.game_buttons.buttonsWindow.contentsPanel and modules.game_buttons.buttonsWindow.contentsPanel.buttons.botAnalyzersButton
analyzerButton = analyzerButton or modules.client_topmenu.getButton("botAnalyzersButton")
if analyzerButton then
    analyzerButton:destroy()
end

--button
analyzerButton = modules.client_topmenu.addRightGameToggleButton('botAnalyzersButton', 'vBot Analyzers', '/images/topbuttons/analyzers', toggle, false, 999999)
analyzerButton:setOn(false)

--toggles window
mainWindow.contentsPanel.HuntingAnalyzer.onClick = function()
    toggleAnalyzer(huntingWindow)
end
mainWindow.onClose = function()
  analyzerButton:setOn(false)
end
mainWindow.contentsPanel.LootAnalyzer.onClick = function()
    toggleAnalyzer(lootWindow)
end
mainWindow.contentsPanel.SupplyAnalyzer.onClick = function()
    toggleAnalyzer(supplyWindow)
end
mainWindow.contentsPanel.DamageDealtAnalyzer.onClick = function()
    toggleAnalyzer(dealtWindow)
end
mainWindow.contentsPanel.DamageTakenAnalyzer.onClick = function()
    toggleAnalyzer(takenWindow)
end
mainWindow.contentsPanel.HealingAnalyzer.onClick = function()
    toggleAnalyzer(healingWindow)
end
mainWindow.contentsPanel.XPAnalyzer.onClick = function()
    toggleAnalyzer(xpWindow)
end
mainWindow.contentsPanel.SkillsTraining.onClick = function()
    toggleAnalyzer(skillsTrainingWindow)
end
mainWindow.contentsPanel.Stats.onClick = function()
  toggleAnalyzer(statsWindow)
end

-- boss tracker
bossWindow.contentsPanel.search.onTextChange = function(widget, newText)
  newText = newText:lower()
  for i, child in ipairs(bossWindow.contentsPanel:getChildren()) do
    local text = child:getId():lower()
    if child:getId() ~= "search" then
      child:setVisible(text:find(newText))
    end
  end
end

-- on login
newTimeFormat = function(v) -- v in seconds
  local hours = string.format("%02.f", math.floor(v/3600))
  local mins = string.format("%02.f", math.floor(v/60 - (hours*60)))

  local final = hours.. "h "..mins.."min"
  return final
end

function createBossPanel(bossName, dueTime)
  local widget = bossWindow.contentsPanel[bossName] or UI.createWidget("BossCreaturePanel", bossWindow.contentsPanel)
  local outfit = storage.analyzers.outfits[bossName]

  widget.time = dueTime
  widget:setId(bossName)
  if outfit then
    widget.creature:setOutfit(outfit)
  else
    widget.creature:setTooltip("Outfit preview not available.\nTo get one you need to 'attack' ".. bossName.."\nOr you need to correct the boss name inside analyzers.lua file, const BOSSES")
  end
  widget.name:setText(bossName)

  local timeLeft = os.difftime(dueTime, os.time())
  if timeLeft > 0 then
    widget.cooldown:setText(newTimeFormat(timeLeft))
    widget.cooldown:setColor('#f29257')
  else
    widget.cooldown:setText("No Cooldown")
    widget.cooldown:setColor('#b8b8b8')
  end
end

for bossName, dueTime in pairs(storage.analyzers.trackedBoss) do
  createBossPanel(bossName, dueTime)
end

local bossRegex = [[You (?:can|may) challenge ([\w\W]*) again in ([\d]*)]]
onTalk(function(name, level, mode, text, channelId, pos)
  if mode == 34 then
    local re = regexMatch(text, bossRegex)
    local name = re and re[1] and re[1][2]
    local cd = re and re[1] and re[1][3]

    for i=1,#BOSSES do
      local bad = BOSSES[i][1]
      local good = BOSSES[i][2]

      if name == bad then
        name = good
      end
    end

    if not cd then return end

    cd = tonumber(cd) * 60 * 60 -- cd in seconds

    storage.analyzers.trackedBoss[name] = os.time() + cd
    createBossPanel(name, os.time() + cd)
  end
end)

-- save outfits
onAttackingCreatureChange(function(newCreature, oldCreature)
  local name = newCreature and newCreature:getName()
  local outfit = newCreature and newCreature:getOutfit()

  if name then
    storage.analyzers.outfits[name] = storage.analyzers.outfits[name] or outfit
  end
end)

--stats window
local totalRounds = UI.DualLabel("Total Rounds:", "0", {}, statsWindow.contentsPanel).right
local avRoundTime = UI.DualLabel("Time by Round:", "00:00h", {}, statsWindow.contentsPanel).right
UI.Separator(statsWindow.contentsPanel)
local totalRefills = UI.DualLabel("Total Refills:", "0", {}, statsWindow.contentsPanel).right
local avRefillTime = UI.DualLabel("Time by Refill:", "00:00h", {}, statsWindow.contentsPanel).right
local lastRefill = UI.DualLabel("Time since Refill:", "00:00h", {maxWidth = 200}, statsWindow.contentsPanel).right
UI.Separator(statsWindow.contentsPanel)
local label = UI.DualLabel("Supplies by Round:", "", {maxWidth = 200}, statsWindow.contentsPanel).left
label:setColor('#EC9706')
local suppliesByRound = UI.createWidget("AnalyzerItemsPanel", statsWindow.contentsPanel)
UI.Separator(statsWindow.contentsPanel)
label = UI.DualLabel("Supplies by Refill:", "", {maxWidth = 200}, statsWindow.contentsPanel).left
label:setColor('#ED7117')
local suppliesByRefill = UI.createWidget("AnalyzerItemsPanel", statsWindow.contentsPanel)
UI.Separator(statsWindow.contentsPanel)


--huntig
local sessionTimeLabel = UI.DualLabel("Session:", "00:00h", {}, huntingWindow.contentsPanel).right
local xpGainLabel = UI.DualLabel("XP Gain:", "0", {}, huntingWindow.contentsPanel).right
local xpHourLabel = UI.DualLabel("XP/h:", "0", {}, huntingWindow.contentsPanel).right
local lootLabel = UI.DualLabel("Loot:", "0", {}, huntingWindow.contentsPanel).right
local suppliesLabel = UI.DualLabel("Supplies:", "0", {}, huntingWindow.contentsPanel).right
local balanceLabel = UI.DualLabel("Balance:", "0", {}, huntingWindow.contentsPanel).right
-- Damage/Healing rows and the Killed Monsters list removed: the 7.72 server
-- sends no damage-dealt, healing or "Loot of <monster>" messages, so these
-- could never be tracked and always showed 0/empty.
UI.DualLabel("Looted items:", "", {maxWidth = 200}, huntingWindow.contentsPanel)
local lootList = UI.createWidget("AnalyzerListPanel", huntingWindow.contentsPanel)


--party
UI.Button("Copy to Clipboard", function() clipboardData() end, partyHuntWindow.contentsPanel)
UI.Button("Reset Sessions", function()
  if BotServer._websocket then
    BotServer.send("partyHunt", false)
  end
end, partyHuntWindow.contentsPanel)

local switch = addSwitch("sendData", "Send Analyzer Data", function(widget)
  widget:setOn(not widget:isOn())
  storage.sendPartyAnalyzerData = widget:isOn()
end, partyHuntWindow.contentsPanel)
switch:setOn(storage.sendPartyAnalyzerData)
UI.Separator(partyHuntWindow.contentsPanel)
local partySessionTimeLabel = UI.DualLabel("Session:", "00:00h", {}, partyHuntWindow.contentsPanel).right
local partyLootLabel = UI.DualLabel("Loot:", "0", {}, partyHuntWindow.contentsPanel).right
local partySuppliesLabel = UI.DualLabel("Supplies:", "0", {}, partyHuntWindow.contentsPanel).right
local partyBalanceLabel = UI.DualLabel("Balance:", "0", {}, partyHuntWindow.contentsPanel).right
UI.Separator(partyHuntWindow.contentsPanel)

local function maintainDropTable()
  local panel = dropTrackerWindow.contentsPanel

  for k,v in pairs(trackedLoot) do
    local widget = panel[k]
    if not widget then
      trackedLoot[k] = nil
    end
  end
end

local function createTrackedItems()
  local panel = dropTrackerWindow.contentsPanel

  for i, child in ipairs(panel:getChildren()) do
    if i > 2 then
      child:destroy()
    end
  end

  for k,v in pairs(trackedLoot) do
    local dropLoot = UI.createWidget("TrackerItem", dropTrackerWindow.contentsPanel)
    local item = dropLoot.item
    local name = dropLoot.name
    local drops = dropLoot.drops
    local id = tonumber(k)
    local itemName = id == 3031 and "gold coin" or id == 3035 and "platinum coin" or id == 3043 and "crystal coin" or Item.create(id):getMarketData().name

    dropLoot:setId(id)
    item:setItemId(id)
    if item:getItemCount() > 1 then
      item:setItemCount(1)
    end
    name:setText(itemName)
    drops:setText("Loot Drops: "..v)

    dropLoot.onDoubleClick = function()
      local id = dropLoot.item:getItemId()
      trackedLoot[tostring(id)] = 0
      drops:setText("Loot Drops: 0")
    end
  
    for i, child in pairs(dropLoot:getChildren()) do
      child:setTooltip("Double click to reset or clear item to remove.")
    end

    item.onItemChange = function(widget)
      local id = widget:getItemId()
      if id == 0 then 
        trackedLoot[widget:getParent():getId()] = nil
        if tonumber(widget:getParent():getId()) then
          widget:getParent():destroy()
          return
        end
        widget:setImageSource('/images/ui/item')
        widget:getParent():setId("blank")
        name:setText("Set Item to start track.")
        drops:setText("Loot Drops: 0")
        return 
      end

    -- only amount have changed, ignore
      if tonumber(widget:getParent():getId()) == id then return end
      local itemName = id == 3031 and "gold coin" or id == 3035 and "platinum coin" or id == 3043 and "crystal coin" or Item.create(id):getMarketData().name

      if trackedLoot[tostring(id)] then
        warn("vBot[Drop Tracker]: Item already added!")
        name:setText("Set Item to start track.")
        widget:setItemId(0)
        return 
      end
  
      widget:setImageSource('')
      drops:setText("Loot Drops: 0")
      name:setText(itemName)
      trackedLoot[tostring(id)] = trackedLoot[tostring(id)] or 0
      widget:getParent():setId(id)
      maintainDropTable()
    end
  end
end

--drop tracker
UI.Button("Add item to track drops", function()
  local dropLoot = UI.createWidget("TrackerItem", dropTrackerWindow.contentsPanel)
  local item = dropLoot.item
  local name = dropLoot.name
  local drops = dropLoot.drops

  item:setImageSource('/images/ui/item')

  dropLoot.onDoubleClick = function()
    local id = dropLoot.item:getItemId()
    trackedLoot[tostring(id)] = 0
    drops:setText("Loot Drops: 0")
  end

  for i, child in pairs(dropLoot:getChildren()) do
    child:setTooltip("Double click to reset or clear item to remove.")
  end

  item.onItemChange = function(widget)
    local id = widget:getItemId()

    if id == 0 then 
      trackedLoot[widget:getParent():getId()] = nil
      if tonumber(widget:getParent():getId()) then
        widget:getParent():destroy()
        return
      end
      widget:setImageSource('/images/ui/item')
      widget:getParent():setId("blank")
      name:setText("Set Item to start track.")
      drops:setText("Loot Drops: 0")
      return 
    end

    -- only amount have changed, ignore
    if tonumber(widget:getParent():getId()) == id then return end
    local itemName = id == 3031 and "gold coin" or id == 3035 and "platinum coin" or id == 3043 and "crystal coin" or Item.create(id):getMarketData().name

    if trackedLoot[tostring(id)] then
      warn("vBot[Drop Tracker]: Item already added!")
      name:setText("Set Item to start track.")
      widget:setItemId(0)
      return 
    end

    widget:setImageSource('')
    drops:setText("Loot Drops: 0")
    name:setText(itemName)
    trackedLoot[tostring(id)] = trackedLoot[tostring(id)] or 0
    widget:getParent():setId(id)
    maintainDropTable()
  end
end, dropTrackerWindow.contentsPanel)

UI.Separator(dropTrackerWindow.contentsPanel)
createTrackedItems()


--loot
local lootInLootAnalyzerLabel = UI.DualLabel("Gold Value:", "0", {}, lootWindow.contentsPanel).right
local lootHourInLootAnalyzerLabel = UI.DualLabel("Per Hour:", "0", {}, lootWindow.contentsPanel).right
UI.Separator(lootWindow.contentsPanel)
--//items panel
local lootItems = UI.createWidget("AnalyzerItemsPanel", lootWindow.contentsPanel)
UI.Separator(lootWindow.contentsPanel)
--//graph
local lootGraph = UI.createWidget("AnalyzerGraph", lootWindow.contentsPanel)
      lootGraph:setTitle("Loot/h")
      lootGraph:setShowLabels(true)
      drawGraph(lootGraph, 0)




--supplies
local suppliesInSuppliesAnalyzerLabel = UI.DualLabel("Gold Value:", "0", {}, supplyWindow.contentsPanel).right
local suppliesHourInSuppliesAnalyzerLabel = UI.DualLabel("Per Hour:", "0", {}, supplyWindow.contentsPanel).right
UI.Separator(supplyWindow.contentsPanel)
--//items panel
local supplyItems = UI.createWidget("AnalyzerItemsPanel", supplyWindow.contentsPanel)
UI.Separator(supplyWindow.contentsPanel)
--//graph
local supplyGraph = UI.createWidget("AnalyzerGraph", supplyWindow.contentsPanel)
      supplyGraph:setTitle("Waste/h")
      supplyGraph:setShowLabels(true)
      drawGraph(supplyGraph, 0)      




-- impact (split across three panels: Damage Dealt / Damage Taken / Healing)
-- On 7.72 the bot only sees three combat signals, so every figure here is an
-- approximation built from what the protocol actually exposes to the client:
--   * Damage dealt : APPROX. We have no "you deal X damage" message, so we read
--                    the floating damage numbers the server makes pop over the
--                    creatures around us. The animated-text colour is NOT given
--                    to Lua, so we can't perfectly tell our own hits from another
--                    hunter's - it's a "damage happening near me" estimate.
--   * Damage taken : EXACT. Parsed from "You lose N hitpoints due to an attack
--                    by <monster>" (TALK_STATUS_MESSAGE), which also feeds the
--                    per-monster breakdown below.
--   * Healing      : APPROX. Any positive change in our own HP (the 0x60 stats
--                    packet). We don't try to separate spell/potion healing from
--                    natural regeneration - any HP we gain counts.

--- damage dealt (approx) -> Damage Dealt panel
-- (the "(approx)" caveat now lives in the window title bar; the redundant
--  in-panel title label was removed to reclaim a row)
local totalDamageLabel = UI.DualLabel("Total:", "0", {}, dealtWindow.contentsPanel).right
local maxDpsLabel = UI.DualLabel("Max (last ~2.5 min):", "0", {maxWidth = 140}, dealtWindow.contentsPanel).right
local bestHitLabel = UI.DualLabel("Hardest Hit (session):", "0", {maxWidth = 140}, dealtWindow.contentsPanel).right
UI.Separator(dealtWindow.contentsPanel)
local dmgGraph = UI.createWidget("AnalyzerGraph", dealtWindow.contentsPanel)
      dmgGraph:setTitle("Damage/round")
      dmgGraph:setShowLabels(true)
      drawGraph(dmgGraph, 0)

--- damage taken -> Damage Taken panel
-- (redundant in-panel title label removed; the window title bar already says
--  "Damage Taken")
local totalTakenLabel = UI.DualLabel("Total:", "0", {}, takenWindow.contentsPanel).right
local maxDtpsLabel = UI.DualLabel("Max (last ~2.5 min):", "0", {maxWidth = 140}, takenWindow.contentsPanel).right
local worstHitLabel = UI.DualLabel("Hardest Hit (session):", "0", {maxWidth = 140}, takenWindow.contentsPanel).right
UI.Separator(takenWindow.contentsPanel)
local takenGraph = UI.createWidget("AnalyzerGraph", takenWindow.contentsPanel)
      takenGraph:setTitle("Damage Taken/round")
      takenGraph:setShowLabels(true)
      drawGraph(takenGraph, 0)

--- distribution -> Damage Taken panel (works for monsters AND players, so it
--- doubles as a PvP "top hitters" board)
UI.Separator(takenWindow.contentsPanel)
local title2 = UI.DualLabel("Damage Taken by Attacker", "", {maxWidth = 200}, takenWindow.contentsPanel).left
title2:setColor('#FABD02')
-- one row per attacker: a name/percent label with a thin bar beneath it showing
-- that attacker's share of the total damage taken, so the worst threats read at
-- a glance. Created interleaved so each bar sits directly under its own row.
local takenTops = {}
local takenBars = {}
for i=1,3 do
  local row = UI.DualLabel("-", "0", {maxWidth = 200}, takenWindow.contentsPanel)
  row.left:setWidth(135)
  takenTops[i] = row
  local bar = UI.createWidget("AnalyzerProgressBar", takenWindow.contentsPanel)
  bar:setBackgroundColor('#FF7F00')
  bar:setPercent(0)
  takenBars[i] = bar
end

--- healing (approx) -> Healing panel
-- (the "(approx)" caveat now lives in the window title bar; the redundant
--  in-panel title label was removed to reclaim a row)
local totalHealingLabel = UI.DualLabel("Total:", "0", {}, healingWindow.contentsPanel).right
local maxHpsLabel = UI.DualLabel("Max (last ~2.5 min):", "0", {maxWidth = 140}, healingWindow.contentsPanel).right
local bestHealLabel = UI.DualLabel("Best Tick (session):", "0", {maxWidth = 140}, healingWindow.contentsPanel).right
UI.Separator(healingWindow.contentsPanel)
local healGraph = UI.createWidget("AnalyzerGraphGreen", healingWindow.contentsPanel)
      healGraph:setTitle("Healing/round")
      healGraph:setShowLabels(true)
      drawGraph(healGraph, 0)


--xp
local xpGrainInXpLabel = UI.DualLabel("XP Gain:", "0", {}, xpWindow.contentsPanel).right
local xpHourInXpLabel = UI.DualLabel("XP/h:", "0", {}, xpWindow.contentsPanel).right
local nextLevelLabel = UI.DualLabel("Next Level:", "-", {}, xpWindow.contentsPanel).right
local progressBar = UI.createWidget("AnalyzerProgressBar", xpWindow.contentsPanel)
progressBar:setPercent(modules.game_skills.skillsWindow.contentsPanel.level.percent:getPercent())
UI.Separator(xpWindow.contentsPanel)
--//graph
local xpGraph = UI.createWidget("AnalyzerGraph", xpWindow.contentsPanel)
      xpGraph:setTitle("XP/h")
      xpGraph:setShowLabels(true)
      drawGraph(xpGraph, 0)


-- skills training (approx)
-- 7.72 rule of thumb: melee/distance/shielding skills only keep progressing if
-- you draw blood on your target at least once every ~10 attack rounds. We can't
-- see our own skill counter, so this is an approximation: a "round" is ~2s and
-- "blood" is a damage number popping on our CURRENT attack target. It can't tell
-- our hits from a partner's, so shared targets read optimistically.
local trainNote = UI.Label("Draw blood every <=10 hits.", skillsTrainingWindow.contentsPanel)
trainNote:setColor('#aaaaaa')
trainNote:setHeight(28)
local efficiencyLabel = UI.DualLabel("Efficiency:", "-", {maxWidth = 200}, skillsTrainingWindow.contentsPanel).right
local roundsSinceBloodLabel = UI.DualLabel("Rounds Since Blood:", "0", {maxWidth = 200}, skillsTrainingWindow.contentsPanel).right
local maxStreakLabel = UI.DualLabel("Worst Streak:", "0", {maxWidth = 200}, skillsTrainingWindow.contentsPanel).right
local roundsLostLabel = UI.DualLabel("Rounds Lost:", "0", {maxWidth = 200}, skillsTrainingWindow.contentsPanel).right
local attackRoundsLabel = UI.DualLabel("Attack Rounds:", "0", {maxWidth = 200}, skillsTrainingWindow.contentsPanel).right
local bloodHitsLabel = UI.DualLabel("Blood Hits:", "0", {maxWidth = 200}, skillsTrainingWindow.contentsPanel).right
local bleedRateLabel = UI.DualLabel("Bleed Rate:", "-", {maxWidth = 200}, skillsTrainingWindow.contentsPanel).right
UI.Separator(skillsTrainingWindow.contentsPanel)
--//graph
local trainGraph = UI.createWidget("AnalyzerGraphBlue", skillsTrainingWindow.contentsPanel)
      trainGraph:setTitle("Rounds Since Blood")
      trainGraph:setShowLabels(true)
      drawGraph(trainGraph, 0)
      




--#############################################
--#############################################   UI DONE
--#############################################
--#############################################
--#############################################
--#############################################

setDefaultTab("Main")
-- first, the variables

local console = modules.game_console
local regex = [[ ([^,|^.]+)]]
local noData = {}
local data = {}

local function getColor(v)
    if v >= 10000000 then -- 10kk, red
        return "#FF0000" 
    elseif v >= 5000000 then -- 5kk, orange
        return "#FFA500"
    elseif v >= 1000000 then -- 1kk, yellow
        return "#FFFF00"
    elseif v >= 100000 then -- 100k, purple
        return "#F25AED"
    elseif v >= 10000 then -- 10k, blue
        return "#5F8DF7"
    elseif v >= 1000 then -- 1k, green
        return "#00FF00"
    elseif v >= 50 then
        return "#FFFFFF" -- 50gp, white
    else
      return "#aaaaaa" -- less than 100gp, grey
    end
end

local function formatStr(str)
    if string.starts(str, "a ") then
        str = str:sub(2, #str)
    elseif string.starts(str, "an ") then
      str = str:sub(3, #str)
    end

    local n = getFirstNumberInText(str)
    if n then
        str = string.split(str, tostring(n))[1]
        str = str:sub(1,#str-1)
    end

    return str:trim()
end

local function getPrice(name)
    name = formatStr(name)
    name = name:lower()
    -- first check custom prices
    if storage.analyzers.customPrices[name] then
      return storage.analyzers.customPrices[name]
    end

    -- if already checked and no data skip looping items.lua
    if noData[name] then
        return 0
    end

    -- maybe was already checked, if so, skip looping items.lua
    if data[name] then
        return data[name]
    end

    -- searching in items.lua - big table, if possible skip
    for k,v in pairs(LootItems) do
        if name == k then
            data[name] = v
            return v
        end
    end

    -- if no data, save it and return 0
    noData[name] = true
    return 0
end

local expGained = function()
  return exp() - startExp
end

function format_thousand(v, comma)
  comma = comma and "," or "."
  if not v then return 0 end
  local s = string.format("%d", math.floor(v))
  local pos = string.len(s) % 3
  if pos == 0 then pos = 3 end
  return string.sub(s, 1, pos)
  .. string.gsub(string.sub(s, pos+1), "(...)", comma.."%1")
end

local expLeft = function()
  local level = lvl()+1
  return math.floor((50*level*level*level)/3 - 100*level*level + (850*level)/3 - 200) - exp()
end

niceTimeFormat = function(v, seconds) -- v in seconds
  local hours = string.format("%02.f", math.floor(v/3600))
  local mins = string.format("%02.f", math.floor(v/60 - (hours*60)))
  local secs = string.format("%02.f", math.floor(math.fmod(v, 60)))

  local final = string.format('%s:%s%s',hours,mins,seconds and ":"..secs or "")
 return final
end
local uptime
sessionTime = function()
  uptime = math.floor((now - launchTime)/1000)
  return niceTimeFormat(uptime)
end
sessionTime()

local expPerHour = function(calculation)
  local r = 0
  if #expTable > 0 then
      r = exp() - expTable[1]
  else
      return "-"
  end

  if uptime < 15*60 then
      r = math.ceil((r/uptime)*60*60)
  else
      r = math.ceil(r*8)
  end
  if calculation then
      return r
  else
      return format_thousand(r, true)
  end
end

local function add(t, text, color, last)
    table.insert(t, text)
    table.insert(t, color)
    if not last then
        table.insert(t, ", ")
        table.insert(t, "#FFFFFF")
    end
end

-- Bot Server
local function sendData()
  if BotServer._websocket then
    local totalDmg, totalHeal, lootWorth, wasteWorth, balance = getHuntingData()
    local outfit = player:getOutfit()
    outfit.mount = 0
    local t = {
      totalDmg, 
      totalHeal, 
      balance, 
      hppercent(), 
      manapercent(), 
      outfit, 
      player:isPartyLeader(), 
      lootWorth, 
      wasteWorth,
      modules.game_skills.skillsWindow.contentsPanel.stamina.value:getText(),
      format_thousand(expGained(), true),
      expPerHour(),
      balanceDesc .. " (" .. hourDesc .. ")",
      sessionTime()
    }

    -- validation
    if lastDataSend.totalDmg ~= t[1] and lastDataSend.totalHeal ~= t[2] then
      BotServer.send("partyHunt", t)
      lastDataSend[1] = t[1]
      lastDataSend[2] = t[2]
    end
  end
end

-- process data
if BotServer._websocket then
  BotServer.listen("partyHunt", function(name, message)
    if message == true then
      sendData()
    elseif message == false then
      resetAnalyzerSessionData()
    else
      membersData[name] = {
        damage = message[1], 
        heal = message[2], 
        balance = message[3], 
        hp = message[4], 
        mana = message[5], 
        outfit = message[6], 
        leader = message[7], 
        loot = message[8], 
        waste = message[9],
        stamina = message[10],
        expGained = message[11],
        expH = message[12],
        balanceH = message[13],
        session = message[14]
      }

      local widgetName = "Widget"..name
      local widget = partyHuntWindow.contentsPanel[widgetName] or UI.createWidget("MemberWidget", partyHuntWindow.contentsPanel)
      widget:setId(widgetName)
      widget.lastUpdate = now


      local t = membersData[name]
      widget.name:setText(name)
      widget.name:setColor("white")
      if t.leader then
        widget.name:setColor('#f8db38')
      end
      schedule(10*1000, function()
        if widget and widget.lastUpdate and now - widget.lastUpdate > 10000 then
          widget.name:setText(widget.name:getText().. " [inactive]")
          widget.name:setColor("#aeaeae")
          widget.health:setBackgroundColor("#aeaeae")
          widget.mana:setBackgroundColor("#aeaeae")
          widget.balance.value:setText("-")
          widget.damage.value:setText("-")
          widget.healing.value:setText("-")
          widget.creature:disable()
        end
      end)
      widget.creature:setOutfit(t.outfit)
      widget.health:setPercent(t.hp)
      widget.health:setBackgroundColor("#00c000")
      widget.mana:setPercent(t.mana)
      widget.mana:setBackgroundColor("#0000FF")
      widget.balance.value:setText(format_thousand(t.balance, true))
      if t.balance < 0 then
        widget.balance.value:setColor('#ff9854')
      elseif t.balance > 0 then
        widget.balance.value:setColor('#45ad25')
      else
        widget.balance.value:setColor('white')
      end
      widget.damage.value:setText(format_thousand(t.damage, true))
      widget.healing.value:setText(format_thousand(t.heal, true))

      widget.onDoubleClick = function()
        membersData[name] = nil
        widget:destroy()
      end

      --tooltip
      local tooltip = "Session: "..t.session.."\n"..
                      "Stamina: "..t.stamina.."\n"..
                      "Exp Gained: "..t.expGained.."\n"..
                      "Exp per Hour: "..t.expH.."\n"..
                      "Balance: "..t.balanceH

      widget.creature:setTooltip(tooltip)
    end
  end)
end


function hightlightText(widget, color, duration)
  for i=0,duration do
    schedule(i * 250, function()
      if i == duration or (i > 0 and i % 2 == 0) then
        widget:setColor("#FFFFFF")
      else
        widget:setColor(color)
      end
    end)
  end
end

local nameRegex = [[Loot of (?:an |a |the |)([^:]+)]]
onTextMessage(function(mode, text)
    if not storage.analyzers.lootChannel then return end
    if not text:find("Loot of") and not text:find("The following items are available in your reward chest") then return end
    local name

    -- adding monster to killed list
    if text:find("Loot of") then
      name = regexMatch(text, nameRegex)[1][2]
      if not killList[name] then
        killList[name] = 1
      else
        killList[name] = killList[name] + 1
      end
      refreshKills()
    end
    -- variables
    local split = string.split(text, ":")
    local re = regexMatch(split[2], regex)
    local combinedWorth = 0
    local formatted
    local div
    local t = {}
    local messageT = {}

    -- add timestamp, creature part and color it as white
    add(t, os.date('%H:%M') .. ' ' .. split[1]..": ", "#FFFFFF", true)
    add(messageT, split[1]..": ", "#FFFFFF", true)    

    -- main part
    if re ~= 0 then
        for i=1,#re do
            local data = re[i][2] -- each looted item
            local formattedLoot = regexMatch(data, [[(^[^(]+)]])[1][1]
            formattedLoot = formattedLoot:trim()
            local amount = getFirstNumberInText(formattedLoot) -- amount found in data
            local price = amount and getPrice(formattedLoot) * amount or getPrice(formattedLoot) -- if amount then multity price, else just take price
            local color = getColor(price) -- generate hex string based off price
            local messageColor = getColor(getPrice(formattedLoot))

            combinedWorth = combinedWorth + price -- add all prices to calculate total worth

            add(t, data, color, i==#re)
            add(messageT, data, color, i==#re)

            --drop tracker
            for i, child in ipairs(dropTrackerWindow.contentsPanel:getChildren()) do
              local childName = child.name
              childName = childName and childName:getText()


              if childName and formattedLoot:find(childName) then
                trackedLoot[tostring(child.item:getItemId())] = trackedLoot[tostring(child.item:getItemId())] + (amount or 1)
                child.drops:setText("Loot Drops: "..trackedLoot[tostring(child.item:getItemId())])

                hightlightText(child.name,"#f0b400", 8)
                modules.game_textmessage.messagesPanel.statusLabel:setVisible(true)
                modules.game_textmessage.messagesPanel.statusLabel:setColoredText({
                  "Valuable loot: ", "#f0b400",
                  childName.."", messageColor,
                  " dropped by "..name.."!", "#f0b400"
                })
                schedule(3000, function()
                  modules.game_textmessage.messagesPanel.statusLabel:setVisible(false)
                end)
              end
            end
        end
    end

    -- format total worth so it wont look obnoxious
    if combinedWorth >= 1000000 then
        div = combinedWorth/1000000
        formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "kk"
    elseif combinedWorth >= 1000 then
        div = combinedWorth/1000
        formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "k"
    else
        formatted = combinedWorth .. "gp"
    end

    if modules.game_textmessage.messagesPanel.centerTextMessagePanel.highCenterLabel:getText() == text then
      modules.game_textmessage.messagesPanel.centerTextMessagePanel.highCenterLabel:setColoredText(messageT)
      schedule(math.max(#text * 50, 2000), function() 
        modules.game_textmessage.messagesPanel.centerTextMessagePanel.highCenterLabel:setVisible(false)
      end)
    end

    -- add total worth to string
    add(t, " - (", "#FFFFFF", true)
    add(t, formatted, getColor(combinedWorth), true)
    add(t, ")", "#FFFFFF", true)

    -- get/create tab and write raw message
    local tabName = "vBot Loot"
    local tab = console.getTab(tabName) or console.addTab(tabName, true)
    console.addText(text, console.SpeakTypesSettings, tabName, "")

    -- find last message in given tab and rewrite it with formatted string
    local panel = console.consoleTabBar:getTabPanel(tab)
    local consoleBuffer = panel:getChildById('consoleBuffer')
    local message = consoleBuffer:getLastChild()
    message:setColoredText(t)
end)

local function niceFormat(v)
  local div
  local formatted
    if v >= 10000000 then
      div = v/10000000
      formatted = math.ceil(div) .. "M"
    elseif v >= 1000000 then
      div = v/1000000
      formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "M"
    elseif v >= 10000 then
      div = v/1000
      formatted = math.floor(div) .. "k"
    elseif v >= 1000 then
        div = v/1000
        formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "k"
    else
        formatted = v
    end
    return formatted
end

resetAnalyzerSessionData = function()
    vBot.CaveBotData = vBot.CaveBotData or {
      refills = 0,
      rounds = 0,
      time = {},
      lastRefill = os.time(),
      refillTime = {}
    }
    launchTime = now
    startExp = exp()
    expTable = {}
    totalDmg = 0
    totalDmgTaken = 0
    totalHeal = 0
    -- windowed max-per-round + per-round graph snapshots
    dmgRounds = {}
    takenRounds = {}
    healRounds = {}
    maxDmgRound = 0
    maxTakenRound = 0
    maxHealRound = 0
    lastDmgGraph = 0
    lastTakenGraph = 0
    lastHealGraph = 0
    -- hardest single hits / best heal tick (persisted in storage)
    storage.bestHit = 0
    storage.worstHit = 0
    storage.bestHeal = 0
    dmgDistribution = {}
    first = {l="-", r="0"}
    second = {l="-", r="0"}
    third = {l="-", r="0"}
    lootedItems = {}
    useData = {}
    usedItems ={}
    refreshLoot()
    refreshWaste()
    xpGraph:clear()
    drawGraph(xpGraph, 0)
    lootGraph:clear()
    drawGraph(lootGraph, 0)
    supplyGraph:clear()
    drawGraph(supplyGraph, 0)
    dmgGraph:clear()
    drawGraph(dmgGraph, 0)
    takenGraph:clear()
    drawGraph(takenGraph, 0)
    healGraph:clear()
    drawGraph(healGraph, 0)
    trainRoundsSinceBlood = 0
    trainMaxStreak = 0
    trainAttackRounds = 0
    trainBloodHits = 0
    trainRoundsLost = 0
    trainBloodFlag = false
    trainTargetPos = nil
    trainTargetPosTime = 0
    trainGraph:clear()
    drawGraph(trainGraph, 0)
    killList = {}
    refreshKills()
    HuntingSessionStart = os.date('%Y-%m-%d, %H:%M:%S')
end

mainWindow.contentsPanel.ResetSession.onClick = function()
  resetAnalyzerSessionData()
end

mainWindow.contentsPanel.Settings.onClick = function()
  settingsWindow:show()
  settingsWindow:raise()
  settingsWindow:focus()
end
  

-- extras window
settingsWindow.closeButton.onClick = function()
  settingsWindow:hide()
end

local function getFrame(v)
  if v >= 1000000 then
      return '/images/ui/rarity_gold'
  elseif v >= 100000 then
      return '/images/ui/rarity_purple'
  elseif v >= 10000 then
      return '/images/ui/rarity_blue'
  elseif v >= 1000 then
      return '/images/ui/rarity_green'
  else
      return '/images/ui/item'
  end
end


displayCondition = function(menuPosition, lookThing, useThing, creatureThing)
  if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
    return true
  end
end
local interface = modules.game_interface

local function setFrames()
  if not storage.analyzers.rarityFrames then return end
  for _, container in pairs(getContainers()) do
      local window = container.itemsPanel
      for i, child in pairs(window:getChildren()) do
          local id = child:getItemId()
          local price = 0

          if id ~= 0 then -- there's item
              local item = Item.create(id)
              local name = item:getMarketData().name:lower()
              price = getPrice(name)

              -- set rarity frame
              child:setImageSource(getFrame(price))
          else -- empty widget
              -- revert any possible changes
              child:setImageSource("/images/ui/item")
          end
          child.onHoverChange = function(widget, hovered)
            if id == 0 or not hovered then
              return interface.removeMenuHook('analyzer')
            end
            interface.addMenuHook('analyzer', 'Price:', function() end, displayCondition, price)          
        end
      end
  end 
end 
setFrames()

onContainerOpen(function(container, previousContainer)
  setFrames()
end)

onAddItem(function(container, slot, item, oldItem)
  setFrames()
end)

onRemoveItem(function(container, slot, item)
  setFrames()
end)

onContainerUpdateItem(function(container, slot, item, oldItem)
  setFrames()
end)

function smallNumbers(n)
  if n >= 10 ^ 6 then
      return string.format("%.1fkk", n / 10 ^ 6)
  elseif n >= 10 ^ 3 then
      return string.format("%.1fk", n / 10 ^ 3)
  else
      return tostring(n)
  end
end

function refreshList()
  local list = settingsWindow.CustomPrices
  list:destroyChildren()

  for name, price in pairs(storage.analyzers.customPrices) do
    local label = UI.createWidget("AnalyzerPriceLabel", list)
    label.remove.onClick = function()
      storage.analyzers.customPrices[name] = nil
      label:destroy()
      schedule(5, function()
        setFrames()
      end)
    end
    label:setText("["..name.."] = "..smallNumbers(price).." gp")
  end
end
refreshList()

settingsWindow.addItem.onClick = function()
  local newPrices = storage.analyzers.customPrices
  local id = settingsWindow.ID:getItemId()
  local newPrice = tonumber(settingsWindow.NewPrice:getText())

  if id < 100 then
    return warn("No item added!")
  end

  local name = Item.create(id):getMarketData().name

  if newPrices[name] then
    return warn("Item already added! Remove it from the list to set a new price!")
  end

  newPrices[name] = newPrice
  settingsWindow.ID:setItemId(0)
  settingsWindow.NewPrice:setText(0)
  schedule(5, function()
    setFrames()
  end)
  refreshList()
end

settingsWindow.LootChannel:setOn(storage.analyzers.lootChannel)
settingsWindow.LootChannel.onClick = function(widget)
  storage.analyzers.lootChannel = not storage.analyzers.lootChannel
  widget:setOn(storage.analyzers.lootChannel)
end

settingsWindow.RarityFrames:setOn(storage.analyzers.rarityFrames)
settingsWindow.RarityFrames.onClick = function(widget)
  storage.analyzers.rarityFrames = not storage.analyzers.rarityFrames
  widget:setOn(storage.analyzers.rarityFrames)
  setFrames()
end

local timeToLevel = function()
    local t = 0
    if expPerHour(true) == 0 or expPerHour() == "-" then
        return "-"
    else
        t = expLeft()/expPerHour(true)
        return niceTimeFormat(math.ceil(t*60*60))
    end
end

local sumT = function(t)
    local s = 0
    for i,v in pairs(t) do
        s = s + v.d
    end
    return s
end

-- The server message is "You lose N hitpoint(s) due to an attack by <name>."
-- (crmain.cc). <name> is the raw attacker name: monsters carry an article
-- ("a dragon", "an orc") while players are bare ("Bubba"). We capture the whole
-- name with [^.]+ and strip any leading article so BOTH monsters and players
-- are attributed - the distribution then doubles as a PvP "top hitters" board.
local regex = "You lose ([0-9]+) hitpoints? due to an attack by ([^.]+)"
onTextMessage(function(mode, text)
    -- Damage taken: exact, from the status message. Feeds the "Damage Taken"
    -- total/graph AND the per-attacker distribution below.
    if text:find("You lose") then
      local match = regexMatch(text, regex)
      local data = match ~= 0 and match[1]
      if data then
        local val = tonumber(data[2]) or 0
        local attacker = data[3]
        if attacker then
          -- drop the monster article; player names have none
          attacker = attacker:gsub("^[Aa]n? ", ""):gsub("^[Tt]he ", ""):trim()
        end
        if val > 0 and attacker and #attacker > 0 then
          totalDmgTaken = totalDmgTaken + val
          if val > storage.worstHit then
            storage.worstHit = val
          end
          table.insert(dmgDistribution, {v=val, m=attacker, t=now})
        end
      end
    end
end)

-- Damage dealt: APPROX. We have no "you deal X" message on 7.72, so we read the
-- floating damage numbers that pop over the creatures around us. The animated
-- text colour isn't exposed to Lua, so we filter by position: numbers on our
-- own tile are damage we TOOK (already handled above) and are ignored here;
-- everything else is treated as damage happening to nearby creatures.
onAnimatedText(function(thing, text)
  local value = tonumber((tostring(text):gsub("%D", "")))
  if not value or value <= 0 then return end

  local tpos = thing and thing.getPosition and thing:getPosition()
  if not tpos then return end
  local ppos = player:getPosition()
  if tpos.z ~= ppos.z then return end
  -- ignore numbers on our own tile (that's damage we took)
  if tpos.x == ppos.x and tpos.y == ppos.y then return end

  totalDmg = totalDmg + value
  if value > storage.bestHit then
    storage.bestHit = value
  end
end)

-- Healing: APPROX. Any positive change to our own HP (0x60 stats packet) counts
-- as healing; we don't separate spell/potion healing from natural regeneration.
local lastHp = nil
macro(100, function()
  local cur = hp()
  if lastHp == nil then lastHp = cur return end
  if cur > lastHp then
    local healed = cur - lastHp
    totalHeal = totalHeal + healed
    if healed > storage.bestHeal then
      storage.bestHeal = healed
    end
  end
  lastHp = cur
end)

-- Skills Training: "blood" = a damage number popping on our CURRENT attack
-- target. The floating number sits on the target's tile, so we match by
-- position; good enough for solo skill training.
--
-- KILLING-BLOW NOTE: when the final hit lands the creature dies, so the server
-- has already cleared g_game.getAttackingCreature() and removed the creature by
-- the time its damage number floats up. To still count that hit we cache the
-- target's last-known tile while it's alive (here and in the round macro) and
-- fall back to that very recent tile when there's no live target.
onAnimatedText(function(thing, text)
  local value = tonumber((tostring(text):gsub("%D", "")))
  if not value or value <= 0 then return end
  local tpos = thing and thing.getPosition and thing:getPosition()
  if not tpos then return end

  -- keep the target's tile fresh while it's alive
  local target = g_game.getAttackingCreature()
  if target and target.getPosition then
    local cpos = target:getPosition()
    if cpos then
      trainTargetPos = cpos
      trainTargetPosTime = now
    end
  end

  -- attribute "blood" to the live target tile, or its last-known tile if the
  -- target just died/cleared (freshness window covers one ~2s round).
  local matchPos = (trainTargetPos and now - trainTargetPosTime <= 4000) and trainTargetPos or nil
  if matchPos and tpos.x == matchPos.x and tpos.y == matchPos.y and tpos.z == matchPos.z then
    trainBloodFlag = true
  end
end)

-- One tick approximates one attack round (~2s). We count a round while we're
-- attacking; we ALSO run a tick when a blood flag is pending even if the target
-- is gone, so a KILLING BLOW (which clears the attack + removes the creature
-- before its damage number floats up) still gets counted instead of being held
-- over to the next target's first round.
macro(2000, function()
  local target = g_game.getAttackingCreature()
  local attacking = g_game.isAttacking() and target ~= nil
  if not attacking and not trainBloodFlag then return end
  -- keep the target's last-known tile fresh so a killing blow can still match
  if attacking and target.getPosition then
    local cpos = target:getPosition()
    if cpos then
      trainTargetPos = cpos
      trainTargetPosTime = now
    end
  end
  trainAttackRounds = trainAttackRounds + 1
  if trainBloodFlag then
    trainBloodHits = trainBloodHits + 1
    trainRoundsSinceBlood = 0
    trainBloodFlag = false
  else
    trainRoundsSinceBlood = trainRoundsSinceBlood + 1
    -- a round is "lost" once we've gone >=10 rounds without drawing blood
    if trainRoundsSinceBlood >= 10 then
      trainRoundsLost = trainRoundsLost + 1
    end
    if trainRoundsSinceBlood > trainMaxStreak then
      trainMaxStreak = trainRoundsSinceBlood
    end
  end
  drawGraph(trainGraph, trainRoundsSinceBlood)
end)

function capitalFistLetter(str)
  return (string.gsub(str, "^%l", string.upper))
end

-- tables maintance
macro(500, function()
  local dmgFinal = {}
  local labelTable = {}
  local dmgSum = 0
    table.insert(expTable, exp())
    if #expTable > 15*60 then
        for i,v in pairs(expTable) do
            if i == 1 then
              table.remove(expTable, i)
            end
        end
    end

    for i,v in pairs(dmgDistribution) do
      if now - v.t > DIST_WINDOW_MS then
        table.remove(dmgDistribution, i)
      else
        dmgSum = dmgSum + v.v
        if not dmgFinal[v.m] then
          dmgFinal[v.m] = v.v
        else
          dmgFinal[v.m] = dmgFinal[v.m] + v.v
        end
      end
    end

    first = dmgFinal[1] or {l="-", r="0", p=0}
    second = dmgFinal[2] or {l="-", r="0", p=0}
    third = dmgFinal[3] or {l="-", r="0", p=0}

    for k,v in pairs(dmgFinal) do
      table.insert(labelTable, {m=k, d=tonumber(v)})
    end

    table.sort(labelTable, function(a,b) return a.d > b.d end)

    for i,v in pairs(labelTable) do
      local pct = dmgSum > 0 and math.floor((v.d/dmgSum)*100) or 0
      local val = pct .. "%"
      local words = string.split(v.m, " ")
      local name = ""
      for i, word in ipairs(words) do
        name = name .. " " .. capitalFistLetter(word)
      end
      name = name:len() < 20 and name or name:sub(1,17).."..."
      name = name:trim()..": "
      if i == 1 then
        first = {l=name, r=val, p=pct}
      elseif i == 2 then
        second = {l=name, r=val, p=pct}
      elseif i == 3 then
        third = {l=name, r=val, p=pct}
      else
        break
      end
    end
end)

function getPanelHeight(panel)

  local elements = panel.List:getChildCount()
  if elements == 0 then
    return 0
  else
    local rows = math.ceil(elements/5)
    local height = rows * 35
    return height
  end
end

function refreshLoot()

    lootItems:destroyChildren()
    lootList:destroyChildren()

    for k,v in pairs(lootedItems) do
      local label1 = UI.createWidget("AnalyzerLootItem", lootItems)
      local price = v.count and getPrice(v.name) * v.count or getPrice(v.name)

      label1:setItemId(k)
      label1:setItemCount(50)
      label1:setShowCount(false)
      label1.count:setText(niceFormat(v.count))
      label1.count:setColor(getColor(price))
      local tooltipName = v.count > 1 and v.name.."s" or v.name
      label1:setTooltip(v.count .. "x " .. tooltipName .. " (Value: "..format_thousand(getPrice(v.name), true).."gp, Sum: "..format_thousand(price, true).."gp)")
      --hunting window loot list
      local label2 = UI.createWidget("ListLabel", lootList)
      label2:setText(v.count .. "x " .. v.name)
    end

    if lootItems:getChildCount() == 0 then
      local label = UI.createWidget("ListLabel", lootList)
      label:setText("None")
    end
end
refreshLoot()

function refreshKills()
    -- Killed-monsters list removed (no "Loot of <monster>" messages on 7.72).
end
refreshKills()

function refreshWaste()

    supplyItems:destroyChildren()
    suppliesByRefill:destroyChildren()
    suppliesByRound:destroyChildren()

    local parents = {supplyItems, suppliesByRound, suppliesByRefill}    

    for k,v in pairs(usedItems) do
      for i=1,#parents do
        local amount = i == 1 and v.count or 
                       i == 2 and v.count/(vBot.CaveBotData.rounds + 1) or 
                       i == 3 and v.count/(vBot.CaveBotData.refills + 1)
        amount = math.floor(amount)
        local label1 = UI.createWidget("AnalyzerLootItem", parents[i])
        local price = amount and getPrice(v.name) * amount or getPrice(v.name)

        label1:setItemId(k)
        label1:setItemCount(50)
        label1:setShowCount(false)
        label1.count:setText(niceFormat(amount))
        label1.count:setColor(getColor(price))
        local tooltipName = amount > 1 and v.name.."s" or v.name
        label1:setTooltip(amount .. "x " .. tooltipName .. " (Value: "..format_thousand(getPrice(v.name), true).."gp, Sum: "..format_thousand(price, true).."gp)")
      end
    end
end

-- loot analyzer
-- adding
local containers = CaveBot.GetLootContainers()
local lastCap = freecap()
onAddItem(function(container, slot, item, oldItem)
  if not table.find(containers, container:getContainerItem():getId()) then return end
  if isInPz() then return end
  if slot > 0 then return end 
  if freecap() >= lastCap then return end
  local name = item:getId()
  local tmpname = item:getId() == 3031 and "gold coin" or item:getId() == 3035 and "platinum coin" or item:getId() == 3043 and "crystal coin" or item:getMarketData().name
  if not lootedItems[name] then
    lootedItems[name] = { count = item:getCount(), name = tmpname }
  else
    lootedItems[name].count =  lootedItems[name].count + item:getCount()
  end
  lastCap = freecap()
  refreshLoot()

  -- drop tracker
end)

onContainerUpdateItem(function(container, slot, item, oldItem)
  if not table.find(containers, container:getContainerItem():getId()) then return end
  if not oldItem then return end
  if isInPz() then return end 
  if freecap() == lastCap then return end
  
  local tmpname = item:getId() == 3031 and "gold coin" or item:getId() == 3035 and "platinum coin" or item:getId() == 3043 and "crystal coin" or item:getMarketData().name
  local amount = item:getCount() - oldItem:getCount()
  if amount < 0 then
    return
  end
  local name = item:getId()
  if not lootedItems[name] then
      lootedItems[name] = { count = amount, name = tmpname }
  else
      lootedItems[name].count = lootedItems[name].count + amount
  end
  lastCap = freecap()
  refreshLoot()
end)

-- ammo
local ammo = {16143, 763, 761, 7365, 3448, 762, 21470, 7364, 14251, 3447, 3449, 15793, 25757, 774, 35901, 6528, 7363, 3450, 16141, 25758, 14252, 3446, 16142, 35902}
onContainerUpdateItem(function(container, slot, item, oldItem)
  local id = item:getId()
  if not table.find(ammo, id) then return end
  local newCount = item:getCount()
  local oldCount = oldItem:getCount()
  local name = item:getMarketData().name

  if oldCount - newCount == 1 then
    if not usedItems[id] then
      usedItems[id] = { count = 1, name = name}
    else
      usedItems[id].count = usedItems[id].count + 1
    end
    refreshWaste()
  end
end)

-- waste
local regex3 = [[\d ([a-z A-Z]*)s...]]
local lackOfData = {}
onTextMessage(function(mode, text)
  text = text:lower()
  if not text:find("using one of") then return end

  local amount = getFirstNumberInText(text)
  local re = regexMatch(text, regex3)
  local name = re[1][2]
  local id = WasteItems[name]

  if not id then

    if not lackOfData[name] then
      lackOfData[name] = true
      print("[Analyzer] no data for item: "..name.. "inside items.lua -> WasteItems")
    end

    return
  end

  if not useData[name] then
    useData[name] = amount
  else
    if math.abs(useData[name]-amount) == 1 then
      useData[name] = amount
      if not usedItems[id] then
        usedItems[id] = { count = 1, name = name}
      else
        usedItems[id].count = usedItems[id].count + 1
      end
    else
      useData[name] = amount
    end
    refreshWaste()
  end
end)

function hourVal(v)
  v = v or 0
  return (v/uptime)*3600
end

function bottingStats()
  lootWorth = 0
  wasteWorth = 0
  for k, v in pairs(lootedItems) do
    if LootItems[v.name] then
      lootWorth = lootWorth + (LootItems[v.name]*v.count)
    end
  end
  for k, v in pairs(usedItems) do
    if LootItems[v.name] then
      wasteWorth = wasteWorth + (LootItems[v.name]*v.count)
    end
  end
  balance = lootWorth - wasteWorth

  return lootWorth, wasteWorth, balance
end

function bottingLabels(lootWorth, wasteWorth, balance)
  balanceDesc = nil
  hourDesc = nil
  desc = nil

  if balance >= 1000000 or balance <= -1000000 then
    desc = balance / 1000000
    balanceDesc = math.floor(desc) .. "." .. math.floor(desc * 10) % 10 .. "kk"
  elseif balance >= 1000 or balance <= -1000 then
    desc = balance / 1000
    balanceDesc = math.floor(desc) .. "." .. math.floor(desc * 10) % 10 .."k"
  else
    balanceDesc = balance .. "gp"
  end

  hour = hourVal(balance)
  if hour >= 1000000 or hour <= -1000000 then
    desc = balance / 1000000
    hourDesc = math.floor(hourVal(desc)) .. "." .. math.floor(hourVal(desc) * 10) % 10 .. "kk/h"
  elseif hour >= 1000 or hour <= -1000 then
    desc = balance / 1000
    hourDesc = math.floor(hourVal(desc)) .. "." .. math.floor(hourVal(desc) * 10) % 10 .. "k/h"
  else
    hourDesc = math.floor(hourVal(balance)) .. "gp/h"
  end

  return balanceDesc, hourDesc
end

function reportStats()
  local lootWorth, wasteWorth, balance = bottingStats()
  local balanceDesc, hourDesc = bottingLabels(lootWorth, wasteWorth, balance)

  local a, b, c

  a = "Session Time: " .. sessionTime() .. ", Exp Gained: " .. format_thousand(expGained(), true) .. ", Exp/h: " .. expPerHour()
  b = " | Balance: " .. balanceDesc .. " (" .. hourDesc .. ")"
  c = a..b

  return c
end

function damageHour()
  if uptime < 5*60 then
    return totalDmg
  else
    return hourVal(totalDmg)
  end
end

function healHour()
  if uptime < 5*60 then
    return totalHeal
  else
    return hourVal(totalHeal)
  end
end

function wasteHour()
  local lootWorth, wasteWorth, balance = bottingStats()
  if uptime < 5*60 then
    return wasteWorth
  else
    return hourVal(wasteWorth)
  end
end


function lootHour()
  local lootWorth, wasteWorth, balance = bottingStats()
  if uptime < 5*60 then
    return lootWorth
  else
    return hourVal(lootWorth)
  end
end

function getHuntingData()
  local lootWorth, wasteWorth, balance = bottingStats()
  return totalDmg, totalHeal, lootWorth, wasteWorth, balance
end

function avgTable(t)
  if type(t) ~= 'table' then return 0 end
  local val = 0

  for i,v in pairs(t) do
    val = val + v
  end

  if #t == 0 then
    return 0
  else
    return val/#t
  end
end

-- main analyzer label refresh (text labels only; the graphs are drawn by the
-- 2s graph macro, which also updates the windowed "Max (last ~2.5 min)" figures)
macro(500, function()
    local lootWorth, wasteWorth, balance = bottingStats()
    local balanceDesc, hourDesc = bottingLabels(lootWorth, wasteWorth, balance)

    --hunt window
    sessionTimeLabel:setText(sessionTime())
    xpGainLabel:setText(format_thousand(expGained(), true))
    xpHourLabel:setText(expPerHour())
    lootLabel:setText(format_thousand(lootWorth, true))
    suppliesLabel:setText(format_thousand(wasteWorth, true))
    balanceLabel:setColor(balance >= 0 and "#45ad25" or "#ff9854")
    balanceLabel:setText(balanceDesc .. " (" .. hourDesc .. ")")

    --loot window
    lootInLootAnalyzerLabel:setText(format_thousand(lootWorth, true))
    lootHourInLootAnalyzerLabel:setText(format_thousand(lootHour(), true))


    --supply window
    suppliesInSuppliesAnalyzerLabel:setText(format_thousand(wasteWorth, true))
    suppliesHourInSuppliesAnalyzerLabel:setText(format_thousand(wasteHour(), true))

    --impact window
    -- damage dealt (approx)
    totalDamageLabel:setText(format_thousand(totalDmg, true))
    maxDpsLabel:setText(format_thousand(maxDmgRound, true))
    bestHitLabel:setText(format_thousand(storage.bestHit, true))

    -- damage taken
    totalTakenLabel:setText(format_thousand(totalDmgTaken, true))
    maxDtpsLabel:setText(format_thousand(maxTakenRound, true))
    worstHitLabel:setText(format_thousand(storage.worstHit, true))

    -- damage taken by attacker (distribution; monsters + players)
    local dist = {first, second, third}
    for i=1,3 do
      takenTops[i].left:setText(dist[i].l)
      takenTops[i].right:setText(dist[i].r)
      takenBars[i]:setPercent(dist[i].p or 0)
    end

    -- skills training (approx): bleed-frequency readout
    roundsSinceBloodLabel:setText(trainRoundsSinceBlood)
    roundsSinceBloodLabel:setColor(trainRoundsSinceBlood >= 10 and "#FF0000" or (trainRoundsSinceBlood >= 7 and "#FFA500" or "#45ad25"))
    maxStreakLabel:setText(trainMaxStreak)
    roundsLostLabel:setText(trainRoundsLost)
    attackRoundsLabel:setText(trainAttackRounds)
    bloodHitsLabel:setText(trainBloodHits)
    if trainAttackRounds > 0 then
      bleedRateLabel:setText(math.floor((trainBloodHits/trainAttackRounds)*100) .. "%")
      -- efficiency = share of rounds that were NOT wasted (>=10 dry), as a percentage
      local efficiency = 100 - ((trainRoundsLost / trainAttackRounds) * 100)
      efficiencyLabel:setText(math.floor(efficiency) .. "%")
      efficiencyLabel:setColor(efficiency >= 90 and "#45ad25" or (efficiency >= 70 and "#FFA500" or "#FF0000"))
    else
      bleedRateLabel:setText("-")
      efficiencyLabel:setText("-")
    end

    -- healing (approx)
    totalHealingLabel:setText(format_thousand(totalHeal, true))
    maxHpsLabel:setText(format_thousand(maxHealRound, true))
    bestHealLabel:setText(format_thousand(storage.bestHeal, true))

    --xp window
    xpGrainInXpLabel:setText(format_thousand(expGained(), true))
    xpHourInXpLabel:setText(expPerHour(), true)
    nextLevelLabel:setText(timeToLevel())
    progressBar:setPercent(modules.game_skills.skillsWindow.contentsPanel.level.percent:getPercent())


    --stats
    totalRounds:setText(vBot.CaveBotData.rounds)
    avRoundTime:setText(niceTimeFormat(avgTable(vBot.CaveBotData.time),true))
    totalRefills:setText(vBot.CaveBotData.refills)
    avRefillTime:setText(niceTimeFormat(avgTable(vBot.CaveBotData.refillTime),true))
    lastRefill:setText(niceTimeFormat(os.difftime(os.time()-vBot.CaveBotData.lastRefill),true))

end)

-- graphs, redrawn every 2s (~one attack round). With AnalyzerGraph's capacity
-- of 75 points that retains roughly the last ~2.5 minutes of history. The combat
-- graphs plot the per-round TOTAL (delta of the cumulative counter since the
-- previous draw); the loot/supply/xp graphs just sample their hourly rate. Each
-- per-round total also feeds the windowed "Max (last ~2.5 min)" labels.
macro(2000, function()
  drawGraph(xpGraph, expPerHour(true) or 0)
  drawGraph(lootGraph, lootHour() or 0)
  drawGraph(supplyGraph, wasteHour() or 0)
  local dmgRound = totalDmg - lastDmgGraph
  lastDmgGraph = totalDmg
  drawGraph(dmgGraph, dmgRound)
  maxDmgRound = windowedMax(dmgRounds, dmgRound)
  local takenRound = totalDmgTaken - lastTakenGraph
  lastTakenGraph = totalDmgTaken
  drawGraph(takenGraph, takenRound)
  maxTakenRound = windowedMax(takenRounds, takenRound)
  local healRound = totalHeal - lastHealGraph
  lastHealGraph = totalHeal
  drawGraph(healGraph, healRound)
  maxHealRound = windowedMax(healRounds, healRound)
end)

--party hunt analyzer
macro(2000, function()
  if not BotServer._websocket then return end

  -- send data
  if storage.sendPartyAnalyzerData then
    sendData()
  end

  local totalWaste, totalLoot, totalBalance = getSumStats()

  partySessionTimeLabel:setText(sessionTime())
  partyLootLabel:setText(format_thousand(totalLoot, true))
  partySuppliesLabel:setText(format_thousand(totalWaste, true))
  partyBalanceLabel:setText(format_thousand(totalBalance, true))

  if totalBalance < 0 then
    partyBalanceLabel:setColor('#ff9854')
  elseif totalBalance > 0 then
    partyBalanceLabel:setColor('#45ad25')
  else
    partyBalanceLabel:setColor('white')
  end

  for bossName, dueTime in pairs(storage.analyzers.trackedBoss) do
    createBossPanel(bossName, dueTime)
  end
end)

-- public functions
-- global namespace
Analyzer = {}

Analyzer.getKillsAmount = function(name)
  return killList[name] or 0
end

Analyzer.getLootedAmount = function(nameOrId)
  if type(nameOrId) == "number" then
    return lootedItems[nameOrId].count or 0
  else
    local nameOrId = nameOrId:lower()
    for k,v in pairs(lootedItems) do
      if v.name == nameOrId then
        return v.count
      end
    end
  end
  return 0
end

Analyzer.getTotalProfit = function()
  local lootWorth, wasteWorth, balance = bottingStats()

  return lootWorth
end

Analyzer.getTotalWaste = function()
  local lootWorth, wasteWorth, balance = bottingStats()

  return wasteWorth
end

Analyzer.getBalance = function()
  local lootWorth, wasteWorth, balance = bottingStats()

  return balance
end

Analyzer.getXpGained = function()
  return expGained()
end

Analyzer.getXpHour = function()
  return expPerHour()
end

Analyzer.getTimeToNextLevel = function()
  return timeToLevel()
end

Analyzer.getCaveBotStats = function()
  local parents = {suppliesByRound, suppliesByRefill}
  local round = {}
  local refill = {}
  for i=1,2 do
    local data = parents[i]
    for j, child in ipairs(data:getChildren()) do
      local id = child:getItemId()
      local count = child.count

      if i == 1 then
        round[id] = count
      else
        refill[id] = count
      end
    end
  end

  return {
    totalRounds = totalRounds:getText(),
    avRoundTime = avRoundTime:getText(),
    totalRefills = totalRefills:getText(),
    avRefillTime = avRefillTime:getText(),
    lastRefill = lastRefill:getText(),
    roundSupplies = round, -- { [id] = amount, [id2] = amount ...}
    refillSupplies = refill -- { [id] = amount, [id2] = amount ...}
  }
end