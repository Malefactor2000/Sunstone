-- Sunstone: everyone's numbers. What players shared, pooled and checked (CommunityData.lua, made by tools/community/build_data.py): drops and coins
-- per creature, where creatures are, what chests and crates hold, sources of pets and mounts, vendor prices, fight times and XP by level.
-- Your own numbers still come first; these fill in what you haven't seen, and replace Classic's tables where enough Forever players agree.

local _, NS = ...
local Cm = NS.Module("Community")
NS.Community = Cm

Cm.ENOUGH = 100 -- corpses before the players' numbers stand instead of Classic's table
local function D() return type(_G.SunstoneCommunity) == "table" and _G.SunstoneCommunity or {} end
local function List(t) return type(t) == "table" and t or {} end

function Cm.Players() return tonumber(D().players) or 0 end
function Cm.Built() return type(D().built) == "string" and D().built or nil end
function Cm.About()
  local function N(t) local n = 0 for _ in pairs(List(t)) do n = n + 1 end return n end
  return string.format("%d kinds of creatures, %d vendors, %d chests and crates, %d sources of pets and mounts.", N(D().mobs), N(D().vend), N(D().obj) + N(D().box), N(D().src))
end

-- a creature: { l = corpses, n = players, c = coins a corpse, i = { item, per corpse, ... }, lo, hi }
function Cm.Mob(id) local m = List(D().mobs)[id] return type(m) == "table" and m or nil end
-- where it is: { map, x, y (0 to 100), ... }
function Cm.Where(id) return List(D().at)[id] end
function Cm.Name(id) local n = List(D().names)[id] return type(n) == "string" and n or nil end
-- what a chest, crate or a zone's fishing gave: { n = opened, i = { item, times, ... }, at = { map, x, y, ... } }
function Cm.Chest(id) return List(D().obj)[id] end
function Cm.Crate(id) return List(D().box)[id] end
function Cm.Fishing(m) return List(D().fish)[m] end
-- sources of a pet or mount: { kind, id, players, times seen, of how many (0 = not counted), ... } (kinds: Finds.lua)
function Cm.Sources(item)
  local out, s = {}, List(List(D().src)[item])
  for k = 1, #s, 5 do out[#out + 1] = { kind = s[k], id = s[k + 1], players = s[k + 2], n = s[k + 3], of = s[k + 4] } end
  return out
end
function Cm.HasSource(item, kind, src)
  for _, e in ipairs(Cm.Sources(item)) do if e.kind == kind and e.id == src then return true end end
  return false
end
-- what a vendor charges: copper for one
function Cm.Price(item, npc)
  local v = List(D().vend)
  if npc then
    local s = List(v[npc])
    for k = 1, #s, 3 do if s[k] == item then return s[k + 1] / math.max(1, s[k + 2]) end end
    return nil
  end
  for _, s in pairs(v) do
    for k = 1, #s, 3 do if s[k] == item then return s[k + 1] / math.max(1, s[k + 2]) end end
  end
end
-- seconds a kill (walking and resting included) others took, solo at a level
function Cm.Pace(level)
  local t, k = 0, 0
  for l = level - 1, level + 1 do
    local p = List(D().pace)[l]
    if type(p) == "table" then t, k = t + p[1], k + p[2] end
  end
  if k >= 100 then return t / k, k end
end
-- XP of a kill: Forever's own, by your level and how much higher or lower the creature is
function Cm.XP(level, diff, elite)
  local e = List(List(D().xp)[level])[elite and diff + 100 or diff]
  if type(e) == "table" and e[1] >= 5 then return e[2], e[1] end
end
-- how long a fight takes your class at your level against a creature `diff` levels off: seconds, fights
function Cm.Fight(class, level, diff)
  local e = List(List(List(D().kt)[class])[level])[diff]
  if type(e) == "table" and e[1] >= 5 then return e[2], e[1] end
end
