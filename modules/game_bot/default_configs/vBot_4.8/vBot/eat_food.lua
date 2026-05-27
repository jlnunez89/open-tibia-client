setDefaultTab("HP")
if voc() ~= 1 and voc() ~= 11 then
    if storage.foodItems then
        local t = {}
        for i, v in pairs(storage.foodItems) do
            if not table.find(t, v.id) then
                table.insert(t, v.id)
            end
        end
        local foodItems = { 3607, 3585, 3592, 3600, 3601 }
        for i, item in pairs(foodItems) do
            if not table.find(t, item) then
                table.insert(storage.foodItems, item)
            end
        end
    end
    macro(500, "Cast Food", function()
        if player:getRegenerationTime() <= 400 then
            cast("exevo pan", 5000)
        end
    end)
end

UI.Label("Eatable items:")
if type(storage.foodItems) ~= "table" then
  storage.foodItems = {3582, 3577}
end

local foodContainer = UI.Container(function(widget, items)
  storage.foodItems = items
end, true)
foodContainer:setHeight(35)
foodContainer:setItems(storage.foodItems)

-- Eat Food: human-like burst eating.
-- Players don't tap a food item every 0.5s; they right-click rapidly until the
-- server says "You are full" and then leave it alone for a while.
-- Behavior:
--   * Idle until player:getRegenerationTime() < eatTriggerSec (default ~200s).
--   * Then "burst": use a food item every random(150-400)ms.
--   * Burst ends when we receive a "full" message OR regen climbs above
--     eatStopSec (default ~800s) OR burst has been running too long.
--   * After a burst, force a cool-down window before checking again.
if type(storage.eatFood) ~= "table" then
  storage.eatFood = {}
end
local eatCfg = storage.eatFood
eatCfg.eatTriggerSec  = eatCfg.eatTriggerSec  or 200   -- start burst below this regen time (seconds)
eatCfg.eatStopSec     = eatCfg.eatStopSec     or 800   -- stop burst above this regen time (seconds)
eatCfg.minDelay       = eatCfg.minDelay       or 150   -- min ms between bites in a burst
eatCfg.maxDelay       = eatCfg.maxDelay       or 400   -- max ms between bites in a burst
eatCfg.cooldownMs     = eatCfg.cooldownMs     or 90000 -- min ms between bursts after a "full" message
eatCfg.maxBurstMs     = eatCfg.maxBurstMs     or 8000  -- safety cap on a single burst

local eatState = { nextBiteAt = 0, burstStartedAt = 0, cooldownUntil = 0, inBurst = false }

local function pickFood()
  for _, container in pairs(g_game.getContainers()) do
    for __, item in ipairs(container:getItems()) do
      for _, foodItem in ipairs(storage.foodItems) do
        if item:getId() == foodItem.id then
          return item
        end
      end
    end
  end
  return nil
end

onTextMessage(function(mode, text)
  if not text then return end
  local lower = text:lower()
  if lower:find("you are full") or lower:find("you are completely") then
    eatState.inBurst = false
    eatState.cooldownUntil = now + eatCfg.cooldownMs
  end
end)

macro(100, "Eat Food", function()
  if not storage.foodItems[1] then return end
  if eatState.inBurst then
    if now < eatState.nextBiteAt then return end
    if now - eatState.burstStartedAt > eatCfg.maxBurstMs
        or player:getRegenerationTime() > eatCfg.eatStopSec then
      eatState.inBurst = false
      eatState.cooldownUntil = now + eatCfg.cooldownMs
      return
    end
    local food = pickFood()
    if not food then
      eatState.inBurst = false
      return
    end
    g_game.use(food)
    eatState.nextBiteAt = now + math.random(eatCfg.minDelay, eatCfg.maxDelay)
  else
    if now < eatState.cooldownUntil then return end
    if player:getRegenerationTime() >= eatCfg.eatTriggerSec then return end
    eatState.inBurst = true
    eatState.burstStartedAt = now
    eatState.nextBiteAt = now
  end
end)
UI.Separator()