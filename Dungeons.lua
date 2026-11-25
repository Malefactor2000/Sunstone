-- Sunstone: the Dungeons tab. Every dungeon and raid: levels, where the door is, quests to pick up first, keys, and each boss's
-- loot under its name, sorted by type (only the types it drops) with the chance of each. Two maps: the way there on the world
-- map, and the inside of the dungeon with the bosses marked, in Sunstone's own window.
-- Data: DungeonData.lua (OneForAll's, with permission; interior layouts by Tarolg, MIT; the pictures are the game's own).

local _, NS = ...
local Dg = NS.Module("Dungeons")
NS.Dungeons = Dg
local E = NS.Engine
local I = "Interface\\Icons\\"

local function Src() return type(_G.SunstoneDungeons) == "table" and _G.SunstoneDungeons or {} end
local function List(t) return type(t) == "table" and t or {} end
local function Level() return UnitLevel("player") or 1 end
local function Mine() return (UnitFactionGroup and UnitFactionGroup("player")) or "Horde" end

Dg.MODES = {
  { "dungeons", "Dungeons", "The ones for your level first" },
  { "raids", "Raids", "Every raid so far" },
}
function Dg.Mode()
  local m = NS.cdb and NS.cdb.dungeonMode
  for _, x in ipairs(Dg.MODES) do if x[1] == m then return x end end
  return Dg.MODES[1]
end
Dg.find = ""

function Dg.Get(name) for _, d in ipairs(List(Src().list)) do if d.n == name then return d end end end
function Dg.Map(d) return List(Src().maps)[d.n] end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------
-- what each item is worth to you, from the upgrade scan: [item] = gain
local gains, gainsOf
local function Gain(id)
  local all = NS.Upgrades and NS.Upgrades.all
  if all ~= gainsOf then
    gains, gainsOf = {}, all
    for _, e in ipairs(all or {}) do
      if (e.gain or 0) > 0 and (not gains[e.id] or e.gain > gains[e.id]) then gains[e.id] = e.gain end
    end
  end
  return gains and gains[id] or nil
end
Dg.Gain = Gain
local function Usable(id)
  local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  if not (get and NS.Upgrades and NS.Upgrades.Can) then return true end
  local ok, _, _, _, _, _, c, sub = pcall(get, id)
  if not ok or (c ~= 2 and c ~= 4) or type(sub) ~= "number" then return true end
  local st = NS.Upgrades.Can(c, sub)
  return st ~= nil
end
function Dg.Chance(p)
  if not p then return "chance not known" end
  if p >= 10 then return string.format("%d%%", p + 0.5) elseif p >= 1 then return (string.format("%.1f%%", p):gsub("%.0%%", "%%%%")) end
  return string.format("%.2f%%", p)
end

-- rows for a list of loot: a small heading per type, its items under it. Returns how many are upgrades for you.
-- what your characters have seen on this boss's body: how many bodies, and how many of them had an item
local function Seen(npc)
  local m = npc and NS.db and NS.db.rec and type(NS.db.rec.mobs) == "table" and NS.db.rec.mobs[npc]
  if type(m) == "table" and type(m.l) == "number" and m.l > 0 then return m end
end
function Dg.LootRows(rows, loot, find, npc)
  local seen = Seen(npc)
  local types, last, ups = List(Src().types), nil, 0
  for _, l in ipairs(List(loot)) do
    local hit = not find or find == "" or l[2]:lower():find(find, 1, true) or (types[l[3]] or ""):lower():find(find, 1, true)
    if hit then
      if l[3] ~= last then
        last = l[3]
        rows[#rows + 1] = { t = "|cffb5a58d" .. (types[l[3]] or "Other") .. "|r", still = true, small = true }
      end
      local g = Gain(l[1])
      if g then ups = ups + 1 end
      local slot = l[4]
      local bits = { Dg.Chance(l[6]) }
      if seen then
        local got = type(seen.i) == "table" and tonumber(seen.i[l[1]]) or 0
        bits[#bits + 1] = string.format("yours: %d of %d", got, seen.l)
      end
      if slot and slot ~= "" and slot ~= "Miscellaneous" and slot ~= types[l[3]] then bits[#bits + 1] = slot end
      if g then bits[#bits + 1] = string.format("|cff8aa666upgrade for you (+%.1f)|r", g) end
      rows[#rows + 1] = { t = l[2], i = l[1], q = l[5], d = table.concat(bits, "  ·  "), ring = g and "good" or nil, dim = (not g and not Usable(l[1])) or nil }
    end
  end
  return ups
end

-- Chances are Classic's where a boss is Classic's; Forever added loot to some of them, which makes the old items rarer.
local function Mixed(loot)
  local known, new = 0, 0
  for _, l in ipairs(List(loot)) do if l[6] then known = known + 1 elseif l[1] > 200000 then new = new + 1 end end
  return known > 0 and new > 0
end

local AbilityRow -- (below)

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function Where(d) return d.m and E.Point(d.m, d.x / 100, d.y / 100) or nil end
local function Fit(d) -- how it fits your level
  local L = Level()
  if L < (d.lo > 0 and d.lo or d.min) - 1 then return "later", "for later" end
  if d.hi > 0 and L > d.hi then return "past", "below you now" end
  return "now", "in your range"
end

local function QuestRows(rows, d)
  local side = Mine():sub(1, 1)
  local _, class = UnitClass("player")
  local log = E.Log()
  local list = {}
  for _, x in ipairs(List(d.quests)) do
    local cls = x.cls and x.cls:upper()
    if (x[5] == "" or x[5] == side) and (not cls or cls:find(class or "?", 1, true)) then list[#list + 1] = x end
  end
  if #list == 0 then return end
  rows[#rows + 1] = { h = string.format("Quests to pick up first (%d)", #list) }
  local L = Level()
  for _, x in ipairs(list) do
    local done = E.Done(x[1])
    local state = done and "done" or log[x[1]] and "in your log" or (x[3] > L and ("from level " .. x[3])) or nil
    local p, _, who = nil, nil, nil
    if not done then
      local ok, a, b, c = pcall(E.QuestStart, x[1])
      if ok then p, who = a, c end
      if type(p) ~= "table" or not p.m then p = nil end
    end
    local bits = { x[6] }
    if x[7] ~= "" then bits[#bits + 1] = x[7] end
    if x.note then bits[#bits + 1] = x.note end
    local best
    for _, id in ipairs(List(x[8])) do local g = Gain(id); if g and (not best or g > best[2]) then best = { id, g } end end
    if best then bits[#bits + 1] = string.format("|cff8aa666Reward upgrade: %s (+%.1f)|r", E.ItemName(best[1]), best[2]) end
    rows[#rows + 1] = E.At({ t = x[4] .. (state and ("  (" .. state .. ")") or ""), d = table.concat(bits, "\n"), dim = (done or x[3] > L) and true or nil,
                             ring = log[x[1]] and "good" or nil, page = NS.QuestFind and function() return NS.QuestFind.Page(x[1]) end or nil }, p)
  end
end

local function KeyRows(rows, d)
  for _, k in ipairs(List(d.keys)) do
    rows[#rows + 1] = { h = (k[3] and "You need: " or "Useful: ") .. k[2] }
    rows[#rows + 1] = { t = k[4], i = k[1] > 0 and k[1] or nil, d = (k[1] > 0 and E.Have(k[1]) > 0) and "You have it." or nil, still = true }
    for n, s in ipairs(List(k[5])) do
      rows[#rows + 1] = { t = n .. ". " .. s[1], d = s[2] .. (s[3] ~= "" and ("\n" .. s[3]) or ""), still = true }
    end
  end
end

function Dg.Page(d)
  local rows, L = {}, Level()
  local fit, words = Fit(d)
  local p = Where(d)
  local top = d.lo > 0 and string.format("Levels %d-%d", d.lo, d.hi) or (d.min > 0 and ("Level " .. d.min) or "Levels not known")
  rows[1] = { t = top .. "  ·  " .. words, ring = fit == "now" and "good" or nil, still = true,
              d = d.loc .. (p and ("\n" .. E.PlaceText(p)) or "") .. (d.desc ~= "" and ("\n" .. d.desc) or "") .. (d.status and ("\n" .. d.status) or "") .. (d.new and "\nNew in Forever." or "")
                .. (d.side and d.side ~= "Contested" and d.side ~= Mine() and d.side ~= "Both" and ("\nIt's in " .. d.side .. " territory.") or ""),
              m = p and p.m, x = p and p.x, y = p and p.y }
  local ups = {}
  for _, b in ipairs(List(d.bosses)) do
    for _, l in ipairs(List(b.loot)) do local g = Gain(l[1]); if g then ups[#ups + 1] = { l, b.n, g } end end
  end
  if #ups > 0 then
    table.sort(ups, function(a, b) return a[3] > b[3] end)
    rows[#rows + 1] = { h = string.format("Upgrades for you here (%d)", #ups) }
    for k = 1, math.min(6, #ups) do
      local u = ups[k]
      rows[#rows + 1] = { t = u[1][2], i = u[1][1], q = u[1][5], ring = "good", d = string.format("%s  ·  %s  ·  +%.1f", u[2], Dg.Chance(u[1][6]), u[3]) }
    end
  end
  QuestRows(rows, d)
  KeyRows(rows, d)
  local n = #List(d.bosses)
  if n > 0 and NS.Look then table.insert(rows, 2, Dg.Gallery(d)) end
  if n > 0 then rows[#rows + 1] = { h = string.format("Bosses and their loot (%d)", n) } end
  for k, b in ipairs(List(d.bosses)) do
    local bits = {}
    if b.lv then bits[#bits + 1] = "Level " .. b.lv end
    local _, kind = Dg.Abilities(b.npc)
    if kind then bits[#bits + 1] = kind end
    local body = Seen(b.npc)
    if body then bits[#bits + 1] = string.format("looted %d time%s by your characters", body.l, body.l == 1 and "" or "s") end
    if b.rare then bits[#bits + 1] = "rare: not always there" end
    if #List(b.loot) == 0 then bits[#bits + 1] = "no loot recorded" end
    if Mixed(b.loot) then bits[#bits + 1] = "Classic's chances: Forever added loot here, so the old items drop less" end
    rows[#rows + 1] = { t = string.format("|cffc99734%d. %s|r", k, b.n), d = table.concat(bits, "  ·  ") .. (b.desc and ("\n" .. b.desc) or ""), still = true, face = b.npc, tex = I .. "INV_Misc_Bone_HumanSkull_01" }
    AbilityRow(rows, b)
    Dg.LootRows(rows, b.loot, nil, b.npc)
  end
  if d.trash and #d.trash > 0 then
    rows[#rows + 1] = { h = "Dropped by the rest" }
    Dg.LootRows(rows, d.trash)
  end
  if d.m and NS.Travel and NS.Travel.Directions then
    local ok, dir = pcall(NS.Travel.Directions, { kind = "point", m = d.m, x = d.x, y = d.y, name = d.n .. " (entrance)" })
    if ok and type(dir) == "table" and #dir > 0 then
      rows[#rows + 1] = { h = "Getting there" }
      for _, r in ipairs(dir) do
        if r.h then rows[#rows + 1] = { t = r.h, still = true, dim = true } else rows[#rows + 1] = r end
      end
    end
  end
  rows[#rows + 1] = { t = "About the chances", d = "Classic's, or Forever's own for its new dungeons, where somebody has counted enough kills. \"Chance not known\" means nobody has yet.", still = true, dim = true }
  return { title = d.n, icon = d.icon ~= "" and d.icon or I .. "INV_Misc_Key_10", rows = rows,
           sub = (d.raid and ("Raid" .. (d.size and (", " .. d.size .. " players") or "")) or "Dungeon, 5 players") .. "  ·  " .. top,
           maps = { d.m and function() Dg.World(d) end or nil, Dg.Map(d) and function() return Dg.ShowMap(d) end or nil } }
end

---------------------------------------------------------------------------
-- The bosses as pictures: one in 3D, all their faces to pick from, and what the picked one drops
---------------------------------------------------------------------------
local pickOf = {}
function Dg.Gallery(d)
  return { panel = { key = "bosses", d = d,
    make = function(row)
      local f = CreateFrame("Frame", nil, row)
      f.bg = NS.Rounded(f, NS.C.surface, "round.png", 10)
      f.view = NS.Look.Model(f, 230, 214)
      f.view:SetPoint("TOPLEFT", 10, -10)
      f.name = NS.Look.Text(f, "GameFontNormalLarge", NS.C.accent)
      f.name:SetPoint("TOPLEFT", f.view, "TOPRIGHT", 14, -2)
      f.name:SetPoint("RIGHT", -10, 0)
      f.sub = NS.Look.Text(f, "GameFontHighlightSmall", NS.C.dim)
      f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
      f.sub:SetPoint("RIGHT", -10, 0)
      f.faces, f.loot = {}, {}
      f.lootHead = NS.Look.Text(f, "GameFontHighlightSmall", NS.C.accent)
      return f
    end,
    update = function(f, width, p)
      local d2, Lk = p.d, NS.Look
      local bosses = List(d2.bosses)
      local pick = math.min(pickOf[d2.n] or 1, #bosses)
      local b = bosses[pick]
      f.view.art:Set("Interface\\TalentFrame\\WarlockDestruction-", 0.4)
      f.view:Show1({ npc = b.npc, icon = I .. "INV_Misc_Bone_HumanSkull_01" })
      f.name:SetText(b.n)
      local _, kind = Dg.Abilities(b.npc)
      f.sub:SetText(table.concat({ b.lv and ("Level " .. b.lv) or "", kind or "", b.rare and "rare: not always there" or "" }, "  "):gsub("^%s+", ""))
      local x0 = 10 + 230 + 14
      local sz, gap = 36, 6
      local cols = math.max(1, math.floor((width - x0 - 10 + gap) / (sz + gap)))
      for k, e in ipairs(bosses) do
        local c = f.faces[k]
        if not c then c = Lk.Icon(f, sz); f.faces[k] = c end
        c:Set(I .. "INV_Misc_Bone_HumanSkull_01", true, e.npc)
        c.edge:SetColor(k == pick and Lk.GOLD or NS.C.border)
        c.edge:Thick(k == pick and 2 or 1)
        c.num:SetText(k)
        c.about = function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); Lk.TipLine(k .. ". " .. e.n, NS.C.accent); if e.lv then Lk.TipLine("Level " .. e.lv) end end
        c:SetScript("OnClick", function() pickOf[d2.n] = k; NS.Window.Redo() end)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", x0 + ((k - 1) % cols) * (sz + gap), -54 - math.floor((k - 1) / cols) * (sz + gap))
        c:Show()
      end
      for k = #bosses + 1, #f.faces do f.faces[k]:Hide() end
      local y = -54 - math.ceil(#bosses / cols) * (sz + gap) - 6
      local loot = List(b.loot)
      f.lootHead:ClearAllPoints()
      f.lootHead:SetPoint("TOPLEFT", x0, y)
      f.lootHead:SetText(#loot > 0 and "Drops (click one for everything about it)" or "")
      for k, l in ipairs(loot) do
        local c = f.loot[k]
        if not c then c = Lk.Icon(f, 32); f.loot[k] = c end
        c.item = l[1]
        c:Set(NS.ItemIcon(l[1]))
        c.edge:SetColor(Lk.QUALITY[l[5] or 1] or NS.C.border)
        local g = Gain(l[1])
        c:Badge(g and "up" or nil)
        c.about = function() Lk.TipLine(Dg.Chance(l[6]), NS.C.dim) end
        c:SetScript("OnClick", function() GameTooltip:Hide(); NS.Window.OpenItem(l[1]) end)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", x0 + ((k - 1) % cols) * 42, y - 18 - math.floor((k - 1) / cols) * 38)
        c:Show()
      end
      for k = #loot + 1, #f.loot do f.loot[k]:Hide() end
      return math.max(234, -y + 18 + math.ceil(#loot / cols) * 38 + 8)
    end } }
end

function Dg.Rows()
  local raid = Dg.Mode()[1] == "raids"
  local find = (Dg.find or ""):lower()
  local rows, groups = {}, { now = {}, later = {}, past = {} }
  local types = List(Src().types)
  for _, d in ipairs(List(Src().list)) do
    if (d.raid and true or false) == raid then
      local hit = find == "" or d.n:lower():find(find, 1, true) or d.loc:lower():find(find, 1, true)
      local extra
      if not hit then
        for _, b in ipairs(List(d.bosses)) do
          if b.n:lower():find(find, 1, true) then hit, extra = true, b.n break end
          for _, l in ipairs(List(b.loot)) do
            if l[2]:lower():find(find, 1, true) then hit, extra = true, l[2] .. " (" .. b.n .. ")" break end
          end
          if hit then break end
        end
      end
      if hit then
        local fit = Fit(d)
        local ups = 0
        for _, b in ipairs(List(d.bosses)) do for _, l in ipairs(List(b.loot)) do if Gain(l[1]) then ups = ups + 1 end end end
        local bits = { d.lo > 0 and string.format("%d-%d", d.lo, d.hi) or ("level " .. d.min), extra or d.loc }
        if ups > 0 then bits[#bits + 1] = string.format("|cff8aa666%d upgrade%s|r", ups, ups == 1 and "" or "s") end
        table.insert(groups[fit], { t = d.n .. (d.new and "  |cff8f7d68new|r" or ""), d = table.concat(bits, "  ·  "), tex = d.icon ~= "" and d.icon or I .. "INV_Misc_Key_10",
                                    key = "dg" .. d.n, dim = fit ~= "now" or nil, away = (d.side == "Alliance" or d.side == "Horde") and d.side ~= Mine() and 1 or 0, page = function() return Dg.Page(d) end })
      end
    end
  end
  for _, g in ipairs({ { "now", "In your level range" }, { "later", "For later" }, { "past", "Below you now" } }) do
    if #groups[g[1]] > 0 then
      rows[#rows + 1] = { h = g[2] }
      -- yours first; the ones in the other side's towns and zones after them
      for away = 0, 1 do for _, r in ipairs(groups[g[1]]) do if r.away == away then rows[#rows + 1] = r end end end
    end
  end
  if #rows == 0 then rows[1] = { t = "Nothing matches", d = "Try a dungeon, a boss, an item or a zone.", still = true } end
  return rows
end

-- what a boss does: its spells by the game's own names (Classic's list; ones the game doesn't know are left out), with a hint each
function Dg.Abilities(npc)
  local e = npc and type(_G.SunstoneBosses) == "table" and _G.SunstoneBosses[npc]
  local out, seen = {}, {}
  for _, x in ipairs(e and List(e.s) or {}) do
    local ok, name = pcall(NS.SpellName, x[1])
    if ok and type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      out[#out + 1] = { id = x[1], n = name, hint = x[2] }
    end
  end
  return out, e and e.k ~= "" and e.k or nil
end
function AbilityRow(rows, b)
  local list = Dg.Abilities(b.npc)
  if #list == 0 then return end
  local names, hints = {}, {}
  for _, a in ipairs(list) do
    names[#names + 1] = a.n
    if a.hint and #hints < 3 then hints[#hints + 1] = a.n .. ": " .. a.hint end
  end
  rows[#rows + 1] = { t = "What it does: " .. table.concat(names, ", "), d = #hints > 0 and table.concat(hints, ".  ") .. "." or nil, spell = list[1].id, key = "does" .. b.npc,
                      page = function()
                        local r = {}
                        for _, a in ipairs(list) do
                          r[#r + 1] = { t = a.n, d = a.hint and (a.hint:gsub("^%l", string.upper) .. ".") or "Hover for what the game says about it.", spell = a.id, still = true,
                                        tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(a.id) or nil }
                        end
                        r[#r + 1] = { t = "From Classic", d = "The list is Classic's; names and descriptions are this game's own. Forever may have changed or added some.", dim = true, still = true }
                        return { title = b.n, rows = r, sub = "What it does", icon = I .. "INV_Misc_Bone_HumanSkull_01" }
                      end }
end

-- its page, in the window
function Dg.Open(d)
  NS.cdb.dungeonMode = d.raid and "raids" or "dungeons"
  NS.Window.Open("dungeons")
  NS.Window.OpenPage(function() return Dg.Page(d) end)
end

---------------------------------------------------------------------------
-- Map 1: the way there, on the world map (with the arrow and the trail)
---------------------------------------------------------------------------
function Dg.World(d)
  if not d.m then return end
  local V, T = NS.MapView, NS.Travel
  local p = E.Point(d.m, d.x / 100, d.y / 100)
  V.trip = { m = d.m, x = d.x / 100, y = d.y / 100, wx = p.wx, wy = p.wy, inst = p.inst, name = d.n }
  NS.Arrow.Go(d.m, d.x / 100, d.y / 100, d.n)
  -- your own zone's map when the door is in it, else the continent, so the whole way shows
  local here = T and T.Here and T.Here()
  local id = d.m
  if here and here.m ~= d.m then
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(here.m)
    if here.inst == p.inst and info and info.parentMapID and info.parentMapID > 0 then id = info.parentMapID else id = here.m end
  end
  if InCombatLockdown and InCombatLockdown() then
    NS.Print("the way to " .. d.n .. " is on your world map (the game doesn't let addons open it in combat).")
  else
    if WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
    if WorldMapFrame and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, id) end
  end
  NS.Safe("map line", V.DrawRoute)
  NS.Print("the way to " .. d.n .. " is drawn on the world map. Re-plan on the Route tab goes back to your quests.")
end

function Dg.Arrived() -- at the door (or gone inside): the line has done its job
  local V = NS.MapView
  local t = V and V.trip
  if not t then return end
  local hbd = NS.HBD()
  local wx, wy, inst
  if hbd then wx, wy, inst = hbd:GetPlayerWorldPosition() end
  if (IsInInstance and IsInInstance()) or (wx and t.wx and inst == t.inst and (wx - t.wx) ^ 2 + (wy - t.wy) ^ 2 < 60 * 60) then
    V.trip = nil
    NS.Safe("map line", V.DrawRoute)
  end
end

---------------------------------------------------------------------------
-- Map 2: inside the dungeon, over most of Sunstone's window
---------------------------------------------------------------------------
local view
-- corners of a picture turned by quarter turns: upper left, lower left, upper right, lower right
local TURN = { [0] = { 0, 0, 0, 1, 1, 0, 1, 1 }, { 1, 0, 0, 0, 1, 1, 0, 1 }, { 1, 1, 1, 0, 0, 1, 0, 0 }, { 0, 1, 1, 1, 0, 0, 1, 0 } }
local SIDE = 190 -- the list of bosses beside the map

local function PinTip(pin)
  local b = pin.boss
  if not (b and GameTooltip) then return end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  if type(b) == "string" then
    GameTooltip:AddLine(b, 0.54, 0.75, 0.44)
  else
    GameTooltip:AddLine(string.format("%d. %s", pin.n, b.n), 0.79, 0.59, 0.2)
    if b.lv then GameTooltip:AddLine("Level " .. b.lv .. (b.rare and ", rare" or ""), 0.7, 0.66, 0.58) end
    local types, last, shown = List(Src().types), nil, 0
    for _, l in ipairs(List(b.loot)) do
      shown = shown + 1
      if shown > 16 then GameTooltip:AddLine("and more: see its list", 0.6, 0.57, 0.5) break end
      if l[3] ~= last then last = l[3]; GameTooltip:AddLine(types[last] or "Other", 0.71, 0.65, 0.55) end
      local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[l[5]] or { r = 0.86, g = 0.85, b = 0.81 }
      GameTooltip:AddDoubleLine("  " .. l[2], l[6] and Dg.Chance(l[6]) or "?", c.r, c.g, c.b, 0.86, 0.85, 0.81)
    end
  end
  GameTooltip:Show()
end

local function Num(v, default) return type(v) == "number" and v or default end

local function Place()
  local v = view
  local s = v.fit * v.zoom
  v.canvas:SetSize(v.map.w * s, v.map.h * s)
  v.canvas:ClearAllPoints()
  v.canvas:SetPoint("CENTER", v.vp, "CENTER", v.ox, v.oy)
  for k = 1, v.used do
    local x = v.tex[k]
    x:SetSize(x.w * s, x.h * s)
    x:ClearAllPoints()
    x:SetPoint("CENTER", v.canvas, "TOPLEFT", x.u * s, -x.v * s)
  end
  for k = 1, v.pinsUsed do
    local p = v.pins[k]
    p:ClearAllPoints()
    p:SetPoint("CENTER", v.canvas, "TOPLEFT", p.u * s, -p.v * s)
  end
end

local function Zoom(delta)
  local old = view.zoom
  view.zoom = math.max(1, math.min(8, old * (delta > 0 and 1.25 or 0.8)))
  local k = view.zoom / old
  view.ox, view.oy = view.ox * k, view.oy * k
  if view.zoom == 1 then view.ox, view.oy = 0, 0 end
  Place()
end

local function Make()
  local parent = _G.SunstoneMainFrame
  local f = CreateFrame("Frame", "SunstoneDungeonMap", parent)
  f:SetPoint("TOPLEFT", 8, -8)
  f:SetPoint("BOTTOMRIGHT", -8, 8)
  f:SetFrameLevel(Num(parent:GetFrameLevel(), 1) + 60)
  f:EnableMouse(true)
  NS.Rounded(f, NS.C.bg, "round.png", 10)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 14, -12)
  f.title:SetTextColor(unpack(NS.C.accent))
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.hint:SetPoint("TOPLEFT", 14, -32)
  f.hint:SetTextColor(unpack(NS.C.dim))
  f.hint:SetText("Wheel: zoom. Drag: move. Hover a number for its loot.")
  f.close = NS.Button(f, "Close map", 84, function() f:Hide() end)
  f.close:SetPoint("TOPRIGHT", -12, -12)
  local vp = CreateFrame("Frame", nil, f)
  vp:SetPoint("TOPLEFT", 10, -50)
  vp:SetPoint("BOTTOMRIGHT", -(SIDE + 20), 10)
  if vp.SetClipsChildren then vp:SetClipsChildren(true) end
  vp:EnableMouse(true)
  if vp.EnableMouseWheel then vp:EnableMouseWheel(true) end
  local bg = vp:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.03, 0.035, 1)
  f.vp, f.canvas = vp, CreateFrame("Frame", nil, vp)
  f.tex, f.pins, f.used, f.pinsUsed, f.rows = {}, {}, 0, 0, {}
  vp:SetScript("OnMouseWheel", function(_, delta) Zoom(delta) end)
  vp:SetScript("OnMouseDown", function()
    if not GetCursorPosition then return end
    local x, y = GetCursorPosition()
    local sc = Num(vp.GetEffectiveScale and vp:GetEffectiveScale(), 1)
    f.drag = { x / sc, y / sc, view.ox, view.oy }
    vp:SetScript("OnUpdate", function()
      local cx, cy = GetCursorPosition()
      view.ox, view.oy = f.drag[3] + cx / sc - f.drag[1], f.drag[4] + cy / sc - f.drag[2]
      Place()
    end)
  end)
  vp:SetScript("OnMouseUp", function() vp:SetScript("OnUpdate", nil) end)
  f:SetScript("OnHide", function() vp:SetScript("OnUpdate", nil) end)
  f.side = CreateFrame("Frame", nil, f)
  f.side:SetPoint("TOPRIGHT", -10, -50)
  f.side:SetPoint("BOTTOMRIGHT", -10, 10)
  f.side:SetWidth(SIDE)
  NS.Rounded(f.side, NS.C.panel, "round.png", 8)
  -- Esc closes the map first, then the window
  f:EnableKeyboard(true)
  if f.SetPropagateKeyboardInput then
    f:SetScript("OnKeyDown", function(self, key)
      local esc = key == "ESCAPE"
      if not (InCombatLockdown and InCombatLockdown()) then self:SetPropagateKeyboardInput(not esc) end
      if esc then self:Hide() end
    end)
  else
    f:EnableKeyboard(false)
  end
  f:Hide()
  return f
end

local function Picture(k, file, layer, sub, u, v, w, h, turn, rot, shade)
  local x = view.tex[k]
  if not x then
    x = view.canvas:CreateTexture(nil, layer, nil, sub)
    view.tex[k] = x
  end
  x:SetDrawLayer(layer, sub)
  if x.SetRotation then x:SetRotation(0) end
  x:SetTexture(file)
  local c = TURN[turn or 0]
  x:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
  if rot and x.SetRotation then x:SetRotation(rot) end
  x:SetVertexColor(shade, shade, shade, 1)
  x.u, x.v, x.w, x.h = u, v, w, h
  x:Show()
end

local function PinAt(k)
  local p = view.pins[k]
  if p then return p end
  p = CreateFrame("Frame", nil, view.canvas)
  p:SetSize(18, 18)
  p:SetFrameLevel(Num(view.canvas:GetFrameLevel(), 1) + 5)
  p.ring = p:CreateTexture(nil, "BACKGROUND")
  p.ring:SetAllPoints()
  p.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  p.disc = p:CreateTexture(nil, "BORDER")
  p.disc:SetPoint("TOPLEFT", 2, -2)
  p.disc:SetPoint("BOTTOMRIGHT", -2, 2)
  p.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  p.disc:SetVertexColor(0.07, 0.06, 0.05, 1)
  p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  p:EnableMouse(true)
  p:SetScript("OnEnter", PinTip)
  p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  view.pins[k] = p
  return p
end

local function SetPin(k, boss, n, u, v)
  local p = PinAt(k)
  p.boss, p.n, p.u, p.v = boss, n, u, v
  local door = type(boss) == "string"
  p.num:SetText(door and "E" or tostring(n))
  local rare = not door and boss.rare
  if door then p.ring:SetVertexColor(0.54, 0.75, 0.44, 1) elseif rare then p.ring:SetVertexColor(0.65, 0.68, 0.75, 1) else p.ring:SetVertexColor(0.79, 0.35, 0.28, 1) end
  p:Show()
  return p
end

function Dg.ShowMap(d)
  local map = Dg.Map(d)
  if not (map and _G.SunstoneMainFrame) then return false end
  view = view or Make()
  local v = view
  v.map, v.d, v.zoom, v.ox, v.oy = map, d, 1, 0, 0
  v.title:SetText(d.n)
  v:Show()
  local w, h = Num(v.vp:GetWidth(), 0), Num(v.vp:GetHeight(), 0)
  if w < 50 or h < 50 then w, h = 640, 440 end
  v.fit = math.min(w / map.w, h / map.h)
  v.used, v.pinsUsed = 0, 0
  for _, g in ipairs(List(map.ground)) do
    v.used = v.used + 1
    Picture(v.used, g[1], "BACKGROUND", 1, g[2], g[3], 1600 / 3, 1600 / 3, 0, nil, map.bright == 1 and 0.85 or map.bright or 0.3)
  end
  for _, t in ipairs(List(map.tiles)) do
    v.used = v.used + 1
    Picture(v.used, t[1], "ARTWORK", t[7] or 0, t[2], t[3], t[4], t[5], t[6], t[8], 1)
  end
  for k = v.used + 1, #v.tex do v.tex[k]:Hide() end
  -- the bosses, numbered as in the list; those without a known spot are only listed
  local spot = {}
  for _, e in ipairs(List(map.bosses)) do spot[e[1]] = e end
  if map.door then
    v.pinsUsed = v.pinsUsed + 1
    SetPin(v.pinsUsed, "Entrance", 0, map.door[1], map.door[2])
  end
  local line, y = 0, -10
  local function Row(text, boss, pin)
    line = line + 1
    local r = v.rows[line]
    if not r then
      r = CreateFrame("Button", nil, v.side)
      r:SetSize(SIDE - 16, 18)
      r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.text:SetPoint("LEFT", 4, 0)
      r.text:SetPoint("RIGHT", -2, 0)
      r.text:SetJustifyH("LEFT")
      if r.text.SetWordWrap then r.text:SetWordWrap(false) end
      r:SetScript("OnEnter", function(self)
        if self.pin then self.pin:SetScale(1.5) end
        if self.boss then PinTip(self) end
      end)
      r:SetScript("OnLeave", function(self)
        if self.pin then self.pin:SetScale(1) end
        if GameTooltip then GameTooltip:Hide() end
      end)
      v.rows[line] = r
    end
    r.boss, r.pin, r.n = boss, pin, pin and pin.n or 0
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 8, y)
    y = y - 18
    r.text:SetText(text)
    r:Show()
    return r
  end
  if map.door then Row("|cff8abf70E|r  Entrance", nil, v.pins[1]) end
  for k, b in ipairs(List(d.bosses)) do
    local e = spot[b.n]
    local pin
    if e then
      v.pinsUsed = v.pinsUsed + 1
      pin = SetPin(v.pinsUsed, b, k, e[2], e[3])
    end
    local r = Row(string.format("|cffc99734%d|r  %s%s", k, b.n, e and (b.rare and "  |cff9a968crare|r" or "") or "  |cff7a756c(spot not known)|r"), b, pin)
    r.n = k
  end
  for k = line + 1, #v.rows do v.rows[k]:Hide() end
  for k = v.pinsUsed + 1, #v.pins do v.pins[k]:Hide() end
  Place()
  return true
end
function Dg.HideMap() if view then view:Hide() end end
function Dg.View() return view end

function Dg:Init()
  C_Timer.NewTicker(5, function() NS.Safe("dungeon trip", Dg.Arrived) end)
end
