-- Sunstone: find a quest (the search box on the Quests tab). By its name, by something it gives (or part of its name), by a spell it teaches,
-- by who gives it or by zone. A quest's page: the map of where it starts, or where its chain starts, every step of the chain with its place,
-- what it asks, what it gives, where it's handed in and what it leads to. Also things worth doing quests for: your campsite, bags, trinkets...
-- Facts: QuestDB.lua (Questie live, else our own), Data.lua, DungeonData.lua, CampData.lua and what your characters have seen (QuestRec.lua).
-- Information only: nothing here takes, shares or hands in a quest.

local _, NS = ...
local QF = NS.Module("QuestFind")
NS.QuestFind = QF
local E = NS.Engine
local C = NS.C

local I = "Interface\\Icons\\"
local NOTE, SCROLL = I .. "INV_Misc_Note_01", I .. "INV_Scroll_03"
QF.find = ""

local function List(v) return type(v) == "table" and v or {} end
local function Comma(n)
  n = math.floor((n or 0) + 0.5)
  return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end
local function Cap(s) return (tostring(s):gsub("^%l", string.upper)) end
local function Camp() return type(_G.SunstoneCamp) == "table" and _G.SunstoneCamp or nil end
local function Data() return type(_G.SunstoneQuests) == "table" and _G.SunstoneQuests or {} end
local function Own(qid, field) return NS.QuestDB.own.Quest.Get(qid, field) end
local function MapName(m) return NS.Travel and NS.Travel.MapName and NS.Travel.MapName(m) or ("map " .. tostring(m)) end

-- a name without asking the server for it when one of the lists has it
local dungeonNames
local function ItemName(id)
  local s = List(Data().items)[id]
  if type(s) == "string" then return s:match("^[^|]*") end
  local n = E.Q("Item", id, "name")
  if type(n) == "string" then return n end
  n = E.Data().names[id]
  if n then return n end
  if not dungeonNames then
    dungeonNames = {}
    for _, d in ipairs(List(type(_G.SunstoneDungeons) == "table" and _G.SunstoneDungeons.list)) do
      for _, b in ipairs(List(d.bosses)) do for _, l in ipairs(List(b.loot)) do dungeonNames[l[1]] = l[2] end end
    end
    for _, o in ipairs(List(Camp() and Camp().objects)) do dungeonNames[o[3]] = o[4] end
    if Camp() then dungeonNames[Camp().banner.item] = Camp().banner.name end
  end
  return dungeonNames[id] or E.ItemName(id)
end
QF.ItemName = ItemName

---------------------------------------------------------------------------
-- The index: every quest, what each gives, and what follows it (read once, in the background)
---------------------------------------------------------------------------
local ix
-- what kind of thing: "bag", "trinket", "recipe", "handy" or nil
local function Kind(id)
  local ok, _, _, _, loc, _, class, sub = pcall(NS.GetItemInfoInstant, id)
  if ok and class == 1 and sub == 0 then return "bag" end
  if ok and loc == "INVTYPE_TRINKET" then return "trinket" end
  if ok and class == 9 then return "recipe" end
  local s = List(Data().items)[id]
  if (type(s) == "string" and s:sub(-2) == "|u") or (ok and class == 15 and (sub == 2 or sub == 5)) then return "handy" end
end

function QF.Ready() return ix ~= nil end
function QF.Build(done)
  if ix then if done then done() end return end
  local lib = E.Lib()
  if not lib or E.Busy("quest index") then return end
  E.Job("quest index", function()
    local out = { list = {}, by = {}, gives = {}, items = {}, after = {} }
    local ids, has = {}, {}
    local function Add(id) if type(id) == "number" and not has[id] then has[id] = true; ids[#ids + 1] = id end end
    for _, id in ipairs(lib.Quest.GetAllIds and lib.Quest.GetAllIds() or {}) do Add(id) end
    for id in pairs(E.Data().quests) do Add(id) end
    for id, r in pairs(List(NS.db and NS.db.qrec)) do if type(r) == "table" and r.n then Add(id) end end
    for _, id in ipairs(ids) do
      E.Yield()
      local name = E.QuestName(id)
      if name and not name:find("^quest %d+$") and not E.Blocked(id) then
        local e = { id = id, n = name, low = name:lower(), lv = E.QuestLevel(id), req = E.QuestReq(id), cls = tonumber(E.Q("Quest", id, "requiredClasses")) or 0 }
        local sb = E.Q("Quest", id, "startedBy")
        if type(sb) == "table" then
          for _, n in pairs(List(sb[1])) do e.who = E.NpcName(n) break end
          if not e.who then for _, n in pairs(List(sb[2])) do local on = E.Q("Object", n, "name") e.who = type(on) == "string" and on or nil break end end
        end
        local z = E.Q("Quest", id, "zoneOrSort")
        if type(z) == "number" and z > 0 and C_Map and C_Map.GetAreaInfo then
          local ok, zn = pcall(C_Map.GetAreaInfo, z)
          e.zone = ok and type(zn) == "string" and zn or nil
        elseif type(sb) == "table" and type(sb[1]) == "table" and type(sb[1][1]) == "number" and sb[1][1] < 0 then
          local spawns = E.Q("Npc", sb[1][1], "spawns")
          local m = type(spawns) == "table" and next(spawns)
          if type(m) == "number" and m < 0 then e.zone = MapName(-m) end
        end
        local sp = Own(id, "rewardSpell")
        if sp and sp > 0 then
          local ok, sn = pcall(NS.SpellName, sp)
          if ok and type(sn) == "string" then e.spell, e.spellLow = sn, sn:lower() end
        end
        out.by[id] = e
        out.list[#out.list + 1] = e
      end
    end
    for _, e in ipairs(out.list) do
      E.Yield()
      local function After(p)
        if type(p) ~= "number" then return end
        local l = out.after[p]
        if not l then l = {}; out.after[p] = l end
        for _, x in ipairs(l) do if x == e.id then return end end
        l[#l + 1] = e.id
      end
      for _, p in pairs(List(E.QuestField(e.id, "preQuestSingle", 6))) do After(p) end
      for _, p in pairs(List(E.QuestField(e.id, "preQuestGroup", 7))) do After(p) end
    end
    -- what they give
    local it = {}
    local function Gives(qid, item)
      if type(item) ~= "number" or type(qid) ~= "number" or item <= 0 or not out.by[qid] then return end
      local g = out.gives[qid]
      if not g then g = {}; out.gives[qid] = g end
      if g[item] then return end
      g[item] = true
      local e = it[item]
      if not e then
        e = { id = item, q = {} }
        it[item] = e
        out.items[#out.items + 1] = e
      end
      e.q[#e.q + 1] = qid
    end
    for _, id in ipairs(lib.Item.GetAllIds and lib.Item.GetAllIds() or {}) do
      E.Yield()
      for _, q in pairs(List(E.Q("Item", id, "questRewards"))) do Gives(q, id) end
    end
    for id, s in pairs(List(Data().items)) do
      E.Yield()
      local f = type(s) == "string" and s:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|([%d,]*)")
      for q in (f or ""):gmatch("%d+") do Gives(tonumber(q), id) end
    end
    for id, e in pairs(E.Data().rewards) do for k = 2, #e do Gives(e[k], id) end end
    for _, d in ipairs(List(type(_G.SunstoneDungeons) == "table" and _G.SunstoneDungeons.list)) do
      for _, x in ipairs(List(d.quests)) do for _, id in ipairs(List(x[8])) do Gives(x[1], id) end end
    end
    for q, l in pairs(List(Data().gives)) do for _, id in ipairs(l) do Gives(q, id) end end
    for q in pairs(List(NS.db and NS.db.qrec)) do
      local ch, gi = NS.QuestRec.Rewards(q)
      for _, l in ipairs({ ch or {}, gi or {} }) do for _, x in ipairs(l) do Gives(q, type(x) == "table" and x[1] or nil) end end
    end
    for _, e in ipairs(out.items) do
      E.Yield()
      e.n = ItemName(e.id)
      e.low = e.n:lower()
      e.kind = Kind(e.id)
    end
    return out
  end, function(res)
    ix = res
    if done then done() end
    if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
  end)
end
function QF.Forget() ix = nil end
function QF.Index() return ix end

---------------------------------------------------------------------------
-- Where you stand with a quest
---------------------------------------------------------------------------
local CLASS = { [1] = "Warrior", [2] = "Paladin", [4] = "Hunter", [8] = "Rogue", [16] = "Priest", [64] = "Shaman", [128] = "Mage", [256] = "Warlock", [1024] = "Druid" }
local function Other() return E.Side() == "H" and "Alliance" or "Horde" end

-- why this character can't have it, or nil
local function NotYours(qid)
  local races = E.Q("Quest", qid, "requiredRaces")
  local d = E.Data().quests[qid]
  if d and (d[4] == "A" or d[4] == "H") and d[4] ~= E.Side() then return Other() .. " only" end
  if type(races) == "number" and races > 0 and not E.RaceOK(races) then
    local lib = E.Lib()
    local masks = lib and lib.Enum and lib.Enum.factionRaceMasks
    local mine = masks and masks[UnitFactionGroup("player") or "Horde"]
    if races >= 1099511627776 or (mine and bit.band(races % 4294967296, mine % 4294967296) == 0) then return Other() .. " only" end
    return "for another race"
  end
  local cls = tonumber(E.Q("Quest", qid, "requiredClasses")) or 0
  if cls > 0 and not E.ClassOK(cls) then
    local names = {}
    for bitv, n in pairs(CLASS) do if bit.band(cls, bitv) ~= 0 then names[#names + 1] = n end end
    table.sort(names)
    return #names > 0 and (table.concat(names, ", ") .. " only") or "for another class"
  end
end

-- -> key, words, rank (lower = sooner)
function QF.State(qid)
  if E.Done(qid) then return "done", "done", 6 end
  local q = E.Log()[qid]
  if q then
    local ready = NS.Route.Finished and NS.Route.Finished(q)
    return "log", ready and "ready to hand in" or "in your log", 1
  end
  local no = NotYours(qid)
  if no then return "no", no, 8 end
  if E.Hidden(qid) then return "away", "not there right now (a holiday's, or taken out)", 7 end
  for _, sk in ipairs({ E.Q("Quest", qid, "requiredSkill") or false }) do
    local name = sk and type(sk[1]) == "number" and NS.SKILL_NAME and NS.SKILL_NAME[sk[1]]
    if name and (E.Skill(name) or 0) < (tonumber(sk[2]) or 1) then
      return "skill", string.format("needs %s%s", name, (tonumber(sk[2]) or 0) > 1 and (" " .. sk[2]) or ""), 5
    end
  end
  for _, e in pairs(List(E.Q("Quest", qid, "exclusiveTo"))) do
    if E.Done(e) then return "other", "done in another version", 6 end
    if E.Log()[e] then return "other", "you have another version", 6 end
  end
  local req, level = E.QuestReq(qid), UnitLevel("player") or 1
  local steps = E.Chain(qid)
  if not steps then return "no", "not for this character", 8 end
  if req > level then return "soon", "from level " .. req, 4 end
  if #steps > 0 then return "chain", string.format("%d quest%s before it", #steps, #steps == 1 and "" or "s"), 3 end
  return "now", "you can start it now", 2
end

local TINT = { now = "good", log = "good", done = "dim", soon = "accent", chain = "accent", no = "warn" }
local function Words(state, words) return "|cff" .. NS.HEX[TINT[state] or "dim"] .. words .. "|r" end

---------------------------------------------------------------------------
-- The chain
---------------------------------------------------------------------------
-- of several quests any of which will do, the one to show: one that's done, one you have, the shortest way this character can go
local function Pick(list)
  local best, score
  for _, p in pairs(list) do
    if type(p) == "number" then
      local s
      if E.Done(p) then s = 0
      elseif E.Log()[p] then s = 1
      else
        local ch = E.Chain(p)
        s = ch and 10 + #ch + E.QuestReq(p) / 100 or (NotYours(p) and 1000 or 500)
        if ch and #list > 1 then -- among equals, the nearest
          local at = E.QuestStart(p)
          local y = at and E.Yards(nil, at)
          s = s + (not y and 0.5 or y == math.huge and 0.9 or math.min(0.8, y / 20000))
        end
      end
      if not score or s < score then best, score = p, s end
    end
  end
  return best
end
-- every quest of the chain up to this one, in order
function QF.Chain(qid)
  local out, seen = {}, {}
  local function Walk(id, depth)
    if seen[id] or depth > 40 then return end
    seen[id] = true
    for _, p in pairs(List(E.QuestField(id, "preQuestGroup", 7))) do if type(p) == "number" then Walk(p, depth + 1) end end
    local single = List(E.QuestField(id, "preQuestSingle", 6))
    local p = next(single) ~= nil and Pick(single)
    if p then Walk(p, depth + 1) end
    out[#out + 1] = id
  end
  Walk(qid, 1)
  return out
end
-- the next quest on the way to `goal` once `qid` is handed in
function QF.Next(goal, qid)
  if goal == qid then return nil end
  local steps = QF.Chain(goal)
  for _, s in ipairs(steps) do if s ~= qid and not E.Done(s) then return s end end
end
-- the one quest that follows this one, when there's just one
function QF.OnlyNext(qid)
  local l = {}
  for _, x in ipairs(ix and ix.after[qid] or {}) do
    if not E.Done(x) and E.QuestOK(x) then l[#l + 1] = x end
  end
  return #l == 1 and l[1] or nil
end
-- what it leads to
function QF.After(qid)
  local out, has = {}, {}
  local function Add(x)
    if type(x) == "number" and x > 0 and not has[x] and x ~= qid and (not ix or ix.by[x]) then has[x] = true; out[#out + 1] = x end
  end
  Add(E.Q("Quest", qid, "nextQuestInChain"))
  for _, x in ipairs(ix and ix.after[qid] or {}) do Add(x) end
  return out
end

-- where a quest starts: point, who, item that starts it (+ where that comes from)
function QF.Start(qid)
  local p, who, item = E.QuestStart(qid)
  if type(p) == "table" and p.m then return p, who end
  if item then
    local pts = {}
    for _, kind in ipairs({ { "Npc", "npcDrops" }, { "Object", "objectDrops" } }) do
      local n = 0
      for _, id in pairs(List(E.Q("Item", item, kind[2]))) do
        n = n + 1
        if n <= 4 then for k, pt in ipairs(E.Points(kind[1], id)) do if k <= 12 then pts[#pts + 1] = pt end end end
      end
    end
    local near = E.Nearest(pts)
    return near, "the item " .. ItemName(item) .. (near and ", found around here" or ""), item
  end
  return nil, who
end
-- where it's handed in
function QF.End(qid)
  local at = NS.QuestDB.EndsAt(qid)
  if at then return E.Point(at.m, at.x, at.y), at.name end
  local fin = E.Q("Quest", qid, "finishedBy")
  if type(fin) ~= "table" then return nil end
  for k, kind in ipairs({ "Npc", "Object" }) do
    for _, id in pairs(List(fin[k])) do
      if kind == "Object" or E.Friendly(id) then
        local on = kind == "Npc" and E.NpcName(id) or E.Q("Object", id, "name")
        return E.Nearest(E.Points(kind, id)), type(on) == "string" and on or "?"
      end
    end
  end
end

---------------------------------------------------------------------------
-- What it gives
---------------------------------------------------------------------------
-- -> choice, given ({ item, count }), money, seen (true = as one of your characters saw it), mixed (known, but not which are a choice)
function QF.Rewards(qid)
  local ch, gi, money = NS.QuestRec.Rewards(qid)
  if ch and (#ch > 0 or #gi > 0) then return ch, gi, money, true end
  ch, gi = Own(qid, "rewardChoice"), Own(qid, "rewardItems")
  for _, id in ipairs(List(NS.QuestDB.Gives(qid))) do
    gi = gi or {}
    gi[#gi + 1] = { id, 1 }
  end
  local known = {}
  for _, l in ipairs({ ch or {}, gi or {} }) do for _, x in ipairs(l) do known[x[1]] = true end end
  local mixed = {}
  for id in pairs(ix and ix.gives[qid] or {}) do if not known[id] then mixed[#mixed + 1] = { id, 1 } end end
  table.sort(mixed, function(a, b) return a[1] < b[1] end)
  return ch or {}, gi or {}, money or Own(qid, "rewardMoney"), false, mixed
end

local function Gain(id) return NS.Dungeons and NS.Dungeons.Gain and NS.Dungeons.Gain(id) end
local function RewardRow(x)
  local g = Gain(x[1])
  return { t = ItemName(x[1]) .. (x[2] and x[2] > 1 and (" x" .. x[2]) or ""), i = x[1], d = g and string.format("An upgrade for you: +%.1f", g) or nil, ring = nil, q = nil }
end
local function RewardRows(rows, qid)
  local ch, gi, money, seen, mixed = QF.Rewards(qid)
  local spell = Own(qid, "rewardSpell")
  local n0 = #rows
  rows[#rows + 1] = { h = "What it gives" }
  local xp, ql = E.QuestXP(qid)
  local level = UnitLevel("player") or 1
  local log = NS.Route.QuestValue and E.Log()[qid] and NS.Route.QuestValue(qid)
  local bits = {}
  local now = log and log.xp and log.xp > 0 and log.xp or (xp and E.AdjustedXP(ql or E.QuestLevel(qid), xp, level)) or 0
  if now > 0 and level < 60 then bits[#bits + 1] = Comma(now) .. " XP" .. (xp and not log and now < xp and (" (" .. Comma(xp) .. " at its own level)") or "") end
  if (money or 0) > 0 then bits[#bits + 1] = NS.Money(money) end
  for _, r in pairs(List(E.Q("Quest", qid, "reputationReward"))) do
    local name = type(r) == "table" and r[1] and QF.FactionName(r[1])
    if name and tonumber(r[2]) then bits[#bits + 1] = string.format("%s%d %s", r[2] > 0 and "+" or "", r[2], name) end
  end
  if #bits > 0 then rows[#rows + 1] = { t = table.concat(bits, "  ·  "), still = true } end
  if #ch > 0 then
    rows[#rows + 1] = { t = #ch > 1 and "Pick one of these" or "You get", dim = true, still = true }
    for _, x in ipairs(ch) do rows[#rows + 1] = RewardRow(x) end
  end
  if #gi > 0 then
    rows[#rows + 1] = { t = #ch > 0 and "And these" or "You get", dim = true, still = true }
    for _, x in ipairs(gi) do rows[#rows + 1] = RewardRow(x) end
  end
  if mixed and #mixed > 0 then
    rows[#rows + 1] = { t = (#ch + #gi > 0) and "Forever's" or (#mixed > 1 and "Items (you may have to pick one)" or "You get"), dim = true, still = true }
    for _, x in ipairs(mixed) do rows[#rows + 1] = RewardRow(x) end
  end
  if spell then
    local ok, name = pcall(NS.SpellName, spell)
    if ok and type(name) == "string" then rows[#rows + 1] = { t = "Teaches: " .. name, spell = spell, still = true, tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell) or nil } end
  end
  if #rows == n0 + 1 then
    rows[#rows + 1] = { t = "Not recorded yet", d = "Sunstone notes what it gives when one of your characters is offered it.", still = true, dim = true }
  elseif not seen and (#ch + #gi > 0) and not NS.QuestDB.Gives(qid) then
    rows[#rows + 1] = { t = "Items and money are Classic's", d = "Forever may have changed them; Sunstone notes its own when you're offered the quest.", still = true, dim = true }
  end
end

local factionNames
function QF.FactionName(id)
  if GetFactionInfoByID then
    local ok, name = pcall(GetFactionInfoByID, id)
    if ok and type(name) == "string" then return name end
  end
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and type(d) == "table" and type(d.name) == "string" then return d.name end
  end
  if not factionNames then
    factionNames = {}
    for _, f in ipairs(E.Data().factions) do if f.id then factionNames[f.id] = f.n end end
  end
  return factionNames[id]
end

---------------------------------------------------------------------------
-- What to do
---------------------------------------------------------------------------
local function ObjectiveRows(rows, qid, spots)
  local n0 = #rows
  rows[#rows + 1] = { h = "What to do" }
  local inLog = E.Log()[qid]
  if inLog then
    for _, o in ipairs(inLog.objectives or {}) do
      rows[#rows + 1] = { t = o.text or "?", ring = o.finished and "good" or nil, dim = o.finished or nil, still = true }
    end
  end
  local function Spot(pts, t)
    for k, p in ipairs(pts) do if k <= 25 and #spots < 60 then spots[#spots + 1] = { m = p.m, x = p.x, y = p.y, t = t, state = "spot" } end end
  end
  local o = E.Q("Quest", qid, "objectives")
  local howMany, shown = { {}, {}, {} }, {}
  for k, l in pairs(List(Own(qid, "objectives"))) do
    if howMany[k] then for _, e in pairs(l) do if type(e) == "table" and e[1] then howMany[k][e[1]] = tonumber(e[3]) end end end
  end
  local function Count(k, e)
    local n = howMany[k][e[1]]
    return n and n > 0 and (n .. " x ") or ""
  end
  local function Once(text, near)
    local key = text .. (near and (near.m .. ":" .. math.floor(near.x * 100)) or "")
    if shown[key] then return false end
    shown[key] = true
    return true
  end
  if type(o) == "table" then
    for _, e in pairs(List(o[1])) do
      if type(e) == "table" and e[1] then
        local pts = E.Points("Npc", e[1])
        local near = E.Nearest(pts)
        local name = E.NpcName(e[1])
        if Once(name, near) then
        rows[#rows + 1] = E.At({ t = Count(1, e) .. (type(e[2]) == "string" and e[2] ~= "" and e[2] or name), tex = I .. "INV_Misc_Bone_Skull_02",
                                 d = Cap(E.Creature(e[1])) .. (near and ("\nNearest: " .. E.PlaceText(near)) or ""), page = NS.Farm and function() return NS.Farm.CreaturePage(e[1]) end or nil }, near)
        Spot(pts, name)
        end
      end
    end
    for _, e in pairs(List(o[2])) do
      if type(e) == "table" and e[1] then
        local pts = E.Points("Object", e[1])
        local near = E.Nearest(pts)
        local on = E.Q("Object", e[1], "name")
        local name = type(on) == "string" and on or "something"
        if Once(name, near) then
        rows[#rows + 1] = E.At({ t = Count(2, e) .. (type(e[2]) == "string" and e[2] ~= "" and e[2] or name), tex = I .. "INV_Misc_Gear_01", still = true,
                                 d = near and ("Nearest: " .. E.PlaceText(near)) or "Where isn't recorded (often inside a dungeon)" }, near)
        Spot(pts, name)
        end
      end
    end
    for _, e in pairs(List(o[3])) do
      if type(e) == "table" and e[1] then
        local pts, who, n = {}, {}, 0
        for _, id in pairs(List(E.Q("Item", e[1], "npcDrops"))) do
          n = n + 1
          if n <= 6 then
            for _, p in ipairs(E.Points("Npc", id)) do if #pts < 120 then pts[#pts + 1] = p end end
            if n <= 3 then who[#who + 1] = E.NpcName(id) end
          end
        end
        n = 0
        for _, id in pairs(List(E.Q("Item", e[1], "objectDrops"))) do
          n = n + 1
          if n <= 4 then
            for _, p in ipairs(E.Points("Object", id)) do if #pts < 160 then pts[#pts + 1] = p end end
            local on = E.Q("Object", id, "name")
            if n <= 2 and type(on) == "string" then who[#who + 1] = on end
          end
        end
        for _, id in pairs(List(E.Q("Item", e[1], "vendors"))) do if #who < 3 then who[#who + 1] = "sold by " .. E.NpcName(id) end end
        local near = E.Nearest(pts)
        local name = ItemName(e[1])
        rows[#rows + 1] = E.At({ t = Count(3, e) .. name, i = e[1], d = (#who > 0 and ("From " .. table.concat(who, ", ")) or "") .. (near and ((#who > 0 and "\n" or "") .. "Nearest: " .. E.PlaceText(near)) or "") }, near)
        Spot(pts, name)
      end
    end
  end
  local te = E.Q("Quest", qid, "triggerEnd")
  if type(te) == "table" and type(te[2]) == "table" then
    local pts = E.SpawnPoints(te[2], 12)
    local near = E.Nearest(pts)
    local seen = te[1] == "Where it went forward"
    if near then
      rows[#rows + 1] = E.At({ t = seen and "Around here it went forward" or "Go there", d = E.PlaceText(near) .. (seen and "\nFrom one of your characters." or ""), still = true, tex = I .. "INV_Misc_Map_01" }, near)
      Spot(pts, "Go here")
    end
  end
  local text = E.Q("Quest", qid, "objectivesText")
  if type(text) == "table" and type(text[1]) == "string" then rows[#rows + 1] = { t = NS.Clean(table.concat(text, " "), 400), still = true, dim = true } end
  if #rows == n0 + 1 then
    rows[#rows] = nil
    local p, who = QF.End(qid)
    rows[#rows + 1] = { h = "What to do" }
    rows[#rows + 1] = { t = who and ("Nothing else recorded: it may just send you to " .. who) or "Not recorded yet",
                        d = "One of Forever's own quests: Sunstone notes where it goes forward as you play it.", still = true, dim = true }
  end
end

---------------------------------------------------------------------------
-- A quest's page
---------------------------------------------------------------------------
local function Title(qid)
  local l = E.QuestLevel(qid)
  return E.QuestName(qid) .. (l > 0 and ("  (" .. l .. ")") or "")
end
QF.Title = Title

-- the quest to do next on the way to this one (itself at the end)
local function NextStep(steps)
  for _, s in ipairs(steps) do if E.Log()[s] then return s end end
  for _, s in ipairs(steps) do if not E.Done(s) then return s end end
  return steps[#steps]
end

-- a word on how, for a quest that needs it (CampData's tips), or nil
function QF.Tip(qid)
  local c = Camp()
  return c and type(c.tips) == "table" and c.tips[qid] or nil
end

function QF.Page(qid)
  if not ix then QF.Build() end
  local rows = {}
  local state, words = QF.State(qid)
  local steps = QF.Chain(qid)
  local nxt = NextStep(steps)
  local camp = Camp()
  -- the chain's places, for the map
  local pins, places = {}, {}
  for k, s in ipairs(steps) do
    local st = QF.State(s)
    local p, who, item = QF.Start(s)
    places[k] = { p = p, who = who, item = item, st = st }
    if p then
      pins[#pins + 1] = { n = tostring(k), m = p.m, x = p.x, y = p.y, t = E.QuestName(s), d = "From " .. (who or "?"),
                          state = s == nxt and st ~= "done" and "next" or st == "done" and "done" or st == "log" and "log" or "todo" }
    end
  end
  local endP, endWho = QF.End(qid)
  local at
  for k, s in ipairs(steps) do if s == nxt then at = places[k] end end
  local start = at and at.p
  local spots = {}
  local body = {}
  ObjectiveRows(body, qid, spots)
  for _, s in ipairs(spots) do pins[#pins + 1] = s end
  if endP and (not start or endP.m ~= start.m or math.abs(endP.x - start.x) + math.abs(endP.y - start.y) > 0.01) then
    pins[#pins + 1] = { n = "?", m = endP.m, x = endP.x, y = endP.y, t = "Hand in: " .. E.QuestName(qid), d = endWho, state = state == "log" and "log" or "todo" }
  end
  local spec = { title = E.QuestName(qid), m = (start and start.m) or (endP and endP.m) or (spots[1] and spots[1].m), pins = pins }
  spec.name = spec.m and MapName(spec.m)
  local drawn = spec.m and NS.ZoneMap and NS.ZoneMap.Art(spec.m)

  -- 1. where to begin
  local first = {}
  if state == "done" then
    first = { t = "You've done this one", d = "It began with " .. (at and at.who or "?") .. (start and (", " .. E.PlaceText(start)) or "") .. "." }
  elseif state == "log" then
    first = E.At({ t = words == "ready to hand in" and "Ready to hand in" or "It's in your quest log", hot = true, ring = "good",
                   d = words == "ready to hand in" and endP and ("To " .. (endWho or "?") .. ", " .. E.PlaceText(endP)) or nil,
                   actLabel = "Only this", act = function() NS.Route.Focus(qid) end }, words == "ready to hand in" and endP or nil)
  else
    local lead = #steps > 1 and nxt ~= qid
    local log = E.Log()[nxt]
    local bits = {}
    if lead then bits[#bits + 1] = string.format("Step %d of %d on the way to %s.", (function() for k, s in ipairs(steps) do if s == nxt then return k end end return 1 end)(), #steps, E.QuestName(qid)) end
    if log then bits[#bits + 1] = "You have it in your log."
    elseif at and at.who then bits[#bits + 1] = (at.item and "Starts from " or "From ") .. at.who .. (start and (", " .. E.PlaceText(start)) or "")
    else bits[#bits + 1] = "Where it starts isn't recorded (it may be inside a dungeon)." end
    local need = 0
    for _, s in ipairs(steps) do if not E.Done(s) then need = math.max(need, E.QuestReq(s)) end end
    if need > (UnitLevel("player") or 1) then bits[#bits + 1] = #steps > 1 and ("All of the chain needs level " .. need .. ".") or ("You can pick it up at level " .. need .. ".") end
    if state == "no" then bits[#bits + 1] = Cap(words) .. "." end
    first = E.At({ t = (lead and "Start the chain here: " or "Start here: ") .. E.QuestName(nxt), hot = state ~= "no", dim = state == "no" or nil, d = table.concat(bits, "\n"),
                   i = at and at.item or nil, still = not (at and at.item) or nil,
                   actLabel = "Follow it", act = state ~= "no" and start and function() NS.Route.Focus(nxt, qid) NS.Print("the route follows " .. E.QuestName(qid) .. (lead and ", beginning with " .. E.QuestName(nxt) or "") .. ". All quests on the Route tab goes back to everything.") end or nil }, start)
  end
  rows[#rows + 1] = first
  if drawn then rows[#rows + 1] = { zmap = spec } end
  if camp and camp.tips[nxt] and state ~= "done" then rows[#rows + 1] = { t = "How", d = camp.tips[nxt], still = true } end

  -- 2. facts
  local bits = {}
  local req, ql = E.QuestReq(qid), E.QuestLevel(qid)
  if ql > 0 then bits[#bits + 1] = "Level " .. ql end
  if req > 1 and state ~= "soon" then bits[#bits + 1] = "from level " .. req end
  if E.QuestElite(qid) then bits[#bits + 1] = "elite: may need a group" end
  if E.Q("Quest", qid, "specialFlags") == 1 then bits[#bits + 1] = "can be done again and again" end
  local cls = tonumber(E.Q("Quest", qid, "requiredClasses")) or 0
  if cls > 0 then for b, n in pairs(CLASS) do if cls == b then bits[#bits + 1] = n:lower() .. " quest" end end end
  local sub = table.concat(bits, "  ·  ")
  RewardRows(rows, qid)

  -- 3. the chain
  if #steps > 1 then
    local done = 0
    for _, s in ipairs(steps) do if E.Done(s) then done = done + 1 end end
    rows[#rows + 1] = { h = string.format("The chain: %d quests, %d done", #steps, done) }
    for k, s in ipairs(steps) do
      local pl = places[k]
      local st, w = QF.State(s)
      local line = (pl.who and ((pl.item and "Starts from " or "From ") .. pl.who) or "Start not recorded") .. (pl.p and (", " .. E.Where(pl.p)) or "")
      rows[#rows + 1] = E.At({ t = string.format("%d. %s", k, Title(s)), d = line .. "  ·  " .. Words(st, w), dim = st == "done" or nil, hot = s == nxt and st ~= "done" or nil, tex = NOTE,
                               page = s ~= qid and function() return QF.Page(s) end or nil, still = s == qid or nil }, st ~= "done" and pl.p or nil)
      if camp and camp.tips[s] and s ~= nxt and st ~= "done" then rows[#rows + 1] = { t = "How", d = camp.tips[s], still = true, dim = true } end
    end
  end

  -- 4. what to do, 5. hand in, 6. what comes of it
  for _, r in ipairs(body) do rows[#rows + 1] = r end
  if endWho then
    rows[#rows + 1] = { h = "Hand it in" }
    rows[#rows + 1] = E.At({ t = endWho, d = endP and E.PlaceText(endP) or "Where isn't recorded (it may be inside a dungeon).", still = true, tex = SCROLL }, endP)
  end
  local after = QF.After(qid)
  if #after > 0 then
    -- yours first; another side's or class's only when there's nothing else
    local l, yours = {}, 0
    for k, x in ipairs(after) do
      local st, w, rank = QF.State(x)
      l[k] = { q = x, st = st, w = w, rank = rank, k = k }
      if rank < 7 then yours = yours + 1 end
    end
    table.sort(l, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.k < b.k end)
    rows[#rows + 1] = { h = "Leads on to" }
    for k = 1, math.min(yours > 0 and yours or #l, 14) do
      local x = l[k]
      rows[#rows + 1] = { t = Title(x.q), d = Words(x.st, x.w), tex = NOTE, dim = (x.st == "no" or x.st == "done") or nil, page = function() return QF.Page(x.q) end }
    end
  end
  local map1 = start and function() NS.Dungeons.World({ m = start.m, x = start.x * 100, y = start.y * 100, n = E.QuestName(nxt) }) end or nil
  return { title = E.QuestName(qid), icon = NOTE, rows = rows, sub = (sub ~= "" and sub .. "  ·  " or "") .. Words(state, words),
           maps = { map1, drawn and function() return NS.ZoneMap.Show(spec) end or nil },
           mapTips = { { "Map: the way there", "Opens your world map with the way drawn from where you are, plus the arrow and the trail.", "Where it starts isn't recorded." },
                       { "Map: the whole chain", "A map with every step numbered, zone by zone.", "No map for this one." } } }
end

---------------------------------------------------------------------------
-- Your campsite
---------------------------------------------------------------------------
local function DungeonOf(name)
  for _, d in ipairs(List(type(_G.SunstoneDungeons) == "table" and _G.SunstoneDungeons.list)) do if d.n == name then return d end end
end
local TIER = { "first", "second", "third" }
local function ObjectItem(o) return o.alt and E.Side() == "A" and o.alt or o[3] end
local function ObjectState(o)
  local rank = E.Skill(o[1])
  if not rank then return nil, "you don't have " .. o[1] end
  if rank < o[5] then return false, string.format("%s %d (you have %d)", o[1], o[5], rank) end
  return true, string.format("%s %d: you have the skill", o[1], o[5])
end
-- what a place gives when somebody asks for the first camp quests: the nearest of this character's
local function Outdoors()
  local camp = Camp()
  return camp and Pick(camp.outdoors)
end

local function Named(name)
  local l = {}
  for _, e in ipairs(ix and ix.list or {}) do if e.n == name and not NotYours(e.id) then l[#l + 1] = e.id end end
  return #l > 0 and Pick(l) or nil
end
function QF.ObjectPage(o)
  if not ix then QF.Build() end
  local rows, item = {}, ObjectItem(o)
  local ok, words = ObjectState(o)
  rows[1] = { t = o[6] .. ".", d = words, i = item, still = true, ring = ok and "good" or nil }
  if o.note then rows[#rows + 1] = { t = o.note, still = true, dim = true } end
  rows[#rows + 1] = { h = "How to learn it" }
  if o.bp then
    rows[#rows + 1] = { t = "Blueprint: " .. ItemName(o.bp):gsub("^Blueprint: ", ""), i = o.bp, d = "Dropped by " .. (function() local l = {} for _, f in ipairs(o.from) do l[#l + 1] = f[1] .. " in " .. f[2] end return table.concat(l, "; ") end)() .. ", or bought from a player. How often it drops isn't known." }
    for _, f in ipairs(o.from) do
      local d = DungeonOf(f[2])
      if d then rows[#rows + 1] = { t = f[2], d = string.format("Levels %d-%d, %s. Boss: %s.", d.lo, d.hi, d.loc, f[1]), tex = d.icon ~= "" and d.icon or I .. "INV_Misc_Key_10", page = function() return NS.Dungeons.Page(d) end } end
    end
  elseif o[1] == "Cooking" then
    rows[#rows + 1] = { t = "Known from the start of Cooking", d = "Cooking trainers teach it; The Great Outdoors shows you how.", still = true }
    local q = Outdoors()
    if q then rows[#rows + 1] = { t = Title(q), d = Words(QF.State(q)), tex = NOTE, page = function() return QF.Page(q) end } end
  else
    rows[#rows + 1] = { t = "Camping 101: " .. o[1], d = "From the people around the campfire in your starting zone, after The Great Outdoors. Reach " .. o[1] .. " 20 and hand it in for this. Trainers teach it at 20, too.", still = true, tex = NOTE }
    local own = Named("Camping 101: " .. o[1])
    local q = own or Outdoors()
    if q then
      local p, who = QF.Start(q)
      rows[#rows + 1] = E.At({ t = own and Title(own) or ("Given by " .. (who or "?")), d = (own and ("From " .. (who or "?") .. (p and ", " or "")) or "") .. (p and E.PlaceText(p) or "") .. (own and ("  ·  " .. Words(QF.State(own))) or ""),
                               tex = own and NOTE or nil, page = own and function() return QF.Page(own) end or nil, still = not own or nil }, p)
    end
    local best, bm
    for _, l in ipairs(List(Camp().learn[o[1]])) do
      if l[1] == "" or l[1] == E.Side() then
        local p = E.Point(l[2], l[3] / 100, l[4] / 100)
        local mins = p and E.Minutes(p) or 99
        if not bm or mins < bm then best, bm = { p = p, name = l[5] }, mins end
      end
    end
    if best then rows[#rows + 1] = E.At({ t = "Handed in to " .. best.name, d = E.PlaceText(best.p) .. "\nThe nearest of several.", still = true }, best.p)
    else
      local t = E.Trainers(o[1], nil, 1)[1]
      if t then rows[#rows + 1] = E.At({ t = "Nearest trainer: " .. t.name, d = E.PlaceText(t.p), still = true }, t.p) end
    end
  end
  if o.mats then
    rows[#rows + 1] = { h = "Made from" }
    for k = 1, #o.mats, 2 do
      local n = o.mats[k + 1]
      rows[#rows + 1] = { t = (n > 0 and (n .. " x ") or "") .. ItemName(o.mats[k]), i = o.mats[k], d = string.format("You have %d.%s", E.Have(o.mats[k]), n == 0 and " How many it takes isn't recorded." or "") }
    end
  else
    for _, r in ipairs(E.ItemRows(item)) do if r.h or r.i or r.page then rows[#rows + 1] = r end end
  end
  return { title = o[4], icon = NS.ItemIcon(item), rows = rows, sub = string.format("Camp object  ·  %s, %s tier", o[1], TIER[o[2]]) }
end

QF.ObjectItem, QF.ObjectState = ObjectItem, ObjectState
-- the camp objects of a profession, as rows
function QF.CampRows(prof)
  local rows = {}
  local rank = E.Skill(prof)
  for _, o in ipairs(List(Camp() and Camp().objects)) do
    if o[1] == prof then
      local ok = ObjectState(o)
      local how
      if o.from then
        local l = {}
        for _, f in ipairs(o.from) do l[#l + 1] = f[1] .. ", " .. f[2] end
        how = "Blueprint drops from " .. table.concat(l, " or ")
      elseif prof == "Cooking" then how = "Taught by trainers from the start"
      else how = "Camping 101, or a trainer at " .. o[5] end
      rows[#rows + 1] = { t = o[4] .. "  |cff" .. NS.HEX.dim .. "skill " .. o[5] .. "|r" .. (E.Have(ObjectItem(o)) > 0 and "  |cff" .. NS.HEX.good .. "you have one|r" or ""), i = ObjectItem(o), key = "qco" .. o[3],
                          ring = ok and "good" or nil, dim = not rank or nil, d = o[6] .. ".\n" .. how .. ".", page = function() return QF.ObjectPage(o) end }
    end
  end
  return rows
end

function QF.BannerPage()
  local b = Camp().banner
  local rows, pins = { { t = b.what, i = b.item, still = true }, { t = b.note, still = true, dim = true } }, {}
  for k, s in ipairs(b.steps) do if s[3] then pins[#pins + 1] = { n = tostring(k), m = s[3], x = s[4] / 100, y = s[5] / 100, t = s[1], d = s[2], state = k == 1 and "next" or "todo" } end end
  local spec = { title = b.name, m = pins[1].m, pins = pins, name = MapName(pins[1].m) }
  if NS.ZoneMap and NS.ZoneMap.Art(spec.m) then rows[#rows + 1] = { zmap = spec } end
  rows[#rows + 1] = { h = "Step by step" }
  for k, s in ipairs(b.steps) do
    rows[#rows + 1] = E.At({ t = k .. ". " .. s[1], d = s[2] .. (s[3] and ("\n" .. E.Where(E.Point(s[3], s[4] / 100, s[5] / 100))) or ""), still = true }, s[3] and E.Point(s[3], s[4] / 100, s[5] / 100) or nil)
  end
  local d = DungeonOf("Scarlet Monastery: Library")
  if d then rows[#rows + 1] = { t = d.n, d = string.format("Levels %d-%d", d.lo, d.hi), tex = d.icon ~= "" and d.icon or I .. "INV_Misc_Key_10", page = function() return NS.Dungeons.Page(d) end } end
  return { title = b.name, icon = NS.ItemIcon(b.item), rows = rows, sub = "Camp decoration",
           maps = { nil, function() return NS.ZoneMap.Show(spec) end }, mapTips = { { "Map: the way there", "", "Use Go beside a step." }, { "Map: the places", "Each place numbered, zone by zone.", "No map." } } }
end

function QF.CampPage()
  local camp = Camp()
  local rows = {}
  if not camp then return { title = "Your campsite", rows = { { t = "CampData.lua is missing: install the addon again." } } } end
  local q = Outdoors()
  rows[#rows + 1] = { h = "Start here" }
  if q then
    local p, who = QF.Start(q)
    rows[#rows + 1] = E.At({ t = Title(q), d = "Your first campfire. From " .. (who or "?") .. (p and (", " .. E.PlaceText(p)) or "") .. "  ·  " .. Words(QF.State(q)), tex = NOTE, page = function() return QF.Page(q) end }, not E.Done(q) and p or nil)
  end
  local last = camp.bag.last
  local st, w = QF.State(last)
  rows[#rows + 1] = { t = "Bedroll: " .. ItemName(camp.bag.item), i = camp.bag.item, d = camp.bag.what .. "\nA chain of 6 quests from level 14 across four or five zones  ·  " .. Words(st, w), page = function() return QF.Page(last) end }
  rows[#rows + 1] = { t = camp.banner.name, i = camp.banner.item, d = camp.banner.what, page = QF.BannerPage }
  -- the professions you have first
  local profs, has = {}, {}
  for _, o in ipairs(camp.objects) do if not has[o[1]] then has[o[1]] = true; profs[#profs + 1] = { o[1], E.Skill(o[1]) and 0 or 1 } end end
  table.sort(profs, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
  for _, p in ipairs(profs) do
    local rank = E.Skill(p[1])
    rows[#rows + 1] = { h = p[1] .. (rank and (" (you have " .. rank .. ")") or "") }
    for _, o in ipairs(camp.objects) do
      if o[1] == p[1] then
        local ok = ObjectState(o)
        rows[#rows + 1] = { t = o[4] .. (E.Have(ObjectItem(o)) > 0 and "  |cff" .. NS.HEX.good .. "you have one|r" or ""), i = ObjectItem(o), dim = not rank or nil,
                            d = o[6] .. ".  Skill " .. o[5] .. (ok and " (reached)" or "") .. (o.from and (".  Blueprint: " .. o.from[1][1] .. ", " .. o.from[1][2]) or (o[5] <= 20 and ".  Camping 101 or a trainer" or "")),
                            page = function() return QF.ObjectPage(o) end }
      end
    end
  end
  rows[#rows + 1] = { h = "Good to know" }
  for _, r in ipairs(camp.rules) do rows[#rows + 1] = { t = r[1], d = r[2], still = true } end
  rows[#rows + 1] = { t = "From guides", d = "Read in November 2026, the month the game came out: numbers can still change. Where the guides disagree it says so.", still = true, dim = true }
  return { title = "Your campsite", icon = I .. "Spell_Fire_Fire", rows = rows, sub = "The campfire, your bedroll and what each profession can put around it" }
end

---------------------------------------------------------------------------
-- Worth a look: kinds of rewards
---------------------------------------------------------------------------
QF.KINDS = {
  { "camp", "Your campsite", I .. "Spell_Fire_Fire", "The first campfire, the bedroll, camp objects for every profession" },
  { "bag", "Bags from quests", I .. "INV_Misc_Bag_08", "Quests that give a bag" },
  { "handy", "Handy things from quests", I .. "INV_Misc_Orb_02", "Things you use again and again, pets and mounts" },
  { "trinket", "Trinkets from quests", I .. "INV_Jewelry_Talisman_07", "For your trinket slots" },
  { "recipe", "Recipes from quests", I .. "INV_Scroll_06", "Quests that give a recipe" },
  { "class", "Your class's quests", I .. "INV_Misc_Book_09", "Spells, weapons and more only your class gets" },
}

function QF.KindPage(key)
  if key == "camp" then return QF.CampPage() end
  local info
  for _, k in ipairs(QF.KINDS) do if k[1] == key then info = k end end
  local page = { title = info[2], icon = info[3], rows = {}, sub = info[4] }
  local rows = page.rows
  if not ix then
    QF.Build()
    rows[1] = { t = "Reading the quests...", d = "A few seconds the first time.", still = true, dim = true }
    return page
  end
  local found, done, seen = {}, 0, {}
  local function Add(qid, item)
    local st, w, rank = QF.State(qid)
    if st == "no" or st == "away" then return end
    if st == "done" or st == "other" then done = done + 1 return end
    if item then -- one that starts from an item nobody knows a source of (a gift code's) isn't something to go and do
      local p, _, starter = QF.Start(qid)
      if starter and not p then return end
    end
    local key2 = item and item.n or E.QuestName(qid) -- (one way to each thing: the soonest)
    if seen[key2] and seen[key2].rank <= rank then return end
    if seen[key2] then seen[key2].gone = true end
    local f = { q = qid, item = item, st = st, w = w, rank = rank, req = E.QuestReq(qid) }
    seen[key2] = f
    found[#found + 1] = f
  end
  if key == "class" then
    for _, e in ipairs(ix.list) do if e.cls > 0 and E.ClassOK(e.cls) then Add(e.id) end end
  else
    for _, it in ipairs(ix.items) do if it.kind == key then for _, qid in ipairs(it.q) do Add(qid, it) end end end
  end
  table.sort(found, function(a, b)
    local x, y = (a.rank <= 3 and 0 or 1), (b.rank <= 3 and 0 or 1)
    if x ~= y then return x < y end
    if a.req ~= b.req then return a.req < b.req end
    return a.q < b.q
  end)
  local head
  for _, f in ipairs(found) do
    if not f.gone and #rows < 140 then
      local h = f.rank <= 3 and "You can start on these" or "Later"
      if h ~= head then head = h; rows[#rows + 1] = { h = h } end
      rows[#rows + 1] = { t = f.item and f.item.n or Title(f.q), i = f.item and f.item.id or nil, tex = not f.item and NOTE or nil,
                          d = (f.item and (Title(f.q) .. "  ·  ") or "") .. Words(f.st, f.w), page = function() return QF.Page(f.q) end }
    end
  end
  if #rows == 0 then rows[1] = { t = "None left for this character", still = true } end
  if done > 0 then rows[#rows + 1] = { t = string.format("%d more you've done", done), still = true, dim = true } end
  if key ~= "class" then rows[#rows + 1] = { t = "Forever's own quests", d = "Most of their rewards aren't recorded anywhere yet; Sunstone adds the ones your characters are offered.", still = true, dim = true } end
  return page
end

-- under the quests in your log
function QF.IdeaRows(rows)
  rows[#rows + 1] = { h = "Worth a look" }
  for _, k in ipairs(QF.KINDS) do
    rows[#rows + 1] = { t = k[2], d = k[4], tex = k[3], key = "qk" .. k[1], page = function() return QF.KindPage(k[1]) end }
  end
end

---------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------
local CAMPWORDS = "camp campsite campfire camping tent bedroll bed roll sleeping bag sleep cozy banner"
local function Split(text)
  local out = {}
  for w in text:lower():gmatch("%S+") do out[#out + 1] = w end
  return out
end
local function Has(low, words)
  if not low then return false end
  for _, w in ipairs(words) do if not low:find(w, 1, true) then return false end end
  return true
end
-- lower = better: the whole name, its beginning, a word's beginning, inside a word
local function Score(low, text)
  if low == text then return 0 end
  if low:sub(1, #text) == text then return 1 end
  if low:find(" " .. text, 1, true) then return 2 end
  return 3
end

-- -> groups { head, entries { q, item } }
function QF.Search(text)
  text = NS.Clean(text or "", 40):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local words = Split(text)
  local out = { names = {}, items = {}, spells = {}, who = {}, zone = {}, camp = {} }
  if #words == 0 or #text < 2 then return out end
  local camp = Camp()
  for _, o in ipairs(List(camp and camp.objects)) do
    if Has((o[4] .. " " .. o[1] .. " camp object campsite"):lower(), words) and (#text > 2) then out.camp[#out.camp + 1] = o end
  end
  out.campPage = #text > 2 and Has(CAMPWORDS, words) or false
  out.bag = #text > 2 and Has("cozy sleeping bag bedroll bed roll", words) or false
  out.banner = camp and #text > 2 and Has((camp.banner.name .. " camp decoration"):lower(), words) or false
  if not ix then return out end
  local num = tonumber(text)
  for _, e in ipairs(ix.list) do
    if Has(e.low, words) or (num and e.id == num) then out.names[#out.names + 1] = { q = e.id, s = Score(e.low, text) }
    elseif e.spellLow and Has(e.spellLow, words) then out.spells[#out.spells + 1] = { q = e.id, s = Score(e.spellLow, text), spell = e.spell }
    elseif #text > 2 and e.who and Has(e.who:lower(), words) then out.who[#out.who + 1] = { q = e.id, s = Score(e.who:lower(), text), who = e.who }
    elseif #text > 2 and e.zone and Has(e.zone:lower(), words) then out.zone[#out.zone + 1] = { q = e.id, s = 0, zone = e.zone } end
  end
  for _, it in ipairs(ix.items) do
    if Has(it.low, words) then
      local s = Score(it.low, text)
      for _, qid in ipairs(it.q) do out.items[#out.items + 1] = { q = qid, item = it, s = s } end
    end
  end
  return out
end

local CAP = { names = 40, items = 40, spells = 12, who = 15, zone = 30 }
local HEADS = { names = "Quests by that name", items = "Quests that give it", spells = "Quests that teach it", who = "Given by", zone = "In that zone" }
function QF.Rows()
  local rows = {}
  local text = QF.find
  local ready = ix ~= nil
  if not ready then QF.Build() end
  local r = QF.Search(text)
  rows[#rows + 1] = { t = "Search: " .. NS.Clean(text, 40), d = ready and "Quest, reward, spell, giver or zone; part of a word will do." or "Reading the quests: a few seconds the first time.", still = true, dim = true,
                      actLabel = "Clear", act = function() if QF.Clear then QF.Clear() end end, key = "qfhead" }
  local n0 = #rows
  if r.campPage or r.bag or r.banner or #r.camp > 0 then
    rows[#rows + 1] = { h = "For your campsite" }
    local camp = Camp()
    if r.bag then
      rows[#rows + 1] = { t = "Bedroll: " .. ItemName(camp.bag.item), i = camp.bag.item, d = "6 quests from level 14  ·  " .. Words(QF.State(camp.bag.last)), key = "qfbag", page = function() return QF.Page(camp.bag.last) end }
    end
    if r.campPage then rows[#rows + 1] = { t = "Your campsite", d = "Everything for it, by profession", tex = I .. "Spell_Fire_Fire", key = "qkcamp", page = QF.CampPage } end
    if r.banner then rows[#rows + 1] = { t = camp.banner.name, i = camp.banner.item, d = "Camp decoration", key = "qfbanner", page = QF.BannerPage } end
    for k = 1, math.min(#r.camp, 14) do
      local o = r.camp[k]
      rows[#rows + 1] = { t = o[4], i = ObjectItem(o), d = o[1] .. " " .. o[5] .. "  ·  " .. o[6], key = "qfo" .. o[3], page = function() return QF.ObjectPage(o) end }
    end
  end
  local shown = {}
  for _, key in ipairs({ "names", "items", "spells", "who", "zone" }) do
    local l = r[key]
    if #l > 0 then
      local level = UnitLevel("player") or 1
      for _, x in ipairs(l) do
        local e = ix and ix.by[x.q]
        x.dl = math.abs((e and e.lv or 0) - level)
      end
      -- the state is only worked out for what could be shown (a short search finds hundreds)
      table.sort(l, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        if a.dl ~= b.dl then return a.dl < b.dl end
        return a.q < b.q
      end)
      local take = {}
      for k = 1, math.min(#l, CAP[key] * 2) do
        local x = l[k]
        x.st, x.w, x.rank = QF.State(x.q)
        x.at, x.n = k, E.QuestName(x.q)
        local p = QF.Start(x.q)
        x.p = p
        x.far = p and E.Yards(nil, p) or 1e9
        take[k] = x
      end
      table.sort(take, function(a, b)
        local x, y = a.rank >= 7 and 1 or 0, b.rank >= 7 and 1 or 0
        if x ~= y then return x < y end
        if a.s ~= b.s then return a.s < b.s end
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.dl ~= b.dl then return a.dl < b.dl end
        if a.n ~= b.n then return a.n < b.n end
        if a.far ~= b.far then return a.far < b.far end
        return a.at < b.at
      end)
      local n, head = 0, nil
      for _, x in ipairs(take) do
        local id = key == "items" and ("i" .. x.n .. ":" .. x.item.n) or ("q" .. x.q)
        local where = x.p and (MapName(x.p.m) .. "  ·  ") or ""
        if n < CAP[key] and not shown[id] then
          shown[id] = true
          if not head then head = true; rows[#rows + 1] = { h = HEADS[key] } end
          n = n + 1
          local qid = x.q
          if key == "items" then
            rows[#rows + 1] = { t = x.item.n, i = x.item.id, d = Title(qid) .. "  ·  " .. where .. Words(x.st, x.w), dim = x.rank >= 6 or nil, key = "qf" .. id, page = function() return QF.Page(qid) end }
          else
            local extra = key == "spells" and ("Teaches " .. x.spell .. "  ·  ") or key == "who" and (x.who .. "  ·  ") or ""
            rows[#rows + 1] = { t = Title(qid), tex = NOTE, d = extra .. where .. Words(x.st, x.w), dim = x.rank >= 6 or nil, key = "qf" .. id, page = function() return QF.Page(qid) end }
          end
        end
      end
      if #l > n and n > 0 then rows[#rows + 1] = { t = string.format("%d more", #l - n), d = "Type a little more to narrow it down.", still = true, dim = true, key = "qfmore" .. key } end
    end
  end
  if #rows == n0 and ready and #NS.Clean(text, 40) < 2 then
    rows[#rows + 1] = { t = "Type a little more", d = "Two letters or more.", still = true, key = "qfnone" }
  elseif #rows == n0 and ready then
    rows[#rows + 1] = { t = "No quest found", d = "Try part of a word. Rewards of Forever's own quests are mostly not recorded yet.", still = true, key = "qfnone" }
  end
  return rows
end

-- for the main search box: the same, shorter, without its own heading
function QF.For(text)
  if not QF.Ready() then QF.Build() end
  local was = QF.find
  QF.find = NS.Clean(text or "", 40)
  local ok, rows = pcall(QF.Rows)
  QF.find = was
  local out, n = {}, 0
  for _, r in ipairs(ok and rows or {}) do
    if r.h then n = 0 out[#out + 1] = r
    elseif r.key ~= "qfhead" and r.key ~= "qfnone" and not (r.still and r.key and r.key:find("^qfmore")) then
      n = n + 1
      if n <= 6 then out[#out + 1] = r elseif n == 7 then out[#out + 1] = { t = "More on the Quests tab", d = "Search there for the rest.", still = true, dim = true, key = "qfm" .. #out, actLabel = "Open", act = function() QF.Open(text) end } end
    end
  end
  while out[#out] and out[#out].h do table.remove(out) end
  return out
end
function QF.GivenBy(item)
  if not ix then QF.Build() return {} end
  for _, e in ipairs(ix.items) do if e.id == item then return e.q end end
  return {}
end

-- opening it from anywhere (/sun quest name)
function QF.Open(text)
  QF.find = NS.Clean(text or "", 40)
  NS.Window.Open("quests")
  if QF.SetBox then QF.SetBox(QF.find) end
  NS.Window.Refresh()
end

NS.Command("quest", "<part of a name> - find a quest by its name or by something it gives", function(rest) QF.Open(rest) end)
