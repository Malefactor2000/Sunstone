-- Sunstone: tells you at login when a newer Sunstone is out, and how to get it: in the CurseForge app for a copy from
-- CurseForge, from GitHub's Releases for one from GitHub. Addons can't go online, so it asks other players' Sunstone, the way
-- OneForAll and Dungeon Journal do.
--
-- The one exception to "silent" (the player's call, 2026-11-26), kept as small as it can be:
--   * The only thing sent or read is a version number like 2.5.9, under Sunstone's own addon-message prefix. Anything
--     else is dropped unread. Nothing received is shown, saved or passed on except the number Sunstone rebuilds from
--     its digits.
--   * It asks once per login: your guild, your party or raid, and Sunstone's own hidden channel. A released copy that's
--     newer answers. Test builds never answer, so nobody hears about a version that isn't out yet.
--   * A number from the channel (strangers) only counts once two different players report it. The sender is used only
--     to tell those two apart: never shown, never saved.
--   * Off in the Guide, Settings, Sharing: then nothing is sent, read or joined.

local ADDON, NS = ...
local V = {}
NS.Version = V
V.released = true -- tools/build_release.py turns this on in the public copy: only released copies answer
V.from = "github" -- where this copy came from: "curseforge" or "github" (tools/build_release.py sets it in each one)
local GET = {
  curseforge = "Update it in the CurseForge app.",
  github = "Download it from github.com/Malefactor2000/Sunstone/releases",
}

local PREFIX, CHANNEL = "Sunstone", "SunstoneVersions"
local LOGIN_WINDOW = 120 -- seconds: a newer version heard this soon after login is said at once, later ones at the next login
local TRUSTED = { GUILD = true, PARTY = true, RAID = true }

local function Parse(s)
  if type(s) ~= "string" or #s > 11 then return nil end
  local a, b, c = s:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) }
end
local function Newer(x, y) -- is x newer than y
  for i = 1, 3 do if x[i] ~= y[i] then return x[i] > y[i] end end
  return false
end
local function Text(t) return string.format("%d.%d.%d", t[1], t[2], t[3]) end
V.Parse, V.Newer = Parse, Newer

local mine = Parse(NS.version)
local loginAt, toldNow, joined, registered = nil, false, false, false
local heard, nHeard, lastSent, lastAnswer = {}, 0, {}, {}

function V.On() return mine ~= nil and not (NS.db and NS.db.versionCheck == false) end
local function Now() return GetTime and GetTime() or 0 end

local function Send(msg, dist, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, dist, target) end
end
local function ChannelId()
  local id = GetChannelName and GetChannelName(CHANNEL)
  return type(id) == "number" and id > 0 and id or nil
end

local function Tell(v)
  toldNow = true
  local t = Parse(v)
  local major = t and mine and (t[1] > mine[1] or t[2] > mine[2]) -- the first or second number went up
  local what = major and string.format("A major Sunstone update is out: %s", v) or string.format("Sunstone %s is out", v)
  NS.Print(string.format("|cffffd100%s (you have %s). %s|r", what, NS.version, GET[V.from or ""] or "Get it from CurseForge or GitHub."))
end

-- A newer version someone reported: kept for your next login, and said now if you've only just logged in
local function Report(t, trusted, from)
  if not (t and Newer(t, mine)) or t[1] > mine[1] + 1 then return end
  local v = Text(t)
  if not trusted then
    local h = heard[v]
    if not h then
      if nHeard >= 20 then return end
      nHeard = nHeard + 1
      h = { n = 0, from = {} }
      heard[v] = h
    end
    if type(from) ~= "string" or from == "" or h.from[from] or h.n >= 5 then return end
    h.from[from] = true
    h.n = h.n + 1
    if h.n < 2 then return end
  end
  local saved = Parse(NS.db.newVersion)
  if not saved or Newer(t, saved) then NS.db.newVersion = v end
  if not toldNow and loginAt and Now() - loginAt <= LOGIN_WINDOW then Tell(NS.db.newVersion) end
end

-- Someone with an older Sunstone asked: a released copy answers, unless another player answers first
local function Answer(dist)
  if not V.released then return end
  if lastSent[dist] and Now() - lastSent[dist] < 30 then return end
  lastSent[dist] = Now()
  local asked = Now()
  C_Timer.After(1 + math.random() * 4, function()
    if not V.On() or (lastAnswer[dist] or -1) >= asked then return end
    if dist == "CHANNEL" then
      local id = ChannelId()
      if id then Send("V:" .. Text(mine), "CHANNEL", id) end
    else
      Send("V:" .. Text(mine), dist)
    end
  end)
end

local function Heard(prefix, msg, dist, sender)
  if prefix ~= PREFIX or not V.On() then return end
  if not (TRUSTED[dist] or dist == "CHANNEL") or type(msg) ~= "string" or #msg > 14 then return end
  local kind, rest = msg:match("^([QV]):(.+)$")
  local t = kind and Parse(rest)
  if not t then return end
  Report(t, TRUSTED[dist], sender)
  if kind == "V" and not Newer(mine, t) then lastAnswer[dist] = Now() end
  if kind == "Q" and Newer(mine, t) then Answer(dist) end
end

local function Join()
  if joined or not V.On() or not JoinTemporaryChannel then return end
  joined = true
  pcall(JoinTemporaryChannel, CHANNEL)
  for i = 1, (NUM_CHAT_WINDOWS or 10) do -- never shown in a chat window
    local f = _G["ChatFrame" .. i]
    if f and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, f, CHANNEL) end
  end
end

local function Ask()
  if not V.On() then return end
  local q = "Q:" .. Text(mine)
  if IsInGuild and IsInGuild() then Send(q, "GUILD") end
  if IsInRaid and IsInRaid() then Send(q, "RAID") elseif IsInGroup and IsInGroup() then Send(q, "PARTY") end
  local id = ChannelId()
  if id then Send(q, "CHANNEL", id) end
end

function V.Start()
  loginAt, toldNow = Now(), false
  local saved = Parse(NS.db.newVersion)
  if saved and not (mine and Newer(saved, mine)) then NS.db.newVersion, saved = nil, nil end -- you've updated
  if not V.On() then return end
  if not registered and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    registered = true
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  end
  C_Timer.After(8, function() if saved and not toldNow and V.On() then Tell(Text(saved)) end end)
  -- the channel after the game's own (General, Trade) so their numbers stay the same
  C_Timer.After(15, function() NS.Safe("version check", Join) end)
  C_Timer.After(20, function() NS.Safe("version check", Ask) end)
end

NS.On("PLAYER_LOGIN", function() V.Start() end)
NS.On("CHAT_MSG_ADDON", Heard)

NS.Setting("Sharing", "Tell me about new versions",
  "At login Sunstone asks your guild, your group and its own hidden channel which version they run, and says in chat when a newer one is out. Only version numbers are sent. Off: nothing is sent or joined.",
  V.On, function(v)
    NS.db.versionCheck = v and true or false
    if v then
      V.Start()
    elseif joined then
      joined = false
      if LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
    end
  end)
