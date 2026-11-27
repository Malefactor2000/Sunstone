-- Sunstone: talent reminder. Reads your live talents, compares them with the plan in
-- Plans.lua and pops up what to take whenever you have points to spend.

local _, NS = ...
local T = NS.Module("Talents")
NS.Talents = T

local function SpellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok, v = pcall(C_Spell.GetSpellName, id)
    if ok and v then return v end
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Returns { [lowercase talent name] = rank }, total points spent.
-- Forever uses the trait (C_Traits) system with classic trees; older clients use GetTalentInfo.
function T.Read()
  local ranks, spent = {}, 0
  T.bySpell = {}
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo then
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    local ci = ok and configID and C_Traits.GetConfigInfo(configID)
    if ci and ci.treeIDs then
      local found = false
      for _, treeID in ipairs(ci.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
          local ni = C_Traits.GetNodeInfo(configID, nodeID)
          if ni and ni.isVisible ~= false then
            local rank = ni.currentRank or ni.ranksPurchased or 0
            local entryID = ni.activeEntry
            if type(entryID) == "table" then entryID = entryID.entryID end
            if not entryID and ni.entryIDs then entryID = ni.entryIDs[1] end
            local name
            if entryID then
              local ei = C_Traits.GetEntryInfo(configID, entryID)
              local di = ei and ei.definitionID and C_Traits.GetDefinitionInfo(ei.definitionID)
              name = di and (di.overrideName or SpellName(di.spellID or di.overriddenSpellID))
            end
            if name and name ~= "" then
              found = true
              local spell = entryID and C_Traits.GetEntryInfo(configID, entryID)
              spell = spell and spell.definitionID and C_Traits.GetDefinitionInfo(spell.definitionID)
              if spell and type(spell.spellID) == "number" and rank > (T.bySpell[spell.spellID] or 0) then T.bySpell[spell.spellID] = rank end
              local key, old = name:lower(), 0
              old = ranks[key] or 0
              if rank > old then -- some builds expose a talent twice: keep the higher rank
                ranks[key] = rank
                spent = spent + rank - old
              end
            end
          end
        end
      end
      if found then return ranks, spent end
    end
  end
  if GetNumTalentTabs and GetTalentInfo then
    for tab = 1, GetNumTalentTabs() do
      for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
        local name, _, _, _, rank = GetTalentInfo(tab, i)
        if name then
          ranks[name:lower()] = rank or 0
          spent = spent + (rank or 0)
        end
      end
    end
    return ranks, spent
  end
end

-- The built-in plans for a class (Plans.lua). An older single-plan table still works.
function NS.ClassPlans(class)
  local p = NS.PLANS and NS.PLANS[class]
  if type(p) ~= "table" then return {} end
  if p.steps then return { p } end
  return p
end

-- The first built-in plan for this class that serves the goal (solo, leveling, dungeons, tank, heal, dps).
function NS.PlanFor(class, goal)
  for _, p in ipairs(NS.ClassPlans(class)) do
    for _, g in ipairs(p.goals or {}) do
      if g == goal then return p end
    end
  end
end

-- A custom plan the desktop helper sent for this character, if any.
function NS.CustomPlan()
  local _, class = UnitClass("player")
  local o = NS.db and NS.db.planOverrides and NS.db.planOverrides[NS.CharKey()]
  if o and o.class == class and o.steps then return o end
end

-- The group roles each class can really fill (the player's call, 2026-11-27); every class can level.
NS.CLASS_ROLES = {
  WARRIOR = { tank = true, dps = true }, PALADIN = { heal = true, tank = true }, HUNTER = { dps = true },
  ROGUE = { dps = true }, PRIEST = { heal = true }, SHAMAN = { heal = true, dps = true }, MAGE = { dps = true },
  WARLOCK = { dps = true }, DRUID = { heal = true, tank = true, dps = true },
}
local GROUP_ROLE = { tank = true, heal = true, dps = true }

-- Can this character pick the goal? Only goals with a plan for the class, and only roles the class can fill.
function NS.GoalAvailable(goal)
  if goal == "custom" then return NS.CustomPlan() ~= nil end
  local _, class = UnitClass("player")
  if GROUP_ROLE[goal] and not (NS.CLASS_ROLES[class or ""] or {})[goal] then return false end
  return NS.PlanFor(class, goal) ~= nil
end

-- The role the goal amounts to: "leveling" (Solo too), "tank", "heal" or "dps"; nil for a plan of your own
function NS.Role(goal)
  goal = goal or NS.TalentGoal()
  if goal == "leveling" or goal == "solo" then return "leveling" end
  if GROUP_ROLE[goal] then return goal end
  if goal == "dungeons" then -- the class's main group role: what its dungeon plan is also for
    local _, class = UnitClass("player")
    local p = NS.PlanFor(class, "dungeons")
    for _, g in ipairs(p and p.goals or {}) do if GROUP_ROLE[g] then return g end end
    return "dps"
  end
  return nil
end

-- The goal this character picked on the Talents tab (saved per character). "custom" = the helper's plan.
-- Nothing picked (or a goal the class has no plan for): the helper's plan if there is one, else leveling.
function NS.TalentGoal()
  local g = NS.cdb and NS.cdb.talents and NS.cdb.talents.goal
  if g and NS.GoalAvailable(g) then return g end
  return NS.CustomPlan() and "custom" or "leveling"
end

-- Has this character picked a role (its goal) yet? Until then Sunstone goes by Leveling.
function NS.RolePicked()
  local g = NS.cdb and NS.cdb.talents and NS.cdb.talents.goal
  return g ~= nil and NS.GoalAvailable(g)
end

-- Returns false (and changes nothing) when the class has no plan for the goal.
function NS.SetTalentGoal(goal)
  if not NS.GoalAvailable(goal) then return false end
  NS.cdb.talents.goal = goal
  -- the role picks the stat weights: score the gear again for it
  if NS.Upgrades and NS.Upgrades.Evaluate and NS.Upgrades.evaluated and not NS.Upgrades.scanning then
    NS.Debounce("upgradesEval", 0.3, NS.Upgrades.Evaluate)
  end
  if NS.Window and NS.Window.Refresh then NS.Window.Refresh() end
  T.Refresh()
  return true
end

-- What a goal is called on screen.
function NS.GoalLabel(goal)
  if goal == "custom" then return "Custom" end
  for _, g in ipairs(NS.GOALS or {}) do
    if g[1] == goal then return g[2] end
  end
  return goal or "?"
end

-- This character's plan: the built-in one for the goal they picked, or the helper's custom plan.
function NS.ActivePlan()
  local _, class = UnitClass("player")
  local goal = NS.TalentGoal()
  if goal == "custom" then return NS.CustomPlan() or NS.PlanFor(class, "leveling") end
  return NS.PlanFor(class, goal)
end

-- Every talent of this character's class with its tooltip text, for planning in the helper.
-- { name, rank, max, desc (current rank, or rank 1), nextDesc }
function T.Tree()
  local out = {}
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return out end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  local ci = ok and configID and C_Traits.GetConfigInfo(configID)
  if not (ci and ci.treeIDs) then return out end
  local seen = {}
  for _, treeID in ipairs(ci.treeIDs) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local ni = C_Traits.GetNodeInfo(configID, nodeID)
      if ni and ni.isVisible ~= false then
        local entryID = ni.activeEntry
        if type(entryID) == "table" then entryID = entryID.entryID end
        if not entryID and ni.entryIDs then entryID = ni.entryIDs[1] end
        local ei = entryID and C_Traits.GetEntryInfo(configID, entryID)
        local di = ei and ei.definitionID and C_Traits.GetDefinitionInfo(ei.definitionID)
        local name = di and (di.overrideName or SpellName(di.spellID or di.overriddenSpellID))
        if name and not seen[name] then
          seen[name] = true
          local rank, max = ni.currentRank or ni.ranksPurchased or 0, ni.maxRanks or 1
          local function Desc(r)
            if not C_Traits.GetTraitDescription then return nil end
            local okd, d = pcall(C_Traits.GetTraitDescription, entryID, r)
            return okd and type(d) == "string" and d or nil
          end
          out[#out + 1] = { name = name, rank = rank, max = max, desc = Desc(math.max(1, rank)),
                            nextDesc = (rank > 0 and rank < max) and Desc(rank + 1) or nil }
        end
      end
    end
  end
  return out
end

function T.Status(levelOverride)
  local plan = NS.ActivePlan()
  if not plan then return nil end
  local ranks, spent = T.Read()
  if not ranks then return nil end
  local level = levelOverride or UnitLevel("player")
  local available = math.max(0, level - 9)
  local st = { level = level, spent = spent, unspent = available - spent, plan = plan,
               missing = {}, offplan = {}, upcoming = {} }
  local target = {}
  for lvl = 10, math.min(level, 60) do
    local s = plan.steps[lvl]
    if s then
      local key = s[1]:lower()
      if (target[key] or 0) < s[2] then target[key] = s[2] end
      if (ranks[key] or 0) < s[2] then
        st.missing[#st.missing + 1] = { level = lvl, name = s[1], rank = s[2], note = s[3] }
      end
    end
  end
  for key, r in pairs(ranks) do
    if r > (target[key] or 0) then st.offplan[#st.offplan + 1] = { key = key, have = r, planned = target[key] or 0 } end
  end
  for lvl = level + 1, math.min(60, level + 3) do
    local s = plan.steps[lvl]
    if s then st.upcoming[#st.upcoming + 1] = { level = lvl, name = s[1], rank = s[2], note = s[3] } end
  end
  return st
end

local function Describe(st)
  local out = {}
  if st.unspent > 0 then
    out[#out + 1] = string.format("|cffc99734You have %d talent point%s to spend:|r", st.unspent, st.unspent == 1 and "" or "s")
    local shown = 0
    for _, m in ipairs(st.missing) do
      if shown >= st.unspent then break end
      shown = shown + 1
      out[#out + 1] = string.format("  |cff8aa666%s|r  rank %d  |cff8f7d68(level %d)|r", m.name, m.rank, m.level)
      if m.note then out[#out + 1] = "    |cff8f7d68" .. m.note .. "|r" end
    end
    if shown == 0 then out[#out + 1] = "  (the plan has nothing left for your level)" end
  else
    out[#out + 1] = "|cff8aa666All talent points are spent.|r"
  end
  if #st.offplan > 0 then
    local names = {}
    for _, o in ipairs(st.offplan) do names[#names + 1] = string.format("%s %d (plan: %d)", o.key, o.have, o.planned) end
    out[#out + 1] = "|cffc46148Differs from the plan:|r " .. table.concat(names, ", ")
  end
  if #st.upcoming > 0 then
    local next = {}
    for _, u in ipairs(st.upcoming) do next[#next + 1] = string.format("%d: %s %d", u.level, u.name, u.rank) end
    out[#out + 1] = "|cff8f7d68Coming up: " .. table.concat(next, " · ") .. "|r"
  end
  return table.concat(out, "\n")
end
T.Describe = Describe

local frame
local function GetFrame()
  if frame then return frame end
  frame = NS.Panel("Talents", 360, 150, "Sunstone · Talents")
  local ok = NS.Button(frame, "Got it", 70, function() frame:Hide() end)
  ok:SetPoint("BOTTOMRIGHT", -8, 8)
  local plan = NS.Button(frame, "Whole plan", 90, function() T.PrintPlan() end)
  plan:SetPoint("RIGHT", ok, "LEFT", -6, 0)
  frame:Hide()
  return frame
end

local function NoPlanText()
  local name = UnitName("player") or "this character"
  local className = UnitClass("player") or "class"
  return name .. " (" .. className .. ") has no " .. NS.GoalLabel(NS.TalentGoal()) .. " talent plan yet. "
    .. "Pick another goal on the Sunstone window's Talents tab (or /sun talents goal <name>)."
end

function T.Show(force, levelOverride)
  local st = T.Status(levelOverride)
  if not st then
    if force or (levelOverride and not NS.ActivePlan()) then NS.Print(NoPlanText()) end
    return
  end
  if not force and st.unspent <= 0 then return end
  local f = GetFrame()
  f.text:SetText(Describe(st))
  f:SetHeight(math.max(110, f.text:GetStringHeight() + 64))
  f:Show()
end

function T.Refresh()
  if frame and frame:IsShown() then T.Show(true) end
end

function T.PrintPlan()
  local plan = NS.ActivePlan()
  if not plan then NS.Print(NoPlanText()) return end
  NS.Print("talent plan: " .. (plan.name or "?"))
  local level = UnitLevel("player")
  for lvl = 10, 60 do
    local s = plan.steps[lvl]
    if s then
      local color = lvl <= level and "|cff8f7d68" or "|cffccb894"
      DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%d: %s %d|r%s", color, lvl, s[1], s[2], s[3] and ("  |cff8f7d68- " .. s[3] .. "|r") or ""))
    end
  end
end

function T:Init()
  NS.On("PLAYER_LEVEL_UP", function(newLevel)
    if NS.cdb.talents.popup then C_Timer.After(2, function() NS.Safe("talents", T.Show, false, newLevel) end) end
  end)
  for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
    NS.On(ev, function() NS.Debounce("talentRefresh", 0.5, T.Refresh) end)
  end
  -- On login, remind once if points are waiting.
  C_Timer.After(6, function() if NS.cdb.talents.popup then NS.Safe("talents", T.Show, false) end end)
end

NS.Command("talents", "- what to take now (add 'plan' for the whole plan, 'goal <name>' to pick a goal, 'off'/'on' for popups)", function(rest)
  rest = (rest or ""):lower()
  local want = rest:match("^goal%s*(.*)$")
  if want then
    local picked
    for _, g in ipairs(NS.GOALS or {}) do
      if want ~= "" and (g[1] == want or g[2]:lower() == want or g[2]:lower():find(want, 1, true) == 1) then picked = g[1] break end
    end
    if want == "custom" then picked = "custom" end
    local names = {}
    for _, g in ipairs(NS.GOALS or {}) do
      if NS.GoalAvailable(g[1]) then names[#names + 1] = g[1] end
    end
    if NS.CustomPlan() then names[#names + 1] = "custom" end
    if picked and NS.SetTalentGoal(picked) then
      NS.Print("talent goal: " .. NS.GoalLabel(picked) .. " - " .. ((NS.ActivePlan() or {}).name or "?"))
    elseif picked then
      NS.Print((UnitClass("player") or "Your class") .. " has no " .. NS.GoalLabel(picked) .. " plan. Pick one: " .. table.concat(names, ", ") .. ".")
    else
      NS.Print("talent goal is " .. NS.GoalLabel(NS.TalentGoal()) .. ". Pick one: " .. table.concat(names, ", ") .. ".")
    end
  elseif rest == "plan" then T.PrintPlan()
  elseif rest == "off" then NS.cdb.talents.popup = false; NS.Print("talent popups off (/sun talents on to undo).")
  elseif rest == "on" then NS.cdb.talents.popup = true; NS.Print("talent popups on.")
  else T.Show(true) end
end)
