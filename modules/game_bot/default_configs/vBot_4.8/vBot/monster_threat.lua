-- Monster Threat overlay.
--
-- The 7.72 client knows nothing about a creature beyond its name, outfit and
-- health bar. The server, however, ships per-monster combat stats in
-- decompiled-tibia-game/mon/*.mon. We bake those into vBot/monster_data.lua
-- (global `MonsterData`, regenerate with tools/gen_monster_data.py) and use
-- them here to colour-code creatures around the player by danger.
--
-- A precomputed `score` (attack/HP/experience weighted, see the generator) is
-- bucketed into four tiers and rendered as a coloured square via setMarked():
--   Trivial   (green)   Moderate (yellow)   Dangerous (orange)   Deadly (red)
--
-- Optional text hints (drawn above the creature via setText):
--   * Tier name.
--   * Kiting hint: the monster's real move speed is spd*2+80 (same formula the
--     server uses for everyone, crmain.cc TCreature::GetSpeed). Compared to our
--     current player:getSpeed() we label it slower / even / FASTER so we know
--     whether we can out-walk it. "noPara" is added when it is also immune to
--     paralyze (truly cannot be kited).
--   * Immunities: damage types it ignores (E=energy F=fire P=earth/poison
--     D=death) so a mage does not waste runes on an immune element. There is no
--     physical immunity in 7.72, so melee always works.
--
-- Notes / limits:
--   * Names not present in MonsterData (custom/renamed creatures) are skipped.
--   * setMarked is shared with a few other scripts (player list, stand lure).
--     We only ever touch monsters and clear our own marks, but a creature that
--     is simultaneously a lure target may flip colours.

setDefaultTab("Target")

if type(storage.monsterThreat) ~= "table" then
  storage.monsterThreat = {}
end
local cfg = storage.monsterThreat
if cfg.enabled == nil then cfg.enabled = false end
if cfg.showName == nil then cfg.showName = false end
if cfg.showSpeed == nil then cfg.showSpeed = false end
if cfg.showImmune == nil then cfg.showImmune = false end
cfg.minTier = cfg.minTier or 1   -- only mark creatures at this tier or higher

-- Danger tiers. `max` is the exclusive upper score bound for the tier.
local TIERS = {
  { max = 200,        color = "#4CAF50", name = "Trivial"   },
  { max = 600,        color = "#FFEB3B", name = "Moderate"  },
  { max = 2000,       color = "#FF9800", name = "Dangerous" },
  { max = math.huge,  color = "#F44336", name = "Deadly"    },
}

local function tierIndex(score)
  for i, t in ipairs(TIERS) do
    if score < t.max then return i end
  end
  return #TIERS
end

-- Margin (move-speed points) before we call a small speed difference decisive.
local SPEED_MARGIN = 10

local function playerSpeed()
  local ok, s = pcall(function() return player:getSpeed() end)
  if ok and type(s) == "number" then return s end
  return nil
end

-- Kiting hint comparing the player's current speed to the monster's base speed.
local function speedTag(data)
  local ps = playerSpeed()
  if not ps then return nil end
  local ms = data.spd * 2 + 80           -- server move-speed formula
  local tag
  if ps > ms + SPEED_MARGIN then
    tag = "slower"                        -- we out-walk it -> kiteable
  elseif ms > ps + SPEED_MARGIN then
    tag = "FASTER"                        -- it out-walks us -> cannot escape
    if data.para == 0 then tag = tag .. " noPara" end
  else
    tag = "even"
  end
  return tag
end

-- Human-readable immunity tag, e.g. "imm FP". nil when nothing is immune.
local IMM_LABEL = { e = "E", f = "F", p = "P", d = "D" }
local function immuneTag(data)
  if not data.imm or #data.imm == 0 then return nil end
  local letters = ""
  for ch in data.imm:gmatch(".") do
    letters = letters .. (IMM_LABEL[ch] or "")
  end
  if #letters == 0 then return nil end
  return "imm " .. letters
end

-- Compose the text shown above a creature from the enabled hint toggles.
local function buildText(data, tierName)
  local parts = {}
  if cfg.showName then parts[#parts + 1] = tierName end
  if cfg.showSpeed then
    local t = speedTag(data)
    if t then parts[#parts + 1] = t end
  end
  if cfg.showImmune then
    local t = immuneTag(data)
    if t then parts[#parts + 1] = t end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "\n")
end

-- Creatures we have marked, so we can clear exactly our own marks.
local markedList = {}
local function clearMarks()
  for _, c in ipairs(markedList) do
    pcall(function()
      c:setMarked("")
      c:setText("")
    end)
  end
  markedList = {}
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
    !text: tr('Monster Threat')

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
  height: 134

  Label
    anchors.top: parent.top
    anchors.left: parent.left
    margin-top: 5
    margin-left: 3
    text: Mark from tier (1-4):
    width: 140
    tooltip: 1 marks everything, 2 hides Trivial, 3 hides Moderate, 4 only Deadly.

  BotTextEdit
    id: minTier
    anchors.verticalCenter: prev.verticalCenter
    anchors.right: parent.right
    margin-right: 5
    width: 45

  BotSwitch
    id: showName
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    width: 180
    !text: tr('Show tier name on creature')

  BotSwitch
    id: showSpeed
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 3
    width: 180
    !text: tr('Show kiting hint (speed)')
    tooltip: slower = you out-walk it; FASTER = it catches you; noPara = paralyze-immune.

  BotSwitch
    id: showImmune
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 4
    margin-left: 3
    width: 180
    !text: tr('Show immunities (E/F/P/D)')
    tooltip: E=energy F=fire P=earth/poison D=death. No physical immunity exists.

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 6
    margin-left: 3
    text: Green Trivial / Yellow Moderate
    color: #aaaaaa

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-left: 3
    text: Orange Dangerous / Red Deadly
    color: #aaaaaa
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
  if not cfg.enabled then clearMarks() end
end

params.showName:setOn(cfg.showName)
params.showName.onClick = function()
  cfg.showName = not cfg.showName
  params.showName:setOn(cfg.showName)
end

params.showSpeed:setOn(cfg.showSpeed)
params.showSpeed.onClick = function()
  cfg.showSpeed = not cfg.showSpeed
  params.showSpeed:setOn(cfg.showSpeed)
end

params.showImmune:setOn(cfg.showImmune)
params.showImmune.onClick = function()
  cfg.showImmune = not cfg.showImmune
  params.showImmune:setOn(cfg.showImmune)
end

params.minTier:setText(tostring(cfg.minTier))
params.minTier.onTextChange = function(_, text)
  local n = tonumber(text)
  if not n then return end
  cfg.minTier = math.max(1, math.min(#TIERS, math.floor(n)))
end

------------------------------------------------------------------------------
-- Overlay loop
------------------------------------------------------------------------------
macro(400, function()
  -- Always start clean so dead/out-of-view creatures don't keep stale marks.
  clearMarks()
  if not cfg.enabled then return end
  if type(MonsterData) ~= "table" then return end

  for _, c in ipairs(getSpectators()) do
    if c:isMonster() then
      local data = MonsterData[c:getName():lower()]
      if data then
        local idx = tierIndex(data.score)
        if idx >= cfg.minTier then
          local tier = TIERS[idx]
          c:setMarked(tier.color)
          local text = buildText(data, tier.name)
          if text then c:setText(text) end
          table.insert(markedList, c)
        end
      end
    end
  end
end)
