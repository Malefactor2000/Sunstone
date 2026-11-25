-- Sunstone: recorder.
-- Writes down what quests and creatures really give you, as plain numbers, so the helper can rank XP
-- and gold by real results instead of guesses:
--   * quests: the XP and money of every quest you turn in (and the level you were);
--   * creatures: kills, the XP of each kill, coins and items in their loot (plus each item's vendor
--     price), what skinning them gave, and the reputation a kill gave;
--   * vendors: what each item costs when you open a vendor (gold, Honor, Merchant's Favor, Marks of Honor...).
--     It only READS the vendor window: it never buys, sells or clicks anything;
--   * battlegrounds: minutes per match and the Honor, Rank Points and Marks of Honor it paid.
--   * how you play: solo, in a group, in a dungeon or a raid. Group numbers are kept APART from solo ones
--     (loot and coins are shared, XP is split, kills come faster) and timed, so the helper can compare
--     XP, gold, cloth and crates per hour between the two; each dungeon run is timed from entering to leaving.
-- Kills: your target dying while it's yours (not tagged by someone else); in a group also the creatures your
-- group kills that you weren't targeting (their nameplates). The Forever client doesn't let
-- addons read the combat log, and Sunstone doesn't try. Loot comes from the loot window. Nothing here
-- reads chat or other players' names (a group is only "how many of you"). The numbers stay in your SavedVariables; sharing them is
-- Share.lua's, and off until you switch it on.
-- "/sun record" shows what's been recorded; "/sun record off" stops it.

local _, NS = ...
local Rec = NS.Module("Recorder")
NS.Recorder = Rec

local MAX_MOBS, MAX_ITEMS, MAX_QUESTS = 4000, 40, 6000
local GATHER = { ["skinning"] = true, ["herb gathering"] = true, ["herbalism"] = true, ["mining"] = true, ["fishing"] = true }

function Rec.DB()
  local r = NS.db.rec
  if type(r) ~= "table" or r.v ~= 1 then
    r = { v = 1, quests = {}, mobs = {}, sell = {}, cal = { f = 0, x = 0, n = 0 }, since = time() }
    NS.db.rec = r
  end
  if type(r.vend) ~= "table" then r.vend = {} end -- vendor prices (added in 1.3)
  if type(r.pvp) ~= "table" then r.pvp = {} end   -- battleground matches (added in 1.3)
  if type(r.ctx) ~= "table" then r.ctx = {} end   -- solo / group / dungeon / raid, per level (added in 1.6)
  if type(r.runs) ~= "table" then r.runs = {} end -- timed dungeon and raid runs (added in 1.6)
  r.gsince = r.gsince or time()                   -- group numbers kept apart from this moment on
  return r
end

local function Off() return NS.db and NS.db.recOff end

local function NpcID(guid)
  if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
Rec.NpcID = NpcID

local function Count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local mobCount
local function Mob(npc)
  local mobs = Rec.DB().mobs
  local m = mobs[npc]
  if not m then
    mobCount = mobCount or Count(mobs)
    if mobCount >= MAX_MOBS then return nil end
    m = { k = 0, l = 0, c = 0, v = 0, i = {} }
    mobs[npc] = m
    mobCount = mobCount + 1
  end
  return m
end

local function AddItem(list, id, n, max)
  if list[id] then list[id] = list[id] + n return end
  if Count(list) < (max or MAX_ITEMS) then list[id] = n end
end

---------------------------------------------------------------------------
-- How you're playing, kept apart:
--   m.g = a creature's numbers from kills made in a group (same fields as the solo ones on m)
--   ctx[kind][level] = { t = seconds playing, k = kills, l = corpses looted, c = coins, x = XP (not quests),
--                        xr = XP while rested, v = typical loot value, rv = random green+ value,
--                        gv = gathered value, i = { [item] = count } }   kind: solo / group / dungeon / raid
--   runs[] = { d = dungeon, id = instance, lvl, n = group size, t = seconds inside, k, l, c, x, v, rv, i, at }
-- The clock only runs while you're doing something: more than GAP seconds without a kill, loot or XP
-- (a break, a long walk, AFK) isn't counted.
---------------------------------------------------------------------------
local GAP, MAX_CTX_ITEMS, MAX_RUNS = 300, 80, 150
local RUN_BACK = 900 -- seconds: back in the same dungeon within this (a repair trip) is still the same run

local function Grouped() return IsInGroup and IsInGroup() or false end

function Rec.Kind()
  if IsInInstance then
    local ok, inside, itype = pcall(IsInInstance)
    if ok and inside then
      if itype == "party" then return "dungeon" end
      if itype == "raid" then return "raid" end
      if itype == "pvp" or itype == "arena" then return nil end -- battlegrounds are timed on their own
    end
  end
  return Grouped() and "group" or "solo"
end

-- A creature's numbers for this kill: the solo ones, or its group ones.
local function Side(m, grouped)
  if not grouped then return m end
  if type(m.g) ~= "table" then m.g = { k = 0, l = 0, c = 0, v = 0, i = {} } end
  return m.g
end

local function Bucket(kind)
  if not kind then return nil end
  local ctx = Rec.DB().ctx
  local byLevel = ctx[kind]
  if type(byLevel) ~= "table" then byLevel = {}; ctx[kind] = byLevel end
  local lvl = UnitLevel("player") or 0
  local b = byLevel[lvl]
  if type(b) ~= "table" then
    b = { t = 0, k = 0, l = 0, c = 0, x = 0, xr = 0, v = 0, rv = 0, gv = 0, i = {} }
    byLevel[lvl] = b
  end
  return b
end

local function Run()
  local r = NS.cdb and NS.cdb.run
  return type(r) == "table" and r.inAt and r or nil
end

-- Something happened (a kill, loot, XP): run the clock for this kind of play.
local clock = {}
local function Tick(kind)
  if not kind then return end
  local now = GetTime()
  if clock.kind == kind and clock.at and now - clock.at <= GAP then
    local b = Bucket(kind)
    if b then b.t = b.t + (now - clock.at) end
  end
  clock.kind, clock.at = kind, now
  local r = Run()
  if r then
    r.seen = time()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n > (r.n or 1) then r.n = n end
  end
end

-- Add to this kind of play (and to the dungeon run, when inside one).
local function Add(kind, field, n)
  local b = Bucket(kind)
  if not b then return end
  b[field] = (b[field] or 0) + n
  local r = Run()
  if r and (kind == "dungeon" or kind == "raid") then r[field] = (r[field] or 0) + n end
end
local function AddLoot(kind, id, n)
  local b = Bucket(kind)
  if not b then return end
  AddItem(b.i, id, n, MAX_CTX_ITEMS)
  local r = Run()
  if r and (kind == "dungeon" or kind == "raid") then
    r.i = r.i or {}
    AddItem(r.i, id, n, MAX_CTX_ITEMS)
  end
end
Rec.Bucket, Rec.Tick, Rec.Add = Bucket, Tick, Add

---------------------------------------------------------------------------
-- Classic's kill-XP formula (used to see how far Forever's XP differs from it)
---------------------------------------------------------------------------
local function ZeroDiff(l)
  if l <= 7 then return 5 elseif l <= 9 then return 6 elseif l <= 11 then return 7 elseif l <= 15 then return 8
  elseif l <= 19 then return 9 elseif l <= 29 then return 11 elseif l <= 39 then return 12 elseif l <= 44 then return 13
  elseif l <= 49 then return 14 elseif l <= 54 then return 15 elseif l <= 59 then return 16 end
  return 17
end
local function GrayLevel(l)
  if l <= 5 then return 0 elseif l <= 39 then return l - math.floor(l / 10) - 5 end
  return l - math.floor(l / 5) - 1
end
function Rec.FormulaXP(pl, ml, elite)
  if type(pl) ~= "number" or type(ml) ~= "number" or ml <= 0 or pl >= 60 then return nil end
  local base, xp = pl * 5 + 45, 0
  if ml >= pl then xp = base * (1 + 0.05 * (ml - pl))
  elseif ml > GrayLevel(pl) then xp = base * (1 - (pl - ml) / ZeroDiff(pl)) end
  if elite then xp = xp * 2 end
  return xp
end

---------------------------------------------------------------------------
-- Creature levels (seen on your target, mouseover and nameplates)
---------------------------------------------------------------------------
local seen, seenN = {}, 0
-- Creature type as a number (Blizzard's own type IDs), so random-drop rates can be pooled by kind:
-- humanoids drop random greens far more often than beasts.
local TYPES = { Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5, Undead = 6, Humanoid = 7,
                Critter = 8, Mechanical = 9, ["Not specified"] = 10, Totem = 11, ["Non-combat Pet"] = 12, ["Gas Cloud"] = 13 }
local function Look(unit)
  local guid = NS.GUID(unit)
  if not NpcID(guid) or seen[guid] then return end
  if seenN > 400 then wipe(seen); seenN = 0 end
  local class = UnitClassification and UnitClassification(unit) or ""
  local kind = UnitCreatureType and UnitCreatureType(unit)
  seen[guid] = { level = UnitLevel(unit), elite = class == "elite" or class == "rareelite" or class == "worldboss",
                 ty = type(kind) == "string" and TYPES[kind] or nil }
  seenN = seenN + 1
end

---------------------------------------------------------------------------
-- Kills and the XP they gave
---------------------------------------------------------------------------
local died = {}         -- creature GUIDs already counted as killed
local kills = {}        -- the last few kills
local xpWaiting         -- XP that arrived just before we saw the kill
local lastXP, lastMax, lastLevel
local turnInAt, gatherAt = -10, -10

-- Reputation from kills: a faction's bar moving right after a kill of yours (quest turn-ins are left out:
-- Questie already knows what quests give). Per creature: m.f[factionID] = { g = reputation, n = kills }.
-- Only the factions the helper asked about (GearList.lua) are watched.
local repLast, repWaiting = {}, nil

local function RepNow()
  local out = {}
  for _, fid in ipairs(NS.Factions()) do
    local _, _, _, abs = NS.Standing(fid)
    if type(abs) == "number" then out[fid] = abs end
  end
  return out
end

local function CreditRep(k, gains)
  local m = Mob(k.npc)
  if not m then return end
  m.f = m.f or {}
  for fid, g in pairs(gains) do
    local e = m.f[fid]
    if not e and Count(m.f) < 8 then
      e = { g = 0, n = 0 }
      m.f[fid] = e
    end
    if e then e.g, e.n = e.g + g, e.n + 1 end
  end
end

local function OnFaction()
  local now = GetTime()
  local gains, any = {}, false
  for fid, v in pairs(RepNow()) do
    local old = repLast[fid]
    if old and v > old and v - old <= 2000 then gains[fid] = v - old; any = true end
    repLast[fid] = v
  end
  if Off() or not any or now - turnInAt < 1.5 then return end
  local found
  for i = #kills, 1, -1 do
    local k = kills[i]
    if now - k.t < 1.5 and not k.rep then
      if found then return end -- two kills at once: can't tell which gave it
      found = k
    end
  end
  if found then
    found.rep = true
    CreditRep(found, gains)
  else
    repWaiting = { t = now, gains = gains }
  end
end

local function Credit(k, gained)
  k.xp = gained
  local m = Mob(k.npc)
  if not m then return end
  local s = Side(m, k.grouped) -- a group's XP is split: kept with the group numbers
  if k.rested then s.xr = (s.xr or 0) + 1 return end -- the rested bonus: not a clean sample
  s.x, s.xk = (s.x or 0) + gained, (s.xk or 0) + 1
  if k.grouped then return end
  if NS.Finds then NS.Finds.OnXP(k, gained) end
  local f = Rec.FormulaXP(k.pl, k.level, k.elite)
  if f and f > 0 then
    local c = Rec.DB().cal
    c.f, c.x, c.n = c.f + f, c.x + gained, c.n + 1
  end
end

function Rec.Kill(guid)
  local npc = NpcID(guid)
  local m = npc and Mob(npc)
  if not m then return end
  local grouped, kind = Grouped(), Rec.Kind()
  local side = Side(m, grouped)
  side.k = side.k + 1
  Add(kind, "k", 1)
  Tick(kind)
  local s = seen[guid]
  if s and type(s.level) == "number" and s.level > 0 then
    m.lo = math.min(m.lo or s.level, s.level)
    m.hi = math.max(m.hi or s.level, s.level)
  end
  if s and s.ty then m.ty = s.ty end
  local k = { t = GetTime(), npc = npc, level = s and s.level, elite = s and s.elite, pl = UnitLevel("player"),
              rested = (GetXPExhaustion and GetXPExhaustion() or 0) > 0, grouped = grouped }
  kills[#kills + 1] = k
  if #kills > 8 then table.remove(kills, 1) end
  if xpWaiting and GetTime() - xpWaiting.t < 1.5 then
    local amount = xpWaiting.amount
    xpWaiting = nil
    Credit(k, amount)
  end
  if repWaiting and GetTime() - repWaiting.t < 1.5 then
    local gains = repWaiting.gains
    repWaiting = nil
    k.rep = true
    CreditRep(k, gains)
  end
  if NS.Finds then NS.Safe("finds", NS.Finds.OnKill, k, guid) end
end

local wasRested = false
local function OnXP()
  local xp, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  local gained
  if lastXP then gained = (lvl > lastLevel) and ((lastMax - lastXP) + xp) or (xp - lastXP) end
  lastXP, lastMax, lastLevel = xp, max, lvl
  local rested = wasRested
  wasRested = (GetXPExhaustion and GetXPExhaustion() or 0) > 0
  if Off() or not gained or gained <= 0 then return end
  local now = GetTime()
  if now - turnInAt < 1.5 then return end -- a quest's XP
  -- every other bit of XP counts toward how you're playing (in a group, kills you didn't see too)
  local kind = Rec.Kind()
  Add(kind, "x", gained)
  if rested then Add(kind, "xr", gained) end
  Tick(kind)
  local found
  for i = #kills, 1, -1 do
    local k = kills[i]
    if now - k.t < 1.5 and not k.xp then
      if found then return end -- two kills at once: can't tell which gave what
      found = k
    end
  end
  if found then Credit(found, gained) else xpWaiting = { t = now, amount = gained } end
end

-- Your target just died: a kill, unless someone else had tagged it (then it isn't yours).
-- In a group, a creature dying on a nameplate counts too (your group kills many you never target).
local diedN = 0
local function CheckUnit(unit)
  if Off() or not UnitExists(unit) or not UnitIsDead(unit) then return end
  if UnitIsPlayer and UnitIsPlayer(unit) then return end
  local guid = NS.GUID(unit)
  if not NpcID(guid) or died[guid] then return end
  if UnitIsTapDenied and UnitIsTapDenied(unit) then return end
  if unit ~= "target" then
    if not Grouped() then return end
    local reaction = UnitReaction and UnitReaction(unit, "player")
    if type(reaction) == "number" and reaction > 4 then return end -- a friendly creature
  end
  Look(unit)
  died[guid] = true
  diedN = diedN + 1
  if diedN > 500 then wipe(died); diedN = 0 end
  Rec.Kill(guid)
end
local function CheckTarget() CheckUnit("target") end

---------------------------------------------------------------------------
-- Loot: what each creature dropped (first look at each corpse only)
---------------------------------------------------------------------------
local looted, lootedN = {}, 0
local open

local function SellPrice(id)
  local sell = Rec.DB().sell
  if sell[id] then return end
  local price = select(11, NS.GetItemInfo(id))
  if type(price) == "number" then sell[id] = price end
end

local lootUntil = 0 -- money arriving until then is the loot window's (counted at loot close)
local function OnLootOpened()
  if Off() then return end
  local gather = GetTime() - gatherAt < 4
  local grouped, kind = Grouped(), Rec.Kind()
  open = { money = GetMoney(), fresh = {}, gather = gather, grouped = grouped, kind = kind }
  local n = GetNumLootItems and GetNumLootItems() or 0
  for slot = 1, n do
    local src = { GetLootSourceInfo(slot) }
    local slotType = GetLootSlotType and GetLootSlotType(slot)
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    for k = 1, #src, 2 do
      local guid, qty = src[k], tonumber(src[k + 1]) or 1
      local npc = NpcID(guid)
      local key = guid and (guid .. (gather and ":g" or ""))
      if npc and key and (not looted[key] or open.fresh[key]) then
        local m = Mob(npc)
        if m then
          local side = gather and m or Side(m, grouped) -- skinning and herbs aren't shared: always solo numbers
          if not open.fresh[key] then
            open.fresh[key] = npc
            looted[key] = true
            lootedN = lootedN + 1
            if gather then m.sn = (m.sn or 0) + 1 else side.l = side.l + 1; Add(kind, "l", 1) end
            Tick(kind)
            if not gather and not died[guid] then -- a kill we didn't see happen (not your target): count it now
              died[guid] = true
              side.k = side.k + 1
              Add(kind, "k", 1)
            end
          end
          if slotType == 1 and id then
            -- Random green / blue (and better) drops are luck, not what the creature usually gives: they go
            -- in their own list (r, rv) so they never inflate farming estimates.
            local quality = select(3, NS.GetItemInfo(link))
            local db = Rec.DB()
            if type(quality) == "number" then
              db.qual = db.qual or {}
              db.qual[id] = quality
            end
            local rare = type(quality) == "number" and quality >= 2
            if gather then
              m.sk = m.sk or {}
              AddItem(m.sk, id, qty)
            elseif rare then
              side.r = side.r or {}
              AddItem(side.r, id, qty)
            else
              AddItem(side.i, id, qty)
            end
            AddLoot(kind, id, qty)
            SellPrice(id)
            local price = db.sell[id]
            if price then
              if gather then Add(kind, "gv", price * qty)
              elseif rare then side.rv = (side.rv or 0) + price * qty; Add(kind, "rv", price * qty)
              else side.v = side.v + price * qty; Add(kind, "v", price * qty) end
            end
          end
        end
      end
    end
  end
  if lootedN > 500 then wipe(looted); lootedN = 0 end
end

local function OnLootClosed()
  local o = open
  open = nil
  lootUntil = GetTime() + 1
  if not o or o.gather then return end
  C_Timer.After(0.4, function()
    local gained = GetMoney() - o.money
    if gained <= 0 then return end
    local list = {}
    for _, npc in pairs(o.fresh) do list[#list + 1] = npc end
    if #list == 0 then return end
    Add(o.kind, "c", gained) -- in a group this is already your share
    for _, npc in ipairs(list) do
      local m = Mob(npc)
      if m then
        local side = Side(m, o.grouped)
        side.c = side.c + gained / #list
      end
    end
  end)
end

-- In a group, your share of the coins someone else loots arrives without a loot window of yours.
-- Money that a vendor, mailbox, trade, the auction house, a trainer, a flight or a quest explains is left out.
local busy = {}       -- open windows that move money: [name] = when it opened
local lastMoney
local function Busy()
  local now = GetTime()
  for k, t in pairs(busy) do
    if now - t > 600 then busy[k] = nil else return true end -- a close we never heard of: forget it after 10 min
  end
  return false
end
local function OnMoney()
  local now = GetMoney()
  local old = lastMoney
  lastMoney = now
  if Off() or not old or now <= old or not Grouped() then return end
  if open or GetTime() < lootUntil or GetTime() - turnInAt < 3 or Busy() then return end
  local kind = Rec.Kind()
  Add(kind, "c", now - old)
  Tick(kind)
end
Rec.OnMoney = OnMoney

---------------------------------------------------------------------------
-- Quests: XP and money at turn-in
---------------------------------------------------------------------------
local questCount
local function OnTurnedIn(qid, xp, money)
  turnInAt = GetTime()
  if Off() or type(qid) ~= "number" then return end
  local q = Rec.DB().quests
  if not q[qid] then
    questCount = questCount or Count(q)
    if questCount >= MAX_QUESTS then return end
    questCount = questCount + 1
  end
  q[qid] = { x = tonumber(xp) or 0, m = tonumber(money) or 0, l = UnitLevel("player") }
end

---------------------------------------------------------------------------
-- Vendor prices: what each item costs at a vendor you open (gold, or a currency such as Honor, Merchant's
-- Favor or Marks of Honor), so the helper can say what a reward really costs. This only READS what the
-- vendor window shows: nothing here buys, sells or clicks. Numbers only, per vendor:
--   vend[npcID] = { t = when, r = your standing with them,
--                   i = { [itemID] = { c = copper, n = items per purchase, x = { { kind, id, amount }, ... } } } }
-- kind 1 = a currency (its ID), kind 2 = an item (its ID), e.g. { 1, 1792, 4250 } = 4250 Honor.
---------------------------------------------------------------------------
local MAX_VENDORS, MAX_VITEMS = 300, 150

local function MerchantCount()
  for _, fn in ipairs({ GetMerchantNumItems or false, C_MerchantFrame and C_MerchantFrame.GetNumItems or false }) do
    if fn then
      local ok, n = pcall(fn)
      if ok and type(n) == "number" then return n end
    end
  end
  return 0
end

-- (item ID, copper, items per purchase) of the vendor's i-th item; the modern client has C_MerchantFrame.GetItemInfo
local function MerchantItem(i)
  local id
  if GetMerchantItemID then
    local ok, v = pcall(GetMerchantItemID, i)
    if ok then id = tonumber(v) end
  end
  if not id and GetMerchantItemLink then
    local ok, link = pcall(GetMerchantItemLink, i)
    if ok and type(link) == "string" then id = tonumber(link:match("item:(%d+)")) end
  end
  local CM = C_MerchantFrame
  if CM and CM.GetItemInfo then
    local ok, t = pcall(CM.GetItemInfo, i)
    if ok and type(t) == "table" then return id, t.price, t.stackCount end
  end
  if GetMerchantItemInfo then
    local ok, _, _, price, per = pcall(GetMerchantItemInfo, i)
    if ok then return id, price, per end
  end
  return id
end

-- What else the i-th item costs (Honor, Favor, marks...): at most 3 parts, as { kind, id, amount }
local function MerchantCosts(i)
  local out = {}
  if not (GetMerchantItemCostInfo and GetMerchantItemCostItem) then return out end
  local ok, n = pcall(GetMerchantItemCostInfo, i)
  for j = 1, math.min((ok and tonumber(n)) or 0, 3) do
    local ok2, _, value, link = pcall(GetMerchantItemCostItem, i, j)
    if ok2 and type(value) == "number" and value > 0 and type(link) == "string" then
      local cid, iid = tonumber(link:match("currency:(%d+)")), tonumber(link:match("item:(%d+)"))
      if cid then out[#out + 1] = { 1, cid, value } elseif iid then out[#out + 1] = { 2, iid, value } end
    end
  end
  return out
end

function Rec.ReadMerchant()
  if Off() then return end
  local npc = NpcID(NS.GUID("npc"))
  if not npc then return end
  local vend = Rec.DB().vend
  local v = vend[npc]
  if not v then
    if Count(vend) >= MAX_VENDORS then return end
    v = { i = {} }
  end
  local items, n = v.i, Count(v.i)
  local seen = 0
  for i = 1, math.min(MerchantCount(), 300) do
    local id, price, per = MerchantItem(i)
    if type(id) == "number" and id > 0 and (items[id] or n < MAX_VITEMS) then
      local e = { c = type(price) == "number" and price >= 0 and math.floor(price) or 0,
                  n = type(per) == "number" and per >= 1 and math.floor(per) or 1 }
      local x = MerchantCosts(i)
      if #x > 0 then e.x = x end
      if e.c > 0 or e.x then
        if not items[id] then n = n + 1 end
        items[id] = e
        seen = seen + 1
      end
    end
  end
  if seen == 0 then return 0 end
  local r = UnitReaction and UnitReaction("npc", "player")
  v.t, v.r = time(), type(r) == "number" and r or nil
  vend[npc] = v
  return seen
end

---------------------------------------------------------------------------
-- Battlegrounds: how long each match took and what it paid (Honor, Rank Points, Marks of Honor), so the helper
-- can say how many matches a reward takes. Nobody has published Honor per match; this measures it.
--   pvp[instance map ID] = { n = matches, m = minutes, h = honor, hn = matches with an honor reading,
--                            rp = rank points, rn = matches with a rank-point reading, mk = marks, w = wins, wn = known results }
---------------------------------------------------------------------------
local MARKS = { 20558, 20559, 20560, 274895 } -- Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands
local HONOR, RANK_POINTS = 1792, 3468
local bg

local function Marks()
  local n = 0
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not fn then return nil end
  for _, id in ipairs(MARKS) do
    local ok, c = pcall(fn, id, true)
    if ok and type(c) == "number" then n = n + c end
  end
  return n
end

local function PvPState()
  local h, rp = NS.Currency(HONOR), NS.Currency(RANK_POINTS)
  return { h = h and h.quantity, hmax = h and h.max, rp = rp and rp.quantity, rpw = rp and rp.week,
           rpwmax = rp and rp.weekMax, mk = Marks() }
end

local function InBattleground()
  if not IsInInstance then return false end
  local ok, inside, kind = pcall(IsInInstance)
  return ok and inside and kind == "pvp"
end

local function BgMap()
  if not GetInstanceInfo then return 0 end
  local ok, _, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
  return ok and type(id) == "number" and id or 0
end

function Rec.FinishBattleground()
  local b = bg
  bg = nil
  if not b or Off() then return end
  local now = PvPState()
  local mins = (GetTime() - b.t) / 60
  if mins < 2 or mins > 120 then return end -- left at once, or something odd: not a match
  local p = Rec.DB().pvp
  local e = p[b.map]
  if not e then
    if Count(p) >= 20 then return end
    e = { n = 0, m = 0, h = 0, hn = 0, rp = 0, rn = 0, mk = 0, w = 0, wn = 0 }
    p[b.map] = e
  end
  e.n, e.m = e.n + 1, e.m + mins
  -- a reading at the Honor cap (or the week's Rank Point cap) isn't what a match pays: left out
  if b.h and now.h and not (b.hmax and b.hmax > 0 and now.h >= b.hmax) then
    e.h, e.hn = e.h + math.max(0, now.h - b.h), e.hn + 1
  end
  if b.rp and now.rp and not (now.rpwmax and now.rpwmax > 0 and (now.rpw or 0) >= now.rpwmax) then
    e.rp, e.rn = e.rp + math.max(0, now.rp - b.rp), e.rn + 1
  end
  if b.mk and now.mk then e.mk = e.mk + math.max(0, now.mk - b.mk) end
  if b.won ~= nil then
    e.wn = e.wn + 1
    if b.won then e.w = e.w + 1 end
  end
end

local function CheckWinner()
  if not bg or not GetBattlefieldWinner then return end
  local ok, w = pcall(GetBattlefieldWinner)
  if ok and (w == 0 or w == 1) then
    local side = UnitFactionGroup("player")
    bg.won = (w == 0 and side == "Horde") or (w == 1 and side == "Alliance")
  end
end

---------------------------------------------------------------------------
-- Dungeon and raid runs: from entering to leaving (a repair trip out and back is the same run), what it gave.
-- The run in progress is kept in SunstoneCharDB.run, so a /reload or a disconnect inside doesn't lose it.
---------------------------------------------------------------------------
local function Instance()
  if not GetInstanceInfo then return nil end
  local ok, name, itype, _, _, _, _, _, id = pcall(GetInstanceInfo)
  if ok and (itype == "party" or itype == "raid") and type(name) == "string" then return name, id end
end

function Rec.FinishRun()
  local r = NS.cdb and NS.cdb.run
  NS.cdb.run = nil
  if type(r) ~= "table" then return end
  if r.inAt then r.t = r.t + math.max(0, (r.seen or time()) - r.inAt) end
  if Off() or r.t < 180 or ((r.k or 0) == 0 and (r.l or 0) == 0) then return end -- in and straight out
  local runs = Rec.DB().runs
  runs[#runs + 1] = { d = NS.Clean(r.d, 60), id = r.id, lvl = r.lvl, n = r.n, t = math.floor(r.t), k = r.k or 0,
                      l = r.l or 0, c = r.c or 0, x = r.x or 0, v = r.v or 0, rv = r.rv or 0, i = r.i or {}, at = r.at }
  while #runs > MAX_RUNS do table.remove(runs, 1) end
end

local function Runs(login)
  local name, id = Instance()
  local r = NS.cdb.run
  if type(r) == "table" then
    local now = time()
    if r.inAt and login then
      -- logged back in: count the time up to the last thing that happened, not the time you were away
      r.t = r.t + math.max(0, (r.seen or r.inAt) - r.inAt)
      r.inAt, r.outAt = nil, r.seen or now
    end
    if name and id == r.id and (r.inAt or now - (r.outAt or 0) <= RUN_BACK) then
      if not r.inAt then r.inAt, r.outAt = now, nil end
      r.seen = r.seen or now
      return
    end
    if r.inAt then -- just left
      r.t = r.t + (now - r.inAt)
      r.inAt, r.outAt = nil, now
    end
    if name or now - (r.outAt or 0) > RUN_BACK then
      r.inAt = nil
      Rec.FinishRun()
    end
  end
  if name and not NS.cdb.run and not Off() then
    local now = time()
    NS.cdb.run = { d = name, id = id, lvl = UnitLevel("player"), n = math.max(1, GetNumGroupMembers and GetNumGroupMembers() or 1),
                   t = 0, inAt = now, seen = now, at = now, k = 0, l = 0, c = 0, x = 0, v = 0, rv = 0, i = {} }
  end
end
Rec.Runs = Runs

local function OnWorld(login, reload)
  NS.Safe("runs", Runs, login)
  if InBattleground() then
    -- after a /reload inside a match the start isn't known: that match isn't timed
    if not bg and not login and not reload and not Off() then
      bg = PvPState()
      bg.t, bg.map = GetTime(), BgMap()
    end
  elseif bg then
    C_Timer.After(2, function() NS.Safe("battleground", Rec.FinishBattleground) end)
  end
end

---------------------------------------------------------------------------
function Rec.Stats()
  local r = Rec.DB()
  local kills, loots, mobs = 0, 0, 0
  for _, m in pairs(r.mobs) do
    kills, loots, mobs = kills + m.k, loots + m.l, mobs + 1
    if type(m.g) == "table" then kills, loots = kills + (m.g.k or 0), loots + (m.g.l or 0) end
  end
  return Count(r.quests), mobs, kills, loots, r.cal
end

-- One kind of play pooled over levels lo..hi: { t, k, l, c, x, xr, v, rv, gv }
function Rec.Pool(kind, lo, hi)
  local out = { t = 0, k = 0, l = 0, c = 0, x = 0, xr = 0, v = 0, rv = 0, gv = 0 }
  for lvl, b in pairs(Rec.DB().ctx[kind] or {}) do
    if type(lvl) == "number" and lvl >= lo and lvl <= hi and type(b) == "table" then
      for f in pairs(out) do if type(b[f]) == "number" then out[f] = out[f] + b[f] end end
    end
  end
  return out
end

-- "solo: 2.1 h, 4,100 XP/h, 41s/h ..." for each kind of play near your level, best gold first
local LABEL = { solo = "solo", group = "in a group", dungeon = "in dungeons", raid = "in raids" }
function Rec.Compare(range)
  local lvl = UnitLevel("player") or 1
  range = range or 3
  local lines = {}
  for _, kind in ipairs({ "solo", "group", "dungeon", "raid" }) do
    local p = Rec.Pool(kind, lvl - range, lvl + range)
    if p.t >= 600 then
      local h = p.t / 3600
      -- the rested bonus doubles kill XP: count half of what came while rested as the bonus
      local xph = math.floor((p.x - p.xr / 2) / h)
      local goldh = (p.c + p.v + p.gv) / h
      lines[#lines + 1] = { goldh, string.format("%s: %.1f h at levels %d-%d - %s XP/h, %s/h (coins + loot at vendor price), %.0f kills/h",
        LABEL[kind], h, math.max(1, lvl - range), lvl + range, BreakUpLargeNumbers and BreakUpLargeNumbers(xph) or tostring(xph),
        NS.Money(goldh), p.k / h) }
    end
  end
  table.sort(lines, function(a, b) return a[1] > b[1] end)
  local out = {}
  for i, l in ipairs(lines) do out[i] = l[2] end
  return out
end

function Rec:Init()
  lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  Rec.DB()
  wasRested = (GetXPExhaustion and GetXPExhaustion() or 0) > 0
  lastMoney = GetMoney()
  NS.On("PLAYER_TARGET_CHANGED", function() Look("target"); CheckTarget() end)
  NS.On("UNIT_HEALTH", function(unit)
    if unit == "target" then CheckTarget()
    elseif type(unit) == "string" and unit:find("^nameplate") then CheckUnit(unit) end
  end)
  NS.On("NAME_PLATE_UNIT_REMOVED", function(unit) CheckUnit(unit) end)
  NS.On("PLAYER_MONEY", OnMoney)
  -- windows that move money (so a group's coin share isn't confused with selling, mail or a trade)
  local function Opened(name) return function() busy[name] = GetTime() end end
  local function Closed(name) return function() busy[name] = nil end end
  for _, w in ipairs({ { "MERCHANT_SHOW", "MERCHANT_CLOSED" }, { "MAIL_SHOW", "MAIL_CLOSED" }, { "TRADE_SHOW", "TRADE_CLOSED" },
                       { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }, { "BANKFRAME_OPENED", "BANKFRAME_CLOSED" },
                       { "TRAINER_SHOW", "TRAINER_CLOSED" }, { "TAXIMAP_OPENED", "TAXIMAP_CLOSED" },
                       { "GOSSIP_SHOW", "GOSSIP_CLOSED" }, { "QUEST_DETAIL", "QUEST_FINISHED" } }) do
    NS.On(w[1], Opened(w[1]))
    NS.On(w[2], Closed(w[1]))
  end
  NS.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) busy["i" .. tostring(kind)] = GetTime() end)
  NS.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) busy["i" .. tostring(kind)] = nil end)
  NS.On("PLAYER_LOGOUT", function()
    local r = NS.cdb and NS.cdb.run
    if type(r) == "table" and r.inAt then r.seen = time() end
  end)
  NS.On("UPDATE_MOUSEOVER_UNIT", function() Look("mouseover") end)
  NS.On("NAME_PLATE_UNIT_ADDED", function(unit) Look(unit) end)
  NS.On("PLAYER_XP_UPDATE", OnXP)
  NS.On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, OnXP) end)
  NS.On("LOOT_OPENED", OnLootOpened)
  NS.On("LOOT_CLOSED", OnLootClosed)
  NS.On("QUEST_TURNED_IN", OnTurnedIn)
  repLast = RepNow()
  NS.On("UPDATE_FACTION", OnFaction)
  NS.On("MERCHANT_SHOW", function() NS.Safe("vendor prices", Rec.ReadMerchant) end)
  NS.On("MERCHANT_UPDATE", function() NS.Debounce("vendor prices", 0.5, Rec.ReadMerchant) end)
  NS.On("PLAYER_ENTERING_WORLD", OnWorld)
  NS.On("UPDATE_BATTLEFIELD_STATUS", CheckWinner)
  NS.On("PVP_MATCH_COMPLETE", CheckWinner)
  NS.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not spellID then return end
    local name = NS.SpellName(spellID)
    if type(name) == "string" and GATHER[name:lower()] then gatherAt = GetTime() end
  end)
end

NS.Command("record", "[on|off] - what Sunstone has recorded about quests and creatures (numbers only, stays on your PC)", function(rest)
  rest = (rest or ""):lower()
  if rest == "off" then NS.db.recOff = true; NS.Print("recording stopped. /sun record on starts it again.") return end
  if rest == "on" then NS.db.recOff = nil; NS.Print("recording on.") return end
  local q, mobs, kills, loots, cal = Rec.Stats()
  NS.Print(string.format("recorded %d quests and %d kinds of creatures (%d kills, %d looted)%s.", q, mobs, kills, loots,
    Off() and " - recording is OFF" or ""))
  if cal.n >= 10 then
    NS.Print(string.format("kill XP here is %.0f%% of Classic's formula (%d clean kills).", cal.x / cal.f * 100, cal.n))
  end
  local r = Rec.DB()
  local matches = 0
  for _, e in pairs(r.pvp) do matches = matches + (e.n or 0) end
  NS.Print(string.format("vendor prices from %d vendors; %d battleground match%s timed; %d dungeon run%s timed.", Count(r.vend),
    matches, matches == 1 and "" or "es", #r.runs, #r.runs == 1 and "" or "s"))
  local cmp = Rec.Compare(3)
  if #cmp > 0 then
    NS.Print("how you play, near your level (best gold first):")
    for _, line in ipairs(cmp) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
  else
    NS.Print("solo vs group: not enough played yet near your level (10 minutes of each kind).")
  end
end)
