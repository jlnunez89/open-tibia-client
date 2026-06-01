-- Auto-Stop Timer.
--
-- Safety/anti-detection helper: after a configurable number of minutes it turns
-- OFF both CaveBot (hunting/walking) and TargetBot (attacking), so you can step
-- away and the character won't keep botting unattended for hours (which is what
-- gets accounts probed/flagged).
--
-- The countdown starts when you enable the switch. Changing the minutes value
-- while it is running re-evaluates the deadline from that same start time. When
-- the deadline passes we stop CaveBot + TargetBot, disable the switch, and warn
-- in the console. It only fires once; flip it back on to arm another window.

setDefaultTab("Cave")

if type(storage.autoStop) ~= "table" then
  storage.autoStop = {}
end
local cfg = storage.autoStop
if cfg.enabled == nil then cfg.enabled = false end
cfg.minutes = cfg.minutes or 30

-- Runtime-only start timestamp (not persisted): a fresh session re-arms the
-- countdown rather than firing instantly on load.
local startAt = now

local ui = setupUI([[
Panel
  height: 37

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Auto-Stop Hunting')

  Label
    id: minLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 3
    text: Stop after (min):
    width: 110

  BotTextEdit
    id: minutes
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 50
]])

local function deadline()
  return startAt + (cfg.minutes * 60000)
end

local function refreshTitle()
  if not cfg.enabled then
    ui.title:setText("Auto-Stop Hunting")
    return
  end
  local remaining = deadline() - now
  if remaining < 0 then remaining = 0 end
  local mins = math.floor(remaining / 60000)
  local secs = math.floor((remaining % 60000) / 1000)
  ui.title:setText(string.format("Auto-Stop: %d:%02d left", mins, secs))
end

ui.title:setOn(cfg.enabled)
ui.title.onClick = function()
  cfg.enabled = not cfg.enabled
  ui.title:setOn(cfg.enabled)
  startAt = now -- (re)start the countdown whenever it is switched on
  refreshTitle()
end

ui.minutes:setText(tostring(cfg.minutes))
ui.minutes.onTextChange = function(_, text)
  local n = tonumber(text)
  if not n then return end
  cfg.minutes = math.max(1, math.floor(n))
end

refreshTitle()

macro(1000, function()
  if not cfg.enabled then return end
  refreshTitle()
  if now < deadline() then return end

  -- Time's up: stop hunting and attacking, then disarm so it only fires once.
  if CaveBot and CaveBot.setOff then CaveBot.setOff() end
  if TargetBot and TargetBot.setOff then TargetBot.setOff() end
  cfg.enabled = false
  ui.title:setOn(false)
  refreshTitle()
  warn("[Auto-Stop] " .. cfg.minutes .. " min elapsed - CaveBot and TargetBot turned off.")
end)
