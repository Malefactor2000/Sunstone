-- Sunstone: its own arrow and waypoints. The arrow points along the trail (Trail.lua) when there is one, so it leads you
-- round the hill instead of at it, and says how far is left to walk and about how long. It shows the quest route's next
-- stop, or a place you picked (Go buttons, /sun go, /sun way), which comes first until you get there or right-click it.
-- "/sun arrow tomtom" hands the pointing to TomTom instead, for those who prefer theirs.
-- Information only: it points. It never moves the character.

local _, NS = ...
local Ar = NS.Module("Arrow")
NS.Arrow = Ar
local C = NS.C

local PI, TWO_PI = math.pi, math.pi * 2
local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min
local atan2 = math.atan2
local REF = "SunstoneArrow"
local AHEAD = 35          -- yards along the trail the arrow aims at
local ARRIVED = 9         -- yards
local TICK = 0.03

local frame, worldPin, miniPin
local tt, ttKey           -- TomTom's waypoint, in TomTom mode

function Ar.Opts()
  local db = NS.db
  if type(db) ~= "table" then return { mode = "own" } end
  if type(db.arrow) ~= "table" then db.arrow = { mode = "own" } end
  return db.arrow
end

function Ar.Mode()
  return TomTom and Ar.Opts().mode == "tomtom" and "tomtom" or "own"
end

-- What the arrow points at: your body while you're a ghost, then a place you picked, then the route's next stop
function Ar.Current()
  if Ar.hold then return nil end
  if Ar.route and Ar.route.body then return Ar.route end
  return Ar.manual or Ar.route
end
function Ar.Picked() return Ar.manual ~= nil and Ar.Current() == Ar.manual end

local function Key(t)
  return t and string.format("%d:%.4f,%.4f:%s:%s", t.m, t.x, t.y, t.title or "", t.hidden and "h" or "") or nil
end

---------------------------------------------------------------------------
-- Setting and clearing
---------------------------------------------------------------------------
local function TomTomSync()
  local t = Ar.Mode() == "tomtom" and Ar.Current() or nil
  local key = Key(t)
  if key and key == ttKey and tt and (not TomTom.IsValidWaypoint or TomTom:IsValidWaypoint(tt)) then return end
  if tt and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tt) end
  tt, ttKey = nil, nil
  if not t then return end
  tt = TomTom:AddWaypoint(t.m, t.x, t.y, { title = "Sunstone: " .. (t.title or "?"), persistent = false, minimap = true, world = true,
                                           crazy = not t.hidden, cleardistance = 0, silent = true, from = "Sunstone" })
  ttKey = key
end

local function Pin(size)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(size, size)
  f.t = f:CreateTexture(nil, "OVERLAY")
  f.t:SetAllPoints()
  f.t:SetTexture(NS.MEDIA .. "dot.png")
  f.t:SetVertexColor(C.red[1], C.red[2], C.red[3], 1)
  f.i = f:CreateTexture(nil, "OVERLAY", nil, 1)
  f.i:SetPoint("TOPLEFT", size * 0.25, -size * 0.25)
  f.i:SetPoint("BOTTOMRIGHT", -size * 0.25, size * 0.25)
  f.i:SetTexture(NS.MEDIA .. "dot.png")
  f.i:SetVertexColor(1, 0.85, 0.4, 1)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self)
    local t = Ar.Current()
    if not t then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(t.title or "Sunstone", C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine(Ar.Picked() and "The place you picked. /sun way clear removes it." or "Your route's next stop.", C.dim[1], C.dim[2], C.dim[3], true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- A pin on the minimap (it stays on the rim while you're far) and, for a place you picked, on the world map. The
-- route's stops have their own numbers there.
local pinKey
local function DrawPins()
  local pins = NS.Pins()
  if not pins then return end
  local t = Ar.Mode() == "own" and Ar.Current() or nil
  local key = t and (Key(t) .. (Ar.Picked() and "m" or "r")) or nil
  if key == pinKey then return end
  pinKey = key
  if pins.RemoveAllWorldMapIcons then pcall(pins.RemoveAllWorldMapIcons, pins, REF) end
  if pins.RemoveAllMinimapIcons then pcall(pins.RemoveAllMinimapIcons, pins, REF) end
  if not t then return end
  miniPin = miniPin or Pin(12)
  local hbd = NS.HBD()
  local wx, wy, wi
  if hbd then wx, wy, wi = hbd:GetWorldCoordinatesFromZone(t.x, t.y, t.m) end
  miniPin:Hide()
  if wx and pins.AddMinimapIconWorld then pins:AddMinimapIconWorld(REF, miniPin, wi, wx, wy, true) else pins:AddMinimapIconMap(REF, miniPin, t.m, t.x, t.y, true, true) end
  if Ar.Picked() then
    worldPin = worldPin or Pin(18)
    pins:AddWorldMapIconMap(REF, worldPin, t.m, t.x, t.y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
  end
end

local function Changed()
  NS.Safe("arrow", TomTomSync)
  NS.Safe("arrow", DrawPins)
  Ar.hop, Ar.hopAt = nil, nil
  NS.Safe("arrow", Ar.Update, true)
end
Ar.Changed = Changed

-- The route's next stop (nil = none). hidden: the route is on but its arrow is switched off.
function Ar.SetRoute(t)
  local same = Key(t) == Key(Ar.route)
  Ar.route = t
  if not same then Changed() end
end

-- A ghost whose body can't be placed: no arrow at all rather than one pointing at a quest.
function Ar.Hold(on)
  on = on and true or nil
  if Ar.hold ~= on then
    Ar.hold = on
    Changed()
  end
end

-- A place you picked: it comes before the route until you arrive or clear it.
function Ar.Go(m, x, y, title)
  if type(m) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return false end
  Ar.manual = { m = m, x = x, y = y, title = NS.Clean(title or "Your waypoint", 80) }
  Changed()
  return true
end

function Ar.Clear()
  if not Ar.manual then return false end
  Ar.manual = nil
  if NS.MapView then NS.MapView.trip = nil end
  Changed()
  return true
end

---------------------------------------------------------------------------
-- Where to point
---------------------------------------------------------------------------
-- A place in another zone: aim at the next crossing on the way there (the route's stops come with theirs worked out).
local function Aim(t)
  if not Ar.Picked() then return t end
  local T = NS.Travel
  local here = T and T.Here and T.Here()
  if not (here and T.NextHop) or here.m == t.m then return t end
  if Ar.hopAt ~= here.m then
    Ar.hopAt = here.m
    local hbd = NS.HBD()
    local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(t.x, t.y, t.m)
    local ok, hop
    if wx then ok, hop = pcall(T.NextHop, here, { m = t.m, x = t.x * 100, y = t.y * 100, wx = wx, wy = wy, inst = inst }) end
    Ar.hop = ok and hop and { m = hop.m, x = hop.x / 100, y = hop.y / 100, title = hop.label .. ", then " .. (t.title or "?") } or nil
  end
  return Ar.hop or t
end

-- What the trail is heading for too: m, x, y, title
function Ar.Target()
  local t = Ar.Current()
  if not t then return nil end
  local a = Aim(t)
  return a.m, a.x, a.y, a.title
end

local function Plain(v)
  return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v or nil
end

-- -> { angle = radians to turn the arrow (0 = straight ahead), dist, secs, title }, or nil and why not
function Ar.Read()
  local m, x, y, title = Ar.Target()
  local hbd = NS.HBD()
  if not m or not hbd then return nil, "none" end
  local px, py, pinst = hbd:GetPlayerWorldPosition()
  local tx, ty, tinst = hbd:GetWorldCoordinatesFromZone(x, y, m)
  if not px or not tx then return nil, "unknown", title end
  if pinst ~= tinst then return nil, "elsewhere", title end
  local straight = sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
  local dist, ax, ay = straight, tx, ty
  local Tr = NS.Trail
  if Tr and Tr.Ahead and straight > AHEAD * 0.7 then
    local qx, qy, left = Tr.Ahead(px, py, AHEAD, tx, ty)
    if qx then ax, ay, dist = qx, qy, max(left, straight) end
  end
  -- HereBeDragons' x runs west and y runs north; facing 0 is north and turns to the left as it grows
  local facing = GetPlayerFacing and Plain(GetPlayerFacing())
  local angle
  if facing then
    angle = atan2(ax - px, ay - py) - facing
    angle = (angle + PI) % TWO_PI - PI
  end
  local speed = GetUnitSpeed and Plain(GetUnitSpeed("player")) or 0
  return { angle = angle, dist = dist, straight = straight, secs = speed > 0.5 and dist / speed or nil, title = title }
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function Build()
  frame = CreateFrame("Button", "SunstoneArrowFrame", UIParent)
  frame:SetSize(64, 58)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:RegisterForDrag("LeftButton")
  frame:RegisterForClicks("RightButtonUp")
  local o = Ar.Opts()
  frame:SetScale(type(o.scale) == "number" and max(0.5, min(2, o.scale)) or 1)
  local pos = o.pos
  if type(pos) == "table" and pos[1] then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else frame:SetPoint("TOP", UIParent, "TOP", 0, -110) end
  frame.shadow = frame:CreateTexture(nil, "ARTWORK")
  frame.shadow:SetSize(52, 52)
  frame.shadow:SetPoint("TOP", 1, -2)
  frame.shadow:SetTexture(NS.MEDIA .. "arrow.png")
  frame.shadow:SetVertexColor(0, 0, 0, 0.55)
  frame.arrow = frame:CreateTexture(nil, "OVERLAY")
  frame.arrow:SetSize(52, 52)
  frame.arrow:SetPoint("TOP", 0, 0)
  frame.arrow:SetTexture(NS.MEDIA .. "arrow.png")
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -52)
  frame.title:SetWidth(230)
  frame.title:SetTextColor(C.text[1], C.text[2], C.text[3])
  frame.title:SetShadowOffset(1, -1)
  frame.left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.left:SetPoint("TOP", frame.title, "BOTTOM", 0, -1)
  frame.left:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  frame.left:SetShadowOffset(1, -1)
  frame:SetScript("OnDragStart", function(self) if not Ar.Opts().locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    Ar.Opts().pos = { p, rp, x, y }
  end)
  frame:SetScript("OnMouseWheel", function(self, d)
    if not (IsControlKeyDown and IsControlKeyDown()) then return end
    local opts = Ar.Opts()
    opts.scale = max(0.5, min(2, (opts.scale or 1) + d * 0.1))
    self:SetScale(opts.scale)
  end)
  frame:SetScript("OnClick", function()
    if Ar.Picked() then
      Ar.Clear()
      NS.Print("that waypoint is cleared.")
    elseif NS.Route and NS.Route.SetArrowShown then
      NS.Route.SetArrowShown(false)
      NS.Print("arrow hidden; the route stays on the map and minimap. /sun arrow on brings it back.")
    end
  end)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(Ar.Picked() and "The place you picked" or "Your route's next stop", C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine("Drag to move, Ctrl + wheel for its size, right-click to " .. (Ar.Picked() and "clear it." or "hide it."), C.dim[1], C.dim[2], C.dim[3], true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local since = 0
  frame:SetScript("OnUpdate", function(_, dt)
    since = since + (type(dt) == "number" and dt or TICK)
    if since < TICK then return end
    since = 0
    NS.Safe("arrow", Ar.Update)
  end)
  Ar.frame = frame
end

-- gold when you're on course, red clay when it's behind you
local function Tint(a)
  local k = min(1, abs(a) / 2.2)
  return 0.98 - 0.22 * k, 0.80 - 0.48 * k, 0.30 - 0.08 * k
end

local lastTitle, lastLeft
local function Text(title, left)
  if title ~= lastTitle then frame.title:SetText(title); lastTitle = title end
  if left ~= lastLeft then frame.left:SetText(left); lastLeft = left end
end

function Ar.Update()
  local t = Ar.Current()
  local show = t and Ar.Mode() == "own" and not (t.hidden and not Ar.Picked())
  if not show then
    if frame then frame:Hide() end
    return
  end
  if not frame then Build() end
  frame:Show()
  local r, why, title = Ar.Read()
  if not r then
    frame.arrow:Hide(); frame.shadow:Hide()
    Text(title or t.title or "", why == "elsewhere" and "on another continent" or "can't place you here")
    return
  end
  if Ar.Picked() and r.straight < ARRIVED and not Ar.hop then
    local name = Ar.manual.title
    Ar.Clear()
    NS.Print("you're there: " .. (name or "your waypoint") .. ".")
    return
  end
  if r.angle then
    local a = r.angle
    local cr, cg, cb = Tint(a)
    if r.straight < ARRIVED then a, cr, cg, cb = PI, 0.55, 0.75, 0.40 end -- on it: points down
    frame.arrow:SetRotation(a)
    frame.shadow:SetRotation(a)
    frame.arrow:SetVertexColor(cr, cg, cb, 1)
    frame.arrow:Show(); frame.shadow:Show()
  else
    frame.arrow:Hide(); frame.shadow:Hide()
  end
  local left = floor(r.dist + 0.5) .. " yards"
  if r.secs and r.secs < 3600 then
    local s = floor(r.secs + 0.5)
    left = left .. string.format("  %d:%02d", floor(s / 60), s % 60)
  end
  Text(r.title or "", left)
end

---------------------------------------------------------------------------
-- /sun way, /sun arrow
---------------------------------------------------------------------------
local function ZoneByName(name)
  local hbd = NS.HBD()
  if not (hbd and name) then return nil end
  name = name:lower()
  local part
  for m, d in pairs(hbd.mapData or {}) do
    local n = type(d) == "table" and d.mapType == 3 and type(d.name) == "string" and d.name:lower()
    if n == name then return m end
    if n and n:find(name, 1, true) == 1 then part = part or m end
  end
  return part
end

-- "45.2 61.3 [title]", "45.2, 61.3", "Durotar 45.2 61.3 [title]" -> m, x, y, title
function Ar.Parse(text)
  text = (text or ""):gsub("(%d)[,;]%s*", "%1 "):gsub("^%s+", ""):gsub("%s+$", "")
  local id, after = text:match("^#(%d+)%s+(.*)$") -- "#1413 45.2 61.3"
  local zone, x, y, title = (after or text):match("^(.-)%s*(%d+%.?%d*)%s+(%d+%.?%d*)%s*(.*)$")
  zone = id or zone
  x, y = tonumber(x), tonumber(y)
  if not x or not y or x > 100 or y > 100 then return nil, "usage: /sun way 45.2 61.3 [what's there], or /sun way Durotar 45.2 61.3" end
  local m
  if zone and zone ~= "" then
    m = tonumber(zone) or ZoneByName(zone)
    if not m then return nil, "no zone called \"" .. NS.Clean(zone, 40) .. "\"." end
  else
    local here = NS.Travel and NS.Travel.Here and NS.Travel.Here()
    m = here and here.m or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not m then return nil, "can't tell which zone you're in: name it, as in /sun way Durotar 45 61." end
  end
  return m, x / 100, y / 100, title ~= "" and title or nil
end

function Ar.Way(rest)
  local low = (rest or ""):lower()
  if low == "clear" or low == "reset" or low == "off" then
    NS.Print(Ar.Clear() and "waypoint cleared." or "there's no waypoint of yours to clear.")
    return
  end
  local m, x, y, title = Ar.Parse(rest)
  if not m then NS.Print(x) return end
  local hbd = NS.HBD()
  local zone = hbd and hbd:GetLocalizedMap(m) or "?"
  Ar.Go(m, x, y, title or string.format("%s %.1f, %.1f", zone, x * 100, y * 100))
  NS.Print(string.format("arrow set to %s %.1f, %.1f%s.", zone, x * 100, y * 100, title and (" (" .. NS.Clean(title, 60) .. ")") or ""))
end

function Ar.SetMode(mode)
  Ar.Opts().mode = mode
  pinKey = "?"
  Changed()
end

NS.Command("way", "[zone] x y [name] - point the arrow there (clear: back to the route)", Ar.Way)
NS.Command("arrow", "[on|off|lock|unlock|reset|tomtom|own] - the arrow (off: the route stays on the map and minimap)", function(rest)
  rest = (rest or ""):lower()
  local o = Ar.Opts()
  if rest == "lock" or rest == "unlock" then
    o.locked = rest == "lock"
    NS.Print("arrow " .. (o.locked and "locked where it is." or "unlocked: drag it."))
  elseif rest == "reset" then
    o.pos, o.scale, o.locked = nil, nil, nil
    if frame then
      frame:ClearAllPoints()
      frame:SetPoint("TOP", UIParent, "TOP", 0, -110)
      frame:SetScale(1)
    end
    NS.Print("arrow back at the top, at its usual size.")
  elseif rest == "tomtom" then
    if not TomTom then NS.Print("TomTom isn't loaded.") return end
    Ar.SetMode("tomtom")
    NS.Print("TomTom's arrow points the way now. /sun arrow own brings Sunstone's back.")
  elseif rest == "own" then
    Ar.SetMode("own")
    NS.Print("Sunstone's own arrow points the way.")
  else
    local on = (rest == "on") or (rest ~= "off" and NS.cdb.route.arrow == false)
    NS.Route.SetArrowShown(on)
    NS.Print("route arrow " .. (on and "on." or "off: the route stays on the map and minimap."))
  end
end)

NS.Setting("The arrow", "Whose arrow", "Sunstone's own, or TomTom's when that's loaded.", function()
  return Ar.Mode() == "tomtom" and "TomTom" or "Sunstone"
end, function() Ar.SetMode(Ar.Mode() == "own" and TomTom and "tomtom" or "own") end)
NS.Setting("The arrow", "Show it for the route", "Off: the route stays on the map and minimap.", function() return NS.cdb.route.arrow ~= false end,
           function(v) NS.Route.SetArrowShown(v) end)
NS.Setting("The arrow", "Locked in place", "Unlocked, drag it anywhere; Ctrl + wheel over it changes its size.", function() return Ar.Opts().locked == true end,
           function(v) Ar.Opts().locked = v and true or nil end)

function Ar:Init()
  Ar.Opts()
  NS.On("PLAYER_ENTERING_WORLD", function()
    pinKey = "?"
    NS.Debounce("arrow", 2, Changed)
  end)
  -- /way too, unless TomTom already answers it
  C_Timer.After(3, function()
    if not TomTom and not SlashCmdList["TOMTOM_WAY"] then
      SLASH_SUNSTONEWAY1 = "/way"
      SlashCmdList["SUNSTONEWAY"] = function(msg) NS.Safe("/way", Ar.Way, msg) end
    end
  end)
end
