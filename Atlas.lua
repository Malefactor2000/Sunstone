-- Sunstone: the smooth map. Turn the wheel or drag on the world map and the whole world is one sheet: zoom from Azeroth down to a camp and drag it
-- anywhere, in the game's own parchment style, with the land you've explored drawn in. The route, its stops, the trail, where you've been, quests,
-- flight masters, boats and dungeon doors are on it. It's Sunstone's own sheet laid over the map (the game's map underneath is never touched, so
-- it works in combat too); right-click steps out, the button at the bottom or any other map choice goes back to the game's own map.
-- Information only.

local _, NS = ...
local At = NS.Module("Atlas")
NS.Atlas = At
local C = NS.C

local W, H = 1002, 668           -- the world sheet's own units
local WORLD, CONTS = 947, { [1414] = 1, [1415] = 0 }
local MAXZ, STEP, SPEED = 75, 1.22, 11
local floor, max, min, exp, log, abs, sqrt = math.floor, math.max, math.min, math.exp, math.log, math.abs, math.sqrt
local function Num(v) return type(v) == "number" and v or nil end
local function List(v) return type(v) == "table" and v or {} end
local function Ease(v, a, b) local t = max(0, min(1, (v - a) / (b - a))) return t * t * (3 - 2 * t) end

function At.On() return not (NS.db and NS.db.atlas == false) and not (NS.IsAddOnLoaded and NS.IsAddOnLoaded("MapUtils")) end

---------------------------------------------------------------------------
-- Where things are on the sheet (0 to 1)
---------------------------------------------------------------------------
function At.Point(wx, wy, inst)
  local hbd = NS.HBD()
  if not (hbd and wx and wy and (inst == 0 or inst == 1) and hbd.GetAzerothWorldMapCoordinatesFromWorld) then return nil end
  local ok, u, v = pcall(hbd.GetAzerothWorldMapCoordinatesFromWorld, hbd, wx, wy, inst, true)
  if ok and Num(u) and Num(v) then return u, v end
end
function At.Spot(m, x, y) -- a place on a zone's map (0 to 1)
  local hbd = NS.HBD()
  if not (hbd and m and x and y) then return nil end
  local ok, wx, wy, inst = pcall(hbd.GetWorldCoordinatesFromZone, hbd, x, y, m)
  if ok and wx then return At.Point(wx, wy, inst) end
end
local rects = {}
function At.Rect(m) -- -> left, top, right, bottom; nil: not on the sheet
  local r = rects[m]
  if r == nil then
    if m == WORLD then r = { 0, 0, 1, 1 }
    else
      local l, t = At.Spot(m, 0, 0)
      local rr, b = At.Spot(m, 1, 1)
      r = l and rr and rr > l and b > t and { l, t, rr, b } or false
    end
    rects[m] = r
  end
  if r then return r[1], r[2], r[3], r[4] end
end
function At.Fit(m) -- the view that fills the window with a map -> x, y, zoom
  local l, t, r, b = At.Rect(m)
  if not l then return nil end
  return (l + r) / 2, (t + b) / 2, max(1, 1 / max(r - l, b - t))
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local f, plane, lay -- the window over the map, the sheet, its layers
local view = { x = 0.5, y = 0.5, z = 1, tz = 1 }
local S, vw, vh = 1, W, H
local dirty = true
At.view = view

local function Clamp() -- (the world fits at zoom 1; a continent's own map reaches past the world map's left or right edge, never past its top or bottom)
  local free = max(0, min(1, (view.z - 1) / 0.18))
  local hw, hh = vw / (2 * W * S * view.z), vh / (2 * H * S * view.z)
  local x0, x1 = 0.5 + (hw - 0.186 - 0.5) * free, 0.5 + (1.159 - hw - 0.5) * free
  view.x = x0 < x1 and max(x0, min(x1, view.x)) or 0.5
  view.y = hh < 0.5 and max(hh, min(1 - hh, view.y)) or 0.5
end
local function Cursor() -- the pointer, from the middle of the window (its own units; up is negative)
  local x, y = GetCursorPosition()
  local s = Num(f:GetEffectiveScale()) or 1
  local l, b = Num(f:GetLeft()) or 0, Num(f:GetBottom()) or 0
  return x / s - l - vw / 2, (b + vh / 2) - y / s
end
local function At2(ox, oy) return view.x + ox / (W * S * view.z), view.y + oy / (H * S * view.z) end -- what's under a spot of the window

function At.Zoom(delta, ox, oy)
  view.glide = nil
  view.tz = max(1, min(MAXZ, (view.tz or view.z) * STEP ^ delta))
  view.ox, view.oy = ox or 0, oy or 0
  view.ax, view.ay = At2(view.ox, view.oy)
end
function At.Glide(x, y, z, secs)
  view.tz = z
  view.glide = { x0 = view.x, y0 = view.y, z0 = view.z, x1 = x, y1 = y, z1 = z, t = 0, d = secs or 0.7 }
end
function At.GlideTo(m)
  local x, y, z = At.Fit(m)
  if not x then return false end
  At.Glide(x, y, z)
  return true
end

---------------------------------------------------------------------------
-- The ground: world and continent art, each zone's own map cut to its outline, the land you've explored
---------------------------------------------------------------------------
local function Sheet(parent, level, all)
  local s = CreateFrame("Frame", nil, parent)
  s:SetAllPoints(all or parent)
  s:SetFrameLevel(level)
  return s
end
local function Tiles(sheet, m) -- the map's own picture, without anything on it
  local art = NS.ZoneMap and NS.ZoneMap.Art(m)
  local l, t, r, b = At.Rect(m)
  if not (art and l) then return false end
  local sx, sy = (r - l) * W / art.w, (b - t) * H / art.h
  for _, p in ipairs(art.tiles) do
    if p[8] == "BACKGROUND" then
      local x = sheet:CreateTexture(nil, "BACKGROUND")
      x:SetTexture(p[1], nil, nil, "TRILINEAR")
      -- the last column and row run over the edge of the map
      local w, h = min(p[4], art.w - p[2]), min(p[5], art.h - p[3])
      x:SetTexCoord(0, p[6] * w / p[4], 0, p[7] * h / p[5])
      x:SetPoint("TOPLEFT", sheet, "TOPLEFT", l * W + p[2] * sx, -(t * H + p[3] * sy))
      x:SetSize(w * sx, h * sy)
      if sheet.cut then pcall(x.AddMaskTexture, x, sheet.cut) end
    end
  end
  return true
end
local function Cut(sheet, zone, file)
  local l, t, r, b = At.Rect(zone)
  if not (sheet.CreateMaskTexture and l) then return nil end
  local ok, m = pcall(sheet.CreateMaskTexture, sheet)
  if not ok or not m then return nil end
  m:SetTexture(NS.MEDIA .. (file or "zones\\z" .. zone .. ".png"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  m:SetPoint("TOPLEFT", sheet, "TOPLEFT", l * W, -t * H)
  m:SetSize((r - l) * W, (b - t) * H)
  sheet.cut = m
  return m
end

local zones = {} -- [zone] = { l, t, r, b, base = sheet, land = sheet, tex = {}, name, any }
local order = {}
local function Zones()
  if #order > 0 then return end
  for m in pairs(List(_G.SunstoneZoneShapes)) do
    local l, t, r, b = At.Rect(m)
    if l then
      local ok, info = pcall(C_Map and C_Map.GetMapInfo or error, m)
      local mid = _G.SunstoneZoneShapes[m]
      zones[m] = { m = m, l = l, t = t, r = r, b = b, name = ok and type(info) == "table" and info.name or "", nx = l + (r - l) * mid[1], ny = t + (b - t) * mid[2] }
      order[#order + 1] = m
    end
  end
  table.sort(order)
end
local function Land(z) -- the land you've explored in a zone
  if not z.land then
    z.land = Sheet(plane, lay.land, plane)
    Cut(z.land, z.m)
    z.tex = {}
  end
  local w, h = (z.r - z.l) * W, (z.b - z.t) * H
  local list = NS.Continent and NS.Continent.ZonePieces and NS.Continent.ZonePieces(z.m) or {}
  for k, p in ipairs(list) do
    local x = z.tex[k]
    if not x then
      x = z.land:CreateTexture(nil, "ARTWORK")
      if z.land.cut then pcall(x.AddMaskTexture, x, z.land.cut) end
      z.tex[k] = x
    end
    x:SetTexture(p[1], nil, nil, "TRILINEAR")
    x:SetTexCoord(0, p[6], 0, p[7])
    x:ClearAllPoints()
    x:SetPoint("TOPLEFT", z.land, "TOPLEFT", z.l * W + p[2] * w, -(z.t * H + p[3] * h))
    x:SetSize(p[4] * w, p[5] * h)
    x:Show()
  end
  for k = #list + 1, #z.tex do z.tex[k]:Hide() end
  z.any, z.built, z.stale = #list > 0, true, nil
end
local function Base(z) -- its own parchment
  z.base = Sheet(plane, lay.base, plane)
  Cut(z.base, z.m)
  Tiles(z.base, z.m)
end

local function InView(z)
  local hw, hh = vw / (2 * W * S * view.z), vh / (2 * H * S * view.z)
  return z.r > view.x - hw and z.l < view.x + hw and z.b > view.y - hh and z.t < view.y + hh
end
local function Ground() -- what's shown at this zoom, and how strongly
  local z = view.z
  local near = view.x < 0.48 and 1414 or 1415
  for m, s in pairs(lay.conts) do
    local a = m == near and Ease(z, 1.02, 1.19) or 0
    s.a = s.a + (a - s.a) * 0.25
    if abs(s.a - a) < 0.01 then s.a = a else dirty = true end
    s:SetAlpha(s.a)
    s:SetShown(s.a > 0)
  end
  local close = Ease(z, 7, 12)
  lay.shade:SetAlpha(0.36 * (1 - close))
  local made = 0
  for _, m in ipairs(order) do
    local zn = zones[m]
    local seen = InView(zn)
    if seen and (not zn.built or zn.stale) and made < 2 then Land(zn); made = made + 1 end
    if zn.land then zn.land:SetShown(seen) end
    if close > 0 and seen then
      if not zn.base and made < 2 then Base(zn); made = made + 1 end
      if zn.base then zn.base:SetShown(true); zn.base:SetAlpha(close) end
    elseif zn.base then zn.base:SetShown(false) end
  end
  if made > 0 then dirty = true end
end

---------------------------------------------------------------------------
-- Lines: the route, the trail, where you've been
---------------------------------------------------------------------------
local lines, used = {}, 0
local function Line(u0, v0, u1, v1, c, thick, sub)
  used = used + 1
  local l = lines[used]
  if not l then
    local ok, made = pcall(lay.lines.CreateLine, lay.lines, nil, "ARTWORK")
    if not ok or not made then used = used - 1 return end
    l = made
    lines[used] = l
  end
  l.thick = thick
  l:SetThickness(thick / (S * view.z))
  if l.SetDrawLayer then l:SetDrawLayer("ARTWORK", sub or 0) end
  l:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  l:SetStartPoint("TOPLEFT", plane, u0 * W, -v0 * H)
  l:SetEndPoint("TOPLEFT", plane, u1 * W, -v1 * H)
  l:Show()
end
local EDGE, NEXT, REST, BEEN, TRAIL = { 0.02, 0.02, 0.03, 0.55 }, { 1, 0.90, 0.52, 1 }, { 0.45, 0.80, 1, 0.95 }, { 0.80, 0.56, 0.95 }, { 1, 0.72, 0.25, 1 }
local function Way(pts, colour, thick, sub)
  for k = 2, #pts do
    local a, b = pts[k - 1], pts[k]
    if a[1] and b[1] then Line(a[1], a[2], b[1], b[2], EDGE, thick + 2.2, sub) end
  end
  for k = 2, #pts do
    local a, b = pts[k - 1], pts[k]
    if a[1] and b[1] then Line(a[1], a[2], b[1], b[2], type(colour) == "function" and colour(b) or colour, thick, sub + 1) end
  end
end
local function Lines()
  used = 0
  local hbd = NS.HBD()
  local px, py, inst
  if hbd then px, py, inst = hbd:GetPlayerWorldPosition() end
  -- where you've been
  local Tk = NS.Track
  if Tk and Tk.On() then
    for _, s in ipairs(List(NS.cdb.track)) do
      local n = #s / 2
      local step = max(1, floor(n / 160 + 0.99))
      local pu, pv
      for j = 1, n do
        if j % step == 0 or j == 1 or j == n then
          local u, v = At.Point(s[j * 2 - 1], s[j * 2], s.i)
          if u and pu then Line(pu, pv, u, v, { BEEN[1], BEEN[2], BEEN[3], 0.8 }, 2.6, 1) end
          pu, pv = u, v
        end
      end
    end
  end
  -- the route
  local V = NS.MapView
  if V and V.RouteStops and (V.LineMode() ~= "off" or V.trip) then
    local pts = {}
    if px then local u, v = At.Point(px, py, inst); pts[1] = { u, v, 0 } end
    for _, p in ipairs(V.RouteStops(V.LineMode() == "all")) do
      local u, v = At.Spot(p.m, p.x / 100, p.y / 100)
      pts[#pts + 1] = { u, v, p.leg }
    end
    Way(pts, function(p) return (p[3] or 1) <= 1 and NEXT or REST end, 3.2, 2)
  end
  -- the trail to the next stop, around the terrain
  local path = NS.Trail and NS.Trail.Path and NS.Trail.Path()
  if type(path) == "table" and inst then
    local pts = {}
    for _, p in ipairs(path) do local u, v = At.Point(p[1], p[2], inst); pts[#pts + 1] = { u, v } end
    Way(pts, TRAIL, 2.4, 4)
  end
  for k = used + 1, #lines do lines[k]:Hide() end
end

---------------------------------------------------------------------------
-- Pins (always the same size on the screen)
---------------------------------------------------------------------------
local pins, pinN = {}, 0
local function Pin()
  pinN = pinN + 1
  local p = pins[pinN]
  if p then return p end
  p = CreateFrame("Button", nil, lay.pins)
  p.rim = p:CreateTexture(nil, "BACKGROUND")
  p.rim:SetAllPoints()
  p.rim:SetTexture(NS.MEDIA .. "dot.png")
  p.bg = p:CreateTexture(nil, "BORDER")
  p.bg:SetPoint("TOPLEFT", 1.5, -1.5)
  p.bg:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
  p.bg:SetTexture(NS.MEDIA .. "dot.png")
  p.bg:SetVertexColor(0.07, 0.055, 0.045, 1)
  p.glyph = p:CreateTexture(nil, "ARTWORK")
  p.glyph:SetPoint("TOPLEFT", 2.5, -2.5)
  p.glyph:SetPoint("BOTTOMRIGHT", -2.5, 2.5)
  p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnEnter", function(self)
    local d = self.d
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.t or "?", C.accent[1], C.accent[2], C.accent[3])
    for _, l in ipairs(List(d.lines)) do
      local text = type(l) == "function" and l() or l
      if type(text) == "string" then GameTooltip:AddLine(text, C.text[1], C.text[2], C.text[3], true) end
    end
    GameTooltip:AddLine("Click: point the arrow here." .. (d.right and (" Right-click: " .. (d.rightText or "more") .. ".") or ""), C.dim[1], C.dim[2], C.dim[3], true)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self, button)
    local d = self.d
    if not d then return end
    if button == "RightButton" then
      if d.right then NS.Safe("map pin", d.right) end
      return
    end
    if d.stop then
      if NS.MapView then NS.MapView.trip = nil end
    end
    NS.Arrow.Go(d.m, d.x, d.y, d.t)
    NS.Print("arrow set to " .. (d.t or "there") .. ".")
  end)
  -- the wheel and dragging go through pins to the map
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta) At.Wheel(delta) end)
  pins[pinN] = p
  return p
end
local GOLD, GREEN, ORANGE, YELLOW, BLUE, STAR = { 1, 0.85, 0.40 }, { 0.50, 0.80, 0.38 }, { 0.92, 0.52, 0.26 }, { 0.98, 0.84, 0.20 }, { 0.45, 0.80, 1 }, { 0.95, 0.75, 0.3 }
local function Put(d, u, v, size, colour, glyph, num, least)
  if not u then return end
  local p = Pin()
  p.d, p.u, p.v, p.least = d, u, v, least or 0
  p:SetSize(size, size)
  p.rim:SetVertexColor(colour[1], colour[2], colour[3], 1)
  if glyph then
    p.glyph:SetTexture(glyph)
    p.glyph:SetVertexColor(colour[1], colour[2], colour[3], 1)
    p.glyph:Show()
  else
    p.glyph:Hide()
  end
  p.num:SetText(num or "")
  p.num:SetTextColor(colour[1], colour[2], colour[3])
end
local questItems, questAt
local function Pins()
  pinN = 0
  local now = GetTime()
  if NS.QuestPins and (not questAt or now - questAt > 6 or NS.QuestPins.Shown()) then
    local ok, list = pcall(NS.QuestPins.ForAtlas)
    questItems, questAt = ok and list or {}, now
  end
  -- flight masters, boats, doors, books (Settings: On the world map)
  for _, d in ipairs(List(NS.MapPins and NS.MapPins.items)) do
    local u, v = At.Spot(d.m, d.x / 100, d.y / 100)
    local c = d.color or GOLD
    Put({ t = d.t, lines = d.lines, m = d.m, x = d.x / 100, y = d.y / 100, right = d.right, rightText = d.rightText }, u, v, (d.size or 16) + 1, c, NS.MEDIA .. "pin_" .. d.glyph .. ".png", nil, 3)
  end
  -- quests (not where a stop of the route stands: its number would be under the mark)
  local at = {}
  for _, s in ipairs(List(NS.cdb.route and NS.cdb.route.enabled and NS.Route and NS.Route.stops)) do
    local u, v = At.Point(s.wx, s.wy, s.inst)
    if u then at[#at + 1] = { u, v } end
  end
  for _, d in ipairs(List(questItems)) do
    local u, v = At.Spot(d.m, d.x, d.y)
    for _, s in ipairs(at) do if u and abs(s[1] - u) < 0.0006 and abs(s[2] - v) < 0.0009 then u = nil end end
    Put({ t = d.t, lines = d.lines, m = d.m, x = d.x, y = d.y }, u, v, min(18, d.size), d.c or YELLOW, NS.MEDIA .. "pin_" .. d.glyph .. ".png", nil, 6)
  end
  -- your stars
  for _, k in ipairs(List(NS.cdb.markers)) do
    if Num(k.mapID) and Num(k.x) and Num(k.y) then
      local u, v = At.Spot(k.mapID, k.x, k.y)
      Put({ t = k.title, lines = { k.note }, m = k.mapID, x = k.x, y = k.y }, u, v, 17, STAR, NS.MEDIA .. "star.png", nil, 0)
    end
  end
  -- the route's stops, the next one last (on top)
  local stops = List(NS.cdb.route and NS.cdb.route.enabled and NS.Route and NS.Route.stops)
  for i = #stops, 1, -1 do
    local s = stops[i]
    local u, v = At.Point(s.wx, s.wy, s.inst)
    if not u then u, v = At.Spot(s.m, s.x, s.y) end
    local k = s.node and s.node.kind
    local c = i == 1 and GOLD or k == "pickup" and YELLOW or k == "turnin" and GREEN or k == "obj" and ORANGE or BLUE
    Put({ t = i .. ". " .. (NS.XPRun and NS.XPRun.Text(s) or "stop"), lines = { k == "obj" and s.node.quest and s.node.quest.title or nil }, m = s.m, x = s.x, y = s.y, stop = true },
      u, v, i == 1 and 24 or 20, c, nil, tostring(i), 0)
  end
  for k = pinN + 1, #pins do pins[k]:Hide() end
end

---------------------------------------------------------------------------
-- Putting it all in place
---------------------------------------------------------------------------
local labels = {}
local function Place()
  local s = S * view.z
  plane:SetScale(s)
  plane:ClearAllPoints()
  plane:SetPoint("TOPLEFT", f, "CENTER", -view.x * W, view.y * H)
  if lay.zoomed ~= view.z then
    for k = 1, used do lines[k]:SetThickness(lines[k].thick / s) end
    lay.zoomed = view.z
  end
  local kx, ky = W * s, H * s
  local function Set(o, u, v, ok, margin)
    local x, y = (u - view.x) * kx, (v - view.y) * ky
    if ok and abs(x) < vw / 2 + margin and abs(y) < vh / 2 + margin then
      o:ClearAllPoints()
      o:SetPoint("CENTER", f, "CENTER", x, -y)
      o:Show()
    else
      o:Hide()
    end
  end
  for k = 1, pinN do local p = pins[k]; Set(p, p.u, p.v, view.z >= p.least, 12) end
  local a = min(Ease(view.z, 1.5, 2.3), 1 - Ease(view.z, 9, 14))
  for k, m in ipairs(order) do
    local l, z = labels[k], zones[m]
    if not l then
      l = lay.labels:CreateFontString(nil, "OVERLAY")
      if not pcall(l.SetFont, l, "Fonts\\MORPHEUS.TTF", 13, "OUTLINE") and l.SetFontObject then l:SetFontObject("GameFontNormal") end
      l:SetJustifyH("CENTER")
      l:SetText(z.name)
      labels[k] = l
    end
    if z.any then l:SetTextColor(1, 0.93, 0.74, a) else l:SetTextColor(0.80, 0.70, 0.54, a * 0.85) end
    Set(l, z.nx, z.ny, a > 0.02, 60)
  end
end

local function You()
  local hbd = NS.HBD()
  local u, v
  if hbd then u, v = At.Point(hbd:GetPlayerWorldPosition()) end
  if not u then f.you:Hide() return end
  local s = S * view.z
  local x, y = (u - view.x) * W * s, (v - view.y) * H * s
  if abs(x) > vw / 2 or abs(y) > vh / 2 then f.you:Hide() return end
  f.you:ClearAllPoints()
  f.you:SetPoint("CENTER", f, "CENTER", x, -y)
  local face = GetPlayerFacing and GetPlayerFacing()
  if Num(face) and f.you.tex.SetRotation then f.you.tex:SetRotation(face) end
  f.you:Show()
end

-- the zone and the spot under the pointer
function At.Under(u, v)
  local hbd = NS.HBD()
  local w = hbd and hbd.worldMapData
  for cont, inst in pairs(CONTS) do
    local d = type(w) == "table" and w[inst]
    if d then
      local wx, wy = d[3] - u * d[1], d[4] - v * d[2]
      local ok, x, y = pcall(hbd.GetZoneCoordinatesFromWorld, hbd, wx, wy, cont)
      if ok and Num(x) and Num(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (inst == 1) == (u < 0.48) then
        local good, info = pcall(C_Map.GetMapInfoAtPosition, cont, x, y)
        if good and type(info) == "table" and info.mapID and info.mapID ~= cont then
          local _, zx, zy = pcall(hbd.GetZoneCoordinatesFromWorld, hbd, wx, wy, info.mapID)
          return info.mapID, info.name, Num(zx), Num(zy)
        end
        return cont
      end
    end
  end
end

local slow, info = 0, 0
local function Tick(_, dt)
  dt = min(0.1, dt or 0.02)
  local g = view.glide
  if g then
    g.t = min(1, g.t + dt / g.d)
    local e = g.t * g.t * (3 - 2 * g.t)
    view.z = exp(log(g.z0) + (log(g.z1) - log(g.z0)) * e)
    local k = abs(1 / g.z0 - 1 / g.z1) > 1e-6 and (1 / view.z - 1 / g.z1) / (1 / g.z0 - 1 / g.z1) or 1 - e
    view.x, view.y = g.x1 + (g.x0 - g.x1) * k, g.y1 + (g.y0 - g.y1) * k
    if g.t >= 1 then view.glide = nil; view.x, view.y, view.z = g.x1, g.y1, g.z1 end
    dirty = true
  elseif abs(log(view.tz / view.z)) > 0.0015 then
    view.z = exp(log(view.z) + (log(view.tz) - log(view.z)) * (1 - exp(-dt * SPEED)))
    if abs(log(view.tz / view.z)) <= 0.0015 then view.z = view.tz end
    if view.ax then view.x, view.y = view.ax - (view.ox or 0) / (W * S * view.z), view.ay - (view.oy or 0) / (H * S * view.z) end
    dirty = true
  end
  if view.drag then
    local ox, oy = Cursor()
    local dx, dy = ox - view.drag.ox, oy - view.drag.oy
    if abs(dx) + abs(dy) > 4 then view.drag.moved = true end
    if view.drag.moved then
      view.x, view.y = view.drag.x - dx / (W * S * view.z), view.drag.y - dy / (H * S * view.z)
      dirty = true
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then view.drag = nil end
  end
  slow = slow + dt
  if slow > 1.5 then
    slow = 0
    NS.Safe("map lines", Lines)
    NS.Safe("map pins", Pins)
    dirty = true
  end
  if dirty then
    dirty = false
    Clamp()
    Ground()
    Place()
  end
  You()
  info = info + dt
  if info > 0.12 then
    info = 0
    local text = ""
    if f:IsMouseOver() then
      local u, v = At2(Cursor())
      local _, name, zx, zy = At.Under(u, v)
      if name then text = name .. (zx and zy and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 and string.format("  %.1f, %.1f", zx * 100, zy * 100) or "") end
    end
    f.info:SetText(text)
  end
end

function At.Wheel(delta)
  local ox, oy = Cursor()
  At.Zoom(delta, ox, oy)
end

local function Click(button)
  if button == "RightButton" then
    if view.z > 3 then At.GlideTo(view.x < 0.48 and 1414 or 1415)
    elseif view.z > 1.06 then At.Glide(0.5, 0.5, 1)
    else At.Hide() end
    return
  end
  if view.z < 9 then -- into the zone under the pointer
    local u, v = At2(Cursor())
    local m = At.Under(u, v)
    if m and At.Rect(m) and not CONTS[m] then At.GlideTo(m) end
  end
end

local function Make()
  local map = WorldMapFrame
  local box = map and map.ScrollContainer
  if not box then return false end
  f = CreateFrame("Frame", "SunstoneAtlasFrame", map)
  f:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  f:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
  if f.SetClipsChildren then f:SetClipsChildren(true) end
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  local back = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  back:SetAllPoints()
  back:SetColorTexture(0.12, 0.08, 0.05, 1)
  plane = CreateFrame("Frame", nil, f)
  plane:SetSize(W, H)
  plane:SetPoint("TOPLEFT", f, "CENTER", 0, 0)
  lay = { conts = {} }
  local base = Num(f:GetFrameLevel()) or 1
  plane:SetFrameLevel(base + 1)
  lay.world = Sheet(plane, base + 2)
  Tiles(lay.world, WORLD)
  for m in pairs(CONTS) do
    lay.conts[m] = Sheet(plane, base + 3)
    lay.conts[m].a = 0
    Cut(lay.conts[m], m, m == 1414 and "softr.png" or "softl.png") -- (fading into the world's sea toward the other continent)
    Tiles(lay.conts[m], m)
  end
  lay.shadeOn = Sheet(plane, base + 4)
  lay.shade = lay.shadeOn:CreateTexture(nil, "BACKGROUND")
  lay.shade:SetPoint("TOPLEFT", plane, "TOPLEFT", -W, H)
  lay.shade:SetPoint("BOTTOMRIGHT", plane, "BOTTOMRIGHT", W, -H)
  lay.shade:SetColorTexture(0.16, 0.10, 0.04, 1)
  lay.base, lay.land = base + 5, base + 6
  lay.lines = Sheet(plane, base + 8, plane)
  lay.labels = Sheet(f, base + 9)
  lay.pins = Sheet(f, base + 10)
  local you = CreateFrame("Frame", nil, f)
  you:SetSize(30, 30)
  you:SetFrameLevel(base + 30)
  you.tex = you:CreateTexture(nil, "OVERLAY")
  you.tex:SetAllPoints()
  you.tex:SetTexture(NS.MEDIA .. "you.png")
  f.you = you
  local top = Sheet(f, base + 40)
  f.info = top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.info:SetPoint("BOTTOMLEFT", 12, 12)
  f.info:SetShadowOffset(1, -1)
  local function Button(text, w, x, fn)
    local b = NS.Button(top, text, w, fn)
    b:SetPoint("BOTTOMRIGHT", x, 8)
    return b
  end
  f.been = Button("", 118, -10, function() if NS.Track then NS.Track.Set(not NS.Track.On()) end end)
  f.route = Button("", 124, -133, function() if NS.MapView then NS.MapView.NextLineMode() end end)
  Button("My route", 70, -262, function() At.FitRoute() end)
  Button("Me", 36, -337, function() At.FitMe() end)
  Button("The game's map", 108, -378, function() At.Hide() end)
  f:SetScript("OnMouseWheel", function(_, delta) At.Wheel(delta) end)
  f:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      view.glide = nil
      view.tz = view.z
      local ox, oy = Cursor()
      view.drag = { ox = ox, oy = oy, x = view.x, y = view.y }
    end
  end)
  f:SetScript("OnMouseUp", function(_, button)
    local d = view.drag
    view.drag = nil
    if button == "LeftButton" and d and d.moved then return end
    NS.Safe("map click", Click, button)
  end)
  f:SetScript("OnUpdate", function(_, dt) NS.Safe("smooth map", Tick, f, dt) end)
  f:SetScript("OnHide", function() view.drag = nil; GameTooltip:Hide() end)
  f:SetScript("OnSizeChanged", function() At.Size() end)
  f:Hide()
  return true
end

function At.Buttons()
  if not f then return end
  local V, Tk = NS.MapView, NS.Track
  f.route:SetText("Route: " .. (V and V.LINE_NAME[V.LineMode()] or "?"))
  f.route:SetActive(V and V.LineMode() ~= "off")
  f.been:SetText(Tk and Tk.On() and "Where I've been: on" or "Where I've been: off")
  f.been:SetActive(Tk and Tk.On())
end
function At.Redraw()
  if not (f and f:IsShown()) then return end
  NS.Safe("map lines", Lines)
  NS.Safe("map pins", Pins)
  At.Buttons()
  dirty = true
end

function At.Size()
  vw, vh = Num(f:GetWidth()) or W, Num(f:GetHeight()) or H
  if vw < 50 or vh < 50 then vw, vh = W, H end
  S = min(vw / W, vh / H)
  lay.zoomed, dirty = nil, true
end
function At.Shown() return f ~= nil and f:IsShown() == true end
-- Lays the sheet over the map, starting from just what the map shows
function At.Show(mapID)
  local x, y, z = At.Fit(mapID or WORLD)
  if not x then return false end
  if not f and not Make() then return false end
  local strata = WorldMapFrame.GetFrameStrata and WorldMapFrame:GetFrameStrata()
  if strata == "FULLSCREEN" or strata == "FULLSCREEN_DIALOG" then pcall(f.SetFrameStrata, f, "FULLSCREEN_DIALOG") else pcall(f.SetFrameStrata, f, "DIALOG") end
  At.Size()
  Zones()
  if not At.Shown() then
    view.x, view.y, view.z, view.tz, view.glide, view.ax = x, y, z, z, nil, nil
    f:Show()
    for _, zn in pairs(zones) do zn.stale = true end
  end
  lay.zoomed = nil
  At.Redraw()
  return true
end
function At.Hide() if f then f:Hide() end end

function At.FitMe()
  local hbd = NS.HBD()
  local u, v
  if hbd then u, v = At.Point(hbd:GetPlayerWorldPosition()) end
  if u then At.Glide(u, v, max(22, view.z)) end
end
function At.FitRoute()
  local l, t, r, b
  local function Add(u, v)
    if not u then return end
    l, r, t, b = min(l or u, u), max(r or u, u), min(t or v, v), max(b or v, v)
  end
  for _, s in ipairs(List(NS.Route and NS.Route.stops)) do
    local u, v = At.Point(s.wx, s.wy, s.inst)
    Add(u, v)
  end
  local hbd = NS.HBD()
  if hbd then Add(At.Point(hbd:GetPlayerWorldPosition())) end
  if not l then return end
  At.Glide((l + r) / 2, (t + b) / 2, max(1, min(45, 0.82 / max(r - l, b - t, 0.012))))
end
-- Opens the map on a place and zooms into it (the route's stops, from Sunstone's window)
function At.Focus(m, x, y, zoom)
  local u, v = At.Spot(m, x, y)
  if not u or not WorldMapFrame then return false end
  if not WorldMapFrame:IsShown() then
    if InCombatLockdown and InCombatLockdown() then
      NS.Print("the game doesn't let addons open the map in combat: press M, then try again.")
      return false
    end
    if ToggleWorldMap then pcall(ToggleWorldMap) end
  end
  if not WorldMapFrame:IsShown() or not At.Show(WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or m) and not At.Show(m) then return false end
  At.Glide(u, v, zoom or 34, 0.9)
  return true
end

---------------------------------------------------------------------------
-- Taking over from the game's map: a turn of the wheel, or dragging it
---------------------------------------------------------------------------
local function CanOpen()
  local map = WorldMapFrame
  local id = At.On() and map and map.GetMapID and map:GetMapID()
  if not id then return nil end
  -- zoomed into the game's own map (where it allows that): left alone
  return At.Rect(id) and id or nil
end
function At:Init()
  local map = WorldMapFrame
  local box = map and map.ScrollContainer
  if not box then return end
  if box.HookScript then
    pcall(box.EnableMouseWheel, box, true)
    pcall(box.HookScript, box, "OnMouseWheel", function(_, delta)
      if At.Shown() then return end
      local id = CanOpen()
      if id then NS.Safe("smooth map", function() if At.Show(id) then At.Wheel(delta) end end) end
    end)
    local from
    pcall(box.HookScript, box, "OnMouseDown", function(_, button)
      if button == "LeftButton" then local x, y = GetCursorPosition(); from = { x, y } end
    end)
    pcall(box.HookScript, box, "OnMouseUp", function() from = nil end)
    pcall(box.HookScript, box, "OnUpdate", function()
      if not from or At.Shown() then return end
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then from = nil return end
      local x, y = GetCursorPosition()
      if abs(x - from[1]) + abs(y - from[2]) > 14 then
        from = nil
        local id = CanOpen()
        if id then
          NS.Safe("smooth map", function()
            if At.Show(id) then
              local ox, oy = Cursor()
              view.drag = { ox = ox, oy = oy, x = view.x, y = view.y, moved = true }
            end
          end)
        end
      end
    end)
  end
  map:HookScript("OnHide", function() At.Hide() end)
  if map.OnMapChanged then
    hooksecurefunc(map, "OnMapChanged", function()
      if not At.Shown() then return end
      local id = map.GetMapID and map:GetMapID()
      if not (id and At.GlideTo(id)) then At.Hide() end
    end)
  end
  NS.On("MAP_EXPLORATION_UPDATED", function()
    for _, z in pairs(zones) do z.stale = true end
    dirty = true
  end)
  NS.Setting("On the world map", "Smooth map", "The wheel zooms and dragging moves one seamless map of the world, in the game's own style. Off while MapUtils is on.", function() return not (NS.db and NS.db.atlas == false) end,
    function(v)
      NS.db.atlas = v and true or false
      if not v then At.Hide() end
    end)
end
