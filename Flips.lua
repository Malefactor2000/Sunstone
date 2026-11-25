-- Sunstone: the vendor-flip panel beside the auction house.
-- It lists everything seen listed for less than a vendor pays, that the money in your bags
-- can buy, best profit first, with a plan for your gold. Scan reads the whole auction house (Scan.lua);
-- a click on a row searches for it (in Auctionator's Shopping tab when that's loaded, else in the game's own search box). Buying, and selling to the vendor, are always your own clicks: nothing here buys or sells.

local _, NS = ...
local F = NS.Module("Flips")
NS.Flips = F
local A = NS.Auction
local C = NS.C

local ROWS, ROW_H, WIDTH, HEIGHT, ICON = 10, 36, 330, 560, 24
local SEARCH_MAX = 20     -- names handed to Auctionator's search at once
local MAX_PASSES = 60     -- background vendor-price look-up passes per visit
local OLD = 30 * 60       -- seconds: prices older than this get a "scan again" nudge

local frame, reopen, rows = nil, nil, {}
local page, passes = 1, 0

function F.AtAuctionHouse()
  local ah = AuctionHouseFrame or AuctionFrame
  return ah ~= nil and ah.IsShown ~= nil and ah:IsShown() and true or false
end

local function Ago(t)
  local s = time() - t
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60 + 0.5) .. " min ago" end
  if s < 86400 then return math.floor(s / 3600 + 0.5) .. " h ago" end
  return math.floor(s / 86400 + 0.5) .. " days ago"
end

local function Name(id)
  local name = NS.GetItemInfo(id)
  return type(name) == "string" and name ~= "" and name or nil
end

---------------------------------------------------------------------------
-- Actions (each one runs from your click)
---------------------------------------------------------------------------
-- Our own scan; on a client where that can't work, Auctionator's, exactly as its Full Scan button starts it.
function F.Scan()
  if not F.AtAuctionHouse() then NS.Print("open the auction house first.") return end
  if NS.Scan and NS.Scan.Can() then
    if NS.Scan.Running() then NS.Scan.Stop("you stopped it") else NS.Scan.Start() end
    F.Render()
    return
  end
  local mixin = AuctionatorScanButtonMixin
  local ok, err = false, "Auctionator's scan wasn't found"
  if A.Api() and mixin and mixin.OnClick then ok, err = pcall(mixin.OnClick, mixin) end
  if ok then
    F.scanning = GetTime()
    C_Timer.After(90, function() F.scanning = nil; NS.Safe("flips", F.Render) end)
  else
    NS.Error("flips scan", err)
    NS.Print("couldn't start Auctionator's scan: use its Full Scan button on the Auctionator tab instead.")
  end
  F.Render()
end

-- Every listing of these items, in Auctionator's Shopping tab, searched by their plain names. (Auctionator's "exact"
-- search wraps the name in quotes - "Merch Sword" - and Forever's auction house finds nothing for that.)
function F.Search(list)
  local api = A.Api()
  if not (api and api.MultiSearch) then
    -- without Auctionator: the name goes into the game's own search box; pressing Search is yours
    local name = list and list[1] and Name(list[1].id)
    local ah = AuctionHouseFrame
    if name and F.AtAuctionHouse() and ah and ah.SearchBar and ah.SearchBar.SetSearchText then
      local ok = pcall(ah.SearchBar.SetSearchText, ah.SearchBar, name)
      NS.Print(ok and ("\"" .. name .. "\" is in the search box: press Search.") or ("search for \"" .. name .. "\"."))
    else
      NS.Print(name and ("search for \"" .. name .. "\".") or "the item's name hasn't loaded yet: try again in a second.")
    end
    return
  end
  if not F.AtAuctionHouse() then NS.Print("open the auction house first.") return end
  local names, seen = {}, {}
  for _, f in ipairs(list or {}) do
    local name = Name(f.id)
    if name and not seen[name] and not name:find('[;%^"]') then
      seen[name] = true
      names[#names + 1] = name
      if #names >= SEARCH_MAX then break end
    end
  end
  if #names == 0 then NS.Print("the item names haven't loaded yet: try again in a second.") return end
  local ok, err = pcall(api.MultiSearch, A.CALLER, names)
  if not ok then NS.Print("Auctionator couldn't run the search: " .. NS.Clean(tostring(err), 120)) end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Row(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, frame)
  r:SetSize(WIDTH - 24, ROW_H - 4)
  r:SetPoint("TOPLEFT", 12, -104 - (i - 1) * ROW_H)
  r.bg = NS.Rounded(r, C.surface, "round.png", 8)
  r.well = CreateFrame("Frame", nil, r)
  r.well:SetSize(ICON + 4, ICON + 4)
  r.well:SetPoint("LEFT", 4, 0)
  NS.Rounded(r.well, C.bg, "round.png", 6)
  r.icon = r.well:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ICON, ICON)
  r.icon:SetPoint("CENTER")
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", ICON + 14, -4)
  r.name:SetPoint("RIGHT", -80, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.gain = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.gain:SetPoint("TOPRIGHT", -8, -4)
  r.gain:SetJustifyH("RIGHT")
  r.gain:SetTextColor(unpack(C.good))
  r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.detail:SetPoint("BOTTOMLEFT", ICON + 14, 4)
  r.detail:SetPoint("RIGHT", -8, 0)
  r.detail:SetJustifyH("LEFT")
  r.detail:SetWordWrap(false)
  r.detail:SetTextColor(unpack(C.dim))
  -- click: every listing of this item in Auctionator; hover: the game's own tooltip (with Auctionator's prices)
  r:SetScript("OnClick", function(self) if self.flip then F.Search({ self.flip }) end end)
  r:SetScript("OnEnter", function(self)
    self.bg:SetColor(C.hover)
    if self.flip and NS.Window and NS.Window.ShowItemTip then NS.Window.ShowItemTip(self, self.flip.id) end
  end)
  r:SetScript("OnLeave", function(self)
    self.bg:SetColor(C.surface)
    if self.tip then self.tip = nil; GameTooltip:Hide() end
  end)
  rows[i] = r
  return r
end

function F.Render()
  if not frame or not frame:IsShown() then return end
  local money = GetMoney() or 0
  local fits, over, plan = A.Plan(A.flips or {}, money)
  F.fits = fits

  -- what we know and how fresh it is
  local status
  local seen = A.seen or 0
  local scan = NS.Scan
  if not A.Any() then
    status = "This client's auction house can't be read, and Auctionator isn't loaded."
  elseif scan and scan.Running() then
    status = string.format("Reading the auction house: %d listings so far. Leave it open; searching for something stops it.", scan.Progress())
  elseif F.scanning then
    status = "Auctionator is scanning the auction house... the list fills in when it's done."
  elseif seen == 0 then
    status = "No prices for this realm yet. Click |cffc99734Scan|r: it reads the whole auction house (a minute or two), then this list fills in."
  else
    local scanned = A.Scanned()
    local fresh = scanned and ("prices from " .. Ago(scanned)) or "prices from an earlier visit"
    status = string.format("You carry %s. %d priced items checked, %s.", NS.Money(money), seen, fresh)
    if not scanned or time() - scanned > OLD then status = status .. " |cffc46148Scan for fresh prices.|r" end
    if (A.waiting or 0) > 0 and (A.asking or 0) > 0 and passes < MAX_PASSES then
      status = status .. string.format("\n|cff8f7d68Looking up vendor prices for %d more items...|r", A.waiting)
    end
  end
  frame.text:SetText(status)
  frame.scan:SetText(scan and scan.Running() and "Stop" or "Scan")

  -- the list: what your money covers, best profit first
  local pages = math.max(1, math.ceil(#fits / ROWS))
  if page > pages then page = pages end
  for i = 1, ROWS do
    local r = Row(i)
    local f = fits[(page - 1) * ROWS + i]
    r.flip = f
    if f then
      r.icon:SetTexture(NS.ItemIcon(f.id) or NS.QUESTION_ICON)
      r.name:SetText(Name(f.id) or ("item " .. f.id .. " (loading)"))
      r.name:SetTextColor(unpack(f.planned and C.text or C.dim))
      r.gain:SetText("+" .. NS.Money(f.gain) .. " each")
      local bits = { "buy under " .. NS.Money(f.sell), "cheapest " .. NS.Money(f.buy) }
      if f.avail then bits[#bits + 1] = f.avail .. " listed" end
      if (f.age or 0) > 0 then bits[#bits + 1] = "seen yesterday" end
      r.detail:SetText(table.concat(bits, "  ·  "))
      r:Show()
    else
      r:Hide()
    end
  end
  frame.prev:SetShown(pages > 1)
  frame.next:SetShown(pages > 1)
  frame.pageText:SetText(pages > 1 and (page .. " / " .. pages) or "")

  -- the plan for your gold
  local foot = {}
  if seen > 0 and A.Any() then
    if #fits == 0 and #over == 0 then
      foot[1] = "Nothing is listed below its vendor price right now. Cheap listings come and go: scan again later."
    elseif #fits == 0 then
      foot[1] = string.format("%d flips found, but each costs more than the %s you carry.", #over, NS.Money(money))
    else
      foot[1] = string.format("|cffccb894One of each of the top %d: costs %s, a vendor pays %s|r |cff8aa666(+%s)|r",
        plan.count, NS.Money(plan.spend), NS.Money(plan.back), NS.Money(plan.gain))
      foot[2] = "Buy every listing under its \"buy under\" price, then sell at any vendor."
      if #over > 0 then foot[#foot + 1] = string.format("%d more cost more than you carry.", #over) end
    end
  end
  local api = A.Api()
  foot[#foot + 1] = (api and "Click a row for its listings in Auctionator." or "Click a row to put its name in the search box.") .. " Prices move fast."
  frame.foot:SetText(table.concat(foot, "\n"))
  frame.searchAll:SetShown(#fits > 0 and api ~= nil and api.MultiSearch ~= nil)
end

local function Build()
  frame = NS.Panel("Flips", WIDTH, HEIGHT, "Vendor flips")
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  frame.close:SetScript("OnClick", function()
    frame:Hide()
    NS.db.flipsOff = true -- stays closed at the auction house until "/sun flips" or the Flips button
    if reopen and F.AtAuctionHouse() then reopen:Show() end
  end)

  frame.scan = NS.Button(frame, "Scan", 70, function() F.Scan() end)
  frame.scan:SetPoint("TOPLEFT", 12, -76)
  frame.searchAll = NS.Button(frame, "Search all", 84, function() F.Search(F.fits) end)
  frame.searchAll:SetPoint("LEFT", frame.scan, "RIGHT", 6, 0)
  frame.refresh = NS.Button(frame, "Refresh", 70, function() passes = 0; A.Update() end)
  frame.refresh:SetPoint("LEFT", frame.searchAll, "RIGHT", 6, 0)

  frame.prev = NS.Button(frame, "<", 24, function() page = math.max(1, page - 1); F.Render() end)
  frame.next = NS.Button(frame, ">", 24, function() page = page + 1; F.Render() end)
  frame.next:SetPoint("TOPRIGHT", -12, -76)
  frame.prev:SetPoint("RIGHT", frame.next, "LEFT", -34, 0)
  frame.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
  frame.pageText:SetTextColor(unpack(C.dim))

  frame.foot = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.foot:SetPoint("TOPLEFT", 12, -104 - ROWS * ROW_H - 4)
  frame.foot:SetPoint("RIGHT", -12, 0)
  frame.foot:SetJustifyH("LEFT")
  frame.foot:SetJustifyV("TOP")
  frame.foot:SetSpacing(2)
  frame.foot:SetTextColor(unpack(C.dim))

  frame:SetScript("OnShow", function() if reopen then reopen:Hide() end end)
end

-- Beside the auction house, unless you've dragged it somewhere else.
local function Dock()
  local ah = AuctionHouseFrame or AuctionFrame
  if ah and not (NS.db.frames and NS.db.frames.Flips) then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
  end
end

-- A small button on the auction house to bring the panel back after closing it.
local function Reopen()
  if reopen then return reopen end
  local ah = AuctionHouseFrame or AuctionFrame
  if not ah then return nil end
  reopen = NS.Button(UIParent, "Flips", 52, function() F.Show(true) end)
  reopen:SetFrameStrata("HIGH")
  reopen:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
  reopen:Hide()
  return reopen
end

function F.Show(force)
  if not frame then Build() end
  if force then NS.db.flipsOff = nil end
  if NS.db.flipsOff then
    local b = Reopen()
    if b then b:Show() end
    return
  end
  Dock()
  frame:Show()
  passes = 0
  A.Update() -- draws the panel
end

function F.Hide()
  if frame then frame:Hide() end
  if reopen then reopen:Hide() end
end

function F:Init()
  -- the auction house opening and closing: the old events, and the newer "interaction" ones Auctionator uses
  local function Opened() NS.Debounce("flips-open", 0.2, F.Show) end
  local function Auctioneer(kind)
    local t = Enum and Enum.PlayerInteractionType
    return t ~= nil and t.Auctioneer ~= nil and kind == t.Auctioneer
  end
  NS.On("AUCTION_HOUSE_SHOW", Opened)
  NS.On("AUCTION_HOUSE_CLOSED", F.Hide)
  NS.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) if Auctioneer(kind) then Opened() end end)
  NS.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) if Auctioneer(kind) then F.Hide() end end)
  NS.On("PLAYER_MONEY", function()
    if frame and frame:IsShown() then NS.Debounce("flips-money", 0.3, F.Render) end
  end)
  -- vendor prices arrive a few hundred at a time: redo the list as they land, while the panel is open
  NS.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
    if ok == false and type(id) == "number" then A.noInfo[id] = true end
    if frame and frame:IsShown() and (A.waiting or 0) > 0 and passes < MAX_PASSES then
      NS.Debounce("flips-items", 2, function() passes = passes + 1; A.Update() end)
    end
  end)
  -- Auctionator tells add-ons when it has taken in new prices (a scan, or browsing the auction house)
  local api = A.Api()
  if api and api.RegisterForDBUpdate then
    pcall(api.RegisterForDBUpdate, A.CALLER, function()
      A.MarkScanned()
      F.scanning = nil
      NS.Debounce("flips-db", 1, function() passes = 0; A.Update() end)
    end)
  end
end
