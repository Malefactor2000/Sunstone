-- Sunstone: what a vendor pays for what you craft, in Auctionator's crafting box.
-- Auctionator's "Profit" line only counts the auction price of the result; with no auction price it counts
-- zero, so every recipe looks like a loss. This adds one line under it in the profession window:
--   Vendor pays: <vendor price x how many one craft makes> (+/- against Auctionator's "To Craft" cost)
-- It reads prices only (the profession window and Auctionator stay as they are; crafting is your click).

local _, NS = ...
local K = NS.Module("Crafting")
NS.Crafting = K
local A = NS.Auction

local function Hex(c) return string.format("|cff%s", c) end

-- The item a recipe makes and how many one craft makes, from the modern profession window.
local function Output(form)
  local info = form:GetRecipeInfo()
  if type(info) ~= "table" or info.isEnchantingRecipe or not info.recipeID then return nil end
  local tx = form.GetTransaction and form:GetTransaction()
  local data
  if tx then
    data = C_TradeSkillUI.GetRecipeOutputItemData(info.recipeID, tx:CreateCraftingReagentInfoTbl(), tx:GetAllocationItemGUID())
  else
    data = C_TradeSkillUI.GetRecipeOutputItemData(info.recipeID)
  end
  local id = type(data) == "table" and (data.itemID or (type(data.hyperlink) == "string"
    and tonumber(data.hyperlink:match("item:(%d+)"))))
  local schem = form.recipeSchematic
  local count = type(schem) == "table" and tonumber(schem.quantityMin) or 1
  return id, math.max(count or 1, 1), info
end

-- What one craft costs, exactly as Auctionator's "To Craft" line counts it, and how many required
-- reagents have no price at all (Auctionator counts those as free).
local function Cost(form, info)
  local CI = Auctionator and Auctionator.CraftingInfo
  if not (CI and CI.CalculateCraftCost and form.GetTransaction) then return nil, 0 end
  local level = form.GetCurrentRecipeLevel and form:GetCurrentRecipeLevel() or nil
  local schem = C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false, level)
  if type(schem) ~= "table" then return nil, 0 end
  local cost = CI.CalculateCraftCost(schem, form:GetTransaction())
  local api, unpriced = A.Api(), 0
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
    local required = (basic == nil and (slot.quantityRequired or 0) > 0) or (basic ~= nil and slot.reagentType == basic)
    if required and #(slot.reagents or {}) > 0 then
      local priced = false
      for _, r in ipairs(slot.reagents) do
        if r.itemID then
          local ok, merchant = false, nil -- what a merchant charges for it
          if api and api.GetVendorPriceByItemID then ok, merchant = pcall(api.GetVendorPriceByItemID, A.CALLER, r.itemID) end
          if (ok and type(merchant) == "number") or A.Price(r.itemID) then priced = true break end
        end
      end
      if not priced then unpriced = unpriced + 1 end
    end
  end
  return type(cost) == "number" and cost or nil, unpriced
end

-- The line itself, or nil when it doesn't apply (enchants, nothing selected, an older Auctionator).
function K.Line(form)
  if type(form) ~= "table" or type(form.GetRecipeInfo) ~= "function" or not C_TradeSkillUI then return nil end
  local id, count, info = Output(form)
  if not id then return nil end
  local each = A.Vendor(id, false)
  if each == nil then
    K.waiting = id
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return Hex(NS.HEX.dim) .. "Vendor pays: looking it up...|r"
  end
  if each == 0 then return Hex(NS.HEX.dim) .. "Vendors won't buy this.|r" end
  local back = each * count
  local text = "Vendor pays: " .. NS.Money(back) .. (count > 1 and (" for " .. count) or "")
  local cost, unpriced = Cost(form, info)
  if cost then
    local gain = back - cost
    text = text .. "  " .. (gain >= 0 and (Hex(NS.HEX.good) .. "(+" .. NS.Money(gain) .. ")|r")
                                    or (Hex(NS.HEX.warn) .. "(-" .. NS.Money(-gain) .. ")|r"))
    local ah = A.Price(id)
    if ah and back >= math.floor(ah * count * 0.95) then text = text .. Hex(NS.HEX.dim) .. " · beats the auction house|r" end
    if unpriced > 0 then
      text = text .. Hex(NS.HEX.dim) .. string.format(" · %d reagent%s unpriced", unpriced, unpriced == 1 and "" or "s") .. "|r"
    end
  end
  return text
end

-- Add the line to Auctionator's own crafting text (its box grows by one line).
function K.Wrap()
  local CI = Auctionator and Auctionator.CraftingInfo
  if K.wrapped or not CI or type(CI.GetInfoText) ~= "function" then return end
  local original = CI.GetInfoText
  CI.GetInfoText = function(form, showProfit, ...)
    local text, lines = original(form, showProfit, ...)
    if showProfit ~= false and type(text) == "string" and type(lines) == "number" then
      local ok, line = pcall(K.Line, form)
      if ok and line then
        text = (lines > 0 and (text .. "\n") or "") .. line
        lines = lines + 1
      elseif not ok then
        NS.Error("crafting", line)
      end
    end
    return text, lines
  end
  K.wrapped = true
end

function K:Init()
  K.Wrap()
  -- the result's details arrived: redraw Auctionator's box so "looking it up" becomes a price
  NS.On("GET_ITEM_INFO_RECEIVED", function(id)
    if K.waiting and id == K.waiting then
      K.waiting = nil
      local box = AuctionatorCraftingInfoProfessionsFrame
      if box and box.IsVisible and box:IsVisible() and box.UpdateTotal then pcall(box.UpdateTotal, box) end
    end
  end)
end
