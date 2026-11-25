-- Sunstone: the search box's index. Every named place on the zone maps (PlacesData.lua; the game gives the names), zones, dungeons, and the rest of
-- Sunstone by name: factions, dungeons, quests, recipes, items, pets and mounts. Forgives a letter or two. Information only.

local _, NS = ...
local Pl = NS.Module("Places")
NS.Places = Pl
local E = NS.Engine
local I = "Interface\\Icons\\"

local function List(t) return type(t) == "table" and t or {} end
local function Plain(s) return (s:lower():gsub("^the%s+", ""):gsub("[’`]", "'")) end

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

-- how well a name answers the search: 0 exact, 1 starts with it, 2 a word of it does, 3 has it inside, 10+ a letter or two off; nil: not at all
function Pl.Score(low, q)
  if low == q then return 0 end
  if low:sub(1, #q) == q then return 1 end
  if low:find(" " .. q, 1, true) then return 2 end
  if #q >= 3 and low:find(q, 1, true) then return 3 end
  if #q >= 4 then
    local most = #q >= 7 and 2 or 1
    local d = Pl.Apart(low, q, most)
    if d <= most then return 10 + d end
    if #q >= 5 and #low > #q then -- the start of a longer name, with a letter off ("wailng" for Wailing Caverns)
      d = Pl.Apart(low:match("^%S+"), q, 1)
      if d <= 1 then return 13 + d end
    end
  end
end

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
function Pl.Forget() index = nil end

-- places by that name, best first: { { name, kind, m, x, y (0-100), score } }
function Pl.Find(q, most)
  q = Plain(q or "")
  local out = {}
  if q == "" then return out end
  local rank = { zone = 0, dungeon = 1, place = 2 }
  for _, e in ipairs(Index()) do
    local s = Pl.Score(e.low, q)
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

---------------------------------------------------------------------------
-- The rest of Sunstone by name
---------------------------------------------------------------------------
local function Best(list, low, q, most)
  local out = {}
  for _, e in ipairs(list) do
    local s = Pl.Score(low(e), q)
    if s then out[#out + 1] = { e = e, s = s } end
  end
  table.sort(out, function(a, b) if a.s ~= b.s then return a.s < b.s end return low(a.e) < low(b.e) end)
  if out[1] and out[1].s < 10 then while out[#out].s >= 10 do table.remove(out) end end
  local r = {}
  for k = 1, math.min(most, #out) do r[k] = out[k].e end
  return r, out[1] and out[1].s
end

function Pl.Elsewhere(q)
  q = Plain(q or "")
  local rows = {}
  if #q < 3 then return rows end
  local function Section(head, list)
    if #list == 0 then return end
    rows[#rows + 1] = { h = head }
    for _, r in ipairs(list) do rows[#rows + 1] = r end
  end
  local D = E.Data()
  local guess = {} -- sections that only matched by a near miss: shown when nothing else did
  local function Take(head, list, score)
    if #list == 0 then return end
    if score and score >= 10 then guess[#guess + 1] = { head, list } else Section(head, list) end
  end
  -- factions
  local f, s = Best(List(D.factions), function(e) return Plain(e.n or "") end, q, 4)
  local t = {}
  for _, e in ipairs(f) do
    if not e.side or e.side == E.Side() then
      local ok, st = pcall(E.StandingText, e.id)
      t[#t + 1] = { t = e.n, d = "Faction" .. (ok and type(st) == "string" and st ~= "" and ("  ·  " .. st) or ""), tex = I .. "INV_Jewelry_Ring_03", key = "sfac" .. e.id,
                    page = NS.Factions2 and NS.Factions2.FactionPage and function() return NS.Factions2.FactionPage(e) end or nil }
    end
  end
  Take("Factions", t, s)
  -- dungeons and raids
  local dl, ds = Best(List(_G.SunstoneDungeons and SunstoneDungeons.list), function(e) return Plain(e.n or "") end, q, 3)
  t = {}
  for _, e in ipairs(dl) do t[#t + 1] = { t = e.n, d = (e.raid and "Raid" or "Dungeon") .. (e.loc and ("  ·  " .. e.loc) or ""), tex = I .. "INV_Misc_Bone_HumanSkull_01", key = "sdg" .. e.n, page = NS.Dungeons and function() return NS.Dungeons.Page(e) end or nil } end
  Take("Dungeons and raids", t, ds)
  -- quests
  local QF = NS.QuestFind
  if QF then
    local ok, r = pcall(QF.Search, q)
    t = {}
    local l = ok and List(r.names) or {}
    table.sort(l, function(a, b) if a.s ~= b.s then return a.s < b.s end return a.q < b.q end)
    for k = 1, math.min(5, #l) do t[k] = { t = E.QuestName(l[k].q), d = "Quest", tex = I .. "INV_Misc_Note_01", key = "sq" .. l[k].q, page = function() return QF.Page(l[k].q) end } end
    Take("Quests", t)
    if QF.Build then pcall(QF.Build) end
  end
  -- pets and mounts
  local S = List(_G.SunstoneCollect)
  for _, c in ipairs({ { List(S.pets), "Companion pet" }, { List(S.mounts), "Mount" } }) do
    local l, cs = Best(c[1], function(e) return Plain(e.n or "") end, q, 3)
    t = {}
    for _, e in ipairs(l) do t[#t + 1] = { t = e.n, d = c[2], i = e.id, key = "sco" .. e.id, page = NS.Collect and function() return NS.Collect.Page(e, c[2] == "Mount") end or nil } end
    Take(c[2] == "Mount" and "Mounts" or "Pets", t, cs)
  end
  -- recipes
  local all = {}
  for prof, list in pairs(List(D.recipes)) do for _, r in ipairs(list) do if type(r.n) == "string" then all[#all + 1] = { r, prof } end end end
  local rl = Best(all, function(e) return Plain(e[1].n) end, q, 4)
  t = {}
  for _, e in ipairs(rl) do
    local r, prof = e[1], e[2]
    if Pl.Score(Plain(r.n), q) < 10 then
      t[#t + 1] = { t = r.n, d = prof .. " " .. tostring(r.k or "?"), i = r.i, key = "sre" .. tostring(r.s or r.n), page = NS.Professions and function() r.prof = r.prof or prof return NS.Professions.RecipePage(r) end or nil }
    end
  end
  Take("Recipes", t)
  -- items
  t = {}
  local hits = {}
  for id, n in pairs(List(D.names)) do
    if type(n) == "string" then
      local low = Plain(n)
      local sc = low == q and 0 or low:sub(1, #q) == q and 1 or low:find(q, 1, true) and 3
      if sc then hits[#hits + 1] = { id, n, sc } end
    end
  end
  table.sort(hits, function(a, b) if a[3] ~= b[3] then return a[3] < b[3] end if #a[2] ~= #b[2] then return #a[2] < #b[2] end return a[1] < b[1] end)
  for k = 1, math.min(4, #hits) do t[k] = { t = hits[k][2], i = hits[k][1], d = "Every way to get it", key = "sit" .. hits[k][1] } end
  Take("Items", t)
  if #rows == 0 then for _, g in ipairs(guess) do Section(g[1] .. " (close to what you typed)", g[2]) end end
  return rows
end
