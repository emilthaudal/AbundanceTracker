-- AbundanceTracker — Options.lua
-- Slash-command options panel for /at and /abt.
-- Uses LibSharedMedia-3.0 for font picker.
-- Calls AbundanceTracker.ApplySettings() on every change.

-- ──────────────────────────────────────────────────────────────
-- Upvalues
-- ──────────────────────────────────────────────────────────────

local math_floor    = math.floor
local math_max      = math.max
local math_min      = math.min
local string_format = string.format
local LibStub       = LibStub
local UIParent      = UIParent

-- ──────────────────────────────────────────────────────────────
-- Constants
-- ──────────────────────────────────────────────────────────────

local PANEL_W          = 360
local PANEL_H          = 480
local PANEL_TITLE      = "AbundanceTracker Options"
local SLIDER_W         = 260
local FONTLIST_W       = 240
local ROW_H            = 28
local PAD              = 14
local LABEL_W          = 110

-- ──────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────

local optionsFrame = nil

local function GetDB(key)
    return AbundanceTracker.GetDB(key)
end

local function SetDB(key, value)
    AbundanceTracker.SetDB(key, value)
    AbundanceTracker.ApplySettings()
end

-- ──────────────────────────────────────────────────────────────
-- Widget factories
-- ──────────────────────────────────────────────────────────────

---Create a label FontString anchored at the given relative frame/y
---@param parent Frame
---@param text string
---@param relY number
---@return FontString
local function CreateLabel(parent, text, relY)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, relY)
    fs:SetWidth(LABEL_W)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

---Create a section header
---@param parent Frame
---@param text string
---@param relY number
---@return FontString
local function CreateHeader(parent, text, relY)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, relY)
    fs:SetText("|cffFFD700" .. text .. "|r")
    return fs
end

---Create an integer slider with label and value display
---@param parent Frame
---@param labelText string
---@param key string          SavedVariable key
---@param minVal number
---@param maxVal number
---@param step number
---@param relY number
---@return Slider
local function CreateSlider(parent, labelText, key, minVal, maxVal, step, relY)
    CreateLabel(parent, labelText, relY)

    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", LABEL_W + PAD + 4, relY + 4)
    slider:SetWidth(SLIDER_W - LABEL_W)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(GetDB(key) or AbundanceTracker.GetDefaults()[key])

    -- Template creates these text children
    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    local valText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOP", slider, "BOTTOM", 0, 2)
    valText:SetText(tostring(math_floor(slider:GetValue())))
    slider.valText = valText

    slider:SetScript("OnValueChanged", function(self, val)
        val = math_floor(val)
        self.valText:SetText(tostring(val))
        SetDB(key, val)
    end)

    return slider
end

---Create a dropdown font picker backed by LibSharedMedia-3.0
---@param parent Frame
---@param labelText string
---@param key string          SavedVariable key storing the font path
---@param relY number
---@return Button  the dropdown button
local function CreateFontPicker(parent, labelText, key, relY)
    CreateLabel(parent, labelText, relY)

    local LSM = LibStub("LibSharedMedia-3.0", true)

    -- Simple button that opens a scrollable list panel
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", LABEL_W + PAD + 4, relY + 4)
    btn:SetSize(FONTLIST_W - LABEL_W, 22)

    local function GetFontName(path)
        if LSM then
            for name, p in pairs(LSM:HashTable("font")) do
                if p == path then return name end
            end
        end
        -- fallback: strip path and extension
        local bare = path:match("([^\\]+)$") or path
        return bare:gsub("%.TTF$", ""):gsub("%.ttf$", "")
    end

    local currentPath = GetDB(key) or AbundanceTracker.GetDefaults()[key]
    btn:SetText(GetFontName(currentPath))

    -- Drop-down list frame (lazy created)
    local listFrame = nil

    local function BuildList()
        if listFrame then
            listFrame:Show()
            return
        end

        local fonts = {}
        if LSM then
            for name, _ in pairs(LSM:HashTable("font")) do
                fonts[#fonts + 1] = name
            end
            table.sort(fonts)
        else
            fonts = { "Friz Quadrata TT", "Arial Narrow" }
        end

        local itemH  = 20
        local lf     = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        lf:SetSize(FONTLIST_W - LABEL_W, math_min(#fonts * itemH, 180))
        lf:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, 0)
        lf:SetFrameStrata("TOOLTIP")
        lf:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        lf:SetBackdropColor(0, 0, 0, 0.9)
        lf:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

        local scrollChild = CreateFrame("Frame", nil, lf)
        scrollChild:SetSize(FONTLIST_W - LABEL_W - 4, #fonts * itemH)

        local scroll = CreateFrame("ScrollFrame", nil, lf)
        scroll:SetPoint("TOPLEFT", lf, "TOPLEFT", 2, -2)
        scroll:SetPoint("BOTTOMRIGHT", lf, "BOTTOMRIGHT", -2, 2)
        scroll:SetScrollChild(scrollChild)

        for i, name in ipairs(fonts) do
            local row = CreateFrame("Button", nil, scrollChild)
            row:SetSize(FONTLIST_W - LABEL_W - 4, itemH)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * itemH)

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(row)
            hl:SetColorTexture(1, 1, 1, 0.08)

            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetAllPoints(row)
            fs:SetJustifyH("LEFT")
            fs:SetText("  " .. name)
            if LSM then
                local p = LSM:Fetch("font", name)
                if p then
                    local ok = pcall(fs.SetFont, fs, p, 11)
                    if not ok then
                        fs:SetFont("Fonts\\FRIZQT__.TTF", 11)
                    end
                end
            end

            local captureName = name
            row:SetScript("OnClick", function()
                local path = LSM and LSM:Fetch("font", captureName) or ("Fonts\\" .. captureName .. ".TTF")
                SetDB(key, path)
                btn:SetText(captureName)
                lf:Hide()
            end)
        end

        listFrame = lf
    end

    btn:SetScript("OnClick", function()
        if listFrame and listFrame:IsShown() then
            listFrame:Hide()
        else
            BuildList()
        end
    end)

    return btn
end

---Create a lock checkbox
---@param parent Frame
---@param relY number
---@return CheckButton
local function CreateLockCheckbox(parent, relY)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, relY)
    cb.Text:SetText("Lock position")
    cb:SetChecked(GetDB("locked") or false)
    cb:SetScript("OnClick", function(self)
        SetDB("locked", self:GetChecked())
    end)
    return cb
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
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)

    -- Title bar
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText(PANEL_TITLE)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Thin separator line under title
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -36)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -36)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Layout rows (relY counts from top, negative = downward)
    local y = -48

    -- ── Position ─────────────────────────────────────────────
    CreateHeader(f, "Position", y)
    y = y - ROW_H

    CreateSlider(f, "X Offset", "posX", -800, 800, 1, y)
    y = y - ROW_H * 2

    CreateSlider(f, "Y Offset", "posY", -600, 600, 1, y)
    y = y - ROW_H * 2

    CreateLockCheckbox(f, y)
    y = y - ROW_H + 4

    -- ── Icon ─────────────────────────────────────────────────
    CreateHeader(f, "Icon", y)
    y = y - ROW_H

    CreateSlider(f, "Size", "iconSize", 24, 128, 2, y)
    y = y - ROW_H * 2

    -- ── Duration Text ─────────────────────────────────────────
    CreateHeader(f, "Duration Text", y)
    y = y - ROW_H

    CreateFontPicker(f, "Font", "durationFont", y)
    y = y - ROW_H + 2

    CreateSlider(f, "Font Size", "durationFontSize", 8, 48, 1, y)
    y = y - ROW_H * 2

    -- ── Stack Count Text ──────────────────────────────────────
    CreateHeader(f, "Stack Count Text", y)
    y = y - ROW_H

    CreateFontPicker(f, "Font", "stackFont", y)
    y = y - ROW_H + 2

    CreateSlider(f, "Font Size", "stackFontSize", 8, 48, 1, y)
    y = y - ROW_H * 2

    -- ── Reset Button ──────────────────────────────────────────
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 26)
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    resetBtn:SetText("Reset Defaults")
    resetBtn:SetScript("OnClick", function()
        local defaults = AbundanceTracker.GetDefaults()
        for k, v in pairs(defaults) do
            AbundanceTracker.SetDB(k, v)
        end
        AbundanceTracker.ApplySettings()
        -- Rebuild panel so widgets reflect the new values
        f:Hide()
        optionsFrame = nil
        f:SetParent(nil)
        CreateOptionsPanel()
    end)

    optionsFrame = f
    f:Show()

    -- Register with UISpecialFrames so Escape closes it
    tinsert(UISpecialFrames, "AbundanceTrackerOptionsFrame")
end

-- ──────────────────────────────────────────────────────────────
-- Slash commands
-- ──────────────────────────────────────────────────────────────

SLASH_ABUNDANCETRACKER1 = "/at"
SLASH_ABUNDANCETRACKER2 = "/abt"
SlashCmdList["ABUNDANCETRACKER"] = function()
    if optionsFrame and optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        CreateOptionsPanel()
    end
end
