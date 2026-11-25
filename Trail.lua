-- Sunstone: a trail of dots on the minimap (and world map) to where you're going, planned around the terrain
-- (Nav.lua). It follows whatever the arrow is set to (the route's next stop or zone crossing, or a place
-- you picked), else any TomTom waypoint you set yourself. Gold dots = walking, blue = swimming, gray = a straight line where no
-- walkable way was found. Re-plans when the destination changes or you wander off the line.
-- Information only: it draws a line to follow. It never moves the character.

local _, NS = ...
local Tr = NS.Module("Trail")
NS.Trail = Tr

local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max
local REF = "SunstoneTrail"
local DOT_TEX = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local SPACING, MAX_DOTS = 9, 48          -- minimap: a dot every 9 yards, up to about 430 yards ahead
local WORLD_SPACING, MAX_WORLD = 30, 220 -- world map
local OFF_PATH = 30                      -- re-plan when you're this far from the line
local ARRIVED = 8
local BUDGET_MS = 3                      -- planning time per frame
local GOLD, BLUE, GRAY = { 0.98, 0.78, 0.25 }, { 0.35, 0.65, 1.0 }, { 0.65, 0.65, 0.65 }

local miniDots, worldDots = {}, {}
local job, path, plan       -- plan = { inst, tx, ty, straight }
Tr.status = "Off"

local function Enabled() return NS.db and NS.db.trail ~= false end

local function Dist(ax, ay, bx, by) return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function Dot(pool, i, size)
  local d = pool[i]
  if not d then
    d = CreateFrame("Frame")
    d:SetSize(size, size)
    d.tex = d:CreateTexture(nil, "OVERLAY")
    d.tex:SetAllPoints()
    d.tex:SetTexture(DOT_TEX)
    pool[i] = d
  end
  return d
end

local function ClearDots()
  local pins = NS.Pins()
  if pins then
    if pins.RemoveAllMinimapIcons then pcall(pins.RemoveAllMinimapIcons, pins, REF) end
    if pins.RemoveAllWorldMapIcons then pcall(pins.RemoveAllWorldMapIcons, pins, REF) end
  end
  for _, d in ipairs(miniDots) do d:Hide() end
  for _, d in ipairs(worldDots) do d:Hide() end
end

function Tr.Clear(status)
  job, path, plan = nil, nil, nil
  ClearDots()
  Tr.status = status or Tr.status
end

-- Where to: the route's current target, else TomTom's closest waypoint. -> mapID, x, y (0..1), title
function Tr.Target()
  local R = NS.Route
  if NS.Arrow and NS.Arrow.Picked() then return NS.Arrow.Target() end
  if R and NS.cdb and NS.cdb.route and NS.cdb.route.enabled and R.target then
    return R.target.m, R.target.x, R.target.y, R.target.title
  end
  if TomTom and TomTom.IsCrazyArrowEmpty and not TomTom:IsCrazyArrowEmpty() and TomTom.GetClosestWaypoint then
    local ok, w = pcall(TomTom.GetClosestWaypoint, TomTom)
    if ok and type(w) == "table" and w[1] and w[2] and w[3] then return w[1], w[2], w[3], w.title end
  end
end

-- The spot `yards` further along the trail and how far is left to walk, for the arrow (nil: no trail to tx, ty, or only a straight line)
function Tr.Ahead(px, py, yards, tx, ty)
  if not path or #path < 2 or not plan or plan.straight or job then return nil end
  if Dist(plan.tx, plan.ty, tx, ty) > 3 then return nil end
  local best, bi, bx, by = math.huge, 1, path[1][1], path[1][2]
  for i = 1, #path - 1 do
    local ax, ay, cx, cy = path[i][1], path[i][2], path[i + 1][1], path[i + 1][2]
    local vx, vy = cx - ax, cy - ay
    local l2 = vx * vx + vy * vy
    local t = l2 > 0 and max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / l2)) or 0
    local qx, qy = ax + vx * t, ay + vy * t
    local d = Dist(px, py, qx, qy)
    if d < best then best, bi, bx, by = d, i, qx, qy end
  end
  if best > OFF_PATH * 2 then return nil end
  local left, need, ox, oy = best, yards, nil, nil
  local x, y = bx, by
  for i = bi, #path - 1 do
    local ex, ey = path[i + 1][1], path[i + 1][2]
    local seg = Dist(x, y, ex, ey)
    if not ox and seg >= need and seg > 0 then ox, oy = x + (ex - x) * need / seg, y + (ey - y) * need / seg end
    need = need - seg
    left = left + seg
    x, y = ex, ey
  end
  if not ox then ox, oy = x, y end
  return ox, oy, left
end

-- Walk along the path from the spot closest to (px, py), calling fn(x, y, water) every `spacing` yards.
local function Walk(px, py, spacing, limit, fn)
  if not path or #path < 2 then return end
  local best, bi, bx, by = math.huge, 1, path[1][1], path[1][2]
  for i = 1, #path - 1 do
    local ax, ay, cx, cy = path[i][1], path[i][2], path[i + 1][1], path[i + 1][2]
    local vx, vy = cx - ax, cy - ay
    local l2 = vx * vx + vy * vy
    local t = l2 > 0 and max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / l2)) or 0
    local qx, qy = ax + vx * t, ay + vy * t
    local d = Dist(px, py, qx, qy)
    if d < best then best, bi, bx, by = d, i, qx, qy end
  end
  local n, carry, x, y = 0, spacing, bx, by
  for i = bi, #path - 1 do
    local ex, ey = path[i + 1][1], path[i + 1][2]
    local seg = Dist(x, y, ex, ey)
    local water = path[i + 1][3]
    while seg >= carry do
      x, y = x + (ex - x) * carry / seg, y + (ey - y) * carry / seg
      seg = seg - carry
      carry = spacing
      n = n + 1
      if n > limit then return best end
      fn(x, y, water)
    end
    carry = carry - seg
    x, y = ex, ey
  end
  return best
end

local function Draw(px, py, inst)
  local pins = NS.Pins()
  if not pins or not path then return end
  local color = plan and plan.straight and GRAY
  local i = 0
  local off = Walk(px, py, SPACING, MAX_DOTS, function(x, y, water)
    i = i + 1
    local d = Dot(miniDots, i, 6)
    local c = color or (water and BLUE or GOLD)
    d.tex:SetVertexColor(c[1], c[2], c[3], 1 - (i / MAX_DOTS) * 0.5)
    d:Show()
    pins:AddMinimapIconWorld(REF, d, inst, x, y, false)
  end)
  for k = i + 1, #miniDots do
    if miniDots[k]:IsShown() then pins:RemoveMinimapIcon(REF, miniDots[k]); miniDots[k]:Hide() end
  end
  return off
end

local function DrawWorld(px, py, inst)
  local pins = NS.Pins()
  if not pins or not path or not pins.AddWorldMapIconWorld then return end
  local color = plan and plan.straight and GRAY
  local i = 0
  Walk(px, py, WORLD_SPACING, MAX_WORLD, function(x, y, water)
    i = i + 1
    local d = Dot(worldDots, i, 7)
    local c = color or (water and BLUE or GOLD)
    d.tex:SetVertexColor(c[1], c[2], c[3], 0.9)
    d:Show()
    pins:AddWorldMapIconWorld(REF, d, inst, x, y, HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
  end)
  for k = i + 1, #worldDots do
    if worldDots[k]:IsShown() then pins:RemoveWorldMapIcon(REF, worldDots[k]); worldDots[k]:Hide() end
  end
end

local function Start(inst, px, py, tx, ty, title)
  plan = { inst = inst, tx = tx, ty = ty, title = title }
  job = coroutine.create(function() return NS.Nav.Find(inst, px, py, tx, ty) end)
  Tr.status = "Planning a way to " .. (title or "your destination") .. "..."
end

local function Finish(ok, pts, info)
  job = nil
  if ok and pts then
    path = pts
    plan.straight = false
    local len = 0
    for i = 1, #pts - 1 do len = len + Dist(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]) end
    Tr.status = string.format("Trail to %s: %d yards, %d turn%s around the terrain.", plan.title or "your destination",
      floor(len + 0.5), #pts - 2, #pts == 3 and "" or "s")
  else
    -- no way found (or an error): a plain straight line, drawn gray
    local hbd = NS.HBD()
    local px, py
    if hbd then px, py = hbd:GetPlayerWorldPosition() end -- (not `hbd and ...`: that keeps only one value)
    path = { { px or plan.tx, py or plan.ty, false }, { plan.tx, plan.ty, false } }
    plan.straight = true
    Tr.status = "No walkable way found to " .. (plan.title or "your destination") .. " (" .. tostring(info or pts) .. "): straight line shown."
  end
  local hbd = NS.HBD()
  local px, py = hbd:GetPlayerWorldPosition()
  if px then DrawWorld(px, py, plan.inst) end
end

local function Tick()
  if not Enabled() then if path or job then Tr.Clear("Off (/sun trail on)") end return end
  local hbd = NS.HBD()
  if not (hbd and NS.Nav and NS.NAV) then return end
  local px, py, inst = hbd:GetPlayerWorldPosition()
  if not px or (IsInInstance and IsInInstance()) then
    if path then Tr.Clear("Not shown inside instances.") end
    return
  end
  local m, x, y, title = Tr.Target()
  if not m then if path or job then Tr.Clear("No destination: turn the route on, or set a TomTom waypoint.") end return end
  local tx, ty, tinst = hbd:GetWorldCoordinatesFromZone(x, y, m)
  if not tx or tinst ~= inst then if path or job then Tr.Clear("Your destination is on another continent.") end return end
  if not NS.Nav.Has(inst) then if path or job then Tr.Clear("No ground data for this continent.") end return end
  if Dist(px, py, tx, ty) < ARRIVED then if path or job then Tr.Clear("You're there.") end return end
  local same = plan and plan.inst == inst and Dist(plan.tx, plan.ty, tx, ty) < 3
  if not same then
    Start(inst, px, py, tx, ty, title)
    return
  end
  if job then return end
  local off = Draw(px, py, inst)
  if off and off > OFF_PATH then Start(inst, px, py, tx, ty, title) end
end

-- planning runs a few milliseconds per frame until it's done
local function Step()
  if not job then return end
  local t0 = debugprofilestop()
  repeat
    local ok, pts, info = coroutine.resume(job)
    if coroutine.status(job) == "dead" then
      if not ok then NS.Error("trail planning", pts) end
      NS.Safe("trail", Finish, ok, pts, info)
      return
    end
  until debugprofilestop() - t0 > BUDGET_MS
end
Tr.Step = Step
function Tr.Busy() return job ~= nil end
function Tr.Path() return path end
local runner = CreateFrame("Frame")
runner:SetScript("OnUpdate", Step)

NS.Setting("The trail", "Dots on the minimap and map", "The way to where the arrow points, around the terrain.", function() return Enabled() end, function(v)
  NS.db.trail = v and true or false
  if v then Tr.Refresh() else Tr.Clear("Off") end
end)

Tr.Tick = Tick
function Tr.Refresh()
  plan = nil -- forces a new plan on the next tick (the old dots stay until it's ready)
  NS.Safe("trail", Tick)
end

function Tr:Init()
  if NS.db.trail == nil then NS.db.trail = true end
  C_Timer.NewTicker(0.25, function() NS.Safe("trail", Tick) end)
  C_Timer.NewTicker(300, function() if NS.Nav and not job then NS.Nav.ForgetWalked() end end) -- newly walked paths count
  -- Well Trodden draws its own trail; two trails at once are confusing, so say so once
  C_Timer.After(8, function()
    if Enabled() and WellTroddenDB and WellTroddenDB.trail and not NS.db.trailHinted then
      NS.db.trailHinted = true
      NS.Print("Sunstone now draws its own trail around the terrain (gold dots). Well Trodden's trail is on too: "
        .. "turn it off with its minimap button or /trodden if you only want one. (/sun trail off turns Sunstone's off.)")
    end
  end)
end

NS.Command("trail", "- the minimap trail around the terrain: on, off, or no word for what it's doing", function(rest)
  rest = (rest or ""):lower()
  if rest == "on" then
    NS.db.trail = true; Tr.Refresh(); NS.Print("trail on.")
  elseif rest == "off" then
    NS.db.trail = false; Tr.Clear("Off (/sun trail on)"); NS.Print("trail off.")
  else
    NS.Print("trail: " .. (Enabled() and Tr.status or "off (/sun trail on)"))
  end
end)
