-- AbundanceTracker — Options.lua
-- Compact draggable options panel for /at and /abt.
-- Styled after JetTools: dark background, blue border, tooltip-style backdrops.
-- Uses LibSharedMedia-3.0 for font picker.

-- ──────────────────────────────────────────────────────────────
-- Upvalues
-- ──────────────────────────────────────────────────────────────

local math_floor    = math.floor
local math_max      = math.max
local math_min      = math.min
local C_Timer       = C_Timer
local UIParent      = UIParent

-- ──────────────────────────────────────────────────────────────
-- Constants
-- ──────────────────────────────────────────────────────────────

local PANEL_W  = 300
local PANEL_H  = 510
local PAD      = 14     -- outer padding / left margin for widgets
local COL_W    = PANEL_W - PAD * 2   -- usable content width
local ITEM_H   = 18     -- font dropdown row height

-- Shared backdrop style (matches JetTools throughout)
local BACKDROP_FRAME = {
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}
local BACKDROP_WIDGET = {
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 12,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- ──────────────────────────────────────────────────────────────
-- State
-- ──────────────────────────────────────────────────────────────

local optionsFrame = nil

-- ──────────────────────────────────────────────────────────────
-- DB accessors
-- ──────────────────────────────────────────────────────────────

local function GetDB(key)
    return AbundanceTracker.GetDB(key)
end

local function SetDB(key, value)
    AbundanceTracker.SetDB(key, value)
    AbundanceTracker.ApplySettings()
end

-- ──────────────────────────────────────────────────────────────
-- Widget: Section header
-- Returns new yOffset after placing the header.
-- ──────────────────────────────────────────────────────────────

local function CreateHeader(parent, text, yOffset)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", PAD, yOffset)
    fs:SetText("|cffaa66ff" .. text .. "|r")
    return yOffset - 20
end

-- ──────────────────────────────────────────────────────────────
-- Widget: Separator line
-- Returns new yOffset.
-- ──────────────────────────────────────────────────────────────

local function CreateSeparator(parent, yOffset)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PAD,       yOffset)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD,      yOffset)
    sep:SetColorTexture(0.3, 0.4, 0.6, 0.8)
    return yOffset - 10
end

-- ──────────────────────────────────────────────────────────────
-- Widget: Integer slider
-- Returns new yOffset (consumes ~52 px).
-- ──────────────────────────────────────────────────────────────

local function CreateSlider(parent, labelText, key, minVal, maxVal, step, yOffset)
    -- Label
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", PAD, yOffset)
    lbl:SetText(labelText)
    yOffset = yOffset - 18

    -- Slider
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", PAD + 4, yOffset)
    slider:SetWidth(COL_W - 8)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(GetDB(key) or AbundanceTracker.GetDefaults()[key])

    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    -- Value display in the centre label slot
    local function UpdateValueText(val)
        slider.Text:SetText(tostring(math_floor(val + 0.5)))
    end
    UpdateValueText(slider:GetValue())

    slider:SetScript("OnValueChanged", function(self, val)
        local rounded = math_floor(val + 0.5)
        UpdateValueText(rounded)
        SetDB(key, rounded)
    end)

    return yOffset - 30   -- slider is ~20 px tall + gap
end

-- ──────────────────────────────────────────────────────────────
-- Widget: Checkbox
-- Returns new yOffset (consumes ~28 px).
-- ──────────────────────────────────────────────────────────────

local function CreateCheckbox(parent, labelText, key, yOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", PAD, yOffset)
    cb:SetSize(20, 20)
    cb:SetChecked(GetDB(key) or false)

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(labelText)

    cb:SetScript("OnClick", function(self)
        SetDB(key, self:GetChecked())
    end)

    return yOffset - 28
end

-- ──────────────────────────────────────────────────────────────
-- Widget: Font dropdown (LibSharedMedia-3.0)
-- Returns new yOffset (consumes ~50 px).
-- ──────────────────────────────────────────────────────────────

local function CreateFontDropdown(parent, labelText, key, yOffset)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    -- Build sorted font name list once
    local fontNames = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            fontNames[#fontNames + 1] = name
        end
        table.sort(fontNames)
    else
        fontNames = { "Friz Quadrata TT" }
    end

    -- Helper: path → display name
    local function PathToName(path)
        if LSM then
            for name, p in pairs(LSM:HashTable("font")) do
                if p == path then return name end
            end
        end
        local bare = (path or ""):match("([^\\]+)$") or path
        return bare:gsub("%.[Tt][Tt][Ff]$", "")
    end

    -- Label
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", PAD, yOffset)
    lbl:SetText(labelText)
    yOffset = yOffset - 18

    -- Toggle button (shows current selection)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", PAD, yOffset)
    btn:SetSize(COL_W, 22)
    btn:SetBackdrop(BACKDROP_WIDGET)
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.4, 0.6)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("LEFT", 8, 0)
    btnText:SetPoint("RIGHT", -20, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetText(PathToName(GetDB(key) or AbundanceTracker.GetDefaults()[key]))
    btn.text = btnText

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetSize(12, 12)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    -- Drop list
    local listH   = math_min(#fontNames * ITEM_H, 160)
    local listFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    listFrame:SetSize(COL_W, listH)
    listFrame:SetBackdrop(BACKDROP_WIDGET)
    listFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    listFrame:SetBackdropBorderColor(0.3, 0.4, 0.6)
    listFrame:SetFrameStrata("TOOLTIP")
    listFrame:Hide()

    -- Scroll frame inside list
    local scrollFrame = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     listFrame, "TOPLEFT",     5,  -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -26, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(COL_W - 30, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local function PopulateList()
        -- Clear existing children
        for _, child in ipairs({ scrollChild:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end

        local yPos = 0
        for _, name in ipairs(fontNames) do
            local row = CreateFrame("Button", nil, scrollChild)
            row:SetSize(COL_W - 35, ITEM_H)
            row:SetPoint("TOPLEFT", 0, -yPos)

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.2)

            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", 5, 0)
            fs:SetPoint("RIGHT", -5, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(name)
            if LSM then
                local p = LSM:Fetch("font", name)
                if p then
                    local ok = pcall(fs.SetFont, fs, p, 11)
                    if not ok then fs:SetFont("Fonts\\FRIZQT__.TTF", 11) end
                end
            end

            local captureName = name
            row:SetScript("OnClick", function()
                local path = (LSM and LSM:Fetch("font", captureName)) or ("Fonts\\" .. captureName .. ".TTF")
                SetDB(key, path)
                btnText:SetText(captureName)
                listFrame:Hide()
            end)

            yPos = yPos + ITEM_H
        end
        scrollChild:SetHeight(math_max(yPos, 1))
    end

    -- Toggle on button click; auto-close when clicking outside
    btn:SetScript("OnClick", function()
        if listFrame:IsShown() then
            listFrame:Hide()
        else
            PopulateList()
            listFrame:Show()
        end
    end)

    listFrame:SetScript("OnShow", function()
        listFrame:SetScript("OnUpdate", function()
            if not btn:IsMouseOver() and not listFrame:IsMouseOver() then
                if IsMouseButtonDown("LeftButton") then
                    listFrame:Hide()
                end
            end
        end)
    end)
    listFrame:SetScript("OnHide", function()
        listFrame:SetScript("OnUpdate", nil)
    end)

    return yOffset - 30   -- button (22) + gap
end

-- ──────────────────────────────────────────────────────────────
-- Panel construction
-- ──────────────────────────────────────────────────────────────

local function CreateOptionsPanel()
    if optionsFrame then
        optionsFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "AbundanceTrackerOptionsFrame", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_W, PANEL_H)
    f:SetPoint("CENTER")
    f:SetBackdrop(BACKDROP_FRAME)
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    f:SetBackdropBorderColor(0.3, 0.4, 0.6)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- Escape closes the panel
    table.insert(UISpecialFrames, "AbundanceTrackerOptionsFrame")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff4dff4dAbundance|rTracker Options")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Content area (inset: 15 left/right/bottom, 40 from top)
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     f, "TOPLEFT",     15, -40)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -15, 15)

    -- ── Layout ───────────────────────────────────────────────
    local y = 0  -- relative to content frame's TOPLEFT

    -- Position section
    y = CreateHeader(content, "Position", y)
    y = CreateSlider(content, "X Offset", "posX", -800, 800, 1, y)
    y = CreateSlider(content, "Y Offset", "posY", -600, 600, 1, y)
    y = CreateCheckbox(content, "Lock position", "locked", y)

    y = CreateSeparator(content, y)

    -- Icon section
    y = CreateHeader(content, "Icon", y)
    y = CreateSlider(content, "Size", "iconSize", 24, 128, 2, y)

    y = CreateSeparator(content, y)

    -- Duration text section
    y = CreateHeader(content, "Duration Text", y)
    y = CreateFontDropdown(content, "Font", "durationFont", y)
    y = CreateSlider(content, "Font Size", "durationFontSize", 8, 48, 1, y)

    y = CreateSeparator(content, y)

    -- Stack count text section
    y = CreateHeader(content, "Stack Count Text", y)
    y = CreateFontDropdown(content, "Font", "stackFont", y)
    y = CreateSlider(content, "Font Size", "stackFontSize", 8, 48, 1, y)

    -- Reset button (bottom-left of the main frame, outside content area)
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 24)
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    resetBtn:SetText("Reset Defaults")
    resetBtn:SetScript("OnClick", function()
        local defaults = AbundanceTracker.GetDefaults()
        for k, v in pairs(defaults) do
            AbundanceTracker.SetDB(k, v)
        end
        AbundanceTracker.ApplySettings()
        -- Rebuild panel to reflect new values
        f:Hide()
        optionsFrame = nil
        f:SetParent(nil)
        C_Timer.After(0, CreateOptionsPanel)
    end)

    optionsFrame = f
    f:Show()
end

-- ──────────────────────────────────────────────────────────────
-- Slash commands: /at and /abt
-- Deferred by one tick so the chat editbox closes before the
-- options frame appears (prevents the editbox staying open).
-- ──────────────────────────────────────────────────────────────

SLASH_ABUNDANCETRACKER1 = "/at"
SLASH_ABUNDANCETRACKER2 = "/abt"
SlashCmdList["ABUNDANCETRACKER"] = function()
    C_Timer.After(0, function()
        if optionsFrame and optionsFrame:IsShown() then
            optionsFrame:Hide()
        else
            CreateOptionsPanel()
        end
    end)
end
