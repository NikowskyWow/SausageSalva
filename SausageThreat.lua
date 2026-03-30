-- ============================================================================
-- SAUSAGE THREAT - Paladin Threat & Coordination (Pro Grid Edition)
-- Author: Sausage Party / Kokotiar
-- ============================================================================

local addonName, addonTable = ...
local SAUSAGE_VERSION = "Beta 0.9" 

-- 1. LOCAL ALIASES (Appendix A, p. 1310) for peak performance
local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local Minimap = _G.Minimap
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown
local select = _G.select
local pairs = _G.pairs
local ipairs = _G.ipairs
local strfind = _G.string.find
local math_rad = _G.math.rad
local math_cos = _G.math.cos
local math_sin = _G.math.sin
local math_deg = _G.math.deg
local math_atan2 = _G.math.atan2
local GetCursorPosition = _G.GetCursorPosition
local tinsert = _G.tinsert or _G.table.insert
local UISpecialFrames = _G.UISpecialFrames

local PREFIX = "STHREAT"
local SALVA_SPELL_ID = 1038 -- Hand of Salvation
local MISDIRECT_SPELL_ID = 34477 -- Misdirection
local TRICKS_SPELL_ID = 57934 -- Tricks of the Trade

local SALVA_NAME = GetSpellInfo(SALVA_SPELL_ID)
local MISDIRECT_NAME = GetSpellInfo(MISDIRECT_SPELL_ID)
local TRICKS_NAME = GetSpellInfo(TRICKS_SPELL_ID)
local THREAT_SOUND = "Interface\\AddOns\\SausageThreat\\sound\\threat.wav"
local mySoundPath

local defaultDB = {
    autoHide = false,
    isShown = true,
    anchor = "TOP",
    frameX = nil,
    frameY = nil,
    btnWidth = 75,
    btnHeight = 35,
    cols = 5,
    spacing = 2,
    hideBorder = false,
    hideHeader = false,
    hideNames = false,
    hideThreat = false,
    showListPala = {},
    showListHunt = {},
    showListRogue = {},
    showListMaster = {},
    enableSound = true,
    bossOnlyAlert = false,
    hideBackground = false,
    showRoles = true,
    cmdLockout = 3,
    radialRingType = 1,
    threatThresholdMelee = 90,  -- Prah threatu pre melee/tankov/healov (%)
    threatThresholdCaster = 110, -- Prah threatu pre castorov: Mage, Warlock, Priest (%)
    minimapPos = 180 -- SDS Default
}

local inCombat = false
local isTestMode = false
local unitButtons = {}
local activePaladins = {}
local currentTab = 1
local focusTarget = nil
local focusTimer = 0
local focusTargetClass = nil -- Zaznamenáva, aká classa bola priradená (pre farbu pulzu)
local preCastTarget = nil
local preCastTimer = 0
local rangeFailTracker = {}
local activeBuffsOnTarget = {} -- Tracker pre MD a ToT (meno -> cas vyprsania)
local lockedSpells = {} -- Cooldown na povely pre hraca

local lockedThreatGUID = nil -- GUID zamknutého threat targetu
local lockedThreatName = nil -- Meno zamknutého threat targetu (pre zobrazenie na tlačidle)
local coordRefreshTimer = 0  -- Timer na periodickú aktualizáciu CoordFrame odpočítavania
local totTargetIsDPS = false -- Sleduje, či bol ToT použitý na DPS cieľ (pre auto-cancel)

-- [[ PRED-DEKLARÁCIE ]]
local EventFrame = CreateFrame("Frame")
local SausageThreatMainFrame_UpdateGrid
local UpdateCombatGrid
local SortPaladins
local UpdateIgnoreScrollFrame
local BroadcastStatus
local HandleRadialClick

local playerClassOrig = select(2, UnitClass("player"))
local debugClass = nil
local debugLeader = false

local isPaladin, isHunter, isRogue, isCoordClass
local mySpellName, mySoundPath

-- [[ UTILITY FUNKCIE ]]
-- Utility: After (Bible-style delay for WotLK)
local function After(delay, func)
    local f = CreateFrame("Frame")
    f.t = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.t >= delay then
            self:SetScript("OnUpdate", nil)
            func()
            self:Hide() -- Cleanup
        end
    end)
end

local function UpdateAddonIdentity()
    local currentClass = debugClass or playerClassOrig
    isPaladin = (currentClass == "PALADIN")
    isHunter = (currentClass == "HUNTER")
    isRogue = (currentClass == "ROGUE")
    isCoordClass = isPaladin or isHunter or isRogue
    
    SALVA_NAME = SALVA_NAME or GetSpellInfo(SALVA_SPELL_ID)
    MISDIRECT_NAME = MISDIRECT_NAME or GetSpellInfo(MISDIRECT_SPELL_ID)
    TRICKS_NAME = TRICKS_NAME or GetSpellInfo(TRICKS_SPELL_ID)
    
    mySpellName = (isPaladin and SALVA_NAME) or (isHunter and MISDIRECT_NAME) or (isRogue and TRICKS_NAME) or nil
    
    local soundFile = (isPaladin and "salvation.wav") or (isHunter and "misdirection.wav") or (isRogue and "tricksoftrade.wav")
    if soundFile then
        mySoundPath = "Interface\\AddOns\\SausageThreat\\sound\\" .. soundFile
    else
        mySoundPath = nil
    end

    -- Dynamická aktualizácia atribútov tlačidiel
    if not InCombatLockdown() then
        for i = 1, 40 do
            local btn = _G["SausageThreatGridBtn"..i]
            if btn then
                btn:SetAttribute("type1", "spell")
                btn:SetAttribute("spell1", mySpellName or "")
            end
        end
    end
end
UpdateAddonIdentity()

local IsRaidLeader_Orig = IsRaidLeader
local function IsRaidLeader_Check()
    if debugLeader then return true end
    return (GetNumRaidMembers() > 0 and IsRaidLeader_Orig()) or (GetNumPartyMembers() > 0 and not (GetNumRaidMembers() > 0) and IsPartyLeader())
end

local function IsRaidOfficer_Check()
    if debugLeader then return true end
    if GetNumRaidMembers() > 0 then
        local myName = UnitName("player")
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name == myName then return rank >= 1 end
        end
    end
    return false
end

-- Prepojenie volaní na naše nové checkery
local IsRaidLeader = IsRaidLeader_Check
local IsRaidOfficer = IsRaidOfficer_Check

local function IsInRaid() return GetNumRaidMembers() > 0 end
local function IsInGroup() return GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 end

local function GetPaladinSpec()
    if not isPaladin then return 0 end
    local highestPoints, spec = -1, 1
    for i = 1, 3 do
        local _, _, points = GetTalentTabInfo(i)
        if points and points > highestPoints then
            highestPoints, spec = points, i
        end
    end
    return spec
end

local function IsEligibleForThreatSound()
    if debugLeader or IsRaidLeader() or IsRaidOfficer() then return true end
    if GetPartyAssignment("MAINTANK", "player") then return true end
    if isPaladin and GetPaladinSpec() == 2 then return true end
    -- Ostatní tankovia podľa 'MAINTANK' role alebo manuálneho nastavenia. 
    return false
end

local globalThreatSoundTime = 0

local function SendComm(msg)
    if not IsInGroup() then return end
    local channel = IsInRaid() and "RAID" or "PARTY"
    if select(2, IsInInstance()) == "pvp" then channel = "BATTLEGROUND" end
    SendAddonMessage(PREFIX, msg, channel)
end

local function GetUnitByName(name)
    if name == UnitName("player") then return "player" end
    if name == UnitName("target") then return "target" end
    if name == UnitName("focus") then return "focus" end
    if IsInRaid() then
        for i=1, GetNumRaidMembers() do
            if UnitName("raid"..i) == name then return "raid"..i end
        end
    elseif IsInGroup() then
        for i=1, GetNumPartyMembers() do
            if UnitName("party"..i) == name then return "party"..i end
        end
    end
    return nil
end

local function DetermineMyRole()
    local _, class = UnitClass("player")
    local highestPoints, spec = -1, 1
    for i = 1, 3 do
        local _, _, points = GetTalentTabInfo(i)
        if points and points > highestPoints then
            highestPoints, spec = points, i
        end
    end
    
    local role = "DPS"
    if class == "PALADIN" then
        if spec == 1 then role = "HEALER" elseif spec == 2 then role = "TANK" end
    elseif class == "WARRIOR" then
        if spec == 3 then role = "TANK" end
    elseif class == "PRIEST" then
        if spec == 1 or spec == 2 then role = "HEALER" end
    elseif class == "SHAMAN" then
        if spec == 3 then role = "HEALER" end
    elseif class == "DRUID" then
        if spec == 3 then role = "HEALER" elseif spec == 2 then role = "TANK" end
    elseif class == "DEATHKNIGHT" then
        if spec == 1 then role = "TANK" end
    end
    return role
end

local function GetUnitRoleFromName(name)
    if not name then return "DPS" end
    if SausageThreatDB.assignedRoles and SausageThreatDB.assignedRoles[name] then
        return SausageThreatDB.assignedRoles[name]
    end
    local unit = GetUnitByName(name)
    if not unit then return "DPS" end
    if GetPartyAssignment("MAINTANK", unit) then return "TANK" end
    return "DPS"
end

-- [[ LOGIKA ZÁZNAMOV A COOLDOWNOV ]]
local function CleanupPaladinList()
    local changed = false
    for i = #activePaladins, 1, -1 do
        local name = activePaladins[i].name
        if not UnitInRaid(name) and not UnitInParty(name) then
            table.remove(activePaladins, i)
            changed = true
        end
    end
    return changed
end

-- Explicitná definícia
SortPaladins = function()
    CleanupPaladinList()
    table.sort(activePaladins, function(a, b) return a.spec < b.spec end)

    local palas, hunts, rogues = {}, {}, {}
    local now = GetTime()
    for _, p in ipairs(activePaladins) do
        local color = "|cFFFFFFFF"
        if p.spec == 1 then color = "|cFFFFFF00" -- Holy
        elseif p.spec == 2 then color = "|cFFFF8800" -- Prot
        elseif p.spec == 3 then color = "|cFFFF0000" -- Ret
        elseif p.spec == 4 then color = "|cFFABD473" -- Hunter
        elseif p.spec == 5 then color = "|cFFFFF569" -- Rogue
        end

        -- Zostatok cooldownu: zobraz odpočítavanie ak nie je ready
        local entry
        if p.isReady == false and p.cooldownEnd and p.cooldownEnd > now then
            local cdLeft = math.ceil(p.cooldownEnd - now)
            entry = color .. p.name .. "|r |cFF888888(" .. cdLeft .. "s)|r"
        elseif p.isReady == false then
            entry = color .. p.name .. "|r |cFF888888(CD)|r"
        else
            entry = color .. p.name .. "|r"
        end

        if p.spec <= 3 then table.insert(palas, entry)
        elseif p.spec == 4 then table.insert(hunts, entry)
        elseif p.spec == 5 then table.insert(rogues, entry)
        end
    end

    if SausageThreatMainFrame_UpdateGrid then
        SausageThreatCoordPala.text:SetText(#palas > 0 and table.concat(palas, ", ") or "|cFF888888None|r")
        SausageThreatCoordHunt.text:SetText(#hunts > 0 and table.concat(hunts, ", ") or "|cFF888888None|r")
        SausageThreatCoordRogue.text:SetText(#rogues > 0 and table.concat(rogues, ", ") or "|cFF888888None|r")
    end
end

-- Bezpečná funkcia na broadcast statusu
BroadcastStatus = function()
    if not isCoordClass then return end
    local spell = (isPaladin and SALVA_NAME) or (isHunter and MISDIRECT_NAME) or (isRogue and TRICKS_NAME)
    if not spell then return end
    
    local start, duration = GetSpellCooldown(spell)
    local isReady = 0
    local remaining = 0
    -- Poistka proti "attempt to compare nil with number"
    if start and duration then
        isReady = (start == 0 or duration <= 1.5) and 1 or 0
        -- Vypočítaj zostatok cooldownu pre broadcast (prijímač ho zobrazí v CoordFrame)
        if isReady == 0 and start > 0 then
            remaining = math.ceil(duration - (GetTime() - start))
            if remaining < 0 then remaining = 0 end
        end
    end

    local spec = 1
    if isPaladin then spec = GetPaladinSpec() elseif isHunter then spec = 4 elseif isRogue then spec = 5 end
    SendComm("ANNOUNCE:"..spec..":"..isReady..":"..remaining)
end

-- [[ HLAVNÝ FRAME ]]
local MainFrame = CreateFrame("Frame", "SausageThreatMainFrame", UIParent)
MainFrame:SetPoint("CENTER", 0, 0)
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
MainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point = SausageThreatDB.anchor or "TOP"
    local x, y
    
    if point == "TOP" then x, y = self:GetLeft() + self:GetWidth()/2, self:GetTop()
    elseif point == "BOTTOM" then x, y = self:GetLeft() + self:GetWidth()/2, self:GetBottom()
    elseif point == "LEFT" then x, y = self:GetLeft(), self:GetTop() - self:GetHeight()/2
    elseif point == "RIGHT" then x, y = self:GetRight(), self:GetTop() - self:GetHeight()/2
    else x, y = self:GetCenter() end

    self:ClearAllPoints()
    self:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
    if SausageThreatDB then SausageThreatDB.frameX, SausageThreatDB.frameY = x, y end
end)

MainFrame:SetScript("OnHide", function() 
    if SausageThreatDB then SausageThreatDB.isShown = false end 
    EventFrame:SetScript("OnUpdate", nil)
end)
MainFrame:SetScript("OnShow", function() 
    if SausageThreatDB then SausageThreatDB.isShown = true end 
    EventFrame:SetScript("OnUpdate", function(self, elapsed) UpdateCombatGrid(elapsed) end)
end)

MainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
MainFrame:SetBackdropColor(1, 1, 1, 1)

local header = MainFrame:CreateTexture(nil, "OVERLAY")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetSize(256, 64)
header:SetPoint("TOP", 0, 12)

local title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText("|cffff8800Sausage|r Threat")

-- [[ LOCK TARGET TLAČIDLO ]]
-- Viditeľné len pre Raid Leadera a Officera
local lockBtn = CreateFrame("Button", nil, MainFrame, "UIPanelButtonTemplate")
lockBtn:SetSize(85, 18)
lockBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -5, -5)
lockBtn:SetText("Lock Target")
lockBtn:Hide()

local function UpdateLockBtnVisibility()
    if IsRaidLeader() or IsRaidOfficer() then
        lockBtn:Show()
    else
        lockBtn:Hide()
        -- Stratili sme práva, uvoľníme zámok
        lockedThreatGUID = nil
        lockedThreatName = nil
        lockBtn:SetText("Lock Target")
    end
end

lockBtn:SetScript("OnClick", function(self)
    if lockedThreatGUID then
        -- Odomknúť
        lockedThreatGUID = nil
        lockedThreatName = nil
        self:SetText("Lock Target")
    else
        -- Zamknúť na aktuálny nepriateľský target
        if UnitExists("target") and UnitCanAttack("player", "target") then
            lockedThreatGUID = UnitGUID("target")
            lockedThreatName = UnitName("target")
            self:SetText("|cffffd200" .. (lockedThreatName or "???") .. "|r")
        else
            print("|cFFFF8800[SausageThreat]|r Select a valid enemy target to lock.")
        end
    end
end)

lockBtn:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if lockedThreatGUID then
        _G.GameTooltip:AddLine("Locked: " .. (lockedThreatName or "???"), 1, 0.8, 0)
        _G.GameTooltip:AddLine("Click to unlock threat target.", 0.7, 0.7, 0.7)
    else
        _G.GameTooltip:AddLine("Lock Threat Target", 1, 1, 1)
        _G.GameTooltip:AddLine("Target an enemy and click to lock\nthreat tracking to that unit.", 0.7, 0.7, 0.7)
    end
    _G.GameTooltip:Show()
end)
lockBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

local ContentFrame = CreateFrame("Frame", "SausageThreatContent", MainFrame)
ContentFrame:SetPoint("TOPLEFT", 15, -35)
ContentFrame:SetSize(1, 1)

-- [[ PANEL PRE KOORDINÁTOROV ]]
local CoordFrame = CreateFrame("Frame", "SausageThreatCoordFrame", UIParent)
CoordFrame:SetSize(320, 30)
CoordFrame:SetPoint("TOP", 0, -50)
CoordFrame:SetMovable(true)
CoordFrame:EnableMouse(true)
CoordFrame:RegisterForDrag("LeftButton")
CoordFrame:SetScript("OnDragStart", CoordFrame.StartMoving)
CoordFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Uloženie pozície CoordFrame do SavedVariables
    if SausageThreatDB then
        SausageThreatDB.coordFrameX = self:GetLeft()
        SausageThreatDB.coordFrameY = self:GetTop()
    end
end)
CoordFrame:SetBackdrop({ 
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background", 
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", 
    tile=true, tileSize=16, edgeSize=12, 
    insets={left=3,right=3,top=3,bottom=3} 
})
CoordFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
CoordFrame:SetBackdropBorderColor(1, 0.6, 0, 0.5)
CoordFrame:Hide()

local function CreateCoordIcon(class, x, name)
    local f = CreateFrame("Frame", name, CoordFrame)
    f:SetSize(16, 16)
    f:SetPoint("LEFT", x, 0)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Icons\\ClassIcon_" .. class)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("LEFT", f, "RIGHT", 3, 0)
    return f
end

CreateCoordIcon("Paladin", 10, "SausageThreatCoordPala")
CreateCoordIcon("Hunter", 110, "SausageThreatCoordHunt")
CreateCoordIcon("Rogue", 210, "SausageThreatCoordRogue")

-- [[ NOVÉ RADIAL MENU (Zmenšené na 128x128, Custom IKONY a VÝSEKY, BEZ ZLATÉHO KRÚŽKU) ]]
local RadialMenu = CreateFrame("Frame", "SausageThreatRadialMenu", UIParent)
RadialMenu:SetSize(175, 175)
RadialMenu:SetFrameStrata("TOOLTIP")
RadialMenu:Hide()

RadialMenu.customRing = RadialMenu:CreateTexture(nil, "OVERLAY", nil, 7)
RadialMenu.customRing:SetAllPoints(RadialMenu)
-- Zmena textúry prebehne v ADDON_LOADED alebo defaultne na paladina

local function CreateSlice(textureName, r, g, b)
    local t = RadialMenu:CreateTexture(nil, "ARTWORK")
    t:SetSize(130, 130)
    t:SetPoint("CENTER", 0, 0)
    t:SetTexture("Interface\\AddOns\\SausageThreat\\Textures\\" .. textureName)
    t:SetVertexColor(r, g, b, 0.4)
    return t
end

local palaSec  = CreateSlice("SliceTop.tga", 0.96, 0.55, 0.73)
local huntSec  = CreateSlice("SliceBotLeft.tga", 0.67, 0.83, 0.45)
local rogueSec = CreateSlice("SliceBotRight.tga", 1.00, 0.96, 0.41)
palaSec:SetAlpha(0.7)
huntSec:SetAlpha(0.7)
rogueSec:SetAlpha(0.7)

local hub = CreateFrame("Frame", nil, RadialMenu)
hub:SetSize(34, 34)
hub:SetPoint("CENTER", 0, 0)

RadialMenu.hubBg = hub:CreateTexture(nil, "OVERLAY", nil, 1)
RadialMenu.hubBg:SetAllPoints()
RadialMenu.hubBg:SetTexture("Interface\\MINIMAP\\UI-Minimap-Background")
RadialMenu.hubBg:SetVertexColor(0, 0, 0, 0.9)

local hubBorder = hub:CreateTexture(nil, "OVERLAY", nil, 2)
hubBorder:SetSize(40, 40)
hubBorder:SetPoint("CENTER", 0, 0)
hubBorder:SetTexture("Interface\\COMMON\\GreyCircle")
hubBorder:SetVertexColor(0.5, 0.5, 0.5, 0.8)

local hubText = hub:CreateFontString(nil, "OVERLAY", "SystemFont_Tiny")
hubText:SetPoint("CENTER", 0, 1)

local function CreateCustomIcon(textureName, x, y)
    local f = CreateFrame("Frame", nil, RadialMenu)
    f:SetSize(32, 32)
    f:SetPoint("CENTER", x, y)
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\SausageThreat\\Textures\\" .. textureName)
    f.tex = tex
    return f
end

local iconPala = CreateCustomIcon("IconSalva.tga", 0, 36)
local iconHunt = CreateCustomIcon("IconMisdirect.tga", -31, -18)
local iconRogue = CreateCustomIcon("IconTricks.tga", 31, -18)

-- Metallic Ring (Clean border)
local aura = RadialMenu:CreateTexture(nil, "OVERLAY", nil, 5)
aura:SetSize(175, 175)
aura:SetPoint("CENTER", 0, 0)
aura:SetTexture("Interface\\COMMON\\GreyCircle")
aura:SetVertexColor(1, 1, 1, 0.8)

RadialMenu.targetName = nil
RadialMenu.currentHoveredClass = nil
RadialMenu.cancelled = false

local function CanAssignBuffToTarget(buffCode, targetName, targetRole)
    if lockedSpells[targetName] and lockedSpells[targetName][buffCode] and lockedSpells[targetName][buffCode] > GetTime() then return false, "COOLDOWN" end
    if activeBuffsOnTarget[targetName] and activeBuffsOnTarget[targetName][buffCode] and activeBuffsOnTarget[targetName][buffCode].expiry > GetTime() then return false, "ACTIVE" end
    
    if buffCode == "PALA" and targetRole == "TANK" then return false, "Salva on Tank" end
    if buffCode == "HUNT" and targetRole ~= "TANK" then return false, "MD non-Tank" end
    if buffCode == "ROGUE" and targetRole == "HEALER" then return false, "ToT on Healer" end
    return true
end

HandleRadialClick = function(targetClass, overrideTargetName)
    local targetName = overrideTargetName or RadialMenu.targetName
    if not targetName then return end
    
    local targetRole = GetUnitRoleFromName(targetName)
    local canAssign, reason = CanAssignBuffToTarget(targetClass, targetName, targetRole)
    if not canAssign then
        if reason ~= "COOLDOWN" and reason ~= "ACTIVE" then print("|cFFFF0000[SausageThreat]|r " .. targetClass .. " blocked for role: " .. targetRole .. " (" .. targetName .. ")!") end
        return
    end
    
    local potentialUnits = {}
    local now = GetTime()
    
    for _, p in ipairs(activePaladins) do
        local penaltyUntil = (rangeFailTracker[targetName] and rangeFailTracker[targetName][p.name]) or 0
        if now >= penaltyUntil then
            if (targetClass == "PALA" and p.spec <= 3) or 
               (targetClass == "HUNT" and p.spec == 4) or 
               (targetClass == "ROGUE" and p.spec == 5) then
                table.insert(potentialUnits, p.name)
            end
        end
    end

    if #potentialUnits > 0 then
        local chosenUnit = potentialUnits[1]
        
        lockedSpells[targetName] = lockedSpells[targetName] or {}
        lockedSpells[targetName][targetClass] = GetTime() + (SausageThreatDB.cmdLockout or 3)
        
        SendComm("PING_CAST:"..targetName..":"..chosenUnit..":"..targetClass)
        print("|cFF00CCFF[SausageThreat]|r Assigning " .. targetClass .. " to " .. chosenUnit)
    else
        print("|cFFFF0000[SausageThreat]|r No available " .. targetClass .. "s in range/ready!")
    end
    RadialMenu:Hide()
end


RadialMenu:SetScript("OnUpdate", function(self)
    if not self:IsShown() then return end
    
    if IsMouseButtonDown("LeftButton") then
        self.cancelled = true
        self:Hide()
        return
    end
    
    if not IsMouseButtonDown("RightButton") then
        if self.currentHoveredClass and not self.cancelled then
            HandleRadialClick(self.currentHoveredClass)
        end
        self:Hide()
        return
    end

    local x, y = GetCursorPosition()
    local s = self:GetEffectiveScale()
    local mx, my = self:GetCenter()
    
    local angle = math.deg(math.atan2(y/s - my, x/s - mx))
    local dist = math.sqrt((x/s - mx)^2 + (y/s - my)^2)

    local tRole = GetUnitRoleFromName(RadialMenu.targetName)
    local pOK = CanAssignBuffToTarget("PALA", RadialMenu.targetName, tRole)
    local hOK = CanAssignBuffToTarget("HUNT", RadialMenu.targetName, tRole)
    local rOK = CanAssignBuffToTarget("ROGUE", RadialMenu.targetName, tRole)

    if pOK then palaSec:SetVertexColor(0.96, 0.55, 0.73, 0.4); palaSec:SetAlpha(0.6); iconPala.tex:SetVertexColor(1, 1, 1) else palaSec:SetVertexColor(0.2, 0.2, 0.2, 0.4); palaSec:SetAlpha(0.4); iconPala.tex:SetVertexColor(0.2, 0.2, 0.2) end
    if hOK then huntSec:SetVertexColor(0.67, 0.83, 0.45, 0.4); huntSec:SetAlpha(0.6); iconHunt.tex:SetVertexColor(1, 1, 1) else huntSec:SetVertexColor(0.2, 0.2, 0.2, 0.4); huntSec:SetAlpha(0.4); iconHunt.tex:SetVertexColor(0.2, 0.2, 0.2) end
    if rOK then rogueSec:SetVertexColor(1.00, 0.96, 0.41, 0.4); rogueSec:SetAlpha(0.6); iconRogue.tex:SetVertexColor(1, 1, 1) else rogueSec:SetVertexColor(0.2, 0.2, 0.2, 0.4); rogueSec:SetAlpha(0.4); iconRogue.tex:SetVertexColor(0.2, 0.2, 0.2) end

    self.currentHoveredClass = nil
    
    if dist < 12 then return end
    if angle >= 30 and angle <= 150 then
        if pOK then self.currentHoveredClass = "PALA"; palaSec:SetAlpha(1.0) end
    elseif angle > 150 or angle <= -90 then
        if hOK then self.currentHoveredClass = "HUNT"; huntSec:SetAlpha(1.0) end
    else
        if rOK then self.currentHoveredClass = "ROGUE"; rogueSec:SetAlpha(1.0) end
    end
end)


-- [[ GRID SYSTÉM A AUTO-VEĽKOSŤ ]]
SausageThreatMainFrame_UpdateGrid = function()
    if InCombatLockdown() or not SausageThreatDB then return end 

    local boxWidth = SausageThreatDB.btnWidth
    local boxHeight = SausageThreatDB.btnHeight
    local maxCols = SausageThreatDB.cols
    local spacing = SausageThreatDB.spacing

    if SausageThreatDB.hideBorder then
        MainFrame:SetBackdrop({ bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile=nil, tile=true, tileSize=16, edgeSize=0, insets={left=3,right=3,top=3,bottom=3} })
    else
        MainFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
    end

    if SausageThreatDB.hideBackground then MainFrame:SetBackdropColor(0,0,0,0) else MainFrame:SetBackdropColor(1, 1, 1, 1) end
    if SausageThreatDB.hideHeader then header:Hide(); title:Hide() else header:Show(); title:Show() end

    ContentFrame:ClearAllPoints()
    ContentFrame:SetPoint("TOP", 0, -35)

    local row, col = 0, 0
    local units = {}

    if isTestMode then for i=1, 25 do units[#units + 1] = "player" end
    else
        if IsInRaid() then for i=1, GetNumRaidMembers() do units[#units + 1] = "raid"..i end
        elseif GetNumPartyMembers() > 0 then units[#units + 1] = "player"; for i=1, GetNumPartyMembers() do units[#units + 1] = "party"..i end
        else units[#units + 1] = "player" end
    end

    local activeCount = 0
    local isSpecial = IsRaidLeader() or IsRaidOfficer()
    local showList = isSpecial and SausageThreatDB.showListMaster or nil
    if not showList or next(showList) == nil then showList = (isPaladin and SausageThreatDB.showListPala) or (isHunter and SausageThreatDB.showListHunt) or (isRogue and SausageThreatDB.showListRogue) end
    showList = showList or {}

    for i = 1, 40 do
        local btn = unitButtons[i]
        local unit = units[i]
        local unitName = nil
        if isTestMode and i <= 25 then unitName = "TestPlayer " .. i elseif unit then unitName = UnitName(unit) end

        local isExplicitlyHidden = (unitName and showList and showList[unitName] == false)
        if unitName and (isTestMode or (unit and not isExplicitlyHidden)) then
            btn:SetAttribute("unit", isTestMode and nil or unit)
            btn.targetUnit = isTestMode and "player" or unit
            btn.unitName = unitName
            btn:SetSize(boxWidth, boxHeight)
            btn:SetFrameLevel(MainFrame:GetFrameLevel() + 5)
            btn.text:SetText(string.sub(unitName, 1, 9))
            if SausageThreatDB.hideNames then btn.text:Hide() else btn.text:Show() end
            btn.threatText:SetText("0%")
            if SausageThreatDB.hideThreat then btn.threatText:Hide() else btn.threatText:Show() end
            
            -- Dynamické centrovanie zvyšného textu
            btn.text:ClearAllPoints(); btn.threatText:ClearAllPoints()
            if SausageThreatDB.hideThreat and not SausageThreatDB.hideNames then
                btn.text:SetPoint("CENTER", 0, 0)
            elseif SausageThreatDB.hideNames and not SausageThreatDB.hideThreat then
                btn.threatText:SetPoint("CENTER", 0, 0)
            else
                btn.text:SetPoint("TOP", 0, -4)
                btn.threatText:SetPoint("BOTTOM", 0, 4)
            end
            
            btn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.9)
            btn.border:SetBackdropBorderColor(1, 1, 1, 0.5)
            btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", col * (boxWidth + spacing), -row * (boxHeight + spacing))
            btn:Show(); btn:SetAlpha(1)

            activeCount = activeCount + 1
            col = col + 1; if col >= maxCols then col = 0; row = row + 1 end
        else
            btn:SetAttribute("unit", nil); btn.targetUnit = nil; btn:Hide()
        end
    end

    if activeCount == 0 then activeCount = 1 end
    local finalRows = math.ceil(activeCount / maxCols); local finalCols = math.min(activeCount, maxCols)
    local newWidth = (finalCols * boxWidth) + ((finalCols - 1) * spacing) + 30
    local headerSize = (SausageThreatDB.hideHeader and 20 or 45); local rlSize = CoordFrame:IsShown() and 15 or 0
    local newHeight = (finalRows * boxHeight) + ((finalRows - 1) * spacing) + headerSize + rlSize + 15
    
    local anchor = SausageThreatDB.anchor or "TOP"
    MainFrame:ClearAllPoints(); MainFrame:SetSize(newWidth, newHeight)
    local screenX = SausageThreatDB.frameX or (UIParent:GetWidth()/2); local screenY = SausageThreatDB.frameY or (UIParent:GetHeight()/2)
    MainFrame:SetPoint(anchor, UIParent, "BOTTOMLEFT", screenX, screenY)
    
    ContentFrame:ClearAllPoints()
    local topOffset = (SausageThreatDB.hideHeader and -15 or -35); if CoordFrame:IsShown() then topOffset = topOffset - 15 end
    if anchor == "LEFT" then ContentFrame:SetPoint("LEFT", 15, 0) elseif anchor == "RIGHT" then ContentFrame:SetPoint("RIGHT", -15, 0) elseif anchor == "BOTTOM" then ContentFrame:SetPoint("BOTTOM", 0, 15) else ContentFrame:SetPoint("TOP", 0, topOffset) end
    ContentFrame:SetSize(newWidth - 30, (finalRows * boxHeight) + (finalRows * spacing))
end

local function CreateGridButtons()
    for i = 1, 40 do
        local btn = CreateFrame("Button", "SausageThreatBtn"..i, ContentFrame, "SecureActionButtonTemplate")
        
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        btn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.9)
        
        btn.border = CreateFrame("Frame", nil, btn)
        btn.border:SetAllPoints()
        btn.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn.border:SetBackdropBorderColor(0, 0, 0, 1)

        -- Decentný vnútorný okraj, aby boxy nepôsobili "prázdne"
        btn.innerBorder = CreateFrame("Frame", nil, btn)
        btn.innerBorder:SetPoint("TOPLEFT", 1, -1)
        btn.innerBorder:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.innerBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn.innerBorder:SetBackdropBorderColor(1, 1, 1, 0.05)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("TOP", 0, -4); btn.text:SetTextColor(1, 1, 1, 1); btn.text:SetShadowColor(0, 0, 0, 1); btn.text:SetShadowOffset(1, -1)
        
        btn.threatText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.threatText:SetPoint("BOTTOM", 0, 4); btn.threatText:SetTextColor(1, 1, 1, 1); btn.threatText:SetShadowColor(0, 0, 0, 1); btn.threatText:SetShadowOffset(1, -1)

        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        btn.icon:SetSize(20, 20); btn.icon:SetPoint("RIGHT", -2, 0); btn.icon:Hide()

        -- Odpočítavanie zostávajúceho času aktívneho buffu (Salva/MD/ToT)
        btn.buffTimer = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.buffTimer:SetPoint("BOTTOMRIGHT", -2, 3)
        btn.buffTimer:SetShadowColor(0, 0, 0, 1)
        btn.buffTimer:SetShadowOffset(1, -1)
        btn.buffTimer:Hide()

        -- Čistý pulzujúci overlay efekt pre príkaz
        btn.pingHighlight = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        btn.pingHighlight:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        btn.pingHighlight:SetAllPoints()
        btn.pingHighlight:SetBlendMode("ADD")
        btn.pingHighlight:Hide()
        
        -- Success Glow for cast feedback
        btn.successGlow = btn.border:CreateTexture(nil, "OVERLAY", nil, 7)
        btn.successGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        btn.successGlow:SetAllPoints()
        btn.successGlow:SetBlendMode("ADD")
        btn.successGlow:SetVertexColor(1, 1, 1, 1)
        btn.successGlow:Hide()
        btn.successGlowTime = 0

        -- Nová vizuálna IKONA uprostred pingu
        btn.pingIcon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        btn.pingIcon:SetSize(30, 30)
        btn.pingIcon:SetPoint("CENTER")
        btn.pingIcon:SetBlendMode("ADD")
        btn.pingIcon:Hide()

        -- THREAT VÝKRIČNÍKY (Na krídlach tlačidla podľa nákresu)
        btn.warnLeft = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        btn.warnLeft:SetPoint("LEFT", 5, 0)
        btn.warnLeft:SetText("!!")
        btn.warnLeft:SetTextColor(1, 0, 0)
        btn.warnLeft:Hide()

        btn.warnRight = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        btn.warnRight:SetPoint("RIGHT", -5, 0)
        btn.warnRight:SetText("!!")
        btn.warnRight:SetTextColor(1, 0, 0)
        btn.warnRight:Hide()
        
        btn.roleIcon = btn:CreateTexture(nil, "OVERLAY", nil, 6)
        btn.roleIcon:SetSize(14, 14)
        btn.roleIcon:SetPoint("TOPLEFT", 1, -1)
        btn.roleIcon:Hide()

        btn:SetAttribute("type1", "spell"); btn:SetAttribute("spell1", mySpellName or "")
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        btn:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and IsShiftKeyDown() then
                local uName = self.unitName or btn.text:GetText()
                if uName and (uName == UnitName("player") or IsRaidLeader() or IsRaidOfficer()) then
                    local curRole = GetUnitRoleFromName(uName)
                    local newRole = (curRole == "DPS" and "TANK") or (curRole == "TANK" and "HEALER") or "DPS"
                    SausageThreatDB.assignedRoles = SausageThreatDB.assignedRoles or {}
                    SausageThreatDB.assignedRoles[uName] = newRole
                    SendComm("SET_ROLE:"..uName..":"..newRole)
                    if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
                    print("|cFF00CCFF[SausageThreat]|r Role for " .. uName .. " changed to " .. newRole)
                end
                return
            end

            if button == "RightButton" then
                if IsRaidLeader() or IsRaidOfficer() or not IsInRaid() then
                    local targetName = self.unitName or UnitName(self.targetUnit)
                    local targetClass = isTestMode and "WARRIOR" or select(2, UnitClass(self.targetUnit))
                    if targetName then
                        RadialMenu.targetName = targetName
                        RadialMenu.currentHoveredClass = nil
                        RadialMenu.cancelled = false
                        RadialMenu.hubBg:SetVertexColor(targetClass and RAID_CLASS_COLORS[targetClass] and RAID_CLASS_COLORS[targetClass].r or 0.5, targetClass and RAID_CLASS_COLORS[targetClass] and RAID_CLASS_COLORS[targetClass].g or 0.5, targetClass and RAID_CLASS_COLORS[targetClass] and RAID_CLASS_COLORS[targetClass].b or 0.5, 0.9)
                        local x, y = GetCursorPosition(); local scale = UIParent:GetEffectiveScale()
                        RadialMenu:ClearAllPoints(); RadialMenu:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/scale, y/scale); RadialMenu:Show()
                    end
                end
            end
        end)

        btn:SetScript("OnMouseUp", function(self, button)
            -- Handled directly by RadialMenu now
        end)

        btn:HookScript("OnClick", function(self, button)
            if button == "LeftButton" then local targetName = self.unitName or UnitName(self.targetUnit); if targetName then SendComm("PRE_CAST:"..targetName); focusTarget, focusTargetClass = nil, nil end end
        end)
        
        -- Zabráni ElvUI FrameGlow systému spracovávať naše buttony ako unit framy
        btn.noMouseoverHighlight = true

        btn:Hide(); unitButtons[i] = btn
    end
end

-- Rozlíšenie zdroja threatu: zamknutý target má prednosť pred aktuálnym targetom
local function ResolveThreatSource()
    if lockedThreatGUID then
        -- Skontroluj boss framy (najčastejší prípad v raidoch)
        for i = 1, 4 do
            local u = "boss" .. i
            if UnitExists(u) and UnitGUID(u) == lockedThreatGUID then return u end
        end
        -- Záloha: aktuálny target alebo targettarget
        if UnitExists("target") and UnitGUID("target") == lockedThreatGUID then return "target" end
        if UnitExists("targettarget") and UnitGUID("targettarget") == lockedThreatGUID then return "targettarget" end
        -- Boss nie je viditeľný (mŕtvy, fázovaný) - vráť nil
        return nil
    end
    -- Štandardné správanie bez zámku
    return UnitExists("target") and "target" or (UnitExists("targettarget") and "targettarget" or nil)
end

UpdateCombatGrid = function(dt)
    if not MainFrame:IsShown() then return end

    local pulse = (math.sin(GetTime() * 5) + 1) / 2
    local inFocusMode = (focusTarget ~= nil and focusTimer > 0)
    if focusTimer > 0 then focusTimer = focusTimer - dt else focusTargetClass = nil end

    -- Periodická aktualizácia CoordFrame odpočítavania cooldownov (každú 1s)
    if CoordFrame:IsShown() then
        coordRefreshTimer = coordRefreshTimer + dt
        if coordRefreshTimer >= 1 then
            coordRefreshTimer = 0
            SortPaladins()
        end
    end

    for i = 1, 40 do
        local btn = unitButtons[i]
        if btn:IsShown() then
            local unit = btn.targetUnit
            local unitName = btn.unitName or btn.text:GetText()
            
            local inRange = 1
            local isOffline = not isTestMode and unit and not UnitIsConnected(unit)
            
            if isOffline then
                btn:SetAlpha(0.2)
                btn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.9)
                btn.text:SetTextColor(0.5, 0.5, 0.5, 1)
                btn.threatText:SetTextColor(0.5, 0.5, 0.5, 1)
                btn.threatText:SetText("|cFF888888OFF|r")
                btn.warnLeft:Hide(); btn.warnRight:Hide()
                btn.pingHighlight:Hide(); btn.pingIcon:Hide(); btn.icon:Hide()
            else
                if not isTestMode and unit and UnitExists(unit) then
                    if mySpellName then inRange = IsSpellInRange(mySpellName, unit) else inRange = UnitInRange(unit) and 1 or 0 end
                    local _, clas = UnitClass(unit)
                    if clas and RAID_CLASS_COLORS[clas] then
                        btn.text:SetTextColor(RAID_CLASS_COLORS[clas].r, RAID_CLASS_COLORS[clas].g, RAID_CLASS_COLORS[clas].b, 1)
                        btn.threatText:SetTextColor(RAID_CLASS_COLORS[clas].r, RAID_CLASS_COLORS[clas].g, RAID_CLASS_COLORS[clas].b, 1)
                    end
                else
                    btn.text:SetTextColor(0, 0, 0, 1); btn.threatText:SetTextColor(0, 0, 0, 1)
                end
                
                if inRange == 0 then btn:SetAlpha(0.4) else btn:SetAlpha(1.0) end

                local threatPct = 0
                if isTestMode then
                    threatPct = (i * 7) % 135
                elseif unit and UnitExists(unit) then
                    -- Použi zamknutý target (ak existuje), inak fallback na aktuálny target
                    local threatSource = ResolveThreatSource()
                    if threatSource then
                        local _, _, pct = UnitDetailedThreatSituation(unit, threatSource)
                        threatPct = pct or 0
                    end
                end
                btn.threatText:SetText(string.format("%d%%", threatPct))

                local role = GetUnitRoleFromName(unitName)
                if unit or isTestMode then
                    if role == "TANK" then
                        btn.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
                        btn.roleIcon:SetTexCoord(0, 0.26171875, 0.26171875, 0.5234375)
                        btn.roleIcon:Show()
                    elseif role == "HEALER" then
                        btn.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
                        btn.roleIcon:SetTexCoord(0.26171875, 0.5234375, 0.0, 0.26171875)
                        btn.roleIcon:Show()
                    else
                        btn.roleIcon:Hide()
                    end

                    local threshold = (SausageThreatDB and SausageThreatDB.threatThresholdMelee) or 90
            if not isTestMode and unit then local _, class = UnitClass(unit); threshold = (class == "MAGE" or class == "WARLOCK" or class == "PRIEST") and ((SausageThreatDB and SausageThreatDB.threatThresholdCaster) or 110) or threshold end
            
            local hasSalva, activeIcon, buffType = false, nil, nil
            local now = GetTime()

            -- Kontrola trackerom (Combat Log)
            if unitName and activeBuffsOnTarget[unitName] then
                for bType, data in pairs(activeBuffsOnTarget[unitName]) do
                    if now < data.expiry then
                        hasSalva = true
                        activeIcon = data.icon
                        buffType = bType
                        break
                    end
                end
            end

            if isTestMode and (i == 3 or i == 7) then 
                hasSalva = true; activeIcon = "Interface\\Icons\\Spell_Holy_SealOfSalvation"; buffType = "PALA"
            elseif unit and UnitExists(unit) and not hasSalva then -- Ak sme este nenasli cez tracker, checkneme UnitBuff
                local s, _, iconS = UnitBuff(unit, SALVA_NAME)
                local m, _, iconM, _, _, _, _, uCasterM = UnitBuff(unit, MISDIRECT_NAME)
                local t, _, iconT, _, _, _, _, uCasterT = UnitBuff(unit, TRICKS_NAME)
                
                if m and uCasterM and UnitIsUnit(uCasterM, unit) then m = nil end
                if t and uCasterT and UnitIsUnit(uCasterT, unit) then t = nil end
                
                if s then hasSalva = true; activeIcon = iconS; buffType = "PALA" 
                elseif m then hasSalva = true; activeIcon = iconM; buffType = "HUNT" 
                elseif t then hasSalva = true; activeIcon = iconT; buffType = "ROGUE" end
            end
            if activeIcon then btn.icon:SetTexture(activeIcon); btn.icon:Show() else btn.icon:Hide() end

            -- Zobrazenie odpočítavania zostávajúceho času buffu
            local buffExpiry = unitName and activeBuffsOnTarget[unitName] and activeBuffsOnTarget[unitName][buffType] and activeBuffsOnTarget[unitName][buffType].expiry
            if hasSalva and buffExpiry then
                local remaining = math.ceil(buffExpiry - now)
                if remaining > 0 then
                    btn.buffTimer:SetText(remaining .. "s")
                    if remaining <= 3 then
                        btn.buffTimer:SetTextColor(1, 0.2, 0.2, 1)
                    else
                        btn.buffTimer:SetTextColor(1, 1, 1, 1)
                    end
                    btn.buffTimer:Show()
                else
                    btn.buffTimer:Hide()
                end
            else
                btn.buffTimer:Hide()
            end

            -- Vyhodnotenie farieb pre PING pulz
            if inFocusMode then
                local isThisFocus = (unitName and focusTarget and string.lower(unitName) == string.lower(focusTarget))
                if isThisFocus then
                    local colorKey = focusTargetClass
                    if isTestMode then
                        colorKey = (debugClass == "HUNTER" and "HUNT" or debugClass == "ROGUE" and "ROGUE" or "PALA")
                    end
                    
                    local r, g, b = 1, 1, 1
                    if colorKey == "PALA" then r, g, b = 0.96, 0.55, 0.73
                    elseif colorKey == "HUNT" then r, g, b = 0.67, 0.83, 0.45
                    elseif colorKey == "ROGUE" then r, g, b = 1.00, 0.96, 0.41 end

                    btn.bg:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, 0.9)
                    btn.pingHighlight:SetVertexColor(r, g, b, 0.4 + (pulse * 0.6))
                    btn.pingHighlight:Show()
                    
                    -- Zobrazenie PING ikony (Salva/MD/Tricks)
                    local iconPath = "Interface\\Icons\\Spell_Holy_SealOfSalvation"
                    if colorKey == "HUNT" then iconPath = "Interface\\Icons\\Ability_Hunter_Misdirection"
                    elseif colorKey == "ROGUE" then iconPath = "Interface\\Icons\\Ability_Rogue_TricksOftheTrade" end
                    btn.pingIcon:SetTexture(iconPath)
                    btn.pingIcon:SetAlpha(0.3 + (pulse * 0.7))
                    btn.pingIcon:Show()
                else
                    btn.bg:SetVertexColor(0.1, 0.1, 0.1, 0.5)
                    btn.pingHighlight:Hide()
                    btn.pingIcon:Hide()
                end
            else
                btn.pingHighlight:Hide()
                btn.pingIcon:Hide()
                if hasSalva then
                    -- Aktívny buff: Jemné farebné pulzovanie podľa spellu
                    local r, g, b = 1, 1, 1
                    if buffType == "PALA" then r, g, b = 0.96, 0.55, 0.73
                    elseif buffType == "HUNT" then r, g, b = 0.67, 0.83, 0.45
                    elseif buffType == "ROGUE" then r, g, b = 1.00, 0.96, 0.41 end
                    
                    btn.bg:SetVertexColor(r * (0.15 + pulse * 0.15), g * (0.15 + pulse * 0.15), b * (0.15 + pulse * 0.15), 0.9)
                    btn.pingHighlight:SetVertexColor(r, g, b, 0.1 + (pulse * 0.2))
                    btn.pingHighlight:Show()
                elseif threatPct >= threshold then 
                    local isTank = (role == "TANK")
                    if isTank then
                        -- TANK LOGIC: Green when aggro, Blue when lost
                        local status = UnitDetailedThreatSituation(unit, "target") or 0
                        if status >= 2 then
                            -- Secure Aggro
                            btn.bg:SetVertexColor(0, 0.8, 0, 0.9) -- Green
                            btn.warnLeft:Hide(); btn.warnRight:Hide()
                        else
                            -- Lost Aggro: BLUE ALERT
                            btn.bg:SetVertexColor(0, 0.5, 1, 0.9) -- Blue/Cyan
                            btn.text:SetTextColor(1, 1, 1, 1)
                            btn.threatText:SetTextColor(1, 1, 1, 1)
                            btn.warnLeft:SetText("??"); btn.warnRight:SetText("??")
                            btn.warnLeft:SetTextColor(0, 0.8, 1)
                            btn.warnRight:SetTextColor(0, 0.8, 1)
                            local invPulse = 1 - pulse
                            btn.warnLeft:SetAlpha(0.2 + (invPulse * 0.8))
                            btn.warnRight:SetAlpha(0.2 + (invPulse * 0.8))
                            btn.warnLeft:Show(); btn.warnRight:Show()
                        end
                        btn.threatSoundWarned = false -- No sound for tanks
                    else
                        -- DPS/HEAL HIGH THREAT: Panic indicator !!
                        btn.bg:SetVertexColor(1, 0, 0, 0.9)
                        btn.text:SetTextColor(1, 1, 1, 1)
                        btn.threatText:SetTextColor(1, 1, 1, 1)
                        btn.warnLeft:SetText("!!"); btn.warnRight:SetText("!!")
                        btn.warnLeft:SetTextColor(1, 0, 0)
                        btn.warnRight:SetTextColor(1, 0, 0)
                        local invPulse = 1 - pulse
                        btn.warnLeft:SetAlpha(0.2 + (invPulse * 0.8))
                        btn.warnRight:SetAlpha(0.2 + (invPulse * 0.8))
                        btn.warnLeft:Show(); btn.warnRight:Show()
                        
                        -- ZAHRAJ ZVUK (LEN PRE RL / TANKOV), ak prave prekrocil threshold
                        local myRole = GetUnitRoleFromName(UnitName("player"))
                        if IsEligibleForThreatSound() and myRole ~= "TANK" and not btn.threatSoundWarned and SausageThreatDB.enableSound then
                            local now = GetTime()
                            if now - globalThreatSoundTime > 3 then
                                local isBoss = (UnitLevel("target") == -1) or (UnitClassification("target") == "worldboss")
                                if not SausageThreatDB.bossOnlyAlert or isBoss then
                                    PlaySoundFile(THREAT_SOUND, "Master")
                                    globalThreatSoundTime = now
                                end
                            end
                            btn.threatSoundWarned = true
                        end
                    end
                elseif threatPct > 0 then 
                    btn.warnLeft:Hide(); btn.warnRight:Hide()
                    btn.threatSoundWarned = false
                    local fade = 1 - (threatPct / threshold)
                    btn.bg:SetVertexColor(1, fade, fade, 0.9)
                else 
                    btn.warnLeft:Hide(); btn.warnRight:Hide()
                    btn.threatSoundWarned = false
                    btn.bg:SetVertexColor(1, 1, 1, 0.9) 
                end
            end

                -- Success Glow Animation
                if btn.successGlowTime > 0 then
                    btn.successGlowTime = btn.successGlowTime - dt
                    btn.successGlow:SetAlpha(math.min(1, btn.successGlowTime / 0.25))
                    btn.successGlow:Show()
                else
                    btn.successGlow:Hide()
                end
            end
        end
    end
    end
end

-- [[ UPDATE / GITHUB CUSTOM FRAME ]]
local GitFrame = CreateFrame("Frame", "SausageThreatGitFrame", UIParent)
GitFrame:SetSize(320, 130)
GitFrame:SetPoint("CENTER")
GitFrame:SetFrameStrata("TOOLTIP")
GitFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
GitFrame:SetBackdropColor(1, 1, 1, 1)
tinsert(UISpecialFrames, "SausageThreatGitFrame")
GitFrame:Hide()

local gitHeader = GitFrame:CreateTexture(nil, "OVERLAY")
gitHeader:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
gitHeader:SetSize(250, 64)
gitHeader:SetPoint("TOP", 0, 12)
local gitTitle = GitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gitTitle:SetPoint("TOP", gitHeader, "TOP", 0, -14)
gitTitle:SetText("UPDATE LINK")
local gitClose = CreateFrame("Button", nil, GitFrame, "UIPanelCloseButton")
gitClose:SetPoint("TOPRIGHT", -8, -8)
local gitDesc = GitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gitDesc:SetPoint("TOP", 0, -35)
gitDesc:SetText("Press Ctrl+C to copy the GitHub link:")
local gitEditBox = CreateFrame("EditBox", nil, GitFrame, "InputBoxTemplate")
gitEditBox:SetSize(260, 20)
gitEditBox:SetPoint("TOP", gitDesc, "BOTTOM", 0, -15)
gitEditBox:SetAutoFocus(true)
local GITHUB_LINK = "https://github.com/NikowskyWow/SausageThreat/releases"

gitEditBox:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= GITHUB_LINK then self:SetText(GITHUB_LINK); self:HighlightText() end
end)
gitEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); GitFrame:Hide() end)
GitFrame:SetScript("OnShow", function() 
    GitFrame:Raise()
    gitEditBox:SetText(GITHUB_LINK); gitEditBox:SetFocus(); gitEditBox:HighlightText() 
end)

-- [[ NASTAVENIA (SETTINGS FRAME) ]]
local SettingsFrame = CreateFrame("Frame", "SausageThreatSettings", UIParent)
SettingsFrame:SetSize(480, 650)
SettingsFrame:SetPoint("CENTER")
SettingsFrame:SetFrameStrata("DIALOG")
SettingsFrame:SetMovable(true)
SettingsFrame:EnableMouse(true)
SettingsFrame:RegisterForDrag("LeftButton")
SettingsFrame:SetScript("OnDragStart", SettingsFrame.StartMoving)
SettingsFrame:SetScript("OnDragStop", SettingsFrame.StopMovingOrSizing)
SettingsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
SettingsFrame:SetBackdropColor(1, 1, 1, 1)
tinsert(UISpecialFrames, "SausageThreatSettings")
SettingsFrame:Hide()

local setHeader = SettingsFrame:CreateTexture(nil, "OVERLAY")
setHeader:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
setHeader:SetSize(256, 64)
setHeader:SetPoint("TOP", 0, 12)
local setTitle = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
setTitle:SetPoint("TOP", setHeader, "TOP", 0, -14)
setTitle:SetText("|cffff8800Sausage|r Threat")
local setClose = CreateFrame("Button", nil, SettingsFrame, "UIPanelCloseButton")
setClose:SetPoint("TOPRIGHT", -8, -8)

local panelContainer = CreateFrame("Frame", nil, SettingsFrame)
panelContainer:SetPoint("TOPLEFT", 0, -65)
panelContainer:SetPoint("BOTTOMRIGHT", 0, 75)
panelContainer:SetFrameLevel(SettingsFrame:GetFrameLevel() + 5)
local generalPanel = CreateFrame("Frame", nil, panelContainer); generalPanel:SetAllPoints()
local listPanel = CreateFrame("Frame", nil, panelContainer); listPanel:SetAllPoints()

PanelTemplates_SetNumTabs(SettingsFrame, 5)

local function CreateTab(id, text, prevTab)
    local tabName = SettingsFrame:GetName() .. "Tab" .. id
    local btn = CreateFrame("Button", tabName, SettingsFrame, "CharacterFrameTabButtonTemplate")
    btn:SetID(id)
    btn:SetText(text)
    if prevTab then
        btn:SetPoint("LEFT", prevTab, "RIGHT", -15, 0)
    else
        btn:SetPoint("BOTTOMLEFT", 15, -28)
    end
    _G[btn:GetName()] = btn

    btn:SetScript("OnClick", function()
        currentTab = id
        PanelTemplates_SetTab(SettingsFrame, id)
        SettingsFrame.RefreshUI()
    end)
    return btn
end

local tab1 = CreateTab(1, "General", nil)
local tab2 = CreateTab(2, "Paladins", tab1)
local tab3 = CreateTab(3, "Hunters", tab2)
local tab4 = CreateTab(4, "Rogues", tab3)
local tab5 = CreateTab(5, "RL View", tab4)

PanelTemplates_SetTab(SettingsFrame, 1)

local ignoreLabel = listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ignoreLabel:SetPoint("TOPLEFT", 15, -5); ignoreLabel:SetText("Players Visibility (Show List)")

local SausageThreatSettings_ReadOnlyLabel = listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
SausageThreatSettings_ReadOnlyLabel:SetPoint("TOP", listPanel, "TOP", 0, -5)
SausageThreatSettings_ReadOnlyLabel:SetText("|cFFFF0000Nastavenia riadené Masterom / Raid Leadrom|r")
SausageThreatSettings_ReadOnlyLabel:Hide()

local btnShowAll = CreateFrame("Button", nil, listPanel, "UIPanelButtonTemplate")
local btnHideAll = CreateFrame("Button", nil, listPanel, "UIPanelButtonTemplate")

local function UpdateSettingsTabsVisibility()
    local isSpecial = IsRaidLeader() or IsRaidOfficer()
    local inRaid = IsInRaid()
    local tabs = { 
        _G[SettingsFrame:GetName() .. "Tab1"], 
        _G[SettingsFrame:GetName() .. "Tab2"], 
        _G[SettingsFrame:GetName() .. "Tab3"], 
        _G[SettingsFrame:GetName() .. "Tab4"], 
        _G[SettingsFrame:GetName() .. "Tab5"] 
    }
    local showTab = {true, false, false, false, false}
    
    if isSpecial then
        showTab[2], showTab[3], showTab[4], showTab[5] = true, true, true, true
    else
        if isPaladin then showTab[2] = true end
        if isHunter then showTab[3] = true end
        if isRogue then showTab[4] = true end
        if not (isPaladin or isHunter or isRogue) then
            showTab[5] = true
        end
    end
    
    local prevTab = nil
    for i = 1, 5 do
        if showTab[i] then
            tabs[i]:ClearAllPoints()
            if prevTab then
                tabs[i]:SetPoint("LEFT", prevTab, "RIGHT", -15, 0)
            else
                tabs[i]:SetPoint("BOTTOMLEFT", 15, -28)
            end
            tabs[i]:Show()
            prevTab = tabs[i]
        else
            tabs[i]:Hide()
        end
    end
    
    if not showTab[currentTab] then
        currentTab = 1
    end
    PanelTemplates_SetTab(SettingsFrame, currentTab)

    if inRaid and not isSpecial then
        SausageThreatSettings_ReadOnlyLabel:Show()
        ignoreLabel:Hide()
        btnShowAll:Disable()
        btnHideAll:Disable()
    else
        SausageThreatSettings_ReadOnlyLabel:Hide()
        ignoreLabel:Show()
        btnShowAll:Enable()
        btnHideAll:Enable()
    end
end

local cbAutoHide = CreateFrame("CheckButton", nil, generalPanel, "OptionsBaseCheckButtonTemplate")
cbAutoHide:SetPoint("TOPLEFT", 20, 0)
cbAutoHide:SetScript("OnClick", function(self)
    if SausageThreatDB then 
        SausageThreatDB.autoHide = self:GetChecked()
        if not inCombat and SausageThreatDB.autoHide then MainFrame:Hide() elseif inCombat then MainFrame:Show() end
    end
end)
local cbAutoHideText = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cbAutoHideText:SetPoint("LEFT", cbAutoHide, "RIGHT", 5, 0); cbAutoHideText:SetText("Auto-hide out of combat")

local function CreateGridSlider(name, text, minV, maxV, x, y, dbKey)
    local slider = CreateFrame("Slider", "SausageThreatSlider"..name, generalPanel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(1)
    _G[slider:GetName().."Low"]:SetText(minV)
    _G[slider:GetName().."High"]:SetText(maxV)
    _G[slider:GetName().."Text"]:SetText(text)
    local valText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOP", slider, "BOTTOM", 0, 3)
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value); valText:SetText(value)
        if SausageThreatDB then SausageThreatDB[dbKey] = value; if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end end
    end)
    return slider
end

local sldCols = CreateGridSlider("Cols", "Columns", 1, 8, 20, -60, "cols")
local sldWidth = CreateGridSlider("Width", "Button Width", 50, 150, 20, -110, "btnWidth")
local sldHeight = CreateGridSlider("Height", "Button Height", 20, 60, 20, -160, "btnHeight")
local sldSpacing = CreateGridSlider("Spacing", "Spacing", 0, 20, 20, -210, "spacing")

local col2X = 220
local function CreateCB(name, text, y, dbKey)
    local cb = CreateFrame("CheckButton", nil, generalPanel, "OptionsBaseCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", col2X, y)
    cb:SetScript("OnClick", function(self)
        if SausageThreatDB then SausageThreatDB[dbKey] = self:GetChecked(); if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end end
    end)
    local t = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 5, 0); t:SetText(text)
    return cb
end
local cbHideBorder = CreateCB("Border", "Hide Main Border", -60, "hideBorder")
local cbHideHeader = CreateCB("Header", "Hide Header", -90, "hideHeader")
local cbHideNames = CreateCB("Names", "Hide Names", -120, "hideNames")
local cbHideThreat = CreateCB("Threat", "Hide Threat %", -150, "hideThreat")
local cbHideBackground = CreateCB("BG", "Hide Main BG", -180, "hideBackground")

-- Removed cbShowRoles as per user request

local sldLockout = CreateGridSlider("Lockout", "Cmd Debounce Lockout (s)", 1, 10, col2X, -250, "cmdLockout")

-- Prahové hodnoty threatu - vlastná sekcia dole cez celú šírku (oddelená od ostatných kontroliek)
local threshSep = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
threshSep:SetPoint("TOPLEFT", 20, -410)
threshSep:SetText("Alert Thresholds:")

local sldThreshMelee = CreateGridSlider("ThreshMelee", "Threat Alert % (Melee)", 70, 130, 20, -435, "threatThresholdMelee")
local sldThreshCaster = CreateGridSlider("ThreshCaster", "Threat Alert % (Caster)", 70, 130, 255, -435, "threatThresholdCaster")

local anchorLabel = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchorLabel:SetPoint("TOPLEFT", 20, -260); anchorLabel:SetText("Growth Direction (Anchor):")

local function CreateAnchorBtn(name, point, x, y)
    local btn = CreateFrame("Button", nil, generalPanel, "UIPanelButtonTemplate")
    btn:SetSize(60, 22); btn:SetPoint("TOPLEFT", x, y); btn:SetText(name)
    btn:SetScript("OnClick", function()
        SausageThreatDB.anchor = point
        local px, py
        if point == "TOP" then px, py = MainFrame:GetLeft() + MainFrame:GetWidth()/2, MainFrame:GetTop()
        elseif point == "BOTTOM" then px, py = MainFrame:GetLeft() + MainFrame:GetWidth()/2, MainFrame:GetBottom()
        elseif point == "LEFT" then px, py = MainFrame:GetLeft(), MainFrame:GetTop() - MainFrame:GetHeight()/2
        elseif point == "RIGHT" then px, py = MainFrame:GetRight(), MainFrame:GetTop() - MainFrame:GetHeight()/2 end
        if px and py then SausageThreatDB.frameX, SausageThreatDB.frameY = px, py end
        if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
    end)
end
CreateAnchorBtn("Down", "TOP", 20, -280); CreateAnchorBtn("Up", "BOTTOM", 85, -280)
CreateAnchorBtn("Right", "LEFT", 150, -280); CreateAnchorBtn("Left", "RIGHT", 215, -280)

local rosterCache = {}
local function MassSyncCheck(state)
    local listKey = (currentTab == 2 and "showListPala") or (currentTab == 3 and "showListHunt") or (currentTab == 4 and "showListRogue") or (currentTab == 5 and "showListMaster")
    local classCode = (currentTab == 2 and "PALA") or (currentTab == 3 and "HUNT") or (currentTab == 4 and "ROGUE") or (currentTab == 5 and "MASTER")
    if not listKey then return end
    
    for _, name in ipairs(rosterCache) do SausageThreatDB[listKey][name] = state end
    
    if IsInGroup() then
        local csv = ""; for name, shown in pairs(SausageThreatDB[listKey]) do if shown then csv = csv .. name .. "," end end
        SendComm("SYNC_LIST:"..classCode..":"..csv)
    end
    UpdateIgnoreScrollFrame(); if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
end

btnShowAll:SetSize(80, 20); btnShowAll:SetPoint("TOPRIGHT", -105, -3); btnShowAll:SetText("Show All")
btnShowAll:SetScript("OnClick", function() MassSyncCheck(true) end)

btnHideAll:SetSize(80, 20); btnHideAll:SetPoint("TOPRIGHT", -15, -3); btnHideAll:SetText("Hide All")
btnHideAll:SetScript("OnClick", function() MassSyncCheck(false) end)

local rosterFrame = CreateFrame("Frame", nil, listPanel)
rosterFrame:SetSize(410, 330); rosterFrame:SetPoint("TOPLEFT", 15, -25)
rosterFrame:SetBackdrop({ 
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background", 
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", 
    tile=true, tileSize=16, edgeSize=12, 
    insets={left=3,right=3,top=3,bottom=3} 
})
rosterFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

local ignoreListScroll = CreateFrame("ScrollFrame", "SausageThreatIgnoreScroll", rosterFrame, "FauxScrollFrameTemplate")
ignoreListScroll:SetPoint("TOPLEFT", 5, -5); ignoreListScroll:SetPoint("BOTTOMRIGHT", -25, 5)

local ignoreRowBtns = {}
for i = 1, 15 do
    local row = CreateFrame("CheckButton", nil, rosterFrame, "UICheckButtonTemplate")
    row:SetSize(20, 20)
    if i == 1 then row:SetPoint("TOPLEFT", 10, -10) else row:SetPoint("TOPLEFT", ignoreRowBtns[i-1], "BOTTOMLEFT", 0, 0) end
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row, "RIGHT", 5, 0)
    row:SetScript("OnClick", function(self)
        if not (not IsInRaid() or IsRaidLeader() or IsRaidOfficer()) then self:SetChecked(not self:GetChecked()); return end
        if not self.playerName then return end
        local listKey = (currentTab == 2 and "showListPala") or (currentTab == 3 and "showListHunt") or (currentTab == 4 and "showListRogue") or (currentTab == 5 and "showListMaster")
        SausageThreatDB[listKey][self.playerName] = self:GetChecked()
        if IsInGroup() then
            local csv = ""
            for name, shown in pairs(SausageThreatDB[listKey]) do if shown then csv = csv .. name .. "," end end
            local classCode = (currentTab == 2 and "PALA") or (currentTab == 3 and "HUNT") or (currentTab == 4 and "ROGUE") or (currentTab == 5 and "MASTER")
            SendComm("SYNC_LIST:"..classCode..":"..csv)
        end
        UpdateIgnoreScrollFrame()
        if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
    end)
    ignoreRowBtns[i] = row
end

UpdateIgnoreScrollFrame = function()
    wipe(rosterCache)
    if IsInRaid() then for i=1, GetNumRaidMembers() do local n = UnitName("raid"..i); if n then rosterCache[#rosterCache+1] = n end end
    elseif GetNumPartyMembers() > 0 then local pn = UnitName("player"); if pn then rosterCache[#rosterCache+1] = pn end; for i=1, GetNumPartyMembers() do local n = UnitName("party"..i); if n then rosterCache[#rosterCache+1] = n end end
    else local pn = UnitName("player"); if pn then rosterCache[#rosterCache+1] = pn end end
    table.sort(rosterCache)

    FauxScrollFrame_Update(ignoreListScroll, #rosterCache, 15, 20)
    local offset = FauxScrollFrame_GetOffset(ignoreListScroll)
    local listKey = (currentTab == 2 and "showListPala") or (currentTab == 3 and "showListHunt") or (currentTab == 4 and "showListRogue") or (currentTab == 5 and "showListMaster")

    for i = 1, 15 do
        local index = offset + i
        local row = ignoreRowBtns[i]
        if index <= #rosterCache and listKey then
            local pName = rosterCache[index]
            row.playerName = pName; row.text:SetText(pName)
            if SausageThreatDB[listKey] and SausageThreatDB[listKey][pName] then row:SetChecked(true); row.text:SetTextColor(1, 1, 1, 1) else row:SetChecked(false); row.text:SetTextColor(0.5, 0.5, 0.5, 1) end
            row:Show()
            if IsInRaid() and not (IsRaidLeader() or IsRaidOfficer()) then row:Disable() else row:Enable() end
        else row:Hide() end
    end
end
ignoreListScroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, 20, UpdateIgnoreScrollFrame) end)

local footerFrame = CreateFrame("Frame", nil, SettingsFrame)
footerFrame:SetSize(480, 75); footerFrame:SetPoint("BOTTOMLEFT", 0, 0); footerFrame:SetFrameLevel(SettingsFrame:GetFrameLevel() + 5)

local btnCheckStatus = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
btnCheckStatus:SetSize(110, 25); btnCheckStatus:SetPoint("BOTTOMLEFT", 15, 45); btnCheckStatus:SetText("Check Group")
btnCheckStatus:SetScript("OnClick", function() if IsRaidLeader() or IsRaidOfficer() or not IsInRaid() then SendComm("CHECK") end end)

local btnTestGrid = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
btnTestGrid:SetSize(100, 25); btnTestGrid:SetPoint("LEFT", btnCheckStatus, "RIGHT", 5, 0); btnTestGrid:SetText("Test Grid")
btnTestGrid:SetScript("OnClick", function()
    isTestMode = not isTestMode
    if isTestMode then CoordFrame:Show(); MainFrame:Show(); EventFrame:SetScript("OnUpdate", function(self, elapsed) UpdateCombatGrid(elapsed) end)
    else if not inCombat then if not (IsInRaid() and (IsRaidLeader() or IsRaidOfficer())) then CoordFrame:Hide() end; if SausageThreatDB.autoHide then MainFrame:Hide() end; EventFrame:SetScript("OnUpdate", nil) end end
    SortPaladins(); if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
end)

local refreshBtn = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
refreshBtn:SetSize(100, 25); refreshBtn:SetPoint("LEFT", btnTestGrid, "RIGHT", 5, 0); refreshBtn:SetText("Update Grid")
refreshBtn:SetScript("OnClick", function() if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid(); UpdateIgnoreScrollFrame(); BroadcastStatus() end end)

local updateBtn = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
updateBtn:SetSize(110, 25); updateBtn:SetPoint("BOTTOMRIGHT", -20, 15); updateBtn:SetText("Check Updates")
updateBtn:SetScript("OnClick", function() GitFrame:Show() end)

local lblVersion = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lblVersion:SetPoint("BOTTOMLEFT", 20, 15); lblVersion:SetText("v " .. SAUSAGE_VERSION)
local lblCredits = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lblCredits:SetPoint("BOTTOM", footerFrame, "BOTTOM", 0, 15); lblCredits:SetText("by Sausage Party")

local cbEnableSound = CreateFrame("CheckButton", nil, generalPanel, "OptionsBaseCheckButtonTemplate")
cbEnableSound:SetPoint("TOPLEFT", 20, -320)
cbEnableSound:SetScript("OnClick", function(self) if SausageThreatDB then SausageThreatDB.enableSound = self:GetChecked() end end)
local cbEnableSoundText = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbEnableSoundText:SetPoint("LEFT", cbEnableSound, "RIGHT", 5, 0); cbEnableSoundText:SetText("Enable Alert Sound")

local testSoundBtn = CreateFrame("Button", nil, generalPanel, "UIPanelButtonTemplate")
testSoundBtn:SetSize(80, 22); testSoundBtn:SetPoint("LEFT", cbEnableSoundText, "RIGHT", 20, 0); testSoundBtn:SetText("Test Sound")
testSoundBtn:SetScript("OnClick", function() if mySoundPath then PlaySoundFile(mySoundPath, "Master") end end)

local cbBossOnlyAlert = CreateFrame("CheckButton", nil, generalPanel, "OptionsBaseCheckButtonTemplate")
cbBossOnlyAlert:SetPoint("TOPLEFT", 20, -350)
cbBossOnlyAlert:SetScript("OnClick", function(self) if SausageThreatDB then SausageThreatDB.bossOnlyAlert = self:GetChecked() end end)
local cbBossOnlyAlertText = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbBossOnlyAlertText:SetPoint("LEFT", cbBossOnlyAlert, "RIGHT", 5, 0); cbBossOnlyAlertText:SetText("Sound alert only on boss")

local radialLabel = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
radialLabel:SetPoint("TOPLEFT", 20, -390); radialLabel:SetText("Radial Theme:")

local ringPaths = { [1] = "rogue", [2] = "paladin", [3] = "hunter" }
local function GetRingPath(id) return "Interface\\AddOns\\SausageThreat\\Textures\\ring_" .. (ringPaths[id] or "paladin") .. ".tga" end

local function CreateThemeBtn(id, label, xOffset)
    local btn = CreateFrame("Button", nil, generalPanel, "UIPanelButtonTemplate")
    btn:SetSize(60, 22); btn:SetPoint("LEFT", radialLabel, "RIGHT", xOffset, 0); btn:SetText(label)
    btn:SetScript("OnClick", function()
        if SausageThreatDB then SausageThreatDB.radialRingType = id end
        if RadialMenu and RadialMenu.customRing then
            RadialMenu.customRing:SetTexture(GetRingPath(id))
        end
    end)
    return btn
end
local themeBtn1 = CreateThemeBtn(1, "Rogue", 10)
local themeBtn2 = CreateThemeBtn(2, "Paladin", 75)
local themeBtn3 = CreateThemeBtn(3, "Hunter", 140)

function SausageThreatSettings_cbBossOnlyAlert_Update()
    if cbBossOnlyAlert and SausageThreatDB then cbBossOnlyAlert:SetChecked(SausageThreatDB.bossOnlyAlert) end
end

function SettingsFrame.RefreshUI()
    if currentTab == 1 then
        generalPanel:Show(); listPanel:Hide()
        cbAutoHide:SetChecked(SausageThreatDB.autoHide)
        sldCols:SetValue(SausageThreatDB.cols); sldWidth:SetValue(SausageThreatDB.btnWidth); sldHeight:SetValue(SausageThreatDB.btnHeight); sldSpacing:SetValue(SausageThreatDB.spacing)
        sldLockout:SetValue(SausageThreatDB.cmdLockout or 3)
        sldThreshMelee:SetValue(SausageThreatDB.threatThresholdMelee or 90)
        sldThreshCaster:SetValue(SausageThreatDB.threatThresholdCaster or 110)
        cbHideBorder:SetChecked(SausageThreatDB.hideBorder); cbHideHeader:SetChecked(SausageThreatDB.hideHeader); cbHideNames:SetChecked(SausageThreatDB.hideNames); cbHideThreat:SetChecked(SausageThreatDB.hideThreat); cbHideBackground:SetChecked(SausageThreatDB.hideBackground)
        cbEnableSound:SetChecked(SausageThreatDB.enableSound)
        SausageThreatSettings_cbBossOnlyAlert_Update()
    else
        generalPanel:Hide(); listPanel:Show(); UpdateIgnoreScrollFrame()
    end
end
SettingsFrame:SetScript("OnShow", function() 
    if SausageThreatDB then 
        SettingsFrame:Raise()
        UpdateSettingsTabsVisibility()
        SettingsFrame.RefreshUI() 
    end 
end)

-- [[ TEST WINDOW ]]
local TestFrame = CreateFrame("Frame", "SausageThreatTestFrame", UIParent)
TestFrame:SetSize(250, 450); TestFrame:SetPoint("CENTER", 300, 0); TestFrame:SetBackdrop(SettingsFrame:GetBackdrop()); TestFrame:SetBackdropColor(1, 1, 1, 1); TestFrame:SetMovable(true); TestFrame:EnableMouse(true); TestFrame:RegisterForDrag("LeftButton"); TestFrame:SetScript("OnDragStart", TestFrame.StartMoving); TestFrame:SetScript("OnDragStop", TestFrame.StopMovingOrSizing); TestFrame:Hide()
local testHeader = TestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal"); testHeader:SetPoint("TOP", 0, -15); testHeader:SetText("SausageThreat Debug")

local function CreateTestButton(text, y, func)
    local btn = CreateFrame("Button", nil, TestFrame, "UIPanelButtonTemplate")
    btn:SetSize(180, 25); btn:SetPoint("TOP", 0, y); btn:SetText(text); btn:SetScript("OnClick", func)
    return btn
end

-- Vylepšená funkcia pre automatické zapnutie Test Gridu po kliknutí na classu
local function SetIdentityAndTest(className)
    debugClass = className
    UpdateAddonIdentity()
    isTestMode = true
    CoordFrame:Show()
    MainFrame:Show()
    EventFrame:SetScript("OnUpdate", function(self, elapsed) UpdateCombatGrid(elapsed) end)
    SortPaladins()
    if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
    print("|cFFFFFF00[SausageThreat]|r Identity: " .. className .. " | Test Mode: |cFF00FF00ON|r")
end

CreateTestButton("Identity: PALADIN", -45, function() SetIdentityAndTest("PALADIN") end)
CreateTestButton("Identity: HUNTER", -75, function() SetIdentityAndTest("HUNTER") end)
CreateTestButton("Identity: ROGUE", -105, function() SetIdentityAndTest("ROGUE") end)

local lbLeader = CreateFrame("CheckButton", nil, TestFrame, "OptionsBaseCheckButtonTemplate")
lbLeader:SetPoint("TOPLEFT", 35, -140); lbLeader:SetScript("OnClick", function(self) debugLeader = self:GetChecked() end)
local lbLeaderText = TestFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); lbLeaderText:SetPoint("LEFT", lbLeader, "RIGHT", 5, 0); lbLeaderText:SetText("Force Leader Rights")

CreateTestButton("Simulate PALA Ping", -185, function() EventFrame:GetScript("OnEvent")(EventFrame, "CHAT_MSG_ADDON", PREFIX, "PING_CAST:player:"..UnitName("player")..":PALA", "RAID", "FakeRL") end)
CreateTestButton("Simulate HUNT Ping", -215, function() EventFrame:GetScript("OnEvent")(EventFrame, "CHAT_MSG_ADDON", PREFIX, "PING_CAST:player:"..UnitName("player")..":HUNT", "RAID", "FakeRL") end)
CreateTestButton("Simulate ROGUE Ping", -245, function() EventFrame:GetScript("OnEvent")(EventFrame, "CHAT_MSG_ADDON", PREFIX, "PING_CAST:player:"..UnitName("player")..":ROGUE", "RAID", "FakeRL") end)
CreateTestButton("Add Fake Spellers", -285, function() activePaladins[#activePaladins+1] = { name="F_Holy", spec=1 }; activePaladins[#activePaladins+1] = { name="F_Hunt", spec=4 }; activePaladins[#activePaladins+1] = { name="F_Rogu", spec=5 }; SortPaladins() end)
CreateTestButton("Fake ANNOUNCE (Pala)", -315, function() EventFrame:GetScript("OnEvent")(EventFrame, "CHAT_MSG_ADDON", PREFIX, "ANNOUNCE:2:1", "RAID", "F_Pala_"..math.random(10,99)) end)
CreateTestButton("Test THREAT Sound", -345, function() if THREAT_SOUND then PlaySoundFile(THREAT_SOUND, "Master") end end)
CreateTestButton("Close Test Window", -390, function() TestFrame:Hide() end)

-- [[ MINIMAP IKONA ]]
local function CreateMinimapButton()
    local mmBtn = CreateFrame("Button", "SausageThreatMinimapBtn", Minimap)
    mmBtn:SetSize(31, 31)
    mmBtn:SetFrameStrata("MEDIUM")
    mmBtn:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    mmBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mmBtn:RegisterForDrag("RightButton")

    local icon = mmBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Inv_Misc_Food_54") -- The Red Chili/Sausage
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")

    local border = mmBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    border:SetVertexColor(1, 0.6, 0) -- Sausage Orange

    local function UpdatePosition()
        local angle = math_rad(SausageThreatDB and SausageThreatDB.minimapPos or 180)
        local x, y = math_cos(angle) * 80, math_sin(angle) * 80
        mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    mmBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if IsShiftKeyDown() then
                if SettingsFrame:IsShown() then SettingsFrame:Hide() else SettingsFrame:Show() end
            else
                if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end
            end
        end
    end)

    mmBtn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local xpos, ypos = GetCursorPosition()
            local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
            local scale = Minimap:GetEffectiveScale()
            xpos, ypos = (xpos / scale) - xmin - 70, (ypos / scale) - ymin - 70
            local angle = math_deg(math_atan2(ypos, xpos))
            if angle < 0 then angle = angle + 360 end
            if SausageThreatDB then SausageThreatDB.minimapPos = angle end
            UpdatePosition()
        end)
    end)
    mmBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    mmBtn:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        _G.GameTooltip:AddLine("|cffff8800Sausage|r Threat", 1, 1, 1)
        _G.GameTooltip:AddLine("Left Click: Toggle Grid", 1, 0.8, 0)
        _G.GameTooltip:AddLine("Shift-Click: Settings", 1, 0.8, 0)
        _G.GameTooltip:Show()
    end)
    mmBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    UpdatePosition()
end

-- Initialize minimap button after a short delay (Bible p. 1327)
After(1, CreateMinimapButton)

-- [[ EVENTY ]]
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")       -- Cataclysm+ (záloha)
EventFrame:RegisterEvent("RAID_ROSTER_UPDATE")        -- WotLK 3.3.5a
EventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")     -- WotLK 3.3.5a
EventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
EventFrame:RegisterEvent("CHAT_MSG_ADDON")
EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
EventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
EventFrame:RegisterEvent("UNIT_AURA")
EventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" and totTargetIsDPS then
            local name, _, _, _, _, duration = UnitBuff("player", TRICKS_NAME)
            if name and duration and duration <= 6 then
                CancelUnitBuff("player", TRICKS_NAME)
                totTargetIsDPS = false
                print("|cFF00CCFF[SausageThreat]|r Auto-canceled Tricks of the Trade on DPS target!")
            end
        end
    elseif event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
            SausageThreatDB = SausageThreatDB or {}
            for k, v in pairs(defaultDB) do if SausageThreatDB[k] == nil then SausageThreatDB[k] = v end end
            if SausageThreatDB.framePoint then SausageThreatDB.anchor = SausageThreatDB.framePoint; SausageThreatDB.framePoint = nil end
            if not SausageThreatDB.frameY or SausageThreatDB.frameY < 0 then SausageThreatDB.frameX = UIParent:GetWidth() / 2; SausageThreatDB.frameY = UIParent:GetHeight() - 100 end
            SausageThreatDB.assignedRoles = SausageThreatDB.assignedRoles or {}
            
            if SausageThreatDB.radialRingType and RadialMenu and RadialMenu.customRing then
                RadialMenu.customRing:SetTexture(GetRingPath(SausageThreatDB.radialRingType))
            end

            MainFrame:ClearAllPoints(); CreateGridButtons()
            if SausageThreatDB.isShown == false or SausageThreatDB.autoHide then MainFrame:Hide() else MainFrame:Show() end
            SausageThreatMainFrame_UpdateGrid()
            UpdateLockBtnVisibility()

            -- Obnovenie uloženej pozície CoordFrame
            if SausageThreatDB.coordFrameX and SausageThreatDB.coordFrameY then
                CoordFrame:ClearAllPoints()
                CoordFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", SausageThreatDB.coordFrameX, SausageThreatDB.coordFrameY)
            end

            -- Záchranná sieť: ElvUI FrameGlow guard pre prípad, že noMouseoverHighlight nestačí
            -- Ak je funkcia globálna, obalíme ju kontrolou na colors, aby nehavarovala na custom framoch
            After(0, function()
                if _G["FrameGlow_CheckMouseover"] then
                    local _origFGC = _G["FrameGlow_CheckMouseover"]
                    _G["FrameGlow_CheckMouseover"] = function(self, ...)
                        if not self or not self.colors then return end
                        return _origFGC(self, ...)
                    end
                end
            end)
            
            -- WotLK safe timer pre načítanie talentov
            local delayFrame = CreateFrame("Frame")
            delayFrame.timer = 0
            delayFrame:SetScript("OnUpdate", function(self, elapsed)
                self.timer = self.timer + elapsed
                if self.timer > 4 then
                    self:SetScript("OnUpdate", nil)
                    local myRole = DetermineMyRole()
                    if SausageThreatDB then
                        SausageThreatDB.assignedRoles[UnitName("player")] = myRole
                    end
                    SendComm("MY_ROLE:"..myRole)
                end
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TALENT_UPDATE" then
            local myRole = DetermineMyRole()
            SausageThreatDB.assignedRoles = SausageThreatDB.assignedRoles or {}
            SausageThreatDB.assignedRoles[UnitName("player")] = myRole
            SendComm("MY_ROLE:"..myRole)
        end
        
        if IsInRaid() and (IsRaidLeader() or IsRaidOfficer()) or isTestMode then CoordFrame:Show() else CoordFrame:Hide() end
        local changed = false; for i = #activePaladins, 1, -1 do if not UnitInRaid(activePaladins[i].name) and not UnitInParty(activePaladins[i].name) then table.remove(activePaladins, i); changed = true end end
        SortPaladins(); SausageThreatMainFrame_UpdateGrid(); if SettingsFrame:IsShown() then UpdateIgnoreScrollFrame() end; BroadcastStatus()
        UpdateLockBtnVisibility()
        if event == "PLAYER_ENTERING_WORLD" and not (IsRaidLeader() or IsRaidOfficer()) then SendComm("REQ_IGNORE") end
    elseif event == "PLAYER_REGEN_DISABLED" then

        inCombat = true; if SausageThreatDB and SausageThreatDB.autoHide then MainFrame:Show() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false; focusTarget, focusTargetClass = nil, nil; if SausageThreatDB and SausageThreatDB.autoHide then MainFrame:Hide() end; SausageThreatMainFrame_UpdateGrid()
        -- Automatické uvoľnenie zámku po skončení boja
        lockedThreatGUID = nil
        lockedThreatName = nil
        lockBtn:SetText("Lock Target")
        UpdateAddonIdentity() -- Poistenie synchronizácie atribútov po boji
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        BroadcastStatus()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix == PREFIX then
            local args = {strsplit(":", msg)}
            local cmd = args[1]

            if cmd == "CHECK" then SendComm("VERSION:"..SAUSAGE_VERSION)
            elseif cmd == "VERSION" then print("|cFFFFFF00[SausageThreat]|r " .. sender .. " is running version " .. args[2])
            elseif cmd == "MY_ROLE" then
                SausageThreatDB.assignedRoles = SausageThreatDB.assignedRoles or {}
                SausageThreatDB.assignedRoles[sender] = args[2]
                if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
            elseif cmd == "SET_ROLE" then
                SausageThreatDB.assignedRoles = SausageThreatDB.assignedRoles or {}
                SausageThreatDB.assignedRoles[args[2]] = args[3]
                if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
            elseif cmd == "SYNC_LIST" then
                local listKey = (args[2] == "PALA" and "showListPala") or (args[2] == "HUNT" and "showListHunt") or (args[2] == "ROGUE" and "showListRogue") or (args[2] == "MASTER" and "showListMaster")
                if listKey and args[3] then
                    wipe(SausageThreatDB[listKey]); for _, n in ipairs({strsplit(",", args[3])}) do if n ~= "" then SausageThreatDB[listKey][n] = true end end
                    if SettingsFrame:IsShown() then SettingsFrame.RefreshUI() end; if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
                end
            elseif cmd == "REQ_IGNORE" then
                if IsRaidLeader() or IsRaidOfficer() or (not IsInRaid() and IsInGroup()) then
                    for _, c in ipairs({"PALA", "HUNT", "ROGUE", "MASTER"}) do
                        local listKey = (c == "PALA" and "showListPala") or (c == "HUNT" and "showListHunt") or (c == "ROGUE" and "showListRogue") or (c == "MASTER" and "showListMaster")
                        local csv = ""; for name, shown in pairs(SausageThreatDB[listKey] or {}) do if shown then csv = csv .. name .. "," end end
                        if csv ~= "" then SendComm("SYNC_LIST:"..c..":"..csv) end
                    end
                    
                    local rolesCsv = ""
                    if SausageThreatDB.assignedRoles then
                        for name, role in pairs(SausageThreatDB.assignedRoles) do
                            if string.len(rolesCsv) > 200 then SendComm("SYNC_ROLES:"..rolesCsv); rolesCsv = "" end
                            rolesCsv = rolesCsv .. name .. "=" .. role .. ","
                        end
                        if rolesCsv ~= "" then SendComm("SYNC_ROLES:"..rolesCsv) end
                    end
                end
            elseif cmd == "SYNC_ROLES" then
                if args[2] then
                    SausageThreatDB.assignedRoles = SausageThreatDB.assignedRoles or {}
                    for _, pair in ipairs({strsplit(",", args[2])}) do
                        if pair and pair ~= "" then
                            local n, r = strsplit("=", pair)
                            if n and r then SausageThreatDB.assignedRoles[n] = r end
                        end
                    end
                    if not InCombatLockdown() then SausageThreatMainFrame_UpdateGrid() end
                end
            elseif cmd == "ANNOUNCE" then
                if sender == UnitName("player") then return end
                -- Odstráň existujúci záznam pre tohto hráča
                for i = #activePaladins, 1, -1 do if activePaladins[i].name == sender then table.remove(activePaladins, i) end end
                local isReadyBool = tonumber(args[3]) == 1
                local cdRemaining = tonumber(args[4]) or 0
                local cooldownEnd = (not isReadyBool and cdRemaining > 0) and (GetTime() + cdRemaining) or nil
                -- Vždy pridaj do zoznamu (aj keď je na cooldowne - zobrazíme odpočítavanie)
                activePaladins[#activePaladins + 1] = {
                    name = sender,
                    spec = tonumber(args[2]),
                    isReady = isReadyBool,
                    cooldownEnd = cooldownEnd
                }
                SortPaladins()
            elseif cmd == "PRE_CAST" then -- Vizuálne zmeny iba
            elseif cmd == "PING_CAST" then
                local targetName, assignedName, targetClass = args[2], args[3], args[4]
                
                if SausageThreatDB and SausageThreatDB.cmdLockout then
                    lockedSpells[targetName] = lockedSpells[targetName] or {}
                    lockedSpells[targetName][targetClass] = GetTime() + SausageThreatDB.cmdLockout
                end
                
                if assignedName == UnitName("player") or isTestMode then
                    local targetUnit = GetUnitByName(targetName)
                    if not isTestMode and targetUnit and mySpellName and IsSpellInRange(mySpellName, targetUnit) == 0 then
                        print("|cFFFF0000[SausageThreat]|r Rejected PING (Out of range): " .. targetName); SendComm("RANGE_FAIL:"..targetName..":"..(targetClass or "PALA"))
                        return
                    end
                    focusTarget, focusTimer, focusTargetClass = targetName, 15.0, targetClass 
                    EventFrame:SetScript("OnUpdate", function(self, elapsed) UpdateCombatGrid(elapsed) end)
                    print("|cFF00CCFF[SausageThreat]|r Cast spell on " .. targetName .. "!")
                    if SausageThreatDB.enableSound and mySoundPath then PlaySoundFile(mySoundPath, "Master") end
                end
            elseif cmd == "RANGE_FAIL" then
                local targetName, targetClass = args[2], args[3]
                print("|cFFFF8800[SausageThreat]|r " .. sender .. " is out of range! Reassigning " .. targetClass .. " on " .. targetName)
                rangeFailTracker[targetName] = rangeFailTracker[targetName] or {}; rangeFailTracker[targetName][sender] = GetTime() + 5
                HandleRadialClick(targetClass, targetName)
            end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, sourceName, _, _, destName, _, spellId = ...
        if subEvent == "SPELL_CAST_SUCCESS" then
            if spellId == SALVA_SPELL_ID or spellId == MISDIRECT_SPELL_ID or spellId == TRICKS_SPELL_ID then
                -- Oznam do chatu (iba ak som kutil ja)
                if sourceName == UnitName("player") and IsInGroup() then
                    SendChatMessage(GetSpellInfo(spellId) .. " on " .. destName .. "!", IsInRaid() and "RAID" or "PARTY")
                    focusTarget, focusTargetClass = nil, nil; BroadcastStatus()
                end
                
                if spellId == TRICKS_SPELL_ID and sourceName == UnitName("player") then
                    if GetUnitRoleFromName(destName) == "DPS" then totTargetIsDPS = true else totTargetIsDPS = false end
                end
                
                -- Zapísanie do vizuálneho trackera (pre všetkých v raide)
                local bType = (spellId == SALVA_SPELL_ID and "PALA") or (spellId == MISDIRECT_SPELL_ID and "HUNT") or (spellId == TRICKS_SPELL_ID and "ROGUE")
                local icon = (spellId == SALVA_SPELL_ID and "Interface\\Icons\\Spell_Holy_SealOfSalvation") or (spellId == MISDIRECT_SPELL_ID and "Interface\\Icons\\Ability_Hunter_Misdirection") or (spellId == TRICKS_SPELL_ID and "Interface\\Icons\\Ability_Rogue_TricksOftheTrade")
                
                local duration = (spellId == MISDIRECT_SPELL_ID and 4) or (spellId == TRICKS_SPELL_ID and 6) or 10
                activeBuffsOnTarget[destName] = activeBuffsOnTarget[destName] or {}
                activeBuffsOnTarget[destName][bType] = { expiry = GetTime() + duration, icon = icon }
                
                -- Trigger Success Glow on button
                if sourceName == UnitName("player") then
                    for i = 1, 40 do
                        local btn = unitButtons[i]
                        if btn and btn:IsShown() and btn.unitName == destName then
                            btn.successGlowTime = 0.25
                            break
                        end
                    end
                end
            end
        end
    end
end)

-- [[ SLASH COMMANDS ]]
SLASH_SausageThreat1 = "/sthreat"
SLASH_SausageThreat2 = "/sth"
SlashCmdList["SausageThreat"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "center" then
        if not InCombatLockdown() then SausageThreatDB.anchor = "TOP"; SausageThreatDB.frameX = UIParent:GetWidth() / 2; SausageThreatDB.frameY = UIParent:GetHeight() - 100; SausageThreatMainFrame_UpdateGrid(); print("|cFFFFFF00[SausageThreat]|r Addon centered (Top-Center).") else print("|cFFFF0000[SausageThreat]|r Cannot center while in combat!") end
    elseif msg == "settings" or msg == "config" then if SettingsFrame:IsShown() then SettingsFrame:Hide() else SettingsFrame:Show() end
    elseif msg == "test" or msg == "debug" then if TestFrame:IsShown() then TestFrame:Hide() else TestFrame:Show() end
    else if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end end
end
