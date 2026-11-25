-- Sunstone: the talent trees as pictures on the Talents tab. Your own trees as the game lays them out, what you've taken, what the plan takes
-- and what comes next (gold), and on hover what one more point would do to your spells and stats, in numbers. Information only: it never
-- spends a point.

local _, NS = ...
local TT = {}
NS.TalentTree = TT
local Lk, C = NS.Look, NS.C
local I = "Interface\\Icons\\"
local function List(t) return type(t) == "table" and t or {} end
local function Num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v or nil end

-- The trees' parts -> { { id, x, y, name, spell, icon, rank, max, edges = { node, ... } }, ... }
function TT.Nodes()
  local out = {}
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return out end
  local ok, config = pcall(C_ClassTalents.GetActiveConfigID)
  local ci = ok and config and C_Traits.GetConfigInfo(config)
  for _, tree in ipairs(ci and ci.treeIDs or {}) do
    for _, id in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
      local ni = C_Traits.GetNodeInfo(config, id)
      local x, y = ni and Num(ni.posX), ni and Num(ni.posY)
      if ni and ni.isVisible ~= false and x and y then
        local entry = ni.activeEntry
        if type(entry) == "table" then entry = entry.entryID end
        if not entry and ni.entryIDs then entry = ni.entryIDs[1] end
        local ei = entry and C_Traits.GetEntryInfo(config, entry)
        local di = ei and ei.definitionID and C_Traits.GetDefinitionInfo(ei.definitionID)
        local spell = di and (di.spellID or di.overriddenSpellID)
        local name = di and (di.overrideName or (spell and NS.SpellName(spell)))
        if name and name ~= "" then
          local icon = di.overrideIcon or (spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)) or (spell and GetSpellTexture and GetSpellTexture(spell))
          local edges = {}
          for _, e in ipairs(List(ni.visibleEdges)) do if type(e) == "table" and e.targetNode then edges[#edges + 1] = e.targetNode end end
          out[#out + 1] = { id = id, x = x, y = y, name = name, spell = spell, icon = icon, rank = Num(ni.currentRank) or Num(ni.ranksPurchased) or 0, max = Num(ni.maxRanks) or 1, edges = edges, tree = tree }
        end
      end
    end
  end
  return out
end

-- Where each goes on a sheet so wide: the game's own places, drawn to size. Trees of one config can lie over each other: then they're put side by side.
function TT.Layout(nodes, width)
  local trees, order = {}, {}
  for _, n in ipairs(nodes) do
    local t = trees[n.tree]
    if not t then t = { x0 = n.x, x1 = n.x, y0 = n.y, y1 = n.y, list = {} }; trees[n.tree] = t; order[#order + 1] = t end
    t.x0, t.x1 = math.min(t.x0, n.x), math.max(t.x1, n.x)
    t.y0, t.y1 = math.min(t.y0, n.y), math.max(t.y1, n.y)
    t.list[#t.list + 1] = n
  end
  if #order == 0 then return 0 end
  -- one tree may hold all three side by side; several trees share one set of places
  local ys = {}
  for _, n in ipairs(nodes) do ys[math.floor(n.y / 50 + 0.5)] = true end
  local lines = {}
  for k in pairs(ys) do lines[#lines + 1] = k end
  table.sort(lines)
  local row = {}
  for k, v in ipairs(lines) do row[v] = k end
  local size = 30
  local part = width / #order
  for k, t in ipairs(order) do
    local span = math.max(1, t.x1 - t.x0)
    local room = part - size - 24
    for _, n in ipairs(t.list) do
      n.px = (k - 1) * part + 12 + (span > 1 and (n.x - t.x0) / span * room or room / 2)
      n.py = 10 + (row[math.floor(n.y / 50 + 0.5)] - 1) * 43
    end
  end
  return 10 + #lines * 43
end

-- what the plan wants of each talent by name: { [name] = { now = ranks by your level, all = ranks in the end, at = next level } }
local function Plan()
  local plan = NS.ActivePlan and NS.ActivePlan()
  local out, nextName = {}, nil
  if not plan then return out end
  local L = UnitLevel("player") or 1
  local ranks = NS.Talents.Read() or {}
  for lvl = 10, 60 do
    local s = plan.steps[lvl]
    if s then
      local k = s[1]:lower()
      local e = out[k] or { now = 0, all = 0 }
      out[k] = e
      e.all = math.max(e.all, s[2])
      if lvl <= L then e.now = math.max(e.now, s[2]) end
      if (ranks[k] or 0) < s[2] then
        if not e.at then e.at = lvl end
        if not nextName then nextName = k end
      end
    end
  end
  return out, nextName
end

local function Tip(b)
  local n, e = b.node, b.plan
  if not b.spell then GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); Lk.TipLine(n.name, C.accent) end
  Lk.TipLine(" ")
  Lk.TipLine(string.format("%d of %d taken", n.rank, n.max), C.accent)
  if e then
    Lk.TipLine(string.format("Sunstone's plan takes %d of it%s.", e.all, e.at and (", the next at level " .. e.at) or ""), e.at and C.text or C.good)
  else
    Lk.TipLine("Not in Sunstone's plan for your goal.", C.dim)
  end
  local CS = NS.CharSheet
  if CS and n.spell and n.rank < n.max then
    local ok, out, sp = pcall(CS.TalentChange, n.spell, n.rank + 1)
    if ok and type(out) == "table" and (#out > 0 or #sp > 0) then
      Lk.TipLine("One more point would give you:", C.accent)
      for k = 1, math.min(6, #out) do Lk.TipLine(out[k][1], C.good, false) end
      for k = 1, math.min(8, #sp) do Lk.TipLine(string.format("%s: %+.1f a cast (%+.1f%%)", sp[k][1], sp[k][2], sp[k][3]), C.good, false) end
    end
  end
end

local function Make(row)
  local p = CreateFrame("Frame", nil, row)
  p.bg = NS.Rounded(p, C.surface, "round.png", 10)
  p.icons, p.lines = {}, {}
  p.note = Lk.Text(p, "GameFontHighlightSmall", C.dim)
  p.note:SetPoint("BOTTOMLEFT", 12, 8)
  return p
end

local function Update(p, width)
  local nodes = TT.Nodes()
  local h = TT.Layout(nodes, width)
  local plan, nextName = Plan()
  local byId = {}
  for _, n in ipairs(nodes) do byId[n.id] = n end
  local li = 0
  for k, n in ipairs(nodes) do
    local b = p.icons[k]
    if not b then
      b = Lk.Icon(p, 30)
      b.about = Tip
      p.icons[k] = b
    end
    local e = plan[n.name:lower()]
    b.node, b.plan, b.spell = n, e, n.spell
    b:Set(n.icon or NS.QUESTION_ICON)
    b:Dim(n.rank == 0 and not e)
    b.tex:SetAlpha(n.rank > 0 and 1 or e and 0.75 or 0.35)
    b.num:SetText(n.rank .. "/" .. ((e and e.all > 0 and e.all) or n.max))
    local isNext = nextName == n.name:lower()
    local col = isNext and Lk.GOLD or n.rank >= n.max and n.max > 0 and Lk.GOLD or n.rank > 0 and C.good or (e and { 0.55, 0.42, 0.20 }) or C.border
    b.edge:SetColor(col)
    b.edge:Thick((isNext or n.rank > 0) and 2 or 1)
    b.num:SetTextColor(col[1], col[2], col[3])
    b:Badge(isNext and "star" or nil)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", n.px, -n.py)
    b:Show()
    for _, id in ipairs(n.edges) do
      local to = byId[id]
      if to then
        li = li + 1
        local l = p.lines[li]
        if not l and p.CreateLine then
          local ok, line = pcall(p.CreateLine, p, nil, "ARTWORK")
          if ok and line then
            l = line
            l:SetThickness(2)
            p.lines[li] = l
          end
        end
        if l then
          l:SetColorTexture(n.rank >= n.max and 0.75 or 0.35, n.rank >= n.max and 0.58 or 0.27, n.rank >= n.max and 0.2 or 0.15, 0.9)
          l:SetStartPoint("TOPLEFT", p, n.px + 15, -(n.py + 30))
          l:SetEndPoint("TOPLEFT", p, to.px + 15, -to.py)
          l:Show()
        end
      end
    end
  end
  for k = #nodes + 1, #p.icons do p.icons[k]:Hide() end
  for k = li + 1, #p.lines do p.lines[k]:Hide() end
  p.note:SetText("Gold star: take this next. The number: what you have of what the plan takes. Hover: what one more point does for you.")
  return h + 30
end

function TT.Row()
  if not Lk then return nil end
  local ok, nodes = pcall(TT.Nodes)
  if not ok or #nodes == 0 then return nil end
  return { panel = { key = "talenttree", make = Make, update = Update } }
end
