-- Sunstone: character snapshot for the desktop helper.
-- WoW only writes addon data to disk on /reload or logout, so "/sun sync" saves a fresh
-- snapshot and reloads the UI (a couple of seconds) so the helper can read it.

local _, NS = ...
local S = NS.Module("Snapshot")
NS.Snapshot = S

local SLOT_NAMES = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2",
  [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand",
  [18] = "Ranged", [19] = "Tabard",
}

local function ItemLevel(link)
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    local ok, v = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and v then return v end
  end
  if GetDetailedItemLevelInfo then
    local ok, v = pcall(GetDetailedItemLevelInfo, link)
    if ok and v then return v end
  end
end

local function Gear()
  local out = {}
  for slot = 1, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local name, _, quality, _, reqLevel, _, _, _, equipLoc = NS.GetItemInfo(link)
      out[#out + 1] = {
        slot = slot, slotName = SLOT_NAMES[slot], id = GetInventoryItemID("player", slot),
        name = name or link:match("%[(.-)%]"), quality = quality, reqLevel = reqLevel,
        equipLoc = equipLoc, ilvl = ItemLevel(link), item = link:match("item:[%-%d:]+"),
      }
    end
  end
  return out
end

local function Bags()
  local counts = {}
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  for bag = 0, 4 do
    for slot = 1, (numSlots and numSlots(bag) or 0) do
      local id, count
      if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then id, count = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        if link then id, count = tonumber(link:match("item:(%d+)")), c end
      end
      if id then counts[id] = (counts[id] or 0) + (count or 1) end
    end
  end
  local out = {}
  for id, c in pairs(counts) do
    out[#out + 1] = { id = id, count = c, name = (NS.GetItemInfo(id)) }
  end
  return out
end

local function Skills()
  local out, seen = {}, {}
  local function add(name, rank, maxRank)
    if type(name) == "string" and name ~= "" and type(rank) == "number" and not seen[name] then
      seen[name] = true
      out[#out + 1] = { name = name, rank = rank, max = maxRank }
    end
  end
  -- the old skill list (weapon skills too)
  if GetNumSkillLines and GetSkillLineInfo then
    local ok, n = pcall(GetNumSkillLines)
    for i = 1, (ok and tonumber(n)) or 0 do
      local ok2, name, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
      if ok2 and not isHeader then add(name, rank, maxRank) end
    end
  end
  -- the profession book: in Forever the old list can come back empty, this one still has the professions
  if GetProfessions and GetProfessionInfo then
    local ok, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
    if ok then
      local list = { p1, p2, p3, p4, p5, p6 }
      for k = 1, 6 do
        if list[k] then
          local ok2, name, _, rank, maxRank = pcall(GetProfessionInfo, list[k])
          if ok2 then add(name, rank, maxRank) end
        end
      end
    end
  end
  return out
end

-- Merchant's Favor (Forever's profession currency, ID 3402) for the gear finder's recipe costs.
local FAVOR = 3402
local function Favor()
  local c = NS.Currency(FAVOR)
  return c and c.quantity
end

S.Skills = Skills

-- Your standing with the factions whose vendors sell gear (the list comes from the helper):
-- [factionID] = { s = 1 Hated ... 8 Exalted, v = how far into that rank, m = the rank's size }. Numbers only.
function S.Reputation()
  local out, n = {}, 0
  for _, fid in ipairs(NS.Factions()) do
    local st, v, size = NS.Standing(fid)
    if st then
      out[fid] = { s = st, v = math.max(0, math.floor(v or 0)), m = math.max(0, math.floor(size or 0)) }
      n = n + 1
    end
  end
  return n > 0 and out or nil
end

-- PvP in Forever: Honor (currency 1792) buys the gear; Rank Points (currency 3468, never spent, capped each
-- week) set your rank. Numbers only.
local HONOR, RANK_POINTS = 1792, 3468
function S.PvP()
  local h, rp = NS.Currency(HONOR), NS.Currency(RANK_POINTS)
  if not (h or rp) then return nil end
  local p = {}
  if h then p.honor, p.honorMax = h.quantity, h.max end
  if rp then p.rp, p.rpWeek, p.rpWeekMax, p.rpTotal = rp.quantity, rp.week, rp.weekMax, rp.total end
  if UnitPVPRank then -- the classic call, if this client still has it: the rank as a number
    local ok, id = pcall(UnitPVPRank, "player")
    if ok and type(id) == "number" and id > 0 and GetPVPRankInfo then
      local ok2, _, number = pcall(GetPVPRankInfo, id)
      if ok2 and type(number) == "number" then p.rank = number end
    end
  end
  return p
end

local function Quests()
  local out = {}
  local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
    or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
  for i = 1, n do
    local info = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID and info.questID > 0 then
      local q = { id = info.questID, title = info.title, level = info.level,
                  complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false, objectives = {} }
      -- what it pays (the helper's gold and XP plans use these)
      if GetQuestLogRewardMoney then
        local ok, m = pcall(GetQuestLogRewardMoney, info.questID)
        if ok and type(m) == "number" then q.money = m end
      end
      if GetQuestLogRewardXP then
        local ok, x = pcall(GetQuestLogRewardXP, info.questID)
        if ok and type(x) == "number" then q.xp = x end
      end
      for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
        q.objectives[#q.objectives + 1] = { text = o.text, done = o.finished, have = o.numFulfilled, need = o.numRequired, type = o.type }
      end
      out[#out + 1] = q
    end
  end
  return out
end

function S.Build()
  local s = { time = time(), version = NS.version }
  s.name, s.realm = UnitName("player"), GetRealmName()
  s.className, s.class = UnitClass("player")
  s.raceName, s.race = UnitRace("player")
  s.faction = UnitFactionGroup("player")
  s.level = UnitLevel("player")
  s.xp, s.xpMax = UnitXP("player"), UnitXPMax("player")
  s.restedXP = GetXPExhaustion and GetXPExhaustion() or 0
  s.money = GetMoney()
  s.favor = Favor()
  s.rep = S.Reputation()
  s.pvp = S.PvP()
  s.zone, s.subzone = GetRealZoneText(), GetSubZoneText()
  s.position = S.Position()
  local ranks, spent = NS.Talents.Read()
  if ranks then
    s.talents = ranks
    s.talentPointsSpent = spent
    s.talentPointsUnspent = math.max(0, s.level - 9) - spent
  end
  s.talentTree = NS.Talents.Tree()
  s.talentGoal = NS.TalentGoal and NS.TalentGoal() or nil
  local plan = NS.ActivePlan()
  if plan then
    s.talentPlan = plan.name
    s.talentPlanSteps = plan.steps
  end
  s.markers = #(NS.cdb.markers or {})
  s.skills = Skills()
  s.gear = Gear()
  s.bags = Bags()
  s.quests = Quests()
  if NS.Route and NS.Route.Describe then s.route = NS.Route.Describe() end
  local up = NS.db.upgrades and NS.db.upgrades[(s.name or "?") .. "-" .. (s.realm or "?")]
  if up then s.upgrades = up end
  s.completedQuests = S.Completed()
  return s
end

-- Where you are: the map library first, then the game's own map position, then the last spot we knew
-- (at logout or in some places neither can tell, and the helper's distances need a starting point).
function S.Position()
  local hbd = NS.HBD()
  if hbd then
    local ok, x, y, m = pcall(hbd.GetPlayerZonePosition, hbd)
    if ok and m and x and x > 0 then
      NS.cdb.lastPos = { mapID = m, x = x, y = y }
      return NS.cdb.lastPos
    end
  end
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
    local m = C_Map.GetBestMapForUnit("player")
    local ok, p = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if m and ok and p and p.GetXY then
      local x, y = p:GetXY()
      if type(x) == "number" and x > 0 then
        NS.cdb.lastPos = { mapID = m, x = x, y = y }
        return NS.cdb.lastPos
      end
    end
  end
  return NS.cdb.lastPos
end

-- Quests this character has turned in (the helper skips their rewards and counts the steps left in
-- a quest chain).
function S.Completed()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, t = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(t) == "table" then for _, id in ipairs(t) do ids[#ids + 1] = id end end
  end
  if #ids == 0 and GetQuestsCompleted then
    local ok, t = pcall(GetQuestsCompleted)
    if ok and type(t) == "table" then for id, done in pairs(t) do if done then ids[#ids + 1] = id end end end
  end
  if #ids == 0 and Questie and Questie.db and Questie.db.char and type(Questie.db.char.complete) == "table" then
    for id, done in pairs(Questie.db.char.complete) do if done then ids[#ids + 1] = id end end
  end
  table.sort(ids)
  while #ids > 6000 do table.remove(ids) end
  return ids
end

-- Where every zone sits in the world (from the map library), so the helper can measure real
-- distances between places in different zones. Built once per session; account-wide.
function S.MapRects()
  local hbd = NS.HBD()
  if not (hbd and type(hbd.mapData) == "table") then return end
  local out, n = {}, 0
  for id, d in pairs(hbd.mapData) do
    if type(id) == "number" and type(d) == "table" and (d.mapType == nil or d.mapType <= 3) then
      local ok, x0, y0, inst = pcall(hbd.GetWorldCoordinatesFromZone, hbd, 0, 0, id)
      local ok2, x1, y1 = pcall(hbd.GetWorldCoordinatesFromZone, hbd, 1, 1, id)
      if ok and ok2 and x0 and x1 and inst then
        out[id] = { inst, math.floor(x0 + 0.5), math.floor(y0 + 0.5), math.floor(x1 + 0.5), math.floor(y1 + 0.5) }
        n = n + 1
        if n >= 1500 then break end
      end
    end
  end
  if n > 0 then NS.db.mapRects = out end
end

-- At logout the game has already let go of most character data (money, XP, professions, gear, bags and
-- position read as 0 or empty), so a logout snapshot keeps those from the last full one.
local KEEP_TABLES = { "gear", "bags", "skills", "quests", "position", "talents", "completedQuests", "rep", "pvp" }
local KEEP_NUMBERS = { "money", "xp", "xpMax", "restedXP", "favor", "talentPointsSpent", "talentPointsUnspent" }
function S.Merge(s, old)
  if type(old) ~= "table" then return s end
  for _, f in ipairs(KEEP_TABLES) do
    if (s[f] == nil or (type(s[f]) == "table" and next(s[f]) == nil)) and type(old[f]) == "table" and next(old[f]) ~= nil then
      s[f] = old[f]
    end
  end
  for _, f in ipairs(KEEP_NUMBERS) do
    if (s[f] == nil or s[f] == 0) and type(old[f]) == "number" and old[f] > 0 then s[f] = old[f] end
  end
  if (s.zone == nil or s.zone == "") and old.zone then s.zone, s.subzone = old.zone, old.subzone end
  return s
end

-- the quest log's details (objectives, XP, level) read blank at logout: the last time they didn't is kept for that
function S.KeepQuests()
  local list = Quests()
  for _, q in ipairs(list) do if #q.objectives > 0 or (q.level or 0) > 0 then S.questLog = list return end end
end
local function FillQuests(s)
  local full = {}
  for _, q in ipairs(S.questLog or {}) do full[q.id] = q end
  for i, q in ipairs(s.quests or {}) do
    if (q.level or 0) == 0 and #(q.objectives or {}) == 0 and full[q.id] then s.quests[i] = full[q.id] end
  end
end

function S.Save(atLogout)
  local s = S.Build()
  if atLogout then FillQuests(s) end
  local key = (s.name or "?") .. "-" .. (s.realm or "?")
  if atLogout then s = S.Merge(s, NS.db.snapshots[key]) end
  NS.db.snapshots[key] = s
  NS.db.lastSnapshot = key
  if not S.rectsDone then
    S.rectsDone = true
    NS.Safe("map sizes", S.MapRects)
  end
  if NS.Auction and (not NS.Auction.updated or GetTime() - NS.Auction.updated > 300) then
    NS.Safe("auction", NS.Auction.Update)
  end
  return s
end

-- Keep a light snapshot on every logout too, so the helper is never far behind.
function S:Init()
  NS.On("QUEST_LOG_UPDATE", function() NS.Debounce("quest log kept", 20, S.KeepQuests) end)
  NS.On("PLAYER_LOGOUT", function() NS.Safe("snapshot", S.Save, true) end)
  -- remember where you are as you move between areas, so a logout snapshot still has a position
  for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do
    NS.On(ev, function() C_Timer.After(1, function() NS.Safe("position", S.Position) end) end)
  end
end

NS.Command("sync", "- send your character to the desktop helper (reloads the UI)", function()
  NS.Safe("snapshot", S.Save)
  -- straight from your typed command: the game only allows a reload that comes from you
  if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end)
