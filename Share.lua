-- Sunstone: sharing finds. Off until you switch it on. What's recorded (Recorder.lua, Finds.lua) is written as one text of numbers, which you can copy
-- to Sunstone's page (one link, with the finds in it), or the small Sunstone Share program sends by itself when you run it. An addon can't reach the internet, and this one doesn't
-- talk to other players: the text only ever goes into your own saved settings and the copy box. Everyone's texts together make the numbers the next
-- version ships with (CommunityData.lua).
-- In it: numbers about creatures, quests, chests, vendors, battlegrounds and dungeon runs; names of creatures nobody knew; a random number that
-- stands for "the same sender as before". Not in it: your character's name, realm, guild, account, gold, bags or gear, other players, chat.

local _, NS = ...
local Sh = NS.Module("Share")
NS.Share = Sh
local C = NS.C

Sh.PAGE = "https://malefactor2000.github.io/Sunstone/share/" -- where finds are sent from, and what's public about them
Sh.REMIND = 7 * 24 * 3600 -- by hand: a reminder at most this often, when there's enough new
Sh.ENOUGH = 25 -- new kills, quests, chests and the like worth a reminder
Sh.FORMAT = 2
local floor = math.floor
local function List(t) return type(t) == "table" and t or {} end
local function Count(t) local n = 0 for _ in pairs(List(t)) do n = n + 1 end return n end

function Sh.Cfg()
  local c = NS.db.share
  if type(c) ~= "table" then c = {}; NS.db.share = c end
  return c
end
function Sh.On() return Sh.Cfg().on == true end

-- a random sender number: not made from anything about you, and gone for good when you stop sharing
local function Token()
  local out = {}
  local seed = floor((GetTime() * 1000) % 1e6) + floor(time() % 1e6)
  for k = 1, 20 do
    seed = (seed * 1103 + 12345 + floor(math.random() * 1e6)) % 1e6
    out[k] = string.format("%x", floor((math.random() * 16 + seed) % 16))
  end
  return table.concat(out)
end
function Sh.Set(on)
  local c = Sh.Cfg()
  c.on = on and true or nil
  if on then c.id = c.id or Token() else c.id, NS.db.shareOut = nil, nil end
  if NS.Window and NS.Window.Refresh then NS.Window.Refresh() end
end

---------------------------------------------------------------------------
-- The text
---------------------------------------------------------------------------
local function Num(v)
  if v ~= v or v == math.huge or v == -math.huge then return "0" end
  if v == floor(v) then return string.format("%.0f", v) end
  return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end
local function Enc(v, out)
  local t = type(v)
  if t == "number" then out[#out + 1] = Num(v)
  elseif t == "string" then out[#out + 1] = '"' .. v:gsub('[^%w %-\',%.]', "") .. '"'
  elseif t == "table" then
    local n = #v
    if n > 0 and Count(v) == n then
      out[#out + 1] = "["
      for i = 1, n do if i > 1 then out[#out + 1] = "," end Enc(v[i], out) end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local first = true
      for k, x in pairs(v) do
        if (type(k) == "number" or type(k) == "string") and (type(x) == "number" or type(x) == "string" or type(x) == "table") then
          if not first then out[#out + 1] = "," end
          first = false
          out[#out + 1] = '"' .. (type(k) == "number" and Num(k) or k:gsub("[^%w]", "")) .. '":'
          Enc(x, out)
        end
      end
      out[#out + 1] = "}"
    end
  else out[#out + 1] = "0" end
end
Sh.Encode = function(v) local out = {} Enc(v, out) return table.concat(out) end

-- only these, whatever else the records hold
local MOB = { "k", "l", "c", "v", "x", "xk", "sn", "rv", "ty", "lo", "hi", "i", "r", "sk", "f" }
local CTX = { "t", "k", "l", "c", "x", "xr", "v", "rv", "gv", "i" }
local RUN = { "id", "lvl", "n", "t", "k", "l", "c", "x", "v", "rv", "i" }
local function Pick(t, fields)
  local o = {}
  for _, f in ipairs(fields) do
    local v = t[f]
    if type(v) == "number" and v ~= 0 or type(v) == "table" and next(v) then o[f] = v end
  end
  return o
end
function Sh.Data()
  local r = NS.Recorder.DB()
  local d = { quests = {}, mobs = {}, vend = {}, ctx = {}, runs = {}, sell = r.sell, qual = r.qual, cal = r.cal, pvp = r.pvp }
  for q, e in pairs(List(r.quests)) do d.quests[q] = Pick(e, { "x", "m", "l" }) end
  for npc, m in pairs(List(r.mobs)) do
    local o = Pick(m, MOB)
    if type(m.g) == "table" then o.g = Pick(m.g, MOB) end
    if next(o) then d.mobs[npc] = o end
  end
  for npc, v in pairs(List(r.vend)) do d.vend[npc] = Pick(v, { "r", "i" }) end
  for kind, levels in pairs(List(r.ctx)) do
    d.ctx[kind] = {}
    for l, b in pairs(List(levels)) do d.ctx[kind][l] = Pick(b, CTX) end
  end
  for _, run in ipairs(List(r.runs)) do d.runs[#d.runs + 1] = Pick(run, RUN) end
  local f = List(r.fx)
  d.fx = { at = f.at, obj = f.obj, box = f.box, fish = f.fish, qi = f.qi, nm = f.nm, xp = f.xp, kt = f.kt, news = f.news }
  return d
end
function Sh.Text()
  local d = Sh.Data()
  d.format, d.ver, d.id = Sh.FORMAT, NS.version, Sh.Cfg().id or ""
  return Sh.Encode(d)
end
-- the way it's copied: marked at both ends, with its length, so a half-pasted text is noticed
function Sh.Code()
  local t = Sh.Text()
  return string.format("SUNSTONE2:%d:%s:END", #t, t)
end
-- as the end of a link: only letters browsers leave alone. What's after the # stays in the browser until you press Send on the page.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
function Sh.Base64(s)
  local out, abc = {}, {}
  for k = 1, 64 do abc[k - 1] = B64:sub(k, k) end
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = abc[floor(n / 262144)] .. abc[floor(n / 4096) % 64] .. (b and abc[floor(n / 64) % 64] or "") .. (c and abc[n % 64] or "")
  end
  return table.concat(out)
end
function Sh.Link() return Sh.PAGE .. "#s2." .. Sh.Base64(Sh.Text()) .. ".end" end

-- how much there is, to know what's new since the last time
function Sh.Amount()
  local q, _, kills, loots = NS.Recorder.Stats()
  local fs = NS.Finds.Stats()
  return q * 2 + kills + loots + (fs.chests + fs.crates + fs.fishing) * 3 + fs.news * 30 + Count(NS.Recorder.DB().vend) * 3
end
function Sh.Fresh() return math.max(0, Sh.Amount() - (tonumber(Sh.Cfg().sent) or 0)) end
function Sh.ByHand() return Sh.Cfg().how ~= "auto" end
local function Since(t) return t and time() - (tonumber(t) or 0) or math.huge end
-- enough new since the last time, a week ago or more: the window's button lights up
function Sh.Due()
  return Sh.On() and Sh.ByHand() and Sh.Fresh() >= Sh.ENOUGH and Since(Sh.Cfg().at) >= Sh.REMIND
end
-- the line in chat: once a week while it's due
function Sh.RemindDue()
  local c = Sh.Cfg()
  return Sh.Due() and c.remind ~= false and Since(c.reminded) >= Sh.REMIND
end
-- the question when it's new: until it's answered, at most twice, a week apart
function Sh.AskDue()
  local c = Sh.Cfg()
  return not c.on and not c.asked and (tonumber(c.asks) or 0) < 2 and Since(c.askAt) >= Sh.REMIND
end

---------------------------------------------------------------------------
-- The page (Guide, Share)
---------------------------------------------------------------------------
local box
local function Box(title, text, help, after)
  if not box then
    box = NS.Panel("Share", 470, 150, "Share your finds")
    box:SetFrameStrata("DIALOG")
    if box.text then box.text:Hide() end
    local eb = CreateFrame("EditBox", nil, box) -- one line: a long text in many lines would stutter
    eb:SetAutoFocus(false)
    if eb.SetMaxLetters then eb:SetMaxLetters(0) end
    if eb.SetMaxBytes then eb:SetMaxBytes(0) end
    eb:SetFontObject(ChatFontNormal)
    eb:SetHeight(26)
    eb:SetPoint("TOPLEFT", 16, -42)
    eb:SetPoint("TOPRIGHT", -16, -42)
    eb:SetTextInsets(8, 8, 2, 2)
    if eb.SetTextColor then eb:SetTextColor(unpack(C.text)) end
    NS.Rounded(eb, C.surface, "round.png", 8)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); box:Hide() end)
    eb:SetScript("OnTextChanged", function(self, typed) if typed then self:SetText(box.want or "") if self.HighlightText then self:HighlightText() end end end)
    eb:SetScript("OnKeyDown", function(_, key)
      if key == "C" and IsControlKeyDown and IsControlKeyDown() and box.after then local fn = box.after C_Timer.After(0.3, function() NS.Safe("share", fn) end) end
    end)
    box.eb = eb
    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.hint:SetPoint("TOPLEFT", 18, -76)
    box.hint:SetPoint("TOPRIGHT", -18, -76)
    box.hint:SetJustifyH("LEFT")
    box.hint:SetTextColor(unpack(C.dim))
  end
  if NS.Window and NS.Window.Scale then box:SetScale(NS.Window.Scale()) end
  if box.title then box.title:SetText(title) end
  box.want, box.after = text, after
  box.eb:SetText(text)
  if box.eb.SetCursorPosition then box.eb:SetCursorPosition(0) end
  box.hint:SetText(help)
  box:Show()
  box.eb:SetFocus()
  if box.eb.HighlightText then box.eb:HighlightText() end
end
Sh.Box = Box
-- counted as sent once it's copied (the game can't see the browser)
local function Copied()
  local c = Sh.Cfg()
  c.sent, c.at = Sh.Amount(), time()
  if box then box.hint:SetText("Copied. Now paste it into your browser's address bar, press Enter, and press Send on the page. That's all: next time is the same.") end
end
function Sh.Copy()
  Box("Send your finds", Sh.Link(), "1. Ctrl+C copies the link, with your finds in it.\n2. Paste it into your browser's address bar and press Enter.\n3. The page shows what's in it. Press Send there.\n(The game doesn't let addons open a browser by themselves.)", Copied)
end
function Sh.CopyCode()
  Box("Your finds as text", Sh.Code(), "Exactly what's sent, nothing else. Ctrl+C copies it; it can be pasted into the box on the page too: " .. Sh.PAGE, Copied)
end
function Sh.CopyPage()
  Box("Sunstone's share page", Sh.PAGE, "Ctrl+C, then paste it into your browser: what sharing is, the Sunstone Share program, the AI version.")
end

---------------------------------------------------------------------------
-- The question, with Yes and No; and the window's button
---------------------------------------------------------------------------
local ask
local function Buttons(list)
  for k, b in ipairs(ask.b) do
    local want = list[k]
    b:SetShown(want ~= nil)
    if want then
      b:SetText(want[1])
      b:SetSize(want[3], 26)
      b.fn = want[2]
      b:SetActive(want[4])
      b:ClearAllPoints()
      if k == 1 then b:SetPoint("BOTTOMLEFT", 18, 16) else b:SetPoint("LEFT", ask.b[k - 1], "RIGHT", 10, 0) end
    end
  end
end
local function Say(title, text)
  ask.title:SetText(title)
  ask.text:SetText(text)
end
function Sh.No()
  local c = Sh.Cfg()
  c.asked = true
  if ask then ask.answered = true; ask:Hide() end
  NS.Print("all right, nothing is shared. If you change your mind, the Share button is at the top of Sunstone's window.")
end
local function How(auto)
  Sh.Cfg().how = auto and "auto" or nil
  ask:Hide()
  if auto then Sh.CopyPage()
  else NS.Print("thank you! Once a week a line here in chat reminds you, with a link to click.") end
  if NS.Window then NS.Window.Refresh() end
end
function Sh.Yes()
  Sh.Set(true)
  local c = Sh.Cfg()
  c.asked = true
  c.at = c.at or time() -- the first reminder in a week
  if not ask then return end
  ask.answered = true
  Say("Thank you! How should they be sent?", "|cff" .. NS.HEX.accent .. "Remind me weekly:|r a line in chat with a link to click. Copy, paste in your browser, press Send.\n\n"
    .. "|cff" .. NS.HEX.accent .. "By itself:|r a small free program (Windows) does it for you after you log out. You get the address of its page next.")
  Buttons({ { "Remind me weekly", function() How(false) end, 140, true }, { "By itself", function() How(true) end, 90 } })
end
function Sh.Ask()
  if not ask then
    ask = NS.Panel("AskShare", 430, 218, "")
    ask:SetFrameStrata("DIALOG")
    ask.title:SetFontObject("GameFontNormalLarge")
    ask.title:ClearAllPoints()
    ask.title:SetPoint("TOPLEFT", 18, -14)
    ask.text:ClearAllPoints()
    ask.text:SetPoint("TOPLEFT", 18, -44)
    ask.text:SetPoint("RIGHT", -18, 0)
    ask.text:SetFontObject("GameFontHighlight")
    ask.text:SetTextColor(unpack(C.text))
    ask.b = {}
    for k = 1, 3 do
      local b
      b = NS.Button(ask, "", 100, function() if b.fn then NS.Safe("share", b.fn) end end)
      ask.b[k] = b
    end
    ask:SetScript("OnHide", function(self)
      if self.answered then return end
      local c = Sh.Cfg() -- closed without an answer: once more in a week, then never again
      c.askAt, c.asks = time(), (tonumber(c.asks) or 0) + 1
    end)
  end
  if NS.Window and NS.Window.Scale then ask:SetScale(NS.Window.Scale()) end
  if not (NS.db.frames and NS.db.frames.AskShare) then
    ask:ClearAllPoints()
    ask:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
  ask.answered = false
  Say("Help everyone's numbers?", "Forever is new, and a lot of it isn't written down anywhere yet. Sunstone can share what your characters see (drops, XP, prices, where pets and mounts come from), "
    .. "and everyone's come back to all of us with each update.\n\nNumbers only: no names, no realm, no chat, no gold or gear. You can stop any time.")
  Buttons({ { "Yes, share", Sh.Yes, 100, true }, { "No, thanks", Sh.No, 100 },
            { "What's in it?", function() ask:Hide(); NS.cdb.guideMode = "share"; if NS.Window then NS.Window.Open("guide") end end, 110 } })
  ask:Show()
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN) end
end

-- the button at the top of Sunstone's window
function Sh.Press()
  if not Sh.On() then Sh.Ask()
  elseif Sh.ByHand() then Sh.Copy()
  else NS.cdb.guideMode = "share"; if NS.Window then NS.Window.Open("guide") end end
end
function Sh.Label(b)
  local due = Sh.Due()
  b:SetText(not Sh.On() and "Share finds" or Sh.ByHand() and (due and "Send finds!" or "Send finds") or "Sharing: on")
  b:SetActive(due)
end
function Sh.Tip(b)
  if not GameTooltip then return end
  GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(Sh.On() and "You share your finds" or "Help everyone's numbers", C.accent[1], C.accent[2], C.accent[3])
  GameTooltip:AddLine(not Sh.On() and "Off. Click to see what it is, and say yes or no." or Sh.ByHand() and "Click: one link with your finds in it, to paste into your browser." or "Sent by the Sunstone Share program or the AI version. Click for more.", C.text[1], C.text[2], C.text[3], true)
  GameTooltip:Show()
end

local function Calm() -- a moment to say something: not fighting, not inside, not in a cutscene
  return not (InCombatLockdown and InCombatLockdown()) and not (IsInInstance and IsInInstance() == true) and not (UnitOnTaxi and UnitOnTaxi("player") == true)
    and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") == true) and not (UIParent.IsShown and UIParent:IsShown() == false)
end
function Sh.Moment()
  if not Calm() then return end
  if Sh.AskDue() then
    if not (ask and ask:IsShown()) then Sh.Ask() end
  elseif Sh.RemindDue() then
    Sh.Cfg().reminded = time()
    NS.Print("you have new finds that would help everyone. Click |Haddon:Sunstone:share|h|cff" .. NS.HEX.accent .. "[Send my finds]|r|h, or the Send finds button at the top of Sunstone's window. (Once a week; off in Guide, Settings.)")
    if NS.Window then NS.Window.Refresh() end
  end
end

local function KB(n) return n >= 1024 and string.format("%d KB", floor(n / 1024 + 0.5)) or (n .. " bytes") end

function Sh.Rows()
  local rows = {}
  local on = Sh.On()
  local q, mobs, kills, loots = NS.Recorder.Stats()
  local fs = NS.Finds.Stats()
  local vend = Count(NS.Recorder.DB().vend)
  rows[#rows + 1] = { t = on and "You share your finds" or "Share your finds?", ring = on and "good" or nil, key = "share", still = true, actLabel = on and "Stop" or "Share",
                      d = on and "Thank you! Nothing sent is tied to you." or
                        "Drops, XP, prices, pets and mounts: it helps everyone.",
                      act = function() Sh.Set(not on) end }
  if on then
    local hand = Sh.ByHand()
    local c = Sh.Cfg()
    rows[#rows + 1] = { t = hand and "You send them by hand" or "Sent by itself", still = true, key = "sharehow", actLabel = hand and "By itself" or "By hand",
                        d = hand and "A line in chat reminds you once a week." or "The Sunstone Share program or the AI version does it.",
                        act = function() c.how = hand and "auto" or nil if NS.Window then NS.Window.Refresh() end end }
    if hand then
      local fresh = Sh.Fresh()
      rows[#rows + 1] = { t = fresh > 0 and "Send your new finds" or "Nothing new to send", still = true, key = "sharecopy", ring = Sh.Due() and "good" or nil, dim = fresh == 0 or nil, actLabel = "Copy link", act = Sh.Copy,
                          d = "Paste the link into your browser, press Send." .. (c.at and (" Last time: " .. date("%d %b", c.at) .. ".") or "") }
    end
    rows[#rows + 1] = { t = "By itself", still = true, key = "shareauto", actLabel = "Page", act = Sh.CopyPage,
                        d = "Optional: a small Windows program, or the AI version." }
  end
  rows[#rows + 1] = { h = "What's in it" }
  rows[#rows + 1] = { t = string.format("%d kinds of creatures, %d kills, %d looted", mobs, kills, loots), still = true, key = "sh1", d = "Coins, drops, skinning, XP, reputation, and where you fought them." }
  rows[#rows + 1] = { t = string.format("%d quests, %d vendors", q, vend), still = true, key = "sh2", d = "What each quest paid and what vendors charge." }
  rows[#rows + 1] = { t = string.format("%d chests, %d kinds of crates, %d fishing grounds", fs.chests, fs.crates, fs.fishing), still = true, key = "sh3", d = "How often they were opened and what was in them." }
  rows[#rows + 1] = { t = "Fight times and XP by level", still = true, key = "sh4", d = "Per class; battlegrounds and dungeon runs timed." }
  if on then
    local ok, text = pcall(Sh.Text)
    rows[#rows + 1] = { t = "The whole text: " .. (ok and KB(#text) or "?"), still = true, key = "sh5", actLabel = "Look", d = "Exactly what would be sent, nothing else.", act = Sh.CopyCode }
  end
  rows[#rows + 1] = { h = "What's never in it" }
  rows[#rows + 1] = { t = "Anything about you or other players", still = true, key = "sh6", d = "No names, realm, guild, gold, bags, gear, chat or friends." }
  local news = NS.Finds.DB().news
  rows[#rows + 1] = { h = "Your new finds" }
  for k = #news, math.max(1, #news - 20), -1 do
    local e = news[k]
    rows[#rows + 1] = { t = NS.Engine.ItemName(e.i), i = e.i, still = true, key = "news" .. k, d = NS.Finds.KIND[e.k]:gsub("^%l", string.upper) .. " " .. NS.Finds.SourceName(e.k, e.s) .. ((e.n or 1) > 1 and (", seen " .. e.n .. " times") or "") .. "." }
  end
  if #news == 0 then rows[#rows + 1] = { t = "None yet", still = true, dim = true, key = "nonews", d = "A companion pet or mount from a source nobody had on record shows up here." } end
  local Cm = NS.Community
  rows[#rows + 1] = { h = "Everyone's numbers in this version" }
  local n, when = Cm and Cm.Players() or 0, Cm and Cm.Built()
  rows[#rows + 1] = { t = n > 0 and string.format("From %d players%s", n, when and (", " .. when) or "") or "None yet", still = true, key = "shall", dim = n == 0 or nil,
                      d = n > 0 and Cm.About() or "The first ones come with the first update after players share." }
  return rows
end

function Sh:Init()
  NS.On("PLAYER_LOGOUT", function()
    if Sh.On() then
      local ok, text = pcall(Sh.Text)
      NS.db.shareOut = ok and { v = Sh.FORMAT, id = Sh.Cfg().id, text = text } or nil
    else
      NS.db.shareOut = nil
    end
  end)
  C_Timer.After(12, function()
    NS.Safe("share", Sh.Moment)
    C_Timer.NewTicker(30, function() NS.Safe("share", Sh.Moment) end)
  end)
  local clicked = 0
  local function Link(link)
    if link ~= "addon:Sunstone:share" or GetTime() - clicked < 0.5 then return end
    clicked = GetTime()
    if Sh.On() then NS.Safe("share", Sh.Copy) end
  end
  if EventRegistry and EventRegistry.RegisterCallback then pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link) Link(link) end, Sh) end
  if SetItemRef and hooksecurefunc then pcall(hooksecurefunc, "SetItemRef", Link) end
  NS.Setting("Sharing", "Remind me to send them", "A line in chat once a week, when you share by hand and there's something new.", function() return Sh.Cfg().remind ~= false end, function(v) Sh.Cfg().remind = v and true or false end)
  NS.Setting("Sharing", "Share my finds", "Off unless you want to help everyone's numbers. Guide, Share says exactly what's in it.", function() return Sh.On() end, Sh.Set)
end

NS.Command("share", "what sharing your finds would send, and the switch (off by default)", function(rest)
  rest = (rest or ""):lower()
  if rest == "on" or rest == "off" then
    Sh.Set(rest == "on")
    NS.Print(Sh.On() and "sharing your finds is on. Thank you!" or "sharing is off, and your sender number is gone.")
    return
  end
  if rest == "copy" then
    if Sh.On() then Sh.Copy() else NS.Print("sharing is off. Switch it on first: /sun share on") end
    return
  end
  NS.cdb.guideMode = "share"
  if NS.Window then NS.Window.Open("guide") end
end)
