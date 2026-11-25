-- Sunstone: the XP, Grind and Gold tabs, worked out in the game (Engine.lua) for whoever you're playing, from level 1.

local _, NS = ...
local L = NS.Module("Lists")
NS.Lists = L
local E = NS.Engine

local STALE = 300 -- seconds before a list is worked out again when you look at it
local MOVED = 600 -- yards you can walk before the distances are redone

local function Comma(n)
  n = math.floor(n + 0.5)
  return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function Redraw() if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end end

-- is this list still right? (level, age, where you are)
local function Fresh(c)
  if not c or c.level ~= UnitLevel("player") or time() - c.t > STALE then return false end
  local y = c.from and E.Yards(c.from)
  return not y or y <= MOVED
end

local function Need(key, find)
  local c = E.cache[key]
  if not Fresh(c) and not E.Busy(key == "xp" and "xp quests" or "grind spots") then
    find(function(res)
      res.from = E.Here()
      Redraw()
    end)
  end
  return c
end

local function NoData(rows)
  if not E.Lib() then
    rows[#rows + 1] = { t = "The quest database didn't load", d = "Sunstone's QuestData.lua is missing: install the addon again.", still = true }
    return true
  end
end

---------------------------------------------------------------------------
-- XP
---------------------------------------------------------------------------
local function QuestPage(r)
  local rows = {}
  rows[1] = not r.xp and { t = "Its XP isn't known yet", d = "Nobody has recorded it. Sunstone will when you hand it in." }
    or E.At({ t = string.format("%s XP, about %d min", Comma(r.xp), math.floor(r.mins + 0.5)), d = string.format("Level %d quest. %.0f XP a minute, walking there and back included.", r.level, r.rate) }, r.p)
  if r.inLog then rows[#rows + 1] = { t = "It's in your quest log" }
  elseif r.p then rows[#rows + 1] = E.At({ t = "Pick it up from " .. (r.who or "?"), d = E.PlaceText(r.p) }, r.p) end
  if r.elite then rows[#rows + 1] = { t = "Elite creatures", d = "May need a group." } end
  local text = E.Q("Quest", r.id, "objectivesText")
  if type(text) == "table" and type(text[1]) == "string" then rows[#rows + 1] = { h = "What to do" }; rows[#rows + 1] = { t = NS.Clean(table.concat(text, " "), 400) } end
  local spots = E.ObjectiveSpots(r.id)
  for i, pts in ipairs(spots) do
    local c = E.Centroid(pts)
    if c and i <= 4 then rows[#rows + 1] = E.At({ t = "Objective " .. i, d = "Around " .. E.PlaceText(c) }, c) end
  end
  local fin = E.Q("Quest", r.id, "finishedBy")
  for _, id in pairs(type(fin) == "table" and type(fin[1]) == "table" and fin[1] or {}) do
    local p = E.Nearest(E.Points("Npc", id))
    rows[#rows + 1] = E.At({ t = "Hand it in to " .. E.NpcName(id), d = p and E.PlaceText(p) or nil }, p)
    break
  end
  -- gear it gives
  local any
  for _, e in ipairs(NS.Upgrades and NS.Upgrades.all or {}) do
    for _, q in ipairs(e.quests or {}) do
      if q.id == r.id then
        if not any then rows[#rows + 1] = { h = "Upgrades it gives you" } any = true end
        rows[#rows + 1] = { t = e.name, i = e.id, q = e.quality, d = string.format("%s, +%.1f", e.slot, e.gain) }
      end
    end
  end
  if NS.QuestFind then rows[#rows + 1] = { t = "Its map, chain and rewards", tex = "Interface\\Icons\\INV_Misc_Note_01", page = function() return NS.QuestFind.Page(r.id) end } end
  return { title = r.name, icon = "Interface\\Icons\\INV_Scroll_03", rows = rows }
end

L.QuestPage = QuestPage
L.bundle = {}
function L.XPRows()
  local rows = {}
  if NoData(rows) then return rows end
  local c = Need("xp", E.FindQuests)
  if not c then
    return { { t = "Looking for quests near you...", d = "A few seconds the first time.", dim = true, key = "status" } }
  end
  local bundle = E.QuestBundle(c.rows)
  L.bundle = {}
  local inSet = {}
  for _, r in ipairs(bundle) do L.bundle[#L.bundle + 1] = r.id; inSet[r.id] = true end
  local function Row(r)
    return { t = string.format("%s (%d)", r.name, r.level), key = "quest" .. r.id, tex = "Interface\\Icons\\INV_Scroll_03",
             d = string.format("%s XP, about %d min%s", Comma(r.xp), math.floor(r.mins + 0.5), r.inLog and ", in your log" or r.elite and ", elite" or ""), page = function() return QuestPage(r) end }
  end
  if #bundle >= 2 then
    rows[#rows + 1] = { h = string.format("%d quests close together (Add set to route)", #bundle) }
    for _, r in ipairs(bundle) do rows[#rows + 1] = Row(r) end
  end
  local mine, rest = {}, {}
  for _, r in ipairs(c.rows) do
    if r.inLog then mine[#mine + 1] = r elseif not (inSet[r.id] and #bundle >= 2) then rest[#rest + 1] = r end
  end
  if #mine > 0 then
    rows[#rows + 1] = { h = "In your quest log, best XP for the time first" }
    for k = 1, math.min(#mine, 10) do rows[#rows + 1] = Row(mine[k]) end
  end
  if #rest > 0 then
    rows[#rows + 1] = { h = "More quests you can pick up" }
    for k = 1, math.min(#rest, 14) do rows[#rows + 1] = Row(rest[k]) end
  end
  if c.other and #c.other > 0 then
    rows[#rows + 1] = { h = "Near you, XP not recorded yet" }
    for k = 1, math.min(#c.other, 10) do
      local r = c.other[k]
      rows[#rows + 1] = { t = string.format("%s (%d)", r.name, r.level), key = "quest" .. r.id, tex = "Interface\\Icons\\INV_Scroll_03",
                          d = "From " .. (r.who or "?") .. ", " .. E.Far(r.p) .. (r.elite and ", elite" or ""), page = function() return QuestPage(r) end }
    end
  end
  if #rows == 0 then rows[1] = { t = "No quests for your level within reach", d = "Within about 25 minutes of you. Try again in another zone." } end
  return rows
end

---------------------------------------------------------------------------
-- Grind
---------------------------------------------------------------------------
local function CampPage(r)
  local rows = { E.At({ t = E.Where(r.p), d = string.format("%s\nAbout %s XP an hour before rested XP, %d spawns around here.", (E.Far(r.p):gsub("^%l", string.upper)), Comma(r.xph), r.n) }, r.p) }
  if r.gph then rows[#rows + 1] = { t = "About " .. NS.Money(math.floor(r.gph)) .. " an hour", d = "From what your recorder has seen these creatures drop." } end
  rows[#rows + 1] = { h = "What's here" }
  for i, m in ipairs(r.mobs) do
    if i > 8 then break end
    local p = E.Nearest(E.Points("Npc", m.id))
    local g = E.GoldPerKill(m.id)
    rows[#rows + 1] = E.At({ t = string.format("%s (%d%s)", E.NpcName(m.id), m.lo, m.hi ~= m.lo and ("-" .. m.hi) or ""),
                             d = string.format("%d spawns here%s", m.n, g and (", about " .. NS.Money(math.floor(g)) .. " a corpse") or ""),
                             tex = "Interface\\Icons\\INV_Misc_Bone_Skull_02", page = function() return NS.Farm.CreaturePage(m.id) end }, p)
  end
  return { title = "Grind spot", icon = "Interface\\Icons\\INV_Sword_04", rows = rows, sub = "Solo, creatures within 2 levels of you" }
end

function L.GrindRows()
  local rows = {}
  if NoData(rows) then return rows end
  local c = Need("camps", E.FindCamps)
  if not c then return { { t = "Looking for creatures at your level...", d = "A few seconds the first time.", dim = true, key = "status" } } end
  for k = 1, math.min(#c.rows, 14) do
    local r = c.rows[k]
    local names = {}
    for i = 1, math.min(#r.mobs, 3) do names[i] = E.NpcName(r.mobs[i].id) end
    rows[#rows + 1] = { t = table.concat(names, ", "), tex = "Interface\\Icons\\INV_Sword_04", key = "camp" .. k,
                        d = string.format("About %s XP an hour%s  ·  %s", Comma(r.xph), r.gph and (", " .. NS.Money(math.floor(r.gph))) or "", E.Far(r.p)), page = function() return CampPage(r) end }
  end
  if #rows == 0 then rows[1] = { t = "No good spot within reach", d = "Nothing at your level within about 30 minutes of you." } end
  return rows
end

---------------------------------------------------------------------------
-- Gold
---------------------------------------------------------------------------
L.GOLD = {
  { "farm", "Ways to make gold", "What to farm, flip and sell" },
  { "bags", "Your bags", "Can I sell this?" },
}
function L.GoldMode()
  local m = NS.cdb and NS.cdb.goldMode
  for _, x in ipairs(L.GOLD) do if x[1] == m then return x end end
  return L.GOLD[1]
end

function L.GoldRows()
  if L.GoldMode()[1] == "bags" and NS.Sell then return NS.Sell.Rows() end
  local rows = {}
  -- 0. what to farm: drop rates, what things sell for, and how easy the creatures are for you (Farm.lua)
  if E.Lib() then
    local c = E.cache.farm
    if not Fresh(c) and not E.Busy("farm spots") and not E.Busy("drop rates") then NS.Farm.Find(Redraw) end
    if not c then rows[1] = { t = "Working out what to farm...", d = "A few seconds the first time.", dim = true, key = "status", still = true } end
    NS.Farm.Rows(rows, c)
  end
  -- 1. vendor flips from the last auction scan
  local A = NS.Auction
  local flips = A and A.Flips and select(1, A.Flips()) or {}
  if #flips > 0 then
    rows[#rows + 1] = { h = "Auction House flips: a vendor pays more" }
    for k = 1, math.min(#flips, 6) do
      local f = flips[k]
      rows[#rows + 1] = { t = string.format("%s: +%s each", E.ItemName(f.id), NS.Money(f.gain)), i = f.id, key = "flip" .. f.id,
                          d = string.format("Buy %s, vendor pays %s", NS.Money(f.buy), NS.Money(f.sell)) }
    end
  end
  -- 2. in your bags: worth more on the auction house
  local bags, seen = {}, {}
  for bag = 0, 4 do
    local n = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots or function() return 0 end)(bag) or 0
    for slot = 1, n do
      local id = (C_Container and C_Container.GetContainerItemID or GetContainerItemID or function() end)(bag, slot)
      if id and not seen[id] then
        seen[id] = true
        local ah, v = A and A.Price and A.Price(id), A and A.Vendor and A.Vendor(id, false)
        if ah and v and ah * 0.95 > v + 2 then bags[#bags + 1] = { id = id, n = E.Have(id), ah = ah, v = v, gain = (ah * 0.95 - v) * E.Have(id) } end
      end
    end
  end
  table.sort(bags, function(a, b) return a.gain > b.gain end)
  if #bags > 0 then
    rows[#rows + 1] = { h = "In your bags: worth more on the Auction House" }
    for k = 1, math.min(#bags, 6) do
      local b = bags[k]
      rows[#rows + 1] = { t = string.format("%s x%d: +%s", E.ItemName(b.id), b.n, NS.Money(math.floor(b.gain))), i = b.id, key = "bag" .. b.id, d = string.format("%s each there, %s at a vendor", NS.Money(b.ah), NS.Money(b.v)) }
    end
  end
  -- 3. quests in your log that pay money
  local pay = {}
  for id, q in pairs(E.Log()) do
    local v = NS.Route.QuestValue and NS.Route.QuestValue(id)
    local rec = NS.db and NS.db.rec and NS.db.rec.quests and NS.db.rec.quests[id]
    local m = v and (v.money or 0) > 0 and v.money or (type(rec) == "table" and type(rec.m) == "number" and rec.m) or 0
    if m > 0 then pay[#pay + 1] = { id = id, name = q.title or E.QuestName(id), m = m, done = q.complete } end
  end
  table.sort(pay, function(a, b) return a.m > b.m end)
  if #pay > 0 then
    rows[#rows + 1] = { h = "Quests in your log that pay" }
    for k = 1, math.min(#pay, 8) do
      rows[#rows + 1] = { t = string.format("%s: %s", pay[k].name, NS.Money(pay[k].m)), d = pay[k].done and "Ready to hand in" or "Not finished yet", tex = "Interface\\Icons\\INV_Misc_Coin_01", key = "pay" .. pay[k].id }
    end
  end
  -- 5. materials that sell, that you can get now
  local mats, level = {}, UnitLevel("player")
  local function Try(id, why)
    local u = A and A.Usual and A.Usual(id)
    local p = u and (u.now and math.min(u.now, u.usual) or u.usual)
    if p and p > 5 then mats[#mats + 1] = { id = id, p = math.floor(p), why = why .. (u.days > 1 and string.format(", seen in %d scans", u.days) or "") } end
  end
  for id, f in pairs(NS.MATERIAL_FAMILY) do
    if f[1] <= level + 1 then
      if f[4] ~= "Skinning" then Try(id, string.format("Drops from %s, level %d-%d", f[3], f[1], f[2]))
      elseif E.Skill("Skinning") then Try(id, string.format("Skinning beasts, level %d-%d", f[1], f[2])) end
    end
  end
  for id, e in pairs(E.Data().reagents) do
    if e.o then
      local need = NS.GATHER_SKILL[e.o:lower()]
      local prof = need and "Mining" or "Herbalism"
      local rank = E.Skill(prof)
      if rank and (not need or rank >= need[2]) then
        local src = E.Best(id)
        if src and src.place and src.mins and src.mins < 35 then Try(id, e.o .. ", " .. E.Far(src.place)) end
      end
    end
  end
  table.sort(mats, function(a, b) return a.p > b.p end)
  if #mats > 0 then
    rows[#rows + 1] = { h = "Materials that sell, that you can gather" }
    for k = 1, math.min(#mats, 8) do rows[#rows + 1] = { t = string.format("%s: %s each", E.ItemName(mats[k].id), NS.Money(mats[k].p)), i = mats[k].id, d = mats[k].why, key = "mat" .. mats[k].id } end
  end
  -- 6. how your own play has paid
  local cmp = NS.Recorder and NS.Recorder.Compare and NS.Recorder.Compare(3) or {}
  if #cmp > 0 then
    rows[#rows + 1] = { h = "How your play has paid (recorded)" }
    for _, t in ipairs(cmp) do rows[#rows + 1] = { t = t } end
  end
  if #rows == 0 then
    rows[1] = { t = "Nothing to go on yet", d = "This fills in from what creatures near you drop, a scan at the Auction House, and quests in your log that pay money." }
    rows[2] = { t = "Until then: sell grays and whites you can't use at any vendor", d = "And keep cloth and leather: they sell well at the Auction House." }
  end
  return rows
end
