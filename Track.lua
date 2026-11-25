-- Sunstone: where you've been. Remembers the way you came (this character, the last hour or two of it) and draws it on the world map in violet when
-- you want to retrace your steps. Off by default; it's remembered either way, so it's there when you switch it on. This is only the picture: the
-- walking paths the trail learns from are Paths.lua's, and work whether or not this is shown. Kept in your own saved settings, sent nowhere.

local _, NS = ...
local Tk = NS.Module("Track")
NS.Track = Tk

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min
local STEP = 28      -- yards between two remembered spots
local BREAK = 140    -- further apart than this isn't walking: a portal, a flight, a hearthstone
local MOST = 1800    -- spots kept
local DRAWN = 450    -- lines drawn at most

function Tk.On() return NS.cdb ~= nil and NS.cdb.trackShown == true end
local function Data()
  local t = NS.cdb.track
  if type(t) ~= "table" then t = {}; NS.cdb.track = t end
  return t
end
function Tk.Count()
  local n = 0
  for _, s in ipairs(Data()) do n = n + #s / 2 end
  return n
end

local last -- { inst, x, y }
function Tk.Add(inst, x, y) -- true when it was far enough to remember
  x, y = floor(x + 0.5), floor(y + 0.5)
  local t = Data()
  local seg = t[#t]
  if last and last.inst == inst and seg and seg.i == inst then
    local d = sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2)
    if d < STEP then return false end
    if d > BREAK then seg = nil end
  else
    seg = nil
  end
  if not seg then
    if t[#t] and #t[#t] < 4 then t[#t] = nil end -- (a single spot is no way)
    seg = { i = inst }
    t[#t + 1] = seg
  end
  seg[#seg + 1] = x
  seg[#seg + 1] = y
  last = { inst = inst, x = x, y = y }
  local over = Tk.Count() - MOST
  while over > 0 and t[1] do
    if #t[1] <= 4 then over = over - #t[1] / 2; table.remove(t, 1)
    else table.remove(t[1], 1); table.remove(t[1], 1); over = over - 1 end
  end
  return true
end

function Tk.Tick()
  local hbd = NS.HBD()
  if not hbd or (IsInInstance and IsInInstance()) then return end
  if (UnitOnTaxi and UnitOnTaxi("player")) or (UnitIsGhost and UnitIsGhost("player")) then last = nil return end
  local x, y, inst = hbd:GetPlayerWorldPosition()
  if not x or not inst then return end
  if Tk.Add(inst, x, y) and Tk.On() then Tk.Draw() end
end

function Tk.Clear()
  NS.cdb.track, last = {}, nil
  Tk.Draw()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- the way on a map: { { x1, y1, x2, y2, age 0 (now) - 1 }, ... }
function Tk.Segments(mapID)
  local hbd = NS.HBD()
  local out = {}
  if not (hbd and hbd.GetZoneCoordinatesFromWorld and mapID) then return out end
  local _, _, inst = hbd:GetPlayerWorldPosition()
  local total, k = max(1, Tk.Count()), 0
  local thin = max(1, floor(total / DRAWN + 0.999))
  for _, s in ipairs(Data()) do
    local px, py
    local n = #s / 2
    for j = 1, n do
      k = k + 1
      if s.i == inst and (j % thin == 1 or thin == 1 or j == n) then
        local ok, x, y = pcall(hbd.GetZoneCoordinatesFromWorld, hbd, s[j * 2 - 1], s[j * 2], mapID, true)
        if not (ok and type(x) == "number" and type(y) == "number" and x > -0.02 and x < 1.02 and y > -0.02 and y < 1.02) then x, y = nil, nil end
        if x and px then out[#out + 1] = { px, py, x, y, 1 - k / total } end
        px, py = x, y
      end
    end
  end
  -- the last bit, up to where you stand
  local d = out[#out]
  if d and hbd.GetPlayerZonePosition and WorldMapFrame and last then
    local wx, wy = hbd:GetPlayerWorldPosition()
    local ok, x, y = pcall(hbd.GetZoneCoordinatesFromWorld, hbd, wx or 0, wy or 0, mapID, true)
    if ok and type(x) == "number" and type(y) == "number" and d[5] < 0.01 then out[#out + 1] = { d[3], d[4], x, y, 0 } end
  end
  return out
end

local lines = {}
function Tk.Draw()
  for _, l in ipairs(lines) do l:Hide() end
  local map, V = WorldMapFrame, NS.MapView
  if not (Tk.On() and map and map:IsShown() and V and V.Layer and map.GetMapID) then return end
  local layer, w, h, zoom = V.Layer()
  if not layer then return end
  local segs = Tk.Segments(map:GetMapID())
  local n = 0
  for pass = 1, 2 do -- a dark edge under it all, then the line
    for _, s in ipairs(segs) do
      n = n + 1
      local l = lines[n]
      if not l then
        l = layer:CreateLine(nil, "ARTWORK")
        lines[n] = l
      end
      l:SetThickness((pass == 1 and 4.5 or 2.5) / max(zoom, 0.1))
      if pass == 1 then l:SetColorTexture(0.02, 0.03, 0.05, 0.45) else l:SetColorTexture(0.80, 0.56, 0.95, 0.95 - 0.55 * min(1, s[5])) end
      if l.SetDrawLayer then l:SetDrawLayer("ARTWORK", pass) end
      l:SetStartPoint("TOPLEFT", layer, s[1] * w, -s[2] * h)
      l:SetEndPoint("TOPLEFT", layer, s[3] * w, -s[4] * h)
      l:Show()
    end
  end
end

function Tk.Set(on)
  NS.cdb.trackShown = on and true or false
  Tk.Draw()
  if NS.MapView and NS.MapView.Buttons then NS.MapView.Buttons() end
  if NS.Atlas then NS.Atlas.Redraw() end
  if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
end

function Tk:Init()
  C_Timer.NewTicker(1, function() NS.Safe("where you've been", Tk.Tick) end)
  if WorldMapFrame then
    WorldMapFrame:HookScript("OnShow", function() NS.Safe("where you've been", Tk.Draw) end)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() NS.Safe("where you've been", Tk.Draw) end) end
  end
  NS.Setting("On the world map", "Where I've been", "The way you came, in violet, to retrace your steps. Off: it's still remembered, and the trail still learns the ground you walk.",
    function() return Tk.On() end, Tk.Set)
end

NS.Command("been", "[on|off|clear] - where you've been, in violet on the world map", function(rest)
  rest = (rest or ""):lower()
  if rest == "clear" then
    Tk.Clear()
    NS.Print("the way you came is forgotten.")
    return
  end
  Tk.Set(rest == "on" or (rest ~= "off" and not Tk.On()))
  NS.Print(Tk.On() and "where you've been is on the world map, in violet." or "where you've been is off the map.")
end)
