-- Sunstone: the Factions tab: rewards you earn with something other than gold.
--   Reputation: every faction with a quartermaster, your standing, what they sell at each rank and how to raise it.
--   Library Books: Forever's books to find around the world, and the reward tiers.
--   Honor: how Forever's PvP rewards work, your Honor and rank, what your battlegrounds have paid.
-- Data.lua, Questie, and what the recorder has seen. A rate nobody has measured is left unknown.

local _, NS = ...
local F = NS.Module("Factions")
NS.Factions2 = F
local E = NS.Engine

F.MODES = {
  { "rep", "Reputation", "Who sells you gear and recipes for standing with them" },
  { "books", "Library Books", "Books to find around the world; 10, 20 and 25 of them pay" },
  { "honor", "Honor", "PvP gear and ranks" },
}
function F.Mode()
  local m = NS.cdb and NS.cdb.factionMode
  for _, x in ipairs(F.MODES) do if x[1] == m then return x end end
  return F.MODES[1]
end

---------------------------------------------------------------------------
-- Reputation
---------------------------------------------------------------------------
-- quests that raise a faction, for this character: built once, in the background
local repQuests
function F.BuildRepQuests()
  local L = E.Lib()
  if repQuests or not L or not L.Quest.GetAllIds then return end
  E.Job("reputation quests", function()
    local want, out = {}, {}
    for _, f in ipairs(E.Data().factions) do want[f.id] = true end
    for _, qid in ipairs(L.Quest.GetAllIds()) do
      E.Yield()
      local rr = E.Q("Quest", qid, "reputationReward")
      if type(rr) == "table" then
        for _, p in pairs(rr) do
          if type(p) == "table" and want[p[1] or 0] and type(p[2]) == "number" and p[2] > 0 then
            out[p[1]] = out[p[1]] or {}
            table.insert(out[p[1]], { q = qid, n = p[2] })
          end
        end
      end
    end
    return out
  end, function(res)
    repQuests = res
    if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
  end)
end

local function QuestsFor(fid)
  local out, level = {}, UnitLevel("player")
  for _, e in ipairs(repQuests and repQuests[fid] or {}) do
    if not E.Done(e.q) and E.QuestReq(e.q) <= level and E.QuestOK(e.q) then
      local chain = E.Chain(e.q)
      if chain and #chain == 0 then
        local p, who = E.QuestStart(e.q)
        if p then out[#out + 1] = { q = e.q, n = e.n, p = p, who = who, mins = E.Minutes(p) } end
      end
    end
  end
  table.sort(out, function(a, b) return a.mins < b.mins end)
  return out
end

local function FactionPage(f)
  local rows = {}
  local st = NS.Standing(f.id)
  rows[1] = { t = (E.StandingText(f.id):gsub("^%l", string.upper)), d = "Standing goes Neutral, Friendly, Honored, Revered, Exalted." }
  for _, v in ipairs(E.Vendors(f.v, 3)) do
    rows[#rows + 1] = E.At({ t = "Quartermaster: " .. v.name, d = v.p and E.PlaceText(v.p) or "Where they stand isn't known yet." }, v.p)
  end
  local level = UnitLevel("player")
  for standing = 5, 8 do
    local n = 0
    for _, it in ipairs(f.i) do
      if it[3] == standing then
        n = n + 1
        if n == 1 then rows[#rows + 1] = { h = E.STANDING[standing] .. (st and (st >= standing and " (you can buy these)" or "") or "") } end
        if n <= 14 then
          local req = E.Q("Item", it[1], "requiredLevel")
          local price = E.VendorPrice(it[1])
          local bits = { it[4] == "gear" and "Gear" or it[4] == "recipe" and "Recipe" or "Item" }
          if type(req) == "number" and req > 1 then bits[#bits + 1] = "level " .. req .. (req > level and " (not yet)" or "") end
          if price then bits[#bits + 1] = NS.Money(price) end
          rows[#rows + 1] = { t = it[2], i = it[1], d = table.concat(bits, ", "), dim = not (st and st >= standing) or nil }
        end
      end
    end
  end
  rows[#rows + 1] = { h = "How to raise it" }
  local qs = QuestsFor(f.id)
  for k = 1, math.min(#qs, 10) do
    local q = qs[k]
    rows[#rows + 1] = E.At({ t = string.format("Quest: %s (+%d)", E.QuestName(q.q), q.n), d = "From " .. (q.who or "?") .. ", " .. E.PlaceText(q.p) }, q.p)
  end
  -- what the recorder has seen kills give
  local best = {}
  for id, m in pairs(NS.db and NS.db.rec and NS.db.rec.mobs or {}) do
    local r = type(m) == "table" and type(m.f) == "table" and m.f[f.id]
    if type(r) == "table" and (r.n or 0) > 0 and (r.g or 0) > 0 then best[#best + 1] = { id = id, per = r.g / r.n } end
  end
  table.sort(best, function(a, b) return a.per > b.per end)
  for k = 1, math.min(#best, 4) do
    local p = E.Nearest(E.Points("Npc", best[k].id))
    rows[#rows + 1] = E.At({ t = string.format("%s: about %d a kill", E.NpcName(best[k].id), math.floor(best[k].per + 0.5)), d = "Seen by your recorder." .. (p and (" " .. E.PlaceText(p)) or "") }, p)
  end
  if #qs == 0 and #best == 0 then
    rows[#rows + 1] = { t = E.Busy("reputation quests") and "Looking for quests that raise it..." or "No quest for it that you can take right now",
                        d = "Sunstone also records the reputation your kills give, and lists it here." }
  end
  return { title = f.n, icon = "Interface\\Icons\\INV_Jewelry_Ring_03", rows = rows, sub = "What they sell, and how to get there" }
end

local function RepRows()
  F.BuildRepQuests()
  local rows, list, level = {}, {}, UnitLevel("player")
  for _, f in ipairs(E.Data().factions) do
    if not f.side or f.side == E.Side() then
      local st, v = NS.Standing(f.id)
      local nxt, reach = nil, 99
      for _, it in ipairs(f.i) do
        if not (st and st >= it[3]) and (not nxt or it[3] < nxt[3] or (it[3] == nxt[3] and it[4] == "gear" and nxt[4] ~= "gear")) then nxt = it end
        if it[4] == "gear" then
          local req = E.Q("Item", it[1], "requiredLevel")
          if type(req) == "number" and req >= level - 5 then reach = math.min(reach, math.max(0, req - level)) end
        end
      end
      local vs = E.Vendors(f.v, 1)
      list[#list + 1] = { f = f, st = st, v = v or 0, nxt = nxt, reach = reach, far = vs[1] and vs[1].mins or 60 }
    end
  end
  table.sort(list, function(a, b) -- gear soonest for your level first, then who's nearest
    local ra, rb = a.reach <= 8 and 0 or 1, b.reach <= 8 and 0 or 1
    if ra ~= rb then return ra < rb end
    if ra == 0 and a.reach ~= b.reach then return a.reach < b.reach end
    return a.far < b.far
  end)
  for _, x in ipairs(list) do
    local d = (E.StandingText(x.f.id):gsub("^%l", string.upper))
    if x.nxt then d = d .. ". Next: " .. x.nxt[2] .. " at " .. E.STANDING[x.nxt[3]] end
    rows[#rows + 1] = { t = x.f.n, d = d, i = x.nxt and x.nxt[1], dim = not x.st or nil, key = "fac" .. x.f.id, page = function() return FactionPage(x.f) end }
  end
  return rows
end

---------------------------------------------------------------------------
-- Library Books
---------------------------------------------------------------------------
local function Territory(m)
  local t = E.Data().territory and E.Data().territory[m]
  return t
end

local function BooksState()
  local turned, missing, carried = 0, {}, 0
  for _, b in ipairs(E.Data().books) do
    if E.Done(b[1]) then turned = turned + 1
    elseif b[2] > 0 and E.Have(b[2]) > 0 then carried = carried + 1
    else
      local p = E.Point(b[4], b[5] / 100, b[6] / 100)
      local t = Territory(b[4])
      missing[#missing + 1] = { b = b, p = p, mins = p and E.Minutes(p) or 99, enemy = t and t ~= E.Side() }
    end
  end
  table.sort(missing, function(a, c)
    if (a.enemy and 1 or 0) ~= (c.enemy and 1 or 0) then return not a.enemy end
    return a.mins < c.mins
  end)
  return turned, missing, carried
end

function F.MissingBooks()
  local out = {}
  local _, missing = BooksState()
  for _, m in ipairs(missing) do
    local b = m.b
    out[#out + 1] = { m = b[4], x = b[5], y = b[6], n = b[3], where = b[7] or "", enemy = m.enemy or nil }
  end
  return out
end

local function BookPage(m)
  local b = m.b
  local rows = { E.At({ t = b[7] ~= "" and b[7] or "Where it is", d = (m.p and E.PlaceText(m.p) or "") .. (b[8] ~= "" and ("\n" .. b[8]) or "") }, m.p) }
  if m.enemy then rows[#rows + 1] = { t = "It's in the other faction's territory", d = "Guards there attack you." } end
  rows[#rows + 1] = { t = "Right-click the book to take it, then hand it to a librarian", i = b[2] > 0 and b[2] or nil }
  return { title = b[3], icon = "Interface\\Icons\\INV_Misc_Book_09", rows = rows, sub = "Library Book" }
end

local function BookRows()
  local rows = {}
  local turned, missing, carried = BooksState()
  rows[1] = { h = string.format("%d of %d turned in%s", turned, #E.Data().books, carried > 0 and string.format(", %d in your bags", carried) or "") }
  for _, t in ipairs(E.Data().tiers) do
    local need, done = t[1], E.Done(t[2])
    rows[#rows + 1] = { t = string.format("%d books%s", need, t[4] > 1 and (", level " .. t[4]) or ""), tex = "Interface\\Icons\\INV_Misc_Book_09", key = "tier" .. need,
                        d = done and "Claimed" or turned >= need and "Ready to claim at the librarian" or string.format("%d more", need - turned), hot = not done and turned >= need or nil,
                        dim = done or nil,
                        page = function()
                          local r = { { h = "Pick one of these" } }
                          for _, it in ipairs(t[5]) do r[#r + 1] = { t = it[2], i = it[1], d = it[3] } end
                          return { title = t[3], rows = r, icon = "Interface\\Icons\\INV_Misc_Book_09", sub = need .. " Library Books" }
                        end }
  end
  if #missing > 0 then rows[#rows + 1] = { h = "Books to find, nearest first" } end
  for _, m in ipairs(missing) do
    rows[#rows + 1] = { t = m.b[3], d = (m.enemy and "Enemy territory. " or "") .. (m.p and E.PlaceText(m.p) or m.b[7]), tex = "Interface\\Icons\\INV_Misc_Book_09",
                        dim = m.enemy or nil, key = "book" .. m.b[1], page = function() return BookPage(m) end }
  end
  return rows
end

---------------------------------------------------------------------------
-- Honor
---------------------------------------------------------------------------
-- Rank Points for each rank and what it gives: Blizzard's PvP post (7 Oct 2026) and the game's files via fan sites
local RANK_STEPS = { 750, 900, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2350, 2500, 2650, 3000 }
local RANK_GIVES = { "a tabard", "a PvP trinket", "cloaks", "a necklace", "combat potions", "a tabard", "a battle standard",
  "epic bracer and belt seals", "the epic boots seal", "the epic gloves seal", "mounts", "epic legs and shoulders seals", "epic chest and helm seals", "epic weapons" }
local BG = { [489] = "Warsong Gulch", [529] = "Arathi Basin", [30] = "Alterac Valley" }

local function Comma(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local function HowPage()
  local rows = {
    { t = "Honor is money", d = "You earn it from defeating players, battlegrounds and PvP quests. It buys a blue PvP set, and an epic set (the blue piece plus an Emboldened Seal that needs a PvP rank)." },
    { t = "Rank Points set your rank", d = "They're never spent. They come from battlegrounds, PvP quests and the tasks in Gadgetzan, and are capped each week. It's your own points, not a race against other players, so everyone can reach rank 14." },
    { t = "Where to spend it", d = E.Side() == "A" and "Stormwind's Champion's Hall in Old Town (76.0, 66.2)." or "Orgrimmar's Hall of Legends (40.6, 68.5)." },
    { h = "Ranks (points in all, reported by fan sites from the game's files)" },
  }
  local total = 0
  for i, s in ipairs(RANK_STEPS) do
    total = total + s
    rows[#rows + 1] = { t = string.format("Rank %d: %s", i, RANK_GIVES[i]), d = Comma(total) .. " Rank Points" }
  end
  return { title = "How PvP rewards work", icon = "Interface\\Icons\\INV_BannerPVP_01", rows = rows }
end

local function HonorRows()
  local rows = {}
  local h, rp = NS.Currency(1792), NS.Currency(3468)
  local rank = 0
  if rp then
    local total = 0
    for i, s in ipairs(RANK_STEPS) do total = total + s; if rp.quantity >= total then rank = i end end
  end
  rows[1] = { t = h and (Comma(h.quantity) .. " Honor") or "No Honor yet", d = rp and string.format("%s Rank Points (rank %d)", Comma(rp.quantity), rank) or nil,
              tex = "Interface\\Icons\\INV_BannerPVP_02", key = "honor", page = HowPage }
  rows[2] = { t = "How PvP rewards work", d = "Ranks, the weekly cap, where to spend it", tex = "Interface\\Icons\\INV_BannerPVP_01", key = "how", page = HowPage }
  local rec = NS.db and NS.db.rec and NS.db.rec.pvp
  local any = false
  for mid, e in pairs(type(rec) == "table" and rec or {}) do
    if type(e) == "table" and (e.n or 0) > 0 then
      if not any then rows[#rows + 1] = { h = "Your battlegrounds" } any = true end
      local bits = { string.format("%d min each", math.floor((e.m or 0) / e.n + 0.5)) }
      if (e.hn or 0) > 0 then bits[#bits + 1] = string.format("%d Honor", math.floor((e.h or 0) / e.hn + 0.5)) end
      if (e.rn or 0) > 0 then bits[#bits + 1] = string.format("%d Rank Points", math.floor((e.rp or 0) / e.rn + 0.5)) end
      rows[#rows + 1] = { t = string.format("%s: %d match%s", BG[mid] or ("Battleground " .. tostring(mid)), e.n, e.n == 1 and "" or "es"), d = table.concat(bits, ", "), tex = "Interface\\Icons\\INV_BannerPVP_02" }
    end
  end
  if not any then rows[#rows + 1] = { t = "No battleground timed yet", d = "Sunstone times each match and what it pays, then shows it here. Nobody has published those numbers." } end
  -- what the vendors you've opened sell for Honor
  local seen = {}
  for npc, v in pairs(NS.db and NS.db.rec and NS.db.rec.vend or {}) do
    for id, e in pairs(type(v) == "table" and type(v.i) == "table" and v.i or {}) do
      for _, x in ipairs(type(e) == "table" and type(e.x) == "table" and e.x or {}) do
        if x[1] == 1 and x[2] == 1792 and not seen[id] then seen[id] = { id = id, n = x[3], npc = npc } end
      end
    end
  end
  local list = {}
  for _, e in pairs(seen) do list[#list + 1] = e end
  table.sort(list, function(a, b) return a.n < b.n end)
  if #list > 0 then
    rows[#rows + 1] = { h = "Sold for Honor (prices your recorder saw)" }
    for k = 1, math.min(#list, 20) do rows[#rows + 1] = { t = E.ItemName(list[k].id), i = list[k].id, d = Comma(list[k].n) .. " Honor, " .. E.NpcName(list[k].npc) } end
  else
    rows[#rows + 1] = { t = "Prices show once you open a PvP vendor", d = "Sunstone reads the window when you do." }
  end
  return rows
end

function F.Rows()
  local m = F.Mode()[1]
  if m == "books" then return BookRows() elseif m == "honor" then return HonorRows() end
  return RepRows()
end
