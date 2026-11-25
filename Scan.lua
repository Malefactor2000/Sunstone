-- Sunstone: its own auction prices. Press Scan on the panel beside the auction house and it pages through everything listed
-- (the same list you get by searching for nothing), noting each item's cheapest price and how many there are. It also notes
-- prices from searches you make yourself. Kept per realm and side for about three weeks, so "usual" prices can be told from
-- one-off ones. Where Auctionator has a fresher price, that one is used (Auction.lua).
-- It only reads the list: it never bids, buys, posts or cancels, and it never scans unless you press Scan.

local _, NS = ...
local S = NS.Module("Scan")
NS.Scan = S

local floor, min, max = math.floor, math.min, math.max
local KEEP_DAYS, MAX_ITEMS = 21, 30000
local STUCK, LONGEST = 20, 300   -- seconds: no progress / longest scan
local TICK = 0.25

function S.Today() return floor(time() / 86400) end

local function Realm()
  if not NS.db then return nil end
  NS.db.ahp = type(NS.db.ahp) == "table" and NS.db.ahp or {}
  local key = (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
  local t = NS.db.ahp[key]
  if type(t) ~= "table" then
    t = { items = {} }
    NS.db.ahp[key] = t
  end
  t.items = type(t.items) == "table" and t.items or {}
  return t
end
S.Realm = Realm

-- one item: "day,price,listed;day,low,high;day,low,high..." (newest day first)
local cache = {}
local function Parse(s)
  local head, rest = s:match("^([^;]+);?(.*)$")
  if not head then return nil end
  local d, p, q = head:match("^(%d+),(%d+),(%d+)$")
  if not d then return nil end
  local e = { day = tonumber(d), price = tonumber(p), listed = tonumber(q), hist = {} }
  for a, lo, hi in rest:gmatch("(%d+),(%d+),(%d+)") do
    e.hist[#e.hist + 1] = { day = tonumber(a), lo = tonumber(lo), hi = tonumber(hi) }
  end
  return e
end

function S.Get(id)
  local e = cache[id]
  if e then return e end
  local t = Realm()
  local s = t and t.items[id]
  if type(s) ~= "string" then return nil end
  e = Parse(s)
  cache[id] = e
  return e
end

local function Store(id, e)
  local parts = { string.format("%d,%d,%d", e.day, e.price, e.listed) }
  local oldest = S.Today() - KEEP_DAYS
  for _, h in ipairs(e.hist) do
    if h.day >= oldest then parts[#parts + 1] = string.format("%d,%d,%d", h.day, h.lo, h.hi) end
  end
  Realm().items[id] = table.concat(parts, ";")
  cache[id] = e
end

-- A price seen just now. first: the first time this scan or search (the cheapest then replaces what was known);
-- otherwise the cheaper of the two, and the numbers add up.
function S.Note(id, price, listed, first)
  if type(id) ~= "number" or id <= 0 or type(price) ~= "number" or price <= 0 then return end
  price, listed = floor(price), floor(type(listed) == "number" and listed or 1)
  local today = S.Today()
  local e = S.Get(id) or { hist = {} }
  if first or not e.price then
    e.price, e.listed = price, listed
  else
    e.price, e.listed = min(e.price, price), e.listed + listed
  end
  e.day = today
  local h = e.hist[1]
  if h and h.day == today then
    h.lo, h.hi = min(h.lo, e.price), max(h.hi, e.price)
  else
    table.insert(e.hist, 1, { day = today, lo = e.price, hi = e.price })
  end
  Store(id, e)
end

-- -> price, age in days, how many were listed
function S.Price(id)
  local e = type(id) == "number" and S.Get(id)
  if not e or not e.price then return nil end
  return e.price, max(0, S.Today() - e.day), e.listed
end

-- every item known: fn(id, price, age, listed)
function S.Each(fn)
  local t = Realm()
  if not t then return end
  for id in pairs(t.items) do
    local p, age, n = S.Price(id)
    if p then fn(id, p, age, n) end
  end
end

-- the middle of the daily prices over the days remembered -> usual, lowest, highest, days
function S.Usual(id)
  local e = type(id) == "number" and S.Get(id)
  if not e or #e.hist == 0 then return nil end
  local prices = {}
  for _, h in ipairs(e.hist) do prices[#prices + 1] = (h.lo + h.hi) / 2 end
  table.sort(prices)
  local n = #prices
  local mid = n % 2 == 1 and prices[(n + 1) / 2] or (prices[n / 2] + prices[n / 2 + 1]) / 2
  return mid, floor(prices[1]), floor(prices[n]), n
end

function S.Count()
  local t, n = Realm(), 0
  if t then for _ in pairs(t.items) do n = n + 1 end end
  return n
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
local run            -- { t0, last, n, total, seen = { [itemID] = true } }
local ticker

function S.Can() return C_AuctionHouse ~= nil and C_AuctionHouse.SendBrowseQuery ~= nil and C_AuctionHouse.GetBrowseResults ~= nil end
function S.Running() return run ~= nil end
function S.Progress() return run and run.n or 0 end

local function Take(results, from, seen)
  local n = 0
  for i = from, #results do
    local r = results[i]
    local key = type(r) == "table" and r.itemKey
    local id = type(key) == "table" and key.itemID
    if type(id) == "number" then
      S.Note(id, r.minPrice, r.totalQuantity, not seen[id])
      if type(r.minPrice) == "number" and r.minPrice > 0 then seen[id] = true end
      n = n + 1
    end
  end
  return n
end

local function Full()
  local f = C_AuctionHouse.HasFullBrowseResults
  local ok, v = pcall(f)
  return f ~= nil and ok and v == true
end

local function Ready()
  local f = C_AuctionHouse.IsThrottledMessageSystemReady
  if not f then return true end
  local ok, v = pcall(f)
  return not ok or v == true
end

local function Stop(why)
  if not run then return end
  local r = run
  run = nil
  if ticker then ticker:Cancel(); ticker = nil end
  local full = why == "done"
  if full then Realm().scanned = time() end
  S.lastWhy = why
  if NS.Auction then
    if r.n > 0 then NS.Auction.MarkScanned() end
    NS.Safe("auction", NS.Auction.Update)
  end
  if full then
    NS.Print(string.format("scan done: %d listings read in %d seconds.", r.n, floor(GetTime() - r.t0 + 0.5)))
  elseif r.n > 0 then
    NS.Print(string.format("scan stopped after %d listings (%s). What it read is kept.", r.n, why))
  else
    NS.Print("the scan didn't start (" .. why .. "). Try again in a moment.")
  end
end
S.Stop = Stop

local function Tick()
  if not run then return end
  local now = GetTime()
  if NS.Flips and NS.Flips.AtAuctionHouse and not NS.Flips.AtAuctionHouse() then return Stop("the auction house closed") end
  if now - run.t0 > LONGEST then return Stop("it took too long") end
  if not run.sent then
    if not Ready() then
      if now - run.t0 > STUCK then Stop("the auction house is busy") end
      return
    end
    run.sent, run.last = true, now
    local ok = pcall(C_AuctionHouse.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    if not ok then Stop("the auction house refused the search") end
    return
  end
  if run.got and Full() then return Stop("done") end
  if now - run.last > STUCK then return Stop("no more answers") end
  if run.got and Ready() and C_AuctionHouse.RequestMoreBrowseResults and now - (run.asked or 0) > TICK then
    run.asked = now
    pcall(C_AuctionHouse.RequestMoreBrowseResults)
  end
end
S.Tick = Tick

function S.Start()
  if not S.Can() then NS.Print("this client's auction house can't be read.") return false end
  if NS.Flips and NS.Flips.AtAuctionHouse and not NS.Flips.AtAuctionHouse() then NS.Print("open the auction house first.") return false end
  if run then return true end
  run = { t0 = GetTime(), last = GetTime(), n = 0, seen = {} }
  ticker = C_Timer.NewTicker(TICK, function() NS.Safe("auction scan", Tick) end)
  NS.Safe("auction scan", Tick)
  return true
end

local browse = { n = 0, seen = {} }  -- a search of your own
local function Updated()
  local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
  if not ok or type(results) ~= "table" then return end
  if run then
    if not run.sent then return end
    if run.got and #results < run.n then return Stop("you searched for something") end
    run.got = true
    local had = run.n
    Take(results, had + 1, run.seen)
    run.n = #results
    if run.n > had then run.last = GetTime() end
    if NS.Flips then NS.Debounce("scan-progress", 0.5, NS.Flips.Render) end
    return
  end
  browse = { n = #results, seen = {} }
  Take(results, 1, browse.seen)
  if #results > 0 then NS.Debounce("scan-update", 3, function() if NS.Auction then NS.Auction.Update() end end) end
end

local function Added(added)
  if type(added) ~= "table" then return end
  if run then
    if not run.sent then return end
    Take(added, 1, run.seen)
    run.n, run.got, run.last = run.n + #added, true, GetTime()
    if NS.Flips then NS.Debounce("scan-progress", 0.5, NS.Flips.Render) end
    return
  end
  Take(added, 1, browse.seen)
  browse.n = browse.n + #added
end

-- one item's own page: its cheapest listing
local function Commodity(id)
  if type(id) ~= "number" or not C_AuctionHouse.GetCommoditySearchResultInfo then return end
  local ok, r = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, id, 1)
  if ok and type(r) == "table" then
    local e = S.Get(id)
    S.Note(id, r.unitPrice, e and e.day == S.Today() and e.listed or r.quantity, true)
  end
end

local function Prune()
  local db = NS.db and NS.db.ahp
  if type(db) ~= "table" then return end
  local oldest = S.Today() - KEEP_DAYS
  for _, t in pairs(db) do
    local n = 0
    for id, s in pairs(type(t) == "table" and type(t.items) == "table" and t.items or {}) do
      local d = type(s) == "string" and tonumber(s:match("^(%d+),"))
      n = n + 1
      if not d or d < oldest or n > MAX_ITEMS then t.items[id] = nil end
    end
  end
end

function S:Init()
  if not S.Can() then return end
  NS.Safe("auction prices", Prune)
  NS.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", Updated)
  NS.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", Added)
  NS.On("AUCTION_HOUSE_BROWSE_FAILURE", function() if run then Stop("the auction house didn't answer") end end)
  NS.On("COMMODITY_SEARCH_RESULTS_UPDATED", Commodity)
end
