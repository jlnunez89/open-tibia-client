-- load all otui files, order doesn't matter
local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text

local configFiles = g_resources.listDirectoryFiles("/bot/" .. configName .. "/vBot", true, false)
for i, file in ipairs(configFiles) do
  local ext = file:split(".")
  if ext[#ext]:lower() == "ui" or ext[#ext]:lower() == "otui" then
    g_ui.importStyle(file)
  end
end

local function loadScript(name)
  return dofile("/vBot/" .. name .. ".lua")
end

-- here you can set manually order of scripts
-- libraries should be loaded first
local luaFiles = {
  "main",
  "hazard_fix",  -- patch DAT NotPathable flags for 7.7 hazards (before any pathfinding)
  "items",
  "vlib",
  "new_cavebot_lib",
  "configs", -- do not change this and above
  "humanize",
  "extras",
  "cavebot",
  "playerlist",
  -- "BotServer", -- removed: requires external BotServer, not available on 7.7
  "alarms",
  "Conditions",
  "Equipper",
  "pushmax",
  "combo",
  "HealBot",
  "new_healer",
  "AttackBot", -- last of major modules
  "ingame_editor",
  "Dropper",
  "Containers",
  -- "quiver_manager", -- removed: quivers not available on 7.7
  -- "quiver_label", -- removed: quivers not available on 7.7
  "tools",
  "antiRs",
  -- "depot_withdraw", -- removed: uses modern item IDs (shopping bag 21411)
  "eat_food",
  "auto_light",
  "auto_fish",
  "equip",
  -- "exeta", -- removed: uses game_cooldown module (8.0+)
  "monster_data",   -- generated 7.7 monster stats (load before monster_threat)
  "monster_threat", -- danger overlay built from monster_data
  "analyzer",
  "spy_level",
  "supplies",
  "depositer_config",
  "npc_talk",
  "xeno_menu",
  "hold_target",
  "cavebot_control_panel",
  "my_rune_maker",
  "my_wanderer",
  "scavenge_items",
  "stack_items",
  "bp_organizer",
  "set_tactics"
}

for i, file in ipairs(luaFiles) do
  loadScript(file)
end

setDefaultTab("Main")
UI.Separator()
UI.Label("Private Scripts:")
UI.Separator()
