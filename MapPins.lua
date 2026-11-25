-- Sunstone: more on the game's world map. Flight masters (the ones you haven't learned stand out), boats and zeppelins with where
-- they go, dungeon doors, library books you haven't handed in, and each zone's levels on the continent map. Click a pin for the
-- arrow. Each kind can be switched off (Guide, Settings).
-- Data: TravelData.lua and Data.lua (OneForAll's, with permission), DungeonData.lua. Information only.

local _, NS = ...
local Mp = NS.Module("MapPins")
NS.MapPins = Mp
local C = NS.C

local REF = "SunstoneMapPins"
local pool, levelPool = {}, {}

Mp.LAYERS = {
  { "flights", "Flight masters", "Yours in gold, the ones you haven't learned yet in red.", true },
  { "boats", "Boats, zeppelins and the tram", "And where each goes.", true },
  { "doors", "Dungeon and raid doors", "With their levels.", true },
  { "books", "Library Books", "The ones you haven't handed in.", true },
  { "levels", "Zone levels", "On the continent map.", true },
}

function Mp.On(key)
  local t = NS.db and NS.db.mapPins
  if type(t) == "table" and t[key] ~= nil then return t[key] end
  for _, l in ipairs(Mp.LAYERS) do if l[1] == key then return l[4] end end
end
function Mp.Set(key, on)
  NS.db.mapPins = type(NS.db.mapPins) == "table" and NS.db.mapPins or {}
  NS.db.mapPins[key] = on and true or false
  NS.Safe("map pins", Mp.Draw)
end

local GOLD, RED, BLUE, GRAY, GREEN = { 0.98, 0.78, 0.25 }, { 0.90, 0.40, 0.30 }, { 0.55, 0.75, 0.95 }, { 0.6, 0.55, 0.5 }, { 0.60, 0.78, 0.45 }

local used = 0
local function Pin()
  used = used + 1
  local p = pool[used]
  if p then return p end
  p = CreateFrame("Button", nil, UIParent)
  p:SetSize(16, 16)
  p.rim = p:CreateTexture(nil, "BACKGROUND")
  p.rim:SetAllPoints()
  p.rim:SetTexture(NS.MEDIA .. "dot.png")
  p.bg = p:CreateTexture(nil, "BORDER")
  p.bg:SetPoint("TOPLEFT", 1.2, -1.2)
  p.bg:SetPoint("BOTTOMRIGHT", -1.2, 1.2)
  p.bg:SetTexture(NS.MEDIA .. "dot.png")
  p.bg:SetVertexColor(0.09, 0.065, 0.05, 1)
  p.glyph = p:CreateTexture(nil, "ARTWORK")
  p.glyph:SetPoint("TOPLEFT", 2.5, -2.5)
  p.glyph:SetPoint("BOTTOMRIGHT", -2.5, 2.5)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnEnter", function(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.t, C.accent[1], C.accent[2], C.accent[3])
    for _, l in ipairs(d.lines or {}) do GameTooltip:AddLine(l, C.text[1], C.text[2], C.text[3], true) end
    GameTooltip:AddLine("Click: point the arrow here." .. (d.right and (" Right-click: " .. d.rightText .. ".") or ""), C.dim[1], C.dim[2], C.dim[3], true)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self, button)
    local d = self.data
    if not d then return end
    if button == "RightButton" then
      if d.right then NS.Safe("map pin", d.right) end
      return
    end
    NS.Arrow.Go(d.m, d.x / 100, d.y / 100, d.t)
    NS.Print("arrow set to " .. d.t .. ".")
  end)
  pool[used] = p
  return p
end

-- d: { m, x, y (0-100), t, lines, glyph, color, right, rightText }
Mp.items = {}
local function Put(pins, d, flag)
  Mp.items[#Mp.items + 1] = d -- (the smooth map shows the same)
  local p = Pin()
  p.data = d
  p:SetSize(d.size or 16, d.size or 16)
  p.glyph:SetTexture(NS.MEDIA .. "pin_" .. d.glyph .. ".png")
  local c = d.color or GOLD
  p.glyph:SetVertexColor(c[1], c[2], c[3], 1)
  p.rim:SetVertexColor(c[1] * 0.75, c[2] * 0.75, c[3] * 0.75, 1)
  p:Show()
  pins:AddWorldMapIconMap(REF, p, d.m, d.x / 100, d.y / 100, flag)
end
Mp.Put = Put

local function Key(f) return string.format("%d:%.1f:%.1f", f.m, f.x, f.y) end

local function Difficulty(lo, hi)
  local lvl = UnitLevel("player") or 1
  if lvl < lo - 3 then return "c46148" elseif lvl < lo then return "d9a441" elseif lvl <= hi then return "8aa666" end
  return "8f7d68"
end

local function Levels(pins)
  local T, hbd = NS.Travel, NS.HBD()
  if not (T.ZoneLevels and hbd and hbd.TranslateZoneCoordinates and C_Map and C_Map.GetMapInfo) then return end
  local n = 0
  for m, lv in pairs(T.ZoneLevels()) do
    local ok, info = pcall(C_Map.GetMapInfo, m)
    local cont = ok and type(info) == "table" and info.parentMapID
    if cont and cont > 0 then
      local x, y = hbd:TranslateZoneCoordinates(0.5, 0.56, m, cont, true)
      if x and y then
        n = n + 1
        local f = levelPool[n]
        if not f then
          f = CreateFrame("Frame", nil, UIParent)
          f:SetSize(44, 12)
          f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          f.text:SetPoint("CENTER")
          f.text:SetShadowOffset(1, -1)
          levelPool[n] = f
        end
        f.text:SetText("|cff" .. Difficulty(lv[1], lv[2]) .. (lv[1] == lv[2] and tostring(lv[1]) or (lv[1] .. "-" .. lv[2])) .. "|r")
        f:Show()
        pins:AddWorldMapIconMap(REF, f, cont, x, y, 0) -- (0: on the continent's own map only)
      end
    end
  end
end

function Mp.Draw()
  local pins, T, E = NS.Pins(), NS.Travel, NS.Engine
  if not pins then return end
  pins:RemoveAllWorldMapIcons(REF)
  for i = 1, used do pool[i]:Hide() end
  for _, f in ipairs(levelPool) do f:Hide() end
  used = 0
  Mp.items = {}
  local PARENT = HBD_PINS_WORLDMAP_SHOW_PARENT or 1
  local CONT = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
  local D = T and T.Data and T.Data()
  if D and Mp.On("flights") then
    local known = T.Known and T.Known() or {}
    for _, f in ipairs(D.flight) do
      if T.Friendly(f.side) then
        local k = known[Key(f)]
        Put(pins, { m = f.m, x = f.x, y = f.y, t = f.name, glyph = "fly", color = k and GOLD or RED, size = k and 14 or 16,
                    lines = { k and (type(k) == "string" and k ~= "" and ("Flight master: " .. k) or "Flight master, learned.")
                                or "Flight master. Sunstone hasn't seen that you know this one: talk to them to learn it." } }, CONT)
      end
    end
  end
  if D and Mp.On("boats") then
    for _, t in ipairs(D.transport) do
      if T.Friendly(t.side) then
        local lines = {}
        for _, d in ipairs(t.dests) do lines[#lines + 1] = "To " .. d end
        Put(pins, { m = t.m, x = t.x, y = t.y, t = t.label:gsub("^%l", string.upper), glyph = (t.kind == "ship" and "boat") or (t.kind == "tram" and "tram") or "zep",
                    color = BLUE, lines = lines }, CONT)
      end
    end
  end
  if Mp.On("doors") and type(_G.SunstoneDungeons) == "table" then
    local lvl = UnitLevel("player") or 1
    for _, d in ipairs(_G.SunstoneDungeons.list or {}) do
      if d.m and d.x and d.y then
        local fits = lvl >= (d.lo or 1) - 1 and lvl <= (d.hi or 60) + 2
        Put(pins, { m = d.m, x = d.x, y = d.y, t = d.n, glyph = "door", color = fits and GREEN or GRAY, size = fits and 17 or 14,
                    lines = { (d.raid and "Raid" or "Dungeon") .. (d.lo and string.format(", levels %d-%d", d.lo, d.hi or d.lo) or "") }, rightText = "its page",
                    right = function() NS.Dungeons.Open(d) end }, CONT)
      end
    end
  end
  if Mp.On("books") and E and NS.Factions2 and NS.Factions2.MissingBooks then
    for _, b in ipairs(NS.Factions2.MissingBooks()) do
      Put(pins, { m = b.m, x = b.x, y = b.y, t = b.n, glyph = "book", color = b.enemy and RED or GOLD, size = 14,
                  lines = { "Library Book" .. (b.where ~= "" and (": " .. b.where) or ""), b.enemy and "In the other faction's territory." or nil } }, PARENT)
    end
  end
  if Mp.On("levels") then Levels(pins) end
end

function Mp:Init()
  local function Soon() NS.Debounce("map pins", 2, Mp.Draw) end
  C_Timer.After(6, function() NS.Safe("map pins", Mp.Draw) end)
  NS.On("PLAYER_LEVEL_UP", Soon)
  NS.On("TAXIMAP_OPENED", function() C_Timer.After(2, Soon) end)
  NS.On("QUEST_TURNED_IN", Soon)
end

for _, l in ipairs(Mp.LAYERS) do
  NS.Setting("On the world map", l[2], l[3], function() return Mp.On(l[1]) end, function(v) Mp.Set(l[1], v) end)
end
NS.Command("pins", "[flights|boats|doors|books|levels] - what's shown on the world map (Guide, Settings has them all)", function(rest)
  rest = (rest or ""):lower()
  for _, l in ipairs(Mp.LAYERS) do
    if l[1] == rest then
      Mp.Set(rest, not Mp.On(rest))
      NS.Print(l[2] .. " on the world map: " .. (Mp.On(rest) and "on." or "off."))
      return
    end
  end
  NS.cdb.guideMode = "set"
  if NS.Window then NS.Window.Open("guide") end
end)
