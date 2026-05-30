-- Humanize: shared anti-detection scheduler.
--
-- Other vBot/CaveBot/TargetBot scripts call into this module to get
-- randomized delays, ask whether they should pause, and trigger occasional
-- turns toward the creature we are attacking / "look around" pauses so the
-- character doesn't move with a robotic fixed cadence.
--
-- Public API (exposed as the global `humanize`):
--   humanize.enabled()                -> bool
--   humanize.delay(kind)              -> ms (0 when disabled or preset=Off)
--     kinds: "move", "action", "attackStart", "loot"
--   humanize.canActNow()              -> bool   (false during a pause)
--   humanize.tickIdle()               -> nil    (call ~1/sec while idle to maybe trigger turn/pause)
--
-- This file is intentionally side-effect-light: it owns its own storage and a
-- single UI tab. CaveBot/TargetBot integrations live in their own files and
-- defensively guard `if humanize and humanize.enabled() then ...`.

setDefaultTab("Target")

if type(storage.humanize) ~= "table" then
  storage.humanize = {}
end
local cfg = storage.humanize
if cfg.enabled       == nil then cfg.enabled = true end
cfg.preset           = cfg.preset           or "Medium"   -- Off / Light / Medium / Paranoid

-- Base jitter ranges (Medium preset). Presets scale these via _scale().
cfg.moveJitterMin    = cfg.moveJitterMin    or 40
cfg.moveJitterMax    = cfg.moveJitterMax    or 180
cfg.actionJitterMin  = cfg.actionJitterMin  or 80
cfg.actionJitterMax  = cfg.actionJitterMax  or 260
cfg.lootJitterMin    = cfg.lootJitterMin    or 220
cfg.lootJitterMax    = cfg.lootJitterMax    or 520
cfg.attackStartMin   = cfg.attackStartMin   or 150
cfg.attackStartMax   = cfg.attackStartMax   or 450

-- Occasional turns toward the creature we are attacking (mimics a player
-- re-facing their target). Chance is rolled at most once per cooldown.
cfg.turnChancePct    = cfg.turnChancePct    or 4
cfg.turnCooldownMs   = cfg.turnCooldownMs   or 12000

-- "Look around" pauses.
cfg.pauseChancePct   = cfg.pauseChancePct   or 2
cfg.pauseCooldownMs  = cfg.pauseCooldownMs  or 90000
cfg.pauseMinMs       = cfg.pauseMinMs       or 1500
cfg.pauseMaxMs       = cfg.pauseMaxMs       or 4000

-- Reposition heuristic: when too many monsters are around, step away from
-- their centroid. Set maxAttackers high to effectively disable. The chance
-- gate adds randomness so the step-away doesn't fire on every opportunity.
cfg.maxAttackers         = cfg.maxAttackers         or 4
cfg.repositionCooldownMs = cfg.repositionCooldownMs or 6000
cfg.repositionChancePct  = cfg.repositionChancePct  or 60

-- Internal state.
local state = {
  lastTurnAt    = 0,
  lastPauseAt   = 0,
  pausedUntil   = 0,
  lastIdleTick  = 0,
}

-- Preset scaling: returns a multiplier for jitter ranges and gates random
-- turns/pauses entirely on the lighter presets.
local function presetScale()
  local p = cfg.preset
  if p == "Off"      then return 0 end
  if p == "Light"    then return 0.5 end
  if p == "Paranoid" then return 1.5 end
  return 1   -- Medium
end

local function randRange(lo, hi)
  if hi < lo then hi = lo end
  return math.random(lo, hi)
end

humanize = {}

function humanize.enabled()
  return cfg.enabled and cfg.preset ~= "Off"
end

function humanize.delay(kind)
  if not humanize.enabled() then return 0 end
  local s = presetScale()
  if s <= 0 then return 0 end
  local lo, hi
  if     kind == "move"        then lo, hi = cfg.moveJitterMin,   cfg.moveJitterMax
  elseif kind == "action"      then lo, hi = cfg.actionJitterMin, cfg.actionJitterMax
  elseif kind == "attackStart" then lo, hi = cfg.attackStartMin,  cfg.attackStartMax
  elseif kind == "loot"        then lo, hi = cfg.lootJitterMin,   cfg.lootJitterMax
  else return 0 end
  return math.floor(randRange(lo, hi) * s)
end

function humanize.canActNow()
  if not humanize.enabled() then return true end
  return now >= state.pausedUntil
end

function humanize.maxAttackers()
  return cfg.maxAttackers or 4
end

function humanize.repositionCooldown()
  return cfg.repositionCooldownMs or 6000
end

function humanize.repositionChance()
  return cfg.repositionChancePct or 100
end

-- "Light" preset disables random turns/pauses entirely.
local function randomBehaviorsAllowed()
  return humanize.enabled() and cfg.preset ~= "Light"
end

local function tryTurnToTarget()
  if not randomBehaviorsAllowed() then return end
  if now - state.lastTurnAt < cfg.turnCooldownMs then return end
  if math.random(0, 99) >= cfg.turnChancePct then return end
  -- Only turn when we actually have a target to face.
  local target = g_game.getAttackingCreature()
  if not target then return end
  local tPos = target:getPosition()
  local pPos = player:getPosition()
  if not tPos or not pPos or tPos.z ~= pPos.z then return end
  local dx = tPos.x - pPos.x
  local dy = tPos.y - pPos.y
  if dx == 0 and dy == 0 then return end
  -- Pick the cardinal direction that best points at the target.
  local d
  if math.abs(dx) >= math.abs(dy) then
    d = dx > 0 and East or West
  else
    d = dy > 0 and South or North
  end
  state.lastTurnAt = now
  -- `turn(dir)` is a vBot helper that emits a turn packet without moving.
  if turn then turn(d) end
end

local function tryRandomPause()
  if not randomBehaviorsAllowed() then return end
  if now - state.lastPauseAt < cfg.pauseCooldownMs then return end
  if math.random(0, 99) >= cfg.pauseChancePct then return end
  state.lastPauseAt = now
  state.pausedUntil = now + randRange(cfg.pauseMinMs, cfg.pauseMaxMs)
end

function humanize.tickIdle()
  if not humanize.enabled() then return end
  -- rate-limit to ~1/sec regardless of caller frequency
  if now - state.lastIdleTick < 1000 then return end
  state.lastIdleTick = now
  if now < state.pausedUntil then return end
  tryTurnToTarget()
  tryRandomPause()
end

------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Humanize')

  Button
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Edit
]])

local params = setupUI([[
Panel
  height: 452

  Label
    anchors.top: parent.top
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Preset:
    width: 100
    tooltip: One of Off / Light / Medium / Paranoid.

  BotTextEdit
    id: preset
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    margin-right: 3
    width: 60

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Move jitter (ms):

  BotTextEdit
    id: moveJitterMin
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 2
    margin-left: 3
    width: 50

  Label
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    text: to

  BotTextEdit
    id: moveJitterMax
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    width: 50

  Label
    anchors.top: moveJitterMin.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Attack start (ms):

  BotTextEdit
    id: attackStartMin
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 2
    margin-left: 3
    width: 50

  Label
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    text: to

  BotTextEdit
    id: attackStartMax
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    width: 50

  Label
    anchors.top: attackStartMin.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Loot jitter (ms):

  BotTextEdit
    id: lootJitterMin
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 2
    margin-left: 3
    width: 50

  Label
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    text: to

  BotTextEdit
    id: lootJitterMax
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 4
    width: 50

  Label
    anchors.top: lootJitterMin.bottom
    anchors.left: parent.left
    margin-top: 10
    margin-left: 3
    text: Turn To Target
    color: #c8a2ff

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 12
    text: Chance % (0-100):
    width: 130

  BotTextEdit
    id: turnChancePct
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 55

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 12
    text: Cooldown (ms):
    width: 130

  BotTextEdit
    id: turnCooldownMs
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 55

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    margin-left: 3
    text: Pause Randomly
    color: #c8a2ff

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 12
    text: Chance % (0-100):
    width: 130

  BotTextEdit
    id: pauseChancePct
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 55

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 12
    text: Cooldown (ms):
    width: 130

  BotTextEdit
    id: pauseCooldownMs
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 55

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    margin-left: 3
    text: Reposition
    color: #c8a2ff

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 12
    text: On >N attackers:
    width: 130
    tooltip: Trigger a reposition when more than N monsters are around the player.

  BotTextEdit
    id: maxAttackers
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 55

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 12
    text: Chance % (0-100):
    width: 130
    tooltip: Probability that a valid reposition opportunity actually triggers a step-away.

  BotTextEdit
    id: repositionChancePct
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 55

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 12
    text: Cooldown (ms):
    width: 130

  BotTextEdit
    id: repositionCooldownMs
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 55
]])
params:hide()

local showParams = false
ui.edit.onClick = function()
  showParams = not showParams
  if showParams then params:show() else params:hide() end
end

ui.title:setOn(cfg.enabled)
ui.title.onClick = function()
  cfg.enabled = not cfg.enabled
  ui.title:setOn(cfg.enabled)
end

local function bindNumber(widget, getter, setter, lo, hi)
  widget:setText(tostring(getter()))
  widget.onTextChange = function(_, text)
    local n = tonumber(text)
    if not n then return end
    if lo then n = math.max(lo, n) end
    if hi then n = math.min(hi, n) end
    setter(n)
  end
end

params.preset:setText(cfg.preset)
params.preset.onTextChange = function(_, text)
  if text == "Off" or text == "Light" or text == "Medium" or text == "Paranoid" then
    cfg.preset = text
  end
end

bindNumber(params.moveJitterMin,        function() return cfg.moveJitterMin        end, function(n) cfg.moveJitterMin        = n end, 0)
bindNumber(params.moveJitterMax,        function() return cfg.moveJitterMax        end, function(n) cfg.moveJitterMax        = n end, 0)
bindNumber(params.attackStartMin,       function() return cfg.attackStartMin       end, function(n) cfg.attackStartMin       = n end, 0)
bindNumber(params.attackStartMax,       function() return cfg.attackStartMax       end, function(n) cfg.attackStartMax       = n end, 0)
bindNumber(params.lootJitterMin,        function() return cfg.lootJitterMin        end, function(n) cfg.lootJitterMin        = n end, 0)
bindNumber(params.lootJitterMax,        function() return cfg.lootJitterMax        end, function(n) cfg.lootJitterMax        = n end, 0)
bindNumber(params.turnChancePct,        function() return cfg.turnChancePct        end, function(n) cfg.turnChancePct        = n end, 0, 100)
bindNumber(params.turnCooldownMs,       function() return cfg.turnCooldownMs       end, function(n) cfg.turnCooldownMs       = n end, 0)
bindNumber(params.pauseChancePct,       function() return cfg.pauseChancePct       end, function(n) cfg.pauseChancePct       = n end, 0, 100)
bindNumber(params.pauseCooldownMs,      function() return cfg.pauseCooldownMs      end, function(n) cfg.pauseCooldownMs      = n end, 0)
bindNumber(params.maxAttackers,         function() return cfg.maxAttackers         end, function(n) cfg.maxAttackers         = n end, 0)
bindNumber(params.repositionChancePct,  function() return cfg.repositionChancePct  end, function(n) cfg.repositionChancePct  = n end, 0, 100)
bindNumber(params.repositionCooldownMs, function() return cfg.repositionCooldownMs end, function(n) cfg.repositionCooldownMs = n end, 0)


-- Self-driven idle tick: random turns and pauses don't need any external
-- caller. Runs once per second when humanize is enabled.
macro(1000, function()
  humanize.tickIdle()
end)
