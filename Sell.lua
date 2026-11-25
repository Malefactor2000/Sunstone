-- Sunstone: "Can I sell this?" For every item: sell it to a vendor, list it on the Auction House, keep it, or not sure, and why.
-- A line on the item's tooltip, and your bags sorted by it (Gold tab, Your bags). Reads only: it never sells, clicks, moves or
-- destroys anything, and it never tells you to destroy something. What it doesn't know it calls "not sure".

local _, NS = ...
local S = NS.Module("Sell")
NS.Sell = S
local E = NS.Engine
local I = "Interface\\Icons\\"

local function List(t) return type(t) == "table" and t or {} end
local function Set(...) local o = {} for _, v in ipairs({ ... }) do o[v] = true end return o end

local TOOLS = Set(6948, 2901, 7005, 5956, 6218, 6339, 11130, 11145, 16207, 6219, 10498, 4471, 9149, 6256, 5060, 6365, 6366, 6367, 19022, 12225, 5175, 5176, 5177, 5178)
local WORD = { sell = "Sell it", ah = "Auction House", keep = "Keep it", use = "Use it or sell it", unsure = "Not sure" }
local HEX = { sell = "8aa666", ah = "6fa8c9", keep = "c99734", use = "8aa666", unsure = "9a968c" }
S.WORD, S.HEX = WORD, HEX

---------------------------------------------------------------------------
-- What wants an item
---------------------------------------------------------------------------
local uses -- [item] = { { prof, recipe }, ... }
function S.Recipes(id)
  if not uses then
    uses = {}
    for prof, list in pairs(E.Data().recipes or {}) do
      for _, r in ipairs(list) do
        for k = 1, #(r.r or {}), 2 do
          local m = r.r[k]
          uses[m] = uses[m] or {}
          table.insert(uses[m], { prof, r })
        end
      end
    end
  end
  return uses[id] or {}
end

local camp -- camp objects, by the recipes that make them, and campfire kits
function S.Camp(id)
  if not camp then
    camp = {}
    for _, list in pairs(E.Data().recipes or {}) do
      for _, r in ipairs(list) do if r.i and (r.cat == "Camping" or (r.n or ""):find("Campfire Kit", 1, true)) then camp[r.i] = true end end
    end
  end
  return camp[id] or false
end

local function Q(kind, id, field)
  local L = NS.Quests()
  local db = L and L[kind]
  if not db then return nil end
  local ok, v = pcall(db.Get, id, field)
  return ok and v or nil
end

-- the items a quest wants or hands out: its objectives, what they're made from, what the giver gave you
local function QuestItems(qid, fn)
  local o = Q("Quest", qid, "objectives")
  for _, e in pairs(List(List(o)[3])) do local i = type(e) == "table" and e[1] or e; if type(i) == "number" then fn(i) end end
  for _, i in pairs(List(Q("Quest", qid, "requiredSourceItems"))) do if type(i) == "number" then fn(i) end end
  local s = Q("Quest", qid, "sourceItemId")
  if type(s) == "number" and s > 0 then fn(s) end
end
local index -- [item] = { quest, ... } for every quest there is; built once in the background
function S.BuildIndex()
  local L = NS.Quests()
  if index or not (L and L.Quest and L.Quest.GetAllIds) then return end
  E.Job("item quests", function()
    local idx = {}
    for _, qid in ipairs(L.Quest.GetAllIds()) do
      E.Yield()
      QuestItems(qid, function(i) idx[i] = idx[i] or {}; table.insert(idx[i], qid) end)
    end
    return idx
  end, function(idx)
    index = idx
    S.Forget()
    if NS.Window and NS.Window.tab == "gold" and NS.Window.DataChanged then NS.Window.DataChanged() end
  end)
end
function S.Indexed() return index ~= nil end

-- quests that need it and you could still do: { id, inLog, level }
function S.Quests(id)
  local out, seen = {}, {}
  local log = E.Log()
  local function Add(qid, starts)
    if type(qid) ~= "number" or seen[qid] or E.Done(qid) then return end
    seen[qid] = true
    if not log[qid] and not E.QuestOK(qid) then return end
    out[#out + 1] = { id = qid, log = log[qid] ~= nil, level = tonumber(Q("Quest", qid, "requiredLevel")) or 0, starts = starts }
  end
  Add(Q("Item", id, "startQuest"), true)
  for qid in pairs(log) do QuestItems(qid, function(i) if i == id then Add(qid) end end) end
  for _, qid in ipairs(index and index[id] or {}) do Add(qid) end
  for _, qid in pairs(List(Q("Item", id, "relatedQuests"))) do Add(qid) end
  table.sort(out, function(a, b) if a.log ~= b.log then return a.log end return a.level < b.level end)
  return out
end

---------------------------------------------------------------------------
-- The verdict: { v, why, vendor, ah (what to count on), ahText }
---------------------------------------------------------------------------
local cache, cacheAt = {}, 0
function S.Forget() cache = {} end

local function Money(c) return NS.Money(math.floor((c or 0) + 0.5)) end

local function Work(id, link, bound)
  local name, l2, quality, _, reqLevel, _, _, _, equipLoc, _, vendor, class, sub, bind = NS.GetItemInfo(link or id)
  if not name then return nil end
  if class == nil then
    local _, _, _, _, _, c, s = NS.GetItemInfoInstant(id)
    class, sub = c, s
  end
  link = link or l2
  local L = UnitLevel("player") or 1
  local r = { id = id, name = name, quality = quality, vendor = (type(vendor) == "number" and vendor > 0) and vendor or nil }
  local function Say(v, why) r.v, r.why = v, why return r end
  -- what it goes for at the Auction House (nil when nobody has seen one, or you can't sell it)
  local soul = bound or bind == 1 or bind == 4 or class == 12
  if not soul then
    local Fm = NS.Farm
    if Fm and Fm.Price then
      local ok, p, where = pcall(Fm.Price, id)
      if ok and where == "Auction House" then r.ah = p end
    end
    if not r.ah and NS.Auction and NS.Auction.Price then
      local p = NS.Auction.Price(id)
      if type(p) == "number" and p > 0 then r.ah, r.once = p * 0.95, true end
    end
    if r.ah and NS.Auction and NS.Auction.Age then r.age = NS.Auction.Age(id) end
  end
  if TOOLS[id] then return Say("keep", "A tool you may need.") end
  if S.Camp(id) then return Say("keep", "For campsites: see Guide, Forever's systems.") end
  -- quests
  local qs = S.Quests(id)
  r.quests = qs
  local soon
  for _, x in ipairs(qs) do
    if x.starts then return Say("keep", "It starts the quest " .. E.QuestName(x.id) .. ".") end
    if x.log then return Say("keep", "Your quest " .. E.QuestName(x.id) .. " needs it.") end
    if not soon and x.level <= L + 5 then soon = x end
  end
  if class == 12 then return Say("unsure", "A quest item, but none of your quests is known to need it. Read its tooltip before you part with it.") end
  if class == 13 then return Say("keep", "A key.") end
  -- recipes you could learn
  if class == 9 then
    for prof, list in pairs(E.Data().recipes or {}) do
      for _, rec in ipairs(list) do
        if rec.ri == id then
          local rank = E.Skill(prof)
          if rank and not (NS.Professions and NS.Professions.Known and NS.Professions.Known(rec)) then
            return Say("keep", string.format("You can learn it%s: %s %s.", rank < (rec.k or 0) and " later" or "", prof, rec.k or ""))
          end
        end
      end
    end
  end
  -- gear
  if (class == 2 or class == 4) and equipLoc and equipLoc ~= "" and NS.Upgrades and NS.Upgrades.GainOf then
    local gain = NS.Upgrades.GainOf(link)
    if gain and gain > 0.5 then
      return Say("keep", (reqLevel or 0) > L and string.format("An upgrade for you at level %d (+%.1f).", reqLevel, gain) or string.format("An upgrade for you (+%.1f): put it on.", gain))
    end
  end
  -- your own professions
  local rec = S.Recipes(id)
  r.recipes = rec
  local mine, other, gray = {}, {}, 0
  for _, e in ipairs(rec) do
    local rank = E.Skill(e[1])
    if rank then
      if rank >= (e[2].x or 999) then gray = gray + 1 else mine[e[1]] = (mine[e[1]] or 0) + 1 end
    else other[e[1]] = (other[e[1]] or 0) + 1 end
  end
  local prof, n = next(mine)
  for p2, n2 in pairs(mine) do if n2 > n then prof, n = p2, n2 end end
  if prof then return Say("keep", string.format("You use it: %s (%d recipe%s that still raise your skill).", prof, n, n == 1 and "" or "s")) end
  if soon and (class == 0 or class == 7) then -- cloth, herbs, food: plenty of repeatable quests take those, so that alone is no reason to hoard
    r.alt = "A quest you could do takes it: " .. E.QuestName(soon.id) .. (soon.level > L and (" (from level " .. soon.level .. ")") or "") .. "."
  elseif soon then return Say("keep", "A quest you can do soon wants it: " .. E.QuestName(soon.id) .. (soon.level > L and (" (from level " .. soon.level .. ")") or "") .. ".") end
  for _, alt in ipairs(E.AltsWith and (function() local out = {} for p3 in pairs(other) do for _, a in ipairs(E.AltsWith(p3) or {}) do out[#out + 1] = { a, p3 } end end return out end)() or {}) do
    r.alt = r.alt or string.format("%s could use it (%s).", alt[1].name or "Another character", alt[2])
  end
  -- worth listing?
  if r.ah and r.ah > (r.vendor or 0) * 1.4 + 30 and (quality or 1) > 0 then
    return Say("ah", string.format("About %s there against %s at a vendor%s.", Money(r.ah), r.vendor and Money(r.vendor) or "nothing", r.once and " (one price seen)" or ""))
  end
  if class == 1 or class == 11 then return Say("unsure", "A bag or quiver: keep it if it's bigger than one you wear.") end
  if class == 6 then return Say("keep", "Ammunition.") end
  if class == 5 then return Say("unsure", "A reagent: keep it if one of your spells uses it.") end
  if class == 0 and quality ~= 0 then return Say("use", r.vendor and ("Food, potion or the like. " .. Money(r.vendor) .. " each at a vendor.") or "Food, potion or the like.") end
  if quality == 0 then return Say(r.vendor and "sell" or "unsure", r.vendor and ("Vendor trash: " .. Money(r.vendor) .. " each.") or "Worth nothing at a vendor, and nothing known wants it.") end
  if not r.vendor then return Say("unsure", "A vendor won't buy it, and nothing known wants it.") end
  if class == 2 or class == 4 then
    local rank = E.Skill("Enchanting")
    return Say("sell", (rank and (quality or 1) >= 2 and "Not an upgrade for you: disenchant it, or sell it for " or "Not an upgrade for you. ") .. Money(r.vendor) .. (rank and (quality or 1) >= 2 and "." or " at a vendor."))
  end
  local words = {}
  for p4, n4 in pairs(other) do words[#words + 1] = p4 .. " (" .. n4 .. ")" end
  table.sort(words)
  if #words > 0 then return Say("sell", "You don't use it; others do: " .. table.concat(words, ", ") .. ". " .. Money(r.vendor) .. " at a vendor. No Auction House price seen yet." ) end
  if gray > 0 then return Say("sell", "Only recipes that no longer raise your skill use it. " .. Money(r.vendor) .. " at a vendor.") end
  if class == 7 or class == 15 then return Say("sell", "Nothing of yours wants it. " .. Money(r.vendor) .. " at a vendor.") end
  return Say("unsure", "Nothing known wants it. " .. Money(r.vendor) .. " at a vendor.")
end

function S.Verdict(id, link, bound)
  if type(id) ~= "number" then return nil end
  local now = GetTime()
  if now - cacheAt > 45 then cache, cacheAt = {}, now end
  local key = (link or id) .. (bound and "b" or "")
  local c = cache[key]
  if c == nil then
    local ok, v = pcall(Work, id, link, bound)
    if not ok then NS.Error("can I sell this", v) v = nil end
    c = v or false
    if c then cache[key] = c end -- (nothing is remembered while the game hasn't loaded the item)
  end
  return c or nil
end

---------------------------------------------------------------------------
-- The tooltip
---------------------------------------------------------------------------
function S.TipOn() return NS.db and NS.db.sellTip ~= false end
function S.SetTip(on) NS.db.sellTip = on and true or false if NS.Window then NS.Window.Refresh() end end

local function AddLine(tip, id, link)
  if not S.TipOn() or not (tip and tip.AddLine) then return end
  local v = S.Verdict(id, link)
  if not v then return end
  tip:AddLine("|cff" .. "8f7d68" .. "Sunstone:|r |cff" .. HEX[v.v] .. WORD[v.v] .. "|r", 1, 1, 1)
  tip:AddLine(v.why, 0.72, 0.69, 0.62, true)
  if v.alt and v.v ~= "keep" then tip:AddLine(v.alt, 0.72, 0.69, 0.62, true) end
end
S.AddLine = AddLine

local function Hook()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
      local id = type(data) == "table" and data.id
      if type(id) == "number" then NS.Safe("can I sell this", AddLine, tip, id, type(data.hyperlink) == "string" and data.hyperlink or nil) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tip)
      local _, link = tip:GetItem()
      local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
      if id then NS.Safe("can I sell this", AddLine, tip, id, link) end
    end)
  end
end

---------------------------------------------------------------------------
-- Your bags
---------------------------------------------------------------------------
function S.Bags()
  local out, by = {}, {}
  local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local info = C_Container and C_Container.GetContainerItemInfo
  if not (slots and info) then return out end
  for bag = 0, 4 do
    for slot = 1, tonumber(slots(bag)) or 0 do
      local ok, i = pcall(info, bag, slot)
      if ok and type(i) == "table" and i.itemID then
        local key = i.itemID .. (i.isBound and "b" or "")
        local e = by[key]
        if not e then
          e = { id = i.itemID, link = i.hyperlink, bound = i.isBound, n = 0, stacks = 0 }
          by[key] = e
          out[#out + 1] = e
        end
        e.n, e.stacks = e.n + (i.stackCount or 1), e.stacks + 1
      end
    end
  end
  return out
end

function S.Page(e, v)
  local rows = { { t = "|cff" .. HEX[v.v] .. WORD[v.v] .. "|r", d = v.why .. (v.alt and ("\n" .. v.alt) or ""), i = e.id, still = true } }
  local bits = {}
  if v.vendor then bits[#bits + 1] = Money(v.vendor) .. " each at a vendor" .. (e.n > 1 and string.format(", %s for all %d", Money(v.vendor * e.n), e.n) or "") end
  local ok, text = false, nil
  if NS.Farm and NS.Farm.PriceText then ok, text = pcall(NS.Farm.PriceText, e.id) end
  if ok and type(text) == "string" and text:find("uction", 1, true) then bits[#bits + 1] = text
  elseif v.ah then bits[#bits + 1] = "About " .. Money(v.ah) .. " at the Auction House (one price seen)" .. (type(v.age) == "number" and v.age > 0 and (", " .. v.age .. " days ago") or "") end
  rows[#rows + 1] = { t = "What it's worth", d = #bits > 0 and table.concat(bits, "\n") or "No price known.", still = true }
  if #List(v.quests) > 0 then
    rows[#rows + 1] = { h = "Quests that want it" }
    for k, x in ipairs(v.quests) do
      if k <= 8 then rows[#rows + 1] = { t = E.QuestName(x.id), d = (x.log and "In your log" or x.starts and "It starts this quest" or (x.level > 0 and ("From level " .. x.level) or "")), still = true } end
    end
  end
  local rec = S.Recipes(e.id)
  if #rec > 0 then
    rows[#rows + 1] = { h = string.format("Recipes that use it (%d)", #rec) }
    table.sort(rec, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return (a[2].k or 0) < (b[2].k or 0) end)
    for k, x in ipairs(rec) do
      if k <= 30 then
        x[2].prof = x[2].prof or x[1]
        rows[#rows + 1] = { t = x[2].n, d = x[1] .. " " .. (x[2].k or "?"), i = x[2].i, q = x[2].q, page = NS.Professions and function() return NS.Professions.RecipePage(x[2]) end or nil }
      end
    end
  end
  rows[#rows + 1] = { t = "More about it", i = e.id, d = "Every way to get it" }
  return { title = v.name, icon = NS.ItemIcon(e.id), rows = rows, sub = "Can I sell this?" }
end

local ORDER = { { "sell", "Safe to sell to a vendor" }, { "ah", "Better on the Auction House" }, { "use", "Use it or sell it" }, { "unsure", "Not sure: look first" }, { "keep", "Keep" } }
function S.Rows()
  local groups, total, waiting, slots = {}, {}, 0, {}
  for _, e in ipairs(S.Bags()) do
    local v = S.Verdict(e.id, e.link, e.bound)
    if not v then waiting = waiting + 1 else
      groups[v.v] = groups[v.v] or {}
      slots[v.v] = (slots[v.v] or 0) + e.stacks
      local worth = (v.v == "ah" and v.ah or v.vendor or 0) * e.n
      total[v.v] = (total[v.v] or 0) + worth
      table.insert(groups[v.v], { t = v.name .. (e.n > 1 and ("  x" .. e.n) or ""), i = e.id, q = v.quality, worth = worth, key = "bag" .. e.id .. (e.bound and "b" or ""),
                                  d = (worth > 0 and (v.v == "sell" or v.v == "ah" or v.v == "use") and (Money(worth) .. "  ·  ") or "") .. v.why, page = function() return S.Page(e, v) end })
    end
  end
  local free = NS.Route and NS.Route.FreeSlots and NS.Route.FreeSlots()
  local rows = { { t = "Your bags" .. (free and string.format("  ·  %d slot%s free", free, free == 1 and "" or "s") or ""), tex = I .. "INV_Misc_Bag_08", key = "bags",
                   d = (slots.sell or 0) > 0 and string.format("Selling the safe ones frees %d slot%s for %s.", slots.sell, slots.sell == 1 and "" or "s", Money(total.sell)) or "Nothing that's plainly safe to sell.",
                   page = S.About },
                 { t = "Line on item tooltips", tex = I .. "INV_Misc_Note_01", key = "selltip", still = true, actLabel = S.TipOn() and "On" or "Off", act = function() S.SetTip(not S.TipOn()) end } }
  for _, g in ipairs(ORDER) do
    local l = groups[g[1]]
    if l then
      table.sort(l, function(a, b) if a.worth ~= b.worth then return a.worth > b.worth end return a.t < b.t end)
      rows[#rows + 1] = { h = string.format("%s (%d)", g[2], #l) .. ((g[1] == "sell" or g[1] == "ah") and (total[g[1]] or 0) > 0 and ("  " .. Money(total[g[1]])) or "") }
      for _, r in ipairs(l) do rows[#rows + 1] = r end
    end
  end
  if waiting > 0 then rows[#rows + 1] = { t = string.format("%d still loading", waiting), dim = true, still = true } end
  return rows
end

function S.About()
  return { title = "Can I sell this?", icon = I .. "INV_Misc_Bag_08", rows = {
    { t = "Safe to sell", d = "Vendor trash, gear that's no upgrade for you, and materials nothing of yours uses.", still = true },
    { t = "Better on the Auction House", d = "Worth clearly more there than at a vendor, by the prices last seen there. Scan now and then to keep them fresh.", still = true },
    { t = "Keep", d = "A quest of yours needs it (or will soon), you can learn it, your professions use it, it's an upgrade, or it's a tool.", still = true },
    { t = "Not sure", d = "Nobody has recorded what it's for. Read its tooltip before you part with it.", still = true },
    { t = "It only tells you", d = "Sunstone never sells, moves or throws anything away.", still = true } } }
end

function S:Init()
  Hook()
  if NS.QuestsReady then
    NS.QuestsReady(function() C_Timer.After(15, function() NS.Safe("item quests", S.BuildIndex) end) end)
  else
    C_Timer.After(25, function() NS.Safe("item quests", S.BuildIndex) end)
  end
  for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "SKILL_LINES_CHANGED" }) do
    NS.On(ev, function() S.Forget() end)
  end
  NS.On("BAG_UPDATE_DELAYED", function()
    if NS.Window and NS.Window.tab == "gold" and NS.cdb.goldMode == "bags" and NS.Window.DataChanged then NS.Window.DataChanged() end
  end)
end
