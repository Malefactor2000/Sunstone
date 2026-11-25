-- Sunstone: the whole continent and the world on the game's own map. The mouse wheel steps out from a zone to its continent and to the world, and
-- back in to the zone under the pointer. On the continent and world maps the land you've explored is drawn in, as on the zone maps (the game's
-- own pictures), the rest is dimmed, and zones have their names; your route and where you've been go across all of it. Both can be switched off.
-- Information only: it changes which map is shown, nothing else.

local _, NS = ...
local Cn = NS.Module("Continent")
NS.Continent = Cn

local CONTINENT, WORLD, ZONE = 2, 1, 3
local function List(v) return type(v) == "table" and v or {} end
local function Num(v) return type(v) == "number" and v or nil end
local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, 8) end
end
local function Info(m) local i = C_Map and Call(C_Map.GetMapInfo, m); return type(i) == "table" and i or nil end

function Cn.WheelOn() return not (NS.db and NS.db.mapWheel == false) end
function Cn.ExploredOn() return not (NS.db and NS.db.mapExplored == false) end

---------------------------------------------------------------------------
-- The pieces: every explored bit of every zone, where it lies on the bigger map (0 to 1)
---------------------------------------------------------------------------
local function Edge(n) -- a picture is as wide as the next power of two
  local f = 16
  while f < n do f = f * 2 end
  return f
end
-- one zone's, on its own map (0 to 1): { { file, x, y, w, h, right, bottom }, ... }
function Cn.ZonePieces(zone)
  local out = {}
  local X = C_MapExplorationInfo
  local layer = C_Map and List(Call(C_Map.GetMapArtLayers, zone))[1]
  local lw, lh = layer and Num(layer.layerWidth), layer and Num(layer.layerHeight)
  if not (X and X.GetExploredMapTextures and lw and lh and lw > 0 and lh > 0) then return out end
  for _, e in ipairs(List(Call(X.GetExploredMapTextures, zone))) do
    local tw, th = Num(e.textureWidth) or 0, Num(e.textureHeight) or 0
    local wide, tall = math.ceil(tw / 256), math.ceil(th / 256)
    for j = 1, tall do
      for k = 1, wide do
        local f = List(e.fileDataIDs)[(j - 1) * wide + k]
        if f then
          local pw = k < wide and 256 or (tw % 256 == 0 and 256 or tw % 256)
          local ph = j < tall and 256 or (th % 256 == 0 and 256 or th % 256)
          out[#out + 1] = { f, ((e.offsetX or 0) + 256 * (k - 1)) / lw, ((e.offsetY or 0) + 256 * (j - 1)) / lh, pw / lw, ph / lh, pw / Edge(pw), ph / Edge(ph) }
        end
      end
    end
  end
  return out
end
-- -> pieces { file, x, y, w, h, right, bottom }, names { name, x, y, w }
function Cn.Pieces(mapID)
  local out, names = {}, {}
  local M, X = C_Map, C_MapExplorationInfo
  if not (M and M.GetMapChildrenInfo and M.GetMapRectOnMap and X and X.GetExploredMapTextures) then return out, names end
  local kids = Call(M.GetMapChildrenInfo, mapID, nil, true)
  for _, z in ipairs(List(kids)) do
    if z.mapType == ZONE and z.mapID ~= mapID then
      local x0, x1, y0, y1 = Call(M.GetMapRectOnMap, z.mapID, mapID)
      local layer = List(Call(M.GetMapArtLayers, z.mapID))[1]
      local lw, lh = layer and Num(layer.layerWidth), layer and Num(layer.layerHeight)
      if Num(x0) and Num(x1) and Num(y0) and Num(y1) and x1 > x0 and y1 > y0 and lw and lh and lw > 0 and lh > 0 then
        local any
        local zw, zh = x1 - x0, y1 - y0
        for _, p in ipairs(Cn.ZonePieces(z.mapID)) do
          any = true
          out[#out + 1] = { zone = z.mapID, p[1], x0 + p[2] * zw, y0 + p[3] * zh, p[4] * zw, p[5] * zh, p[6], p[7] }
        end
        local mid = List(_G.SunstoneZoneShapes)[z.mapID]
        local nx, ny = mid and mid[1] or 0.5, mid and mid[2] or 0.5
        names[#names + 1] = { z.name, x0 + (x1 - x0) * nx, y0 + (y1 - y0) * ny, x1 - x0, any, zone = z.mapID, box = { x0, y0, x1, y1 } }
      end
    end
  end
  return out, names
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local sheet, tex, labels, shade = nil, {}, {}, nil
local masks = {} -- a zone's outline (media, zones): its pictures are cut to it
local function Mask(zone, box, w, h)
  if not (sheet.CreateMaskTexture and List(_G.SunstoneZoneShapes)[zone]) then return nil end
  local m = masks[zone]
  if not m then
    local ok, made = pcall(sheet.CreateMaskTexture, sheet)
    if not ok or not made then return nil end
    m = made
    m:SetTexture(NS.MEDIA .. "zones\\z" .. zone .. ".png", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    masks[zone] = m
  end
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", sheet, "TOPLEFT", box[1] * w, -box[2] * h)
  m:SetSize((box[3] - box[1]) * w, (box[4] - box[2]) * h)
  return m
end
local function Hide()
  if sheet then sheet:Hide() end
end
function Cn.Shows(mapID)
  local i = Info(mapID)
  return i ~= nil and (i.mapType == CONTINENT or i.mapType == WORLD)
end
function Cn.Draw()
  local map = WorldMapFrame
  if not (map and map:IsShown() and map.GetMapID) then return end
  local mapID = map:GetMapID()
  if not (mapID and Cn.ExploredOn() and Cn.Shows(mapID)) then Hide() return end
  local scroll = map.ScrollContainer
  local canvas = scroll and scroll.Child
  if not canvas then return end
  local pieces, names = Cn.Pieces(mapID)
  if #pieces == 0 and #names == 0 then Hide() return end
  if not sheet then
    sheet = CreateFrame("Frame", nil, canvas)
    sheet:SetAllPoints(canvas)
    if sheet.SetClipsChildren then sheet:SetClipsChildren(true) end
    shade = sheet:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0.16, 0.10, 0.04, 0.38)
  end
  local lvl = NS.MapView and NS.MapView.GroundLevel and NS.MapView.GroundLevel()
  if type(lvl) == "number" then sheet:SetFrameLevel(math.min(8998, lvl)) end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if type(w) ~= "number" or w <= 0 then return end
  local cut = {}
  for _, n in ipairs(names) do if n[5] then cut[n.zone] = Mask(n.zone, n.box, w, h) end end
  for k, p in ipairs(pieces) do
    local t = tex[k]
    if not t then
      t = sheet:CreateTexture(nil, "ARTWORK")
      tex[k] = t
    end
    t:SetTexture(p[1], nil, nil, "TRILINEAR")
    t:SetTexCoord(0, p[6], 0, p[7])
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", sheet, "TOPLEFT", p[2] * w, -p[3] * h)
    t:SetSize(p[4] * w, p[5] * h)
    local m = cut[p.zone]
    if t.cut ~= m then
      if t.cut then pcall(t.RemoveMaskTexture, t, t.cut) end
      if m then pcall(t.AddMaskTexture, t, m) end
      t.cut = m
    end
    t:Show()
  end
  for k = #pieces + 1, #tex do tex[k]:Hide() end
  local zoomed = Info(mapID).mapType == CONTINENT
  local n = 0
  for _, l in ipairs(zoomed and names or {}) do
    n = n + 1
    local f = labels[n]
    if not f then
      f = sheet:CreateFontString(nil, "OVERLAY")
      if not pcall(f.SetFont, f, "Fonts\\MORPHEUS.TTF", 11, "OUTLINE") and f.SetFontObject then f:SetFontObject("GameFontNormalSmall") end
      f:SetJustifyH("CENTER")
      labels[n] = f
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", sheet, "TOPLEFT", l[2] * w, -l[3] * h)
    f:SetWidth(math.max(54, l[4] * w * 0.8))
    f:SetText(l[1] or "")
    if l[5] then f:SetTextColor(1, 0.93, 0.74, 0.95) else f:SetTextColor(0.78, 0.68, 0.52, 0.75) end
    f:Show()
  end
  for k = n + 1, #labels do labels[k]:Hide() end
  sheet:Show()
end

---------------------------------------------------------------------------
-- The wheel
---------------------------------------------------------------------------
local lastTurn = 0
-- which map a turn of the wheel leads to (nil: none). x, y: the pointer, 0 to 1
function Cn.Next(mapID, delta, x, y)
  local i = Info(mapID)
  if not i then return nil end
  if delta < 0 then
    local up = Num(i.parentMapID)
    local p = up and up > 0 and Info(up)
    if p and (p.mapType or 0) >= WORLD then return up end
    return nil
  end
  if (i.mapType == CONTINENT or i.mapType == WORLD) and x and y and C_Map.GetMapInfoAtPosition then
    local z = Call(C_Map.GetMapInfoAtPosition, mapID, x, y)
    local id = type(z) == "table" and Num(z.mapID)
    if not id or id == mapID then return nil end
    -- from the world: the continent first, then the zone
    if i.mapType == WORLD then
      local step, guard = z, 0
      while step and step.mapType and step.mapType > CONTINENT and guard < 5 do
        step, guard = step.parentMapID and Info(step.parentMapID), guard + 1
      end
      return step and step.mapType == CONTINENT and step.mapID or id
    end
    return id
  end
end
function Cn.Wheel(container, delta)
  if NS.Atlas and NS.Atlas.On() and NS.Atlas.Rect(WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or 0) then return end -- (the smooth map has it)
  if not Cn.WheelOn() or (InCombatLockdown and InCombatLockdown()) then return end
  if NS.IsAddOnLoaded and NS.IsAddOnLoaded("MapUtils") then return end -- it does this itself
  local map = WorldMapFrame
  local now = GetTime()
  if not (map and map.GetMapID and map.SetMapID) or now - lastTurn < 0.22 then return end
  -- zoomed into a map (where the game allows that): its own zoom first
  local scale, least = Call(container.GetCanvasScale, container), Call(container.GetScaleForMinZoom, container)
  if delta < 0 and Num(scale) and Num(least) and scale > least * 1.02 then return end
  local x, y = Call(container.GetNormalizedCursorPosition, container)
  local to = Cn.Next(map:GetMapID(), delta, Num(x), Num(y))
  if to and to ~= map:GetMapID() then
    lastTurn = now
    pcall(map.SetMapID, map, to)
  end
end

function Cn:Init()
  local map = WorldMapFrame
  if not map then return end
  local container = map.ScrollContainer
  if container and container.HookScript then
    pcall(container.EnableMouseWheel, container, true)
    if not pcall(container.HookScript, container, "OnMouseWheel", function(self, delta) NS.Safe("map wheel", Cn.Wheel, self, delta) end) then
      pcall(container.SetScript, container, "OnMouseWheel", function(self, delta) NS.Safe("map wheel", Cn.Wheel, self, delta) end)
    end
  end
  local function Again() NS.Safe("explored land", Cn.Draw) end
  map:HookScript("OnShow", Again)
  if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", Again) end
  NS.On("MAP_EXPLORATION_UPDATED", Again)
  NS.Setting("On the world map", "Wheel: zone, continent, world", "The mouse wheel steps out to the continent and the world, and in to the zone under the pointer (not in combat).",
    Cn.WheelOn, function(v) NS.db.mapWheel = v and true or false end)
  NS.Setting("On the world map", "Explored land on big maps", "The continent and world maps show what you've explored, dim the rest and name the zones.", Cn.ExploredOn,
    function(v) NS.db.mapExplored = v and true or false; Cn.Draw() end)
end
