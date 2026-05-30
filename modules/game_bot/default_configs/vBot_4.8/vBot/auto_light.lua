-- Auto Light: cast a light spell when the player is in the dark and not
-- emitting their own light. Helps avoid the "robot walks blind" tell.
--
-- Detection (verified against the 7.72 server source):
--   * World ambient (SV_CMD_AMBIENTE / GetAmbiente) is a single byte that the
--     server derives from the in-game time. It is NEVER 0: it steps through
--     0x33 (51, deep night) -> 0x66 (102) -> 0x99 (153) -> 0xCC (204) ->
--     0xFF (255, full daylight). So a threshold below 51 (the old default of
--     50) can never be reached, which is why the script never fired.
--   * The ambient byte only reflects surface day/night. Underground (floor
--     z > 7) is rendered fully dark by the client regardless of ambient, so we
--     must treat being underground as "dark" on its own.
--   * Player creature-light (SV_CMD_CREATURE_LIGHT / GetCreatureLight) starts
--     at the spell's radius: "utevo lux" -> 6, "utevo gran lux" -> 8. Vanilla
--     unlit chars report 0. So any value >= 2 means we are already lit.
--
-- Spell light DURATION (from magic.cc Enlight + crskill.cc TSkillLight):
--   Enlight() does SetTimer(SKILL_LIGHT, Radius, Duration/Radius, ...), and the
--   skill timer is processed about once per second (main.cc ProcessSkills).
--   Brightness starts at Radius and decays by 1 every (Duration/Radius)+1 secs:
--     * "utevo lux"      Radius=6, Duration=500  -> ~84s/step, ~8 min total,
--                        stays >=2 brightness for ~5.6 min.
--     * "utevo gran lux" Radius=8, Duration=1000 -> ~126s/step, ~17 min total.
--   So a single cast keeps us lit for MINUTES, not seconds. The old 60s window
--   (and the structure that ignored it whenever the client reported any light
--   value) is why the bot kept recasting and burned all its mana.
--
-- We cast when enabled AND it's dark (underground or night) AND we are NOT
-- already lit AND we have mana AND not in a PZ AND the recast window elapsed.
-- "Already lit" is true if EITHER the client reports our projected creature
-- light at/above the threshold, OR we cast recently (timer fallback). Both are
-- checked independently so a 0/unknown light reading can never force a recast
-- while our spell light is clearly still active.

setDefaultTab("HP")

if type(storage.autoLight) ~= "table" then
  storage.autoLight = {}
end
local cfg = storage.autoLight
cfg.enabled              = cfg.enabled              or false
cfg.spell                = cfg.spell                or "utevo lux"
cfg.manaCost             = cfg.manaCost             or 20
-- Cast when ambient is below this. 160 covers the three night/twilight steps
-- (51 / 102 / 153) while leaving the two daylight steps (204 / 255) alone.
cfg.ambientThreshold     = cfg.ambientThreshold     or 160
-- Consider ourselves "already lit" at or above this creature-light brightness.
cfg.playerLightThreshold = cfg.playerLightThreshold or 2
cfg.minRecastMs          = cfg.minRecastMs          or 5000
-- Assume a cast keeps us comfortably lit for this long. Sized for "utevo lux",
-- which stays >=2 brightness for ~5.6 min; 4 min leaves a safe margin so we
-- refresh before it gets dim instead of recasting every few seconds.
cfg.litDurationMs        = cfg.litDurationMs        or 240000
if cfg.ignoreInPz == nil then cfg.ignoreInPz = true end

UI.Label("Auto Light:")
UI.TextEdit(cfg.spell, function(widget, text)
  cfg.spell = text
end)

local function getAmbient()
  local ok, light = pcall(function() return g_map.getLight() end)
  if ok and light and light.intensity then return light.intensity end
  return 255
end

local function getPlayerLight()
  local ok, light = pcall(function() return player:getLight() end)
  if ok and light and light.intensity then return light.intensity end
  return nil -- light reading unavailable
end

local function getFloor()
  local ok, p = pcall(function() return player:getPosition() end)
  if ok and p and p.z then return p.z end
  return 7
end

local lastCastAt = 0
-- Named macro: vBot renders a green ON / red OFF toggle button automatically
-- (same UI treatment as "Eat Food").
local autoLightMacro = macro(1000, "Auto Light", function()
  if cfg.ignoreInPz and isInPz() then return end
  if now - lastCastAt < cfg.minRecastMs then return end
  if mana() < cfg.manaCost then return end
  if not cfg.spell or #cfg.spell == 0 then return end

  -- Dark if underground (client forces darkness) or surface night/twilight.
  local underground = getFloor() > 7
  local dark = underground or getAmbient() < cfg.ambientThreshold
  if not dark then return end

  -- Already lit from a recent cast? Our spell light lasts minutes on this
  -- server, so honor the timer window unconditionally. This is what stops the
  -- constant recasting/mana drain even when the client reports light as 0.
  if now - lastCastAt < cfg.litDurationMs then return end

  -- Also skip if the client reports we are already projecting light (active
  -- spell light still up, a torch, etc.). Treated as an extra suppressor only.
  local playerLight = getPlayerLight()
  if playerLight and playerLight >= cfg.playerLightThreshold then return end

  say(cfg.spell)
  lastCastAt = now
end)

if cfg.enabled and autoLightMacro and autoLightMacro.setOn then
  autoLightMacro.setOn(true)
end

UI.Separator()
