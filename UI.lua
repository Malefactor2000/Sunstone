-- Sunstone: the in-game window and the minimap button.
-- Your gear and its upgrades, XP quests, grind spots, gold, professions, factions (reputation, Library Books, Honor),
-- talents and the route. Tabs along the top; pick on the left, read everything about it on the right. Everything is
-- worked out in the game (Engine.lua) from a character's first login; the desktop helper is optional.
-- On each row: Map = a star on your map, Go = the arrow. Rows about an item show its icon, and hovering them
-- shows the game's own tooltip for that item.
-- Left-click the minimap button (or type /sun) to open it; right-click turns the quest route on/off.

local _, NS = ...
local W = NS.Module("Window")
NS.Window = W

local I = "Interface\\Icons\\"
local TABS = { -- key, name, icon (game icons, so you can see at a glance which page you're on)
  { "guide", "Guide", I .. "INV_Misc_QuestionMark" },
  { "upgrades", "Gear", I .. "INV_Chest_Chain_05" }, { "route", "XP & Route", I .. "INV_Misc_Map_01" },
  { "grind", "Grind", I .. "INV_Sword_04" }, { "gold", "Gold", I .. "INV_Misc_Coin_01" },
  { "prof", "Professions", I .. "Trade_BlackSmithing" }, { "factions", "Factions", I .. "INV_Jewelry_Ring_03" },
  { "dungeons", "Dungeons", I .. "INV_Misc_Key_10" },
  { "collect", "Pets & Mounts", I .. "INV_Box_PetCarrier_01" },
  { "class", "Class", I .. "INV_Misc_Book_09" }, { "talents", "Talents", I .. "INV_Misc_Book_11" },
  { "quests", "Quests", I .. "INV_Misc_Note_01" },
}
-- The Quests tab's order for the route: what the arrow and the map point you to next
local OPTIMIZE = {
  { "path", "Pathing", "Quickest way round, handing in as you go" },
  { "xp", "XP", "Most XP first" },
  { "rewards", "Rewards", "Gear upgrades and money first" },
  { "all", "Balanced", "XP and rewards together" },
}
local ICON = 24 -- item icon size; it sits in a slightly larger rounded well
local C = NS.C
-- an item's quality, in quiet versions of the game's colours (nothing that glares)
local QUALITY = { [0] = C.dim, [2] = { 0.42, 0.62, 0.34 }, [3] = { 0.40, 0.54, 0.74 }, [4] = { 0.60, 0.46, 0.72 }, [5] = { 0.80, 0.50, 0.22 } }

---------------------------------------------------------------------------
-- Lists from the desktop helper (checked: only short text and numbers are used)
---------------------------------------------------------------------------
local function Results()
  local inbox = SunstoneInbox
  local r = type(inbox) == "table" and type(inbox.results) == "table" and inbox.results[NS.CharKey()]
  return type(r) == "table" and r or nil
end

local function ValidPos(r)
  return type(r.m) == "number" and type(r.x) == "number" and type(r.y) == "number"
    and r.x >= 0 and r.x <= 1 and r.y >= 0 and r.y <= 1
end

local function Rows(list, limit)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, r in ipairs(list) do
    if #out >= (limit or 30) then break end
    if type(r) == "table" and (type(r.t) == "string" or type(r.h) == "string") then
      local row = { t = r.t and NS.Clean(r.t, 140), h = r.h and NS.Clean(r.h, 80),
                    d = type(r.d) == "string" and NS.Clean(r.d, 420) or nil }
      if ValidPos(r) then row.m, row.x, row.y = r.m, r.x, r.y end
      -- the item (its icon and its real tooltip): a whole number in the item ID range, nothing else
      if type(r.i) == "number" and r.i > 0 and r.i < 10000000 and r.i == math.floor(r.i) then row.i = r.i end
      if type(r.s) == "table" then -- the steps it takes (shown when the row is clicked)
        local steps = {}
        for _, x in ipairs(r.s) do
          if type(x) == "string" and #steps < 24 then steps[#steps + 1] = NS.Clean(x, 260) end
        end
        if #steps > 0 then row.s = steps end
      end
      out[#out + 1] = row
    end
  end
  return out
end

W.Rows = Rows -- (for the tests)

local function QuestSet(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, q in ipairs(list) do
    if type(q) == "number" and q > 0 and q < 10000000 and #out < 20 then out[#out + 1] = q end
  end
  return out
end

---------------------------------------------------------------------------
-- Live bits: distance from you, the talent plan, the route
---------------------------------------------------------------------------
local function Yards(row)
  local hbd = NS.HBD()
  if not (hbd and row.m) then return nil end
  local px, py, pi = hbd:GetPlayerWorldPosition()
  local ok, wx, wy, wi = pcall(hbd.GetWorldCoordinatesFromZone, hbd, row.x, row.y, row.m)
  if not (px and ok and wx and pi == wi) then return nil end
  return math.floor(math.sqrt((px - wx) ^ 2 + (py - wy) ^ 2) + 0.5)
end

-- What the class trainer can teach you now, and at your next levels (Data.lua: the client's own spell list)
local function TrainerSpells(rows)
  local _, class = UnitClass("player")
  local list = NS.Engine and NS.Engine.Data().spells[class or ""]
  if not list or not (IsPlayerSpell or IsSpellKnown) then return rows end
  local level = UnitLevel("player")
  local function Known(id)
    for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false }) do
      if fn then
        local ok, v = pcall(fn, id)
        if ok and v then return true end
      end
    end
    return false
  end
  local now, soon = {}, {}
  for _, s in ipairs(list) do
    if s[5] == 0 and s[6] == 0 then -- (race and talent spells are left out)
      if s[1] <= level and s[1] > level - 12 and not Known(s[2]) then now[#now + 1] = s
      elseif s[1] > level and s[1] <= level + 4 then soon[#soon + 1] = s end
    end
  end
  local function Add(head, spells, n)
    if #spells == 0 then return end
    rows[#rows + 1] = { h = head }
    for k = 1, math.min(#spells, n) do
      local s = spells[k]
      rows[#rows + 1] = { t = s[3] .. (s[4] > 0 and (" (rank " .. s[4] .. ")") or ""), still = true,
                          d = "Level " .. s[1] .. (s[7] ~= "" and (", from a quest: " .. s[7]) or ""),
                          tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s[2]) or (GetSpellTexture and GetSpellTexture(s[2])) or nil }
    end
  end
  Add("Your class trainer teaches now", now, 8)
  Add("From your class trainer soon", soon, 6)
  return rows
end

local function TalentRows()
  local rows = {}
  local plan = NS.ActivePlan and NS.ActivePlan()
  local st = plan and NS.Talents and NS.Talents.Status and NS.Talents.Status()
  if not st then
    local className = UnitClass("player") or "this class"
    if not plan then
      rows[1] = { t = string.format("No %s plan for %s yet", NS.GoalLabel(NS.TalentGoal()), className),
                  d = "Pick another goal above. The goal is saved for this character." }
    else
      rows[1] = { t = "Can't read your talents right now", d = "Try again in a moment." }
    end
    return TrainerSpells(rows)
  end
  rows[#rows + 1] = { t = "Plan: " .. (plan.name or "?"), d = plan.why }
  rows[#rows + 1] = { h = st.unspent > 0 and string.format("%d point%s to spend", st.unspent, st.unspent == 1 and "" or "s")
                      or "All points spent" }
  for i, m in ipairs(st.missing) do
    if i > math.max(st.unspent, 1) then break end
    rows[#rows + 1] = { t = string.format("%s, rank %d", m.name, m.rank), d = (m.note and (m.note .. " ") or "") .. "(level " .. m.level .. ")" }
  end
  if #st.offplan > 0 then
    local names = {}
    for _, o in ipairs(st.offplan) do names[#names + 1] = string.format("%s %d (plan: %d)", o.key, o.have, o.planned) end
    rows[#rows + 1] = { t = "Off the plan", d = table.concat(names, ", ")
      .. ". To follow this plan, reset your talents at your class trainer, then spend them as shown here." }
  end
  if #st.upcoming > 0 then
    rows[#rows + 1] = { h = "Coming up" }
    for _, u in ipairs(st.upcoming) do
      rows[#rows + 1] = { t = string.format("Level %d: %s %d", u.level, u.name, u.rank), d = u.note }
    end
  end
  return TrainerSpells(rows)
end

local function StopText(s)
  local q = s.node.quest
  if s.node.kind == "sell" then return "Sell at a merchant" .. (s.who and " (" .. s.who .. ")" or "") end
  return (s.node.kind == "turnin" and "Turn in: " .. (q.title or "?"))
    or (s.node.kind == "pickup" and "Pick up: " .. (q.title or "?")) or s.node.label
end

-- The route's details live here (it has no window of its own): next stop, then every stop in order.
-- The route itself stays on the map, minimap and arrow until Route off, whatever windows are open or closed.
local function Coins(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return string.format("%dg %02ds", g, s) end
  return s > 0 and string.format("%ds %02dc", s, k) or string.format("%dc", k)
end

-- The Quests tab: every quest in your log with what it gives, On/Off for the route, and "Only this" (a route for
-- just that quest and the rest of its chain). The order (Pathing / XP / Rewards / All) is the bar above.
local function QuestRows()
  local rows = {}
  local R = NS.Route
  if not R then return rows end
  local quests = R.Quests and R.Quests() or {}
  local focus = R.FocusID and R.FocusID()
  if not NS.cdb.route.enabled then
    rows[#rows + 1] = { t = "The route is off",
                        d = "Switch quests On here, then Route on (Route tab). Only this starts a route for one quest "
                          .. "straight away." }
  end
  local f = NS.cdb.route.focus
  if focus and type(f) == "table" then
    rows[#rows + 1] = { t = "Routing only: " .. (f.title or "one quest"), hot = true,
                        d = "When you hand it in, the route moves on to the next quest of its chain. Clear goes back to "
                          .. "the quests you switched On.",
                        actLabel = "Clear", act = function() R.Focus(nil) end }
  end
  if #quests == 0 then
    rows[#rows + 1] = { t = "No quests in your log", d = "" }
    if NS.QuestFind then NS.QuestFind.IdeaRows(rows) end
    return rows
  end
  local on = 0
  for _, q in ipairs(quests) do if R.OnRoute and R.OnRoute(q) then on = on + 1 end end
  rows[#rows + 1] = { t = "Every quest", d = string.format("%d of %d on the route. A finished quest is handed in on the way even if it isn't switched on.", on, #quests),
                      actLabel = "All on", act = function() R.SetAll(true) end,
                      act2Label = "All off", act2 = function() R.SetAll(false) end }
  local auto = R.AutoNew and R.AutoNew()
  rows[#rows + 1] = { t = "New quests", d = auto and "A quest you pick up joins the route by itself."
                        or "A quest you pick up stays Off until you switch it On here.",
                      ring = auto and "good" or "warn", actLabel = auto and "On" or "Off",
                      act = function() R.SetAutoNew(not auto) end }
  for _, q in ipairs(quests) do
    local left, total = 0, 0
    for _, o in ipairs(q.objectives or {}) do
      total = total + 1
      if not o.finished then left = left + 1 end
    end
    local bits = { q.failed and "failed" or (q.complete or (total > 0 and left == 0)) and "ready to turn in"
      or total == 0 and "go and talk to whoever it names" or string.format("%d of %d left", left, total) }
    local v = R.QuestValue and R.QuestValue(q.id) or {}
    if (v.xp or 0) > 0 then bits[#bits + 1] = BreakUpLargeNumbers and BreakUpLargeNumbers(v.xp) .. " XP" or (v.xp .. " XP") end
    if (v.money or 0) > 0 then bits[#bits + 1] = Coins(v.money) end
    if v.up then bits[#bits + 1] = string.format("upgrade: %s (+%.1f)", v.up.name or "?", v.up.gain or 0) end
    local qid, off = q.id, R.Excluded and R.Excluded(q.id)
    rows[#rows + 1] = { t = (q.title or "?") .. (q.level and ("  (" .. q.level .. ")") or ""), d = table.concat(bits, "  ·  "),
                        dim = off and focus ~= qid, hot = focus == qid, ring = off and "warn" or "good", key = "ql" .. qid,
                        page = NS.QuestFind and function() return NS.QuestFind.Page(qid) end or nil,
                        actLabel = off and "Off" or "On", act = function() R.Toggle(qid) end,
                        act2Label = focus == qid and "Routing" or "Only this",
                        act2 = function() if focus ~= qid then R.Focus(qid) end end }
  end
  if NS.QuestFind then NS.QuestFind.IdeaRows(rows) end
  return rows
end

local function RouteRows()
  local rows = {}
  local R = NS.Route
  local X = NS.XPRun
  if X and R then -- the run: one switch, and what it comes to
    local on = X.On()
    rows[1] = { t = "XP run", key = "xprun", tex = X.ICON.pickup, page = X.Page, ring = on and "good" or "warn", actLabel = on and "On" or "Off", act = function() X.SetOn(not on) end,
                d = X.Busy() and "Looking for quests around here..." or NS.cdb.route.enabled and X.Short() or "Pick up, do and hand in quests in one round" }
  end
  if not (R and NS.cdb.route.enabled) then
    rows[#rows + 1] = { t = "The quest route is off", key = "routeoff", still = true,
                d = "Route on (above) works out the quickest order through your quests, handing finished ones in on the "
                  .. "way: numbered stops on the map, a line and the arrow. It stays on until you turn it off here, with /sun route, or by right-clicking the "
                  .. "minimap button. Closing this window doesn't stop it. XP run also picks up the quests around you that are "
                  .. "worth it. The Quests tab picks which of yours and in what order, or just one quest." }
    if X and R then X.Rows(rows) end
    return rows
  end
  local focus = NS.cdb.route.focus
  if type(focus) == "table" and focus.id then
    rows[#rows + 1] = { t = "Only: " .. (focus.title or "one quest"),
                        d = "The route covers just this quest; when you hand it in, it moves on to the next quest of its "
                          .. "chain. All quests goes back to the full route.",
                        actLabel = "All quests", act = function() R.Focus(nil) end }
  end
  if R.status then rows[#rows + 1] = { t = R.status, d = "" } end
  local n, xp, slots, free = R.Waiting()
  if n > 0 or (free and free <= 6) then
    local bits = {}
    if n > 0 and xp > 0 then bits[#bits + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp)) .. " XP waiting" end
    if slots > 0 then bits[#bits + 1] = string.format("their items fill %d bag slot%s", slots, slots == 1 and "" or "s") end
    if free then bits[#bits + 1] = string.format("%d bag slot%s free", free, free == 1 and "" or "s") end
    rows[#rows + 1] = { t = n > 0 and string.format("%d finished quest%s to hand in", n, n == 1 and "" or "s") or "Your bags are filling up",
                        d = table.concat(bits, "  ·  "), ring = (free and free <= 3) and "warn" or "good", still = true }
  end
  local nx = R.Next and R.Next()
  if nx then
    local s = nx.stop
    local d = string.format("%s %.1f, %.1f", nx.zone, s.x * 100, s.y * 100)
    if (s.node.kind == "obj" or s.node.kind == "travel") and s.node.quest.title then d = s.node.quest.title .. "  ·  " .. d end
    local hop = R.hop
    if hop and NS.Travel and NS.Travel.MapName then
      d = d .. string.format("\nOn the way: %s at %s %.1f, %.1f (the arrow points there first)", hop.label,
                             NS.Travel.MapName(hop.m), hop.x, hop.y)
    end
    -- what else there is to hand in at the same place
    local here, left = {}, 0
    for k = 2, #R.stops do
      local o = R.stops[k]
      if not (o.node.kind == "turnin" or o.node.kind == "sell") or o.m ~= s.m
        or (o.wx - s.wx) ^ 2 + (o.wy - s.wy) ^ 2 > 150 ^ 2 then break end
      if #here < 5 then here[#here + 1] = o.node.kind == "sell" and "sell at a merchant" or (o.node.quest.title or "?") else left = left + 1 end
    end
    if #here > 0 and (s.node.kind == "turnin" or s.node.kind == "sell") then
      d = d .. "\nAlso here: " .. table.concat(here, ", ") .. (left > 0 and string.format(" and %d more", left) or "")
    elseif nx.after then d = d .. "\nThen: " .. StopText(nx.after) end
    local q = s.node.quest
    local tip = type(q) == "table" and q.id and s.node.kind ~= "pickup" and NS.QuestFind and NS.QuestFind.Tip and NS.QuestFind.Tip(q.id)
    if tip then d = d .. "\nHow: " .. tip end
    if NS.Arrow and NS.Arrow.manual then
      d = d .. "\nThe arrow is pointing at a place you chose (" .. (NS.Arrow.manual.title or "?") .. "): Re-plan, or a right-click on the arrow, points it back at the route."
    end
    rows[#rows + 1] = { h = "Next stop" }
    rows[#rows + 1] = { t = StopText(s), d = d, m = s.m, x = s.x, y = s.y }
    rows[#rows + 1] = { h = string.format("The whole route: %d stop%s", #R.stops, #R.stops == 1 and "" or "s") }
  end
  for i, s in ipairs(R.stops or {}) do
    local bits = {}
    if s.node.kind == "obj" or s.node.kind == "sell" then bits[1] = s.node.quest.title end
    if s.node.kind == "travel" then bits[1] = "For " .. (s.node.quest.title or "?") .. ", on the other side" end
    local t = s.secs and s.secs >= 50 and math.floor(s.secs / 60 + 0.5)
    if t then bits[#bits + 1] = s.fly and string.format("fly part of the way, %d min", t) or string.format("%d min walk", t) end
    rows[#rows + 1] = { t = i .. ". " .. StopText(s), d = #bits > 0 and table.concat(bits, "  ·  ") or nil, m = s.m, x = s.x, y = s.y, tex = X and X.StopIcon(s) or nil, key = "stop" .. tostring(s.key) }
  end
  local other = #(R.elsewhere or {}) + #(R.unknown or {})
  if other > 0 then
    local away = R.stops and R.stops[1] and R.stops[1].node.kind == "travel"
    rows[#rows + 1] = { t = string.format("%d more not on the route", other),
                        d = away and "On the other continent: the route takes you to the boat or zeppelin first, and picks them up once you land. \"List in chat\" names them."
                          or "On another continent, or Questie has no spot for them. \"List in chat\" names them." }
  end
  if not nx and not R.status then
    rows[#rows + 1] = { t = "Nothing to route right now", d = "No quest objectives or turn-ins found nearby." }
  end
  if X and not focus then X.Rows(rows) end
  return rows
end


---------------------------------------------------------------------------
-- Actions on a row
---------------------------------------------------------------------------
function W.Mark(row)
  if not row or not row.m then return end
  local list = NS.cdb.markers
  list[#list + 1] = { title = row.t, note = row.d and row.d:sub(1, 160), mapID = row.m, x = row.x, y = row.y, from = "window" }
  if NS.Markers then NS.Markers.Redraw() end
  NS.Print("star added on your map: " .. row.t .. "  (/sun markers lists them)")
end

function W.Go(row)
  if not row or not row.m then return end
  if NS.MapView then NS.MapView.trip = nil end
  NS.Arrow.Go(row.m, row.x, row.y, row.t)
end

function W.AddSet(tab)
  local quests, lines = {}, {}
  for _, q in ipairs(NS.Lists.bundle or {}) do
    quests[#quests + 1] = q
    if #lines < 15 then lines[#lines + 1] = NS.Engine.QuestName(q) end
  end
  if #quests == 0 then return end
  NS.cdb.goal = { name = tab == "xp" and "XP plan" or "Gold plan", quests = quests, lines = lines }
  if not NS.cdb.route.enabled then NS.Route.Enable(true) else NS.Route.sig = nil; NS.Route.Compute(true) end
  NS.Print(#quests .. " quest givers added to your route (/sun goal shows the list).")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame, pool = nil, {}
-- The route changed (re-planned, a stop done or skipped, turned on or off): redraw the Route tab if it's showing.
function W.RouteChanged()
  if frame and frame:IsShown() and (W.tab == "route" or W.tab == "quests") then W.Refresh() end
end
W.tab = "upgrades"

-- Gear: every slot you have, or the upgrades as a list (easiest first, most gain for the time, the biggest gain per
-- slot), and, on its own, what's listed on the Auction House right now.
local MODES = {
  { "slots", "Character", nil, "You, your gear and your spells in real numbers" },
  { "easy", "Easiest", "upgrades", "Quickest to get first" },
  { "value", "Best value", "upgrades_value", "Most gain for the time" },
  { "best", "Best", "upgrades_best", "Biggest gain per slot, whatever it takes" },
  { "ah", "Auction House", "upgrades_ah", "From your last scan at the Auction House" },
  { "enchants", "Enchants", nil, "What's on your gear, and what would be worth it" },
  { "sets", "Sets", nil, "Item sets your class can wear" },
}
local function GearMode()
  local m = NS.cdb and NS.cdb.gearMode
  for _, x in ipairs(MODES) do if x[1] == m then return x end end
  return MODES[1]
end

-- The real item tooltip (stats, where it drops, whether you can use it) for a row's item.
function W.ShowItemTip(owner, id, spell)
  if type(id) ~= "number" and type(spell) == "number" and GameTooltip and GameTooltip.SetSpellByID then
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if pcall(GameTooltip.SetSpellByID, GameTooltip, spell) then GameTooltip:Show(); owner.tip = true end
    return
  end
  if type(id) ~= "number" or not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local ok = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, id)
  if not ok then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id) end
  if not ok then GameTooltip:AddLine("item " .. id) end
  GameTooltip:Show()
  owner.tip = true
end

---------------------------------------------------------------------------
-- Layout: main tabs along the top; on the left a narrow list to pick from; on the right, most of the window,
-- everything about what you picked (an item's page: where it comes from, its recipe, every material and where
-- to find it). Items on a page open their own page; Back goes to the one before.
---------------------------------------------------------------------------
local WIDTH, HEIGHT = 1060, 640
local LIST_W = 300           -- the list on the left
local BAND_H = 80            -- banner + tabs
local lists = {}             -- "main" (left) and "detail" (right): { key, pool, content, current }
local Layout

local function List(t) return type(t) == "table" and t or {} end
local function ItemName(id)
  local ok, name = pcall(NS.GetItemInfo, id)
  if ok and type(name) == "string" then return name end
end

local function Short(s, n)
  if not s or #s <= n then return s end
  return s:sub(1, n - 3):gsub("%s+%S*$", "") .. "..."
end

-- One row: a rounded plate with an optional item icon, a title, a detail line, Map / Go and up to two actions.
local function Row(list, i)
  local r = list.pool[i]
  if r then return r end
  r = CreateFrame("Frame", nil, list.content)
  r.bg = NS.Rounded(r, C.surface, "round.png", 8)
  r.mark = r:CreateTexture(nil, "ARTWORK") -- the picked row on the left: a short gold mark at its edge
  r.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
  r.mark:SetPoint("TOPLEFT", 1, -7)
  r.mark:SetPoint("BOTTOMLEFT", 1, 7)
  r.mark:SetWidth(3)
  r.mark:Hide()
  r:EnableMouse(true)
  r:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.data or self.data.h then return end
    if list.key == "main" then W.Select(self.data)
    elseif self.data.page then W.OpenPage(self.data.page)
    elseif self.data.i then W.OpenItem(self.data.i, self.data) end
  end)
  r:SetScript("OnEnter", function(self)
    if self.data and not self.data.h and (list.key == "main" or self.data.i or self.data.page) then self.bg:SetColor(C.hover) end
    W.ShowItemTip(self, self.data and self.data.i, self.data and self.data.spell)
  end)
  r:SetScript("OnLeave", function(self)
    self.bg:SetColor((list.key == "main" and W.Picked(self.data)) and C.hover or C.surface)
    if self.tip then self.tip = nil; GameTooltip:Hide() end
  end)
  -- the item's icon in a small dark rounded well; clicking it opens the item's page
  r.well = CreateFrame("Button", nil, r)
  r.well:SetSize(ICON + 6, ICON + 6)
  r.well:SetPoint("TOPLEFT", 7, -7)
  NS.Rounded(r.well, C.bg, "round.png", 6)
  r.icon = r.well:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ICON, ICON)
  r.icon:SetPoint("CENTER")
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's own frame so it sits flush in the well
  if NS.Look then r.wellEdge = NS.Look.Edge(r.well, 1) end
  r.well:SetScript("OnClick", function()
    if not r.data then return end
    if r.data.page then
      if list.key == "main" then W.Select(r.data) else W.OpenPage(r.data.page) end
    elseif r.data.i then W.OpenItem(r.data.i, r.data, list.key == "main") end
  end)
  r.well:SetScript("OnEnter", function(self) W.ShowItemTip(self, r.data and r.data.i, r.data and r.data.spell) end)
  r.well:SetScript("OnLeave", function(self) if self.tip then self.tip = nil; GameTooltip:Hide() end end)
  r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.title:SetJustifyH("LEFT")
  r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.detail:SetJustifyH("LEFT")
  r.detail:SetSpacing(2)
  r.more = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- "›" on rows that open a page
  r.more:SetPoint("RIGHT", -8, 0)
  r.more:SetTextColor(unpack(C.accent))
  r.more:SetText(">")
  r.map = NS.Button(r, "Map", 40, function() W.Mark(r.data) end)
  r.go = NS.Button(r, "Go", 34, function() W.Go(r.data) end)
  r.go:SetPoint("TOPRIGHT", -7, -7)
  r.map:SetPoint("RIGHT", r.go, "LEFT", -5, 0)
  -- a row's own action, when it has one ("Only this" on a quest, "All quests" on the focus row)
  -- the ring around the action button: green = on the route, red = off (row.ring = "good" / "warn")
  r.ring = CreateFrame("Frame", nil, r)
  r.ring.c = NS.Rounded(r.ring, C.good, "pill.png", 9)
  r.ring:Hide()
  r.act = NS.Button(r, "", 80, function() if r.data and r.data.act then NS.Safe("row action", r.data.act) end end)
  r.act2 = NS.Button(r, "", 72, function() if r.data and r.data.act2 then NS.Safe("row action", r.data.act2) end end)
  r.ring:SetPoint("TOPLEFT", r.act, "TOPLEFT", -2, 2)
  r.ring:SetPoint("BOTTOMRIGHT", r.act, "BOTTOMRIGHT", 2, -2)
  local lvl = r.GetFrameLevel and r:GetFrameLevel()
  if type(lvl) == "number" then -- ring above the row, button above the ring
    r.ring:SetFrameLevel(lvl + 1)
    r.act:SetFrameLevel(lvl + 2)
  end
  list.pool[i] = r
  return r
end

function Layout(list, rows)
  list.current = rows
  if list.key == "detail" then
    if NS.ZoneMap then NS.ZoneMap.HideInline() end
    if NS.Look then NS.Look.HideInline() end
  end
  if list.key == "main" then W.current = rows end
  local width = list.content:GetWidth()
  local main = list.key == "main"
  local y = 0
  for i, data in ipairs(rows) do
    local r = Row(list, i)
    r.data = data
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r.title:ClearAllPoints()
    r.detail:ClearAllPoints()
    if data.h then -- a section heading: gold text over a thin dark-red line
      r.bg:Hide(); r.map:Hide(); r.go:Hide(); r.detail:Hide(); r.well:Hide(); r.act:Hide(); r.act2:Hide()
      r.ring:Hide(); r.mark:Hide(); r.more:Hide()
      r.title:SetPoint("TOPLEFT", 4, -6)
      r.title:SetPoint("RIGHT", -4, 0)
      r.title:SetTextColor(unpack(C.accent))
      r.title:SetText(data.h)
      r:SetHeight(r.title:GetStringHeight() + 10)
    elseif data.zmap then -- a zone map (ZoneMap.lua)
      r.map:Hide(); r.go:Hide(); r.detail:Hide(); r.well:Hide(); r.act:Hide(); r.act2:Hide(); r.ring:Hide(); r.mark:Hide(); r.more:Hide()
      r.title:SetText("")
      local h = NS.ZoneMap and NS.ZoneMap.Inline(r, data.zmap, width)
      r.bg:SetColor(C.surface)
      if h then r.bg:Show() else r.bg:Hide() end
      r:SetHeight(h or 1)
    elseif data.panel then -- a panel of its own (Look.lua: the pet planner, the character page, pictures)
      r.map:Hide(); r.go:Hide(); r.detail:Hide(); r.well:Hide(); r.act:Hide(); r.act2:Hide(); r.ring:Hide(); r.mark:Hide(); r.more:Hide()
      r.title:SetText("")
      r.bg:Hide()
      r:SetHeight(NS.Look and NS.Look.Inline(r, data.panel, width) or 1)
    else
      local picked = main and W.Picked(data)
      r.bg:Show()
      r.bg:SetColor(picked and C.hover or C.surface)
      r.mark:SetShown(picked)
      -- the list on the left is for picking: Map / Go and the full text are on the right
      local hasPos = (not main) and data.m ~= nil
      r.map:SetShown(hasPos); r.go:SetShown(hasPos)
      local opens = (main and not data.act and not data.still) or (not main and (data.i ~= nil or data.page ~= nil))
      r.more:SetShown(opens and not hasPos)
      local right = hasPos and -90 or (opens and -20 or -10)
      r.act:ClearAllPoints()
      if data.act then
        r.act:SetText(data.actLabel or "Do it")
        if hasPos then r.act:SetPoint("RIGHT", r.map, "LEFT", -5, 0) else r.act:SetPoint("TOPRIGHT", -7, -7) end
        r.act:Show()
        right = right - 85
      else
        r.act:Hide()
      end
      if data.act and data.ring and C[data.ring] then
        r.ring.c:SetColor(C[data.ring])
        r.ring:Show()
      else
        r.ring:Hide()
      end
      r.act2:ClearAllPoints()
      if data.act2 then
        r.act2:SetText(data.act2Label or "More")
        if data.act then r.act2:SetPoint("RIGHT", r.act, "LEFT", -5, 0)
        elseif hasPos then r.act2:SetPoint("RIGHT", r.map, "LEFT", -5, 0)
        else r.act2:SetPoint("TOPRIGHT", -7, -7) end
        r.act2:Show()
        right = right - 77
      else
        r.act2:Hide()
      end
      local left = 12
      if data.i or data.tex or data.face then
        -- a creature's own face, an item's icon (its edge in the item's quality), or a picture
        local face = data.face and NS.Look and NS.Look.Face(r.icon, data.face)
        if not face then r.icon:SetTexture((data.i and NS.ItemIcon(data.i)) or data.tex or NS.QUESTION_ICON) end
        if r.wellEdge then
          local q = data.q
          if not q and data.i then q = select(3, NS.GetItemInfo(data.i)) end
          local known = data.i and type(q) == "number" and NS.Look.QUALITY[q]
          r.wellEdge:SetColor(known or C.border, known and 1 or 0.8)
        end
        r.well:Show()
        left = ICON + 20
      else
        r.well:Hide()
      end
      r.title:SetPoint("TOPLEFT", left, -8)
      r.title:SetPoint("RIGHT", right, 0)
      r.title:SetTextColor(unpack((data.hot or picked) and C.accent or data.dim and C.dim or QUALITY[data.q or 1] or C.text))
      r.title:SetText(data.t or "")
      local detail = data.d or ""
      if main then
        detail = Short(detail:gsub("\n.*", ""), 90) or ""
      else
        local yd = hasPos and Yards(data)
        if yd then detail = detail .. (detail ~= "" and "  ·  " or "") .. yd .. " yd from you" end
        for _, step in ipairs(data.s or {}) do detail = detail .. (detail ~= "" and "\n" or "") .. "|cff" .. NS.HEX.accent .. "-|r " .. step end
      end
      r.detail:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
      r.detail:SetPoint("RIGHT", right, 0)
      r.detail:SetTextColor(unpack(C.dim))
      r.detail:SetText(detail)
      r.detail:SetShown(detail ~= "")
      local h = r.title:GetStringHeight() + (detail ~= "" and r.detail:GetStringHeight() + 4 or 0) + 16
      r:SetHeight((data.i or data.tex or data.face) and math.max(h, ICON + 20) or h)
    end
    r:Show()
    y = y + r:GetHeight() + (main and 4 or 6)
  end
  for i = #rows + 1, #list.pool do list.pool[i]:Hide() end
  list.content:SetHeight(math.max(y, 10))
end

---------------------------------------------------------------------------
-- The right side: pages (a picked row, an item, the whole talent plan) with Back
---------------------------------------------------------------------------
local history = {}

-- An item's page: every way to get it, its recipe, each material and where to find it (Engine.lua).
local function ItemPage(id, row)
  local rows = {}
  local ok, list = pcall(NS.Engine.ItemRows, id)
  if ok and type(list) == "table" then
    for _, r in ipairs(list) do rows[#rows + 1] = r end
  else
    NS.Error("item page", list)
  end
  local res = Results()
  local details = res and type(res.details) == "table" and res.details
  local page = details and (details[id] or details[tostring(id)])
  if #rows == 0 and type(page) == "table" then
    for _, r in ipairs(Rows(page, 60)) do rows[#rows + 1] = r end
  elseif #rows <= 1 and row and row.s then
    rows[#rows + 1] = { h = "What it takes" }
    for _, s in ipairs(row.s) do rows[#rows + 1] = { t = s } end
  end
  if NS.Places and NS.Places.ItemExtra then -- quests, chests, what wants it, what it's worth
    local ok2, extra = pcall(NS.Places.ItemExtra, id)
    if not ok2 then NS.Error("item page", extra) end
    local quests = {}
    for _, r in ipairs(rows) do if type(r.t) == "string" then quests[r.t] = true end end
    for _, r in ipairs(ok2 and extra or {}) do rows[#rows + 1] = r end
  end
  if NS.CharSheet then -- gear: what it would change
    local link = select(2, NS.GetItemInfo(id))
    local more = link and NS.CharSheet.ItemRows(link)
    for k = #List(more), 1, -1 do table.insert(rows, 1, more[k]) end
  end
  return { title = NS.Engine.ItemName(id), icon = NS.ItemIcon(id), id = id, rows = rows,
           sub = "Click an item below for its own page. Hover an icon for the game's tooltip." }
end

local function RowPage(row)
  if row.page then
    local ok, page = pcall(row.page)
    if ok and type(page) == "table" then page.make = row.page; return page end
    NS.Error("page", page)
  end
  if row.i then return ItemPage(row.i, row) end
  local rows = { { t = row.t, d = row.d, m = row.m, x = row.x, y = row.y, act = row.act, actLabel = row.actLabel,
                   act2 = row.act2, act2Label = row.act2Label, ring = row.ring } }
  if row.s then
    rows[#rows + 1] = { h = "What it takes" }
    for _, s in ipairs(row.s) do rows[#rows + 1] = { t = s } end
  end
  return { title = row.t, rows = rows }
end

-- The Talents tab's right side: the whole plan, level by level.
local PlanPage
function PlanPage()
  local plan = NS.ActivePlan and NS.ActivePlan()
  if not plan then return { title = "Talent plan", rows = { { t = "No plan for this goal", d = "Pick a goal above." } } } end
  local rows, level = {}, UnitLevel("player")
  local tree = NS.TalentTree and NS.TalentTree.Row()
  if tree then rows[#rows + 1] = tree end
  if plan.why then rows[#rows + 1] = { t = plan.why } end
  for lvl = 10, 60 do
    local s = plan.steps[lvl]
    if s then
      if (lvl - 10) % 10 == 0 then rows[#rows + 1] = { h = "Levels " .. lvl .. "-" .. math.min(60, lvl + 9) } end
      rows[#rows + 1] = { t = string.format("%d: %s %d", lvl, s[1], s[2]), d = s[3], dim = lvl <= level }
    end
  end
  return { title = plan.name or "Talent plan", rows = rows, make = PlanPage, sub = "The whole plan; levels you've reached are dimmed." }
end

local function EmptyPage()
  return { title = "Details", empty = true, rows = { { t = "Pick something on the left",
    d = "Everything about it shows here: where to go, what it takes, recipes and materials, with Map and Go." } } }
end

local function ShowPage(page)
  W.page = page
  frame.dTitle:SetText(page.title or "")
  frame.dSub:SetText(page.sub or "")
  if page.icon then
    frame.dIcon:SetTexture(page.icon)
    frame.dWell:Show()
  else
    frame.dWell:Hide()
  end
  frame.back:SetShown(#history > 0)
  frame.dHead:ClearAllPoints()
  frame.dHead:SetPoint("TOPLEFT", #history > 0 and 78 or 10, -8)
  frame.dHead:SetPoint("RIGHT", page.maps and -100 or -10, 0)
  for k, b in ipairs(frame.mapButtons) do
    b.fn = page.maps and page.maps[k] or nil
    b:SetShown(page.maps ~= nil)
    b.icon:SetTexture(page.mapTips and k == 2 and I .. "INV_Misc_Map_01" or b.tex)
    if page.mapTips and k == 1 then b.icon:SetTexture(I .. "Ability_Tracking") end
    b.icon:SetDesaturated(b.fn == nil)
    b.icon:SetAlpha(b.fn and 1 or 0.35)
  end
  Layout(lists.detail, page.rows or {})
  frame.dsf:SetVerticalScroll(0)
end
W.ShowPage = ShowPage

-- Picking a row on the left: its page on the right (a fresh start: Back goes nowhere).
function W.Select(row)
  W.selected, W.auto = row, false
  history = {}
  ShowPage(RowPage(row))
  Layout(lists.main, lists.main.current or {})
end

-- Opening an item (an icon, or a material on a page): its own page; Back returns to this one.
function W.OpenItem(id, row, fromList)
  W.auto = false
  if fromList then
    W.selected = row
    history = {}
    Layout(lists.main, lists.main.current or {})
  elseif W.page then
    history[#history + 1] = W.page
  end
  ShowPage(ItemPage(id, row))
end

-- Opening a page from a page (a recipe, a skill range): Back returns here.
function W.OpenPage(make)
  local ok, page = pcall(make)
  if not ok or type(page) ~= "table" then NS.Error("page", page) return end
  W.auto = false
  if W.page then history[#history + 1] = W.page end
  page.make = make
  ShowPage(page)
end

-- The list on the left is rebuilt on every refresh: a picked row is the one with the same key (or the row itself).
function W.Picked(data)
  local s = W.selected
  return s ~= nil and data ~= nil and (data == s or (data.key ~= nil and data.key == s.key))
end

-- Something worked out in the background is ready: redraw (the window only, and only if it's open).
function W.DataChanged()
  NS.Debounce("windowData", 0.3, function()
    if frame and frame:IsShown() then W.Refresh() end
  end)
end

-- The page on show made again in place (a choice on one of its panels changed): the same spot, the same way back.
function W.Redo()
  if not (frame and frame:IsShown() and W.page and W.page.make) then return end
  local make = W.page.make
  local ok, page = pcall(make)
  if not ok or type(page) ~= "table" then NS.Error("page", page) return end
  page.make = make
  local at = frame.dsf.GetVerticalScroll and tonumber(frame.dsf:GetVerticalScroll()) or 0
  ShowPage(page)
  if at > 0 then frame.dsf:SetVerticalScroll(at) end
end

function W.Back()
  local page = table.remove(history)
  if page then ShowPage(page) end
end

---------------------------------------------------------------------------
-- Refresh: the tab's bar, the list on the left, the page on the right
---------------------------------------------------------------------------
local function Ago(t)
  if type(t) ~= "number" then return nil end
  local m = math.floor((time() - t) / 60)
  return m < 1 and "just now" or m < 120 and (m .. " min ago") or (math.floor(m / 60) .. " h ago")
end

local function E() return NS.Engine end
local BARS -- the filter bar each tab shows under the tabs (set in Build)

function W.Refresh()
  if frame and frame.share and NS.Share then NS.Safe("share", NS.Share.Label, frame.share) end
  if not frame or not frame:IsShown() then return end
  local tab = W.tab
  if tab ~= "dungeons" and NS.Dungeons and NS.Dungeons.HideMap then NS.Dungeons.HideMap() end
  if NS.ZoneMap then NS.ZoneMap.HideUnless(tab) end
  for key, b in pairs(frame.tabs) do b:SetActive(key == tab) end
  frame.tabGap:ClearAllPoints()
  local tb = frame.tabs[tab]
  if tb then
    frame.tabGap:SetPoint("TOPLEFT", tb, "BOTTOMLEFT", 1, 0)
    frame.tabGap:SetPoint("TOPRIGHT", tb, "BOTTOMRIGHT", -1, 0)
    frame.tabGap:Show()
  else
    frame.tabGap:Hide()
  end
  local r = Results()
  local rows
  local gm = GearMode()
  for key, b in pairs(frame.modes) do b:SetActive(key == gm[1]) end
  frame.modeHint:SetText(gm[4])
  local bar = BARS[tab]
  for _, b in pairs(BARS) do b:SetShown(b == bar) end
  if tab == "talents" and NS.TalentGoal then
    -- only the goals this class has a plan for (a Mage gets no Tanking or Healing button), packed left
    local cur = NS.TalentGoal()
    local x = frame.goalX0
    for _, key in ipairs(frame.goalOrder) do
      local b = frame.goals[key]
      b:SetActive(key == cur)
      local show = NS.GoalAvailable(key)
      b:SetShown(show)
      if show then
        b:ClearAllPoints()
        b:SetPoint("LEFT", x, 0)
        x = x + b:GetWidth() + 4
      end
    end
  end
  if frame.profFind then frame.profFind:SetShown(tab == "prof" and NS.Professions.Mode()[1] == "find") end
  if tab == "prof" and NS.Professions then
    local cur = NS.Professions.Mode()
    for key, b in pairs(frame.profModes) do b:SetActive(key == cur[1]) end
    frame.profHint:SetText(cur[3])
  elseif tab == "class" and NS.Class then
    local cur = NS.Class.Mode()
    for key, b in pairs(frame.classModes) do b:SetActive(key == cur[1]) end
    frame.classHint:SetText(cur[3])
  elseif tab == "gold" and NS.Lists.GoldMode then
    local cur = NS.Lists.GoldMode()
    for key, b in pairs(frame.goldModes) do b:SetActive(key == cur[1]) end
    frame.goldHint:SetText(cur[3])
  elseif tab == "guide" and NS.Guide then
    local cur = NS.Guide.Mode()
    for key, b in pairs(frame.guideModes) do b:SetActive(key == cur[1]) end
    frame.guideHint:SetText("")
    frame.guideFind:SetShown(cur[1] ~= "now")
  elseif tab == "dungeons" and NS.Dungeons then
    local cur = NS.Dungeons.Mode()
    for key, b in pairs(frame.dunModes) do b:SetActive(key == cur[1]) end
    frame.dunHint:SetText(cur[3])
  elseif tab == "collect" and NS.Collect then
    local cur, show = NS.Collect.Mode(), NS.Collect.Show()
    for key, b in pairs(frame.colModes) do b:SetActive(key == cur[1]) end
    for key, b in pairs(frame.colShow) do b:SetActive(key == show[1]) end
    frame.colHint:SetText("")
  elseif tab == "factions" and NS.Factions2 then
    local cur = NS.Factions2.Mode()
    for key, b in pairs(frame.facModes) do b:SetActive(key == cur[1]) end
    frame.facHint:SetText(cur[3])
  end
  if tab == "quests" and NS.Route and NS.Route.Optimize then
    local cur = NS.Route.Optimize()
    for key, b in pairs(frame.opts) do b:SetActive(key == cur) end
    for _, o in ipairs(OPTIMIZE) do if o[1] == cur then frame.optHint:SetText(o[3]) end end
  end
  if tab == "route" then
    local on = NS.cdb.route.enabled and true or false
    frame.rOnOff:SetText(on and "Route off" or "Route on")
    frame.rOnOff:SetActive(on)
    local run = NS.XPRun and NS.XPRun.On()
    frame.rPick:SetText(run and "Pick up quests: on" or "Pick up quests: off")
    frame.rPick:SetActive(run)
    local arrow = NS.cdb.route.arrow ~= false
    frame.rArrow:SetText(arrow and "Arrow: on" or "Arrow: off")
    frame.rArrow:SetActive(arrow)
    frame.rArrow:SetShown(on)
    frame.rReplan:SetShown(on)
    frame.rSkip:SetShown(on and NS.Route.stops and #NS.Route.stops > 0)
    local n = NS.Route.SkippedCount and NS.Route.SkippedCount() or 0
    frame.rUnskip:SetText("Un-skip (" .. n .. ")")
    frame.rUnskip:SetShown(on and n > 0)
    frame.routeHint:SetText("")
    local V = NS.MapView
    if V and V.LineMode then
      frame.rLine:SetText("Map: " .. V.LINE_NAME[V.LineMode()])
      frame.rLine:SetActive(V.LineMode() ~= "off")
    end
    local been = NS.Track and NS.Track.On()
    frame.rBeen:SetText(been and "Where I've been: on" or "Where I've been: off")
    frame.rBeen:SetActive(been)
  end
  local top = -(BAND_H + (bar and 30 or 6))
  frame.sf:SetPoint("TOPLEFT", 12, top)
  frame.dp:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + LIST_W + 28, top)
  if tab == "search" then rows = W.searchRows or {}
  elseif tab == "talents" then rows = TalentRows()
  elseif tab == "route" then rows = RouteRows()
  elseif tab == "quests" then
    if NS.QuestFind and NS.QuestFind.find ~= "" then
      local ok, list = pcall(NS.QuestFind.Rows)
      if ok and type(list) == "table" then rows = list
      else NS.Error("quest search", list); rows = { { t = "Something went wrong in the search", d = "Type /sun errors to see what.", still = true } } end
    else rows = QuestRows() end
  else
    local make = tab == "upgrades" and (gm[1] == "slots" and (NS.CharSheet and NS.CharSheet.Rows or NS.Gear.SlotRows) or gm[1] == "enchants" and NS.Sets.EnchantRows or gm[1] == "sets" and NS.Sets.SetRows
        or function() return NS.Gear.ListRows(gm[1]) end)
      or tab == "xp" and NS.Lists.XPRows or tab == "grind" and NS.Lists.GrindRows or tab == "gold" and NS.Lists.GoldRows
      or tab == "prof" and NS.Professions.Rows or tab == "factions" and NS.Factions2.Rows or tab == "class" and NS.Class.Rows
      or tab == "collect" and NS.Collect.Rows or tab == "dungeons" and NS.Dungeons.Rows or tab == "guide" and NS.Guide.Rows
    local ok, list = pcall(make or function() return {} end)
    if ok and type(list) == "table" then rows = list
    else NS.Error(tab .. " tab", list); rows = { { t = "Something went wrong on this tab", d = "Type /sun errors to see what.", still = true } } end
  end
  if #rows == 0 then rows = { { t = "Nothing here right now", still = true } } end
  -- Same tab (a click on a row's button, a re-plan): stay where you were scrolled to and keep the page.
  -- Another tab: the top of the list, and the page goes back to that tab's own start.
  local same = W.lastTab == tab
  local keep = 0
  if same and frame.sf.GetVerticalScroll then keep = tonumber(frame.sf:GetVerticalScroll()) or 0 end
  W.lastTab = tab
  if not same then W.selected = nil end
  local mode = tab == "upgrades" and gm[1] or tab == "prof" and NS.Professions.Mode()[1] or tab == "class" and NS.Class.Mode()[1] or tab == "collect" and NS.Collect.Mode()[1] or tab == "guide" and NS.Guide.Mode()[1] or tab == "dungeons" and NS.Dungeons.Mode()[1] or tab == "gold" and NS.Lists.GoldMode()[1] or tab == "factions" and NS.Factions2.Mode()[1]
    or tab == "quests" and NS.QuestFind and NS.QuestFind.find ~= "" and "find" or ""
  local modeChanged = same and W.lastMode ~= mode
  W.lastMode = mode
  if modeChanged and tab ~= "prof" and tab ~= "class" then W.selected = nil end -- (a profession stays picked when its page style changes)
  if W.selected then -- the same row in the fresh list
    local found
    for _, x in ipairs(rows) do if W.Picked(x) then found = x end end
    if found then W.selected = found end
  end
  Layout(lists.main, rows)
  local range = frame.sf.GetVerticalScrollRange and tonumber(frame.sf:GetVerticalScrollRange())
  if range and keep > range then keep = range end
  frame.sf:SetVerticalScroll(keep)
  local first
  if tab ~= "talents" and (tab ~= "quests" or mode == "find") and tab ~= "search" then
    for _, x in ipairs(rows) do if not x.h and (x.page or x.i) then first = x; break end end
  end
  -- (the row Sunstone opened by itself gives way when a better first row turns up; one you picked stays)
  if not same or not W.page or (modeChanged and not W.selected) or (W.page.empty and not W.selected)
    or (W.auto and first and #history == 0 and not W.Picked(first)) then
    history = {}
    if first then -- open the first thing on the list, so the page is never blank
      W.selected, W.auto = first, true
      Layout(lists.main, rows)
      ShowPage(RowPage(first))
    else
      ShowPage(tab == "talents" and PlanPage() or EmptyPage())
    end
  elseif W.selected and #history == 0 and (not W.page.id or modeChanged) then
    local at = frame.dsf.GetVerticalScroll and tonumber(frame.dsf:GetVerticalScroll()) or 0
    ShowPage(RowPage(W.selected)) -- the picked row may have changed (On/Off, a re-plan, new prices)
    if not modeChanged and at > 0 then frame.dsf:SetVerticalScroll(at) end
  elseif tab == "talents" and not W.selected then
    ShowPage(PlanPage())
  end
  -- the button at the bottom changes with the tab
  local a = frame.action
  a:Hide()
  if tab == "route" and NS.cdb.route.enabled then
    a:SetText("List in chat"); a.fn = function() NS.Route.Print() end; a:Show()
  elseif tab == "talents" then
    a:SetText("Plan in chat"); a.fn = function() NS.Talents.PrintPlan() end; a:Show()
  end
  frame.sub:SetText(UnitName("player") .. " · level " .. UnitLevel("player"))
  local status = "Live"
  if tab == "upgrades" then status = NS.Gear.Status() or "Live"
  elseif (tab == "route" and (E().Busy("xp quests") or E().Busy("xp run"))) or (tab == "xp" and E().Busy("xp quests")) or (tab == "grind" and E().Busy("grind spots"))
    or (tab == "gold" and (E().Busy("farm spots") or E().Busy("drop rates"))) then status = "Working it out..." end
  frame.status:SetText(status)
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------
-- A main tab: an icon and a name on a plate; the open tab is deep red with a gold edge along its top and
-- stands on the gold line (the gap under it joins it to the page).
local function Tab(parent, key, label, icon)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(26)
  b.bg = NS.Rounded(b, C.surface, "round.png", 6)
  b.edge = b:CreateTexture(nil, "ARTWORK")
  b.edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
  b.edge:SetPoint("TOPLEFT", 5, -1)
  b.edge:SetPoint("TOPRIGHT", -5, -1)
  b.edge:SetHeight(2)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", 6, 0)
  b.icon:SetTexture(icon)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b.label:SetText(label)
  local w = b.label.GetStringWidth and b.label:GetStringWidth()
  b:SetWidth(((type(w) == "number" and w > 0) and w or #label * 6) + 33) -- (eleven tabs have to fit)
  function b:SetActive(on)
    self.active = on
    self.bg:SetColor(on and C.hover or C.surface)
    self.edge:SetShown(on)
    self.label:SetTextColor(unpack(on and C.accent or C.dim))
    if self.icon.SetDesaturated then self.icon:SetDesaturated(not on) end
    self.icon:SetAlpha(on and 1 or 0.7)
  end
  b:SetScript("OnEnter", function(self) if not self.active then self.label:SetTextColor(unpack(C.text)) end end)
  b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
  b:SetScript("OnClick", function() W.tab = key; W.Refresh() end)
  b:SetActive(false)
  return b
end

local function Line(parent, y)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
  t:SetPoint("TOPLEFT", 1, y)
  t:SetPoint("TOPRIGHT", -1, y)
  t:SetHeight(1)
  return t
end

local function FilterBar(y)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 12, y)
  bar:SetSize(WIDTH - 24, 22)
  bar:Hide()
  return bar
end

---------------------------------------------------------------------------
-- The window's size: everything in it grows or shrinks together (text, icons, pictures). Drag the corner, the A- and A+ buttons, or /sun size
---------------------------------------------------------------------------
local SMALL = 0.7
local function Number(v, default) return type(v) == "number" and v or default end
function W.MaxScale() -- as big as still fits the screen
  local w, h = Number(UIParent:GetWidth(), 0), Number(UIParent:GetHeight(), 0)
  if w < 200 or h < 200 then return 2 end
  return math.max(SMALL, math.min(w / WIDTH, h / HEIGHT) * 0.985)
end
function W.Scale()
  local s = NS.db and NS.db.windowScale
  if type(s) ~= "number" then s = math.max(1, math.min(1.3, W.MaxScale() * 0.92)) end -- (never chosen: easy to read, with room around it)
  return math.max(SMALL, math.min(W.MaxScale(), s))
end
function W.ApplyScale(s, save) -- the top left corner stays where it is
  if not frame then return end
  s = math.max(SMALL, math.min(W.MaxScale(), s or W.Scale()))
  local old = Number(frame:GetScale(), 1)
  local l, t = frame:GetLeft(), frame:GetTop()
  frame:SetScale(s)
  if type(l) == "number" and type(t) == "number" and math.abs(s - old) > 0.001 then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / s, t * old / s)
    if save then NS.db.frames.Main = { "TOPLEFT", "BOTTOMLEFT", l * old / s, t * old / s } end
  end
  if save then NS.db.windowScale = math.floor(s * 100 + 0.5) / 100 end
  if frame.sizeText then frame.sizeText:SetText(string.format("%d%%", s * 100 + 0.5)) end
end

-- the game's tooltip grows with it while it's about something in the window
local function Inside(f)
  for _ = 1, 25 do
    if f == nil then return false end
    if f == frame then return true end
    if type(f) ~= "table" or (f.IsForbidden and f:IsForbidden()) or not f.GetParent then return false end
    f = f:GetParent()
  end
  return false
end
local function HookTips()
  if not (hooksecurefunc and GameTooltip and GameTooltip.HookScript) then return end
  local was
  local function Back(tip)
    if was then
      tip:SetScale(was)
      was = nil
    end
  end
  pcall(hooksecurefunc, GameTooltip, "SetOwner", function(tip, owner)
    local ok, mine = pcall(Inside, owner)
    if ok and mine then
      if not was then was = Number(tip:GetScale(), 1) end
      tip:SetScale(was * math.max(1, math.min(1.5, W.Scale())))
    else
      Back(tip)
    end
  end)
  pcall(GameTooltip.HookScript, GameTooltip, "OnHide", Back)
end

local function Sizer()
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(20, 20)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  local lvl = frame.GetFrameLevel and frame:GetFrameLevel()
  if type(lvl) == "number" then grip:SetFrameLevel(lvl + 20) end
  local G = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
  grip:SetNormalTexture(G .. "Up")
  grip:SetHighlightTexture(G .. "Highlight")
  grip:SetPushedTexture(G .. "Down")
  grip:SetScript("OnMouseDown", function(self)
    local l, t, sc = frame:GetLeft(), frame:GetTop(), Number(frame:GetScale(), 1)
    if type(l) ~= "number" or type(t) ~= "number" then return end
    l, t = l * sc, t * sc -- in the screen's own units
    local es = Number(UIParent:GetEffectiveScale(), 1)
    local x0, y0 = GetCursorPosition()
    local wide, high = WIDTH * sc, HEIGHT * sc
    self:SetScript("OnUpdate", function(g)
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        g:SetScript("OnUpdate", nil)
        W.ApplyScale(Number(frame:GetScale(), 1), true)
        W.Refresh()
        return
      end
      local x, y = GetCursorPosition()
      local s = math.max((wide + (x - x0) / es) / WIDTH, (high - (y - y0) / es) / HEIGHT)
      s = math.max(SMALL, math.min(W.MaxScale(), s))
      frame:SetScale(s)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l / s, t / s)
      frame.sizeText:SetText(string.format("%d%%", s * 100 + 0.5))
      NS.db.windowScale = math.floor(s * 100 + 0.5) / 100
      NS.db.frames.Main = { "TOPLEFT", "BOTTOMLEFT", l / s, t / s }
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    W.ApplyScale(Number(frame:GetScale(), 1), true)
    W.Refresh()
  end)
  grip:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("Drag: make everything bigger or smaller", C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine("The text, icons and pictures all grow with it.", C.text[1], C.text[2], C.text[3], true)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.grip = grip
  -- and two buttons at the top, with the size between them
  local more = NS.Button(frame, "A+", 28, function() W.ApplyScale(Number(frame:GetScale(), 1) + 0.1, true); W.Refresh() end)
  more:SetPoint("TOPRIGHT", -306, -13)
  frame.sizeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.sizeText:SetPoint("RIGHT", more, "LEFT", -5, 0)
  frame.sizeText:SetWidth(36)
  frame.sizeText:SetJustifyH("CENTER")
  frame.sizeText:SetTextColor(unpack(C.dim))
  local less = NS.Button(frame, "A-", 28, function() W.ApplyScale(Number(frame:GetScale(), 1) - 0.1, true); W.Refresh() end)
  less:SetPoint("RIGHT", frame.sizeText, "LEFT", -5, 0)
  frame.bigger, frame.smaller = more, less
end

local function Build()
  frame = NS.Panel("Main", WIDTH, HEIGHT, "Sunstone")
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame.text:Hide()
  tinsert(UISpecialFrames, frame:GetName()) -- Esc closes it
  -- the banner and the tab strip: a darker band across the top, its bottom edge straight (clipped)
  local band = CreateFrame("Frame", nil, frame)
  band:SetPoint("TOPLEFT", 1, -1)
  band:SetPoint("TOPRIGHT", -1, -1)
  band:SetHeight(BAND_H - 1)
  if band.SetClipsChildren then band:SetClipsChildren(true) end
  local bandInner = CreateFrame("Frame", nil, band)
  bandInner:SetPoint("TOPLEFT")
  bandInner:SetPoint("TOPRIGHT")
  bandInner:SetHeight(BAND_H + 24)
  NS.Rounded(bandInner, C.band, "round.png", 11)
  local level = frame.GetFrameLevel and frame:GetFrameLevel()
  if type(level) == "number" then band:SetFrameLevel(level); bandInner:SetFrameLevel(level) end -- behind the name and the lines, not over them
  Line(frame, -(BAND_H - 32)) -- a thin line between the banner and the tabs
  frame.tabLine = Line(frame, -BAND_H)
  -- banner: the Sunstone mark, the name in gold, who's playing under it
  local logo = frame:CreateTexture(nil, "ARTWORK")
  logo:SetTexture("Interface\\AddOns\\Sunstone\\icon.png")
  logo:SetSize(30, 30)
  logo:SetPoint("TOPLEFT", 12, -8)
  frame.title:ClearAllPoints()
  frame.title:SetPoint("TOPLEFT", 50, -9)
  frame.title:SetFontObject("GameFontNormalLarge")
  frame.title:SetTextColor(unpack(C.accent))
  frame.title:SetText("Sunstone")
  frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.sub:SetPoint("TOPLEFT", 50, -28)
  frame.sub:SetTextColor(unpack(C.dim))
  frame.close:ClearAllPoints()
  frame.close:SetPoint("TOPRIGHT", -8, -12)
  -- search: "how do I get to...", "nearest bank", a dungeon, a town, a zone
  local box = CreateFrame("EditBox", nil, frame)
  box:SetSize(260, 22)
  box:SetPoint("TOPRIGHT", -36, -12)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetTextInsets(10, 8, 0, 0)
  box:SetMaxLetters(80)
  if box.SetTextColor then box:SetTextColor(unpack(C.text)) end
  NS.Rounded(box, C.surface, "pill.png", 7)
  local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("LEFT", 11, 0)
  hint:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 0.85)
  hint:SetText("Search: a place, faction, quest, item...")
  box:SetScript("OnEditFocusGained", function() hint:Hide() end)
  box:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    self:ClearFocus()
    W.Search(text)
  end)
  frame.search = box
  frame.share = NS.Button(frame, "Share finds", 92, function() if NS.Share then NS.Safe("share", NS.Share.Press) end end)
  frame.share:SetHeight(22)
  frame.share:SetPoint("TOPRIGHT", -424, -12)
  frame.share:HookScript("OnEnter", function(self) if NS.Share then NS.Share.Tip(self) end end)
  frame.share:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- the main tabs, standing on the gold line
  frame.tabs = {}
  local x = 12
  for _, t in ipairs(TABS) do
    local b = Tab(frame, t[1], t[2], t[3])
    b:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", x, -BAND_H)
    x = x + b:GetWidth() + 3
    frame.tabs[t[1]] = b
  end
  frame.tabGap = frame:CreateTexture(nil, "OVERLAY") -- hides the line under the open tab
  frame.tabGap:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
  frame.tabGap:SetHeight(2)
  BARS = {}
  -- Upgrades: Easiest / Best value / Best / Auction House
  local bar = FilterBar(-(BAND_H + 6))
  frame.modebar, frame.modes = bar, {}
  BARS.upgrades = bar
  local mx = 0
  for _, m in ipairs(MODES) do
    local key, label = m[1], m[2]
    local b = NS.Button(bar, label, math.floor(#label * 6 + 20), function()
      NS.cdb.gearMode = key
      W.Refresh()
    end)
    b:SetHeight(20)
    b:SetPoint("LEFT", mx, 0)
    mx = mx + b:GetWidth() + 5
    frame.modes[key] = b
  end
  frame.modeHint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.modeHint:SetPoint("LEFT", mx + 6, 0)
  frame.modeHint:SetTextColor(unpack(C.dim))
  -- Professions: what the page shows; Factions: reputation, Library Books or Honor
  local function ModeBar(tab, modes, setting)
    local b2 = FilterBar(-(BAND_H + 6))
    BARS[tab] = b2
    local map, x2 = {}, 0
    for _, m in ipairs(modes) do
      local key, label = m[1], m[2]
      local b = NS.Button(b2, label, math.floor(#label * 6 + 20), function() NS.cdb[setting] = key; W.Refresh() end)
      b:SetHeight(20)
      b:SetPoint("LEFT", x2, 0)
      x2 = x2 + b:GetWidth() + 5
      map[key] = b
    end
    local hint = b2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", x2 + 6, 0)
    hint:SetTextColor(unpack(C.dim))
    return map, hint
  end
  frame.profModes, frame.profHint = ModeBar("prof", NS.Professions.MODES, "profMode")
  frame.goldModes, frame.goldHint = ModeBar("gold", NS.Lists.GOLD, "goldMode")
  frame.facModes, frame.facHint = ModeBar("factions", NS.Factions2.MODES, "factionMode")
  frame.classModes, frame.classHint = ModeBar("class", NS.Class.MODES, "classMode")
  frame.colModes, frame.colHint = ModeBar("collect", NS.Collect.MODES, "collectMode")
  frame.guideModes, frame.guideHint = ModeBar("guide", NS.Guide.MODES, "guideMode")
  frame.dunModes, frame.dunHint = ModeBar("dungeons", NS.Dungeons.MODES, "dungeonMode")
  -- a search box on the right of a tab's bar: what's typed narrows the list as you type
  local function FindBox(bar2, module, hintText)
    local fb = CreateFrame("EditBox", nil, bar2)
    fb:SetSize(220, 20)
    fb:SetPoint("RIGHT", bar2, "RIGHT", 0, 0)
    fb:SetAutoFocus(false)
    fb:SetFontObject(ChatFontNormal)
    fb:SetTextInsets(10, 8, 0, 0)
    fb:SetMaxLetters(40)
    if fb.SetTextColor then fb:SetTextColor(unpack(C.text)) end
    NS.Rounded(fb, C.surface, "pill.png", 7)
    local fh = fb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fh:SetPoint("LEFT", 11, 0)
    fh:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 0.85)
    fh:SetText(hintText)
    fb:SetScript("OnEditFocusGained", function() fh:Hide() end)
    fb:SetScript("OnEditFocusLost", function(self) fh:SetShown(self:GetText() == "") end)
    fb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    fb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    fb:SetScript("OnTextChanged", function(self)
      local text = NS.Clean(self:GetText() or "", 40)
      if text == module.find then return end
      module.find = text
      NS.Debounce("find box", 0.3, W.Refresh)
    end)
    return fb
  end
  frame.profFind = FindBox(BARS.prof, NS.Professions, "Recipe, item or material")
  frame.guideFind = FindBox(BARS.guide, NS.Guide, "Search this page")
  frame.dunFind = FindBox(BARS.dungeons, NS.Dungeons, "Dungeon, boss, item or zone")
  frame.colFind = FindBox(BARS.collect, NS.Collect, "Name, zone, vendor or \"new\"")
  -- Pets & Mounts: all, the missing ones, the ones you have
  frame.colShow = {}
  local cx
  for _, m in ipairs(NS.Collect.SHOW) do
    local key, label = m[1], m[2]
    local b = NS.Button(BARS.collect, label, math.floor(#label * 6 + 20), function() NS.cdb.collectShow = key; W.Refresh() end)
    b:SetHeight(20)
    if cx then b:SetPoint("LEFT", cx, "RIGHT", 4, 0) else b:SetPoint("LEFT", 190, 0) end
    cx = b
    frame.colShow[key] = b
  end
  -- Quests: the route's order (Pathing / XP / Rewards / All)
  local qbar = FilterBar(-(BAND_H + 6))
  frame.questbar, frame.opts = qbar, {}
  BARS.quests = qbar
  local label = qbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", 0, 0)
  label:SetTextColor(unpack(C.dim))
  label:SetText("Route order:")
  local lw = label.GetStringWidth and label:GetStringWidth()
  local ox = ((type(lw) == "number" and lw > 0) and lw or 66) + 8 -- the width can read 0 before the text is drawn
  for _, o in ipairs(OPTIMIZE) do
    local key, text = o[1], o[2]
    local b = NS.Button(qbar, text, math.floor(#text * 6 + 20), function() NS.Safe("route", NS.Route.SetOptimize, key) end)
    b:SetHeight(20)
    b:SetPoint("LEFT", ox, 0)
    ox = ox + b:GetWidth() + 5
    frame.opts[key] = b
  end
  if NS.QuestFind then
    local QF = NS.QuestFind
    frame.questFind = FindBox(qbar, QF, "Find a quest, or something one gives")
    frame.questFind:SetWidth(250)
    function QF.SetBox(text) frame.questFind:SetText(text) end
    function QF.Clear()
      QF.find = ""
      frame.questFind:SetText("")
      frame.questFind:ClearFocus()
      W.Refresh()
    end
  end
  frame.optHint = qbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.optHint:SetPoint("LEFT", ox + 6, 0)
  frame.optHint:SetTextColor(unpack(C.dim))
  -- Talents: the goal this character's plan is for (saved per character); only the goals the class can do
  local gbar = FilterBar(-(BAND_H + 6))
  frame.goalbar, frame.goals, frame.goalOrder = gbar, {}, {}
  BARS.talents = gbar
  local glabel = gbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  glabel:SetPoint("LEFT", 0, 0)
  glabel:SetTextColor(unpack(C.dim))
  glabel:SetText("Goal:")
  local gw = glabel.GetStringWidth and glabel:GetStringWidth()
  local gx = ((type(gw) == "number" and gw > 0) and gw or 30) + 8
  frame.goalX0 = gx
  local goalList = {}
  for _, g in ipairs(NS.GOALS or {}) do goalList[#goalList + 1] = g end
  goalList[#goalList + 1] = { "custom", "Custom" } -- the desktop helper's plan; shown only when there is one
  for _, g in ipairs(goalList) do
    local key, text = g[1], g[2]
    local b = NS.Button(gbar, text, math.floor(#text * 6 + 16), function() NS.Safe("talents", NS.SetTalentGoal, key) end)
    b:SetHeight(20)
    b:SetPoint("LEFT", gx, 0)
    gx = gx + b:GetWidth() + 4
    frame.goals[key] = b
    frame.goalOrder[#frame.goalOrder + 1] = key
  end
  -- Route: its buttons (the route has no window of its own)
  local rbar = FilterBar(-(BAND_H + 6))
  frame.routebar = rbar
  BARS.route = rbar
  local function RouteButton(text, width, fn)
    local b = NS.Button(rbar, text, width, function() NS.Safe("route", fn) end)
    b:SetHeight(20)
    return b
  end
  frame.rOnOff = RouteButton("Route on", 76, function() NS.Route.Enable(not NS.cdb.route.enabled) end)
  frame.rOnOff:SetPoint("LEFT", 0, 0)
  frame.rPick = RouteButton("Pick up quests: off", 126, function() if NS.XPRun then NS.XPRun.SetOn(not NS.XPRun.On()) end end)
  frame.rPick:SetPoint("LEFT", frame.rOnOff, "RIGHT", 5, 0)
  frame.rArrow = RouteButton("Arrow: on", 72, function() NS.Route.SetArrowShown(NS.cdb.route.arrow == false) end)
  frame.rArrow:SetPoint("LEFT", frame.rPick, "RIGHT", 5, 0)
  frame.rReplan = RouteButton("Re-plan", 66, function() NS.Route.Resume() end)
  frame.rReplan:SetPoint("LEFT", frame.rArrow, "RIGHT", 5, 0)
  frame.rSkip = RouteButton("Skip next stop", 100, function() NS.Route.SkipCurrent() end)
  frame.rSkip:SetPoint("LEFT", frame.rReplan, "RIGHT", 5, 0)
  frame.rUnskip = RouteButton("Un-skip (0)", 84, function() NS.Route.Unskip() end)
  frame.rUnskip:SetPoint("LEFT", frame.rSkip, "RIGHT", 5, 0)
  frame.rLine = RouteButton("Map: whole route", 112, function() if NS.MapView then NS.MapView.NextLineMode() end end)
  frame.rBeen = RouteButton("Where I've been: off", 124, function() if NS.Track then NS.Track.Set(not NS.Track.On()) end end)
  frame.rBeen:SetPoint("RIGHT", rbar, "RIGHT", 0, 0)
  frame.rLine:SetPoint("RIGHT", frame.rBeen, "LEFT", -5, 0)
  frame.routeHint = rbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.routeHint:SetPoint("LEFT", frame.rUnskip, "RIGHT", 8, 0)
  frame.routeHint:SetPoint("RIGHT", frame.rLine, "LEFT", -6, 0)
  frame.routeHint:SetJustifyH("LEFT")
  frame.routeHint:SetTextColor(unpack(C.dim))
  -- the list on the left (narrow: for picking)
  local sf = CreateFrame("ScrollFrame", "SunstoneMainScroll", frame, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -(BAND_H + 6))
  sf:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 42)
  sf:SetWidth(LIST_W)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(LIST_W, 10)
  sf:SetScrollChild(content)
  frame.sf, frame.content = sf, content
  lists.main = { key = "main", pool = {}, content = content }
  -- the page on the right (wide: for reading)
  local dp = CreateFrame("Frame", nil, frame)
  dp:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + LIST_W + 28, -(BAND_H + 6))
  dp:SetPoint("BOTTOMRIGHT", -12, 42)
  NS.Rounded(dp, C.panel, "round.png", 10)
  frame.dp = dp
  frame.back = NS.Button(dp, "< Back", 62, function() W.Back() end)
  frame.back:SetPoint("TOPLEFT", 8, -10)
  frame.back:Hide()
  local head = CreateFrame("Frame", nil, dp)
  head:SetHeight(36)
  frame.dHead = head
  frame.dWell = CreateFrame("Frame", nil, head)
  frame.dWell:SetSize(34, 34)
  frame.dWell:SetPoint("LEFT", 0, 0)
  NS.Rounded(frame.dWell, C.bg, "round.png", 7)
  frame.dIcon = frame.dWell:CreateTexture(nil, "ARTWORK")
  frame.dIcon:SetSize(28, 28)
  frame.dIcon:SetPoint("CENTER")
  frame.dIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.dTitle = head:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.dTitle:SetPoint("TOPLEFT", 42, -1)
  frame.dTitle:SetPoint("RIGHT", 0, 0)
  frame.dTitle:SetJustifyH("LEFT")
  frame.dTitle:SetTextColor(unpack(C.accent))
  frame.dSub = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.dSub:SetPoint("TOPLEFT", frame.dTitle, "BOTTOMLEFT", 0, -3)
  frame.dSub:SetPoint("RIGHT", 0, 0)
  frame.dSub:SetJustifyH("LEFT")
  frame.dSub:SetTextColor(unpack(C.dim))
  -- dungeons: the way there on the world map, and the map of the inside
  frame.mapButtons = {}
  for k, m in ipairs({ { I .. "INV_Misc_Map_01", "Map: the way there", "Opens your world map with the way drawn from where you are to the entrance, plus the arrow and the trail." },
                       { I .. "INV_Misc_Bone_HumanSkull_01", "Map: inside, with the bosses", "A map of the dungeon's inside, with every boss numbered." } }) do
    local b = CreateFrame("Button", nil, dp)
    b:SetSize(36, 36)
    b:SetPoint("TOPRIGHT", -(8 + (2 - k) * 44), -8)
    NS.Rounded(b, C.surface, "round.png", 8)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    b.tex = m[1]
    b.icon:SetTexture(m[1])
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      local tips = W.page and W.page.mapTips and W.page.mapTips[k]
      GameTooltip:AddLine(tips and tips[1] or m[2], C.accent[1], C.accent[2], C.accent[3])
      GameTooltip:AddLine(self.fn and (tips and tips[2] or m[3]) or tips and tips[3] or (k == 1 and "The entrance isn't recorded yet." or "No inside map for this one yet."), 0.86, 0.85, 0.81, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) if self.fn then NS.Safe("dungeon map", self.fn) end end)
    b:Hide()
    frame.mapButtons[k] = b
  end
  local dsf = CreateFrame("ScrollFrame", "SunstoneDetailScroll", dp, "UIPanelScrollFrameTemplate")
  dsf:SetPoint("TOPLEFT", 10, -52)
  dsf:SetPoint("BOTTOMRIGHT", -28, 8)
  local dcontent = CreateFrame("Frame", nil, dsf)
  dcontent:SetSize(WIDTH - (12 + LIST_W + 28) - 12 - 38, 10)
  dsf:SetScrollChild(dcontent)
  frame.dsf = dsf
  lists.detail = { key = "detail", pool = {}, content = dcontent }
  -- bottom: where the lists came from, and the buttons
  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.status:SetPoint("BOTTOMLEFT", 14, 16)
  frame.status:SetTextColor(unpack(C.dim))
  local refresh = NS.Button(frame, "Refresh", 70, function()
    NS.Engine.cache = {}
    NS.Engine.ForgetSources()
    if NS.Upgrades and not NS.Upgrades.scanning then NS.Safe("upgrades", NS.Upgrades.Scan) end
    W.Refresh()
  end)
  refresh:SetPoint("BOTTOMRIGHT", -28, 12)
  frame.action = NS.Button(frame, "", 116, function(self) if self.fn then self.fn() end end)
  frame.action:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
  frame:SetScript("OnShow", function() NS.Safe("window", W.Refresh) end)
  Sizer()
  frame:SetScale(W.Scale()) -- (where it was left is in its own units, so the size comes first)
  frame.sizeText:SetText(string.format("%d%%", W.Scale() * 100 + 0.5))
  HookTips()
  frame:Hide()
end

function W.Search(text)
  if not frame then Build() end
  W.searchText = text
  if NS.Places and not NS.Places.Ready() then -- (a few seconds the first time: then it looks again by itself)
    NS.Places.Build(function() if W.tab == "search" and W.searchText then W.Search(W.searchText) end end)
  elseif NS.QuestFind and not NS.QuestFind.Ready() then
    NS.QuestFind.Build(function() if W.tab == "search" and W.searchText then W.Search(W.searchText) end end)
  end
  W.searchRows = NS.Travel and NS.Travel.Search(text) or {}
  if NS.Places and not (NS.Places.Ready() and NS.QuestFind and NS.QuestFind.Ready()) then
    table.insert(W.searchRows, { t = "Still reading everything...", d = "A few seconds the first time; more shows up by itself.", still = true, dim = true, key = "sreading" })
  end
  W.tab = "search"
  frame:Show()
  W.Refresh()
end

function W.Toggle()
  if not frame then Build() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

function W.Open(tab)
  if not frame then Build() end
  if tab == "xp" then tab = "route" end -- (one tab since 2.2)
  if tab then W.tab = tab end
  frame:Show()
  W.Refresh()
end

---------------------------------------------------------------------------
-- Minimap button (drag it around the minimap; /sun minimap hides or shows it)
---------------------------------------------------------------------------
local button
local function Place()
  local a = NS.db.minimap.angle or math.rad(200)
  local r = (Minimap:GetWidth() / 2) + 10
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function MinimapButton()
  if button or not Minimap then return end
  button = CreateFrame("Button", "SunstoneMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  local back = button:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(NS.MEDIA .. "dot.png")
  back:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
  back:SetSize(22, 22)
  back:SetPoint("CENTER")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\Sunstone\\icon.png")
  icon:SetSize(22, 22)
  icon:SetPoint("CENTER")
  local ring = button:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53)
  ring:SetPoint("TOPLEFT")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnClick", function(_, which)
    if which == "RightButton" then
      NS.Route.Enable(not NS.cdb.route.enabled)
      NS.Print("quest route " .. (NS.cdb.route.enabled and "on." or "off."))
    else
      W.Toggle()
    end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Sunstone", C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine("Left-click: open  ·  Right-click: quest route on/off", C.text[1], C.text[2], C.text[3])
    GameTooltip:AddLine("Drag to move", C.dim[1], C.dim[2], C.dim[3])
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      NS.db.minimap.angle = math.atan2(cy / s - my, cx / s - mx)
      Place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  Place()
  button:SetShown(not NS.db.minimap.hide)
end

function W:Init()
  for _, ev in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do -- another screen size: still on it
    NS.On(ev, function() NS.Debounce("windowScale", 0.5, function() if frame then NS.Safe("window size", W.ApplyScale) end end) end)
  end
  NS.Command("size", "<percent> - how big Sunstone's window is, text and all (/sun size 130)", function(rest)
    local n = tonumber((tostring(rest or ""):gsub("%%", "")))
    if n and n < 10 then n = n * 100 end
    if n then
      NS.db.windowScale = math.max(SMALL, math.min(W.MaxScale(), n / 100))
      if frame then W.ApplyScale(NS.db.windowScale, true) end
    end
    NS.Print(string.format("the window is at %d%%; %d%% is the biggest that fits your screen.", W.Scale() * 100 + 0.5, W.MaxScale() * 100))
  end)
  NS.db.minimap = NS.db.minimap or { angle = math.rad(200) }
  NS.Safe("minimap button", MinimapButton)
  -- keep the live tabs fresh while the window is open
  NS.On("PLAYER_LEVEL_UP", function() NS.Debounce("window", 2, W.Refresh) end)
  NS.On("TRAIT_CONFIG_UPDATED", function() NS.Debounce("window", 1, W.Refresh) end)
  NS.On("CHARACTER_POINTS_CHANGED", function() NS.Debounce("window", 1, W.Refresh) end)
  NS.On("QUEST_LOG_UPDATE", function()
    if W.tab == "route" or W.tab == "quests" then NS.Debounce("window", 2, W.Refresh) end
  end)
end

NS.Command("minimap", "- hide or show the minimap button", function()
  NS.db.minimap.hide = not NS.db.minimap.hide
  if button then button:SetShown(not NS.db.minimap.hide) end
  NS.Print("minimap button " .. (NS.db.minimap.hide and "hidden (/sun minimap brings it back)." or "shown."))
end)
