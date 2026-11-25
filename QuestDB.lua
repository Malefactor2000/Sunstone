-- Sunstone: where quest, creature, object and item facts come from. Questie's database when it's installed (read live, never
-- copied); otherwise our own: Classic's quests (QuestData.lua) and what Sunstone has seen on Forever as you play (QuestRec.lua),
-- which also fills in the quests Questie doesn't know. Everything else asks NS.Quests() and gets the same shape either way:
-- { Quest, Npc, Object, Item } with Get(id, field) and GetAllIds(), and Enum.

local _, NS = ...
local QD = NS.Module("QuestDB")
NS.QuestDB = QD

local floor = math.floor

local function Src() return type(_G.SunstoneQuests) == "table" and _G.SunstoneQuests or nil end
function QD.Questie()
  local L = _G.LibQuestieDB
  if L and L.Quest and L.Npc and L.Item and L.Object and L.Quest.Get then return L end
end

---------------------------------------------------------------------------
-- Reading a record: "a|b|c" with the empty ones left out at the end
---------------------------------------------------------------------------
local function Split(s, sep)
  local out, from = {}, 1
  while true do
    local at = s:find(sep, from, true)
    if not at then out[#out + 1] = s:sub(from) return out end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + 1
  end
end
local function Ids(s)
  if not s or s == "" then return nil end
  local out = {}
  for n in s:gmatch("%-?%d+") do out[#out + 1] = tonumber(n) end
  return #out > 0 and out or nil
end
local function Pairs(s) -- "76:250;47:5" -> { { 76, 250 }, ... }
  if not s or s == "" then return nil end
  local out = {}
  for a, b in s:gmatch("(%-?%d+):(%-?%d+)") do out[#out + 1] = { tonumber(a), tonumber(b) } end
  return #out > 0 and out or nil
end
local function Who(s) -- "n12,13;o5;i9" -> { { 12, 13 }, { 5 }, { 9 } }
  if not s or s == "" then return nil end
  local out, at = {}, { n = 1, o = 2, i = 3 }
  for part in s:gmatch("[^;]+") do
    local k = at[part:sub(1, 1)]
    if k then out[k] = Ids(part:sub(2)) end
  end
  return next(out) and out or nil
end

-- places: a continent position -> the zone it's in and the spot there, asked of the game
local VALUE = {}
do
  local s = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, #s do VALUE[s:byte(i)] = i - 1 end
end
local continents
local function Continent(inst)
  if not continents then
    continents = { [0] = 1415, [1] = 1414 } -- (the flight masters' maps are "continents" too, 1463 and 1464: those know no zones)
    local hbd = NS.HBD()
    for m, d in pairs(hbd and hbd.mapData or {}) do
      if type(d) == "table" and d.mapType == 2 and d.instance and not continents[d.instance] and m ~= 1463 and m ~= 1464 then continents[d.instance] = m end
    end
  end
  return continents[inst]
end
-- -> uiMapID, x, y (0-100)
function QD.Place(inst, wx, wy)
  local hbd, cont = NS.HBD(), Continent(inst)
  if not (hbd and cont and hbd.GetZoneCoordinatesFromWorld) then return nil end
  local cx, cy = hbd:GetZoneCoordinatesFromWorld(wx, wy, cont, true)
  local m
  if cx and C_Map and C_Map.GetMapInfoAtPosition then
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont, cx, cy)
    m = ok and type(info) == "table" and info.mapID or nil
  end
  m = m or cont
  local x, y = hbd:GetZoneCoordinatesFromWorld(wx, wy, m, true)
  if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return m, x * 100, y * 100 end
  if cx then return cont, cx * 100, cy * 100 end
end

-- "spawns" as Questie gives them ({ [area] = { { x, y }, ... } }), with -uiMapID in place of the area (QD.AreaMap knows)
-- (Forever's own quests have no creature numbers: their givers are places, numbered below zero, "@map,x,y")
local function Spawns(s0, s1)
  local out
  if s0 and s0:sub(1, 1) == "@" then
    local m, x, y = s0:match("^@(%d+),([%d%.]+),([%d%.]+)")
    return m and { [-tonumber(m)] = { { tonumber(x), tonumber(y) } } } or nil
  end
  for inst, s in pairs({ [0] = s0 or "", [1] = s1 or "" }) do
    for i = 1, #s - 5, 6 do
      local a, b, c, d, e, f = s:byte(i, i + 5)
      local wx = (VALUE[a] or 0) * 4096 + (VALUE[b] or 0) * 64 + (VALUE[c] or 0) - 17200
      local wy = (VALUE[d] or 0) * 4096 + (VALUE[e] or 0) * 64 + (VALUE[f] or 0) - 17200
      local m, x, y = QD.Place(inst, wx, wy)
      if m then
        out = out or {}
        out[-m] = out[-m] or {}
        table.insert(out[-m], { x, y })
      end
    end
  end
  return out
end

-- an area ID (Questie's) or -uiMapID (ours) -> uiMapID
local zoneDB
function QD.AreaMap(area)
  if type(area) ~= "number" then return nil end
  if area < 0 then return -area end
  if not zoneDB and QuestieLoader then
    local ok, z = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    if ok then zoneDB = z end
  end
  if not (zoneDB and zoneDB.GetUiMapIdByAreaId) then return nil end
  local ok, m = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, area)
  return ok and m or nil
end

---------------------------------------------------------------------------
-- Our own records
---------------------------------------------------------------------------
local SIDE_ANY, SIDE_NONE = 0, 1099511627776 -- (no race has that bit)
local function Races(s)
  if not s or s == "" then return 0 end
  if s == "A" or s == "H" then
    return (UnitFactionGroup("player") or "Horde"):sub(1, 1) == s and SIDE_ANY or SIDE_NONE
  end
  return tonumber(s) or 0
end
local function IdCounts(s) -- "6076:1;60:2" -> { { 6076, 1 }, { 60, 2 } }
  return Pairs(s)
end
local function Objectives(s)
  if not s or s == "" then return nil end
  local out, at = {}, { m = 1, o = 2, i = 3 }
  for part in s:gmatch("[^;]+") do
    local k, id, n, text = part:match("^(%a)(%d+):(%d*):(.*)$")
    local l = k and at[k]
    if l then
      out[l] = out[l] or {}
      table.insert(out[l], { tonumber(id), text ~= "" and text or nil, tonumber(n) })
    end
  end
  return next(out) and out or nil
end
local function Explore(s)
  if not s or s == "" then return nil end
  local out
  for inst, wx, wy in s:gmatch("(%d+),(%-?%d+),(%-?%d+)") do
    local m, x, y = QD.Place(tonumber(inst), tonumber(wx), tonumber(wy))
    if m then
      out = out or { "Explore", {} }
      out[2][-m] = out[2][-m] or {}
      table.insert(out[2][-m], { x, y })
    end
  end
  return out
end

local FIELDS = {
  quests = {
    name = function(f) return f[1] end, questLevel = function(f) return tonumber(f[2]) end, requiredLevel = function(f) return tonumber(f[3]) end,
    requiredMaxLevel = function(f) return tonumber(f[4]) end, requiredRaces = function(f) return Races(f[5]) end,
    requiredClasses = function(f) return tonumber(f[6]) end, startedBy = function(f) return Who(f[7]) end, finishedBy = function(f) return Who(f[8]) end,
    objectives = function(f) return Objectives(f[9]) end, triggerEnd = function(f) return Explore(f[10]) end, sourceItemId = function(f) return tonumber(f[11]) end,
    requiredSourceItems = function(f) return Ids(f[12]) end, preQuestGroup = function(f) return Ids(f[13]) end, preQuestSingle = function(f) return Ids(f[14]) end,
    exclusiveTo = function(f) return Ids(f[15]) end, nextQuestInChain = function(f) return tonumber(f[16]) end,
    requiredSkill = function(f) local p = Pairs(f[17]) return p and p[1] end, reputationReward = function(f) return Pairs(f[18]) end,
    zoneOrSort = function(f) return tonumber(f[19]) end, xp = function(f) return tonumber(f[20]) end, specialFlags = function(f) return f[21] == "r" and 1 or nil end,
    rewardChoice = function(f) return IdCounts(f[22]) end, rewardItems = function(f) return IdCounts(f[23]) end,
    rewardMoney = function(f) return tonumber(f[24]) end, rewardSpell = function(f) return tonumber(f[25]) end,
  },
  npcs = {
    name = function(f) return f[1] end, minLevel = function(f) return tonumber(f[2]) end, maxLevel = function(f) return tonumber(f[3]) end,
    rank = function(f) return tonumber(f[4]) or 0 end, factionID = function(f) return tonumber(f[5]) end,
    friendlyToFaction = function(f) return f[6] ~= "" and f[6] or nil end, npcFlags = function(f) return tonumber(f[7]) or 0 end,
    spawns = function(f) return Spawns(f[8], f[9]) end,
  },
  objects = { name = function(f) return f[1] end, spawns = function(f) return Spawns(f[2], f[3]) end },
  items = {
    name = function(f) return f[1] end, npcDrops = function(f) return Ids(f[2]) end, objectDrops = function(f) return Ids(f[3]) end, vendors = function(f) return Ids(f[4]) end,
    requiredLevel = function(f) return tonumber(f[5]) or 0 end, startQuest = function(f) return tonumber(f[6]) end, questRewards = function(f) return Ids(f[7]) end,
    relatedQuests = function() return nil end, again = function(f) return f[8] == "u" or nil end,
  },
}

local function Own(kind)
  local ids
  local lastId, last -- the record read last, split (its fields are usually asked for one after the other)
  return {
    Get = function(id, field)
      local fn = FIELDS[kind][field]
      if not fn then return nil end
      if id ~= lastId then
        local s = Src()
        local rec = s and s[kind] and s[kind][id]
        if type(rec) ~= "string" then return nil end
        lastId, last = id, Split(rec, "|")
      end
      return fn(last)
    end,
    GetAllIds = function()
      if not ids then
        ids = {}
        local s = Src()
        for id in pairs(s and s[kind] or {}) do ids[#ids + 1] = id end
      end
      return ids
    end,
  }
end

QD.own = {
  Quest = Own("quests"), Npc = Own("npcs"), Object = Own("objects"), Item = Own("items"),
  Enum = {
    classKeys = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 },
    factionRaceMasks = { Alliance = 77, Horde = 178 },
    raceMaskById = { 1, 2, 4, 8, 16, 32, 64, 128 },
  },
}

---------------------------------------------------------------------------
-- What everything else asks
---------------------------------------------------------------------------
-- what Sunstone saw itself comes after Questie (which is checked by many) and before Classic's data for a quest Forever changed
local SEEN_FIRST = { startedBy = true, finishedBy = true } -- who really gives and takes it here
local function Merged(kind, base, rec, questie)
  local function Get(id, field)
    if rec and not questie and SEEN_FIRST[field] then
      local v = rec(id, field)
      if v ~= nil then return v end
    end
    local v = base.Get(id, field)
    if v == nil and rec then v = rec(id, field) end
    return v
  end
  return { Get = Get, GetAllIds = base.GetAllIds }
end

local libs = {}
function NS.Quests()
  local L = QD.Questie()
  local key = L or "own"
  local lib = libs[key]
  if lib then return lib end
  local base = L or (Src() and QD.own)
  if not base then return nil end
  local Rec = NS.QuestRec
  lib = {
    Quest = Merged("Quest", base.Quest, Rec and Rec.Quest, L ~= nil), Npc = Merged("Npc", base.Npc, Rec and Rec.Npc),
    Object = Merged("Object", base.Object), Item = Merged("Item", base.Item, Rec and Rec.Item), Enum = base.Enum, questie = L ~= nil,
  }
  libs[key] = lib
  return lib
end
-- Questie tells us when its database is ready; without it ours is ready at once
function NS.QuestsReady(fn)
  if Questie and Questie.API and Questie.API.RegisterOnReady then Questie.API.RegisterOnReady(fn) else C_Timer.After(6, fn) end
end

-- Chains picked out by hand (OneForAll's, with permission): where this side starts a quest, where one ends, what the last one gives
local function Spot(e)
  if type(e) == "table" and type(e[2]) == "number" then return { name = e[1], m = e[2], x = e[3] / 100, y = e[4] / 100 } end
end
function QD.StartsAt(id)
  local s = Src() and Src().starts
  local e = s and s[id]
  return e and Spot(e[(UnitFactionGroup("player") or "Horde"):sub(1, 1)])
end
function QD.EndsAt(id)
  local s = Src() and Src().ends
  return s and Spot(s[id])
end
function QD.Gives(id)
  local s = Src() and Src().gives
  return s and s[id]
end

-- Quest XP: Questie's Forever table, else Classic's -> { level, xp } per quest, or nil
local qxp, qxpOf
function QD.XPTable()
  local key = QD.Questie() or "own"
  if qxpOf ~= key then
    qxp, qxpOf = false, key
    if QuestieLoader then
      local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestXP")
      if ok and type(mod) == "table" and type(mod.db) == "table" then qxp = mod.db end
    end
    if not qxp and key == "own" and Src() then
      qxp = setmetatable({}, { __index = function(t, id)
        local q = QD.own.Quest
        local xp = q.Get(id, "xp")
        local v = xp and { q.Get(id, "questLevel"), xp } or false
        rawset(t, id, v)
        return v
      end })
    end
  end
  return qxp or nil
end
