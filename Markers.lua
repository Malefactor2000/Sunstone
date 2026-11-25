-- Sunstone: map markers delivered by the desktop helper (through Inbox.lua) and shown as stars
-- on the world map and minimap until you clear them. Markers belong to the character they
-- were made for; the inbox names that character.

local _, NS = ...
local M = NS.Module("Markers")
NS.Markers = M

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" -- yellow star
local worldPins, miniPins = {}, {}

local function List() return NS.cdb.markers end

local function NewPin(size)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(size, size)
  local t = f:CreateTexture(nil, "OVERLAY")
  t:SetAllPoints()
  t:SetTexture(ICON)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self)
    local mk = self.marker
    if not mk then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Sunstone #" .. (mk.n or "?") .. ": " .. (mk.title or "Marker"), 0.77, 0.62, 0.45)
    if mk.note then GameTooltip:AddLine(mk.note, 0.86, 0.85, 0.81, true) end
    GameTooltip:AddLine(string.format("%.1f, %.1f", (mk.x or 0) * 100, (mk.y or 0) * 100), 0.6, 0.6, 0.6)
    GameTooltip:AddLine("/sun go " .. (mk.n or "?") .. " for the arrow · /sun clear " .. (mk.n or "?") .. " to remove", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

function M.Redraw()
  local pins = NS.Pins()
  if not pins then return end
  pins:RemoveAllWorldMapIcons(M)
  pins:RemoveAllMinimapIcons(M)
  for i, mk in ipairs(List()) do
    mk.n = i
    if mk.mapID and mk.x and mk.y then
      worldPins[i] = worldPins[i] or NewPin(16)
      worldPins[i].marker = mk
      pins:AddWorldMapIconMap(M, worldPins[i], mk.mapID, mk.x, mk.y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
      miniPins[i] = miniPins[i] or NewPin(12)
      miniPins[i].marker = mk
      pins:AddMinimapIconMap(M, miniPins[i], mk.mapID, mk.x, mk.y, true, true)
    end
  end
end

local function ValidCoord(v) return type(v) == "number" and v >= 0 and v <= 1 end

-- Apply a new inbox once per character (the inbox file stays the same across later reloads).
function M.ApplyInbox()
  local inbox = SunstoneInbox
  if type(inbox) ~= "table" or type(inbox.id) ~= "number" or inbox.id == 0 then return end
  local me = NS.CharKey()

  -- Talent plans are stored for the character they name, whoever is logged in.
  local plans = type(inbox.plans) == "table" and inbox.plans or { inbox.plan }
  for _, plan in ipairs(plans) do
    if type(plan) == "table" and type(plan.char) == "string" and type(plan.id) == "number"
        and plan.id ~= (NS.db.planIds[plan.char] or 0) then
      NS.db.planIds[plan.char] = plan.id
      if plan.reset then
        NS.db.planOverrides[plan.char] = nil
        if plan.char == me then
          if NS.cdb.talents.goal == "custom" then NS.cdb.talents.goal = nil end
          NS.Print("back to the built-in talent plan.")
        end
      elseif type(plan.steps) == "table" and type(plan.class) == "string" then
        local steps = {}
        for lvl, s in pairs(plan.steps) do
          if type(lvl) == "number" and lvl >= 10 and lvl <= 60 and type(s) == "table" and type(s[1]) == "string" and type(s[2]) == "number" then
            steps[lvl] = { NS.Clean(s[1], 40), s[2], s[3] and NS.Clean(s[3], 160) or nil }
          end
        end
        NS.db.planOverrides[plan.char] = { class = NS.Clean(plan.class, 12), name = NS.Clean(plan.name or "Plan from the helper", 80), steps = steps }
        if plan.char == me then
          NS.cdb.talents.goal = "custom" -- a plan made for this character: use it (the goal bar's Custom button)
          NS.Print("new talent plan from the helper: " .. NS.Clean(plan.name or "?", 80) .. "  (/sun talents)")
        end
      end
    end
  end

  -- Markers and messages: this character's delivery only.
  local d = type(inbox.deliveries) == "table" and inbox.deliveries[me]
  if not d and inbox.markers and (not inbox.char or inbox.char == me) then d = inbox end -- 1.0 format
  if type(d) ~= "table" or type(d.id) ~= "number" or d.id == NS.cdb.lastInboxId then return end
  NS.cdb.lastInboxId = d.id
  NS.db.inboxSeen[me] = d.id
  inbox = d
  local list = List()
  if inbox.clear then wipe(list) end
  local added = 0
  local function Exists(mk)
    for _, o in ipairs(list) do
      if o.mapID == mk.mapID and math.abs(o.x - mk.x) < 0.002 and math.abs(o.y - mk.y) < 0.002 then return true end
    end
  end
  for _, mk in ipairs(type(inbox.markers) == "table" and inbox.markers or {}) do
    if added >= 25 then break end
    if type(mk) == "table" and type(mk.mapID) == "number" and ValidCoord(mk.x) and ValidCoord(mk.y) and not Exists(mk) then
      list[#list + 1] = { title = NS.Clean(mk.title or "Marker", 60), note = mk.note and NS.Clean(mk.note, 160) or nil,
                          mapID = mk.mapID, x = mk.x, y = mk.y, from = "helper" }
      added = added + 1
    end
  end
  -- A goal plan (XP / gold): quests to pick up, added to the route, plus a few lines to read with /sun goal.
  local g = inbox.goal
  if type(g) == "table" then
    if g.clear then
      NS.cdb.goal = nil
      NS.Print("goal plan cleared.")
    else
      local quests, lines = {}, {}
      for _, q in ipairs(type(g.quests) == "table" and g.quests or {}) do
        if type(q) == "number" and q > 0 and q < 10000000 and #quests < 20 then quests[#quests + 1] = q end
      end
      for _, l in ipairs(type(g.lines) == "table" and g.lines or {}) do
        if type(l) == "string" and #lines < 15 then lines[#lines + 1] = NS.Clean(l, 200) end
      end
      NS.cdb.goal = { name = NS.Clean(g.name or "Goal plan", 80), quests = quests, lines = lines }
      NS.Print("new goal plan from the helper: " .. NS.cdb.goal.name .. " (" .. #quests .. " quests to pick up). /sun goal shows it"
        .. (NS.cdb.route.enabled and "; they're in your route now." or "; /sun route on adds them to your route."))
    end
    if NS.Route and NS.Route.Compute then NS.Route.sig = nil; NS.Safe("route", NS.Route.Compute, true) end
  end
  if type(inbox.message) == "string" and inbox.message ~= "" then NS.Print("|cffccb894" .. NS.Clean(inbox.message, 200) .. "|r") end
  if added > 0 then NS.Print(added .. " marker" .. (added == 1 and "" or "s") .. " added (stars on your map). /sun markers lists them.") end
  if inbox.clear and added == 0 then NS.Print("markers cleared.") end
end

function M.Add(mk)
  local list = List()
  list[#list + 1] = mk
  M.Redraw()
end

function M:Init()
  M.ApplyInbox()
  M.Redraw()
end

NS.Command("markers", "- list map markers", function()
  local list = List()
  if #list == 0 then NS.Print("no markers.") return end
  local hbd = NS.HBD()
  for i, mk in ipairs(list) do
    local zone = hbd and hbd:GetLocalizedMap(mk.mapID) or tostring(mk.mapID)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffc99734#%d|r %s - %s %.1f, %.1f%s", i, mk.title or "Marker", zone or "?",
      mk.x * 100, mk.y * 100, mk.note and ("  |cff8f7d68" .. mk.note .. "|r") or ""))
  end
end)

NS.Command("clear", "[n] - remove marker n, or all markers", function(rest)
  local list = List()
  local n = tonumber(rest)
  if n then
    if not list[n] then NS.Print("no marker #" .. n) return end
    table.remove(list, n)
    NS.Print("marker #" .. n .. " removed.")
  else
    wipe(list)
    NS.Print("all markers removed.")
  end
  M.Redraw()
end)

NS.Command("go", "n - point the arrow at marker n (right-click the arrow to go back to the route)", function(rest)
  local mk = List()[tonumber(rest) or 0]
  if not mk then NS.Print("usage: /sun go <marker number>  (see /sun markers)") return end
  NS.Arrow.Go(mk.mapID, mk.x, mk.y, mk.title or "Sunstone marker")
  NS.Print("arrow set to marker #" .. rest .. ". Right-click the arrow (or /sun way clear) to go back to the quest route.")
end)
