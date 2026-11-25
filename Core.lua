-- Sunstone: core (saved data, events, slash commands, small UI helpers).
--
-- Ground rules, kept on purpose (and checked by the offline tests):
--   * Information only: Sunstone never presses keys, moves the character or acts for the player. At a vendor
--     it only reads the prices on show; it never buys, sells or clicks anything there.
--   * Deaf to other players: it registers no chat, whisper, mail, guild or party message events and
--     never reads other players' names or text, so nothing anyone types in game can reach it.
--   * Silent: it sends no chat or addon messages and joins no channels, so other players can't
--     detect it or talk to it.
--   * Everything it receives from the desktop helper (Inbox.lua, GearList.lua) is checked and cleaned
--     before use.

local ADDON, NS = ...
NS.version = "2.5.3"

function NS.CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

-- Plain text only: no UI escape codes (|c colours, |H links, |T textures), no control characters.
function NS.Clean(s, maxLen)
  if type(s) ~= "string" then return "" end
  s = s:gsub("|", "/"):gsub("[%c]", " ")
  if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
  return s
end

local PREFIX = "|cffc99734Sunstone:|r "
function NS.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg)) end

-- Errors are caught and kept so one broken feature never takes the others down.
NS.errors = {}
function NS.Error(where, err)
  local line = tostring(where) .. ": " .. tostring(err)
  NS.errors[#NS.errors + 1] = line
  if #NS.errors > 50 then table.remove(NS.errors, 1) end
  if not NS.quietErrors then
    NS.Print("|cffc46148error in " .. line .. "|r  (/sun errors)")
  end
end
function NS.Safe(where, fn, ...)
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then NS.Error(where, a); return nil end
  return a, b, c, d
end

---------------------------------------------------------------------------
-- Game API under its current names. The Forever client moved several functions into C_ tables
-- (C_Item, C_CVar, C_AddOns...); these use the new name and fall back to the old one.
---------------------------------------------------------------------------
local function Pick(ns, name)
  return function(...)
    local t = _G[ns]
    local fn = (t and t[name]) or _G[name]
    if fn then return fn(...) end
  end
end
NS.GetItemInfo = Pick("C_Item", "GetItemInfo")
NS.GetItemInfoInstant = Pick("C_Item", "GetItemInfoInstant")
NS.GetItemStats = Pick("C_Item", "GetItemStats")
NS.GetCVar = Pick("C_CVar", "GetCVar")
NS.SetCVar = Pick("C_CVar", "SetCVar")
NS.IsAddOnLoaded = Pick("C_AddOns", "IsAddOnLoaded")
function NS.SpellName(id)
  local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
  if not name and GetSpellInfo then name = (GetSpellInfo(id)) end
  return name
end
function NS.Money(copper)
  copper = math.floor(tonumber(copper) or 0)
  local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  if fn then
    local ok, s = pcall(fn, copper)
    if ok and s then return s end
  end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  return (g > 0 and (g .. "g ") or "") .. ((s > 0 or g > 0) and (s .. "s ") or "") .. c .. "c"
end
-- An item's icon by its ID (known even before the item itself has loaded), as OneForAll does it in Forever.
NS.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
function NS.ItemIcon(id)
  if type(id) ~= "number" then return nil end
  for _, fn in ipairs({ C_Item and C_Item.GetItemIconByID or false, GetItemIcon or false }) do
    if fn then
      local ok, icon = pcall(fn, id)
      if ok and icon then return icon end
    end
  end
end
-- A currency (Honor 1792, Rank Points 3468, Merchant's Favor 3402): { quantity, max, week, weekMax, total } as numbers.
function NS.Currency(id)
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if ok and type(info) == "table" and type(info.quantity) == "number" then
      local function n(v) return type(v) == "number" and v or nil end
      return { quantity = info.quantity, max = n(info.maxQuantity), week = n(info.quantityEarnedThisWeek),
               weekMax = n(info.maxWeeklyQuantity), total = n(info.totalEarned) }
    end
  end
  if GetCurrencyInfo then
    local ok, _, amount, _, week, weekMax, max = pcall(GetCurrencyInfo, id)
    if ok and type(amount) == "number" then
      return { quantity = amount, week = tonumber(week), weekMax = tonumber(weekMax), max = tonumber(max) }
    end
  end
end
-- Your standing with a faction: reaction (1 Hated ... 4 Neutral, 5 Friendly ... 8 Exalted), how far into that
-- rank, the rank's size, and the absolute value (both ways the Forever client offers, as OneForAll reads it).
function NS.Standing(fid)
  if type(fid) ~= "number" then return nil end
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, fid)
    if ok and type(d) == "table" and type(d.reaction) == "number" then
      local lo, hi = d.currentReactionThreshold or 0, d.nextReactionThreshold or 0
      local cur = d.currentStanding or 0
      return d.reaction, cur - lo, hi - lo, cur
    end
  end
  if GetFactionInfoByID then
    local ok, name, _, st, bmin, bmax, val = pcall(GetFactionInfoByID, fid)
    if ok and name and type(st) == "number" then
      return st, (val or 0) - (bmin or 0), (bmax or 0) - (bmin or 0), val or 0
    end
  end
end
-- The factions the helper asked about (their reputation vendors sell gear): numbers from GearList.lua only.
function NS.Factions()
  local gl = _G.SunstoneGearList
  local out = {}
  for _, f in ipairs(NS.Engine and NS.Engine.Data().factions or {}) do out[#out + 1] = f.id end
  if #out == 0 and type(gl) == "table" and type(gl.factions) == "table" then
    for _, f in ipairs(gl.factions) do
      if type(f) == "number" and f > 0 and f < 100000 and f == math.floor(f) and #out < 60 then out[#out + 1] = f end
    end
  end
  return out
end
-- GUIDs can be hidden ("secret") from addons in some situations in this client: treat those as unknown.
function NS.GUID(unit)
  local g = UnitGUID(unit)
  if g == nil or (issecretvalue and issecretvalue(g)) then return nil end
  return g
end

-- The map library (libs\HereBeDragons; TomTom's copy if that one is newer).
function NS.HBD() return LibStub and LibStub("HereBeDragons-2.0", true) end
function NS.Pins() return LibStub and LibStub("HereBeDragons-Pins-2.0", true) end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
function NS.On(event, fn)
  if not handlers[event] then
    -- Unknown events raise an error on modern clients; skip them quietly.
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
    handlers[event] = {}
  end
  table.insert(handlers[event], fn)
  return true
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then NS.Error(event, err) end
  end
end)

-- Runs fn after `delay` seconds, collapsing repeated calls with the same key.
local pending = {}
function NS.Debounce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    NS.Safe(key, fn)
  end)
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function InitDB()
  SunstoneDB = SunstoneDB or {}
  local db = SunstoneDB
  db.snapshots = db.snapshots or {}
  db.frames = db.frames or {}
  db.planOverrides = db.planOverrides or {}   -- [Name-Realm] = plan from the helper
  db.planIds = db.planIds or {}
  db.inboxSeen = db.inboxSeen or {}           -- [Name-Realm] = last delivery applied (the helper reads this)
  db.planOverride, db.lastInboxId = nil, nil  -- 1.0 leftovers
  SunstoneCharDB = SunstoneCharDB or {}
  local c = SunstoneCharDB
  c.markers = c.markers or {}
  if type(db.markers) == "table" then         -- 1.0 kept markers account-wide: hand them to this character
    for _, mk in ipairs(db.markers) do c.markers[#c.markers + 1] = mk end
    db.markers = nil
  end
  c.lastInboxId = c.lastInboxId or 0
  c.route = c.route or {}
  if c.route.enabled == nil then c.route.enabled = false end
  c.talents = c.talents or {}
  if c.talents.popup == nil then c.talents.popup = false end
  NS.db, NS.cdb = db, c
end

NS.modules = {}
function NS.Module(name)
  local m = { name = name }
  NS.modules[#NS.modules + 1] = m
  return m
end

NS.On("ADDON_LOADED", function(name)
  if name == ADDON then InitDB() end
end)
NS.On("PLAYER_LOGIN", function()
  if not NS.db then InitDB() end
  for _, m in ipairs(NS.modules) do
    if m.Init then NS.Safe(m.name .. ".Init", m.Init, m) end
  end
end)

---------------------------------------------------------------------------
-- Look: dark mode in warm tones: near-black with oxblood panels, deep reds for what's selected, darker golds for
-- lines and headings, and parchment-toned text (no bright white, nothing that glares late at night).
---------------------------------------------------------------------------
NS.C = {
  bg = { 0.063, 0.047, 0.039, 0.97 },     -- window background (warm near-black)
  band = { 0.043, 0.031, 0.027, 1 },      -- the banner and the tab strip, a shade darker
  panel = { 0.082, 0.059, 0.049, 1 },     -- the details side
  surface = { 0.118, 0.078, 0.063, 1 },   -- rows, buttons (dark oxblood)
  hover = { 0.200, 0.098, 0.078, 1 },     -- hovered / selected (deep red)
  button = { 0.180, 0.118, 0.088, 1 },    -- buttons: a shade above the plates they stand on
  border = { 0.420, 0.302, 0.122, 1 },    -- frame lines (dark bronze-gold)
  text = { 0.800, 0.722, 0.580 },         -- parchment
  dim = { 0.560, 0.490, 0.408 },          -- faded parchment
  accent = { 0.788, 0.592, 0.204 },       -- deep gold
  red = { 0.600, 0.157, 0.133 },          -- deep red
  good = { 0.541, 0.651, 0.400 },         -- muted olive
  warn = { 0.769, 0.380, 0.282 },         -- red clay
}
-- the same colours for text written into chat or panels
NS.HEX = { text = "ccb894", dim = "8f7d68", accent = "c99734", good = "8aa666", warn = "c46148", red = "992822" }
NS.MEDIA = "Interface\\AddOns\\Sunstone\\media\\"

-- A rounded rectangle behind a frame, from one small white texture cut in nine and tinted.
-- Returns a handle with :SetColor(c) / :Show() / :Hide().
function NS.Rounded(frame, color, file, screenCorner, sublevel, inset)
  file = file or "round.png"
  local size = file == "pill.png" and 32 or 64
  local s = (size == 32 and 10 or 16) / size
  local cs, d = screenCorner or 10, inset or 0
  local parts = {}
  local function Part(l, r, t, b)
    local x = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel or 0)
    x:SetTexture(NS.MEDIA .. file)
    x:SetTexCoord(l, r, t, b)
    parts[#parts + 1] = x
    return x
  end
  local tl, tr = Part(0, s, 0, s), Part(1 - s, 1, 0, s)
  local bl, br = Part(0, s, 1 - s, 1), Part(1 - s, 1, 1 - s, 1)
  tl:SetSize(cs, cs); tl:SetPoint("TOPLEFT", d, -d)
  tr:SetSize(cs, cs); tr:SetPoint("TOPRIGHT", -d, -d)
  bl:SetSize(cs, cs); bl:SetPoint("BOTTOMLEFT", d, d)
  br:SetSize(cs, cs); br:SetPoint("BOTTOMRIGHT", -d, d)
  local top = Part(s, 1 - s, 0, s); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bot = Part(s, 1 - s, 1 - s, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local left = Part(0, s, s, 1 - s); left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local right = Part(1 - s, 1, s, 1 - s); right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  local mid = Part(s, 1 - s, s, 1 - s); mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  local h = {}
  function h:SetColor(c) for _, p in ipairs(parts) do p:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end end
  function h:Show() for _, p in ipairs(parts) do p:Show() end end
  function h:Hide() for _, p in ipairs(parts) do p:Hide() end end
  h:SetColor(color)
  return h
end

---------------------------------------------------------------------------
-- UI helpers: a movable dark rounded panel that remembers where it was left
---------------------------------------------------------------------------
function NS.Panel(key, width, height, title)
  local f = CreateFrame("Frame", "Sunstone" .. key .. "Frame", UIParent)
  f:SetSize(width, height)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    NS.db.frames[key] = { p, rp, x, y }
  end)
  local pos = NS.db and NS.db.frames[key]
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end

  f.border = NS.Rounded(f, NS.C.border, "round.png", 12, -2)
  f.back = NS.Rounded(f, NS.C.bg, "round.png", 11, -1, 1)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -9)
  f.title:SetTextColor(unpack(NS.C.accent))
  f.title:SetText(title or "Sunstone")

  local close = CreateFrame("Button", nil, f)
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", -5, -4)
  local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  x:SetPoint("CENTER")
  x:SetText("×")
  x:SetTextColor(unpack(NS.C.dim))
  close:SetScript("OnEnter", function() x:SetTextColor(unpack(NS.C.text)) end)
  close:SetScript("OnLeave", function() x:SetTextColor(unpack(NS.C.dim)) end)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close

  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("TOPLEFT", 12, -30)
  f.text:SetPoint("RIGHT", -12, 0)
  f.text:SetJustifyH("LEFT")
  f.text:SetJustifyV("TOP")
  f.text:SetSpacing(2)
  f.text:SetTextColor(unpack(NS.C.text))
  return f
end

-- A soft rounded button (tabs use it too: :SetActive(true) marks the selected one).
function NS.Button(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 70, 20)
  local bg = NS.Rounded(b, NS.C.button, "pill.png", 7)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER")
  fs:SetTextColor(unpack(NS.C.text))
  b:SetFontString(fs)
  b:SetText(label)
  b.bg, b.label = bg, fs
  function b:SetActive(on)
    self.active = on
    bg:SetColor(on and NS.C.hover or NS.C.button)
    fs:SetTextColor(unpack(on and NS.C.accent or NS.C.text))
  end
  b:SetScript("OnEnter", function(self) bg:SetColor(NS.C.hover) end)
  b:SetScript("OnLeave", function(self) bg:SetColor(self.active and NS.C.hover or NS.C.button) end)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------------------
-- Settings (Guide, Settings): each is a group, a name, a line about it, and how to read and set it. get() may return a word
-- instead of on/off; set() is then called with the opposite of "is it the first choice".
---------------------------------------------------------------------------
NS.settings = {}
function NS.Setting(group, name, about, get, set) NS.settings[#NS.settings + 1] = { group = group, name = name, about = about, get = get, set = set } end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
NS.commands = {}
function NS.Command(name, help, fn) NS.commands[name] = { help = help, fn = fn } end

local ORDER = { "talents", "quest", "xp", "pet", "stats", "size", "route", "skip", "list", "goal", "upgrades", "flips", "way", "arrow", "trail", "been", "pins", "map", "minimap", "record", "sync", "markers", "go", "clear", "errors" }
local function Help()
  NS.Print("commands (/sun or /sunstone):")
  for _, name in ipairs(ORDER) do
    local c = NS.commands[name]
    if (name == "sync" or name == "goal") and _G.SunstoneInbox == nil then c = nil end -- (only with the desktop helper)
    if c then DEFAULT_CHAT_FRAME:AddMessage("  |cffc99734/sun " .. name .. "|r " .. c.help) end
  end
end

NS.Command("errors", "- show errors Sunstone caught", function()
  if #NS.errors == 0 then NS.Print("no errors caught.") return end
  for _, e in ipairs(NS.errors) do DEFAULT_CHAT_FRAME:AddMessage("  " .. e) end
end)

SLASH_SUNSTONE1 = "/sun"
SLASH_SUNSTONE2 = "/sunstone"
SlashCmdList["SUNSTONE"] = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower()
  if not cmd and NS.Window then NS.Safe("window", NS.Window.Toggle) return end -- plain /sun opens the window
  local c = cmd and NS.commands[cmd]
  if not c then Help() return end
  NS.Safe("/sun " .. cmd, c.fn, rest or "")
end
