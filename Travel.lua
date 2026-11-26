-- Sunstone: "how do I get to...?" and "where's the nearest...?", answered inside the game.
-- Finds the quickest way from where you stand to a zone, town, dungeon or service: walking (zone to zone
-- through their borders), flight paths (from your faction's flight masters; you need to know the route)
-- and zeppelins, boats, airships and trams. The data is TravelData.lua (written by the desktop helper from
-- OneForAll's and Questie's data); everything here is checked before use and runs offline.

local _, NS = ...
local T = NS.Module("Travel")
NS.Travel = T

local RUN, FLY = 7, 30            -- yards per second: on foot, on a flight path
local DETOUR, RIDE = 1.3, 150     -- real paths are longer than straight lines; a boat or zeppelin ride in seconds

---------------------------------------------------------------------------
-- Data (checked: only numbers and short text are used)
---------------------------------------------------------------------------
local D
local function Num(v) return type(v) == "number" and v == v end
local function Str(v, n) return type(v) == "string" and NS.Clean(v, n or 60) or nil end

local function Load()
  if D then return D end
  local src = _G.SunstoneTravel
  D = { flight = {}, transport = {}, cross = {}, levels = {}, dungeons = {}, npcs = {} }
  if type(src) ~= "table" then return D end
  local function Rows(list) return type(list) == "table" and list or {} end
  for _, f in ipairs(Rows(src.flight)) do
    if type(f) == "table" and Num(f[1]) and Num(f[2]) and Num(f[3]) then
      D.flight[#D.flight + 1] = { m = f[1], x = f[2], y = f[3], side = Str(f[4], 3) or "", name = Str(f[5], 40) or "Flight master" }
    end
  end
  for kind, label in pairs({ zeppelin = "zeppelin", ship = "boat", air = "airship", tram = "tram" }) do
    for _, e in ipairs(Rows(src[kind])) do
      if type(e) == "table" and Num(e[1]) and Num(e[2]) and Num(e[3]) then
        local dests = {}
        for i = 5, 8 do if Str(e[i]) then dests[#dests + 1] = Str(e[i]) end end
        D.transport[#D.transport + 1] = { m = e[1], x = e[2], y = e[3], side = Str(e[4], 3) or "", kind = kind, label = label, dests = dests }
      end
    end
  end
  for _, c in ipairs(Rows(src.cross)) do
    if type(c) == "table" and Num(c[1]) and Num(c[2]) and Num(c[3]) and Num(c[4]) then
      D.cross[#D.cross + 1] = { m = c[1], x = c[2], y = c[3], to = c[4] }
    end
  end
  for _, l in ipairs(Rows(src.levels)) do
    if type(l) == "table" and Num(l[1]) and Num(l[2]) and Num(l[3]) then D.levels[l[1]] = { l[2], l[3] } end
  end
  for _, d in ipairs(Rows(src.dungeons)) do
    if type(d) == "table" and Str(d[1]) and Num(d[2]) and Num(d[3]) and Num(d[4]) then
      D.dungeons[#D.dungeons + 1] = { name = Str(d[1]), m = d[2], x = d[3], y = d[4], lvl = Num(d[5]) and d[5] or 0 }
    end
  end
  for _, n in ipairs(Rows(src.npcs)) do
    if type(n) == "table" and Str(n[1], 30) and Num(n[3]) and Num(n[4]) and Num(n[5]) then
      D.npcs[#D.npcs + 1] = { code = Str(n[1], 30), name = Str(n[2], 40) or "?", m = n[3], x = n[4], y = n[5], side = Str(n[6], 3) or "" }
    end
  end
  return D
end

T.Data = Load
function T.ZoneLevels() return Load().levels end

local function Me() return (UnitFactionGroup("player") or "Horde"):sub(1, 1) end
local function Friendly(side) return side == "" or side == "AH" or side:find(Me(), 1, true) ~= nil end
T.Friendly = Friendly

local function World(m, x, y)
  local hbd = NS.HBD()
  if not hbd then return nil end
  local ok, wx, wy, inst = pcall(hbd.GetWorldCoordinatesFromZone, hbd, x / 100, y / 100, m)
  if ok and wx then return wx, wy, inst end
end

local function MapName(m)
  local hbd = NS.HBD()
  return hbd and hbd.GetLocalizedMap and hbd:GetLocalizedMap(m) or ("map " .. tostring(m))
end
T.MapName = MapName

local function Where(p) return string.format("%s %.1f, %.1f", MapName(p.m), p.x, p.y) end

local function Dist(a, b)
  if not (a.wx and b.wx) or a.inst ~= b.inst then return nil end
  return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
end

local function Here()
  local hbd = NS.HBD()
  if not hbd then return nil end
  local x, y, m = hbd:GetPlayerZonePosition()
  local wx, wy, inst = hbd:GetPlayerWorldPosition()
  if not (x and m and wx) then return nil end
  return { m = m, x = x * 100, y = y * 100, wx = wx, wy = wy, inst = inst, label = "you" }
end
T.Here = Here

---------------------------------------------------------------------------
-- Places: zones, towns, dungeons, services
---------------------------------------------------------------------------
local zoneIndex
local function Zones()
  if zoneIndex then return zoneIndex end
  zoneIndex = {}
  local hbd = NS.HBD()
  if hbd and type(hbd.mapData) == "table" then
    for id, d in pairs(hbd.mapData) do
      if type(id) == "number" and type(d) == "table" and type(d.name) == "string" and (d.mapType == nil or d.mapType == 3) then
        zoneIndex[d.name:lower()] = zoneIndex[d.name:lower()] or id
      end
    end
  end
  return zoneIndex
end

local function FindZone(text)
  local z = Zones()
  if z[text] then return z[text] end
  local best, bestLen
  for name, id in pairs(z) do
    if (name:find(text, 1, true) == 1 or text:find(name, 1, true)) and (not bestLen or #name < bestLen) then best, bestLen = id, #name end
  end
  return best
end

-- "Town, Zone" names from the boat / zeppelin lists: the town's dock is the place
local function FindTown(text)
  for _, t in ipairs(Load().transport) do
    for _, dest in ipairs(t.dests) do
      local town, zone = dest:lower():match("^([^,]+),%s*(.+)$")
      if town and (town == text or town:find(text, 1, true) == 1) then
        local zm = FindZone(zone)
        -- the arrival is the dock or tower of that kind inside that zone
        for _, o in ipairs(D.transport) do
          if o.m == zm and o.kind == t.kind then return { kind = "point", m = o.m, x = o.x, y = o.y, name = dest } end
        end
        if zm then return { kind = "zone", m = zm, name = dest } end
      end
    end
  end
end

local SHORT = { rfc = "ragefire", wc = "wailing", dm = "deadmines", sfk = "shadowfang", bfd = "blackfathom", rfk = "razorfen kraul",
                rfd = "razorfen downs", sm = "scarlet", zf = "zul'farrak", brd = "blackrock depths", ulda = "uldaman", mara = "maraudon" }
local function FindDungeon(text)
  text = SHORT[text] or text
  for _, d in ipairs(Load().dungeons) do
    local n = d.name:lower()
    if n:find(text, 1, true) or (#text > 5 and text:find(n, 1, true)) then return d end
  end
end

local SERVICES = {
  bank = "bank", banker = "bank", ah = "auction", auction = "auction", ["auction house"] = "auction", auctioneer = "auction",
  inn = "inn", innkeeper = "inn", hearth = "inn", hearthstone = "inn", ["flight master"] = "flight", flight = "flight",
  ["flight path"] = "flight", fly = "flight", taxi = "flight", ["wind rider"] = "flight", gryphon = "flight",
  stable = "stable", ["stable master"] = "stable", mailbox = "mailbox", mail = "mailbox", repair = "repair", armorer = "repair",
  reagents = "reagents", reagent = "reagents", ["trade supplies"] = "trade", thread = "trade", ["general goods"] = "general",
  food = "general", water = "general", ["weapon master"] = "weapon", ["weapon trainer"] = "weapon", riding = "riding",
  ["riding trainer"] = "riding", ["spirit healer"] = "spirit",
}
local SERVICE_NAMES = { bank = "banker", auction = "auctioneer", inn = "innkeeper", flight = "flight master", stable = "stable master",
                        mailbox = "mailbox", repair = "repair vendor", reagents = "reagent vendor", trade = "trade supplies vendor",
                        general = "general goods vendor", weapon = "weapon master", riding = "riding trainer", spirit = "spirit healer" }

local PROFESSION = { tailor = "tailoring", alchemist = "alchemy", leatherworker = "leatherworking", blacksmith = "blacksmithing",
                     enchanter = "enchanting", engineer = "engineering", miner = "mining", herbalist = "herbalism", herb = "herbalism",
                     skinner = "skinning", cook = "cooking", fisher = "fishing", fisherman = "fishing" }
local function FindService(text)
  local code = SERVICES[text]
  if code then return code, SERVICE_NAMES[code] end
  local what = text:match("^(.-)%s*trainer$")
  if what then
    if what == "" or what == "class" or what == "my" or what == "my class" then
      local _, class = UnitClass("player")
      what = class:lower()
    end
    what = PROFESSION[what] or what
    if what == "first aid" or what:find("^%a+$") then return "trainer:" .. what, what .. " trainer" end
  end
end

---------------------------------------------------------------------------
-- The route: Dijkstra over walking (inside a zone), borders, flights and rides
---------------------------------------------------------------------------
local graph -- static part: nodes with positions, edges between them
local function AddNode(nodes, n)
  n.wx, n.wy, n.inst = World(n.m, n.x, n.y)
  if not n.wx then return nil end
  nodes[#nodes + 1] = n
  n.id = #nodes
  n.edges = {}
  return n
end

local function Link(a, b, cost, how)
  a.edges[#a.edges + 1] = { to = b, cost = cost, how = how }
end

local function Build()
  if graph then return graph end
  local d = Load()
  local nodes, byMap = {}, {}
  local function Index(n) if n then byMap[n.m] = byMap[n.m] or {}; table.insert(byMap[n.m], n) end return n end
  -- zone borders: each crossing point links to the matching point on the other side
  for _, c in ipairs(d.cross) do Index(AddNode(nodes, { m = c.m, x = c.x, y = c.y, kind = "cross", to = c.to })) end
  for _, n in ipairs(nodes) do
    if n.kind == "cross" then
      local best, bd
      for _, o in ipairs(byMap[n.to] or {}) do
        if o.kind == "cross" and o.to == n.m then
          local dd = Dist(n, o)
          if dd and (not bd or dd < bd) then best, bd = o, dd end
        end
      end
      if not best then
        -- no matching crossing listed: arrive at the same spot, seen on the other zone's map
        local hbd = NS.HBD()
        local ok, x, y = pcall(hbd.TranslateZoneCoordinates, hbd, n.x / 100, n.y / 100, n.m, n.to, true)
        if ok and x then best = Index(AddNode(nodes, { m = n.to, x = x * 100, y = y * 100, kind = "arrive" })) end
      end
      if best then Link(n, best, 5, "cross") end
    end
  end
  -- flight masters of your faction: fly between any two on the same continent
  local fms = {}
  for _, f in ipairs(d.flight) do
    if Friendly(f.side) then fms[#fms + 1] = Index(AddNode(nodes, { m = f.m, x = f.x, y = f.y, kind = "flight", name = f.name })) end
  end
  for _, a in ipairs(fms) do
    for _, b in ipairs(fms) do
      if a ~= b then
        local dd = Dist(a, b)
        if dd then Link(a, b, dd * 1.1 / FLY + 20, "fly") end
      end
    end
  end
  -- zeppelins, boats, airships, trams: to the same kind of stop nearest the named destination
  local stops = {}
  for _, t in ipairs(d.transport) do
    if Friendly(t.side) then
      local n = Index(AddNode(nodes, { m = t.m, x = t.x, y = t.y, kind = "ride", label = t.label, ride = t.kind, dests = t.dests }))
      if n then stops[#stops + 1] = n end
    end
  end
  for _, a in ipairs(stops) do
    for _, dest in ipairs(a.dests) do
      local zone = dest:match(",%s*(.+)$") or dest
      local zm = FindZone(zone:lower())
      local cx, cy, ci
      if zm then cx, cy, ci = World(zm, 50, 50) end -- (all three values: "zm and World()" would keep only one)
      local best, bd
      for _, b in ipairs(stops) do
        if b ~= a and b.ride == a.ride and cx and b.inst == ci then
          local dd = math.sqrt((b.wx - cx) ^ 2 + (b.wy - cy) ^ 2)
          if b.m == zm then dd = 0 end
          if not bd or dd < bd then best, bd = b, dd end
        end
      end
      if best then Link(a, best, a.ride == "tram" and 60 or RIDE, "ride:" .. dest) end
    end
  end
  graph = { nodes = nodes, byMap = byMap }
  return graph
end

-- walking inside one zone, as a list of edges from p to every node in its zone
local function Walks(p, list)
  local out = {}
  for _, o in ipairs(list or {}) do
    if o ~= p then
      local dd = Dist(p, o)
      if dd then out[#out + 1] = { to = o, cost = dd * DETOUR / RUN, how = "walk" } end
    end
  end
  return out
end

-- opts.walk: on foot (and boats / zeppelins) only, no flights (Sunstone can't tell which flight paths you know),
-- and the target only from inside its own zone: never a straight line over a zone's mountains.
local function Route(start, target, opts)
  local g = Build()
  local walk = opts and opts.walk
  local goal = { kind = "goal" }
  local dist, prev, done = { [start] = 0 }, {}, {}
  local function Edges(n)
    if n == goal then return {} end
    local e = {}
    for _, x in ipairs(n.edges or {}) do if not (walk and x.how == "fly") then e[#e + 1] = x end end
    for _, x in ipairs(Walks(n, g.byMap[n.m])) do e[#e + 1] = x end
    if target.kind == "zone" and n.m == target.m then e[#e + 1] = { to = goal, cost = 0, how = "arrive" } end
    if target.kind == "point" then
      local dd = Dist(n, target.node)
      if dd and (n.m == target.node.m or (not walk and dd < 1500)) then e[#e + 1] = { to = goal, cost = dd * DETOUR / RUN, how = "walk" } end
    end
    return e
  end
  -- the start can also walk to every node in its own zone (Walks covers it); a point target in the
  -- same zone is reachable straight away
  while true do
    local cur, cd
    for n, v in pairs(dist) do if not done[n] and (not cd or v < cd) then cur, cd = n, v end end
    if not cur or cur == goal then break end
    done[cur] = true
    for _, e in ipairs(Edges(cur)) do
      local nd = cd + e.cost
      if not dist[e.to] or nd < dist[e.to] then dist[e.to], prev[e.to] = nd, { from = cur, how = e.how } end
    end
  end
  if not dist[goal] then return nil end
  local path, n = {}, goal
  while prev[n] do table.insert(path, 1, { node = n, from = prev[n].from, how = prev[n].how }); n = prev[n].from end
  return path, dist[goal]
end

-- the route as a few plain steps (rows for the window: t, d, m/x/y for Map and Go)
local function Steps(path, target)
  local rows, i = {}, 1
  while i <= #path do
    local s = path[i]
    local a, b = s.from, s.node
    if s.how == "fly" then
      rows[#rows + 1] = { t = string.format("Fly from %s to %s", a.name or "the flight master", b.name or "the flight master"),
                          d = Where(a) .. " → " .. MapName(b.m) .. "  (if you know that flight path)", m = a.m, x = a.x / 100, y = a.y / 100 }
    elseif s.how:sub(1, 5) == "ride:" then
      rows[#rows + 1] = { t = string.format("Take the %s to %s", a.label or "boat", s.how:sub(6)), d = "Leaves from " .. Where(a),
                          m = a.m, x = a.x / 100, y = a.y / 100 }
    elseif s.how == "cross" then
      rows[#rows + 1] = { t = "Cross into " .. MapName(b.m), d = "Border at " .. Where(a), m = a.m, x = a.x / 100, y = a.y / 100 }
    elseif s.how == "walk" and b.kind == "goal" then
      if target.kind == "point" then
        rows[#rows + 1] = { t = "Then on to " .. target.name, d = Where(target.node), m = target.node.m, x = target.node.x / 100, y = target.node.y / 100 }
      end
    end
    i = i + 1
  end
  if target.kind == "zone" then
    local lv = Load().levels[target.m]
    rows[#rows + 1] = { t = "You're in " .. MapName(target.m), d = lv and string.format("Levels %d-%d", lv[1], lv[2]) or nil }
  end
  return rows
end

-- For the quest route's arrow: the first place to head for on the way to a spot in another zone, the next zone
-- crossing (or boat / zeppelin) along the walking route, so the arrow and trail don't cut over mountains.
-- nil when the spot is in your own zone, or no way there is known (then the arrow points straight at it).
local hopCache = {}
function T.NextHop(here, p)
  if not here or not p or not p.m then return nil end
  if here.wx and p.wx then
    local fp = T.FlightOnTheWay(here, p)
    if fp then return fp.first end
  end
  if here.m == p.m then return nil end
  -- where you stand matters too (a zone can have several crossings): roughly, in tenths of the map
  local key = string.format("%d:%d,%d>%d:%.0f,%.0f", here.m, math.floor((here.x or 0) / 10), math.floor((here.y or 0) / 10),
                            p.m, p.x, p.y)
  if hopCache[key] ~= nil then return hopCache[key] or nil end
  local node = { m = p.m, x = p.x, y = p.y }
  node.wx, node.wy, node.inst = World(p.m, p.x, p.y)
  local hop = false
  if node.wx then
    local path = Route(here, { kind = "point", node = node, name = "" }, { walk = true })
    for _, s in ipairs(path or {}) do
      if s.how == "cross" then
        hop = { m = s.from.m, x = s.from.x, y = s.from.y, label = "Cross into " .. MapName(s.node.m) }
        break
      elseif s.how:sub(1, 5) == "ride:" then
        hop = { m = s.from.m, x = s.from.x, y = s.from.y, label = "Take the " .. (s.from.label or "boat") .. " to " .. s.how:sub(6) }
        break
      end
    end
  end
  hopCache[key] = hop
  return hop or nil
end

-- A spot on another continent: the boat, zeppelin or airship stop where the way there leaves this one (whether or not
-- you've been there: docks are always on the map). { m, x, y (0-100), wx, wy, inst, label }, or nil.
local dockCache = {}
function T.Dock(here, p)
  if not (here and here.m and here.wx and p and p.m) then return nil end
  local key = string.format("%d:%d,%d>%d:%.0f,%.0f", here.m, math.floor((here.x or 0) / 10), math.floor((here.y or 0) / 10), p.m, p.x, p.y)
  if dockCache[key] ~= nil then return dockCache[key] or nil end
  local node = { m = p.m, x = p.x, y = p.y }
  node.wx, node.wy, node.inst = World(p.m, p.x, p.y)
  local dock = false
  if node.wx then
    local path = Route(here, { kind = "point", node = node, name = "" }, { walk = true })
    for _, s in ipairs(path or {}) do
      -- (the ride that leaves this land: a tram between two cities doesn't count)
      if s.how:sub(1, 5) == "ride:" and s.from.inst == here.inst and s.node.inst ~= here.inst then
        local a = s.from
        dock = { m = a.m, x = a.x, y = a.y, wx = a.wx, wy = a.wy, inst = a.inst, label = "Take the " .. (a.label or "boat") .. " to " .. s.how:sub(6) }
        break
      end
    end
  end
  dockCache[key] = dock
  return dock or nil
end

-- For the route line on the world map: every crossing point (both sides of each border, or each boat stop) on the
-- walking route from a to b, so a leg into another zone bends through the passes. {} within one zone.
local hopsCache = {}
function T.Hops(a, b)
  if not a or not b or not a.m or not b.m then return {} end
  if a.wx and b.wx then
    local fp = T.FlightOnTheWay(a, b)
    if fp then return fp.points end
  end
  if a.m == b.m then return {} end
  local key = string.format("%d:%.0f,%.0f>%d:%.0f,%.0f", a.m, a.x, a.y, b.m, b.x, b.y)
  if hopsCache[key] then return hopsCache[key] end
  local start = { m = a.m, x = a.x, y = a.y }
  start.wx, start.wy, start.inst = World(a.m, a.x, a.y)
  local node = { m = b.m, x = b.x, y = b.y }
  node.wx, node.wy, node.inst = World(b.m, b.x, b.y)
  local out = {}
  if start.wx and node.wx then
    local path = Route(start, { kind = "point", node = node, name = "" }, { walk = true })
    for _, s in ipairs(path or {}) do
      if s.how == "cross" or s.how:sub(1, 5) == "ride:" then
        out[#out + 1] = { m = s.from.m, x = s.from.x, y = s.from.y }
        out[#out + 1] = { m = s.node.m, x = s.node.x, y = s.node.y }
      end
    end
  end
  hopsCache[key] = out
  return out
end

function T.Directions(target)
  local here = Here()
  if not here then return { { t = "Can't see where you are right now", d = "Try again outside (no position inside dungeons)." } } end
  if target.kind == "point" then
    target.node = { m = target.m, x = target.x, y = target.y }
    target.node.wx, target.node.wy, target.node.inst = World(target.m, target.x, target.y)
    local dd = Dist(here, target.node)
    if dd and dd < 400 then
      return { { t = target.name .. " is right around here", d = string.format("%s, about %d yards away", Where(target.node), dd),
                 m = target.m, x = target.x / 100, y = target.y / 100 } }
    end
  elseif here.m == target.m then
    local lv = Load().levels[target.m]
    return { { t = "You're already in " .. MapName(target.m), d = lv and string.format("Levels %d-%d", lv[1], lv[2]) or nil } }
  end
  if target.kind == "zone" and not (Build().byMap[target.m]) then
    local name = target.name or MapName(target.m)
    target = { kind = "point", m = target.m, x = 50, y = 50, name = name }
    target.node = { m = target.m, x = 50, y = 50 }
    target.node.wx, target.node.wy, target.node.inst = World(target.m, 50, 50)
  end
  -- On foot first (zone crossings, boats, zeppelins): a flight only as an extra line when it saves real time,
  -- since Sunstone can't tell which flight paths you know. Only a flight that's the sole way there leads.
  local name = target.name or MapName(target.m)
  local function Min(s) return math.max(1, math.floor(s / 60 + 0.5)) end
  local path, secs = Route(here, target, { walk = true })
  local fpath, fsecs = Route(here, target)
  if not path and not fpath then
    return { { t = "No route found to " .. name,
               d = "It may need a boat or flight Sunstone doesn't know yet, or it's on the other faction's side." } }
  end
  if not path then
    local rows = Steps(fpath, target)
    table.insert(rows, 1, { h = string.format("To %s: about %d min (needs a flight)", name, Min(fsecs)) })
    return rows
  end
  local rows = Steps(path, target)
  table.insert(rows, 1, { h = string.format("To %s on foot: about %d min", name, Min(secs)) })
  if fpath and fsecs and secs - fsecs >= 180 and fsecs <= secs * 0.67 then
    for _, s in ipairs(fpath) do
      if s.how == "fly" then
        local a, b = s.from, s.node
        table.insert(rows, 2, { t = string.format("Faster if you know the flight path: about %d min", Min(fsecs)),
                                d = string.format("Fly from %s (%s) to %s, %s", a.name or "the flight master", Where(a),
                                                  b.name or "the flight master", MapName(b.m)),
                                m = a.m, x = a.x / 100, y = a.y / 100 })
        break
      end
    end
  end
  return rows
end

function T.Nearest(code, label)
  local here = Here()
  local list = {}
  for _, n in ipairs(Load().npcs) do
    if n.code == code and Friendly(n.side) then
      local p = { m = n.m, x = n.x, y = n.y }
      p.wx, p.wy, p.inst = World(n.m, n.x, n.y)
      local dd = here and Dist(here, p)
      list[#list + 1] = { n = n, d = dd or math.huge }
    end
  end
  if #list == 0 then return { { t = "No " .. label .. " known for your faction" } } end
  table.sort(list, function(a, b) return a.d < b.d end)
  local rows = { { h = "Nearest " .. label .. (#list > 1 and "s" or "") } }
  for i = 1, math.min(4, #list) do
    local e = list[i]
    rows[#rows + 1] = { t = e.n.name .. ", " .. MapName(e.n.m),
                        d = string.format("%.1f, %.1f", e.n.x, e.n.y) .. (e.d < math.huge and string.format("  ·  %d yd", e.d) or "  ·  another continent"),
                        m = e.n.m, x = e.n.x / 100, y = e.n.y / 100 }
  end
  -- far away: add the way there
  if list[1].d > 1500 then
    local dir = T.Directions({ kind = "point", m = list[1].n.m, x = list[1].n.x, y = list[1].n.y, name = list[1].n.name })
    for _, r in ipairs(dir) do rows[#rows + 1] = r end
  end
  return rows
end

---------------------------------------------------------------------------
-- The search box: works out what you asked for
---------------------------------------------------------------------------
function T.Search(text)
  local q = (text or ""):lower():gsub("[%?%!%.]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  for _, p in ipairs({ "^how do i get to ", "^how do you get to ", "^how to get to ", "^how can i get to ", "^directions to ",
                       "^where is the nearest ", "^where's the nearest ", "^wheres the nearest ", "^where is a ", "^where is ",
                       "^where's ", "^wheres ", "^nearest ", "^closest ", "^find ", "^take me to ", "^go to ", "^the ", "^a " }) do
    q = q:gsub(p, "")
  end
  if q == "" then return { { t = "Type a place or a service", d = "e.g. Thousand Needles, Ratchet, Wailing Caverns, bank, innkeeper, flight master, warlock trainer" } } end
  local code, label = FindService(q)
  local also = NS.Places and NS.Places.Elsewhere(q) or {}
  local sure = NS.Places and NS.Places.best or 99 -- how well the rest of Sunstone answers it (0: called just that)
  local function With(rows) -- what else goes by that name
    for _, r in ipairs(also) do rows[#rows + 1] = r end
    return rows
  end
  if code then return With(T.Nearest(code, label)) end
  local found = NS.Places and NS.Places.Find(q) or {}
  local best = found[1]
  local function Other(rows, from)
    local n = 0
    for k = from, #found do
      local f = found[k]
      if f.x and f.kind ~= "dungeon" then
        if n == 0 then rows[#rows + 1] = { h = "Places like that" } end
        n = n + 1
        local row = NS.Places.PlaceRow(f.name .. ", " .. MapName(f.m), f.m, f.x, f.y, string.format("%.1f, %.1f", f.x, f.y), "spl" .. k)
        rows[#rows + 1] = row
      end
    end
    return rows
  end
  local function Way(f)
    if f.kind == "zone" then
      local rows = T.Directions({ kind = "zone", m = f.m, name = f.name })
      local here = T.Here and T.Here()
      if not (here and here.m == f.m) then table.insert(rows, 1, NS.Places.PlaceRow(f.name, f.m, 50, 50, "Zone", "splz")) end
      return rows
    end
    local rows = T.Directions({ kind = "point", m = f.m, x = f.x, y = f.y, name = f.name })
    table.insert(rows, 1, NS.Places.PlaceRow(f.name, f.m, f.x, f.y, string.format("%s %.1f, %.1f", MapName(f.m), f.x, f.y), "splp"))
    return rows
  end
  if best and best.kind ~= "dungeon" and best.score <= 1 and best.score <= sure and not SHORT[q] then return With(Other(Way(best), 2)) end
  local dg = FindDungeon(q)
  if dg then
    local rows = T.Directions({ kind = "point", m = dg.m, x = dg.x, y = dg.y, name = dg.name .. " (entrance)" })
    if dg.lvl > 0 then table.insert(rows, 2, { t = dg.name .. ": recommended from about level " .. dg.lvl }) end
    return With(rows)
  end
  if best and best.score < 10 and best.kind ~= "dungeon" then
    if sure < best.score then -- something is called just that: it first, the place after
      local rows = also
      for _, r in ipairs(Other(Way(best), 2)) do rows[#rows + 1] = r end
      return rows
    end
    return With(Other(Way(best), 2))
  end
  local town = FindTown(q)
  if town then return With(T.Directions(town)) end
  local zm = FindZone(q)
  if zm then return With(T.Directions({ kind = "zone", m = zm, name = MapName(zm) })) end
  if #also > 0 and sure < 10 then return also end
  if best then -- a letter or two off
    local rows = Way(best)
    table.insert(rows, 1, { t = "Closest name: " .. best.name, d = "Nothing is spelled \"" .. NS.Clean(text, 40) .. "\".", still = true })
    return With(Other(rows, 2))
  end
  if #also > 0 then return also end
  return { { t = "Nothing found for \"" .. NS.Clean(text, 40) .. "\"",
             d = "Try a place (Gadgetzan), a zone, a dungeon, a faction, a quest, an item, a recipe, or a service (bank, inn, flight master, mailbox, warlock trainer)." } }
end

---------------------------------------------------------------------------
-- The flight paths you know: learned from the flight map whenever you open one (the world map's own "undiscovered"
-- flag isn't reliable on Forever), and from MapUtils' list for this character if that addon kept one.
-- cdb.flights["map:x:y" of the flight master] = the flight point's name
---------------------------------------------------------------------------
local function FlightKey(f) return string.format("%d:%.1f:%.1f", f.m, f.x, f.y) end
local function Flights()
  NS.cdb.flights = type(NS.cdb.flights) == "table" and NS.cdb.flights or {}
  return NS.cdb.flights
end
function T.Known() return Flights() end
T.version = 0
local function NearestMaster(wx, wy, inst, within)
  local best, bd
  for _, f in ipairs(Load().flight) do
    if Friendly(f.side) then
      local fx, fy, fi = World(f.m, f.x, f.y)
      if fx and fi == inst then
        local d = math.sqrt((fx - wx) ^ 2 + (fy - wy) ^ 2)
        if d <= within and (not bd or d < bd) then best, bd = f, d end
      end
    end
  end
  return best
end
local function Learn(f, name)
  local k = f and FlightKey(f)
  if not k or Flights()[k] then return false end
  Flights()[k] = NS.Clean(name or "", 60)
  T.version = T.version + 1
  return true
end

function T.LearnFlights() -- the flight map is open
  local hbd = NS.HBD()
  if not (hbd and NumTaxiNodes and TaxiNodeName and TaxiNodeGetType) then return end
  local kinds, new = {}, false
  for i = 1, NumTaxiNodes() do
    local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
    if type(name) == "string" and name ~= "" then kinds[name] = kind end
    if kind == "CURRENT" then
      local wx, wy, inst = hbd:GetPlayerWorldPosition()
      if wx then new = Learn(NearestMaster(wx, wy, inst, 120), name) or new end
    end
  end
  local m, seen = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"), {}
  while m and m ~= 0 and not seen[m] do
    seen[m] = true
    local ok, nodes = pcall(function() return C_TaxiMap.GetAllTaxiNodes(m) end)
    for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
      local kind = kinds[n.name]
      if (kind == "REACHABLE" or kind == "CURRENT") and n.position then
        local x, y = n.position.x, n.position.y
        if n.position.GetXY then x, y = n.position:GetXY() end
        local ok2, wx, wy, inst = pcall(hbd.GetWorldCoordinatesFromZone, hbd, x, y, m)
        if ok2 and wx then new = Learn(NearestMaster(wx, wy, inst, 300), n.name) or new end
      end
    end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    m = info and info.parentMapID
  end
  if new and NS.Route and NS.cdb.route and NS.cdb.route.enabled then
    NS.Debounce("route flights", 3, function() NS.Route.Compute(true) end)
  end
end

local function SeedFlights()
  local list = type(_G.MAUTTAB) == "table" and type(_G.MAUTTAB.flightKnowledge) == "table" and UnitGUID
    and _G.MAUTTAB.flightKnowledge[UnitGUID("player") or ""]
  local hbd = NS.HBD()
  if not (type(list) == "table" and hbd and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
  local done = {}
  for _, f in ipairs(Load().flight) do
    if not done[f.m] then
      done[f.m] = true
      local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, f.m)
      for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
        if n.nodeID and list[n.nodeID] and n.position then
          local x, y = n.position.x, n.position.y
          if n.position.GetXY then x, y = n.position:GetXY() end
          local ok2, wx, wy, inst = pcall(hbd.GetWorldCoordinatesFromZone, hbd, x, y, f.m)
          if ok2 and wx then Learn(NearestMaster(wx, wy, inst, 200), n.name) end
        end
      end
    end
  end
end

-- The nearest flight master of your side whose flight path you haven't learned, within a short walk; only once at least
-- one flight map has been read (before that, nothing is known about which you have)
function T.NewFlight()
  if next(Flights()) == nil then return nil end
  local here = Here()
  if not here then return nil end
  local best, bd
  for _, f in ipairs(Load().flight) do
    if Friendly(f.side) and not Flights()[FlightKey(f)] then
      local wx, wy, inst = World(f.m, f.x, f.y)
      if wx and inst == here.inst then
        local d = math.sqrt((wx - here.wx) ^ 2 + (wy - here.wy) ^ 2)
        if d < 1500 and (not bd or d < bd) then best, bd = { name = f.name, p = { m = f.m, x = f.x / 100, y = f.y / 100, wx = wx, wy = wy, inst = inst } }, d end
      end
    end
  end
  return best
end

-- "Crossroads" from "Crossroads, The Barrens"
local function FlightName(f)
  local n = Flights()[FlightKey(f)]
  n = type(n) == "string" and n:match("^([^,]+)") or nil
  return (n and n ~= "") and n or MapName(f.m)
end

---------------------------------------------------------------------------
-- Travel time between two spots (the quest route's order is worked out with it): straight across a zone until the
-- walk has been measured around the terrain (T.Measure), through the zone crossings into another zone, or by the
-- flight paths you know when that's quicker.
---------------------------------------------------------------------------
local IN_ZONE, IN_CITY, ROUGH = 1.06, 1.3, 1.4   -- how much longer than a straight line, until it's measured (hopeful, so a
local OVER_BORDER = 1.15                         -- good way is tried and measured rather than never looked at)
local AIR, FLY_STOP = 1.5, 25                    -- flights bend too; seconds to talk, take off and land
local CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
local hubs, hubsFor = {}, nil  -- [instance] = { list, byMap, W, F, N }
local where = {}               -- [location key] = its walking times to every hub
local measured, count = {}, 0  -- [spot][spot] = how many times longer than the straight line (false = no way found)

local function Key(p) return math.floor(p.wx / 4 + 10000) * 100000 + math.floor(p.wy / 4 + 10000) end
local function Nothing() end

local function Reset()
  hubs, where, hopCache, hopsCache = {}, {}, {}, {}
  hubsFor = (graph and tostring(graph) or "") .. T.version
end

-- Everything walkable or flyable between zones on one continent: crossings, and your flight masters.
local function Hubs(inst, yield)
  Build()
  if hubsFor ~= tostring(graph) .. T.version then Reset() end
  if hubs[inst] then return hubs[inst] end
  if not yield then return nil end -- only worked out in the background
  local h = { list = {}, byMap = {}, flights = 0 }
  local at = {}
  for _, n in ipairs(graph.nodes) do
    local known = n.kind == "flight" and Flights()[FlightKey(n)] ~= nil
    if n.inst == inst and (n.kind == "cross" or n.kind == "arrive" or known) then
      h.list[#h.list + 1] = n
      at[n] = #h.list
      h.byMap[n.m] = h.byMap[n.m] or {}
      table.insert(h.byMap[n.m], #h.list)
      if known then h.flights = h.flights + 1 end
    end
  end
  local N = #h.list
  local W = {}
  for a = 1, N do
    local row, n = {}, h.list[a]
    for b = 1, N do
      local o = h.list[b]
      row[b] = a == b and 0 or (n.m == o.m and Dist(n, o) * (CITIES[n.m] and IN_CITY or 1.2) / RUN) or math.huge
    end
    for _, e in ipairs(n.edges or {}) do
      if e.how == "cross" and at[e.to] then row[at[e.to]] = math.min(row[at[e.to]], 5 + (Dist(n, e.to) or 0) / RUN) end
    end
    W[a] = row
    yield()
  end
  local function Shortest(X, nxt)
    for k = 1, N do
      local rk = X[k]
      for i = 1, N do
        local ri = X[i]
        local ik = ri[k]
        if ik < math.huge and i ~= k then
          for j = 1, N do
            local v = ik + rk[j]
            if v < ri[j] - 0.01 then
              ri[j] = v
              if nxt then nxt[i][j] = nxt[i][k] end
            end
          end
        end
      end
      yield()
    end
  end
  Shortest(W)
  h.W = W
  if h.flights >= 2 then
    local F, nxt = {}, {}
    for a = 1, N do
      F[a], nxt[a] = {}, {}
      for b = 1, N do
        F[a][b], nxt[a][b] = W[a][b], b
        local x, y = h.list[a], h.list[b]
        if a ~= b and x.kind == "flight" and y.kind == "flight" then
          local v = Dist(x, y) * AIR / FLY + FLY_STOP
          if v < F[a][b] then F[a][b] = v end
        end
      end
    end
    h.direct = {}
    for a = 1, N do h.direct[a] = {} for b = 1, N do h.direct[a][b] = F[a][b] < W[a][b] - 0.01 end end
    Shortest(F, nxt)
    h.F, h.N = F, nxt
  end
  hubs[inst] = h
  return h
end

-- A spot's walking (and flying) time to every hub, kept for the session
local function Place(p, h)
  local key = Key(p)
  local w = where[key]
  if w then return w end
  w = { near = {}, W = {}, F = h.F and {} or nil }
  for _, i in ipairs(h.byMap[p.m] or {}) do
    w.near[i] = math.sqrt((h.list[i].wx - p.wx) ^ 2 + (h.list[i].wy - p.wy) ^ 2) * (CITIES[p.m] and IN_CITY or 1.2) / RUN
  end
  for j = 1, #h.list do
    local bw, bf
    for i, t in pairs(w.near) do
      local v = t + h.W[i][j]
      if not bw or v < bw then bw = v end
      if h.F then
        v = t + h.F[i][j]
        if not bf or v < bf then bf = v end
      end
    end
    w.W[j] = bw or math.huge
    if w.F then w.F[j] = bf or math.huge end
  end
  where[key] = w
  return w
end

local function Measurable(a, b, line)
  local inst = b.inst or a.inst
  return line * RUN <= T.LEG_MAX and inst and NS.Nav and NS.Nav.Has and NS.Nav.Has(inst) and not CITIES[a.m or 0] and not CITIES[b.m or 0]
end
-- spots close together share a measurement: 40-yard squares for longer walks, 8-yard ones for short ones
local function Square(p, size) return (math.floor(p.wx / size) + 20000) * 100000 + math.floor(p.wy / size) + 20000 end
local function Squares(a, b, line)
  local size = line * RUN > 250 and 40 or 8
  return Square(a, size) * 2 + (size == 8 and 1 or 0), Square(b, size) * 2 + (size == 8 and 1 or 0)
end
local function Measured(a, b, line)
  local ka, kb = Squares(a, b, line)
  local m = measured[ka]
  return m and m[kb]
end
local function StraightSecs(a, b) return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) / RUN end

-- -> seconds, and true when flying is the quicker way
function T.Seconds(a, b)
  local line = StraightSecs(a, b)
  if line < 1 then return line end
  local m = Measured(a, b, line)
  local walk = m and line * m or nil
  local same = a.m ~= nil and a.m == b.m
  if not walk and (same or not a.m or not b.m) then walk = line * (a.m and CITIES[a.m] and IN_CITY or a.m and IN_ZONE or ROUGH) end
  local h = hubs[a.inst or 0] or hubs[b.inst or 0]
  if not h or not a.m or not b.m then return walk or line * ROUGH end
  local pa = Place(a, h)
  local pb = Place(b, h)
  local viaW, viaF = math.huge, math.huge
  if not walk and not m and m ~= false and Measurable(a, b, line) then walk = line * OVER_BORDER end
  if not walk then
    for j, t in pairs(pb.near) do viaW = math.min(viaW, pa.W[j] + t) end
    walk = viaW < math.huge and math.max(viaW, line) or line * ROUGH
  end
  if pa.F and line > 120 then
    for j, t in pairs(pb.near) do viaF = math.min(viaF, pa.F[j] + t) end
    if viaF < walk - 45 then return viaF, true end
  end
  return walk
end

-- Get ready for a set of spots (a little each frame): the crossings of this continent, and each spot's way to them
function T.Prepare(from, nodes, yield)
  local h = Hubs(from.inst, yield)
  if not h then return end
  local n = 0
  for _ in pairs(where) do n = n + 1 end
  if n > 1500 then where = {} end
  for _, nd in ipairs(nodes) do
    for _, c in ipairs(nd.cands) do
      c.inst = c.inst or from.inst
      Place(c, h)
      yield()
    end
  end
end

-- Measures one walk around the terrain (inside a background job). True when that's new.
T.LEG_MAX = 2600 -- yards: longer walks go by their zone crossings
T.effort = 0
function T.Measure(a, b)
  local Nv = NS.Nav
  local inst = b.inst or a.inst
  local line = StraightSecs(a, b) * RUN
  if line < 60 or not Measurable(a, b, line / RUN) then return false end
  local ka, kb = Squares(a, b, line / RUN)
  if measured[ka] and measured[ka][kb] ~= nil then return false end
  if count > 4000 then measured, count = {}, 0 end
  local len, why, cells = Nv.Length(inst, a.wx, a.wy, b.wx, b.wy, 1500 + math.floor(line * 6))
  T.effort = T.effort + (cells or 0)
  local ratio = len and math.max(1, len / line) or (type(why) == "string" and why:find("too far", 1, true) and 1.7) or false
  measured[ka] = measured[ka] or {}
  measured[kb] = measured[kb] or {}
  measured[ka][kb], measured[kb][ka] = ratio, ratio
  count = count + 1
  return true
end

-- The flight on the way from a to b, when flying is quicker: the place to go first, and the bends for the map line
function T.FlightOnTheWay(a, b)
  if not (a and b and a.wx and b.wx and a.m and b.m) then return nil end
  local h = hubs[a.inst or 0] or hubs[b.inst or 0]
  if not (h and h.F) then return nil end
  local _, fly = T.Seconds(a, b)
  if not fly then return nil end
  local pa, pb = Place(a, h), Place(b, h)
  local bi, bj, bd
  for i, t in pairs(pa.near) do
    for j, u in pairs(pb.near) do
      local v = t + h.F[i][j] + u
      if not bd or v < bd then bi, bj, bd = i, j, v end
    end
  end
  if not bi then return nil end
  local first, points, guard = nil, {}, 0
  local i = bi
  points[1] = { m = h.list[i].m, x = h.list[i].x, y = h.list[i].y }
  while i ~= bj and guard < 60 do
    guard = guard + 1
    local j = h.N[i][bj]
    if not j or j == i then break end
    local x, y = h.list[i], h.list[j]
    points[#points + 1] = { m = y.m, x = y.x, y = y.y }
    if not first then
      if h.direct[i][j] and x.kind == "flight" then
        first = { m = x.m, x = x.x, y = x.y, label = "Fly from " .. FlightName(x) .. " to " .. FlightName(y), fly = true }
      elseif x.m ~= y.m then
        first = { m = x.m, x = x.x, y = x.y, label = "Cross into " .. MapName(y.m) }
      end
    end
    i = j
  end
  return first and { first = first, points = points } or nil
end

-- where you can sell, rest and so on: every friendly service of these kinds
local points
function T.Points(codes)
  if not points then
    points = {}
    for _, n in ipairs(Load().npcs) do
      if Friendly(n.side) then
        local wx, wy, inst = World(n.m, n.x, n.y)
        if wx then points[#points + 1] = { code = n.code, name = n.name, m = n.m, x = n.x, y = n.y, wx = wx, wy = wy, inst = inst } end
      end
    end
  end
  local out = {}
  for _, p in ipairs(points) do if codes[p.code] then out[#out + 1] = p end end
  return out
end

-- the map library can change maps on zone changes; rebuild the graph when the faction data could differ
function T:Init()
  NS.On("PLAYER_ENTERING_WORLD", function()
    graph, points = nil, nil
    C_Timer.After(6, function() NS.Safe("flight paths", SeedFlights) end)
  end)
  NS.On("TAXIMAP_OPENED", function() C_Timer.After(0.3, function() NS.Safe("flight paths", T.LearnFlights) end) end)
end
