-- AbundanceTracker — Core.lua
-- Tracks the shortest remaining Rejuvenation/Germination duration and total
-- combined aura count across all party/raid members.
--
-- Germination (talent) applies a second Rejuvenation-like HoT ("Rejuvenation (Germination)")
-- on the same target. Both count toward Abundance stacks (+8% Regrowth crit each, cap 12).
--
-- Only active for Restoration Druids. Detects spec at login and on spec swap.
--
-- API: WoW Midnight 12.0.1 (Interface 120001)
--   Aura tracking: UNIT_AURA → ScanUnit (name-based, avoids secret value access)
--   Scan filter: "HELPFUL PLAYER" to find player-cast buffs on friendly targets

-- ──────────────────────────────────────────────────────────────
-- Upvalues
-- ──────────────────────────────────────────────────────────────

local GetTime                = GetTime
local UnitExists             = UnitExists
local UnitClass              = UnitClass
local GetNumGroupMembers     = GetNumGroupMembers
local IsInRaid               = IsInRaid
local math_floor             = math.floor
local string_format          = string.format
local C_UnitAuras            = C_UnitAuras
local C_Timer                = C_Timer
local C_SpecializationInfo   = C_SpecializationInfo
local LibStub                = LibStub

-- ──────────────────────────────────────────────────────────────
-- Constants
-- ──────────────────────────────────────────────────────────────

local ADDON_NAME             = "AbundanceTracker"
local REJUV_SPELL_NAME       = "Rejuvenation"
local GERM_SPELL_NAME        = "Rejuvenation (Germination)"
local MAX_STACKS             = 12                -- 12 × 8% = 96% Abundance cap
local TICKER_RATE            = 0.1               -- seconds between display refreshes
local AURA_FILTER            = "HELPFUL PLAYER"
local DRUID_CLASS_ID         = 11
local RESTO_DRUID_SPEC_ID    = 105

-- Defaults — merged into AbundanceTrackerDB at load if key is absent
local DEFAULTS = {
    posX             = 0,
    posY             = -200,
    iconSize         = 64,
    durationFont     = "Fonts\\FRIZQT__.TTF",
    durationFontSize = 18,
    stackFont        = "Fonts\\FRIZQT__.TTF",
    stackFontSize    = 14,
    locked           = false,
}

-- ──────────────────────────────────────────────────────────────
-- Saved variables & state
-- ──────────────────────────────────────────────────────────────

AbundanceTrackerDB = AbundanceTrackerDB or {}

-- Cache structure: rejuvCache[unitToken] = { [auraInstanceID] = expirationTime, ... }
-- Supports multiple auras per unit (Rejuvenation + Germination on same target).
local rejuvCache = {}

local mainFrame  = nil
local ticker     = nil
local isReady    = false   -- true once PLAYER_LOGIN has fired
local isEnabled  = false   -- true only when player is Resto Druid and addon is running

-- ──────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────

local function DB(key)
    return AbundanceTrackerDB[key]
end

local function SetDB(key, value)
    AbundanceTrackerDB[key] = value
end

---@return boolean
local function IsRestoDruid()
    local _, _, classId = UnitClass("player")
    if classId ~= DRUID_CLASS_ID then return false end

    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex then return false end

    local specId = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    return specId == RESTO_DRUID_SPEC_ID
end

---@param seconds number
---@return string
local function FormatDuration(seconds)
    if seconds <= 0 then return "0" end
    if seconds < 10 then
        return string_format("%.1f", seconds)
    end
    return string_format("%d", math_floor(seconds))
end

local function IterateGroup(callback)
    if IsInRaid() then
        local count = GetNumGroupMembers()
        for i = 1, count do
            callback("raid" .. i)
        end
    else
        callback("player")
        local count = GetNumGroupMembers()
        for i = 1, count do
            callback("party" .. i)
        end
    end
end

-- ──────────────────────────────────────────────────────────────
-- Aura cache management
-- ──────────────────────────────────────────────────────────────

-- Full rescan of a single unit — rebuilds its entire sub-table.
-- Uses GetAuraDataBySpellName (name-based) to avoid secret spellId comparisons.
-- auraInstanceID is documented NeverSecret and safe to use as a table key.
local function ScanUnit(unit)
    if not UnitExists(unit) then
        rejuvCache[unit] = nil
        return
    end

    local unitEntry = {}

    -- Rejuvenation
    local aura1 = C_UnitAuras.GetAuraDataBySpellName(unit, REJUV_SPELL_NAME, AURA_FILTER)
    if aura1 then
        unitEntry[aura1.auraInstanceID] = aura1.expirationTime
    end

    -- Rejuvenation (Germination)
    local aura2 = C_UnitAuras.GetAuraDataBySpellName(unit, GERM_SPELL_NAME, AURA_FILTER)
    if aura2 then
        unitEntry[aura2.auraInstanceID] = aura2.expirationTime
    end

    -- Only store an entry for this unit if we found at least one tracked aura
    if next(unitEntry) then
        rejuvCache[unit] = unitEntry
    else
        rejuvCache[unit] = nil
    end
end

local function ScanAllUnits()
    rejuvCache = {}
    IterateGroup(ScanUnit)
end

-- ──────────────────────────────────────────────────────────────
-- Display
-- ──────────────────────────────────────────────────────────────

local function ApplyFonts()
    if not mainFrame then return end
    local dFont = DB("durationFont")     or DEFAULTS.durationFont
    local dSize = DB("durationFontSize") or DEFAULTS.durationFontSize
    local sFont = DB("stackFont")        or DEFAULTS.stackFont
    local sSize = DB("stackFontSize")    or DEFAULTS.stackFontSize
    mainFrame.durationText:SetFont(dFont, dSize, "OUTLINE")
    mainFrame.stackText:SetFont(sFont, sSize, "OUTLINE")
end

local function ApplySizeAndPosition()
    if not mainFrame then return end
    local size = DB("iconSize") or DEFAULTS.iconSize
    local posX = DB("posX")     or DEFAULTS.posX
    local posY = DB("posY")     or DEFAULTS.posY

    mainFrame:SetSize(size, size)
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)

    local stackPad = math_floor(size * 0.08)
    mainFrame.stackText:ClearAllPoints()
    mainFrame.stackText:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -stackPad, stackPad)

    mainFrame.durationText:ClearAllPoints()
    mainFrame.durationText:SetPoint("CENTER", mainFrame, "CENTER", 0, math_floor(size * 0.05))

    -- Resize glow relative to new icon size
    mainFrame.glow:SetSize(size * 1.6, size * 1.6)
end

local function CreateMainFrame()
    if mainFrame then return end

    local size = DB("iconSize") or DEFAULTS.iconSize
    local posX = DB("posX")     or DEFAULTS.posX
    local posY = DB("posY")     or DEFAULTS.posY

    local f = CreateFrame("Frame", "AbundanceTrackerFrame", UIParent, "BackdropTemplate")
    f:SetSize(size, size)
    f:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not DB("locked") then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y   = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        SetDB("posX", math_floor(x - ux))
        SetDB("posY", math_floor(y - uy))
    end)

    -- Rejuvenation icon (spell 774 → fileID 136081)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(136081)
    bg:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.bg = bg

    -- Dark overlay for text readability
    local overlay = f:CreateTexture(nil, "ARTWORK")
    overlay:SetAllPoints(f)
    overlay:SetColorTexture(0, 0, 0, 0.35)
    f.overlay = overlay

    -- Green glow (shown at max stacks)
    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetSize(size * 1.6, size * 1.6)
    glow:SetPoint("CENTER", f, "CENTER", 0, 0)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    glow:SetVertexColor(0.1, 1.0, 0.2, 1.0)
    glow:Hide()
    f.glow = glow

    -- Duration text (center)
    local durationText = f:CreateFontString(nil, "OVERLAY")
    durationText:SetPoint("CENTER", f, "CENTER", 0, math_floor(size * 0.05))
    durationText:SetJustifyH("CENTER")
    durationText:SetJustifyV("MIDDLE")
    durationText:SetShadowOffset(1, -1)
    durationText:SetShadowColor(0, 0, 0, 1)
    f.durationText = durationText

    -- Stack count text (bottom-right)
    local stackText = f:CreateFontString(nil, "OVERLAY")
    local stackPad  = math_floor(size * 0.08)
    stackText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -stackPad, stackPad)
    stackText:SetJustifyH("RIGHT")
    stackText:SetShadowOffset(1, -1)
    stackText:SetShadowColor(0, 0, 0, 1)
    f.stackText = stackText

    -- Border
    f:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)

    mainFrame = f

    ApplyFonts()
    ApplySizeAndPosition()

    f:Hide()
end

local function UpdateDisplay()
    if not mainFrame then return end

    local now    = GetTime()
    local count  = 0
    local minExp = nil

    for _, unitEntry in pairs(rejuvCache) do
        for _, expTime in pairs(unitEntry) do
            local remaining = expTime - now
            if remaining > 0 then
                count = count + 1
                if not minExp or expTime < minExp then
                    minExp = expTime
                end
            end
        end
    end

    if count == 0 then
        mainFrame:Hide()
        return
    end

    mainFrame:Show()

    -- Duration text: shortest remaining across all tracked auras
    local minRemaining = minExp - now
    mainFrame.durationText:SetText(FormatDuration(minRemaining))

    if minRemaining > 4 then
        mainFrame.durationText:SetTextColor(1, 1, 1, 1)
    elseif minRemaining > 2 then
        mainFrame.durationText:SetTextColor(1, 0.8, 0, 1)
    else
        mainFrame.durationText:SetTextColor(1, 0.2, 0.2, 1)
    end

    -- Stack count text
    mainFrame.stackText:SetText(count)

    if count >= MAX_STACKS then
        mainFrame.stackText:SetTextColor(1, 0.85, 0, 1)
        mainFrame.glow:Show()
    else
        mainFrame.stackText:SetTextColor(1, 1, 1, 1)
        mainFrame.glow:Hide()
    end
end

-- ──────────────────────────────────────────────────────────────
-- Enable / disable lifecycle
-- ──────────────────────────────────────────────────────────────

local function EnableAddon()
    if isEnabled then return end
    isEnabled = true

    CreateMainFrame()

    if not ticker then
        ticker = C_Timer.NewTicker(TICKER_RATE, function()
            UpdateDisplay()
        end)
    end

    ScanAllUnits()
end

local function DisableAddon()
    if not isEnabled then return end
    isEnabled = false

    if ticker then
        ticker:Cancel()
        ticker = nil
    end

    rejuvCache = {}

    if mainFrame then
        mainFrame:Hide()
    end
end

-- ──────────────────────────────────────────────────────────────
-- Event handler
-- ──────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON_NAME then return end

        for key, default in pairs(DEFAULTS) do
            if AbundanceTrackerDB[key] == nil then
                AbundanceTrackerDB[key] = default
            end
        end

        print("|cff4dff4dAbundanceTracker|r loaded. Type |cffFFD700/at|r to open options.")

    elseif event == "PLAYER_LOGIN" then
        isReady = true

        if IsRestoDruid() then
            EnableAddon()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end

        if IsRestoDruid() then
            EnableAddon()
        else
            DisableAddon()
        end

    elseif event == "UNIT_AURA" then
        if not isEnabled then return end
        local unit = ...
        -- Always do a full name-based scan — avoids all secret value access
        -- (info.isFullUpdate, aura.spellId, aura.isFromPlayerOrPlayerPet are
        -- all potentially secret in combat in WoW Midnight 12.0.1)
        ScanUnit(unit)

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if not isEnabled then return end
        ScanAllUnits()
        UpdateDisplay()
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ──────────────────────────────────────────────────────────────
-- Public API (used by Options.lua)
-- ──────────────────────────────────────────────────────────────

AbundanceTracker = AbundanceTracker or {}

function AbundanceTracker.GetDB(key)
    return DB(key)
end

function AbundanceTracker.SetDB(key, value)
    SetDB(key, value)
end

function AbundanceTracker.ApplySettings()
    if not mainFrame then return end
    ApplySizeAndPosition()
    ApplyFonts()
    UpdateDisplay()
end

function AbundanceTracker.GetDefaults()
    return DEFAULTS
end
