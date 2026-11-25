-- Sunstone: what to farm for gold.
-- For every creature you could farm: what a corpse is worth (coins, gray trash, cloth, meat, leather: drop rate times
-- what it sells for) and how long one takes to kill at your level (its level against yours, its health and damage, how
-- many stand together, how fast they come back, and the pace you've really kept). Value times kills an hour = gold an hour.
-- Drop rates come from, in order: your own corpses, Classic's loot tables (MobData.lua, from CMaNGOS), Questie's
-- (Wowhead) rates. Prices: vendors, and what things have usually gone for in your Auction House scans. Your own numbers outweigh the others as they pile up, and every page says which it used.
-- Random greens and better are luck: they're shown apart and never counted in the gold an hour.

local _, NS = ...
local Fm = NS.Module("Farm")
NS.Farm = Fm
local E = NS.Engine

local PRIOR = 20        -- your corpses count as much as the tables once you've looted this many
local MIN_OWN = 5       -- corpses before your own numbers are used where there's no table
local BASE_CYCLE = 60   -- seconds a kill, everything included, until your own pace is known
local RESPAWN = 12      -- kills an hour one spawn can feed (about a 5 minute respawn)
local AH_TIMES = 25     -- ... and the most it may be over the vendor price (silly listings aside)
local AH_CLASS = { [0] = true, [5] = true, [7] = true } -- consumables, reagents, trade goods: what really sells there

local function List(t) return type(t) == "table" and t or {} end

local function Rec(id)
  local mobs = NS.db and NS.db.rec and NS.db.rec.mobs
  local m = type(mobs) == "table" and mobs[id]
  return type(m) == "table" and m or nil
end

-- Classic's numbers for a creature (MobData.lua): { hp, dmg, coin, type, loot = { item, rate, ... }, skin = {...}, rare = copper }
local function M() return type(_G.SunstoneMobs) == "table" and _G.SunstoneMobs or nil end
local tableCache = {}
local function Table(id)
  local c = tableCache[id]
  if c ~= nil then return c or nil end
  local d = M()
  local r = d and type(d.mobs) == "table" and d.mobs[id]
  local out = false
  if type(r) == "table" then
    out = { hp = r[1], dmg = r[2], coin = r[3], type = r[4], loot = List(d.loot[r[5] or 0]), skin = d.loot[r[6] or 0], rare = r[7] }
  end
  -- players' corpses: instead of Classic's loot when there are enough of them, or where Classic knows nothing
  local s = NS.Community and NS.Community.Mob(id)
  if s and (s.l or 0) >= (out and NS.Community.ENOUGH or 20) then
    out = out or {}
    out.coin, out.loot, out.players, out.corpses = s.c or 0, List(s.i), s.n or 0, s.l
  end
  tableCache[id] = out
  return out or nil
end
Fm.Table = Table

---------------------------------------------------------------------------
-- What an item sells for
---------------------------------------------------------------------------
-- what to count on, where ("vendor" or "Auction House"), the vendor price, the Auction House record
local priceCache, priceAt = {}, 0
local Work
function Fm.Price(id)
  local now = GetTime()
  if now - priceAt > 60 then priceCache, priceAt = {}, now end
  local c = priceCache[id]
  if not c then
    c = { Work(id) }
    priceCache[id] = c
  end
  return c[1], c[2], c[3], c[4]
end
function Work(id)
  local v = NS.Auction and NS.Auction.Vendor and NS.Auction.Vendor(id, false)
  if not v then v = M() and M().sell and M().sell[id] end
  local _, _, _, _, _, class = NS.GetItemInfoInstant(id)
  local u = class and AH_CLASS[class] and NS.Auction and NS.Auction.Usual and NS.Auction.Usual(id)
  if u then
    -- what it has usually gone for, or today's price if that's lower (you'd be undercutting it); less the house's cut
    local ah = (u.now and math.min(u.now, u.usual) or u.usual) * 0.95
    if v and v > 0 then ah = math.min(ah, v * AH_TIMES) end
    -- one scan's price is a weaker promise than one that has held over several
    local sure = u.days >= 3 and 1 or u.days == 2 and 0.8 or 0.6
    local count = (v or 0) + (ah - (v or 0)) * sure
    if count > (v or 0) then return count, "Auction House", v, u end
  end
  return v, "vendor", v, u
end

-- "usually 1s 20c at the Auction House (5 scans, 90c to 1s 50c), now 1s 10c, 40 listed"
function Fm.PriceText(id)
  local p, where, v, u = Fm.Price(id)
  if not p then return "What it sells for isn't known yet" end
  local out = {}
  if where == "Auction House" and u then
    out[1] = string.format("Usually %s at the Auction House (%s%s)%s%s", NS.Money(math.floor(u.usual + 0.5)),
                           u.days == 1 and "one scan" or (u.days .. " scans"), u.days > 1 and string.format(", %s to %s", NS.Money(u.lo), NS.Money(u.hi)) or "",
                           u.now and u.days > 1 and (", now " .. NS.Money(u.now)) or "", u.avail and string.format(", %d listed", u.avail) or "")
    if u.days >= 3 and u.hi <= 2 * u.lo then out[1] = out[1] .. ". A steady price" end
  end
  if v and v > 0 then out[#out + 1] = string.format("%s at a vendor", NS.Money(v)) end
  return table.concat(out, ". ")
end

---------------------------------------------------------------------------
-- Questie's drop rates, turned round: creature -> { item = percent }, and which creatures drop an item (Classic's
-- tables and Questie's): built once, in the background
---------------------------------------------------------------------------
local byNpc, byItem
function Fm.BuildRates(done)
  if byNpc then if done then done() end return end
  local ok, mod = false, nil
  if QuestieLoader then ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "DropDB") end
  local tbl = ok and type(mod) == "table" and type(mod.tableWowhead) == "table" and mod.tableWowhead or {}
  E.Job("drop rates", function()
    local out, rev = {}, {}
    local function Drops(item, npc)
      rev[item] = rev[item] or {}
      rev[item][npc] = true
    end
    local d = M()
    for npc, r in pairs(d and List(d.mobs) or {}) do
      E.Yield()
      local l = List(d.loot[r[5] or 0])
      for k = 1, #l, 2 do if l[k + 1] >= 0.02 then Drops(l[k], npc) end end
    end
    for item, npcs in pairs(tbl) do
      E.Yield()
      if type(item) == "number" and item > 0 and type(npcs) == "table" then
        for npc, pct in pairs(npcs) do
          if type(npc) == "number" and type(pct) == "number" and pct > 0 then
            out[npc] = out[npc] or {}
            out[npc][item] = pct
            Drops(item, npc)
          end
        end
      end
    end
    return { out, rev }
  end, function(res)
    byNpc, byItem = res[1], res[2]
    E.ForgetSources()
    if done then done() end
  end)
end

-- Creatures near your level that drop an item, the likeliest first (at most `n`): { { id, chance } }
function Fm.Droppers(item, n)
  local out, L = {}, UnitLevel("player")
  for npc in pairs(List(byItem and byItem[item])) do
    E.Yield()
    local lo, hi = E.Huntable(npc)
    if lo and lo <= L + 3 and hi >= L - 12 then
      local c = Fm.Chance(item, npc)
      if c then out[#out + 1] = { id = npc, chance = c } end
    end
  end
  table.sort(out, function(a, b) if a.chance ~= b.chance then return a.chance > b.chance end return a.id < b.id end)
  while #out > (n or 30) do table.remove(out) end
  return out
end

---------------------------------------------------------------------------
-- What a corpse gives
---------------------------------------------------------------------------
local function Quality(id) return select(3, NS.GetItemInfo(id)) end

-- { items = { { id, n (per corpse), own, from } }, coin, own (your corpses), from = "you" / "mixed" / "classic" / "questie" }
local lootCache = {}
function Fm.Forget() lootCache = {} end
function Fm.Loot(id)
  local c = lootCache[id]
  if c and GetTime() - c.t < 60 then return c.v or nil end
  local m, t = Rec(id), Table(id)
  local own = m and m.l or 0
  local w = own / (own + PRIOR)
  local items, seen = {}, {}
  local function Add(item, n, from)
    if not seen[item] and n > 0 then
      seen[item] = true
      items[#items + 1] = { id = item, n = n, from = from }
    end
  end
  local coin
  if t then
    for k = 1, #List(t.loot), 2 do
      local item, n = t.loot[k], t.loot[k + 1]
      local mine = own > 0 and (List(m.i)[item] or 0) / own or nil
      Add(item, mine and (w * mine + (1 - w) * n) or n, own >= PRIOR and "you" or own > 0 and "mixed" or t.players and "players" or "classic")
    end
    coin = t.coin or 0
    if own > 0 then coin = w * ((m.c or 0) / own) + (1 - w) * coin end
  elseif own >= MIN_OWN then
    coin = (m.c or 0) / own
  end
  if own >= MIN_OWN or (t and own > 0) then
    for item, n in pairs(List(m.i)) do
      if type(item) == "number" and type(n) == "number" and (Quality(item) or 1) < 2 then
        Add(item, t and w * n / own or n / own, t and "mixed" or "you")
      end
    end
  end
  for item, pct in pairs(List(byNpc and byNpc[id])) do
    if not seen[item] and (Quality(item) or 1) < 2 and own < MIN_OWN then Add(item, pct / 100, "questie") end
  end
  -- skinning, when you can
  if E.Skill("Skinning") then
    if m and (m.sn or 0) >= 3 then
      for item, n in pairs(List(m.sk)) do Add(item, n / m.sn, "you") end
    elseif t and t.skin then
      for k = 1, #t.skin, 2 do Add(t.skin[k], t.skin[k + 1], "classic") end
    end
  end
  local out
  if #items > 0 or coin then
    out = { items = items, coin = coin or 0, own = own,
            from = own >= PRIOR and "you" or (t and (own > 0 and "mixed" or t.players and "players" or "classic")) or (own >= MIN_OWN and "you") or "questie" }
    local total, vend = out.coin, out.coin
    for _, e in ipairs(items) do
      local p, where, v = Fm.Price(e.id)
      e.price, e.where, e.vendor = p, where, v
      total = total + (p or 0) * e.n
      vend = vend + (v or 0) * e.n
    end
    out.value, out.vendor = total, vend
    table.sort(items, function(a, b) return (a.price or 0) * a.n > (b.price or 0) * b.n end)
    -- random greens and better: what they've added on average (luck; shown, never counted)
    if m and own >= 30 and (m.rv or 0) > 0 then out.rare = m.rv / own elseif t and t.rare and t.rare > 0 then out.rare = t.rare end
  end
  lootCache[id] = { t = GetTime(), v = out or false }
  return out or nil
end

-- How often this creature drops this item, 0 to 1, and where the number is from; nil = nobody knows
function Fm.Chance(item, npc)
  local m, t = Rec(npc), Table(npc)
  local own = m and m.l or 0
  local mine = own > 0 and math.min(1, (List(m.i)[item] or 0) / own) or nil
  local base, from
  if t then
    for k = 1, #List(t.loot), 2 do if t.loot[k] == item then base, from = math.min(1, t.loot[k + 1]), t.players and string.format("%d corpses of %d players", t.corpses, t.players) or "Classic's loot table" end end
  end
  if not base and byNpc and byNpc[npc] and byNpc[npc][item] then base, from = byNpc[npc][item] / 100, "Wowhead, through Questie" end
  if mine and own >= PRIOR and (mine > 0 or not base) then return mine > 0 and mine or nil, string.format("your %d corpses", own) end
  if base and mine then return (own * mine + PRIOR * base) / (own + PRIOR), from .. " and your own corpses" end
  if base then return base, from end
  if mine and mine > 0 and own >= MIN_OWN then return mine, string.format("your %d corpses", own) end
end

local FROM = { players = "corpses Sunstone's players shared", you = "your own corpses", mixed = "your own corpses and Classic's loot tables", classic = "Classic's loot tables (Forever's may differ a little)",
               questie = "Questie's (Wowhead) rates, which only cover some items" }
Fm.FROM = FROM

---------------------------------------------------------------------------
-- How long one takes to kill
---------------------------------------------------------------------------
-- your pace solo near your level: seconds a kill, walking and resting included (the recorder times it)
function Fm.Pace()
  local L = UnitLevel("player")
  local p = NS.Recorder and NS.Recorder.Pool and NS.Recorder.Pool("solo", L - 2, L + 1)
  if p and (p.k or 0) >= 20 and (p.t or 0) > 0 then
    return math.max(20, math.min(150, p.t / p.k)), p.k
  end
  local shared = NS.Community and NS.Community.Pace(L)
  if shared then return math.max(20, math.min(150, shared)) end
  return BASE_CYCLE
end

-- seconds for one kill of this creature at your level
function Fm.KillTime(id)
  local lo, hi = E.Huntable(id)
  if not lo then return nil end
  local d = (lo + hi) / 2 - UnitLevel("player")
  local f = d >= 0 and (1 + 0.15 * d) or math.max(0.45, 1 + 0.07 * d)
  local t = Table(id)
  local ref = M() and M().hpRef
  if t and t.hp and ref then
    local r = ref[math.floor((lo + hi) / 2 + 0.5)]
    if type(r) == "table" and r[1] and r[1] > 0 then
      f = f * math.max(0.5, math.min(2.5, t.hp / r[1])) ^ 0.7
      if t.dmg and r[2] and r[2] > 0 then f = f * math.max(0.6, math.min(2, t.dmg / r[2])) ^ 0.5 end
    end
  end
  local base = Fm.Pace()
  return base * (0.35 + 0.65 * f), f -- (walking up and looting don't change with the creature)
end

function Fm.Ease(f)
  if not f then return "" end
  if f <= 0.7 then return "very easy for you" elseif f <= 0.95 then return "easy for you" elseif f <= 1.2 then return "a normal fight"
  elseif f <= 1.6 then return "a harder fight" end
  return "a tough fight"
end

---------------------------------------------------------------------------
-- The spots, best gold an hour first
---------------------------------------------------------------------------
function Fm.Find(done)
  Fm.BuildRates(function()
    E.Job("farm spots", function()
      local L = UnitLevel("player")
      local camps = E.BuildCamps(function(id, lo)
        if lo > L + 2 or lo < math.max(1, L - 12) then return false end
        local a, b = E.Huntable(id)
        if not a or b > L + 2 then return false end
        local l = Fm.Loot(id)
        return l and l.value > 0
      end, E.Reach())
      local rows, items = {}, {}
      for _, c in ipairs(camps) do
        E.Yield()
        local value, vendor, rare, secs, n, mobs = 0, 0, 0, 0, 0, {}
        for id, cnt in pairs(c.npcs) do
          local l, t, f = Fm.Loot(id), Fm.KillTime(id)
          if l and t then
            value, vendor, rare, secs, n = value + l.value * cnt, vendor + l.vendor * cnt, rare + (l.rare or 0) * cnt, secs + t * cnt, n + cnt
            mobs[#mobs + 1] = { id = id, n = cnt, value = l.value, f = f, from = l.from, own = l.own }
          end
        end
        if n >= 4 then
          local kph = math.min(3600 / (secs / n), RESPAWN * n)
          table.sort(mobs, function(a, b) return a.n * a.value > b.n * b.value end)
          local gph = value / n * kph
          rows[#rows + 1] = { p = c.p, n = n, kph = kph, gph = gph, vph = vendor / n * kph, rph = rare / n * kph, trip = c.trip,
                              score = gph * 60 / (60 + c.trip), mobs = mobs }
          -- each thing worth selling: how many an hour here
          local per, who = {}, {}
          for _, mb in ipairs(mobs) do
            local l = Fm.Loot(mb.id)
            for _, it in ipairs(l and l.items or {}) do
              if it.price and it.price > 0 then
                local ph = it.n * mb.n / n * kph
                per[it.id] = (per[it.id] or 0) + ph
                if not who[it.id] or ph > who[it.id][2] then who[it.id] = { mb.id, ph } end
              end
            end
          end
          for item, ph in pairs(per) do
            local price, where = Fm.Price(item)
            local worth = (price or 0) * ph
            local s = worth * 60 / (60 + c.trip)
            if not items[item] or s > items[item].score then
              items[item] = { id = item, ph = ph, price = price, where = where, worth = worth, score = s, spot = rows[#rows], best = who[item][1] }
            end
          end
        end
      end
      table.sort(rows, function(a, b) return a.score > b.score end)
      local list = {}
      for _, it in pairs(items) do list[#list + 1] = it end
      table.sort(list, function(a, b) return a.score > b.score end)
      while #list > 20 do table.remove(list) end
      while #rows > 25 do table.remove(rows) end
      return { t = time(), level = L, rows = rows, items = list, from = E.Here() }
    end, function(res)
      E.cache.farm = res
      if done then done(res) end
    end)
  end)
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function Money(c) return NS.Money(math.floor((c or 0) + 0.5)) end

local function Percent(n)
  local p = n * 100
  if p >= 10 then return string.format("%d%%", math.floor(p + 0.5)) end
  return string.format("%.1f%%", p)
end

-- A creature: what it drops, how often, what each is worth to you
function Fm.CreaturePage(id)
  local rows = {}
  local l = Fm.Loot(id)
  local secs, f = Fm.KillTime(id)
  local p = E.Nearest(E.Points("Npc", id))
  rows[1] = E.At({ t = E.NpcName(id), d = E.Creature(id) .. (f and (", " .. Fm.Ease(f)) or "") .. (p and ("\n" .. E.PlaceText(p)) or "") }, p)
  if l then
    rows[#rows + 1] = { t = string.format("A corpse is worth about %s", Money(l.value)),
                        d = string.format("%s of it coins%s. From %s%s.", Money(l.coin), l.vendor < l.value - 0.5 and (", " .. Money(l.vendor) .. " selling it all to a vendor") or "", FROM[l.from],
                                          l.own > 0 and string.format(" (%d of yours)", l.own) or "") }
    if l.rare then rows[#rows + 1] = { t = string.format("Random greens add about %s a corpse on average", Money(l.rare)), d = "Luck: not counted above.", dim = true } end
    if #l.items > 0 then rows[#rows + 1] = { h = "What it drops" } end
    for k = 1, math.min(#l.items, 16) do
      local it = l.items[k]
      rows[#rows + 1] = { t = string.format("%s: %s", E.ItemName(it.id), it.n > 1 and string.format("%.1f each", it.n) or Percent(it.n)), i = it.id,
                          d = Fm.PriceText(it.id) }
    end
  else
    rows[#rows + 1] = { t = "Nobody has recorded what it drops yet", d = "Sunstone records it as you loot: about 5 corpses are enough to start." }
  end
  return { title = E.NpcName(id), icon = "Interface\\Icons\\INV_Misc_Bone_Skull_02", rows = rows, sub = "What it drops, how often, and what that's worth" }
end

function Fm.SpotPage(r)
  local rows = { E.At({ t = string.format("About %s an hour", Money(r.gph)),
                        d = string.format("%s\nAbout %d kills an hour, %d spawns.%s", E.PlaceText(r.p), math.floor(r.kph + 0.5), r.n,
                                          r.vph < r.gph * 0.97 and (" Selling everything to a vendor instead: " .. Money(r.vph) .. " an hour.") or "") }, r.p) }
  if r.rph and r.rph > 1 then rows[#rows + 1] = { t = string.format("Random greens: about %s more an hour on average", Money(r.rph)), d = "Luck, so it isn't counted above.", dim = true } end
  local pace, k = Fm.Pace()
  rows[#rows + 1] = { t = k and string.format("Your pace: a kill every %d seconds (%d kills timed)", math.floor(pace + 0.5), k) or "Your own pace isn't known yet",
                      d = k and "Walking, looting and resting included." or "A kill a minute is assumed until the recorder has timed 20 kills near your level.", dim = true }
  rows[#rows + 1] = { h = "What's here" }
  for i, m in ipairs(r.mobs) do
    if i > 8 then break end
    rows[#rows + 1] = { t = string.format("%s: about %s a corpse", E.NpcName(m.id), Money(m.value)), tex = "Interface\\Icons\\INV_Misc_Bone_Skull_02",
                        d = string.format("%s, %s, %d spawn%s here\nFrom %s", E.Creature(m.id), Fm.Ease(m.f), m.n, m.n == 1 and "" or "s", FROM[m.from]),
                        page = function() return Fm.CreaturePage(m.id) end }
  end
  return { title = "Farm spot", icon = "Interface\\Icons\\INV_Misc_Coin_01", rows = rows, sub = "Solo. Click a creature for its drops." }
end

function Fm.ItemPage(it)
  local rows = { { t = E.ItemName(it.id), i = it.id, d = Fm.PriceText(it.id) },
                 { t = string.format("About %s an hour from this alone", Money(it.worth)), d = string.format("About %.0f of them an hour at the spot below.", it.ph) } }
  rows[#rows + 1] = { h = "Best spot for it" }
  rows[#rows + 1] = { t = string.format("About %s an hour in all", Money(it.spot.gph)), d = E.PlaceText(it.spot.p), m = it.spot.p.m, x = it.spot.p.x, y = it.spot.p.y,
                      page = function() return Fm.SpotPage(it.spot) end, tex = "Interface\\Icons\\INV_Misc_Coin_01" }
  rows[#rows + 1] = { h = "Who drops it there" }
  for _, m in ipairs(it.spot.mobs) do
    local c, from = Fm.Chance(it.id, m.id)
    if c then
      rows[#rows + 1] = { t = string.format("%s: %s", E.NpcName(m.id), Percent(c)), d = string.format("%s, %s. From %s.", E.Creature(m.id), Fm.Ease(m.f), from or "?"),
                          tex = "Interface\\Icons\\INV_Misc_Bone_Skull_02", page = function() return Fm.CreaturePage(m.id) end }
    end
  end
  return { title = E.ItemName(it.id), icon = NS.ItemIcon(it.id), rows = rows, sub = "Farm it and sell it" }
end

---------------------------------------------------------------------------
-- Rows for the Gold tab
---------------------------------------------------------------------------
function Fm.Rows(rows, c)
  if c and #c.rows > 0 then
    rows[#rows + 1] = { h = "Fastest gold near you, farming alone" }
    for k = 1, math.min(#c.rows, 6) do
      local r = c.rows[k]
      local names = {}
      for i = 1, math.min(#r.mobs, 2) do names[i] = E.NpcName(r.mobs[i].id) end
      rows[#rows + 1] = { t = string.format("%s an hour: %s", Money(r.gph), table.concat(names, ", ")), d = E.PlaceText(r.p) .. ", " .. Fm.Ease(r.mobs[1].f),
                          tex = "Interface\\Icons\\INV_Misc_Coin_01", key = "farm" .. k, page = function() return Fm.SpotPage(r) end }
    end
  end
  if c and c.items and #c.items > 0 then
    rows[#rows + 1] = { h = "Best things to farm and sell" }
    for k = 1, math.min(#c.items, 8) do
      local it = c.items[k]
      rows[#rows + 1] = { t = string.format("%s: %s an hour", E.ItemName(it.id), Money(it.worth)), i = it.id, key = "farmitem" .. it.id,
                          d = string.format("%s each (%s), %s", Money(it.price), it.where, E.NpcName(it.best or it.spot.mobs[1].id)), page = function() return Fm.ItemPage(it) end }
    end
  end
end

function Fm:Init()
  NS.On("LOOT_CLOSED", function() NS.Debounce("farmForget", 20, Fm.Forget) end)
  -- Questie's rates, once it has settled (also used for drop chances on item pages)
  C_Timer.After(12, function() NS.Safe("drop rates", Fm.BuildRates) end)
end
