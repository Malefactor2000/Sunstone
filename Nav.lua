-- Sunstone: walking routes around the terrain, for the minimap trail.
-- Ground data: NavData.lua, built from the game's own map tiles by tools/terrain/build_nav.py. Each 8.33-yard
-- cell is 0 = open ground, 1 = deep water (you can swim it, but routes avoid it), 2 = blocked (too steep,
-- magma, slime, or no ground at all). Places you've walked (Paths.lua, and Well Trodden's learned paths) always count as open,
-- which covers ramps, bridges and gates the slope check gets wrong.
-- Positions are HereBeDragons world coordinates (x, y): x = the game's west axis, y = its north axis.
-- Information only: this draws a line to follow. It never moves the character.

local _, NS = ...
local N = NS.Module("Nav")
NS.Nav = N

local floor, abs, sqrt, min, max = math.floor, math.abs, math.sqrt, math.min, math.max
local byte = string.byte
local yield = coroutine.yield

local LEN = {}
do
  local s = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, #s do LEN[byte(s, i)] = i end
  LEN[byte("!")] = 0
end

local ALL_OPEN, VOID = {}, {}
local tiles = {}    -- [instance] = { [tile key] = 4096 cell states | ALL_OPEN | VOID }
local walked = {}   -- [instance] = { [cell key] = true }: where you've been

function N.Has(inst)
  return NS.NAV and NS.NAV.maps and NS.NAV.maps[inst] ~= nil
end

local function Fill(s, t, value)
  local pos = 1
  for row = 0, 63 do
    local i, stop, mark = row * 64, row * 64 + 64, false
    while i < stop do
      local L = LEN[byte(s, pos)] or 64
      pos = pos + 1
      if mark then
        for k = i, i + L - 1 do t[k] = value end
      end
      i = i + L
      mark = not mark
    end
  end
end

local function Tile(inst, key)
  local m = tiles[inst]
  if not m then m = {}; tiles[inst] = m end
  local t = m[key]
  if t then return t end
  local d = NS.NAV.maps[inst]
  local b, w = d.blocked[key], d.water and d.water[key]
  if not b then
    t = VOID
  elseif b == true and not w then
    t = ALL_OPEN
  else
    t = {}
    for k = 0, 4095 do t[k] = 0 end
    if type(b) == "string" then Fill(b, t, 2) end
    if w then Fill(w, t, 1) end
  end
  m[key] = t
  return t
end

local function State(inst, gx, gy)
  local w = walked[inst]
  if w and w[gx * 4096 + gy] then return 0 end
  if gx < 0 or gy < 0 or gx > 4095 or gy > 4095 then return 2 end
  local t = Tile(inst, floor(gx / 64) * 64 + floor(gy / 64))
  if t == ALL_OPEN then return 0 elseif t == VOID then return 2 end
  return t[(gx % 64) * 64 + gy % 64]
end
N.State = State

-- world (HereBeDragons x, y) <-> cell
function N.Cell(x, y)
  local nav = NS.NAV
  return floor((nav.origin - y) / nav.cell), floor((nav.origin - x) / nav.cell)
end

function N.World(gx, gy)
  local nav = NS.NAV
  return nav.origin - (gy + 0.5) * nav.cell, nav.origin - (gx + 0.5) * nav.cell
end

-- Where you've walked becomes open cells: Sunstone's own record, and Well Trodden's learned paths (read once per continent, a
-- little at a time).
local function BuildWalked(inst)
  local w = {}
  walked[inst] = w
  if NS.Paths then NS.Paths.Each(inst, function(gx, gy) w[gx * 4096 + gy] = true end) end
  local maps = WellTroddenDB and WellTroddenDB.maps
  local m = maps and maps[inst]
  if not (m and m.nodes) then return end
  local count = 0
  local function Line(ax, ay, bx, by)
    local ga, gb = N.Cell(ax, ay)
    local ha, hb = N.Cell(bx, by)
    local steps = max(abs(ha - ga), abs(hb - gb)) * 2 + 1
    for k = 0, steps do
      local t = k / steps
      w[floor(ga + (ha - ga) * t + 0.5) * 4096 + floor(gb + (hb - gb) * t + 0.5)] = true
    end
  end
  for id, n in pairs(m.nodes) do
    if type(n) == "table" and n[1] and n[2] then
      Line(n[1], n[2], n[1], n[2])
      for nb in pairs(n[3] or {}) do
        local o = m.nodes[nb]
        if o and o[1] and (type(id) ~= "number" or type(nb) ~= "number" or nb > id) then
          if (o[1] - n[1]) ^ 2 + (o[2] - n[2]) ^ 2 < 60 * 60 then Line(n[1], n[2], o[1], o[2]) end
        end
      end
      count = count + 1
      if count % 1500 == 0 then yield() end
    end
  end
end

function N.Forget()
  tiles, walked = {}, {}
end

-- Re-read the walked paths on the next plan (they grow as you walk).
function N.ForgetWalked()
  walked = {}
end

---------------------------------------------------------------------------
-- A* over the cells, then straightened to as few turns as the ground allows
---------------------------------------------------------------------------
local SQ2 = sqrt(2)
local DX = { -1, 1, 0, 0, -1, -1, 1, 1 }
local DY = { 0, 0, -1, 1, -1, 1, -1, 1 }
local STEP = { 1, 1, 1, 1, SQ2, SQ2, SQ2, SQ2 }
local COST = { [0] = 1, [1] = 3 }   -- open ground, deep water
N.MAX_EXPAND = 250000

local function Octile(ax, ay, bx, by)
  local dx, dy = abs(ax - bx), abs(ay - by)
  return (dx > dy) and (dx + (SQ2 - 1) * dy) or (dy + (SQ2 - 1) * dx)
end

local function NearestOpen(inst, gx, gy, r)
  if State(inst, gx, gy) ~= 2 then return gx, gy end
  for d = 1, r do
    for ox = -d, d do
      for oy = -d, d do
        if (abs(ox) == d or abs(oy) == d) and State(inst, gx + ox, gy + oy) ~= 2 then return gx + ox, gy + oy end
      end
    end
  end
end

-- Is the straight line between two cells clear? Water only counts as clear when `swim` is set.
local function Clear(inst, ax, ay, bx, by, swim)
  local dx, dy = bx - ax, by - ay
  local n = floor(max(abs(dx), abs(dy)) * 3) + 1
  for k = 0, n do
    local t = k / n
    local x, y = ax + 0.5 + dx * t, ay + 0.5 + dy * t
    local s = State(inst, floor(x), floor(y))
    if s == 2 or (s == 1 and not swim) then return false end
  end
  return true
end
N.Clear = Clear

-- The search itself: the goal's cell, the cells' parents, how many were looked at and the cost (in cells); or nil and
-- the reason. `greed` above 1 heads for the goal harder: far fewer cells looked at, a way that may be a little longer.
local function Search(inst, sx, sy, tx, ty, cap, greed, every)
  if not walked[inst] then BuildWalked(inst) end
  local ax, ay = N.Cell(sx, sy)
  local bx, by = N.Cell(tx, ty)
  ax, ay = NearestOpen(inst, ax, ay, 4)
  bx, by = NearestOpen(inst, bx, by, 8)
  if not ax then return nil, "you're standing somewhere the ground data calls blocked" end
  if not bx then return nil, "the destination is somewhere the ground data calls blocked" end
  local goal = bx * 4096 + by
  local gs, parent, closed = {}, {}, {}
  local hk, hf, hn = {}, {}, 0
  local function Push(k, f)
    hn = hn + 1
    local i = hn
    while i > 1 do
      local p = floor(i / 2)
      if hf[p] <= f then break end
      hk[i], hf[i] = hk[p], hf[p]
      i = p
    end
    hk[i], hf[i] = k, f
  end
  local function Pop()
    local k = hk[1]
    local lk, lf = hk[hn], hf[hn]
    hk[hn], hf[hn] = nil, nil
    hn = hn - 1
    if hn > 0 then
      local i = 1
      while true do
        local c = i * 2
        if c > hn then break end
        if c < hn and hf[c + 1] < hf[c] then c = c + 1 end
        if hf[c] >= lf then break end
        hk[i], hf[i] = hk[c], hf[c]
        i = c
      end
      hk[i], hf[i] = lk, lf
    end
    return k
  end
  local start = ax * 4096 + ay
  gs[start] = 0
  Push(start, Octile(ax, ay, bx, by))
  local expanded, found = 0, false
  while hn > 0 do
    local k = Pop()
    if k == goal then found = true break end
    if not closed[k] then
      closed[k] = true
      expanded = expanded + 1
      if expanded > cap then return nil, "too far around to plan", expanded end
      if expanded % every == 0 then yield() end
      local cx, cy = floor(k / 4096), k % 4096
      local g = gs[k]
      for d = 1, 8 do
        local nx, ny = cx + DX[d], cy + DY[d]
        local s = State(inst, nx, ny)
        if s ~= 2 and (d <= 4 or (State(inst, cx + DX[d], cy) ~= 2 and State(inst, cx, cy + DY[d]) ~= 2)) then
          local nk = nx * 4096 + ny
          local ng = g + STEP[d] * COST[s]
          if not closed[nk] and (not gs[nk] or ng < gs[nk]) then
            gs[nk] = ng
            parent[nk] = k
            Push(nk, ng + Octile(nx, ny, bx, by) * greed)
          end
        end
      end
    end
  end
  if not found then return nil, "no walkable way found", expanded end
  return goal, parent, expanded, gs[goal]
end

-- How far it is on foot, in yards, without drawing the way (for the route's order; runs inside a coroutine).
function N.Length(inst, sx, sy, tx, ty, cap)
  if not N.Has(inst) then return nil, "no ground data for this continent", 0 end
  local goal, why, expanded, g = Search(inst, sx, sy, tx, ty, cap or 20000, 1.4, 250)
  if not goal then return nil, why, expanded or 0 end
  return g * NS.NAV.cell * 0.97, nil, expanded
end

-- Runs inside a coroutine (it yields now and then). Returns a list of points { x, y, water } from the start
-- to the goal in world coordinates, plus a note; or nil and the reason.
function N.Find(inst, sx, sy, tx, ty)
  if not N.Has(inst) then return nil, "no ground data for this continent" end
  local goal, parent, expanded = Search(inst, sx, sy, tx, ty, N.MAX_EXPAND, 1.001, 600)
  if not goal then return nil, parent end
  -- the cell path, start to goal
  local cells, k = {}, goal
  while k do
    cells[#cells + 1] = k
    k = parent[k]
  end
  local n = #cells
  for i = 1, floor(n / 2) do cells[i], cells[n - i + 1] = cells[n - i + 1], cells[i] end
  -- keep only the turns: from each point, go straight to the farthest point still in clear view
  local pts, i = {}, 1
  local function Add(c)
    local gx, gy = floor(c / 4096), c % 4096
    local x, y = N.World(gx, gy)
    pts[#pts + 1] = { x, y, State(inst, gx, gy) == 1 }
  end
  Add(cells[1])
  while i < n do
    local ix, iy = floor(cells[i] / 4096), cells[i] % 4096
    local swim = State(inst, ix, iy) == 1
    local j = i + 1
    while j < n do
      local c = cells[j + 1]
      if not Clear(inst, ix, iy, floor(c / 4096), c % 4096, swim or State(inst, floor(c / 4096), c % 4096) == 1) then break end
      j = j + 1
    end
    Add(cells[j])
    i = j
    if #pts % 50 == 0 then yield() end
  end
  pts[1][1], pts[1][2] = sx, sy
  pts[#pts][1], pts[#pts][2] = tx, ty
  return pts, expanded
end
