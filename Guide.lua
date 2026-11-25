-- Sunstone: the Guide tab. "What now?" for your character at your level; what's different coming from Retail; Forever's own
-- systems; which races can be which classes; and what each stat does for you. Works from level 1, without the desktop helper.
-- Data: GuideData.lua (facts checked against Forever guides; what they disagree on is said to be uncertain), the rest live.

local _, NS = ...
local Gd = NS.Module("Guide")
NS.Guide = Gd
local E = NS.Engine
local I = "Interface\\Icons\\"

Gd.MODES = {
  { "now", "What now?", "For your character, right now" },
  { "retail", "From Retail", "What's different here" },
  { "systems", "Forever's systems", "Legacy, campsites and more" },
  { "who", "Class & race", "Who can be what" },
  { "stats", "Stats", "What each does for you" },
  { "share", "Share", "Help everyone's numbers" },
  { "set", "Settings", "Arrow, map, tooltips" },
}
function Gd.Mode()
  local m = NS.cdb and NS.cdb.guideMode
  for _, x in ipairs(Gd.MODES) do if x[1] == m then return x end end
  return Gd.MODES[1]
end
Gd.find = ""

local function Src() return type(_G.SunstoneGuide) == "table" and _G.SunstoneGuide or {} end
local function List(t) return type(t) == "table" and t or {} end
local function Level() return UnitLevel("player") or 1 end
local function Class() return select(2, UnitClass("player")) end
local function Money(c) return NS.Money(math.floor((c or 0) + 0.5)) end
local function Purse() return GetMoney and tonumber(GetMoney()) or 0 end

---------------------------------------------------------------------------
-- What your trainer teaches, and what it costs: what trainers have really charged you (seen at their window), else Classic's price
---------------------------------------------------------------------------
local function Seen()
  NS.db.trainer = type(NS.db.trainer) == "table" and NS.db.trainer or {}
  return NS.db.trainer
end
function Gd.SeeTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost) then return end
  local _, class = UnitClass("player")
  local t = Seen()
  t[class] = type(t[class]) == "table" and t[class] or {}
  local n = 0
  for i = 1, math.min(GetNumTrainerServices() or 0, 400) do
    local name, rank = GetTrainerServiceInfo(i)
    local cost = GetTrainerServiceCost(i)
    if type(name) == "string" and type(cost) == "number" and cost > 0 then
      local r = tonumber(tostring(rank or ""):match("%d+")) or 0
      t[class][name .. "|" .. r] = cost
      n = n + 1
    end
  end
  if n > 0 and NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
end
-- copper, and true when it's a price you've seen yourself
function Gd.Cost(name, rank, level)
  local t = Seen()[Class() or ""]
  local v = type(t) == "table" and (t[name .. "|" .. (rank or 0)] or t[name .. "|0"])
  if type(v) == "number" then return v, true end
  local c = List(Src().cost)[name]
  return c and c[level] or nil, false
end

local function HasSpell(name)
  for _, sp in ipairs(E.Data().spells[Class() or ""] or {}) do
    if sp[3] == name then
      for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false }) do
        local ok, v = false, nil
        if fn then ok, v = pcall(fn, sp[2]) end
        if ok and v then return true end
      end
    end
  end
  return false
end

local function Known(id)
  for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false }) do
    if fn then
      local ok, v = pcall(fn, id)
      if ok and v then return true end
    end
  end
  return false
end

-- { now = spells to train, soon = the next levels', cost = what the known prices add up to, missing = how many have none }
function Gd.Training()
  local list = E.Data().spells[Class() or ""] or {}
  local L = Level()
  local out = { now = {}, soon = {}, cost = 0, missing = 0, seen = true }
  if not (IsPlayerSpell or IsSpellKnown) then return out end
  local best = {} -- only the highest rank you could learn of each counts towards "you're missing it"
  for _, s in ipairs(list) do
    if s[5] == 0 and s[6] == 0 and s[7] == "" then
      if s[1] <= L and s[1] > L - 12 and not Known(s[2]) then
        out.now[#out.now + 1] = s
        local c, seen = Gd.Cost(s[3], s[4], s[1])
        if c then out.cost = out.cost + c; if not seen then out.seen = false end else out.missing = out.missing + 1 end
      elseif s[1] > L and s[1] <= L + 4 then out.soon[#out.soon + 1] = s end
    end
  end
  return out
end

local function SpellTex(id) return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or (GetSpellTexture and GetSpellTexture(id)) or nil end
local function SpellRow(s, L)
  local c, seen = Gd.Cost(s[3], s[4], s[1])
  return { t = s[3] .. (s[4] > 0 and (" (rank " .. s[4] .. ")") or ""), tex = SpellTex(s[2]), spell = s[2], still = true, dim = s[1] > L or nil,
           d = "Level " .. s[1] .. (c and ("  ·  " .. (seen and "" or "about ") .. Money(c)) or "") }
end

local function TrainPage()
  local t, rows, L = Gd.Training(), {}, Level()
  if #t.now > 0 then
    rows[1] = { t = string.format("%d to learn for %s%s", #t.now, t.seen and "" or "about ", Money(t.cost)), still = true,
                d = "You have " .. Money(Purse()) .. "." .. (t.missing > 0 and string.format(" (%d with no known price.)", t.missing) or "")
                  .. (t.seen and "" or " Prices are Classic's until you've opened a trainer's window: then they're what yours asks.") }
    rows[#rows + 1] = { h = "You can learn now" }
    for _, s in ipairs(t.now) do rows[#rows + 1] = SpellRow(s, L) end
  else
    rows[1] = { t = "You've learned everything for your level", still = true }
  end
  if #t.soon > 0 then
    rows[#rows + 1] = { h = "At your next levels" }
    for _, s in ipairs(t.soon) do rows[#rows + 1] = SpellRow(s, L) end
  end
  local name = UnitClass("player")
  if NS.Travel and NS.Travel.Search and type(name) == "string" then
    local ok, found = pcall(NS.Travel.Search, name:lower() .. " trainer")
    local n = 0
    for _, r in ipairs(ok and type(found) == "table" and found or {}) do
      if r.m and n < 3 then
        if n == 0 then rows[#rows + 1] = { h = "Nearest trainers" } end
        n = n + 1
        rows[#rows + 1] = { t = r.t, d = r.d, m = r.m, x = r.x, y = r.y }
      end
    end
  end
  return { title = "Train new skills", icon = I .. "INV_Misc_Book_09", rows = rows, sub = "What your class trainer teaches" }
end

---------------------------------------------------------------------------
-- Class quests
---------------------------------------------------------------------------
-- { { name, level, icon, quest = the next one to do, left = how many, state = "now" | "soon" | "log" } }
function Gd.ClassQuests()
  local out, L = {}, Level()
  local log = E.Log()
  for _, m in ipairs(List(List(Src().milestones)[Class() or ""])) do
    if m[2] <= L + 4 and not HasSpell(m[1]) then
      local open, left, inlog, done = nil, 0, nil, 0
      for _, q in ipairs(m[4]) do
        if E.Done(q) then done = done + 1
        elseif E.QuestOK(q) then
          left = left + 1
          if log[q] then inlog = inlog or q end
          if not open then
            local chain = E.Chain(q)
            if chain and #chain == 0 then open = q end
          end
        end
      end
      local pick = inlog or open
      if pick and left > 0 then out[#out + 1] = { name = m[1], level = m[2], icon = I .. m[3], quest = pick, state = inlog and "log" or m[2] <= L and "now" or "soon" } end
    end
  end
  return out
end
local function ClassQuestPage(c)
  local rows = {}
  local qr = E.QuestRoute(c.quest)
  rows[1] = E.At({ t = E.QuestName(c.quest), d = (c.state == "log" and "It's in your quest log." or qr and qr.d or "Where it starts isn't recorded."), still = true }, qr and qr.place)
  rows[#rows + 1] = { t = "From level " .. c.level, d = "Class quests give spells, forms, demons, totems and good gear: worth doing when they open.", still = true }
  return { title = c.name, icon = c.icon, rows = rows, sub = "Class quest" }
end

---------------------------------------------------------------------------
-- What now?
---------------------------------------------------------------------------
local RIDE = { { 40, 1000000, "Riding", "60% faster. 100 gold (90 at Honored with your faction); one guide counts the first mount in that, another mounts at 20 gold each." },
               { 60, 10000000, "Fast riding", "100% faster. 1,000 gold for the training (900 at Honored), and 200 for the mount." } }
local MILES = {
  { 10, "Talents", "Your first talent point. The Talents tab has a plan for each way to play." },
  { 10, "Class quest", "Many classes get one at 10: forms, demons, pets, stances." },
  { 13, "First dungeons", "Ragefire Chasm and Hall of Thanes begin around here. See the Dungeons tab." },
  { 20, "More of your class", "Most classes get something big at 20." },
  { 25, "Legacy Points", "Your account's first Legacy Point (also at 150 in a crafting profession)." },
  { 40, "Riding, mail and plate", "Riding (100 gold). Hunters and shamans can learn mail, warriors and paladins plate." },
  { 45, "Legacy", "Another Legacy Point for the class." },
  { 60, "The cap", "Fast riding, raids, and a third Legacy Point for the class." },
}

local function SavePage(next)
  local rows = { { t = next[3] .. " at level " .. next[1], d = next[4], still = true },
                 { t = "You have " .. Money(Purse()), d = Purse() >= next[2] and "That covers the training." or string.format("%s to go for the training.", Money(next[2] - Purse())), still = true },
                 { h = "Ways to get there" },
                 { t = "Gold tab", d = "What to farm for the time, flips, and what in your bags sells.", still = true },
                 { t = "Reputation", d = "Honored with your own faction takes 10% off riding and mounts.", still = true } }
  return { title = "Save for " .. next[3]:lower(), icon = I .. "Ability_Mount_RidingHorse", rows = rows }
end

local function Go(tab, mode, value)
  return function()
    if mode then NS.cdb[mode] = value end
    NS.Window.tab = tab
    NS.Window.Refresh()
  end
end

function Gd.Now()
  local rows, L = {}, Level()
  local function Head(h) rows[#rows + 1] = { h = h } end
  Head("Do this next")
  if NS.Share and NS.Share.Due() then
    rows[#rows + 1] = { t = "Send your new finds", tex = I .. "INV_Misc_Note_02", key = "gnShare", still = true, actLabel = "Copy link", act = NS.Share.Copy, d = "One link: paste it into your browser, press Send on the page." }
  end
  -- quests ready to hand in, bags
  if NS.Route and NS.Route.Waiting then
    local n, xp, slots, free = NS.Route.Waiting()
    if n > 0 then
      rows[#rows + 1] = { t = string.format("Hand in %d finished quest%s", n, n == 1 and "" or "s"), tex = I .. "INV_Misc_Note_01", key = "gnHand", still = true, ring = "good",
                          d = (xp > 0 and (xp .. " XP waiting") or "Their XP is waiting") .. (slots > 0 and string.format(", and they hold %d bag slots", slots) or ""), actLabel = "Route", act = Go("route") }
    end
    if free and free <= 4 then
      rows[#rows + 1] = { t = string.format("Only %d bag slot%s free", free, free == 1 and "" or "s"), tex = I .. "INV_Misc_Bag_08", key = "gnBags", still = true, ring = "warn", d = "See what's safe to sell.",
                          actLabel = "Bags", act = Go("gold", "goldMode", "bags") }
    end
  end
  -- training
  local t = Gd.Training()
  if #t.now > 0 then
    rows[#rows + 1] = { t = string.format("Train %d new skill%s", #t.now, #t.now == 1 and "" or "s"), tex = I .. "INV_Misc_Book_09", key = "gnTrain", ring = Purse() >= t.cost and "good" or "warn",
                        d = string.format("%s%s in all; you have %s", t.seen and "" or "About ", Money(t.cost), Money(Purse())), page = TrainPage }
  end
  -- talents
  local st = NS.Talents and NS.Talents.Status and NS.Talents.Status(nil)
  if st and (st.unspent or 0) > 0 then
    local m = st.missing and st.missing[1]
    rows[#rows + 1] = { t = string.format("Spend %d talent point%s", st.unspent, st.unspent == 1 and "" or "s"), tex = I .. "Ability_Marksmanship", key = "gnTalent", still = true, ring = "good",
                        d = m and (m.name .. " " .. m.rank) or "See your plan", actLabel = "Talents", act = Go("talents") }
  end
  -- class quests
  for _, c in ipairs(Gd.ClassQuests()) do
    rows[#rows + 1] = { t = "Class quest: " .. c.name, tex = c.icon, key = "gnCq" .. c.name, dim = c.state == "soon" or nil, ring = c.state == "now" and "good" or nil,
                        d = (c.state == "soon" and ("From level " .. c.level .. ": ") or c.state == "log" and "In your log: " or "") .. E.QuestName(c.quest), page = function() return ClassQuestPage(c) end }
  end
  -- weapons it could learn
  local U = NS.Upgrades
  if U and U.Can and U.WEAPON_NAME then
    local can = {}
    for sub, name in pairs(U.WEAPON_NAME) do
      local state, lvl = U.Can(2, sub)
      if state == "train" and (lvl or 0) <= L then can[#can + 1] = { sub, name } end
    end
    if #can > 0 then
      table.sort(can, function(a, b) return a[2] < b[2] end)
      local names = {}
      for _, c in ipairs(can) do names[#names + 1] = c[2] end
      rows[#rows + 1] = { t = "Weapons you could learn", tex = I .. "INV_Sword_04", key = "gnWeapon", d = table.concat(names, ", "), page = function()
        local r = {}
        for _, c in ipairs(can) do
          local w = E.WeaponMaster(c[1])
          r[#r + 1] = E.At({ t = c[2], d = w and (w.name .. ", " .. w.city) or "No weapon master of your faction teaches it, by our lists", still = true }, w and w.p)
        end
        return { title = "Weapons you could learn", icon = I .. "INV_Sword_04", rows = r, sub = "From weapon masters" }
      end }
    end
  end
  -- a flight path you don't have yet, near you
  local f = NS.Travel and NS.Travel.NewFlight and NS.Travel.NewFlight()
  if f then
    rows[#rows + 1] = { t = "Learn a flight path", tex = I .. "Ability_Mount_WarHippogryph", key = "gnFly", d = f.name .. "  ·  " .. E.PlaceText(f.p), m = f.p.m, x = f.p.x, y = f.p.y }
  end
  -- professions at their limit
  for _, info in ipairs(NS.Professions and NS.Professions.LIST or {}) do
    local rank, max = E.Skill(info[1])
    if rank and max and rank >= max and max < 300 then
      rows[#rows + 1] = { t = info[1] .. " is at its limit", tex = info[2], key = "gnProf" .. info[1], still = true, d = string.format("%d / %d: learn the next rank from a trainer", rank, max),
                          actLabel = "Show", act = Go("prof", "profMode", "over") }
    end
  end
  if #rows == 1 then rows[2] = { t = "Nothing waiting", d = "Off you go: XP & Route says where.", still = true } end
  -- right for your level
  local dun = {}
  for _, d in ipairs(type(_G.SunstoneDungeons) == "table" and _G.SunstoneDungeons.list or {}) do
    if not d.raid and d.lo > 0 and L >= d.lo - 1 and L <= d.hi then dun[#dun + 1] = d end
  end
  Head("Right for your level")
  for _, d in ipairs(dun) do
    rows[#rows + 1] = { t = d.n, tex = d.icon, key = "gnDg" .. d.n, d = string.format("Dungeon  ·  levels %d-%d  ·  %s", d.lo, d.hi, d.loc), page = function() return NS.Dungeons.Page(d) end }
  end
  if #dun == 0 then
    rows[#rows + 1] = { t = L < 13 and "Dungeons begin around level 13" or "No dungeon for exactly your level", still = true, d = "XP & Route: an XP run picks up the quests around you that pay best." }
  end
  local rest = GetXPExhaustion and GetXPExhaustion()
  if type(rest) == "number" and rest > 0 then
    rows[#rows + 1] = { t = "You're rested", tex = I .. "Spell_Nature_Sleep", key = "gnRest", still = true, d = string.format("%s extra XP from kills still to come: a good time to fight.", BreakUpLargeNumbers and BreakUpLargeNumbers(rest) or rest) }
  elseif L < 60 then
    rows[#rows + 1] = { t = "Not rested", tex = I .. "Spell_Nature_Sleep", key = "gnRest", still = true, d = "Log out in an inn or a city to earn extra XP for next time." }
  end
  -- what's coming
  Head("Coming up")
  local free = Class() == "WARLOCK" or Class() == "PALADIN"
  if free and L < 40 then
    rows[#rows + 1] = { t = "Level 40: your mount is a class quest", tex = I .. "Ability_Mount_RidingHorse", key = "gnRide", still = true,
                        d = "Warlocks and paladins learn theirs from a class quest, so there's no need to save for riding." }
  end
  for _, r in ipairs(RIDE) do
    if L < r[1] and not (free and r[1] == 40) then
      rows[#rows + 1] = { t = string.format("Save for %s (level %d)", r[3]:lower(), r[1]), tex = I .. "Ability_Mount_RidingHorse", key = "gnRide" .. r[1], d = string.format("%s; you have %s", Money(r[2]), Money(Purse())), page = function() return SavePage(r) end }
      break
    end
  end
  local n = 0
  for _, m in ipairs(MILES) do
    if m[1] > L and n < 4 then
      n = n + 1
      rows[#rows + 1] = { t = string.format("Level %d: %s", m[1], m[2]), d = m[3], key = "gnM" .. m[1] .. m[2], still = true, dim = true }
    end
  end
  return rows
end

---------------------------------------------------------------------------
-- From Retail, systems, class and race, stats
---------------------------------------------------------------------------
local function TextPage(title, text, icon)
  return { title = title, icon = icon, rows = { { t = text, still = true } } }
end
local function Hit(...)
  local f = (Gd.find or ""):lower()
  if f == "" then return true end
  for _, v in ipairs({ ... }) do if type(v) == "string" and v:lower():find(f, 1, true) then return true end end
  return false
end

local function Retail()
  local rows = { { h = "Coming from Retail" } }
  for k, r in ipairs(List(Src().retail)) do
    if Hit(r[1], r[2]) then
      rows[#rows + 1] = { t = r[1], d = r[2]:match("^[^%.]+") .. ".", key = "ret" .. k, page = function() return TextPage(r[1], r[2], I .. "INV_Misc_Book_11") end }
    end
  end
  if #rows == 1 then rows[2] = { t = "Nothing matches", still = true } end
  return rows
end

-- Legacy Points, if the game keeps them as a currency addons can read: looked for by name once a session, in the background
-- (the guides don't agree on the numbers, so the game's own are the only ones shown)
local legacy
function Gd.FindLegacy(again)
  if (legacy ~= nil and not again) or not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return end
  legacy = false
  E.Job("legacy points", function()
    for id = 1, 5000 do
      local ok, c = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
      if ok and type(c) == "table" and type(c.name) == "string" and not (issecretvalue and issecretvalue(c.name)) and c.name:lower():find("legacy", 1, true) then return id end
      if id % 50 == 0 then E.Yield() end
    end
    return nil
  end, function(id)
    legacy = id or false
    if id and NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
  end)
end
function Gd.Legacy()
  local ok, c = false, nil
  if legacy then ok, c = pcall(C_CurrencyInfo.GetCurrencyInfo, legacy) end
  if ok and type(c) == "table" and type(c.quantity) == "number" then return c.name, c.quantity, type(c.maxQuantity) == "number" and c.maxQuantity > 0 and c.maxQuantity or nil end
end

local function Systems()
  local rows = {}
  Gd.FindLegacy()
  local ln, lq, lm = Gd.Legacy()
  for k, sy in ipairs(List(Src().systems)) do
    local hit = Hit(sy[1])
    for _, x in ipairs(sy[3]) do hit = hit or Hit(x[1], x[2]) end
    if hit then
      rows[#rows + 1] = { t = sy[1], d = sy[3][1][2]:match("^[^%.]+") .. ".", tex = I .. sy[2], key = "sys" .. k, page = function()
        local r = {}
        if sy[1]:find("Legacy", 1, true) and ln then
          r[1] = { t = string.format("You have %d%s %s", lq, lm and (" of " .. lm) or "", ln), d = "From the game itself.", still = true, ring = "good" }
        end
        for _, x in ipairs(sy[3]) do
          r[#r + 1] = { h = x[1] }
          r[#r + 1] = { t = x[2], still = true }
        end
        return { title = sy[1], icon = I .. sy[2], rows = r, sub = "From Forever guides, 24 November 2026" }
      end }
    end
  end
  if #rows == 0 then rows[1] = { t = "Nothing matches", still = true } end
  return rows
end

local NAME = { Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER", Rogue = "ROGUE", Priest = "PRIEST", Shaman = "SHAMAN", Mage = "MAGE", Warlock = "WARLOCK", Druid = "DRUID" }
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local function Who()
  local rows = { { h = "Classes: who can be one" } }
  local data = type(_G.SunstoneClass) == "table" and _G.SunstoneClass or {}
  for _, c in ipairs(CLASSES) do
    local a, h = {}, {}
    for _, r in ipairs(List(Src().races)) do
      for one in r[3]:gmatch("[^,]+") do
        one = one:gsub("^%s+", "")
        if one:gsub("%*", "") == c then table.insert(r[2] == "Alliance" and a or h, r[1] .. (one:find("%*") and " (new)" or "")) end
      end
    end
    if Hit(c, table.concat(a, " "), table.concat(h, " ")) then
      local about = List(data[NAME[c]]).about
      rows[#rows + 1] = { t = c, tex = I .. "ClassIcon_" .. c, key = "who" .. c, d = about and about[1] or nil, page = function()
        local r = {}
        for _, t in ipairs(about or {}) do r[#r + 1] = { t = t, still = true } end
        r[#r + 1] = { h = "Alliance" }
        r[#r + 1] = { t = #a > 0 and table.concat(a, ", ") or "None", still = true }
        r[#r + 1] = { h = "Horde" }
        r[#r + 1] = { t = #h > 0 and table.concat(h, ", ") or "None", still = true }
        r[#r + 1] = { t = "More about it", d = "The Class tab: weapons, level by level, rotations, macros.", still = true, actLabel = "Open", act = Go("class") }
        return { title = c, icon = I .. "ClassIcon_" .. c, rows = r, sub = "Who can be one, and what it's like" }
      end }
    end
  end
  for _, side in ipairs({ "Alliance", "Horde" }) do
    rows[#rows + 1] = { h = side .. " races" }
    for _, r in ipairs(List(Src().races)) do
      if r[2] == side and Hit(r[1], r[3], r[4]) then
        rows[#rows + 1] = { t = r[1], d = r[3]:gsub("%*", " (new)"), key = "race" .. r[1], page = function()
          return { title = r[1], rows = { { h = "Can be" }, { t = (r[3]:gsub("%*", " (new in Forever)")), still = true }, { h = "Racial abilities" }, { t = r[4], d = "Their tooltips are in your spellbook.", still = true },
                                          { t = "From Warcraft Tavern's Forever lists", still = true, dim = true } }, sub = side }
        end }
      end
    end
  end
  return rows
end

local function Stats()
  local rows, class = {}, Class()
  local U = NS.Upgrades
  local ok, w = false, nil
  if U and U.Weights then ok, w = pcall(U.Weights, class, Level()) end
  w = ok and type(w) == "table" and w or {}
  local list, top, best = {}, 0, nil
  local PERCENT = { hit = true, crit = true, dodge = true, parry = true, block = true } -- counted per percent, not per point
  for _, st in ipairs(List(Src().stats)) do
    local v = w[st[1]]
    -- weapon damage and armor are counted on other scales: shown, not compared
    local apart = (st[1]:find("^dps") or st[1] == "armor") and "scale" or PERCENT[st[1]] and "percent" or nil
    if type(v) == "number" and v > top and not apart then top, best = v, st[2] end
    list[#list + 1] = { st, type(v) == "number" and v or 0, apart }
  end
  table.sort(list, function(a, b) if (a[2] > 0) ~= (b[2] > 0) then return a[2] > 0 end if (a[3] and true or false) ~= (b[3] and true or false) then return not a[3] end return a[2] > b[2] end)
  local name = UnitClass("player")
  rows[1] = { h = "For you: " .. (name or "your class") .. ", level " .. Level() }
  local useless = false
  for _, e in ipairs(list) do
    local st, v = e[1], e[2]
    if Hit(st[2], st[3]) then
      if v <= 0 and not useless then
        useless = true
        rows[#rows + 1] = { h = "Not worth chasing for your class" }
      end
      local pct = v > 0 and not e[3] and top > 0 and math.floor(v / top * 100 + 0.5)
      rows[#rows + 1] = { t = st[2], d = st[3] .. (pct and (pct >= 100 and "\nYour best stat, point for point." or string.format("\n%d%% as good as %s, point for point.", math.max(1, pct), best))
                            or v > 0 and e[3] == "percent" and top > 0 and string.format("\n1%% is worth about %d points of %s.", math.floor(v / top + 0.5), best)
                            or v > 0 and "\nCounts for you (on its own scale)." or ""),
                          key = "st" .. st[1], still = true, dim = v <= 0 or nil, ring = pct and pct >= 60 and "good" or nil }
    end
  end
  rows[#rows + 1] = { t = "How this is worked out", d = "From the same stat weights the Gear tab uses for your talent plan's goal (SimGear's for Forever).", still = true, dim = true }
  return rows
end

local function Settings()
  local rows, last = {}, nil
  for _, s in ipairs(NS.settings) do
    if s.group ~= last then rows[#rows + 1] = { h = s.group } last = s.group end
    local ok, v = pcall(s.get)
    if ok then
      local label = type(v) == "string" and v or (v and "On" or "Off")
      rows[#rows + 1] = { t = s.name, d = s.about, still = true, key = "set" .. s.group .. s.name, dim = v == false or nil, actLabel = label,
                          act = function() NS.Safe("setting", s.set, not s.get()); if NS.Window then NS.Window.Refresh() end end }
    end
  end
  return rows
end

function Gd.Rows()
  local m = Gd.Mode()[1]
  if m == "set" then return Settings() end
  if m == "share" and NS.Share then return NS.Share.Rows() end
  if m == "retail" then return Retail() elseif m == "systems" then return Systems() elseif m == "who" then return Who() elseif m == "stats" then return Stats() end
  return Gd.Now()
end

function Gd:Init()
  NS.On("TRAINER_SHOW", function() C_Timer.After(0.5, function() NS.Safe("trainer prices", Gd.SeeTrainer) end) end)
end
