function g_game.getRsa()
  return G.currentRsa
end

function g_game.findPlayerItem(itemId, subType)
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
        for slot = InventorySlotFirst, InventorySlotLast do
            local item = localPlayer:getInventoryItem(slot)
            if item and item:getId() == itemId and (subType == -1 or item:getSubType() == subType) then
                return item
            end
        end
    end

    return g_game.findItemInContainers(itemId, subType)
end

-- Action throttle. The server queues every rune/use-with and spell packet and each
-- new one cancels the pending queue (snapping back a walk in progress), while
-- spells/runes inside the exhaustion window are held for up to a second. To stop
-- spammed actions from piling up, at most one rune/use-with or spell is sent per
-- gap; a call that comes too early is deferred (only the latest one is kept) and
-- also waits for the current step to finish. Configurable in Options > Game.
local actionThrottle = { lastSentAt = 0, pending = nil, polling = false }
local ACTION_POLL_MS = 20
local ACTION_WALK_HOLD_MAX_MS = 300 -- never delay an action longer than this just to wait for a step

local function actionThrottleEnabled()
  return g_settings.getBoolean('actionThrottle', true)
end

local function canSendAction(now, since)
  local readyAt = actionThrottle.lastSentAt + g_settings.getNumber('actionThrottleGap', 1000)
  if now < readyAt then return false end
  local player = g_game.getLocalPlayer()
  if player and player:isWalking() and now < math.max(readyAt, since) + ACTION_WALK_HOLD_MAX_MS then
    return false
  end
  return true
end

local function pollPendingAction()
  local pending = actionThrottle.pending
  if not pending then
    actionThrottle.polling = false
    return
  end
  if not g_game.isOnline() then
    actionThrottle.pending = nil
    actionThrottle.polling = false
    return
  end
  local now = g_clock.millis()
  if not actionThrottleEnabled() or canSendAction(now, pending.since) then
    actionThrottle.pending = nil
    actionThrottle.polling = false
    actionThrottle.lastSentAt = now
    pending.run()
    return
  end
  scheduleEvent(pollPendingAction, ACTION_POLL_MS)
end

local function throttleAction(run)
  if not actionThrottleEnabled() then
    return run()
  end
  local now = g_clock.millis()
  local pending = actionThrottle.pending
  if pending then
    pending.run = run -- keep only the latest action
  elseif canSendAction(now, now) then
    actionThrottle.lastSentAt = now
    return run()
  else
    actionThrottle.pending = { run = run, since = now }
  end
  if not actionThrottle.polling then
    actionThrottle.polling = true
    scheduleEvent(pollPendingAction, ACTION_POLL_MS)
  end
end

local spellWordsCache
local function isSpellText(text)
  if not spellWordsCache then
    spellWordsCache = {}
    for _, profile in pairs(SpellInfo or {}) do
      for _, spell in pairs(profile) do
        if spell.words then
          spellWordsCache[spell.words] = spell.parameter and 'parameter' or 'plain'
        end
      end
    end
  end

  local tokens = {}
  for token in text:lower():gmatch('%S+') do
    tokens[#tokens + 1] = token
  end
  for count = #tokens, 1, -1 do
    local kind = spellWordsCache[table.concat(tokens, ' ', 1, count)]
    if kind == 'plain' and count == #tokens then return true end
    if kind == 'parameter' then return true end
  end
  return false
end

if not g_game.talkNative then
  g_game.talkNative = g_game.talk
  g_game.talkChannelNative = g_game.talkChannel
end

function g_game.talk(text)
  if type(text) == 'string' and isSpellText(text) then
    return throttleAction(function() g_game.talkNative(text) end)
  end
  return g_game.talkNative(text)
end

function g_game.talkChannel(mode, channelId, text)
  if mode == MessageModes.Say and type(text) == 'string' and isSpellText(text) then
    return throttleAction(function() g_game.talkChannelNative(mode, channelId, text) end)
  end
  return g_game.talkChannelNative(mode, channelId, text)
end

-- Pre-7.8 clients send the creature's (truncated) id as the target object type in
-- the use-with packet (0x83) instead of the creature object type, so the server
-- silently ignores any use-with aimed at a creature (or, when the truncated id
-- happens to be a valid type, handles it unpredictably). Craft the packet
-- ourselves for creature targets.
if not g_game.useWithNative then
  g_game.useWithNative = g_game.useWith
end

-- 7.7 clients identify a creature as object type 99 when it is the target of a
-- use-with.
local CREATURE_OBJECT_TYPE = 99
local ClientUseTwoObjects = 0x83

local function sendUseWithOnCreature(item, creature, subType)
  local protocol = g_game.getProtocolGame()
  if not protocol or not g_game.isOnline() then
    return
  end

  local itemPos = item:getPosition()
  if not itemPos or (itemPos.x == 0xFFFF and itemPos.y == 0xFFFF) then
    itemPos = { x = 0xFFFF, y = 0, z = 0 } -- virtual item in the inventory
  end

  local msg = OutputMessage.create()
  msg:addU8(ClientUseTwoObjects)
  msg:addPosition(itemPos)
  msg:addU16(item:getId())
  msg:addU8(item:getStackPos())
  msg:addPosition(creature:getPosition())
  msg:addU16(CREATURE_OBJECT_TYPE)
  msg:addU8(creature:getStackPos())
  protocol:send(msg)

  pcall(function() g_game.onUseWith(itemPos, item:getId(), creature, subType) end)
end

function g_game.useWith(item, toThing, subType)
  local isCreature = toThing and toThing.isCreature and toThing:isCreature()
  local craftPacket = isCreature and item and g_game.getClientVersion() < 780
  -- Diagnostics: run `G.debugUseWith = true` in the terminal to log each call.
  if G.debugUseWith then
    local p = toThing and toThing:getPosition()
    g_logger.info(string.format("[useWith] item=%s target=%s pos=%s sub=%s crafted=%s",
      item and item:getId() or "nil", toThing and toThing:getId() or "nil",
      p and (p.x .. "," .. p.y .. "," .. p.z) or "nil", tostring(subType), tostring(craftPacket and true or false)))
  end
  return throttleAction(function()
    if craftPacket then
      sendUseWithOnCreature(item, toThing, subType)
    elseif subType == nil then
      g_game.useWithNative(item, toThing)
    else
      g_game.useWithNative(item, toThing, subType)
    end
  end)
end

if g_game.useInventoryItemWith then
  if not g_game.useInventoryItemWithNative then
    g_game.useInventoryItemWithNative = g_game.useInventoryItemWith
  end

  function g_game.useInventoryItemWith(itemId, toThing, subType)
    return throttleAction(function()
      if subType == nil then
        g_game.useInventoryItemWithNative(itemId, toThing)
      else
        g_game.useInventoryItemWithNative(itemId, toThing, subType)
      end
    end)
  end
end

function g_game.chooseRsa(host)
  if G.currentRsa ~= CIPSOFT_RSA and G.currentRsa ~= OTSERV_RSA then return end
  if host:ends('.tibia.com') or host:ends('.cipsoft.com') then
    g_game.setRsa(CIPSOFT_RSA)

    if g_app.getOs() == 'windows' then
      g_game.setCustomOs(OsTypes.Windows)
    else
      g_game.setCustomOs(OsTypes.Linux)
    end
  else
    if G.currentRsa == CIPSOFT_RSA then
      g_game.setCustomOs(-1)
    end
    g_game.setRsa(OTSERV_RSA)
  end

  -- Hack fix to resolve some 760 login issues
  if g_game.getClientVersion() <= 760 then
    g_game.setCustomOs(2)
  end
end

function g_game.setRsa(rsa, e)
  e = e or '65537'
  g_crypt.rsaSetPublicKey(rsa, e)
  G.currentRsa = rsa
end

function g_game.isOfficialTibia()
  return G.currentRsa == CIPSOFT_RSA
end

function g_game.getSupportedClients()
  return {
    740, 741, 750, 760, 770, 772,
    780, 781, 782, 790, 792,

    800, 810, 811, 820, 821, 822,
    830, 831, 840, 842, 850, 853,
    854, 855, 857, 860, 861, 862,
    870, 871,

    900, 910, 920, 931, 940, 943,
    944, 951, 952, 953, 954, 960,
    961, 963, 970, 971, 972, 973,
    980, 981, 982, 983, 984, 985,
    986,

    1000, 1001, 1002, 1010, 1011,
    1012, 1013, 1020, 1021, 1022,
    1030, 1031, 1032, 1033, 1034,
    1035, 1036, 1037, 1038, 1039,
    1040, 1041, 1050, 1051, 1052,
    1053, 1054, 1055, 1056, 1057,
    1058, 1059, 1060, 1061, 1062,
    1063, 1064, 1070, 1071, 1072,
    1073, 1074, 1075, 1076, 1080,
    1081, 1082, 1090, 1091, 1092,
    1093, 1094, 1095, 1096, 1097,
    1098, 1099
  }
end

-- The client version and protocol version where
-- unsynchronized for some releases, not sure if this
-- will be the normal standard.

-- Client Version: Publicly given version when
-- downloading Cipsoft client.

-- Protocol Version: Previously was the same as
-- the client version, but was unsychronized in some
-- releases, now it needs to be verified and added here
-- if it does not match the client version.

-- Reason for defining both: The server now requires a
-- Client version and Protocol version from the client.

-- Important: Use getClientVersion for specific protocol
-- features to ensure we are using the proper version.

function g_game.getClientProtocolVersion(client)
  local clients = {
    [980] = 971,
    [981] = 973,
    [982] = 974,
    [983] = 975,
    [984] = 976,
    [985] = 977,
    [986] = 978,
    [1001] = 979,
    [1002] = 980
  }
  return clients[client] or client
end

if not G.currentRsa then
  g_game.setRsa(OTSERV_RSA)
end
