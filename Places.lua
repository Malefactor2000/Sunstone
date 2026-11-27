-- Sunstone: the search box. Every named place (PlacesData.lua; the game gives the names), and everything else Sunstone knows, by name: items, quests,
-- creatures and people, things in the world, dungeons and bosses, factions, recipes, sets, enchants, pets, mounts, beasts, spells, classes,
-- professions, the Guide's pages and the settings. Part of a word will do, words in any order, a letter or two off is forgiven.
-- A place opens with the way there, an item with everything about it. Information only.

local _, NS = ...
local Pl = NS.Module("Places")
NS.Places = Pl
local E = NS.Engine
local I = "Interface\\Icons\\"

local function List(t) return type(t) == "table" and t or {} end
local function Plain(s) return (s:lower():gsub("^the%s+", ""):gsub("[’`']", ""):gsub("[%-:,]", " "):gsub("%s+", " ")) end
Pl.Plain = Plain

-- how many letters apart two words are (a swapped pair counts as one); more than `most`: most + 1
function Pl.Apart(a, b, most)
  local la, lb = #a, #b
  if math.abs(la - lb) > most then return most + 1 end
  local prev2, prev, cur = nil, {}, {}
  for j = 0, lb do prev[j] = j end
  for i = 1, la do
    cur = { [0] = i }
    local least = i
    for j = 1, lb do
      local cost = a:byte(i) == b:byte(j) and 0 or 1
      local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      if prev2 and i > 1 and j > 1 and a:byte(i) == b:byte(j - 1) and a:byte(i - 1) == b:byte(j) then v = math.min(v, prev2[j - 2] + 1) end
      cur[j] = v
      if v < least then least = v end
    end
    if least > most then return most + 1 end
    prev2, prev = prev, cur
  end
  return prev[lb]
end

local function Words(q)
  local w = {}
  for x in q:gmatch("%S+") do w[#w + 1] = x end
  return w
end
-- how well a name answers the search: 0 exact, 1 starts with it, 2 a word of it does, 3 has it inside, 4 has all its words, 10+ a letter or two off; nil: not at all
function Pl.Score(low, q, words, strict)
  if low == q then return 0 end
  if low:find(q, 1, true) then
    if low:sub(1, #q) == q then return 1 end
    if low:find(" " .. q, 1, true) then return 2 end
    if #q >= 3 then return 3 end
  end
  words = words or Words(q)
  if #words > 1 then
    local all = true
    for _, w in ipairs(words) do if not low:find(w, 1, true) then all = false break end end
    if all then return 4 end
  end
  if strict then return nil end
  if #q >= 4 then
    local most = #q >= 7 and 2 or 1
    local d = Pl.Apart(low, q, most)
    if d <= most then return 10 + d end
  end
  -- each word of the search close to a word of the name
  if #q >= 5 then
    local total = 0
    for _, w in ipairs(words) do
      local near
      if low:find(w, 1, true) then near = 0
      elseif #w >= 4 then
        for x in low:gmatch("%S+") do
          local most = #w >= 8 and 2 or 1
          local d = Pl.Apart(x, w, most)
          if d <= most and (not near or d < near) then near = d end
        end
      end
      if not near then return nil end
      total = total + near
    end
    if total <= 3 then return 13 + total end
  end
end

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------
local index
local function Index()
  if index then return index end
  index = {}
  local function Add(name, kind, t)
    if type(name) ~= "string" or name == "" then return end
    t.name, t.low, t.kind = name, Plain(name), kind
    index[#index + 1] = t
  end
  local hbd = NS.HBD()
  for id, d in pairs(hbd and hbd.mapData or {}) do
    if type(id) == "number" and type(d) == "table" and (d.mapType == nil or d.mapType == 3) then Add(d.name, "zone", { m = id }) end
  end
  local zones = {}
  for _, e in ipairs(index) do zones[e.low] = true end
  if C_Map and C_Map.GetAreaInfo then
    for area, p in pairs(List(_G.SunstonePlaces)) do
      local ok, name = pcall(C_Map.GetAreaInfo, area)
      if ok and type(name) == "string" and not zones[Plain(name)] then Add(name, "place", { m = p[1], x = p[2] / 10, y = p[3] / 10 }) end
    end
  end
  for _, d in ipairs(List(_G.SunstoneTravel and SunstoneTravel.dungeons)) do
    local name, m, x, y = d.name or d[1], d.m or d[2], d.x or d[3], d.y or d[4]
    if type(name) == "string" and type(m) == "number" then Add(name, "dungeon", { m = m, x = x, y = y }) end
  end
  return index
end

-- places by that name, best first: { { name, kind, m, x, y (0-100), score } }
function Pl.Find(q, most)
  q = Plain(q or "")
  local out, words = {}, Words(q)
  if q == "" then return out end
  local rank = { zone = 0, dungeon = 1, place = 2 }
  for _, e in ipairs(Index()) do
    local s = Pl.Score(e.low, q, words)
    if s then out[#out + 1] = { name = e.name, kind = e.kind, m = e.m, x = e.x, y = e.y, score = s, low = e.low } end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score < b.score end
    if a.kind ~= b.kind then return rank[a.kind] < rank[b.kind] end
    if #a.low ~= #b.low then return #a.low < #b.low end
    if a.low ~= b.low then return a.low < b.low end
    return a.m < b.m
  end)
  if out[1] and out[1].score < 10 then -- (guesses only when nothing matches as it's written)
    while out[#out].score >= 10 do table.remove(out) end
  end
  while #out > (most or 6) do table.remove(out) end
  return out
end

-- The way to a spot: the arrow and the trail to it, and the route drawn on the map
function Pl.Way(m, x, y, name) -- x, y: 0 to 1
  local V = NS.MapView
  local p = E.Point(m, x, y)
  if V and p then V.trip = { m = m, x = x, y = y, wx = p.wx, wy = p.wy, inst = p.inst, name = name } end
  NS.Arrow.Go(m, x, y, name)
  if InCombatLockdown and InCombatLockdown() then
    NS.Print("the way to " .. name .. " is on your world map (the game doesn't let addons open it in combat).")
    return
  end
  if WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
  local shown
  if NS.Atlas and NS.Atlas.On() and NS.Atlas.FitTo then shown = NS.Safe("smooth map", NS.Atlas.FitTo, m, x, y) end
  if not shown and WorldMapFrame and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, m) end
  if V then NS.Safe("map line", V.DrawRoute) end
  NS.Print("the way to " .. name .. " is drawn on the world map. Re-plan on the Route tab goes back to your quests.")
end
function Pl.PlaceRow(name, m, x, y, d, key) -- x, y: 0 to 100
  return { t = name, d = d, m = m, x = x / 100, y = y / 100, key = key, tex = I .. "INV_Misc_Map_01", actLabel = "Show the way", act = function() Pl.Way(m, x / 100, y / 100, name) end }
end

---------------------------------------------------------------------------
-- Everything else, read once in the background: { name, low, kind, ... }
---------------------------------------------------------------------------
local all
local GROUPS = { -- kind, heading, how many are shown
  { "class", "Classes", 3 }, { "prof", "Professions", 3 }, { "faction", "Factions", 4 }, { "dungeon", "Dungeons and raids", 4 }, { "boss", "Bosses", 4 },
  { "item", "Items", 8 }, { "npc", "Creatures and people", 6 }, { "pet", "Companion pets", 4 }, { "mount", "Mounts", 4 }, { "beast", "Hunter pets", 4 }, { "recipe", "Recipes", 5 },
  { "set", "Item sets", 3 }, { "enchant", "Enchants", 3 }, { "spell", "Spells", 4 }, { "object", "Things in the world", 4 }, { "book", "Library Books", 4 },
  { "guide", "In the Guide", 4 }, { "setting", "Settings", 4 }, { "tab", "In Sunstone", 4 },
}
local LOOSE = { item = true, npc = true, object = true } -- (thousands of these: a letter off is only tried when nothing else is found)
local TABS = {
  { "Grind spots, XP an hour", "grind" }, { "Gold: ways to make gold, farm spots", "gold" }, { "Your bags: can I sell this?", "gold", "goldMode", "bags" }, { "Auction House, vendor flips", "gold" },
  { "Route, XP run, quest route", "route" }, { "Talents, talent plan", "talents" }, { "Gear upgrades", "upgrades" }, { "Enchants for your gear", "upgrades", "gearMode", "enchants" }, { "Item sets", "upgrades", "gearMode", "sets" },
  { "Professions, crafting", "prof" }, { "New recipes in Forever, new patterns", "prof", "profMode", "forever" }, { "Campsite, campfire, camp objects", "guide", "guideMode", "camp" }, { "Shopping list, crafting list", "prof", "profMode", "list" }, { "Reputation", "factions" }, { "Honor, battlegrounds, PvP", "factions", "factionMode", "honor" }, { "Library Books", "factions", "factionMode", "books" },
  { "Hunter pet planner", "class", "classMode", "pets" }, { "Macros", "class", "classMode", "macros" }, { "Rotations", "class", "classMode", "rot" }, { "Share your finds", "guide", "guideMode", "share" },
  { "What now?", "guide", "guideMode", "now" }, { "Settings", "guide", "guideMode", "set" }, { "Stats: what each does for you", "guide", "guideMode", "stats" }, { "Quest search", "quests" },
}

local function BuildAll()
  local out, seen = {}, {}
  local function Add(kind, name, t)
    if type(name) ~= "string" or #name < 2 then return end
    t = t or {}
    local key = kind .. ":" .. (t.id or name)
    if seen[key] then return end
    seen[key] = true
    t.kind, t.name, t.low = kind, name, Plain(name)
    out[#out + 1] = t
    E.Yield()
  end
  local D = E.Data()
  for _, f in ipairs(List(D.factions)) do if not f.side or f.side == E.Side() then Add("faction", f.n, { f = f }) end end
  for _, d in ipairs(List(_G.SunstoneDungeons and SunstoneDungeons.list)) do
    Add("dungeon", d.n, { d = d })
    for _, b in ipairs(List(d.bosses)) do
      Add("boss", b.n, { d = d })
      for _, l in ipairs(List(b.loot)) do if type(l[1]) == "number" then Add("item", l[2], { id = l[1] }) end end
    end
  end
  -- items: the ones the lists name, what quests give or want, what recipes make and teach
  for id, n in pairs(List(D.names)) do Add("item", n, { id = id }) end
  for prof, list in pairs(List(D.recipes)) do
    for _, r in ipairs(list) do
      if type(r.n) == "string" then
        Add("recipe", r.n, { r = r, prof = prof, id = r.s })
        if type(r.i) == "number" then Add("item", r.n, { id = r.i }) end
        if type(r.ri) == "number" and type(r.rn) == "string" then Add("item", r.rn, { id = r.ri }) end
      end
    end
  end
  for _, f in ipairs(List(D.factions)) do for _, it in ipairs(List(f.i)) do if type(it[1]) == "number" then Add("item", it[2], { id = it[1] }) end end end
  local camp = type(_G.SunstoneCamp) == "table" and SunstoneCamp or {}
  for _, o in ipairs(List(camp.objects)) do Add("item", o[4], { id = o[3] }) end
  if camp.banner then Add("item", camp.banner.name, { id = camp.banner.item }) end
  if camp.bag then Add("item", "Cozy Sleeping Bag", { id = camp.bag.item, also = "bedroll bed roll sleeping bag" }) end
  local own = NS.QuestDB and NS.QuestDB.own or {}
  for kind, src in pairs({ item = own.Item, npc = own.Npc, object = own.Object }) do
    for _, id in ipairs(src and src.GetAllIds and src.GetAllIds() or {}) do
      local ok, n = pcall(src.Get, id, "name")
      if ok and type(n) == "string" then Add(kind, n, { id = id }) end
    end
  end
  for id, n in pairs(List(D.npcs)) do if type(n) == "table" then Add("npc", n[1], { id = id }) end end
  local L = E.Lib and E.Lib()
  if L and L.questie then -- (with Questie there are many more)
    for kind, src in pairs({ item = L.Item, npc = L.Npc, object = L.Object }) do
      for _, id in ipairs(src and src.GetAllIds and src.GetAllIds() or {}) do
        local ok, n = pcall(src.Get, id, "name")
        if ok and type(n) == "string" then Add(kind, n, { id = id }) end
      end
    end
  end
  for id, r in pairs(List(NS.db.rec and NS.db.rec.sell)) do -- and what your own characters have seen
    local ok, n = pcall(NS.GetItemInfo, id)
    if ok and type(n) == "string" and r then Add("item", n, { id = id }) end
  end
  local S = List(_G.SunstoneCollect)
  for _, e in ipairs(List(S.pets)) do Add("pet", e.n, { e = e }) end
  for _, e in ipairs(List(S.mounts)) do Add("mount", e.n, { e = e }) end
  local P = List(_G.SunstonePets)
  for _, f in ipairs(List(P.families)) do
    Add("beast", f.n .. " (family)", { fam = f.n, d = "Hunter pet family" })
    for _, b in ipairs(List(f.tames)) do if type(b[1]) == "number" then Add("beast", b[2], { id = b[1], npc = b[1], d = f.n .. (b[3] and ("  ·  level " .. b[3]) or "") .. (b[4] and ("  ·  " .. b[4]) or "") }) end end
  end
  for _, a in ipairs(List(P.abilities)) do Add("beast", a.n .. " (pet skill)", { fam = nil, d = "Pet skill" }) end
  for _, s in ipairs(List(_G.SunstoneSets and SunstoneSets.sets)) do Add("set", s.n, { d = s.sub }) end
  for _, o in ipairs(List(_G.SunstoneSets and SunstoneSets.options)) do Add("enchant", o.n, { d = o.p, i = o.i }) end
  if NS.CharSheet and NS.CharSheet.Known then
    local ok, known = pcall(NS.CharSheet.Known)
    for k, v in pairs(ok and List(known) or {}) do
      local n = type(v) == "table" and (v.n or v.name) or type(k) == "string" and k
      if type(n) == "string" then Add("spell", n) end
    end
  end
  if NS.Class and NS.Class.Rows then
    local ok, rows = pcall(NS.Class.Rows)
    for _, r in ipairs(ok and rows or {}) do if r.page and type(r.t) == "string" then Add("class", (r.t:gsub("%s+%(you%)", "")), { row = r }) end end
  end
  for _, p in ipairs(List(NS.Professions and NS.Professions.LIST)) do Add("prof", p[1], { info = p }) end
  for _, b in ipairs(List(D.books)) do Add("book", b[3], { id = b[1], m = b[4], x = b[5], y = b[6], d = b[7] }) end
  local mode = NS.cdb.guideMode
  for _, m in ipairs({ "retail", "systems", "who" }) do
    NS.cdb.guideMode = m
    local ok, rows = pcall(NS.Guide.Rows)
    for _, r in ipairs(ok and List(rows) or {}) do if type(r.t) == "string" and not r.h then Add("guide", r.t, { row = r, mode = m, also = type(r.d) == "string" and Plain(r.d):sub(1, 200) or nil, id = m .. r.t }) end end
  end
  NS.cdb.guideMode = mode
  for _, s in ipairs(List(NS.settings)) do Add("setting", s.name, { s = s, also = Plain(s.group .. " " .. (s.about or "")), id = s.group .. s.name }) end
  for _, t in ipairs(TABS) do Add("tab", t[1], { t = t, id = t[1] }) end
  return out
end

function Pl.Ready() return all ~= nil end
local waiting
function Pl.Build(done)
  if all then if done then done() end return end
  waiting = done or waiting
  if E.Busy and E.Busy("search index") then return end
  E.Job("search index", BuildAll, function(res)
    all = res
    local fn = waiting
    waiting = nil
    if fn then fn() end
  end)
end
function Pl.Forget() index, all = nil, nil end
function Pl.Count() return all and #all or 0 end

-- a row for an entry
local function RowOf(e)
  local k, key = e.kind, "s" .. e.kind .. tostring(e.id or e.name)
  if k == "faction" then
    local ok, st = pcall(E.StandingText, e.f.id)
    return { t = e.name, d = "Faction" .. (ok and type(st) == "string" and st ~= "" and ("  ·  " .. st) or ""), tex = I .. "INV_Jewelry_Ring_03", key = key, page = function() return NS.Factions2.FactionPage(e.f) end }
  elseif k == "dungeon" or k == "boss" then
    return { t = e.name, d = k == "boss" and ("Boss in " .. e.d.n) or ((e.d.raid and "Raid" or "Dungeon") .. (e.d.loc and ("  ·  " .. e.d.loc) or "")), tex = I .. "INV_Misc_Bone_HumanSkull_01", key = key, page = function() return NS.Dungeons.Page(e.d) end }
  elseif k == "item" then
    return { t = e.name, i = e.id, d = "Everything about it", key = key }
  elseif k == "npc" or k == "object" then
    local p = E.Nearest(E.Points(k == "npc" and "Npc" or "Object", e.id))
    local bits = {}
    local lv = k == "npc" and E.Creature(e.id) or ""
    if lv ~= "" then bits[1] = lv:gsub("^%l", string.upper) end
    if p then bits[#bits + 1] = E.Where(p) else bits[#bits + 1] = "Where isn't known (often inside a dungeon)" end
    local row = E.At({ t = e.name, d = table.concat(bits, "  ·  "), tex = I .. (k == "npc" and "Ability_Hunter_MarkedForDeath" or "INV_Box_01"), key = key }, p)
    if p then row.actLabel, row.act = "Show the way", function() Pl.Way(p.m, p.x, p.y, e.name) end end
    if k == "npc" and e.id > 0 and NS.Farm and NS.Farm.CreaturePage and E.Huntable(e.id) then row.page = function() return NS.Farm.CreaturePage(e.id) end end
    return row
  elseif k == "pet" or k == "mount" then
    return { t = e.name, i = e.e.id, d = k == "pet" and "Companion pet" or "Mount", key = key, page = function() return NS.Collect.Page(e.e, k == "mount") end }
  elseif k == "beast" then
    return { t = e.name, d = e.d, tex = I .. "Ability_Hunter_BeastCall", key = key, still = true, actLabel = "Open", act = function()
      if e.npc then NS.PetPlan.Open(e.npc) else if e.fam then NS.PetPlan.PickFamily(e.fam) end NS.PetPlan.Open() end
    end }
  elseif k == "recipe" then
    return { t = e.name, d = e.prof .. " " .. tostring(e.r.k or "?"), i = e.r.i, key = key, page = function() e.r.prof = e.r.prof or e.prof return NS.Professions.RecipePage(e.r) end }
  elseif k == "spell" then
    return { t = e.name, d = "Your spell, in real numbers", tex = I .. "INV_Misc_Book_09", key = key, page = function() return NS.CharSheet.SpellPage(e.name) end }
  elseif k == "class" then
    return { t = e.name, d = "Class guide: weapons, leveling, rotations, macros", tex = e.row.tex, key = key, page = e.row.page }
  elseif k == "prof" then
    return { t = e.name, d = "Profession", tex = e.info[2], key = key, page = function() return NS.Professions.Page(e.info) end }
  elseif k == "book" then
    local row = Pl.PlaceRow(e.name, e.m, e.x, e.y, "Library Book" .. (e.d and ("  ·  " .. e.d) or ""), key)
    row.tex = I .. "INV_Misc_Book_11"
    return row
  elseif k == "guide" then
    return { t = e.name, d = e.row.d, tex = e.row.tex, i = e.row.i, key = key, page = e.row.page, still = not e.row.page or nil }
  elseif k == "setting" then
    local ok, v = pcall(e.s.get)
    return { t = e.name, d = e.s.about, still = true, key = key, actLabel = type(v) == "string" and v or (ok and v and "On" or "Off"),
             act = function() NS.Safe("setting", e.s.set, not e.s.get()) if NS.Window then NS.Window.Search(NS.Window.searchText or e.name) end end }
  elseif k == "set" or k == "enchant" then
    return { t = e.name, d = (k == "set" and "Item set" or "Enchant or armor kit") .. (type(e.d) == "string" and ("  ·  " .. e.d) or ""), i = e.i, key = key, still = not e.i or nil, actLabel = "Open",
             act = function() NS.cdb.gearMode = k == "set" and "sets" or "enchants" NS.Window.Open("upgrades") end }
  elseif k == "tab" then
    return { t = e.name, d = "Opens it", tex = I .. "INV_Misc_Note_02", still = true, key = key, actLabel = "Open", act = function()
      if e.t[3] then NS.cdb[e.t[3]] = e.t[4] end
      NS.Window.Open(e.t[2])
    end }
  end
end

function Pl.Elsewhere(q)
  local said = q or ""
  q = Plain(said)
  local rows, words = {}, Words(q)
  if #q < 2 then return rows end
  local groups, top = {}, {}
  local function Try(strict, loose)
    for _, e in ipairs(all or {}) do
      if (not loose and not LOOSE[e.kind]) or (loose and LOOSE[e.kind]) then
        local s = Pl.Score(e.low, q, words, strict or (loose and loose ~= "near") or (loose == "near" and e.low:byte(1) ~= q:byte(1) and not e.low:find(" " .. q:sub(1, 1), 1, true)))
        if not s and e.also and #q >= 4 and e.also:find(q, 1, true) then s = 5 end
        if s then
          groups[e.kind] = groups[e.kind] or {}
          table.insert(groups[e.kind], { e, s })
          if not top[e.kind] or s < top[e.kind] then top[e.kind] = s end
        end
      end
    end
  end
  Try(true)
  Try(true, "exact")
  -- the quest search knows quests by name, by what they give and teach, by who gives them, and the campsite
  local quests = NS.QuestFind and NS.QuestFind.For and NS.QuestFind.For(said) or {}
  if not next(groups) and #quests == 0 then
    Try(false)
    if not next(groups) and #q >= 5 then Try(false, "near") end
  end
  local order = {}
  for k, g in ipairs(GROUPS) do
    local l = groups[g[1]]
    if l then
      table.sort(l, function(a, b)
        if a[2] ~= b[2] then return a[2] < b[2] end
        if #a[1].low ~= #b[1].low then return #a[1].low < #b[1].low end
        if a[1].low ~= b[1].low then return a[1].low < b[1].low end
        return tostring(a[1].id) < tostring(b[1].id)
      end)
      order[#order + 1] = { g = g, l = l, s = top[g[1]], k = k }
    end
  end
  table.sort(order, function(a, b)
    local x, y = math.min(a.s, 2), math.min(b.s, 2)
    if a.s >= 5 then x = a.s end
    if b.s >= 5 then y = b.s end
    if x ~= y then return x < y end
    return a.k < b.k
  end)
  local near = order[1] and order[1].s >= 10
  local function Show(o)
    rows[#rows + 1] = { h = o.g[2] .. (near and " (close to what you typed)" or "") }
    local n, shown = 0, {}
    for _, x in ipairs(o.l) do
      if n < o.g[3] and not (o.g[1] == "npc" and shown[x[1].low]) then
        local ok, r = pcall(RowOf, x[1])
        if ok and r then n = n + 1 shown[x[1].low] = true rows[#rows + 1] = r elseif not ok then NS.Error("search", r) end
      end
    end
    if #o.l > n and n >= o.g[3] then rows[#rows + 1] = { t = string.format("%d more", #o.l - n), d = "Type a little more to narrow it down.", still = true, dim = true, key = "smore" .. o.g[1] } end
  end
  for _, o in ipairs(order) do if o.s <= 1 then Show(o) end end -- what's called just that comes first
  for _, r in ipairs(quests) do rows[#rows + 1] = r end
  for _, o in ipairs(order) do if o.s > 1 then Show(o) end end
  Pl.best = order[1] and order[1].s or (#quests > 0 and 3) or nil
  return rows
end

---------------------------------------------------------------------------
-- An item's page: what else there is to know about it
---------------------------------------------------------------------------
function Pl.ItemExtra(id)
  local rows = {}
  local function Head(h) rows[#rows + 1] = { h = h } end
  -- quests that give it (Forever's own too)
  local QF = NS.QuestFind
  local given = QF and QF.GivenBy and QF.GivenBy(id) or {}
  if #given > 0 then
    Head("Quests that give it")
    for k = 1, math.min(6, #given) do
      local qid = given[k]
      rows[#rows + 1] = { t = E.QuestName(qid), d = "The whole chain, step by step, on a map", tex = I .. "INV_Misc_Note_01", key = "igq" .. qid, page = function() return QF.Page(qid) end }
    end
  end
  -- the bedroll, the banner and the camp objects have their own pages
  local camp = type(_G.SunstoneCamp) == "table" and SunstoneCamp or nil
  if camp and QF then
    if camp.bag and camp.bag.item == id and #given == 0 then
      Head("Quests that give it")
      rows[#rows + 1] = { t = E.QuestName(camp.bag.last), d = "The last of 6 quests, from level 14: every step on a map, from where you are now", tex = I .. "INV_Misc_Note_01", key = "igbag", page = function() return QF.Page(camp.bag.last) end }
    elseif camp.banner and camp.banner.item == id and QF.BannerPage then
      Head("How to get it")
      rows[#rows + 1] = { t = camp.banner.name, d = "Every step on a map", tex = I .. "INV_Misc_Note_01", key = "igban", page = QF.BannerPage }
    end
    for _, o in ipairs(List(camp.objects)) do
      if o[3] == id and QF.ObjectPage then
        Head("For your campsite")
        rows[#rows + 1] = { t = o[4], d = o[1] .. " " .. tostring(o[5]) .. "  ·  " .. tostring(o[6]), tex = I .. "Spell_Fire_Fire", key = "igobj", page = function() return QF.ObjectPage(o) end }
      end
    end
    if QF.CampPage and camp.bag and camp.bag.item == id then rows[#rows + 1] = { t = "Your campsite", d = "Everything for it, by profession", tex = I .. "Spell_Fire_Fire", key = "igcamp", page = QF.CampPage } end
  end
  -- out of chests, crates and what players found
  local S, C = List(_G.SunstoneCollect), NS.Collect
  local chest, inside = List(S.chest)[id], List(S.inside)[id]
  if (chest or inside) and C then
    Head("Found in")
    for k = 1, #List(chest), 3 do
      local p = E.Nearest(E.Points("Object", chest[k]))
      local row = E.At({ t = chest[k + 2] .. "  " .. C.Percent(chest[k + 1]), d = p and E.PlaceText(p) or "Where it stands isn't recorded (often inside a dungeon).", key = "ich" .. chest[k] }, p)
      if p then row.actLabel, row.act = "Show the way", function() Pl.Way(p.m, p.x, p.y, chest[k + 2]) end end
      rows[#rows + 1] = row
    end
    for k = 1, #List(inside), 2 do rows[#rows + 1] = { t = "Inside " .. E.ItemName(inside[k]) .. "  " .. C.Percent(inside[k + 1]), i = inside[k], d = "Open it to see.", key = "iin" .. inside[k] } end
  end
  for k, s in ipairs(NS.Community and NS.Community.Sources(id) or {}) do
    if k == 1 then Head("Found by players") end
    rows[#rows + 1] = { t = NS.Finds.KIND[s.kind]:gsub("^%l", string.upper) .. " " .. NS.Finds.SourceName(s.kind, s.id), d = string.format("%d player%s.", s.players, s.players == 1 and "" or "s"), still = true, key = "ico" .. k }
  end
  -- what wants it
  local Sell = NS.Sell
  local ok, qs = pcall(function() return Sell and Sell.Quests(id) or {} end)
  if ok and #qs > 0 then
    Head("Quests that need it")
    for k = 1, math.min(6, #qs) do
      local x = qs[k]
      rows[#rows + 1] = { t = E.QuestName(x.id), d = x.log and "In your log" or x.starts and "It starts this quest" or x.holiday and ((x.holiday ~= "" and ("When the " .. x.holiday .. " is on") or "While its holiday is on") .. (x.again and ", again and again" or "") .. (x.level > 0 and (", from level " .. x.level) or "")) or (x.level > 0 and ("From level " .. x.level) or ""), tex = I .. "INV_Misc_Note_01", key = "inq" .. x.id, page = QF and function() return QF.Page(x.id) end or nil }
    end
  end
  local ok2, rec = pcall(function() return Sell and Sell.Recipes(id) or {} end)
  if ok2 and #rec > 0 then
    table.sort(rec, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return (a[2].k or 0) < (b[2].k or 0) end)
    Head(string.format("Made into (%d recipe%s)", #rec, #rec == 1 and "" or "s"))
    for k = 1, math.min(8, #rec) do
      local x = rec[k]
      rows[#rows + 1] = { t = x[2].n, d = x[1] .. " " .. (x[2].k or "?"), i = x[2].i, key = "ire" .. k, page = NS.Professions and function() x[2].prof = x[2].prof or x[1] return NS.Professions.RecipePage(x[2]) end or nil }
    end
    if #rec > 8 then rows[#rows + 1] = { t = string.format("%d more", #rec - 8), still = true, dim = true, key = "iremore" } end
  end
  -- what it's worth
  local bits = {}
  local ok3, vendor = pcall(E.VendorPrice, id)
  local sell = select(11, NS.GetItemInfo(id))
  if type(sell) == "number" and sell > 0 then bits[#bits + 1] = NS.Money(sell) .. " when you sell it to a vendor" end
  if ok3 and type(vendor) == "number" and vendor > 0 then bits[#bits + 1] = NS.Money(math.floor(vendor + 0.5)) .. " to buy from a vendor" end
  if NS.Farm and NS.Farm.PriceText then
    local ok4, text = pcall(NS.Farm.PriceText, id)
    if ok4 and type(text) == "string" and text:find("uction", 1, true) then bits[#bits + 1] = text end
  end
  local v = Sell and Sell.Verdict(id)
  if #bits > 0 or v then
    Head("Worth")
    if #bits > 0 then rows[#rows + 1] = { t = "What it's worth", d = table.concat(bits, "\n"), still = true, key = "iworth" } end
    if v then rows[#rows + 1] = { t = "|cff" .. Sell.HEX[v.v] .. Sell.WORD[v.v] .. "|r", d = v.why, still = true, key = "isell" } end
  end
  return rows
end

function Pl:Init()
  C_Timer.After(25, function() NS.Safe("search", Pl.Build) end)
end
