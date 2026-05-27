-- Humanize: shared anti-detection scheduler.
--
-- Other vBot/CaveBot/TargetBot scripts call into this module to get
-- randomized delays, ask whether they should pause, and trigger occasional
-- random turns / "look around" pauses so the character doesn't move with a
-- robotic fixed cadence.
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

setDefaultTab("Humanize")

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

-- Random turns while idle.
cfg.turnChancePct    = cfg.turnChancePct    or 4
cfg.turnCooldownMs   = cfg.turnCooldownMs   or 12000

-- "Look around" pauses.
cfg.pauseChancePct   = cfg.pauseChancePct   or 2
cfg.pauseCooldownMs  = cfg.pauseCooldownMs  or 90000
cfg.pauseMinMs       = cfg.pauseMinMs       or 1500
cfg.pauseMaxMs       = cfg.pauseMaxMs       or 4000

-- Reposition heuristic: when too many monsters are around, step away from
-- their centroid. Set maxAttackers high to effectively disable.
cfg.maxAttackers         = cfg.maxAttackers         or 4
cfg.repositionCooldownMs = cfg.repositionCooldownMs or 6000

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

-- "Light" preset disables random turns/pauses entirely.
local function randomBehaviorsAllowed()
  return humanize.enabled() and cfg.preset ~= "Light"
end

local function tryRandomTurn()
  if not randomBehaviorsAllowed() then return end
  if now - state.lastTurnAt < cfg.turnCooldownMs then return end
  if math.random(0, 99) >= cfg.turnChancePct then return end
  local dirs = { North, East, South, West }
  local d = dirs[math.random(1, #dirs)]
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
  tryRandomTurn()
  tryRandomPause()
end

------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------
UI.Label("Anti-detection humanization")

local enableBtn
enableBtn = UI.Button(cfg.enabled and "Humanize: ON" or "Humanize: OFF", function(widget)
  cfg.enabled = not cfg.enabled
  widget:setText(cfg.enabled and "Humanize: ON" or "Humanize: OFF")
end)

UI.Label("Preset (Off / Light / Medium / Paranoid):")
UI.TextEdit(cfg.preset, function(widget, text)
  -- Only accept known presets; silently keep last value otherwise.
  if text == "Off" or text == "Light" or text == "Medium" or text == "Paranoid" then
    cfg.preset = text
  end
end)

UI.Separator()
UI.Label("Move jitter ms (min,max):")
UI.TextEdit(tostring(cfg.moveJitterMin), function(widget, text)
  local n = tonumber(text); if n then cfg.moveJitterMin = math.max(0, n) end
end)
UI.TextEdit(tostring(cfg.moveJitterMax), function(widget, text)
  local n = tonumber(text); if n then cfg.moveJitterMax = math.max(0, n) end
end)

UI.Label("Attack start jitter ms (min,max):")
UI.TextEdit(tostring(cfg.attackStartMin), function(widget, text)
  local n = tonumber(text); if n then cfg.attackStartMin = math.max(0, n) end
end)
UI.TextEdit(tostring(cfg.attackStartMax), function(widget, text)
  local n = tonumber(text); if n then cfg.attackStartMax = math.max(0, n) end
end)

UI.Label("Loot jitter ms (min,max):")
UI.TextEdit(tostring(cfg.lootJitterMin), function(widget, text)
  local n = tonumber(text); if n then cfg.lootJitterMin = math.max(0, n) end
end)
UI.TextEdit(tostring(cfg.lootJitterMax), function(widget, text)
  local n = tonumber(text); if n then cfg.lootJitterMax = math.max(0, n) end
end)

UI.Label("Random turn chance %/sec & cooldown ms:")
UI.TextEdit(tostring(cfg.turnChancePct), function(widget, text)
  local n = tonumber(text); if n then cfg.turnChancePct = math.max(0, math.min(100, n)) end
end)
UI.TextEdit(tostring(cfg.turnCooldownMs), function(widget, text)
  local n = tonumber(text); if n then cfg.turnCooldownMs = math.max(0, n) end
end)

UI.Label("Random pause chance %/sec & cooldown ms:")
UI.TextEdit(tostring(cfg.pauseChancePct), function(widget, text)
  local n = tonumber(text); if n then cfg.pauseChancePct = math.max(0, math.min(100, n)) end
end)
UI.TextEdit(tostring(cfg.pauseCooldownMs), function(widget, text)
  local n = tonumber(text); if n then cfg.pauseCooldownMs = math.max(0, n) end
end)

UI.Label("Reposition when >N monsters around & cooldown ms:")
UI.TextEdit(tostring(cfg.maxAttackers), function(widget, text)
  local n = tonumber(text); if n then cfg.maxAttackers = math.max(0, n) end
end)
UI.TextEdit(tostring(cfg.repositionCooldownMs), function(widget, text)
  local n = tonumber(text); if n then cfg.repositionCooldownMs = math.max(0, n) end
end)

UI.Separator()

-- Self-driven idle tick: random turns and pauses don't need any external
-- caller. Runs once per second when humanize is enabled.
macro(1000, function()
  humanize.tickIdle()
end)
