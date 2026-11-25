-- Sunstone: finds. The second half of the recorder: where creatures are fought, what chests, crates and fishing give, what quests reward, how long a
-- fight takes and what XP it pays at each level, and things nobody had on record (a companion pet's source, an unknown creature's name).
-- Numbers only (and the names of creatures Sunstone doesn't know). Nothing about you, other players or chat. It stays in your saved settings;
-- sharing it is Share.lua's, and off until you switch it on.

local _, NS = ...
local Fi = NS.Module("Finds")
NS.Finds = Fi
local E = NS.Engine

local MOST = { at = 3000, obj = 800, box = 300, fish = 120, qi = 3000, nm = 400, cells = 10, items = 60, news = 200 }
local floor = math.floor
local function List(t) return type(t) == "table" and t or {} end
local function Off() return NS.db and NS.db.recOff end
local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

function Fi.DB()
  local r = NS.Recorder.DB()
  local f = r.fx
  if type(f) ~= "table" or f.v ~= 1 then
    f = { v = 1 }
    r.fx = f
  end
  for _, k in ipairs({ "at", "obj", "box", "fish", "qi", "nm", "xp", "kt", "news" }) do if type(f[k]) ~= "table" then f[k] = {} end end
  return f
end

local counts = {}
local function Slot(kind, id, make) -- f[kind][id], made when there's room
  local t = Fi.DB()[kind]
  if t[id] == nil then
    counts[kind] = counts[kind] or Count(t)
    if counts[kind] >= MOST[kind] then return nil end
    counts[kind] = counts[kind] + 1
    t[id] = make
  end
  return t[id]
end
local function AddItem(t, id, n)
  if t[id] then t[id] = t[id] + n elseif Count(t) < MOST.items then t[id] = n end
end

-- where you stand, as one number: the map, then x and y in hundredths of it; nil inside dungeons
local function Cell()
  if IsInInstance and IsInInstance() then return nil end
  local hbd = NS.HBD()
  if not hbd then return nil end
  local x, y, m = hbd:GetPlayerZonePosition()
  if type(x) ~= "number" or type(y) ~= "number" or type(m) ~= "number" or x < 0 or y < 0 or x >= 1 or y >= 1 then return nil end
  return m * 10000 + floor(x * 100) * 100 + floor(y * 100), m
end
function Fi.Spot(cell) -- -> map, x, y (0 to 1)
  local m = floor(cell / 10000)
  local r = cell - m * 10000
  return m, (floor(r / 100) + 0.5) / 100, (r % 100 + 0.5) / 100
end
local function AddCell(t)
  local c = Cell()
  if not c then return end
  if t[c] then t[c] = t[c] + 1 elseif Count(t) < MOST.cells then t[c] = 1 end
end

---------------------------------------------------------------------------
-- Fights: where, how long, what XP
---------------------------------------------------------------------------
local fight, fightN = {}, 0 -- [guid] = when it began
function Fi.OnTarget() -- the target's health moved
  if Off() or not (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return end
  local guid = NS.GUID("target")
  if not NS.Recorder.NpcID(guid) or fight[guid] then return end
  if fightN > 100 then fight, fightN = {}, 0 end
  fight[guid] = GetTime()
  fightN = fightN + 1
end

local function Diff(k)
  local d = type(k.level) == "number" and k.level > 0 and type(k.pl) == "number" and k.level - k.pl
  return d and d >= -20 and d <= 8 and d or nil
end
local function Pair(t, a, b, n, v) -- t[a][b] = { n, sum }
  t[a] = type(t[a]) == "table" and t[a] or {}
  local e = t[a][b]
  if type(e) ~= "table" then e = { 0, 0 }; t[a][b] = e end
  e[1], e[2] = e[1] + n, e[2] + v
end

function Fi.OnKill(k, guid)
  if Off() then return end
  local f = Fi.DB()
  local at = Slot("at", k.npc, {})
  if at then AddCell(at) end
  local began = guid and fight[guid]
  if guid then fight[guid] = nil end
  local d = Diff(k)
  local _, class = UnitClass("player")
  if began and d and not k.grouped and not k.elite and type(class) == "string" then
    local secs = GetTime() - began
    if secs >= 1 and secs <= 180 then
      f.kt[class] = type(f.kt[class]) == "table" and f.kt[class] or {}
      Pair(f.kt[class], k.pl, d, 1, floor(secs * 10 + 0.5) / 10)
    end
  end
  -- a creature Sunstone doesn't know: its name (a creature's, checked by its GUID; never a player's)
  if not f.nm[k.npc] and E.NpcName(k.npc):find("^NPC %d+$") then
    local unit = "target"
    local name = NS.Recorder.NpcID(NS.GUID(unit)) == k.npc and UnitName(unit)
    if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and #name <= 40 and name:find("^[%a][%a '%-,]+$") then Slot("nm", k.npc, name) end
  end
end
function Fi.OnXP(k, gained) -- an unrested kill on your own
  local d = Diff(k)
  if Off() or not d then return end
  Pair(Fi.DB().xp, k.pl, k.elite and d + 100 or d, 1, gained)
end

---------------------------------------------------------------------------
-- Finds nobody had on record: companion pets and mounts, and where they came from
---------------------------------------------------------------------------
Fi.KIND = { "drops from", "is in", "comes out of", "is fished up in", "is sold by", "is a reward of" } -- creature, object, item, map, vendor, quest
local function Special(item) -- a companion pet or a mount
  local _, _, _, _, _, class, sub = NS.GetItemInfoInstant(item)
  return class == 15 and (sub == 2 or sub == 5)
end
Fi.Special = Special
local function Known(item, kind, src)
  local S = List(_G.SunstoneCollect)
  for _, list in ipairs({ List(S.pets), List(S.mounts) }) do
    for _, e in ipairs(list) do
      if e.id == item then
        if kind == 1 then
          for _, id in ipairs(List(e.d)) do if id == src then return true end end
        elseif kind == 5 then
          for _, id in ipairs(List(e.v)) do if id == src then return true end end
        elseif kind == 6 then
          for _, id in ipairs(List(e.q)) do if id == src then return true end end
        end
      end
    end
  end
  if kind == 1 then
    local r = List(S.rate)[item]
    if r then for k = 4, #r, 2 do if r[k] == src then return true end end end
  elseif kind == 2 then
    local r = List(S.chest)[item]
    if r then for k = 1, #r, 3 do if r[k] == src then return true end end end
  elseif kind == 3 then
    local r = List(S.inside)[item]
    if r then for k = 1, #r, 2 do if r[k] == src then return true end end end
  end
  return NS.Community ~= nil and NS.Community.HasSource(item, kind, src)
end
function Fi.SourceName(kind, src)
  if kind == 1 or kind == 5 then return E.NpcName(src) end
  if kind == 3 then return E.ItemName(src) end
  if kind == 4 then local i = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(src) return type(i) == "table" and i.name or "a zone" end
  if kind == 6 then return "a quest" .. (E.QuestName and E.QuestName(src) and (": " .. E.QuestName(src)) or "") end
  return "a chest or something like it"
end
function Fi.News(item, kind, src)
  if not (item and kind and src) or not Special(item) or Known(item, kind, src) then return false end
  local news = Fi.DB().news
  for _, e in ipairs(news) do if e.i == item and e.k == kind and e.s == src then e.n = (e.n or 1) + 1 return false end end
  if #news >= MOST.news then return false end
  news[#news + 1] = { i = item, k = kind, s = src, n = 1 }
  local link = select(2, NS.GetItemInfo(item)) or E.ItemName(item)
  NS.Print("a new find: " .. tostring(link) .. " " .. Fi.KIND[kind] .. " " .. Fi.SourceName(kind, src) .. ". Nobody had that on record." ..
           (NS.Share and not NS.Share.On() and " (/sun share to help others find it)" or ""))
  return true
end

---------------------------------------------------------------------------
-- Loot that isn't a corpse's: chests, crates, fishing. And pets and mounts out of anything
---------------------------------------------------------------------------
local looted, lootedN = {}, 0
local function ItemOf(guid) -- the opened item's ID
  if C_Item and C_Item.GetItemIDByGUID then
    local ok, id = pcall(C_Item.GetItemIDByGUID, guid)
    if ok and type(id) == "number" then return id end
  end
  if C_Item and C_Item.GetItemLocation and C_Item.GetItemID then
    local ok, loc = pcall(C_Item.GetItemLocation, guid)
    if ok and loc then
      local ok2, id = pcall(C_Item.GetItemID, loc)
      if ok2 and type(id) == "number" then return id end
    end
  end
end
function Fi.OnLoot()
  if Off() then return end
  local n = GetNumLootItems and GetNumLootItems() or 0
  local fishing = IsFishingLoot and IsFishingLoot()
  local fresh = {}
  for slot = 1, n do
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    local src = { GetLootSourceInfo(slot) }
    for k = 1, #src, 2 do
      local guid, qty = src[k], tonumber(src[k + 1]) or 1
      if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
        local what, _, _, _, _, oid = strsplit("-", guid)
        local kind, key, where
        if fishing then
          local _, m = Cell()
          if m then kind, key, where = 4, m, "fish" end
        elseif what == "GameObject" then
          kind, key, where = 2, tonumber(oid), "obj"
        elseif what == "Item" then
          kind, key, where = 3, ItemOf(guid), "box"
        elseif what == "Creature" or what == "Vehicle" then
          kind, key = 1, tonumber(oid)
        end
        if key then
          if where and (not looted[guid] or fresh[guid]) then
            local e = Slot(where, key, { n = 0, i = {} })
            if e then
              if not fresh[guid] then
                fresh[guid] = true
                looted[guid] = true
                lootedN = lootedN + 1
                e.n = e.n + 1
                if where == "obj" then e.at = e.at or {}; AddCell(e.at) end
              end
              if id then AddItem(e.i, id, qty) end
            end
          end
          if id and (not looted[guid .. id]) and Special(id) then
            looted[guid .. id] = true
            Fi.News(id, kind, key)
          end
        end
      end
    end
  end
  if lootedN > 400 then looted, lootedN = {}, 0 end
end

-- what a quest gives, when it's handed in
function Fi.OnQuest()
  if Off() or not GetQuestID then return end
  local qid = GetQuestID()
  if type(qid) ~= "number" or qid <= 0 or not GetQuestItemLink then return end
  local items = {}
  for _, k in ipairs({ { "choice", GetNumQuestChoices }, { "reward", GetNumQuestRewards } }) do
    for i = 1, math.min(10, k[2] and k[2]() or 0) do
      local ok, link = pcall(GetQuestItemLink, k[1], i)
      local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
      if id then
        items[#items + 1] = id
        if Special(id) then Fi.News(id, 6, qid) end
      end
    end
  end
  if #items > 0 and Slot("qi", qid, items) then Fi.DB().qi[qid] = items end
end

function Fi.OnVendor()
  if Off() then return end
  local npc = NS.Recorder.NpcID(NS.GUID("npc"))
  local v = npc and NS.Recorder.DB().vend[npc]
  for item in pairs(List(v and v.i)) do if type(item) == "number" and Special(item) then Fi.News(item, 5, npc) end end
end

function Fi.Stats()
  local f = Fi.DB()
  return { places = Count(f.at), chests = Count(f.obj), crates = Count(f.box), fishing = Count(f.fish), rewards = Count(f.qi), names = Count(f.nm), news = #f.news }
end

function Fi:Init()
  Fi.DB()
  NS.On("UNIT_HEALTH", function(unit) if unit == "target" then Fi.OnTarget() end end)
  NS.On("LOOT_OPENED", function() NS.Safe("finds", Fi.OnLoot) end)
  NS.On("QUEST_COMPLETE", function() NS.Safe("finds", Fi.OnQuest) end)
  NS.On("MERCHANT_SHOW", function() C_Timer.After(1.2, function() NS.Safe("finds", Fi.OnVendor) end) end)
end
