-- Sunstone: pets on the Class tab. Hunters: suggestions first (what to tame now, which skills to teach next, rare beasts
-- worth collecting), then every family, every skill and who teaches it. Warlocks: each demon, what its spells are for, the
-- level each rank comes at and which grimoires to buy. Data: PetData.lua (OneForAll's, with permission; Questie).
-- Skill texts are the data's; what they're good for is said in our own words.

local _, NS = ...
local Pt = NS.Module("Pets")
NS.Pets = Pt
local E = NS.Engine
local I = "Interface\\Icons\\"

local function Src() return type(_G.SunstonePets) == "table" and _G.SunstonePets or {} end
local function List(t) return type(t) == "table" and t or {} end
local function Level() return UnitLevel("player") or 1 end
local function IsClass(token) return select(2, UnitClass("player")) == token end

---------------------------------------------------------------------------
-- Hunter: what things are for
---------------------------------------------------------------------------
local USE = { -- skill -> what it's good for
  Growl = "Holds the enemy's attention so it hits the pet, not you. Keep it on when alone; turn it off in dungeons with a tank.",
  Bite = "Its big hit. Good for any pet that has it.",
  Claw = "A cheap hit it can use often: steady damage.",
  Cower = "Makes enemies care less about the pet. For dungeons, so the tank keeps them; leave it off when alone.",
  Dash = "A burst of speed to reach the target sooner.",
  Dive = "A burst of speed to reach the target sooner (flyers).",
  Charge = "Rushes in and roots the target for a moment: a good opener, and it keeps runners from getting away.",
  Swipe = "Hits several enemies at once: good when you pull more than one.",
  Thunderstomp = "Hits everything around it: good when you pull several.",
  Prowl = "Sneaks, and its first hit out of stealth is stronger.",
  ["Furious Howl"] = "Boosts the damage of those near it: the one for groups and dungeons.",
  ["Demoralizing Screech"] = "Enemies near it hit weaker: helps whoever is being hit.",
  ["Scorpid Poison"] = "A poison that builds up: good on long fights.",
  ["Lightning Breath"] = "Damage from range that armor doesn't reduce: good against plate and mail wearers.",
  ["Lava Breath"] = "Fire breath, and it slows how fast the target attacks and casts. No core hound has been found that can be tamed on Forever so far.",
  ["Shell Shield"] = "Takes less damage for a while: the safest pet for hard fights.",
  Web = "Roots the target so it can't move: good for runners and for getting away.",
  ["Tendon Rip"] = "Slows or cripples the target: it can't get away.",
  ["Savage Rend"] = "A bleed that keeps hurting.",
  Dismember = "A hard, crippling bite.",
  Pinch = "Pins the target's attention or movement: see its text below.",
  ["Dust Cloud"] = "Kicks up dust so enemies near it miss more.",
  ["Trickster's Dance"] = "Dodges half the blows and attacks faster for a while: good when it's in trouble.",
  ["Sonic Blast"] = "Damage from a little way off, and the target casts slower: good against casters.",
  ["Mine!"] = "The birds of prey's own skill: see its text below.",
  ["Great Stamina"] = "More health. Cheap and always useful: buy it as soon as you can.",
  ["Natural Armor"] = "Takes less physical damage. Always useful for a pet that holds enemies for you.",
}
Pt.USE = USE
local PICKS = { -- what you want, why, how to choose the families
  { "Leveling alone, quick kills", "They deal the most damage.", function(f) return f.role == "Offense" and (f.dmg or 1) >= 1.05 end, "dmg" },
  { "A pet that takes the hits", "The toughest: you can shoot in peace.", function(f) return f.role == "Defense" and (f.hp or 1) * (f.ar or 1) >= 1.04 end, "tough" },
  { "Several enemies at once", "Hits more than one at a time.", function(f) return f.only == "Swipe" or f.only == "Thunderstomp" end, "tough" },
  { "Dungeons and groups", "Helps the whole group.", function(f) return f.only == "Furious Howl" or f.only == "Demoralizing Screech" end, "dmg" },
  { "Catching runners, fighting players", "Roots, slows or sneaks.", function(f) return f.only == "Charge" or f.only == "Web" or f.only == "Tendon Rip" or f.only == "Prowl" end, "dmg" },
  { "Easy to feed", "Eats nearly anything you find.", function(f) return #List(f.diet) >= 5 end, "diet" },
}
local SORT = { dmg = function(f) return f.dmg or 1 end, tough = function(f) return (f.hp or 1) * (f.ar or 1) end, diet = function(f) return #List(f.diet) end }

local function Nums(text) -- "16-17" -> 16, 17
  local a, b = tostring(text or ""):match("(%d+)%s*%-?%s*(%d*)")
  a = tonumber(a)
  return a, tonumber(b) or a
end
local function Place(b)
  if b[5] and b[6] then return { m = b[5], x = b[6] / 100, y = b[7] / 100 } end
end
local function Far(b)
  local p = Place(b)
  return p and E.Minutes(E.Point(p.m, p.x, p.y)) or nil
end
local function Icon(name) return name and (I .. name) or nil end
local function BeastRow(b, extra)
  local bits = { "Level " .. (b[3] ~= "" and b[3] or "?") .. (b.elite and ", elite" or "") .. (b.rare and ", rare" or "") }
  bits[#bits + 1] = b[4]
  local p = Place(b)
  if extra then bits[#bits + 1] = extra end
  local e = NS.PetPlan and NS.PetPlan.Beast(b[1])
  local f = e and e.f
  return { t = b[2], d = table.concat(bits, "  ·  "), m = p and p.m, x = p and p.x, y = p and p.y, face = b[1], tex = f and (I .. f.icon) or nil,
           actLabel = "Show", act = f and function() NS.PetPlan.Open(b[1]) end or nil }
end

-- Beasts of a family you could tame at your level, the best ones (closest to your level) first
local function Tameable(f, L, span)
  local out = {}
  for _, b in ipairs(List(f.tames)) do
    local lo, hi = Nums(b[3])
    if lo and lo <= L and hi >= L - (span or 6) and not b.rare then
      local far = Far(b)
      out[#out + 1] = { b = b, far = far or 500, gap = L - math.min(hi, L) }
    end
  end
  table.sort(out, function(x, y) return x.far + x.gap * 4 < y.far + y.gap * 4 end)
  return out
end

-- the highest rank of a skill your pet could have, and the next one
local function Rank(a, L)
  local now, nxt
  for i, r in ipairs(List(a.ranks)) do
    if r[1] <= L then now = i elseif not nxt then nxt = i end
  end
  return now, nxt
end
local function Teachers(r, L)
  local out = {}
  for _, b in ipairs(List(r[4])) do
    local lo = Nums(b[3])
    out[#out + 1] = { b = b, far = (Far(b) or 500) + ((lo or 1) > L and 1000 or 0) }
  end
  table.sort(out, function(x, y) return x.far < y.far end)
  return out
end

local SkillPage, FamilyPage

function Pt.Trainers(rows, n)
  local me = (UnitFactionGroup and UnitFactionGroup("player") or "Horde"):sub(1, 1)
  local list = {}
  for _, t in ipairs(List(Src().trainers)) do
    if t[3]:find(me, 1, true) then
      local p = { m = t[4], x = t[5] / 100, y = t[6] / 100 }
      p = E.Point(p.m, p.x, p.y)
      list[#list + 1] = { t = t, p = p, far = E.Minutes(p) or 500 }
    end
  end
  table.sort(list, function(a, b) return a.far < b.far end)
  for k = 1, math.min(n or 3, #list) do
    local e = list[k]
    rows[#rows + 1] = { t = e.t[2], d = "Pet trainer  ·  " .. E.PlaceText(e.p), m = e.p.m, x = e.p.x, y = e.p.y }
  end
end

function SkillPage(a)
  local L, rows = Level(), {}
  rows[1] = { t = USE[a.n] or a.eff, d = a.eff ~= "" and a.eff or nil, tex = Icon(a.icon), still = true }
  rows[#rows + 1] = { t = "Who can have it", d = table.concat(List(a.fam), ", "), still = true }
  if a.src == "trainer" then
    rows[#rows + 1] = { h = "Bought from a pet trainer" }
    Pt.Trainers(rows, 2)
  end
  rows[#rows + 1] = { h = "Ranks" }
  local now = Rank(a, L)
  for i, r in ipairs(List(a.ranks)) do
    local ps = NS.PetPlan and select(2, NS.PetPlan.Skill(a.n))
    local pr = ps and ps.r and ps.r[i]
    rows[#rows + 1] = { t = string.format("Rank %d  ·  pet level %d  ·  %s", i, r[1], r[2] > 0 and (r[2] .. " training points") or a.n == "Growl" and "free" or "training points not known yet"),
                        d = r[3] .. (pr and pr[3] > 0 and string.format("\n%d focus%s", pr[3], pr[4] > 0 and string.format(", every %g seconds", pr[4]) or ", no cooldown") or ""),
                        tex = Icon(a.icon), spell = pr and pr[1], hot = i == now or nil, dim = r[1] > L or nil, still = true }
    if a.src ~= "trainer" then
      local list = Teachers(r, L)
      for k = 1, math.min(i == now and 4 or 2, #list) do
        local row = BeastRow(list[k].b, list[k].b.fam)
        row.t = "Learn it from " .. row.t
        row.dim = r[1] > L or nil
        rows[#rows + 1] = row
      end
    end
  end
  if a.src ~= "trainer" then
    rows[#rows + 1] = { t = "How learning works", still = true,
                        d = "Tame a beast that has the skill and fight alongside it until the game says you learned it. Then you can teach that rank to any pet whose family "
                          .. "can have it (Beast Training), for training points." }
  end
  return { title = a.n, icon = Icon(a.icon), rows = rows, sub = a.src == "trainer" and "From a pet trainer" or "Learned from wild beasts" }
end

Pt.SkillPage = SkillPage
local function Ability(name) for _, a in ipairs(List(Src().abilities)) do if a.n == name then return a end end end

function FamilyPage(f)
  local L, rows = Level(), {}
  local pct = function(v) return string.format("%+d%%", ((v or 1) - 1) * 100 + ((v or 1) >= 1 and 0.5 or -0.5)) end
  rows[1] = { t = f.role .. (f.only and (", the only family with " .. f.only) or ""), tex = Icon(f.icon), still = true,
              actLabel = "Plan one", act = NS.PetPlan and function() NS.PetPlan.PickFamily(f.n); NS.PetPlan.Open() end or nil,
              d = (f.dmg and string.format("Damage %s, health %s, armor %s against an average pet.\n", pct(f.dmg), pct(f.hp), pct(f.ar)) or "")
                .. "Eats: " .. table.concat(List(f.diet), ", ") .. "." }
  if f.only and USE[f.only] then rows[#rows + 1] = { t = f.only, d = USE[f.only], page = Ability(f.only) and function() return SkillPage(Ability(f.only)) end or nil } end
  rows[#rows + 1] = { h = "Skills it can learn" }
  for _, n in ipairs(List(f.ab)) do
    local a = Ability(n)
    local now, nxt = a and Rank(a, L)
    rows[#rows + 1] = { t = n, tex = a and Icon(a.icon), d = a and ((now and ("Rank " .. now .. " at your level") or "Not at your level yet")
                          .. (nxt and string.format(", rank %d at %d", nxt, a.ranks[nxt][1]) or "")) or nil, page = a and function() return SkillPage(a) end or nil }
  end
  rows[#rows + 1] = { t = "Plus Growl, Great Stamina, Natural Armor and the resistances", d = "From a pet trainer, for any pet.", still = true }
  rows[#rows + 1] = { h = "Where to tame one" }
  local near, shown = Tameable(f, L, 6), {}
  for k = 1, math.min(4, #near) do
    local row = BeastRow(near[k].b)
    row.hot = k == 1 or nil
    shown[near[k].b] = true
    rows[#rows + 1] = row
  end
  if #near == 0 then rows[#rows + 1] = { t = "None near your level", d = "The whole list, by level:", still = true } end
  local all = {}
  for _, b in ipairs(List(f.tames)) do if not shown[b] then all[#all + 1] = b end end
  table.sort(all, function(x, y) return (Nums(x[3]) or 99) < (Nums(y[3]) or 99) end)
  if #all > 0 then rows[#rows + 1] = { h = "All of them, by level" } end
  for _, b in ipairs(all) do
    local row = BeastRow(b)
    row.dim = (Nums(b[3]) or 0) > L or nil
    rows[#rows + 1] = row
  end
  return { title = f.n, icon = Icon(f.icon), rows = rows, sub = "Hunter pet family" }
end

local function Rares()
  local out, seen = {}, {}
  for _, r in ipairs(List(Src().rares)) do out[#out + 1] = r; seen[r[1]] = true end
  for _, f in ipairs(List(Src().families)) do
    for _, b in ipairs(List(f.tames)) do
      if b.rare and not seen[b[1]] then
        seen[b[1]] = true
        out[#out + 1] = { b[1], b[2], b[3], b[4], b[5], b[6], b[7], rare = 1, elite = b.elite, fam = f.n }
      end
    end
  end
  table.sort(out, function(x, y) return (Nums(x[3]) or 99) < (Nums(y[3]) or 99) end)
  return out
end
Pt.Rares = Rares

local function RarePage()
  local L, rows = Level(), {}
  rows[1] = { t = "Rare beasts", d = "Ones people tame for their looks, their speed or the bragging. A rare one isn't always there: it can take a while to come back, and others hunt it too.", still = true }
  local now, later = {}, {}
  for _, b in ipairs(Rares()) do
    local lo = Nums(b[3]) or 99
    table.insert(lo <= L and now or later, b)
  end
  local function Add(title, list, dim)
    if #list == 0 then return end
    rows[#rows + 1] = { h = string.format("%s (%d)", title, #list) }
    for _, b in ipairs(list) do
      local row = BeastRow(b, b.fam)
      row.d = row.d .. (b.why and ("\n" .. b.why) or "") .. (b.speed and string.format(" Attacks every %.1f s.", b.speed) or "")
      row.dim = dim
      rows[#rows + 1] = row
    end
  end
  Add("You could tame these now", now)
  Add("For later", later, true)
  return { title = "Rare beasts", icon = I .. "Ability_Hunter_BeastTaming", rows = rows, sub = "Hunter pets worth collecting" }
end

local function PickPage(p)
  local L, rows, list = Level(), {}, {}
  for _, f in ipairs(List(Src().families)) do if p[3](f) then list[#list + 1] = f end end
  table.sort(list, function(a, b) return SORT[p[4]](a) > SORT[p[4]](b) end)
  rows[1] = { t = p[2], still = true }
  for _, f in ipairs(list) do
    local near = Tameable(f, math.max(L, 10), 6)
    rows[#rows + 1] = { t = f.n .. (f.only and ("  (" .. f.only .. ")") or ""), tex = Icon(f.icon), page = function() return FamilyPage(f) end,
                        d = (near[1] and ("Near your level: " .. near[1].b[2] .. ", " .. near[1].b[4]) or "None near your level right now")
                          .. (f.only and USE[f.only] and ("\n" .. USE[f.only]) or "") }
  end
  return { title = p[1], rows = rows, sub = "Hunter pets: suggestions" }
end

local function SkillsPage()
  local rows, L = {}, Level()
  rows[1] = { t = "Skills come two ways", d = "Some are bought from a pet trainer. The rest you learn by taming a beast that has them, then teach to your own pet for training points "
    .. "(a pet earns points as it levels and gets loyal).", still = true }
  for _, kind in ipairs({ "wild", "trainer" }) do
    rows[#rows + 1] = { h = kind == "wild" and "Learned from wild beasts" or "Bought from a pet trainer" }
    for _, a in ipairs(List(Src().abilities)) do
      if a.src == kind then
        local now, nxt = Rank(a, L)
        rows[#rows + 1] = { t = a.n, tex = Icon(a.icon), page = function() return SkillPage(a) end,
                            d = (USE[a.n] or a.eff) .. "\n" .. (now and ("Rank " .. now .. " at your level") or ("From level " .. (a.ranks[1] and a.ranks[1][1] or "?")))
                              .. (now and nxt and string.format(", rank %d at %d", nxt, a.ranks[nxt][1]) or "") }
      end
    end
  end
  return { title = "Pet skills", icon = I .. "Ability_Hunter_BeastCall", rows = rows, sub = "Hunter pets" }
end

local function FamiliesPage()
  local rows = {}
  for _, role in ipairs({ "Offense", "Defense", "General" }) do
    rows[#rows + 1] = { h = role == "Offense" and "Offense: they deal the most" or role == "Defense" and "Defense: they take the most" or "General: in between" }
    for _, f in ipairs(List(Src().families)) do
      if f.role == role then
        rows[#rows + 1] = { t = f.n, tex = Icon(f.icon), d = (f.only and ("Only family with " .. f.only .. ". ") or "") .. "Eats " .. table.concat(List(f.diet), ", "):lower() .. ".",
                            page = function() return FamilyPage(f) end }
      end
    end
  end
  return { title = "Pet families", icon = I .. "Ability_Hunter_Pet_Cat", rows = rows, sub = "Hunter pets" }
end

function Pt.Hunter(rows)
  local L, mine = Level(), IsClass("HUNTER")
  local panel = NS.PetPlan and NS.PetPlan.Row()
  if panel then
    rows[#rows + 1] = panel
    NS.PetPlan.Rows(rows)
  end
  rows[#rows + 1] = { t = L < 10 and mine and "Pets come at level 10" or "Where to start", still = true,
                      d = "A hunter's taming quests start at level 10. Tame something close to your own level, keep it fed (a happy pet hits harder), and give it Growl, Great Stamina "
                        .. "and Natural Armor from a pet trainer first: those suit every pet." }
  rows[#rows + 1] = { h = "Suggestions: what do you want it for?" }
  for _, p in ipairs(PICKS) do
    local list = {}
    for _, f in ipairs(List(Src().families)) do if p[3](f) then list[#list + 1] = f end end
    table.sort(list, function(a, b) return SORT[p[4]](a) > SORT[p[4]](b) end)
    local names = {}
    for k = 1, math.min(5, #list) do names[k] = list[k].n end
    rows[#rows + 1] = { t = p[1], tex = list[1] and Icon(list[1].icon), d = table.concat(names, ", "), page = function() return PickPage(p) end }
  end
  if mine then
    rows[#rows + 1] = { h = "Worth taming near you now (level " .. math.max(10, L) .. ")" }
    local best = {}
    for _, f in ipairs(List(Src().families)) do
      local near = Tameable(f, math.max(10, L), 5)
      if near[1] then best[#best + 1] = { f = f, n = near[1], s = near[1].far - (f.role == "Offense" and 6 or 0) - ((f.dmg or 1) - 1) * 60 } end
    end
    table.sort(best, function(a, b) return a.s < b.s end)
    for k = 1, math.min(5, #best) do
      local row = BeastRow(best[k].n.b, best[k].f.n)
      row.tex = Icon(best[k].f.icon)
      rows[#rows + 1] = row
    end
    if #best == 0 then rows[#rows + 1] = { t = "Nothing recorded near your level", still = true } end
    rows[#rows + 1] = { h = "Skills to look for next" }
    local n = 0
    for _, name in ipairs({ "Growl", "Great Stamina", "Natural Armor", "Bite", "Claw", "Dash", "Dive" }) do
      local a = Ability(name)
      local now = a and Rank(a, L)
      if now and n < 6 then
        n = n + 1
        local from = a.src == "trainer" and "pet trainer" or nil
        if not from then local t = Teachers(a.ranks[now], L)[1]; from = t and (t.b[2] .. ", " .. t.b[4]) or "a wild beast" end
        rows[#rows + 1] = { t = string.format("%s, rank %d", name, now), tex = Icon(a.icon), d = "From " .. from, page = function() return SkillPage(a) end }
      end
    end
  end
  rows[#rows + 1] = { h = "Look it up" }
  local nr = #Rares()
  rows[#rows + 1] = { t = string.format("Rare beasts (%d)", nr), tex = I .. "Ability_Hunter_BeastTaming", d = "For collectors: where each one is and why people want it", page = RarePage }
  rows[#rows + 1] = { t = string.format("Every family (%d)", #List(Src().families)), tex = I .. "Ability_Hunter_Pet_Cat", d = "What each is good at, eats and can learn, and where to tame one", page = FamiliesPage }
  rows[#rows + 1] = { t = string.format("Every skill (%d)", #List(Src().abilities)), tex = I .. "Ability_Hunter_BeastCall", d = "What it's for, its ranks by level, and who teaches it", page = SkillsPage }
  rows[#rows + 1] = { h = "Pet trainers" }
  Pt.Trainers(rows, 3)
end

---------------------------------------------------------------------------
-- Warlock demons
---------------------------------------------------------------------------
local DEMONS = {
  { "Imp", I .. "Spell_Shadow_SummonImp", 1, "From your first class quest, at level 1.",
    "Stays at range and throws firebolts. The most damage while you level early, and its Blood Pact gives your group health. Fragile: don't let it hold enemies.", 416 },
  { "Voidwalker", I .. "Spell_Shadow_SummonVoidWalker", 10, "From a class quest at level 10.",
    "Holds enemies so they hit it, not you. The safe choice for soloing: let it get a hit or two in before you cast.", 1860 },
  { "Succubus", I .. "Spell_Shadow_SummonSuccubus", 20, "From a class quest at level 20.",
    "Deals the most in melee range and can Seduce a humanoid out of the fight. Good for dungeons with humanoids and for players.", 1863 },
  { "Felhunter", I .. "Spell_Shadow_SummonFelHunter", 30, "From a class quest at level 30.",
    "The answer to casters: eats magic effects, locks spells, hard to kill with magic. For caster enemies and players.", 417 },
}
local DEMON_USE = {
  Firebolt = { "Its attack. Keep it on.", 1 }, ["Blood Pact"] = { "More health for your whole group: always worth it.", 4 },
  ["Fire Shield"] = { "Burns whatever hits the one wearing it: for the tank. Costs the imp mana, so many leave it off alone.", 14 },
  ["Phase Shift"] = { "Can't be hit while it isn't attacking: keeps it alive when you only want Blood Pact.", 12 },
  Torment = { "Holds one enemy's attention. Keep it on when alone; off in dungeons with a tank.", 10 },
  Sacrifice = { "Gives up the voidwalker for a shield on you: your emergency button.", 16 },
  ["Consume Shadows"] = { "Heals itself out of a fight: use it between pulls instead of waiting.", 18 },
  Suffering = { "Holds everything near it: for when several enemies come at you.", 24 },
  ["Lash of Pain"] = { "Its attack. Keep it on.", 20 }, ["Soothing Kiss"] = { "Enemies care less about it: use it when it pulls too much attention.", 22 },
  Seduction = { "Charms a humanoid until it's hurt: takes one enemy out of the fight.", 26 },
  ["Lesser Invisibility"] = { "Hides it while it isn't fighting.", 32 },
  ["Devour Magic"] = { "Eats a magic effect: off a friend it's bad ones, off an enemy it's good ones. It heals when it does.", 30 },
  ["Tainted Blood"] = { "Whatever hits it in melee hits weaker.", 32 }, ["Spell Lock"] = { "Stops a spell being cast and blocks that school for a moment.", 36 },
  Paranoia = { "Helps your group notice stealthed enemies.", 42 },
}
local FIRST = { Firebolt = 1, Torment = 10, ["Lash of Pain"] = 20, ["Devour Magic"] = 30 } -- rank 1 comes with the demon

local function Grimoires(demon)
  local out = {}
  for _, g in ipairs(List(Src().grimoires)) do if g[1] == demon then out[#out + 1] = g end end
  table.sort(out, function(a, b) return (DEMON_USE[a[2]] and DEMON_USE[a[2]][2] or 99) < (DEMON_USE[b[2]] and DEMON_USE[b[2]][2] or 99) end)
  return out
end
Pt.Grimoires = Grimoires

local function DemonTrainers(rows, n)
  local list = {}
  for _, id in ipairs(List(Src().demonTrainers)) do
    local L = NS.Quests()
    local ok, side = false, nil
    if L and L.Npc then ok, side = pcall(L.Npc.Get, id, "friendlyToFaction") end
    local me = (UnitFactionGroup and UnitFactionGroup("player") or "Horde"):sub(1, 1)
    if not (ok and type(side) == "string" and not side:find(me, 1, true)) then
      local p, m = E.Nearest(E.Points("Npc", id))
      if p then list[#list + 1] = { id = id, p = p, m = m } end
    end
  end
  table.sort(list, function(a, b) return a.m < b.m end)
  for k = 1, math.min(n, #list) do
    rows[#rows + 1] = E.At({ t = E.NpcName(list[k].id), d = "Demon trainer (sells grimoires)  ·  " .. E.PlaceText(list[k].p) }, list[k].p)
  end
end

local function DemonPage(d)
  local L, rows = Level(), {}
  if NS.Look then
    rows[1] = NS.Look.PicturePanel("demon", { npc = d[6], icon = d[2], title = d[1], sub = d[4], lines = { d[5] }, art = "Interface\\TalentFrame\\WarlockSummoning-" })
  else rows[1] = { t = d[5], d = d[4], tex = d[2], still = true } end
  rows[#rows + 1] = { h = "Its spells" }
  for _, g in ipairs(Grimoires(d[1])) do
    local use = DEMON_USE[g[2]]
    rows[#rows + 1] = { t = g[2], d = (use and use[1] or "") .. (FIRST[g[2]] and "\nRank 1 comes with the demon; later ranks are grimoires." or ""), still = true }
    for _, r in ipairs(g[3]) do
      rows[#rows + 1] = { t = string.format("Rank %d  ·  level %d%s", r[1], r[2], r[4] > 0 and ("  ·  " .. NS.Money(r[4])) or ""), i = r[3],
                          d = r[2] <= L and "You can buy this one now" or nil, dim = r[2] > L or nil }
    end
  end
  rows[#rows + 1] = { t = "How grimoires work", d = "Buy them from a demon trainer (they stand by the warlock trainers), then use the book with that demon summoned. Prices are Classic's; a good "
    .. "reputation lowers them.", still = true }
  return { title = d[1], icon = d[2], rows = rows, sub = "Warlock demon" }
end

function Pt.Warlock(rows)
  local L, mine = Level(), IsClass("WARLOCK")
  rows[#rows + 1] = { t = "Which demon when", still = true, d = "Imp for damage early and for group health, Voidwalker to solo safely, Succubus for damage and humanoids, Felhunter against casters. "
    .. "Their spells level with grimoires you buy: without them a demon falls behind." }
  for _, d in ipairs(DEMONS) do
    local names = {}
    for _, g in ipairs(Grimoires(d[1])) do names[#names + 1] = g[2] end
    rows[#rows + 1] = { t = d[1] .. "  (level " .. d[3] .. ")", tex = d[2], d = table.concat(names, ", "), dim = mine and L < d[3] or nil, page = function() return DemonPage(d) end }
  end
  if mine then
    local now, soon = {}, {}
    for _, d in ipairs(DEMONS) do
      for _, g in ipairs(Grimoires(d[1])) do
        local best, nx
        for _, r in ipairs(g[3]) do if r[2] <= L then best = r elseif not nx then nx = r end end
        if best and L >= d[3] then now[#now + 1] = { d[1], g[2], best } end
        if nx and nx[2] <= L + 4 and nx[2] >= d[3] then soon[#soon + 1] = { d[1], g[2], nx } end
      end
    end
    rows[#rows + 1] = { h = "The newest rank of each at your level" }
    for _, e in ipairs(now) do
      rows[#rows + 1] = { t = string.format("%s, rank %d", e[2], e[3][1]), i = e[3][3], d = string.format("%s  ·  level %d%s", e[1], e[3][2], e[3][4] > 0 and ("  ·  " .. NS.Money(e[3][4])) or "") }
    end
    if #soon > 0 then
      rows[#rows + 1] = { h = "Coming up" }
      table.sort(soon, function(a, b) return a[3][2] < b[3][2] end)
      for _, e in ipairs(soon) do
        rows[#rows + 1] = { t = string.format("Level %d: %s, rank %d", e[3][2], e[2], e[3][1]), i = e[3][3], d = e[1] .. (e[3][4] > 0 and ("  ·  " .. NS.Money(e[3][4])) or "") }
      end
    end
  end
  rows[#rows + 1] = { h = "Later on" }
  rows[#rows + 1] = { t = "Infernal (50) and Doomguard (60)", d = "Big temporary demons from class quests: they fight you when their time is up, so plan for it.", still = true }
  rows[#rows + 1] = { h = "Demon trainers" }
  DemonTrainers(rows, 3)
end

function Pt.Page(token, rows)
  if token == "HUNTER" then Pt.Hunter(rows)
  elseif token == "WARLOCK" then Pt.Warlock(rows)
  else
    rows[#rows + 1] = { t = "This class has no pet of its own", d = "Hunters tame beasts and warlocks summon demons: pick one of them on the left. (Pets that only follow you around are on Pets & Mounts.)", still = true }
  end
end
