-- Sunstone: the Pets & Mounts tab. Every companion pet and mount there's data for: how to get it (who sells it and for
-- what, what drops it and how often, its quest, craft, holiday), what it takes to use it, and which ones you have.
-- Data: CollectData.lua (Questie's Forever data, Classic's drop tables) and Questie live. What nobody has recorded yet is
-- listed as that: nothing here guesses.

local _, NS = ...
local C = NS.Module("Collect")
NS.Collect = C
local E = NS.Engine
local I = "Interface\\Icons\\"

C.MODES = {
  { "pets", "Pets", "Companion pets: how to get each one" },
  { "mounts", "Mounts", "Every mount: how to get each one" },
}
C.SHOW = { { "all", "All" }, { "miss", "Missing" }, { "got", "Got" } }
function C.Mode()
  local m = NS.cdb and NS.cdb.collectMode
  for _, x in ipairs(C.MODES) do if x[1] == m then return x end end
  return C.MODES[1]
end
function C.Show()
  local m = NS.cdb and NS.cdb.collectShow
  for _, x in ipairs(C.SHOW) do if x[1] == m then return x end end
  return C.SHOW[1]
end
C.find = ""

local function Src() return type(_G.SunstoneCollect) == "table" and _G.SunstoneCollect or {} end
local function List(t) return type(t) == "table" and t or {} end
local function Lib() return NS.Quests() end
local function Side(npc) -- "Alliance" / "Horde" when an NPC only deals with one of them
  local L = Lib()
  local ok, f = false, nil
  if L and L.Npc then ok, f = pcall(L.Npc.Get, npc, "friendlyToFaction") end
  if ok and f == "A" then return "Alliance" elseif ok and f == "H" then return "Horde" end
end
local function Mine() return (UnitFactionGroup and UnitFactionGroup("player")) or "Horde" end

---------------------------------------------------------------------------
-- Drop chances (recipes use these too)
---------------------------------------------------------------------------
-- Every creature worth killing for an item: { npc, chance (0-1 or nil), from }, best first; and how many can drop it in all
function C.Drops(item, extra)
  local r = List(Src().rate)[item]
  local out, seen = {}, {}
  local Fm = NS.Farm
  local shared = {}
  for _, s in ipairs(NS.Community and NS.Community.Sources(item) or {}) do if s.kind == 1 then shared[s.id] = s end end
  local function Add(npc, base)
    if seen[npc] then return end
    seen[npc] = true
    local p, from = base, base and "Classic's tables" or nil
    if Fm and Fm.Chance then
      local ok, v, f = pcall(Fm.Chance, item, npc)
      -- your own corpses, weighed against Classic's number, when there are enough of them
      if ok and type(v) == "number" and v > 0 and not base then p, from = v, f end
      local rec = NS.db and NS.db.rec and NS.db.rec.mobs and NS.db.rec.mobs[npc]
      local corpses = rec and rec.l or 0
      if base and corpses >= 20 then
        local mine = (List(rec.i)[item] or 0)
        if mine > 0 then
          p = (mine + 20 * base) / (corpses + 20)
          from = string.format("Classic's tables and your %d corpses", corpses)
        end
      end
    end
    out[#out + 1] = { npc = npc, p = p, from = from }
  end
  if r then for k = 4, #r, 2 do Add(r[k], r[k + 1]) end end
  for _, id in ipairs(List(extra)) do Add(id) end
  for id, s in pairs(shared) do
    Add(id)
    for _, e in ipairs(out) do
      if e.npc == id and not e.p and s.of >= 20 and s.n > 0 then e.p, e.from = s.n / s.of, string.format("%d of %d corpses of %d players", s.n, s.of, s.players) end
    end
  end
  table.sort(out, function(a, b) return (a.p or 0) > (b.p or 0) end)
  return out, r and r[1] or #out, r and r[2], r and r[3]
end

function C.Percent(p)
  local v = p * 100
  if v >= 10 then return string.format("%d%%", v + 0.5) elseif v >= 1 then return string.format("%.1f%%", v) end
  return string.format(v >= 0.1 and "%.2f%%" or "%.3f%%", v)
end
local function Kills(p)
  local n = math.floor(1 / p + 0.5)
  return n <= 1 and "every time" or string.format("about %s kills on average", BreakUpLargeNumbers and BreakUpLargeNumbers(n) or n)
end

-- Rows for an item's drops: the best for you first (chance, the time a kill takes, how far), a note for world drops
function C.DropRows(item, extra, max)
  local list, total, lo, hi = C.Drops(item, extra)
  local rows, L = {}, UnitLevel("player")
  local Fm = NS.Farm
  for _, d in ipairs(list) do
    local p, mins = E.Nearest(E.Points("Npc", d.npc))
    local kill = 60
    if Fm and Fm.KillTime then local ok, t = pcall(Fm.KillTime, d.npc); if ok and type(t) == "number" then kill = t end end
    d.place, d.mins = p, (mins or 60) + (d.p and kill / d.p / 60 or 600)
    local _, a = pcall(function() return Lib().Npc.Get(d.npc, "minLevel") end)
    d.lvl = type(a) == "number" and a or nil
    if d.lvl and d.lvl > L + 4 then d.mins = d.mins + 5000 end
  end
  table.sort(list, function(a, b) return a.mins < b.mins end)
  local top = 0
  for _, d in ipairs(list) do top = math.max(top, d.p or 0) end
  for k = 1, math.min(max or 5, #list) do
    local d = list[k]
    local c = E.Creature(d.npc)
    local bits = {}
    if c ~= "" then bits[1] = c:gsub("^%l", string.upper) .. (d.lvl and d.lvl > L + 4 and " (too high for you yet)" or "") end
    if d.p then bits[#bits + 1] = Kills(d.p):gsub("^%l", string.upper) .. (d.from and (", by " .. d.from) or "")
    else bits[#bits + 1] = "How often isn't known yet" end
    if d.place then bits[#bits + 1] = E.PlaceText(d.place) else bits[#bits + 1] = "Where it lives isn't recorded (often inside a dungeon)" end
    rows[#rows + 1] = E.At({ t = "Drops from " .. E.NpcName(d.npc) .. (d.p and ("  " .. C.Percent(d.p)) or ""), d = table.concat(bits, ".\n") }, d.place)
    rows[#rows].mins = d.mins
  end
  if total > #rows then
    rows[#rows + 1] = { t = string.format("%d creatures can drop it in all", total),
                        d = (lo and string.format("Level %d to %d. ", lo, hi) or "") .. (total > 40 and top < 0.005
                          and "A world drop: don't hunt it on purpose, watch the Auction House and keep your eyes open." or "The best ones for you are above."),
                        still = true, mins = 9000 }
  end
  for _, s in ipairs(NS.Community and NS.Community.Sources(item) or {}) do -- what players found
    if s.kind ~= 1 then
      local p = (s.kind == 5 or s.kind == 2) and E.Nearest(E.Points(s.kind == 5 and "Npc" or "Object", s.id)) or nil
      local name = NS.Finds.SourceName(s.kind, s.id)
      rows[#rows + 1] = E.At({ t = NS.Finds.KIND[s.kind]:gsub("^%l", string.upper) .. " " .. name .. (s.of >= 20 and s.n > 0 and ("  " .. C.Percent(s.n / s.of)) or ""),
                               d = string.format("Found by %d player%s%s.", s.players, s.players == 1 and "" or "s", s.players < 3 and " (not confirmed by many yet)" or "") .. (p and ("\n" .. E.PlaceText(p)) or ""),
                               i = s.kind == 3 and s.id or nil }, p)
    end
  end
  for _, e in ipairs({ List(Src().chest)[item] or {} }) do
    for k = 1, #e, 3 do
      local p = E.Nearest(E.Points("Object", e[k]))
      rows[#rows + 1] = E.At({ t = "In " .. e[k + 2] .. "  " .. C.Percent(e[k + 1]), d = p and E.PlaceText(p) or "Where it stands isn't recorded (often inside a dungeon)." }, p)
    end
  end
  local ins = List(Src().inside)[item]
  if ins then
    for k = 1, #ins, 2 do rows[#rows + 1] = { t = "Inside " .. E.ItemName(ins[k]) .. "  " .. C.Percent(ins[k + 1]), i = ins[k], d = "Open it to see." } end
  end
  return rows, top, total
end

-- an item's price at the Auction House, when one has been seen
function C.AuctionRow(item)
  local Fm = NS.Farm
  if not (Fm and Fm.Price) then return nil end
  local ok, p = pcall(Fm.Price, item)
  local ok2, vendor = pcall(E.VendorPrice, item)
  local text = ok and type(p) == "number" and p > 0 and Fm.PriceText and select(2, pcall(Fm.PriceText, item)) or nil
  if not (type(text) == "string" and text:find("uction", 1, true)) then return nil end
  return { t = "On the Auction House: " .. NS.Money(p), d = text, still = true, vendor = ok2 and vendor or nil }
end

---------------------------------------------------------------------------
-- What you have
---------------------------------------------------------------------------
-- The game's own journals when it has them, your bags, else what you marked yourself
local names, namesAt
local function Companions()
  if names and GetTime() - namesAt < 10 then return names end
  names, namesAt = {}, GetTime()
  if GetNumCompanions and GetCompanionInfo then
    for _, kind in ipairs({ "CRITTER", "MOUNT" }) do
      local ok, n = pcall(GetNumCompanions, kind)
      for k = 1, ok and tonumber(n) or 0 do
        local ok2, _, name = pcall(GetCompanionInfo, kind, k)
        if ok2 and type(name) == "string" then names[name:lower()] = true end
      end
    end
  end
  return names
end
local function Plain(n) -- "Cat Carrier (Bombay)" -> "bombay", "Reins of the Pack Kodo" -> "pack kodo"
  local inner = n:match("%((.-)%)")
  n = inner or n
  for _, p in ipairs({ "^Reins of the ", "^Horn of the ", "^Whistle of the ", "^Scroll of " }) do n = n:gsub(p, "") end
  return n:lower()
end
function C.Owned(e, mount)
  local got = NS.cdb.got
  if type(got) == "table" and got[e.id] ~= nil then return got[e.id], "marked" end
  if E.Have(e.id) > 0 then return true, "bags" end
  if mount and C_MountJournal and C_MountJournal.GetMountFromItem then
    local ok, mid = pcall(C_MountJournal.GetMountFromItem, e.id)
    if ok and type(mid) == "number" then
      local r = { pcall(C_MountJournal.GetMountInfoByID, mid) }
      if r[1] and r[12] ~= nil then return r[12] == true, "journal" end
    end
  elseif not mount and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
    local r = { pcall(C_PetJournal.GetPetInfoByItemID, e.id) }
    local species = r[1] and r[14]
    if type(species) == "number" and C_PetJournal.GetNumCollectedInfo then
      local ok, n = pcall(C_PetJournal.GetNumCollectedInfo, species)
      if ok and type(n) == "number" then return n > 0, "journal" end
    end
  end
  if Companions()[Plain(e.n)] then return true, "journal" end
  return false
end
function C.Mark(e, on)
  NS.cdb.got = type(NS.cdb.got) == "table" and NS.cdb.got or {}
  NS.cdb.got[e.id] = on
  if NS.Window then NS.Window.Refresh() end
end

---------------------------------------------------------------------------
-- Rows and pages
---------------------------------------------------------------------------
local HORDE, ALLIANCE = 2 + 16 + 32 + 128, 1 + 4 + 8 + 64
local function Bits(mask, want) -- does the mask share a bit with `want`? (both small)
  local b = 1
  while b <= 1024 do
    if mask % (2 * b) >= b and want % (2 * b) >= b then return true end
    b = b * 2
  end
  return false
end
-- which side it's for, when it's only for one
function C.Faction(e)
  if e.race then
    local h, a = Bits(e.race, HORDE), Bits(e.race, ALLIANCE)
    if h and not a then return "Horde" elseif a and not h then return "Alliance" end
  end
  if e.v and not e.d and not e.q then
    local side
    for _, id in ipairs(e.v) do
      local s = Side(id)
      if not s then return nil end
      if side and side ~= s then return nil end
      side = s
    end
    return side
  end
end

local GROUPS = { "Sold by vendors", "Drops", "Quests", "Made with a profession", "Holidays, promotions and the store", "Nobody has recorded where it comes from yet" }
local function Group(e)
  if e.short then return 3 end
  if e.v then return 1 end
  if (e.d or List(Src().rate)[e.id]) and not (e.note and e.q) then return 2 end
  if e.q then return 3 end
  if e.craft then return 4 end
  if e.note then return 5 end
  if List(Src().chest)[e.id] or List(Src().inside)[e.id] then return 2 end
  local s = NS.Community and NS.Community.Sources(e.id)[1]
  if s then return s.kind == 5 and 1 or s.kind == 6 and 3 or 2 end
  return 6
end
local function Short(e)
  if e.short then return e.short end
  local g = Group(e)
  local found = NS.Community and NS.Community.Sources(e.id)[1]
  if found and not (e.v or e.d or e.q or e.craft or e.note or List(Src().rate)[e.id]) then
    return NS.Finds.KIND[found.kind]:gsub("^%l", string.upper) .. " " .. NS.Finds.SourceName(found.kind, found.id)
  end
  if g == 1 then
    local id = e.v[1]
    local best, bm
    for _, v in ipairs(e.v) do
      local s = Side(v)
      local p, m = E.Nearest(E.Points("Npc", v))
      if (not s or s == Mine()) and p and (not bm or m < bm) then best, bm, id = p, m, v end
    end
    return E.NpcName(id) .. (best and (", " .. (E.Where(best):gsub(" [%d%.]+, [%d%.]+$", ""))) or "")
  elseif g == 2 then
    local l = C.Drops(e.id, e.d)
    return l[1] and (E.NpcName(l[1].npc) .. (l[1].p and ("  " .. C.Percent(l[1].p)) or "")) or "Found"
  elseif g == 3 then return "Quest: " .. E.QuestName(e.q[1])
  elseif g == 4 then return string.format("%s %d", e.craft[1], e.craft[2])
  elseif g == 5 then return (e.note:match("^[^%.]+") or ""):sub(1, 70) end
  return nil
end

function C.Page(e, mount)
  local rows = {}
  local own, how = C.Owned(e, mount)
  local need = {}
  if e.lv then need[#need + 1] = "level " .. e.lv end
  if e.ride then need[#need + 1] = e.ride >= 150 and "epic riding (150)" or "riding (75)" end
  local side = C.Faction(e)
  rows[1] = { t = own and "You have it" or "You don't have it yet", ring = own and "good" or nil, i = e.id,
              d = (how == "journal" and "The game says so." or how == "bags" and "It's in your bags." or how == "marked" and "You marked it."
                or "If that's wrong, mark it with the button.") .. (#need > 0 and ("\nNeeds " .. table.concat(need, ", ") .. ".") or "") .. (side and ("\n" .. side .. " only.") or "")
                .. (e.new and "\nNew in Forever." or ""),
              actLabel = own and "Not mine" or "Got it", act = function() C.Mark(e, not own) end }
  local looks = type(_G.SunstoneLooks) == "table" and type(_G.SunstoneLooks.item) == "table" and _G.SunstoneLooks.item[e.id]
  if looks and NS.Look then
    table.insert(rows, 1, NS.Look.PicturePanel("collect", { npc = looks[1], display = looks[2] ~= 0 and looks[2] or nil, icon = NS.ItemIcon(e.id), title = e.n,
      sub = (mount and "Mount" or "Companion pet") .. (e.new and ", new in Forever" or ""), lines = { own and "|cff" .. NS.HEX.good .. "Yours|r" or Short(e) or "" },
      art = mount and "Interface\\TalentFrame\\WarriorArms-" or "Interface\\TalentFrame\\DruidRestoration-" }))
  end
  rows[#rows + 1] = { h = "How to get it" }
  local n0 = #rows
  if e.note then rows[#rows + 1] = { t = e.note, still = true } end
  for _, id in ipairs(e.v or {}) do
    local p = E.Nearest(E.Points("Npc", id))
    local s = Side(id)
    local bits = {}
    if p then bits[1] = E.PlaceText(p) end
    local price = e.p or E.VendorPrice(e.id, id)
    if price and price > 0 then bits[#bits + 1] = NS.Money(price) .. (s and s ~= Mine() and "" or " (less with a good reputation)") end
    if e.rep then
      for _, f in ipairs(E.Data().factions) do
        if f.id == e.rep[1] then bits[#bits + 1] = "Needs standing with " .. f.n .. " (" .. E.StandingText(f.id) .. ")" end
      end
    end
    rows[#rows + 1] = E.At({ t = "Sold by " .. E.NpcName(id) .. (s and ("  (" .. s .. ")") or ""), d = table.concat(bits, "\n"), dim = s and s ~= Mine() or nil }, p)
  end
  for _, qid in ipairs(e.q or {}) do
    local qr = E.QuestRoute(qid)
    rows[#rows + 1] = E.At({ t = "Quest: " .. E.QuestName(qid), d = qr and qr.d or nil, q = nil }, qr and qr.place)
  end
  if e.craft then rows[#rows + 1] = { t = string.format("Made with %s %d", e.craft[1], e.craft[2]), d = "See Professions, Find a recipe." } end
  if e.d or List(Src().rate)[e.id] or List(Src().chest)[e.id] or List(Src().inside)[e.id] or (NS.Community and NS.Community.Sources(e.id)[1]) then
    for _, r in ipairs((C.DropRows(e.id, e.d, 6))) do rows[#rows + 1] = r end
  end
  local ah = C.AuctionRow(e.id)
  if ah then rows[#rows + 1] = ah end
  if #rows == n0 then
    rows[#rows + 1] = { t = "Nobody has recorded where it comes from yet",
                        d = "The game's data has it, but neither Questie nor the guides know how to get it on Forever so far.", still = true }
  end
  return { title = e.n, icon = NS.ItemIcon(e.id), rows = rows, sub = (mount and "Mount" or "Companion pet") .. (e.new and ", new in Forever" or "") }
end

function C.Rows()
  local mount = C.Mode()[1] == "mounts"
  local list = List(mount and Src().mounts or Src().pets)
  local show, find = C.Show()[1], (C.find or ""):lower()
  local rows, groups, got, total = {}, {}, 0, 0
  for _, e in ipairs(list) do
    local own = C.Owned(e, mount)
    total = total + 1
    if own then got = got + 1 end
    local short
    local hit = find == "" or e.n:lower():find(find, 1, true)
    if not hit then
      short = Short(e)
      hit = (short and short:lower():find(find, 1, true)) or (e.note and e.note:lower():find(find, 1, true)) or (find == "new" and e.new)
    end
    if hit and (show == "all" or (show == "got") == own) then
      local g = Group(e)
      groups[g] = groups[g] or {}
      local side = C.Faction(e)
      table.insert(groups[g], { t = e.n, d = short or Short(e), i = e.id, ring = own and "good" or nil, dim = (side and side ~= Mine()) or nil, key = "col" .. e.id,
                                other = (side and side ~= Mine()) and 1 or 0, page = function() return C.Page(e, mount) end })
    end
  end
  rows[1] = { t = string.format("%d of %d %s", got, total, mount and "mounts" or "pets"), tex = I .. (mount and "Ability_Mount_RidingHorse" or "INV_Box_PetCarrier_01"),
              d = "Showing " .. (show == "all" and "all of them" or show == "miss" and "the ones you're missing" or "the ones you have"), key = "colall",
              page = function() return C.About(mount) end }
  for g, name in ipairs(GROUPS) do
    local l = groups[g]
    if l then
      table.sort(l, function(a, b) if a.other ~= b.other then return a.other < b.other end return a.t < b.t end)
      rows[#rows + 1] = { h = string.format("%s (%d)", name, #l) }
      for _, r in ipairs(l) do rows[#rows + 1] = r end
    end
  end
  if #rows == 1 then rows[2] = { t = "Nothing matches", d = find ~= "" and "Clear the search box, or try part of a name, a zone or a vendor." or nil } end
  return rows
end

function C.About(mount)
  local rows = {
    { t = mount and "Mounts" or "Companion pets",
      d = mount and "From level 40 you can ride (60% faster) after learning Riding from your race's riding trainer; epic mounts (100% faster) come at 60. Paladins and "
        .. "warlocks learn a mount as a class spell." or "Companions follow you around and do nothing else: they're for fun and for collecting." },
    { t = "Search box above", d = "Type part of a name, a zone, a vendor or \"new\" (new in Forever). All / Missing / Got narrows the list.", still = true },
    { t = "Green ring: you have it", d = "From the game's own list when it has one, from your bags, or marked by you (Got it on its page).", still = true },
  }
  local list = List(mount and Src().mountsUnknown or Src().petsUnknown)
  if #list > 0 then
    rows[#rows + 1] = { h = "Seen in Forever's data, source unknown" }
    for _, n in ipairs(list) do rows[#rows + 1] = { t = n, still = true } end
    rows[#rows + 1] = { t = "Nobody has found these in the game yet", d = "They're in the game's files. Some may never be released.", still = true }
  end
  return { title = mount and "Mounts" or "Companion pets", icon = I .. (mount and "Ability_Mount_RidingHorse" or "INV_Box_PetCarrier_01"), rows = rows }
end
