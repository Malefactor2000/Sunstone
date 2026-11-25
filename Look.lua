-- Sunstone: the graphics kit. Framed icons with quality-coloured edges, stat bars, 3D models you can turn (your character, beasts, bosses,
-- demons, pets and mounts) and panels that stand inside a page. All art and models are the game's own; a model the game can't show leaves
-- its icon in its place. Information only: trying an item on changes nothing but the picture.

local _, NS = ...
local Lk = {}
NS.Look = Lk
local C = NS.C
local I = "Interface\\Icons\\"

-- item quality, a little brighter than the text versions: these are thin edges
Lk.QUALITY = { [0] = { 0.45, 0.42, 0.38 }, [1] = { 0.62, 0.56, 0.46 }, [2] = { 0.36, 0.72, 0.28 }, [3] = { 0.25, 0.50, 0.86 }, [4] = { 0.63, 0.36, 0.82 },
               [5] = { 0.92, 0.55, 0.16 } }
Lk.GOLD = { 0.95, 0.74, 0.26 }
Lk.BLUE = { 0.36, 0.55, 0.80 }

-- a frame's method, when this client has it (models differ from client to client)
local function Try(f, name, ...)
  local fn = f and f[name]
  if type(fn) ~= "function" then return false end
  return pcall(fn, f, ...)
end
Lk.Try = Try

function Lk.DisplayOf(npc)
  if type(npc) ~= "number" then return nil end
  local looks = type(_G.SunstoneLooks) == "table" and _G.SunstoneLooks or {}
  local d = type(looks.npc) == "table" and looks.npc[npc]
  if d then return d end
  local seen = NS.db and type(NS.db.looks) == "table" and NS.db.looks[npc] -- learned from one you targeted
  return type(seen) == "number" and seen or nil
end

-- The round picture of a creature on a texture (false: none known)
function Lk.Face(tex, npc, display)
  local d = display or Lk.DisplayOf(npc)
  if not (d and type(SetPortraitTextureFromCreatureDisplayID) == "function") then return false end
  return (pcall(SetPortraitTextureFromCreatureDisplayID, tex, d))
end

---------------------------------------------------------------------------
-- Edges, icons, bars, text
---------------------------------------------------------------------------
function Lk.Edge(f, thick, layer, sub)
  local t = thick or 1
  local e = {}
  for k = 1, 4 do e[k] = f:CreateTexture(nil, layer or "OVERLAY", nil, sub or 1) end
  e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(t)
  e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(t)
  e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(t)
  e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(t)
  local h = {}
  function h:SetColor(c, a) for _, x in ipairs(e) do x:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1) end end
  function h:SetShown(on) for _, x in ipairs(e) do x:SetShown(on and true or false) end end
  function h:Thick(n) e[1]:SetHeight(n); e[2]:SetHeight(n); e[3]:SetWidth(n); e[4]:SetWidth(n) end
  h:SetColor(C.border)
  return h
end

function Lk.Text(f, font, color, justify)
  local s = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  s:SetTextColor(unpack(color or C.text))
  s:SetJustifyH(justify or "LEFT")
  return s
end

-- An icon button: picture, edge, a small number at the corner, dimming. b.about(b) fills the tooltip; b.item / b.spell show the game's own.
function Lk.Icon(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.back = b:CreateTexture(nil, "BACKGROUND")
  b.back:SetAllPoints()
  b.back:SetColorTexture(0.02, 0.015, 0.012, 1)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetPoint("TOPLEFT", 1, -1)
  b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  b.edge = Lk.Edge(b, 1)
  b.num = Lk.Text(b, "NumberFontNormalSmall", C.text, "RIGHT")
  b.num:SetPoint("BOTTOMRIGHT", -2, 2)
  b.mark = b:CreateTexture(nil, "OVERLAY", nil, 2) -- a small badge at the top left
  b.mark:SetSize(math.max(14, size * 0.40), math.max(14, size * 0.40))
  b.mark:SetPoint("TOPLEFT", -3, 3)
  b.mark:Hide()
  function b:Badge(name) -- "up" (an upgrade), "star", or nothing
    self.mark:SetTexture(name and (NS.MEDIA .. name .. ".png") or nil)
    self.mark:SetTexCoord(0, 1, 0, 1)
    self.mark:SetShown(name ~= nil)
  end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.9, 0.6, 0.14)
  function b:Set(texture, face, npc)
    if face and Lk.Face(self.tex, npc, face ~= true and face or nil) then
      self.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      return
    end
    self.tex:SetTexture(texture or NS.QUESTION_ICON)
    self.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  function b:Dim(on)
    Try(self.tex, "SetDesaturated", on and true or false)
    self.tex:SetAlpha(on and 0.45 or 1)
  end
  b:SetScript("OnEnter", function(self)
    if self.item or self.spell then NS.Window.ShowItemTip(self, self.item, self.spell) end
    if self.about then
      if not (self.item or self.spell) then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
      NS.Safe("tooltip", self.about, self)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

function Lk.TipLine(text, color, wrap)
  local c = color or C.text
  GameTooltip:AddLine(text, c[1], c[2], c[3], wrap ~= false)
end

-- A stat bar: a name on the left, the value on the right, a fill, and a thin mark (what it's compared with)
function Lk.Bar(parent, height)
  local b = CreateFrame("Frame", nil, parent)
  b:SetHeight(height or 18)
  b.back = b:CreateTexture(nil, "BACKGROUND")
  b.back:SetAllPoints()
  b.back:SetColorTexture(0.03, 0.022, 0.018, 1)
  b.fill = b:CreateTexture(nil, "BORDER")
  b.fill:SetPoint("TOPLEFT", 1, -1)
  b.fill:SetPoint("BOTTOMLEFT", 1, 1)
  b.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b.edge = Lk.Edge(b, 1, "ARTWORK")
  b.edge:SetColor(C.border, 0.7)
  b.mark = b:CreateTexture(nil, "OVERLAY", nil, 3)
  b.mark:SetWidth(2)
  b.mark:SetColorTexture(1, 0.92, 0.7, 0.9)
  b.mark:Hide()
  b.name = Lk.Text(b, "GameFontHighlightSmall", C.text)
  b.name:SetPoint("LEFT", 7, 0)
  b.value = Lk.Text(b, "GameFontHighlightSmall", C.text, "RIGHT")
  b.value:SetPoint("RIGHT", -7, 0)
  function b:Set(name, share, value, color, mark)
    local w = math.max(10, (tonumber(self:GetWidth()) or 100) - 2)
    self.name:SetText(name)
    self.value:SetText(value)
    local s = math.max(0.005, math.min(1, share or 0))
    self.fill:SetWidth(w * s)
    local c = color or C.red
    self.fill:SetVertexColor(c[1], c[2], c[3], 0.85)
    if mark then
      local x = 1 + w * math.max(0, math.min(1, mark))
      self.mark:ClearAllPoints()
      self.mark:SetPoint("TOPLEFT", x, -1)
      self.mark:SetPoint("BOTTOMLEFT", x, 1)
      self.mark:Show()
    else
      self.mark:Hide()
    end
  end
  b:EnableMouse(true)
  b:SetScript("OnEnter", function(self)
    if not self.about then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    NS.Safe("tooltip", self.about, self)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- The game's four-piece backgrounds (talent trees "...-TopLeft", the dressing room's "...1" to "...4") behind a frame
function Lk.Art(f, talents)
  local pieces = {}
  for k = 1, 4 do pieces[k] = f:CreateTexture(nil, "BACKGROUND", nil, 2) end
  local h = {}
  function h:Set(base, shade)
    local w, ht = tonumber(f:GetWidth()) or 100, tonumber(f:GetHeight()) or 100
    local names = talents and { "TopLeft", "TopRight", "BottomLeft", "BottomRight" } or { "1", "2", "3", "4" }
    -- the first piece is 256 wide of about 300, and 256 high of about 331 (the lower pieces are only drawn on at the top)
    local fw, fh = talents and 256 / 300 or 256 / 318, 256 / 331
    local tx, ty = talents and 44 / 64 or 62 / 64, 75 / 128
    local s = shade or 0.6
    for k = 1, 4 do
      local p = pieces[k]
      local right, low = k % 2 == 0, k > 2
      p:SetTexture(base .. names[k])
      p:SetTexCoord(0, right and tx or 1, 0, low and ty or 1)
      p:SetVertexColor(s, s, s, 1)
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", f, "TOPLEFT", right and w * fw or 0, low and -ht * fh or 0)
      p:SetSize(right and w * (1 - fw) or w * fw, low and ht * (1 - fh) or ht * fh)
      p:Show()
    end
  end
  function h:Hide() for _, p in ipairs(pieces) do p:Hide() end end
  return h
end

---------------------------------------------------------------------------
-- 3D models
---------------------------------------------------------------------------
-- A framed model: drag to turn, + and - for size. v:Show{ unit=, display=, npc=, icon= } (the first of them that works); v:Show("player") = you, in your gear
-- kind "dress": the dressing room (v:TryOn(item), v:Reset()).
local ANGLE = 0.45
function Lk.Model(parent, w, h, kind)
  local v = CreateFrame("Frame", nil, parent)
  v:SetSize(w, h)
  v.back = v:CreateTexture(nil, "BACKGROUND")
  v.back:SetAllPoints()
  v.back:SetColorTexture(0.035, 0.026, 0.022, 1)
  v.art = Lk.Art(v, kind ~= "dress")
  v.big = v:CreateTexture(nil, "BORDER")
  local side = math.min(96, math.min(w, h) * 0.5)
  v.big:SetSize(side, side)
  v.big:SetPoint("CENTER")
  v.big:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  v.bigEdge = CreateFrame("Frame", nil, v)
  v.bigEdge:SetPoint("TOPLEFT", v.big, -1, 1)
  v.bigEdge:SetPoint("BOTTOMRIGHT", v.big, 1, -1)
  Lk.Edge(v.bigEdge, 1)
  local ok, m = pcall(CreateFrame, kind == "dress" and "DressUpModel" or "PlayerModel", nil, v)
  if not ok then m = nil end
  v.model = m
  v.angle, v.zoom = ANGLE, 1
  local over = CreateFrame("Frame", nil, v) -- the frame around it, above the model
  over:SetAllPoints()
  local lvl = v.GetFrameLevel and v:GetFrameLevel()
  if type(lvl) == "number" then over:SetFrameLevel(lvl + 4) end
  Lk.Edge(over, 1):SetColor(C.border)
  v.over = over
  local function Icon(on) v.iconOn = on; v.big:SetShown(on); v.bigEdge:SetShown(on) end
  local function Pose()
    Try(m, "SetPortraitZoom", 0)
    Try(m, "SetCamDistanceScale", 1 / v.zoom)
    if not Try(m, "SetFacing", v.angle) then Try(m, "SetRotation", v.angle) end
  end
  if m then
    m:SetPoint("TOPLEFT", 2, -2)
    m:SetPoint("BOTTOMRIGHT", -2, 2)
    Try(m, "SetScript", "OnModelLoaded", function() Icon(false); Pose() end)
  end
  local function Clear() if not Try(m, "ClearModel") then Try(m, "SetModel", "") end end
  -- a 3D picture isn't cut off by the edge of a page: when it's scrolled partly out, it's left out
  local guard, wait = CreateFrame("Frame", nil, v), 0
  guard:SetScript("OnUpdate", function(_, dt)
    wait = wait + (dt or 0)
    if not m or wait < 0.03 then return end
    wait = 0
    local sf = _G.SunstoneDetailScroll
    local t, b, st, sb = v:GetTop(), v:GetBottom(), sf and sf:GetTop(), sf and sf:GetBottom()
    if not (type(t) == "number" and type(b) == "number" and type(st) == "number" and type(sb) == "number") then return end
    local inside = t <= st + 1 and b >= sb - 1
    if inside ~= v.inside then
      v.inside = inside
      Try(m, "SetAlpha", inside and 1 or 0)
    end
  end)
  v:SetScript("OnShow", function(self) -- a model can lose itself while its window is closed: shown again when it opens
    if self.last and m then
      C_Timer.After(0.05, function()
        if not self:IsVisible() then return end
        self.key = nil
        self:Show1(self.last)
        if self.after then NS.Safe("model", self.after) end
      end)
    end
  end)
  function v:Show1(spec)
    self.last = spec
    local key = spec == "player" and "player" or (spec.unit and ("u" .. tostring(spec.npc))) or tostring(spec.display) .. ":" .. tostring(spec.npc)
    self.big:SetTexture(type(spec) == "table" and spec.icon or I .. "INV_Misc_QuestionMark")
    if self.key == key and not (type(spec) == "table" and spec.fresh) then return end
    self.key, self.angle, self.zoom = key, ANGLE, 1
    if not m then Icon(true) return end
    Icon(spec ~= "player")
    Clear()
    local shown
    if spec == "player" then shown = Try(m, "SetUnit", "player")
    else
      local display = spec.display or Lk.DisplayOf(spec.npc)
      if spec.unit and UnitExists(spec.unit) then
        shown = Try(m, "SetUnit", spec.unit)
        if shown and not display and spec.npc then -- remember its model: it can be shown again without the beast
          local tries = 0
          local function Learn()
            tries = tries + 1
            local ok2, d = pcall(function() return m:GetDisplayInfo() end)
            if ok2 and type(d) == "number" and d > 0 and not (issecretvalue and issecretvalue(d)) then
              if v.key == key and NS.db then
                NS.db.looks = type(NS.db.looks) == "table" and NS.db.looks or {}
                NS.db.looks[spec.npc] = d
              end
            elseif tries < 8 then C_Timer.After(0.25, Learn) end
          end
          C_Timer.After(0.2, Learn)
        end
      elseif display then shown = Try(m, "SetDisplayInfo", display)
      elseif spec.npc then shown = Try(m, "SetCreature", spec.npc) end
    end
    if not shown then Icon(true) end
    Pose()
    C_Timer.After(0.1, Pose)
  end
  function v:TryOn(item)
    if type(item) == "number" then item = "item:" .. item end
    return Try(m, "TryOn", item)
  end
  function v:Reset()
    self.key = nil
    if not Try(m, "Dress") then self:Show1("player") return end
    self.key = "player"
  end
  -- turning it
  v:EnableMouse(true)
  v:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local x = GetCursorPosition()
    local from = self.angle
    self:SetScript("OnUpdate", function(s)
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then s:SetScript("OnUpdate", nil) return end
      local now = GetCursorPosition()
      s.angle = from + (now - x) * 0.012
      if not Try(m, "SetFacing", s.angle) then Try(m, "SetRotation", s.angle) end
    end)
  end)
  v:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  v:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  local function Step(text, x, by)
    local b = NS.Button(over, text, 20, function() v.zoom = math.max(0.5, math.min(2.5, v.zoom * by)); Pose() end)
    b:SetHeight(18)
    b:SetPoint("BOTTOMRIGHT", x, 6)
    return b
  end
  Step("+", -6, 1.2)
  Step("-", -28, 1 / 1.2)
  return v
end

---------------------------------------------------------------------------
-- Panels standing in a page: a row with panel = { key =, make = function(parent) -> frame, update = function(frame, width, panel) -> height }
---------------------------------------------------------------------------
local made, shown = {}, {}
function Lk.HideInline()
  for f in pairs(shown) do f:Hide(); shown[f] = nil end
end
function Lk.Inline(row, p, width)
  local f = made[p.key]
  if not f then
    f = p.make(row)
    made[p.key] = f
  end
  f:SetParent(row)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  f:SetWidth(width)
  local lvl = row.GetFrameLevel and row:GetFrameLevel()
  if type(lvl) == "number" then f:SetFrameLevel(lvl + 2) end
  local ok, h = pcall(p.update, f, width, p)
  if not ok then NS.Error("panel " .. tostring(p.key), h); f:Hide(); return nil end
  f:SetHeight(h or 10)
  f:Show()
  shown[f] = true
  return h
end
function Lk.Made(key) return made[key] end

-- A plain picture panel: the 3D model on the left, a name and lines of text beside it.
-- spec = { unit/display/npc/icon, title, sub, lines = { { text, color } }, art = talent art base, h = height }
function Lk.PicturePanel(key, spec)
  return { panel = { key = "pic" .. key, spec = spec,
    make = function(row)
      local f = CreateFrame("Frame", nil, row)
      f.bg = NS.Rounded(f, C.surface, "round.png", 10)
      f.view = Lk.Model(f, 230, 190)
      f.view:SetPoint("TOPLEFT", 8, -8)
      f.title = Lk.Text(f, "GameFontNormalLarge", C.accent)
      f.title:SetPoint("TOPLEFT", f.view, "TOPRIGHT", 14, -6)
      f.title:SetPoint("RIGHT", -10, 0)
      f.sub = Lk.Text(f, "GameFontHighlightSmall", C.dim)
      f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
      f.sub:SetPoint("RIGHT", -10, 0)
      f.body = Lk.Text(f, "GameFontHighlight", C.text)
      f.body:SetPoint("TOPLEFT", f.sub, "BOTTOMLEFT", 0, -10)
      f.body:SetPoint("RIGHT", -10, 0)
      f.body:SetSpacing(3)
      f.hint = Lk.Text(f, "GameFontHighlightSmall", C.dim)
      f.hint:SetPoint("BOTTOMLEFT", f.view, "BOTTOMRIGHT", 14, 4)
      f.hint:SetText("Drag the picture to turn it.")
      return f
    end,
    update = function(f, _, p)
      local s = p.spec
      f.view.art:Set(s.art or "Interface\\TalentFrame\\HunterBeastMastery-", 0.45)
      f.view:Show1(s)
      f.title:SetText(s.title or "")
      f.sub:SetText(s.sub or "")
      local out = {}
      for _, l in ipairs(s.lines or {}) do out[#out + 1] = l end
      f.body:SetText(table.concat(out, "\n"))
      return 206
    end } }
end
