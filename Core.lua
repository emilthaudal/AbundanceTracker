-- AbundanceTracker — Core.lua
-- Tracks the shortest remaining Rejuvenation/Germination duration and total
-- combined aura count across all party/raid members.
--
-- Germination (talent) applies a second Rejuvenation-like HoT ("Rejuvenation (Germination)")
-- on the same target. Both count toward Abundance stacks (+8% Regrowth crit each, cap 12).
--
-- API: WoW Midnight 12.0.1 (Interface 120001)
--   Aura tracking: UNIT_AURA incremental diff + C_UnitAuras APIs
--   Scan filter: "HELPFUL PLAYER" to find player-cast buffs on friendly targets

-- ──────────────────────────────────────────────────────────────
-- Upvalues
-- ──────────────────────────────────────────────────────────────

local GetTime              = GetTime
local UnitExists           = UnitExists
local GetNumGroupMembers   = GetNumGroupMembers
local IsInRaid             = IsInRaid
local math_floor           = math.floor
local string_format        = string.format
local C_UnitAuras          = C_UnitAuras
local C_Timer              = C_Timer
local LibStub              = LibStub

-- ──────────────────────────────────────────────────────────────
-- Constants
-- ──────────────────────────────────────────────────────────────

local ADDON_NAME            = "AbundanceTracker"
local REJUV_SPELL_ID        = 774               -- Rejuvenation
local REJUV_SPELL_NAME      = "Rejuvenation"
local GERM_SPELL_ID         = 155777            -- Rejuvenation (Germination)
local GERM_SPELL_NAME       = "Rejuvenation (Germination)"
local TRACKED_IDS           = { [REJUV_SPELL_ID] = true, [GERM_SPELL_ID] = true }
local MAX_STACKS            = 12                -- 12 × 8% = 96% Abundance cap
local TICKER_RATE           = 0.1               -- seconds between display refreshes
local AURA_FILTER           = "HELPFUL PLAYER"

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
local isReady    = false

-- ──────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────

local function DB(key)
    return AbundanceTrackerDB[key]
end

local function SetDB(key, value)
    AbundanceTrackerDB[key] = value
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

-- Full rescan of a single unit — rebuilds its entire sub-table
local function ScanUnit(unit)
    if not UnitExists(unit) then
        rejuvCache[unit] = nil
        return
    end

    local unitEntry = {}

    -- Check both Rejuvenation and Rejuvenation (Germination)
    local aura1 = C_UnitAuras.GetAuraDataBySpellName(unit, REJUV_SPELL_NAME, AURA_FILTER)
    if aura1 and aura1.spellId == REJUV_SPELL_ID then
        unitEntry[aura1.auraInstanceID] = aura1.expirationTime
    end

    local aura2 = C_UnitAuras.GetAuraDataBySpellName(unit, GERM_SPELL_NAME, AURA_FILTER)
    if aura2 and aura2.spellId == GERM_SPELL_ID then
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

-- Process incremental UNIT_AURA updateInfo for a single unit
local function ProcessAuraUpdate(unit, info)
    if not UnitExists(unit) then
        rejuvCache[unit] = nil
        return
    end

    if info.isFullUpdate then
        ScanUnit(unit)
        return
    end

    -- Ensure the per-unit sub-table exists for add/update paths
    local unitEntry = rejuvCache[unit]

    -- Newly added auras
    if info.addedAuras then
        for _, aura in ipairs(info.addedAuras) do
            if TRACKED_IDS[aura.spellId] and aura.isFromPlayerOrPlayerPet then
                if not unitEntry then
                    unitEntry = {}
                    rejuvCache[unit] = unitEntry
                end
                unitEntry[aura.auraInstanceID] = aura.expirationTime
            end
        end
    end

    -- Updated auras — re-query by instanceID for fresh expirationTime
    if info.updatedAuraInstanceIDs and unitEntry then
        for _, instanceID in ipairs(info.updatedAuraInstanceIDs) do
            if unitEntry[instanceID] ~= nil then
                local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, instanceID)
                if aura then
                    unitEntry[instanceID] = aura.expirationTime
                else
                    unitEntry[instanceID] = nil
                end
            end
        end
    end

    -- Removed auras
    if info.removedAuraInstanceIDs and unitEntry then
        for _, instanceID in ipairs(info.removedAuraInstanceIDs) do
            unitEntry[instanceID] = nil
        end
    end

    -- Clean up empty unit entries
    if unitEntry and not next(unitEntry) then
        rejuvCache[unit] = nil
    end
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
        CreateMainFrame()

        if not ticker then
            ticker = C_Timer.NewTicker(TICKER_RATE, function()
                UpdateDisplay()
            end)
        end

        ScanAllUnits()

    elseif event == "UNIT_AURA" then
        if not isReady then return end
        local unit, info = ...
        if not info then
            ScanUnit(unit)
            return
        end
        ProcessAuraUpdate(unit, info)

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if not isReady then return end
        ScanAllUnits()
        UpdateDisplay()
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
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
