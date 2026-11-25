-- Sunstone: auction house prices, from its own scan (Scan.lua) and from Auctionator's, whichever is fresher.
-- After a scan this works out:
--   * vendor flips: items listed for less than a vendor pays for them (buy, then sell to any vendor);
--   * what the things you carry and the drops the recorder has seen are worth on the auction house,
--     so the helper can tell you what to post and what to vendor, and value farming by real prices.
-- Auctionator's prices come through its public API; the flip search also reads its price list
-- (guarded: if Auctionator changes it, only that part stops). Everything stays in your
-- SavedVariables for the desktop helper. The flip panel beside the auction house is Flips.lua;
-- "/sun flips" opens it there, or prints the best flips anywhere else.
-- Reading prices only: nothing here buys, sells or posts. That is always your own click.

local _, NS = ...
local A = NS.Module("Auction")
NS.Auction = A

A.CALLER = "Sunstone"
local CALLER = A.CALLER
local MAX_SAVED, MAX_KEPT, MAX_PRICES = 40, 300, 3000
local MAX_REQUESTS = 300   -- item lookups asked of the server per pass (the rest wait for the next pass)
local MAX_AGE = 1          -- days: a listing older than yesterday's scan has most likely sold
local MIN_GAIN = 2         -- copper per item: less isn't worth the walk to a vendor

local function Api()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end
A.Api = Api

local function TheirPrice(id)
  local api = Api()
  if not api or type(id) ~= "number" then return nil end
  local ok, p = pcall(api.GetAuctionPriceByItemID, CALLER, id)
  return ok and type(p) == "number" and p > 0 and p or nil
end

local function TheirAge(id)
  local api = Api()
  if not api then return nil end
  local ok, d = pcall(api.GetAuctionAgeByItemID, CALLER, id)
  return ok and type(d) == "number" and d or nil
end

-- The freshest price known -> price, age in days, how many were listed (Sunstone's scan only), whose
function A.Latest(id)
  local p, age, n
  if NS.Scan then p, age, n = NS.Scan.Price(id) end
  local q = TheirPrice(id)
  local qAge = q and TheirAge(id)
  if q and (not p or (qAge or 99) < (age or 99)) then return q, qAge, nil, "Auctionator" end
  if p then return p, age, n, "Sunstone" end
end
function A.Price(id) return (A.Latest(id)) end
function A.Age(id)
  local _, age = A.Latest(id)
  return age
end
-- can prices be read at all (our own scan, or Auctionator)?
function A.Any() return Api() ~= nil or (NS.Scan ~= nil and NS.Scan.Can()) end

-- Only ask the game for an item's details when it already has them: asking about thousands of unknown
-- items at once floods the server, so those are looked up a few hundred at a time instead.
local function Cached(id)
  local f = C_Item and C_Item.IsItemDataCachedByID
  if not f then return true end
  local ok, v = pcall(f, id)
  return not ok or v == true
end

A.asked, A.noInfo = {}, {}
local requested = 0

-- What a vendor pays you: the game's item info, else the recorder's note of it.
-- (NOT Auctionator's "vendor price": that is what a merchant charges, often several times more.)
-- nil = not known yet (looked up in the background unless `lookup` is false).
function A.Vendor(id, lookup)
  if Cached(id) then
    local price = select(11, NS.GetItemInfo(id))
    if type(price) == "number" then return price end
  end
  local rec = NS.db.rec and NS.db.rec.sell
  if rec and type(rec[id]) == "number" then return rec[id] end
  if lookup ~= false and not A.asked[id] and requested < MAX_REQUESTS
     and C_Item and C_Item.RequestLoadItemDataByID then
    requested = requested + 1
    A.asked[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id) -- known next pass
  end
end

-- Auctionator's price list for this realm (its own table; read only).
function A.PriceList()
  local db = Auctionator and Auctionator.Database and Auctionator.Database.db
  return type(db) == "table" and db or nil
end

-- What an item has usually been listed for over Auctionator's remembered scans (about three weeks): the middle of the
-- daily lows, the lowest and highest, how many days it was seen, today's price (if recent) and how many were listed.
-- Auctionator doesn't know what sold, so "seen on several scans at a steady price" is the best sign there is.
local RECENT = 3 -- days: an older "last price" isn't today's price
local function TheirUsual(id)
  local db = A.PriceList()
  local d = db and type(id) == "number" and db[tostring(id)]
  if type(d) ~= "table" or type(d.h) ~= "table" then return nil end
  local prices, newest = {}, nil
  for day, h in pairs(d.h) do
    if type(h) == "number" and h > 0 then
      local l = type(d.l) == "table" and d.l[day]
      prices[#prices + 1] = (type(l) == "number" and l > 0) and (l + h) / 2 or h
      local n = tonumber(day)
      if n and (not newest or n > newest) then newest = n end
    end
  end
  if #prices == 0 then return nil end
  table.sort(prices)
  local mid = (#prices % 2 == 1) and prices[(#prices + 1) / 2] or (prices[#prices / 2] + prices[#prices / 2 + 1]) / 2
  local age = TheirAge(id)
  local avail = newest and type(d.a) == "table" and d.a[tostring(newest)]
  return { usual = mid, lo = math.floor(prices[1]), hi = math.floor(prices[#prices]), days = #prices, age = age,
           now = age and age <= RECENT and type(d.m) == "number" and d.m > 0 and d.m or nil, avail = type(avail) == "number" and avail or nil }
end

function A.Usual(id)
  local theirs = TheirUsual(id)
  local S = NS.Scan
  local mid, lo, hi, days
  if S then mid, lo, hi, days = S.Usual(id) end
  if not mid or (theirs and theirs.days > days) then
    local p, age, n, who = A.Latest(id) -- their days, our price if it's the fresher one
    if theirs and who == "Sunstone" then theirs.age, theirs.now, theirs.avail = age, age <= RECENT and p or nil, n end
    return theirs
  end
  local p, age, n = A.Latest(id)
  return { usual = mid, lo = lo, hi = hi, days = days, age = age, now = age and age <= RECENT and p or nil, avail = n or (theirs and theirs.avail) }
end

-- Every priced item: fn(id, price, age in days, how many were listed)
function A.Each(fn)
  local done = {}
  if NS.Scan then
    NS.Scan.Each(function(id)
      local p, age, n = A.Latest(id)
      done[id] = true
      if p then fn(id, p, age, n) end
    end)
  end
  local n = 0
  for key, data in pairs(A.PriceList() or {}) do
    local id = type(key) == "string" and key:match("^%d+$") and tonumber(key)
    if id and not done[id] and type(data) == "table" and type(data.m) == "number" and data.m > 0 then
      local avail
      if type(data.a) == "table" then
        for _, c in pairs(data.a) do if type(c) == "number" then avail = math.max(avail or 0, c) end end
      end
      fn(id, data.m, TheirAge(id), avail)
      n = n + 1
      if n > 80000 then break end
    end
  end
end

-- Every item listed for less than a vendor pays, from the latest scans (today's or yesterday's).
-- Returns the flips (best first), how many priced items were checked, and how many still await a vendor price.
function A.Flips()
  if not A.Any() then return {}, 0, 0 end
  local out, seen, waiting = {}, 0, 0
  requested = 0
  A.Each(function(id, price, age, avail)
    seen = seen + 1
    if age and age <= MAX_AGE then -- stale prices first: no point looking up what a vendor pays for those
      local sell = A.Vendor(id)
      if sell == nil then
        if not A.noInfo[id] then waiting = waiting + 1 end
      elseif sell - price >= MIN_GAIN then
        out[#out + 1] = { id = id, buy = price, sell = sell, gain = sell - price, age = age, avail = avail }
      end
    end
  end)
  table.sort(out, function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.id < b.id end)
  while #out > MAX_KEPT do table.remove(out) end
  return out, seen, waiting
end

-- The flips your money covers, best first, and a shopping plan: one of each from the top down while the money lasts.
-- (Only the cheapest listing of each is known to be under the vendor price until you search it.)
function A.Plan(flips, money)
  money = money or 0
  local fits, over, spend, back, n = {}, {}, 0, 0, 0
  for _, f in ipairs(flips or {}) do
    if f.buy <= money then fits[#fits + 1] = f else over[#over + 1] = f end
  end
  for _, f in ipairs(fits) do
    f.planned = spend + f.buy <= money
    if f.planned then spend, back, n = spend + f.buy, back + f.sell, n + 1 end
  end
  return fits, over, { count = n, spend = spend, back = back, gain = back - spend }
end

-- Auction prices of what matters to the helper: your bags and the drops the recorder has seen.
function A.Prices()
  local ids, out, n = {}, {}, 0
  local snap = NS.db.snapshots and NS.db.snapshots[NS.CharKey()]
  for _, b in ipairs(snap and snap.bags or {}) do if type(b.id) == "number" then ids[b.id] = true end end
  local rec = NS.db.rec
  for _, m in pairs(rec and rec.mobs or {}) do
    for id in pairs(m.i or {}) do ids[id] = true end
    for id in pairs(m.sk or {}) do ids[id] = true end
  end
  for id in pairs(ids) do
    local p = A.Price(id)
    if p then
      out[id] = { p, A.Age(id) or 99, A.Vendor(id, false) }
      n = n + 1
      if n >= MAX_PRICES then break end
    end
  end
  return out
end

function A.RealmKey() return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?") end

function A.Update()
  if not A.Any() then return end
  NS.db.ah = NS.db.ah or {}
  local flips, seen, waiting = A.Flips()
  A.flips, A.seen, A.waiting, A.asking = flips, seen, waiting, requested
  local saved = {}
  for i = 1, math.min(MAX_SAVED, #flips) do
    local f = flips[i]
    saved[i] = { id = f.id, buy = f.buy, sell = f.sell, gain = f.gain, age = f.age, avail = f.avail }
  end
  local key = A.RealmKey()
  local old = NS.db.ah[key]
  NS.db.ah[key] = { t = time(), items = seen, flips = saved, prices = A.Prices(),
                    scanned = old and old.scanned, money = GetMoney() }
  A.updated = GetTime()
  if NS.Flips and NS.Flips.Render then NS.Safe("flips", NS.Flips.Render) end
end

-- When prices were last taken in on this realm (a scan, or browsing the auction house).
function A.Scanned()
  local data = NS.db.ah and NS.db.ah[A.RealmKey()]
  return data and data.scanned
end
function A.MarkScanned()
  NS.db.ah = NS.db.ah or {}
  local key = A.RealmKey()
  NS.db.ah[key] = NS.db.ah[key] or { t = time(), items = 0, flips = {}, prices = {} }
  NS.db.ah[key].scanned = time()
end

function A.Print()
  if not A.Any() then NS.Print("this client's auction house can't be read, and Auctionator isn't loaded.") return end
  A.Update()
  local flips, seen = A.flips or {}, A.seen or 0
  if seen == 0 then
    NS.Print("no auction prices for this realm yet. At the auction house, press Scan on Sunstone's panel, then try again.")
    return
  end
  if #flips == 0 then
    NS.Print(string.format("nothing is listed below its vendor price right now (%d priced items checked). "
      .. "Cheap listings come and go: scan again later.", seen))
    return
  end
  local money = GetMoney()
  local fits, over, plan = A.Plan(flips, money)
  NS.Print(string.format("vendor flips you can afford with %s (buy on the auction house, sell to any vendor; %d priced items checked):",
    NS.Money(money), seen))
  for i = 1, math.min(10, #fits) do
    local f = fits[i]
    local name = NS.GetItemInfo(f.id) or ("item " .. f.id)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: buy under %s (cheapest %s)  |cff8aa666+%s each|r%s",
      name, NS.Money(f.sell), NS.Money(f.buy), NS.Money(f.gain),
      f.avail and ("  |cff8f7d68(" .. f.avail .. " listed)|r") or ""))
  end
  if #fits == 0 then
    NS.Print(string.format("%d flips found, but each costs more than the %s you carry.", #over, NS.Money(money)))
  elseif plan.count > 0 then
    NS.Print(string.format("one of each of the top %d costs %s and a vendor pays %s (+%s).",
      plan.count, NS.Money(plan.spend), NS.Money(plan.back), NS.Money(plan.gain)))
  end
  NS.Print("prices move fast: check the listing before you buy.")
end

function A:Init()
  -- after an auction house visit (Auctionator scans while it's open) and before a sync
  NS.On("AUCTION_HOUSE_CLOSED", function() C_Timer.After(1, function() NS.Safe("auction", A.Update) end) end)
  C_Timer.After(20, function() NS.Safe("auction", A.Update) end)
end

NS.Command("flips", "- items on the auction house that a vendor pays more for (the panel opens beside the auction house)", function()
  if NS.Flips and NS.Flips.AtAuctionHouse and NS.Flips.AtAuctionHouse() then
    NS.Flips.Show(true)
  else
    A.Print()
  end
end)
