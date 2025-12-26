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

local function CopyTableShallow(src)
  local dst = {}
  if not src then return dst end
  for k, v in pairs(src) do
    dst[k] = v
  end
  return dst
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

  if db.settings.preferAlign == nil then db.settings.preferAlign = true end

  if db.settings.showAllUses == nil then db.settings.showAllUses = true end
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
-- Boss Locking
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

-------------------------------------------------
-- Schedules
-------------------------------------------------
local function BuildScheduleFromStart(predicted, cd)
  local out = {}
  predicted = tonumber(predicted) or 0
  cd = tonumber(cd) or 0
  if predicted <= 0 or cd <= 0 then return out end

  local t = 0
  while t <= predicted do
    table.insert(out, t)
    t = t + cd
  end
  return out
end

local function BuildScheduleFromEnd(predicted, cd, anchorRem)
  local out = {}
  predicted = tonumber(predicted) or 0
  cd = tonumber(cd) or 0
  anchorRem = tonumber(anchorRem) or 0
  if predicted <= 0 or cd <= 0 then return out end

  local last = predicted - anchorRem
  if last < 0 then last = 0 end

  local t = last
  while t >= 0 do
    table.insert(out, 1, t)
    t = t - cd
  end

  return out
end

local function BuildSchedule(def, predicted)
  local cd = GetDefCooldownSeconds(def)

  if def.oncePerFight then
    local anchor = def.anchorRem or def.dur or 0
    local one = predicted - (anchor or 0)
    if one < 0 then one = 0 end
    return { one }
  end

  if S().preferAlign and def.anchorRem then
    return BuildScheduleFromEnd(predicted, cd, def.anchorRem)
  end

  return BuildScheduleFromStart(predicted, cd)
end

local function NextMarkerInSchedule(sched, elapsed)
  if not sched or table.getn(sched) == 0 then return nil end
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

local function NearestMarkerDelta(sched, elapsed)
  if not sched or table.getn(sched) == 0 then return nil end
  local bestAbs, bestDt = nil, nil
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

local function ScheduleHasZeroMarker(sched)
  if not sched then return false end
  local i = 1
  while i <= table.getn(sched) do
    if Abs((sched[i] or 0) - 0) < 0.001 then return true end
    i = i + 1
  end
  return false
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
-- Visible range (execute zoom)
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

-------------------------------------------------
-- Eligibility rules
-------------------------------------------------
local function IsDefAllowedNow(def)
  if def.oncePerFight then
    if not WCM.state.execute then return false end
  end
  return true
end

-------------------------------------------------
-- Prompt logic
-------------------------------------------------
local function MissedLastMarkerAndNoFuture(elapsed, predicted, cd, sched)
  local hw = tonumber(S().highlightWindow) or 0.7
  local buffer = tonumber(S().loseUseBuffer) or 2.0

  local nextDt = NextMarkerInSchedule(sched, elapsed)
  if nextDt ~= nil then return false end

  local remaining = predicted - elapsed
  if remaining < 0 then remaining = 0 end

  if remaining <= (cd + buffer) then
    local dtNearest = NearestMarkerDelta(sched, elapsed)
    if dtNearest and dtNearest > hw then
      return true
    end
  end

  return false
end

local function GetDefPromptState(def, elapsed, predicted)
  if (not CooldownAvailable(def)) then return nil end
  if (not IsDefAllowedNow(def)) then return nil end
  if (not CooldownReady(def)) then return nil end

  local hw = tonumber(S().highlightWindow) or 0.7
  local soonW = tonumber(S().incomingWindow) or 4.0

  local cd = GetDefCooldownSeconds(def)
  local sched = BuildSchedule(def, predicted)
  if not sched or table.getn(sched) == 0 then return "HOLD", nil end

  if elapsed <= hw and ScheduleHasZeroMarker(sched) then
    return "PRESS NOW", -elapsed
  end

  local dtNearest = NearestMarkerDelta(sched, elapsed)
  if not dtNearest then return "HOLD", nil end

  local absNearest = Abs(dtNearest)

  if absNearest <= hw then
    return "PRESS NOW", dtNearest
  end

  if S().preferAlign then
    if MissedLastMarkerAndNoFuture(elapsed, predicted, cd, sched) then
      return "PRESS NOW", dtNearest
    end
  else
    local remaining = predicted - elapsed
    if remaining < 0 then remaining = 0 end
    if remaining <= (cd + (tonumber(S().loseUseBuffer) or 2.0)) then
      return "PRESS NOW", dtNearest
    end
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
    if def.anchorRem and CooldownAvailable(def) and CooldownReady(def) and IsDefAllowedNow(def) then
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
    Consider(COOLDOWNS[i])
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

  local apText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  apText:SetPoint("LEFT", ap, "RIGHT", 6, 0)
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
      if self.promptText then self.promptText:SetText("") end
    else
      self.promptFrame:Show()
      self.promptFrame:SetFrameStrata("HIGH")
      self.promptFrame:SetFrameLevel(200)
      self.promptTex:SetTexture(CooldownTexture(promptDef))
      self.promptTex:SetAlpha(0.98)
      if self.promptText then self.promptText:SetText(promptState) end
    end
  else
    self.promptFrame:Hide()
    if self.promptText then self.promptText:SetText("") end
  end

  local di = 1
  while di <= table.getn(COOLDOWNS) do
    local def = COOLDOWNS[di]

    if S().showAllUses and CooldownAvailable(def) then
      local ready = CooldownReady(def)
      local sched = BuildSchedule(def, predicted)

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
          if ready and absdt <= hw then
            mode2 = "now"
          elseif ready and absdt <= soonW then
            mode2 = "soon"
          end

          local isPrimary = false
          if promptDef and promptState == "PRESS NOW" and def.id == promptDef.id then
            if ready and absdt <= hw then
              isPrimary = true
            end
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
-- Options UI (scrollable, OK/Cancel pinned)
-------------------------------------------------
WCM.Options = WCM.Options or {}

local function MakeHeader(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function MakeSubHeader(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(text)
  return fs
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

local function MakeDivider(parent, x, y, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  t:SetWidth(w)
  t:SetHeight(2)
  t:SetTexture(1, 1, 1, 0.12)
  return t
end

local function MakeCheck(parent, name, label, x, y)
  local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local tx = getglobal(cb:GetName() .. "Text")
  tx:SetText(label)
  tx:ClearAllPoints()
  tx:SetPoint("LEFT", cb, "RIGHT", 6, 1)
  tx:SetJustifyH("LEFT")
  return cb
end

function WCM.Options:GetDraft()
  self.draft = self.draft or CopyTableShallow(S())
  return self.draft
end

function WCM.Options:BeginDraft()
  self.savedSnapshot = CopyTableShallow(S())
  self.draft = CopyTableShallow(S())
  self._syncing = false
  self._committed = false
end

function WCM.Options:RevertToSnapshot()
  if not self.savedSnapshot then return end
  local snap = self.savedSnapshot
  for k, v in pairs(snap) do
    S()[k] = v
  end
  if WCM.UI then
    WCM.UI:ApplyPosition()
    WCM.UI:ApplyLock()
  end
end

function WCM.Options:ApplyDraftPreview()
  local d = self:GetDraft()

  if WCM.UI and WCM.UI.frame then
    if d.scale then WCM.UI:SetScale(d.scale) end
    if d.left and d.top then
      WCM.UI:SetPosition(d.left, d.top)
    end
    S().locked = d.locked and true or false
    WCM.UI:ApplyLock()
  end

  S().autoHideOOC = d.autoHideOOC and true or false
  S().lockToBoss = d.lockToBoss and true or false
  S().bwEnabled = d.bwEnabled and true or false
  S().livePredict = d.livePredict and true or false
  S().executeBarRed = d.executeBarRed and true or false
  S().executeZoom = d.executeZoom and true or false
  S().executeZoomByPct = d.executeZoomByPct and true or false
  S().testExecuteSim = d.testExecuteSim and true or false
  S().testAutoStop = d.testAutoStop and true or false
  S().showPrompt = d.showPrompt and true or false
  S().promptOnlyPressNow = d.promptOnlyPressNow and true or false
  S().showAllUses = d.showAllUses and true or false

  if d.trinketCD then S().trinketCD = d.trinketCD end
  if d.executeThreshold then S().executeThreshold = d.executeThreshold end
  if d.executeZoomWindow then S().executeZoomWindow = d.executeZoomWindow end
end

function WCM.Options:CommitDraft()
  local d = self:GetDraft()
  for k, v in pairs(d) do
    S()[k] = v
  end
  self._committed = true
end

function WCM.Options:UpdatePosSliderRanges()
  if not self.frame or not WCM.UI or not WCM.UI.frame then return end
  if not self.xSlider or not self.ySlider then return end

  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()

  local scale = (self:GetDraft().scale or (WCM.UI.frame:GetScale() or 1))
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

  local d = self:GetDraft()

  if self.lockCB then self.lockCB:SetChecked(d.locked and true or false) end

  if self.scaleSlider then
    self.scaleSlider:SetValue(d.scale or 1.0)
    getglobal(self.scaleSlider:GetName() .. "Text"):SetText(string.format("%.2f", d.scale or 1.0))
  end

  if self.xBox then self.xBox:SetText(tostring(math.floor((d.left or 0) + 0.5))) end
  if self.yBox then self.yBox:SetText(tostring(math.floor((d.top or 0) + 0.5))) end

  if self.xSlider then self.xSlider:SetValue(d.left or 0) end
  if self.ySlider then self.ySlider:SetValue(d.top or 0) end

  if self.trinketBox then self.trinketBox:SetText(tostring(d.trinketCD or 120)) end
  if self.execBox then self.execBox:SetText(tostring(d.executeThreshold or 20)) end
  if self.zoomBox then self.zoomBox:SetText(tostring(d.executeZoomWindow or 30)) end

  if self.autoHideCB then self.autoHideCB:SetChecked(d.autoHideOOC and true or false) end
  if self.lockBossCB then self.lockBossCB:SetChecked(d.lockToBoss and true or false) end

  if self.bwCB then self.bwCB:SetChecked(d.bwEnabled and true or false) end
  if self.liveCB then self.liveCB:SetChecked(d.livePredict and true or false) end
  if self.execRedCB then self.execRedCB:SetChecked(d.executeBarRed and true or false) end

  if self.execZoomCB then self.execZoomCB:SetChecked(d.executeZoom and true or false) end
  if self.execZoomPctCB then self.execZoomPctCB:SetChecked(d.executeZoomByPct and true or false) end
  if self.testExecCB then self.testExecCB:SetChecked(d.testExecuteSim and true or false) end
  if self.testAutoStopCB then self.testAutoStopCB:SetChecked(d.testAutoStop and true or false) end

  if self.showPromptCB then self.showPromptCB:SetChecked(d.showPrompt and true or false) end
  if self.promptOnlyNowCB then self.promptOnlyNowCB:SetChecked(d.promptOnlyPressNow and true or false) end
  if self.allUsesCB then self.allUsesCB:SetChecked(d.showAllUses and true or false) end

  self._syncing = false
end

function WCM.Options:Create()
  if self.frame then return end

  local f = CreateFrame("Frame", "WCM_Options", UIParent)
  f:SetWidth(600)
  f:SetHeight(520)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
  end

  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(999)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)

  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  AddSpecialFrame("WCM_Options")
  f:Hide()

  MakeHeader(f, "WCM Options", 12, -12)

  local close = CreateFrame("Button", "WCM_Options_Close", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() f:Hide() end)

  MakeDivider(f, 12, -40, 576)

  local footer = CreateFrame("Frame", nil, f)
  footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
  footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
  footer:SetHeight(30)

  local ok = CreateFrame("Button", "WCM_Options_OK", footer, "UIPanelButtonTemplate")
  ok:SetWidth(120)
  ok:SetHeight(22)
  ok:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
  ok:SetText("OK")

  local cancel = CreateFrame("Button", "WCM_Options_Cancel", footer, "UIPanelButtonTemplate")
  cancel:SetWidth(120)
  cancel:SetHeight(22)
  cancel:SetPoint("RIGHT", ok, "LEFT", -10, 0)
  cancel:SetText("Cancel")

  local scroll = CreateFrame("ScrollFrame", "WCM_Options_Scroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 48)

  local content = CreateFrame("Frame", "WCM_Options_Content", scroll)
  content:SetWidth(540)
  content:SetHeight(820)
  scroll:SetScrollChild(content)

  self.frame = f
  self.scroll = scroll
  self.content = content

  local function D() return WCM.Options:GetDraft() end
  local function Preview() WCM.Options:ApplyDraftPreview() end

  local y = -6

  MakeSubHeader(content, "Layout", 0, y); y = y - 26

  local lockCB = MakeCheck(content, "WCM_Options_Lock", "Locked. Uncheck to drag the bar.", 0, y); y = y - 34
  self.lockCB = lockCB

  MakeLabel(content, "Scale", 0, y); y = y - 18
  local scale = CreateFrame("Slider", "WCM_Options_Scale", content, "OptionsSliderTemplate")
  scale:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
  scale:SetWidth(340)
  scale:SetMinMaxValues(0.60, 1.80)
  scale:SetValueStep(0.05)
  if scale.SetObeyStepOnDrag then scale:SetObeyStepOnDrag(true) end
  getglobal(scale:GetName() .. "Low"):SetText("0.60")
  getglobal(scale:GetName() .. "High"):SetText("1.80")
  getglobal(scale:GetName() .. "Text"):SetText("1.00")
  self.scaleSlider = scale
  y = y - 50

  MakeLabel(content, "Position X (left)", 0, y); y = y - 18
  local xs = CreateFrame("Slider", "WCM_Options_PosX", content, "OptionsSliderTemplate")
  xs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
  xs:SetWidth(400)
  xs:SetValueStep(1)
  if xs.SetObeyStepOnDrag then xs:SetObeyStepOnDrag(true) end
  getglobal(xs:GetName() .. "Low"):SetText("")
  getglobal(xs:GetName() .. "High"):SetText("")
  getglobal(xs:GetName() .. "Text"):SetText("")
  self.xSlider = xs

  local xBox = MakeEditBox(content, 90, 18, 420, y - 2)
  self.xBox = xBox
  y = y - 54

  MakeLabel(content, "Position Y (top)", 0, y); y = y - 18
  local ys = CreateFrame("Slider", "WCM_Options_PosY", content, "OptionsSliderTemplate")
  ys:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
  ys:SetWidth(400)
  ys:SetValueStep(1)
  if ys.SetObeyStepOnDrag then ys:SetObeyStepOnDrag(true) end
  getglobal(ys:GetName() .. "Low"):SetText("")
  getglobal(ys:GetName() .. "High"):SetText("")
  getglobal(ys:GetName() .. "Text"):SetText("")
  self.ySlider = ys

  local yBox = MakeEditBox(content, 90, 18, 420, y - 2)
  self.yBox = yBox
  y = y - 62

  MakeDivider(content, 0, y, 540); y = y - 18

  MakeSubHeader(content, "Behavior", 0, y); y = y - 26
  local autoHideCB = MakeCheck(content, "WCM_Options_AutoHide", "Hide the bar out of combat", 0, y); y = y - 26
  local lockBossCB = MakeCheck(content, "WCM_Options_LockBoss", "Boss-only prediction. Ignore adds.", 0, y); y = y - 34
  self.autoHideCB = autoHideCB
  self.lockBossCB = lockBossCB

  MakeDivider(content, 0, y, 540); y = y - 18

  -------------------------------------------------
  -- Prediction and Execute (fixed layout)
  -------------------------------------------------
  MakeSubHeader(content, "Prediction and Execute", 0, y); y = y - 26

  local colL = 0
  local colR = 320

  local rowTop = y

  local bwCB = MakeCheck(content, "WCM_Options_BW", "Use BigWigs boss times (history)", colL, rowTop)
  rowTop = rowTop - 26
  local liveCB = MakeCheck(content, "WCM_Options_Live", "Live adjust prediction from boss HP drop", colL, rowTop)
  rowTop = rowTop - 26
  local execRedCB = MakeCheck(content, "WCM_Options_ExecRed", "Make the bar red in execute phase", colL, rowTop)
  rowTop = rowTop - 34

  self.bwCB = bwCB
  self.liveCB = liveCB
  self.execRedCB = execRedCB

  local rightY = y

  MakeLabel(content, "Trinket cooldown (sec)", colR, rightY); rightY = rightY - 18
  local tcdBox = MakeEditBox(content, 70, 18, colR + 170, rightY + 2)
  self.trinketBox = tcdBox
  rightY = rightY - 30

  MakeLabel(content, "Execute starts at (%)", colR, rightY); rightY = rightY - 18
  local exBox = MakeEditBox(content, 70, 18, colR + 170, rightY + 2)
  self.execBox = exBox
  rightY = rightY - 34

  local execZoomCB = MakeCheck(content, "WCM_Options_ExecZoom", "Zoom timeline in execute", colR, rightY)
  rightY = rightY - 26
  local execZoomPctCB = MakeCheck(content, "WCM_Options_ExecZoomPct", "Zoom by execute percent", colR, rightY)
  rightY = rightY - 30

  self.execZoomCB = execZoomCB
  self.execZoomPctCB = execZoomPctCB

  MakeLabel(content, "Zoom seconds (when percent zoom is off)", colR, rightY); rightY = rightY - 18
  local zBox = MakeEditBox(content, 70, 18, colR + 170, rightY + 2)
  self.zoomBox = zBox
  rightY = rightY - 18

  y = rowTop
  if rightY < y then y = rightY end
  y = y - 10

  MakeDivider(content, 0, y, 540); y = y - 18

  MakeSubHeader(content, "UI", 0, y); y = y - 26
  local showPromptCB = MakeCheck(content, "WCM_Options_ShowPrompt", "Show Action Prompt icon", 0, y); y = y - 26
  local promptOnlyNowCB = MakeCheck(content, "WCM_Options_PromptOnlyNow", "Only show it when you should press now", 0, y); y = y - 26
  local allUsesCB = MakeCheck(content, "WCM_Options_AllUses", "Show every scheduled use on the timeline", 0, y); y = y - 34
  self.showPromptCB = showPromptCB
  self.promptOnlyNowCB = promptOnlyNowCB
  self.allUsesCB = allUsesCB

  MakeDivider(content, 0, y, 540); y = y - 18

  MakeSubHeader(content, "Test", 0, y); y = y - 26
  local testExecCB = MakeCheck(content, "WCM_Options_TestExec", "Simulate execute during manual test", 0, y); y = y - 26
  local testAutoStopCB = MakeCheck(content, "WCM_Options_TestStop", "Stop test automatically at predicted time", 0, y); y = y - 34
  self.testExecCB = testExecCB
  self.testAutoStopCB = testAutoStopCB

  content:SetHeight(Abs(y) + 40)

  local function DVal() return WCM.Options:GetDraft() end
  local function PreviewNow() WCM.Options:ApplyDraftPreview() end

  lockCB:SetScript("OnClick", function()
    DVal().locked = lockCB:GetChecked() and true or false
    PreviewNow()
  end)

  scale:SetScript("OnValueChanged", function()
    if WCM.Options._syncing then return end
    local v = Round2(scale:GetValue())
    DVal().scale = v
    getglobal(scale:GetName() .. "Text"):SetText(string.format("%.2f", v))
    WCM.Options:UpdatePosSliderRanges()
    PreviewNow()
    WCM.Options:SyncFromDB()
  end)

  xs:SetScript("OnValueChanged", function()
    if WCM.Options._syncing then return end
    local v = math.floor(xs:GetValue() + 0.5)
    DVal().left = v
    if xBox and xBox.SetText then xBox:SetText(tostring(v)) end
    PreviewNow()
  end)

  ys:SetScript("OnValueChanged", function()
    if WCM.Options._syncing then return end
    local v = math.floor(ys:GetValue() + 0.5)
    DVal().top = v
    if yBox and yBox.SetText then yBox:SetText(tostring(v)) end
    PreviewNow()
  end)

  xBox:SetScript("OnEnterPressed", function()
    local v = tonumber(xBox:GetText())
    if v then
      DVal().left = v
      PreviewNow()
      WCM.Options:SyncFromDB()
      Print("Position updated (preview)")
    end
    xBox:ClearFocus()
  end)

  yBox:SetScript("OnEnterPressed", function()
    local v = tonumber(yBox:GetText())
    if v then
      DVal().top = v
      PreviewNow()
      WCM.Options:SyncFromDB()
      Print("Position updated (preview)")
    end
    yBox:ClearFocus()
  end)

  autoHideCB:SetScript("OnClick", function()
    DVal().autoHideOOC = autoHideCB:GetChecked() and true or false
    PreviewNow()
  end)

  lockBossCB:SetScript("OnClick", function()
    DVal().lockToBoss = lockBossCB:GetChecked() and true or false
    PreviewNow()
  end)

  bwCB:SetScript("OnClick", function()
    DVal().bwEnabled = bwCB:GetChecked() and true or false
    PreviewNow()
  end)

  liveCB:SetScript("OnClick", function()
    DVal().livePredict = liveCB:GetChecked() and true or false
    PreviewNow()
  end)

  execRedCB:SetScript("OnClick", function()
    DVal().executeBarRed = execRedCB:GetChecked() and true or false
    PreviewNow()
  end)

  execZoomCB:SetScript("OnClick", function()
    DVal().executeZoom = execZoomCB:GetChecked() and true or false
    PreviewNow()
  end)

  execZoomPctCB:SetScript("OnClick", function()
    DVal().executeZoomByPct = execZoomPctCB:GetChecked() and true or false
    PreviewNow()
  end)

  testExecCB:SetScript("OnClick", function()
    DVal().testExecuteSim = testExecCB:GetChecked() and true or false
    PreviewNow()
  end)

  testAutoStopCB:SetScript("OnClick", function()
    DVal().testAutoStop = testAutoStopCB:GetChecked() and true or false
    PreviewNow()
  end)

  showPromptCB:SetScript("OnClick", function()
    DVal().showPrompt = showPromptCB:GetChecked() and true or false
    PreviewNow()
  end)

  promptOnlyNowCB:SetScript("OnClick", function()
    DVal().promptOnlyPressNow = promptOnlyNowCB:GetChecked() and true or false
    PreviewNow()
  end)

  allUsesCB:SetScript("OnClick", function()
    DVal().showAllUses = allUsesCB:GetChecked() and true or false
    PreviewNow()
  end)

  tcdBox:SetScript("OnEnterPressed", function()
    local v = tonumber(tcdBox:GetText())
    if v then
      v = Clamp(v, 30, 600)
      DVal().trinketCD = v
      tcdBox:SetText(tostring(v))
      PreviewNow()
      Print("Trinket cooldown updated (preview)")
    end
    tcdBox:ClearFocus()
  end)

  exBox:SetScript("OnEnterPressed", function()
    local v = tonumber(exBox:GetText())
    if v then
      v = Clamp(v, 1, 99)
      DVal().executeThreshold = v
      exBox:SetText(tostring(v))
      PreviewNow()
      Print("Execute threshold updated (preview)")
    end
    exBox:ClearFocus()
  end)

  zBox:SetScript("OnEnterPressed", function()
    local v = tonumber(zBox:GetText())
    if v then
      v = Clamp(v, 10, 120)
      DVal().executeZoomWindow = v
      zBox:SetText(tostring(v))
      PreviewNow()
      Print("Execute zoom seconds updated (preview)")
    end
    zBox:ClearFocus()
  end)

  ok:SetScript("OnClick", function()
    WCM.Options:CommitDraft()
    Print("Options saved")
    f:Hide()
  end)

  cancel:SetScript("OnClick", function()
    f:Hide()
  end)

  f:SetScript("OnShow", function()
    WCM.Options:BeginDraft()
    WCM.Options:UpdatePosSliderRanges()
    WCM.Options:SyncFromDB()
    PreviewNow()
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(999)
  end)

  f:SetScript("OnHide", function()
    if not WCM.Options._committed then
      WCM.Options:RevertToSnapshot()
      Print("Options canceled")
    end
    WCM.Options.draft = nil
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
      " showAllUses=" .. tostring(S().showAllUses) ..
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
