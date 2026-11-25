-- Sunstone: planning your crafting, on the Professions tab.
--   Crafting list: what you want to make, and everything that still takes, with where each thing comes from.
--   Plan: the cheapest way up to the next rank or to 300, with what it all takes.
--   Profit: what you can make that sells for more than its materials, to a vendor or at the Auction House.
-- A material counts at the least of: a vendor's price, the last Auction House scan, making it yourself, and the time it takes to
-- farm one (CraftData.lua, from Classic's loot tables) at what an hour of your time makes at your level. What has none of these is
-- a rough guess, and marked. Nothing here crafts, buys or sells: that's your own click.

local _, NS = ...
local K = NS.Module("Crafts")
NS.Crafts = K
local E, P = NS.Engine, NS.Professions
local I = "Interface\\Icons\\"
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local function List(t) return type(t) == "table" and t or {} end

local ODDS = { orange = 1, yellow = 0.75, green = 0.25 }  -- how often a craft raises your skill, as in Classic (K.Odds: yours, once seen)
local COOLDOWN = 7200   -- seconds one use of a long cooldown is counted as (Arcanite, Mooncloth): you can't make many
local function Craft() return type(_G.SunstoneCraft) == "table" and _G.SunstoneCraft or {} end

-- What an hour of farming is worth, in copper a second: about 1g an hour at 5, 2g at 20, 5g at 60
function K.Rate() return max(3, 0.25 * (UnitLevel("player") or 1)) end

-- How to count materials: "least" (whichever is cheapest), "self" (no Auction House), "buy" (what can be bought is bought)
K.BASES = { { "least", "Whatever is cheapest" }, { "self", "Without the Auction House" }, { "buy", "Buy all I can" } }
function K.Basis()
  local b = NS.cdb and NS.cdb.craftBasis
  for _, x in ipairs(K.BASES) do if x[1] == b then return x end end
  return K.BASES[1]
end

local bySpell
local function Recipe(spell)
  if not bySpell then
    bySpell = {}
    for prof, list in pairs(E.Data().recipes) do
      for _, r in ipairs(list) do
        r.prof = prof
        bySpell[r.s] = r
      end
    end
  end
  return bySpell[spell]
end
K.Recipe = Recipe

---------------------------------------------------------------------------
-- What one of a thing costs
---------------------------------------------------------------------------
-- memo: one plan's prices. -> copper, how ("vendor", "ah", "make", "farm", "other", "list" or "guess"), the recipe (make, other), seconds to farm one
function K.Unit(id, prof, memo, depth)
  memo = memo or {}
  local m = memo[id]
  if m then return m[1], m[2], m[3], m[4] end
  depth = depth or 0
  local basis = K.Basis()[1]
  local best, how, with
  local function Try(v, h, w)
    if v and (not best or v < best) then best, how, with = v, h, w end
  end
  local A = NS.Auction
  Try(E.VendorPrice(id), "vendor")
  if basis ~= "self" then Try(A and A.Price and A.Price(id), "ah") end
  local maker = depth < 3 and P.MakerOf(prof, id)
  if maker and (not maker.sd or maker.sd == E.Side()) and (E.Skill(prof) or 300) >= (maker.k or 0) then
    memo[id] = { 1e12, "loop" }
    local cost = K.Cost(maker, memo, depth + 1)
    memo[id] = nil
    if cost then Try((cost + (maker.cd and COOLDOWN * K.Rate() or 0)) / (maker.c or 1), "make", maker) end
  end
  local secs = List(Craft().farm)[id]
  if secs and not memo.nofarm and not (basis == "buy" and best) then Try(secs * K.Rate(), "farm") end
  if not best and not memo.nofarm and depth < 3 then -- another profession makes it
    memo[id] = { 1e12, "loop" }
    for _, r in ipairs(E.Made(id)) do
      local cost = K.Cost(r, memo, depth + 1)
      if cost then Try((cost + (r.cd and COOLDOWN * K.Rate() or 0)) / (r.c or 1), "other", r) end
    end
    memo[id] = nil
  end
  if not best and memo.nofarm then return nil end -- (profit: only what has a price)
  if not best then
    local sell = A and A.Vendor and A.Vendor(id, true)
    if List(Craft().price)[id] then Try(List(Craft().price)[id], "list")
    elseif sell and sell > 0 then Try(max(sell * 6, 60 * K.Rate()), "guess")
    else Try(600 * K.Rate(), "guess") end -- nothing known: as if it took ten minutes
  end
  memo[id] = { best, how, with, secs }
  return best, how, with, secs
end
local ROUGH_HOW = { list = true, guess = true }

-- a recipe's materials -> copper, true when part of it is a rough guess; nil when something has no price at all
function K.Cost(r, memo, depth)
  local total, rough = 0, false
  for k = 1, #r.r, 2 do
    local u, how = K.Unit(r.r[k], r.prof, memo, depth)
    if not u or u >= 1e12 then return nil end
    if ROUGH_HOW[how] then rough = true end
    total = total + u * r.r[k + 1]
  end
  return total, rough
end

---------------------------------------------------------------------------
-- The crafting list: cdb.craft[spell] = how many
---------------------------------------------------------------------------
local function Want()
  NS.cdb.craft = type(NS.cdb.craft) == "table" and NS.cdb.craft or {}
  return NS.cdb.craft
end
function K.Count(spell) return Want()[spell] or 0 end
function K.Add(spell, n)
  local w = Want()
  local v = max(0, min(999, (w[spell] or 0) + n))
  w[spell] = v > 0 and v or nil
  if NS.Window then NS.Window.Refresh() end
end
function K.Clear()
  wipe(Want())
  if NS.Window then NS.Window.Refresh() end
end

-- Everything a set of crafts takes: [recipe] = times. What's in your bags is used first; a material you can make yourself is broken down into its own.
-- -> raw = { [item] = needed beyond what can be made }, mid = { { r, times } } (what to make on the way)
function K.Needs(list, useBags)
  local need, mid, left = {}, {}, {}
  local function Bags(id)
    if left[id] == nil then left[id] = useBags and E.Have(id) or 0 end
    return left[id]
  end
  local midAt = {}
  local function Use(r, times, depth)
    for k = 1, #r.r, 2 do
      local id, n = r.r[k], r.r[k + 1] * times
      local maker = P.MakerOf(r.prof, id)
      if maker and (maker == r or depth > 3 or (maker.sd and maker.sd ~= E.Side()) or maker.cd or (E.Skill(r.prof) or 0) < (maker.k or 0)) then maker = nil end
      need[id] = (need[id] or 0) + n
      if maker then
        local have = min(Bags(id), n)
        left[id] = left[id] - have
        local short = n - have
        if short > 0 then
          local t = ceil(short / (maker.c or 1))
          if not midAt[maker] then
            midAt[maker] = { r = maker, n = 0 }
            mid[#mid + 1] = midAt[maker]
          end
          midAt[maker].n = midAt[maker].n + t
          Use(maker, t, depth + 1)
        end
        need[id] = need[id] - n
        if need[id] <= 0 then need[id] = nil end
      end
    end
  end
  for _, e in ipairs(list) do Use(e.r, e.n, 0) end
  return need, mid
end

local function Span(secs)
  if secs >= 5400 then return string.format("%.1f hours", secs / 3600) end
  if secs >= 90 then return string.format("%d minutes", floor(secs / 60 + 0.5)) end
  return "a minute"
end
K.Span = Span

-- what your other characters had on them when last seen
local function Alts(id)
  local out, me = {}, NS.CharKey()
  for key, s in pairs(NS.db.snapshots or {}) do
    if key ~= me and type(s) == "table" and s.realm == GetRealmName() and s.faction == UnitFactionGroup("player") then
      for _, b in ipairs(List(s.bags)) do
        local n = type(b) == "table" and b.id == id and tonumber(b.count or b.n)
        if n and n > 0 then out[#out + 1] = (s.name or "?") .. " has " .. n end
      end
    end
  end
  return out
end

local HOWS = { { "have", "You have these" }, { "vendor", "From a vendor" }, { "farm", "To farm or gather" }, { "ah", "Cheapest at the Auction House" },
               { "other", "Made, not found" }, { "guess", "No price known (a rough guess)" } }
-- -> copper to buy, seconds to farm, rough, the lot in copper
local function MaterialRows(rows, need, prof, opts)
  local by, buy, time, rough, all = {}, 0, 0, false, 0
  local memo = {}
  for id, n in pairs(need) do
    local have = E.Have(id)
    local short = max(0, n - have)
    local u, how, with, secs = K.Unit(id, prof, memo)
    if how == "make" then how = "other" end -- (on the list as a material: you can't make it yet)
    local group = short == 0 and "have" or (how == "list" or how == "guess") and "guess" or how
    if short > 0 then
      all = all + u * short
      if how == "farm" then time = time + secs * short else buy = buy + u * short end
      if group == "guess" then rough = true end
    end
    by[group] = by[group] or {}
    table.insert(by[group], { id = id, n = n, have = have, short = short, u = u, how = how, with = with, secs = secs })
  end
  for _, h in ipairs(HOWS) do
    local l = by[h[1]]
    if l then
      table.sort(l, function(a, b) if a.u * a.short ~= b.u * b.short then return a.u * a.short > b.u * b.short end return E.ItemName(a.id) < E.ItemName(b.id) end)
      rows[#rows + 1] = { h = h[2] }
      for _, e in ipairs(l) do
        local bits, place = {}, nil
        if e.short > 0 then
          local b = E.Best(e.id)
          place = b and b.place
          if b then bits[1] = b.label .. (b.d and b.d ~= "" and ("\n" .. (b.d:match("^[^\n]+") or "")) or "") end
          local ah = NS.Auction and NS.Auction.Price and NS.Auction.Price(e.id)
          if e.how == "farm" then
            bits[#bits + 1] = "About " .. Span(e.secs * e.short) .. " of farming" .. (ah and (", or " .. NS.Money(ah * e.short) .. " at the Auction House") or "")
          else
            bits[#bits + 1] = (h[1] == "guess" and "Roughly " or "About ") .. NS.Money(e.u * e.short) .. (e.how == "ah" and " at the Auction House" or e.with and (", " .. e.with.prof .. " makes it") or "")
              .. (e.secs and h[1] ~= "vendor" and (", or " .. Span(e.secs * e.short) .. " of farming") or "")
          end
          local alts = Alts(e.id)
          if #alts > 0 then bits[#bits + 1] = table.concat(alts, ", ") end
        end
        rows[#rows + 1] = E.At({ t = string.format("%dx %s", e.short > 0 and e.short or e.n, E.ItemName(e.id)) .. (e.have > 0 and e.short > 0 and string.format("  (of %d, you have %d)", e.n, e.have) or ""),
                                 i = e.id, d = #bits > 0 and table.concat(bits, "\n") or nil, dim = e.short == 0 or nil, key = (opts or "need") .. e.id }, place)
      end
    end
  end
  return buy, time, rough, all
end

function K.Listed()
  local out = {}
  for spell, n in pairs(Want()) do
    local r = Recipe(spell)
    if r and type(n) == "number" and n > 0 then out[#out + 1] = { r = r, n = n } end
  end
  table.sort(out, function(a, b) if a.r.prof ~= b.r.prof then return a.r.prof < b.r.prof end return a.r.n < b.r.n end)
  return out
end

function K.ListRows()
  local list, rows = K.Listed(), {}
  if #list == 0 then
    rows[1] = { t = "Nothing on your list yet", d = "Open any recipe (the other buttons above) and press Add: Sunstone then works out everything it takes and where to get it.", still = true }
    return rows
  end
  rows[1] = { h = "To make" }
  for _, e in ipairs(list) do
    local r = e.r
    local skill = E.Skill(r.prof)
    local note = P.Known(r) and "" or not skill and ("You don't have " .. r.prof .. ".") or skill < (r.k or 0) and string.format("Needs %s %d.", r.prof, r.k) or "You haven't learned it yet."
    rows[#rows + 1] = { t = string.format("%dx %s", e.n, r.n), i = r.i, tex = not r.i and I .. "INV_Scroll_03" or nil, q = r.q, d = (r.prof .. (note ~= "" and (". " .. note) or "")), key = "list" .. r.s,
                        page = function() return P.RecipePage(r) end, actLabel = "+1", act = function() K.Add(r.s, 1) end, act2Label = "-1", act2 = function() K.Add(r.s, -1) end }
  end
  local need, mid = K.Needs(list, true)
  if #mid > 0 then
    rows[#rows + 1] = { h = "Make these on the way" }
    for _, m in ipairs(mid) do
      rows[#rows + 1] = { t = string.format("%dx %s", m.n * (m.r.c or 1), m.r.n), i = m.r.i, d = m.r.prof .. " " .. (m.r.k or "?"), key = "mid" .. m.r.s, page = function() return P.RecipePage(m.r) end }
    end
  end
  local buy, time, rough, all = MaterialRows(rows, need, list[1].r.prof)
  if all == 0 then rows[#rows + 1] = { t = "You have everything", still = true, ring = "good" }
  else rows[#rows + 1] = { t = K.Sum(buy, time, rough), still = true, d = "Counted: " .. K.Basis()[2]:lower() .. ". The Plan page has that switch." } end
  rows[#rows + 1] = { t = "Start over", d = "Empties the list.", still = true, key = "listclear", actLabel = "Clear", act = K.Clear }
  return rows
end

function K.Sum(buy, time, rough)
  local bits = {}
  if buy > 0 then bits[#bits + 1] = (rough and "roughly " or "about ") .. NS.Money(buy) .. " to buy" end
  if time > 0 then bits[#bits + 1] = "about " .. Span(time) .. " of farming" end
  local t = table.concat(bits, " and ")
  return t == "" and "Nothing left to get" or (t:gsub("^%l", string.upper))
end

-- at a vendor who sells something the list still needs: one line in chat
function K.AtVendor()
  local list = K.Listed()
  if #list == 0 or not GetMerchantNumItems then return end
  local need, bits = (K.Needs(list, true)), {}
  for i = 1, GetMerchantNumItems() or 0 do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if not id and GetMerchantItemLink then
      local l = GetMerchantItemLink(i)
      id = type(l) == "string" and tonumber(l:match("item:(%d+)")) or nil
    end
    local short = id and need[id] and need[id] - E.Have(id) or 0
    if short > 0 then bits[#bits + 1] = short .. "x " .. E.ItemName(id) end
  end
  if #bits > 0 then NS.Print("for your crafting list, this vendor sells: " .. table.concat(bits, ", ") .. ".") end
end

-- the two rows on a recipe's page
function K.RecipeRows(rows, r)
  local n = K.Count(r.s)
  rows[#rows + 1] = { t = n > 0 and string.format("On your crafting list: %d", n) or "Want to make it?", still = true, key = "add" .. r.s, d = "The Crafting list adds up what it all takes and where to get it.",
                      actLabel = "Add 1", act = function() K.Add(r.s, 1) end, act2Label = n > 0 and "Remove" or "Add 5", act2 = function() K.Add(r.s, n > 0 and -n or 5) end }
end

---------------------------------------------------------------------------
-- The cheapest way up
---------------------------------------------------------------------------
K.target = {}    -- [prof] = "next" or 300
local plans = {} -- [prof] = { key, segs, ... }

-- can it be part of a plan: known, taught by a trainer, or sold as a recipe by a vendor of yours -> what learning it costs, how, and the fee as it's
-- weighed (a trip to learn one recipe has to be worth it)
local function Plannable(r)
  if r.cd or not r.k or not r.x then return nil end
  if r.sd and r.sd ~= E.Side() then return nil end
  if P.Known(r) or r.st then return 0, "known", 0 end
  if not r.ri then
    local t, fee = E.Teacher(r.prof, r.s)
    if not t and not fee then return nil end
    return fee or 0, "trainer", (fee or 0) + 45 * K.Rate()
  end
  if r.rep or r.fav then return nil end
  if type(r.v) == "table" then
    -- what the vendor asks: seen, else Classic's price, else about what such recipes cost
    local price = E.VendorPrice(r.ri) or List(Craft().recipe)[r.ri] or floor(0.06 * r.k * r.k + 100)
    for _, v in pairs(r.v) do
      local id = type(v) == "table" and v[1] or v
      if type(id) == "number" and E.Friendly(id) then return price, "vendor", price + 420 * K.Rate() end
    end
  end
  local A = NS.Auction
  local ah = K.Basis()[1] ~= "self" and A and A.Price and A.Price(r.ri)
  if ah then return ah, "ah", ah + 60 * K.Rate() end
end

-- ranks cost money too: what learning up to `cap` costs from here
local function RankFees(prof, from, to)
  local out = {}
  local ranks = E.Data().prof[prof] and E.Data().prof[prof].ranks
  for i = 1, 4 do
    local r = ranks and ranks[i]
    if r and r[2] > from and (ranks[i - 1] and ranks[i - 1][2] or 0) < to then out[#out + 1] = { name = r[1], cap = r[2], fee = r[3], skill = r[4], level = r[5] } end
  end
  return out
end
K.RankFees = RankFees

-- How often a craft of this color raises your skill: your own crafts once there are enough of them, else Classic's
function K.Odds(color)
  local t = NS.db and type(NS.db.craftOdds) == "table" and NS.db.craftOdds[color or ""]
  if type(t) == "table" and (t.n or 0) >= 25 then return max(0.05, min(1, (t.up or 0) / t.n)), true end
  return ODDS[color or ""]
end

-- Dynamic programming over skill points: best[s] = the least spent to reach s; a recipe is learned once per stretch it's used for.
-- What a craft makes that the plan needs later (bolts, bars, potions) isn't lost: from the second round its materials come off.
local function Solve(prof, from, to, list)
  local best, via = { [from] = 0 }, {}
  for s = from, to - 1 do
    if best[s] then
      for _, e in ipairs(list) do
        local r = e.r
        if r.k <= s and s < r.x then
          local spent, casts = best[s] + e.weigh, 0
          for p = s, min(to, r.x) - 1 do
            local odds = K.Odds(P.Color(r, p))
            if not odds then break end
            spent, casts = spent + e.net / odds, casts + 1 / odds
            local total = spent + casts * 2 -- (a little per craft: free materials don't mean hundreds of them)
            if not best[p + 1] or total < best[p + 1] then best[p + 1], via[p + 1] = total, { s = s, e = e, casts = casts } end
          end
        end
      end
    end
    E.Yield()
  end
  local reach = to
  while reach > from and not best[reach] do reach = reach - 1 end
  local segs, s = {}, reach
  while s > from and via[s] do
    local v = via[s]
    table.insert(segs, 1, { e = v.e, from = v.s, to = s, casts = v.casts })
    s = v.s
  end
  return segs, reach, best[reach] or 0
end

-- what it costs to go from a to b with one recipe; nil when it doesn't reach
local function Stretch(e, a, b)
  local r, cost, casts = e.r, e.weigh, 0
  if r.k > a then return nil end
  for p = a, b - 1 do
    local odds = K.Odds(P.Color(r, p))
    if not odds or p >= r.x then return nil end
    cost, casts = cost + e.net / odds, casts + 1 / odds
  end
  return cost + casts * 2, casts
end

function K.Work(prof, from, to)
  local memo, list = {}, {}
  local A = NS.Auction
  for _, r in ipairs(E.Data().recipes[prof] or {}) do
    r.prof = prof
    local fee, how, weigh = Plannable(r)
    if fee and r.x > from and r.k < to then
      local cost, rough = K.Cost(r, memo)
      -- what a vendor pays for the result comes off (a known price only; never more than 90% of the materials)
      local back = cost and r.i and A and A.Vendor and A.Vendor(r.i, false) or 0
      if cost then list[#list + 1] = { r = r, fee = fee, how = how, weigh = weigh, cost = cost, back = back * (r.c or 1), rough = rough, net = max(cost * 0.1, cost - back * (r.c or 1)) } end
    end
    E.Yield()
  end
  local segs, reach, total
  for round = 1, 4 do
    segs, reach, total = Solve(prof, from, to, list)
    if round == 4 then break end
    -- what the plan's crafts use and make
    local use, make = {}, {}
    for _, g in ipairs(segs) do
      local r = g.e.r
      for k = 1, #r.r, 2 do use[r.r[k]] = (use[r.r[k]] or 0) + r.r[k + 1] * g.casts end
      if r.i then make[r.i] = (make[r.i] or 0) + (r.c or 1) * g.casts end
    end
    local changed = false
    for _, e in ipairs(list) do
      local r = e.r
      local net = max(e.cost * 0.1, e.cost - e.back)
      local share = r.i and use[r.i] and min(1, use[r.i] / max(1, make[r.i] or (r.c or 1))) or 0
      if share > 0 then net = max(e.cost * 0.04, min(net, e.cost * (1 - share) + e.cost * 0.04 * share)) end
      if math.abs(net - e.net) > 0.5 then e.net, changed = net, true end
    end
    if not changed then break end
    E.Yield()
  end
  -- neighbours with the same recipe are one step
  local out = {}
  for _, g in ipairs(segs) do
    local l = out[#out]
    if l and l.e == g.e then l.to, l.casts = g.to, l.casts + g.casts else out[#out + 1] = g end
  end
  local learned = {}
  for _, g in ipairs(out) do
    local e = g.e
    local r = e.r
    g.r, g.n, g.rough, g.how = r, ceil(g.casts - 0.01), e.rough, e.how
    g.fee = not learned[r.s] and e.fee or 0
    learned[r.s] = true
    -- the next best ways over the same points
    local mine = Stretch(e, g.from, g.to)
    local alts = {}
    for _, o in ipairs(list) do
      local c = o ~= e and mine and Stretch(o, g.from, g.to)
      if c then alts[#alts + 1] = { r = o.r, more = max(0, c - mine), how = o.how, fee = o.fee } end
    end
    table.sort(alts, function(a, b) return a.more < b.more end)
    while #alts > 3 do table.remove(alts) end
    g.alts, g.cost = alts, mine or 0
    E.Yield()
  end
  -- recipes you'd have to find (drops, quests, reputation, Merchant's Favor) that would make a dear stretch cheaper, or go past where the rest end
  local finds, seen = {}, {}
  local stretches = {}
  for _, g in ipairs(out) do if g.to - g.from >= 5 then stretches[#stretches + 1] = { g.from, g.to, g.cost, false } end end
  if reach < to then stretches[#stretches + 1] = { reach, min(to, reach + 25), nil, true } end
  for _, r in ipairs(E.Data().recipes[prof] or {}) do
    if not r.cd and r.k and r.x and (not r.sd or r.sd == E.Side()) and not P.Known(r) and not Plannable(r) and r.x > from and r.k < to then
      local cost = K.Cost(r, memo)
      if cost then
        local e = { r = r, weigh = 0, net = max(cost * 0.1, cost - (r.i and A and A.Vendor and A.Vendor(r.i, false) or 0) * (r.c or 1)) }
        for _, st in ipairs(stretches) do
          local a, b = max(st[1], r.k), min(st[2], r.x)
          if b - a >= 5 then
            local c = Stretch(e, a, b)
            local save = c and st[3] and st[3] * (b - a) / (st[2] - st[1]) - c
            if c and (st[4] or (save and save > max(1500, c * 0.35))) then
              local f = { r = r, from = a, to = b, save = save, past = st[4], cost = c }
              local old = seen[r.s]
              if not old or (f.save or 0) > (old.save or 0) then seen[r.s] = f end
            end
          end
        end
      end
    end
    E.Yield()
  end
  for _, f in pairs(seen) do finds[#finds + 1] = f end
  table.sort(finds, function(a, b)
    if (a.past and true or false) ~= (b.past and true or false) then return a.past and true or false end
    if a.past then return a.cost < b.cost end
    return (a.save or 0) > (b.save or 0)
  end)
  while #finds > 8 do table.remove(finds) end
  return { segs = out, from = from, to = to, reach = reach, total = total, finds = finds }
end

local function Target(prof)
  local rank, cap = E.Skill(prof)
  rank, cap = rank or 1, cap or 75
  if K.target[prof] == 300 then return rank, 300 end
  local t = cap
  if rank >= cap then t = min(300, cap + 75) end
  return rank, max(t, 75)
end

function K.PlanRows(prof, info, rows)
  if info[3] == "gather" or prof == "Fishing" or not E.Data().recipes[prof] then
    rows[#rows + 1] = { t = "No recipes to plan with", d = prof .. " goes up by gathering: the Skill up page shows what and where.", still = true }
    return
  end
  local from, to = Target(prof)
  local learned = E.Skill(prof) ~= nil
  rows[#rows + 1] = { t = "Materials: " .. K.Basis()[2]:lower(), still = true, key = "planbasis", actLabel = "Change", act = function()
      for i, x in ipairs(K.BASES) do if x[1] == K.Basis()[1] then NS.cdb.craftBasis = K.BASES[i % #K.BASES + 1][1] break end end
      NS.Window.Refresh()
    end, d = ({ least = "Vendor, Auction House, making it or farming it: the least of them. An hour of farming counts as about " .. NS.Money(K.Rate() * 3600) .. " at your level.",
                self = "Vendors, what you make and what you farm: no Auction House.", buy = "Anything that can be bought is bought; the rest is farmed." })[K.Basis()[1]] }
  rows[#rows + 1] = { t = string.format("From %d to %d", from, to), still = true, key = "plantarget" .. prof, d = learned and "The cheapest recipes you know or a trainer teaches." or "As if you learned it now.",
                      actLabel = to == 300 and "Next rank" or "To 300", act = function() K.target[prof] = to ~= 300 and 300 or nil; NS.Window.Refresh() end }
  if from >= 300 or from >= to then
    rows[#rows + 1] = { t = "You're there", d = "Nothing left to plan.", still = true }
    return
  end
  local key = prof .. from .. ">" .. to .. K.Basis()[1] .. (NS.Auction and NS.Auction.Scanned and tostring(NS.Auction.Scanned()) or "")
  local pl = plans[prof]
  if not pl or pl.key ~= key then
    if not E.Busy("craft plan") then
      E.Job("craft plan", function() return K.Work(prof, from, to) end, function(res)
        plans[prof] = res
        if res then res.key = key end
        if NS.Window then NS.Window.Refresh() end
      end)
    end
    rows[#rows + 1] = { t = "Working it out...", still = true }
    return
  end
  local fees, ri, spent, rough = RankFees(prof, E.Skill(prof) and select(2, E.Skill(prof)) or 0, to), 1, 0, false
  local lvl = UnitLevel("player") or 1
  rows[#rows + 1] = { h = "Make, in this order" }
  local list = {}
  local function Rank()
    local f = fees[ri]
    local later = f.level and f.level > lvl
    rows[#rows + 1] = { t = "Learn " .. f.name, tex = I .. "INV_Misc_Book_09", still = true, ring = later and "warn" or nil,
                        d = string.format("Before skill %d%s%s", f.cap - 74, f.level and f.level > 0 and (later and string.format(". Needs level %d: you're %d", f.level, lvl) or ", needs level " .. f.level) or "",
                                          f.fee and f.fee > 0 and (", " .. NS.Money(f.fee)) or "") }
    spent = spent + (f.fee or 0)
    ri = ri + 1
  end
  local HOW = { trainer = "Learn it from a trainer", vendor = "Buy the recipe from a vendor", ah = "Buy the recipe at the Auction House" }
  for _, g in ipairs(pl.segs) do
    while fees[ri] and fees[ri].cap > 75 and fees[ri].cap - 75 <= g.from do Rank() end
    local r = g.r
    rough = rough or g.rough
    spent = spent + g.fee
    list[#list + 1] = { r = r, n = g.n }
    local d = P.Known(r) and "You know it." or r.st and "Known from the start." or g.fee == 0 and "Already learned in this plan."
      or ((HOW[g.how] or "Learn it") .. (g.fee > 0 and (", " .. NS.Money(g.fee)) or "") .. ".")
    if g.rough then d = d .. " |cff8f7d68A material is only guessed at.|r" end
    local alts = {}
    for k = 1, min(2, #g.alts) do
      local o = g.alts[k]
      alts[k] = o.r.n .. (o.more >= 100 and (" (" .. NS.Money(o.more) .. " more)") or " (about the same)")
    end
    if #alts > 0 then d = d .. "\n|cff8f7d68Or: " .. table.concat(alts, ", ") .. "|r" end
    rows[#rows + 1] = { t = string.format("%d to %d: about %dx %s", g.from, g.to, g.n, r.n), i = r.i, tex = not r.i and I .. "Trade_Engraving" or nil, q = r.q, key = "plan" .. r.s .. g.from,
                        page = function() return P.RecipePage(r) end, d = d, actLabel = "Add", act = function() K.Add(r.s, g.n) end }
    -- a step that runs over a rank's limit says so before the next step
    while fees[ri] and fees[ri].cap > 75 and fees[ri].cap - 75 < g.to do Rank() end
  end
  if pl.reach < to then
    rows[#rows + 1] = { t = string.format("Past %d, no trainer or vendor recipe raises it", pl.reach), d = "You'd have to find one: see below.", still = true, ring = "warn" }
  end
  local need, mid = K.Needs(list, false)
  if #mid > 0 then
    local bits = {}
    for _, m in ipairs(mid) do bits[#bits + 1] = string.format("%dx %s", m.n * (m.r.c or 1), m.r.n) end
    rows[#rows + 1] = { t = "Made on the way", d = table.concat(bits, ", ") .. ". (Making them can raise your skill too, so you may need a few less of the rest.)", still = true }
  end
  if #List(pl.finds) > 0 then
    rows[#rows + 1] = { h = "Worth finding" }
    for _, f in ipairs(pl.finds) do
      local r = f.r
      rows[#rows + 1] = { t = r.n .. string.format("  (%d to %d)", f.from, f.to), i = r.i, tex = not r.i and I .. "INV_Scroll_03" or nil, q = r.q, key = "find" .. r.s, page = function() return P.RecipePage(r) end,
                          d = (P.FromText and P.FromText(r) or "A recipe to find") .. (f.past and "\nGoes past where the trainers' recipes end." or f.save and ("\nWould save about " .. NS.Money(f.save) .. " there.") or "") }
    end
  end
  local buy, time, rough2 = MaterialRows(rows, need, prof, "plan")
  rough = rough or rough2
  rows[#rows + 1] = { t = K.Sum(buy + spent, time, rough), still = true, ring = "good",
                      d = string.format("%s of it in lessons and recipes.", NS.Money(spent)) .. (rough and " Some materials are only guessed at: an Auction House scan makes this better." or "")
                          .. "\n" .. K.OddsText() }
end

function K.OddsText()
  local bits = {}
  for _, c in ipairs({ "yellow", "green" }) do
    local v, yours = K.Odds(c)
    if yours then bits[#bits + 1] = string.format("%s %d%%", c, v * 100 + 0.5) end
  end
  if #bits > 0 then return "How often a craft raises your skill is from your own crafts: " .. table.concat(bits, ", ") .. "." end
  return "How often a craft raises your skill is Classic's (yellow 75%, green 25%) until Sunstone has seen enough of your own crafts."
end

-- your own crafts: did the skill go up? (The game says so in the skill list a moment later.)
local lastRank = {}
function K.Crafted(spell)
  local r = Recipe(spell)
  local rank, cap = nil, nil
  if r then rank, cap = E.Skill(r.prof) end
  local c = rank and P.Color(r, rank)
  if (c ~= "yellow" and c ~= "green") or (cap and rank >= cap) then return end
  lastRank[r.prof] = lastRank[r.prof] or rank
  local t = type(NS.db.craftOdds) == "table" and NS.db.craftOdds or {}
  NS.db.craftOdds = t
  t[c] = type(t[c]) == "table" and t[c] or { n = 0, up = 0 }
  t[c].n = (t[c].n or 0) + 1
  C_Timer.After(4, function()
    local now = E.Skill(r.prof)
    local was = lastRank[r.prof]
    if type(now) == "number" and was and now > was then
      t[c].up = min(t[c].n, (t[c].up or 0) + (now - was))
      lastRank[r.prof] = now
    end
  end)
end

---------------------------------------------------------------------------
-- Profit
---------------------------------------------------------------------------
local CUT = 0.95 -- the Auction House keeps 5%
-- -> { r, cost, rough, vendor (profit at a vendor), ah (profit at the Auction House), ahDays, makes }
function K.Profit(prof)
  local out, memo, unpriced = {}, { nofarm = true }, 0
  local skill = E.Skill(prof)
  local A = NS.Auction
  for _, r in ipairs(E.Data().recipes[prof] or {}) do
    r.prof = prof
    if r.i and (not r.sd or r.sd == E.Side()) and (P.Known(r) or r.st or not skill or (skill >= (r.k or 0) and not r.ri)) then
      local cost, rough = K.Cost(r, memo)
      if not cost or rough then
        unpriced = unpriced + 1
      else
        local n = r.c or 1
        local v = A and A.Vendor(r.i, true)
        local u = A and A.Usual and A.Usual(r.i)
        local e = { r = r, cost = cost, vendor = v and v * n - cost or nil, ah = u and u.usual and floor(u.usual * n * CUT) - cost or nil, days = u and u.days, avail = u and u.avail }
        e.best = max(e.vendor or -1e9, e.ah or -1e9)
        if e.best > 0 then out[#out + 1] = e end
      end
    end
    E.Yield()
  end
  table.sort(out, function(a, b) return a.best > b.best end)
  return out, unpriced
end

function K.ProfitRows(prof, info, rows)
  if info[3] == "gather" or not E.Data().recipes[prof] then
    rows[#rows + 1] = { t = "Nothing is made with " .. prof, d = "Gold, Farming spots shows what gathering brings.", still = true }
    return
  end
  local list, unpriced = K.Profit(prof)
  local vendor, ah = {}, {}
  for _, e in ipairs(list) do
    if e.vendor and e.vendor > 0 then vendor[#vendor + 1] = e end
    if e.ah and e.ah > max(0, e.vendor or 0) then ah[#ah + 1] = e end
  end
  table.sort(vendor, function(a, b) return a.vendor > b.vendor end)
  local function Row(e, gain, where)
    local r = e.r
    rows[#rows + 1] = { t = r.n .. "  |cff" .. NS.HEX.good .. "+" .. NS.Money(gain) .. "|r", i = r.i, q = r.q, key = "profit" .. where .. r.s, page = function() return P.RecipePage(r) end,
                        d = string.format("Materials %s%s", NS.Money(e.cost), P.Known(r) and "" or ", you haven't learned it")
                            .. (where == "ah" and string.format("\nUsually %s at the Auction House (%d scan%s%s)", NS.Money((e.ah + e.cost) / CUT / (r.c or 1)), e.days or 0, e.days == 1 and "" or "s",
                                                                e.avail and (", " .. e.avail .. " listed") or "") or "") }
  end
  if #vendor > 0 then
    rows[#rows + 1] = { h = "A vendor pays more than it costs (sure money)" }
    for k = 1, min(12, #vendor) do Row(vendor[k], vendor[k].vendor, "v") end
  end
  if #ah > 0 then
    rows[#rows + 1] = { h = "At the Auction House, by its usual price (after the 5% cut)" }
    for k = 1, min(20, #ah) do Row(ah[k], ah[k].ah, "ah") end
  end
  if #vendor + #ah == 0 then rows[#rows + 1] = { t = "Nothing seen that pays", d = "From the prices known so far. If you gather the materials yourself, they cost you only time.", still = true } end
  rows[#rows + 1] = { t = string.format("%d recipe%s left out", unpriced, unpriced == 1 and "" or "s"), dim = true, still = true,
                      d = "A material of theirs has no price seen yet. A scan at the Auction House (Sunstone's panel there) fills these in." }
end

function K:Init()
  NS.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spell)
    if unit == "player" and type(spell) == "number" and not (issecretvalue and issecretvalue(spell)) then NS.Safe("crafts", K.Crafted, spell) end
  end)
  NS.On("MERCHANT_SHOW", function() C_Timer.After(0.6, function() NS.Safe("crafting list", K.AtVendor) end) end)
end
