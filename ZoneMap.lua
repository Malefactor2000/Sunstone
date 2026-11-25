-- Sunstone: zone maps inside Sunstone's own window. The game's own map of a zone with all of its terrain on it (mountains, rivers, roads, also
-- where you haven't been: ZoneMapData.lua), numbered places, and you. A small one can stand in a page (a row with "zmap"), a big one opens over
-- the window (wheel: zoom, drag: move). Information only.

local _, NS = ...
local Z = NS.Module("ZoneMap")
NS.ZoneMap = Z
local C = NS.C

local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local MERGE = 0.016   -- closer than this (share of the map) and two places share a pin
local SIDE = 250
-- a pin's ring: the next step, one you're on, done, for later, a place something is done
local RING = { pick = { 0.98, 0.84, 0.20 }, hand = { 0.48, 0.78, 0.36 }, ["do"] = { 0.86, 0.46, 0.22 }, next = { 0.98, 0.80, 0.28 }, log = { 0.54, 0.75, 0.44 }, done = { 0.45, 0.43, 0.40 }, todo = { 0.79, 0.35, 0.28 }, spot = { 0.50, 0.75, 0.95 } }

local function Num(v, default) return type(v) == "number" and v or default end
local function List(v) return type(v) == "table" and v or {} end

---------------------------------------------------------------------------
-- A map's pictures
---------------------------------------------------------------------------
-- -> { w, h, tiles = { { file, x, y, width, height, right edge, bottom edge }, ... } } in the map's own pixels; nil = the game has no such map
local arts = {}
local function Edge(n) -- a piece's last column or row: the picture is as big as the next power of two
  local f = 32
  while f < n do f = f * 2 end
  return f
end
function Z.Art(m)
  if arts[m] ~= nil then return arts[m] or nil end
  local M = C_Map
  if not (M and M.GetMapArtLayers and M.GetMapArtLayerTextures) then return nil end
  local ok, layers = pcall(M.GetMapArtLayers, m)
  local L = ok and type(layers) == "table" and layers[1]
  local ok2, files = pcall(M.GetMapArtLayerTextures, m, 1)
  if not (type(L) == "table" and ok2 and type(files) == "table" and files[1] and Num(L.layerWidth, 0) > 0 and Num(L.tileWidth, 0) > 0) then
    arts[m] = false
    return nil
  end
  local art = { w = L.layerWidth, h = L.layerHeight, tiles = {} }
  local cols, rows = math.ceil(L.layerWidth / L.tileWidth), math.ceil(L.layerHeight / L.tileHeight)
  for r = 1, rows do
    for c = 1, cols do
      local f = files[(r - 1) * cols + c]
      if f then art.tiles[#art.tiles + 1] = { f, (c - 1) * L.tileWidth, (r - 1) * L.tileHeight, L.tileWidth, L.tileHeight, 1, 1, "BACKGROUND" } end
    end
  end
  local over = type(_G.SunstoneZoneMaps) == "table" and _G.SunstoneZoneMaps[m]
  for piece in (type(over) == "string" and over or ""):gmatch("[^;]+") do
    local w, h, x, y, list = piece:match("^(%d+),(%d+),(%d+),(%d+),([%d:]+)$")
    w, h, x, y = tonumber(w), tonumber(h), tonumber(x), tonumber(y)
    if w then
      local pc, pr, k = math.ceil(w / 256), math.ceil(h / 256), 0
      for f in list:gmatch("%d+") do
        local c, r = k % pc, math.floor(k / pc)
        local pw = c < pc - 1 and 256 or (w % 256 == 0 and 256 or w % 256)
        local ph = r < pr - 1 and 256 or (h % 256 == 0 and 256 or h % 256)
        art.tiles[#art.tiles + 1] = { tonumber(f), x + c * 256, y + r * 256, pw, ph, pw / Edge(pw), ph / Edge(ph), "BORDER" }
        k = k + 1
      end
    end
  end
  arts[m] = art
  return art
end

---------------------------------------------------------------------------
-- One map being shown: a window onto it (vp), the sheet (clipped at its edges), pictures and pins
---------------------------------------------------------------------------
local function PinTip(p)
  local d = p.data
  if not (d and GameTooltip) then return end
  GameTooltip:SetOwner(p, "ANCHOR_RIGHT")
  for k, e in ipairs(d) do
    GameTooltip:AddLine((e.n and (e.n .. ". ") or "") .. (e.t or "?"), C.accent[1], C.accent[2], C.accent[3])
    if e.d and e.d ~= "" then GameTooltip:AddLine(e.d, C.text[1], C.text[2], C.text[3], true) end
    if k == 6 and #d > 6 then GameTooltip:AddLine("and " .. (#d - 6) .. " more here", C.dim[1], C.dim[2], C.dim[3]) break end
  end
  GameTooltip:AddLine("Click: point the arrow here.", C.dim[1], C.dim[2], C.dim[3])
  GameTooltip:Show()
end

local function New(parent)
  local v = { tex = {}, pins = {}, used = 0, pinsUsed = 0, scale = 1 }
  v.vp = CreateFrame("Frame", nil, parent)
  if v.vp.SetClipsChildren then v.vp:SetClipsChildren(true) end
  local bg = v.vp:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.045, 0.04, 1)
  v.sheet = CreateFrame("Frame", nil, v.vp)
  if v.sheet.SetClipsChildren then v.sheet:SetClipsChildren(true) end
  v.paper = CreateFrame("Frame", nil, v.sheet)
  v.paper:SetPoint("TOPLEFT")
  v.paper:SetPoint("BOTTOMRIGHT")
  v.pinsOn = CreateFrame("Frame", nil, v.paper)
  v.pinsOn:SetPoint("TOPLEFT")
  v.pinsOn:SetPoint("BOTTOMRIGHT")
  v.pinsOn:SetFrameLevel(Num(v.paper:GetFrameLevel(), 1) + 3)
  return v
end

local function PinAt(v, k)
  local p = v.pins[k]
  if p then return p end
  p = CreateFrame("Button", nil, v.pinsOn)
  p.ring = p:CreateTexture(nil, "BACKGROUND")
  p.ring:SetAllPoints()
  p.ring:SetTexture(DISC)
  p.disc = p:CreateTexture(nil, "BORDER")
  p.disc:SetPoint("TOPLEFT", 2, -2)
  p.disc:SetPoint("BOTTOMRIGHT", -2, 2)
  p.disc:SetTexture(DISC)
  p.disc:SetVertexColor(0.07, 0.06, 0.05, 1)
  p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  p:SetScript("OnEnter", PinTip)
  p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  p:SetScript("OnClick", function(self)
    local d = self.data and self.data[1]
    if d then
      if NS.MapView then NS.MapView.trip = nil end
      NS.Arrow.Go(d.m, d.x, d.y, d.t)
      NS.Print("arrow set to " .. (d.t or "there") .. ".")
    end
  end)
  v.pins[k] = p
  return p
end

-- pins on one map, the ones in the same spot together, the dots that aren't steps underneath
function Z.Merge(pins, m)
  local out = {}
  for _, pass in ipairs({ true, false }) do
    for _, p in ipairs(List(pins)) do
      if p.m == m and (p.state == "spot") == pass and type(p.x) == "number" then
        local at
        if not pass then
          for _, g in ipairs(out) do
            if g.state ~= "spot" and math.abs(g.x - p.x) < MERGE and math.abs(g.y - p.y) < MERGE then at = g break end
          end
        end
        if at then
          at[#at + 1] = p
          local rank = { done = 1, todo = 2, log = 3, next = 4 }
          if (rank[p.state] or 0) > (rank[at.state] or 0) then at.state = p.state end
        else
          out[#out + 1] = { p, x = p.x, y = p.y, state = p.state }
        end
      end
    end
  end
  for _, g in ipairs(out) do
    local a, b = g[1].n, g[#g].n
    g.label = a and (b and b ~= a and (#g == 2 and (a .. "," .. b) or (a .. "-" .. b)) or tostring(a)) or ""
  end
  return out
end

-- where the pictures and pins are, at this zoom
local function Place(v)
  local s = v.scale
  v.sheet:SetSize(v.art.w * s, v.art.h * s)
  v.sheet:ClearAllPoints()
  v.sheet:SetPoint("CENTER", v.vp, "CENTER", v.ox or 0, v.oy or 0)
  for k = 1, v.used do
    local x = v.tex[k]
    x:SetSize(x.w * s, x.h * s)
    x:ClearAllPoints()
    x:SetPoint("TOPLEFT", v.paper, "TOPLEFT", x.u * s, -x.v * s)
  end
  for k = 1, v.pinsUsed do
    local p = v.pins[k]
    p:ClearAllPoints()
    p:SetPoint("CENTER", v.paper, "TOPLEFT", p.x * v.art.w * s, -p.y * v.art.h * s)
  end
  -- the way from stop to stop, on this map
  local n, path = 0, List(v.path)
  local hbd = NS.HBD and NS.HBD()
  local function At(p) -- a spot on the zone next door, on this one's map
    if p.m == v.m then return p.x, p.y end
    if not (p.wx and hbd and hbd.GetZoneCoordinatesFromWorld) then return nil end
    local ok, x, y = pcall(hbd.GetZoneCoordinatesFromWorld, hbd, p.wx, p.wy, v.m, true)
    if ok and type(x) == "number" and type(y) == "number" and x > -1 and x < 2 and y > -1 and y < 2 then return x, y end
  end
  local function Line(i, thick)
    v.lines = v.lines or {}
    local l = v.lines[i]
    if not l then
      if not v.pinsOn.CreateLine then return nil end
      local ok, made = pcall(v.pinsOn.CreateLine, v.pinsOn, nil, "BACKGROUND")
      if not ok or not made then return nil end
      l = made
      v.lines[i] = l
    end
    l:SetThickness(thick)
    return l
  end
  local function Segments(pass) -- first all the dark edges, then the lines on them
    for k = 2, #path do
      local ax, ay = At(path[k - 1])
      local bx, by = At(path[k])
      if ax and bx and (math.abs(ax - bx) > 0.002 or math.abs(ay - by) > 0.002) and (path[k].m == v.m or path[k - 1].m == v.m) then
        local l = Line(n + 1, pass == 1 and 5.5 or k == 2 and 3.5 or 2.5)
        if not l then return end
        n = n + 1
        if pass == 1 then l:SetColorTexture(0.03, 0.03, 0.04, 0.6)
        elseif k == 2 then l:SetColorTexture(1, 0.93, 0.55, 1)
        else l:SetColorTexture(0.45, 0.80, 1, 0.95) end
        l:SetStartPoint("TOPLEFT", v.paper, ax * v.art.w * s, -ay * v.art.h * s)
        l:SetEndPoint("TOPLEFT", v.paper, bx * v.art.w * s, -by * v.art.h * s)
        l:Show()
      end
    end
  end
  if #path > 1 then Segments(1); Segments(2) end
  for k = n + 1, #(v.lines or {}) do v.lines[k]:Hide() end
end

-- draws map m with its pins; false = the game has no picture of it
local function Draw(v, m, pins, fit)
  local art = Z.Art(m)
  if not art then return false end
  v.art, v.m = art, m
  for k, t in ipairs(art.tiles) do
    local x = v.tex[k]
    if not x then
      x = v.paper:CreateTexture(nil, t[8])
      v.tex[k] = x
    end
    x:SetDrawLayer(t[8], math.min(7, k > 12 and 1 or 0))
    x:SetTexture(t[1])
    x:SetTexCoord(0, t[6], 0, t[7])
    x.u, x.v, x.w, x.h = t[2], t[3], t[4], t[5]
    x:Show()
  end
  v.used = #art.tiles
  for k = v.used + 1, #v.tex do v.tex[k]:Hide() end
  local n = 0
  for _, g in ipairs(Z.Merge(pins, m)) do
    n = n + 1
    local p = PinAt(v, n)
    p.data, p.x, p.y = g, g.x, g.y
    local c = RING[g.state] or RING.todo
    local spot = g.state == "spot"
    local size = spot and 9 or (g.state == "next" and 24 or 20)
    p:SetSize(#g.label > 2 and size + 10 or size, size)
    p.ring:SetVertexColor(c[1], c[2], c[3], spot and 0.85 or 1)
    p.disc:SetShown(not spot)
    p.num:SetText(spot and "" or g.label)
    p.num:SetTextColor(c[1], c[2], c[3])
    p:Show()
  end
  -- you
  local here = NS.Engine and NS.Engine.Here and NS.Engine.Here()
  if here and here.m == m then
    n = n + 1
    local p = PinAt(v, n)
    p.data, p.x, p.y = { { t = "You", m = m, x = here.x, y = here.y } }, here.x, here.y
    p:SetSize(12, 12)
    p.ring:SetVertexColor(1, 1, 1, 1)
    p.disc:SetShown(true)
    p.num:SetText("")
    p:Show()
  end
  v.pinsUsed = n
  for k = n + 1, #v.pins do v.pins[k]:Hide() end
  v.scale = fit(art)
  Place(v)
  return true
end

---------------------------------------------------------------------------
-- A small one, in a page
---------------------------------------------------------------------------
local inline
function Z.HideInline() if inline then inline.box:Hide() end end
-- draws it in a row; the height it takes, or nil
function Z.Inline(row, spec, width)
  local w = math.min(500, math.max(200, (width or 500) - 24))
  if not inline then
    local box = CreateFrame("Frame", nil, row)
    inline = New(box)
    inline.box = box
    inline.vp:SetPoint("TOPLEFT")
    inline.vp:EnableMouse(true)
    inline.vp:SetScript("OnMouseUp", function() if inline.spec then NS.Safe("zone map", Z.Show, inline.spec) end end)
    inline.note = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inline.note:SetPoint("TOPLEFT", inline.vp, "BOTTOMLEFT", 2, -5)
    inline.note:SetTextColor(unpack(C.dim))
    inline.note:SetJustifyH("LEFT")
  end
  local art = Z.Art(spec.m)
  if not art then inline.box:Hide() return nil end
  local h = math.floor(w * art.h / art.w + 0.5)
  inline.spec, inline.row = spec, row
  inline.box:SetParent(row)
  inline.box:ClearAllPoints()
  inline.box:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -10)
  inline.box:SetSize(w, h + 20)
  inline.box:SetFrameLevel(Num(row:GetFrameLevel(), 1) + 2)
  inline.vp:SetSize(w, h)
  inline.ox, inline.oy = 0, 0
  inline.path = spec.path
  Draw(inline, spec.m, spec.pins, function(a) return w / a.w end)
  inline.note:SetText((spec.name or "") .. "  ·  Click the map for a bigger one.")
  inline.box:Show()
  return h + 38
end

---------------------------------------------------------------------------
-- A big one, over the window
---------------------------------------------------------------------------
local big
local function Zoom(delta)
  local old = big.zoom
  big.zoom = math.max(1, math.min(6, old * (delta > 0 and 1.25 or 0.8)))
  local k = big.zoom / old
  big.ox, big.oy = big.ox * k, big.oy * k
  if big.zoom == 1 then big.ox, big.oy = 0, 0 end
  big.scale = big.fit * big.zoom
  Place(big)
end

local function Make()
  local parent = _G.SunstoneMainFrame
  local f = CreateFrame("Frame", "SunstoneZoneMap", parent)
  f:SetPoint("TOPLEFT", 8, -8)
  f:SetPoint("BOTTOMRIGHT", -8, 8)
  f:SetFrameLevel(Num(parent:GetFrameLevel(), 1) + 60)
  f:EnableMouse(true)
  NS.Rounded(f, C.bg, "round.png", 10)
  big = New(f)
  big.frame, big.zoom, big.ox, big.oy, big.rows, big.zones = f, 1, 0, 0, {}, {}
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 14, -12)
  f.title:SetTextColor(unpack(C.accent))
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.hint:SetPoint("TOPLEFT", 14, -32)
  f.hint:SetTextColor(unpack(C.dim))
  f.hint:SetText("Wheel: zoom. Drag: move. Hover a number. Click one for the arrow.")
  f.close = NS.Button(f, "Close map", 84, function() f:Hide() end)
  f.close:SetPoint("TOPRIGHT", -12, -12)
  local vp = big.vp
  vp:SetPoint("TOPLEFT", 10, -50)
  vp:SetPoint("BOTTOMRIGHT", -(SIDE + 20), 10)
  vp:EnableMouse(true)
  if vp.EnableMouseWheel then vp:EnableMouseWheel(true) end
  vp:SetScript("OnMouseWheel", function(_, delta) Zoom(delta) end)
  vp:SetScript("OnMouseDown", function()
    if not GetCursorPosition then return end
    local x, y = GetCursorPosition()
    local sc = Num(vp.GetEffectiveScale and vp:GetEffectiveScale(), 1)
    big.drag = { x / sc, y / sc, big.ox, big.oy }
    vp:SetScript("OnUpdate", function()
      local cx, cy = GetCursorPosition()
      big.ox, big.oy = big.drag[3] + cx / sc - big.drag[1], big.drag[4] + cy / sc - big.drag[2]
      Place(big)
    end)
  end)
  vp:SetScript("OnMouseUp", function() vp:SetScript("OnUpdate", nil) end)
  f:SetScript("OnHide", function() vp:SetScript("OnUpdate", nil) end)
  f.side = CreateFrame("Frame", nil, f)
  f.side:SetPoint("TOPRIGHT", -10, -50)
  f.side:SetPoint("BOTTOMRIGHT", -10, 10)
  f.side:SetWidth(SIDE)
  NS.Rounded(f.side, C.panel, "round.png", 8)
  f:EnableKeyboard(true)
  if f.SetPropagateKeyboardInput then -- Esc closes the map first, then the window
    f:SetScript("OnKeyDown", function(self, key)
      local esc = key == "ESCAPE"
      if not (InCombatLockdown and InCombatLockdown()) then self:SetPropagateKeyboardInput(not esc) end
      if esc then self:Hide() end
    end)
  else
    f:EnableKeyboard(false)
  end
  f:Hide()
end

-- the maps its steps are on, in order: { m, name }
function Z.Zones(spec)
  local out, has = {}, {}
  for _, p in ipairs(List(spec.pins)) do
    if p.m and not has[p.m] and p.state ~= "spot" then
      has[p.m] = true
      out[#out + 1] = p.m
    end
  end
  if spec.m and not has[spec.m] then table.insert(out, 1, spec.m) end
  return out
end

local function Name(m) return NS.Travel and NS.Travel.MapName and NS.Travel.MapName(m) or ("map " .. m) end

local function Fill(m)
  local f = big.frame
  big.zoom, big.ox, big.oy = 1, 0, 0
  big.path = big.spec.path
  local w, h = Num(big.vp:GetWidth(), 0), Num(big.vp:GetHeight(), 0)
  if w < 50 or h < 50 then w, h = 750, 500 end
  local ok = Draw(big, m, big.spec.pins, function(a)
    big.fit = math.min(w / a.w, h / a.h)
    return big.fit
  end)
  big.sheet:SetShown(ok)
  f.title:SetText((big.spec.title and (big.spec.title .. ": ") or "") .. Name(m) .. (ok and "" or " (the game has no map of it)"))
  local line, y = 0, -10
  local function Line(text, onClick, e)
    line = line + 1
    local r = big.rows[line]
    if not r then
      r = CreateFrame("Button", nil, f.side)
      r:SetSize(SIDE - 16, 18)
      r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.text:SetPoint("LEFT", 4, 0)
      r.text:SetPoint("RIGHT", -2, 0)
      r.text:SetJustifyH("LEFT")
      if r.text.SetWordWrap then r.text:SetWordWrap(false) end
      r:SetScript("OnClick", function(self) if self.fn then NS.Safe("zone map", self.fn) end end)
      r:SetScript("OnEnter", function(self)
        if self.e and GameTooltip then
          GameTooltip:SetOwner(self, "ANCHOR_LEFT")
          GameTooltip:AddLine((self.e.n and (self.e.n .. ". ") or "") .. (self.e.t or "?"), C.accent[1], C.accent[2], C.accent[3])
          if self.e.d and self.e.d ~= "" then GameTooltip:AddLine(self.e.d, C.text[1], C.text[2], C.text[3], true) end
          GameTooltip:Show()
        end
      end)
      r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      big.rows[line] = r
    end
    r.fn, r.e = onClick, e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 8, y)
    y = y - 18
    r.text:SetText(text)
    r:Show()
  end
  for _, z in ipairs(Z.Zones(big.spec)) do
    Line((z == m and "|cff" .. NS.HEX.accent or "|cff" .. NS.HEX.dim) .. Name(z) .. "|r", function() Fill(z) end)
    for _, p in ipairs(List(big.spec.pins)) do
      if p.m == z and p.n and line < 27 then
        Line(string.format("   |cff%s%s|r  %s", p.state == "next" and "fac947" or p.state == "log" and "8abf70" or p.state == "done" and "736e66" or "c95947", p.n, p.t or "?"), function()
          if z ~= m then Fill(z) end
          if NS.MapView then NS.MapView.trip = nil end
          NS.Arrow.Go(p.m, p.x, p.y, p.t)
        end, p)
      end
    end
  end
  for k = line + 1, #big.rows do big.rows[k]:Hide() end
end

-- spec = { title, m (the map to start on), name, pins = { { n, m, x, y (0-1), t, d, state }, ... } }
function Z.Show(spec)
  if not _G.SunstoneMainFrame then return false end
  if not big then Make() end
  big.spec, big.tab = spec, NS.Window and NS.Window.tab
  big.frame:Show()
  Fill(spec.m or Z.Zones(spec)[1])
  return true
end
function Z.Hide() if big then big.frame:Hide() end end
function Z.HideUnless(tab) if big and big.tab ~= tab then big.frame:Hide() end end
function Z.Big() return big end
