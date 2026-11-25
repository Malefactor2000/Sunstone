-- Sunstone: travel map.
-- Lets you keep the big world map open while you travel: one opacity while standing still, a lower one
-- while moving (so you can see where you're going through it), a size setting, and the quest route
-- drawn on the map as a line from you through every stop. "/sun map" opens the settings.
-- If MapUtils is installed it already fades the map while moving; Sunstone then sets MapUtils'
-- own fade setting instead of fighting it, and does the size and the route line itself.

local _, NS = ...
local V = NS.Module("MapView")
NS.MapView = V

local DEFAULTS = { on = false, alpha = 1, moving = 0.5, scale = 1, line = true }

function V.Cfg()
  local c = NS.db.map
  if type(c) ~= "table" then c = {}; NS.db.map = c end
  for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
  return c
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function MapUtilsLoaded()
  local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  return fn and fn("MapUtils") and type(MAUTTAB) == "table"
end

---------------------------------------------------------------------------
-- Opacity and size
---------------------------------------------------------------------------
local function Apply()
  local map = WorldMapFrame
  if not map then return end
  local c = V.Cfg()
  -- Off = the world map is left completely alone (only put back once if we changed it).
  if not InCombatLockdown() then
    if c.on and c.scale ~= 1 then
      pcall(map.SetScale, map, c.scale)
      V.scaled = true
    elseif V.scaled then
      pcall(map.SetScale, map, 1)
      V.scaled = nil
    end
  end
  if MapUtilsLoaded() then
    if c.on then
      MAUTTAB["WORLDMAPFADE"] = true
      MAUTTAB["WORLDMAPFADEOPACITY"] = math.floor(c.moving * 100 + 0.5)
    end
  elseif c.on then
    -- the game's own "fade map while moving" would fight our opacity: pause it while ours is on
    if NS.GetCVar("mapFade") == "1" then
      NS.db.mapFadeWas = "1"
      pcall(NS.SetCVar, "mapFade", "0")
    end
    V.faded = true
  elseif V.faded or NS.db.mapFadeWas then
    pcall(map.SetAlpha, map, 1)
    V.faded = nil
    if NS.db.mapFadeWas then
      pcall(NS.SetCVar, "mapFade", NS.db.mapFadeWas)
      NS.db.mapFadeWas = nil
    end
  end
end
V.Apply = Apply

local fader = CreateFrame("Frame")
fader:Hide()
local acc, lineAcc = 0, 0
fader:SetScript("OnUpdate", function(_, elapsed)
  acc, lineAcc = acc + elapsed, lineAcc + elapsed
  if acc < 0.1 then return end
  acc = 0
  local map, c = WorldMapFrame, V.Cfg()
  if c.on and not MapUtilsLoaded() then
    local moving = IsPlayerMoving and IsPlayerMoving()
    local target = moving and c.moving or c.alpha
    local cur = map:GetAlpha()
    if math.abs(cur - target) > 0.02 then map:SetAlpha(cur + (target - cur) * 0.5) end
  end
  if lineAcc >= 1 then
    lineAcc = 0
    NS.Safe("map line", V.DrawRoute)
  end
end)

---------------------------------------------------------------------------
-- The route as a line on the world map
---------------------------------------------------------------------------
-- What the route draws: "next" (the way to the next stop), "all" (the whole round) or "off"
V.LINES = { "all", "next", "off" }
V.LINE_NAME = { next = "next stop", all = "whole route", off = "off" }
function V.LineMode()
  local c = V.Cfg()
  if c.lineMode ~= "next" and c.lineMode ~= "all" and c.lineMode ~= "off" then c.lineMode = c.line == false and "off" or "all" end
  return c.lineMode
end
function V.SetLineMode(m)
  V.Cfg().lineMode = m
  V.Cfg().line = m ~= "off"
  V.DrawRoute()
  if V.Buttons then V.Buttons() end
  if NS.Atlas then NS.Atlas.Redraw() end
  if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
end
function V.NextLineMode()
  local now = V.LineMode()
  for k, m in ipairs(V.LINES) do if m == now then V.SetLineMode(V.LINES[k % #V.LINES + 1]) return end end
end

-- A sheet on the map for lines: over the explored ground (which would hide them), under the icons -> sheet, width, height, zoom
local sheet
function V.GroundLevel() -- just above the explored ground, below the icons
  local map = WorldMapFrame
  local canvas = map and map.ScrollContainer and map.ScrollContainer.Child
  if not canvas then return nil end
  local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
  if type(mgr) == "table" and mgr.GetValidFrameLevel then
    local ok, v = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
    if ok and type(v) == "number" then return v + 1 end
  end
  local base = canvas.GetFrameLevel and canvas:GetFrameLevel()
  return type(base) == "number" and base + 400 or nil
end
function V.Layer()
  local map = WorldMapFrame
  local scroll = map and map.ScrollContainer
  local canvas = scroll and scroll.Child
  if not (canvas and canvas.CreateLine) then return nil end
  if not sheet then
    sheet = CreateFrame("Frame", nil, canvas)
    sheet:SetAllPoints(canvas)
  end
  local lvl = V.GroundLevel()
  if lvl then sheet:SetFrameLevel(math.min(9000, lvl + 1)) end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if type(w) ~= "number" or w <= 0 then return nil end
  local zoom = scroll.GetCanvasScale and scroll:GetCanvasScale() or 1
  return sheet, w, h, type(zoom) == "number" and zoom or 1
end

-- The points the route's line goes through (zone crossings on the way included): { m, x, y (0-100), leg }
function V.RouteStops(all)
  local out = {}
  local hbd = NS.HBD()
  local stops = V.trip and { V.trip } or NS.Route and NS.Route.stops or {}
  local prev
  local px, py, pm
  if hbd then px, py, pm = hbd:GetPlayerZonePosition() end
  if px and pm then
    prev = { m = pm, x = px * 100, y = py * 100 }
    prev.wx, prev.wy, prev.inst = hbd:GetPlayerWorldPosition()
  end
  for i, s in ipairs(stops) do
    if i > 1 and not all then break end
    local cur = { m = s.m, x = s.x * 100, y = s.y * 100, wx = s.wx, wy = s.wy, inst = s.inst }
    if prev and NS.Travel and NS.Travel.Hops then
      local ok, hops = pcall(NS.Travel.Hops, prev, cur)
      for _, h in ipairs(ok and hops or {}) do out[#out + 1] = { m = h.m, x = h.x, y = h.y, leg = i } end
    end
    out[#out + 1] = { m = cur.m, x = cur.x, y = cur.y, leg = i }
    prev = cur
  end
  return out
end

local lines = {}
function V.DrawRoute()
  for _, l in ipairs(lines) do l:Hide() end
  local map, hbd = WorldMapFrame, NS.HBD()
  local mode = V.LineMode()
  if not ((mode ~= "off" or V.trip) and map and map:IsShown() and hbd) then return end
  if not map.GetMapID then return end
  local layer, lw, lh, lz = V.Layer()
  if not layer then return end
  local mapID = map:GetMapID()
  if not mapID then return end
  -- a trip somewhere (a dungeon's door) instead of the quest route, until you get there or re-plan
  local stops = V.trip and { V.trip } or NS.Route and NS.Route.stops or {}
  if #stops == 0 then return end
  -- you, then each stop; a leg into another zone goes through the zone crossings on the way (not over the mountains)
  local pts = {}
  local function Add(p, leg)
    local x, y = hbd:TranslateZoneCoordinates(p.x / 100, p.y / 100, p.m, mapID, true)
    if x then pts[#pts + 1] = { x, y, leg } end
  end
  local prev
  local px, py, pm = hbd:GetPlayerZonePosition()
  if px and pm then
    prev = { m = pm, x = px * 100, y = py * 100 }
    prev.wx, prev.wy, prev.inst = hbd:GetPlayerWorldPosition()
    Add(prev, 0)
  end
  for i, s in ipairs(stops) do
    if i > 1 and mode ~= "all" then break end -- (the rest of the round only when asked for)
    local cur = { m = s.m, x = s.x * 100, y = s.y * 100, wx = s.wx, wy = s.wy, inst = s.inst }
    if prev and NS.Travel and NS.Travel.Hops then
      local ok, hops = pcall(NS.Travel.Hops, prev, cur)
      for _, h in ipairs(ok and hops or {}) do Add(h, i) end
    end
    Add(cur, i)
    prev = cur
  end
  local w, h, zoom = lw, lh, lz
  local legs = 0
  for _, p in ipairs(pts) do if p[3] == 1 then legs = legs + 1 end end
  local dots = legs <= 1 and not V.trip and NS.Trail and NS.Trail.Path and NS.Trail.Path() ~= nil -- the trail's dots already show the way to the next stop
  local n = 0
  for pass = 1, 2 do -- a dark edge under the whole way, then the lines
  for i = 2, #pts do
    n = n + 1
    local l = lines[n]
    if not l then
      l = layer:CreateLine(nil, "OVERLAY")
      lines[n] = l
    end
    if l.SetDrawLayer then l:SetDrawLayer("OVERLAY", pass) end
    l:SetThickness((pass == 1 and 6 or 3.5) / math.max(zoom, 0.1))
    -- the way to the next stop (however many crossings it takes) in gold, the rest of the round in light blue
    if pass == 1 then l:SetColorTexture(0.03, 0.03, 0.04, 0.55)
    elseif (pts[i][3] or 1) <= 1 then l:SetColorTexture(1, 0.90, 0.52, 0.95) else l:SetColorTexture(0.45, 0.80, 1, 0.9) end
    l:SetStartPoint("TOPLEFT", layer, pts[i - 1][1] * w, -pts[i - 1][2] * h)
    l:SetEndPoint("TOPLEFT", layer, pts[i][1] * w, -pts[i][2] * h)
    l:SetShown(not (dots and (pts[i][3] or 1) <= 1))
  end
  end
end

---------------------------------------------------------------------------
-- Settings panel: - / + buttons (no templates that differ between clients)
---------------------------------------------------------------------------
local panel
local ROWS = {
  { key = "alpha", label = "Map opacity standing still", step = 0.1, lo = 0.2, hi = 1 },
  { key = "moving", label = "Map opacity while moving", step = 0.1, lo = 0.1, hi = 1 },
  { key = "scale", label = "Map size", step = 0.1, lo = 0.5, hi = 1.5 },
}

local function Refresh()
  if not panel then return end
  local c = V.Cfg()
  for _, r in ipairs(ROWS) do
    local disabled = r.key == "alpha" and MapUtilsLoaded()
    r.value:SetText(disabled and "MapUtils" or string.format("%d%%", c[r.key] * 100 + 0.5))
  end
  panel.lineBtn:SetText("Route: " .. V.LINE_NAME[V.LineMode()])
  panel.onBtn:SetText(c.on and "Travel map: on" or "Travel map: off")
  panel.text:SetText(MapUtilsLoaded() and "|cff8f7d68MapUtils is installed: it does the fading, Sunstone sets how faint.|r" or
    "|cff8f7d68Open the world map (M) and walk: it fades so you can see where you're going.|r")
end

local function Change(key, delta)
  local c = V.Cfg()
  for _, r in ipairs(ROWS) do
    if r.key == key then c[key] = Clamp(math.floor((c[key] + delta) * 10 + 0.5) / 10, r.lo, r.hi) end
  end
  c.on = true
  Apply()
  Refresh()
end

function V.Show()
  if not panel then
    panel = NS.Panel("Map", 290, 168, "Sunstone · Travel map")
    panel.text:ClearAllPoints()
    panel.text:SetPoint("BOTTOMLEFT", 10, 38)
    panel.text:SetPoint("RIGHT", -10, 0)
    for i, r in ipairs(ROWS) do
      local y = -30 - (i - 1) * 24
      local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", 10, y - 4)
      fs:SetText(r.label)
      local plus = NS.Button(panel, "+", 22, function() Change(r.key, r.step) end)
      plus:SetPoint("TOPRIGHT", -10, y)
      r.value = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      r.value:SetPoint("RIGHT", plus, "LEFT", -6, 0)
      r.value:SetWidth(52)
      local minus = NS.Button(panel, "-", 22, function() Change(r.key, -r.step) end)
      minus:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    end
    panel.lineBtn = NS.Button(panel, "Route line", 120, function()
      V.NextLineMode()
      Refresh()
    end)
    panel.lineBtn:SetPoint("BOTTOMLEFT", 8, 8)
    panel.onBtn = NS.Button(panel, "Travel map", 140, function()
      local c = V.Cfg()
      c.on = not c.on
      Apply()
      Refresh()
    end)
    panel.onBtn:SetPoint("BOTTOMRIGHT", -8, 8)
  end
  Refresh()
  panel:Show()
end

-- Two small buttons on the world map itself: what the route draws, and where you've been
local onMap
function V.ButtonsOn() return not (NS.db and NS.db.mapButtons == false) end
function V.Buttons()
  local map = WorldMapFrame
  local scroll = map and map.ScrollContainer
  if not scroll then return end
  if not onMap then
    if not (V.ButtonsOn() and map:IsShown()) then return end
    onMap = CreateFrame("Frame", nil, map)
    onMap:SetSize(250, 22)
    onMap:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -10, 8)
    local lvl = map.GetFrameLevel and map:GetFrameLevel()
    if type(lvl) == "number" then onMap:SetFrameLevel(math.min(9500, lvl + 4000)) end
    onMap.been = NS.Button(onMap, "", 118, function() if NS.Track then NS.Track.Set(not NS.Track.On()) end end)
    onMap.been:SetPoint("RIGHT", 0, 0)
    onMap.route = NS.Button(onMap, "", 124, V.NextLineMode)
    onMap.route:SetPoint("RIGHT", onMap.been, "LEFT", -5, 0)
  end
  onMap:SetShown(V.ButtonsOn())
  onMap.route:SetText("Route: " .. V.LINE_NAME[V.LineMode()])
  onMap.route:SetActive(V.LineMode() ~= "off")
  onMap.route:SetShown(NS.cdb.route.enabled == true or V.trip ~= nil)
  local been = NS.Track and NS.Track.On()
  onMap.been:SetText(been and "Where I've been: on" or "Where I've been: off")
  onMap.been:SetActive(been)
end

function V:Init()
  local map = WorldMapFrame
  if not map then return end
  V.Cfg()
  NS.Setting("On the world map", "The whole route", "Lines through every stop, in the order you'll go: gold to the next one, light blue after that. Off: just the next stop.",
    function() return V.LineMode() == "all" end, function(v) V.SetLineMode(v and "all" or "next") end)
  NS.Setting("On the world map", "Buttons on the map", "The two small buttons at its bottom right: the route, and where you've been.", V.ButtonsOn, function(v) NS.db.mapButtons = v and true or false; V.Buttons() end)
  map:HookScript("OnShow", function() Apply(); fader:Show(); NS.Safe("map line", V.DrawRoute); NS.Safe("map buttons", V.Buttons) end)
  map:HookScript("OnHide", function() fader:Hide() end)
  if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", function() NS.Safe("map line", V.DrawRoute) end) end
  NS.On("PLAYER_REGEN_ENABLED", Apply) -- size changes wait until combat ends
  if map:IsShown() then fader:Show() end
end

NS.Command("map", "- travel map: see-through world map while moving, its size, the route drawn on it", function(rest)
  rest = (rest or ""):lower()
  local c = V.Cfg()
  local key, num = rest:match("^(%a+)%s+(%d+)")
  local field = ({ opacity = "alpha", alpha = "alpha", moving = "moving", size = "scale", scale = "scale" })[key or ""]
  if field and tonumber(num) then
    local row
    for _, r in ipairs(ROWS) do if r.key == field then row = r end end
    c[field] = Clamp(tonumber(num) / 100, row.lo, row.hi)
    c.on = true
    Apply()
    NS.Print(string.format("%s set to %d%%.", row.label, c[field] * 100 + 0.5))
  elseif rest:match("^line") then
    local m = ({ ["line on"] = "all", ["line all"] = "all", ["line next"] = "next", ["line off"] = "off" })[rest]
    if m then V.SetLineMode(m) else V.NextLineMode() end
    NS.Print("the route on the map: " .. V.LINE_NAME[V.LineMode()] .. ".")
  elseif rest == "off" then
    c.on = false
    Apply()
    NS.Print("travel map off (normal map).")
  else
    V.Show()
  end
end)
