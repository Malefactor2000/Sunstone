-- Sunstone: remembers the quests you do, for all your characters: who gives and takes each one and where, and the places its
-- objectives moved forward. That's how Forever's new quests, which no Classic database has, get onto the route and the map.
-- Kept only on this computer (SunstoneDB.qrec). It reads the quest log, the quest window you have open and where you stand;
-- nothing else. Information only.

local _, NS = ...
local R = NS.Module("QuestRec")
NS.QuestRec = R

local MAX_POINTS, APART = 12, 1.2   -- spots kept per objective; percent of a zone between two
local MAX_QUESTS = 3000

local function Store()
  if not NS.db then return {} end
  if type(NS.db.qrec) ~= "table" then NS.db.qrec = {} end
  return NS.db.qrec
end

local function Rec(id, make)
  if type(id) ~= "number" or id <= 0 then return nil end
  local s = Store()
  local r = s[id]
  if type(r) ~= "table" then
    if not make then return nil end
    r = {}
    s[id] = r
  end
  return r
end

local function Plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function Here()
  local hbd = NS.HBD()
  if not hbd or (IsInInstance and IsInInstance()) then return nil end
  local x, y, m = hbd:GetPlayerZonePosition()
  if not (x and m) then return nil end
  return { m, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 }
end

-- who you're talking to: "n", id for a creature, "o", id for an object, "i" for an item in your bags
local function Giver()
  local g = NS.GUID("questnpc") or NS.GUID("npc")
  if type(g) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", g)
  id = tonumber(id)
  if (kind == "Creature" or kind == "Vehicle") and id then return "n", id end
  if kind == "GameObject" and id then return "o", id end
  if kind == "Item" then return "i" end
end

local function Mark(id, field)
  local kind, who = Giver()
  if not kind then return end
  local r = Rec(id, true)
  local p = kind ~= "i" and Here() or nil
  r[field] = { kind, who, p and p[1], p and p[2], p and p[3] }
end

-- what the window in front of you says the quest gives: items to choose from, items you get, money
local function Rewards(id)
  if not (GetNumQuestChoices and GetNumQuestRewards and GetQuestItemLink) then return end
  local function Items(kind, n)
    local out = {}
    for i = 1, math.min(tonumber(n) or 0, 10) do
      local ok, link = pcall(GetQuestItemLink, kind, i)
      local item = ok and type(Plain(link)) == "string" and tonumber(link:match("item:(%d+)"))
      if item then
        local num
        if GetQuestItemInfo then
          local ok2, _, _, c = pcall(GetQuestItemInfo, kind, i)
          num = ok2 and type(c) == "number" and c > 1 and c or nil
        end
        out[#out + 1] = { item, num or 1 }
      end
    end
    return out
  end
  local choice, given = Items("choice", GetNumQuestChoices()), Items("reward", GetNumQuestRewards())
  local money = GetRewardMoney and tonumber(GetRewardMoney()) or 0
  local r = Rec(id, true)
  -- (items not loaded yet have no link: a shorter list never replaces a longer one)
  local old = type(r.w) == "table" and r.w or {}
  r.w = { c = #choice >= #(old.c or {}) and choice or old.c, g = #given >= #(old.g or {}) and given or old.g, m = money > 0 and money or old.m }
end

-- what the hand-in window asks you to bring: { { item, count }, ... }. That's how an item learns which quest takes it, for
-- Forever's quests no database has (Darkmoon Faire turn-ins and the like)
local wanting -- [item] = { quest, ... }, built when first asked
local function Needs(id)
  if not (GetNumQuestItems and GetQuestItemLink) then return end
  local out = {}
  for i = 1, math.min(tonumber(GetNumQuestItems()) or 0, 6) do
    local ok, link = pcall(GetQuestItemLink, "required", i)
    link = ok and Plain(link)
    local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if item then
      local c
      if GetQuestItemInfo then
        local ok2, _, _, n = pcall(GetQuestItemInfo, "required", i)
        c = ok2 and type(n) == "number" and n > 0 and n or nil
      end
      out[#out + 1] = { item, c or 1 }
    end
  end
  if #out == 0 then return end
  local r = Rec(id, true)
  if type(r.need) == "table" and #r.need > #out then return end -- (items not loaded yet have no link)
  r.need = out
  if not r.n and GetTitleText then
    local t = Plain(GetTitleText())
    if type(t) == "string" and t ~= "" then r.n = NS.Clean(t, 80) end
  end
  wanting = nil
  if NS.Sell and NS.Sell.Forget then NS.Sell.Forget() end
end
-- quests whose hand-in window asked one of your characters for this item: { quest, ... } or nil
function R.Wanting(item)
  if not wanting then
    wanting = {}
    for id, r in pairs(Store()) do
      for _, e in ipairs(type(r) == "table" and type(r.need) == "table" and r.need or {}) do
        local i = type(e) == "table" and e[1]
        if type(i) == "number" then wanting[i] = wanting[i] or {} table.insert(wanting[i], id) end
      end
    end
  end
  return wanting[item]
end

-- what the log says about a quest
local function FromLog(id)
  local L = C_QuestLog
  if not (L and L.GetLogIndexForQuestID and L.GetInfo) then return end
  local ok, i = pcall(L.GetLogIndexForQuestID, id)
  local info = ok and i and L.GetInfo(i)
  if type(info) ~= "table" then return end
  local r = Rec(id, true)
  local title = Plain(info.title)
  if type(title) == "string" then r.n = NS.Clean(title, 80) end
  if type(info.level) == "number" then r.l = info.level end
  r.side = (UnitFactionGroup("player") or "Horde"):sub(1, 1)
  if GetQuestLogRewardXP then
    local ok2, xp = pcall(GetQuestLogRewardXP, id)
    if ok2 and type(xp) == "number" and xp > 0 and type(info.level) == "number" and info.level >= (UnitLevel("player") or 1) - 4 then r.xp = xp end
  end
end

---------------------------------------------------------------------------
-- Objectives: a place where the number went up
---------------------------------------------------------------------------
local counts = {}   -- [quest] = { [objective] = number }
local function AddSpot(r, i, o)
  local p = Here()
  if not p then return end
  r.o = r.o or {}
  local e = r.o[i]
  if type(e) ~= "table" then
    e = { k = o.type, t = NS.Clean((Plain(o.text) or ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*:?%s*", ""), 60), p = {} }
    r.o[i] = e
  end
  for _, q in ipairs(e.p) do
    if q[1] == p[1] and math.abs(q[2] - p[2]) < APART and math.abs(q[3] - p[3]) < APART then return end
  end
  if #e.p < MAX_POINTS then e.p[#e.p + 1] = p end
end

function R.Look()
  local L = C_QuestLog
  if not (L and L.GetNumQuestLogEntries and L.GetInfo and L.GetQuestObjectives) then return end
  for i = 1, L.GetNumQuestLogEntries() or 0 do
    local info = L.GetInfo(i)
    local id = type(info) == "table" and not info.isHeader and info.questID
    if type(id) == "number" and id > 0 then
      local obj = L.GetQuestObjectives(id) or {}
      local was = counts[id]
      local now = {}
      for k, o in ipairs(obj) do
        local n = type(o.numFulfilled) == "number" and o.numFulfilled or (o.finished and 1 or 0)
        if o.finished and n == 0 then n = 1 end
        now[k] = n
        if was and was[k] and n > was[k] then AddSpot(Rec(id, true), k, o) end
      end
      if not was then FromLog(id) end
      counts[id] = now
    end
  end
end

---------------------------------------------------------------------------
-- In the shape of a quest database (QuestDB.lua asks for what nobody else has)
---------------------------------------------------------------------------
local function Who(e)
  if type(e) ~= "table" then return nil end
  if e[1] == "n" and e[2] then return { { e[2] } } end
  if e[1] == "o" and e[2] then return { nil, { e[2] } } end
end
local places -- [npc or object] = { m, x, y }
local function Places()
  if places then return places end
  places = { n = {}, o = {} }
  for _, r in pairs(Store()) do
    if type(r) == "table" then
      for _, f in ipairs({ "s", "f" }) do
        local e = r[f]
        if type(e) == "table" and e[2] and e[3] and places[e[1]] then places[e[1]][e[2]] = { e[3], e[4], e[5] } end
      end
    end
  end
  return places
end
function R.Quest(id, field)
  local r = Rec(id)
  if not r then return nil end
  if field == "name" then return r.n
  elseif field == "questLevel" then return r.l
  elseif field == "requiredLevel" then return nil
  elseif field == "requiredRaces" then return r.side and (r.side == (UnitFactionGroup("player") or "Horde"):sub(1, 1) and 0 or 1099511627776) or nil
  elseif field == "startedBy" then return Who(r.s)
  elseif field == "finishedBy" then return Who(r.f)
  elseif field == "triggerEnd" and type(r.o) == "table" then
    -- every spot where something moved forward, as places to go
    local out = { "Where it went forward", {} }
    for _, e in pairs(r.o) do
      for _, p in ipairs(type(e) == "table" and e.p or {}) do
        out[2][-p[1]] = out[2][-p[1]] or {}
        table.insert(out[2][-p[1]], { p[2], p[3] })
      end
    end
    return next(out[2]) and out or nil
  end
end
-- what a quest gave one of your characters: choice = { { item, count }, ... }, given = { ... }, money; nil = not seen yet
function R.Rewards(id)
  local r = Rec(id)
  local w = r and type(r.w) == "table" and r.w
  if not w then return nil end
  return w.c or {}, w.g or {}, w.m
end
function R.Npc(id, field)
  if field == "spawns" then
    local p = Places().n[id]
    return p and { [-p[1]] = { { p[2], p[3] } } } or nil
  end
end
function R.Item() return nil end

-- spots seen for one objective of a quest (for the route: what the databases don't know) -> { { m, x, y }, ... }
function R.Spots(id, i)
  local r = Rec(id)
  local e = r and type(r.o) == "table" and r.o[i]
  return type(e) == "table" and e.p or nil
end

function R.Count()
  local n = 0
  for _ in pairs(Store()) do n = n + 1 end
  return n
end

local function Prune()
  local s, ids = Store(), {}
  for id, r in pairs(s) do
    if type(id) ~= "number" or type(r) ~= "table" then s[id] = nil else ids[#ids + 1] = id end
  end
  if #ids > MAX_QUESTS then
    table.sort(ids)
    for i = 1, #ids - MAX_QUESTS do s[ids[i]] = nil end -- the oldest content goes first
  end
end

function R:Init()
  NS.Safe("quest record", Prune)
  NS.On("QUEST_DETAIL", function()
    local id = GetQuestID and GetQuestID()
    if type(id) == "number" and id > 0 then
      NS.Safe("quest record", Mark, id, "s")
      NS.Safe("quest record", Rewards, id)
      R.detail = { id, GetTime() }
      C_Timer.After(1, function() if GetQuestID and GetQuestID() == id then NS.Safe("quest record", Rewards, id) end end)
    end
  end)
  NS.On("QUEST_ACCEPTED", function(a, b)
    local id = type(b) == "number" and b or a
    if type(id) ~= "number" then return end
    places = nil
    C_Timer.After(1, function() NS.Safe("quest record", FromLog, id) end)
  end)
  local function Ending()
    local id = GetQuestID and GetQuestID()
    if type(id) == "number" and id > 0 then NS.Safe("quest record", Mark, id, "f") places = nil end
  end
  NS.On("QUEST_COMPLETE", function()
    Ending()
    local id = GetQuestID and GetQuestID()
    if type(id) == "number" and id > 0 then
      NS.Safe("quest record", Rewards, id)
      C_Timer.After(1, function() if GetQuestID and GetQuestID() == id then NS.Safe("quest record", Rewards, id) end end)
    end
  end)
  NS.On("QUEST_PROGRESS", function()
    Ending()
    local id = GetQuestID and GetQuestID()
    if type(id) == "number" and id > 0 then
      NS.Safe("quest record", Needs, id)
      C_Timer.After(1, function() if GetQuestID and GetQuestID() == id then NS.Safe("quest record", Needs, id) end end)
    end
  end)
  NS.On("QUEST_LOG_UPDATE", function() NS.Debounce("quest record", 0.4, R.Look) end)
end
