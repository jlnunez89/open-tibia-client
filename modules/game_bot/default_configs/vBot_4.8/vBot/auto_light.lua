-- Auto Light: cast a light spell when the player is in the dark and not
-- emitting their own light. Helps avoid the "robot walks blind" tell.
--
-- Detection:
--   * World ambient (from SV_CMD_AMBIENTE) via g_map.getLight().intensity
--     (0..255-ish; ~100 == daylight in OT, lower == darker).
--   * Player creature-light (from SV_CMD_CREATURE_LIGHT) via
--     player:getLight().intensity. Vanilla chars have intensity 0;
--     utevo lux raises it to ~5 for ~10 minutes.
--
-- We cast when enabled AND ambient is dark AND we're unlit AND we have mana
-- AND not in a PZ AND the minimum recast window has elapsed.

setDefaultTab("HP")

if type(storage.autoLight) ~= "table" then
  storage.autoLight = {}
end
local cfg = storage.autoLight
cfg.enabled              = cfg.enabled              or false
cfg.spell                = cfg.spell                or "utevo lux"
cfg.manaCost             = cfg.manaCost             or 20
cfg.ambientThreshold     = cfg.ambientThreshold     or 50
cfg.playerLightThreshold = cfg.playerLightThreshold or 20
cfg.minRecastMs          = cfg.minRecastMs          or 5000
if cfg.ignoreInPz == nil then cfg.ignoreInPz = true end

UI.Label("Auto Light:")
UI.TextEdit(cfg.spell, function(widget, text)
  cfg.spell = text
end)

local function getAmbient()
  local ok, light = pcall(function() return g_map.getLight() end)
  if ok and light and light.intensity then return light.intensity end
  return 100
end

local function getPlayerLight()
  local ok, light = pcall(function() return player:getLight() end)
  if ok and light and light.intensity then return light.intensity end
  return 0
end

local lastCastAt = 0
-- Named macro: vBot renders a green ON / red OFF toggle button automatically
-- (same UI treatment as "Eat Food").
local autoLightMacro = macro(1000, "Auto Light", function()
  if cfg.ignoreInPz and isInPz() then return end
  if now - lastCastAt < cfg.minRecastMs then return end
  if mana() < cfg.manaCost then return end
  if not cfg.spell or #cfg.spell == 0 then return end
  if getAmbient() >= cfg.ambientThreshold then return end
  if getPlayerLight() >= cfg.playerLightThreshold then return end
  say(cfg.spell)
  lastCastAt = now
end)

if cfg.enabled and autoLightMacro and autoLightMacro.setOn then
  autoLightMacro.setOn(true)
end

UI.Separator()
