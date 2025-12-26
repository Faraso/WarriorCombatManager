WCM = WCM or {}

-------------------------------------------------
-- Utils
-------------------------------------------------
local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[WCM]|r " .. tostring(msg))
  end
end

local function Clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function Abs(x)
  if x < 0 then return -x end
  return x
end

local function Now()
  return GetTime()
end

local function Lower(s)
  if not s then return "" end
  return string.lower(s)
end

local function F1(x)
  return string.format("%.1f", x or 0)
end

local function Round2(v)
  return math.floor(v * 100 + 0.5) / 100
end

local function InCombat()
  if type(InCombatLockdown) == "function" then
    return InCombatLockdown() and true or false
  end
  if type(UnitAffectingCombat) == "function" then
    return UnitAffectingCombat("player") and true or false
  end
  return false
end

Print("Core.lua loaded")

-------------------------------------------------
-- DB
-------------------------------------------------
local function InitDB()
  WarriorCombatManagerDB = WarriorCombatManagerDB or {}
  local db = WarriorCombatManagerDB
  db.settings = db.settings or {}
  db.history = db.history or {}

  if db.settings.left == nil then db.settings.left = nil end
  if db.settings.top == nil then db.settings.top = nil end

  if db.settings.locked == nil then db.settings.locked = true end
  if db.settings.scale == nil then db.settings.scale = 1.0 end

  if db.settings.x == nil then db.settings.x = 0 end
  if db.settings.y == nil then db.settings.y = 220 end

  if db.settings.highlightWindow == nil then db.settings.highlightWindow = 0.7 end
  if db.settings.incomingWindow == nil then db.settings.incomingWindow = 4.0 end

  if db.settings.dimAlpha == nil then db.settings.dimAlpha = 0.18 end
  if db.settings.baseAlpha == nil then db.settings.baseAlpha = 0.35 end

  if db.settings.bwEnabled == nil then db.settings.bwEnabled = true end
  if db.settings.defaultPredicted == nil then db.settings.defaultPredicted = 120 end
  if db.settings.avgN == nil then db.settings.avgN = 3 end
  if db.settings.maxHistory == nil then db.settings.maxHistory = 12 end

  if db.settings.trinketCD == nil then db.settings.trinketCD = 120 end
  if db.settings.loseUseBuffer == nil then db.settings.loseUseBuffer = 2.0 end

  if db.settings.executeThreshold == nil then db.settings.executeThreshold = 20 end

  if db.settings.livePredict == nil then db.settings.livePredict = true end
  if db.settings.livePredictPeriod == nil then db.settings.livePredictPeriod = 5.0 end
  if db.settings.livePredictAlpha == nil then db.settings.livePredictAlpha = 0.15 end

  if db.settings.livePredictWarmup == nil then db.settings.livePredictWarmup = 8.0 end
  if db.settings.livePredictMinDrop == nil then db.settings.livePredictMinDrop = 3.0 end

  if db.settings.strictFinalStack == nil then db.settings.strictFinalStack = true end

  if db.settings.showPrompt == nil then db.settings.showPrompt = true end
  if db.settings.promptOnlyPressNow == nil then db.settings.promptOnlyPressNow = true end

  if db.settings.executeBarRed == nil then db.settings.executeBarRed = true end

  if db.settings.executeZoom == nil then db.settings.executeZoom = true end
  if db.settings.executeZoomByPct == nil then db.settings.executeZoomByPct = true end
  if db.settings.executeZoomWindow == nil then db.settings.executeZoomWindow = 30 end

  if db.settings.testExecuteSim == nil then db.settings.testExecuteSim = true end
  if db.settings.testAutoStop == nil then db.settings.testAutoStop = true end

  if db.settings.autoHideOOC == nil then db.settings.autoHideOOC = true end

  if db.settings.lockToBoss == nil then db.settings.lockToBoss = true end

  -- NEW: default perfect align behavior
  if db.settings.preferAlign == nil then db.settings.preferAlign = true end
end

local function S()
  return WarriorCombatManagerDB.settings
end

local function H()
  return WarriorCombatManagerDB.history
end

-------------------------------------------------
-- State
-------------------------------------------------
WCM.state = WCM.state or {
  running = false,
  startTime = 0,
  predicted = 120,
  basePredicted = 120,
  elapsed = 0,
  boss = nil,
  source = "manual",
  execute = false,
  targetPct = nil,

  lastPct = nil,
  lastPredictAdjust = 0,

  firstPct = nil,

  bossGUID = nil,
  bossNameLock = nil,
}

-------------------------------------------------
-- History
-------------------------------------------------
local function EnsureBossHistory(boss)
  if not boss or boss == "" then return nil end
  local hist = H()[boss]
  if not hist then
    hist = { times = {}, last = nil }
    H()[boss] = hist
  end
  if not hist.times then hist.times = {} end
  return hist
end

local function PushBossTime(boss, seconds)
  seconds = tonumber(seconds)
  if not boss or boss == "" then return end
  if not seconds or seconds <= 0 then return end

  local hist = EnsureBossHistory(boss)
  if not hist then return end

  table.insert(hist.times, seconds)
  hist.last = seconds

  local maxH = S().maxHistory or 12
  while table.getn(hist.times) > maxH do
    table.remove(hist.times, 1)
  end
end

local function GetBossPredicted(boss)
  local n = S().avgN or 3
  local def = S().defaultPredicted or 120
  if not boss or boss == "" then return def end

  local hist = H()[boss]
  if not hist or not hist.times or table.getn(hist.times) == 0 then
    return def
  end

  local count = table.getn(hist.times)
  local take = n
  if take > count then take = count end

  local sum = 0
  local i = count - take + 1
  while i <= count do
    sum = sum + (hist.times[i] or 0)
    i = i + 1
  end

  if take <= 0 then return def end
  local avg = sum / take
  if avg < 10 then avg = 10 end
  return avg
end

function WCM:PrintBossHistory(boss)
  if not boss or boss == "" then
    Print("usage: /wcm hist <bossname>")
    return
  end

  local hist = H()[boss]
  if not hist or not hist.times or table.getn(hist.times) == 0 then
    Print("No history for " .. boss)
    return
  end

  local s = ""
  local i = 1
  while i <= table.getn(hist.times) do
    s = s .. string.format("%.1f", hist.times[i])
    if i < table.getn(hist.times) then s = s .. ", " end
    i = i + 1
  end

  Print("History " .. boss .. ": [" .. s .. "] last=" .. tostring(hist.last) ..
    " predicted=" .. string.format("%.1f", GetBossPredicted(boss)))
end

-------------------------------------------------
-- Boss Locking helpers
-------------------------------------------------
local function ResetBossLock()
  WCM.state.bossGUID = nil
  WCM.state.bossNameLock = nil
end

local function TryLockBossFromUnit(unit, bossName)
  if not unit then return false end
  if type(UnitExists) ~= "function" then return false end
  if not UnitExists(unit) then return false end

  if type(UnitName) == "function" then
    local n = UnitName(unit)
    if bossName and n and n == bossName then
      WCM.state.bossNameLock = bossName
      if type(UnitGUID) == "function" then
        WCM.state.bossGUID = UnitGUID(unit)
      end
      return true
    end
  end

  return false
end

local function LockBoss(bossName)
  ResetBossLock()
  WCM.state.bossNameLock = bossName

  if not S().lockToBoss then return end

  local locked = false
  locked = TryLockBossFromUnit("target", bossName) or locked
  locked = TryLockBossFromUnit("focus", bossName) or locked

  if locked and WCM.state.bossGUID then
    Print("Boss locked: " .. tostring(bossName) .. " guid=" .. tostring(WCM.state.bossGUID))
  else
    Print("Boss locked by name: " .. tostring(bossName))
  end
end

local function MatchLockedBoss(unit)
  if not S().lockToBoss then return true end
  if not unit then return false end
  if type(UnitExists) ~= "function" or not UnitExists(unit) then return false end

  local guidLock = WCM.state.bossGUID
  if guidLock and type(UnitGUID) == "function" then
    local g = UnitGUID(unit)
    if g and g == guidLock then return true end
    return false
  end

  local nameLock = WCM.state.bossNameLock
  if nameLock and type(UnitName) == "function" then
    local n = UnitName(unit)
    if n and n == nameLock then return true end
  end

  return false
end

local function GetLockedBossUnit()
  if not S().lockToBoss then
    if type(UnitExists) == "function" and UnitExists("target") then return "target" end
    return nil
  end

  if MatchLockedBoss("target") then return "target" end
  if MatchLockedBoss("focus") then return "focus" end

  return nil
end

local function GetLockedBossHealthPct()
  local unit = GetLockedBossUnit()
  if not unit then return nil end
  if type(UnitHealth) ~= "function" or type(UnitHealthMax) ~= "function" then return nil end
  local cur = UnitHealth(unit)
  local mx = UnitHealthMax(unit)
  if not mx or mx <= 0 then return nil end
  if not cur then return nil end
  return (cur / mx) * 100
end

local function IsLockedBossAttackable()
  local unit = GetLockedBossUnit()
  if not unit then return false end
  if type(UnitCanAttack) == "function" then
    return UnitCanAttack("player", unit) and true or false
  end
  return true
end

-------------------------------------------------
-- Start/Stop
-------------------------------------------------
function WCM:StartTest(predicted)
  predicted = tonumber(predicted) or (S().defaultPredicted or 120)
  predicted = Clamp(predicted, 10, 9999)

  self.state.running = true
  self.state.startTime = Now()
  self.state.predicted = predicted
  self.state.basePredicted = predicted
  self.state.elapsed = 0
  self.state.boss = "Test"
  self.state.source = "manual"
  self.state.execute = false
  self.state.targetPct = nil
  self.state.lastPct = nil
  self.state.lastPredictAdjust = 0
  self.state.firstPct = nil
  ResetBossLock()

  if WCM.UI then WCM.UI:Show(true) end
  Print("Test started. predicted=" .. tostring(predicted) .. "s")
end

function WCM:StopTest()
  self.state.running = false
  self.state.elapsed = 0
  self.state.boss = nil
  self.state.source = "manual"
  self.state.execute = false
  self.state.targetPct = nil
  self.state.lastPct = nil
  self.state.lastPredictAdjust = 0
  self.state.firstPct = nil
  ResetBossLock()
  Print("Test stopped")
end

function WCM:StartEncounter(boss, predicted, source)
  predicted = tonumber(predicted) or GetBossPredicted(boss)
  predicted = Clamp(predicted, 10, 9999)

  self.state.running = true
  self.state.startTime = Now()
  self.state.predicted = predicted
  self.state.basePredicted = predicted
  self.state.elapsed = 0
  self.state.boss = boss
  self.state.source = source or "bigwigs"
  self.state.execute = false
  self.state.targetPct = nil
  self.state.lastPct = nil
  self.state.lastPredictAdjust = 0
  self.state.firstPct = nil

  LockBoss(boss)

  if WCM.UI then WCM.UI:Show(true) end
  Print("Engaged: " .. tostring(boss) .. " predicted=" .. string.format("%.1f", predicted) .. " src=" .. tostring(self.state.source))
end

function WCM:StopEncounter(durationFromBW, bossName, source)
  if not self.state.running then return end

  local boss = bossName or self.state.boss
  local elapsed = Now() - (self.state.startTime or Now())

  local dur = tonumber(durationFromBW)
  if not dur or dur <= 0 then dur = elapsed end

  self.state.running = false
  self.state.elapsed = 0
  self.state.execute = false
  self.state.targetPct = nil
  self.state.lastPct = nil
  self.state.lastPredictAdjust = 0
  self.state.firstPct = nil
  ResetBossLock()

  if boss and boss ~= "" and boss ~= "Test" then
    PushBossTime(boss, dur)
    Print("Victory: " .. tostring(boss) .. " duration=" .. string.format("%.2f", dur) ..
      " predicted(now)=" .. string.format("%.1f", GetBossPredicted(boss)) .. " src=" .. tostring(source or self.state.source))
  else
    Print("Victory: Test duration=" .. string.format("%.2f", dur))
  end

  if S().autoHideOOC and (not InCombat()) then
    if WCM.UI then WCM.UI:Hide() end
  end
end

-------------------------------------------------
-- Ability names
-------------------------------------------------
local SPELLS = {
  DW = "Death Wish",
  RECK = "Recklessness",
  BR = "Bloodrage",
  BF = "Blood Fury",
}

-------------------------------------------------
-- Spellbook helpers
-------------------------------------------------
local SpellIndexCache = {}

local function ResetSpellCache()
  SpellIndexCache = {}
end

local function FindSpellIndexByName(spellName)
  if not spellName or spellName == "" then return nil end

  if SpellIndexCache[spellName] ~= nil then
    if SpellIndexCache[spellName] == false then return nil end
    return SpellIndexCache[spellName]
  end

  if type(GetNumSpellTabs) ~= "function" then
    SpellIndexCache[spellName] = false
    return nil
  end

  local numTabs = GetNumSpellTabs()
  local t = 1
  while t <= numTabs do
    local _, _, offset, numSpells = GetSpellTabInfo(t)
    local i = offset + 1
    local last = offset + numSpells
    while i <= last do
      local name = GetSpellName(i, BOOKTYPE_SPELL)
      if name == spellName then
        SpellIndexCache[spellName] = i
        return i
      end
      i = i + 1
    end
    t = t + 1
  end

  SpellIndexCache[spellName] = false
  return nil
end

local function HasSpell(spellName)
  return FindSpellIndexByName(spellName) ~= nil
end

local function IsSpellReady(spellName)
  local idx = FindSpellIndexByName(spellName)
  if not idx then return false end
  local start, dur, enabled = GetSpellCooldown(idx, BOOKTYPE_SPELL)
  if enabled == 0 then return false end
  if not start or not dur then return false end
  if dur == 0 or start == 0 then return true end
  return ((start + dur) - Now()) <= 0
end

-------------------------------------------------
-- Trinket helpers
-------------------------------------------------
local function GetInvTexture(slot)
  local tex = GetInventoryItemTexture("player", slot)
  if tex == "" then tex = nil end
  return tex
end

local function GetInvLink(slot)
  local link = GetInventoryItemLink("player", slot)
  if link == "" then link = nil end
  return link
end

local function IsTrinketReady(slot)
  local start, dur, enabled = GetInventoryItemCooldown("player", slot)
  if enabled == 0 then return false end
  if not start or not dur then return false end
  if dur == 0 or start == 0 then return true end
  return ((start + dur) - Now()) <= 0
end

local WCM_TT = nil
local function EnsureTooltip()
  if WCM_TT then return end
  WCM_TT = CreateFrame("GameTooltip", "WCM_ScanTooltip", UIParent, "GameTooltipTemplate")
  WCM_TT:SetOwner(UIParent, "ANCHOR_NONE")
end

local function TooltipHasUseTextFromInventory(slot)
  EnsureTooltip()
  WCM_TT:ClearLines()
  if type(WCM_TT.SetInventoryItem) ~= "function" then return false end
  WCM_TT:SetInventoryItem("player", slot)

  local i = 1
  while i <= 20 do
    local line = getglobal("WCM_ScanTooltipTextLeft" .. i)
    if line then
      local txt = line:GetText()
      if txt then
        local l = Lower(txt)
        if l and (string.find(l, "use") or string.find(l, "use:")) then
          return true
        end
      end
    end
    i = i + 1
  end
  return false
end

local function TrinketHasUse(slot)
  local link = GetInvLink(slot)
  if not link then return false end

  if type(GetItemSpell) == "function" then
    local spellName = GetItemSpell(link)
    if spellName and spellName ~= "" then
      return true
    end
  end

  return TooltipHasUseTextFromInventory(slot)
end

-------------------------------------------------
-- Icons
-------------------------------------------------
local ICONS = {
  DW = "Interface\\Icons\\Spell_Shadow_DeathPact",
  RECK = "Interface\\Icons\\Ability_CriticalStrike",
  BR = "Interface\\Icons\\Ability_Racial_BloodRage",
  BF = "Interface\\Icons\\Racial_Orc_BerserkerStrength",
  UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-------------------------------------------------
-- Cooldowns
-------------------------------------------------
local COOLDOWNS = {
  { id="DW", kind="spell", name=SPELLS.DW, icon=ICONS.DW, cd=180, dur=30, anchorRem=30, prio=1 },
  { id="T13", kind="trinket", slot=13, cdKey="trinketCD", dur=20, anchorRem=20, prio=2 },
  { id="T14", kind="trinket", slot=14, cdKey="trinketCD", dur=20, anchorRem=20, prio=2 },
  { id="BF", kind="spell", name=SPELLS.BF, icon=ICONS.BF, cd=120, dur=15, anchorRem=15, prio=3 },
  { id="RECK", kind="spell", name=SPELLS.RECK, icon=ICONS.RECK, cd=1800, dur=15, anchorRem=15, prio=4, oncePerFight=true },
  { id="BR", kind="spell", name=SPELLS.BR, icon=ICONS.BR, cd=60, dur=10, anchorRem=10, prio=5 },
}

local function IsTrinketEligible(slot)
  local link = GetInvLink(slot)
  if not link then return false end
  if not TrinketHasUse(slot) then return false end
  return true
end

local function CooldownAvailable(def)
  if def.kind == "spell" then
    return HasSpell(def.name)
  end
  if def.kind == "trinket" then
    return IsTrinketEligible(def.slot)
  end
  return false
end

local function CooldownReady(def)
  if def.kind == "spell" then
    return IsSpellReady(def.name)
  end
  if def.kind == "trinket" then
    return IsTrinketReady(def.slot)
  end
  return false
end

local function CooldownTexture(def)
  if def.kind == "spell" then
    return def.icon or ICONS.UNKNOWN
  end
  if def.kind == "trinket" then
    return GetInvTexture(def.slot) or ICONS.UNKNOWN
  end
  return ICONS.UNKNOWN
end

local function GetDefCooldownSeconds(def)
  local cd = def.cd
  if def.cdKey == "trinketCD" then
    cd = tonumber(S().trinketCD) or 120
  end
  return cd
end

local function BuildSchedule(predicted, cd, dur)
  local out = {}
  predicted = tonumber(predicted) or 0
  cd = tonumber(cd) or 0
  dur = tonumber(dur) or 0
  if predicted <= 0 or cd <= 0 then return out end

  local t = predicted - dur
  if t < 0 then t = 0 end

  while t >= 0 do
    table.insert(out, 1, t)
    t = t - cd
  end

  return out
end

local function LoseAUseNow(elapsed, predicted, cd)
  local buffer = S().loseUseBuffer or 2.0
  local remaining = predicted - elapsed
  if remaining < 0 then remaining = 0 end
  if remaining <= (cd + buffer) then
    return true
  end
  return false
end

-- NEW: find next marker after now, to enforce perfect align default
local function NextMarkerDelta(def, elapsed, predicted)
  local cd = GetDefCooldownSeconds(def)
  local sched = BuildSchedule(predicted, cd, def.dur)
  if table.getn(sched) == 0 then return nil end

  local best = nil
  local i = 1
  while i <= table.getn(sched) do
    local tMark = sched[i]
    if tMark >= elapsed then
      local dt = tMark - elapsed
      if (not best) or dt < best then
        best = dt
      end
    end
    i = i + 1
  end
  return best
end

-------------------------------------------------
-- Execute detection + live prediction adjustment
-------------------------------------------------
local function UpdateExecuteState()
  WCM.state.execute = false
  WCM.state.targetPct = nil

  if not WCM.state.running then return end

  local thr = tonumber(S().executeThreshold) or 20
  thr = Clamp(thr, 1, 99)

  if WCM.state.source == "manual" and S().testExecuteSim then
    local predicted = tonumber(WCM.state.predicted) or 0
    local elapsed = tonumber(WCM.state.elapsed) or 0
    if predicted > 0 then
      local execStart = predicted * (1 - (thr / 100))
      if elapsed >= execStart then
        WCM.state.execute = true
      end
    end
    return
  end

  if not IsLockedBossAttackable() then return end

  local pct = GetLockedBossHealthPct()
  if not pct then return end

  WCM.state.targetPct = pct
  if not WCM.state.firstPct then
    WCM.state.firstPct = pct
  end

  if pct <= thr then
    WCM.state.execute = true
  end
end

local function LivePredictTick()
  if not S().livePredict then return end
  if not WCM.state.running then return end
  if not IsLockedBossAttackable() then return end

  local pct = WCM.state.targetPct
  if not pct then return end
  if pct >= 99 then return end
  if pct <= 1 then return end

  local warmup = tonumber(S().livePredictWarmup) or 8.0
  warmup = Clamp(warmup, 0, 60)
  if (WCM.state.elapsed or 0) < warmup then return end

  local minDrop = tonumber(S().livePredictMinDrop) or 3.0
  minDrop = Clamp(minDrop, 0, 50)
  local first = WCM.state.firstPct
  if not first then return end
  if (first - pct) < minDrop then return end

  local t = Now()
  local period = tonumber(S().livePredictPeriod) or 5.0
  if (t - (WCM.state.lastPredictAdjust or 0)) < period then return end

  local lastPct = WCM.state.lastPct
  WCM.state.lastPct = pct
  if lastPct and pct > lastPct then return end

  local elapsed = WCM.state.elapsed or 0
  local fracDone = 1 - (pct / 100)
  if fracDone <= 0.01 then return end

  local estTotal = elapsed / fracDone
  if not estTotal or estTotal < 10 or estTotal > 9999 then return end

  local alpha = tonumber(S().livePredictAlpha) or 0.15
  alpha = Clamp(alpha, 0.02, 0.50)

  local cur = WCM.state.predicted or WCM.state.basePredicted or 120
  local newPred = (cur * (1 - alpha)) + (estTotal * alpha)
  newPred = Clamp(newPred, 10, 9999)

  WCM.state.predicted = newPred
  WCM.state.lastPredictAdjust = t
end

-------------------------------------------------
-- Action Prompt logic
-------------------------------------------------
local function GetVisibleRange(elapsed, predicted)
  local vStart = 0
  local vEnd = predicted

  if S().executeZoom and WCM.state.execute then
    if S().executeZoomByPct then
      local thr = tonumber(S().executeThreshold) or 20
      thr = Clamp(thr, 1, 99)
      local win = predicted * (thr / 100)
      if win < 5 then win = 5 end
      vEnd = predicted
      vStart = predicted - win
      if vStart < 0 then vStart = 0 end
    else
      local win2 = tonumber(S().executeZoomWindow) or 30
      win2 = Clamp(win2, 10, 120)
      vEnd = predicted
      vStart = predicted - win2
      if vStart < 0 then vStart = 0 end
    end
  end

  if vEnd <= vStart then
    vStart = 0
    vEnd = predicted
  end

  return vStart, vEnd
end

local function IsDefEligibleOutsideExecute(def)
  if def.oncePerFight and (not WCM.state.execute) then
    return false
  end
  return true
end

local function FindNearestMarkerDelta(def, elapsed, predicted)
  local cd = GetDefCooldownSeconds(def)
  local sched = BuildSchedule(predicted, cd, def.dur)
  if table.getn(sched) == 0 then return nil end

  local bestAbs = nil
  local bestDt = nil

  local i = 1
  while i <= table.getn(sched) do
    local tMark = sched[i]
    local dt = elapsed - tMark
    local a = Abs(dt)
    if (not bestAbs) or a < bestAbs then
      bestAbs = a
      bestDt = dt
    end
    i = i + 1
  end

  return bestDt
end

local function GetDefPromptState(def, elapsed, predicted)
  if (not CooldownAvailable(def)) then return nil end
  if (not IsDefEligibleOutsideExecute(def)) then return nil end

  local ready = CooldownReady(def)
  if not ready then return nil end

  local hw = tonumber(S().highlightWindow) or 0.7
  local soonW = tonumber(S().incomingWindow) or 4.0

  local dtNearest = FindNearestMarkerDelta(def, elapsed, predicted)
  if not dtNearest then
    return "HOLD", nil
  end
  local absNearest = Abs(dtNearest)

  local cd = GetDefCooldownSeconds(def)
  local loseNow = LoseAUseNow(elapsed, predicted, cd)

  -- PERFECT ALIGN DEFAULT:
  -- lose-a-use only triggers if there is no upcoming marker (already past last marker).
  local nextDt = NextMarkerDelta(def, elapsed, predicted)
  local hasUpcoming = (nextDt ~= nil)
  local canLoseOverride = (not S().preferAlign) or (not hasUpcoming)

  if loseNow and canLoseOverride then
    return "PRESS NOW", dtNearest
  end

  if absNearest <= hw then
    return "PRESS NOW", dtNearest
  end

  if absNearest <= soonW then
    return "SOON", dtNearest
  end

  return "HOLD", dtNearest
end

local function MakeFinalPrimary(elapsed, predicted)
  if not S().strictFinalStack then return nil end
  local remaining = predicted - elapsed
  if remaining < 0 then remaining = 0 end
  if remaining > 30 then return nil end

  local bestId = nil
  local bestScore = nil

  local i = 1
  while i <= table.getn(COOLDOWNS) do
    local def = COOLDOWNS[i]
    if def.anchorRem and CooldownAvailable(def) and CooldownReady(def) and IsDefEligibleOutsideExecute(def) then
      local diff = Abs(remaining - def.anchorRem)
      local score = diff + (def.prio or 50) * 0.01
      if not bestScore or score < bestScore then
        bestScore = score
        bestId = def.id
      end
    end
    i = i + 1
  end

  return bestId
end

local function PickBestPrompt(elapsed, predicted, forcePrimaryId)
  local bestDef = nil
  local bestState = nil
  local bestScore = nil

  local primaryDef = nil
  if forcePrimaryId then
    local pi = 1
    while pi <= table.getn(COOLDOWNS) do
      if COOLDOWNS[pi].id == forcePrimaryId then
        primaryDef = COOLDOWNS[pi]
        break
      end
      pi = pi + 1
    end
  end

  local function Consider(def)
    local state, dt = GetDefPromptState(def, elapsed, predicted)
    if not state then return end

    local prio = def.prio or 50
    local score = 9999

    if state == "PRESS NOW" then
      score = 0 + prio * 0.01
    elseif state == "SOON" then
      score = 10 + prio * 0.01 + (Abs(dt or 0) * 0.05)
    else
      score = 50 + prio * 0.01 + (Abs(dt or 0) * 0.02)
    end

    if (not bestScore) or score < bestScore then
      bestScore = score
      bestDef = def
      bestState = state
    end
  end

  if primaryDef and CooldownAvailable(primaryDef) then
    Consider(primaryDef)
  end

  local i = 1
  while i <= table.getn(COOLDOWNS) do
    local def = COOLDOWNS[i]
    Consider(def)
    i = i + 1
  end

  return bestDef, bestState
end

-------------------------------------------------
-- UI
-------------------------------------------------
WCM.UI = WCM.UI or {}

local function ApplyIconState(tex, mode, isPrimary)
  local baseA = S().baseAlpha or 0.35
  local dimA = S().dimAlpha or 0.18

  if mode == "now" then
    tex:SetAlpha(isPrimary and 1.0 or 0.60)
    tex:SetWidth(isPrimary and 30 or 26)
    tex:SetHeight(isPrimary and 30 or 26)
  elseif mode == "soon" then
    tex:SetAlpha(0.70)
    tex:SetWidth(24)
    tex:SetHeight(24)
  elseif mode == "ready" then
    tex:SetAlpha(baseA)
    tex:SetWidth(22)
    tex:SetHeight(22)
  else
    tex:SetAlpha(dimA)
    tex:SetWidth(22)
    tex:SetHeight(22)
  end
end

local function MakeLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function MakeEditBox(parent, width, height, x, y)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetAutoFocus(false)
  eb:SetMultiLine(false)
  eb:SetWidth(width)
  eb:SetHeight(height)
  eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  eb:SetFontObject("ChatFontNormal")
  eb:SetTextInsets(6, 6, 2, 2)

  if eb.SetBackdrop then
    eb:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    eb:SetBackdropColor(0, 0, 0, 0.75)
  end

  return eb
end

local function AddSpecialFrame(name)
  if not UISpecialFrames then return end
  local i = 1
  while UISpecialFrames[i] do
    if UISpecialFrames[i] == name then return end
    i = i + 1
  end
  table.insert(UISpecialFrames, name)
end

local function AcquireIcon(ui)
  ui.iconPoolUsed = ui.iconPoolUsed + 1
  local idx = ui.iconPoolUsed
  if not ui.iconPool[idx] then
    local t = ui.frame:CreateTexture(nil, "OVERLAY")
    t:SetWidth(22)
    t:SetHeight(22)
    t:SetTexture(ICONS.UNKNOWN)
    t:SetAlpha(0.2)
    t:Hide()
    ui.iconPool[idx] = t
  end
  local tex = ui.iconPool[idx]
  tex:Show()
  return tex
end

local function ReleaseIcons(ui)
  local i = 1
  while i <= ui.iconPoolUsed do
    ui.iconPool[i]:Hide()
    i = i + 1
  end
  ui.iconPoolUsed = 0
end

local function TimeToBarX(ui, t, vStart, vEnd)
  local barLeft = 46
  local barRight = ui.frame:GetWidth() - 2
  local barW = barRight - barLeft
  if barW < 1 then barW = 1 end

  local frac = 0
  local span = vEnd - vStart
  if span > 0 then
    frac = (t - vStart) / span
  end
  frac = Clamp(frac, 0, 1)
  return barLeft + (barW * frac)
end

function WCM.UI:Create()
  if self.frame then return end

  local f = CreateFrame("Frame", "WCM_Timeline", UIParent)
  f:SetWidth(520)
  f:SetHeight(58)
  f:SetScale(S().scale or 1.0)
  f:Hide()
  f:SetFrameStrata("MEDIUM")

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetTexture(0, 0, 0, 0.35)

  local barBG = f:CreateTexture(nil, "BORDER")
  barBG:SetPoint("LEFT", f, "LEFT", 44, -8)
  barBG:SetPoint("RIGHT", f, "RIGHT", -2, -8)
  barBG:SetHeight(34)
  barBG:SetTexture(0.15, 0.15, 0.15, 0.75)

  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("LEFT", f, "LEFT", 44, -8)
  fill:SetHeight(34)
  fill:SetTexture(0.35, 0.35, 0.35, 0.75)
  fill:SetWidth(0)

  local now = f:CreateTexture(nil, "OVERLAY")
  now:SetWidth(2)
  now:SetHeight(34)
  now:SetTexture(1, 1, 1, 0.90)
  now:Hide()

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -4)
  title:SetText("WCM")

  local info = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -4)
  info:SetText("")

  local mode = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  mode:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 4)
  mode:SetText("")

  local ap = CreateFrame("Frame", "WCM_ActionPrompt", f)
  ap:SetWidth(40)
  ap:SetHeight(40)
  ap:SetPoint("LEFT", f, "LEFT", 2, -8)
  ap:SetFrameStrata("HIGH")
  ap:SetFrameLevel(200)

  local apTex = ap:CreateTexture(nil, "OVERLAY")
  apTex:SetAllPoints(ap)
  apTex:SetTexture(ICONS.UNKNOWN)
  apTex:SetAlpha(0.95)

  local apText = ap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  apText:SetPoint("TOPLEFT", ap, "TOPRIGHT", 6, -2)
  apText:SetText("")
  apText:SetJustifyH("LEFT")

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")

  f:SetScript("OnDragStart", function()
    if not S().locked then f:StartMoving() end
  end)

  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local left = f:GetLeft()
    local top = f:GetTop()
    if left and top then
      S().left = left
      S().top = top
      if WCM.Options and WCM.Options.SyncFromDB then WCM.Options:SyncFromDB() end
    end
  end)

  self.frame = f
  self.bg = bg
  self.barBG = barBG
  self.fill = fill
  self.now = now
  self.title = title
  self.info = info
  self.mode = mode

  self.promptFrame = ap
  self.promptTex = apTex
  self.promptText = apText

  self.iconPool = {}
  self.iconPoolUsed = 0

  self:ApplyLock()
end

function WCM.UI:ApplyLock()
  if not self.frame then return end
  if S().locked then self.frame:EnableMouse(false) else self.frame:EnableMouse(true) end
end

function WCM.UI:ClampToScreen(left, top)
  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()

  local scale = self.frame:GetScale() or 1
  local fw = self.frame:GetWidth() * scale
  local fh = self.frame:GetHeight() * scale

  local minLeft = 0
  local maxLeft = sw - fw
  local minTop = fh
  local maxTop = sh

  left = Clamp(left, minLeft, maxLeft)
  top = Clamp(top, minTop, maxTop)
  return left, top
end

function WCM.UI:ApplyPosition()
  if not self.frame then return end
  self.frame:SetScale(S().scale or 1.0)
  self.frame:ClearAllPoints()

  local left = S().left
  local top = S().top

  if left and top then
    left, top = self:ClampToScreen(left, top)
    S().left = left
    S().top = top
    self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  else
    self.frame:SetPoint("CENTER", UIParent, "CENTER", S().x or 0, S().y or 220)
  end
end

function WCM.UI:SetScale(scale)
  if not self.frame then self:Create() end
  scale = tonumber(scale)
  if not scale then return end
  scale = Clamp(scale, 0.60, 1.80)
  S().scale = scale
  self.frame:SetScale(scale)

  if S().left and S().top then
    local left, top = self:ClampToScreen(S().left, S().top)
    S().left = left
    S().top = top
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  end
end

function WCM.UI:SetPosition(left, top)
  if not self.frame then self:Create() end
  left = tonumber(left)
  top = tonumber(top)
  if not left or not top then return end
  left, top = self:ClampToScreen(left, top)
  S().left = left
  S().top = top
  self.frame:ClearAllPoints()
  self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function WCM.UI:Show(force)
  if not self.frame then self:Create() end
  self:ApplyPosition()
  self:ApplyLock()

  if (not force) and S().autoHideOOC and (not InCombat()) and (not WCM.state.running) then
    self.frame:Hide()
    return
  end

  self.frame:Show()
end

function WCM.UI:Hide()
  if not self.frame then return end
  self.frame:Hide()
end

function WCM.UI:UpdateTimeline(elapsed, predicted)
  if not self.frame or not self.frame:IsShown() then return end

  local bossName = WCM.state.boss or "Test"
  self.title:SetText("WCM " .. bossName)

  local src = WCM.state.source or "manual"
  local pct = WCM.state.targetPct
  local pctTxt = ""
  if pct then pctTxt = " " .. string.format("%.0f", pct) .. "%" end
  self.info:SetText(F1(elapsed) .. "/" .. F1(predicted) .. "s " .. src .. pctTxt)

  if WCM.state.execute then
    self.mode:SetText("EXECUTE")
  else
    self.mode:SetText("")
  end

  if S().executeBarRed and WCM.state.execute then
    self.fill:SetTexture(0.75, 0.15, 0.15, 0.75)
    self.barBG:SetTexture(0.20, 0.08, 0.08, 0.80)
  else
    self.fill:SetTexture(0.35, 0.35, 0.35, 0.75)
    self.barBG:SetTexture(0.15, 0.15, 0.15, 0.75)
  end

  local vStart, vEnd = GetVisibleRange(elapsed, predicted)
  local span = vEnd - vStart
  if span < 0.01 then span = 0.01 end

  local barLeft = 46
  local barRight = self.frame:GetWidth() - 2
  local barW = barRight - barLeft
  if barW < 1 then barW = 1 end

  local frac = (elapsed - vStart) / span
  frac = Clamp(frac, 0, 1)
  self.fill:SetWidth(barW * frac)

  local nowX = barLeft + (barW * frac)
  self.now:ClearAllPoints()
  self.now:SetPoint("LEFT", self.frame, "LEFT", nowX, -8)
  self.now:Show()

  ReleaseIcons(self)

  local hw = tonumber(S().highlightWindow) or 0.7
  local soonW = tonumber(S().incomingWindow) or 4.0

  local primaryId = MakeFinalPrimary(elapsed, predicted)
  local promptDef, promptState = nil, nil
  if S().showPrompt then
    promptDef, promptState = PickBestPrompt(elapsed, predicted, primaryId)
  end

  if S().showPrompt and promptDef and promptState then
    if S().promptOnlyPressNow and promptState ~= "PRESS NOW" then
      self.promptFrame:Hide()
      self.promptText:SetText("")
    else
      self.promptFrame:Show()
      self.promptFrame:SetFrameStrata("HIGH")
      self.promptFrame:SetFrameLevel(200)
      self.promptTex:SetTexture(CooldownTexture(promptDef))
      self.promptTex:SetAlpha(0.98)
      self.promptText:SetText(promptState)
      self.promptText:Show()
    end
  else
    self.promptFrame:Hide()
    if self.promptText then self.promptText:SetText("") end
  end

  local di = 1
  while di <= table.getn(COOLDOWNS) do
    local def = COOLDOWNS[di]

    if CooldownAvailable(def) then
      local cd = GetDefCooldownSeconds(def)
      local sched = BuildSchedule(predicted, cd, def.dur)
      local ready = CooldownReady(def)

      local si = 1
      while si <= table.getn(sched) do
        local tMark = sched[si]
        if tMark >= vStart and tMark <= vEnd then
          local x = TimeToBarX(self, tMark, vStart, vEnd)

          local tex = AcquireIcon(self)
          tex:SetTexture(CooldownTexture(def))
          tex:ClearAllPoints()
          tex:SetPoint("CENTER", self.frame, "LEFT", x, -8)

          local dt = elapsed - tMark
          local absdt = Abs(dt)

          local mode2 = "dim"
          if ready then mode2 = "ready" end
          if absdt <= hw and ready then
            mode2 = "now"
          elseif absdt <= soonW and ready then
            mode2 = "soon"
          end

          local isPrimary = false
          if promptDef and promptState == "PRESS NOW" and def.id == promptDef.id and mode2 == "now" then
            isPrimary = true
          end

          ApplyIconState(tex, mode2, isPrimary)
        end
        si = si + 1
      end
    end

    di = di + 1
  end
end

-------------------------------------------------
-- Options UI
-------------------------------------------------
WCM.Options = WCM.Options or {}

function WCM.Options:UpdatePosSliderRanges()
  if not self.frame or not WCM.UI or not WCM.UI.frame then return end
  if not self.xSlider or not self.ySlider then return end

  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()

  local scale = WCM.UI.frame:GetScale() or 1
  local fw = WCM.UI.frame:GetWidth() * scale
  local fh = WCM.UI.frame:GetHeight() * scale

  local minLeft = 0
  local maxLeft = sw - fw
  local minTop = fh
  local maxTop = sh

  if maxLeft < minLeft then maxLeft = minLeft end
  if maxTop < minTop then maxTop = minTop end

  self.xSlider:SetMinMaxValues(minLeft, maxLeft)
  self.ySlider:SetMinMaxValues(minTop, maxTop)
end

function WCM.Options:SyncFromDB()
  if self._syncing then return end
  self._syncing = true

  if WCM.UI and WCM.UI.frame and (not (S().left and S().top)) then
    local left = WCM.UI.frame:GetLeft()
    local top = WCM.UI.frame:GetTop()
    if left and top then
      S().left = left
      S().top = top
    end
  end

  if self.xBox and self.xBox.SetText then self.xBox:SetText(tostring(math.floor((S().left or 0) + 0.5))) end
  if self.yBox and self.yBox.SetText then self.yBox:SetText(tostring(math.floor((S().top or 0) + 0.5))) end

  if self.xSlider and self.xSlider.SetValue then self.xSlider:SetValue(S().left or 0) end
  if self.ySlider and self.ySlider.SetValue then self.ySlider:SetValue(S().top or 0) end

  if self.trinketBox and self.trinketBox.SetText then self.trinketBox:SetText(tostring(S().trinketCD or 120)) end
  if self.execBox and self.execBox.SetText then self.execBox:SetText(tostring(S().executeThreshold or 20)) end
  if self.zoomBox and self.zoomBox.SetText then self.zoomBox:SetText(tostring(S().executeZoomWindow or 30)) end

  if self.autoHideCB and self.autoHideCB.SetChecked then self.autoHideCB:SetChecked(S().autoHideOOC and true or false) end
  if self.lockBossCB and self.lockBossCB.SetChecked then self.lockBossCB:SetChecked(S().lockToBoss and true or false) end

  if self.showPromptCB and self.showPromptCB.SetChecked then self.showPromptCB:SetChecked(S().showPrompt and true or false) end
  if self.promptOnlyNowCB and self.promptOnlyNowCB.SetChecked then self.promptOnlyNowCB:SetChecked(S().promptOnlyPressNow and true or false) end

  self._syncing = false
end

function WCM.Options:Create()
  if self.frame then return end

  local f = CreateFrame("Frame", "WCM_Options", UIParent)
  f:SetWidth(520)
  f:SetHeight(520)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.90)
  end

  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(999)

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)

  f:SetScript("OnDragStart", function()
    f:StartMoving()
  end)

  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
  end)

  AddSpecialFrame("WCM_Options")
  f:Hide()

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
  title:SetText("WCM Options")

  local close = CreateFrame("Button", "WCM_Options_Close", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() f:Hide() end)

  local lock = CreateFrame("CheckButton", "WCM_Options_Lock", f, "UICheckButtonTemplate")
  lock:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
  getglobal(lock:GetName() .. "Text"):SetText("Locked")
  lock:SetChecked(S().locked and true or false)
  lock:SetScript("OnClick", function()
    S().locked = lock:GetChecked() and true or false
    if WCM.UI and WCM.UI.ApplyLock then WCM.UI:ApplyLock() end
  end)

  MakeLabel(f, "Scale", 10, -62)
  local scale = CreateFrame("Slider", "WCM_Options_Scale", f, "OptionsSliderTemplate")
  scale:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -80)
  scale:SetWidth(300)
  scale:SetMinMaxValues(0.60, 1.80)
  scale:SetValueStep(0.05)
  if scale.SetObeyStepOnDrag then scale:SetObeyStepOnDrag(true) end
  scale:SetValue(S().scale)
  getglobal(scale:GetName() .. "Low"):SetText("0.60")
  getglobal(scale:GetName() .. "High"):SetText("1.80")
  getglobal(scale:GetName() .. "Text"):SetText(string.format("%.2f", S().scale))
  scale:SetScript("OnValueChanged", function()
    local v = Round2(scale:GetValue())
    S().scale = v
    getglobal(scale:GetName() .. "Text"):SetText(string.format("%.2f", v))
    if WCM.UI and WCM.UI.SetScale then WCM.UI:SetScale(v) end
    WCM.Options:UpdatePosSliderRanges()
    WCM.Options:SyncFromDB()
  end)

  MakeLabel(f, "Position X (left)", 10, -120)
  local xs = CreateFrame("Slider", "WCM_Options_PosX", f, "OptionsSliderTemplate")
  xs:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -140)
  xs:SetWidth(350)
  xs:SetValueStep(1)
  if xs.SetObeyStepOnDrag then xs:SetObeyStepOnDrag(true) end
  getglobal(xs:GetName() .. "Low"):SetText("")
  getglobal(xs:GetName() .. "High"):SetText("")
  getglobal(xs:GetName() .. "Text"):SetText("")

  local xBox = MakeEditBox(f, 90, 18, 380, -142)
  xBox:SetText(tostring(math.floor((S().left or 0) + 0.5)))

  MakeLabel(f, "Position Y (top)", 10, -172)
  local ys = CreateFrame("Slider", "WCM_Options_PosY", f, "OptionsSliderTemplate")
  ys:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -192)
  ys:SetWidth(350)
  ys:SetValueStep(1)
  if ys.SetObeyStepOnDrag then ys:SetObeyStepOnDrag(true) end
  getglobal(ys:GetName() .. "Low"):SetText("")
  getglobal(ys:GetName() .. "High"):SetText("")
  getglobal(ys:GetName() .. "Text"):SetText("")

  local yBox = MakeEditBox(f, 90, 18, 380, -194)
  yBox:SetText(tostring(math.floor((S().top or 0) + 0.5)))

  xs:SetScript("OnValueChanged", function()
    if WCM.Options._syncing then return end
    local v = math.floor(xs:GetValue() + 0.5)
    S().left = v
    if xBox and xBox.SetText then xBox:SetText(tostring(v)) end
    if WCM.UI and WCM.UI.SetPosition and S().top then WCM.UI:SetPosition(S().left, S().top) end
  end)

  ys:SetScript("OnValueChanged", function()
    if WCM.Options._syncing then return end
    local v = math.floor(ys:GetValue() + 0.5)
    S().top = v
    if yBox and yBox.SetText then yBox:SetText(tostring(v)) end
    if WCM.UI and WCM.UI.SetPosition and S().left then WCM.UI:SetPosition(S().left, S().top) end
  end)

  xBox:SetScript("OnEnterPressed", function()
    local v = tonumber(xBox:GetText())
    if v and S().top then
      WCM.UI:SetPosition(v, S().top)
      WCM.Options:SyncFromDB()
      Print("Position set")
    end
    xBox:ClearFocus()
  end)

  yBox:SetScript("OnEnterPressed", function()
    local v = tonumber(yBox:GetText())
    if v and S().left then
      WCM.UI:SetPosition(S().left, v)
      WCM.Options:SyncFromDB()
      Print("Position set")
    end
    yBox:ClearFocus()
  end)

  local ah = CreateFrame("CheckButton", "WCM_Options_AutoHide", f, "UICheckButtonTemplate")
  ah:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -224)
  getglobal(ah:GetName() .. "Text"):SetText("Auto-hide out of combat")
  ah:SetChecked(S().autoHideOOC and true or false)
  ah:SetScript("OnClick", function()
    S().autoHideOOC = ah:GetChecked() and true or false
    Print("Auto-hide out of combat " .. (S().autoHideOOC and "enabled" or "disabled"))
    if WCM.UI then
      if S().autoHideOOC and (not InCombat()) and (not WCM.state.running) then
        WCM.UI:Hide()
      else
        WCM.UI:Show(true)
      end
    end
  end)

  local lb = CreateFrame("CheckButton", "WCM_Options_LockBoss", f, "UICheckButtonTemplate")
  lb:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -248)
  getglobal(lb:GetName() .. "Text"):SetText("Lock prediction to boss (ignore adds)")
  lb:SetChecked(S().lockToBoss and true or false)
  lb:SetScript("OnClick", function()
    S().lockToBoss = lb:GetChecked() and true or false
    Print("Lock to boss " .. (S().lockToBoss and "enabled" or "disabled"))
  end)

  MakeLabel(f, "Trinket CD (sec)", 10, -279)
  local tcdBox = MakeEditBox(f, 70, 18, 130, -283)
  tcdBox:SetText(tostring(S().trinketCD or 120))
  tcdBox:SetScript("OnEnterPressed", function()
    local v = tonumber(tcdBox:GetText())
    if v then
      v = Clamp(v, 30, 600)
      S().trinketCD = v
      tcdBox:SetText(tostring(v))
      Print("Trinket CD set to " .. tostring(v))
    end
    tcdBox:ClearFocus()
  end)

  MakeLabel(f, "Execute threshold (%)", 240, -279)
  local exBox = MakeEditBox(f, 60, 18, 375, -283)
  exBox:SetText(tostring(S().executeThreshold or 20))
  exBox:SetScript("OnEnterPressed", function()
    local v = tonumber(exBox:GetText())
    if v then
      v = Clamp(v, 1, 99)
      S().executeThreshold = v
      exBox:SetText(tostring(v))
      Print("Execute threshold set to " .. tostring(v) .. "%")
    end
    exBox:ClearFocus()
  end)

  local bw = CreateFrame("CheckButton", "WCM_Options_BW", f, "UICheckButtonTemplate")
  bw:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -310)
  getglobal(bw:GetName() .. "Text"):SetText("Enable BigWigs integration")
  bw:SetChecked(S().bwEnabled and true or false)
  bw:SetScript("OnClick", function()
    S().bwEnabled = bw:GetChecked() and true or false
    Print("BigWigs integration " .. (S().bwEnabled and "enabled" or "disabled"))
  end)

  local lp = CreateFrame("CheckButton", "WCM_Options_LivePredict", f, "UICheckButtonTemplate")
  lp:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -336)
  getglobal(lp:GetName() .. "Text"):SetText("Live prediction adjustment")
  lp:SetChecked(S().livePredict and true or false)
  lp:SetScript("OnClick", function()
    S().livePredict = lp:GetChecked() and true or false
    Print("Live prediction " .. (S().livePredict and "enabled" or "disabled"))
  end)

  local xr = CreateFrame("CheckButton", "WCM_Options_ExecRed", f, "UICheckButtonTemplate")
  xr:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -362)
  getglobal(xr:GetName() .. "Text"):SetText("Execute makes bar red")
  xr:SetChecked(S().executeBarRed and true or false)
  xr:SetScript("OnClick", function()
    S().executeBarRed = xr:GetChecked() and true or false
    Print("Execute bar red " .. (S().executeBarRed and "enabled" or "disabled"))
  end)

  local ez = CreateFrame("CheckButton", "WCM_Options_ExecZoom", f, "UICheckButtonTemplate")
  ez:SetPoint("TOPLEFT", f, "TOPLEFT", 240, -310)
  getglobal(ez:GetName() .. "Text"):SetText("Execute zoom enabled")
  ez:SetChecked(S().executeZoom and true or false)
  ez:SetScript("OnClick", function()
    S().executeZoom = ez:GetChecked() and true or false
    Print("Execute zoom " .. (S().executeZoom and "enabled" or "disabled"))
  end)

  local ezp = CreateFrame("CheckButton", "WCM_Options_ExecZoomPct", f, "UICheckButtonTemplate")
  ezp:SetPoint("TOPLEFT", f, "TOPLEFT", 240, -336)
  getglobal(ezp:GetName() .. "Text"):SetText("Zoom by execute percent")
  ezp:SetChecked(S().executeZoomByPct and true or false)
  ezp:SetScript("OnClick", function()
    S().executeZoomByPct = ezp:GetChecked() and true or false
    Print("Execute zoom mode = " .. (S().executeZoomByPct and "percent" or "seconds"))
  end)

  MakeLabel(f, "Zoom seconds (if percent off)", 240, -362)
  local zBox = MakeEditBox(f, 60, 18, 420, -366)
  zBox:SetText(tostring(S().executeZoomWindow or 30))
  zBox:SetScript("OnEnterPressed", function()
    local v = tonumber(zBox:GetText())
    if v then
      v = Clamp(v, 10, 120)
      S().executeZoomWindow = v
      zBox:SetText(tostring(v))
      Print("Execute zoom seconds set to " .. tostring(v))
    end
    zBox:ClearFocus()
  end)

  local te = CreateFrame("CheckButton", "WCM_Options_TestExec", f, "UICheckButtonTemplate")
  te:SetPoint("TOPLEFT", f, "TOPLEFT", 240, -388)
  getglobal(te:GetName() .. "Text"):SetText("Simulate execute in manual test")
  te:SetChecked(S().testExecuteSim and true or false)
  te:SetScript("OnClick", function()
    S().testExecuteSim = te:GetChecked() and true or false
    Print("Test execute simulation " .. (S().testExecuteSim and "enabled" or "disabled"))
  end)

  local tas = CreateFrame("CheckButton", "WCM_Options_TestAS", f, "UICheckButtonTemplate")
  tas:SetPoint("TOPLEFT", f, "TOPLEFT", 240, -414)
  getglobal(tas:GetName() .. "Text"):SetText("Auto stop test at predicted")
  tas:SetChecked(S().testAutoStop and true or false)
  tas:SetScript("OnClick", function()
    S().testAutoStop = tas:GetChecked() and true or false
    Print("Test auto stop " .. (S().testAutoStop and "enabled" or "disabled"))
  end)

  local sp = CreateFrame("CheckButton", "WCM_Options_ShowPrompt", f, "UICheckButtonTemplate")
  sp:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -448)
  getglobal(sp:GetName() .. "Text"):SetText("Action Prompt enabled (left icon)")
  sp:SetChecked(S().showPrompt and true or false)
  sp:SetScript("OnClick", function()
    S().showPrompt = sp:GetChecked() and true or false
    Print("Action prompt " .. (S().showPrompt and "enabled" or "disabled"))
  end)

  local pnow = CreateFrame("CheckButton", "WCM_Options_PromptOnlyNow", f, "UICheckButtonTemplate")
  pnow:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -474)
  getglobal(pnow:GetName() .. "Text"):SetText("Prompt only when PRESS NOW")
  pnow:SetChecked(S().promptOnlyPressNow and true or false)
  pnow:SetScript("OnClick", function()
    S().promptOnlyPressNow = pnow:GetChecked() and true or false
    Print("Prompt mode = " .. (S().promptOnlyPressNow and "press-now only" or "always show states"))
  end)

  self.frame = f
  self.xSlider = xs
  self.ySlider = ys
  self.xBox = xBox
  self.yBox = yBox
  self.trinketBox = tcdBox
  self.execBox = exBox
  self.zoomBox = zBox
  self.autoHideCB = ah
  self.lockBossCB = lb
  self.showPromptCB = sp
  self.promptOnlyNowCB = pnow

  f:SetScript("OnShow", function()
    WCM.Options:UpdatePosSliderRanges()
    WCM.Options:SyncFromDB()
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(999)
  end)
end

function WCM.Options:Toggle()
  if not self.frame then self:Create() end
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
  end
end

-------------------------------------------------
-- BigWigs integration via BossRecords
-------------------------------------------------
WCM.BW = WCM.BW or { hooked = false, method = "none" }

local function BW_Engage(bossName)
  if not bossName or bossName == "" then return end
  if not S().bwEnabled then return end
  if (not WCM.state.running) or (WCM.state.boss ~= bossName) then
    WCM:StartEncounter(bossName, GetBossPredicted(bossName), "bossrecords")
  end
end

local function BW_Victory(bossName, duration)
  if not bossName or bossName == "" then return end
  if not S().bwEnabled then return end
  if WCM.state.running and WCM.state.boss == bossName then
    WCM:StopEncounter(duration, bossName, "bossrecords")
  else
    PushBossTime(bossName, duration)
    Print("History updated (bossrecords): " .. bossName .. " duration=" .. string.format("%.2f", duration))
  end
end

local function TryHookBossRecords()
  if WCM.BW.hooked then return true end
  if type(BigWigsBossRecords) ~= "table" then return false end
  if type(BigWigsBossRecords.StartBossfight) ~= "function" then return false end
  if type(BigWigsBossRecords.EndBossfight) ~= "function" then return false end

  if BigWigsBossRecords.__WCM_HOOKED then
    WCM.BW.hooked = true
    WCM.BW.method = "bossrecords"
    return true
  end

  local origStart = BigWigsBossRecords.StartBossfight
  local origEnd = BigWigsBossRecords.EndBossfight

  BigWigsBossRecords.StartBossfight = function(self, module, ...)
    local ok = origStart(self, module, unpack(arg or {}))
    if module and module.bossSync and (not module.trashMod) then
      local bossName = nil
      if type(module.ToString) == "function" then bossName = module:ToString() end
      if not bossName or bossName == "" then bossName = module.name end
      BW_Engage(bossName)
    end
    return ok
  end

  BigWigsBossRecords.EndBossfight = function(self, module, ...)
    local bossName = nil
    if module and type(module.ToString) == "function" then bossName = module:ToString() end
    if not bossName or bossName == "" then bossName = module and module.name or nil end

    local duration = nil
    if WCM.state.running and bossName and WCM.state.boss == bossName then
      duration = Now() - (WCM.state.startTime or Now())
    end

    local ok = origEnd(self, module, unpack(arg or {}))

    if bossName and duration and duration > 0 then
      BW_Victory(bossName, duration)
    end

    return ok
  end

  BigWigsBossRecords.__WCM_HOOKED = true
  WCM.BW.hooked = true
  WCM.BW.method = "bossrecords"
  Print("BigWigs adapter hooked (BossRecords)")
  return true
end

-------------------------------------------------
-- Init + driver
-------------------------------------------------
WCM._inited = WCM._inited or false
WCM._hookTryStart = WCM._hookTryStart or 0
WCM._hookTryActive = WCM._hookTryActive or false

local function DoInit(reason)
  if WCM._inited then return end
  WCM._inited = true

  InitDB()
  WCM.UI:Create()
  WCM.Options:Create()

  Print("Init done via " .. tostring(reason))
  Print("Loaded BigWigs integration")

  WCM._hookTryStart = Now()
  WCM._hookTryActive = true

  if S().autoHideOOC and (not InCombat()) and (not WCM.state.running) then
    if WCM.UI then WCM.UI:Hide() end
  end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

driver:SetScript("OnEvent", function()
  if event == "PLAYER_LOGIN" then
    DoInit("PLAYER_LOGIN")
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    DoInit("PLAYER_ENTERING_WORLD")
    return
  end
  if event == "SPELLS_CHANGED" then
    ResetSpellCache()
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    if S().autoHideOOC and WCM.UI and (not WCM.state.running) then
      WCM.UI:Show(false)
    end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    if S().autoHideOOC and WCM.UI and (not WCM.state.running) then
      WCM.UI:Hide()
    end
    return
  end
end)

driver:SetScript("OnUpdate", function()
  if WCM._hookTryActive and (not WCM.BW.hooked) then
    local t = Now()
    if (t - WCM._hookTryStart) <= 8.0 then
      if TryHookBossRecords() then
        WCM._hookTryActive = false
      end
    else
      WCM._hookTryActive = false
      Print("BigWigs adapter could not hook BossRecords")
    end
  end

  if WCM.state.running then
    WCM.state.elapsed = Now() - WCM.state.startTime

    if WCM.state.source == "manual" and S().testAutoStop then
      if WCM.state.elapsed >= (WCM.state.predicted or 0) then
        WCM:StopEncounter(WCM.state.predicted, "Test", "manual")
        return
      end
    end

    UpdateExecuteState()
    LivePredictTick()

    if WCM.UI and WCM.UI.UpdateTimeline then
      WCM.UI:UpdateTimeline(WCM.state.elapsed, WCM.state.predicted)
    end
  end
end)

-------------------------------------------------
-- Slash
-------------------------------------------------
SLASH_WCM1 = "/wcm"
SlashCmdList["WCM"] = function(msg)
  msg = msg or ""

  if msg == "show" then
    if WCM.UI then WCM.UI:Show(true) end
    Print("Shown")
  elseif msg == "hide" then
    if WCM.UI then WCM.UI:Hide() end
    Print("Hidden")
  elseif msg == "opt" or msg == "options" then
    if WCM.Options then WCM.Options:Toggle() end
  elseif string.sub(msg, 1, 5) == "start" then
    local n = string.sub(msg, 6)
    WCM:StartTest(n)
  elseif msg == "stop" then
    WCM:StopTest()
  elseif string.sub(msg, 1, 4) == "hist" then
    local boss = string.sub(msg, 6)
    if boss and boss ~= "" then
      WCM:PrintBossHistory(boss)
    else
      Print("usage: /wcm hist <bossname>")
    end
  elseif msg == "diag" then
    Print("diag: preferAlign=" .. tostring(S().preferAlign) ..
      " autoHideOOC=" .. tostring(S().autoHideOOC) ..
      " inCombat=" .. tostring(InCombat()) ..
      " running=" .. tostring(WCM.state.running) ..
      " boss=" .. tostring(WCM.state.boss) ..
      " bwEnabled=" .. tostring(S().bwEnabled) ..
      " hooked=" .. tostring(WCM.BW and WCM.BW.hooked) ..
      " method=" .. tostring(WCM.BW and WCM.BW.method) ..
      " lockToBoss=" .. tostring(S().lockToBoss) ..
      " bossGUID=" .. tostring(WCM.state.bossGUID) ..
      " bossNameLock=" .. tostring(WCM.state.bossNameLock) ..
      " showPrompt=" .. tostring(S().showPrompt) ..
      " promptOnlyPressNow=" .. tostring(S().promptOnlyPressNow))
  else
    Print("/wcm show | hide | opt | start [sec] | stop | hist <boss> | diag")
  end
end
