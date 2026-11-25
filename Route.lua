-- Sunstone: shortest quest route.
-- Takes every unfinished objective and every turn-in in your quest log, looks up where they
-- are (QuestDB.lua), and works out the quickest order to do them in, with
-- the rule that a quest's objectives come before its turn-in, and finished quests handed in along
-- the way. The next stop goes to the arrow (Arrow.lua; Trail.lua draws the walkable trail to it); every
-- stop is numbered on the world map. A first plan is there at once; a better one, with real walking
-- times around the terrain, is worked out in the background. It re-plans when an objective
-- finishes, the quest log changes, or your bags fill up.

local _, NS = ...
local R = NS.Module("Route")
NS.Route = R

local sqrt = math.sqrt
local function D(a, b)
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  return sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- The order of the stops.
-- What counts is time, not yards: walking between stops (Travel.lua: around mountains, through the passes, by the
-- flight paths you know) plus the time each stop's work takes. On top of that, a finished quest costs something for
-- every second it's carried around: its XP isn't helping you yet, and its items sit in your bags. So the plan goes
-- through a town to hand things in as soon as that's worth the detour, then carries on with the rest.
-- Pure Lua, no game calls (tested outside the game).

---------------------------------------------------------------------------
local Solver
do
Solver = {}
NS.RouteSolver = Solver

local floor, max, min, huge = math.floor, math.max, math.min, math.huge
local RUN = 7 -- yards a second on foot

Solver.HOLD = 0.025       -- a finished quest you're carrying: each second costs this much (on top of the second itself)
Solver.XPW = 0.25         -- and this much times the share of a level its XP is worth
Solver.STICK = 20         -- seconds: a fresh plan has to beat the one you're following by this much
Solver.SMALL_DETOUR = 36  -- seconds (about 250 yards): handing in a finished quest is always worth this much
Solver.DETOUR_SHARE = 0.35 -- or this share of the leg it's put into
Solver.HARD = 0.2         -- a quest this many levels above you takes that share longer per level

local function Straight(a, b) return D(a, b) / RUN end

---------------------------------------------------------------------------
-- The problem: nodes[i] = { cands = { {wx=, wy=}, ... }, deps = { nodes that must come first }, ready = true when it's a
-- finished quest's turn-in, work = seconds it takes there, hold = cost a second while its quest is finished and carried,
-- share = its XP as a share of your level, ql = the quest's level, w = extra weight on getting here early }
---------------------------------------------------------------------------
local function Setup(start, nodes, opts)
  local ctx = { nodes = nodes, start = start, travel = opts and opts.travel or Straight, level = opts and opts.level, n = #nodes }
  local ids, spots = {}, { [0] = start }
  local K = 0
  for i, nd in ipairs(nodes) do
    ids[i] = {}
    for c, p in ipairs(nd.cands) do
      K = K + 1
      ids[i][c], spots[K] = K, p
    end
  end
  ctx.ids, ctx.spots, ctx.K = ids, spots, K + 1
  ctx.M = {}
  -- which turn-ins wait for each objective
  ctx.waits, ctx.ndeps, ctx.isDep = {}, {}, {}
  ctx.H0, ctx.E0 = 0, 0
  ctx.hold, ctx.early = {}, {}
  for i, nd in ipairs(nodes) do
    local deps = nd.deps or {}
    ctx.ndeps[i] = #deps
    local handin = nd.ready or #deps > 0 or nd.kind == "turnin"
    ctx.hold[i] = handin and (nd.hold or Solver.HOLD) or 0
    ctx.early[i] = (nd.w or 0) + (nd.early or 0)
    ctx.E0 = ctx.E0 + ctx.early[i]
    if handin and #deps == 0 then ctx.H0 = ctx.H0 + ctx.hold[i] end
    for _, d in ipairs(deps) do
      ctx.waits[d] = ctx.waits[d] or {}
      table.insert(ctx.waits[d], i)
    end
  end
  return ctx
end

local function T(ctx, a, b) -- seconds between two spots (0 = where you are)
  if a == b then return 0 end
  local M, k = ctx.M, a * ctx.K + b
  local v = M[k]
  if not v then
    v = ctx.travel(ctx.spots[a], ctx.spots[b]) or huge
    M[k] = v
    M[b * ctx.K + a] = v
  end
  return v
end

-- What an order costs; huge when a turn-in comes before its objectives. `bound`: stop early once it's worse than that.
local left = {}
local function Evaluate(ctx, order, cand, bound)
  local nodes, ids, ndeps, hold, early, waits = ctx.nodes, ctx.ids, ctx.ndeps, ctx.hold, ctx.early, ctx.waits
  local M, K, L = ctx.M, ctx.K, ctx.level
  local cost, prev, H, E, acc = 0, 0, ctx.H0, ctx.E0, 0
  for i = 1, ctx.n do left[i] = ndeps[i] end
  for k = 1, #order do
    local i = order[k]
    if left[i] > 0 then return huge end
    local id = ids[i][cand[i]]
    local dt = (prev == id) and 0 or M[prev * K + id] or T(ctx, prev, id)
    local nd = nodes[i]
    local work = nd.work or 0
    if work > 0 and L and nd.ql and nd.ql > L + acc then work = work * (1 + Solver.HARD * min(5, nd.ql - L - acc)) end
    cost = cost + (dt + work) * (1 + H + E)
    if bound and cost >= bound then return cost end
    prev = id
    E = E - early[i]
    if hold[i] > 0 then H = H - hold[i] end
    if nd.share then acc = acc + nd.share end
    local w = waits[i]
    if w then
      for x = 1, #w do
        local j = w[x]
        left[j] = left[j] - 1
        if left[j] == 0 then H = H + hold[j] end
      end
    end
  end
  return cost
end

local function Seconds(ctx, order, cand) -- just the walking and the work
  local t, prev = 0, 0
  for k = 1, #order do
    local id = ctx.ids[order[k]][cand[order[k]]]
    t = t + T(ctx, prev, id) + (ctx.nodes[order[k]].work or 0)
    prev = id
  end
  return t
end

---------------------------------------------------------------------------
-- A first order
---------------------------------------------------------------------------
-- go to the nearest stop that's allowed next (hand-ins count as a bit nearer)
local function Greedy(ctx, favour)
  local n, order, cand, placed, prev = ctx.n, {}, {}, {}, 0
  for _ = 1, n do
    local bi, bc, bd
    for i = 1, n do
      if not placed[i] then
        local ok = true
        for _, d in ipairs(ctx.nodes[i].deps or {}) do if not placed[d] then ok = false break end end
        if ok then
          local f = ctx.hold[i] > 0 and favour or 1
          for c, id in ipairs(ctx.ids[i]) do
            local dd = T(ctx, prev, id) * f
            if not bd or dd < bd then bi, bc, bd = i, c, dd end
          end
        end
      end
    end
    if not bi then break end
    placed[bi] = true
    order[#order + 1], cand[bi] = bi, bc
    prev = ctx.ids[bi][bc]
  end
  return order, cand
end

-- last time's order, with whatever is new put where it costs the least
local function Warm(ctx, keys)
  local byKey = {}
  for i, nd in ipairs(ctx.nodes) do if nd.key then byKey[nd.key] = i end end
  local order, cand, placed = {}, {}, {}
  for _, k in ipairs(keys) do
    local i = byKey[k]
    if i and not placed[i] then
      order[#order + 1], placed[i] = i, true
      cand[i] = 1
    end
  end
  if #order == 0 then return nil end
  for k = 1, #order do -- the best spot for each, in order
    local i, prev, best, bd = order[k], k > 1 and ctx.ids[order[k - 1]][cand[order[k - 1]]] or 0, 1, nil
    for c, id in ipairs(ctx.ids[i]) do
      local dd = T(ctx, prev, id)
      if not bd or dd < bd then best, bd = c, dd end
    end
    cand[i] = best
  end
  -- objectives first, so a new turn-in finds its objectives already placed
  for pass = 1, 2 do
    for i = 1, ctx.n do
      if not placed[i] and (pass == 2 or ctx.ndeps[i] == 0) then
        placed[i] = true
        local best, bj, bc
        for j = 1, #order + 1 do
          table.insert(order, j, i)
          for c = 1, #ctx.ids[i] do
            cand[i] = c
            local prev = j > 1 and ctx.ids[order[j - 1]][cand[order[j - 1]]] or 0
            local id, nxt = ctx.ids[i][c], order[j + 1]
            local add = T(ctx, prev, id) + (nxt and T(ctx, id, ctx.ids[nxt][cand[nxt]]) or 0)
            if not best or add < best then
              local f = ctx.ndeps[i] == 0
              if not f then
                f = true
                local pos = {}
                for x, o in ipairs(order) do pos[o] = x end
                for _, d in ipairs(ctx.nodes[i].deps) do if (pos[d] or 0) > j then f = false end end
              end
              if f then best, bj, bc = add, j, c end
            end
          end
          table.remove(order, j)
        end
        if not bj then bj, bc = #order + 1, 1 end
        table.insert(order, bj, i)
        cand[i] = bc
      end
    end
  end
  if Evaluate(ctx, order, cand) == huge then return nil end
  return order, cand
end

---------------------------------------------------------------------------
-- Making it better
---------------------------------------------------------------------------
-- stops that are handed in at the same place (a town): moved there together
local function Towns(ctx)
  local groups, of = {}, {}
  for i, nd in ipairs(ctx.nodes) do
    if ctx.hold[i] > 0 or nd.kind == "pickup" then
      local p, g = nd.cands[1], nil
      for _, t in ipairs(groups) do
        for _, o in ipairs(t) do if D(ctx.nodes[o].cands[1], p) <= 220 then g = t break end end
        if g then break end
      end
      if not g then g = {}; groups[#groups + 1] = g end
      g[#g + 1] = i
      of[i] = g
    end
  end
  return groups, of
end

local function Copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

-- `tick` returns true when time's up (it may also give the game a frame in between)
local function Improve(ctx, order, cand, tick)
  local n, ids = #order, ctx.ids
  local cost = Evaluate(ctx, order, cand)
  local EPS = 0.05
  local try = {}
  local towns = ctx.towns
  local slack = 200 * min(1, ctx.E0 + ctx.H0) -- the more there is to get done early, the longer the detours worth trying
  local improved, passes = true, 0

  local function Accept(c)
    for k = 1, n do order[k] = try[k] end
    cost, improved = c, true
  end

  while improved and passes < 40 do
    improved, passes = false, passes + 1

    -- a) which of its spots each stop is done at (which camp of a creature)
    for k = 1, n do
      local i = order[k]
      local list = ids[i]
      if #list > 1 then
        local prev = k > 1 and ids[order[k - 1]][cand[order[k - 1]]] or 0
        local nx = k < n and ids[order[k + 1]][cand[order[k + 1]]] or nil
        local keep = cand[i]
        local now = T(ctx, prev, list[keep]) + (nx and T(ctx, list[keep], nx) or 0)
        local best, bd = keep, now
        for c, id in ipairs(list) do
          local dd = T(ctx, prev, id) + (nx and T(ctx, id, nx) or 0)
          if dd < bd - EPS then best, bd = c, dd end
        end
        if best ~= keep then
          cand[i] = best
          local c = Evaluate(ctx, order, cand, cost)
          if c < cost - EPS then cost, improved = c, true else cand[i] = keep end
        end
      end
    end
    if tick() then break end

    -- b) a visit to a town: everything there that can already be handed in at that point
    for _, town in ipairs(towns) do
      for j = 0, n - 1 do
        local pos = {}
        for k = 1, n do pos[order[k]] = k end
        local moved, any = {}, false
        for _, i in ipairs(town) do
          if pos[i] > j + 1 then
            local ok = true
            for _, d in ipairs(ctx.nodes[i].deps or {}) do if pos[d] > j then ok = false break end end
            if ok then moved[i], any = true, true end
          end
        end
        if any then
          local x = 0
          for k = 1, j do x = x + 1; try[x] = order[k] end
          for k = j + 1, n do if moved[order[k]] then x = x + 1; try[x] = order[k] end end
          for k = j + 1, n do if not moved[order[k]] then x = x + 1; try[x] = order[k] end end
          local c = Evaluate(ctx, try, cand, cost)
          if c < cost - EPS then Accept(c) end
        end
      end
      if tick() then return cost end
    end

    -- c) a stretch of one to six stops moved elsewhere (a whole visit, a camp with several objectives)
    for len = 1, min(6, n - 1) do
      local i = 1
      while i + len - 1 <= n do
        local best, bj, bflip
        local a = i > 1 and ids[order[i - 1]][cand[order[i - 1]]] or 0
        local f, l = ids[order[i]][cand[order[i]]], ids[order[i + len - 1]][cand[order[i + len - 1]]]
        local b = i + len <= n and ids[order[i + len]][cand[order[i + len]]] or nil
        local gain = T(ctx, a, f) + (b and T(ctx, l, b) or 0) - (b and T(ctx, a, b) or 0)
        for j = 0, n do
          if j < i - 1 or j > i + len - 1 then
            local p = j > 0 and ids[order[j]][cand[order[j]]] or 0
            local q = j < n and ids[order[j + 1]][cand[order[j + 1]]] or nil
            local base = q and T(ctx, p, q) or 0
            for flip = 0, (len > 1 and 1 or 0) do
              local h, t = (flip == 1) and l or f, (flip == 1) and f or l
              local add = T(ctx, p, h) + (q and T(ctx, t, q) or 0) - base
              -- a longer walk can still be the better order (something handed in sooner), but not a much longer one
              if add - gain < max(30, gain * 0.5) + slack then
                local x = 0
                local function Put(from, to) for k = from, to do x = x + 1; try[x] = order[k] end end
                local function Seg()
                  if flip == 1 then for k = i + len - 1, i, -1 do x = x + 1; try[x] = order[k] end else Put(i, i + len - 1) end
                end
                if j < i then Put(1, j) Seg() Put(j + 1, i - 1) Put(i + len, n)
                else Put(1, i - 1) Put(i + len, j) Seg() Put(j + 1, n) end
                local c = Evaluate(ctx, try, cand, best or cost)
                if c < (best or cost) - EPS then best, bj, bflip = c, j, flip end
              end
            end
          end
        end
        if best then
          local x, j = 0, bj
          local function Put(from, to) for k = from, to do x = x + 1; try[x] = order[k] end end
          local function Seg()
            if bflip == 1 then for k = i + len - 1, i, -1 do x = x + 1; try[x] = order[k] end else Put(i, i + len - 1) end
          end
          if j < i then Put(1, j) Seg() Put(j + 1, i - 1) Put(i + len, n)
          else Put(1, i - 1) Put(i + len, j) Seg() Put(j + 1, n) end
          Accept(best)
        else
          i = i + 1
        end
        if tick() then return cost end
      end
    end

    -- d) a stretch walked the other way round
    if not improved then
      for i = 1, n - 1 do
        for j = i + 1, n do
          local a = i > 1 and ids[order[i - 1]][cand[order[i - 1]]] or 0
          local x1, x2 = ids[order[i]][cand[order[i]]], ids[order[j]][cand[order[j]]]
          local b = j < n and ids[order[j + 1]][cand[order[j + 1]]] or nil
          local delta = T(ctx, a, x2) + (b and T(ctx, x1, b) or 0) - T(ctx, a, x1) - (b and T(ctx, x2, b) or 0)
          if delta < 60 then
            for k = 1, n do try[k] = (k >= i and k <= j) and order[i + j - k] or order[k] end
            local c = Evaluate(ctx, try, cand, cost)
            if c < cost - EPS then Accept(c) end
          end
        end
        if tick() then return cost end
      end
    end
  end
  return cost
end

-- Right past it: a finished quest handed in wherever that's only a small detour from where the route goes anyway.
function Solver.PullReady(ctx, order, cand)
  local ids = ctx.ids
  local k = 2
  while k <= #order do
    local i = order[k]
    if ctx.hold[i] > 0 then
      local pos = {}
      for x = 1, #order do pos[order[x]] = x end
      local first = 0
      for _, d in ipairs(ctx.nodes[i].deps or {}) do first = max(first, pos[d]) end
      for j = first, k - 2 do
        local a = j > 0 and ids[order[j]][cand[order[j]]] or 0
        local b = ids[order[j + 1]][cand[order[j + 1]]]
        local leg = T(ctx, a, b)
        local bc, bd
        for c, id in ipairs(ids[i]) do
          local dd = T(ctx, a, id) + T(ctx, id, b) - leg
          if not bd or dd < bd then bc, bd = c, dd end
        end
        local limit = ctx.nodes[i].ready and max(Solver.SMALL_DETOUR, min(120, Solver.DETOUR_SHARE * leg)) or Solver.SMALL_DETOUR / 2
        if bd and bd <= limit then
          table.remove(order, k)
          cand[i] = bc
          table.insert(order, j + 1, i)
          break
        end
      end
    end
    k = k + 1
  end
  return order, cand
end

function Solver.Feasible(nodes, route)
  local pos = {}
  for k = 1, #route do pos[route[k].node] = k end
  for k = 1, #route do
    for _, dep in ipairs(nodes[route[k].node].deps or {}) do
      if pos[dep] and pos[dep] > k then return false end
    end
  end
  return true
end

-- the length of a route in yards, as the crow flies
function Solver.Cost(start, nodes, route)
  local cost, prev = 0, start
  for k = 1, #route do
    local p = nodes[route[k].node].cands[route[k].c]
    cost = cost + D(prev, p)
    prev = p
  end
  return cost
end

-- Returns an ordered list of { node = i, c = which spot }, what it costs, and the seconds it takes.
-- opts: travel(a, b) -> seconds, level = yours, warm = last time's order (node keys), yield = give the game a frame,
-- stop() = true when nobody wants the answer any more; budgetMs of thinking (clock() in ms).
function Solver.Solve(start, nodes, budgetMs, clock, opts)
  if #nodes == 0 then return {}, 0, 0 end
  opts = opts or {}
  clock = clock or function() return os.clock() * 1000 end
  local ctx = Setup(start, nodes, opts)
  ctx.towns = Towns(ctx)
  local spent, t0 = 0, clock()
  local function tick()
    local now = clock()
    spent = spent + (now - t0)
    if opts.yield then opts.yield() end
    t0 = clock()
    return (opts.stop and opts.stop()) or (budgetMs and spent > budgetMs)
  end
  local bestO, bestC, best
  local margin = 0.05
  local function Start(order, cand)
    if not order or #order < ctx.n then return end
    local c = Improve(ctx, order, cand, tick)
    if not best or c < best - margin then bestO, bestC, best = Copy(order), Copy(cand), c end
  end
  if opts.warm then
    Start(Warm(ctx, opts.warm))
    if best and not opts.yield then margin = Solver.STICK end
  end
  if not best or not tick() then Start(Greedy(ctx, 0.6)) end
  if not best then bestO, bestC = Greedy(ctx, 0.6); best = Evaluate(ctx, bestO, bestC) end
  if opts.yield and not tick() then Start(Greedy(ctx, 1)) end
  -- shake it and try again, while there's time (only in the background)
  local n, seed = #bestO, 12345
  local function Rnd(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return a + floor(seed / 65536) % (b - a + 1)
  end
  while opts.yield and n >= 6 and not tick() do
    local order, cand = Copy(bestO), Copy(bestC)
    for _ = 1, Rnd(1, 3) do
      local len = Rnd(1, min(6, n - 1))
      local i = Rnd(1, n - len + 1)
      local seg = {}
      for _ = 1, len do seg[#seg + 1] = table.remove(order, i) end
      local j = Rnd(1, #order + 1)
      for x = #seg, 1, -1 do table.insert(order, j, seg[x]) end
    end
    if Evaluate(ctx, order, cand) < huge then Start(order, cand) end
  end
  Solver.PullReady(ctx, bestO, bestC)
  local route = {}
  for k, i in ipairs(bestO) do route[k] = { node = i, c = bestC[i] } end
  return route, Evaluate(ctx, bestO, bestC), Seconds(ctx, bestO, bestC)
end

-- What a given order would cost (to compare two plans by the same measure)
function Solver.Measure(start, nodes, route, opts)
  local ctx = Setup(start, nodes, opts)
  local order, cand = {}, {}
  for k, o in ipairs(route) do order[k], cand[o.node] = o.node, o.c end
  return Evaluate(ctx, order, cand), Seconds(ctx, order, cand)
end
end

---------------------------------------------------------------------------
-- Quest data (QuestDB.lua) -> stops with world positions
---------------------------------------------------------------------------
local QDB, NDB, IDB, ODB
local function DBReady()
  local L = NS.Quests()
  if not L then return false end
  QDB, NDB, IDB, ODB = L.Quest, L.Npc, L.Item, L.Object
  return true
end

local mapCache = {}
local function AreaToMap(areaId)
  local m = mapCache[areaId]
  if m ~= nil then return m or nil end
  local v = NS.QuestDB.AreaMap(areaId)
  mapCache[areaId] = v or false
  return v
end

local function SpawnPoints(spawns, out)
  out = out or {}
  if type(spawns) ~= "table" then return out end
  local hbd = NS.HBD()
  for areaId, coords in pairs(spawns) do
    local m = type(coords) == "table" and AreaToMap(areaId)
    if m then
      for _, xy in ipairs(coords) do
        local x, y = xy[1], xy[2]
        if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
          local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(x / 100, y / 100, m)
          if wx then out[#out + 1] = { wx = wx, wy = wy, inst = inst, m = m, x = x / 100, y = y / 100 } end
        end
      end
    end
  end
  return out
end

local entityCache = {}
local function EntityPoints(kind, id)
  local key = kind .. ":" .. tostring(id)
  if entityCache[key] then return entityCache[key] end
  local spawns
  if kind == "npc" then spawns = NDB.Get(id, "spawns") else spawns = ODB.Get(id, "spawns") end
  local pts = SpawnPoints(spawns)
  entityCache[key] = pts
  return pts
end

local function Append(dst, src) for i = 1, #src do dst[#dst + 1] = src[i] end return dst end

local function EntryPoints(e)
  local pts = {}
  if e.kind == "npc" then
    for _, id in ipairs(e.ids) do Append(pts, EntityPoints("npc", id)) end
  elseif e.kind == "object" then
    for _, id in ipairs(e.ids) do Append(pts, EntityPoints("object", id)) end
  elseif e.kind == "item" then
    local id = e.ids[1]
    local npcs, objs = IDB.Get(id, "npcDrops"), IDB.Get(id, "objectDrops")
    if type(npcs) == "table" then for k = 1, math.min(#npcs, 30) do Append(pts, EntityPoints("npc", npcs[k])) end end
    if type(objs) == "table" then for k = 1, math.min(#objs, 30) do Append(pts, EntityPoints("object", objs[k])) end end
    if #pts == 0 then
      local vendors = IDB.Get(id, "vendors")
      if type(vendors) == "table" then for k = 1, math.min(#vendors, 10) do Append(pts, EntityPoints("npc", vendors[k])) end end
    end
  end
  return pts
end

local function DbObjectives(qid)
  local lists = { monster = {}, item = {}, object = {} }
  local o = QDB.Get(qid, "objectives")
  if type(o) ~= "table" then return lists end
  for _, e in ipairs(o[1] or {}) do
    lists.monster[#lists.monster + 1] = { kind = "npc", ids = { e[1] }, name = NDB.Get(e[1], "name"), alt = e[2] }
  end
  for _, e in ipairs(o[5] or {}) do
    local ids = type(e[1]) == "table" and e[1] or { e[2] }
    lists.monster[#lists.monster + 1] = { kind = "npc", ids = ids, name = e[3] or NDB.Get(e[2], "name") }
  end
  for _, e in ipairs(o[2] or {}) do
    lists.object[#lists.object + 1] = { kind = "object", ids = { e[1] }, name = ODB.Get(e[1], "name"), alt = e[2] }
  end
  for _, e in ipairs(o[3] or {}) do
    lists.item[#lists.item + 1] = { kind = "item", ids = { e[1] }, name = IDB.Get(e[1], "name"), alt = e[2] }
  end
  return lists
end

local function Contains(text, name)
  return type(name) == "string" and name ~= "" and text:find(name:lower(), 1, true) ~= nil
end

-- Matches the game's objective lines to Questie's entries: by name first, then by order.
local function MatchObjectives(lists, objectives)
  local used, out = {}, {}
  for idx, o in ipairs(objectives) do
    local list = lists[o.type]
    local text = (o.text or ""):lower()
    if list then
      for _, e in ipairs(list) do
        if not used[e] and (Contains(text, e.name) or Contains(text, e.alt)) then used[e] = true; out[idx] = e; break end
      end
    end
  end
  for idx, o in ipairs(objectives) do
    local list = lists[o.type]
    if not out[idx] and list then
      for _, e in ipairs(list) do
        if not used[e] then used[e] = true; out[idx] = e; break end
      end
    end
  end
  return out
end

local CLUSTER_R = 120 -- yards: spawns closer than this count as one camp
local function Candidates(points, here)
  local clusters = {}
  for _, p in ipairs(points) do
    if p.inst == here.inst then
      local best, bestD
      for _, c in ipairs(clusters) do
        local dx, dy = c.sx / c.n - p.wx, c.sy / c.n - p.wy
        local dd = dx * dx + dy * dy
        if dd <= CLUSTER_R * CLUSTER_R and (not bestD or dd < bestD) then best, bestD = c, dd end
      end
      if best then
        best.n, best.sx, best.sy = best.n + 1, best.sx + p.wx, best.sy + p.wy
        best.pts[#best.pts + 1] = p
      else
        clusters[#clusters + 1] = { n = 1, sx = p.wx, sy = p.wy, pts = { p } }
      end
    end
  end
  if #clusters == 0 then return {} end
  -- Each camp is represented by its spawn nearest the camp's middle (always a valid map spot).
  for _, c in ipairs(clusters) do
    local cx, cy = c.sx / c.n, c.sy / c.n
    local rep, rd
    for _, p in ipairs(c.pts) do
      local dx, dy = p.wx - cx, p.wy - cy
      local dd = dx * dx + dy * dy
      if not rd or dd < rd then rep, rd = p, dd end
    end
    c.wx, c.wy, c.inst, c.m, c.x, c.y, c.pts = rep.wx, rep.wy, rep.inst, rep.m, rep.x, rep.y, nil
  end
  table.sort(clusters, function(a, b) return a.n > b.n end)
  local maxN, out = clusters[1].n, {}
  local nearest, nd
  for _, c in ipairs(clusters) do
    local dd = D(here, c)
    if not nd or dd < nd then nearest, nd = c, dd end
    if #out < 6 and c.n >= math.max(1, math.floor(maxN * 0.25)) then out[#out + 1] = c end
  end
  local has = false
  for _, c in ipairs(out) do if c == nearest then has = true end end
  if not has then out[#out + 1] = nearest end
  return out
end

local function QuestLog()
  local quests = {}
  local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
    or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
  for i = 1, n do
    local info = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID and info.questID > 0 then
      local id = info.questID
      quests[#quests + 1] = {
        id = id, title = info.title, level = info.level,
        failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) or false,
        complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false,
        objectives = C_QuestLog.GetQuestObjectives(id) or {},
      }
    end
  end
  return quests
end

R.skipped = {}
R.MOST = 60 -- stops a plan may have before no more quests are added to it
R.Quests = function() return QuestLog() end

-- Routing just one quest (class and profession quests shouldn't wait behind the levelling route). The focus
-- follows the quest's chain: when it's turned in, the next quest in the chain is routed, starting with picking it up.
function R.Focus(qid, goal) -- goal: the quest the whole chain is for (QuestFind.lua), so the route knows which way it goes on
  local f
  if qid then
    local title
    for _, q in ipairs(QuestLog()) do if q.id == qid then title = q.title end end
    f = { id = qid, title = title or (QDB and QDB.Get(qid, "name")) or ("quest " .. qid), goal = goal }
  end
  NS.cdb.route.focus = f
  R.sig = nil
  if not NS.cdb.route.enabled then R.Enable(true) else R.Compute(true) end
  R.UpdatePanel()
  return f
end

local function FocusID()
  local f = NS.cdb.route and NS.cdb.route.focus
  return type(f) == "table" and type(f.id) == "number" and f.id or nil
end
R.FocusID = FocusID

-- Quests are only on the route once switched On (Quests tab; All on switches every one on). The focus quest and
-- the quests of a goal plan from the helper (Add set to route) always count.
-- Switched Off by you (not just never switched on): then even its hand-in stays off the route.
local function SwitchedOff(qid)
  local off = NS.cdb.route and NS.cdb.route.off
  return type(off) == "table" and off[qid] == true
end
local function Included(qid)
  local inc = NS.cdb.route and NS.cdb.route.include
  if type(inc) == "table" and inc[qid] == true then return true end
  if SwitchedOff(qid) then return false end
  local goal = NS.cdb.goal
  if type(goal) == "table" and type(goal.quests) == "table" then
    for _, g in ipairs(goal.quests) do if g == qid then return true end end
  end
  return false
end
R.Included = Included
-- Nothing left to do but hand it in
local function Finished(q)
  if q.failed then return false end
  if q.complete then return true end
  local n = 0
  for _, o in ipairs(q.objectives) do
    if not o.finished then return false end
    n = n + 1
  end
  return n > 0
end
R.Finished = Finished
-- On the route: what you switched On, and every finished quest (its XP and the bag space it holds shouldn't wait)
local function OnRoute(q)
  return Included(q.id) or (Finished(q) and not SwitchedOff(q.id))
    or (NS.XPRun ~= nil and NS.XPRun.InRun(q.id) and not SwitchedOff(q.id) and not q.failed)
end
R.OnRoute = OnRoute
local function InLog(qid) for _, q in ipairs(QuestLog()) do if q.id == qid then return q end end end
function R.Excluded(qid)
  local q = InLog(qid)
  if q then return not OnRoute(q) end
  return not Included(qid)
end
local function Changed()
  R.sig = nil
  if NS.cdb.route.enabled then R.Compute(true) end
  R.UpdatePanel()
end
function R.Toggle(qid)
  NS.cdb.route.include = type(NS.cdb.route.include) == "table" and NS.cdb.route.include or {}
  NS.cdb.route.off = type(NS.cdb.route.off) == "table" and NS.cdb.route.off or {}
  local on = R.Excluded(qid)
  NS.cdb.route.include[qid], NS.cdb.route.off[qid] = on or nil, not on or nil
  Changed()
end
-- A quest you pick up joins the route on its own (Quests tab: "New quests: On / Off")
function R.AutoNew() return NS.cdb.route.autoNew ~= false end
function R.SetAutoNew(on)
  NS.cdb.route.autoNew = on and true or false
  R.UpdatePanel()
end
function R.Accepted(a, b)
  local qid = (type(b) == "number" and b > 0) and b or a -- QUEST_ACCEPTED is (questID) or (logIndex, questID)
  if type(qid) ~= "number" or qid <= 0 then return end
  if not R.AutoNew() and not (NS.XPRun and NS.XPRun.Picked(qid)) then return end -- (one the run sent you for always joins)
  NS.cdb.route.include = type(NS.cdb.route.include) == "table" and NS.cdb.route.include or {}
  if type(NS.cdb.route.off) == "table" then NS.cdb.route.off[qid] = nil end
  if NS.cdb.route.include[qid] then return end
  NS.cdb.route.include[qid] = true
  R.sig = nil
  NS.Debounce("route new quest", 1.5, function() if NS.cdb.route.enabled then R.Compute(true) end; R.UpdatePanel() end)
end

function R.SetAll(on)
  local inc, off = {}, {}
  for _, q in ipairs(QuestLog()) do if on then inc[q.id] = true else off[q.id] = true end end
  NS.cdb.route.include, NS.cdb.route.off = inc, off
  Changed()
end

-- What the route optimizes for: path (shortest walk), xp, rewards (gear upgrades and money), all (both)
R.OPTIMIZE = { "path", "xp", "rewards", "all" }
function R.Optimize() return (NS.cdb.route and NS.cdb.route.optimize) or "path" end
function R.SetOptimize(mode)
  NS.cdb.route.optimize = mode
  R.sig = nil
  R.Compute(true)
  R.UpdatePanel()
end

-- Each quest's rewards, as the game shows them: XP, money, and the best gear upgrade among its rewards
-- (from the upgrade scan). For the Quests tab and the xp / rewards / all orders.
function R.QuestValue(qid)
  local xp, money = 0, 0
  if GetQuestLogRewardXP then
    local ok, v = pcall(GetQuestLogRewardXP, qid)
    if ok and type(v) == "number" then xp = v end
  end
  if GetQuestLogRewardMoney then
    local ok, v = pcall(GetQuestLogRewardMoney, qid)
    if ok and type(v) == "number" then money = v end
  end
  local up
  for _, e in ipairs((NS.Upgrades and NS.Upgrades.all) or {}) do
    for _, q in ipairs(e.quests or {}) do
      if q.id == qid and (not up or e.gain > up.gain) then up = { gain = e.gain, name = e.name, slot = e.slot } end
    end
  end
  return { xp = xp, money = money, up = up }
end

-- The weight of each stop for the chosen order: the quest's value (0-1 against the best quest in the log),
-- shared between its stops, so a whole quest gets pulled forward rather than just its turn-in.
R.PRIORITY = 1.5 -- all the weights together; higher = value counts more against walking
function R.Weight(nodes)
  local mode = R.Optimize()
  for _, nd in ipairs(nodes) do nd.w = nil end
  if mode == "path" or FocusID() then return end
  local per, count = {}, {}
  for _, nd in ipairs(nodes) do
    local qid = nd.quest and nd.quest.id
    if qid and nd.kind ~= "pickup" and nd.kind ~= "corpse" then
      count[qid] = (count[qid] or 0) + 1
      if not per[qid] then per[qid] = R.QuestValue(qid) end
      if nd.kind == "turnin" and (per[qid].xp or 0) <= 0 and nd.xp then per[qid].xp = nd.xp end -- (not in the log yet)
    end
  end
  local maxXP, maxMoney, maxUp = 0, 0, 0
  for _, v in pairs(per) do
    maxXP, maxMoney = math.max(maxXP, v.xp), math.max(maxMoney, v.money)
    maxUp = math.max(maxUp, v.up and v.up.gain or 0)
  end
  local val, total = {}, 0
  for qid, v in pairs(per) do
    local x = maxXP > 0 and v.xp / maxXP or 0
    local rw = 0.6 * (maxUp > 0 and (v.up and v.up.gain or 0) / maxUp or 0) + 0.4 * (maxMoney > 0 and v.money / maxMoney or 0)
    local s = (mode == "xp" and x) or (mode == "rewards" and rw) or 0.5 * x + 0.5 * rw
    val[qid] = s
    total = total + s
  end
  if total <= 0 then return end
  for _, nd in ipairs(nodes) do
    local qid = nd.quest and nd.quest.id
    if qid and val[qid] and count[qid] then nd.w = R.PRIORITY * val[qid] / total / count[qid] end
  end
end

---------------------------------------------------------------------------
-- What each stop is worth and how long it takes (the order weighs these)
---------------------------------------------------------------------------
-- a quest's XP: the game's own number, else Questie's for your level
local function QuestXP(q)
  local xp = 0
  if GetQuestLogRewardXP then
    local ok, v = pcall(GetQuestLogRewardXP, q.id)
    if ok and type(v) == "number" then xp = v end
  end
  local E = NS.Engine
  if q.notYet then xp = 0 end -- (the game only knows it for quests in the log)
  if xp <= 0 and E and E.QuestXPTable then
    local ok, t = pcall(E.QuestXPTable)
    local e = ok and type(t) == "table" and t[q.id]
    if type(e) == "table" and tonumber(e[2]) then xp = E.AdjustedXP(tonumber(e[1]) or 0, tonumber(e[2]), UnitLevel("player")) end
  end
  return xp
end

-- free bag slots (ordinary bags: not quivers, soul bags or profession bags); nil when the game doesn't say
function R.FreeSlots()
  local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if not get then return nil end
  local free, any = 0, false
  for bag = 0, 4 do
    local ok, n, kind = pcall(get, bag)
    if ok and type(n) == "number" and (kind == nil or kind == 0) then
      free = free + n
      if n > 0 or bag == 0 then any = true end
    end
  end
  return any and free or nil
end

local function Count(item)
  local get = (C_Item and C_Item.GetItemCount) or GetItemCount
  local ok, n = false, nil
  if get then ok, n = pcall(get, item) end
  return ok and type(n) == "number" and n or 0
end

-- bag slots a quest's items take up right now
local function QuestSlots(q, lists)
  local n = 0
  for _, e in ipairs(lists.item) do
    local have = Count(e.ids[1])
    if have > 0 then n = n + math.ceil(have / 20) end
  end
  return n
end

-- what a bag slot is worth, the fuller the bags the more
R.ROOMY, R.FULL = 12, 3
local function SlotPrice(free)
  if not free or free >= R.ROOMY then return 0.005 end
  return 0.005 + 0.115 * ((R.ROOMY - free) / R.ROOMY) ^ 2
end

-- seconds an objective takes: its kills at your pace (rarer drops take more), things to pick up, a place to visit
local CHANCE, PICK, VISIT, MAXWORK = 0.4, 25, 40, 1500
local function Work(o, e)
  local have, need = (o.text or ""):match("(%d+)%s*/%s*(%d+)")
  have, need = tonumber(o.numFulfilled) or tonumber(have) or 0, tonumber(o.numRequired) or tonumber(need) or 1
  local n = math.max(1, need - have)
  if not e or o.type == "event" then return VISIT end
  if e.kind == "object" then return math.min(MAXWORK, n * PICK) end
  local Fm = NS.Farm
  local kill = Fm and Fm.Pace and Fm.Pace() or 60
  local npc = e.kind == "npc" and e.ids[1]
  local chance = 1
  if e.kind == "item" then
    local npcs = IDB.Get(e.ids[1], "npcDrops")
    if type(npcs) ~= "table" or #npcs == 0 then return math.min(MAXWORK, n * PICK) end
    npc = npcs[1]
    chance = CHANCE
    if Fm and Fm.Chance then
      local ok, p = pcall(Fm.Chance, e.ids[1], npc)
      if ok and type(p) == "number" and p > 0.02 then chance = p end
    end
  end
  if npc and Fm and Fm.KillTime then
    local ok, t = pcall(Fm.KillTime, npc)
    if ok and type(t) == "number" then kill = t end
  end
  local secs = math.min(MAXWORK, n / chance * kill)
  return secs, secs / kill
end

local HANDIN = 8 -- seconds at whoever takes the quest
local function Values(q, lists, node, free)
  local xpMax = UnitXPMax and UnitXPMax("player") or 0
  local xp = QuestXP(q)
  local share = (xpMax and xpMax > 0) and math.min(0.6, xp / xpMax) or 0
  node.xp, node.share, node.ql = xp, share, (tonumber(q.level) or 0) > 0 and q.level or nil
  node.slots = Finished(q) and QuestSlots(q, lists) or 0
  local mode = R.Optimize()
  local xpw = (mode == "rewards" and 0.5 or mode == "xp" and 2.5 or 1) * Solver.XPW
  node.hold = Solver.HOLD + xpw * share + SlotPrice(free) * math.max(node.slots, Finished(q) and 0 or 1)
  node.early = 0.15 * share
  node.work = HANDIN
end

-- Bags nearly full: a stop at a merchant, on the way
local SELLERS = { general = true, repair = true, trade = true, reagents = true, inn = true }
local function SellNode(here, free)
  if not free or not R.needSell or NS.cdb.route.sell == false then return nil end
  local Tv = NS.Travel
  local pts = Tv and Tv.Points and Tv.Points(SELLERS) or {}
  local near = {}
  for _, p in ipairs(pts) do if p.inst == here.inst then near[#near + 1] = { p = p, d = D(p, here) } end end
  table.sort(near, function(a, b) return a.d < b.d end)
  local cands = {}
  for k = 1, math.min(12, #near) do
    local p = near[k].p
    cands[k] = { wx = p.wx, wy = p.wy, m = p.m, x = p.x / 100, y = p.y / 100, n = 1, who = p.name }
  end
  if #cands == 0 then return nil end
  return { kind = "sell", quest = { title = string.format("%d bag slot%s free", free, free == 1 and "" or "s") }, label = "Sell at a merchant",
           cands = cands, key = "sell", deps = {}, ready = true, work = 20, hold = 0.15 + 0.2 * math.max(0, R.FULL - free) }
end
local function CheckBags()
  local free = R.FreeSlots()
  if not free then R.needSell = false return nil end
  if free <= R.FULL and not (R.soldAt and GetTime() - R.soldAt < 600) then R.needSell = true elseif free >= R.FULL * 2 then R.needSell = false end
  return free
end

-- A quest that isn't in the log yet: a stop at whoever gives it
local function PickupNode(qid, here, elsewhere, unknown)
  local st = QDB.Get(qid, "startedBy")
  local pts = {}
  if type(st) == "table" then
    for _, id in ipairs(st[1] or {}) do Append(pts, EntityPoints("npc", id)) end
    for _, id in ipairs(st[2] or {}) do Append(pts, EntityPoints("object", id)) end
  end
  local title = QDB.Get(qid, "name") or ("quest " .. qid)
  local cands = Candidates(pts, here)
  if #cands > 0 then
    return { kind = "pickup", quest = { id = qid, title = title }, label = "Pick up", cands = cands, key = qid .. ":pickup", deps = {} }
  end
  local list = (#pts > 0) and elsewhere or unknown
  list[#list + 1] = title .. ": pick up"
end

-- A quest that isn't in the log yet, whole: pick it up, do it, hand it in (each after the one before). false = not all of its places are known
-- here (what is known is still added, down to just picking it up).
local function Wanted(qid) -- how many of each thing it wants: own data (Questie doesn't say)
  local out = { npc = {}, object = {}, item = {} }
  local own = NS.QuestDB.own and NS.QuestDB.own.Quest
  local ok, o = pcall(own and own.Get or error, qid, "objectives")
  if ok and type(o) == "table" then
    for k, kind in ipairs({ "npc", "object", "item" }) do
      for _, e in pairs(type(o[k]) == "table" and o[k] or {}) do
        if type(e) == "table" and e[1] and tonumber(e[3]) then out[kind][e[1]] = tonumber(e[3]) end
      end
    end
  end
  return out
end
local USUAL = { npc = 8, object = 5, item = 6 }
function R.QuestNodes(qid, here, nodes, elsewhere, unknown, free)
  local pick = PickupNode(qid, here, elsewhere, unknown)
  if not pick then return false end
  local E = NS.Engine
  local q = { id = qid, title = pick.quest.title, level = E and E.QuestLevel(qid) or 0, objectives = {}, notYet = true }
  pick.quest, pick.work = q, 8
  nodes[#nodes + 1] = pick
  local first = #nodes
  local lists, want = DbObjectives(qid), Wanted(qid)
  local deps, whole = {}, true
  local function Do(key, pts, label, o, e, kills)
    local cands = Candidates(pts, here)
    if #cands == 0 then
      whole = false
      local list = (#pts > 0) and elsewhere or unknown
      list[#list + 1] = q.title .. ": " .. label
      return
    end
    local work, n = Work(o, e)
    nodes[#nodes + 1] = { kind = "obj", quest = q, label = label, cands = cands, key = qid .. ":" .. key, deps = { first }, work = work,
                          kills = kills and n or nil, ql = q.level > 0 and q.level or nil }
    deps[#deps + 1] = #nodes
  end
  local seen = {}
  for _, kind in ipairs({ "monster", "object", "item" }) do
    for k, e in ipairs(lists[kind]) do
      local id = e.ids[1]
      local same = (e.name or "?") .. tostring(id)
      if not seen[same] then
        seen[same] = true
        local ek = e.kind == "npc" and "npc" or e.kind
        local n = want[ek] and want[ek][id] or USUAL[ek] or 1
        if kind == "monster" and e.alt and e.alt ~= "" and not want.npc[id] then n = 1 end -- (a place or a deed, not a kill list)
        local label = (e.alt and e.alt ~= "" and e.alt) or ((ek == "npc" and "Kill " or ek == "item" and "Get " or "Use ") .. (e.name or "?"))
        Do(kind .. k, EntryPoints(e), label .. (n > 1 and (" x" .. n) or ""), { text = "", numFulfilled = 0, numRequired = n, type = kind }, e, true)
      end
    end
  end
  local te = QDB.Get(qid, "triggerEnd")
  if type(te) == "table" and type(te[2]) == "table" then Do("event", SpawnPoints(te[2]), type(te[1]) == "string" and te[1] ~= "" and te[1] or "Go there", { type = "event" }, nil) end
  if not whole then return false end
  local fin, pts = QDB.Get(qid, "finishedBy"), {}
  if type(fin) == "table" then
    for _, id in ipairs(fin[1] or {}) do Append(pts, EntityPoints("npc", id)) end
    for _, id in ipairs(fin[2] or {}) do Append(pts, EntityPoints("object", id)) end
  end
  local cands = Candidates(pts, here)
  if #cands == 0 then
    local list = (#pts > 0) and elsewhere or unknown
    list[#list + 1] = q.title .. ": turn in"
    return false
  end
  local node = { kind = "turnin", quest = q, label = "Turn in", cands = cands, key = qid .. ":turnin", deps = #deps > 0 and deps or { first }, ready = false }
  Values(q, lists, node, free)
  nodes[#nodes + 1] = node
  return true
end
function R.HereNow()
  local hbd = NS.HBD()
  if not hbd or not DBReady() then return nil end
  local wx, wy, inst = hbd:GetPlayerWorldPosition()
  return wx and { wx = wx, wy = wy, inst = inst } or nil
end

function R.BuildNodes(here)
  local nodes, elsewhere, unknown = {}, {}, {}
  local free = CheckBags()
  local focus = FocusID()
  local focusInLog = false
  for _, q in ipairs(QuestLog()) do
    if q.id == focus then focusInLog = true end
    if not q.failed and ((focus and q.id == focus) or (not focus and OnRoute(q))) then
      local objNodes, blocked = {}, false
      local lists = DbObjectives(q.id)
      if not q.complete then
        local matched = MatchObjectives(lists, q.objectives)
        for idx, o in ipairs(q.objectives) do
          if not o.finished then
            local key = q.id .. ":" .. idx
            local pts = matched[idx] and EntryPoints(matched[idx]) or {}
            if #pts == 0 and o.type == "event" then
              local te = QDB.Get(q.id, "triggerEnd")
              if type(te) == "table" then pts = SpawnPoints(te[2]) end
            end
            if #pts == 0 and NS.QuestRec then -- nobody's database knows: where it went forward for one of your characters
              local spots = NS.QuestRec.Spots(q.id, idx)
              if spots then
                local by = {}
                for _, p in ipairs(spots) do
                  by[-p[1]] = by[-p[1]] or {}
                  table.insert(by[-p[1]], { p[2], p[3] })
                end
                pts = SpawnPoints(by)
              end
            end
            local cands = Candidates(pts, here)
            local label = o.text ~= "" and o.text or "Objective"
            if R.skipped[key] then
              blocked = true
            elseif #cands > 0 then
              local work, kills = Work(o, matched[idx])
              nodes[#nodes + 1] = { kind = "obj", quest = q, label = label, cands = cands, key = key, deps = {},
                                    work = work, kills = kills, ql = (tonumber(q.level) or 0) > 0 and q.level or nil }
              objNodes[#objNodes + 1] = #nodes
            else
              blocked = true
              local list = (#pts > 0) and elsewhere or unknown
              list[#list + 1] = q.title .. ": " .. label
            end
          end
        end
      end
      if not blocked then
        local key = q.id .. ":turnin"
        local fin = QDB.Get(q.id, "finishedBy")
        local pts = {}
        if type(fin) == "table" then
          for _, id in ipairs(fin[1] or {}) do Append(pts, EntityPoints("npc", id)) end
          for _, id in ipairs(fin[2] or {}) do Append(pts, EntityPoints("object", id)) end
        end
        local cands = Candidates(pts, here)
        if R.skipped[key] then
          -- skipped for now
        elseif #cands > 0 then
          -- ready = nothing left to do but hand it in: done the first time the route passes near
          local node = { kind = "turnin", quest = q, label = "Turn in", cands = cands, key = key, deps = objNodes,
                         ready = #objNodes == 0 }
          Values(q, lists, node, free)
          nodes[#nodes + 1] = node
        else
          local list = (#pts > 0) and elsewhere or unknown
          list[#list + 1] = q.title .. ": turn in"
        end
      end
    end
  end
  if focus then
    -- the focused quest isn't in the log yet (the next one in its chain): go and pick it up
    if not focusInLog and not (C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(focus)) then
      local nd = PickupNode(focus, here, elsewhere, unknown)
      if nd then nodes[#nodes + 1] = nd end
    end
    return nodes, elsewhere, unknown
  end
  if #nodes > 0 and not R.skipped.sell then
    local nd = SellNode(here, free)
    if nd then nodes[#nodes + 1] = nd end
  end
  -- Quests that aren't in the log yet, whole (picked up, done and handed in on the same round): the XP run's, the ones
  -- switched on on the XP & Route tab, and the helper's goal plan.
  local more, seen = {}, {}
  for _, q in ipairs(QuestLog()) do seen[q.id] = true end
  local function Want(qid)
    if type(qid) ~= "number" or seen[qid] or R.skipped[qid .. ":pickup"] then return end
    if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then return end
    seen[qid] = true
    more[#more + 1] = qid
  end
  local goal = NS.cdb.goal
  for _, qid in ipairs(type(goal) == "table" and type(goal.quests) == "table" and goal.quests or {}) do Want(qid) end
  for _, qid in ipairs(NS.XPRun and NS.XPRun.List() or {}) do Want(qid) end
  for _, qid in ipairs(more) do
    if #nodes > R.MOST then break end
    R.QuestNodes(qid, here, nodes, elsewhere, unknown, free)
  end
  return nodes, elsewhere, unknown
end

---------------------------------------------------------------------------
-- Showing the route: the arrow, numbered map pins, the map line. It has no window of its own: its details
-- and buttons are on the Route tab of the Sunstone window (/sun), and closing a window never turns it off.
---------------------------------------------------------------------------
R.stops, R.elsewhere, R.unknown = {}, {}, {}
local NowMs
local pinPool = {}

local function Pin(i)
  local p = pinPool[i]
  if p then return p end
  p = CreateFrame("Frame", nil, UIParent)
  p:SetSize(16, 16)
  p.ring = p:CreateTexture(nil, "BACKGROUND")
  p.ring:SetAllPoints()
  p.bg = p:CreateTexture(nil, "BORDER")
  p.bg:SetPoint("TOPLEFT", 2, -2)
  p.bg:SetPoint("BOTTOMRIGHT", -2, 2)
  p.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
  p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  p:EnableMouse(true)
  p:SetScript("OnEnter", function(self)
    local s = self.stop
    if not s then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(string.format("Sunstone stop %d: %s", self.index, s.node.label), 0.77, 0.62, 0.45)
    GameTooltip:AddLine(s.node.quest.title, 0.86, 0.85, 0.81)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pinPool[i] = p
  return p
end

local function ClearPins()
  local pins = NS.Pins()
  if pins then pins:RemoveAllWorldMapIcons(R) end
end

local function DrawPins()
  local pins = NS.Pins()
  if not pins then return end
  pins:RemoveAllWorldMapIcons(R)
  for i, s in ipairs(R.stops) do
    local p = Pin(i)
    p.stop, p.index = s, i
    p.num:SetText(i)
    if i == 1 then p.ring:SetColorTexture(0.77, 0.62, 0.45, 1) else p.ring:SetColorTexture(0.56, 0.57, 0.60, 0.9) end
    pins:AddWorldMapIconMap(R, p, s.m, s.x, s.y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
  end
end

local function StopTitle(s)
  local q = s.node.quest
  if s.node.kind == "corpse" or s.node.kind == "sell" then return s.node.label end
  if s.node.kind == "turnin" then return "Turn in: " .. (q.title or "?") end
  if s.node.kind == "pickup" then return "Pick up: " .. (q.title or "?") end
  return s.node.label .. "  |cff8f7d68(" .. (q.title or "?") .. ")|r"
end

local function ClearArrow()
  R.target = nil
  if NS.Arrow then NS.Arrow.SetRoute(nil) end
end

-- The next stop in another zone: aim for the next zone crossing on the way (Travel's walking route), not a
-- straight line over the mountains. Re-aimed whenever you change zone, until you're in the stop's zone.
local function Hop(s)
  local T = NS.Travel
  if not (T and T.NextHop and T.Here) then return nil end
  local here = T.Here()
  R.arrowZone = here and here.m
  if not here then return nil end
  local ok, hop = pcall(T.NextHop, here, { m = s.m, x = s.x * 100, y = s.y * 100, wx = s.wx, wy = s.wy, inst = s.inst })
  return ok and hop or nil
end

local function SetArrow()
  local s = R.stops[1]
  if NS.Arrow and not (R.ghost and s and s.key ~= "corpse") then NS.Arrow.Hold(false) end
  if not s or R.paused then ClearArrow(); R.hop, R.target = nil, nil; return end
  -- a ghost whose body Sunstone can't place: no arrow at all rather than one pointing at a quest
  if R.ghost and s.key ~= "corpse" then ClearArrow(); R.hop, R.target = nil, nil; if NS.Arrow then NS.Arrow.Hold(true) end return end
  local title = (s.node.kind == "turnin" and "Turn in: " .. (s.node.quest.title or "?"))
    or (s.node.kind == "pickup" and "Pick up: " .. (s.node.quest.title or "?")) or s.node.label
  local hop = Hop(s)
  R.hop = hop
  local m, x, y = s.m, s.x, s.y
  if hop then
    m, x, y = hop.m, hop.x / 100, hop.y / 100
    title = hop.label .. ", then " .. title
  end
  R.target = { m = m, x = x, y = y, title = title } -- the minimap trail (Trail.lua) heads here too
  -- Arrow off (Route tab / "/sun arrow off"): the stop stays on the map and minimap, without the arrow
  if NS.Arrow then NS.Arrow.SetRoute({ m = m, x = x, y = y, title = title, hidden = NS.cdb.route.arrow == false or nil,
                                               body = s.key == "corpse" or nil }) end
end
R.SetArrow = SetArrow

function R.SetArrowShown(on)
  NS.cdb.route.arrow = on and true or false
  SetArrow()
  R.UpdatePanel()
end

-- The Route tab of the Sunstone window shows the route; tell it something changed.
function R.UpdatePanel()
  if NS.Window and NS.Window.RouteChanged then NS.Safe("window", NS.Window.RouteChanged) end
end

-- The next stop, for the Route tab: what, where, how far (yards in a straight line) and what comes after.
function R.Next()
  local s = R.stops[1]
  if not s then return nil end
  local hbd = NS.HBD()
  local wx, wy
  if hbd then wx, wy = hbd:GetPlayerWorldPosition() end
  return { stop = s, zone = hbd and hbd:GetLocalizedMap(s.m) or "?", dist = wx and D({ wx = wx, wy = wy }, s) or nil,
           after = R.stops[2] }
end

function R.Resume()
  R.paused, R.sig = false, nil
  if NS.MapView then NS.MapView.trip = nil end
  if NS.Arrow then NS.Arrow.Clear() end
  R.Compute(true)
end

function R.Unskip()
  wipe(R.skipped)
  R.Compute(true)
end

-- What's waiting to be handed in: how many, their XP, the bag slots they hold; and free slots
function R.Waiting()
  local n, xp, slots = 0, 0, 0
  for _, s in ipairs(R.stops) do
    if s.node.kind == "turnin" and s.node.ready then
      n, xp, slots = n + 1, xp + (s.node.xp or 0), slots + (s.node.slots or 0)
    end
  end
  return n, xp, slots, R.FreeSlots()
end

function R.SkippedCount()
  local n = 0
  for _ in pairs(R.skipped) do n = n + 1 end
  return n
end

-- Dead and released (a ghost): nothing on the route can be done until you're back in your body, so the first
-- stop is your corpse, and the quests are planned from there (where you'll be once you're alive again).
local function IsGhost() return (UnitIsGhost and UnitIsGhost("player")) and true or false end
R.IsGhost = IsGhost
R.CORPSE = { kind = "corpse", label = "Your body", quest = { title = "Your body" } }
local function CorpseSpot(hbd)
  if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_Map and C_Map.GetBestMapForUnit) then return nil end
  local m = C_Map.GetBestMapForUnit("player")
  for _ = 1, 5 do -- the body may be in another zone than the graveyard: look on the bigger maps too
    if not m or m == 0 then return nil end
    local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, m)
    if ok and pos then
      local x, y
      if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
      if x and y and (x > 0 or y > 0) then
        local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(x, y, m)
        if wx then return { wx = wx, wy = wy, inst = inst, m = m, x = x, y = y } end
      end
    end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    m = info and info.parentMapID
  end
end

function NowMs()
  if debugprofilestop then return debugprofilestop() end
  return GetTime() * 1000
end

-- how full the bags are, in steps that matter to the plan
local function BagLevel()
  local f = CheckBags()
  return (not f and "?" or f <= 1 and "full" or f <= R.FULL and "nearly" or f <= 6 and "filling" or f < R.ROOMY and "some" or "roomy")
    .. (R.needSell and "+sell" or "")
end

-- What the route depends on; re-plan only when this changes (not on every kill count).
local function Signature()
  local parts = {}
  for _, q in ipairs(QuestLog()) do
    local done = {}
    for idx, o in ipairs(q.objectives) do done[#done + 1] = o.finished and "1" or "0" end
    parts[#parts + 1] = q.id .. (q.complete and "c" or "") .. (q.failed and "f" or "") .. table.concat(done)
  end
  local hbd = NS.HBD()
  local _, _, inst = hbd:GetPlayerWorldPosition()
  local sk = {}
  for k in pairs(R.skipped) do sk[#sk + 1] = k end
  table.sort(sk)
  local goal = NS.cdb.goal and NS.cdb.goal.quests or {}
  return table.concat(parts, ",") .. "|" .. tostring(inst) .. "|" .. table.concat(sk, ",") .. "|" .. table.concat(goal, ",")
    .. (IsGhost() and "|ghost" or "") .. "|focus" .. tostring(FocusID()) .. "|" .. R.Optimize() .. "|" .. BagLevel() .. "|" .. (NS.XPRun and NS.XPRun.Key() or "")
end

-- The same plan, thought through: travel times prepared, then the order, then the walk between its stops measured
-- around the terrain (a straight line can hide a mountain) and the order again with those, until it settles. In the
-- background, a little each frame; a newer plan replaces an older one that's still thinking.
R.THINK = 400    -- ms of thinking a round, and this much more for each stop
R.THINK_STOP = 25
R.ROUNDS = 8
R.NEAR = 4       -- each stop's walk to this many of its neighbours is measured first
function R.Improve(from, nodes, opts, order, show)
  local T, E = NS.Travel, NS.Engine
  if not (T and T.Prepare and E and E.Job) or #nodes == 0 then return end
  local gen = R.generation
  local function Stale() return gen ~= R.generation end
  E.Job("route plan " .. gen, function()
    T.Prepare(from, nodes, E.Yield)
    if Stale() then return end
    -- the walks that matter most: each stop's spot to its nearest neighbours'
    local spots = { from }
    for _, o in ipairs(order) do spots[#spots + 1] = nodes[o.node].cands[o.c] end
    for i, a in ipairs(spots) do
      local near = {}
      for j, b in ipairs(spots) do if i ~= j then near[#near + 1] = { b, D(a, b) } end end
      table.sort(near, function(x, y) return x[2] < y[2] end)
      local n = 0
      for _, e in ipairs(near) do
        if e[2] > 60 then
          T.Measure(a, e[1])
          if Stale() then return end
          n = n + 1
          if n >= R.NEAR then break end
        end
      end
    end
    local route = order
    for round = 1, R.ROUNDS do
      local keys = {}
      for k, o in ipairs(route) do keys[k] = nodes[o.node].key end
      local think = R.THINK + R.THINK_STOP * #nodes
      local r = Solver.Solve(from, nodes, round == 1 and think or think / 2, NowMs,
                                   { travel = T.Seconds, level = opts.level, warm = keys, yield = E.Yield, stop = Stale })
      if Stale() then return end
      route = r
      local fresh, prev = 0, from
      for _, o in ipairs(route) do
        local p = nodes[o.node].cands[o.c]
        if T.Measure(prev, p) then fresh = fresh + 1 end
        if Stale() then return end
        prev = p
      end
      if fresh == 0 then break end
    end
    return route
  end, function(res)
    if not res or Stale() or not NS.cdb.route.enabled then return end
    -- keep the plan you're following unless the new one is clearly better
    local was, wasSecs = Solver.Measure(from, nodes, order, opts)
    local now, secs = Solver.Measure(from, nodes, res, opts)
    if now < was - Solver.STICK then show(res, now, secs) else show(order, was, wasSecs) end
    R.thought = { was = was, now = now }
    SetArrow()
    DrawPins()
    R.UpdatePanel()
    if NS.MapView then NS.Safe("map line", NS.MapView.DrawRoute) end
  end)
end

function R.Compute(force)
  if not NS.cdb.route.enabled then return end
  if not DBReady() then R.status = "The quest database isn't loaded."; R.UpdatePanel(); return end
  if not NS.HBD() then R.status = "The map library (HereBeDragons) did not load."; R.UpdatePanel(); return end
  local sig = Signature()
  if not force and sig == R.sig then return end
  local hbd = NS.HBD()
  local wx, wy, inst = hbd:GetPlayerWorldPosition()
  if not wx then
    R.status = "Can't see your position here (instance?). The route resumes outside."
    R.UpdatePanel()
    return
  end
  R.sig, R.status = sig, nil
  local here = { wx = wx, wy = wy, inst = inst }
  local ghost = IsGhost()
  local corpse = ghost and CorpseSpot(hbd) or nil
  if corpse and corpse.inst ~= inst then corpse = nil end
  local from = corpse or here -- a ghost's quests start from the body
  R.origin, R.plannedAt, R.ghost = from, GetTime(), ghost -- where and when this plan was made (see Watch)
  local nodes, elsewhere, unknown = R.BuildNodes(from)
  R.Weight(nodes) -- the chosen order: pathing, or XP / rewards first
  local level = UnitLevel("player")
  local opts = { travel = NS.Travel and NS.Travel.Seconds or nil, level = level, warm = R.lastOrder }
  local order, cost, secs = Solver.Solve(from, nodes, 15, NowMs, opts)
  R.elsewhere, R.unknown = elsewhere, unknown
  R.generation = (R.generation or 0) + 1
  local function Show(list, value, seconds)
    R.cost, R.eta = value, seconds
    R.stops, R.lastOrder = {}, {}
    if corpse then
      R.stops[1] = { node = R.CORPSE, key = "corpse", wx = corpse.wx, wy = corpse.wy, m = corpse.m, x = corpse.x, y = corpse.y }
    elseif ghost then
      R.status = "You're a ghost: get back to your body first (the game's minimap arrow points to it). The route waits."
    end
    local prev = from
    for _, o in ipairs(list) do
      local nd = nodes[o.node]
      local c = nd.cands[o.c]
      local t, fly = nil, nil
      if opts.travel then t, fly = opts.travel(prev, c) end
      R.stops[#R.stops + 1] = { node = nd, key = nd.key, wx = c.wx, wy = c.wy, inst = from.inst, m = c.m, x = c.x, y = c.y, secs = t, fly = fly, who = c.who }
      R.lastOrder[#R.lastOrder + 1] = nd.key
      prev = c
    end
  end
  Show(order, cost, secs)
  R.Improve(from, nodes, opts, order, Show)
  if #order == 0 and not FocusID() and not R.status then
    local any = false
    for _, q in ipairs(QuestLog()) do if OnRoute(q) then any = true; break end end
    if not any then
      R.status = "No quests are switched On yet: pick them on the Quests tab (All on puts every quest on the route)."
    end
  end
  SetArrow()
  DrawPins()
  R.UpdatePanel()
  if NS.MapView then NS.Safe("map line", NS.MapView.DrawRoute) end
end

function R.SkipCurrent()
  local s = R.stops[1]
  if not s then return end
  R.skipped[s.key] = true
  NS.Print("skipped: " .. StopTitle(s) .. "  (/sun skip reset brings skipped stops back)")
  R.Compute(true)
end

function R.Pause()
  R.paused = true
  ClearArrow()
  R.UpdatePanel()
end

function R.Enable(on)
  NS.cdb.route.enabled = on and true or false
  if on then
    R.paused, R.sig = false, nil
    if NS.Arrow then NS.Arrow.Clear() end
    R.Compute(true)
  else
    ClearArrow()
    ClearPins()
    R.stops = {}
    if NS.MapView then NS.Safe("map line", NS.MapView.DrawRoute) end
  end
  R.UpdatePanel()
end

function R.Print()
  if #R.stops == 0 then NS.Print("no route right now.") end
  local hbd = NS.HBD()
  if #R.stops > 0 then
    NS.Print(string.format("route: %d stops, roughly %d minutes of walking and work", #R.stops, math.floor((R.eta or 0) / 60 + 0.5)))
  end
  for i, s in ipairs(R.stops) do
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffc99734%d.|r %s |cff8f7d68- %s %.1f, %.1f|r", i, StopTitle(s),
      hbd and hbd:GetLocalizedMap(s.m) or "?", s.x * 100, s.y * 100))
  end
  for _, e in ipairs(R.elsewhere) do DEFAULT_CHAT_FRAME:AddMessage("  |cff8f7d68elsewhere: " .. e .. "|r") end
  for _, e in ipairs(R.unknown) do DEFAULT_CHAT_FRAME:AddMessage("  |cff8f7d68no known place for: " .. e .. "|r") end
end

-- Short text version for the desktop helper's snapshot.
function R.Describe()
  if not NS.cdb.route.enabled then return nil end
  local out = {}
  for i, s in ipairs(R.stops) do
    out[#out + 1] = { n = i, kind = s.node.kind, label = s.node.label, quest = s.node.quest.title, questID = s.node.quest.id,
                      mapID = s.m, x = s.x, y = s.y }
  end
  return out
end

-- Re-plan from where you are when it matters, not only when the quest log changes: walking within reach of a
-- ready turn-in that isn't the next stop, or being far from where the plan was made (a flight, hearth, detour).
R.NEAR_READY = 150   -- yards
R.MOVED_FAR = 1200   -- yards
R.MIN_REPLAN = 10    -- seconds between re-plans for these reasons
function R.Watch()
  -- crossed into another zone: aim at the next crossing on the way (or the stop itself once you're in its zone)
  if NS.cdb.route.enabled and not R.paused and #R.stops > 0 and NS.Travel and NS.Travel.Here then
    local here = NS.Travel.Here()
    if here and here.m ~= R.arrowZone then
      SetArrow()
      R.UpdatePanel()
    end
  end
  if not NS.cdb.route.enabled or R.paused or not R.origin or #R.stops == 0 or IsGhost() then return end
  if UnitOnTaxi and UnitOnTaxi("player") then return end
  if GetTime() - (R.plannedAt or 0) < R.MIN_REPLAN then return end
  local hbd = NS.HBD()
  if not hbd then return end
  local wx, wy, inst = hbd:GetPlayerWorldPosition()
  if not wx or inst ~= R.origin.inst then return end
  local me = { wx = wx, wy = wy }
  for k = 2, math.min(#R.stops, 60) do
    local s = R.stops[k]
    local key = s.key or k
    R.looked = R.looked or {}
    if s.node.ready and D(me, s) <= R.NEAR_READY and GetTime() - (R.looked[key] or -1e9) > 90 then
      R.looked[key] = GetTime()
      return R.Compute(true)
    end
  end
  if D(me, R.origin) > R.MOVED_FAR then return R.Compute(true) end
end

-- The focused quest was handed in: follow its chain to the next quest, or go back to all quests at the end.
function R.FocusTurnedIn(qid)
  local f = FocusID()
  if not f or qid ~= f then return end
  local goal = type(NS.cdb.route.focus) == "table" and NS.cdb.route.focus.goal
  local nxt = NS.QuestFind and goal and NS.QuestFind.Next(goal, qid)
  if not nxt and goal ~= qid then nxt = DBReady() and QDB.Get(qid, "nextQuestInChain") end
  if type(nxt) ~= "number" and not goal and NS.QuestFind then nxt = NS.QuestFind.OnlyNext(qid) end
  if type(nxt) == "number" and nxt > 0 then
    local title = QDB.Get(nxt, "name") or ("quest " .. nxt)
    NS.cdb.route.focus = { id = nxt, title = title, goal = goal or nil }
    NS.Print("next in the chain: " .. title .. ". The route follows it (All quests on the Route tab goes back to everything).")
  else
    NS.cdb.route.focus = nil
    NS.Print("that was the end of the chain: the route covers all your quests again.")
  end
  R.sig = nil
  NS.Debounce("route focus", 1.5, function() R.Compute(true) end)
  R.UpdatePanel()
end

function R:Init()
  C_Timer.NewTicker(3, function() NS.Safe("route watch", R.Watch) end)
  NS.On("QUEST_TURNED_IN", function(qid) NS.Safe("route focus", R.FocusTurnedIn, qid) end)
  NS.On("QUEST_ACCEPTED", function(a, b) NS.Safe("route new quest", R.Accepted, a, b) end)
  local function Changed() NS.Debounce("route", 1, function() R.Compute(false) end) end
  NS.On("BAG_UPDATE_DELAYED", function() NS.Debounce("route bags", 4, function() R.Compute(false) end) end)
  NS.On("MERCHANT_SHOW", function() R.soldAt, R.needSell = GetTime(), false end)
  NS.On("MERCHANT_CLOSED", Changed)
  for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
                        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
                        "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do -- released as a ghost / back in your body
    NS.On(ev, Changed)
  end
  local function Start()
    if NS.cdb.route.enabled then C_Timer.After(2, function() NS.Safe("route", R.Compute, true) end) end
  end
  if NS.QuestDB.Questie() and Questie and Questie.API and Questie.API.RegisterOnReady then
    Questie.API.RegisterOnReady(Start)
  else
    C_Timer.After(8, Start)
  end
end

NS.Command("route", "[on|off|all|<quest name>] - shortest route through your quests, or just one quest and its chain",
  function(rest)
  local raw = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
  rest = raw:lower()
  if rest == "on" then R.Enable(true)
  elseif rest == "off" then R.Enable(false)
  elseif rest == "all" then
    R.Focus(nil)
    NS.Print("the route covers all your quests again.")
    return
  elseif rest ~= "" then
    -- just one quest: the first in your log whose name contains the text
    for _, q in ipairs(QuestLog()) do
      if q.title and q.title:lower():find(rest, 1, true) then
        R.Focus(q.id)
        NS.Print("routing only: " .. q.title .. " (and the rest of its chain). /sun route all goes back to everything.")
        return
      end
    end
    NS.Print("no quest in your log is called anything like '" .. raw .. "'.")
    return
  else R.Enable(not NS.cdb.route.enabled) end
  NS.Print("quest route " .. (NS.cdb.route.enabled and "on." or "off."))
end)
NS.Command("skip", "- skip the current stop ('reset' brings skipped stops back)", function(rest)
  if (rest or ""):lower() == "reset" then
    NS.Print("skipped stops are back.")
    R.Unskip()
  else
    R.SkipCurrent()
  end
end)
NS.Command("list", "- print the whole route", function() R.Print() end)
NS.Command("goal", "['clear'] - the XP / gold plan from the helper (its quests are added to your route)", function(rest)
  local g = NS.cdb.goal
  if (rest or ""):lower() == "clear" then
    NS.cdb.goal = nil
    NS.Print("goal plan cleared.")
    R.sig = nil
    R.Compute(true)
    return
  end
  if not g then NS.Print("no goal plan. Ask the helper (e.g. 'best XP quests near me'), then /sun sync.") return end
  NS.Print(g.name .. ":")
  for _, l in ipairs(g.lines or {}) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
  if not NS.cdb.route.enabled then NS.Print("/sun route on puts its quest givers into your route.") end
end)
