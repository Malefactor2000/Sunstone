-- Sunstone: quests on the map, the minimap and nameplates. "!" where someone has a quest for you (your class, race, level and what
-- you've already done), "?" where a quest in your log is handed in (bright when it's finished), and for what your quests still want, one
-- mark for each group of creatures or things, bigger for bigger groups. On a nameplate: a mark over creatures your quests want.
-- With Questie installed these stay off unless you switch them on (Guide, Settings), so nothing shows twice.
-- Facts: QuestDB.lua. Information only: nothing here accepts or hands in a quest.

local _, NS = ...
local Q = NS.Module("QuestPins")
NS.QuestPins = Q
local E = NS.Engine
local C = NS.C

local REF = "SunstoneQuestPins"
local GROUP = 2.6          -- percent of the map: closer than this is one group
local MAX_GROUPS = 14      -- marks per objective
local MAX_GIVERS = 400
local GRAY = 9             -- this many levels below you, a quest is hardly worth the walk
local GOLD, DIM, BLUE, RED = { 0.98, 0.80, 0.28 }, { 0.55, 0.52, 0.46 }, { 0.50, 0.75, 0.95 }, { 0.90, 0.45, 0.35 }

-- "auto" (on without Questie), "on" or "off"
function Q.Mode()
  local m = NS.db and NS.db.questPins
  return (m == "on" or m == "off") and m or "auto"
end
function Q.Shown()
  local m = Q.Mode()
  if m == "auto" then return not (NS.QuestDB.Questie() and Questie) end
  return m == "on"
end
function Q.SetMode(m)
  NS.db.questPins = m
  Q.Refresh()
end
local function Part(key) return not (NS.db and type(NS.db.questParts) == "table" and NS.db.questParts[key] == false) end
local function SetPart(key, on)
  NS.db.questParts = type(NS.db.questParts) == "table" and NS.db.questParts or {}
  NS.db.questParts[key] = on and true or false
  Q.Refresh()
end

---------------------------------------------------------------------------
-- What to show
---------------------------------------------------------------------------
local function Level() return UnitLevel("player") or 1 end

-- would someone give you this quest right now?
function Q.Available(qid, log)
  if log[qid] or E.Done(qid) then return false end
  local level = Level()
  local req, ql = E.QuestReq(qid), E.QuestLevel(qid)
  if req > level or (ql > 0 and ql < level - GRAY) then return false end
  local top = E.Q("Quest", qid, "requiredMaxLevel")
  if type(top) == "number" and top > 0 and level > top then return false end
  if not E.QuestOK(qid) then return false end
  for _, e in pairs(E.Q("Quest", qid, "exclusiveTo") or {}) do if E.Done(e) or log[e] then return false end end
  local chain = E.Chain(qid)
  return chain ~= nil and #chain == 0
end

local function Title(qid)
  local l = E.QuestLevel(qid)
  return (l > 0 and ("[" .. l .. "] ") or "") .. E.QuestName(qid)
end

local givers = {}      -- { m, x, y (0-1), who, quests = { id } }
-- Who has something for you: in the background, a little at a time
function Q.BuildGivers(done)
  local lib = E.Lib()
  if not (lib and lib.Quest.GetAllIds) or E.Busy("quest givers") then return end
  E.Job("quest givers", function()
    local at, out = {}, {}
    local log = E.Log()
    local level = Level()
    local ids = {}
    for _, qid in ipairs(lib.Quest.GetAllIds()) do ids[#ids + 1] = qid end
    for _, qid in ipairs(ids) do
      E.Yield()
      local ql, req = E.QuestLevel(qid), E.QuestReq(qid)
      if req <= level and (ql <= 0 or ql >= level - GRAY) and Q.Available(qid, log) then
        local sb = E.Q("Quest", qid, "startedBy")
        for k, kind in ipairs({ "Npc", "Object" }) do
          local n = 0
          for _, id in pairs(type(sb) == "table" and type(sb[k]) == "table" and sb[k] or {}) do
            n = n + 1
            if n <= 4 and (kind == "Object" or E.Friendly(id)) then
              for i, p in ipairs(E.Points(kind, id)) do
                if i > 2 or #out >= MAX_GIVERS then break end
                local key = p.m .. ":" .. math.floor(p.x * 400) .. ":" .. math.floor(p.y * 400)
                local g = at[key]
                if not g then
                  local name = kind == "Npc" and E.NpcName(id) or E.Q("Object", id, "name")
                  g = { m = p.m, x = p.x, y = p.y, who = type(name) == "string" and name or "?", quests = {} }
                  at[key] = g
                  out[#out + 1] = g
                end
                local has
                for _, q in ipairs(g.quests) do if q == qid then has = true end end
                if not has then g.quests[#g.quests + 1] = qid end
              end
            end
          end
        end
      end
    end
    return out
  end, function(res)
    givers = res or {}
    if done then done() end
  end)
end
function Q.Givers() return givers end

-- groups of points on one map: { m, x, y, n }
function Q.Groups(pts)
  local out = {}
  for _, p in ipairs(pts) do
    local best
    for _, g in ipairs(out) do
      if g.m == p.m then
        local dx, dy = (g.sx / g.n - p.x) * 100, (g.sy / g.n - p.y) * 100
        if dx * dx + dy * dy <= GROUP * GROUP then best = g break end
      end
    end
    if best then best.n, best.sx, best.sy = best.n + 1, best.sx + p.x, best.sy + p.y
    else out[#out + 1] = { m = p.m, n = 1, sx = p.x, sy = p.y } end
  end
  for _, g in ipairs(out) do g.x, g.y = g.sx / g.n, g.sy / g.n end
  table.sort(out, function(a, b) return a.n > b.n end)
  while #out > MAX_GROUPS do table.remove(out) end
  return out
end

-- what your quests still want: { m, x, y, n, glyph, lines }, and the creatures themselves for the nameplates
local wantedNpc = {}
function Q.Objectives()
  local out, want = {}, {}
  for _, q in ipairs(NS.Route.Quests()) do
    local o = E.Q("Quest", q.id, "objectives")
    local function Add(pts, glyph, x)
      -- the log's line as it stands when you look (marks aren't redrawn for every kill)
      local function line()
        if not x.i then return x.t end
        local now = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.id)
        return now and now[x.i] and now[x.i].text or x.t
      end
      for _, g in ipairs(Q.Groups(pts)) do
        out[#out + 1] = { m = g.m, x = g.x, y = g.y, n = g.n, glyph = glyph, title = Title(q.id), line = line }
      end
    end
    if not q.complete and not q.failed then
      local texts, used = {}, {}
      for i, x in ipairs(q.objectives) do texts[i] = { t = x.text or "", done = x.finished, type = x.type, i = i } end
      -- the log's line for a name ("Razormane Defender slain: 3/8"), or the next one of that kind
      local function Line(name, kind)
        local low = type(name) == "string" and name:lower() or nil
        for i, x in ipairs(texts) do if not used[i] and low and x.t:lower():find(low, 1, true) then used[i] = true return x end end
        for i, x in ipairs(texts) do if not used[i] and x.type == kind then used[i] = true return x end end
      end
      for _, e in pairs(type(o) == "table" and type(o[1]) == "table" and o[1] or {}) do
        local x = type(e) == "table" and e[1] and Line(E.NpcName(e[1]), "monster")
        if x and not x.done then Add(E.Points("Npc", e[1]), "kill", x); want[e[1]] = want[e[1]] or x.t end
      end
      for _, e in pairs(type(o) == "table" and type(o[2]) == "table" and o[2] or {}) do
        local x = type(e) == "table" and e[1] and Line(E.Q("Object", e[1], "name"), "object")
        if x and not x.done then Add(E.Points("Object", e[1]), "use", x) end
      end
      for _, e in pairs(type(o) == "table" and type(o[3]) == "table" and o[3] or {}) do
        local x = type(e) == "table" and e[1] and Line(E.ItemName(e[1]), "item")
        if x and not x.done then
          local pts, n = {}, 0
          for _, id in pairs(E.Q("Item", e[1], "npcDrops") or {}) do
            n = n + 1
            if n <= 8 then
              for _, p in ipairs(E.Points("Npc", id)) do if #pts < 160 then pts[#pts + 1] = p end end
              want[id] = want[id] or x.t
            end
          end
          n = 0
          for _, id in pairs(E.Q("Item", e[1], "objectDrops") or {}) do
            n = n + 1
            if n <= 6 then for _, p in ipairs(E.Points("Object", id)) do if #pts < 220 then pts[#pts + 1] = p end end end
          end
          Add(pts, "loot", x)
        end
      end
      local te = E.Q("Quest", q.id, "triggerEnd")
      if type(te) == "table" and type(te[2]) == "table" then Add(E.SpawnPoints(te[2], 30), "use", { t = "Go here" }) end
    end
  end
  wantedNpc = want
  return out
end

-- where your quests are handed in
function Q.TurnIns()
  local at, out = {}, {}
  for _, q in ipairs(NS.Route.Quests()) do
    local fin = E.Q("Quest", q.id, "finishedBy")
    local ready = q.complete or #(q.objectives or {}) == 0
    for k, kind in ipairs({ "Npc", "Object" }) do
      for _, id in pairs(type(fin) == "table" and type(fin[k]) == "table" and fin[k] or {}) do
        for i, p in ipairs(E.Points(kind, id)) do
          if i > 2 then break end
          local key = p.m .. ":" .. math.floor(p.x * 400) .. ":" .. math.floor(p.y * 400)
          local g = at[key]
          if not g then
            local name = kind == "Npc" and E.NpcName(id) or E.Q("Object", id, "name")
            g = { m = p.m, x = p.x, y = p.y, who = type(name) == "string" and name or "?", ready = {}, later = {} }
            at[key] = g
            out[#out + 1] = g
          end
          local l = ready and g.ready or g.later
          l[#l + 1] = q.id
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local pools = { world = {}, mini = {} }
local used = { world = 0, mini = 0 }

local function Pin(kind)
  used[kind] = used[kind] + 1
  local pool = pools[kind]
  local p = pool[used[kind]]
  if p then return p end
  p = CreateFrame("Button", nil, UIParent)
  p.shade = p:CreateTexture(nil, "BACKGROUND")
  p.shade:SetAllPoints()
  p.shade:SetTexture(NS.MEDIA .. "dot.png")
  p.shade:SetVertexColor(0.05, 0.035, 0.03, 0.85)
  p.glyph = p:CreateTexture(nil, "ARTWORK")
  p.glyph:SetPoint("TOPLEFT", 1.5, -1.5)
  p.glyph:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
  p:RegisterForClicks("LeftButtonUp")
  p:SetScript("OnEnter", function(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.t, C.accent[1], C.accent[2], C.accent[3])
    for _, l in ipairs(d.lines) do
      local text = type(l) == "function" and l() or l
      if type(text) == "string" then GameTooltip:AddLine(text, C.text[1], C.text[2], C.text[3], true) end
    end
    if kind == "world" then GameTooltip:AddLine("Click: point the arrow here.", C.dim[1], C.dim[2], C.dim[3], true) end
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self)
    local d = self.data
    if d and kind == "world" then
      NS.Arrow.Go(d.m, d.x, d.y, d.t)
      NS.Print("arrow set to " .. d.t .. ".")
    end
  end)
  pool[used[kind]] = p
  return p
end

Q.items = {}
local function Put(pins, d)
  Q.items[#Q.items + 1] = d -- (the smooth map shows the same)
  local w = Pin("world")
  w.data = d
  w:SetSize(d.size, d.size)
  w.glyph:SetTexture(NS.MEDIA .. "pin_" .. d.glyph .. ".png")
  w.glyph:SetVertexColor(d.c[1], d.c[2], d.c[3], 1)
  w:Show()
  pins:AddWorldMapIconMap(REF, w, d.m, d.x, d.y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
  if Part("mini") then
    local m = Pin("mini")
    m.data = d
    m:SetSize(math.min(13, d.size - 2), math.min(13, d.size - 2))
    m.glyph:SetTexture(NS.MEDIA .. "pin_" .. d.glyph .. ".png")
    m.glyph:SetVertexColor(d.c[1], d.c[2], d.c[3], 1)
    m:Show()
    pins:AddMinimapIconMap(REF, m, d.m, d.x, d.y, true, false)
  end
end

local function Clear()
  local pins = NS.Pins()
  if not pins then return end
  pins:RemoveAllWorldMapIcons(REF)
  pins:RemoveAllMinimapIcons(REF)
  for k, pool in pairs(pools) do
    for i = 1, used[k] do pool[i]:Hide() end
    used[k] = 0
  end
  Q.items = {}
end

local List_ -- what's put on the map
function Q.Draw()
  Clear()
  local pins = NS.Pins()
  if not pins or not Q.Shown() or not E.Lib() then wantedNpc = {} Q.Plates() return end
  for _, d in ipairs(List_()) do Put(pins, d) end
  Q.Plates()
end
-- for the smooth map: there too when Questie draws the game map's own
function Q.ForAtlas()
  if Q.Shown() then return Q.items end
  if Q.Mode() ~= "auto" or not E.Lib() then return {} end
  return List_()
end
List_ = function()
  local out = {}
  local function Put(_, d) out[#out + 1] = d end
  local pins
  if Part("wants") then
    for _, o in ipairs(Q.Objectives()) do
      Put(pins, { m = o.m, x = o.x, y = o.y, glyph = o.glyph, c = BLUE, size = math.min(20, 10 + math.floor(o.n ^ 0.6)), t = o.title, lines = { o.line, o.n > 1 and (o.n .. " here") or nil } })
    end
  else
    Q.Objectives() -- (the nameplates still want to know)
  end
  if Part("gives") then
    for _, g in ipairs(givers) do
      local lines, low = {}, true
      for _, qid in ipairs(g.quests) do
        lines[#lines + 1] = Title(qid)
        if E.QuestLevel(qid) == 0 or E.QuestLevel(qid) >= Level() - 5 then low = false end
      end
      Put(pins, { m = g.m, x = g.x, y = g.y, glyph = "bang", c = low and DIM or GOLD, size = 16, t = g.who, lines = lines })
    end
  end
  if Part("takes") then
    for _, g in ipairs(Q.TurnIns()) do
      local lines = {}
      for _, qid in ipairs(g.ready) do lines[#lines + 1] = "Hand in: " .. Title(qid) end
      for _, qid in ipairs(g.later) do lines[#lines + 1] = "|cff" .. NS.HEX.dim .. Title(qid) .. " (not done yet)|r" end
      Put(pins, { m = g.m, x = g.x, y = g.y, glyph = "ask", c = #g.ready > 0 and GOLD or DIM, size = #g.ready > 0 and 18 or 14, t = g.who, lines = lines })
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Nameplates
---------------------------------------------------------------------------
local plates = {}  -- [unit] = mark
local function NpcOf(unit)
  local g = NS.GUID(unit)
  if type(g) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", g)
  return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end

local function Plate(unit)
  local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
  local mark = plates[unit]
  local id = np and Q.Shown() and Part("plates") and NpcOf(unit)
  local want = id and wantedNpc[id]
  if not want then
    if mark then mark:Hide() end
    return
  end
  if not mark then
    mark = CreateFrame("Frame", nil, UIParent)
    mark:SetSize(16, 16)
    mark.bg = mark:CreateTexture(nil, "BACKGROUND")
    mark.bg:SetAllPoints()
    mark.bg:SetTexture(NS.MEDIA .. "dot.png")
    mark.bg:SetVertexColor(0.05, 0.035, 0.03, 0.85)
    mark.t = mark:CreateTexture(nil, "ARTWORK")
    mark.t:SetPoint("TOPLEFT", 2, -2)
    mark.t:SetPoint("BOTTOMRIGHT", -2, 2)
    mark.t:SetTexture(NS.MEDIA .. "pin_bang.png")
    mark.t:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], 1)
    plates[unit] = mark
  end
  mark:SetParent(np)
  mark:ClearAllPoints()
  mark:SetPoint("LEFT", np, "RIGHT", -8, 0)
  mark:Show()
end
function Q.Plates()
  for unit in pairs(plates) do Plate(unit) end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(u) then Plate(u) end
  end
end
function Q.Wanted(id) return wantedNpc[id] end

---------------------------------------------------------------------------
-- Keeping it up to date
---------------------------------------------------------------------------
function Q.Refresh()
  if not Q.Shown() then NS.Safe("quest pins", Q.Draw) return end
  Q.BuildGivers(function() NS.Safe("quest pins", Q.Draw) end)
  NS.Safe("quest pins", Q.Draw)
end

-- what's drawn depends on this: which quests you have, and which of their parts are done
function Q.Signature()
  local parts = {}
  for _, q in ipairs(NS.Route.Quests()) do
    local f = {}
    for i, o in ipairs(q.objectives) do f[i] = o.finished and "1" or "0" end
    parts[#parts + 1] = q.id .. (q.complete and "c" or "") .. table.concat(f)
  end
  return table.concat(parts, ",")
end

function Q:Init()
  local drawn
  local function Soon()
    NS.Debounce("quest pins", 2.5, function()
      if not Q.Shown() then return end
      local sig = Q.Signature()
      if sig ~= drawn then drawn = sig; Q.Draw() end
    end)
  end
  local function All() NS.Debounce("quest pins all", 4, Q.Refresh) end
  NS.QuestsReady(function() C_Timer.After(10, function() NS.Safe("quest pins", Q.Refresh) end) end)
  NS.On("QUEST_LOG_UPDATE", Soon)
  NS.On("QUEST_ACCEPTED", All)
  NS.On("QUEST_REMOVED", All)
  NS.On("QUEST_TURNED_IN", All)
  NS.On("PLAYER_LEVEL_UP", All)
  NS.On("NAME_PLATE_UNIT_ADDED", function(unit) if type(unit) == "string" then NS.Safe("quest plates", Plate, unit) end end)
  NS.On("NAME_PLATE_UNIT_REMOVED", function(unit) local m = plates[unit] if m then m:Hide() end end)
end

NS.Setting("Quests on the map", "Quest icons", "Auto: on when Questie isn't installed, so nothing shows twice.", function()
  return ({ auto = "Auto", on = "On", off = "Off" })[Q.Mode()]
end, function() Q.SetMode(({ auto = "on", on = "off", off = "auto" })[Q.Mode()]) end)
for _, x in ipairs({ { "gives", "Quests to pick up", "An exclamation mark where someone has one for you." }, { "takes", "Where to hand in", "A question mark, bright when it's finished." },
                     { "wants", "What your quests want", "Marks on groups of creatures and things." }, { "mini", "On the minimap too", "The same marks, small." },
                     { "plates", "Nameplate marks", "Over creatures your quests want." } }) do
  NS.Setting("Quests on the map", x[2], x[3], function() return Part(x[1]) end, function(v) SetPart(x[1], v) end)
end
