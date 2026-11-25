-- Sunstone: two pages of the Gear tab.
--   Enchants: what's on each thing you wear, and the enchants worth most to you for it, by your talent goal's stat weights; who
--   can make them (you, your other characters, or an enchanter) and what they take.
--   Sets: every item set your class can wear, what you have of it, its bonuses and where each piece comes from.
-- Data: SetData.lua (OneForAll's, with permission). Information only.

local _, NS = ...
local S = NS.Module("Sets")
NS.Sets = S
local E, U = NS.Engine, NS.Upgrades
local I = "Interface\\Icons\\"
local HEX = NS.HEX

local function Src() return type(_G.SunstoneSets) == "table" and _G.SunstoneSets or {} end
local function List(t) return type(t) == "table" and t or {} end
local function Level() return UnitLevel("player") or 1 end
local function Class() return select(2, UnitClass("player")) end

---------------------------------------------------------------------------
-- What stats are worth
---------------------------------------------------------------------------
local WEAPON_SPEED = { INVTYPE_2HWEAPON = 3.2, INVTYPE_RANGED = 2.8, INVTYPE_RANGEDRIGHT = 2.6 } -- typical seconds a swing, for flat weapon damage

function S.Worth(stats, equipLoc, kind)
  local w = U.Weights(Class(), Level())
  local total = U.StatsScore(stats, w)
  local flat = List(stats).WEAPON_DAMAGE
  if type(flat) == "number" then
    local dps = (kind == "ranged" and (w.dpsranged or w.dps)) or (kind == "melee" and (w.dpsmelee or w.dps)) or 0
    total = total + (dps or 0) * flat / (WEAPON_SPEED[equipLoc or ""] or 2.2)
  end
  return total
end

---------------------------------------------------------------------------
-- Enchants
---------------------------------------------------------------------------
local INV = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8,
              INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14, INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16,
              INVTYPE_2HWEAPON = 17, INVTYPE_ROBE = 20, INVTYPE_WEAPONMAINHAND = 21, INVTYPE_WEAPONOFFHAND = 22, INVTYPE_RANGEDRIGHT = 26 }
local SLOTS = { { 1, "Head" }, { 3, "Shoulders" }, { 5, "Chest" }, { 15, "Back" }, { 9, "Wrists" }, { 10, "Hands" }, { 7, "Legs" }, { 8, "Feet" },
                { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" } }
local RANGED = { [2] = true, [3] = true, [16] = true, [18] = true }

local function Fits(o, classID, sub, inv)
  if o.c and o.c ~= classID then return false end
  if o.t and o.t ~= 0 and (not inv or math.floor(o.t / 2 ^ inv) % 2 ~= 1) then return false end
  if o.m and o.m ~= 0 and math.floor(o.m / 2 ^ sub) % 2 ~= 1 then return false end
  return true
end

local function Text(e)
  local x = List(Src().enchants)[e]
  return x and x[1] or ("enchant " .. tostring(e))
end

-- every enchant that fits what's in a slot, best first: { o, text, worth, special }, and what's on it now
function S.Options(slot)
  local link = GetInventoryItemLink("player", slot)
  if not link then return nil end
  local id, _, _, loc, _, classID, sub = NS.GetItemInfoInstant(link)
  local inv = INV[loc or ""]
  if not inv or (classID ~= 2 and classID ~= 4) then return nil end
  local kind = classID == 2 and (RANGED[sub] and "ranged" or sub ~= 19 and "melee") or nil
  local now = tonumber(link:match("item:%d+:(%d+)"))
  local cur = now and now > 0 and List(Src().enchants)[now]
  local out, best = {}, {}
  for _, o in ipairs(List(Src().options)) do
    local x = List(Src().enchants)[o.e]
    if x and Fits(o, classID, sub, inv) then
      local e = { o = o, text = x[1], worth = S.Worth(x[2], loc, kind), special = x[3] }
      local b = best[o.e] -- the same effect two ways: the one that takes less skill
      if not b or (o.req or 999) < (b.o.req or 999) then
        if b then for i, y in ipairs(out) do if y == b then table.remove(out, i) break end end end
        best[o.e] = e
        out[#out + 1] = e
      end
    end
  end
  table.sort(out, function(a, b)
    if a.worth ~= b.worth then return a.worth > b.worth end
    return (a.o.req or 0) < (b.o.req or 0)
  end)
  return out, { id = id, link = link, name = NS.GetItemInfo(link), enchant = now and now > 0 and now or nil, text = now and now > 0 and Text(now) or nil,
                worth = cur and S.Worth(cur[2], loc, kind) or 0, loc = loc }
end

-- who could make it: "you", another of yours, or nil
local function Maker(o)
  if not o.p then return nil end
  local mine = E.Skill(o.p)
  if mine and o.req and mine >= o.req then return "you" end
  for _, a in ipairs(E.AltsWith(o.p)) do if o.req and (a.rank or 0) >= o.req then return a.name end end
end

local function Sensible(o) -- one somebody near your level would have
  return (o.req or 0) <= math.max(60, Level() * 5 + 25) or Maker(o) ~= nil
end

local function OptionRow(e, cur, key)
  local o = e.o
  local who = Maker(o)
  local bits = {}
  if o.p then bits[#bits + 1] = string.format("%s%s", o.p, o.req and (" " .. o.req) or "") end
  if o.src then bits[#bits + 1] = o.src end
  bits[#bits + 1] = who == "you" and "you have the skill" or who and (who .. " has the skill") or nil
  local r = o.s and NS.Crafts and NS.Crafts.Recipe(o.s)
  local gain = e.worth - (cur and cur.worth or 0)
  return { t = e.text .. (e.worth > 0.05 and string.format("  |cff%s%s%.1f|r", gain > 0.05 and HEX.good or HEX.dim, gain >= 0 and "+" or "", gain) or ""),
           d = o.n .. (#bits > 0 and ("\n" .. table.concat(bits, ", ")) or "") .. (e.special and e.worth <= 0.05 and "\nAn effect the stat weights don't count." or ""),
           i = o.i or (r and r.i) or nil, tex = not (o.i or (r and r.i)) and I .. "Trade_Engraving" or nil, key = key .. o.n, dim = not Sensible(o) or nil,
           ring = who and gain > 0.05 and "good" or nil, page = r and function() return NS.Professions.RecipePage(r) end or nil }
end

local function SlotPage(slot, label)
  local opts, cur = S.Options(slot)
  local rows = {}
  if not opts then return { title = label, rows = { { t = "Nothing there to enchant", still = true } } } end
  rows[1] = { t = cur.text and ("On it now: " .. cur.text) or "No enchant on it", d = cur.name, i = cur.id, still = true }
  local near, far, fx = {}, {}, {}
  for _, e in ipairs(opts) do
    local l = e.worth <= 0.05 and e.special and fx or Sensible(e.o) and near or far
    l[#l + 1] = e
  end
  local function Put(h, list, n)
    if #list == 0 then return end
    rows[#rows + 1] = { h = h }
    for k = 1, math.min(n, #list) do rows[#rows + 1] = OptionRow(list[k], cur, "opt" .. slot) end
  end
  Put("Around your level, best for you first", near, 14)
  Put("Other effects (not counted in points)", fx, 12)
  Put("Higher up", far, 10)
  return { title = label .. ": enchants", icon = NS.ItemIcon(cur.id), rows = rows, sub = "What each is worth to you, by your talent goal" }
end

function S.EnchantRows()
  local rows, any = { { h = "What you wear" } }, false
  for _, s in ipairs(SLOTS) do
    local opts, cur = S.Options(s[1])
    if opts and #opts > 0 then
      any = true
      local best
      for _, e in ipairs(opts) do if Sensible(e.o) and e.worth - cur.worth > 0.05 then best = e break end end
      local who = best and Maker(best.o)
      rows[#rows + 1] = { t = s[2] .. (best and string.format("  |cff%s+%.1f|r", HEX.good, best.worth - cur.worth) or ""), i = cur.id, key = "ench" .. s[1], ring = who and "good" or nil,
                          d = (cur.text and ("Now: " .. cur.text) or "Not enchanted") .. (best and string.format("\nBest near your level: %s (%s%s)", best.text, best.o.p or best.o.src or "?",
                              best.o.req and (" " .. best.o.req) or "") .. (who and ("\n" .. (who == "you" and "You" or who) .. (who == "you" and " have" or " has") .. " the skill for it.") or "") or ""),
                          page = function() return SlotPage(s[1], s[2]) end }
    end
  end
  if not any then rows[#rows + 1] = { t = "Nothing you wear can be enchanted yet", still = true } end
  rows[#rows + 1] = { t = "Worth it while leveling?", dim = true, still = true,
                      d = "You'll replace most pieces within a few levels: cheap enchants on weapons, chest and legs pay off most. Keep dear ones for gear you'll wear a while." }
  return rows
end

---------------------------------------------------------------------------
-- Sets
---------------------------------------------------------------------------
local GROUP = { dungeon = "Dungeons", crafted = "Crafted", world = "World drops and others", raid = "Raids", pvp = "Honor" }
local GORDER = { "dungeon", "crafted", "world", "pvp", "raid" }

local function Usable(s)
  if s.cls and not s.cls[Class()] then return false end
  if s.side and s.side ~= E.Side() then return false end
  local arm = ({ Cloth = 1, Leather = 2, Mail = 3, Plate = 4 })[s.arm or ""]
  if arm and U.Can and not U.Can(4, arm) then return false end
  return true
end

local function Own(s)
  local n = 0
  for _, it in ipairs(s.i) do if E.Have(it[1]) > 0 then n = n + 1 end end
  return n
end

-- what its counted bonuses are worth, with all the pieces
local function BonusWorth(s)
  local v = 0
  for _, b in ipairs(List(s.s)) do v = v + S.Worth(b[2]) end
  return v
end

local function SetPage(s)
  local rows, own = {}, Own(s)
  local have = {}
  for _, b in ipairs(List(s.b)) do
    have[#have + 1] = { t = string.format("%d pieces: %s", b[1], b[2]), still = true, dim = own < b[1] or nil, ring = own >= b[1] and "good" or nil }
  end
  local worth = BonusWorth(s)
  rows[#rows + 1] = { h = string.format("Bonuses (you have %d of %d pieces)", own, #s.i) }
  for _, r in ipairs(have) do rows[#rows + 1] = r end
  if worth > 0.05 then rows[#rows + 1] = { t = string.format("All the stat bonuses together: worth %.1f to you", worth), dim = true, still = true } end
  rows[#rows + 1] = { h = "Pieces" }
  for _, it in ipairs(s.i) do
    local n = E.Have(it[1])
    local c = U.Compare and U.Compare("item:" .. it[1])
    local src = table.concat(List(it[5]), ", ")
    rows[#rows + 1] = { t = it[2] .. (n > 0 and "  (yours)" or ""), i = it[1], q = it[4], key = "piece" .. it[1], ring = n > 0 and "good" or nil,
                        d = (it[3] ~= "" and (it[3] .. "  ·  ") or "") .. (src ~= "" and src or "Where it comes from isn't known yet")
                            .. (c and not c.no and not c.worn and c.gain and c.gain > 0.05 and string.format("\n|cff%s+%.1f on what you wear|r", HEX.good, c.gain) or "") }
  end
  if s.st == 2 then rows[#rows + 1] = { t = "Where this set comes from isn't known yet on Forever", dim = true, still = true } end
  return { title = s.n, rows = rows, icon = NS.ItemIcon(s.i[1] and s.i[1][1]), sub = (GROUP[s.g] or "Set") .. (s.sub and ("  ·  " .. s.sub) or "") .. (s.arm and ("  ·  " .. s.arm) or "") }
end

function S.SetRows()
  local by, rows, lvl = {}, {}, Level()
  local started = {}
  for _, s in ipairs(List(Src().sets)) do
    if Usable(s) then
      local own = Own(s)
      local row = { t = s.n .. string.format("  %d / %d", own, #s.i), i = s.i[1] and s.i[1][1] or nil, q = s.i[1] and s.i[1][4] or nil, key = "set" .. s.id, dim = (s.lv or 1) > lvl + 8 or nil,
                    d = (s.sub and s.sub or GROUP[s.g] or "") .. (s.lv and ("  ·  level " .. s.lv) or "") .. (s.arm and ("  ·  " .. s.arm) or ""), page = function() return SetPage(s) end,
                    lv = s.lv or 1, ring = own == #s.i and "good" or nil }
      if own > 0 then started[#started + 1] = row else
        by[s.g] = by[s.g] or {}
        table.insert(by[s.g], row)
      end
    end
  end
  if #started > 0 then
    rows[#rows + 1] = { h = "Started" }
    for _, r in ipairs(started) do rows[#rows + 1] = r end
  end
  for _, g in ipairs(GORDER) do
    local l = by[g]
    if l and #l > 0 then
      table.sort(l, function(a, b)
        local da, db = a.lv > lvl + 8 and a.lv + 100 or math.abs(a.lv - lvl), b.lv > lvl + 8 and b.lv + 100 or math.abs(b.lv - lvl)
        if da ~= db then return da < db end
        return a.t < b.t
      end)
      rows[#rows + 1] = { h = GROUP[g] }
      for _, r in ipairs(l) do rows[#rows + 1] = r end
    end
  end
  if #rows == 0 then rows[1] = { t = "No sets for your class", still = true } end
  return rows
end
