-- ============================================================================
-- SAUSAGE SALVA - Paladin Threat & Salvation Coordinator (Pro Grid Edition)
-- Author: Sausage Party / Kokotiar
-- ============================================================================

local addonName, addonTable = ...
local SAUSAGE_VERSION = "v1.0.0" -- SEM SCRIPT DOPLNI VERZIU PODLA TAGU
local PREFIX = "SSALVA"
local SALVA_SPELL_ID = 1038
local SALVA_SPELL_NAME = GetSpellInfo(SALVA_SPELL_ID)

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
    anchor = "TOP",
    hideBorder = false,
    hideHeader = false,
    hideNames = false,
    hideThreat = false,
    ignored = {},
    soundFile = "Interface\\AddOns\\SausageSalva\\sound\\salvation.wav",
    enableSound = true,
    hideBackground = false
}

local inCombat = false
local isTestMode = false -- Premenná pre testovací režim
local unitButtons = {}
local activePaladins = {}
local focusTarget = nil
local focusTimer = 0
local preCastTarget = nil
local preCastTimer = 0

-- [[ EVENTY A INICIALIZACIA DB ]]
local EventFrame = CreateFrame("Frame")

-- Pred-deklarácia funkcií (aby boli dostupné v celom skripte)
local SausageSalvaMainFrame_UpdateGrid
local UpdateCombatGrid
local SortPaladins
local UpdateIgnoreScrollFrame
local BroadcastPaladinStatus

local playerClass = select(2, UnitClass("player"))
local isPaladin = (playerClass == "PALADIN")

-- [[ POMOCNÉ FUNKCIE ]]
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

local function IsTank(unit)
    -- UnitGroupRolesAssigned neexistuje v 3.3.5 (bolo pridané v Cataclysm)
    -- Použijeme len kontrolu buffov a party assignments
    if GetPartyAssignment("MAINTANK", unit) then return true end
    
    -- Ak testujeme sami, chceme sa vidieť aj keď sme tank (na ladenie UI)
    if not IsInGroup() and unit == "player" then return false end

    local auras = { [71] = true, [9634] = true, [25780] = true, [48263] = true }
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellId = UnitAura(unit, i, "HELPFUL")
        if not spellId then break end
        if auras[spellId] then return true end
    end
    return false
end

-- Pomocná funkcia pre odosielanie správ
local function SendComm(msg)
    if not IsInGroup() then return end
    local channel = IsInRaid() and "RAID" or "PARTY"
    if select(2, IsInInstance()) == "pvp" then channel = "BATTLEGROUND" end
    SendAddonMessage(PREFIX, msg, channel)
end

-- [[ HLAVNÝ FRAME (Tenký, automatický dizajn bez krížika) ]]
local MainFrame = CreateFrame("Frame", "SausageSalvaMainFrame", UIParent)
MainFrame:SetPoint("CENTER", 0, 0)
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
MainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point = SausageSalvaDB.anchor or "TOP"
    local x, y
    
    if point == "TOP" then
        x, y = self:GetLeft() + self:GetWidth()/2, self:GetTop()
    elseif point == "BOTTOM" then
        x, y = self:GetLeft() + self:GetWidth()/2, self:GetBottom()
    elseif point == "LEFT" then
        x, y = self:GetLeft(), self:GetTop() - self:GetHeight()/2
    elseif point == "RIGHT" then
        x, y = self:GetRight(), self:GetTop() - self:GetHeight()/2
    else
        x, y = self:GetCenter()
    end

    self:ClearAllPoints()
    self:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
    
    if SausageSalvaDB then 
        SausageSalvaDB.frameX = x
        SausageSalvaDB.frameY = y
    end
end)

MainFrame:SetScript("OnHide", function() 
    if SausageSalvaDB then SausageSalvaDB.isShown = false end 
    EventFrame:SetScript("OnUpdate", nil)
end)
MainFrame:SetScript("OnShow", function() 
    if SausageSalvaDB then SausageSalvaDB.isShown = true end 
    EventFrame:SetScript("OnUpdate", function(self, elapsed) UpdateCombatGrid(elapsed) end)
end)
-- Hlavné okno NIE JE v UISpecialFrames, aby ho ESC nezatváral (oprava na želanie)

-- Profesionálne tenké okraje
MainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})

local header = MainFrame:CreateTexture(nil, "OVERLAY")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetSize(256, 64)
header:SetPoint("TOP", 0, 12)

local title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText("Sausage Salva")

local ContentFrame = CreateFrame("Frame", "SausageSalvaContent", MainFrame)
ContentFrame:SetPoint("TOPLEFT", 15, -35)
ContentFrame:SetSize(1, 1) -- Základná veľkosť

local rlPanelText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rlPanelText:SetPoint("TOPLEFT", 15, -32)
rlPanelText:SetPoint("TOPRIGHT", -15, -32)
rlPanelText:SetJustifyH("CENTER")
rlPanelText:SetText("Available Paladins: None")
rlPanelText:Hide()

-- [[ UPDATE / GITHUB CUSTOM FRAME ]]
local GitFrame = CreateFrame("Frame", "SausageAutomsgGitFrame", UIParent)
GitFrame:SetSize(320, 130)
GitFrame:SetPoint("CENTER")
GitFrame:SetFrameStrata("DIALOG")
GitFrame:SetBackdrop(MainFrame:GetBackdrop())
-- Pridanie do UISpecialFrames pre ESC
UISpecialFrames[#UISpecialFrames + 1] = "SausageAutomsgGitFrame"
GitFrame:Hide()

local gitHeader = GitFrame:CreateTexture(nil, "OVERLAY")
gitHeader:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
gitHeader:SetSize(250, 64)
gitHeader:SetPoint("TOP", 0, 12)
local gitTitle = GitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gitTitle:SetPoint("TOP", gitHeader, "TOP", 0, -14)
gitTitle:SetText("UPDATE LINK")
local gitClose = CreateFrame("Button", nil, GitFrame, "UIPanelCloseButton")
gitClose:SetPoint("TOPRIGHT", -2, -2)
local gitDesc = GitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gitDesc:SetPoint("TOP", 0, -35)
gitDesc:SetText("Press Ctrl+C to copy the GitHub link:")
local gitEditBox = CreateFrame("EditBox", nil, GitFrame, "InputBoxTemplate")
gitEditBox:SetSize(260, 20)
gitEditBox:SetPoint("TOP", gitDesc, "BOTTOM", 0, -15)
gitEditBox:SetAutoFocus(true)
local GITHUB_LINK = "https://github.com/NikowskyWow/SausageSalva/releases"

gitEditBox:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= GITHUB_LINK then self:SetText(GITHUB_LINK); self:HighlightText() end
end)
gitEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); GitFrame:Hide() end)
GitFrame:SetScript("OnShow", function() gitEditBox:SetText(GITHUB_LINK); gitEditBox:SetFocus(); gitEditBox:HighlightText() end)

-- [[ NASTAVENIA (SETTINGS FRAME) ]]
local SettingsFrame = CreateFrame("Frame", "SausageSalvaSettings", UIParent)
SettingsFrame:SetSize(450, 420)
SettingsFrame:SetPoint("CENTER")
SettingsFrame:SetFrameStrata("DIALOG")
SettingsFrame:SetMovable(true)
SettingsFrame:EnableMouse(true)
SettingsFrame:RegisterForDrag("LeftButton")
SettingsFrame:SetScript("OnDragStart", SettingsFrame.StartMoving)
SettingsFrame:SetScript("OnDragStop", SettingsFrame.StopMovingOrSizing)

SettingsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
SettingsFrame:SetBackdropColor(0, 0, 0, 1.0) -- Úplne nepriehľadné pozadie
-- Pridanie do UISpecialFrames pre ESC
UISpecialFrames[#UISpecialFrames + 1] = "SausageSalvaSettings"
SettingsFrame:Hide()

local setHeader = SettingsFrame:CreateTexture(nil, "OVERLAY")
setHeader:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
setHeader:SetSize(256, 64)
setHeader:SetPoint("TOP", 0, 12)
local setTitle = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
setTitle:SetPoint("TOP", setHeader, "TOP", 0, -14)
setTitle:SetText("Settings")
local setClose = CreateFrame("Button", nil, SettingsFrame, "UIPanelCloseButton")
setClose:SetPoint("TOPRIGHT", -2, -2)

local cbAutoHide = CreateFrame("CheckButton", nil, SettingsFrame, "OptionsBaseCheckButtonTemplate")
cbAutoHide:SetPoint("TOPLEFT", 20, -30)
cbAutoHide:SetScript("OnClick", function(self)
    if SausageSalvaDB then 
        SausageSalvaDB.autoHide = self:GetChecked()
        -- Okamžitá reakcia: Ak sme mimo boja a zapneme auto-hide, schováme okno.
        -- Ak sme v boji a vypneme auto-hide, uistíme sa že okno je vidieť.
        if not inCombat and SausageSalvaDB.autoHide then
            MainFrame:Hide()
        elseif inCombat then
            MainFrame:Show()
        end
    end
end)
local cbAutoHideText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbAutoHideText:SetPoint("LEFT", cbAutoHide, "RIGHT", 5, 0)
cbAutoHideText:SetText("Auto-hide out of combat")

-- Nastavenie Gridu (Sliders)
local function CreateGridSlider(name, text, minV, maxV, x, y, dbKey)
    local slider = CreateFrame("Slider", "SausageSalvaSlider"..name, SettingsFrame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(1)
    _G[slider:GetName().."Low"]:SetText(minV)
    _G[slider:GetName().."High"]:SetText(maxV)
    _G[slider:GetName().."Text"]:SetText(text)
    
    local valText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOP", slider, "BOTTOM", 0, 3)
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        valText:SetText(value)
        if SausageSalvaDB then 
            SausageSalvaDB[dbKey] = value
            if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
        end
    end)
    return slider
end

local sldCols = CreateGridSlider("Cols", "Columns", 1, 8, 20, -80, "cols")
local sldWidth = CreateGridSlider("Width", "Button Width", 50, 150, 20, -130, "btnWidth")
local sldHeight = CreateGridSlider("Height", "Button Height", 20, 60, 20, -180, "btnHeight")
local sldSpacing = CreateGridSlider("Spacing", "Spacing", 0, 20, 20, -230, "spacing")

local cbHideBorder = CreateFrame("CheckButton", nil, SettingsFrame, "OptionsBaseCheckButtonTemplate")
cbHideBorder:SetPoint("TOPLEFT", 205, -280)
cbHideBorder:SetScript("OnClick", function(self)
    if SausageSalvaDB then 
        SausageSalvaDB.hideBorder = self:GetChecked()
        if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
    end
end)
local cbHideBorderText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbHideBorderText:SetPoint("LEFT", cbHideBorder, "RIGHT", 5, 0)
cbHideBorderText:SetText("Hide Main Border")

local cbHideHeader = CreateFrame("CheckButton", nil, SettingsFrame, "OptionsBaseCheckButtonTemplate")
cbHideHeader:SetPoint("TOPLEFT", 20, -280)
cbHideHeader:SetScript("OnClick", function(self)
    if SausageSalvaDB then 
        SausageSalvaDB.hideHeader = self:GetChecked()
        if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
    end
end)
local cbHideHeaderText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbHideHeaderText:SetPoint("LEFT", cbHideHeader, "RIGHT", 5, 0)
cbHideHeaderText:SetText("Hide Header")

local cbHideNames = CreateFrame("CheckButton", nil, SettingsFrame, "OptionsBaseCheckButtonTemplate")
cbHideNames:SetPoint("TOPLEFT", 20, -310)
cbHideNames:SetScript("OnClick", function(self)
    if SausageSalvaDB then 
        SausageSalvaDB.hideNames = self:GetChecked()
        if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
    end
end)
local cbHideNamesText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbHideNamesText:SetPoint("LEFT", cbHideNames, "RIGHT", 5, 0)
cbHideNamesText:SetText("Hide Names")

local cbHideThreat = CreateFrame("CheckButton", nil, SettingsFrame, "OptionsBaseCheckButtonTemplate")
cbHideThreat:SetPoint("TOPLEFT", 205, -310)
cbHideThreat:SetScript("OnClick", function(self)
    if SausageSalvaDB then 
        SausageSalvaDB.hideThreat = self:GetChecked()
        if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
    end
end)
local cbHideThreatText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbHideThreatText:SetPoint("LEFT", cbHideThreat, "RIGHT", 5, 0)
cbHideThreatText:SetText("Hide Threat %")

local cbHideBackground = CreateFrame("CheckButton", nil, SettingsFrame, "OptionsBaseCheckButtonTemplate")
cbHideBackground:SetPoint("TOPLEFT", 205, -250)
cbHideBackground:SetScript("OnClick", function(self)
    if SausageSalvaDB then 
        SausageSalvaDB.hideBackground = self:GetChecked()
        if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
    end
end)
local cbHideBackgroundText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbHideBackgroundText:SetPoint("LEFT", cbHideBackground, "RIGHT", 5, 0)
cbHideBackgroundText:SetText("Hide Main BG")

-- Anchor Selection
local anchorLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchorLabel:SetPoint("TOPLEFT", 20, -345)
anchorLabel:SetText("Growth Direction (Anchor):")

local function CreateAnchorBtn(name, point, x, y)
    local btn = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
    btn:SetSize(60, 22)
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetText(name)
    btn:SetScript("OnClick", function()
        local oldAnchor = SausageSalvaDB.anchor or "TOP"
        SausageSalvaDB.anchor = point
        print("|cFFFFFF00[SausageSalva]|r Growth set to: " .. name)
        
        -- Prepočet súradníc tak, aby addon ostal na MIERU
        local x, y
        if point == "TOP" then
            x, y = MainFrame:GetLeft() + MainFrame:GetWidth()/2, MainFrame:GetTop()
        elseif point == "BOTTOM" then
            x, y = MainFrame:GetLeft() + MainFrame:GetWidth()/2, MainFrame:GetBottom()
        elseif point == "LEFT" then
            x, y = MainFrame:GetLeft(), MainFrame:GetTop() - MainFrame:GetHeight()/2
        elseif point == "RIGHT" then
            x, y = MainFrame:GetRight(), MainFrame:GetTop() - MainFrame:GetHeight()/2
        end

        if x and y then
            SausageSalvaDB.frameX = x
            SausageSalvaDB.frameY = y
        end

        if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
    end)
    return btn
end

CreateAnchorBtn("Down", "TOP", 180, -340)
CreateAnchorBtn("Up", "BOTTOM", 245, -340)
CreateAnchorBtn("Right", "LEFT", 310, -340)
CreateAnchorBtn("Left", "RIGHT", 375, -340)

-- Ignore List (Pravá strana, FauxScrollFrame UI)
local ignoreLabel = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ignoreLabel:SetPoint("TOPLEFT", 200, -35)
ignoreLabel:SetText("Ignore Players (RL Only)")

local rosterFrame = CreateFrame("Frame", nil, SettingsFrame)
rosterFrame:SetSize(180, 220)
rosterFrame:SetPoint("TOPLEFT", 200, -55)
rosterFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
rosterFrame:SetBackdropColor(0,0,0,0.5)

local ignoreListScroll = CreateFrame("ScrollFrame", "SausageSalvaIgnoreScroll", rosterFrame, "FauxScrollFrameTemplate")
ignoreListScroll:SetPoint("TOPLEFT", 5, -5)
ignoreListScroll:SetPoint("BOTTOMRIGHT", -25, 5)

local ignoreRowBtns = {}
for i = 1, 10 do
    local row = CreateFrame("CheckButton", nil, rosterFrame, "UICheckButtonTemplate")
    row:SetSize(20, 20)
    if i == 1 then row:SetPoint("TOPLEFT", 10, -10) else row:SetPoint("TOPLEFT", ignoreRowBtns[i-1], "BOTTOMLEFT", 0, 0) end
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row, "RIGHT", 5, 0)
    row:SetScript("OnClick", function(self)
        -- Povolenie ignore listu ak sme solo, v malej parte (LFG) alebo sme leader/officer v raide
        local canIgnore = not IsInRaid() or (IsRaidLeader() or IsRaidOfficer())
        
        if not canIgnore then
            self:SetChecked(not self:GetChecked())
            print("|cFFFF0000[SausageSalva]|r You must be Raid Leader or Officer to set ignores in a RAID.")
            return
        end
        local playerName = self.playerName
        if playerName then
            -- Ak sme v raide, synchronizujeme správu, inak len lokálne prepneme
            if IsInRaid() or GetNumPartyMembers() > 0 then
                SendComm("TOGGLE_IGNORE:"..playerName)
            else
                -- Lokálne prepnutie pre solo/party
                if SausageSalvaDB.ignored[playerName] then
                    SausageSalvaDB.ignored[playerName] = false
                else
                    SausageSalvaDB.ignored[playerName] = true
                end
                UpdateIgnoreScrollFrame()
                if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
            end
        end
    end)
    ignoreRowBtns[i] = row
end

local rosterCache = {}
function UpdateIgnoreScrollFrame()
    wipe(rosterCache)
    if IsInRaid() then
        for i=1, GetNumRaidMembers() do 
            local n = UnitName("raid"..i)
            if n then rosterCache[#rosterCache + 1] = n end
        end
    elseif GetNumPartyMembers() > 0 then
        local pn = UnitName("player")
        if pn then rosterCache[#rosterCache + 1] = pn end
        for i=1, GetNumPartyMembers() do 
            local n = UnitName("party"..i)
            if n then rosterCache[#rosterCache + 1] = n end
        end
    else
        local pn = UnitName("player")
        if pn then rosterCache[#rosterCache + 1] = pn end
    end
    table.sort(rosterCache)

    FauxScrollFrame_Update(ignoreListScroll, #rosterCache, 10, 20)
    local offset = FauxScrollFrame_GetOffset(ignoreListScroll)
    for i = 1, 10 do
        local index = offset + i
        local row = ignoreRowBtns[i]
        if index <= #rosterCache then
            local pName = rosterCache[index]
            row.playerName = pName
            row.text:SetText(pName)
            if SausageSalvaDB and SausageSalvaDB.ignored[pName] then
                row:SetChecked(true)
                row.text:SetTextColor(0.5, 0.5, 0.5, 1)
            else
                row:SetChecked(false)
                row.text:SetTextColor(1, 1, 1, 1)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end
ignoreListScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, 20, UpdateIgnoreScrollFrame)
end)

local btnCheckPala = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
btnCheckPala:SetSize(140, 25)
btnCheckPala:SetPoint("BOTTOMLEFT", 20, 15)
btnCheckPala:SetText("Check Paladins")
btnCheckPala:SetScript("OnClick", function()
    if IsRaidLeader() or IsRaidOfficer() or not IsInRaid() then
        print("|cFFFFFF00[SausageSalva]|r Requesting version check...")
        SendComm("CHECK")
    else
        print("|cFFFF0000[SausageSalva]|r Only Raid Leader or Officer can do this.")
    end
end)

local btnTestGrid = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
btnTestGrid:SetSize(100, 25)
btnTestGrid:SetPoint("LEFT", btnCheckPala, "RIGHT", 10, 0)
btnTestGrid:SetText("Test Grid")
btnTestGrid:SetScript("OnClick", function()
    isTestMode = not isTestMode
    print("|cFFFFFF00[SausageSalva]|r Test Mode: " .. (isTestMode and "|cFF00FF00ON" or "|cFFFF0000OFF"))
    
    if isTestMode then
        rlPanelText:Show()
        EventFrame:SetScript("OnUpdate", function(self, elapsed) UpdateCombatGrid(elapsed) end)
    elseif not inCombat then
        if not (IsInRaid() and (IsRaidLeader() or IsRaidOfficer())) then
            rlPanelText:Hide()
        end
        EventFrame:SetScript("OnUpdate", nil)
    end

    SortPaladins()
    if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
end)

local updateBtn = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
updateBtn:SetSize(110, 25)
updateBtn:SetPoint("BOTTOMRIGHT", -20, 15)
updateBtn:SetText("Check Updates")
updateBtn:SetScript("OnClick", function() GitFrame:Show() end)

local refreshBtn = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
refreshBtn:SetSize(100, 25)
refreshBtn:SetPoint("RIGHT", updateBtn, "LEFT", -5, 0)
refreshBtn:SetText("Update Grid")
refreshBtn:SetScript("OnClick", function() 
    if not InCombatLockdown() then
        SausageSalvaMainFrame_UpdateGrid()
        UpdateIgnoreScrollFrame()
        BroadcastPaladinStatus()
        print("|cFFFFFF00[SausageSalva]|r Grid forced update.")
    else
        print("|cFFFF0000[SausageSalva]|r Cannot force update during combat!")
    end
end)

local lblVersion = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lblVersion:SetPoint("BOTTOM", 0, 30)
lblVersion:SetText(SAUSAGE_VERSION)
local lblCredits = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lblCredits:SetPoint("BOTTOM", 0, 15)
lblCredits:SetText("by Sausage Party")

-- Alert Sound UI (Simplified)
local cbEnableSound = CreateFrame("CheckButton", nil, SettingsFrame, "OptionsBaseCheckButtonTemplate")
cbEnableSound:SetPoint("TOPLEFT", 20, -370)
cbEnableSound:SetScript("OnClick", function(self)
    if SausageSalvaDB then 
        SausageSalvaDB.enableSound = self:GetChecked()
    end
end)
local cbEnableSoundText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbEnableSoundText:SetPoint("LEFT", cbEnableSound, "RIGHT", 5, 0)
cbEnableSoundText:SetText("Enable Alert Sound (salvation.wav)")

local testSoundBtn = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
testSoundBtn:SetSize(80, 22)
testSoundBtn:SetPoint("LEFT", cbEnableSoundText, "RIGHT", 20, 0)
testSoundBtn:SetText("Test Sound")
testSoundBtn:SetScript("OnClick", function()
    local path = SausageSalvaDB.soundFile
    if path and path ~= "" then
        PlaySoundFile(path, "Master")
    end
end)

SettingsFrame:SetScript("OnShow", function()
    if not SausageSalvaDB then return end
    cbAutoHide:SetChecked(SausageSalvaDB.autoHide)
    sldCols:SetValue(SausageSalvaDB.cols)
    sldWidth:SetValue(SausageSalvaDB.btnWidth)
    sldHeight:SetValue(SausageSalvaDB.btnHeight)
    sldSpacing:SetValue(SausageSalvaDB.spacing)
    cbHideBorder:SetChecked(SausageSalvaDB.hideBorder)
    cbHideHeader:SetChecked(SausageSalvaDB.hideHeader)
    cbHideNames:SetChecked(SausageSalvaDB.hideNames)
    cbHideThreat:SetChecked(SausageSalvaDB.hideThreat)
    cbHideBackground:SetChecked(SausageSalvaDB.hideBackground)
    cbEnableSound:SetChecked(SausageSalvaDB.enableSound)
    UpdateIgnoreScrollFrame()
end)

-- [[ MINIMAP IKONA ]]
local minimapIcon = CreateFrame("Button", "SausageSalvaMinimapIcon", Minimap)
minimapIcon:SetSize(32, 32)
minimapIcon:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
local iconTex = minimapIcon:CreateTexture(nil, "BACKGROUND")
iconTex:SetTexture("Interface\\Icons\\Inv_Misc_Food_54")
iconTex:SetSize(20, 20)
iconTex:SetPoint("CENTER")
local iconBorder = minimapIcon:CreateTexture(nil, "OVERLAY")
iconBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
iconBorder:SetSize(54, 54)
iconBorder:SetPoint("TOPLEFT", 0, 0)

minimapIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapIcon:RegisterForDrag("RightButton") -- Zmena na pravé tlačidlo podľa pravidiel
local isDragging = false
minimapIcon:SetScript("OnDragStart", function(self)
    self:LockHighlight(); isDragging = true
    self:SetScript("OnUpdate", function(self)
        local xpos, ypos = GetCursorPosition()
        local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
        xpos = xmin - xpos/UIParent:GetScale() + 70
        ypos = ypos/UIParent:GetScale() - ymin - 70
        local angle = math.deg(math.atan2(ypos, xpos))
        local x, y = math.cos(math.rad(angle)) * 80, math.sin(math.rad(angle)) * 80
        self:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - x, y - 52)
    end)
end)
minimapIcon:SetScript("OnDragStop", function(self) self:UnlockHighlight(); isDragging = false; self:SetScript("OnUpdate", nil) end)
minimapIcon:SetScript("OnClick", function(self, button)
    if isDragging then return end
    if button == "LeftButton" then
        if IsShiftKeyDown() then 
            -- Shift + LeftClick otvorí nastavenia
            if SettingsFrame:IsShown() then SettingsFrame:Hide() else SettingsFrame:Show() end
        else
            -- Obyčajný LeftClick prepne hlavné okno
            if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end
        end
    end
end)

-- [[ GRID SYSTÉM A AUTO-VEĽKOSŤ ]]
function SausageSalvaMainFrame_UpdateGrid()
    if InCombatLockdown() or not SausageSalvaDB then return end 

    local boxWidth = SausageSalvaDB.btnWidth
    local boxHeight = SausageSalvaDB.btnHeight
    local maxCols = SausageSalvaDB.cols
    local spacing = SausageSalvaDB.spacing

    -- Aplikácia borderu a hlavičky
    if SausageSalvaDB.hideBorder then
        MainFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = nil, tile = true, tileSize = 16, edgeSize = 0,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        MainFrame:SetBackdropBorderColor(0, 0, 0, 0)
    else
        MainFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        MainFrame:SetBackdropBorderColor(1, 1, 1, 1)
    end

    if SausageSalvaDB.hideBackground then
        MainFrame:SetBackdropColor(0, 0, 0, 0)
    else
        MainFrame:SetBackdropColor(0, 0, 0, 1)
    end

    if SausageSalvaDB.hideHeader then
        header:Hide()
        title:Hide()
    else
        header:Show()
        title:Show()
    end
    -- Offset ostáva VŽDY rovnaký, aby grid neposkakoval
    ContentFrame:ClearAllPoints()
    ContentFrame:SetPoint("TOP", 0, -35)

    local row, col = 0, 0
    local units = {}

    if isTestMode then
        -- Simulácia 25 hráčov pre test
        for i=1, 25 do units[#units + 1] = "player" end
    else
        if IsInRaid() then
            for i=1, GetNumRaidMembers() do units[#units + 1] = "raid"..i end
        elseif GetNumPartyMembers() > 0 then
            units[#units + 1] = "player"
            for i=1, GetNumPartyMembers() do units[#units + 1] = "party"..i end
        else
            units[#units + 1] = "player" 
        end
    end

    local activeCount = 0
    for i = 1, 40 do
        local btn = unitButtons[i]
        local unit = units[i]
        local unitName = nil
        
        if isTestMode and i <= 25 then
            unitName = "TestPlayer " .. i
        elseif unit then
            unitName = UnitName(unit)
        end

        if unitName and (isTestMode or (unit and not SausageSalvaDB.ignored[unitName])) then
            btn:SetAttribute("unit", isTestMode and nil or unit)
            btn.targetUnit = isTestMode and "player" or unit
            btn.unitName = unitName -- Plné meno pre správne porovnanie focusu
            btn:SetSize(boxWidth, boxHeight)
            btn:SetFrameLevel(MainFrame:GetFrameLevel() + 5) -- Vynútenie vrstvy navrchu
            btn.text:SetText(string.sub(unitName, 1, 6))
            if SausageSalvaDB.hideNames then btn.text:Hide() else btn.text:Show() end
            btn.threatText:SetText("0%")
            if SausageSalvaDB.hideThreat then btn.threatText:Hide() else btn.threatText:Show() end
            
            btn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.9)
            btn.border:SetBackdropBorderColor(1, 1, 1, 0.5) -- Biely okraj pre test viditeľnosti
            
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", col * (boxWidth + spacing), -row * (boxHeight + spacing))
            
            -- Force zobrazenie
            btn:Show()
            btn:SetAlpha(1)

            activeCount = activeCount + 1
            col = col + 1
            if col >= maxCols then
                col = 0
                row = row + 1
            end
        else
            btn:SetAttribute("unit", nil)
            btn.targetUnit = nil
            btn:Hide()
        end
    end

    -- Dynamicka zmena velkosti okna
    if activeCount == 0 then activeCount = 1 end
    local finalRows = math.ceil(activeCount / maxCols)
    local finalCols = math.min(activeCount, maxCols)
    
    local newWidth = (finalCols * boxWidth) + ((finalCols - 1) * spacing) + 30
    local headerSize = (SausageSalvaDB.hideHeader and 20 or 45)
    local rlSize = 0
    if rlPanelText:IsShown() then rlSize = 15 end
    
    local newHeight = (finalRows * boxHeight) + ((finalRows - 1) * spacing) + headerSize + rlSize + 15
    
    -- Dynamický anchor pre zmenu veľkosti
    local anchor = SausageSalvaDB.anchor or "TOP"
    MainFrame:ClearAllPoints()
    MainFrame:SetSize(newWidth, newHeight)
    
    -- Vždy používame BOTTOMLEFT ako základný kotevný bod obrazovky (najstabilnejšie v 3.3.5)
    local screenX = SausageSalvaDB.frameX or (UIParent:GetWidth()/2)
    local screenY = SausageSalvaDB.frameY or (UIParent:GetHeight()/2)
    
    MainFrame:SetPoint(anchor, UIParent, "BOTTOMLEFT", screenX, screenY)
    
    -- Pozicionovanie ContentFrame v strede
    ContentFrame:ClearAllPoints()
    local topOffset = (SausageSalvaDB.hideHeader and -15 or -35)
    if rlPanelText:IsShown() then topOffset = topOffset - 15 end
    
    if anchor == "LEFT" then
        ContentFrame:SetPoint("LEFT", 15, 0)
    elseif anchor == "RIGHT" then
        ContentFrame:SetPoint("RIGHT", -15, 0)
    elseif anchor == "BOTTOM" then
        ContentFrame:SetPoint("BOTTOM", 0, 15)
    else
        ContentFrame:SetPoint("TOP", 0, topOffset)
    end
    
    ContentFrame:SetSize(newWidth - 30, (finalRows * boxHeight) + (finalRows * spacing))
end

-- Tvorba profi tlacidiel (Profi Textury + Tiene)
local function CreateGridButtons()
    for i = 1, 40 do
        local btn = CreateFrame("Button", "SausageSalvaBtn"..i, ContentFrame, "SecureActionButtonTemplate")
        
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        btn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.9)
        
        btn.border = CreateFrame("Frame", nil, btn)
        btn.border:SetAllPoints()
        btn.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn.border:SetBackdropBorderColor(0, 0, 0, 1)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("TOP", 0, -4)
        btn.text:SetTextColor(1, 1, 1, 1)
        btn.text:SetShadowColor(0, 0, 0, 1)
        btn.text:SetShadowOffset(1, -1)
        
        btn.threatText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.threatText:SetPoint("BOTTOM", 0, 4)
        btn.threatText:SetTextColor(1, 1, 1, 1)
        btn.threatText:SetShadowColor(0, 0, 0, 1)
        btn.threatText:SetShadowOffset(1, -1)

        -- Červený kríž pre Focus (Ping)
        btn.cross = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        btn.cross:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Flash")
        btn.cross:SetPoint("CENTER")
        btn.cross:SetSize(40, 40)
        btn.cross:SetVertexColor(1, 0, 0, 1)
        btn.cross:SetBlendMode("ADD")
        btn.cross:Hide()

        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", SALVA_SPELL_NAME)
        
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:HookScript("OnClick", function(self, button)
            local targetName = UnitName(self.targetUnit)
            if not targetName then return end

            if button == "RightButton" then
                if IsRaidLeader() or IsRaidOfficer() or not IsInRaid() then
                    if #activePaladins > 0 then
                        local chosenPaladin = activePaladins[1].name
                        SendComm("PING_CAST:"..targetName..":"..chosenPaladin)
                        local myName = UnitName("player")
                        if chosenPaladin == myName then
                            print("|cFF00CCFF[SausageSalva]|r Assigning cast to yourself.")
                        else
                            print("|cFF00CCFF[SausageSalva]|r Assigning cast to " .. chosenPaladin)
                        end
                    else
                        print("|cFFFF0000[SausageSalva]|r No Paladins available!")
                    end
                else
                    print("|cFFFF0000[SausageSalva]|r Only Raid Leader or Officer can delegate casts.")
                end
            elseif button == "LeftButton" then
                SendComm("PRE_CAST:"..targetName)
                focusTarget = nil 
            end
        end)
        
        btn:Hide()
        unitButtons[i] = btn
    end
end

-- [[ UPDATE LOGIKA V BOJI ]]
local function CleanupPaladinList()
    local changed = false
    for i = #activePaladins, 1, -1 do
        local name = activePaladins[i].name
        -- Ak hráč už nie je v skupine/raide, odstránime ho
        if not UnitInRaid(name) and not UnitInParty(name) then
            table.remove(activePaladins, i)
            changed = true
        end
    end
    return changed
end

function SortPaladins()
    CleanupPaladinList()
    table.sort(activePaladins, function(a, b) return a.spec < b.spec end)
    local text = "Available Paladins: "
    
    local displayStrings = {}
    for _, p in ipairs(activePaladins) do
        local color = (p.spec == 1) and "|cFFFFFF00" or (p.spec == 2) and "|cFFFF8800" or "|cFFFF0000"
        table.insert(displayStrings, color .. p.name .. "|r")
    end

    if isTestMode then
        table.insert(displayStrings, "|cFFFFFF00TestHoly|r")
        table.insert(displayStrings, "|cFFFF8800TestProt|r")
        table.insert(displayStrings, "|cFFFF0000TestRet|r")
    end

    if #displayStrings == 0 then
        text = text .. "|cFF888888None|r"
    else
        text = text .. table.concat(displayStrings, " ")
    end
    rlPanelText:SetText(text)
end

function UpdateCombatGrid(dt)
    -- Ak nie je okno zobrazené, nič nepočítame (šetrenie výkonu)
    if not MainFrame:IsShown() then return end

    local pulse = (math.sin(GetTime() * 5) + 1) / 2
    local inFocusMode = (focusTarget ~= nil and focusTimer > 0)
    
    if focusTimer > 0 then focusTimer = focusTimer - dt end

    for i = 1, 40 do
        local btn = unitButtons[i]
        if btn:IsShown() then
            local unit = btn.targetUnit
            local unitName = btn.unitName or btn.text:GetText()
            
            local threatPct = 0
            if isTestMode then
                threatPct = (i * 7) % 135
            elseif unit and UnitExists(unit) then
                local _, _, pct = UnitDetailedThreatSituation(unit, "target")
                threatPct = pct or 0
            end

            btn.threatText:SetText(string.format("%d%%", threatPct))

            local threshold = 100
            if not isTestMode and unit then
                local _, class = UnitClass(unit)
                threshold = (class == "MAGE" or class == "WARLOCK" or class == "PRIEST") and 120 or 100
            end
            local isTestSalva = isTestMode and (i == 3 or i == 7)
            local isTestFocus = isTestMode and (i == 5)
            
            local hasSalva = false
            if isTestSalva then 
                hasSalva = true 
            elseif unit and UnitExists(unit) then
                if UnitBuff(unit, SALVA_SPELL_NAME) then hasSalva = true end
            end

            if isTestFocus or inFocusMode then
                if (isTestMode and isTestFocus) or (not isTestMode and unitName and focusTarget and string.lower(unitName) == string.lower(focusTarget)) then
                    -- Príkaz na Salvu: Biele pulzovanie pozadia + Červený pulzujúci kríž
                    btn.bg:SetVertexColor(0.6 + (pulse * 0.4), 0.6 + (pulse * 0.4), 0.6 + (pulse * 0.4), 0.9)
                    btn.cross:SetAlpha(0.4 + (pulse * 0.6))
                    btn.cross:Show()
                else
                    btn.bg:SetVertexColor(0.1, 0.1, 0.1, 0.5) -- Ostatné stmavené
                    btn.cross:Hide()
                end
            else
                btn.cross:Hide()
                if threatPct >= threshold then
                    btn.bg:SetVertexColor(0.6 + (pulse * 0.4), 0, 0, 0.9) -- Agresívna červená
                elseif threatPct > 0 then
                    local redIntensity = (threatPct / threshold) * 0.6
                    btn.bg:SetVertexColor(0.2 + redIntensity, 0.2, 0.2, 0.9) -- Postupne do červena
                else
                    btn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.9) -- Základná tmavosivá
                end
            end

            -- Salva prebíja farbu (Modro-Zlatý pulz)
            if hasSalva then
                local r = 0.8 * (1 - pulse)
                local g = 0.7 * (1 - pulse) + (0.5 * pulse)
                local b = 1.0 * pulse
                btn.bg:SetVertexColor(r, g, b, 0.95)
            end
        end
    end
end

function BroadcastPaladinStatus()
    if not isPaladin then return end
    local start, duration = GetSpellCooldown(SALVA_SPELL_NAME)
    local isReady = (start == 0 or duration <= 1.5) and 1 or 0
    local spec = GetPaladinSpec()
    SendComm("ANNOUNCE:"..spec..":"..isReady)
end

-- [[ EVENTY A INICIALIZACIA DB ]]
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
EventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
EventFrame:RegisterEvent("CHAT_MSG_ADDON")
EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
EventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            -- REGISTRÁCIA PREFIXU (Dôležité pre 3.3.5)
            if RegisterAddonMessagePrefix then
                RegisterAddonMessagePrefix(PREFIX)
            end
            
            SausageSalvaDB = SausageSalvaDB or {}
            for k, v in pairs(defaultDB) do
                if SausageSalvaDB[k] == nil then SausageSalvaDB[k] = v end
            end

            if SausageSalvaDB.framePoint then
                SausageSalvaDB.anchor = SausageSalvaDB.framePoint
                SausageSalvaDB.framePoint = nil
            end

            -- If coordinates are missing or old relative format (negative Y), reset to default
            if not SausageSalvaDB.frameY or SausageSalvaDB.frameY < 0 then
                SausageSalvaDB.frameX = UIParent:GetWidth() / 2
                SausageSalvaDB.frameY = UIParent:GetHeight() - 100
            end

            MainFrame:ClearAllPoints()
            
            -- Tlačidlá MUSIA byť vytvorené PRED prvým UpdateGrid
            CreateGridButtons()
            
            if SausageSalvaDB.isShown == false or SausageSalvaDB.autoHide then MainFrame:Hide() else MainFrame:Show() end
            
            -- Prvý update gridu až po vytvorení tlačidiel
            SausageSalvaMainFrame_UpdateGrid()
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        local showList = IsInRaid() and (IsRaidLeader() or IsRaidOfficer())
        if showList then rlPanelText:Show() else rlPanelText:Hide() end
        CleanupPaladinList()
        SortPaladins()
        SausageSalvaMainFrame_UpdateGrid()
        if SettingsFrame:IsShown() then UpdateIgnoreScrollFrame() end
        BroadcastPaladinStatus()
        
        -- Ak sme prišli do sveta a nie sme leader, vyžiadame si ignore list
        if event == "PLAYER_ENTERING_WORLD" and not (IsRaidLeader() or IsRaidOfficer()) then
            SendComm("REQ_IGNORE")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if SausageSalvaDB and SausageSalvaDB.autoHide then 
            MainFrame:Show() 
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        focusTarget = nil 
        if SausageSalvaDB and SausageSalvaDB.autoHide then 
            MainFrame:Hide() 
        end
        SausageSalvaMainFrame_UpdateGrid() 
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        BroadcastPaladinStatus()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix == PREFIX then
            local args = {strsplit(":", msg)}
            local cmd = args[1]

            if cmd == "CHECK" then SendComm("VERSION:"..SAUSAGE_VERSION)
            elseif cmd == "VERSION" then print("|cFFFFFF00[SausageSalva]|r " .. sender .. " má verziu " .. args[2])
            elseif cmd == "TOGGLE_IGNORE" then
                local ignoredName = args[2]
                if SausageSalvaDB.ignored[ignoredName] then
                    SausageSalvaDB.ignored[ignoredName] = false
                    print("|cFF00FF00[SausageSalva]|r Unignored: " .. ignoredName)
                else
                    SausageSalvaDB.ignored[ignoredName] = true
                    print("|cFFFF0000[SausageSalva]|r Ignored: " .. ignoredName)
                end
                if SettingsFrame:IsShown() then UpdateIgnoreScrollFrame() end
                if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
            elseif cmd == "REQ_IGNORE" then
                -- Iba leader/officer odpovedá na žiadosť o ignore list
                if IsRaidLeader() or IsRaidOfficer() or (not IsInRaid() and IsInGroup()) then
                    local list = ""
                    for name, isIgnored in pairs(SausageSalvaDB.ignored) do
                        if isIgnored then
                            list = list .. name .. ","
                        end
                    end
                    if list ~= "" then
                        SendComm("IGNORE_LIST:"..list)
                    end
                end
            elseif cmd == "IGNORE_LIST" then
                local list = args[2]
                if list then
                    local names = {strsplit(",", list)}
                    -- Pri hromadnej synchronizácii najprv vyčistíme starý list (iba u prijímateľa)
                    -- aby sme presne kopírovali nastavenie leadera
                    wipe(SausageSalvaDB.ignored)
                    for _, n in ipairs(names) do
                        if n ~= "" then
                            SausageSalvaDB.ignored[n] = true
                        end
                    end
                    if SettingsFrame:IsShown() then UpdateIgnoreScrollFrame() end
                    if not InCombatLockdown() then SausageSalvaMainFrame_UpdateGrid() end
                end
            elseif cmd == "ANNOUNCE" then
                -- Do zoznamu dostupných na delegáciu nebudeme pridávať samého seba
                if sender == UnitName("player") then return end

                local spec, isReady = tonumber(args[2]), tonumber(args[3])
                for i = #activePaladins, 1, -1 do
                    if activePaladins[i].name == sender then table.remove(activePaladins, i) end
                end
                if isReady == 1 then activePaladins[#activePaladins + 1] = {name = sender, spec = spec} end
                SortPaladins()
            elseif cmd == "PRE_CAST" then
                -- Message received, but no visual pulse triggered as per user request
            elseif cmd == "PING_CAST" then
                local targetName, assignedPaladin = args[2], args[3]
                local myName = UnitName("player")
                if assignedPaladin == myName then
                    focusTarget, focusTimer = targetName, 15.0 
                    -- Vynútenie OnUpdate ak sme náhodou mimo boja alebo v teste
                    EventFrame:SetScript("OnUpdate", function(self, elapsed) UpdateCombatGrid(elapsed) end)
                    print("|cFF00CCFF[SausageSalva]|r Cast Hand of Salvation on " .. targetName .. "!")
                    
                    if SausageSalvaDB.enableSound and SausageSalvaDB.soundFile and SausageSalvaDB.soundFile ~= "" then
                        PlaySoundFile(SausageSalvaDB.soundFile, "Master")
                    end
                end
            end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, sourceName, _, _, destName, _, spellId = ...
        if subEvent == "SPELL_CAST_SUCCESS" and spellId == SALVA_SPELL_ID and sourceName == UnitName("player") then
            if IsInGroup() then SendChatMessage("Hand of Salvation on " .. destName .. "!", IsInRaid() and "RAID" or "PARTY") end
            focusTarget = nil 
            BroadcastPaladinStatus()
        end
    end
end)

-- [[ SLASH COMMANDS ]]
SLASH_SAUSAGESALVA1 = "/ssalva"
SLASH_SAUSAGESALVA2 = "/salva"
SlashCmdList["SAUSAGESALVA"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "center" then
        if not InCombatLockdown() then
            SausageSalvaDB.anchor = "TOP"
            SausageSalvaDB.frameX = UIParent:GetWidth() / 2
            SausageSalvaDB.frameY = UIParent:GetHeight() - 100
            SausageSalvaMainFrame_UpdateGrid()
            print("|cFFFFFF00[SausageSalva]|r Addon centered (Top-Center).")
        else
            print("|cFFFF0000[SausageSalva]|r Cannot center while in combat!")
        end
    elseif msg == "settings" or msg == "config" then
        if SettingsFrame:IsShown() then SettingsFrame:Hide() else SettingsFrame:Show() end
    else
        if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end
    end
end