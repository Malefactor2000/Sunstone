-- Sunstone: the Class tab, for any class (also ones you've never played): what it's like, the weapons and armor it can use and
-- where to learn them, what it gains at each level, its rotations by role, and macros to copy.
-- ClassData.lua (written for Sunstone, every spell checked against the game's own lists), Weapons.lua (the game's own class
-- table), Data.lua (class spells, weapon masters). Sunstone only shows macros to copy: it never makes or presses one.

local _, NS = ...
local Cl = NS.Module("Class")
NS.Class = Cl
local E = NS.Engine

local ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
               MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local DUAL = { ROGUE = 10, WARRIOR = 20, HUNTER = 20 } -- dual wield (the game's class table)
local ROLE = { solo = "Solo", dps = "Damage", tank = "Tank", heal = "Healer" }
local RELIC = { PALADIN = "Librams", DRUID = "Idols", SHAMAN = "Totems (the item kind)" }
local function Icon(token) return "Interface\\Icons\\ClassIcon_" .. NAME[token] end

Cl.MODES = {
  { "over", "Overview", "What the class is like" },
  { "gear", "Weapons & armor", "What it can use, and where to learn it" },
  { "levels", "Level by level", "What it gains at each level" },
  { "rot", "Rotations", "What to press, by role" },
  { "macros", "Macros", "Ready to copy" },
  { "pets", "Pets", "Hunter beasts, warlock demons" },
}
function Cl.Mode()
  local m = NS.cdb and NS.cdb.classMode
  for _, x in ipairs(Cl.MODES) do if x[1] == m then return x end end
  return Cl.MODES[1]
end

local function Data(token) return type(_G.SunstoneClass) == "table" and _G.SunstoneClass[token] or nil end
local function Mine() return select(2, UnitClass("player")) end
local function Tex(id)
  if not id then return nil end
  for _, fn in ipairs({ C_Spell and C_Spell.GetSpellTexture or false, GetSpellTexture or false }) do
    if fn then
      local ok, t = pcall(fn, id)
      if ok and t then return t end
    end
  end
end

---------------------------------------------------------------------------
-- A class's spells
---------------------------------------------------------------------------
local cache = {}
-- name -> { level, id, talent }; the first rank
local function Spells(token)
  if cache[token] then return cache[token] end
  local out, minRank = {}, {}
  for _, s in ipairs(E.Data().spells[token] or {}) do
    local e = out[s[3]]
    if not e or s[1] < e.level then out[s[3]] = { level = s[1], id = s[2], talent = s[6] == 1 or nil, rank = s[4] } end
    if not minRank[s[3]] or s[4] < minRank[s[3]] then minRank[s[3]] = s[4] end
  end
  -- a spell whose first rank no trainer sells is one you begin with
  for name, r in pairs(minRank) do if r >= 2 and not out[name].talent then out[name].level, out[name].begin = 1, true end end
  local d = Data(token)
  for _, name in ipairs(d and d.start or {}) do
    out[name] = out[name] or { level = 1 }
    out[name].level, out[name].begin = 1, true
  end
  cache[token] = out
  return out
end

-- the level a spell comes at, for a rotation: from the talent plan when it's a talent, else from the trainer
local function When(token, name, planId)
  for _, p in ipairs(NS.PLANS and NS.PLANS[token] or {}) do
    if p.id == planId then
      for lvl = 10, 60 do
        local s = p.steps[lvl]
        if s and s[1] == name then return lvl, true end
      end
    end
  end
  local s = Spells(token)[name]
  if s then return (not s.talent) and s.level or nil, s.talent end
  return nil, true -- a talent this plan doesn't take
end

---------------------------------------------------------------------------
-- Weapons and armor
---------------------------------------------------------------------------
local RACES = { [0] = "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
local function RaceNames(mask)
  local out = {}
  for b = 0, 7 do if mask % (2 * 2 ^ b) >= 2 ^ b then out[#out + 1] = RACES[b] end end
  if mask >= 4294967296 then out[#out + 1] = "Skyborne" end
  return out
end

-- { [kind][sub] = { start = true / mask, learn = level or nil } } for a class
local function Uses(token)
  local out = { [2] = {}, [4] = {} }
  for _, r in ipairs(type(_G.SunstoneWeapons) == "table" and _G.SunstoneWeapons or {}) do
    if bit.band(r[3], BIT[token]) ~= 0 and out[r[1]] then
      local e = out[r[1]][r[2]] or {}
      out[r[1]][r[2]] = e
      if r[4] == 1 then
        if r[6] == -1 then e.all = true else e.mask = math.max(e.mask or 0, 0) + r[6] end
      else
        e.learn = r[5]
      end
    end
  end
  return out
end

local ARMOR = { { 1, "Cloth" }, { 2, "Leather" }, { 3, "Mail" }, { 4, "Plate" }, { 6, "Shields" } }
local WEAPONS = { 4, 5, 0, 1, 7, 8, 15, 10, 13, 6, 2, 3, 18, 16, 19 }

local function GearPage(token, rows)
  local u, mine = Uses(token), token == Mine()
  local me = UnitLevel("player")
  local name = NS.Upgrades and NS.Upgrades.WEAPON_NAME or {}
  rows[#rows + 1] = { h = "Armor" }
  for _, a in ipairs(ARMOR) do
    local e = u[4][a[1]]
    if e then
      local lvl = not (e.all or e.mask) and e.learn or 1
      rows[#rows + 1] = { t = a[2], d = lvl > 1 and ("From level " .. lvl .. (mine and me < lvl and " (not yet)" or "")) or "From the start", dim = mine and me < lvl or nil }
    end
  end
  if RELIC[token] then rows[#rows + 1] = { t = RELIC[token], d = "In the ranged slot" } end
  if DUAL[token] then rows[#rows + 1] = { t = "Dual wield", d = "From level " .. DUAL[token], dim = mine and me < DUAL[token] or nil } end
  local start, learn = {}, {}
  for _, sub in ipairs(WEAPONS) do
    local e = u[2][sub]
    if e then
      if e.all and not (mine and false) then start[#start + 1] = { sub, "From the start" }
      elseif e.mask then
        local who = table.concat(RaceNames(e.mask), ", ")
        if e.learn then learn[#learn + 1] = { sub, e.learn, who .. " start with it" } else start[#start + 1] = { sub, "From the start" } end
      else
        learn[#learn + 1] = { sub, e.learn or 0 }
      end
    end
  end
  rows[#rows + 1] = { h = "Weapons from the start" }
  for _, s in ipairs(start) do rows[#rows + 1] = { t = name[s[1]] or "?", d = s[2] } end
  if #start == 0 then rows[#rows + 1] = { t = "Depends on the race: see below" } end
  if #learn > 0 then rows[#rows + 1] = { h = "Weapons it can learn from a weapon master (about 10 silver each in Classic)" } end
  for _, l in ipairs(learn) do
    local m = E.WeaponMaster(l[1])
    local state = mine and NS.Upgrades.Can(2, l[1])
    local bits = {}
    if state == "known" then bits[1] = "You know it." end
    if l[2] and l[2] > 1 then bits[#bits + 1] = "From level " .. l[2] .. "." end
    if l[3] then bits[#bits + 1] = l[3] .. "." end
    if m then bits[#bits + 1] = m.name .. ", " .. m.city .. "." .. (state ~= "known" and (" " .. E.PlaceText(m.p)) or "") end
    rows[#rows + 1] = E.At({ t = name[l[1]] or "?", d = table.concat(bits, " "), dim = state == "known" or nil }, state ~= "known" and m and m.p or nil)
  end
  -- what it can't
  local no = {}
  for _, sub in ipairs(WEAPONS) do if not u[2][sub] then no[#no + 1] = (name[sub] or "?"):lower() end end
  if #no > 0 then rows[#rows + 1] = { t = "Never", d = table.concat(no, ", "):gsub("^%l", string.upper) .. ".", dim = true } end
end

---------------------------------------------------------------------------
-- Level by level
---------------------------------------------------------------------------
local function LevelLines(token, lvl)
  local out = {}
  local u = Uses(token)
  for _, a in ipairs(ARMOR) do
    local e = u[4][a[1]]
    if e and not (e.all or e.mask) and e.learn == lvl then out[#out + 1] = { t = a[2] .. " armor", d = "From your class trainer", gear = true } end
  end
  for _, sub in ipairs(WEAPONS) do
    local e = u[2][sub]
    if e and e.learn == lvl and lvl > 1 then out[#out + 1] = { t = NS.Upgrades.WEAPON_NAME[sub], d = "From a weapon master", gear = true } end
  end
  if DUAL[token] == lvl then out[#out + 1] = { t = "Dual wield", d = "From your class trainer", gear = true } end
  if lvl == 10 then out[#out + 1] = { t = "Talents", d = "One point a level from now on (Talents tab)", gear = true } end
  if lvl == 40 then out[#out + 1] = { t = "Riding", d = "Your first mount", gear = true } end
  for _, s in ipairs(E.Data().spells[token] or {}) do
    if s[1] == lvl then
      out[#out + 1] = { t = s[3] .. (s[4] > 0 and (" (rank " .. s[4] .. ")") or ""), spell = s[2], tex = Tex(s[2]), n = s[3], r = s[4],
                        d = (s[7] ~= "" and ("From a quest: " .. s[7])) or (s[6] == 1 and "If you took the talent") or (s[5] ~= 0 and "Some races only") or "From your class trainer" }
    end
  end
  return out
end

local function LevelPage(token, lvl)
  local rows = {}
  for _, l in ipairs(LevelLines(token, lvl)) do rows[#rows + 1] = l end
  return { title = NAME[token] .. ", level " .. lvl, icon = Icon(token), rows = rows, sub = "Hover a spell for the game's tooltip." }
end

local function LevelsPage(token, rows)
  local mine, me = token == Mine(), UnitLevel("player")
  local begin = {}
  for name, s in pairs(Spells(token)) do if s.begin then begin[#begin + 1] = name end end
  table.sort(begin)
  if #begin > 0 then rows[#rows + 1] = { t = "You start with", d = table.concat(begin, ", ") .. "." } end
  local nextUp
  for lvl = 1, 60 do
    local list = LevelLines(token, lvl)
    if #list > 0 then
      local short, gear = {}, {}
      for _, l in ipairs(list) do
        if l.gear then gear[#gear + 1] = l.t else short[#short + 1] = l.n .. ((l.r or 0) > 1 and (" " .. l.r) or "") end
      end
      local all = {}
      for _, g in ipairs(gear) do all[#all + 1] = g end
      for _, s in ipairs(short) do all[#all + 1] = s end
      local isNext = mine and lvl > me and not nextUp
      if isNext then nextUp = lvl end
      rows[#rows + 1] = { t = "Level " .. lvl .. (isNext and "  (next for you)" or ""), d = table.concat(all, ", "), hot = isNext or nil, dim = mine and lvl <= me or nil,
                          page = function() return LevelPage(token, lvl) end }
    end
  end
end

---------------------------------------------------------------------------
-- Rotations
---------------------------------------------------------------------------
-- Do you have this spell (any rank)? The game only answers to the names of spells you know; nil = it doesn't say (it knows
-- none of the spells your class starts with, so its answers can't be trusted: then it goes by level)
local function Knows(name)
  local get = C_Spell and C_Spell.GetSpellInfo or GetSpellInfo
  if not get then return nil end
  local ok, v = pcall(get, name)
  if not ok then return nil end
  return v ~= nil
end
local function Have(name)
  local d = Data(Mine())
  for _, first in ipairs(d and d.start or {}) do
    if Knows(first) then return Knows(name) end
  end
end

-- A rotation. On your own class: what you can use now, in order and numbered, then what you don't have yet, gray and unnumbered.
local function Steps(rows, token, list, plan)
  local mine, me = token == Mine(), UnitLevel("player")
  local gray = "|cff7a756c"
  local n, later, notes = 0, {}, {}
  for _, s in ipairs(list) do
    if s[1] == "" then
      notes[#notes + 1] = { t = s[2], dim = true }
    else
      local names, levels, id, can, train = {}, {}, nil, {}, false
      for one in s[1]:gmatch("[^/]+") do
        names[#names + 1] = one
        local lvl, talent = When(token, one, plan)
        local info = Spells(token)[one]
        id = id or (info and info.id)
        local byLevel = (not lvl and not talent) or (lvl and lvl <= me) or false
        local have = mine and Have(one)
        if have == nil then have = byLevel end
        if have then can[#can + 1] = one
        elseif byLevel and not talent and lvl then train = true end
        local text = lvl and lvl > 1 and string.format("level %d%s", lvl, talent and " talent" or "")
        if text then if levels[#levels] ~= text then levels[#levels + 1] = text end
        elseif talent and not lvl then levels[#levels + 1] = "a talent this plan skips" end
      end
      if mine and #can == 0 then
        local when = train and "your trainer has it now" or #levels > 0 and table.concat(levels, ", ") or "not yet"
        later[#later + 1] = { t = gray .. table.concat(names, " or ") .. "|r", d = gray .. (train and "Learn it: " or "") .. when .. "|r", tex = Tex(id) or Icon(token), spell = id, dim = true, ring = train and "warn" or nil }
      else
        n = n + 1
        local d = s[2]
        if not mine and #levels > 0 then d = d .. "  |cff" .. NS.HEX.dim .. "(" .. table.concat(levels, ", ") .. ")|r" end
        rows[#rows + 1] = { t = string.format("%d. %s", n, table.concat(mine and can or names, " or ")), d = d, tex = Tex(id) or Icon(token), spell = id }
      end
    end
  end
  if mine and n == 0 and #later > 0 then rows[#rows + 1] = { t = "Nothing here yet at your level", dim = true, still = true } end
  for _, r in ipairs(notes) do rows[#rows + 1] = r end
  if #later > 0 then
    rows[#rows + 1] = { t = gray .. "Not yet: these join as you gain them|r", dim = true, still = true }
    for _, r in ipairs(later) do rows[#rows + 1] = r end
  end
end
local function PlanName(token, id)
  for _, p in ipairs(NS.PLANS and NS.PLANS[token] or {}) do if p.id == id then return p.name end end
end

local function RotationPage(token, r)
  local rows = {}
  local plan = PlanName(token, r.plan)
  if plan then rows[1] = { t = "Goes with the talent plan: " .. plan, d = token == Mine() and "Pick its goal on the Talents tab." or nil, dim = true } end
  rows[#rows + 1] = { h = r.l1 }
  Steps(rows, token, r.single, r.plan)
  rows[#rows + 1] = { h = r.l2 }
  Steps(rows, token, r.multi, r.plan)
  rows[#rows + 1] = { t = "From the top, press the first one that's ready and useful", dim = true,
                      d = token == Mine() and "Numbered ones are what you have now. Gray ones below them aren't yours yet." or "The level each comes at is in brackets." }
  return { title = NAME[token] .. ": " .. r.name, icon = Icon(token), rows = rows, sub = ROLE[r.role] or "" }
end

local function RotationsPage(token, rows)
  local d = Data(token)
  local last
  local old = token == Mine() and NS.Tips and NS.Tips.OldRanks() or {}
  if #old > 0 then
    rows[#rows + 1] = { h = "Old ranks on your bars" }
    for _, o in ipairs(old) do
      rows[#rows + 1] = { t = string.format("%s: rank %d on %s, you know rank %d", o.name, o.rank, NS.Tips.SlotName(o.slot), o.best), tex = Tex(o.id), spell = o.id, still = true,
                          d = "Drag the new one from your spellbook onto it, unless you keep the old one to save mana." }
    end
  end
  for _, r in ipairs(d and d.rot or {}) do
    if r.role ~= last then rows[#rows + 1] = { h = ROLE[r.role] or r.role } last = r.role end
    local first = {}
    for i = 1, math.min(4, #r.single) do if r.single[i][1] ~= "" then first[#first + 1] = (r.single[i][1]:gsub("/.*", "")) end end
    rows[#rows + 1] = { t = r.name, d = table.concat(first, ", ") .. "...\n" .. r.l1 .. ", then " .. r.l2:lower(), tex = Icon(token), page = function() return RotationPage(token, r) end }
  end
end

---------------------------------------------------------------------------
-- Macros
---------------------------------------------------------------------------
local box
function Cl.Copy(title, text, help)
  if not box then
    box = NS.Panel("Copy", 420, 210, "Copy")
    box:SetFrameStrata("DIALOG")
    if box.text then box.text:Hide() end
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetPoint("TOPLEFT", 16, -40)
    eb:SetPoint("BOTTOMRIGHT", -16, 40)
    eb:SetTextInsets(8, 8, 8, 8)
    if eb.SetTextColor then eb:SetTextColor(unpack(NS.C.text)) end
    NS.Rounded(eb, NS.C.surface, "round.png", 8)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); box:Hide() end)
    box.eb = eb
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 16)
    hint:SetTextColor(unpack(NS.C.dim))
    box.hint = hint
  end
  box.hint:SetText(help or "Ctrl+C to copy. Then /macro, New, and paste with Ctrl+V.")
  if NS.Window and NS.Window.Scale then box:SetScale(NS.Window.Scale()) end
  if box.title then box.title:SetText(title) end
  box.eb:SetText(text)
  box:Show()
  box.eb:SetFocus()
  if box.eb.HighlightText then box.eb:HighlightText() end
end

-- the spells a macro's text casts
local function MacroSpells(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    local body = line:match("^/cast%s+(.+)") or line:match("^/castsequence%s+(.+)")
    if body then
      body = body:gsub("%[[^%]]*%]", ""):gsub("reset=%S+", "")
      for part in body:gmatch("[^;,]+") do
        part = part:gsub("^%s*!?%s*", ""):gsub("%s+$", "")
        if part ~= "" then out[#out + 1] = part end
      end
    end
  end
  return out
end

local function MacroRows(rows, list, token)
  local mine, later = token == Mine(), {}
  for _, m in ipairs(list or {}) do
    local name, d, text = m[1], m[2], m[3]
    local ok, need = not mine, {}
    if mine then
      local all = MacroSpells(text)
      if #all == 0 then ok = true end
      for _, sp in ipairs(all) do
        local have = Have(sp)
        if have == nil then local lvl = When(token, sp); have = not lvl or lvl <= UnitLevel("player") end
        if have then ok = true else need[#need + 1] = sp end
      end
    end
    local row = { t = name, d = (d ~= "" and (d .. "\n") or "") .. "|cff" .. NS.HEX.accent .. text .. "|r", actLabel = "Copy", act = function() Cl.Copy(name, text) end, still = true }
    if ok then rows[#rows + 1] = row else
      row.dim, row.t, row.d = true, "|cff7a756c" .. name .. "|r", "|cff7a756cNeeds " .. table.concat(need, ", ") .. "|r"
      later[#later + 1] = row
    end
  end
  return later
end

-- Pulls and prep: one key, pressed several times, goes through the spells in order. On your own class the text is written from
-- the spells you have (a sequence stops dead at one you don't know), so copy it again when you learn more.
local function Opener(o, token)
  local mine, me = token == Mine(), UnitLevel("player")
  local adds = {}
  local function Can(name)
    if not mine then return true end
    local have = Have(name)
    if have == nil then
      local lvl, talent = When(token, name)
      have = lvl ~= nil and lvl <= me or (lvl == nil and not talent)
    end
    return have
  end
  local function Pick(text) -- "A|B": the first you have
    for one in text:gmatch("[^|]+") do if Can(one) then return one end end
  end
  local function Missing(text)
    local first = text:match("^[^|]+")
    local lvl = When(token, first)
    local t = first .. (lvl and (" at " .. lvl) or "")
    for _, x in ipairs(adds) do if x == t then return end end
    adds[#adds + 1] = t
  end
  local lines, cast = { "#showtooltip" }, 0
  local function Lines(list)
    for _, l in ipairs(list) do
      if l[1] == "" then lines[#lines + 1] = l[2]
      else
        local one = Pick(l[1])
        if one then lines[#lines + 1] = (l[2]:gsub("{}", function() return one end)); cast = cast + 1 else Missing(l[1]) end
      end
    end
  end
  Lines(o[6])
  local seq = {}
  for k, text in ipairs(o[5]) do
    local one = Pick(text)
    if one then
      if seq[#seq] ~= one or text == o[5][k - 1] then seq[#seq + 1] = one end
      if one ~= text:match("^[^|]+") then Missing(text) end
    else Missing(text) end
  end
  if #seq == 1 then lines[#lines + 1] = "/cast " .. o[8] .. seq[1]
  elseif #seq > 1 then lines[#lines + 1] = "/castsequence " .. o[8] .. (o[4] ~= "" and ("reset=" .. o[4] .. " ") or "") .. table.concat(seq, ", ") end
  Lines(o[7])
  return (#seq + cast > 0) and table.concat(lines, "\n") or nil, adds
end
Cl.Opener = Opener

local function MacrosPage(token, rows)
  local d = Data(token)
  rows[#rows + 1] = { t = "How to use one", d = "Copy, type /macro, press New, pick the red question mark icon (it then shows the spell), paste, and drag it to your bar. One macro holds 255 letters. If the icon stays a question mark, a name doesn't match a spell you know.", dim = true }
  local later = {}
  for _, kind in ipairs({ "pull", "prep" }) do
    local first = true
    for _, o in ipairs(d and d.openers or {}) do
      if o[1] == kind then
        local text, adds = Opener(o, token)
        local more = token == Mine() and #adds > 0 and ("\n|cff7a756cLater it adds " .. table.concat(adds, ", ") .. ": copy it again then.|r") or ""
        if text then
          if first then
            rows[#rows + 1] = { h = kind == "pull" and "Pulls: press the same key several times" or "Before a fight" }
            first = false
          end
          local name = o[2]
          rows[#rows + 1] = { t = name, d = o[3] .. "\n|cff" .. NS.HEX.accent .. text .. "|r" .. more, actLabel = "Copy", act = function() Cl.Copy(name, text) end, still = true }
        else
          later[#later + 1] = { t = "|cff7a756c" .. o[2] .. "|r", d = "|cff7a756cNeeds " .. table.concat(adds, ", ") .. "|r", dim = true, still = true }
        end
      end
    end
  end
  rows[#rows + 1] = { h = "In the fight" }
  for _, r in ipairs(MacroRows(rows, d and d.macros, token)) do later[#later + 1] = r end
  rows[#rows + 1] = { h = "For any class" }
  MacroRows(rows, type(_G.SunstoneClass) == "table" and _G.SunstoneClass.general)
  if #later > 0 then
    rows[#rows + 1] = { h = "Not yet" }
    for _, r in ipairs(later) do rows[#rows + 1] = r end
  end
  rows[#rows + 1] = { t = "What a macro can't do", d = "One press casts one spell: it can't watch cooldowns, health or buffs for you. If a sequence stops on a spell that won't go off (no target, out of range), it waits there until it does or resets.", dim = true, still = true }
end
local function OverPage(token, rows)
  local d = Data(token)
  for _, a in ipairs(d and d.about or {}) do rows[#rows + 1] = { t = a } end
  rows[#rows + 1] = { h = "Roles" }
  for _, r in ipairs(d and d.rot or {}) do
    rows[#rows + 1] = { t = r.name, d = ROLE[r.role], tex = Icon(token), page = function() return RotationPage(token, r) end }
  end
  if token == Mine() and NS.Travel and NS.Travel.Search then
    local ok, found = pcall(NS.Travel.Search, NAME[token]:lower() .. " trainer")
    local n = 0
    for _, r in ipairs(ok and type(found) == "table" and found or {}) do
      if r.m and n < 2 then
        if n == 0 then rows[#rows + 1] = { h = "Your class trainers" } end
        n = n + 1
        rows[#rows + 1] = { t = r.t, d = r.d, m = r.m, x = r.x, y = r.y }
      end
    end
  end
end

function Cl.Page(token)
  local rows, mode = {}, Cl.Mode()
  if mode[1] == "gear" then GearPage(token, rows) elseif mode[1] == "levels" then LevelsPage(token, rows)
  elseif mode[1] == "rot" then RotationsPage(token, rows) elseif mode[1] == "macros" then MacrosPage(token, rows)
  elseif mode[1] == "pets" and NS.Pets then NS.Pets.Page(token, rows)
  else OverPage(token, rows) end
  return { title = NAME[token], icon = Icon(token), rows = rows, sub = mode[3] }
end

function Cl.Rows()
  local mine, rows = Mine(), {}
  local function Row(token)
    local d = Data(token)
    local roles, seen = {}, {}
    for _, r in ipairs(d and d.rot or {}) do
      local n = r.role == "solo" and nil or ROLE[r.role]
      if n and not seen[n] then seen[n] = true; roles[#roles + 1] = n end
    end
    return { t = NAME[token] .. (token == mine and "  (you)" or ""), d = table.concat(roles, ", "), tex = Icon(token), key = "class" .. token,
             page = function() return Cl.Page(token) end }
  end
  if NAME[mine or ""] then rows[1] = Row(mine) end
  rows[#rows + 1] = { h = "Every class" }
  for _, token in ipairs(ORDER) do if token ~= mine then rows[#rows + 1] = Row(token) end end
  return rows
end
