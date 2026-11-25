-- Sunstone: "you just sold that". At a vendor it watches the list of what can be bought back. When something you need lands there (a quest wants it, your
-- profession uses it, it's an upgrade, a rare find, worth far more at the Auction House, or you marked it Keep), it says so at once, while it can
-- still be bought back. It only looks and tells: it never sells, buys back, moves or clicks anything.

local _, NS = ...
local So = NS.Module("SoldWatch")
NS.SoldWatch = So
local E = NS.Engine

local RARE = 0.07     -- a drop in at most this share of your own corpses is a rare find
local FARMED = 20     -- ... once you've looted this many of them
local LOSS = 500      -- copper: that much less than the Auction House is worth a word
local function List(t) return type(t) == "table" and t or {} end
local function Set() NS.cdb.keep = type(NS.cdb.keep) == "table" and NS.cdb.keep or {} return NS.cdb.keep end

function So.On() return not (NS.db and NS.db.soldWatch == false) end
function So.Kept(id) return Set()[id] == true end
function So.Keep(id, on)
  Set()[id] = on and true or nil
  if NS.Sell then NS.Sell.Forget() end
  if NS.Window then NS.Window.Refresh() end
end

-- what can be bought back: { [item] = how many }, and each one's link
function So.Buyback()
  local out, links = {}, {}
  local n = GetNumBuybackItems and tonumber(GetNumBuybackItems()) or 0
  for i = 1, n do
    local id, link, qty
    if GetBuybackItemLink then
      local ok, l = pcall(GetBuybackItemLink, i)
      if ok and type(l) == "string" then link, id = l, tonumber(l:match("item:(%d+)")) end
    end
    if not id and C_MerchantFrame and C_MerchantFrame.GetBuybackItemID then
      local ok, v = pcall(C_MerchantFrame.GetBuybackItemID, i)
      if ok and type(v) == "number" then id = v end
    end
    if id then
      if GetBuybackItemInfo then
        local ok, _, _, _, q = pcall(GetBuybackItemInfo, i)
        if ok and type(q) == "number" then qty = q end
      end
      out[id] = (out[id] or 0) + (qty or 1)
      links[id] = link or links[id]
    end
  end
  return out, links
end

-- how often your own corpses had it: found, looted
function So.Found(id)
  local got, of = 0, 0
  for _, m in pairs(List(NS.db.rec and NS.db.rec.mobs)) do
    if type(m) == "table" then
      local n = List(m.i)[id] or List(m.r)[id]
      if type(n) == "number" then got, of = got + n, of + (tonumber(m.l) or 0) end
    end
  end
  return got, of
end

-- why you'd want it back; nil: nothing wrong with selling it
function So.Why(id, link)
  local _, _, quality, _, _, _, _, _, _, _, vendor = NS.GetItemInfo(link or id)
  if So.Kept(id) then return "You marked it to keep." end
  if quality == 0 then return nil end
  local v = NS.Sell and NS.Sell.Verdict(id, link)
  if v and v.v == "keep" then return v.why end
  if NS.Finds and NS.Finds.Special and NS.Finds.Special(id) then return "A companion pet or a mount." end
  local _, _, _, _, _, class = NS.GetItemInfoInstant(id)
  if class == 12 then return "A quest item." end
  if type(quality) == "number" and quality >= 3 then return "A rare item." end
  if v and v.v == "ah" and v.ah and v.ah - (v.vendor or 0) >= LOSS then return v.why end
  if class == 7 or class == 5 or class == 9 then
    local got, of = So.Found(id)
    if got > 0 and of >= FARMED and got / of <= RARE then return string.format("A rare find: %d in %d of your corpses.", got, of) end
  end
  return nil
end

---------------------------------------------------------------------------
-- Saying it: bright blue across the top of the screen for a few seconds (nothing to click, nothing in the way), and red in chat
---------------------------------------------------------------------------
local RED = "ff4a3d"
local HOLD, FADE = 5, 1.5
local flash
local showing = {} -- { { id, n, why, link } }: what's on the screen right now
local function Draw()
  if #showing == 0 then if flash then flash:Hide() end return end
  if not flash then
    flash = CreateFrame("Frame", "SunstoneSoldFrame", UIParent)
    flash:SetSize(900, 60)
    flash:SetPoint("TOP", UIParent, "TOP", 0, -150)
    flash:SetFrameStrata("FULLSCREEN_DIALOG")
    flash:EnableMouse(false)
    flash.big = flash:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    flash.big:SetPoint("TOP", 0, 0)
    flash.big:SetTextColor(0.25, 0.80, 1)
    flash.big:SetShadowOffset(2, -2)
    flash.small = flash:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    flash.small:SetPoint("TOP", flash.big, "BOTTOM", 0, -6)
    flash.small:SetTextColor(0.72, 0.93, 1)
    flash.small:SetShadowOffset(1, -1)
    for _, f in ipairs({ { flash.big, 26 }, { flash.small, 17 } }) do -- (a thick black outline: readable over grass, snow or sky)
      local file = f[1].GetFont and f[1]:GetFont()
      if type(file) == "string" and f[1].SetFont then pcall(f[1].SetFont, f[1], file, f[2], "THICKOUTLINE") end
    end
    flash:SetScript("OnUpdate", function(self, dt)
      self.left = (self.left or 0) - (dt or 0)
      if self.left <= 0 then showing = {} self:Hide()
      elseif self.left < FADE then self:SetAlpha(self.left / FADE) end
    end)
  end
  local e = showing[#showing]
  local names = {}
  for k = #showing, math.max(1, #showing - 2), -1 do names[#names + 1] = (showing[k].n > 1 and (showing[k].n .. " ") or "") .. E.ItemName(showing[k].id) end
  flash.big:SetText("You just sold " .. table.concat(names, ", ") .. "!")
  flash.small:SetText((#showing == 1 and (e.why .. "  ") or "") .. "Buyback tab, now")
  flash.left = HOLD + FADE
  flash:SetAlpha(1)
  flash:Show()
end
function So.Showing() return showing end

function So.Fine(id)
  NS.cdb.soldFine = type(NS.cdb.soldFine) == "table" and NS.cdb.soldFine or {}
  NS.cdb.soldFine[id] = true
  NS.Print("all right, no more warnings about " .. E.ItemName(id) .. ".")
end
local function Tell(id, n, link)
  if NS.cdb.soldFine and NS.cdb.soldFine[id] then return end
  local why = So.Why(id, link)
  if not why then return end
  for k, e in ipairs(showing) do if e.id == id then n = n + e.n table.remove(showing, k) break end end
  showing[#showing + 1] = { id = id, n = n, why = why, link = link }
  NS.Print("|cff" .. RED .. "you just sold " .. (n > 1 and (n .. " ") or "") .. "|r" .. (link or E.ItemName(id)) .. "|cff" .. RED .. ". " .. why .. " It's under the vendor's Buyback tab for now.|r |Haddon:Sunstone:soldfine:"
    .. id .. "|h|cff" .. NS.HEX.dim .. "[Don't warn about this]|r|h")
  Draw()
end

local open, base = false, {}
function So.Look()
  if not open then return end
  local now, links = So.Buyback()
  local was = base
  base = now
  if not So.On() then return end
  for id, n in pairs(now) do
    local more = n - (was[id] or 0)
    if more > 0 then Tell(id, more, links[id]) end
  end
  -- bought back: nothing more to say about it
  local left, changed = {}, false
  for _, e in ipairs(showing) do
    if now[e.id] or not was[e.id] then left[#left + 1] = e else changed = true end
  end
  if changed then showing = left Draw() end
end
function So.Open()
  base = So.Buyback()
  open = true
end
function So.Close() open = false end

function So:Init()
  local clicked = 0
  local function Link(link)
    local id = type(link) == "string" and tonumber(link:match("^addon:Sunstone:soldfine:(%d+)$"))
    if not id or GetTime() - clicked < 0.5 then return end
    clicked = GetTime()
    NS.Safe("sold watch", So.Fine, id)
  end
  if EventRegistry and EventRegistry.RegisterCallback then pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link) Link(link) end, So) end
  if SetItemRef and hooksecurefunc then pcall(hooksecurefunc, "SetItemRef", Link) end
  NS.On("MERCHANT_SHOW", function() NS.Safe("sold watch", So.Open) end)
  NS.On("MERCHANT_CLOSED", function() So.Close() end)
  local function Soon() if open then NS.Debounce("sold watch", 0.25, function() NS.Safe("sold watch", So.Look) end) end end
  NS.On("MERCHANT_UPDATE", Soon)
  NS.On("BAG_UPDATE_DELAYED", Soon)
  NS.Setting("At vendors", "Warn me when I sell something I need", "Quest items, materials you use, upgrades, rare finds, things you marked Keep: said at once, while you can still buy them back.", function() return So.On() end,
    function(v) NS.db.soldWatch = v and true or false end)
end
