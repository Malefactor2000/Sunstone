-- Sunstone: gear upgrades.
-- Collects the gear a character of your class and level can get (quest rewards, vendors, crafting, dungeons,
-- reputation, Library Books: Data.lua and Questie), reads each item's real stats from the game, scores it with the
-- stat weights of your talent goal (Data.lua) and compares it with what you wear. Gear.lua works out where each
-- upgrade comes from and how quick it is. Works from a character's first login, without the desktop helper.

local _, NS = ...
local U = NS.Module("Upgrades")
NS.Upgrades = U

-- Armor / weapon subclasses each class can use (Classic rules; mail/plate at 40 shown as allowed).
local ARMOR = { MISC = 0, CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4, SHIELD = 6, LIBRAM = 7, IDOL = 8, TOTEM = 9 }
local PROF = {
  WARLOCK = { armor = { 0, 1 }, weapon = { 7, 10, 15, 19 } },
  MAGE    = { armor = { 0, 1 }, weapon = { 7, 10, 15, 19 } },
  PRIEST  = { armor = { 0, 1 }, weapon = { 4, 10, 15, 19 } },
  ROGUE   = { armor = { 0, 1, 2 }, weapon = { 2, 3, 4, 7, 13, 15, 16, 18 } },
  DRUID   = { armor = { 0, 1, 2, 8 }, weapon = { 4, 5, 10, 13, 15 } },
  HUNTER  = { armor = { 0, 1, 2, 3 }, weapon = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 } },
  SHAMAN  = { armor = { 0, 1, 2, 3, 6, 9 }, weapon = { 0, 1, 4, 5, 10, 13, 15 } },
  PALADIN = { armor = { 0, 1, 2, 3, 4, 6, 7 }, weapon = { 0, 1, 4, 5, 6, 7, 8 } },
  WARRIOR = { armor = { 0, 1, 2, 3, 4, 6 }, weapon = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 } },
}

-- Stat names from GetItemStats -> short keys
local STAT = {
  ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
  ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi",
  ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal", ITEM_MOD_SPELL_HEALING_DONE = "heal",
  ITEM_MOD_SHADOW_DAMAGE_SHORT = "shadow", ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "shadow",
  ITEM_MOD_FIRE_DAMAGE_SHORT = "fire", ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "fire",
  ITEM_MOD_FROST_DAMAGE_SHORT = "frost", ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "frost",
  ITEM_MOD_ARCANE_DAMAGE_SHORT = "arcane", ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "arcane",
  ITEM_MOD_NATURE_DAMAGE_SHORT = "nature", ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "nature",
  ITEM_MOD_HOLY_DAMAGE_SHORT = "holy", ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "holy",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
  ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_SPELL_CRIT_RATING_SHORT = "scrit",
  ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "shit",
  ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_SPELL_HASTE_RATING_SHORT = "shaste",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap", ITEM_MOD_ATTACK_POWER_FERAL_SHORT = "fap",
  ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "fap",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", RESISTANCE0_NAME = "armor", ITEM_MOD_ARMOR_SHORT = "armor",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge", ITEM_MOD_PARRY_RATING_SHORT = "parry",
  ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_BLOCK_VALUE_SHORT = "bv", ITEM_MOD_HEALTH_SHORT = "hp", ITEM_MOD_MANA_SHORT = "mana",
  ITEM_MOD_WEAPON_SKILL_RATING_SHORT = "wskill",
}
local RATING = { crit = 14, hit = 10, scrit = 14, shit = 10 } -- rating points per 1 % (Data.lua has the full list)
local SAME = { scrit = "crit", shit = "hit", shaste = "haste" } -- a spec's curve may only list the plain one

-- Which spec's stat weights go with the talent plan you follow (Data.lua: one curve per spec, by level)
local PLAN_SPEC = {
  ["warrior-arms"] = "Arms", ["warrior-fury"] = "Fury", ["warrior-protection"] = "Protection",
  ["paladin-retribution"] = "Retribution", ["paladin-retribution-raid"] = "Retribution", ["paladin-protection"] = "Protection",
  ["paladin-holy"] = "Holy", ["hunter-beastmastery"] = "Beast Mastery", ["hunter-survival-raid"] = "Survival",
  ["hunter-marksmanship-raid"] = "Marksmanship", ["rogue-combat"] = "Combat", ["rogue-combat-raid"] = "Combat",
  ["priest-shadow"] = "Shadow", ["priest-shadow-raid"] = "Shadow", ["priest-holy"] = "Holy", ["shaman-enhancement"] = "Enhancement",
  ["shaman-enhancement-raid"] = "Enhancement", ["shaman-restoration"] = "Restoration", ["shaman-tank"] = "Enhancement",
  ["mage-frost"] = "Frost", ["mage-fire-raid"] = "Fire", ["warlock-leveling"] = "Affliction", ["warlock-solo"] = "Demonology",
  ["warlock-demonology-raid"] = "Demonology", ["druid-feral"] = "Feral (Cat)", ["druid-bear"] = "Feral (Bear)",
  ["druid-cat-raid"] = "Feral (Cat)", ["druid-restoration"] = "Restoration",
}
-- Which weapon's DPS the "dps" weight is about; other weapon kinds use dpsmelee (or nothing).
local DPS_KIND = { WARLOCK = "wand", MAGE = "wand", PRIEST = "wand", HUNTER = "ranged" }
local RANGED_SUB = { [2] = true, [3] = true, [16] = true, [18] = true }
local function WeaponKind(classID, subClassID)
  if classID ~= 2 then return nil end
  if subClassID == 19 then return "wand" end
  if RANGED_SUB[subClassID] then return "ranged" end
  return "melee"
end
local SIMPLE = {
  caster = { sta = 0.5, int = 0.7, spi = 0.4, sp = 1, mp5 = 0.5, crit = 1, hit = 1, dps = 1.5, armor = 0.01 },
  agile  = { sta = 0.5, agi = 1, str = 0.5, ap = 0.5, rap = 0.5, crit = 1, hit = 1, dps = 3, armor = 0.02 },
  strong = { sta = 0.6, str = 1, agi = 0.6, ap = 0.5, crit = 1, hit = 1, dps = 3, armor = 0.03, def = 0.5 },
}
local CLASS_SIMPLE = { MAGE = "caster", PRIEST = "caster", DRUID = "caster", SHAMAN = "strong", WARLOCK = "caster",
  ROGUE = "agile", HUNTER = "agile", WARRIOR = "strong", PALADIN = "strong" }

local weightCache = {}
-- Armor for a melee or hunter build that plays alone: 20 armor = 1 attack power (the curves' own level-30 Enhancement
-- point has about twice that; their other points have next to nothing).
local SOLO_ARMOR = 0.05
U.SOLO_ARMOR = SOLO_ARMOR
local function ForSolo(class, planId) -- the build is for leveling or playing alone (no build picked counts as leveling)
  if not planId or planId == "none" then return true end
  for _, p in ipairs(NS.ClassPlans and NS.ClassPlans(class) or {}) do
    if p.id == planId then
      for _, g in ipairs(p.goals or {}) do if g == "solo" or g == "leveling" then return true end end
      return false
    end
  end
  return true -- a plan of your own from the desktop helper
end
-- One spec's weights at a level, from a class's table in Data.lua (nil = no weights for it)
local function At(c, spec, level)
  local curve = c and type(c.curves) == "table" and (c.curves[spec] or c.curves.Leveling)
  if not curve then return nil end
  if level >= 58 then
    for _, sp in ipairs(c.specs or {}) do if sp[1] == spec then return sp[2] end end
  end
  if level <= curve[1][1] then return curve[1][2] end
  for i = 2, #curve do
    local a, b = curve[i - 1], curve[i]
    if level <= b[1] then
      local t, w = (level - a[1]) / (b[1] - a[1]), {}
      for k in pairs(a[2]) do w[k] = (a[2][k] or 0) * (1 - t) + (b[2][k] or 0) * t end
      for k in pairs(b[2]) do if w[k] == nil then w[k] = (b[2][k] or 0) * t end end
      return w
    end
  end
  return curve[#curve][2]
end
local function Weights(class, level, planId) -- planId: another character's; left out = yours
  local D = NS.Engine and NS.Engine.Data()
  local c = D and D.weights[class]
  if not planId then
    local plan = NS.ActivePlan and NS.ActivePlan()
    planId = plan and plan.id or "none"
  end
  local key = class .. level .. tostring(planId)
  if weightCache[key] then return weightCache[key], weightCache[key .. "spec"] end
  local spec = PLAN_SPEC[planId] or "Leveling"
  local out = At(c, spec, level) or SIMPLE[CLASS_SIMPLE[class] or "caster"]
  -- The damage curves leave armor out (or nearly), so cloth with a point of Intellect beat leather or mail for a
  -- melee or hunter playing alone. Playing solo, every hit you take costs time to heal or eat back: armor counts.
  if ((out.ap or 0) > 0 or (out.rap or 0) > 0) and (out.armor or 0) < SOLO_ARMOR and ForSolo(class, planId) then
    local w = {}
    for k, v in pairs(out) do w[k] = v end
    w.armor = SOLO_ARMOR
    out = w
  end
  weightCache[key], weightCache[key .. "spec"] = out, spec
  return out, spec
end
U.Weights = Weights

-- What the weights of your role count most, in words -> { up to three stat names }, whether armor counts
local NAMES = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", ap = "attack power",
                rap = "ranged attack power", sp = "spell power", heal = "healing power" }
function U.Values(class, level, planId)
  if not class then _, class = UnitClass("player") end
  local w = Weights(class, level or UnitLevel("player"), planId)
  local list = {}
  for k, n in pairs(NAMES) do
    local v = w[k]
    if k == "sp" and (w.heal or 0) > 0 then v = nil end -- healing gear: "healing power" says it
    if k == "ap" and (w.rap or 0) >= (w.ap or 0) then v = nil end -- a hunter: ranged attack power says it
    if type(v) == "number" and v > 0.05 then list[#list + 1] = { n, v } end
  end
  table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
  local out = {}
  for i = 1, math.min(3, #list) do out[i] = list[i][1] end
  return out, (w.armor or 0) >= SOLO_ARMOR
end

local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
local SLOT_NAME = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
  "Finger", "Finger", "Trinket", "Trinket", "Back", "Main Hand", "Off Hand", "Ranged" }

local function GetStats(link)
  local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not fn then return {} end
  local ok, s = pcall(fn, link)
  return ok and s or {}
end

-- an item's stats under short names (sta, int, sp, dps, armor, ...)
function U.Stats(link)
  local out = {}
  for key, v in pairs(GetStats(link)) do
    local k = STAT[key]
    if k and type(v) == "number" then out[k] = (out[k] or 0) + v end
  end
  return out
end
U.SLOTS = SLOTS

local function Score(link, weights, class, kind)
  local total = 0
  local rating = NS.Engine and NS.Engine.Data().rating or RATING
  for key, v in pairs(GetStats(link)) do
    local k = STAT[key]
    local w
    if k == "dps" then
      if kind == "melee" then w = weights.dpsmelee or (not DPS_KIND[class] and weights.dps)
      elseif kind == "offhand" then w = weights.dpsoh
      elseif kind and kind == DPS_KIND[class] then w = weights.dps
      elseif kind == "ranged" then w = weights.dpsranged end
    else
      w = k and (weights[k] or weights[SAME[k] or ""])
    end
    if w and type(v) == "number" then
      local per = rating[k] or RATING[k]
      total = total + w * (per and per > 0 and v / per or v)
    end
  end
  return total
end

-- what a plain list of stats is worth (set bonuses, enchants): keys as in GetItemStats, PCT_<key> = percent
function U.StatsScore(stats, weights)
  local total = 0
  local rating = NS.Engine and NS.Engine.Data().rating or RATING
  for key, v in pairs(type(stats) == "table" and stats or {}) do
    local pct = key:match("^PCT_(.+)$")
    local k = STAT[pct or key]
    local w = k and k ~= "dps" and (weights[k] or weights[SAME[k] or ""])
    if w and type(v) == "number" then
      local per = rating[k] or RATING[k]
      total = total + w * (not pct and per and per > 0 and v / per or v)
    end
  end
  return total
end

-- Can you use it? "known" (now), "train" (a weapon master teaches it) and the level it takes, or nil (your class never).
-- Weapons.lua has it per class and race from the game's own files; what you've already learned is asked of the game.
local WEAPON_SPELL = { [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200, [7] = 201, [8] = 202,
                       [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567, [18] = 5011, [19] = 5009 }
U.WEAPON_NAME = { [0] = "One-Handed Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns", [4] = "One-Handed Maces", [5] = "Two-Handed Maces",
                  [6] = "Polearms", [7] = "One-Handed Swords", [8] = "Two-Handed Swords", [10] = "Staves", [13] = "Fist Weapons", [15] = "Daggers",
                  [16] = "Thrown", [18] = "Crossbows", [19] = "Wands" }
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local function Learned(sub)
  local spell = WEAPON_SPELL[sub]
  for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false }) do
    if fn and spell then
      local ok, v = pcall(fn, spell)
      if ok and v == true then return true end
    end
  end
  return false
end
function U.Can(classID, sub)
  local _, class = UnitClass("player")
  local tbl, bitc = _G.SunstoneWeapons, CLASS_BIT[class or ""]
  local p = PROF[class]
  if classID == 4 and (sub == 0 or sub > 6) or type(tbl) ~= "table" or not bitc then -- jewelry, relics (or no table)
    local list = p and ((classID == 4 and p.armor) or (classID == 2 and p.weapon))
    if not p then return "known", 0 end
    for _, s in ipairs(list or {}) do if s == sub then return "known", 0 end end
    return nil
  end
  local race = select(3, UnitRace("player"))
  local flag = type(race) == "number" and (race == 95 and 4294967296 or race == 96 and 8589934592 or race <= 31 and 2 ^ (race - 1)) or nil
  local state, level
  for _, r in ipairs(tbl) do
    if r[1] == classID and r[2] == sub and bit.band(r[3], bitc) ~= 0 and (r[6] == -1 or not flag or r[6] % (2 * flag) >= flag) then
      if r[4] == 1 then return "known", 0 end
      if not state then state, level = "train", r[5] end
    end
  end
  if classID == 4 then return state and "known" or nil, level or 0 end -- (armor is learned from your class trainer at its level)
  if state and Learned(sub) then return "known", 0 end
  return state, level or 0
end

local function Usable(class, classID, subClassID)
  if classID ~= 2 and classID ~= 4 or type(subClassID) ~= "number" then return false end
  local state, level = U.Can(classID, subClassID)
  return state ~= nil and level <= UnitLevel("player") + 4
end

-- Score of what the item would replace. A two-hander replaces main and off hand together; an
-- off-hand item can't go next to a two-hander (nil = skip it).
local function EquippedScore(slots, weights, class, equipLoc)
  local function SlotScore(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return 0 end
    local _, _, _, _, _, classID, subClassID = NS.GetItemInfoInstant(link)
    return Score(link, weights, class, WeaponKind(classID, subClassID))
  end
  if equipLoc == "INVTYPE_2HWEAPON" then return SlotScore(16) + SlotScore(17), 16 end
  if slots[1] == 17 then
    local mh = GetInventoryItemLink("player", 16)
    if mh and select(4, NS.GetItemInfoInstant(mh)) == "INVTYPE_2HWEAPON" then return nil end
  end
  local worst, worstSlot
  for _, slot in ipairs(slots) do
    local sc = SlotScore(slot)
    if not worst or sc < worst then worst, worstSlot = sc, slot end
  end
  return worst or 0, worstSlot
end

-- How much better an item is than what you wear, for your class and goal (an item in your bags, say); nil = not for you
function U.GainOf(link)
  local _, class = UnitClass("player")
  local level = UnitLevel("player")
  local _, _, _, _, _, _, _, _, equipLoc = NS.GetItemInfo(link)
  local slots = SLOTS[equipLoc or ""]
  local _, _, _, _, _, classID, subClassID = NS.GetItemInfoInstant(link)
  if not slots or not Usable(class, classID, subClassID) then return nil end
  local eq = EquippedScore(slots, Weights(class, level), class, equipLoc)
  return eq and Score(link, Weights(class, level), class, WeaponKind(classID, subClassID)) - eq or nil
end

-- The same for a tooltip, with what it's compared with -> { score, old, gain, oldName, empty, worn, level, train, spec, twoHand } or
-- { no = true } (your class can't use it); nil = not gear, or not loaded yet
function U.Compare(link)
  local _, class = UnitClass("player")
  local level = UnitLevel("player")
  local name, _, _, _, req, _, _, _, equipLoc = NS.GetItemInfo(link)
  if not name then return nil end
  local slots = SLOTS[equipLoc or ""]
  local id, _, _, _, _, classID, subClassID = NS.GetItemInfoInstant(link)
  if not slots or (classID ~= 2 and classID ~= 4) then return nil end
  local state = U.Can(classID, subClassID)
  if not state then return { no = true } end
  local w, spec = Weights(class, level)
  local c = { score = Score(link, w, class, WeaponKind(classID, subClassID)), spec = spec or "you", level = type(req) == "number" and req or nil,
              train = state == "train" and classID == 2 and (U.WEAPON_NAME[subClassID] or "that weapon") or nil }
  for _, sl in ipairs(slots) do
    local on = GetInventoryItemLink("player", sl)
    if on and (on == link or (GetInventoryItemID("player", sl) == id and on:match("item:[%-%d]+:[%-%d]*:[%-%d]*:[%-%d]*:[%-%d]*:[%-%d]*:([%-%d]*)")
                              == link:match("item:[%-%d]+:[%-%d]*:[%-%d]*:[%-%d]*:[%-%d]*:[%-%d]*:([%-%d]*)"))) then c.worn = true end
  end
  local old, slot = EquippedScore(slots, w, class, equipLoc)
  if not old then c.twoHand, c.old = true, 0 return c end
  c.old, c.gain = old, c.score - old
  local on = slot and GetInventoryItemLink("player", slot)
  c.oldName = on and (NS.GetItemInfo(on)) or nil
  c.empty = not on
  return c
end

-- How much better an item is for another of your characters than what it wore when last seen -> gain, level it needs (if above it); nil = no,
-- or not everything is loaded yet. Weapons it would have to learn first are left out.
function U.AltGain(s, link)
  local class, level = s.class, s.level
  local p = PROF[class or ""]
  if not p or type(level) ~= "number" or type(s.gear) ~= "table" then return nil end
  local name, _, _, _, req, _, _, _, equipLoc = NS.GetItemInfo(link)
  local slots = SLOTS[equipLoc or ""]
  local _, _, _, _, _, classID, subClassID = NS.GetItemInfoInstant(link)
  if not name or not slots or (classID ~= 2 and classID ~= 4) then return nil end
  req = type(req) == "number" and req or 0
  if req > level + 6 then return nil end
  local ok
  for _, sub in ipairs(classID == 4 and p.armor or p.weapon) do if sub == subClassID then ok = true end end
  if not ok or (classID == 4 and (subClassID == 4 or (subClassID == 3 and (class == "HUNTER" or class == "SHAMAN"))) and level < 40) then return nil end
  local plan = s.talentGoal and NS.PlanFor and NS.PlanFor(class, s.talentGoal)
  local w = Weights(class, level, plan and plan.id or "none")
  local by = {}
  for _, g in ipairs(s.gear) do if type(g) == "table" and type(g.slot) == "number" then by[g.slot] = g end end
  local cached = C_Item and C_Item.IsItemDataCachedByID
  local function SlotScore(slot)
    local g = by[slot]
    if not g or not g.id then return 0 end
    if cached and not cached(g.id) then
      if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, g.id) end
      return nil
    end
    local l = g.item or ("item:" .. g.id)
    local _, _, _, _, _, gc, gs = NS.GetItemInfoInstant(l)
    return Score(l, w, class, WeaponKind(gc, gs))
  end
  local old
  if equipLoc == "INVTYPE_2HWEAPON" then
    local a, b = SlotScore(16), SlotScore(17)
    old = a and b and a + b
  else
    if slots[1] == 17 and by[16] and by[16].equipLoc == "INVTYPE_2HWEAPON" then return nil end
    for _, sl in ipairs(slots) do
      local v = SlotScore(sl)
      if not v then return nil end
      if not old or v < old then old = v end
    end
  end
  if not old then return nil end
  return Score(link, w, class, WeaponKind(classID, subClassID)) - old, req > level and req or nil
end

-- Where a quest starts: first quest giver spawn, as a map position.
local function QuestStart(qid)
  local L = NS.Quests()
  local sb = L.Quest.Get(qid, "startedBy")
  local npcs = type(sb) == "table" and sb[1]
  if type(npcs) ~= "table" or not npcs[1] then return nil end
  local npc = npcs[1]
  local spawns = L.Npc.Get(npc, "spawns")
  if type(spawns) ~= "table" then return { npc = L.Npc.Get(npc, "name") } end
  for areaId, coords in pairs(spawns) do
    local xy = type(coords) == "table" and coords[1]
    if xy and xy[1] and xy[1] > 0 then
      local m = NS.QuestDB.AreaMap(areaId)
      if m then return { npc = L.Npc.Get(npc, "name"), mapID = m, x = xy[1] / 100, y = xy[2] / 100 } end
    end
  end
  return { npc = L.Npc.Get(npc, "name") }
end

U.candidates = {}   -- itemID -> { quests = {...} }
U.results = {}

local function QuestOK(qid, class, horde)
  local L = NS.Quests()
  if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then return false end
  if NS.Engine and NS.Engine.Lib() then return NS.Engine.QuestOK(qid) end
  local races = L.Quest.Get(qid, "requiredRaces")
  if races and races ~= 0 and horde and bit.band(races, horde) == 0 then return false end
  local classes = L.Quest.Get(qid, "requiredClasses")
  local mask = L.Enum and L.Enum.classKeys and L.Enum.classKeys[class]
  if classes and classes ~= 0 and mask and bit.band(classes, mask) == 0 then return false end
  return true
end

-- Score every candidate whose item data is loaded; ask the game for the rest, a batch at a time
-- (items the server never answers are given up on after three tries).
local asked = {}
local function R1(v) return math.floor((v or 0) * 10 + 0.5) / 10 end
function U.Evaluate()
  local _, class = UnitClass("player")
  local level = UnitLevel("player")
  local weights = Weights(class, level)
  local best, all = {}, {}
  local waiting, requested = 0, 0
  for id, cand in pairs(U.candidates) do
    local name, link, quality, ilvl, reqLevel, _, _, _, equipLoc = NS.GetItemInfo(id)
    if not name then
      if (asked[id] or 0) < 3 then
        waiting = waiting + 1
        if requested < 60 and C_Item and C_Item.RequestLoadItemDataByID then
          requested = requested + 1
          asked[id] = (asked[id] or 0) + 1
          C_Item.RequestLoadItemDataByID(id)
        end
      end
    else
      local slots = SLOTS[equipLoc or ""]
      local _, _, _, _, _, classID, subClassID = NS.GetItemInfoInstant(id)
      if slots and Usable(class, classID, subClassID) and (reqLevel or 0) <= level + 4 then
        local sc = Score(link, weights, class, WeaponKind(classID, subClassID))
        local eq, eqSlot = EquippedScore(slots, weights, class, equipLoc)
        local gain = eq and sc - eq or 0
        -- an item far above you with no level on it (test and event items) isn't something you can go and get
        local odd = (reqLevel or 0) == 0 and not cand.quests and (ilvl or 0) > level + 15
        local state, skillLevel = U.Can(classID, subClassID)
        if classID == 4 and (skillLevel or 0) > (reqLevel or 0) then reqLevel = skillLevel end -- mail and plate at 40
        if gain > 0.5 and not odd then
          local entry = { id = id, name = name, link = link, ilvl = ilvl, reqLevel = reqLevel, slot = SLOT_NAME[eqSlot] or "?",
                          slots = slots, slotId = slots[1], quality = quality,
                          train = classID == 2 and state == "train" and subClassID or nil, trainLevel = skillLevel,
                          score = sc, cur = eq, gain = gain, quests = cand.quests, extra = cand.extra,
                          ah = cand.ah, aha = cand.aha, two = equipLoc == "INVTYPE_2HWEAPON" or nil }
          all[#all + 1] = entry
          if cand.quests then
            local key = slots[1] == 11 and "ring" or slots[1] == 13 and "trinket" or slots[1]
            if not best[key] or gain > best[key].gain then best[key] = entry end
          end
        end
      end
    end
  end
  table.sort(all, function(a, b) return a.gain > b.gain end)
  U.all, U.evaluated = all, true
  U.waiting = waiting
  if NS.Gear and NS.Gear.Changed then NS.Gear.Changed() end
  local list = {}
  for _, e in pairs(best) do list[#list + 1] = e end
  table.sort(list, function(a, b) return a.gain > b.gain end)
  for i = 1, #list do
    local e = list[i]
    if i <= 12 and not e.start then
      local q = e.quests[1]
      e.questID, e.questName, e.questLevel = q.id, q.name, q.level
      e.start = QuestStart(q.id)
    end
  end
  U.results, U.waiting = list, waiting
  if NS.db then
    NS.db.upgrades = NS.db.upgrades or {}
    local trimmed = {}
    for i = 1, math.min(#list, 12) do
      local e = list[i]
      trimmed[i] = { id = e.id, name = e.name, ilvl = e.ilvl, reqLevel = e.reqLevel, slot = e.slot, gain = R1(e.gain),
                     questID = e.questID, questName = e.questName, questLevel = e.questLevel, start = e.start }
    end
    -- Every upgrade from every source, for the desktop helper's rankings: up to 150 from quests, crafting, vendors,
    -- rewards and dungeons, plus up to 40 more that are only on the Auction House (its own list in the helper).
    local items, ahOnly = {}, 0
    for _, e in ipairs(all) do
      local only = e.ah and not e.quests and not e.extra
      if (only and ahOnly < 40) or (not only and #items - ahOnly < 150) then
        if only then ahOnly = ahOnly + 1 end
        local q
        if e.quests then
          q = {}
          for k = 1, math.min(3, #e.quests) do q[k] = e.quests[k].id end
        end
        items[#items + 1] = { id = e.id, name = e.name, slot = e.slot, gain = R1(e.gain), cur = R1(e.cur), req = e.reqLevel,
                              ilvl = e.ilvl, q = q, x = e.extra and true or nil, two = e.two,
                              ah = e.ah and math.floor(e.ah) or nil, aha = e.aha }
      end
    end
    NS.db.upgrades[NS.CharKey()] = { time = time(), level = level, list = trimmed, items = items, waiting = waiting }
  end
  return list
end

local function Wearable(id, class)
  local _, _, _, equipLoc, _, classID, subClassID = NS.GetItemInfoInstant(id)
  return equipLoc and SLOTS[equipLoc] and Usable(class, classID, subClassID)
end

-- Crafted gear, dungeon loot, quest rewards, reputation and Library Book gear from Data.lua, and the helper's GearList.lua
-- (item ID = required level, numbers only): what this character could wear now or soon.
local function AddGearList(found, class, level)
  local n = 0
  local function Add(id, req)
    if type(id) ~= "number" or type(req) ~= "number" or req < level - 12 or req > level + 4 then return end
    if n >= 1500 or not Wearable(id, class) then return end
    found[id] = found[id] or {}
    found[id].extra = true
    n = n + 1
  end
  local gl = _G.SunstoneGearList
  if type(gl) == "table" and type(gl.items) == "table" then
    for id, req in pairs(gl.items) do Add(id, req) end
  end
  local D = NS.Engine and NS.Engine.Data()
  if not D then return n end
  for _, list in pairs(D.recipes) do
    for _, r in ipairs(list) do
      if r.i and r.lv and (not r.sd or r.sd == NS.Engine.Side()) then Add(r.i, r.lv) end
    end
  end
  for id, l in pairs(D.loot) do
    local dg = D.dungeons[l[1][1]]
    if dg and dg[2] <= level + 4 and dg[3] >= level - 8 then Add(id, level) end
  end
  for id, e in pairs(NS.Engine.RepItems()) do
    if e[1].kind == "gear" then
      local req = NS.Engine.Q("Item", id, "requiredLevel")
      if type(req) == "number" and req > 0 then Add(id, req) end
    end
  end
  for id, b in pairs(NS.Engine.BookItems()) do Add(id, b.tier[4]) end
  return n
end

-- Quest rewards listed in Data.lua (a quest you can't take yet, or one far above you, isn't offered)
local function AddRewards(found, class, level)
  local E = NS.Engine
  if not E then return end
  for id, rw in pairs(E.Data().rewards) do
    if rw[1] <= level + 4 and Wearable(id, class) then
      local quests = {}
      for k = 2, #rw do
        local qid = rw[k]
        local ql = E.QuestLevel(qid)
        if E.QuestReq(qid) <= level + 4 and ql <= level + 5 and ql >= level - 12 and not E.Done(qid) and E.QuestOK(qid) then
          quests[#quests + 1] = { id = qid, name = E.QuestName(qid), level = ql }
        end
      end
      if quests[1] then
        found[id] = found[id] or {}
        if not found[id].quests then found[id].quests = quests end
      end
    end
  end
end

-- Gear listed on the Auction House in recent scans (read only; prices in copper). Only for the
-- helper's separate "Auction House" list: the other upgrade lists never use the Auction House.
local AH_MAX_AGE = 3   -- days
local function AddAuction(found, class)
  local A = NS.Auction
  if not (A and A.Each) then return 0 end
  local n = 0
  A.Each(function(id, price, age)
    if n >= 600 or not age or age > AH_MAX_AGE then return end
    local _, _, _, equipLoc, _, classID, subClassID = NS.GetItemInfoInstant(id)
    if equipLoc and SLOTS[equipLoc] and Usable(class, classID, subClassID) then
      found[id] = found[id] or {}
      found[id].ah, found[id].aha = price, age
      n = n + 1
    end
  end)
  return n
end

-- Walk the item list a few hundred entries per frame to find quest rewards near your level.
function U.Scan()
  local L = NS.Quests()
  if U.scanning then return end
  local _, class = UnitClass("player")
  local level = UnitLevel("player")
  if not (L and L.Item and L.Item.GetAllIds) then -- no quest database: Data.lua alone
    local found = {}
    NS.Safe("upgrade rewards", AddRewards, found, class, level)
    U.extraCount = AddGearList(found, class, level)
    pcall(AddAuction, found, class)
    U.candidates, U.scannedLevel = found, level
    U.Evaluate()
    return
  end
  U.scanning = true
  local horde = UnitFactionGroup("player") == "Horde" and L.Enum and L.Enum.factionRaceMasks and L.Enum.factionRaceMasks.Horde
  if UnitFactionGroup("player") == "Alliance" then horde = L.Enum and L.Enum.factionRaceMasks and L.Enum.factionRaceMasks.Alliance end
  local ids = L.Item.GetAllIds()
  local i, found = 1, {}
  local ticker
  ticker = C_Timer.NewTicker(0.05, function()
    local ok, err = pcall(function()
      local stop = math.min(i + 400, #ids)
      for k = i, stop do
        local id = ids[k]
        local req = L.Item.Get(id, "requiredLevel") or 0
        if req >= level - 10 and req <= level + 5 and req > 0 or (req == 0 and level <= 12) then
          local rewards = L.Item.Get(id, "questRewards")
          local vendors = L.Item.Get(id, "vendors")
          if type(vendors) == "table" and next(vendors) and req <= level + 4 and (req > 0 or level <= 5) and Wearable(id, class) then
            found[id] = found[id] or {}
            found[id].extra = true
          end
          if type(rewards) == "table" and rewards[1] then
            local quests = {}
            for _, qid in ipairs(rewards) do
              local ql, qreq = L.Quest.Get(qid, "questLevel") or 0, L.Quest.Get(qid, "requiredLevel") or 0
              if qreq <= level + 4 and ql <= level + 5 and QuestOK(qid, class, horde) then
                quests[#quests + 1] = { id = qid, name = L.Quest.Get(qid, "name"), level = L.Quest.Get(qid, "questLevel") }
              end
            end
            if quests[1] then found[id] = found[id] or {}; found[id].quests = quests end
          end
        end
      end
      i = stop + 1
      if i > #ids then
        ticker:Cancel()
        NS.Safe("upgrade rewards", AddRewards, found, class, level)
        U.extraCount = AddGearList(found, class, level)
        local okAh, nAh = pcall(AddAuction, found, class)
        U.ahCount = okAh and nAh or 0
        U.candidates, U.scanning, U.scannedLevel = found, false, level
        U.Evaluate()
        C_Timer.After(5, function() NS.Safe("upgrades", U.Evaluate) end) -- items that loaded late
      end
    end)
    if not ok then ticker:Cancel(); U.scanning = false; NS.Error("upgrades scan", err) end
  end)
end

function U.Print(mark)
  local list = U.results
  if U.scanning then NS.Print("still looking through quest rewards, try again in a few seconds.") return end
  if not list or #list == 0 then NS.Print("no quest-reward upgrades found near your level right now.") return end
  NS.Print("best quest-reward upgrades for you (gain = score over what you wear):")
  local hbd = NS.HBD()
  local marks = {}
  for i = 1, math.min(#list, 8) do
    local e = list[i]
    local where = ""
    if e.start and e.start.mapID then
      where = string.format(" · %s, %s %.1f, %.1f", e.start.npc or "?", hbd and hbd:GetLocalizedMap(e.start.mapID) or "?", e.start.x * 100, e.start.y * 100)
      if mark and i <= 5 then
        marks[#marks + 1] = { title = e.name .. " (" .. e.slot .. ")", note = "Quest: " .. (e.questName or "?") .. " from " .. (e.start.npc or "?"),
                              mapID = e.start.mapID, x = e.start.x, y = e.start.y, from = "upgrades" }
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffc99734%s|r %s  |cff8aa666+%.1f|r  |cff8f7d68quest: %s (level %s)%s|r",
      e.slot, e.link or e.name, e.gain, e.questName or "?", tostring(e.questLevel or "?"), where))
  end
  if mark then
    for _, m in ipairs(marks) do NS.cdb.markers[#NS.cdb.markers + 1] = m end
    if NS.Markers then NS.Markers.Redraw() end
    NS.Print(#marks .. " quest givers marked with stars. /sun clear removes them.")
  end
  if (U.waiting or 0) > 0 then NS.Print("(" .. U.waiting .. " items were still loading; run it again for a fuller list)") end
  if (U.extraCount or 0) > 0 then
    NS.Print("The window (/sun) has crafted gear, vendor gear and dungeon drops too.")
  end
end

function U:Init()
  NS.On("GET_ITEM_INFO_RECEIVED", function() if not U.scanning and next(U.candidates) then NS.Debounce("upgradesEval", 2, U.Evaluate) end end)
  NS.On("PLAYER_EQUIPMENT_CHANGED", function() NS.Debounce("upgradesEval", 1, U.Evaluate) end)
  NS.On("PLAYER_LEVEL_UP", function() C_Timer.After(3, function() NS.Safe("upgrades", U.Scan) end) end)
  NS.On("QUEST_TURNED_IN", function() C_Timer.After(2, function() NS.Safe("upgrades", U.Scan) end) end)
  -- after the Auction House closes, Auctionator's prices may be new: look again (for the Auction House list)
  NS.On("AUCTION_HOUSE_CLOSED", function() C_Timer.After(3, function() NS.Safe("upgrades", U.Scan) end) end)
  local function Start() C_Timer.After(4, function() NS.Safe("upgrades", U.Scan) end) end
  NS.QuestsReady(Start)
end

NS.Command("upgrades", "['mark'] - best quest-reward gear for you ('mark' stars the quest givers)", function(rest)
  U.Print((rest or ""):lower() == "mark")
end)
