-- Sunstone: the Professions tab. Every profession: your skill, what to make next to raise it, where the trainers are,
-- each recipe (materials, where to learn it, what it costs) and what your other characters can already make.
-- Recipes, trainers and ranks: Data.lua. Where materials come from: Engine.lua.

local _, NS = ...
local P = NS.Module("Professions")
NS.Professions = P
local E = NS.Engine

local I = "Interface\\Icons\\"
P.LIST = { -- name, icon, what kind, a line about it
  { "Alchemy", I .. "Trade_Alchemy", "craft", "Potions and elixirs. Herbalism gathers its herbs." },
  { "Blacksmithing", I .. "Trade_BlackSmithing", "craft", "Mail and plate armor, weapons. Mining gathers its ore." },
  { "Enchanting", I .. "Trade_Engraving", "craft", "Permanent bonuses on gear. Its materials come from disenchanting green and better items." },
  { "Engineering", I .. "Trade_Engineering", "craft", "Gadgets, explosives, guns and scopes. Mining gathers its ore." },
  { "Leatherworking", I .. "INV_Misc_ArmorKit_17", "craft", "Leather and mail armor. Skinning gathers its leather." },
  { "Tailoring", I .. "Trade_Tailoring", "craft", "Cloth armor and bags. Its cloth drops from humanoids, so it needs no gathering skill." },
  { "Herbalism", I .. "Spell_Nature_NatureTouchGrow", "gather", "Herbs for Alchemy, or to sell." },
  { "Mining", I .. "Trade_Mining", "gather", "Ore and stone for Blacksmithing and Engineering, or to sell." },
  { "Skinning", I .. "INV_Misc_Pelt_Wolf_01", "gather", "Leather from beasts, for Leatherworking or to sell." },
  { "Cooking", I .. "INV_Misc_Food_15", "second", "Food that heals and gives bonuses. Anyone can learn it besides two main professions." },
  { "First Aid", I .. "Spell_Holy_SealOfSacrifice", "second", "Bandages from cloth. Anyone can learn it besides two main professions." },
  { "Fishing", I .. "Trade_Fishing", "second", "Fish for Cooking, or to sell. Anyone can learn it besides two main professions." },
}
P.MODES = { -- key, label, what the page shows
  { "over", "Overview", "Your skill, the next rank, trainers" },
  { "forever", "Forever", "Camp objects and everything new in Forever, by skill" },
  { "skill", "Skill up", "What to make next to raise it" },
  { "gear", "Gear for you", "What it makes that you could wear" },
  { "all", "All recipes", "Every recipe by skill" },
  { "plan", "Plan", "The cheapest way up" },
  { "profit", "Profit", "What sells for more than it costs" },
  { "list", "Crafting list", "What you want to make, and what's missing" },
  { "find", "Find a recipe", "" },
}
function P.Mode()
  local m = NS.cdb and NS.cdb.profMode
  for _, x in ipairs(P.MODES) do if x[1] == m then return x end end
  return P.MODES[1]
end

-- Do you know this recipe? true, or nil when the game doesn't say (a recipe you never opened counts as unknown)
function P.Known(r)
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, r.s)
    if ok and v == true then return true end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, r.s)
    if ok and type(info) == "table" and info.learned == true then return true end
  end
end

-- what a recipe is worth for skill right now: "orange" ... "gray", or nil when you can't make it yet
function P.Color(r, skill)
  if not skill or not r.k or skill < r.k then return nil end
  if skill < (r.y or 0) then return "orange" elseif skill < (r.g or 0) then return "yellow"
  elseif skill < (r.x or 0) then return "green" end
  return "gray"
end
local CHANCE = { orange = "always raises your skill", yellow = "usually raises it", green = "sometimes raises it", gray = "no longer raises it" }
local ORDER = { orange = 1, yellow = 2, green = 3, gray = 4 }

-- What the materials cost at a vendor or the Auction House; nil when a price isn't known
function P.Cost(r)
  local total = 0
  for k = 1, #r.r, 2 do
    local id, n = r.r[k], r.r[k + 1]
    local price = E.VendorPrice(id)
    local ah = NS.Auction and NS.Auction.Price and NS.Auction.Price(id)
    if ah and (not price or ah < price) then price = ah end
    if not price then return nil end
    total = total + price * n
  end
  return total
end

local function CanMake(r) -- how many with what's in your bags
  local least
  for k = 1, #r.r, 2 do
    local n = math.floor(E.Have(r.r[k]) / math.max(1, r.r[k + 1]))
    if not least or n < least then least = n end
  end
  return least or 0
end

local function Materials(r)
  local bits = {}
  for k = 1, #r.r, 2 do bits[#bits + 1] = string.format("%dx %s", r.r[k + 1], E.ItemName(r.r[k])) end
  return table.concat(bits, ", ")
end

---------------------------------------------------------------------------
-- A recipe's page
---------------------------------------------------------------------------
-- the recipe of the same profession that makes a material (bolts, bars, leather), so it's made rather than hunted
local makers = {}
local function MakerOf(prof, id)
  if not prof then return nil end
  if not makers[prof] then
    makers[prof] = {}
    for _, r in ipairs(E.Data().recipes[prof] or {}) do
      r.prof = prof
      if r.i and not makers[prof][r.i] then makers[prof][r.i] = r end
    end
  end
  return makers[prof][id]
end
P.MakerOf = MakerOf

function P.RecipePage(r)
  local skill = E.Skill(r.prof)
  local rows = {}
  local color = P.Color(r, skill)
  local d = {}
  if skill then d[1] = string.format("You have %s %d.", r.prof, skill) end
  if color then d[#d + 1] = "It's " .. color .. " for you: " .. CHANCE[color] .. "." end
  d[#d + 1] = string.format("Yellow at %s, green at %s, gray at %s.", r.y or "?", r.g or "?", r.x or "?")
  rows[1] = { t = string.format("%s %s%s", r.prof, r.k or "?", (r.c or 1) > 1 and string.format(", makes %d", r.c) or ""), d = table.concat(d, " ") }
  if r.cd then rows[#rows + 1] = { t = "It has a long cooldown", d = "You can only make it every so often." } end
  if NS.Crafts then NS.Crafts.RecipeRows(rows, r) end
  rows[#rows + 1] = { h = P.Known(r) and "You know this recipe" or "Where to learn it" }
  local src = E.RecipeSources(r)
  for k = 1, math.min(#src, P.Known(r) and 1 or 8) do
    local s = src[k]
    rows[#rows + 1] = E.At({ t = s.label, d = s.d, i = k == 1 and r.ri or nil, still = s.still }, s.place)
  end
  rows[#rows + 1] = { h = "Materials" }
  for k = 1, #r.r, 2 do
    local id, n = r.r[k], r.r[k + 1]
    local have = E.Have(id)
    local maker = have < n and MakerOf(r.prof, id) or nil
    if maker == r then maker = nil end
    local b = have < n and not maker and E.Best(id) or nil
    rows[#rows + 1] = maker and { t = string.format("%dx %s  (you have %d)", n, E.ItemName(id), have), i = id, page = function() return P.RecipePage(maker) end,
                                  d = string.format("You make it: %s %s. Click for its materials.", r.prof, maker.k or "?") } or E.At({ t = string.format("%dx %s  (you have %d)", n, E.ItemName(id), have), i = id,
                             d = have >= n and "In your bags." or (b and (b.label .. (b.d and b.d ~= "" and ("\n" .. (b.d:match("^[^\n]+") or "")) or ""))
                                 or "Where it comes from isn't known yet.") }, b and b.place)
  end
  local cost = P.Cost(r)
  if cost then rows[#rows + 1] = { t = "The materials cost about " .. NS.Money(cost), d = "Vendor prices, or the last Auction House scan where it's cheaper." } end
  if r.i then
    rows[#rows + 1] = { h = "The item" }
    rows[#rows + 1] = { t = E.ItemName(r.i), i = r.i, q = r.q, d = "Other ways to get it, and what it's for" }
  end
  return { title = r.n, icon = r.i and NS.ItemIcon(r.i) or nil, rows = rows, sub = r.prof .. (r.cat and (", " .. r.cat) or "") }
end

local function RecipeRow(r, d)
  return { t = r.n, d = d, i = r.i, tex = not r.i and (I .. "Trade_Engraving") or nil, q = r.q, page = function() return P.RecipePage(r) end }
end

---------------------------------------------------------------------------
-- A profession's page, four ways
---------------------------------------------------------------------------
local RANK_NAME = { "Apprentice", "Journeyman", "Expert", "Artisan" }
local RANK_CAP = { 75, 150, 225, 300 }
local RANK_SKILL = { 0, 50, 125, 200 }

local function NextRank(prof, max)
  local ranks = E.Data().prof[prof] and E.Data().prof[prof].ranks
  for i = 1, 4 do
    local r = ranks and ranks[i]
    local cap = r and r[2] or RANK_CAP[i]
    if cap > (max or 0) then
      return i, r and r[1] or RANK_NAME[i], cap, r and r[4] or RANK_SKILL[i], r and r[5] or nil, r and r[3] or nil
    end
  end
end

local function TrainerRows(rows, prof, mask, n)
  local list = E.Trainers(prof, mask, n)
  if #list == 0 and mask then list = E.Trainers(prof, nil, n) end
  for _, t in ipairs(list) do rows[#rows + 1] = E.At({ t = t.name, d = t.title .. ", " .. E.PlaceText(t.p) }, t.p) end
  if #list == 0 then rows[#rows + 1] = { t = "No trainer known on your side" } end
end

local function Overview(prof, info, rows)
  local rank, max = E.Skill(prof)
  if rank then
    rows[#rows + 1] = { t = string.format("%s %d / %d", prof, rank, max or 0), d = info[4] }
  else
    rows[#rows + 1] = { t = "You haven't learned " .. prof, d = info[4] }
  end
  local i, name, cap, skill, level, cost = NextRank(prof, rank and max or 0)
  if i then
    local bits = {}
    if skill and skill > 0 then bits[#bits + 1] = string.format("at skill %d%s", skill, rank and rank < skill and string.format(" (%d to go)", skill - rank) or "") end
    if level and level > 0 then bits[#bits + 1] = string.format("level %d%s", level, UnitLevel("player") < level and " (not yet)" or "") end
    if cost and cost > 0 then bits[#bits + 1] = NS.Money(cost) end
    rows[#rows + 1] = { h = rank and "Next rank" or "Start here" }
    rows[#rows + 1] = { t = string.format("%s: up to %d", name, cap), d = #bits > 0 and (table.concat(bits, ", "):gsub("^%l", string.upper)) or nil }
    TrainerRows(rows, prof, 2 ^ (i - 1), 3)
  elseif rank then
    rows[#rows + 1] = { t = "You've learned every rank" }
  end
  if P.ForeverRows then P.ForeverRows(prof, rows, true) end
  local alts = E.AltsWith(prof)
  if #alts > 0 then
    rows[#rows + 1] = { h = "Your other characters" }
    for _, a in ipairs(alts) do rows[#rows + 1] = { t = string.format("%s: %d", a.name, a.rank), d = "As of their last logout." } end
  end
  if rank and info[3] ~= "gather" and E.Data().recipes[prof] then
    local learn = {}
    for _, r in ipairs(E.Data().recipes[prof]) do
      if not r.st and (not r.sd or r.sd == E.Side()) and (r.k or 999) <= rank and not P.Known(r) and not r.ri and P.Color(r, rank) ~= "gray" then learn[#learn + 1] = r end
    end
    table.sort(learn, function(a, b) return (a.k or 0) > (b.k or 0) end)
    if #learn > 0 then
      rows[#rows + 1] = { h = "A trainer can teach you (recipes you don't know yet)" }
      for k = 1, math.min(#learn, 10) do
        local t, fee = E.Teacher(prof, learn[k].s)
        rows[#rows + 1] = RecipeRow(learn[k], string.format("Skill %s%s%s", learn[k].k or "?", fee and fee > 0 and (", " .. NS.Money(fee)) or "", t and (", " .. t.name) or ""))
      end
    end
  end
  if rank then
    rows[#rows + 1] = { h = "Trainers near you" }
    TrainerRows(rows, prof, nil, 4)
  end
  local c = NS.Currency and NS.Currency(3402)
  local hub = E.Data().hub[E.Side()]
  if hub and rank and info[3] == "craft" then
    rows[#rows + 1] = { h = "Merchant's Favor (it buys recipes)" }
    rows[#rows + 1] = E.At({ t = c and ("You have " .. c.quantity) or "Merchant's Favor", d = table.concat(E.Data().crateSteps, "\n") },
                           hub[2] > 0 and E.Point(hub[2], hub[6] / 100, hub[7] / 100) or nil)
  end
end

local function Recipes(prof)
  local out = {}
  for _, r in ipairs(E.Data().recipes[prof] or {}) do
    r.prof = prof
    if not r.sd or r.sd == E.Side() then out[#out + 1] = r end
  end
  return out
end

local function Gathering(prof, rows)
  local rank = E.Skill(prof) or 0
  rows[#rows + 1] = { h = "What you gather, and where" }
  local n = 0
  local list = {}
  for id, e in pairs(E.Data().reagents) do
    if e.o then
      local need = NS.GATHER_SKILL[e.o:lower()]
      local isOre = need ~= nil or e.o:lower():find("vein", 1, true) or e.o:lower():find("deposit", 1, true)
      local isFish = e.o:lower():find("school", 1, true) or e.o:lower():find("wreckage", 1, true)
      local kind = isOre and "Mining" or isFish and "Fishing" or "Herbalism"
      if kind == prof then list[#list + 1] = { id = id, o = e.o, need = need and need[2] } end
    end
  end
  if prof == "Skinning" then
    for id, f in pairs(NS.MATERIAL_FAMILY) do if f[4] == "Skinning" then list[#list + 1] = { id = id, o = string.format("Beasts of about level %d-%d", f[1], f[2]), need = f[1] } end end
  end
  table.sort(list, function(a, b)
    if (a.need or 999) ~= (b.need or 999) then return (a.need or 999) < (b.need or 999) end
    return a.o < b.o
  end)
  for _, e in ipairs(list) do
    n = n + 1
    if n > 40 then break end
    local b = E.Best(e.id)
    local price = NS.Auction and NS.Auction.Price and NS.Auction.Price(e.id)
    local d = e.o .. (e.need and prof == "Mining" and string.format(" (skill %d%s)", e.need, rank < e.need and ", not yet" or "") or "")
    if b and b.place then d = d .. "\nNearest: " .. E.PlaceText(b.place) end
    if price then d = d .. "\nAuction House: " .. NS.Money(price) end
    rows[#rows + 1] = E.At({ t = E.ItemName(e.id), i = e.id, d = d }, b and b.place)
  end
  if n == 0 then rows[#rows + 1] = { t = "Fish from any open water; schools on the minimap give more." } end
end

local function SkillUp(prof, info, rows)
  local rank, max = E.Skill(prof)
  if info[3] == "gather" or prof == "Fishing" then Gathering(prof, rows) return end
  local learned = rank ~= nil
  if not rank then rows[#rows + 1] = { t = "You haven't learned " .. prof, d = "The Overview page has the nearest trainer." } rank = 1 end
  local now, soon = {}, {}
  for _, r in ipairs(Recipes(prof)) do
    local c = P.Color(r, rank)
    if c and c ~= "gray" and not r.cd then
      local known = P.Known(r) or r.st
      now[#now + 1] = { r = r, c = c, known = known and true or false, cost = P.Cost(r), make = CanMake(r) }
    elseif not c and r.k and r.k <= rank + 15 then
      soon[#soon + 1] = r
    end
  end
  table.sort(now, function(a, b)
    if a.known ~= b.known then return a.known end
    if ORDER[a.c] ~= ORDER[b.c] then return ORDER[a.c] < ORDER[b.c] end
    if (a.make > 0) ~= (b.make > 0) then return a.make > 0 end
    if (a.cost or 1e9) ~= (b.cost or 1e9) then return (a.cost or 1e9) < (b.cost or 1e9) end
    return (a.r.k or 0) > (b.r.k or 0)
  end)
  local function Row(e)
    local d = string.format("%s: %s\n%s", e.c:gsub("^%l", string.upper), CHANCE[e.c], Materials(e.r))
    if e.make > 0 then d = d .. string.format("\nYou can make %d with what's in your bags.", e.make) end
    if e.cost then d = d .. "\nMaterials: about " .. NS.Money(e.cost) end
    return RecipeRow(e.r, d)
  end
  local known, other = {}, {}
  for _, e in ipairs(now) do local l = e.known and known or other; l[#l + 1] = e end
  if max and rank >= max then
    rows[#rows + 1] = { t = string.format("You're at your limit (%d / %d)", rank, max), d = "Learn the next rank first: the Overview page has the trainer." }
  end
  if #known > 0 then
    rows[#rows + 1] = { h = learned and string.format("Make these at skill %d (recipes you know)", rank) or "Recipes you start with" }
    for k = 1, math.min(#known, 8) do rows[#rows + 1] = Row(known[k]) end
  end
  if #other > 0 then
    rows[#rows + 1] = { h = #known > 0 and "Or learn one of these" or string.format("Recipes that raise it at skill %d", rank) }
    for k = 1, math.min(#other, 8) do rows[#rows + 1] = Row(other[k]) end
  end
  if #soon > 0 then
    table.sort(soon, function(a, b) return a.k < b.k end)
    rows[#rows + 1] = { h = "Soon" }
    for k = 1, math.min(#soon, 8) do rows[#rows + 1] = RecipeRow(soon[k], "At skill " .. soon[k].k) end
  end
  if #now + #soon == 0 then rows[#rows + 1] = { t = "Nothing left that raises it", d = "Every recipe is gray at this skill." } end
end

local function GearFor(prof, _, rows)
  local rank = E.Skill(prof)
  local byId = {}
  for _, e in ipairs(NS.Upgrades and NS.Upgrades.all or {}) do byId[e.id] = e end
  local list = {}
  for _, r in ipairs(Recipes(prof)) do
    local e = r.i and byId[r.i]
    if e then list[#list + 1] = { r = r, e = e } end
  end
  table.sort(list, function(a, b) return (a.r.k or 0) < (b.r.k or 0) end)
  rows[#rows + 1] = { h = "What it makes that would be an upgrade for you (now or within a few levels)" }
  for k = 1, math.min(#list, 24) do
    local r, e = list[k].r, list[k].e
    rows[#rows + 1] = RecipeRow(r, string.format("%s  +%.1f%s\n%s %s%s", e.slot, e.gain, (e.reqLevel or 0) > UnitLevel("player") and (", wearable at " .. e.reqLevel) or "",
                                                 prof, r.k or "?", rank and (rank >= (r.k or 0) and " (you can make it)" or string.format(" (you have %d)", rank)) or ""))
  end
  if #list == 0 then rows[#rows + 1] = { t = NS.Gear and NS.Gear.Status() or "Nothing it makes beats what you wear right now" } end
end

local function BandPage(prof, lo, hi)
  local rows, rank = {}, E.Skill(prof)
  for _, r in ipairs(Recipes(prof)) do
    local k = r.k or 0
    if k >= lo and k <= hi and #rows < 160 then
      local c = P.Color(r, rank)
      local src = r.st and "known from the start" or r.ri and (r.fav and (r.fav .. " Merchant's Favor") or "a recipe item") or "trainer"
      rows[#rows + 1] = RecipeRow(r, string.format("Skill %s, %s%s%s", r.k or "?", src, c and (", " .. c) or "", P.Known(r) and ", you know it" or ""))
      rows[#rows].dim = rank and rank < k or nil
    end
  end
  if #rows == 0 then rows[1] = { t = "No recipes in this range" } end
  return { title = string.format("%s %d-%d", prof, math.max(1, lo), hi), rows = rows, sub = "Click a recipe for its materials and where to learn it." }
end

local function AllRecipes(prof, info, rows)
  if not E.Data().recipes[prof] then Gathering(prof, rows) return end
  local all, rank = Recipes(prof), E.Skill(prof)
  for lo = 0, 275, 25 do
    local hi = lo + 24
    if lo == 275 then hi = 300 end
    local n, known = 0, 0
    for _, r in ipairs(all) do if (r.k or 0) >= lo and (r.k or 0) <= hi then n = n + 1; if P.Known(r) then known = known + 1 end end end
    if n > 0 then
      rows[#rows + 1] = { t = string.format("Skill %d-%d", math.max(1, lo), hi), d = string.format("%d recipe%s%s", n, n == 1 and "" or "s", known > 0 and (", you know " .. known) or ""),
                          hot = rank and rank >= lo and rank <= hi or nil, page = function() return BandPage(prof, lo, hi) end }
    end
  end
end

---------------------------------------------------------------------------
-- What Forever added: the camp objects, and every new recipe by skill, with where its pattern comes from
---------------------------------------------------------------------------
function P.IsNew(r) return (r.s or 0) > 60000 or (r.i or 0) > 60000 end
local function NewOnes(prof)
  local out = {}
  if not E.Data().recipes[prof] then return out end
  for _, r in ipairs(Recipes(prof)) do if P.IsNew(r) and r.cat ~= "Camping" then out[#out + 1] = r end end
  table.sort(out, function(a, b) if (a.k or 0) ~= (b.k or 0) then return (a.k or 0) < (b.k or 0) end return a.n < b.n end)
  return out
end
P.NewOnes = NewOnes
-- "Pattern: sold by Xizzer, Ironforge 43.6, 29.0" / "Pattern drops from ..." / "A trainer teaches it"
local function HowText(r)
  local ok, src = pcall(E.RecipeSources, r)
  local s = ok and src and src[1]
  local from = P.From(r)
  local head = r.ri and "Pattern: " or ""
  if s and s.label then
    local where = type(s.d) == "string" and s.d:match("^[^\n]+") or nil
    return head .. s.label .. (where and where ~= "" and (", " .. where) or "")
  end
  return head .. (P.FromText and P.FromText(r) or from)
end
P.HowText = HowText
local function NewRow(r, rank)
  local c = P.Color(r, rank)
  local row = RecipeRow(r, string.format("%s %s%s%s\n%s", r.prof, r.k or "?", c and (", " .. c .. " for you") or "", P.Known(r) and ", you know it" or "", HowText(r)))
  row.ring = P.Known(r) and "good" or nil
  row.dim = rank and rank < (r.k or 0) or nil
  row.key = "new" .. tostring(r.s)
  return row
end
local function NewPage(prof, title, list)
  local rows, rank = {}, E.Skill(prof)
  for k = 1, math.min(#list, 120) do rows[k] = NewRow(list[k], rank) end
  if #list > 120 then rows[#rows + 1] = { t = string.format("%d more", #list - 120), still = true, dim = true } end
  if #rows == 0 then rows[1] = { t = "None", still = true } end
  return { title = title, rows = rows, sub = "New in Forever. Click one for its materials and every way to learn it." }
end
function P.ForeverRows(prof, rows, short)
  local QF = NS.QuestFind
  local rank = E.Skill(prof)
  local camp = QF and QF.CampRows and QF.CampRows(prof) or {}
  if #camp > 0 then
    rows[#rows + 1] = { h = "For your campsite" }
    for _, r in ipairs(camp) do rows[#rows + 1] = r end
    if not short then rows[#rows + 1] = { t = "Everything for your campsite", d = "The campfire, the bedroll and every profession's objects", tex = I .. "Spell_Fire_Fire", key = "qkcamp", page = QF.CampPage } end
  end
  local list = NewOnes(prof)
  if #list == 0 then return rows end
  rows[#rows + 1] = { h = string.format("New in Forever: %d recipes", #list) }
  if short then
    rows[#rows + 1] = { t = string.format("%d recipes new in Forever", #list), d = "By skill and by kind, with where each pattern comes from", tex = I .. "INV_Scroll_03", key = "newall", page = function()
      local r = {}
      P.ForeverRows(prof, r)
      return { title = prof .. ": Forever", rows = r, sub = "Camp objects and everything new in Forever" }
    end }
    return rows
  end
  if rank then
    local near = {}
    for _, r in ipairs(list) do if not P.Known(r) and (r.k or 0) >= rank - 20 and (r.k or 0) <= rank + 30 then near[#near + 1] = r end end
    if #near > 0 then
      rows[#rows + 1] = { t = string.format("Around your skill (%d)", rank), d = string.format("%d you don't know yet", #near), hot = true, tex = I .. "INV_Scroll_03", key = "newnear", page = function() return NewPage(prof, prof .. " around " .. rank, near) end }
    end
  end
  for lo = 0, 275, 25 do
    local hi = lo == 275 and 300 or lo + 24
    local part, known = {}, 0
    for _, r in ipairs(list) do if (r.k or 0) >= lo and (r.k or 0) <= hi then part[#part + 1] = r if P.Known(r) then known = known + 1 end end end
    if #part > 0 then
      rows[#rows + 1] = { t = string.format("Skill %d-%d", math.max(1, lo), hi), d = string.format("%d new%s", #part, known > 0 and (", you know " .. known) or ""), hot = rank and rank >= lo and rank <= hi or nil, key = "newband" .. lo,
                          page = function() return NewPage(prof, string.format("%s %d-%d", prof, math.max(1, lo), hi), part) end }
    end
  end
  local kinds, order = {}, {}
  for _, r in ipairs(list) do
    local c = r.cat or "Other"
    if not kinds[c] then kinds[c] = {} order[#order + 1] = c end
    table.insert(kinds[c], r)
  end
  table.sort(order)
  rows[#rows + 1] = { h = "By kind" }
  for _, c in ipairs(order) do
    local l = kinds[c]
    rows[#rows + 1] = { t = c, d = string.format("%d, skill %s to %s", #l, l[1].k or "?", l[#l].k or "?"), i = l[1].i, key = "newkind" .. c, page = function() return NewPage(prof, prof .. ": " .. c, l) end }
  end
  return rows
end

function P.Page(info)
  local prof = info[1]
  local rows, mode = {}, P.Mode()[1]
  if mode == "skill" then SkillUp(prof, info, rows)
  elseif mode == "forever" then P.ForeverRows(prof, rows)
  elseif mode == "gear" then GearFor(prof, info, rows)
  elseif mode == "all" then AllRecipes(prof, info, rows)
  elseif mode == "plan" then NS.Crafts.PlanRows(prof, info, rows)
  elseif mode == "profit" then NS.Crafts.ProfitRows(prof, info, rows)
  else Overview(prof, info, rows) end
  local rank, max = E.Skill(prof)
  return { title = prof .. (rank and string.format("  %d / %d", rank, max or 0) or ""), icon = info[2], rows = rows, sub = P.Mode()[3] }
end

---------------------------------------------------------------------------
-- Find a recipe: by name, by what it makes or by its material, and by where it comes from
---------------------------------------------------------------------------
P.FROM = { -- key, label, test
  { "any", "anywhere" }, { "trainer", "trainers" }, { "vendor", "vendors" }, { "drop", "drops" }, { "quest", "quests" },
  { "rep", "a reputation" }, { "favor", "Merchant's Favor" }, { "none", "unknown" },
}
function P.From(r) -- the main way to get it
  if r.st or not r.ri then return "trainer" end
  if r.fav then return "favor" end
  if r.rep then return "rep" end
  if r.v and #r.v > 0 then return "vendor" end
  if r.qs and #r.qs > 0 then return "quest" end
  local C = NS.Collect
  if (r.d and #r.d > 0) or (C and #C.Drops(r.ri) > 0) then return "drop" end
  return "none"
end
P.find, P.prof, P.from, P.missing = "", nil, "any", false
local function FromLabel(key) for _, f in ipairs(P.FROM) do if f[1] == key then return f[2] end end end
local FROM_WORD = { trainer = "Trainer", vendor = "Vendor", drop = "Drop", quest = "Quest", rep = "Reputation", favor = "Merchant's Favor", none = "Source unknown" }
local function FromText(r)
  local k = P.From(r)
  if k == "rep" and r.rep then
    for _, f in ipairs(E.Data().factions) do if f.id == r.rep[1] then return f.n end end
  elseif k == "favor" and type(r.fav) == "number" then return string.format("%d Merchant's Favor", r.fav)
  elseif k == "drop" and NS.Collect then
    local l = NS.Collect.Drops(r.ri, r.d)
    if l[1] then return "Drop: " .. E.NpcName(l[1].npc) .. (l[1].p and ("  " .. NS.Collect.Percent(l[1].p)) or "") end
  end
  return FROM_WORD[k]
end
P.FromText = FromText
local LIMIT = 120
local function FindRows()
  local find = (P.find or ""):lower()
  local list, total = {}, 0
  for _, info in ipairs(P.LIST) do
    local prof = info[1]
    if not P.prof or P.prof == prof then
      for _, r in ipairs(E.Data().recipes[prof] and Recipes(prof) or {}) do
        local hit = find == "" or r.n:lower():find(find, 1, true) ~= nil
        if not hit and r.i then hit = E.ItemName(r.i):lower():find(find, 1, true) ~= nil end
        if not hit and find ~= "" and #find >= 4 then
          for k = 1, #r.r, 2 do if E.ItemName(r.r[k]):lower():find(find, 1, true) then hit = true break end end
        end
        if hit and (P.from == "any" or P.From(r) == P.from) and not (P.missing and P.Known(r)) then
          total = total + 1
          if #list < LIMIT then list[#list + 1] = r end
        end
      end
    end
  end
  local function Cycle(values, cur) for i, v in ipairs(values) do if v == cur then return values[i % #values + 1] end end return values[1] end
  local rows = { { t = "Profession: " .. (P.prof or "all"), tex = I .. "INV_Misc_Book_09", actLabel = "Change", key = "findprof", still = true, act = function()
      local v = { "" }
      for _, info in ipairs(P.LIST) do if E.Data().recipes[info[1]] then v[#v + 1] = info[1] end end
      local nx = Cycle(v, P.prof or "")
      P.prof = nx ~= "" and nx or nil
      NS.Window.Refresh()
    end },
    { t = "From: " .. FromLabel(P.from), tex = I .. "INV_Misc_Map_01", actLabel = "Change", key = "findfrom", still = true, act = function()
      local v = {}
      for _, f in ipairs(P.FROM) do v[#v + 1] = f[1] end
      P.from = Cycle(v, P.from)
      NS.Window.Refresh()
    end },
    { t = P.missing and "Only ones you don't know" or "Known ones too", tex = I .. "INV_Misc_Note_01", actLabel = "Change", key = "findmiss", still = true, act = function()
      P.missing = not P.missing
      NS.Window.Refresh()
    end },
    { h = string.format("%d recipe%s", total, total == 1 and "" or "s") .. (total > LIMIT and string.format(" (first %d: type to narrow it down)", LIMIT) or "") } }
  table.sort(list, function(a, b) if a.prof ~= b.prof then return a.prof < b.prof end if (a.k or 0) ~= (b.k or 0) then return (a.k or 0) < (b.k or 0) end return a.n < b.n end)
  for _, r in ipairs(list) do
    rows[#rows + 1] = { t = r.n, d = string.format("%s %s  ·  %s", r.prof, r.k or "?", FromText(r)), i = r.i, q = r.q, key = "find" .. r.s, ring = P.Known(r) and "good" or nil,
                        tex = not r.i and I .. "INV_Scroll_03" or nil, page = function() return P.RecipePage(r) end }
  end
  if total == 0 then rows[#rows + 1] = { t = "Nothing matches", d = "Try part of the recipe's name, what it makes or one of its materials.", still = true } end
  return rows
end
P.FindRows = FindRows

function P.Rows()
  if P.Mode()[1] == "find" then return FindRows() end
  if P.Mode()[1] == "list" then return NS.Crafts.ListRows() end
  local mine, other = {}, {}
  for _, info in ipairs(P.LIST) do
    local rank, max = E.Skill(info[1])
    local d
    if rank then
      local i, name, _, skill = NextRank(info[1], max or 0)
      d = (i and skill and rank >= skill and string.format("%s is ready to learn", name)) or (max and rank >= max and "At its limit") or nil
    else
      local alts = E.AltsWith(info[1])
      if alts[1] then d = string.format("%s has %d", alts[1].name, alts[1].rank) end
    end
    local row = { t = info[1] .. (rank and string.format("  %d / %d", rank, max or 0) or ""), d = d, tex = info[2], dim = not rank or nil, key = "prof" .. info[1],
                  page = function() return P.Page(info) end }
    if rank then mine[#mine + 1] = row else other[#other + 1] = row end
  end
  local rows = {}
  if #mine > 0 then rows[#rows + 1] = { h = "Yours" } end
  for _, r in ipairs(mine) do rows[#rows + 1] = r end
  rows[#rows + 1] = { h = #mine > 0 and "The others" or "Professions (you can learn two main ones)" }
  for _, r in ipairs(other) do rows[#rows + 1] = r end
  return rows
end
