-- Sunstone: the in-game engine.
-- Works out, inside the game and from a character's very first login, where things come from and how far away they
-- are: quests (and what has to be done before them), vendors, crafting, dungeons, reputation, creatures, veins and
-- herbs. Two sources: Data.lua (OneForAll's data, with its author's permission) and QuestDB.lua (Questie's database read live, else our own).
-- Everything the addon has seen for itself (recorded prices, your other characters' professions) is used too.
-- What neither knows is left unknown: nothing here guesses a drop chance or a price.

local _, NS = ...
local E = NS.Module("Engine")
NS.Engine = E

local RUN, DETOUR = 7, 1.3          -- yards per second on foot; real paths are longer than a straight line
local PER_QUEST, IN_LOG = 8, 4      -- minutes for a quest step, and for one you already have
local UNKNOWN_TRIP, FAR_TRIP = 12, 60

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local KEYS = { "npcs", "names", "recipes", "prof", "trainers", "reagents", "vprice", "dungeons", "loot", "factions", "books",
               "tiers", "rating", "weights", "rewards", "quests", "weapons", "spells", "hub", "favorPay", "crateSteps", "territory" }
local data
function E.Data()
  if data then return data end
  local src = type(_G.SunstoneData) == "table" and _G.SunstoneData or {}
  data = {}
  for _, k in ipairs(KEYS) do data[k] = type(src[k]) == "table" and src[k] or {} end
  return data
end

-- Quest and creature facts (QuestDB.lua): Questie's database, else our own. nil when there's neither.
local function Lib() return NS.Quests() end
E.Lib = Lib

local function Q(ent, id, field)
  local L = Lib()
  if not L or not L[ent] or id == nil then return nil end
  local ok, v = pcall(L[ent].Get, id, field)
  if ok then return v end
end
E.Q = Q

local function List(v) return type(v) == "table" and v or {} end

---------------------------------------------------------------------------
-- Long jobs run a few milliseconds per frame (never inside a pcall: they yield)
---------------------------------------------------------------------------
local jobs, sliceEnd = {}, 0
local function NowMs() return debugprofilestop and debugprofilestop() or GetTime() * 1000 end
function E.Yield()
  if coroutine.running() and NowMs() > sliceEnd then coroutine.yield() end
end
function E.Busy(key) return jobs[key] ~= nil end
function E.Job(key, fn, done)
  if jobs[key] then return false end
  local co = coroutine.create(fn)
  jobs[key] = co
  local function Step()
    sliceEnd = NowMs() + 5
    local ok, res = coroutine.resume(co)
    if not ok then
      jobs[key] = nil
      NS.Error(key, res)
    elseif coroutine.status(co) == "dead" then
      jobs[key] = nil
      if done then NS.Safe(key, done, res) end
    else
      C_Timer.After(0, Step)
    end
  end
  C_Timer.After(0, Step)
  return true
end

---------------------------------------------------------------------------
-- Places and travel
---------------------------------------------------------------------------
function E.Point(m, x, y) -- x, y: 0 to 1
  if type(m) ~= "number" or m <= 0 or type(x) ~= "number" or type(y) ~= "number" or (x <= 0 and y <= 0) then return nil end
  local p = { m = m, x = x, y = y }
  local hbd = NS.HBD()
  if hbd then
    local ok, wx, wy, inst = pcall(hbd.GetWorldCoordinatesFromZone, hbd, x, y, m)
    if ok and wx then p.wx, p.wy, p.inst = wx, wy, inst end
  end
  return p
end

local here, hereAt
function E.Here()
  local now = GetTime()
  if here and hereAt and now - hereAt < 1 then return here end
  local p = NS.Snapshot and NS.Snapshot.Position and NS.Snapshot.Position()
  here = p and E.Point(p.mapID, p.x, p.y) or nil
  hereAt = now
  return here
end

-- yards between two places; math.huge = another continent; nil = can't tell
function E.Yards(a, b)
  a = a or E.Here()
  if not a or not b then return nil end
  if a.wx and b.wx then
    if a.inst ~= b.inst then return math.huge end
    return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
  end
end

local function Speed() return RUN * ((UnitLevel("player") or 1) >= 40 and 1.6 or 1) end

-- minutes to get there (from where you are, or from `a`)
function E.Minutes(b, a)
  local y = E.Yards(a, b)
  if y == nil then return UNKNOWN_TRIP end
  if y == math.huge then return FAR_TRIP end
  return y * DETOUR / Speed() / 60
end

function E.Where(p)
  if not p then return "" end
  return string.format("%s %.1f, %.1f", NS.Travel and NS.Travel.MapName and NS.Travel.MapName(p.m) or ("map " .. p.m), p.x * 100, p.y * 100)
end

function E.Far(p)
  local y = p and E.Yards(nil, p)
  if y == nil then return "" end
  if y == math.huge then return "on another continent" end
  return string.format("%d yards away", math.floor(y / 10 + 0.5) * 10)
end

function E.Overseas(p)
  return p ~= nil and E.Yards(nil, p) == math.huge
end

local function PlaceText(p)
  if not p then return "" end
  local f = E.Far(p)
  return E.Where(p) .. (f ~= "" and (", " .. f) or "")
end
E.PlaceText = PlaceText

function E.Duration(mins)
  if mins < 90 then return string.format("about %d min", math.max(1, math.floor(mins + 0.5))) end
  return string.format("about %.1f h", mins / 60)
end

local function At(row, p) -- adds Map / Go to a row
  if p then row.m, row.x, row.y = p.m, p.x, p.y end
  return row
end
E.At = At

function E.Nearest(pts)
  local best, bm
  for _, p in ipairs(pts or {}) do
    local mins = E.Minutes(p)
    if not bm or mins < bm then best, bm = p, mins end
  end
  return best, bm
end

local areaMap = {}
local function AreaToMap(area)
  local m = areaMap[area]
  if m ~= nil then return m or nil end
  local v = NS.QuestDB.AreaMap(area)
  areaMap[area] = v or false
  return v
end

local function SpawnPoints(spawns, limit)
  local out = {}
  for area, coords in pairs(List(spawns)) do
    local m = type(coords) == "table" and AreaToMap(area)
    if m then
      for _, xy in ipairs(coords) do
        local x, y = xy[1], xy[2]
        if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
          out[#out + 1] = E.Point(m, x / 100, y / 100)
          if limit and #out >= limit then return out end
        end
      end
    end
  end
  return out
end
E.SpawnPoints = SpawnPoints

local pointCache = {}
function E.Points(kind, id) -- kind "Npc" or "Object": every known spawn
  local key = kind .. id
  if pointCache[key] then return pointCache[key] end
  local pts = SpawnPoints(Q(kind, id, "spawns"), 80)
  if #pts == 0 and kind == "Npc" then
    local n = E.Data().npcs[id]
    if n and n[2] then pts[1] = E.Point(n[2], n[3] / 100, n[4] / 100) end
  end
  if #pts == 0 and NS.Community then -- where players met it
    local c = kind == "Npc" and NS.Community.Where(id) or kind == "Object" and List(NS.Community.Chest(id)).at
    for k = 1, #List(c), 3 do pts[#pts + 1] = E.Point(c[k], c[k + 1] / 100, c[k + 2] / 100) end
  end
  pointCache[key] = pts
  return pts
end

---------------------------------------------------------------------------
-- NPCs and creatures
---------------------------------------------------------------------------
local function Side() return (UnitFactionGroup("player") or "Horde"):sub(1, 1) end
E.Side = Side

function E.NpcName(id)
  local n = Q("Npc", id, "name")
  if type(n) == "string" then return n end
  local d = E.Data().npcs[id]
  return d and d[1] or NS.Community and NS.Community.Name(id) or ("NPC " .. tostring(id))
end

function E.Friendly(id)
  local f = Q("Npc", id, "friendlyToFaction")
  if type(f) ~= "string" then
    local d = E.Data().npcs[id]
    f = d and d[5]
  end
  return type(f) ~= "string" or f == "" or f:find(Side(), 1, true) ~= nil
end

-- Questie lists neutral (yellow) beasts as friendly to both sides: these factions are animals you can fight.
local CRITTERS = { [31] = true, [188] = true, [190] = true, [1555] = true }
local NEUTRAL_BEASTS = { [7] = true, [15] = true, [32] = true, [189] = true, [1094] = true }
function E.Huntable(id) -- lowest level, highest level; nil when it isn't something to grind
  local lo = Q("Npc", id, "minLevel")
  if type(lo) ~= "number" or lo < 1 then return nil end
  local rank = Q("Npc", id, "rank")
  if type(rank) == "number" and rank > 0 then return nil end
  local f = Q("Npc", id, "friendlyToFaction")
  if type(f) == "string" and f ~= "" and f:find(Side(), 1, true) then
    local fac = Q("Npc", id, "factionID")
    if not NEUTRAL_BEASTS[fac or 0] then return nil end
  end
  local flags = Q("Npc", id, "npcFlags")
  if type(flags) == "number" and flags > 0 then return nil end
  local hi = Q("Npc", id, "maxLevel")
  if type(hi) ~= "number" then hi = lo end
  if hi - lo > 6 then return nil end -- odd generic entries ("Cat 7-30")
  local fac = Q("Npc", id, "factionID")
  if CRITTERS[fac or 0] or (hi <= 1 and (fac == 7 or fac == nil)) then return nil end -- critters (adders, rats, gazelles)
  local md = type(_G.SunstoneMobs) == "table" and _G.SunstoneMobs.mobs and _G.SunstoneMobs.mobs[id]
  if md and md[4] == 8 then return nil end -- (Classic calls it a critter)
  if fac == nil and #E.Points("Npc", id) < 3 then return nil end -- props and one-offs Questie knows little about
  return lo, hi
end

local RANK = { [1] = "elite", [2] = "rare elite", [3] = "boss", [4] = "rare" }
function E.Creature(id) -- "level 12-14, elite"
  local lo, hi = Q("Npc", id, "minLevel"), Q("Npc", id, "maxLevel")
  local bits = {}
  if type(lo) == "number" and lo > 0 then
    bits[1] = "level " .. lo .. ((type(hi) == "number" and hi ~= lo) and ("-" .. hi) or "")
  end
  local r = RANK[Q("Npc", id, "rank") or 0]
  if r then bits[#bits + 1] = r end
  return table.concat(bits, ", ")
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
function E.ItemName(id)
  local ok, name = pcall(NS.GetItemInfo, id)
  if ok and type(name) == "string" then return name end
  local n = E.Data().names[id]
  if n then return n end
  n = Q("Item", id, "name")
  return type(n) == "string" and n or ("item " .. tostring(id))
end

function E.Have(id)
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not fn then return 0 end
  local ok, n = pcall(fn, id)
  return ok and type(n) == "number" and n or 0
end

-- what a vendor charges: seen by the recorder first, then the game's own price list for trade goods and recipes
function E.VendorPrice(id, npc)
  local vend = NS.db and NS.db.rec and NS.db.rec.vend
  if type(vend) == "table" then
    local v = npc and vend[npc]
    local e = v and type(v.i) == "table" and v.i[id]
    if type(e) == "table" and type(e.c) == "number" and e.c > 0 then return e.c / math.max(1, e.n or 1) end
    if not npc then
      for _, w in pairs(vend) do
        local e2 = type(w) == "table" and type(w.i) == "table" and w.i[id]
        if type(e2) == "table" and type(e2.c) == "number" and e2.c > 0 then return e2.c / math.max(1, e2.n or 1) end
      end
    end
  end
  local shared = NS.Community and NS.Community.Price(id, npc)
  if shared then return shared end
  local p = E.Data().vprice[id]
  return type(p) == "number" and p or nil
end

---------------------------------------------------------------------------
-- You: professions, finished quests, other characters
---------------------------------------------------------------------------
local skills, skillsAt
function E.Skills() -- { tailoring = { rank, max, name } }
  local now = GetTime()
  if skills and now - skillsAt < 3 then return skills end
  skills, skillsAt = {}, now
  for _, s in ipairs(NS.Snapshot and NS.Snapshot.Skills and NS.Snapshot.Skills() or {}) do
    skills[s.name:lower()] = { rank = s.rank, max = s.max, name = s.name }
  end
  return skills
end

function E.Skill(prof)
  local s = prof and E.Skills()[prof:lower()]
  return s and s.rank, s and s.max
end

-- Your other characters (same realm and side) with a profession, from their last save: "Ragna (Tailoring 62)"
function E.AltsWith(prof, need)
  local out = {}
  local me, realm, side = UnitName("player"), GetRealmName(), UnitFactionGroup("player")
  for _, s in pairs(NS.db and NS.db.snapshots or {}) do
    if type(s) == "table" and type(s.name) == "string" and s.name ~= me and s.faction == side and s.realm == realm then
      for _, k in ipairs(List(s.skills)) do
        if type(k) == "table" and type(k.name) == "string" and k.name:lower() == prof:lower() and type(k.rank) == "number" then
          out[#out + 1] = { name = s.name, rank = k.rank, ok = not need or k.rank >= need }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.rank > b.rank end)
  return out
end

function E.Done(qid)
  local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
  if not f then return false end
  local ok, v = pcall(f, qid)
  return ok and v == true
end

local log, logAt
function E.Log() -- { [questID] = quest from the route's log reader }
  local now = GetTime()
  if log and now - logAt < 2 then return log end
  log, logAt = {}, now
  for _, q in ipairs(NS.Route and NS.Route.Quests and NS.Route.Quests() or {}) do log[q.id] = q end
  return log
end

local raceFlag
local function RaceOK(mask)
  if type(mask) ~= "number" or mask == 0 then return true end
  if mask == 1099511627776 then return false end -- (our own data's mark for the other side)
  if raceFlag == nil then
    local L = Lib()
    local byId = L and L.Enum and L.Enum.raceMaskById
    local id = select(3, UnitRace("player"))
    raceFlag = byId and id and byId[id] or false
  end
  if not raceFlag then
    local L = Lib()
    local masks = L and L.Enum and L.Enum.factionRaceMasks
    local mine = masks and masks[UnitFactionGroup("player") or "Horde"]
    if not mine or mask > 4294967295 then return true end
    return bit.band(mask, mine % 4294967296) ~= 0
  end
  return mask % (2 * raceFlag) >= raceFlag -- (Forever's newer races are past 32 bits: no bit library here)
end

local CLASS_KEY = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
E.RaceOK = RaceOK
local function ClassOK(mask)
  if type(mask) ~= "number" or mask == 0 then return true end
  local key = CLASS_KEY[select(2, UnitClass("player")) or ""]
  return not key or bit.band(mask, key) ~= 0
end

E.ClassOK = ClassOK

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local function QuestField(qid, field, dataIndex)
  local v = Q("Quest", qid, field)
  if v == nil and dataIndex then
    local d = E.Data().quests[qid]
    v = d and d[dataIndex]
  end
  return v
end

E.QuestField = QuestField

function E.QuestName(qid)
  local n = QuestField(qid, "name", 1)
  return type(n) == "string" and n or ("quest " .. tostring(qid))
end
function E.QuestLevel(qid) return tonumber(QuestField(qid, "questLevel", 2)) or 0 end
function E.QuestReq(qid) return tonumber(QuestField(qid, "requiredLevel", 3)) or 0 end

-- quests that aren't there for you: hidden by Questie, or a holiday's while it isn't on
local corrections, events
local SEASONAL = { [-22] = true, [-284] = true, [-364] = true, [-366] = true, [-368] = true, [-369] = true, [-370] = true,
                   [-374] = true, [-375] = true, [-376] = true, [-1001] = true, [-1002] = true, [-1003] = true, [-1005] = true }
function E.Blocked(qid) -- (taken out by Questie: not a holiday's)
  if corrections == nil then E.Hidden(qid) end
  return corrections and corrections.hiddenQuests[qid] and true or false
end
function E.Hidden(qid)
  if corrections == nil then
    corrections, events = false, false
    if QuestieLoader then
      local ok, c = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieCorrections")
      if ok and type(c) == "table" and type(c.hiddenQuests) == "table" then corrections = c end
      local ok2, e = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieEvent")
      if ok2 and type(e) == "table" and e.IsEventQuest and e.IsEventActiveForQuest then events = e end
    end
  end
  if corrections and corrections.hiddenQuests[qid] then return true end
  if events then
    local ok, is = pcall(events.IsEventQuest, qid)
    if ok and is then
      local ok2, on = pcall(events.IsEventActiveForQuest, qid)
      return not (ok2 and on)
    end
  end
  return SEASONAL[Q("Quest", qid, "zoneOrSort") or 0] and not events or false
end

-- a holiday's quest (hidden only while the holiday isn't on): the holiday's name, "" when the data doesn't say which; nil = not one
local HOLIDAY = { [-364] = "Darkmoon Faire" }
function E.Holiday(qid)
  if E.Blocked(qid) then return nil end
  local sort = Q("Quest", qid, "zoneOrSort") or 0
  if sort == -284 then return nil end -- ("Special": Season of Discovery's and the like, no holiday)
  local is = SEASONAL[sort]
  if not is and events then local ok, e = pcall(events.IsEventQuest, qid) is = ok and e end
  if not is then return nil end
  return HOLIDAY[sort] or ""
end

function E.QuestOK(qid, anyTime) -- anyTime: a holiday's quest counts even while the holiday isn't on
  if anyTime then if E.Blocked(qid) then return false end elseif E.Hidden(qid) then return false end
  if not RaceOK(Q("Quest", qid, "requiredRaces")) or not ClassOK(QuestField(qid, "requiredClasses", 5)) then return false end
  local d = E.Data().quests[qid]
  if d and (d[4] == "A" or d[4] == "H") and d[4] ~= Side() then return false end
  for _, sk in ipairs({ Q("Quest", qid, "requiredSkill") or false }) do -- a profession quest: only with that profession
    if sk and type(sk[1]) == "number" and NS.SKILL_NAME and NS.SKILL_NAME[sk[1]] and not E.Skill(NS.SKILL_NAME[sk[1]]) then return false end
  end
  return true
end

-- Quests still to do before this one, in order; nil = this character can't get it.
function E.Chain(qid, depth, seen)
  depth, seen = depth or 0, seen or {}
  if seen[qid] or depth > 10 then return {} end
  seen[qid] = true
  if not E.QuestOK(qid) then return nil end
  local log = E.Log()
  for _, e in pairs(List(Q("Quest", qid, "exclusiveTo"))) do if E.Done(e) or log[e] then return nil end end -- (another version done or taken)
  local out, has = {}, {}
  local function add(list, last)
    for _, x in ipairs(list) do if not has[x] then has[x] = true; out[#out + 1] = x end end
    if last and not has[last] then has[last] = true; out[#out + 1] = last end
  end
  for _, p in pairs(List(QuestField(qid, "preQuestGroup", 7))) do
    if not E.Done(p) then
      local sub = E.Chain(p, depth + 1, seen)
      if not sub then return nil end
      add(sub, p)
    end
  end
  local single = List(QuestField(qid, "preQuestSingle", 6))
  local any, best, bestQ = next(single) == nil, nil, nil
  for _, p in pairs(single) do if E.Done(p) then any = true end end
  if not any then
    for _, p in pairs(single) do
      local copy = {}
      for k in pairs(seen) do copy[k] = true end
      local sub = E.Chain(p, depth + 1, copy)
      if sub and log[p] then best, bestQ = sub, p break end -- the one you already have (Call of Fire: one start per race)
      if sub and (not best or #sub < #best) then best, bestQ = sub, p end
    end
    if not best then return nil end
    add(best, bestQ)
  end
  return out
end

-- Where it starts: place, who, or (nil, name, itemID) for a quest an item starts.
function E.QuestStart(qid)
  local at = NS.QuestDB.StartsAt(qid) -- (a chain that starts in another place for each side)
  if at then return E.Point(at.m, at.x, at.y), at.name end
  local sb = Q("Quest", qid, "startedBy")
  local best, bm, who
  if type(sb) == "table" then
    local n = 0
    for _, id in pairs(List(sb[1])) do
      n = n + 1
      if n <= 6 and E.Friendly(id) then
        local p, mins = E.Nearest(E.Points("Npc", id))
        if p and (not bm or mins < bm) then best, bm, who = p, mins, E.NpcName(id) end
      end
    end
    n = 0
    for _, id in pairs(List(sb[2])) do
      n = n + 1
      local p, mins
      if n <= 3 then p, mins = E.Nearest(E.Points("Object", id)) end
      if p and (not bm or mins < bm) then
        local on = Q("Object", id, "name")
        best, bm, who = p, mins, type(on) == "string" and on or "an object"
      end
    end
    if not best then
      for _, id in pairs(List(sb[3])) do return nil, E.ItemName(id), id end
    end
  end
  if not best then
    local d = E.Data().quests[qid]
    if d and d[8] ~= "" then return d[9] > 0 and E.Point(d[9], d[10] / 100, d[11] / 100) or nil, d[8] end
  end
  return best, who
end

function E.QuestElite(qid)
  local o = Q("Quest", qid, "objectives")
  if type(o) ~= "table" then return false end
  local function elite(id) local r = Q("Npc", id, "rank"); return r == 1 or r == 2 end
  for _, e in pairs(List(o[1])) do if type(e) == "table" and elite(e[1]) then return true end end
  local n = 0
  for _, e in pairs(List(o[3])) do
    if type(e) == "table" and n < 3 then
      n = n + 1
      local k = 0
      for _, id in pairs(List(Q("Item", e[1], "npcDrops"))) do
        k = k + 1
        if k <= 3 and elite(id) then return true end
      end
    end
  end
  return false
end

-- Every objective's known spots, one list per objective
function E.ObjectiveSpots(qid)
  local o, out = Q("Quest", qid, "objectives"), {}
  local has = false
  local function Add(list, pts) for _, p in ipairs(pts) do if #list < 40 then list[#list + 1] = p end end end
  if type(o) == "table" then
    for _, e in pairs(List(o[1])) do has = true; if type(e) == "table" and e[1] then local l = {}; Add(l, E.Points("Npc", e[1])); if #l > 0 then out[#out + 1] = l end end end
    for _, e in pairs(List(o[2])) do has = true; if type(e) == "table" and e[1] then local l = {}; Add(l, E.Points("Object", e[1])); if #l > 0 then out[#out + 1] = l end end end
    for _, e in pairs(List(o[3])) do
      has = true
      if type(e) == "table" and e[1] then
        local l, n = {}, 0
        for _, id in pairs(List(Q("Item", e[1], "npcDrops"))) do n = n + 1; if n <= 6 then Add(l, E.Points("Npc", id)) end end
        n = 0
        for _, id in pairs(List(Q("Item", e[1], "objectDrops"))) do n = n + 1; if n <= 4 then Add(l, E.Points("Object", id)) end end
        if #l > 0 then out[#out + 1] = l end
      end
    end
  end
  local te = Q("Quest", qid, "triggerEnd")
  if type(te) == "table" and type(te[2]) == "table" then
    has = true
    local l = SpawnPoints(te[2], 10)
    if #l > 0 then out[#out + 1] = l end
  end
  return out, has
end

function E.Centroid(pts)
  local count, best = {}, nil
  for _, p in ipairs(pts) do
    count[p.m] = (count[p.m] or 0) + 1
    if not best or count[p.m] > count[best] then best = p.m end
  end
  if not best then return nil end
  local n, x, y = 0, 0, 0
  for _, p in ipairs(pts) do if p.m == best then n, x, y = n + 1, x + p.x, y + p.y end end
  return E.Point(best, x / n, y / n)
end

-- Quest XP (Questie's Forever table, recorded sessions), at your level the way the game pays it
function E.QuestXP(qid)
  local t = NS.QuestDB.XPTable()
  local e = t and t[qid]
  if type(e) ~= "table" then
    local r = NS.db and type(NS.db.qrec) == "table" and NS.db.qrec[qid] -- what one of your characters was paid
    if type(r) == "table" and tonumber(r.xp) and tonumber(r.l) then return tonumber(r.xp), tonumber(r.l) end
    return nil
  end
  return tonumber(e[2]), tonumber(e[1])
end
function E.QuestXPTable() return NS.QuestDB.XPTable() end

function E.AdjustedXP(qlevel, xp, level)
  if level >= 60 or not qlevel or qlevel <= 0 or not xp or xp <= 0 then return 0 end
  local mult = math.min(10, math.max(1, 2 * (qlevel - level) + 20))
  local v = xp * mult / 10
  local function r(step, half) return step * math.floor((v + half) / step) end
  if v <= 100 then return r(5, 2) elseif v <= 500 then return r(10, 5) elseif v <= 1000 then return r(25, 12) end
  return r(50, 25)
end

-- A quest as a way to get something: { mins, label, d, place, req, qid } or nil
function E.QuestRoute(qid)
  if E.Done(qid) then return nil end
  local chain = E.Chain(qid)
  if not chain then return nil end
  local steps = {}
  for _, s in ipairs(chain) do steps[#steps + 1] = s end
  steps[#steps + 1] = qid
  local inLog = E.Log()
  local todo = {}
  for _, s in ipairs(steps) do if not inLog[s] then todo[#todo + 1] = s end end
  local mins = PER_QUEST * #todo + IN_LOG * (#steps - #todo)
  local name, lines, place = E.QuestName(qid), {}, nil
  if inLog[qid] then
    lines[1] = "It's in your quest log."
  else
    local first = todo[1] or qid
    local p, who, item = E.QuestStart(first)
    if #steps > 1 then
      lines[1] = string.format("%d quests in all; start with \"%s\".", #steps, E.QuestName(first))
    end
    if item then
      mins = mins + 15
      lines[#lines + 1] = "It starts from an item: " .. (who or "?")
    elseif p then
      mins = mins + E.Minutes(p)
      place = p
      lines[#lines + 1] = "From " .. (who or "?") .. ", " .. PlaceText(p)
    else
      mins = mins + UNKNOWN_TRIP
      lines[#lines + 1] = who and ("From " .. who) or "Where it starts isn't known."
    end
  end
  local level, req = UnitLevel("player"), 0
  for _, s in ipairs(steps) do req = math.max(req, E.QuestReq(s)) end
  local ql = E.QuestLevel(qid)
  if req > level then lines[#lines + 1] = "You can pick it up at level " .. req .. "." end
  if ql > level + 2 then
    mins = mins * 1.4
    lines[#lines + 1] = "Quest level " .. ql .. ": tough at your level."
  end
  if E.QuestElite(qid) then
    mins = mins + 25
    lines[#lines + 1] = "Elite creatures: may need a group."
  end
  return { kind = "quest", mins = mins, label = "Quest: " .. name, d = table.concat(lines, "\n"), place = place, req = req,
           ql = ql, qid = qid, steps = #steps, ok = req <= level }
end

---------------------------------------------------------------------------
-- Where an item comes from
---------------------------------------------------------------------------
-- item -> recipes that make it; recipe item -> its recipe; item -> reputation and Library Book entries
local made, taught, repItems, bookItems
local function Index()
  if made then return end
  made, taught, repItems, bookItems = {}, {}, {}, {}
  local D = E.Data()
  for prof, list in pairs(D.recipes) do
    for _, r in ipairs(list) do
      r.prof = prof
      if not r.sd or r.sd == Side() then
        if r.i then made[r.i] = made[r.i] or {}; table.insert(made[r.i], r) end
        if r.ri then taught[r.ri] = r end
      end
    end
  end
  for _, f in ipairs(D.factions) do
    if not f.side or f.side == Side() then
      for _, it in ipairs(f.i) do
        repItems[it[1]] = repItems[it[1]] or {}
        table.insert(repItems[it[1]], { f = f, standing = it[3], kind = it[4], v = it[5], name = it[2] })
      end
    end
  end
  for _, t in ipairs(D.tiers) do
    for _, it in ipairs(t[5]) do bookItems[it[1]] = { tier = t, text = it[3] } end
  end
end
function E.Made(id) Index(); return made[id] or {} end
function E.Taught(id) Index(); return taught[id] end
function E.RepItems() Index(); return repItems end
function E.BookItems() Index(); return bookItems end

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
E.STANDING = STANDING
function E.StandingText(fid)
  local st, v, size = NS.Standing(fid)
  if not st then return "you haven't met them yet" end
  if size and size > 0 then return string.format("you're %s, %d / %d", STANDING[st] or "?", v or 0, size) end
  return "you're " .. (STANDING[st] or "?")
end

-- where a profession's trainers are: nearest first, only the ones who teach `mask` (1 Apprentice ... 8 Artisan) if given
function E.Trainers(prof, mask, limit)
  local D, out = E.Data(), {}
  local rtr = D.prof[prof] and D.prof[prof].rtr
  for _, t in ipairs(D.trainers[prof] or {}) do
    if t[4] == "" or t[4]:find(Side(), 1, true) then
      local ok = true
      if mask and rtr then ok = bit.band(rtr[t[1]] or 0, mask) ~= 0 end
      if ok then
        local p = E.Point(t[5], t[6] / 100, t[7] / 100)
        if p then out[#out + 1] = { id = t[1], name = t[2], title = t[3], p = p, mins = E.Minutes(p) } end
      end
    end
  end
  table.sort(out, function(a, b) return a.mins < b.mins end)
  while limit and #out > limit do table.remove(out) end
  return out
end

-- who teaches a recipe: nearest trainer on your side, the fee, and the skill it needs
local teachers
function E.Teacher(prof, spell)
  local D = E.Data()
  if not teachers then
    teachers = {}
    for pn, p in pairs(D.prof) do
      for _, t in ipairs(List(p.teach)) do
        for _, sp in ipairs(t[2]) do
          local key = pn .. sp
          teachers[key] = teachers[key] or {}
          for _, n in ipairs(t[1]) do teachers[key][n] = true end
        end
      end
    end
  end
  local who = teachers[prof .. spell]
  local fee = D.prof[prof] and D.prof[prof].fees and D.prof[prof].fees[spell]
  if not who then return nil, fee and fee[1] end
  local best
  for _, t in ipairs(D.trainers[prof] or {}) do
    if who[t[1]] and (t[4] == "" or t[4]:find(Side(), 1, true)) then
      local p = E.Point(t[5], t[6] / 100, t[7] / 100)
      local mins = p and E.Minutes(p) or 99
      if not best or mins < best.mins then best = { id = t[1], name = t[2], title = t[3], p = p, mins = mins } end
    end
  end
  return best, fee and fee[1]
end

local function Vendors(ids, limit)
  local out = {}
  for _, id in pairs(List(ids)) do
    E.Yield()
    if type(id) == "number" and E.Friendly(id) then
      local p, mins = E.Nearest(E.Points("Npc", id))
      out[#out + 1] = { id = id, name = E.NpcName(id), p = p, mins = mins or 30 }
    end
  end
  table.sort(out, function(a, b) return a.mins < b.mins end)
  while #out > (limit or 3) do table.remove(out) end
  return out
end
E.Vendors = Vendors

-- The ways to get a recipe (for its own page and for crafting): rows, and the quickest one's minutes
function E.RecipeSources(r)
  local out = {}
  if r.st then
    out[1] = { mins = 0, label = "You know it from the start of the profession" }
    return out
  end
  if not r.ri then
    local t, fee = E.Teacher(r.prof, r.s)
    if t then
      out[1] = { mins = t.mins + 1, label = "Taught by " .. t.name, place = t.p,
                 d = t.title .. (t.p and (", " .. PlaceText(t.p)) or "") .. (fee and fee > 0 and (". " .. NS.Money(fee)) or "") }
    else
      out[1] = { mins = 15, label = "Taught by " .. r.prof .. " trainers", d = r.k and ("From skill " .. r.k) or nil }
    end
    return out
  end
  local price = r.p or E.VendorPrice(r.ri)
  for _, v in ipairs(Vendors(r.v, 3)) do
    local bits = {}
    if v.p then bits[1] = PlaceText(v.p) end
    if r.fav then
      local c = NS.Currency and NS.Currency(3402)
      bits[#bits + 1] = string.format("costs %sMerchant's Favor%s", type(r.fav) == "number" and (r.fav .. " ") or "", c and string.format(" (you have %d)", c.quantity) or "")
    elseif price then
      bits[#bits + 1] = NS.Money(price)
    end
    if r.rep then
      for _, f in ipairs(E.Data().factions) do
        if f.id == r.rep[1] then bits[#bits + 1] = string.format("needs %s with %s (%s)", STANDING[r.rep[2]] or "?", f.n, E.StandingText(f.id)) end
      end
    end
    out[#out + 1] = { mins = v.mins + (r.fav and 60 or 2) + (r.rep and 120 or 0), label = "Sold by " .. v.name, place = v.p, d = table.concat(bits, "\n") }
  end
  for _, qid in ipairs(r.qs or {}) do
    local qr = E.QuestRoute(qid)
    if qr then out[#out + 1] = { mins = qr.mins, label = qr.label, place = qr.place, d = qr.d } end
  end
  if NS.Collect then
    for _, row in ipairs((NS.Collect.DropRows(r.ri, r.d, 5))) do
      out[#out + 1] = { mins = (row.mins or 600) + 60, label = row.t, d = row.d, place = row.m and { m = row.m, x = row.x, y = row.y } or nil, drop = true, still = row.still }
    end
    local ah = NS.Collect.AuctionRow(r.ri)
    if ah then out[#out + 1] = { mins = 8, label = ah.t, d = ah.d } end
  end
  if #out == 0 then out[1] = { mins = 500, label = "Where this recipe comes from isn't known yet" } end
  table.sort(out, function(a, b) return a.mins < b.mins end)
  return out
end

-- Every way to get an item, quickest first: { kind, label, d, place, mins, ok (you can do it now), req }
local srcCache = {}
function E.ForgetSources() srcCache = {} end
function E.Sources(id)
  local c = srcCache[id]
  if c and GetTime() - c.t < 120 then return c.list end
  Index()
  local D, out, level = E.Data(), {}, UnitLevel("player")
  -- quests
  local quests, seen = {}, {}
  for _, qid in pairs(List(Q("Item", id, "questRewards"))) do if type(qid) == "number" and not seen[qid] then seen[qid] = true; quests[#quests + 1] = qid end end
  local rw = D.rewards[id]
  if rw then for k = 2, #rw do if not seen[rw[k]] then seen[rw[k]] = true; quests[#quests + 1] = rw[k] end end end
  for k = 1, math.min(#quests, 8) do
    E.Yield()
    local r = E.QuestRoute(quests[k])
    if r then out[#out + 1] = r end
  end
  -- reputation vendors (so they aren't listed as plain vendors below)
  local repVendor = {}
  for _, e in ipairs(repItems[id] or {}) do
    for _, v in ipairs(e.v or {}) do repVendor[v] = true end
    for _, v in ipairs(e.f.v or {}) do repVendor[v] = true end
    local vs = Vendors((e.v and #e.v > 0) and e.v or e.f.v, 1)
    local st = NS.Standing(e.f.id)
    local ready = st and st >= e.standing
    out[#out + 1] = { kind = "rep", ok = ready or false, mins = (vs[1] and vs[1].mins or 30) + (ready and 2 or 240 * (e.standing - math.max(4, math.min(st or 4, e.standing)))),
                      label = string.format("%s: %s", e.f.n, STANDING[e.standing]), place = vs[1] and vs[1].p,
                      d = (vs[1] and ("Sold by " .. vs[1].name .. (vs[1].p and (", " .. PlaceText(vs[1].p)) or "")) or "") .. "\n"
                          .. E.StandingText(e.f.id):gsub("^%l", string.upper) .. (ready and ": enough already." or "."),
                      fid = e.f.id, untimed = not ready }
  end
  -- vendors
  for _, v in ipairs(Vendors(Q("Item", id, "vendors") or (D.reagents[id] and D.reagents[id].v), 3)) do
    if not repVendor[v.id] then
      local price = E.VendorPrice(id, v.id) or E.VendorPrice(id)
      out[#out + 1] = { kind = "vendor", ok = true, mins = v.mins + 2, label = "Buy from " .. v.name, place = v.p,
                        d = (v.p and PlaceText(v.p) or "") .. (price and ("\n" .. NS.Money(price) .. " each") or "") }
    end
  end
  -- crafting
  for _, r in ipairs(made[id] or {}) do
    local rank = E.Skill(r.prof)
    local need = r.k or 1
    local s = { kind = "craft", recipe = r, label = string.format("Craft it: %s %d", r.prof, need), req = 0, untimed = true }
    if rank and rank >= need then
      s.ok, s.mins, s.d = true, 20, string.format("You have %s %d.", r.prof, rank)
      if r.ri then s.mins = s.mins + math.min(E.RecipeSources(r)[1].mins, 240) end
    elseif rank then
      s.ok, s.mins, s.d = false, 60 + 2 * (need - rank), string.format("You have %s %d: %d more skill points.", r.prof, rank, need - rank)
    else
      local alts = E.AltsWith(r.prof, need)
      if alts[1] and alts[1].ok then
        s.ok, s.mins, s.d, s.alt = true, 45, string.format("Your %s can make it (%s %d).", alts[1].name, r.prof, alts[1].rank), alts[1].name
      elseif alts[1] then
        s.ok, s.mins, s.d = false, 150, string.format("Your %s has %s %d; it needs %d.", alts[1].name, r.prof, alts[1].rank, need)
      else
        s.ok, s.mins, s.d = false, 200, "Someone with " .. r.prof .. " can make it for you."
      end
    end
    out[#out + 1] = s
  end
  -- dungeons
  for _, l in ipairs(D.loot[id] or {}) do
    local dg = D.dungeons[l[1]]
    if dg then
      local p = dg[4] > 0 and E.Point(dg[4], dg[5] / 100, dg[6] / 100) or nil
      out[#out + 1] = { kind = "dungeon", ok = level >= math.max(dg[7], dg[2] - 3), req = math.max(dg[7], dg[2]), mins = 120 + (p and E.Minutes(p) or 30),
                        untimed = true, label = dg[1] .. ": " .. l[2] .. (l[3] and string.format(" (%s%%)", l[3] >= 10 and math.floor(l[3] + 0.5) or l[3]) or ""),
                        place = p, d = string.format("Levels %d-%d%s%s", dg[2], dg[3], dg[7] > 0 and (", from level " .. dg[7]) or "", p and ("\nEntrance: " .. PlaceText(p)) or "")
                          .. (l[3] and "" or "\nDrop chance not known yet.") }
    end
  end
  -- Library Books
  local b = bookItems[id]
  if b then
    out[#out + 1] = { kind = "books", ok = level >= b.tier[4], req = b.tier[4], mins = 30 * b.tier[1], untimed = true,
                      label = string.format("Library Books: %d books", b.tier[1]), d = "Reward of \"" .. b.tier[3] .. "\"." .. (b.text ~= "" and (" " .. b.text) or "") }
  end
  -- recipe items: their own list
  local tr = taught[id]
  if tr then
    for _, s in ipairs(E.RecipeSources(tr)) do
      out[#out + 1] = { kind = "recipe", ok = not s.drop, mins = s.mins, label = s.label, d = s.d, place = s.place }
    end
  end
  -- creatures
  local drops = List(Q("Item", id, "npcDrops"))
  local n, list = 0, {}
  for _, npc in pairs(drops) do
    E.Yield()
    n = n + 1
    if n <= 40 and type(npc) == "number" then
      local p, mins = E.Nearest(E.Points("Npc", npc))
      if p then list[#list + 1] = { id = npc, p = p, mins = mins } end
    end
  end
  if #list == 0 and D.reagents[id] and D.reagents[id].d then
    for _, npc in ipairs(D.reagents[id].d) do
      local p, mins = E.Nearest(E.Points("Npc", npc))
      if p then list[#list + 1] = { id = npc, p = p, mins = mins } end
    end
    n = math.max(n, D.reagents[id].dn or 0)
  end
  if NS.Farm then -- the ones Questie doesn't list (cloth, meat, junk): Classic's loot tables
    local had = {}
    for _, e in ipairs(list) do had[e.id] = true end
    for _, f in ipairs(NS.Farm.Droppers(id, 60)) do
      if not had[f.id] then
        local p, mins = E.Nearest(E.Points("Npc", f.id))
        if p and not E.Overseas(p) then list[#list + 1] = { id = f.id, p = p, mins = mins } end
      end
    end
  end
  for _, e in ipairs(list) do
    if NS.Farm then e.chance, e.from = NS.Farm.Chance(id, e.id) end
    local secs = e.chance and NS.Farm.KillTime(e.id)
    e.cost = e.mins + (e.chance and math.min(400, (secs or 60) / 60 / math.max(e.chance, 0.001)) or 40 + (n <= 3 and 60 or 0))
      + ((Q("Npc", e.id, "minLevel") or 0) > level + 3 and 120 or 0)
  end
  table.sort(list, function(x, y) return x.cost < y.cost end)
  for k = 1, math.min(#list, 4) do
    local e = list[k]
    local cr = E.Creature(e.id)
    local pct = e.chance and (e.chance >= 0.1 and string.format(" (%d%%)", math.floor(e.chance * 100 + 0.5)) or string.format(" (%.1f%%)", e.chance * 100)) or ""
    out[#out + 1] = { kind = "drop", ok = true, untimed = true, mins = e.cost, label = "Drops from " .. E.NpcName(e.id) .. pct, place = e.p, npc = e.id,
                      d = (cr ~= "" and (cr .. ". ") or "") .. PlaceText(e.p) .. (e.from and ("\nDrop rate from " .. e.from .. ".") or "")
                        .. ((k == 1 and n > 4) and string.format("\n%d creatures drop it in all.", n) or "") }
  end
  -- veins, herbs, chests
  local objs, best = List(Q("Item", id, "objectDrops")), {}
  for _, ob in pairs(objs) do
    E.Yield()
    if type(ob) == "number" then
      local p, mins = E.Nearest(E.Points("Object", ob))
      if p then best[#best + 1] = { id = ob, p = p, mins = mins } end
    end
  end
  table.sort(best, function(x, y) return x.mins < y.mins end)
  local rg = D.reagents[id]
  if #best == 0 and rg and rg.oz then
    for _, z in ipairs(rg.oz) do
      local p = E.Point(z[1], z[2] / 100, z[3] / 100)
      if p then best[#best + 1] = { name = rg.o, p = p, mins = E.Minutes(p), zone = true } end
    end
    table.sort(best, function(x, y) return x.mins < y.mins end)
  end
  local names = {}
  for _, e in ipairs(best) do
    local nm = e.name or Q("Object", e.id, "name") or "an object"
    if not names[nm] and #out < 24 then
      names[nm] = true
      local need = NS.GATHER_SKILL and NS.GATHER_SKILL[nm:lower()]
      local low = nm:lower()
      local box = low:find("chest", 1, true) or low:find("crate", 1, true) or low:find("box", 1, true) or low:find("barrel", 1, true)
      out[#out + 1] = { kind = "gather", ok = true, untimed = true, mins = e.mins + (box and 120 or 15), label = nm, place = e.p,
                        d = (need and (need[1] .. " " .. need[2] .. ". ") or "") .. (e.zone and "Around " or "Nearest: ") .. PlaceText(e.p) }
    end
  end
  if rg then
    if rg.f then out[#out + 1] = { kind = "fish", ok = true, untimed = true, mins = 60, label = "Fishing", d = rg.f } end
    if rg.c then out[#out + 1] = { kind = "make", ok = true, untimed = true, mins = 50, label = "Made from " .. rg.c } end
    if rg.de then out[#out + 1] = { kind = "de", ok = true, untimed = true, mins = 70, label = "Disenchanting", d = string.format("Items of item level %d to %d", rg.de[1], rg.de[2]) } end
  end
  local fam = NS.MATERIAL_FAMILY and NS.MATERIAL_FAMILY[id]
  if fam then
    out[#out + 1] = { kind = "family", ok = true, untimed = true, mins = 25, label = string.format("%s %s of about level %d-%d", fam[4], fam[3], fam[1], fam[2]) }
  end
  -- the Auction House, when Auctionator has seen it lately
  local A = NS.Auction
  local price = A and A.Price and A.Price(id)
  if price then
    local age = A.Age and A.Age(id)
    out[#out + 1] = { kind = "ah", ok = true, mins = 999, label = "Auction House: " .. NS.Money(price),
                      d = (NS.Farm and NS.Farm.PriceText(id) or "") .. (age and (age == 0 and "\nSeen in today's scan" or string.format("\nSeen %d day%s ago", age, age == 1 and "" or "s")) or "") }
  end
  table.sort(out, function(x, y)
    if (x.ok and 1 or 0) ~= (y.ok and 1 or 0) then return x.ok end
    return x.mins < y.mins
  end)
  srcCache[id] = { t = GetTime(), list = out }
  return out
end

-- The quickest way that isn't the Auction House
function E.Best(id)
  for _, s in ipairs(E.Sources(id)) do if s.kind ~= "ah" then return s end end
end

-- "Skinning beasts of level 1-27" and the like: cloth and leather come from whole families of creatures
NS.MATERIAL_FAMILY = {
  [2589] = { 1, 20, "humanoids", "Drops from" }, [2592] = { 15, 30, "humanoids", "Drops from" },
  [4306] = { 26, 40, "humanoids", "Drops from" }, [4338] = { 38, 50, "humanoids", "Drops from" },
  [14047] = { 50, 60, "humanoids", "Drops from" }, [14256] = { 50, 60, "demons", "Drops from" },
  [2318] = { 1, 27, "beasts", "Skinning" }, [2319] = { 15, 38, "beasts", "Skinning" }, [4234] = { 26, 46, "beasts", "Skinning" },
  [4304] = { 35, 58, "beasts", "Skinning" }, [8170] = { 45, 60, "beasts", "Skinning" },
}
-- the Mining skill each vein needs (Classic's values; Forever's mining guide agrees wherever it gives a number)
NS.GATHER_SKILL = {
  ["copper vein"] = { "Mining", 1 }, ["tin vein"] = { "Mining", 65 }, ["silver vein"] = { "Mining", 75 },
  ["iron deposit"] = { "Mining", 125 }, ["gold vein"] = { "Mining", 155 }, ["mithril deposit"] = { "Mining", 175 },
  ["truesilver deposit"] = { "Mining", 230 }, ["dark iron deposit"] = { "Mining", 230 },
  ["small thorium vein"] = { "Mining", 245 }, ["rich thorium vein"] = { "Mining", 275 },
}
NS.SKILL_NAME = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism", [185] = "Cooking",
  [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning", [129] = "First Aid" }

---------------------------------------------------------------------------
-- An item's page (the right side of the window): every way to get it, its recipe and materials
---------------------------------------------------------------------------
local function Cap(s) return s and (s:gsub("^%l", string.upper)) end

-- the nearest weapon master on your side who teaches a kind of weapon
function E.WeaponMaster(sub)
  local best
  for _, w in ipairs(E.Data().weapons) do
    if w[3] == Side() then
      for _, sk in ipairs(w[8]) do
        if sk == sub then
          local p = E.Point(w[4], w[5] / 100, w[6] / 100)
          local mins = p and E.Minutes(p) or 99
          if not best or mins < best.mins then best = { name = w[2], city = w[7], p = p, mins = mins } end
        end
      end
    end
  end
  return best
end

local function MaterialRows(rows, r)
  rows[#rows + 1] = { h = string.format("Materials (%s %s)", r.prof, r.k or "?") }
  for k = 1, #r.r, 2 do
    local id, n = r.r[k], r.r[k + 1]
    local have = E.Have(id)
    local b = have < n and E.Best(id) or nil
    local row = { t = string.format("%dx %s  (you have %d)", n, E.ItemName(id), have), i = id, good = have >= n or nil }
    if have >= n then row.d = "In your bags."
    elseif b then
      row.d = b.label .. (b.d and b.d ~= "" and ("\n" .. (b.d:match("^[^\n]+") or "")) or "")
      At(row, b.place)
    else
      row.d = "Where it comes from isn't known yet."
    end
    rows[#rows + 1] = row
  end
end

local function RecipeRow(r)
  if r.ri then
    local s = E.RecipeSources(r)[1]
    return At({ t = "Recipe: " .. (r.rn or E.ItemName(r.ri)), i = r.ri, d = s and (s.label .. (s.d and ("\n" .. s.d) or "")) }, s and s.place)
  end
  local s = E.RecipeSources(r)[1]
  return At({ t = s.label, d = s.d }, s.place)
end

local HEAD = { quest = "Quests", vendor = "Vendors", craft = "Crafting", dungeon = "Dungeons", rep = "Reputation", books = "Library Books",
               recipe = "Where to get this recipe", drop = "Creatures", gather = "Gathering", fish = "Gathering", make = "Crafting",
               de = "Gathering", family = "Creatures", ah = "Auction House" }

function E.ItemRows(id)
  local rows, src = {}, E.Sources(id)
  local have = E.Have(id)
  if have > 0 then rows[#rows + 1] = { t = string.format("You have %d", have) } end
  if #src == 0 then
    rows[#rows + 1] = { t = "No source known yet",
                        d = "Sunstone adds it once you (or a friend whose numbers you import) loot it, or open a vendor that sells it." }
  end
  local best = src[1]
  local done = {}
  for _, s in ipairs(src) do
    local head = HEAD[s.kind] or "Other"
    if not done[head] then
      done[head] = true
      rows[#rows + 1] = { h = (s == best and not done.best and #src > 1) and (head .. " (easiest)") or head }
      done.best = true
      for _, o in ipairs(src) do
        if (HEAD[o.kind] or "Other") == head then
          local bits = {}
          if o.d and o.d ~= "" then bits[1] = o.d end
          if not o.untimed and o.kind ~= "ah" and o.mins < 400 and o.ok then bits[#bits + 1] = Cap(E.Duration(o.mins)) .. "." end
          rows[#rows + 1] = At({ t = o.label, d = table.concat(bits, "\n"), dim = o.ok == false or nil,
                                 page = o.npc and NS.Farm and function() return NS.Farm.CreaturePage(o.npc) end
                                   or o.kind == "quest" and o.qid and NS.QuestFind and function() return NS.QuestFind.Page(o.qid) end or nil }, o.place)
          if o.recipe then
            rows[#rows + 1] = RecipeRow(o.recipe)
            MaterialRows(rows, o.recipe)
          end
        end
      end
    end
  end
  -- a recipe item: what it teaches you to make
  local tr = E.Taught(id)
  if tr then
    rows[#rows + 1] = { h = "What it makes" }
    rows[#rows + 1] = { t = tr.n, i = tr.i, d = string.format("%s %s%s", tr.prof, tr.k or "?", E.Skill(tr.prof) and string.format(" (you have %d)", E.Skill(tr.prof)) or "") }
    MaterialRows(rows, tr)
  end
  -- weapons: can you use it, and who teaches it
  local _, _, _, _, _, classID, sub = NS.GetItemInfoInstant(id)
  if classID == 2 and NS.Upgrades and NS.Upgrades.Can then
    local state, lvl = NS.Upgrades.Can(classID, sub)
    local kind = NS.Upgrades.WEAPON_NAME[sub]
    if kind and state == "train" then
      local m = E.WeaponMaster(sub)
      table.insert(rows, 1, At({ t = "Learn " .. kind .. " first", hot = true, page = nil,
                                 d = (m and ("Weapon master " .. m.name .. ", " .. m.city .. ". " .. PlaceText(m.p)) or "From a weapon master.")
                                   .. (lvl > UnitLevel("player") and ("\nFrom level " .. lvl .. ".") or "") .. "\nMost weapons cost 10 silver to learn in Classic." }, m and m.p))
    elseif kind and not state then
      table.insert(rows, 1, { t = "Your class can't use " .. kind:lower(), hot = true })
    end
  end
  return rows
end

---------------------------------------------------------------------------
-- XP: the quests that pay best for the time, near you
---------------------------------------------------------------------------
E.cache = {}
local OBJECTIVE, OVERHEAD = 6, 2

local function QuestMinutes(qid, p, inLog)
  local from = p or E.Here()
  local work = OVERHEAD
  local spots, has = E.ObjectiveSpots(qid)
  local complete = inLog and inLog.complete
  if complete then spots = {} end
  if not complete and has and #spots == 0 then return nil end -- inside a dungeon, or nobody knows where
  local last = from
  for _, pts in ipairs(spots) do
    local c = E.Centroid(pts)
    local y = c and E.Yards(from, c)
    work = work + OBJECTIVE + ((y and y ~= math.huge) and 2 * y * DETOUR / Speed() / 60 or 4)
    last = c or last
  end
  local fin = Q("Quest", qid, "finishedBy")
  local handIn
  if type(fin) == "table" then
    for _, id in pairs(List(fin[1])) do
      local pt = E.Points("Npc", id)[1]
      if pt then
        local y = E.Yards(last, pt)
        handIn = (y and y ~= math.huge) and y * DETOUR / Speed() / 60 or nil
        break
      end
    end
  end
  return work + (handIn or 2), #spots
end

function E.FindQuests(done)
  return E.Job("xp quests", function()
    local L = UnitLevel("player")
    local rows, log2 = {}, E.Log()
    local tbl = E.QuestXPTable() or {}
    local ids = {}
    for qid, e in pairs(tbl) do
      if type(qid) == "number" and type(e) == "table" and not log2[qid] then
        local lvl = tonumber(e[1]) or 0
        if lvl <= L + 3 and lvl >= L - 6 then ids[#ids + 1] = qid end
      end
    end
    E.Yield()
    for qid in pairs(log2) do ids[#ids + 1] = qid end
    -- quests whose XP nobody has recorded yet (mostly Forever's new zones): listed apart, nearest first
    local lib = Lib()
    local unknown = {}
    for _, qid in ipairs(lib and lib.Quest.GetAllIds and lib.Quest.GetAllIds() or {}) do
      E.Yield()
      if not tbl[qid] and not log2[qid] then
        local req = Q("Quest", qid, "requiredLevel")
        local ql = Q("Quest", qid, "questLevel")
        if type(req) == "number" and req <= L and type(ql) == "number" and ql > 0 and ql <= L + 3 and ql >= L - 4 then unknown[#unknown + 1] = qid end
      end
    end
    local other = {}
    for _, qid in ipairs(unknown) do
      E.Yield()
      if not E.Done(qid) and E.QuestOK(qid) then
        local p, who, item = E.QuestStart(qid)
        if p and not item then
          local trip = E.Minutes(p)
          local chain = trip <= 10 and E.Chain(qid)
          if chain and #chain == 0 then
            other[#other + 1] = { id = qid, name = E.QuestName(qid), level = E.QuestLevel(qid), mins = trip, p = p, who = who, elite = E.QuestElite(qid) }
          end
        end
      end
    end
    table.sort(other, function(a, b) return a.mins < b.mins end)
    for _, qid in ipairs(ids) do
      E.Yield()
      local inLog = log2[qid]
      if not E.Done(qid) and not (inLog and inLog.failed) and (inLog or (E.QuestReq(qid) <= L and E.QuestOK(qid))) then
        local base, lvl = E.QuestXP(qid)
        lvl = lvl or E.QuestLevel(qid)
        local xp = base and E.AdjustedXP(lvl, base, L) or 0
        if inLog and NS.Route.QuestValue then
          local v = NS.Route.QuestValue(qid)
          if v and (v.xp or 0) > 0 then xp = v.xp end
        end
        if xp > 0 then
          local chain = inLog and {} or E.Chain(qid)
          if chain and #chain == 0 then
            local p, who, item
            if not inLog then p, who, item = E.QuestStart(qid) end
            local trip = p and E.Minutes(p) or 0
            if inLog or (p and not item and trip <= math.min(25, E.Reach() + 3)) then
              local work = QuestMinutes(qid, p, inLog)
              if work then
                local elite = E.QuestElite(qid)
                local mins = math.max(1, trip + work * (elite and 1.6 or 1))
                rows[#rows + 1] = { id = qid, name = E.QuestName(qid), level = lvl, xp = xp, mins = mins, rate = xp / mins, inLog = inLog and true or nil,
                                    elite = elite, p = p, who = who }
              end
            end
          end
        end
      end
    end
    table.sort(rows, function(a, b) return a.rate > b.rate end)
    return { t = time(), level = L, rows = rows, other = other }
  end, function(res)
    E.cache.xp = res
    if done then done(res) end
  end)
end

-- the streamlined set: your best quests whose givers stand close together
function E.QuestBundle(rows, limit, radius)
  local picked, hub = {}, nil
  limit, radius = limit or 6, radius or 1500
  for _, r in ipairs(rows or {}) do if not r.inLog and r.p then hub = r.p; break end end
  for _, r in ipairs(rows or {}) do
    if #picked >= limit then break end
    if not r.inLog and not r.elite and r.p and hub then
      local y = E.Yards(hub, r.p)
      if (y and y <= radius) or (y == nil and hub.m == r.p.m) then picked[#picked + 1] = r end
    end
  end
  return picked
end

---------------------------------------------------------------------------
-- Grinding: camps of creatures at your level near you
---------------------------------------------------------------------------
local ZERO = { { 7, 5 }, { 9, 6 }, { 11, 7 }, { 15, 8 }, { 19, 9 }, { 29, 11 }, { 39, 12 }, { 44, 13 }, { 49, 14 }, { 54, 15 }, { 59, 16 } }
local function Gray(l)
  if l <= 5 then return 0 elseif l <= 39 then return l - math.floor(l / 10) - 5 end
  return l - math.floor(l / 5) - 1
end
function E.KillXP(pl, ml)
  if pl >= 60 or ml <= 0 then return 0 end
  local base = pl * 5 + 45
  if ml >= pl then return base * (1 + 0.05 * (ml - pl)) end
  if ml <= Gray(pl) then return 0 end
  local zd = 17
  for _, z in ipairs(ZERO) do if pl <= z[1] then zd = z[2]; break end end
  return base * (1 - (pl - ml) / zd)
end

-- what a corpse is worth (Farm.lua: coins and usual loot); nil = nobody knows
function E.GoldPerKill(id)
  local l = NS.Farm and NS.Farm.Loot(id)
  return l and l.value or nil
end

-- how far (minutes) is worth walking: a level 3 stays near home
function E.Reach()
  local L = UnitLevel("player") or 1
  return L < 10 and 9 or L < 20 and 16 or 30
end

local CAMP, RESPAWN, KPH = 4, 12, 60
-- Groups of creatures that stand together: { p, n, npcs = { id = count }, trip }. Only inside a job (it yields).
-- accept(id, lowest level) says which creatures count.
function E.BuildCamps(accept, reach)
  local lib = Lib()
  if not lib or not lib.Npc.GetAllIds then return {} end
  local cells, start = {}, E.Here()
  for _, id in ipairs(lib.Npc.GetAllIds()) do
    E.Yield()
    local lo = Q("Npc", id, "minLevel")
    if type(lo) == "number" and accept(id, lo) then
      -- (not kept in the cache: thousands of creatures you may never ask about)
      for _, p in ipairs(pointCache["Npc" .. id] or SpawnPoints(Q("Npc", id, "spawns"), 80)) do
        if not start or not start.inst or p.inst == start.inst then
          local gx, gy = math.floor(p.x * 100 / CAMP), math.floor(p.y * 100 / CAMP)
          local key = p.m * 10000 + gx * 100 + gy
          local c = cells[key]
          if not c then c = { m = p.m, gx = gx, gy = gy, sx = 0, sy = 0, n = 0, npcs = {} }; cells[key] = c end
          c.sx, c.sy, c.n = c.sx + p.x, c.sy + p.y, c.n + 1
          c.npcs[id] = (c.npcs[id] or 0) + 1
        end
      end
    end
  end
  local camps = {}
  for _, c in pairs(cells) do
    E.Yield()
    local n, sx, sy, mix = 0, 0, 0, {}
    for dx = -1, 1 do
      for dy = -1, 1 do
        local o = cells[c.m * 10000 + (c.gx + dx) * 100 + c.gy + dy]
        if o then
          n, sx, sy = n + o.n, sx + o.sx, sy + o.sy
          for k, v in pairs(o.npcs) do mix[k] = (mix[k] or 0) + v end
        end
      end
    end
    if n >= 5 then
      local p = E.Point(c.m, sx / n, sy / n)
      local y = E.Yards(nil, p)
      local trip = E.Minutes(p)
      if p and trip <= reach and y ~= nil and y ~= math.huge then camps[#camps + 1] = { p = p, n = n, npcs = mix, trip = trip, gx = c.gx, gy = c.gy } end
    end
  end
  table.sort(camps, function(a, b) return a.n > b.n end)
  local kept = {}
  for _, c in ipairs(camps) do
    local ok = true
    for _, k in ipairs(kept) do if k.p.m == c.p.m and math.abs(k.gx - c.gx) <= 2 and math.abs(k.gy - c.gy) <= 2 then ok = false; break end end
    if ok and #kept < 120 then kept[#kept + 1] = c end
  end
  return kept
end

function E.FindCamps(done)
  return E.Job("grind spots", function()
    local L = UnitLevel("player")
    local kept = E.BuildCamps(function(id, lo)
      if lo > L + 2 or lo < L - 8 then return false end
      local a, b2 = E.Huntable(id)
      local mid = a and (a + b2) / 2
      return mid and mid >= L - 2 and mid <= L + 2
    end, E.Reach())
    local rows = {}
    for _, c in ipairs(kept) do
      E.Yield()
      local xp, gold, gn, mobs = 0, 0, 0, {}
      for id, n in pairs(c.npcs) do
        local a, b = E.Huntable(id)
        xp = xp + E.KillXP(L, (a + b) / 2) * n
        local g = E.GoldPerKill(id)
        if g then gold, gn = gold + g * n, gn + n end
        mobs[#mobs + 1] = { id = id, n = n, lo = a, hi = b }
      end
      table.sort(mobs, function(a, b) return a.n > b.n end)
      local kph = math.min(KPH, RESPAWN * c.n)
      local xph = xp / c.n * kph
      rows[#rows + 1] = { p = c.p, n = c.n, xph = xph, gph = gn > 0 and gold / gn * kph or nil, trip = c.trip, score = xph * 60 / (60 + c.trip), mobs = mobs }
    end
    table.sort(rows, function(a, b) return a.score > b.score end)
    return { t = time(), level = L, rows = rows }
  end, function(res)
    E.cache.camps = res
    if done then done(res) end
  end)
end

-- Forget what was worked out when it can have changed
function E:Init()
  local function Soon() NS.Debounce("engineForget", 1, function()
    log, skills = nil, nil
    E.ForgetSources()
    E.cache.xp = nil
    if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
  end) end
  NS.On("QUEST_TURNED_IN", Soon)
  NS.On("QUEST_ACCEPTED", Soon)
  NS.On("QUEST_REMOVED", Soon)
  NS.On("SKILL_LINES_CHANGED", function() NS.Debounce("engineSkills", 2, function() skills = nil; E.ForgetSources() end) end)
  NS.On("PLAYER_LEVEL_UP", function() C_Timer.After(2, function() E.cache = {}; E.ForgetSources() end) end)
end
