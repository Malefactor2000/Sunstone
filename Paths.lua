-- Sunstone: the ground you've walked. Every place you have stood counts as walkable for the trail (Nav.lua), which settles
-- the ramps, bridges, tunnels and gates the ground data gets wrong, for all your characters. Nothing is sent anywhere.
-- Kept in NS.db.walk[continent][row] as runs of cells, on the same grid as Nav's ground data.
-- Well Trodden's learned paths are used too when it's installed.
-- Information only: it remembers where you were. It never moves the character.

local _, NS = ...
local P = NS.Module("Paths")
NS.Paths = P

local floor, abs, max, sqrt = math.floor, math.abs, math.max, math.sqrt
local STEP = 0.5            -- seconds
local JUMP = 60             -- yards between two looks: more than this is a portal, a hearthstone or a lag spike
local FASTEST = 22          -- yards a second: faster is a fall, a flight or a boat

local live = {}             -- [inst] = { [cell key] = true }, what's saved plus what's new
local dirty = {}
local last                  -- { inst, x, y, t }

local function Store(inst)
  NS.db.walk = type(NS.db.walk) == "table" and NS.db.walk or {}
  NS.db.walk[inst] = type(NS.db.walk[inst]) == "table" and NS.db.walk[inst] or {}
  return NS.db.walk[inst]
end

-- a row: its cells (0-4095) as run starts and lengths, "start,length;start,length"
function P.Encode(cells)
  local list = {}
  for c in pairs(cells) do list[#list + 1] = c end
  table.sort(list)
  local out, i = {}, 1
  while i <= #list do
    local a, b = list[i], list[i]
    while list[i + 1] == b + 1 do i = i + 1; b = list[i] end
    out[#out + 1] = a == b and tostring(a) or (a .. "-" .. b)
    i = i + 1
  end
  return table.concat(out, ";")
end
function P.Decode(s)
  local t = {}
  for part in (type(s) == "string" and s or ""):gmatch("[^;]+") do
    local a, b = part:match("^(%d+)%-(%d+)$")
    a, b = tonumber(a or part), tonumber(b or part)
    if a and b and a >= 0 and b >= a and b < 4096 then for c = a, b do t[c] = true end end
  end
  return t
end

local function Load(inst)
  local L = live[inst]
  if L then return L end
  L = {}
  live[inst] = L
  for row, s in pairs(Store(inst)) do
    if type(row) == "number" then L[row] = P.Decode(s) end
  end
  return L
end

-- every walked cell of a continent: fn(row, column)
function P.Each(inst, fn)
  if not NS.db then return end
  for row, cells in pairs(Load(inst)) do
    for c in pairs(cells) do fn(row, c) end
  end
end

function P.Count(inst)
  local n = 0
  P.Each(inst, function() n = n + 1 end)
  return n
end

local function Mark(inst, row, col)
  if row < 0 or row > 4095 or col < 0 or col > 4095 then return end
  local L = Load(inst)
  local r = L[row]
  if not r then r = {}; L[row] = r end
  if not r[col] then
    r[col] = true
    dirty[inst] = dirty[inst] or {}
    dirty[inst][row] = true
  end
end

function P.Save()
  for inst, rows in pairs(dirty) do
    local s = Store(inst)
    for row in pairs(rows) do s[row] = P.Encode(live[inst][row]) end
    dirty[inst] = nil
  end
end

-- Are you on your own feet (or mount)? Flights, ghosts, falls and swimming don't count.
local function OnFoot()
  if UnitOnTaxi and UnitOnTaxi("player") then return false end
  if IsFalling and IsFalling() then return false end
  if IsFlying and IsFlying() then return false end
  if IsSwimming and IsSwimming() then return false end
  if UnitIsGhost and UnitIsGhost("player") then return false end
  return true
end

function P.Tick()
  local N, hbd = NS.Nav, NS.HBD()
  if not (N and N.Cell and hbd) then return end
  if IsInInstance and IsInInstance() then last = nil return end
  local x, y, inst = hbd:GetPlayerWorldPosition()
  if not x or not N.Has(inst) or not OnFoot() then last = nil return end
  local now = GetTime()
  local was = last
  last = { inst = inst, x = x, y = y, t = now }
  if not was or was.inst ~= inst then return end
  local d = sqrt((x - was.x) ^ 2 + (y - was.y) ^ 2)
  if d < 1 or d > JUMP or d > FASTEST * max(now - was.t, STEP) then return end
  local ax, ay = N.Cell(was.x, was.y)
  local bx, by = N.Cell(x, y)
  local steps = max(abs(bx - ax), abs(by - ay)) * 2 + 1
  for k = 0, steps do
    local t = k / steps
    Mark(inst, floor(ax + (bx - ax) * t + 0.5), floor(ay + (by - ay) * t + 0.5))
  end
end

function P:Init()
  C_Timer.NewTicker(STEP, function() NS.Safe("paths", P.Tick) end)
  C_Timer.NewTicker(120, function() NS.Safe("paths", P.Save) end)
  NS.On("PLAYER_LOGOUT", function() NS.Safe("paths", P.Save) end)
end
