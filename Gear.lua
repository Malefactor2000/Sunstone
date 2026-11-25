-- Sunstone: the Upgrades tab. Every equipment slot with what you wear and the best you could get for it, and the same
-- upgrades as lists (easiest first, best value, biggest gain, Auction House). The scores come from Upgrades.lua, where
-- each item comes from and how far it is from Engine.lua. Nothing here needs the desktop helper.

local _, NS = ...
local G = NS.Module("Gear")
NS.Gear = G
local E = NS.Engine

-- slot number, name, the game's slot name (for the empty-slot picture)
G.SLOTS = {
  { 16, "Main hand", "MainHandSlot" }, { 17, "Off hand", "SecondaryHandSlot" }, { 18, "Ranged", "RangedSlot" },
  { 1, "Head", "HeadSlot" }, { 2, "Neck", "NeckSlot" }, { 3, "Shoulders", "ShoulderSlot" }, { 15, "Back", "BackSlot" },
  { 5, "Chest", "ChestSlot" }, { 9, "Wrists", "WristSlot" }, { 10, "Hands", "HandsSlot" }, { 6, "Waist", "WaistSlot" },
  { 7, "Legs", "LegsSlot" }, { 8, "Feet", "FeetSlot" }, { 11, "Ring 1", "Finger0Slot" }, { 12, "Ring 2", "Finger1Slot" },
  { 13, "Trinket 1", "Trinket0Slot" }, { 14, "Trinket 2", "Trinket1Slot" },
}
local RANDOM = { dungeon = true, drop = true }
local MAX_WORK = 260 -- upgrades to find sources for (the biggest gains; there are rarely more)

local function Fits(e, slot)
  for _, s in ipairs(e.slots or {}) do if s == slot then return true end end
  return false
end

local function Gain(e)
  local pct = e.cur and e.cur > 0.5 and string.format(", +%d%%", math.floor(100 * e.gain / e.cur + 0.5)) or ""
  return string.format("+%.1f%s", e.gain, pct)
end

---------------------------------------------------------------------------
-- Sources for every upgrade (a background job: a few milliseconds a frame)
---------------------------------------------------------------------------
G.done = nil -- the upgrade list the sources were worked out for
function G.Changed()
  NS.Debounce("gearSources", 1, function()
    local all = NS.Upgrades and NS.Upgrades.all
    if not all then return end
    local started = E.Job("gear sources", function()
      local n = 0
      for _, e in ipairs(all) do
        E.Yield()
        if e.quests or e.extra then
          n = n + 1
          if n > MAX_WORK then break end
          local s = E.Best(e.id)
          if s and e.train then -- the trip to a weapon master comes first
            local m = E.WeaponMaster(e.train)
            local c = {}
            for k, v in pairs(s) do c[k] = v end
            c.mins = s.mins + (m and m.mins or 30) + 2
            c.master = m
            c.req = math.max(s.req or 0, e.trainLevel or 0)
            s = c
          end
          e.src = s
        end
      end
      return all
    end, function(list)
      G.done = list
      if NS.Window and NS.Window.DataChanged then NS.Window.DataChanged() end
      -- the scan found more while this ran
      if NS.Upgrades.all ~= list then G.Changed() end
    end)
    if not started then NS.Debounce("gearSourcesAgain", 3, G.Changed) end
  end)
end

local function Kind(e) -- "now", "random", "later", "ah" or nil (no source known)
  local s, level = e.src, UnitLevel("player")
  if not s then return e.ah and "ah" or nil end
  if (e.reqLevel or 0) > level or (s.req or 0) > level then return "later" end
  if E.Overseas(s.place) or (s.master and E.Overseas(s.master.p)) then return "far" end
  if RANDOM[s.kind] then return "random" end
  if s.ok then return "now" end
  return "later"
end

local function SourceText(e, long)
  local s = e.src
  if not s then return "Where it comes from isn't known yet" end
  local out = s.label
  if e.train then
    local kind = NS.Upgrades.WEAPON_NAME[e.train] or "this weapon"
    out = long and string.format("Learn %s first%s\n%s", kind, s.master and (" (" .. s.master.name .. ", " .. s.master.city .. ")") or "", out)
      or string.format("learn %s first, %s", kind, out)
  end
  if long and s.d and s.d ~= "" then out = out .. "\n" .. s.d end
  if not s.untimed and s.ok and s.mins < 400 then out = out .. (long and "\n" or ", ") .. E.Duration(s.mins) end
  return out
end

local function Entry(e, long, level)
  local row = { t = string.format("%s  (%s)", e.name, Gain(e)), d = SourceText(e, long), i = e.id, q = e.quality }
  if (e.reqLevel or 0) > level then row.d = "Wearable at level " .. e.reqLevel .. ". " .. row.d end
  local link = long and NS.CharSheet and select(2, NS.GetItemInfo(e.id))
  local change = link and NS.CharSheet.ChangeText(link, 5)
  if change then row.d = "|cff" .. NS.HEX.good .. change .. "|r\n" .. row.d end
  if e.two then row.t = row.t .. "  two-handed" end
  return E.At(row, e.src and e.src.place)
end

local function Status()
  local U = NS.Upgrades
  if not U then return nil end
  if U.scanning or not U.evaluated then return "Looking through the gear you can get... (a few seconds after you log in)" end
  if E.Busy("gear sources") or G.done ~= U.all then return "Working out where it all comes from..." end
  if (U.waiting or 0) > 0 then return string.format("%d items are still loading from the game.", U.waiting) end
end
G.Status = Status

---------------------------------------------------------------------------
-- The slots
---------------------------------------------------------------------------
local function Worn(slot)
  local link = GetInventoryItemLink("player", slot)
  if not link then return nil end
  local id = tonumber(tostring(link):match("item:(%d+)"))
  local name, _, quality, ilvl = NS.GetItemInfo(link)
  return { id = id, name = name or (id and E.ItemName(id)) or "?", quality = quality, ilvl = ilvl }
end

local function SlotIcon(slotName)
  if not GetInventorySlotInfo then return nil end
  local ok, _, tex = pcall(GetInventorySlotInfo, slotName)
  return ok and tex or nil
end

function G.SlotPage(slot, label, icon)
  local level, rows = UnitLevel("player"), {}
  local w = Worn(slot)
  rows[1] = { h = "Wearing" }
  if w then
    rows[2] = { t = w.name, i = w.id, q = w.quality, d = w.ilvl and ("Item level " .. w.ilvl) or nil }
  else
    rows[2] = { t = "Nothing", d = "Anything you can wear here is an upgrade." }
  end
  local now, random, later, ah, far = {}, {}, {}, {}, {}
  for _, e in ipairs(NS.Upgrades and NS.Upgrades.all or {}) do
    if Fits(e, slot) then
      local k = Kind(e)
      if k == "now" then now[#now + 1] = e elseif k == "random" then random[#random + 1] = e
      elseif k == "far" then far[#far + 1] = e
      elseif k == "later" then later[#later + 1] = e end
      if e.ah then ah[#ah + 1] = e end
    end
  end
  table.sort(now, function(a, b) return a.src.mins < b.src.mins end)
  table.sort(later, function(a, b)
    local la, lb = math.max(a.reqLevel or 0, a.src.req or 0), math.max(b.reqLevel or 0, b.src.req or 0)
    if la ~= lb then return la < lb end
    return a.gain > b.gain
  end)
  local function Add(head, list, n)
    if #list == 0 then return end
    rows[#rows + 1] = { h = head }
    for k = 1, math.min(#list, n) do rows[#rows + 1] = Entry(list[k], true, level) end
  end
  Add("Upgrades you can get now, quickest first", now, 12)
  Add("Random drops", random, 8)
  Add("Coming up", later, 8)
  Add("On another continent", far, 5)
  if #ah > 0 then
    rows[#rows + 1] = { h = "Auction House" }
    for k = 1, math.min(#ah, 6) do
      rows[#rows + 1] = { t = string.format("%s  (%s)", ah[k].name, Gain(ah[k])), i = ah[k].id, q = ah[k].quality, d = NS.Money(ah[k].ah) }
    end
  end
  local st = Status()
  if #now + #random + #later + #ah + #far == 0 then
    rows[#rows + 1] = { t = st and "Still looking" or "Nothing better found for this slot right now", d = st }
  elseif st then
    rows[#rows + 1] = { t = st, dim = true }
  end
  return { title = label, icon = (w and w.id and NS.ItemIcon(w.id)) or icon, rows = rows,
           sub = "Click an item for everything about it. Scores use your talent goal (Talents tab)." }
end

function G.SlotRows()
  local rows = {}
  local st = Status()
  for _, s in ipairs(G.SLOTS) do
    local slot, label = s[1], s[2]
    local w = Worn(slot)
    local best, n
    n = 0
    for _, e in ipairs(NS.Upgrades and NS.Upgrades.all or {}) do
      if Fits(e, slot) and Kind(e) == "now" then
        n = n + 1
        if not best or e.gain > best.gain then best = e end
      end
    end
    local icon = SlotIcon(s[3])
    local d = label
    if best then d = string.format("%s  ·  %d upgrade%s, best +%.1f", label, n, n == 1 and "" or "s", best.gain)
    elseif not st then d = label .. "  ·  nothing better nearby" end
    rows[#rows + 1] = { t = w and w.name or "Empty", d = d, i = w and w.id, tex = not (w and w.id) and (icon or NS.QUESTION_ICON) or nil,
                        q = w and w.quality, dim = not w or nil, key = "slot" .. slot,
                        page = function() return G.SlotPage(slot, label, icon) end }
  end
  if st then table.insert(rows, 1, { t = st, d = "Your slots fill in as it goes.", dim = true, key = "status" }) end
  return rows
end

---------------------------------------------------------------------------
-- The lists
---------------------------------------------------------------------------
function G.ListRows(mode)
  local level, rows = UnitLevel("player"), {}
  local all = NS.Upgrades and NS.Upgrades.all or {}
  local st = Status()
  local function Head(e) return string.format("%s  (%s)", e.name, Gain(e)) end
  local function Row(e, d) return { t = Head(e), d = e.slot .. "  ·  " .. d, i = e.id, q = e.quality, key = "item" .. e.id } end
  if mode == "ah" then
    local list = {}
    for _, e in ipairs(all) do if e.ah and (e.reqLevel or 0) <= level then list[#list + 1] = e end end
    table.sort(list, function(a, b) return a.gain > b.gain end)
    local money = GetMoney and GetMoney() or 0
    for k = 1, math.min(#list, 20) do
      rows[#rows + 1] = Row(list[k], NS.Money(list[k].ah) .. (list[k].ah > money and " (more than you have)" or ""))
    end
    if #rows == 0 then
      rows[1] = { t = "No Auction House upgrades in your last scan", d = "At the Auction House, press Scan on Sunstone's panel, then come back." }
    end
    return rows
  end
  local now, random, later = {}, {}, {}
  for _, e in ipairs(all) do
    local k = Kind(e)
    if k == "now" then now[#now + 1] = e elseif k == "random" then random[#random + 1] = e elseif k == "later" then later[#later + 1] = e end
  end
  if st then rows[#rows + 1] = { t = st, dim = true, key = "status" } end
  if mode == "best" then
    local bySlot, list = {}, {}
    for _, e in ipairs(all) do
      local k = Kind(e)
      if k == "now" or k == "random" then
        local key = e.slots[1]
        if not bySlot[key] or e.gain > bySlot[key].gain then bySlot[key] = e end
      end
    end
    for _, e in pairs(bySlot) do list[#list + 1] = e end
    table.sort(list, function(a, b) return a.gain > b.gain end)
    for _, e in ipairs(list) do rows[#rows + 1] = Row(e, SourceText(e)) end
  else
    if mode == "value" then
      table.sort(now, function(a, b) return a.gain / (a.src.mins + 5) > b.gain / (b.src.mins + 5) end)
    else
      table.sort(now, function(a, b) return a.src.mins < b.src.mins end)
    end
    local top, n = {}, 0
    for _, e in ipairs(now) do
      local key = e.slots[1]
      -- an item only counts if it beats every one listed before it for the same slot
      if not top[key] or e.gain > top[key] * 1.05 then
        top[key] = e.gain
        rows[#rows + 1] = Row(e, SourceText(e))
        n = n + 1
        if n >= 18 then break end
      end
    end
    table.sort(random, function(a, b) return a.gain > b.gain end)
    if #random > 0 then
      rows[#rows + 1] = { h = "Random drops" }
      for k = 1, math.min(#random, 6) do rows[#rows + 1] = Row(random[k], SourceText(random[k])) end
    end
  end
  table.sort(later, function(a, b)
    local la, lb = math.max(a.reqLevel or 0, a.src.req or 0), math.max(b.reqLevel or 0, b.src.req or 0)
    if la ~= lb then return la < lb end
    return a.gain > b.gain
  end)
  if #later > 0 and mode ~= "best" then
    rows[#rows + 1] = { h = "Coming up" }
    for k = 1, math.min(#later, 8) do
      local e = later[k]
      local l = math.max(e.reqLevel or 0, e.src.req or 0)
      rows[#rows + 1] = Row(e, (l > level and ("level " .. l .. ", ") or "") .. e.src.label)
    end
  end
  if #rows == 0 then rows[1] = { t = "Nothing better found right now", d = "Sunstone looks again when you level up, hand in a quest or change your gear." } end
  return rows
end
