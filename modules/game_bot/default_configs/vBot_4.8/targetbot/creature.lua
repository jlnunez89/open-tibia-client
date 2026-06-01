
TargetBot.Creature = {}
TargetBot.Creature.configsCache = {}
TargetBot.Creature.cached = 0

TargetBot.Creature.resetConfigs = function()
  TargetBot.targetList:destroyChildren()
  TargetBot.Creature.resetConfigsCache()
end

TargetBot.Creature.resetConfigsCache = function()
  TargetBot.Creature.configsCache = {}
  TargetBot.Creature.cached = 0
end

TargetBot.Creature.addConfig = function(config, focus)
  if type(config) ~= 'table' or type(config.name) ~= 'string' then
    return error("Invalid targetbot creature config (missing name)")
  end
  TargetBot.Creature.resetConfigsCache()

  if not config.regex then
    config.regex = ""
    for part in string.gmatch(config.name, "[^,]+") do
      if config.regex:len() > 0 then
        config.regex = config.regex .. "|"
      end
      config.regex = config.regex .. "^" .. part:trim():lower():gsub("%*", ".*"):gsub("%?", ".?") .. "$"
    end
  end

  local widget = UI.createWidget("TargetBotEntry", TargetBot.targetList)
  widget:setText(config.name)
  widget.value = config

  widget.onDoubleClick = function(entry) -- edit on double click
    schedule(20, function() -- schedule to have correct focus
      TargetBot.Creature.edit(entry.value, function(newConfig)
        entry:setText(newConfig.name)
        entry.value = newConfig
        TargetBot.Creature.resetConfigsCache()
        TargetBot.save()
      end)
    end)
  end

  if focus then
    widget:focus()
    TargetBot.targetList:ensureChildVisible(widget)
  end
  return widget
end

TargetBot.Creature.getConfigs = function(creature)
  if not creature then return {} end
  local name = creature:getName():trim():lower()
  -- this function may be slow, so it will be using cache
  if TargetBot.Creature.configsCache[name] then
    return TargetBot.Creature.configsCache[name]
  end
  local configs = {}
  for _, config in ipairs(TargetBot.targetList:getChildren()) do
    if regexMatch(name, config.value.regex)[1] then
      table.insert(configs, config.value)
    end
  end
  -- Order matched rules from MOST specific to LEAST specific so a precise rule
  -- (e.g. "Dragon Lord") always wins over a broader one (e.g. "Dragon*" or the
  -- catch-all "*"). Specificity is ranked, for the pattern part that actually
  -- matched this creature, as:
  --   exact name (no wildcards)  <  uses '?'  <  uses '*'  <  catch-all "*"
  -- and within the same class, fewer wildcards is more specific.
  TargetBot.Creature.sortConfigsBySpecificity(configs, name)
  if TargetBot.Creature.cached > 1000 then 
    TargetBot.Creature.resetConfigsCache() -- too big cache size, reset
  end
  TargetBot.Creature.configsCache[name] = configs -- add to cache
  TargetBot.Creature.cached = TargetBot.Creature.cached + 1
  return configs
end

-- Specificity rank of a single raw glob part (lower = more specific).
-- '*' is treated as far broader than '?', and a lone "*" catch-all is last.
local function patternRank(pattern)
  if pattern == "*" then return math.huge end
  local _, stars = pattern:gsub("%*", "")
  local _, quests = pattern:gsub("%?", "")
  return stars * 1000 + quests
end

-- Best (most specific) rank among the comma-separated parts of a config's name
-- that actually match `name`. Falls back to math.huge if none match (shouldn't
-- happen because the config only reaches here after a regex match).
local function configRank(config, name)
  local best = math.huge
  for part in string.gmatch(config.name, "[^,]+") do
    local p = part:trim():lower()
    local rx = "^" .. p:gsub("%*", ".*"):gsub("%?", ".?") .. "$"
    if regexMatch(name, rx)[1] then
      local r = patternRank(p)
      if r < best then best = r end
    end
  end
  return best
end

TargetBot.Creature.sortConfigsBySpecificity = function(configs, name)
  -- Decorate with rank + original index, stable-sort, then strip. Stable order
  -- (by original list position) is preserved for equally-specific rules.
  local decorated = {}
  for i, config in ipairs(configs) do
    decorated[i] = {config = config, rank = configRank(config, name), index = i}
  end
  table.sort(decorated, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.index < b.index
  end)
  for i, d in ipairs(decorated) do
    configs[i] = d.config
  end
  return configs
end

TargetBot.Creature.calculateParams = function(creature, path)
  local configs = TargetBot.Creature.getConfigs(creature) -- most specific first
  -- Walk rules from most to least specific and use the first one that actually
  -- applies (priority > 0). This makes a precise rule take precedence over a
  -- broader/catch-all rule even when the broader rule would yield a higher raw
  -- priority value.
  for _, config in ipairs(configs) do
    local priority = TargetBot.Creature.calculatePriority(creature, config, path)
    if priority > 0 then
      return {
        config = config,
        creature = creature,
        danger = TargetBot.Creature.calculateDanger(creature, config, path),
        priority = priority
      }
    end
  end
  -- No rule applies (e.g. all out of range): not a target this tick. Danger is
  -- left at 0 to preserve the original behaviour (danger was only counted for a
  -- selected, attackable config).
  return {
    config = nil,
    creature = creature,
    danger = 0,
    priority = 0
  }
end

TargetBot.Creature.calculateDanger = function(creature, config, path)
  -- config is based on creature_editor
  return config.danger
end
