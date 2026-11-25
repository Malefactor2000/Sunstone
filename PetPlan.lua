-- Sunstone: the pet planner (Class tab, Hunter, Pets; /sun pet). Pick any beast (a family, one from a list, or the one you target) and see
-- it in 3D with what it would be at your level: health, armor, damage, which skills it can learn and what each really does, how many training
-- points a set costs, and how two pets compare. Family and skill numbers are the Forever client's own; a pet's health, armor and damage by level
-- are Classic's, corrected by your own pet whenever you have one out. For hunters also: a line on a beast's tooltip and a small paw by the
-- target frame. Information only: it never tames, casts, teaches or feeds anything.

local _, NS = ...
local PP = NS.Module("PetPlan")
NS.PetPlan = PP
local E, Lk, C = NS.Engine, NS.Look, NS.C
local I = "Interface\\Icons\\"

local function Src() return type(_G.SunstonePets) == "table" and _G.SunstonePets or {} end
local function Num() return type(_G.SunstonePetStats) == "table" and _G.SunstonePetStats or {} end
local function List(t) return type(t) == "table" and t or {} end
local function Plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function N(v) return Plain(v) and type(v) == "number" and v or nil end
local function IsHunter() return select(2, UnitClass("player")) == "HUNTER" end
local function Icon(n) return n and (I .. n) or nil end

local LOYALTY = { "Rebellious", "Unruly", "Submissive", "Dependable", "Faithful", "Best Friend" }
local SLOTS = 4          -- active skills a pet can have at once (Petopia's Forever pages)
local FOCUS = 6          -- focus a second (24 every 4 seconds, Classic's)
local HAPPY = 1.25       -- a happy pet's damage (Classic's)
local ROLE = { Offense = "Deals damage", Defense = "Takes hits", General = "All-round" }
local FOOD = { Meat = "INV_Misc_Food_14", Fish = "INV_Misc_Fish_02", ["Raw Fish"] = "INV_Misc_Fish_02", Cheese = "INV_Misc_Food_37", Bread = "INV_Misc_Food_11",
               Fungus = "INV_Mushroom_05", Fruit = "INV_Misc_Food_19" }
local PASSIVE = { ["Great Stamina"] = true, ["Natural Armor"] = true, ["Arcane Resistance"] = true, ["Fire Resistance"] = true, ["Frost Resistance"] = true,
                  ["Nature Resistance"] = true, ["Shadow Resistance"] = true }
local ALL = { "Growl", "Cower", "Great Stamina", "Natural Armor", "Arcane Resistance", "Fire Resistance", "Frost Resistance", "Nature Resistance", "Shadow Resistance" }

---------------------------------------------------------------------------
-- Looking things up
---------------------------------------------------------------------------
local byNpc, famOf, knows, abil
local function Index()
  if byNpc then return end
  byNpc, famOf, knows, abil = {}, {}, {}, {}
  for _, f in ipairs(List(Src().families)) do
    famOf[f.n] = f
    for _, b in ipairs(List(f.tames)) do byNpc[b[1]] = byNpc[b[1]] or { b = b, f = f } end
  end
  for _, r in ipairs(List(Src().rares)) do
    if r.fam and famOf[r.fam] then byNpc[r[1]] = byNpc[r[1]] or { b = r, f = famOf[r.fam] } end
  end
  for _, a in ipairs(List(Src().abilities)) do
    abil[a.n] = a
    for k, r in ipairs(List(a.ranks)) do
      for _, b in ipairs(List(r[4])) do
        local t = knows[b[1]] or {}
        knows[b[1]] = t
        t[#t + 1] = { a.n, k }
        if b.fam and famOf[b.fam] then byNpc[b[1]] = byNpc[b[1]] or { b = b, f = famOf[b.fam] } end
      end
    end
  end
end
function PP.Family(name) Index() return famOf[name] end
function PP.Beast(npc) -- { b = { npc, name, level, zone, map, x, y }, f = family }, also the ones you targeted
  Index()
  local e = byNpc[npc]
  if e then return e end
  local seen = NS.db and type(NS.db.beasts) == "table" and NS.db.beasts[npc]
  if type(seen) == "table" and famOf[seen.fam or ""] then
    e = { b = { npc, NS.Clean(seen.n, 60), tostring(seen.lv or "?"), NS.Clean(seen.z or "", 40), seen.m, seen.x, seen.y, own = true, elite = seen.elite }, f = famOf[seen.fam] }
    byNpc[npc] = e
    return e
  end
end
function PP.Knows(npc) Index() return List(knows[npc]) end -- what a wild one already has: { { skill, rank }, ... }
function PP.Skill(name) Index() return abil[name], List(Num().skills)[name] end
function PP.SkillsOf(f) -- every skill a family can have, its own first
  local out, seen = {}, {}
  local function Add(n) if n and not seen[n] and PP.Skill(n) then seen[n] = true; out[#out + 1] = n end end
  Add(f.only)
  for _, n in ipairs(List(f.ab)) do Add(n) end
  for _, n in ipairs(ALL) do Add(n) end
  return out
end
-- The best rank of a skill at a level -> its number, its numbers { spell, level, focus, cooldown, damage, dot, what, much }, its training points; or nil and the first level
function PP.Rank(name, L)
  local a, s = PP.Skill(name)
  local rr = s and s.r or {}
  local best
  for k, r in ipairs(rr) do if r[2] <= L then best = k end end
  if not best then return nil, rr[1] and rr[1][2] end
  local pr = a and List(a.ranks)[best]
  return best, rr[best], pr and pr[2] or 0, pr
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
function PP.Reduction(armor, L) return armor / (armor + 400 + 85 * L) end -- against something of the same level (Classic's rule)

-- your own pet's real numbers against what Sunstone works out for it: how far off the estimate is
local function Yard() local y = NS.cdb and NS.cdb.petReal; return type(y) == "table" and y or nil end

-- What a pet of a family is at a level with a set of skills ({ name = true })
function PP.Numbers(f, L, set, npc, raw)
  local base = List(Num().base)[math.max(1, math.min(60, L))] or { 1, 0, 20, 20, 20 }
  local fam = List(Num().fam)[f.n] or { 0, 0, 0 }
  local y = not raw and Yard() or nil
  local o = { L = L, tp = 0, tpMax = L * 5, actives = 0, unknown = 0, skills = {}, yard = y }
  local hp, armor = base[1] * (1 + fam[3] / 100), base[2] * (1 + fam[2] / 100)
  hp, armor = hp * (y and y.hp or 1), armor * (y and y.armor or 1)
  local ap = 2 * base[3] - 20
  local hit = (L - math.floor(L / 4)) * 1.25 + math.max(0, ap) / 14 * 2
  local dps = hit / 2 * (1 + fam[1] / 100) * (y and y.dps or 1)
  local speed = List(Num().speed)[npc or 0] or (NS.db and type(NS.db.petSpeed) == "table" and N(NS.db.petSpeed[npc or 0])) or 2
  o.dpsCalm = dps
  o.dps, o.speed, o.hit = dps * HAPPY, speed, dps * HAPPY * speed
  -- skills
  local focus, use = FOCUS, {}
  for name in pairs(set or {}) do
    local k, r, tp = PP.Rank(name, L)
    if k then
      o.tp = o.tp + (tp or 0)
      if (tp or 0) == 0 and name ~= "Growl" then o.unknown = o.unknown + 1 end
      if not PASSIVE[name] then o.actives = o.actives + 1 end
      if r[7] == "sta" then hp = hp + r[8] elseif r[7] == "armor" then armor = armor + r[8] end
      local _, s = PP.Skill(name)
      local phys = (s.school or 1) == 1
      local dmg = (r[5] + (r[7] == "stack" and r[6] or r[6])) * (phys and (1 + fam[1] / 100) or 1) * HAPPY
      local e = { n = name, k = k, r = r, dmg = dmg, phys = phys, per = r[3] > 0 and dmg / r[3] or 0 }
      o.skills[name] = e
      if not PASSIVE[name] then use[#use + 1] = e end
    end
  end
  -- what its focus goes into: Growl first (it's kept on), then the most damage for the focus, as often as the cooldown allows
  table.sort(use, function(a, b)
    if (a.n == "Growl") ~= (b.n == "Growl") then return a.n == "Growl" end
    if a.per ~= b.per then return a.per > b.per end
    return a.n < b.n
  end)
  o.skillDps = 0
  for _, e in ipairs(use) do
    if (e.dmg > 0 or e.n == "Growl") and e.r[3] > 0 and focus > 0.05 then
      local most = 1 / math.max(1.5, e.r[4]) -- casts a second
      local n = math.min(most, focus / e.r[3])
      focus = focus - n * e.r[3]
      e.dps = n * e.dmg
      e.every = 1 / n
      o.skillDps = o.skillDps + e.dps
    end
  end
  o.hp, o.armor = math.floor(hp + 0.5), math.floor(armor + 0.5)
  o.less = PP.Reduction(o.armor, L)
  o.tough = o.hp / (1 - o.less)
  o.total = o.dps + o.skillDps
  return o
end

-- The strongest set that fits: its own skill, Growl, the best hits, then health and armor for the points
function PP.BestSet(f, L, loyalty)
  local points = L * ((loyalty or 6) - 1)
  local set, used, act = {}, 0, 0
  local function Add(n)
    local k, _, tp = PP.Rank(n, L)
    if not k or set[n] then return end
    if not PASSIVE[n] and act >= SLOTS then return end
    if used + (tp or 0) > points then return end
    set[n] = true
    used = used + (tp or 0)
    if not PASSIVE[n] then act = act + 1 end
  end
  Add("Growl")
  local has = {}
  for _, n in ipairs(PP.SkillsOf(f)) do has[n] = true end
  if f.only ~= "Prowl" then Add(f.only or "") end
  for _, n in ipairs({ "Bite", "Claw", "Great Stamina", "Natural Armor" }) do if has[n] then Add(n) end end
  for _, n in ipairs({ "Dash", "Dive", f.only or "" }) do if has[n] then Add(n) end end
  return set
end

-- The scale of the bars: the best any family has at that level
local tops = {}
local function Tops(L)
  if tops[L] then return tops[L] end
  local t = { hp = 1, armor = 1, dps = 1, skill = 1, tough = 1 }
  for _, f in ipairs(List(Src().families)) do
    local o = PP.Numbers(f, L, PP.BestSet(f, L, 6), nil, true)
    t.hp, t.armor, t.dps = math.max(t.hp, o.hp), math.max(t.armor, o.armor), math.max(t.dps, o.dps)
    t.skill, t.tough = math.max(t.skill, o.skillDps), math.max(t.tough, o.tough)
  end
  tops[L] = t
  return t
end

---------------------------------------------------------------------------
-- Your own pet, and beasts you look at
---------------------------------------------------------------------------
local function UnitFamily(unit)
  if not UnitCreatureFamily then return nil end
  local ok, fam = pcall(UnitCreatureFamily, unit)
  if not (ok and Plain(fam) and type(fam) == "string") then return nil end
  Index()
  return famOf[fam]
end
local function NpcOf(unit)
  local g = NS.GUID(unit)
  if type(g) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", g)
  return kind == "Creature" and tonumber(id) or nil
end
local function PetKnows(spell)
  for _, fn in ipairs({ C_SpellBook and C_SpellBook.IsSpellKnown or false, IsSpellKnown or false }) do
    if fn then
      local ok, v = pcall(fn, spell, fn == IsSpellKnown and true or (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or 1)
      if ok and Plain(v) and v then return true end
    end
  end
  return false
end
-- A wild beast you target or point at -> { npc, name, level, f, elite } (nil: not one of a hunter's families, or somebody's pet)
function PP.Unit(unit)
  if not (UnitExists and UnitExists(unit)) then return nil end
  for _, fn in ipairs({ UnitIsPlayer or false, UnitPlayerControlled or false }) do
    if fn then
      local ok, v = pcall(fn, unit)
      if ok and Plain(v) and v then return nil end
    end
  end
  local f = UnitFamily(unit)
  local npc = f and NpcOf(unit)
  if not npc then return nil end
  local name, lv = UnitName(unit), UnitLevel(unit)
  local cl = UnitClassification and UnitClassification(unit)
  return { npc = npc, f = f, unit = unit, name = Plain(name) and name or "?", level = N(lv) or -1,
           elite = Plain(cl) and (cl == "elite" or cl == "rareelite" or cl == "worldboss") or nil, rare = Plain(cl) and (cl == "rare" or cl == "rareelite") or nil }
end
-- keep what isn't in the lists: where a beast you targeted was, and how fast it attacks
local function Note(u)
  if not (u and NS.db) then return end
  if UnitAttackSpeed then
    local ok, s = pcall(UnitAttackSpeed, u.unit)
    s = ok and N(s)
    if s and s >= 0.8 and s <= 4 then
      NS.db.petSpeed = type(NS.db.petSpeed) == "table" and NS.db.petSpeed or {}
      NS.db.petSpeed[u.npc] = math.floor(s * 10 + 0.5) / 10
    end
  end
  if not PP.Beast(u.npc) then
    NS.db.beasts = type(NS.db.beasts) == "table" and NS.db.beasts or {}
    local n = 0
    for _ in pairs(NS.db.beasts) do n = n + 1 end
    if n >= 400 then return end
    local here = E.Here()
    local x, y = here and N(here.x), here and N(here.y)
    NS.db.beasts[u.npc] = { n = u.name, fam = u.f.n, lv = u.level > 0 and u.level or "?", z = GetRealZoneText and GetRealZoneText() or "", m = here and here.m,
                            x = x and math.floor(x * 1000 + 0.5) / 10, y = y and math.floor(y * 1000 + 0.5) / 10, elite = u.elite }
  end
end

-- Your pet out and calm: its real numbers (they carry your talents and gear), and how far Sunstone's are off
function PP.ReadPet()
  if not (IsHunter() and UnitExists and UnitExists("pet")) or (UnitAffectingCombat and UnitAffectingCombat("pet")) then return nil end
  local f = UnitFamily("pet")
  local L, hp = N(UnitLevel("pet")), N(UnitHealthMax("pet"))
  if not (f and L and hp and hp > 1) then return nil end
  local function Call(fn, ...) if not fn then return nil end local r = { pcall(fn, ...) } if r[1] then return unpack(r, 2) end end
  local _, armor = Call(UnitArmor, "pet")
  local lo, hi, _, _, _, _, pct = Call(UnitDamage, "pet")
  local speed = Call(UnitAttackSpeed, "pet")
  local _, happy = Call(GetPetHappiness)
  local set = {}
  for _, n in ipairs(PP.SkillsOf(f)) do
    local _, s = PP.Skill(n)
    for _, r in ipairs(s and s.r or {}) do if PetKnows(r[1]) then set[n] = true end end
  end
  local me = { fam = f.n, level = L, name = Plain(UnitName("pet")) and UnitName("pet") or f.n, hp0 = hp, armor0 = N(armor), set = set, speed = N(speed), at = time() }
  lo, hi = N(lo), N(hi)
  if lo and hi and N(speed) and speed > 0 then me.dps0 = (lo + hi) / 2 / speed end
  me.happy = N(happy)
  local o = PP.Numbers(f, L, set, nil, true)
  local plain = PP.Numbers(f, L, {}, nil, true)
  local extraHp, extraAr = o.hp - plain.hp, o.armor - plain.armor
  local function Ratio(a, b) local r = a and b and b > 0 and a / b or nil; return r and r > 0.4 and r < 2.5 and r or nil end
  me.hp = Ratio(hp - extraHp, plain.hp) or 1
  me.armor = Ratio(me.armor0 and (me.armor0 - extraAr), plain.armor) or 1
  me.dps = Ratio(me.dps0 and me.dps0 / ((me.happy and me.happy > 0 and me.happy or 125) / 100), plain.dpsCalm) or 1
  NS.cdb.petReal = me
  return me
end

---------------------------------------------------------------------------
-- What's on the bench (per character)
---------------------------------------------------------------------------
function PP.State()
  local s = NS.cdb.petPlan
  if type(s) ~= "table" then s = {}; NS.cdb.petPlan = s end
  s.loyalty = N(s.loyalty) or 6
  if type(s.sets) ~= "table" then s.sets = {} end
  if s.follow == nil then s.follow = true end
  if not PP.Family(s.fam) then s.fam, s.npc = "Cat", nil end
  return s
end
function PP.Level() return math.max(1, math.min(60, N(PP.State().level) or UnitLevel("player") or 10)) end
function PP.Set(fam)
  local s = PP.State()
  local f = PP.Family(fam or s.fam)
  local t = s.sets[f.n]
  if type(t) ~= "table" then return PP.BestSet(f, PP.Level(), s.loyalty), f end
  local has, out = {}, {}
  for _, n in ipairs(PP.SkillsOf(f)) do has[n] = true end
  for n in pairs(t) do if has[n] then out[n] = true end end
  return out, f
end

-- the beast of a family to start from: one you could tame near your level, the closest place first
local function Start(f)
  local L, best, bs = PP.Level()
  for _, b in ipairs(List(f.tames)) do
    local lo = tonumber(tostring(b[3]):match("%d+")) or 99
    local gap = lo <= L and (L - lo) or (lo - L) * 6
    local s = gap * 4 + (b.rare and 120 or 0) + (b[5] and math.min(120, E.Minutes(E.Point(b[5], b[6] / 100, b[7] / 100)) or 120) or 90)
    if not bs or s < bs then best, bs = b, s end
  end
  return best and best[1]
end

local function Redo()
  if NS.Window and NS.Window.Redo then NS.Window.Redo() end
end
function PP.PickFamily(name)
  local s = PP.State()
  local f = PP.Family(name)
  if not f then return end
  s.fam, s.npc = name, Start(f)
  Redo()
end
function PP.Pick(npc, quiet)
  local e = PP.Beast(npc)
  if not e then return false end
  local s = PP.State()
  s.fam, s.npc = e.f.n, npc
  if not quiet then Redo() end
  return true
end
function PP.FromUnit(unit)
  local u = PP.Unit(unit)
  if not u then return nil end
  Note(u)
  local s = PP.State()
  s.fam, s.npc = u.f.n, u.npc
  return u
end
-- Opens the planner's page (the Class tab, hunters, pets)
function PP.Open(npc)
  if npc then PP.Pick(npc, true) end
  local W = NS.Window
  if not W then return end
  NS.cdb.classMode = "pets"
  W.Open("class")
  for _, r in ipairs(W.current or {}) do if r.key == "classHUNTER" then W.Select(r) end end
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local panel
local function Pct(v) return string.format("%+d%%", v) end
local function One(v) return v >= 100 and string.format("%d", v + 0.5) or string.format("%.1f", v) end
local function Diff(a, b, dec)
  if not b then return "" end
  local d = a - b
  if math.abs(d) < (dec and 0.05 or 0.5) then return "" end
  return string.format("  |cff%s(%s%s)|r", d > 0 and NS.HEX.good or NS.HEX.warn, d > 0 and "+" or "-", dec and One(math.abs(d)) or string.format("%d", math.abs(d) + 0.5))
end

local function SkillTip(b)
  local n, f = b.skill, b.f
  local a, s = PP.Skill(n)
  local L, st = PP.Level(), PP.State()
  local k, r, tp, pr = PP.Rank(n, L)
  if not b.spell then GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); Lk.TipLine(n, C.accent) end
  if not k then
    Lk.TipLine("From pet level " .. tostring(r or "?") .. ".", C.warn)
    if a and a.eff ~= "" then Lk.TipLine(a.eff) end
  else
    Lk.TipLine(" ")
    Lk.TipLine(string.format("Rank %d at pet level %d", k, L) .. (s.r[k + 1] and string.format(", rank %d at %d", k + 1, s.r[k + 1][2]) or ", its last rank"), C.accent)
    if r[3] > 0 then Lk.TipLine(string.format("%d focus%s", r[3], r[4] > 0 and string.format(", every %s", r[4] >= 60 and string.format("%g min", r[4] / 60) or string.format("%g s", r[4])) or ", no cooldown")) end
    local e = PP.Numbers(f, L, { [n] = true }, st.npc).skills[n]
    if e and e.dmg > 0 then
      Lk.TipLine(string.format("About %s damage for a happy %s of that level%s.", One(e.dmg), f.n:lower(), r[7] == "aoe" and ", to each enemy near" or r[7] == "stack" and ", up to 5 times as it builds up" or ""))
      Lk.TipLine(string.format("%.2f damage for each point of focus%s.", e.per, e.phys and "" or "; armor doesn't reduce it"), C.dim)
    end
    if pr and pr[3] and pr[3] ~= "" and not b.spell then Lk.TipLine(pr[3]) end
    Lk.TipLine(n == "Growl" and "Costs no training points." or (tp or 0) > 0 and string.format("%d training points.", tp) or "Training points: not known yet.", C.dim)
    if n == "Great Stamina" then Lk.TipLine("+" .. r[8] .. " health", C.good) elseif n == "Natural Armor" then Lk.TipLine("+" .. r[8] .. " armor", C.good) end
  end
  local use = NS.Pets and NS.Pets.USE and NS.Pets.USE[n]
  if use then Lk.TipLine(use, C.text) end
  for _, kn in ipairs(PP.Knows(st.npc)) do
    if kn[1] == n then Lk.TipLine(string.format("This beast has it: tame it to learn rank %d.", kn[2]), C.good) end
  end
  if a and a.src == "trainer" then Lk.TipLine("From a pet trainer.", C.dim) end
  Lk.TipLine(b.later and "Right-click: ranks and who teaches it." or "Click: put it in or take it out.  Right-click: ranks and who teaches it.", C.dim)
end

local function Toggle(n)
  local s = PP.State()
  local set, f = PP.Set()
  local k, r = PP.Rank(n, PP.Level())
  if not k then
    NS.Print(n .. " needs pet level " .. tostring(r or "?") .. ".")
    return
  end
  if set[n] then set[n] = nil
  else
    if not PASSIVE[n] then
      local act = 0
      for x in pairs(set) do if not PASSIVE[x] and PP.Rank(x, PP.Level()) then act = act + 1 end end
      if act >= SLOTS then
        UIErrorsFrame:AddMessage("A pet can have four of these at once: take one out first.", 1, 0.6, 0.3)
        return
      end
    end
    set[n] = true
  end
  s.sets[f.n] = set
  Redo()
end

local function Make(row)
  local p = CreateFrame("Frame", nil, row)
  panel = p
  p.bg = NS.Rounded(p, C.surface, "round.png", 10)
  p.fams, p.skills, p.slots, p.foods = {}, {}, {}, {}
  for k, f in ipairs(List(Src().families)) do
    local b = Lk.Icon(p, 30)
    b:Set(Icon(f.icon))
    b.fam = f.n
    b:SetScript("OnClick", function() PP.PickFamily(f.n) end)
    b.about = function()
      local m = List(Num().fam)[f.n] or { 0, 0, 0 }
      Lk.TipLine(f.n, C.accent)
      Lk.TipLine(ROLE[f.role] or f.role, C.dim)
      Lk.TipLine(string.format("Damage %s, armor %s, health %s", Pct(m[1]), Pct(m[2]), Pct(m[3])))
      if f.only then Lk.TipLine("Only they have " .. f.only .. ".") end
      Lk.TipLine("Eats " .. table.concat(List(f.diet), ", "):lower() .. ".", C.dim)
      if #List(f.tames) == 0 then Lk.TipLine("None found on Forever that can be tamed so far.", C.warn) end
    end
    p.fams[k] = b
  end
  p.view = Lk.Model(p, 236, 228)
  p.name = Lk.Text(p, "GameFontNormalLarge", C.accent)
  p.sub = Lk.Text(p, "GameFontHighlightSmall", C.dim)
  p.lvl = Lk.Text(p, "GameFontHighlight", C.text)
  p.minus = NS.Button(p, "-", 22, function() PP.State().level = math.max(1, PP.Level() - 1); Redo() end)
  p.plus = NS.Button(p, "+", 22, function() PP.State().level = math.min(60, PP.Level() + 1); Redo() end)
  p.mine = NS.Button(p, "My level", 62, function() PP.State().level = nil; Redo() end)
  p.bars = {}
  for k = 1, 5 do p.bars[k] = Lk.Bar(p, 18) end
  p.tpBar = Lk.Bar(p, 15)
  p.loyal = NS.Button(p, "", 128, function() local s = PP.State(); s.loyalty = s.loyalty % 6 + 1; Redo() end)
  p.best = NS.Button(p, "Best set", 58, function() PP.State().sets[PP.State().fam] = nil; Redo() end)
  p.none = NS.Button(p, "Clear", 44, function() PP.State().sets[PP.State().fam] = {}; Redo() end)
  for k = 1, SLOTS do
    local b = Lk.Icon(p, 36)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self) if self.skill then Toggle(self.skill) end end)
    b.about = function(self) if self.skill then SkillTip(self) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); Lk.TipLine("An empty place: a pet can have four active skills. Click one below.") end end
    p.slots[k] = b
  end
  p.slotText = Lk.Text(p, "GameFontHighlightSmall", C.dim)
  p.slotText:SetSpacing(2)
  p.skillHead = Lk.Text(p, "GameFontNormal", C.accent)
  p.skillHead:SetText("Skills it can learn")
  p.skillHint = Lk.Text(p, "GameFontHighlightSmall", C.dim)
  p.note = Lk.Text(p, "GameFontHighlightSmall", C.dim)
  p.note:SetSpacing(2)
  p.target = NS.Button(p, "", 150, function()
    if PP.FromUnit("target") then Redo() else NS.Print("Target a wild beast first (one of a hunter's pet families).") end
  end)
  p.follow = NS.Button(p, "", 112, function() local s = PP.State(); s.follow = not s.follow; Redo() end)
  p.pet = NS.Button(p, "My pet", 52, function()
    local me = PP.ReadPet() or Yard()
    if not me then NS.Print("Call your pet first.") return end
    local s = PP.State()
    s.fam, s.npc, s.level = me.fam, nil, me.level
    s.sets[me.fam] = me.set
    Redo()
  end)
  p.pin = NS.Button(p, "", 104, function()
    local s = PP.State()
    if s.pin then s.pin = nil
    else
      local set = PP.Set()
      local e = s.npc and PP.Beast(s.npc)
      s.pin = { fam = s.fam, npc = s.npc, name = e and e.b[2] or s.fam, set = set }
    end
    Redo()
  end)
  p.where = NS.Button(p, "Map", 44, function()
    local e = PP.State().npc and PP.Beast(PP.State().npc)
    if e and e.b[5] then NS.Window.Mark({ t = e.b[2], m = e.b[5], x = e.b[6] / 100, y = e.b[7] / 100 }) end
  end)
  p.go = NS.Button(p, "Go", 36, function()
    local e = PP.State().npc and PP.Beast(PP.State().npc)
    if e and e.b[5] then NS.Window.Go({ t = e.b[2], m = e.b[5], x = e.b[6] / 100, y = e.b[7] / 100 }) end
  end)
  return p
end

local function Update(p, width)
  local s = PP.State()
  local set, f = PP.Set()
  local L = PP.Level()
  local e = s.npc and PP.Beast(s.npc)
  if e and e.f.n ~= f.n then e, s.npc = nil, nil end
  if not s.npc and not s.noBeast then s.npc = Start(f); e = s.npc and PP.Beast(s.npc) end
  local o = PP.Numbers(f, L, set, s.npc)
  local pin = type(s.pin) == "table" and PP.Family(s.pin.fam) and s.pin or nil
  local po = pin and PP.Numbers(PP.Family(pin.fam), L, List(pin.set), pin.npc)
  local top = Tops(L)
  -- families
  local per, gap = 19, 5
  local size = math.floor((width - 24 - gap * (per - 1)) / per)
  size = math.max(22, math.min(34, size))
  for k, b in ipairs(p.fams) do
    local col, rw = (k - 1) % per, math.floor((k - 1) / per)
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 12 + col * (size + gap), -10 - rw * (size + gap))
    local on = b.fam == f.n
    b.edge:SetColor(on and Lk.GOLD or C.border)
    b.edge:Thick(on and 2 or 1)
    b:Dim(not on and #List(PP.Family(b.fam).tames) == 0)
  end
  local top0 = -(10 + math.ceil(#p.fams / per) * (size + gap) + 6)
  -- the beast
  p.view:ClearAllPoints()
  p.view:SetPoint("TOPLEFT", 12, top0)
  p.view.art:Set("Interface\\TalentFrame\\HunterBeastMastery-", 0.5)
  local live = UnitExists and UnitExists("target") and s.npc and NpcOf("target") == s.npc
  if s.npc then p.view:Show1({ npc = s.npc, unit = live and "target" or nil, icon = Icon(f.icon) })
  elseif UnitExists and UnitExists("pet") and UnitFamily("pet") == f then p.view:Show1({ unit = "pet", npc = -1, icon = Icon(f.icon), fresh = true })
  else p.view:Show1({ icon = Icon(f.icon) }) end
  p.name:ClearAllPoints()
  p.name:SetPoint("TOPLEFT", p.view, "TOPRIGHT", 14, 0)
  p.name:SetPoint("RIGHT", -12, 0)
  p.name:SetText(e and e.b[2] or f.n)
  local bits = { f.n, (ROLE[f.role] or f.role):lower() }
  if e then
    bits[#bits + 1] = "wild: level " .. (e.b[3] ~= "" and e.b[3] or "?") .. (e.b.elite and " elite" or "") .. (e.b.rare and ", rare" or "")
    if e.b[4] and e.b[4] ~= "" then bits[#bits + 1] = e.b[4] end
  end
  p.sub:ClearAllPoints()
  p.sub:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -3)
  p.sub:SetPoint("RIGHT", -12, 0)
  p.sub:SetText(table.concat(bits, "  ·  "))
  p.lvl:ClearAllPoints()
  p.lvl:SetPoint("TOPLEFT", p.sub, "BOTTOMLEFT", 0, -9)
  p.lvl:SetText("As your pet at level " .. L)
  p.minus:ClearAllPoints(); p.minus:SetPoint("LEFT", p.lvl, "RIGHT", 10, 0)
  p.plus:ClearAllPoints(); p.plus:SetPoint("LEFT", p.minus, "RIGHT", 4, 0)
  p.mine:ClearAllPoints(); p.mine:SetPoint("LEFT", p.plus, "RIGHT", 4, 0)
  p.mine:SetShown(s.level ~= nil)
  local x0 = 12 + 236 + 14
  local bw = width - x0 - 12
  local fam = List(Num().fam)[f.n] or { 0, 0, 0 }
  local function S(v, t) return v and math.max(0.04, math.min(1, (v / t - 0.6) / 0.4)) end -- (the bars start at 60% of the best, so differences show)
  local rows = {
    { "Health", S(o.hp, top.hp), string.format("%d%s", o.hp, po and Diff(o.hp, po.hp) or ""), { 0.30, 0.52, 0.22 }, po and S(po.hp, top.hp),
      function() Lk.TipLine("Health at level " .. L, C.accent); Lk.TipLine(f.n .. "s have " .. Pct(fam[3]) .. " health" .. (set["Great Stamina"] and ", and Great Stamina adds its own" or "") .. ".") end },
    { "Armor", S(o.armor, top.armor), string.format("%d%s   takes %d%% less", o.armor, po and Diff(o.armor, po.armor) or "", o.less * 100 + 0.5), { 0.42, 0.40, 0.46 }, po and S(po.armor, top.armor),
      function() Lk.TipLine("Armor at level " .. L, C.accent); Lk.TipLine(f.n .. "s have " .. Pct(fam[2]) .. " armor. Against a level " .. L .. " enemy's weapon hits it takes " .. string.format("%.1f", o.less * 100) .. "% less; spells ignore it.") end },
    { "Toughness", S(o.tough, top.tough), string.format("%d%s", o.tough, po and Diff(o.tough, po.tough) or ""), { 0.45, 0.33, 0.20 }, po and S(po.tough, top.tough),
      function() Lk.TipLine("Toughness", C.accent); Lk.TipLine("How much weapon damage from a level " .. L .. " enemy it takes to bring it down, armor counted.") end },
    { "Attacks", S(o.dps, top.dps), string.format("%s a second%s", One(o.dps), po and Diff(o.dps, po.dps, true) or ""), { 0.60, 0.17, 0.13 }, po and S(po.dps, top.dps),
      function()
        Lk.TipLine("Its own attacks", C.accent)
        Lk.TipLine(string.format("About %d a hit, every %.1f seconds, when happy. %ss deal %s damage.", o.hit + 0.5, o.speed, f.n, Pct(fam[1])))
        Lk.TipLine("A slower or faster beast deals the same a second: fast ones hit smaller and more often, which interrupts casters more.", C.dim)
      end },
    { "Skills", o.skillDps / top.skill, string.format("+%s a second%s", One(o.skillDps), po and Diff(o.skillDps, po.skillDps, true) or ""), { 0.66, 0.42, 0.12 }, po and po.skillDps / top.skill,
      function()
        Lk.TipLine("Damage from the skills in the set", C.accent)
        Lk.TipLine("Spending about 6 focus a second (Classic's), the best use of it first:")
        local l = {}
        for _, x in pairs(o.skills) do if x.dps then l[#l + 1] = x end end
        table.sort(l, function(a, b) return a.dps > b.dps end)
        for _, x in ipairs(l) do Lk.TipLine(string.format("%s: %s", x.n, x.dmg > 0 and string.format("%s damage every %.1f s, %s a second", One(x.dmg), x.every, One(x.dps)) or string.format("every %.1f s", x.every)), C.text, false) end
      end },
  }
  for k, r in ipairs(rows) do
    local b = p.bars[k]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x0, top0 - 62 - (k - 1) * 21)
    b:SetWidth(bw)
    b:Set(r[1], r[2], r[3], r[4], r[5])
    b.about = r[6]
  end
  -- the set
  local y1 = top0 - 62 - 5 * 21 - 3
  local act = {}
  for n in pairs(set) do if not PASSIVE[n] and PP.Rank(n, L) then act[#act + 1] = n end end
  table.sort(act, function(a, b) if (a == "Growl") ~= (b == "Growl") then return a == "Growl" end return a < b end)
  local nm = {}
  for k, b in ipairs(p.slots) do
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x0 + (k - 1) * 42, y1)
    local n = act[k]
    b.skill, b.f, b.later = n, f, nil
    if n then
      local a = PP.Skill(n)
      local rk, r = PP.Rank(n, L)
      b.spell = r[1]
      b:Set((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(r[1])) or Icon(a.icon))
      b.num:SetText(rk)
      b.edge:SetColor(Lk.GOLD)
      b.tex:Show()
      nm[#nm + 1] = n
    else
      b.spell = nil
      b.tex:Hide()
      b.num:SetText("")
      b.edge:SetColor(C.border)
    end
  end
  p.slotText:ClearAllPoints()
  p.slotText:SetPoint("TOPLEFT", x0 + 4 * 42 + 6, y1 - 2)
  p.slotText:SetPoint("RIGHT", -12, 0)
  local pas = {}
  for n in pairs(set) do if PASSIVE[n] and PP.Rank(n, L) then pas[#pas + 1] = n end end
  table.sort(pas)
  p.slotText:SetText(string.format("%d of %d active skills%s", #act, SLOTS, #pas > 0 and ("\nAlways on: " .. table.concat(pas, ", ")) or ""))
  local tpMax = L * (s.loyalty - 1)
  p.tpBar:ClearAllPoints()
  p.tpBar:SetPoint("TOPLEFT", x0, y1 - 41)
  p.tpBar:SetWidth(bw - 134)
  p.tpBar:Set("Training points", tpMax > 0 and o.tp / tpMax or (o.tp > 0 and 1 or 0), string.format("%d of %d%s", o.tp, tpMax, o.unknown > 0 and " (+?)" or ""), o.tp > tpMax and C.red or { 0.24, 0.36, 0.55 })
  p.tpBar.about = function()
    Lk.TipLine("Training points", C.accent)
    Lk.TipLine("A pet has its level times (loyalty - 1): " .. L .. " x " .. (s.loyalty - 1) .. " = " .. tpMax .. ".")
    if o.tp > tpMax then Lk.TipLine("This set needs more than it has.", C.warn) end
    if o.unknown > 0 then Lk.TipLine("What " .. o.unknown .. " of these skills cost isn't known yet (new in Forever).", C.dim) end
  end
  p.loyal:ClearAllPoints()
  p.loyal:SetPoint("LEFT", p.tpBar, "RIGHT", 6, 0)
  p.loyal:SetText("Loyalty: " .. LOYALTY[s.loyalty])
  -- buttons under the picture
  local y2 = top0 - 228 - 8
  local u = PP.Unit("target")
  p.target:ClearAllPoints(); p.target:SetPoint("TOPLEFT", 12, y2)
  p.target:SetText(u and ("Target: " .. (u.name:len() > 18 and (u.name:sub(1, 17) .. "...") or u.name)) or "Use my target")
  p.target:SetActive(u ~= nil)
  p.where:ClearAllPoints(); p.where:SetPoint("LEFT", p.target, "RIGHT", 4, 0)
  p.go:ClearAllPoints(); p.go:SetPoint("LEFT", p.where, "RIGHT", 4, 0)
  local pos = e and e.b[5]
  p.where:SetShown(pos ~= nil); p.go:SetShown(pos ~= nil)
  p.follow:ClearAllPoints(); p.follow:SetPoint("TOPLEFT", x0, y2)
  p.follow:SetText(s.follow and "Follows my target" or "Follow target")
  p.follow:SetActive(s.follow)
  p.pin:ClearAllPoints(); p.pin:SetPoint("LEFT", p.follow, "RIGHT", 4, 0)
  p.pin:SetText(pin and "Stop comparing" or "Compare to this")
  p.pin:SetActive(pin ~= nil)
  p.best:ClearAllPoints(); p.best:SetPoint("LEFT", p.pin, "RIGHT", 4, 0)
  p.none:ClearAllPoints(); p.none:SetPoint("LEFT", p.best, "RIGHT", 4, 0)
  p.pet:ClearAllPoints()
  p.pet:SetPoint("LEFT", p.none, "RIGHT", 4, 0)
  p.pet:SetShown(IsHunter())
  -- every skill it can learn
  local y3 = y2 - 28
  p.skillHead:ClearAllPoints()
  p.skillHead:SetPoint("TOPLEFT", 12, y3)
  p.skillHint:ClearAllPoints()
  p.skillHint:SetPoint("LEFT", p.skillHead, "RIGHT", 10, 0)
  p.skillHint:SetText("Click to put in or take out. The number is the rank at that level; a star: this beast has it.")
  local all = PP.SkillsOf(f)
  local has = {}
  for _, kn in ipairs(PP.Knows(s.npc)) do has[kn[1]] = kn[2] end
  local sz, sg = 38, 6
  local cols = math.floor((width - 24 + sg) / (sz + sg))
  for k, n in ipairs(all) do
    local b = p.skills[k]
    if not b then
      b = Lk.Icon(p, sz)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b.about = SkillTip
      b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
          if NS.Pets and NS.Pets.SkillPage then GameTooltip:Hide(); NS.Window.OpenPage(function() return NS.Pets.SkillPage((PP.Skill(self.skill))) end) end
        else Toggle(self.skill) end
      end)
      p.skills[k] = b
    end
    local a = PP.Skill(n)
    local rk, r = PP.Rank(n, L)
    local first = List(select(2, PP.Skill(n)).r)[1]
    b.skill, b.f, b.later = n, f, not rk
    b.spell = rk and r[1] or (first and first[1]) or nil
    b:Set((b.spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spell)) or Icon(a.icon))
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 12 + ((k - 1) % cols) * (sz + sg), y3 - 22 - math.floor((k - 1) / cols) * (sz + sg))
    b:Dim(not rk)
    b.num:SetText(rk and rk or ("L" .. tostring(r or "?")))
    local num = rk and C.text or C.warn
    b.num:SetTextColor(num[1], num[2], num[3])
    b.edge:SetColor(set[n] and rk and Lk.GOLD or n == f.only and Lk.BLUE or C.border)
    b.edge:Thick(set[n] and rk and 2 or 1)
    b:Badge(has[n] and "star" or nil)
    b:Show()
  end
  for k = #all + 1, #p.skills do p.skills[k]:Hide() end
  local y4 = y3 - 22 - math.ceil(#all / cols) * (sz + sg) - 4
  p.note:ClearAllPoints()
  p.note:SetPoint("TOPLEFT", 12, y4)
  p.note:SetWidth(width - 24)
  local y = Yard()
  local lines = {}
  if pin then lines[#lines + 1] = "Compared with " .. pin.name .. " (" .. pin.fam .. ", its own set): the light mark on each bar." end
  lines[#lines + 1] = y and string.format("Corrected by your own pet (%s, level %d): your talents and gear are in these numbers.", NS.Clean(y.name, 24), y.level)
    or "Family and skill numbers are Forever's own. Health, armor and attacks by level are Classic's, for a happy pet: " .. (IsHunter() and "call your pet and they're corrected by it." or "yours may differ a little.")
  p.note:SetText(table.concat(lines, "\n"))
  return -y4 + (#lines * 14) + 12
end

function PP.Row()
  if not Lk then return nil end
  return { panel = { key = "petplan", make = Make, update = Update } }
end
function PP.Shown() return panel ~= nil and panel.IsVisible and panel:IsVisible() == true end

---------------------------------------------------------------------------
-- Under the panel: where the beast is, and others of its family
---------------------------------------------------------------------------
function PP.Rows(rows)
  local s = PP.State()
  local f = PP.Family(s.fam)
  if s.npc == nil then s.npc = Start(f) end
  local e = s.npc and PP.Beast(s.npc)
  if e then
    local b = e.b
    local pts = E.Points("Npc", b[1])
    rows[#rows + 1] = { h = "Where to find " .. b[2] }
    local pins, m = {}, b[5]
    for _, p in ipairs(pts) do if not m then m = p.m end end
    if m then
      local n = 0
      for _, p in ipairs(pts) do if p.m == m and n < 60 then n = n + 1; pins[n] = { m = m, x = p.x, y = p.y, t = b[2], state = "spot" } end end
      if b[5] == m and b[6] then pins[#pins + 1] = { m = m, x = b[6] / 100, y = b[7] / 100, t = b[2], n = 1, state = "next", d = "Level " .. tostring(b[3]) } end
      rows[#rows + 1] = { zmap = { m = m, name = b[4], pins = pins, title = b[2] } }
      rows[#rows + 1] = { t = b[2], d = "Level " .. tostring(b[3]) .. (b.elite and ", elite" or "") .. (b.rare and ", rare: not always there" or "") .. "  ·  " .. tostring(b[4])
                          .. (b.own and "\nNoted when you targeted it; not on the lists of beasts known to be tameable." or ""), face = b[1], tex = Icon(f.icon),
                          m = b[5], x = b[6] and b[6] / 100, y = b[7] and b[7] / 100 }
    else
      rows[#rows + 1] = { t = b[2], d = "Level " .. tostring(b[3]) .. "  ·  " .. tostring(b[4]) .. "\nInside a dungeon, or its place isn't recorded.", face = b[1], tex = Icon(f.icon), still = true }
    end
    local kn = PP.Knows(b[1])
    if #kn > 0 then
      rows[#rows + 1] = { h = "What it already knows" }
      for _, k in ipairs(kn) do
        local a, st = PP.Skill(k[1])
        local r = st and st.r[k[2]]
        rows[#rows + 1] = { t = string.format("%s, rank %d", k[1], k[2]), tex = Icon(a.icon), spell = r and r[1],
                            d = "Tame it and fight alongside it until you've learned this, then you can teach it to any pet whose family can have it (pet level " .. (r and r[2] or "?") .. ").",
                            page = NS.Pets.SkillPage and function() return NS.Pets.SkillPage(a) end or nil }
      end
    end
  end
  local L = PP.Level()
  local near = {}
  for _, b in ipairs(List(f.tames)) do
    if b[1] ~= s.npc then
      local lo = tonumber(tostring(b[3]):match("%d+")) or 99
      near[#near + 1] = { b = b, gap = lo <= L and (L - lo) or (lo - L) * 3 + 5 }
    end
  end
  table.sort(near, function(x, y) if x.gap ~= y.gap then return x.gap < y.gap end return x.b[2] < y.b[2] end)
  if #near > 0 then rows[#rows + 1] = { h = "More " .. f.n:lower() .. "s, the closest to level " .. L .. " first" } end
  for k = 1, math.min(8, #near) do
    local b = near[k].b
    local kn = {}
    for _, x in ipairs(PP.Knows(b[1])) do kn[#kn + 1] = x[1] .. " " .. x[2] end
    rows[#rows + 1] = { t = b[2], d = "Level " .. tostring(b[3]) .. (b.elite and ", elite" or "") .. (b.rare and ", rare" or "") .. "  ·  " .. tostring(b[4])
                        .. (#kn > 0 and ("\nTeaches " .. table.concat(kn, ", ")) or ""), face = b[1], tex = Icon(f.icon), dim = (tonumber(tostring(b[3]):match("%d+")) or 99) > L or nil,
                        m = b[5], x = b[6] and b[6] / 100, y = b[7] and b[7] / 100, actLabel = "Show", act = function() PP.Pick(b[1]) end }
  end
end

---------------------------------------------------------------------------
-- In the world: a tooltip line and a paw by the target (hunters; Settings turns them off)
---------------------------------------------------------------------------
function PP.On(key)
  local v = NS.cdb and NS.cdb["petPlan" .. key]
  if v == nil then return IsHunter() end
  return v and true or false
end
function PP.TipLines(u)
  local out = {}
  local f = u.f
  local m = List(Num().fam)[f.n] or { 0, 0, 0 }
  local L = math.max(1, math.min(60, UnitLevel("player") or 1))
  out[1] = string.format("%s: damage %s, armor %s, health %s", f.n, Pct(m[1]), Pct(m[2]), Pct(m[3]))
  local o = PP.Numbers(f, L, {}, u.npc)
  out[2] = string.format("Yours at %d: about %d health, %s damage a second", L, o.hp, One(o.dps))
  local kn = {}
  for _, x in ipairs(PP.Knows(u.npc)) do kn[#kn + 1] = x[1] .. " " .. x[2] end
  if #kn > 0 then out[#out + 1] = "Teaches " .. table.concat(kn, ", ") end
  if u.level > L then out[#out + 1] = "Too high to tame yet" end
  return out
end

local paw
local function Paw()
  if not (PP.On("Paw") and TargetFrame) then if paw then paw:Hide() end return end
  local u = PP.Unit("target")
  if not u then if paw then paw:Hide() end return end
  if not paw then
    paw = Lk.Icon(UIParent, 26)
    paw:SetFrameStrata("MEDIUM")
    paw:SetPoint("RIGHT", TargetFrame, "LEFT", 2, 6)
    paw.edge:SetColor(Lk.GOLD)
    paw:SetScript("OnClick", function()
      local t = PP.FromUnit("target")
      if t then PP.Open() end
    end)
    paw.about = function()
      local t = PP.Unit("target")
      Lk.TipLine(t and t.name or "Pet planner", C.accent)
      for _, l in ipairs(t and PP.TipLines(t) or {}) do Lk.TipLine(l) end
      Lk.TipLine("Click: see it in the pet planner.", C.dim)
    end
  end
  paw:Set(Icon(u.f.icon))
  paw:Show()
end

function PP:Init()
  NS.On("PLAYER_TARGET_CHANGED", function()
    local u = PP.Unit("target")
    if u then Note(u) end
    if PP.Shown() then
      if u and PP.State().follow then PP.FromUnit("target") end
      Redo()
    end
    Paw()
  end)
  NS.On("UNIT_PET", function(unit) if unit == "player" then NS.Debounce("readPet", 2, function() NS.Safe("pet", PP.ReadPet) end) end end)
  if IsHunter() then C_Timer.After(6, function() NS.Safe("pet", PP.ReadPet) end) end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
      if tip ~= GameTooltip or not PP.On("Tip") then return end
      NS.Safe("beast tooltip", function()
        local u = PP.Unit("mouseover")
        if not u then return end
        for k, l in ipairs(PP.TipLines(u)) do
          tip:AddLine((k == 1 and ("|cff" .. NS.HEX.accent .. "Sunstone:|r ") or "") .. l, C.text[1], C.text[2], C.text[3], false)
        end
      end)
    end)
  end
  NS.Setting("Hunter pets", "Beasts on tooltips", "Pointing at a wild beast shows what it would be as your pet and what it teaches.", function() return PP.On("Tip") end, function(on) NS.cdb.petPlanTip = on and true or false end)
  NS.Setting("Hunter pets", "Paw by the target", "A small button by the target frame when you target a beast hunters can have: opens the pet planner on it.", function() return PP.On("Paw") end,
    function(on) NS.cdb.petPlanPaw = on and true or false; Paw() end)
  NS.Command("pet", "- the pet planner, on the beast you target (or /sun pet <name>)", function(rest)
    rest = (rest or ""):lower()
    if rest ~= "" then
      Index()
      for npc, x in pairs(byNpc) do if x.b[2]:lower():find(rest, 1, true) then PP.Open(npc) return end end
      for n in pairs(famOf) do if n:lower():find(rest, 1, true) then PP.PickFamily(n); PP.Open() return end end
      NS.Print("No beast or family called that.")
      return
    end
    PP.FromUnit("target")
    PP.Open()
  end)
end
