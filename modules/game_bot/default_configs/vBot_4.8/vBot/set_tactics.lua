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
    !text: tr('Set Tactics')

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
-- Constants not available in bot sandbox, use literal values
-- FightOffensive=1, FightBalanced=2, FightDefensive=3
-- DontChase=0, ChaseOpponent=1

if not storage.setTactics then
  storage.setTactics = {
    enabled = false,
    intervalSec = 10, 
    fightMode = 3, -- Defensive by default.
    chaseOpponent = false,
    safeFight = true
  }
end

local config = storage.setTactics

-- ── Bind toggle ──────────────────────────────────────────────
ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

-- ── Popup setup window ───────────────────────────────────────
local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local stWindow = UI.createWindow('SetTacticsWindow', rootWidget)
  stWindow:hide()

  ui.setup.onClick = function()
    stWindow:show()
    stWindow:raise()
    stWindow:focus()
  end

  stWindow.closeButton.onClick = function()
    stWindow:hide()
  end

  -- Interval
  stWindow.interval:setText(tostring(config.intervalSec))
  stWindow.interval.onTextChange = function(widget, text)
    local val = tonumber(text)
    if val and val >= 1 then
      config.intervalSec = val
    end
  end

  -- Fight stance combo box
  local stanceNames = { "Full Attack", "Balanced", "Full Defence" }
  local stanceValues = { 1, 2, 3 }
  local stanceByName = {}
  for i, name in ipairs(stanceNames) do
    stWindow.fightStance:addOption(name)
    stanceByName[name] = stanceValues[i]
  end

  -- Select current config value
  for i, val in ipairs(stanceValues) do
    if val == config.fightMode then
      stWindow.fightStance:setOption(stanceNames[i])
      break
    end
  end

  stWindow.fightStance.onOptionChange = function(widget)
    local name = widget:getCurrentOption().text
    if stanceByName[name] then
      config.fightMode = stanceByName[name]
    end
  end

  -- Chase
  stWindow.chaseOpponent:setChecked(config.chaseOpponent)
  stWindow.chaseOpponent.onClick = function(widget)
    config.chaseOpponent = not config.chaseOpponent
    widget:setChecked(config.chaseOpponent)
  end

  -- Safe fight
  stWindow.safeFight:setChecked(config.safeFight)
  stWindow.safeFight.onClick = function(widget)
    config.safeFight = not config.safeFight
    widget:setChecked(config.safeFight)
  end
end

-- ── Macro ────────────────────────────────────────────────────
local lastApply = 0

macro(1000, function()
  if not config.enabled then return end
  if now - lastApply < config.intervalSec * 1000 then return end
  lastApply = now

  g_game.setFightMode(config.fightMode)
  g_game.setChaseMode(config.chaseOpponent and 1 or 0)
  g_game.setSafeFight(config.safeFight)
end)
