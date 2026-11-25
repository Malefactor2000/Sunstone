-- Sunstone: your character in numbers (Gear tab, Character; /sun stats). You in 3D with your gear around you, every stat with what it really does,
-- how fast health and mana come back in and out of a fight, what each of your spells and attacks does against an enemy of a level you choose, with
-- your talents and spell power counted. Click a slot to try other gear on (what's in your bags, and the upgrades Sunstone knows): the picture and
-- every number change. The same is worked out for any upgrade Sunstone shows. Spell and talent numbers are the Forever client's own
-- (CharData.lua); how Intellect, Agility, Spirit, hit and armor work is Classic's rule, corrected by what the game says about you now.
-- Information only: it never equips, casts or changes anything.

local _, NS = ...
local CS = NS.Module("CharSheet")
NS.CharSheet = CS
local E, Lk, C, U = NS.Engine, NS.Look, NS.C, NS.Upgrades
local HEX = NS.HEX
local I = "Interface\\Icons\\"

local function Src() return type(_G.SunstoneChar) == "table" and _G.SunstoneChar or {} end
local function List(t) return type(t) == "table" and t or {} end
local function N(v) if v ~= nil and not (issecretvalue and issecretvalue(v)) and type(v) == "number" then return v end end
local function Call(fn, ...) -- a game function's answers, when this client has it
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, 9) end
end
local function Class() return (select(2, UnitClass("player"))) end
local function Level() return UnitLevel("player") or 1 end
local band = bit and bit.band or function(a, b) -- (the offline tests have no bit library)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end
local function Short(v)
  if v >= 100 or v == math.floor(v) then return string.format("%d", v + 0.5) end
  return string.format("%.1f", v)
end
local function Signed(v, f) return (v >= 0 and "+" or "-") .. (f and string.format(f, math.abs(v)) or Short(math.abs(v))) end

local STATS = { "str", "agi", "sta", "int", "spi" }
local STAT_NAME = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit" }
local SCHOOL = { [1] = { 1, "Physical" }, [2] = { 2, "Holy", "holy" }, [4] = { 3, "Fire", "fire" }, [8] = { 4, "Nature", "nature" }, [16] = { 5, "Frost", "frost" },
                 [32] = { 6, "Shadow", "shadow" }, [64] = { 7, "Arcane", "arcane" } }
local STR_AP = { WARRIOR = 2, PALADIN = 2, SHAMAN = 2, DRUID = 2 }
local AGI_AP = { ROGUE = 1, HUNTER = 1 }
local AGI_RAP = { HUNTER = 2, ROGUE = 1, WARRIOR = 1 }
local SPELL_CRIT = { PALADIN = { 14.77, 0.65 }, PRIEST = { 10.03, 0.82 }, SHAMAN = { 11.51, 0.80 }, MAGE = { 14.77, 0.65 }, WARLOCK = { 11.30, 0.82 }, DRUID = { 12.41, 0.79 } } -- Classic
local MANA_TICK = { DRUID = { 0.2, 15 }, HUNTER = { 0.2, 15 }, MAGE = { 0.25, 12.5 }, PALADIN = { 0.2, 15 }, PRIEST = { 0.25, 12.5 }, SHAMAN = { 0.2, 17 }, WARLOCK = { 0.2, 15 } }
local HEALTH_TICK = { DRUID = { 0.11, 1 }, HUNTER = { 0.43, -5.5 }, MAGE = { 0.11, 1 }, PALADIN = { 0.25, 0 }, PRIEST = { 0.15, 1.4 }, ROGUE = { 0.84, -13 },
                      SHAMAN = { 0.28, -3.6 }, WARLOCK = { 0.12, 1.5 }, WARRIOR = { 1.26, -22.6 } }
local CASTER = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true }

---------------------------------------------------------------------------
-- Your talents' effects -> { { aura, what, what2, mask, value }, ... }
---------------------------------------------------------------------------
function CS.Talents(ranks)
  local out = {}
  local T = NS.Talents
  if not ranks then
    if not (T and T.Read) then return out end
    pcall(T.Read)
    ranks = T.bySpell
  end
  for spell, rank in pairs(List(ranks)) do
    for _, e in ipairs(List(List(Src().talents)[spell])) do
      local v = rank > 0 and (e[5][rank] or e[5][#e[5]])
      if v and v ~= 0 then out[#out + 1] = { e[1], e[2], e[3], e[4], v, spell } end
    end
  end
  return out
end
local function StatPct(tal, k) -- a talent's "+X% Stamina"
  local bit1 = 2 ^ (k - 1)
  local p = 0
  for _, e in ipairs(tal) do
    if e[1] == 137 and (e[3] ~= 0 and band(e[3], bit1) ~= 0 or (e[3] == 0 and (e[2] == -1 or e[2] == k - 1))) then p = p + e[5] end
  end
  return 1 + p / 100
end

---------------------------------------------------------------------------
-- What the game says about you now
---------------------------------------------------------------------------
local live, liveAt
function CS.Live(fresh)
  local now = GetTime()
  if live and not fresh and now - liveAt < 1 then return live end
  local class, L = Class(), Level()
  local s = { class = class, L = L, sp = {}, scrit = {} }
  for k, n in ipairs(STATS) do
    local base, eff = Call(UnitStat, "player", k)
    s[n] = N(eff) or N(base)
  end
  s.hp, s.mana = N(Call(UnitHealthMax, "player")), N(Call(UnitPowerMax, "player", 0))
  if s.mana == 0 or class == "WARRIOR" or class == "ROGUE" then s.mana = nil end
  local _, armor = Call(UnitArmor, "player")
  s.armor = N(armor)
  for _, x in pairs(SCHOOL) do
    if x[1] > 1 then
      s.sp[x[1]] = N(Call(GetSpellBonusDamage, x[1])) or 0
      s.scrit[x[1]] = N(Call(GetSpellCritChance, x[1])) or 0
    end
  end
  s.heal = N(Call(GetSpellBonusHealing)) or 0
  local b, p, n = Call(UnitAttackPower, "player")
  s.ap = N(b) and N(b) + (N(p) or 0) + (N(n) or 0)
  b, p, n = Call(UnitRangedAttackPower, "player")
  s.rap = N(b) and N(b) + (N(p) or 0) + (N(n) or 0)
  s.mcrit, s.rcrit = N(Call(GetCritChance)), N(Call(GetRangedCritChance))
  s.hit, s.shit = N(Call(GetHitModifier)) or 0, N(Call(GetSpellHitModifier)) or 0
  s.haste = N(Call(UnitSpellHaste, "player")) or 0
  s.dodge, s.parry, s.block = N(Call(GetDodgeChance)), N(Call(GetParryChance)), N(Call(GetBlockChance))
  local rest, cast = Call(GetManaRegen)
  if s.mana then s.rest, s.cast = N(rest), N(cast) end
  local lo, hi, olo, ohi = Call(UnitDamage, "player")
  local sm, so = Call(UnitAttackSpeed, "player")
  s.speed, s.speed2 = N(sm), N(so)
  if N(lo) and N(hi) then s.lo, s.hi = lo, hi end
  if N(olo) and N(ohi) and s.speed2 then s.olo, s.ohi = olo, ohi end
  local rs, rlo, rhi = Call(UnitRangedDamage, "player")
  if N(rs) and rs > 0 and N(rlo) and N(rhi) and rhi > 0 then s.rspeed, s.rlo, s.rhi = rs, rlo, rhi end
  s.hp5 = 0
  for slot = 1, 18 do s.hp5 = s.hp5 + (CS.Stats(GetInventoryItemLink("player", slot)).hp5 or 0) end
  s.tal = CS.Talents()
  s.mult = {}
  for k, st in ipairs(STATS) do s.mult[st] = StatPct(s.tal, k) end
  s.hpPct, s.manaPct = 1, 1
  for _, e in ipairs(s.tal) do
    if e[1] == 133 then s.hpPct = s.hpPct + e[5] / 100 elseif e[1] == 132 and e[2] == 0 then s.manaPct = s.manaPct + e[5] / 100 end
  end
  -- what a point of Agility and Intellect is worth in critical strikes: the game's own, else Classic's
  local ag, it = N(Call(GetCritChanceFromAgility, "player")), N(Call(GetSpellCritChanceFromIntellect, "player"))
  if ag and s.agi and s.agi > 5 and ag > 0 then s.agiCrit = ag / s.agi end
  if it and s.int and s.int > 5 and it > 0 then s.intCrit = it / s.int; s.intLive = true
  elseif SPELL_CRIT[class] then s.intCrit = 1 / (SPELL_CRIT[class][1] + SPELL_CRIT[class][2] * L) end
  local m = MANA_TICK[class]
  if m and s.rest and s.spi and s.rest > 0 then
    local guess = (s.spi * m[1] + m[2]) / 2
    s.spiMana = m[1] / 2 * math.max(0.3, math.min(3, s.rest / guess))
    s.castShare = s.cast and s.cast / s.rest or 0
  end
  local h = HEALTH_TICK[class]
  if h and s.spi then
    s.hpRest = math.max(0, s.spi * h[1] + h[2]) / 2
    s.spiHp = h[1] / 2
    local seen = NS.cdb and type(NS.cdb.regen) == "table" and NS.cdb.regen
    if seen and N(seen.hp) and seen.L == L then s.hpSeen = seen.hp end
  end
  live, liveAt = s, now
  return s
end

---------------------------------------------------------------------------
-- Gear: an item's stats, and what a change of gear changes
---------------------------------------------------------------------------
local function Weapon(link) -- low, high, seconds a swing (from the game's own tooltip)
  if not (link and C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
  local ok, d = pcall(C_TooltipInfo.GetHyperlink, link)
  if not (ok and type(d) == "table") then return nil end
  local lo, hi, sp
  for _, l in ipairs(List(d.lines)) do
    for _, t in ipairs({ l.leftText, l.rightText }) do
      if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then
        local a, b2 = t:match("^(%d+) %- (%d+)")
        if a and not lo then lo, hi = tonumber(a), tonumber(b2) end
        local s = t:match("(%d+%.%d+)$")
        if s and t:find("Speed", 1, true) then sp = tonumber(s) end
      end
    end
  end
  if lo and sp and sp > 0.5 then return lo, hi, sp end
end

local itemCache = {}
function CS.Stats(link) -- short stat keys, and "w" for weapons
  if not link then return {} end
  local c = itemCache[link]
  if c then return c end
  c = U.Stats(link)
  local _, _, _, _, _, classID = NS.GetItemInfoInstant(link)
  if classID == 2 then
    local lo, hi, sp = Weapon(link)
    if lo then c.w = { lo, hi, sp } end
  end
  if next(c) then itemCache[link] = c end
  return c
end

local function Worn(slot) return GetInventoryItemLink("player", slot) end
local function EquipLoc(link) return link and select(4, NS.GetItemInfoInstant(link)) end

-- Adds the difference of putting link into slot (nil = taking it off) to d; state of both hands counted
function CS.AddChange(d, slot, link, plan)
  local old = plan and plan[slot] or Worn(slot)
  for k, v in pairs(CS.Stats(old)) do
    if k ~= "w" and k ~= "dps" then d[k] = (d[k] or 0) - v end
  end
  for k, v in pairs(CS.Stats(link)) do
    if k ~= "w" and k ~= "dps" then d[k] = (d[k] or 0) + v end
  end
  if slot == 16 or slot == 17 or slot == 18 then
    d.weapons = d.weapons or {}
    d.weapons[slot] = { CS.Stats(old), CS.Stats(link) }
  end
  if slot == 16 and link and EquipLoc(link) == "INVTYPE_2HWEAPON" and Worn(17) then
    for k, v in pairs(CS.Stats(Worn(17))) do if k ~= "w" and k ~= "dps" then d[k] = (d[k] or 0) - v end end
    d.offGone = true
  end
  return d
end

local function Rating(k) local r = E.Data().rating; return type(r) == "table" and r[k] or nil end

-- A new state from what you are and a difference of gear
function CS.With(s, d)
  local o = {}
  for k, v in pairs(s) do o[k] = v end
  o.sp, o.scrit = {}, {}
  for k, v in pairs(s.sp) do o.sp[k] = v end
  for k, v in pairs(s.scrit) do o.scrit[k] = v end
  o.d = d
  local dst = {}
  for _, n in ipairs(STATS) do
    dst[n] = (d[n] or 0) * (s.mult[n] or 1)
    if o[n] then o[n] = o[n] + dst[n] end
  end
  if o.hp then o.hp = o.hp + (dst.sta * 10 + (d.hp or 0)) * s.hpPct end
  if o.mana then o.mana = o.mana + (dst.int * 15 + (d.mana or 0)) * s.manaPct end
  if o.armor then o.armor = o.armor + (d.armor or 0) + dst.agi * 2 end
  local ap = (d.ap or 0) + dst.str * (STR_AP[s.class] or 1) + dst.agi * (AGI_AP[s.class] or 0)
  local rap = (d.ap or 0) + (d.rap or 0) + dst.agi * (AGI_RAP[s.class] or 0)
  if o.ap then o.ap = o.ap + ap end
  if o.rap then o.rap = o.rap + rap end
  -- spell power: the plain kind, a school's own, and talents that turn a stat into it
  local all = d.sp or 0
  for mask, x in pairs(SCHOOL) do
    if x[3] then
      local extra = 0
      for _, e in ipairs(s.tal) do
        if e[1] == 174 and band(e[2], mask) ~= 0 then
          for k, n in ipairs(STATS) do if band(math.max(0, e[3]), 2 ^ (k - 1)) ~= 0 then extra = extra + dst[n] * e[5] / 100 end end
        end
      end
      o.sp[x[1]] = o.sp[x[1]] + all + (d[x[3]] or 0) + extra
    end
  end
  o.heal = o.heal + all + (d.heal or 0)
  local function Pct(...) local t = 0 for _, k in ipairs({ ... }) do local r = Rating(k); if d[k] and r and r > 0 then t = t + d[k] / r end end return t end
  local crit = Pct("crit")
  for k, v in pairs(o.scrit) do o.scrit[k] = v + crit + Pct("scrit") + dst.int * (s.intCrit or 0) end
  if o.mcrit then o.mcrit = o.mcrit + crit + dst.agi * (s.agiCrit or 0) end
  if o.rcrit then o.rcrit = o.rcrit + crit + dst.agi * (s.agiCrit or 0) end
  o.hit, o.shit = o.hit + Pct("hit"), o.shit + Pct("hit", "shit")
  o.haste = o.haste + Pct("haste", "shaste")
  if o.dodge then o.dodge = o.dodge + Pct("dodge") end
  if o.parry then o.parry = o.parry + Pct("parry") end
  if o.block then o.block = o.block + Pct("block") end
  local mp = (d.mp5 or 0) / 5
  if o.rest then
    local sp = dst.spi * (s.spiMana or 0)
    o.rest = o.rest + mp + sp
    if o.cast then o.cast = o.cast + mp + sp * (s.castShare or 0) end
  end
  if o.hpRest then o.hpRest = math.max(0, o.hpRest + dst.spi * (s.spiHp or 0)) + (d.hp5 or 0) / 5 end
  o.hp5 = (s.hp5 or 0) + (d.hp5 or 0)
  -- weapons: the swing's own damage changes with the weapon, and 14 attack power are one damage a second
  local function Swing(lo, hi, speed, slot, power)
    if not (lo and speed and speed > 0) then return lo, hi, speed end
    local w = d.weapons and d.weapons[slot]
    local a, b = w and w[1], w and w[2]
    if b and b.w then
      local ow = a and a.w
      local base = ow and { lo - ow[1], hi - ow[2], ow[3] } or nil
      local perSec = base and (base[1] + base[2]) / 2 / math.max(0.5, speed) or (power and s.ap or 0) / 14
      local ns = b.w[3] * (ow and speed / ow[3] or 1)
      lo, hi, speed = b.w[1] + perSec * ns, b.w[2] + perSec * ns, ns
    elseif w and b and (b.dps or (a and a.dps)) then
      local gain = ((b.dps or 0) - (a and a.dps or 0)) * speed
      lo, hi = math.max(0, lo + gain), math.max(0, hi + gain)
    end
    return lo + power / 14 * speed, hi + power / 14 * speed, speed
  end
  o.lo, o.hi, o.speed = Swing(s.lo, s.hi, s.speed, 16, ap)
  o.olo, o.ohi, o.speed2 = Swing(s.olo, s.ohi, s.speed2, 17, ap * 0.5)
  if d.offGone then o.olo, o.ohi = nil, nil end
  o.rlo, o.rhi, o.rspeed = Swing(s.rlo, s.rhi, s.rspeed, 18, (s.class == "HUNTER" or s.class == "ROGUE" or s.class == "WARRIOR") and rap or 0)
  return o
end

function CS.Hit(lo, hi, speed) return lo and speed and speed > 0 and (lo + hi) / 2 / speed or nil end

---------------------------------------------------------------------------
-- Enemies
---------------------------------------------------------------------------
function CS.Enemy(L)
  local e = List(Src().enemy)[math.max(1, math.min(63, L))] or { 100, 100, 5, 2 }
  return { L = L, hp = e[1], armor = e[2], hit = e[3], speed = e[4] }
end
function CS.Reduction(armor, by) return math.max(0, math.min(0.75, armor / (armor + 400 + 85 * by))) end
function CS.SpellHit(you, them, bonus)
  local d = them - you
  local h = d >= 3 and 83 - (d - 3) * 11 or 96 - math.max(-3, d)
  return math.max(1, math.min(99, h + (bonus or 0))) / 100
end
function CS.MeleeHit(you, them, bonus) -- missed, dodged (from behind it's all you have)
  local d = math.max(0, (them - you) * 5)
  local miss = d > 10 and 6 + (d - 10) * 0.4 or 5 + d * 0.1
  local dodge = 5 + d * 0.1
  return 1 - math.max(0, miss - (bonus or 0)) / 100 - dodge / 100
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
local function Knows(id)
  for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false, C_SpellBook and C_SpellBook.IsSpellKnown or false }) do
    if fn then
      local ok, v = pcall(fn, id)
      if ok and v and not (issecretvalue and issecretvalue(v)) then return true end
    end
  end
  return false
end
-- the best rank you know of each spell that deals damage or heals
local knownList, knownAt
function CS.Known()
  if knownList and GetTime() - knownAt < 5 then return knownList end
  local best, order = {}, {}
  for id, e in pairs(List(List(Src().spells)[Class() or ""])) do
    if Knows(id) then
      local n = NS.SpellName(id)
      if n and (not best[n] or best[n][2] < e[2]) then
        if not best[n] then order[#order + 1] = n end
        best[n] = { id, e[2], e }
      end
    end
  end
  table.sort(order)
  local out = {}
  for _, n in ipairs(order) do out[#out + 1] = { n = n, id = best[n][1], e = best[n][3] } end
  knownList, knownAt = out, GetTime()
  return out
end

function CS.Forget() live, knownList = nil, nil end

local function Mod(s, e, op) -- what your talents add to a spell: percent, flat
  local pct, flat = 0, 0
  for _, t in ipairs(s.tal) do
    if (t[1] == 107 or t[1] == 108) and t[2] == op and type(t[4]) == "table" then
      local on = false
      for k = 1, 4 do if band(t[4][k] or 0, e[8][k] or 0) ~= 0 then on = true end end
      if on then if t[1] == 108 then pct = pct + t[5] else flat = flat + t[5] end end
    end
  end
  return pct, flat
end

-- One cast against an enemy -> numbers (nil where the game's own files don't say)
function CS.Cast(id, e, s, enemy)
  local L = s.L
  local x = { id = id, school = e[1], heal = 0, hit = 0, lo = 0, hi = 0, dot = 0, hot = 0, absorb = 0, bonus = 0, parts = {} }
  local lvl = math.max(0, math.min(L, e[3] > 0 and e[3] or L) - e[2])
  local sc = SCHOOL[e[1]] or SCHOOL[1]
  local phys = e[1] == 1
  local sp = not phys and (s.sp[sc[1]] or 0) or 0
  local pDmg, pAll = (Mod(s, e, 0)), (Mod(s, e, 8))
  local pDot = (Mod(s, e, 22))
  local school = 0
  if not phys then for _, t in ipairs(s.tal) do if t[1] == 79 and band(math.max(0, t[2]), e[1]) ~= 0 then school = school + t[5] end end end
  local mHit, mDot = (1 + (pDmg + pAll) / 100) * (1 + school / 100), (1 + (pDot + pAll) / 100) * (1 + school / 100)
  x.talHit, x.talDot = mHit, mDot
  local weapon, pct, flat
  local dpct, dflat = Mod(s, e, 1)
  for k = 9, #e do
    local f = e[k]
    local kind, b, per, var, coef, period, ticks, combo = f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]
    b = b + (per or 0) * lvl
    if kind == "hit" or kind == "ticks" then
      local n = kind == "ticks" and ticks or 1
      local cb = combo and combo > 0 and 5 or 0
      local base = b + cb * (combo or 0)
      local add = sp * (coef or 0)
      x.lo, x.hi = x.lo + (base * (1 - (var or 0) / 2) + add) * mHit * n, x.hi + (base * (1 + (var or 0) / 2) + add) * mHit * n
      x.bonus = x.bonus + add * mHit * n
      x.coef = (x.coef or 0) + (coef or 0) * n
      if cb > 0 then x.combo = 5 end
      x.base = (x.base or 0) + base * n
    elseif kind == "dot" then
      local n = ticks
      if dflat ~= 0 or dpct ~= 0 then n = math.max(1, math.floor(((period * ticks) * (1 + dpct / 100) + dflat / 1000) / period + 0.01)) end
      local base = b + (combo and combo > 0 and 5 * combo or 0)
      local add = sp * (coef or 0)
      x.dot = x.dot + (base + add) * n * mDot
      x.bonus = x.bonus + add * n * mDot
      x.coef = (x.coef or 0) + (coef or 0) * n
      x.dotBase = (x.dotBase or 0) + base * n
      x.dotSecs = period * n
    elseif kind == "heal" then
      local add = s.heal * (coef or 0)
      x.healLo, x.healHi = (b * (1 - (var or 0) / 2) + add) * mHit, (b * (1 + (var or 0) / 2) + add) * mHit
      x.heal = x.heal + (b + add) * mHit
      x.bonus = x.bonus + add * mHit
      x.coef = (x.coef or 0) + (coef or 0)
      x.base = (x.base or 0) + b
    elseif kind == "hot" then
      local add = s.heal * (coef or 0)
      x.hot = x.hot + (b + add) * ticks * mDot
      x.bonus = x.bonus + add * ticks * mDot
      x.coef = (x.coef or 0) + (coef or 0) * ticks
      x.dotBase = (x.dotBase or 0) + b * ticks
      x.dotSecs = period * ticks
    elseif kind == "absorb" then
      x.absorb = x.absorb + b + s.heal * (coef or 0)
    elseif kind == "weapon" or kind == "norm" then
      weapon, flat = kind, (flat or 0) + b
    elseif kind == "pct" then
      pct = b
    end
  end
  if weapon then
    local rng = s.class == "HUNTER" and (NS.SpellName(id) or ""):find("Shot", 1, true)
    local lo, hi = s.lo, s.hi
    if rng then lo, hi = s.rlo, s.rhi end
    if lo then
      local m = (pct or 100) / 100 * mHit
      x.lo, x.hi = x.lo + (lo + flat) * m, x.hi + (hi + flat) * m
      x.weapon, x.flat, x.wpct = true, flat, pct
    end
  end
  -- cast time, cooldown, cost: the game's own answer (your talents and haste are in it)
  local info = C_Spell and C_Spell.GetSpellInfo and Call(C_Spell.GetSpellInfo, id)
  local ms = type(info) == "table" and N(info.castTime)
  if not ms and GetSpellInfo then ms = N((select(4, Call(GetSpellInfo, id)))) end
  x.cast = (ms or e[4]) / 1000
  if s.haste ~= (CS.Live().haste or 0) and x.cast > 0 then x.cast = x.cast * (1 + (CS.Live().haste or 0) / 100) / (1 + s.haste / 100) end
  if e[7] == 1 then x.channel = true; x.cast = math.max(1.5, e[6]) end
  x.time = math.max(phys and s.class ~= "HUNTER" and (s.class == "ROGUE" or s.class == "DRUID") and 1 or 1.5, x.cast)
  local cp, cf = Mod(s, e, 11)
  x.cd = math.max(0, e[5] * (1 + cp / 100) + cf / 1000)
  local cost = C_Spell and C_Spell.GetSpellPowerCost and Call(C_Spell.GetSpellPowerCost, id)
  local c1 = type(cost) == "table" and cost[1]
  if type(c1) == "table" then x.cost, x.power = N(c1.cost), N(c1.type) or 0 end
  -- critical strikes
  local _, cflat = Mod(s, e, 7)
  x.crit = (phys and (s.class == "HUNTER" and s.rcrit or s.mcrit) or s.scrit[sc[1]] or 0) + cflat
  local cdm = (Mod(s, e, 15))
  local cm = phys and 2 or 1.5
  x.critBy = 1 + (cm - 1) * (1 + cdm / 100)
  -- against the enemy
  local them = enemy and enemy.L or L
  if x.heal > 0 or x.hot > 0 or x.absorb > 0 then
    x.chance = 1
  else
    x.chance = (phys or (s.class == "HUNTER" and not (x.coef and x.coef > 0))) and CS.MeleeHit(L, them, s.hit) or CS.SpellHit(L, them, s.shit + (select(2, Mod(s, e, 16))))
  end
  x.less = phys and enemy and x.lo > 0 and CS.Reduction(enemy.armor, L) or 0
  local direct = (x.lo + x.hi) / 2
  x.direct = direct
  local withCrit = direct * (1 + x.crit / 100 * (x.critBy - 1))
  x.avg = (withCrit * (1 - x.less) + x.dot) * x.chance
  x.avgHeal = x.heal * (1 + x.crit / 100 * 0.5) + x.hot
  x.total = x.avg > 0 and x.avg or (x.avgHeal > 0 and x.avgHeal or x.absorb)
  x.kind = x.avg > 0 and "damage" or x.avgHeal > 0 and "healing" or x.absorb > 0 and "absorbed" or nil
  x.per = x.total / x.time
  if x.cost and x.cost > 0 and x.power == 0 then x.mana = x.total / x.cost end
  if enemy and x.avg > 0 then x.share = x.avg / enemy.hp end
  return x
end

---------------------------------------------------------------------------
-- What a piece of gear would change, in a few lines (for upgrades, tooltips and the picker)
---------------------------------------------------------------------------
local function Slot(link) -- the slot an item would go to: the one it's the most help in
  local slots = U.SLOTS[EquipLoc(link) or ""]
  if not slots then return nil end
  if #slots == 1 then return slots[1] end
  local best, bs
  for _, sl in ipairs(slots) do
    local w = Worn(sl)
    local sc = 0
    if w then for k, v in pairs(CS.Stats(w)) do if type(v) == "number" then sc = sc + v end end end
    if not bs or sc < bs then best, bs = sl, sc end
  end
  return best
end
CS.SlotOf = Slot

local function Line(out, a, b, name, f, dec, extra)
  if not (a and b) then return end
  local v = b - a
  if math.abs(v) < (dec or 0.5) then return end
  out[#out + 1] = { string.format("%s %s%s", Signed(v, f), name, extra and extra(v) or ""), v }
end

-- -> { { text, change }, ... } best first; s0 = now, s1 = with it
function CS.Compare(s0, s1, spells)
  local out = {}
  Line(out, s0.hp, s1.hp, "health")
  Line(out, s0.mana, s1.mana, "mana")
  Line(out, s0.armor, s1.armor, "armor", nil, nil, function()
    local a, b = CS.Reduction(s0.armor, s0.L), CS.Reduction(s1.armor, s0.L)
    return string.format(" (%s%% less from weapon hits)", Signed((b - a) * 100, "%.1f"))
  end)
  local e0, e1 = CS.Hit(s0.lo, s0.hi, s0.speed), CS.Hit(s1.lo, s1.hi, s1.speed)
  if not CASTER[s0.class] or (s0.class == "PALADIN" or s0.class == "SHAMAN") then Line(out, e0, e1, "damage a second swinging", "%.1f", 0.05) end
  Line(out, CS.Hit(s0.rlo, s0.rhi, s0.rspeed), CS.Hit(s1.rlo, s1.rhi, s1.rspeed), s0.class == "HUNTER" and "damage a second shooting" or CASTER[s0.class] and "damage a second with the wand" or "damage a second at range", "%.1f", 0.05)
  if CASTER[s0.class] or s0.class == "HUNTER" then
    Line(out, s0.rest, s1.rest, "mana a second resting", "%.2f", 0.005)
    Line(out, s0.cast, s1.cast, "mana a second while casting", "%.2f", 0.005)
  end
  Line(out, s0.hpRest, s1.hpRest, "health a second out of combat", "%.2f", 0.005)
  if (s1.hp5 or 0) ~= 0 and (s1.hp5 or 0) ~= (s0.hp5 or 0) then out[#out + 1] = { Signed(((s1.hp5 or 0) - (s0.hp5 or 0)) / 5, "%.1f") .. " health a second in a fight", (s1.hp5 or 0) - (s0.hp5 or 0) } end
  if CASTER[s0.class] then
    local c0, c1 = 0, 0
    for k, v in pairs(s0.scrit) do if v >= c0 then c0, c1 = v, s1.scrit[k] end end
    Line(out, c0, c1, "spell critical chance", "%.2f%%", 0.005)
    Line(out, s0.shit, s1.shit, "spell hit", "%.2f%%", 0.005)
  end
  if s0.class ~= "MAGE" and s0.class ~= "PRIEST" and s0.class ~= "WARLOCK" then
    Line(out, s0.mcrit, s1.mcrit, "critical chance", "%.2f%%", 0.005)
    Line(out, s0.hit, s1.hit, "hit", "%.2f%%", 0.005)
  end
  Line(out, s0.haste, s1.haste, "casting speed", "%.1f%%", 0.05)
  Line(out, s0.dodge, s1.dodge, "dodge", "%.2f%%", 0.005)
  local enemy = CS.Enemy(CS.EnemyLevel())
  local sp = {}
  for _, k in ipairs(spells or CS.Known()) do
    local a, b = CS.Cast(k.id, k.e, s0, enemy), CS.Cast(k.id, k.e, s1, enemy)
    if a.kind and b.total and a.total > 0 and math.abs(b.total - a.total) >= 0.05 then sp[#sp + 1] = { k.n, b.total - a.total, (b.total / a.total - 1) * 100, a.kind } end
  end
  table.sort(sp, function(x, y) return math.abs(x[2]) > math.abs(y[2]) end)
  return out, sp
end

function CS.Change(link, slot)
  slot = slot or Slot(link)
  if not slot then return nil end
  local s0 = CS.Live()
  local s1 = CS.With(s0, CS.AddChange({}, slot, link))
  return CS.Compare(s0, s1)
end
-- A talent at another rank: what it would change. (Stats the game already counts for you are scaled by the difference.)
function CS.TalentChange(spell, rank)
  local s0 = CS.Live()
  local ranks = {}
  for k, v in pairs(List(NS.Talents.bySpell)) do ranks[k] = v end
  ranks[spell] = rank
  local s1 = CS.With(s0, {})
  s1.tal = CS.Talents(ranks)
  local d = {}
  for k, n in ipairs(STATS) do
    local m = StatPct(s1.tal, k)
    if m ~= s0.mult[n] and s0[n] then d[n] = s0[n] * (m / s0.mult[n] - 1) / s0.mult[n] end
  end
  if next(d) then
    local tal = s1.tal
    s1 = CS.With(s0, d)
    s1.tal = tal
  end
  local function Sum(tal, aura, what) local t = 0 for _, e in ipairs(tal) do if e[1] == aura and (what == nil or e[2] == what) then t = t + e[5] end end return t end
  local function Diff(aura, what) return Sum(s1.tal, aura, what) - Sum(s0.tal, aura, what) end
  if s1.hp then s1.hp = s1.hp * (1 + Diff(133) / 100) end
  if s1.mana then s1.mana = s1.mana * (1 + Diff(132, 0) / 100) end
  if s1.mcrit then s1.mcrit = s1.mcrit + Diff(52) + Diff(290) end
  if s1.rcrit then s1.rcrit = s1.rcrit + Diff(52) + Diff(290) end
  for k, v in pairs(s1.scrit) do s1.scrit[k] = v + Diff(57) + Diff(290) end
  s1.hit, s1.shit = s1.hit + Diff(54), s1.shit + Diff(55)
  if s1.dodge then s1.dodge = s1.dodge + Diff(49) end
  if s1.parry then s1.parry = s1.parry + Diff(47) end
  if s1.cast and s1.rest then s1.cast = s1.cast + s1.rest * Diff(134) / 100 end
  if s1.armor then s1.armor = s1.armor * (1 + (Diff(101, 1) + Diff(142, 1)) / 100) end
  return CS.Compare(s0, s1)
end
-- one line for a list: "+34 health, +2.1 Shadow Bolt, ..."
function CS.ChangeText(link, n)
  local ok, out, sp = pcall(CS.Change, link)
  if not (ok and type(out) == "table") then return nil end
  local bits = {}
  for k = 1, math.min(2, #List(sp)) do bits[#bits + 1] = string.format("%s %s%s", sp[k][1], Signed(sp[k][2]), sp[k][4] == "damage" and " damage" or "") end
  for k = 1, math.min((n or 4) - #bits, #out) do bits[#bits + 1] = out[k][1] end
  return #bits > 0 and table.concat(bits, ", ") or nil
end
-- rows for an item's page
function CS.ItemRows(link)
  local slot = link and Slot(link)
  if not slot then return nil end
  local ok, out, sp = pcall(CS.Change, link, slot)
  if not ok then NS.Error("what it changes", out) return nil end
  if #out == 0 and #sp == 0 then return nil end
  local a, b = {}, {}
  for _, l in ipairs(out) do a[#a + 1] = string.format("|cff%s%s|r", l[2] >= 0 and HEX.good or HEX.warn, l[1]) end
  for k = 1, math.min(10, #sp) do
    b[#b + 1] = string.format("%s: |cff%s%s|r %s a cast (%s%%)", sp[k][1], sp[k][2] >= 0 and HEX.good or HEX.warn, Signed(sp[k][2]), sp[k][4], Signed(sp[k][3], "%.1f"))
  end
  local w = Worn(slot)
  local rows = { { h = "What it would change for you" } }
  rows[#rows + 1] = { t = w and ("Instead of " .. (NS.GetItemInfo(w) or "what you wear")) or "In an empty slot", d = table.concat(a, "\n"), still = true, i = w and tonumber(w:match("item:(%d+)")) or nil,
                      actLabel = "Try it on", act = function() CS.Try(slot, link); CS.Open() end }
  if #b > 0 then rows[#rows + 1] = { t = "Your spells and attacks, on average", d = table.concat(b, "\n"), still = true, tex = I .. "INV_Misc_Book_09" } end
  return rows
end

---------------------------------------------------------------------------
-- What's tried on (this session), the enemy's level
---------------------------------------------------------------------------
CS.plan = {}
function CS.Try(slot, link)
  if CS.plan[slot] == link then CS.plan[slot] = nil else CS.plan[slot] = link end
  CS.dress = true
end
function CS.EnemyLevel() return math.max(1, math.min(63, N(CS.enemyLevel) or Level())) end
function CS.State()
  local s0 = CS.Live()
  if not next(CS.plan) then return s0, s0 end
  local d = {}
  for slot, link in pairs(CS.plan) do CS.AddChange(d, slot, link) end
  return s0, CS.With(s0, d)
end

function CS.Candidates(slot) -- what could go in a slot: your bags, then what Sunstone knows you could get
  local out, seen = {}, {}
  local w = Worn(slot)
  if w then out[1] = { link = w, worn = true } end
  local function Add(link, e)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if not id or seen[id] then return end
    seen[id] = true
    out[#out + 1] = { link = link, e = e, bag = not e }
  end
  if w then seen[tonumber(w:match("item:(%d+)")) or 0] = true end
  local num = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local get = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  for bag = 0, 4 do
    for k = 1, (num and num(bag) or 0) do
      local link = get and Call(get, bag, k)
      if type(link) == "string" then
        for _, sl in ipairs(U.SLOTS[EquipLoc(link) or ""] or {}) do
          if sl == slot then
            local _, _, _, _, _, classID, sub = NS.GetItemInfoInstant(link)
            if (classID == 2 or classID == 4) and U.Can(classID, sub) then Add(link) end
          end
        end
      end
    end
  end
  local list = {}
  for _, e in ipairs(U.all or {}) do
    for _, sl in ipairs(e.slots or {}) do if sl == slot then list[#list + 1] = e end end
  end
  table.sort(list, function(a, b) return a.gain > b.gain end)
  for k = 1, math.min(40, #list) do
    local link = select(2, NS.GetItemInfo(list[k].id)) or ("item:" .. list[k].id)
    Add(link, list[k])
  end
  return out
end

---------------------------------------------------------------------------
-- The panel: you, your gear, your stats
---------------------------------------------------------------------------
local LEFT = { 1, 2, 3, 15, 5, 9, 10 }
local RIGHT = { 6, 7, 8, 11, 12, 13, 14 }
local LOW = { 16, 17, 18 }
local RACE = { Scourge = "Scourge", Orc = "Orc", Troll = "Troll", Tauren = "Tauren", Human = "Human", Dwarf = "Dwarf", Gnome = "Gnome", NightElf = "NightElf", BloodElf = "BloodElf", Draenei = "Draenei" }
local SZ, GAP = 36, 9

local function Redo() if NS.Window and NS.Window.Redo then NS.Window.Redo() end end
local function Info(slot) for _, x in ipairs(NS.Gear.SLOTS) do if x[1] == slot then return x[2], x[3] end end return "?", nil end

local function BestNow(slot)
  local best
  for _, e in ipairs(U.all or {}) do
    if e.src and e.src.ok and (e.reqLevel or 0) <= Level() then
      for _, sl in ipairs(e.slots or {}) do if sl == slot and (not best or e.gain > best.gain) then best = e end end
    end
  end
  return best
end

local function SlotButton(p, slot)
  local b = Lk.Icon(p, SZ)
  b.slot = slot
  b:SetScript("OnClick", function() CS.slot = CS.slot ~= slot and slot or nil; Redo() end)
  b.about = function(self)
    local label = Info(slot)
    if self.link then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) then Lk.TipLine(label, C.accent) end
      if CS.plan[slot] then Lk.TipLine("Tried on: not really worn.", Lk.GOLD) end
    else
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      Lk.TipLine(label .. ": empty", C.accent)
    end
    local e = BestNow(slot)
    if e then Lk.TipLine(string.format("An upgrade you can get: %s", e.name), C.good) end
    Lk.TipLine("Click: try other gear here.", C.dim)
  end
  return b
end

local function Make(row)
  local p = CreateFrame("Frame", nil, row)
  p.bg = NS.Rounded(p, C.surface, "round.png", 10)
  p.slots = {}
  p.view = Lk.Model(p, 236, 306, "dress")
  p.view:SetPoint("TOPLEFT", 10 + SZ + 6, -10)
  for k, sl in ipairs(LEFT) do p.slots[sl] = SlotButton(p, sl); p.slots[sl]:SetPoint("TOPLEFT", 10, -10 - (k - 1) * (SZ + GAP)) end
  for k, sl in ipairs(RIGHT) do p.slots[sl] = SlotButton(p, sl); p.slots[sl]:SetPoint("TOPLEFT", 10 + SZ + 6 + 236 + 6, -10 - (k - 1) * (SZ + GAP)) end
  for k, sl in ipairs(LOW) do p.slots[sl] = SlotButton(p, sl); p.slots[sl]:SetPoint("TOPLEFT", 10 + SZ + 6 + 55 + (k - 1) * (SZ + GAP), -10 - 306 - 7) end
  p.reset = NS.Button(p, "Take it all off again", 130, function() CS.plan = {}; CS.dress = true; Redo() end)
  p.reset:SetPoint("TOPLEFT", 10, -10 - 306 - 52)
  p.eText = Lk.Text(p, "GameFontHighlightSmall", C.text)
  p.minus = NS.Button(p, "-", 20, function() CS.enemyLevel = math.max(1, CS.EnemyLevel() - 1); Redo() end)
  p.plus = NS.Button(p, "+", 20, function() CS.enemyLevel = math.min(63, CS.EnemyLevel() + 1); Redo() end)
  p.mine = NS.Button(p, "Mine", 40, function() CS.enemyLevel = nil; Redo() end)
  p.name = Lk.Text(p, "GameFontNormal", C.accent)
  p.stats = {}
  return p
end

local function StatRow(p, k)
  local r = p.stats[k]
  if r then return r end
  r = CreateFrame("Frame", nil, p)
  r:SetHeight(15)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
  r.hl:Hide()
  r.name = Lk.Text(r, "GameFontHighlightSmall", C.text)
  r.name:SetPoint("LEFT", 6, 0)
  r.value = Lk.Text(r, "GameFontHighlightSmall", C.text, "RIGHT")
  r.value:SetPoint("RIGHT", -6, 0)
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if not self.about then return end
    self.hl:Show()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    NS.Safe("stat", self.about)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
  p.stats[k] = r
  return r
end

-- the stat list: { heading } or { name, value text, now, new, tooltip }
function CS.StatRows(s0, s1)
  local out = {}
  local L, cl = s0.L, s0.class
  local enemy = CS.Enemy(CS.EnemyLevel())
  local spells = CS.Known()
  local function H(t) out[#out + 1] = { h = t } end
  local function Add(name, a, b, f, tip, dec)
    if a == nil or b == nil then return end
    local d = b - a
    local text = f(b)
    if math.abs(d) >= (dec or 0.5) then text = string.format("%s  |cff%s%s|r", text, d > 0 and HEX.good or HEX.warn, Signed(d, (dec or 0.5) < 0.5 and "%.2f" or nil)) end
    out[#out + 1] = { name, text, tip }
  end
  local int = function(v) return string.format("%d", v + 0.5) end
  local pct = function(v) return string.format("%.2f%%", v) end
  local ps = function(v) return string.format("%.1f a second", v) end
  local T = Lk.TipLine
  -- one more of a stat, through everything it touches
  local function More(key, n)
    local s2 = CS.With(s1, { [key] = n })
    local lines, sp = CS.Compare(s1, s2, spells)
    T(string.format("%d more would give you:", n), C.accent)
    for _, l in ipairs(lines) do T(l[1], C.good) end
    for k = 1, math.min(6, #sp) do T(string.format("%s: %s a cast", sp[k][1], Signed(sp[k][2], "%.2f")), C.good) end
    if #lines == 0 and #sp == 0 then T("nothing that can be worked out", C.dim) end
  end
  H("Attributes")
  local about = {
    str = "Attack power (" .. (STR_AP[cl] or 1) .. " each), and how much a shield blocks.",
    agi = "Critical strikes with weapons, dodge, 2 armor each" .. (AGI_RAP[cl] and ", ranged attack power" or "") .. ".",
    sta = "10 health each. (Out of a fight, health comes back by Spirit; a bigger pool only takes longer to fill.)",
    int = "15 mana each, spell critical strikes, and how fast weapon skills go up.",
    spi = "How fast mana comes back while you haven't cast for five seconds, and health out of combat.",
  }
  for _, n in ipairs(STATS) do
    Add(STAT_NAME[n], s0[n], s1[n], int, function()
      T(STAT_NAME[n] .. ": " .. int(s1[n] or 0), C.accent)
      T(about[n])
      if (s0.mult[n] or 1) ~= 1 then T(string.format("Your talents make each point from gear count %.2f.", s0.mult[n]), C.good) end
      T(" ")
      More(n, 10)
    end)
  end
  H("Staying alive")
  Add("Health", s0.hp, s1.hp, int, function()
    T("Health: " .. int(s1.hp), C.accent)
    T(string.format("An ordinary level %d enemy hits for about %d every %.1f seconds before armor: about %d hits, %d seconds, to bring you down.", enemy.L, enemy.hit + 0.5, enemy.speed,
      math.ceil(s1.hp / math.max(1, enemy.hit * (1 - CS.Reduction(s1.armor or 0, enemy.L)))), math.ceil(s1.hp / math.max(1, enemy.hit * (1 - CS.Reduction(s1.armor or 0, enemy.L)))) * enemy.speed))
  end)
  Add("Armor", s0.armor, s1.armor, int, function()
    T("Armor: " .. int(s1.armor), C.accent)
    T(string.format("A level %d enemy's weapon hits are %.1f%% weaker: about %d instead of %d. It does nothing against spells.", enemy.L, CS.Reduction(s1.armor, enemy.L) * 100,
      enemy.hit * (1 - CS.Reduction(s1.armor, enemy.L)) + 0.5, enemy.hit + 0.5))
    T(string.format("100 more armor: %.1f%% weaker.", CS.Reduction(s1.armor + 100, enemy.L) * 100), C.good)
  end)
  Add("Dodge", s0.dodge, s1.dodge, pct, function() T("Dodge", C.accent); T("Blows that don't land at all. Each level an enemy is above you takes a little off.") end, 0.005)
  if cl == "WARRIOR" or cl == "PALADIN" or cl == "ROGUE" or cl == "HUNTER" or cl == "SHAMAN" then
    if (s1.parry or 0) > 0 then Add("Parry", s0.parry, s1.parry, pct, nil, 0.005) end
    if (s1.block or 0) > 0 then Add("Block", s0.block, s1.block, pct, nil, 0.005) end
  end
  H("Coming back")
  Add("Health, out of combat", s0.hpRest, s1.hpRest, ps, function()
    T("Health out of combat", C.accent)
    T(string.format("About %.1f a second from Spirit (Classic's rule for your class), so about %d seconds from empty to full. A third more while sitting.", s1.hpRest, s1.hp and s1.hp / math.max(0.1, s1.hpRest) or 0))
    if s0.hpSeen then T(string.format("Measured on you: %.1f a second.", s0.hpSeen), C.good) end
    T("Food and bandages come on top.", C.dim)
  end, 0.005)
  Add("Health, in a fight", (s0.hp5 or 0) / 5, (s1.hp5 or 0) / 5, ps, function()
    T("Health in a fight", C.accent)
    T("Only what items say (\"health per 5 seconds\") and some talents, racials and spells: Spirit does nothing for health while you fight.")
  end, 0.005)
  Add("Mana, resting", s0.rest, s1.rest, ps, function()
    T("Mana when you haven't cast for five seconds", C.accent)
    T(string.format("%.2f a second (the game's own number): %d seconds from empty to full.", s1.rest, (s1.mana or 0) / math.max(0.1, s1.rest)))
    if s0.spiMana then T(string.format("10 Spirit: about %s a second.", Signed(s0.spiMana * 10 * (s0.mult.spi or 1), "%.2f")), C.good) end
  end, 0.005)
  Add("Mana, casting", s0.cast, s1.cast, ps, function()
    T("Mana while you're casting", C.accent)
    T(string.format("%.2f a second. For five seconds after each cast Spirit counts for nothing, or for the share your talents let through; \"mana per 5 seconds\" on items always counts.", s1.cast))
  end, 0.005)
  Add("Mana", s0.mana, s1.mana, int, function()
    T("Mana: " .. int(s1.mana), C.accent)
    local l = {}
    for _, k in ipairs(spells) do
      local x = CS.Cast(k.id, k.e, s1, enemy)
      if x.cost and x.cost > 0 and x.power == 0 and x.total > 0 then l[#l + 1] = { k.n, math.floor(s1.mana / x.cost), x.total * math.floor(s1.mana / x.cost), x.kind } end
    end
    table.sort(l, function(a, b) return a[3] > b[3] end)
    for k = 1, math.min(6, #l) do T(string.format("%s: %d casts, %d %s", l[k][1], l[k][2], l[k][3], l[k][4])) end
  end)
  if CASTER[cl] then
    H("Spells")
    local best, key = -1, 6
    for _, k in ipairs({ 6, 3, 5, 7, 4, 2 }) do if (s1.sp[k] or 0) > best then best, key = s1.sp[k], k end end
    local same = true
    for _, k in ipairs({ 2, 3, 4, 5, 6, 7 }) do if math.abs((s1.sp[k] or 0) - best) > 0.5 then same = false end end
    local names = { [2] = "Holy", [3] = "Fire", [4] = "Nature", [5] = "Frost", [6] = "Shadow", [7] = "Arcane" }
    Add(same and "Spell damage" or ("Spell damage (" .. names[key] .. ")"), s0.sp[key], s1.sp[key], int, function()
      T("Spell damage", C.accent)
      for _, k in ipairs({ 2, 3, 4, 5, 6, 7 }) do if not same then T(string.format("%s: %d", names[k], s1.sp[k] + 0.5)) end end
      T("What it adds to each cast now:", C.accent)
      for _, k in ipairs(spells) do
        local x = CS.Cast(k.id, k.e, s1, enemy)
        if x.coef and x.coef > 0 and x.kind == "damage" then T(string.format("%s: +%s (%d%% of it), of %s", k.n, Short(x.bonus), x.coef * 100 + 0.5, Short(x.direct + x.dot)), C.text, false) end
      end
      T(" ")
      More("sp", 10)
    end)
    Add("Healing", s0.heal, s1.heal, int, function()
      T("Healing", C.accent)
      local any
      for _, k in ipairs(spells) do
        local x = CS.Cast(k.id, k.e, s1, enemy)
        if x.coef and x.coef > 0 and x.kind ~= "damage" then any = true; T(string.format("%s: +%s of %s", k.n, Short(x.bonus), Short(x.total)), C.text, false) end
      end
      if not any then T("Added to your healing spells.") end
    end)
    Add("Spell critical", s0.scrit[key], s1.scrit[key], pct, function()
      T("Spell critical strikes", C.accent)
      T("A critical spell does half again as much (talents can raise that).")
      if s0.intCrit then T(string.format("%.0f Intellect give 1%%%s.", 1 / s0.intCrit, s0.intLive and "" or " (Classic's rule)"), C.good) end
    end, 0.005)
    Add("Spell hit", s0.shit, s1.shit, pct, function()
      T("Spell hit", C.accent)
      for d = 0, 3 do T(string.format("Level %d enemy: %.0f%% of your spells land", L + d, CS.SpellHit(L, L + d, s1.shit) * 100), C.text, false) end
      T("Classic's rule; 1% can always miss.", C.dim)
    end, 0.005)
    Add("Casting speed", s0.haste, s1.haste, function(v) return string.format("%+.1f%%", v) end, function()
      T("Casting speed", C.accent)
      T("Haste shortens casts: at 10% a 2.5 second cast takes 2.27 seconds. The table below counts it.")
    end, 0.05)
  end
  H("Weapons")
  if cl ~= "MAGE" and cl ~= "PRIEST" and cl ~= "WARLOCK" then
    Add("Attack power", s0.ap, s1.ap, int, function() T("Attack power", C.accent); T(string.format("14 of it are 1 damage a second: %.1f a second now.", s1.ap / 14)); More("ap", 14) end)
    Add("Critical", s0.mcrit, s1.mcrit, pct, function() T("Critical strikes", C.accent); T("A critical blow does double."); if s0.agiCrit then T(string.format("%.0f Agility give 1%%.", 1 / s0.agiCrit), C.good) end end, 0.005)
    Add("Hit", s0.hit, s1.hit, pct, function()
      T("Hit", C.accent)
      for d = 0, 3 do T(string.format("Level %d enemy: %.0f%% of your specials land", L + d, CS.MeleeHit(L, L + d, s1.hit) * 100), C.text, false) end
      T("Classic's rule, from behind, with your weapon skill at its best for your level.", C.dim)
    end, 0.005)
  end
  local function Swing(name, lo0, hi0, sp0, lo1, hi1, sp1)
    local a, b = CS.Hit(lo0, hi0, sp0), CS.Hit(lo1, hi1, sp1)
    if not (a and b) then return end
    local less = CS.Reduction(enemy.armor, L)
    Add(name, a, b, ps, function()
      T(name, C.accent)
      T(string.format("%d to %d every %.2f seconds.", lo1, hi1 + 0.5, sp1))
      if name == "Wand" then T("Armor does nothing against a wand.")
      else T(string.format("Against an ordinary level %d enemy (about %d armor) it's %.1f%% weaker: %.1f a second, before misses and critical hits.", enemy.L, enemy.armor, less * 100, b * (1 - less))) end
    end, 0.05)
  end
  Swing("Main hand", s0.lo, s0.hi, s0.speed, s1.lo, s1.hi, s1.speed)
  Swing("Off hand", s0.olo, s0.ohi, s0.speed2, s1.olo, s1.ohi, s1.speed2)
  Swing(CASTER[cl] and "Wand" or "Ranged", s0.rlo, s0.rhi, s0.rspeed, s1.rlo, s1.rhi, s1.rspeed)
  return out
end

local function Update(p, width)
  local s0, s1 = CS.State()
  local _, race = UnitRace("player")
  p.view.art:Set("Interface\\DRESSUPFRAME\\DressUpBackground-" .. (RACE[race or ""] or "Orc"), 0.75)
  p.view.after = function() for _, link in pairs(CS.plan) do p.view:TryOn(link) end end
  if CS.dress or p.view.key ~= "player" then
    CS.dress = nil
    p.view.key = nil
    p.view:Show1("player")
    if next(CS.plan) then
      C_Timer.After(0.2, p.view.after)
    end
  end
  for slot, b in pairs(p.slots) do
    local link = CS.plan[slot] or Worn(slot)
    local _, slotName = Info(slot)
    b.link = link
    local q
    if link then
      local id = tonumber(link:match("item:(%d+)"))
      b:Set(NS.ItemIcon(id) or NS.QUESTION_ICON)
      q = select(3, NS.GetItemInfo(link))
      b:Dim(false)
    else
      local ok, _, tex = pcall(GetInventorySlotInfo or error, slotName)
      b:Set(ok and tex or nil)
      b:Dim(true)
    end
    local picked = CS.slot == slot
    b.edge:SetColor(CS.plan[slot] and Lk.GOLD or picked and C.text or (q and Lk.QUALITY[q]) or C.border)
    b.edge:Thick((CS.plan[slot] or picked) and 2 or 1)
    b:Badge(not CS.plan[slot] and BestNow(slot) ~= nil and "up" or nil)
  end
  p.reset:SetShown(next(CS.plan) ~= nil)
  -- stats, in the space to the right
  local x = 10 + SZ + 6 + 236 + 6 + SZ + 12
  local w = width - x - 10
  p.name:ClearAllPoints()
  p.name:SetPoint("TOPLEFT", x + 6, -10)
  p.name:SetText(next(CS.plan) and "With what you're trying on" or (UnitName("player") .. ", level " .. s0.L))
  p.eText:ClearAllPoints()
  p.eText:SetPoint("TOPLEFT", 154, -10 - 306 - 56)
  p.eText:SetText("Enemies of level " .. CS.EnemyLevel())
  p.minus:ClearAllPoints(); p.minus:SetPoint("LEFT", p.eText, "RIGHT", 8, 0)
  p.plus:ClearAllPoints(); p.plus:SetPoint("LEFT", p.minus, "RIGHT", 3, 0)
  p.mine:ClearAllPoints(); p.mine:SetPoint("LEFT", p.plus, "RIGHT", 3, 0)
  p.mine:SetShown(CS.enemyLevel ~= nil)
  local list = CS.StatRows(s0, s1)
  local y = -28
  for k, d in ipairs(list) do
    local r = StatRow(p, k)
    r:ClearAllPoints()
    if d.h then
      y = y - 3
      r.name:SetText(d.h)
      r.name:SetTextColor(unpack(C.accent))
      r.value:SetText("")
      r.about = nil
    else
      r.name:SetText(d[1])
      r.name:SetTextColor(unpack(C.text))
      r.value:SetText(d[2])
      r.about = d[3]
    end
    r:SetPoint("TOPLEFT", x, y)
    r:SetWidth(w)
    r:Show()
    y = y - 15
  end
  for k = #list + 1, #p.stats do p.stats[k]:Hide() end
  return math.max(400, -y + 8)
end

---------------------------------------------------------------------------
-- The picker for a slot
---------------------------------------------------------------------------
local function MakePick(row)
  local p = CreateFrame("Frame", nil, row)
  p.bg = NS.Rounded(p, C.surface, "round.png", 10)
  p.icons = {}
  p.head = Lk.Text(p, "GameFontNormal", C.accent)
  p.head:SetPoint("TOPLEFT", 12, -10)
  p.hint = Lk.Text(p, "GameFontHighlightSmall", C.dim)
  p.hint:SetPoint("LEFT", p.head, "RIGHT", 10, 0)
  p.none = Lk.Text(p, "GameFontHighlightSmall", C.dim)
  p.none:SetPoint("TOPLEFT", 12, -34)
  return p
end
local function UpdatePick(p, width)
  local slot = CS.slot
  local label = Info(slot)
  local list = CS.Candidates(slot)
  p.head:SetText(label)
  p.hint:SetText("Hover: what it would change. Click: try it on. Gold edge: tried on; a bag: you have it.")
  local sz, gap = 38, 6
  local cols = math.floor((width - 24 + gap) / (sz + gap))
  for k, d in ipairs(list) do
    local b = p.icons[k]
    if not b then
      b = Lk.Icon(p, sz)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b:SetScript("OnClick", function(self, button)
        local id = tonumber(tostring(self.link):match("item:(%d+)"))
        if button == "RightButton" then GameTooltip:Hide(); if id then NS.Window.OpenItem(id) end return end
        if self.worn then CS.plan[CS.slot] = nil; CS.dress = true else CS.Try(CS.slot, self.link) end
        Redo()
      end)
      b.about = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        if self.worn then Lk.TipLine("You're wearing this.", C.dim) return end
        local ok, out, sp = pcall(CS.Change, self.link, CS.slot)
        if ok and type(out) == "table" then
          Lk.TipLine("Instead of what you wear:", C.accent)
          for _, l in ipairs(out) do Lk.TipLine(l[1], l[2] >= 0 and C.good or C.warn, false) end
          for n = 1, math.min(6, #List(sp)) do Lk.TipLine(string.format("%s: %s a cast", sp[n][1], Signed(sp[n][2])), sp[n][2] >= 0 and C.good or C.warn, false) end
        end
        if self.from then Lk.TipLine(self.from, C.dim) end
        Lk.TipLine("Click: try it on.  Right-click: where it comes from.", C.dim)
      end
      p.icons[k] = b
    end
    local id = tonumber(tostring(d.link):match("item:(%d+)"))
    b.link, b.worn = d.link, d.worn
    b.from = d.e and d.e.src and d.e.src.label or nil
    b:Set(id and NS.ItemIcon(id))
    local q = (d.e and d.e.quality) or select(3, NS.GetItemInfo(d.link))
    local on = CS.plan[slot] == d.link
    b.edge:SetColor(on and Lk.GOLD or (q and Lk.QUALITY[q]) or C.border)
    b.edge:Thick(on and 2 or 1)
    b:Badge(nil)
    b.mark:SetTexture(d.bag and I .. "INV_Misc_Bag_08" or nil)
    b.mark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.mark:SetShown(d.bag == true)
    b.num:SetText(d.worn and "on" or d.e and ("+" .. Short(d.e.gain)) or "")
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 12 + ((k - 1) % cols) * (sz + gap), -32 - math.floor((k - 1) / cols) * (sz + gap))
    b:Show()
  end
  for k = #list + 1, #p.icons do p.icons[k]:Hide() end
  p.none:SetShown(#list == 0)
  p.none:SetText("Nothing for this slot in your bags, and no upgrade known yet.")
  return 40 + math.max(1, math.ceil(#list / cols)) * (sz + gap)
end

---------------------------------------------------------------------------
-- The spells
---------------------------------------------------------------------------
-- One spell: every rank of it, and what would raise it
function CS.SpellPage(name)
  local s0, s1 = CS.State()
  local enemy = CS.Enemy(CS.EnemyLevel())
  local rows, ranks, best = {}, {}, nil
  for id, e in pairs(List(List(Src().spells)[Class() or ""])) do
    if NS.SpellName(id) == name and e[2] > 0 then ranks[#ranks + 1] = { id = id, e = e, known = Knows(id) } end
  end
  table.sort(ranks, function(a, b) return a.e[2] < b.e[2] end)
  for _, r in ipairs(ranks) do if r.known then best = r end end
  local tex = best and ((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(best.id)) or (GetSpellTexture and GetSpellTexture(best.id)))
  rows[1] = { h = "Every rank, for you now" .. (next(CS.plan) and ", with what you're trying on" or "") }
  for k, r in ipairs(ranks) do
    local x = CS.Cast(r.id, r.e, s1, enemy)
    if x.total > 0 and (r.known or r.e[2] <= s1.L + 12) then
      rows[#rows + 1] = { t = string.format("Rank %d  ·  level %d%s", k, r.e[2], r == best and "  ·  your best" or ""), spell = r.id, tex = tex, hot = r == best or nil, dim = not r.known or nil, still = true,
        d = string.format("%s %s a cast, %s a second%s%s", Short(x.total), x.kind, Short(x.per), x.mana and string.format(", %.2f for each mana (%d mana)", x.mana, x.cost) or "",
          x.coef and x.coef > 0 and string.format("\n%s of it is your %s", Short(x.bonus), x.kind == "damage" and "spell damage" or "healing") or "") }
    end
  end
  if best then
    local x = CS.Cast(best.id, best.e, s1, enemy)
    local what = {}
    local function Try(label, d)
      local y = CS.Cast(best.id, best.e, CS.With(s1, d), enemy)
      if y.total - x.total > 0.005 then what[#what + 1] = { label, y.total - x.total } end
    end
    Try("10 spell damage", { sp = 10 }); Try("10 healing", { heal = 10 }); Try("10 Intellect", { int = 10 }); Try("10 Strength", { str = 10 }); Try("10 Agility", { agi = 10 })
    Try("14 attack power", { ap = 14 }); Try("14 ranged attack power", { rap = 14 })
    Try("1% critical", { crit = Rating("crit") or 14 }); Try("1% spell critical", { scrit = Rating("scrit") or 14 }); Try("1% hit", { hit = Rating("hit") or 10 }); Try("1% spell hit", { shit = Rating("shit") or 10 })
    table.sort(what, function(a, b) return a[2] > b[2] end)
    if #what > 0 then
      rows[#rows + 1] = { h = "What would raise it" }
      local l = {}
      for _, w in ipairs(what) do l[#l + 1] = string.format("%s: |cff%s+%.2f|r a cast (%.1f%%)", w[1], HEX.good, w[2], w[2] / x.total * 100) end
      rows[#rows + 1] = { t = "From gear", d = table.concat(l, "\n"), tex = I .. "INV_Chest_Chain_05", still = true }
    end
    local tl = {}
    for _, n in ipairs(NS.TalentTree and NS.TalentTree.Nodes() or {}) do
      local hits
      for _, e in ipairs(n.spell and n.rank < n.max and List(List(Src().talents)[n.spell]) or {}) do
        for k = 1, 4 do if type(e[4]) == "table" and band(e[4][k] or 0, best.e[8][k] or 0) ~= 0 then hits = true end end
      end
      if hits then
        local ok, _, sp = pcall(CS.TalentChange, n.spell, n.rank + 1)
        for _, z in ipairs(ok and List(sp) or {}) do
          if z[1] == name and z[2] > 0.005 then tl[#tl + 1] = { n, z[2], z[3] } end
        end
      end
    end
    table.sort(tl, function(a, b) return a[2] > b[2] end)
    if #tl > 0 then
      rows[#rows + 1] = { h = "One more point in" }
      for k = 1, math.min(6, #tl) do
        rows[#rows + 1] = { t = string.format("%s  (%d of %d)", tl[k][1].name, tl[k][1].rank, tl[k][1].max), d = string.format("|cff%s+%.2f|r a cast (%.1f%%)", HEX.good, tl[k][2], tl[k][3]), tex = tl[k][1].icon, spell = tl[k][1].spell, still = true }
      end
    end
  end
  return { title = name, icon = tex, rows = rows, sub = string.format("Against an ordinary level %d enemy", enemy.L) }
end

local function MakeSpells(row)
  local p = CreateFrame("Frame", nil, row)
  p.rows = {}
  return p
end
local function SpellTip(r)
  local x, x0, k = r.x, r.x0, r.k
  local T = Lk.TipLine
  local s = r.s
  T(" ")
  T("For you now" .. (next(CS.plan) and ", with what you're trying on" or ""), C.accent)
  local sc = SCHOOL[x.school] or SCHOOL[1]
  if x.weapon then
    T(string.format("Your weapon's swing%s%s: %d to %d", x.wpct and string.format(" x %d%%", x.wpct) or "", (x.flat or 0) ~= 0 and string.format(" + %s", Short(x.flat)) or "", x.lo, x.hi + 0.5))
  elseif x.direct > 0 then
    T(string.format("The spell itself: %s%s", Short(x.base or 0), x.combo and " at five combo points" or ""))
  elseif x.heal > 0 then T(string.format("The spell itself: %s", Short(x.base or 0))) end
  if x.dotBase then T(string.format("%s over %g seconds: %s", x.hot > 0 and "Healing" or "Damage", x.dotSecs or 0, Short(x.dotBase))) end
  if x.coef and x.coef > 0 then
    local power = (x.kind == "damage") and (s.sp[sc[1]] or 0) or s.heal
    T(string.format("+ %s from your %d %s (%d%% of it)", Short(x.bonus), power, x.kind == "damage" and "spell damage" or "healing", x.coef * 100 + 0.5), C.good)
  end
  if math.abs(x.talHit - 1) > 0.001 and (x.direct > 0 or x.heal > 0) then T(string.format("Talents: x %.2f on the hit", x.talHit), C.good) end
  if math.abs(x.talDot - 1) > 0.001 and (x.dot > 0 or x.hot > 0) then T(string.format("Talents: x %.2f over time", x.talDot), C.good) end
  if x.direct > 0 then T(string.format("Lands for %d to %d; %.1f%% are critical for %d to %d", x.lo + 0.5, x.hi + 0.5, x.crit, x.lo * x.critBy + 0.5, x.hi * x.critBy + 0.5)) end
  if x.heal > 0 then T(string.format("Heals %d to %d; %.1f%% are critical", (x.healLo or 0) + 0.5, (x.healHi or 0) + 0.5, x.crit)) end
  if x.kind == "damage" then
    local en = CS.Enemy(CS.EnemyLevel())
    T(string.format("Level %d enemy: %.0f%% land%s", en.L, x.chance * 100, x.less > 0 and string.format(", its armor takes off %.0f%%", x.less * 100) or ""))
    T(string.format("On average %s a cast: %.0f%% of its %d health, about %d casts", Short(x.avg), x.share * 100, en.hp, math.ceil(1 / math.max(0.001, x.share))), C.accent)
  else
    T(string.format("On average %s a cast", Short(x.total)), C.accent)
  end
  T(string.format("%s a second of casting (%s)", Short(x.per), x.channel and string.format("channeled %.1f s", x.cast) or x.cast > 0 and string.format("%.1f s cast", x.cast) or "instant")
    .. (x.cd > 0 and string.format(", every %g s", x.cd) or ""))
  if x.mana then T(string.format("%s %s for each mana (%d mana)", string.format("%.2f", x.mana), x.kind, x.cost)) end
  if x.coef and x.coef > 0 then T(string.format("One more %s: +%.2f", x.kind == "damage" and "spell damage" or "healing", x.coef * (x.direct > 0 and x.talHit or x.heal > 0 and x.talHit or x.talDot)), C.good) end
  if x0 and x0 ~= x and math.abs(x0.total - x.total) >= 0.05 then T(string.format("Without what you're trying on: %s", Short(x0.total)), C.dim) end
  T("Click: every rank, and what would raise it.", C.dim)
  if not (x.direct > 0 or x.dot > 0 or x.heal > 0 or x.hot > 0 or x.absorb > 0) then T("The game's files don't give its damage directly: see its text above.", C.dim) end
end
local function UpdateSpells(p, width)
  local s0, s1 = CS.State()
  local enemy = CS.Enemy(CS.EnemyLevel())
  local list = {}
  for _, k in ipairs(CS.Known()) do
    local x = CS.Cast(k.id, k.e, s1, enemy)
    if x.total > 0 then list[#list + 1] = { k = k, x = x, x0 = s0 ~= s1 and CS.Cast(k.id, k.e, s0, enemy) or x } end
  end
  table.sort(list, function(a, b)
    if (a.x.kind == "damage") ~= (b.x.kind == "damage") then return a.x.kind == "damage" end
    return a.x.total > b.x.total
  end)
  local y, top = 0, 0
  for _, d in ipairs(list) do if d.x.kind == "damage" then top = math.max(top, d.x.total) end end
  for k, d in ipairs(list) do
    local r = p.rows[k]
    if not r then
      r = CreateFrame("Frame", nil, p)
      r:SetHeight(38)
      r.bg = NS.Rounded(r, C.surface, "round.png", 8)
      r.icon = Lk.Icon(r, 28)
      r.icon:SetPoint("LEFT", 7, 0)
      r.icon.about = function(self) SpellTip(self.row) end
      r.icon.row = r
      r.bar = r:CreateTexture(nil, "BORDER")
      r.bar:SetPoint("BOTTOMLEFT", 42, 4)
      r.bar:SetHeight(4)
      r.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
      r.name = Lk.Text(r, "GameFontHighlight", C.text)
      r.name:SetPoint("TOPLEFT", 42, -5)
      r.cols = {}
      for c = 1, 5 do r.cols[c] = Lk.Text(r, c == 1 and "GameFontHighlight" or "GameFontHighlightSmall", C.text, "RIGHT") end
      r:EnableMouse(true)
      r:SetScript("OnEnter", function(self)
        self.bg:SetColor(C.hover)
        NS.Window.ShowItemTip(self, nil, self.icon.spell)
        SpellTip(self)
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function(self) self.bg:SetColor(C.surface); GameTooltip:Hide() end)
      local function Open(self) local n = (self.row or self).k.n; GameTooltip:Hide(); NS.Window.OpenPage(function() return CS.SpellPage(n) end) end
      r:SetScript("OnMouseUp", Open)
      r.icon:SetScript("OnClick", Open)
      p.rows[k] = r
    end
    local x = d.x
    r.x, r.x0, r.k, r.s = x, d.x0, d.k, s1
    r.icon.spell = d.k.id
    r.icon:Set((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(d.k.id)) or (GetSpellTexture and GetSpellTexture(d.k.id)))
    r.name:SetText(d.k.n)
    local diff = x.total - d.x0.total
    local cells = {
      Short(x.total) .. (math.abs(diff) >= 0.05 and string.format(" |cff%s(%s)|r", diff > 0 and HEX.good or HEX.warn, Signed(diff)) or "") .. "\n|cff" .. HEX.dim .. x.kind .. "|r",
      Short(x.per) .. "\n|cff" .. HEX.dim .. "a second|r",
      x.mana and (string.format("%.2f", x.mana) .. "\n|cff" .. HEX.dim .. "each mana|r") or "",
      x.coef and x.coef > 0 and (string.format("%d%%", x.coef * 100 + 0.5) .. "\n|cff" .. HEX.dim .. "of power|r") or "",
      x.share and (string.format("%.0f%%", x.share * 100) .. "\n|cff" .. HEX.dim .. "of a level " .. enemy.L .. "|r") or "",
    }
    local cx = { width - 12, width - 92, width - 162, width - 236, width - 306 }
    local at = { 5, 4, 3, 2, 1 }
    for c = 1, 5 do
      local f = r.cols[at[c]]
      f:ClearAllPoints()
      f:SetPoint("RIGHT", r, "LEFT", cx[c], 0)
      f:SetText(cells[at[c]])
    end
    local sh = x.kind == "damage" and top > 0 and x.total / top or 0.5
    r.bar:SetWidth(math.max(4, sh * 180))
    local col = ({ [4] = { 0.80, 0.35, 0.12 }, [32] = { 0.50, 0.30, 0.66 }, [16] = { 0.30, 0.55, 0.80 }, [8] = { 0.35, 0.60, 0.25 }, [2] = { 0.80, 0.70, 0.35 }, [64] = { 0.65, 0.40, 0.75 } })[x.school] or { 0.55, 0.45, 0.35 }
    r.bar:SetVertexColor(col[1], col[2], col[3], 0.9)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetWidth(width)
    r:Show()
    y = y + 42
  end
  for k = #list + 1, #p.rows do p.rows[k]:Hide() end
  return math.max(1, y)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
function CS.Page()
  local rows = { { panel = { key = "charsheet", make = Make, update = Update } } }
  if CS.slot then rows[#rows + 1] = { panel = { key = "charpick", make = MakePick, update = UpdatePick } } end
  local s0, s1 = CS.State()
  if next(CS.plan) then
    local out, sp = CS.Compare(s0, s1)
    local a, b = {}, {}
    for _, l in ipairs(out) do a[#a + 1] = string.format("|cff%s%s|r", l[2] >= 0 and HEX.good or HEX.warn, l[1]) end
    for k = 1, math.min(12, #sp) do b[#b + 1] = string.format("%s |cff%s%s|r (%s%%)", sp[k][1], sp[k][2] >= 0 and HEX.good or HEX.warn, Signed(sp[k][2]), Signed(sp[k][3], "%.1f")) end
    rows[#rows + 1] = { h = "All together, it would change" }
    rows[#rows + 1] = { t = #out > 0 and "Your stats" or "Nothing that can be worked out", d = table.concat(a, "\n"), still = true }
    if #b > 0 then rows[#rows + 1] = { t = "Your spells and attacks, a cast on average", d = table.concat(b, "\n"), still = true } end
  end
  local known = CS.Known()
  if #known > 0 then
    rows[#rows + 1] = { h = string.format("What your spells and attacks do to an ordinary enemy of level %d", CS.EnemyLevel()) }
    rows[#rows + 1] = { panel = { key = "charspells", make = MakeSpells, update = UpdateSpells } }
  end
  rows[#rows + 1] = { t = "Where the numbers come from", still = true, dim = true,
    d = "Your stats, cast times and costs: the game, right now, with your talents and buffs. Spells, how much of your spell power each gets, and what talents do to them: the Forever client's own files. "
      .. "What an ordinary enemy of a level has, and how hit, armor, Intellect and Spirit work: Classic's rules, fitted to what the game says about you where it says something. "
      .. "Set bonuses, enchants on new gear and effects that only go off now and then aren't counted." }
  return { title = "Your character", icon = I .. "INV_Chest_Chain_05", rows = rows, sub = "Hover anything for its real numbers. Click a slot to try other gear." }
end
function CS.Row()
  return { t = "Your character", d = "Your stats and spells in real numbers; try gear on", tex = I .. "Spell_Nature_WispSplode", key = "charsheet", page = CS.Page }
end
function CS.Open()
  local W = NS.Window
  if not W then return end
  NS.cdb.gearMode = "slots"
  W.Open("upgrades")
  for _, r in ipairs(W.current or {}) do if r.key == "charsheet" then W.Select(r) end end
end
function CS.Rows()
  local rows = { CS.Row() }
  for _, r in ipairs(NS.Gear.SlotRows()) do rows[#rows + 1] = r end
  return rows
end

---------------------------------------------------------------------------
-- Watching how fast your health really comes back (out of combat, not eating, not full)
---------------------------------------------------------------------------
local lastHp, lastT, sum, span
local function Eating()
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for k = 1, 40 do
    local ok, a = pcall(get or error, "player", k, "HELPFUL")
    if not (ok and type(a) == "table") then return false end
    local n = a.name
    if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return true end
    if n == "Food" or n == "Drink" or n == "Food & Drink" or n == "First Aid" or n == "Refreshment" or n == "Renew" or n == "Rejuvenation" or n == "Regrowth" or n == "Cozy Fire" then return true end
  end
  return false
end
function CS.Watch()
  local hp, max = N(Call(UnitHealth, "player")), N(Call(UnitHealthMax, "player"))
  local now = GetTime()
  if not (hp and max) or InCombatLockdown() then lastHp, sum, span = nil, 0, 0 return end
  if lastHp and hp > lastHp and now - lastT < 6 and (hp - lastHp) < max * 0.12 and hp < max then
    if (span or 0) == 0 and Eating() then lastHp = nil return end
    sum, span = (sum or 0) + (hp - lastHp), (span or 0) + (now - lastT)
    if span >= 8 then
      if not Eating() then
        local r = NS.cdb.regen
        local v = sum / span
        NS.cdb.regen = { hp = type(r) == "table" and r.L == Level() and N(r.hp) and (r.hp * 2 + v) / 3 or v, L = Level() }
      end
      sum, span = 0, 0
    end
  elseif not lastHp or hp < lastHp or now - lastT >= 6 then
    sum, span = 0, 0
  end
  lastHp, lastT = hp, now
end

function CS:Init()
  NS.On("UNIT_HEALTH", function(unit) if unit == "player" then NS.Safe("regeneration", CS.Watch) end end)
  local function Fresh()
    live = nil
    NS.Debounce("charsheet", 0.5, function()
      local W = NS.Window
      if W and W.page and W.page.title == "Your character" and not InCombatLockdown() then CS.dress = true; W.Redo() end
    end)
  end
  NS.On("PLAYER_EQUIPMENT_CHANGED", Fresh)
  for _, ev in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED" }) do NS.On(ev, CS.Forget) end
  NS.Command("stats", "- your character in numbers: stats, regeneration, what your spells do, trying gear on", function() CS.Open() end)
end
