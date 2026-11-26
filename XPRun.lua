-- Sunstone: XP runs (the XP & Route tab). With picking up switched on, the route isn't only what's in your log: the quests near you that pay
-- best for the extra time they take are picked up, done and handed in on the same round, in the shortest order. Which ones is yours to say:
-- every quest has On / Off. New ones that open up as you hand things in join by themselves. Information only: it accepts nothing.

local _, NS = ...
local X = NS.Module("XPRun")
NS.XPRun = X
local E, R = NS.Engine, NS.Route
local C = NS.C
local I = "Interface\\Icons\\"

X.MAX = 10          -- quests to pick up at once
X.FLOOR = 0.75      -- one has to pay at least this share of what plain killing pays for the time
X.LENGTHS = { 30, 60, 90, 150 } -- minutes a round may take
X.QUICK = 150       -- seconds: one this quick is worth it even when the round is full
X.FAR = 2200        -- yards: that far from where it was chosen, the choice is made afresh
local FRESH = 420   -- seconds the list of quests near you is good for
local DETOUR = 1.3  -- walking goes around things
local RUN = 7       -- yards a second

local function List(t) return type(t) == "table" and t or {} end
local function Cfg() return NS.cdb.route end
function X.On() return Cfg().run == true end
local function Picks() local c = Cfg(); if type(c.picks) ~= "table" then c.picks = {} end return c.picks end
local function Set(key) local c = Cfg(); if type(c[key]) ~= "table" then c[key] = {} end return c[key] end
function X.Want(qid) return List(Cfg().wantPick)[qid] == true end
function X.Never(qid) return List(Cfg().noPick)[qid] == true end

local function Done(qid) return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) end
local function LogIds() local out = {} for _, q in ipairs(R.Quests()) do out[q.id] = q end return out end

-- The quests to pick up now: the ones you switched on yourself, then the run's own. Never one that's in the log or done.
function X.List()
  local out, seen, log = {}, {}, LogIds()
  local function Add(qid)
    if type(qid) == "number" and not seen[qid] and not log[qid] and not Done(qid) then seen[qid] = true; out[#out + 1] = qid end
  end
  local mine = {}
  for qid, on in pairs(List(Cfg().wantPick)) do if on then mine[#mine + 1] = qid end end
  table.sort(mine)
  for _, qid in ipairs(mine) do Add(qid) end
  if X.On() then for _, qid in ipairs(Picks()) do if not X.Never(qid) then Add(qid) end end end
  return out
end
function X.Picked(qid)
  for _, id in ipairs(X.List()) do if id == qid then return true end end
  return false
end
-- A quest in the log belongs to the run unless you switched it off (elite ones and far ones stay out until you switch them on)
function X.InRun(qid)
  if not X.On() then return false end
  local t = Cfg().runLog
  return type(t) ~= "table" or t[qid] == true
end
function X.Key() -- what the route's plan depends on
  return (X.On() and "run" or "") .. table.concat(X.List(), ",")
end

---------------------------------------------------------------------------
-- Which ones: the XP they give for the extra time they take on your round (a background job)
---------------------------------------------------------------------------
local function Dist(a, b) return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) end
local function Walk(a, b) return Dist(a, b) * DETOUR / RUN end

-- The cheapest places in a round (list of spots, 1 = where you are) for a quest's stops, in the order they have to come
-- -> extra seconds, where: { { position, spot }, ... }
local function Insert(seq, nodes)
  local round, extra, from = {}, 0, 1
  for k = 1, #seq do round[k] = seq[k] end
  local function Put(nd, after)
    local bc, bp, bs
    for _, c in ipairs(nd.cands) do
      for p = after, #round do
        local a, b = round[p], round[p + 1]
        local t = Walk(a, c) + (b and (Walk(c, b) - Walk(a, b)) or 0)
        if not bs or t < bs then bc, bp, bs = c, p, t end
      end
    end
    if not bc then return nil end
    table.insert(round, bp + 1, bc)
    extra = extra + bs + (nd.work or 0)
    return bp + 1
  end
  local last = 1
  for _, nd in ipairs(nodes) do
    if nd.kind == "pickup" then from = Put(nd, 1); last = from or 1
    elseif nd.kind == "obj" then
      local p = Put(nd, from or 1)
      if p then last = p <= last and last + 1 or p end
    else Put(nd, last) end
  end
  return extra, round
end
X.Insert = Insert

local function LogRoom()
  local most = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 20
  local n = 0
  for _ in pairs(LogIds()) do n = n + 1 end
  return math.max(0, (tonumber(most) or 20) - n)
end
X.LogRoom = LogRoom

local function Fresh()
  local c = E.cache.xp
  if not c or c.level ~= UnitLevel("player") or time() - (c.t or 0) > FRESH or c.stale then return false end
  local y = c.from and E.Yards(c.from)
  return not y or y <= 900
end

function X.Ready() return E.cache.xp ~= nil end
function X.Busy() return E.Busy("xp quests") or E.Busy("xp run") end

-- killing at your level: XP a second, for what's not worth the walk
local function KillRate()
  local L = UnitLevel("player") or 1
  local pace = NS.Farm and NS.Farm.Pace and NS.Farm.Pace() or 60
  return E.KillXP(L, L) / math.max(20, pace)
end

function X.Choose(afresh)
  if not X.On() or X.Busy() then return end
  if not Fresh() then
    E.FindQuests(function(res)
      res.from = E.Here()
      NS.Safe("xp run", X.Choose, afresh)
      if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
    end)
    return
  end
  local here = R.HereNow and R.HereNow()
  if not here then return end
  local rows = E.cache.xp.rows or {}
  E.Job("xp run", function()
    local log, L = LogIds(), UnitLevel("player") or 1
    -- what's in the log already: worth doing on this round?
    local mine = {}
    for _, r in ipairs(rows) do
      if r.inLog and not r.elite and r.mins <= 45 then mine[r.id] = true end
    end
    for id, q in pairs(log) do if R.Finished(q) then mine[id] = true end end
    -- the round without pickups, in its order
    local seq = { { wx = here.wx, wy = here.wy } }
    for _, s in ipairs(R.stops or {}) do
      local qid = s.node.quest and s.node.quest.id
      if not qid or log[qid] then seq[#seq + 1] = s end
    end
    local function Nodes(id)
      local nodes, e, u = {}, {}, {}
      local ok = R.QuestNodes(id, here, nodes, e, u)
      if ok and #e == 0 and #u == 0 and #nodes >= 2 then return nodes end
    end
    local cands, byId = {}, {}
    for _, r in ipairs(rows) do
      E.Yield()
      if not r.inLog and not r.elite and not X.Never(r.id) and not log[r.id] and #cands < 60 then
        local nodes = Nodes(r.id)
        if nodes then
          local kills = 0
          for _, nd in ipairs(nodes) do kills = kills + (nd.kills or 0) end
          local c = { id = r.id, nodes = nodes, xp = r.xp + kills * E.KillXP(L, math.min(L, r.level)), quest = r.xp }
          cands[#cands + 1] = c
          byId[r.id] = c
        end
      end
    end
    local out, room = {}, math.min(X.MAX, LogRoom())
    local total, most = 0, X.Length() * 60 -- the time the round takes as it stands
    for k = 2, #seq do total = total + Walk(seq[k - 1], seq[k]) + ((seq[k].node and seq[k].node.work) or 0) end
    local function Take(c, extra, round)
      out[#out + 1] = c.id
      c.taken, c.extra, seq = true, extra, round
      total = total + extra
    end
    -- the ones you asked for come first, then the ones already chosen (a plan that keeps changing its mind is no plan)
    for qid in pairs(List(Cfg().wantPick)) do
      local c = byId[qid]
      if c and not c.taken then local ex, ro = Insert(seq, c.nodes); c.taken, c.extra, seq, total = true, ex, ro, total + ex end
    end
    if not afresh then
      for _, qid in ipairs(Picks()) do
        local c = byId[qid]
        if c and not c.taken and #out < room then local ex, ro = Insert(seq, c.nodes); Take(c, ex, ro) end
      end
    end
    local floor = KillRate() * X.FLOOR
    while #out < room do
      local bc, be, br, bv
      for _, c in ipairs(cands) do
        if not c.taken then
          E.Yield()
          local extra, round = Insert(seq, c.nodes)
          local v = c.xp / math.max(20, extra)
          if (total + extra <= most or extra <= X.QUICK) and (not bv or v > bv) then bc, be, br, bv = c, extra, round, v end
        end
      end
      if not bc or bv < floor then break end
      Take(bc, be, br)
    end
    local extra = {}
    for _, c in ipairs(cands) do if c.extra then extra[c.id] = c.extra end end
    return { picks = out, log = mine, extra = extra, at = here }
  end, function(res)
    if not res or not X.On() then return end
    Cfg().picks, Cfg().runLog = res.picks, res.log
    X.extra, X.at, X.chosenAt, X.level = res.extra, res.at, GetTime(), UnitLevel("player")
    if Cfg().enabled then R.sig = nil; R.Compute(true) end
    R.UpdatePanel()
    if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
  end)
end

-- something changed that opens or closes quests: look again, soon
function X.Again(delay, afresh)
  if not X.On() then return end
  NS.Debounce("xp run", delay or 4, function()
    if E.cache.xp then E.cache.xp.stale = true end
    NS.Safe("xp run", X.Choose, afresh)
  end)
end

---------------------------------------------------------------------------
-- Switches
---------------------------------------------------------------------------
local function Changed()
  R.sig = nil
  if Cfg().enabled then R.Compute(true) end
  R.UpdatePanel()
end
function X.Length() return tonumber(Cfg().runMins) or 60 end
function X.NextLength()
  local now, pick = X.Length(), X.LENGTHS[1]
  for k, m in ipairs(X.LENGTHS) do if m == now then pick = X.LENGTHS[k % #X.LENGTHS + 1] end end
  Cfg().runMins = pick
  if X.On() then X.Choose(true) end
  R.UpdatePanel()
  if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
end
function X.SetOn(on)
  Cfg().run = on and true or false
  if on then
    if type(Cfg().focus) == "table" then R.Focus(nil) end
    if not Cfg().enabled then R.Enable(true) else Changed() end
    X.Choose(true)
  else
    Changed()
  end
end
function X.Add(qid) -- pick this one up, whether the run is on or not
  Set("noPick")[qid] = nil
  Set("wantPick")[qid] = true
  if type(Cfg().off) == "table" then Cfg().off[qid] = nil end
  if not Cfg().enabled then R.Enable(true) else Changed() end
end
function X.Drop(qid)
  Set("wantPick")[qid] = nil
  Set("noPick")[qid] = true
  Changed()
  if X.On() then X.Choose() end
end
function X.Reset() Cfg().noPick, Cfg().wantPick = nil, nil; Changed(); X.Choose(true) end

---------------------------------------------------------------------------
-- What it comes to
---------------------------------------------------------------------------
function X.Totals() -- stops, minutes, quest XP, kill XP
  local xp, kills, L = 0, 0, UnitLevel("player") or 1
  for _, s in ipairs(R.stops or {}) do
    local nd = s.node
    if nd.kind == "turnin" then xp = xp + (nd.xp or 0) end
    if nd.kills then kills = kills + nd.kills * E.KillXP(L, math.min(L, nd.ql or L)) end
  end
  return #(R.stops or {}), (R.eta or 0) / 60, xp, kills
end
local function Comma(n)
  n = math.floor(n + 0.5)
  return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end
function X.Short() -- for the list
  local n, mins, xp, kills = X.Totals()
  if n == 0 then return nil end
  return string.format("%d stop%s, %d min%s", n, n == 1 and "" or "s", math.floor(mins + 0.5), xp + kills > 0 and (", " .. Comma(xp + kills) .. " XP") or "")
end
function X.Summary()
  local n, mins, xp, kills = X.Totals()
  if n == 0 then return nil end
  local out = string.format("%d stop%s, about %d min", n, n == 1 and "" or "s", math.floor(mins + 0.5))
  if xp > 0 then
    out = out .. string.format(": %s XP from quests%s", Comma(xp), kills >= 50 and (" and about " .. Comma(kills) .. " from kills") or "")
    if mins >= 2 then out = out .. string.format(", about %s an hour", Comma((xp + kills) / mins * 60)) end
    local need = UnitXPMax and UnitXPMax("player")
    if type(need) == "number" and need > 0 then out = out .. string.format(" (%d%% of a level)", (xp + kills) / need * 100 + 0.5) end
  end
  return out .. "."
end

---------------------------------------------------------------------------
-- The page: the round on a map, and every stop
---------------------------------------------------------------------------
X.ICON = { pickup = "Interface\\GossipFrame\\AvailableQuestIcon", turnin = "Interface\\GossipFrame\\ActiveQuestIcon", sell = I .. "INV_Misc_Coin_01", travel = I .. "INV_Misc_Map_01", corpse = I .. "INV_Misc_Bone_HumanSkull_01" }
function X.StopIcon(s)
  local k = s.node.kind
  if X.ICON[k] then return X.ICON[k] end
  return (s.node.kills or 0) > 0 and I .. "Ability_DualWield" or I .. "INV_Misc_Bag_08"
end
local STATE = { pickup = "pick", turnin = "hand", obj = "do", sell = "done" }
function X.Map()
  local stops = R.stops or {}
  if #stops == 0 then return nil end
  local here = E.Here()
  local pins, path = {}, {}
  if here then path[1] = { m = here.m, x = here.x, y = here.y, wx = here.wx, wy = here.wy } end
  for i, s in ipairs(stops) do
    pins[i] = { n = i, m = s.m, x = s.x, y = s.y, t = X.Text(s), d = s.node.kind == "obj" and s.node.quest.title or nil, state = i == 1 and "next" or STATE[s.node.kind] or "do" }
    path[#path + 1] = { m = s.m, x = s.x, y = s.y, wx = s.wx, wy = s.wy }
  end
  local m = stops[1].m
  return { m = m, name = NS.Travel and NS.Travel.MapName and NS.Travel.MapName(m) or "", pins = pins, path = path, title = "Your round" }
end
function X.Text(s)
  local q = s.node.quest
  if s.node.kind == "sell" then return "Sell at a merchant" end
  return (s.node.kind == "turnin" and "Turn in: " .. (q.title or "?")) or (s.node.kind == "pickup" and "Pick up: " .. (q.title or "?")) or s.node.label
end
function X.Page()
  local rows = {}
  local on, route = X.On(), Cfg().enabled
  rows[1] = { t = on and "Picking up quests: on" or "Picking up quests: off", tex = X.ICON.pickup, ring = on and "good" or "warn", actLabel = on and "On" or "Off", act = function() X.SetOn(not on) end,
              d = on and "The route picks up, does and hands in the quests that pay best for the extra time, in one round with yours."
                or "The route covers the quests in your log that you switched on, and any you switch on below." }
  if on then
    rows[#rows + 1] = { t = string.format("A round of about %d minutes", X.Length()), d = "How long one may get before no more quests are added (quick ones on the way still are).", tex = I .. "INV_Misc_PocketWatch_01", still = true,
                        actLabel = "Change", act = X.NextLength }
  end
  local sum = route and X.Summary()
  if sum then rows[#rows + 1] = { t = "This round", d = sum, tex = I .. "INV_Misc_Map_01", still = true } end
  if X.Busy() then rows[#rows + 1] = { t = "Looking for quests around here...", d = "A few seconds.", dim = true, still = true } end
  local map = route and X.Map()
  if map then rows[#rows + 1] = { zmap = map } end
  if route and #(R.stops or {}) > 0 then
    rows[#rows + 1] = { h = "In this order" }
    for i, s in ipairs(R.stops) do
      local bits = {}
      if s.node.kind == "obj" then bits[1] = s.node.quest.title end
      if s.node.kind == "turnin" and (s.node.xp or 0) > 0 then bits[1] = Comma(s.node.xp) .. " XP" end
      local t = s.secs and s.secs >= 50 and math.floor(s.secs / 60 + 0.5)
      if t then bits[#bits + 1] = s.fly and string.format("fly part of the way, %d min", t) or string.format("%d min walk", t) end
      if s.node.work and s.node.work >= 60 then bits[#bits + 1] = string.format("%d min there", math.floor(s.node.work / 60 + 0.5)) end
      local qid = s.node.quest and s.node.quest.id
      rows[#rows + 1] = { t = i .. ". " .. X.Text(s), d = #bits > 0 and table.concat(bits, "  ·  ") or nil, tex = X.StopIcon(s), m = s.m, x = s.x, y = s.y, hot = i == 1 or nil,
                          actLabel = "Zoom in", act = NS.Atlas and function() NS.Atlas.Focus(s.m, s.x, s.y) end or nil,
                          page = qid and NS.QuestFind and function() return NS.QuestFind.Page(qid) end or nil }
    end
  elseif not route then
    rows[#rows + 1] = { t = "The route is off", d = "Switching picking up on starts it. Route on (above) starts it with just the quests in your log.", still = true }
  end
  rows[#rows + 1] = { t = "How quests are chosen", dim = true, still = true,
    d = "By the XP they give, kills included, for the extra minutes they add to your round: walking, the work, and the way back. Each has to beat plain killing, more or less. Up to " .. X.MAX .. " at a time and no more than your log has room for; elite and "
      .. "dungeon quests only if you switch them on yourself. When you hand something in and a new quest opens up, it's looked at too. Creature XP on its own is on the Grind tab." }
  return { title = "Your round", icon = I .. "INV_Misc_Map_01", rows = rows, sub = "Pick up, do, hand in: one loop" }
end

-- The list's rows: what's picked up on the way, what else could be, with On / Off
function X.Rows(rows)
  local c = E.cache.xp
  if not c and not E.Busy("xp quests") then
    E.FindQuests(function(res) res.from = E.Here(); if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end end)
  elseif c and not Fresh() and not X.Busy() and (not X.lookedAt or GetTime() - X.lookedAt > 30) then
    X.lookedAt = GetTime()
    if X.On() then X.Choose() else E.FindQuests(function(res) res.from = E.Here(); if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end end) end
  end
  local info = {}
  for _, r in ipairs(c and c.rows or {}) do info[r.id] = r end
  for _, r in ipairs(c and c.other or {}) do info[r.id] = info[r.id] or r end
  local function Row(qid, on)
    local r = info[qid] or {}
    local bits = {}
    if r.xp then bits[#bits + 1] = Comma(r.xp) .. " XP" end
    local ex = on and X.extra and X.extra[qid]
    if ex then bits[#bits + 1] = string.format("%d min more", math.max(1, math.floor(ex / 60 + 0.5)))
    elseif r.xp and r.mins then bits[#bits + 1] = string.format("about %d min", math.floor(r.mins + 0.5)) end
    if r.elite then bits[#bits + 1] = "elite" end
    if r.who then bits[#bits + 1] = r.who end
    local lv = r.level or E.QuestLevel(qid)
    return { t = string.format("%s (%d)", r.name or E.QuestName(qid), lv or 0), d = table.concat(bits, "  ·  "), key = "xq" .. qid, tex = X.ICON.pickup, ring = on and "good" or "warn", dim = not on or nil,
             actLabel = on and "On" or "Off", act = function() if on then X.Drop(qid) else X.Add(qid) end end, page = NS.Lists and NS.Lists.QuestPage and r.name and function() return NS.Lists.QuestPage(r) end
               or (NS.QuestFind and function() return NS.QuestFind.Page(qid) end) or nil }
  end
  local list, inList = X.List(), {}
  if #list > 0 then
    rows[#rows + 1] = { h = string.format("Picked up on the way (%d)", #list) }
    for _, qid in ipairs(list) do inList[qid] = true; rows[#rows + 1] = Row(qid, true) end
  end
  local more, n = {}, 0
  local log = LogIds()
  for _, r in ipairs(c and c.rows or {}) do
    if not r.inLog and not inList[r.id] and not log[r.id] then more[#more + 1] = r.id end
  end
  if #more > 0 then
    rows[#rows + 1] = { h = "More you could pick up, best XP for the time first" }
    for _, qid in ipairs(more) do
      n = n + 1
      if n > 16 then break end
      rows[#rows + 1] = Row(qid, false)
    end
  end
  local other = {}
  for _, r in ipairs(c and c.other or {}) do if not inList[r.id] and not log[r.id] and #other < 10 then other[#other + 1] = r.id end end
  if #other > 0 then
    rows[#rows + 1] = { h = "Near you, XP not recorded yet" }
    for _, qid in ipairs(other) do rows[#rows + 1] = Row(qid, false) end
  end
  if not c then rows[#rows + 1] = { t = "Looking for quests near you...", d = "A few seconds the first time.", dim = true, key = "status", still = true }
  elseif #list == 0 and #more == 0 and #other == 0 then
    rows[#rows + 1] = { t = "No more quests for your level within reach", d = "Within about 25 minutes of you. Try again in another zone.", still = true }
  end
  if next(List(Cfg().noPick)) or next(List(Cfg().wantPick)) then
    rows[#rows + 1] = { t = "Your own On and Off", d = "Forget them and let Sunstone choose again.", still = true, key = "xqreset", actLabel = "Forget", act = X.Reset }
  end
end

function X:Init()
  -- a set added from the old XP tab becomes quests you switched on
  local goal = NS.cdb.goal
  if type(goal) == "table" and goal.name == "XP plan" and type(goal.quests) == "table" then
    for _, qid in ipairs(goal.quests) do if type(qid) == "number" then Set("wantPick")[qid] = true end end
    NS.cdb.goal = nil
  end
  NS.On("QUEST_ACCEPTED", function(a, b)
    local qid = (type(b) == "number" and b > 0) and b or a
    local want = Cfg().wantPick
    if type(want) == "table" and type(qid) == "number" then want[qid] = nil end
  end)
  NS.On("QUEST_TURNED_IN", function() X.Again(5) end)
  NS.On("QUEST_REMOVED", function() X.Again(8) end)
  NS.On("PLAYER_LEVEL_UP", function() X.Again(6, true) end)
  C_Timer.NewTicker(20, function()
    if not (X.On() and Cfg().enabled) or X.Busy() or (InCombatLockdown and InCombatLockdown()) then return end
    local now = R.HereNow and R.HereNow()
    if not now then return end
    if not X.at or now.inst ~= X.at.inst or Dist(now, X.at) > X.FAR then NS.Safe("xp run", X.Choose, X.at ~= nil) end
  end)
end

NS.Command("xp", "[on|off] - an XP run: the route picks up, does and hands in the quests that pay best, in one round", function(rest)
  rest = (rest or ""):lower()
  local on = rest == "on" or (rest ~= "off" and not X.On())
  X.SetOn(on)
  NS.Print(on and "XP run on: quests worth the time are picked up on the way." or "XP run off: the route covers the quests in your log.")
end)
