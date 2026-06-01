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
--   * A held TORCH (or lamp) does NOT raise creature-light -- its glow is item
--     light from the .dat, rendered client-side only. We therefore also inspect
--     equipped items via g_things.getThingType(id):getLight() and treat their
--     intensity as light we are already emitting. This is why a lit torch alone
--     now stops the bot from casting.
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
-- "Already lit" is true if EITHER we are carrying/holding a light-emitting item
-- (torch/lamp), OR the client reports our creature light at/above the
-- threshold, OR we cast recently (timer fallback). The item/creature light
-- check runs first so a lit torch suppresses casting on its own, independent of
-- the spell recast timer.

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

-- Scrollbar bound to a cfg field. `scale` lets us show user-friendly units
-- (e.g. seconds) while storing another unit (ms): stored = shownValue * scale.
-- Reuses the globally-imported ExtrasScrollBar style.
local function addLightScrollBar(field, title, min, max, default, scale, tooltip)
  scale = scale or 1
  local widget = UI.createWidget('ExtrasScrollBar')
  widget.text:setTooltip(tooltip)
  widget.scroll:setTooltip(tooltip)
  widget.scroll.onValueChange = function(scroll, value)
    widget.text:setText(title .. ": " .. value)
    cfg[field] = value * scale
  end
  widget.scroll:setRange(min, max)
  if max - min > 1000 then
    widget.scroll:setStep(100)
  elseif max - min > 100 then
    widget.scroll:setStep(10)
  end
  widget.scroll:setValue(math.floor((cfg[field] or (default * scale)) / scale))
  widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
end

-- Ambient darkness threshold. Server night/twilight steps are 51 / 102 / 153;
-- daylight is 204 / 255. Cast when ambient is below this. 160 covers all three
-- night steps. Range stays within the meaningful 50..255 band.
addLightScrollBar("ambientThreshold", "Darkness threshold", 50, 255, 160, 1,
  "Cast when world ambient light is below this. 51/102/153 are night & twilight; 204/255 are daylight. Higher = casts earlier in the evening.")

-- Already-lit creature/item light level that suppresses casting. utevo lux=6,
-- gran lux=8; a value of 2 means "still meaningfully lit".
addLightScrollBar("playerLightThreshold", "Already-lit level", 1, 8, 2, 1,
  "Skip casting while our own light (spell or torch) is at/above this brightness. utevo lux starts at 6, gran lux at 8.")

-- Mana required before we bother casting.
addLightScrollBar("manaCost", "Min mana to cast", 0, 200, 20, 1,
  "Do not cast the light spell unless we have at least this much mana.")

-- How long one cast keeps us lit (seconds, stored as ms). utevo lux stays >=2
-- brightness ~5.6 min, so 240s leaves a safe refresh margin.
addLightScrollBar("litDurationMs", "Recast every (s)", 30, 600, 240, 1000,
  "Assume a single cast keeps us lit for this many seconds before refreshing. Sized for utevo lux (~5.6 min); raise for gran lux.")

local function getAmbient()
  local ok, light = pcall(function() return g_map.getLight() end)
  if ok and light and light.intensity then return light.intensity end
  return 255
end

-- Creature light is what the SERVER tells the client we emit, and on this
-- server that is only ever set by light SPELLS (utevo lux, etc). A held torch
-- does NOT change creature light -- its glow is item light baked into the .dat
-- and rendered purely client-side. So we have to inspect equipped items too,
-- otherwise the bot is blind to a lit torch and keeps recasting on top of it.
local function getCreatureLight()
  local ok, light = pcall(function() return player:getLight() end)
  if ok and light and light.intensity then return light.intensity end
  return nil -- light reading unavailable
end

-- Max light intensity emitted by anything we are wearing/holding (torch, lamp,
-- etc). The two hands are where light sources normally go, but we scan every
-- slot so a glowing helmet/lantern is covered too.
local equippedLightSlots = {
  InventorySlotHead, InventorySlotBody, InventorySlotRight,
  InventorySlotLeft, InventorySlotFeet, InventorySlotAmmo,
}
local function getEquippedLight()
  local best = 0
  for _, slot in ipairs(equippedLightSlots) do
    local ok, intensity = pcall(function()
      local item = player:getInventoryItem(slot)
      if not item then return 0 end
      local tt = g_things.getThingType(item:getId(), ThingCategoryItem)
      if not tt then return 0 end
      local light = tt:getLight()
      return (light and light.intensity) or 0
    end)
    if ok and intensity and intensity > best then best = intensity end
  end
  return best
end

-- Effective light = the brighter of our spell (creature) light and any light
-- source we are wearing. Returns nil only when the creature reading itself is
-- unavailable AND we found no equipped light, so callers can stay conservative.
local function getPlayerLight()
  local creature = getCreatureLight()
  local equipped = getEquippedLight()
  if creature == nil and equipped == 0 then return nil end
  return math.max(creature or 0, equipped)
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

  -- Already lit? Either from an equipped light source (torch/lamp) or from a
  -- recent spell cast. We check the light reading FIRST so a lit torch alone is
  -- enough to suppress casting -- it never expires on a timer, so it must not be
  -- gated behind the recast window below.
  local playerLight = getPlayerLight()
  if playerLight and playerLight >= cfg.playerLightThreshold then return end

  -- Spell light lasts minutes on this server, so honor the timer window even if
  -- the client reports our creature light as 0. This stops constant recasting
  -- and mana drain when we are relying on a spell rather than a torch.
  if now - lastCastAt < cfg.litDurationMs then return end

  say(cfg.spell)
  lastCastAt = now
end)

if cfg.enabled and autoLightMacro and autoLightMacro.setOn then
  autoLightMacro.setOn(true)
end

UI.Separator()
