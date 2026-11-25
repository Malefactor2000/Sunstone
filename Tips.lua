-- Sunstone: what gear is worth, on the game's own item tooltips (yours, vendors', quest rewards', auctions', links): how it
-- compares with what you wear by the stat weights of your talent goal, and which of your other characters it would help (things
-- that aren't bound only). And a word when an old rank of a spell sits on your bars while you know a better one.
-- Information only: it never moves, equips or replaces anything.

local _, NS = ...
local Ti = NS.Module("Tips")
NS.Tips = Ti
local U = NS.Upgrades
local HEX = NS.HEX

function Ti.On(key) return not (NS.db and type(NS.db.tips) == "table" and NS.db.tips[key] == false) end
function Ti.Set(key, on)
  NS.db.tips = type(NS.db.tips) == "table" and NS.db.tips or {}
  NS.db.tips[key] = on and true or false
end

---------------------------------------------------------------------------
-- Gear
---------------------------------------------------------------------------
local cache, cacheAt = {}, 0

local function Num(v)
  if v >= 100 then return string.format("%d", v + 0.5) end
  return (string.format("%.1f", v):gsub("%.0$", ""))
end

-- -> the lines for an item: { { left, right }, ... }
function Ti.GearLines(link, bound)
  local out = {}
  local c = U.Compare(link)
  if not c then return out end
  if not c.no then
    local bits = {}
    if c.level and c.level > (UnitLevel("player") or 1) then bits[#bits + 1] = "at level " .. c.level end
    if c.train then bits[#bits + 1] = "learn " .. c.train .. " first" end
    local after = #bits > 0 and (" |cff" .. HEX.dim .. "(" .. table.concat(bits, ", ") .. ")|r") or ""
    if c.twoHand then
      out[#out + 1] = "|cff" .. HEX.dim .. "Goes with a one-hander; you're using a two-hander.|r"
    elseif c.worn then
      if c.score > 0.05 then out[#out + 1] = "|cff" .. HEX.dim .. "You're wearing it: worth " .. Num(c.score) .. " for " .. c.spec .. ".|r" end
    elseif c.score > 0.05 or c.old > 0.05 then
      local than = c.oldName or (c.empty and "an empty slot") or "what you wear"
      if c.gain > 0.05 then out[#out + 1] = "|cff" .. HEX.good .. "Upgrade: +" .. Num(c.gain) .. "|r over " .. than .. after
      elseif c.gain < -0.05 then out[#out + 1] = "|cff" .. HEX.dim .. Num(-c.gain) .. " below " .. than .. "|r" .. after
      else out[#out + 1] = "|cff" .. HEX.dim .. "As good as " .. than .. "|r" .. after end
    end
  end
  if not c.no and not c.worn and not c.twoHand and NS.CharSheet then
    local change = NS.CharSheet.ChangeText(link, 4)
    if change then out[#out + 1] = "|cff" .. HEX.dim .. "For you: " .. change .. "|r" end
  end
  if not bound and Ti.On("alts") then
    local best = {}
    local me = NS.CharKey()
    for key, s in pairs(NS.db.snapshots or {}) do
      if key ~= me and type(s) == "table" and s.realm == GetRealmName() and s.faction == UnitFactionGroup("player") then
        local g, at = U.AltGain(s, link)
        if g and g > 0.5 then best[#best + 1] = { s.name, g, at } end
      end
    end
    table.sort(best, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(3, #best) do
      local b = best[i]
      out[#out + 1] = "|cff" .. HEX.accent .. NS.Clean(b[1] or "?", 20) .. ":|r |cff" .. HEX.good .. "+" .. Num(b[2]) .. "|r"
        .. (b[3] and (" |cff" .. HEX.dim .. "(at level " .. b[3] .. ")|r") or "")
    end
  end
  return out
end

local function Bound(data, link)
  local bind = select(14, NS.GetItemInfo(link))
  if bind == 1 or bind == 4 then return true end
  for _, l in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
    local t = type(l) == "table" and l.leftText
    if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and (t == ITEM_SOULBOUND or t == ITEM_BIND_ON_PICKUP or t == ITEM_BIND_QUEST) then return true end
  end
  return false
end

local function Add(tip, link, data)
  if not Ti.On("gear") or type(link) ~= "string" then return end
  local now = GetTime()
  if now - cacheAt > 4 then cache, cacheAt = {}, now end
  local bound = Bound(data, link)
  local key = link .. (bound and "b" or "")
  local lines = cache[key]
  if not lines then
    lines = Ti.GearLines(link, bound)
    cache[key] = lines
  end
  for i, l in ipairs(lines) do
    tip:AddLine((i == 1 and ("|cff" .. HEX.accent .. "Sunstone:|r ") or "") .. l, 0.80, 0.72, 0.58, false)
  end
end
Ti.Add = Add

local function Hook()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
      local link = type(data) == "table" and data.hyperlink
      if not link and tip.GetItem then
        local ok, _, l = pcall(tip.GetItem, tip)
        link = ok and l or nil
      end
      if type(link) == "string" and not (issecretvalue and issecretvalue(link)) then NS.Safe("gear tooltip", Add, tip, link, data) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tip)
      local _, link = tip:GetItem()
      if link then NS.Safe("gear tooltip", Add, tip, link) end
    end)
  end
end

---------------------------------------------------------------------------
-- Old ranks on your bars
---------------------------------------------------------------------------
local function KnowsId(id)
  for _, fn in ipairs({ C_SpellBook and C_SpellBook.IsSpellKnown or false, IsPlayerSpell or false, IsSpellKnown or false }) do
    if fn then
      local ok, v = pcall(fn, id)
      if ok and v == true then return true end
    end
  end
  return false
end

-- { { slot, name, rank, best, id } }: the first slot of each spell whose rank on the bar is below the best you know
function Ti.OldRanks()
  local out = {}
  if not GetActionInfo then return out end
  local _, class = UnitClass("player")
  local byId, ranks = {}, {}
  for _, s in ipairs(NS.Engine.Data().spells[class] or {}) do
    if type(s[4]) == "number" and s[4] > 0 then
      byId[s[2]] = s
      ranks[s[3]] = ranks[s[3]] or {}
      table.insert(ranks[s[3]], s)
    end
  end
  local seen = {}
  for slot = 1, 180 do
    local ok, kind, id = pcall(GetActionInfo, slot)
    local s = ok and kind == "spell" and type(id) == "number" and byId[id]
    if s and not seen[id] then
      seen[id] = true
      local best
      for _, r in ipairs(ranks[s[3]]) do
        if r[4] > s[4] and (not best or r[4] > best[4]) and KnowsId(r[2]) then best = r end
      end
      if best then out[#out + 1] = { slot = slot, name = s[3], rank = s[4], best = best[4], id = best[2], old = id } end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- "Action Bar 2, button 5" for a slot
function Ti.SlotName(slot)
  return "bar " .. math.ceil(slot / 12) .. ", button " .. ((slot - 1) % 12 + 1)
end

-- after training: one line in chat for each spell whose old rank is still on a bar
function Ti.WarnRanks()
  if not Ti.On("ranks") then return end
  NS.cdb.rankTold = type(NS.cdb.rankTold) == "table" and NS.cdb.rankTold or {}
  local told, new = NS.cdb.rankTold, {}
  for _, r in ipairs(Ti.OldRanks()) do
    if told[r.name] ~= r.best then
      told[r.name] = r.best
      new[#new + 1] = string.format("%s: rank %d is on your bar (%s), you know rank %d", r.name, r.rank, Ti.SlotName(r.slot), r.best)
    end
  end
  for i = 1, math.min(5, #new) do NS.Print(new[i] .. (i == #new and ". Drag the new one from your spellbook (or keep the old one to save mana)." or ".")) end
  if #new > 5 then NS.Print((#new - 5) .. " more: see Class, Rotations.") end
end

function Ti:Init()
  Hook()
  local function Later() NS.Debounce("old ranks", 6, Ti.WarnRanks) end
  NS.On("LEARNED_SPELL_IN_SKILL_LINE", Later)
  NS.On("LEARNED_SPELL_IN_TAB", Later)
  NS.On("TRAINER_CLOSED", Later)
  NS.On("PLAYER_ENTERING_WORLD", function() NS.Debounce("old ranks", 20, Ti.WarnRanks) end)
end

NS.Setting("Tooltips", "Gear value on item tooltips", "How an item compares with what you wear, by your talent goal's stat weights.", function() return Ti.On("gear") end, function(v) Ti.Set("gear", v) end)
NS.Setting("Tooltips", "Your other characters too", "Unbound gear: which of your other characters on this realm it would help.", function() return Ti.On("alts") end, function(v) Ti.Set("alts", v) end)
NS.Setting("Tooltips", "Can I sell this?", "Keep, sell or auction, on every item.", function() return NS.Sell.TipOn() end, function(v) NS.Sell.SetTip(v) end)
NS.Setting("Tooltips", "Old spell ranks", "A line in chat when an old rank is still on your bars after training.", function() return Ti.On("ranks") end, function(v) Ti.Set("ranks", v) end)
