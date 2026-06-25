local targetBotLure = false
local targetCount = 0 
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local delayFrom = nil
local dynamicLureDelay = false

local attackJitterFor = nil
local attackJitterUntil = 0

-- Training mode target selection. Instead of just holding a single creature
-- alive, Training Mode picks a target from the configured pool and switches
-- between targets using the stop/resume HP band: a target is only ACQUIRED once
-- it has healed to/above resumeAbove%, and is DROPPED once it falls to/below
-- stopBelow%. Between the two thresholds we keep the current target (hysteresis)
-- so selection doesn't flap. This lets the bot, e.g., burst one summoned Monk
-- down then move to a second healthy Monk while the first heals. The id of the
-- currently selected creature is kept across ticks. See TargetBot.Creature.
-- getTrainingTarget below; it returns the params table to attack (or nil).
local trainingTargetId = nil

-- Minimal config used when a training pool creature matches no TargetBot rule
-- (e.g. the player's current manual target or a party member). Chase + basic
-- auto-attack only; no spells/runes are cast for these.
local defaultTrainingConfig = {
  name = "Training",
  priority = 1,
  danger = 0,
  maxDistance = 10,
  chase = true,
  keepDistance = false,
  keepDistanceRange = 1,
}

-- True for creatures Training Mode may attack from the "TargetBot" pool. Unlike
-- the normal target scan (which is limited to plain monsters), this also allows
-- summoned creatures so training on another player's summons (e.g. Monks) works.
-- Creature types (see gamelib/creature.lua): 1 = monster, 2 = npc, 3 = own
-- summon, 4 = other player's summon. The bot sandbox doesn't expose those
-- constants, so the raw numbers are used (matching the rest of the targetbot).
local function isTrainableMonster(c)
  if c:isLocalPlayer() or c:isPlayer() then return false end
  local t = c:getType()
  return c:isMonster() or t == 3 or t == 4
end

local function trainingParamsFor(creature, params)
  if params then return params end
  return {config = defaultTrainingConfig, creature = creature, danger = 0, priority = 1}
end

TargetBot.Creature.getTrainingTarget = function()
  local training = storage.targetTraining
  if not (training and training.enabled) then
    trainingTargetId = nil
    return nil
  end
  local stopBelow = tonumber(training.stopBelow) or 40
  local resumeAbove = tonumber(training.resumeAbove) or 70
  local source = training.source or "TargetBot"
  local pos = player:getPosition()

  -- Build the candidate pool (deduped by id). Each entry carries the creature,
  -- optional TargetBot params (for proper spell/rune attacking), and current HP.
  local pool = {}
  local seen = {}
  local function add(creature, params)
    if not creature then return end
    local id = creature:getId()
    if seen[id] then return end
    local hp = creature:getHealthPercent()
    if not hp or hp <= 0 then return end
    seen[id] = true
    pool[#pool + 1] = {creature = creature, params = params, hp = hp, id = id}
  end

  if source == "Current Target" then
    add(g_game.getAttackingCreature())
    -- Keep watching the last picked target even after we stopped attacking it,
    -- so we can detect it healing back to resumeAbove% and resume.
    if trainingTargetId then add(getCreatureById(trainingTargetId)) end
  elseif source == "Party Members" then
    for _, spec in ipairs(g_map.getSpectatorsInRange(pos, false, 7, 7)) do
      if not spec:isLocalPlayer() and spec:isPlayer() and spec:isPartyMember() then
        add(spec)
      end
    end
  else -- "TargetBot": pool bounded by the TargetBot creature rules.
    for _, spec in ipairs(g_map.getSpectatorsInRange(pos, false, 7, 7)) do
      if isTrainableMonster(spec) then
        local path = findPath(pos, spec:getPosition(), 7, {ignoreLastCreature = true, ignoreNonPathable = true, ignoreCost = true, ignoreCreatures = true})
        if path then
          local params = TargetBot.Creature.calculateParams(spec, path)
          if params.priority > 0 then
            add(spec, params)
          end
        end
      end
    end
  end

  -- Resolve the currently-held target within the pool.
  local current = nil
  if trainingTargetId then
    for _, e in ipairs(pool) do
      if e.id == trainingTargetId then current = e break end
    end
  end

  -- Keep the current target until it drops to/below stopBelow% (de-select).
  if current and current.hp > stopBelow then
    return trainingParamsFor(current.creature, current.params)
  end

  -- Acquire a new target: the healthiest candidate at/above resumeAbove%. This
  -- naturally rotates to a fresh, full-HP target while the previous one heals.
  local best = nil
  for _, e in ipairs(pool) do
    if e.hp >= resumeAbove and (not best or e.hp > best.hp) then
      best = e
    end
  end
  if best then
    trainingTargetId = best.id
    return trainingParamsFor(best.creature, best.params)
  end

  -- Nothing healthy enough yet: stop and wait for a target to heal up.
  trainingTargetId = nil
  return nil
end

-- Anti-detection: when too many monsters are clustered around the player,
-- step away from their centroid to break stationary-tank patterns. Gated
-- by humanize.maxAttackers() and a cooldown. No-op when humanize is off.
local lastOverloadReposition = 0
local function overloadReposition()
  if not (humanize and humanize.enabled()) then return end
  local cooldown = humanize.repositionCooldown and humanize.repositionCooldown() or 6000
  if now - lastOverloadReposition < cooldown then return end
  local pPos = player:getPosition()
  local attackers = {}
  for _, c in ipairs(g_map.getSpectatorsInRange(pPos, false, 4, 4)) do
    if c:isMonster() then
      table.insert(attackers, c:getPosition())
    end
  end
  local maxA = humanize.maxAttackers and humanize.maxAttackers() or 4
  if #attackers <= maxA then return end
  -- Chance gate: even when overcrowded, only reposition some of the time so the
  -- step-away isn't perfectly predictable. A failed roll still consumes the
  -- cooldown so the chance is evaluated once per opportunity, not every tick.
  local chance = humanize.repositionChance and humanize.repositionChance() or 100
  if math.random(0, 99) >= chance then
    lastOverloadReposition = now
    return
  end
  local sx, sy = 0, 0
  for _, p in ipairs(attackers) do sx = sx + p.x; sy = sy + p.y end
  local cx, cy = sx / #attackers, sy / #attackers
  local dx, dy = pPos.x - cx, pPos.y - cy
  local stepX = (math.abs(dx) < 0.001) and 0 or (dx > 0 and 1 or -1)
  local stepY = (math.abs(dy) < 0.001) and 0 or (dy > 0 and 1 or -1)
  if stepX == 0 and stepY == 0 then return end
  local target = {x = pPos.x + stepX, y = pPos.y + stepY, z = pPos.z}
  local tile = g_map.getTile(target)
  if not tile or not tile:isWalkable() or not tile:isPathable() then return end
  lastOverloadReposition = now
  return CaveBot.GoTo(target, 0)
end

TargetBot.Creature.attack = function(params, targets, isLooting) -- params {config, creature, danger, priority}
  if player:isWalking() then
    lastWalk = now
  end

  local config = params.config
  local creature = params.creature

  if g_game.getAttackingCreature() ~= creature then
    -- Anti-detection: skip attack initiation entirely during a humanize pause.
    if humanize and humanize.enabled() and not humanize.canActNow() then
      TargetBot.delay(250)
      return
    end
    -- Anti-detection: stagger the attack packet by a small randomized delay
    -- on each new target acquisition. We arm the delay once per target then
    -- attack normally on the next tick that lands after the deadline.
    if humanize and humanize.enabled() then
      if attackJitterFor ~= creature then
        local jitter = humanize.delay("attackStart")
        attackJitterFor = creature
        attackJitterUntil = now + jitter
        if jitter > 0 then
          TargetBot.delay(jitter)
          return
        end
      elseif now < attackJitterUntil then
        TargetBot.delay(attackJitterUntil - now)
        return
      end
    end
    g_game.attack(creature)
  else
    attackJitterFor = creature
  end

  if not isLooting then -- walk only when not looting
    -- Phase 6: try overload reposition before the normal walk routine; if it
    -- returns a walk action, defer normal walk this tick.
    if overloadReposition() then return end
    TargetBot.Creature.walk(creature, config, targets)
  end

  -- attacks
  local mana = player:getMana()
  if config.useGroupAttack and config.groupAttackSpell:len() > 1 and mana > config.minManaGroup then
    local creatures = g_map.getSpectatorsInRange(player:getPosition(), false, config.groupAttackRadius, config.groupAttackRadius)
    local playersAround = false
    local monsters = 0
    for _, creature in ipairs(creatures) do
      if not creature:isLocalPlayer() and creature:isPlayer() and (not config.groupAttackIgnoreParty or creature:getShield() <= 2) then
        playersAround = true
      elseif creature:isMonster() then
        monsters = monsters + 1
      end
    end
    if monsters >= config.groupAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.sayAttackSpell(config.groupAttackSpell, config.groupAttackDelay) then
        return
      end
    end
  end

  if config.useGroupAttackRune and config.groupAttackRune > 100 then
    local creatures = g_map.getSpectatorsInRange(creature:getPosition(), false, config.groupRuneAttackRadius, config.groupRuneAttackRadius)
    local playersAround = false
    local monsters = 0
    for _, creature in ipairs(creatures) do
      if not creature:isLocalPlayer() and creature:isPlayer() and (not config.groupAttackIgnoreParty or creature:getShield() <= 2) then
        playersAround = true
      elseif creature:isMonster() then
        monsters = monsters + 1
      end
    end
    if monsters >= config.groupRuneAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.useAttackItem(config.groupAttackRune, 0, creature, config.groupRuneAttackDelay) then
        return
      end
    end
  end
  if config.useSpellAttack and config.attackSpell:len() > 1 and mana > config.minMana then
    if TargetBot.sayAttackSpell(config.attackSpell, config.attackSpellDelay) then
      return
    end
  end
  if config.useRuneAttack and config.attackRune > 100 then
    if TargetBot.useAttackItem(config.attackRune, 0, creature, config.attackRuneDelay) then
      return
    end
  end
end

TargetBot.Creature.walk = function(creature, config, targets)
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  
  local isTrapped = true
  local pos = player:getPosition()
  local dirs = {{-1,1}, {0,1}, {1,1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}}
  for i=1,#dirs do
    local tile = g_map.getTile({x=pos.x-dirs[i][1],y=pos.y-dirs[i][2],z=pos.z})
    if tile and tile:isWalkable(false) then
      isTrapped = false
    end
  end

  -- data for external dynamic lure
  if config.lureMin and config.lureMax and config.dynamicLure then
    if config.lureMin >= targets then
      targetBotLure = true
    elseif targets >= config.lureMax then
      targetBotLure = false
    end
  end
  targetCount = targets
  delayValue = config.lureDelay

  if config.lureMax then
    lureMax = config.lureMax
  end

  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom

  -- luring
  if config.closeLure and config.closeLureAmount <= getMonsters(1) then
    return TargetBot.allowCaveBot(150)
  end
  if TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure) and not (creature:getHealthPercent() < (storage.extras.killUnder or 30)) and not isTrapped then
    if targetBotLure then
      anchorPosition = nil
      return TargetBot.allowCaveBot(150)
    else
      if targets < config.lureCount then
        if config.lureCavebot then
          anchorPosition = nil
          return TargetBot.allowCaveBot(150)
        else
          local path = findPath(pos, cpos, 5, {ignoreNonPathable=true, precision=2})
          if path then
            return TargetBot.walkTo(cpos, 10, {marginMin=5, marginMax=6, ignoreNonPathable=true})
          end
        end
      end
    end
  end

  local currentDistance = findPath(pos, cpos, 10, {ignoreCreatures=true, ignoreNonPathable=true, ignoreCost=true})
  -- Chase override: while there are still reachable corpses queued for looting,
  -- don't chase the next live target. This stops the character from oscillating
  -- between walking to a fresh corpse (looting) and chasing a mob a few tiles
  -- away. Forced kills (killUnder) are unaffected.
  local killUnder = storage.extras.killUnder or 1
  local chaseActive = config.chase and not TargetBot.Looting.hasReachableLoot()
  if ((killUnder > 1 and (creature:getHealthPercent() < killUnder)) or chaseActive) and not config.keepDistance then
    if #currentDistance > 1 then
      return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, precision=1})
    end
  elseif config.keepDistance then
    if not anchorPosition or distanceFromPlayer(anchorPosition) > config.anchorRange then
      anchorPosition = pos
    end
    if #currentDistance ~= config.keepDistanceRange and #currentDistance ~= config.keepDistanceRange + 1 then
      if config.anchor and anchorPosition and getDistanceBetween(pos, anchorPosition) <= config.anchorRange*2 then
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=config.keepDistanceRange, marginMax=config.keepDistanceRange + 1, maxDistanceFrom={anchorPosition, config.anchorRange}})
      else
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=config.keepDistanceRange, marginMax=config.keepDistanceRange + 1})
      end
    end
  end

  --target only movement
  if config.avoidAttacks then
    local diffx = cpos.x - pos.x
    local diffy = cpos.y - pos.y
    local candidates = {}
    if math.abs(diffx) == 1 and diffy == 0 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x, y=pos.y+1, z=pos.z}}
    elseif diffx == 0 and math.abs(diffy) == 1 then
      candidates = {{x=pos.x-1, y=pos.y, z=pos.z}, {x=pos.x+1, y=pos.y, z=pos.z}}
    end
    for _, candidate in ipairs(candidates) do
      local tile = g_map.getTile(candidate)
      if tile and tile:isWalkable() and tile:isPathable() then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
      end
    end
  elseif config.faceMonster then
    local diffx = cpos.x - pos.x
    local diffy = cpos.y - pos.y
    local candidates = {}
    if diffx == 1 and diffy == 1 then
      candidates = {{x=pos.x+1, y=pos.y, z=pos.z}, {x=pos.x, y=pos.y-1, z=pos.z}}
    elseif diffx == -1 and diffy == 1 then
      candidates = {{x=pos.x-1, y=pos.y, z=pos.z}, {x=pos.x, y=pos.y-1, z=pos.z}}
    elseif diffx == -1 and diffy == -1 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x-1, y=pos.y, z=pos.z}} 
    elseif diffx == 1 and diffy == -1 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x+1, y=pos.y, z=pos.z}}       
    else
      local dir = player:getDirection()
      if diffx == 1 and dir ~= 1 then turn(1)
      elseif diffx == -1 and dir ~= 3 then turn(3)
      elseif diffy == 1 and dir ~= 2 then turn(2)
      elseif diffy == -1 and dir ~= 0 then turn(0)
      end
    end
    for _, candidate in ipairs(candidates) do
      local tile = g_map.getTile(candidate)
      if tile and tile:isWalkable() and tile:isPathable() then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
      end
    end
  end
end

onPlayerPositionChange(function(newPos, oldPos)
  if CaveBot.isOff() then return end
  if TargetBot.isOff() then return end
  if not lureMax then return end
  if storage.TargetBotDelayWhenPlayer then return end
  if not dynamicLureDelay then return end

  if targetCount < (delayFrom or lureMax/2) or not target() then return end
  CaveBot.delay(delayValue or 0)
end)