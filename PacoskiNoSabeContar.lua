local ADDON_NAME = ...
local ADDON_TITLE = "PacoskiNoSabeContar"
local DUNGEON_DIFFICULTY_MYTHIC_KEYSTONE = 8
local MAX_NAMEPLATES = 40

local DEFAULTS = {
    enabled = true,
    showOnlyInMythicPlus = true,
    showRawValue = false,
    anchorPoint = "RIGHT",
    relativePoint = "RIGHT",
    x = 34,
    y = 0,
    fontSize = 14,
    fontFlags = "OUTLINE",
    fontPath = STANDARD_TEXT_FONT,
    fontLabel = "Default",
    textColor = { 1, 1, 1 },
    targetColor = { 1, 1, 1, 1 },
    otherColor = { 1, 1, 1, 0.75 },
    hideInCombat = false,
    debug = false,
}

local db
local activeTexts = {}
local storedTexts = {}
local eventFrame = CreateFrame("Frame")
local PARENT_TEXT_KEY = ADDON_NAME .. "Text"
local optionsPanel

local function CopyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. ADDON_TITLE .. ":|r " .. tostring(message))
end

local function EnsureDatabase()
    PacoskiNoSabeContarDB = CopyDefaults(PacoskiNoSabeContarDB, DEFAULTS)
    db = PacoskiNoSabeContarDB

    -- Migration: after pull-feature removal, force-hide-in-combat can leave all plates blank.
    if db.migrated_20260504_pull_removed ~= true then
        db.hideInCombat = false
        db.migrated_20260504_pull_removed = true
    end
end

local function IsMythicPlus()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then
        return false
    end

    local _, _, difficultyID = GetInstanceInfo()
    return difficultyID == DUNGEON_DIFFICULTY_MYTHIC_KEYSTONE
end

local function ShouldShow()
    if not db or db.enabled ~= true then
        return false
    end

    if db.debug == true then
        return true
    end

    if db.showOnlyInMythicPlus ~= true then
        return true
    end

    return IsMythicPlus()
end

local function GetEnemyForcesForUnit(unit)
    if not unit or not UnitExists(unit) or not UnitCanAttack("player", unit) then
        return nil
    end

    if not (C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues) then
        return nil
    end

    local value, _, percentString = C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)
    if percentString then
        return value, percentString
    end

    return nil
end

local function GetPlateForUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return nil
    end
    return C_NamePlate.GetNamePlateForUnit(unit)
end

local function GetTextParent(plateFrame)
    if not plateFrame then
        return UIParent
    end

    if plateFrame.unitFrame and plateFrame.unitFrame.healthBar then
        return plateFrame.unitFrame.healthBar
    end

    if plateFrame.unitFrame then
        return plateFrame.unitFrame
    end

    return plateFrame
end

local function AcquireText()
    local text = table.remove(storedTexts)
    if text then
        return text
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(6200)

    local fontString = frame:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint("CENTER")
    fontString:SetJustifyH("CENTER")
    fontString:SetJustifyV("MIDDLE")
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)

    return { frame = frame, fontString = fontString }
end

local function ReleaseText(unit)
    local text = activeTexts[unit]
    if not text then
        return
    end

    if text.parent and text.parent[PARENT_TEXT_KEY] == text then
        text.parent[PARENT_TEXT_KEY] = nil
    end

    text.unit = nil
    text.parent = nil
    text.fontString:SetText("")
    text.frame:Hide()
    text.frame:ClearAllPoints()
    text.frame:SetParent(UIParent)
    activeTexts[unit] = nil
    storedTexts[#storedTexts + 1] = text
end

local function ReleaseAllTexts()
    local unit = next(activeTexts)
    while unit do
        ReleaseText(unit)
        unit = next(activeTexts)
    end
end

local function FormatForcesText(value, percentString)
    if db.showRawValue == true then
        return tostring(value or "")
    end
    return tostring(percentString) .. "%"
end

local function ApplyTextStyle(text, unit)
    text.fontString:SetFont(db.fontPath or STANDARD_TEXT_FONT, db.fontSize or DEFAULTS.fontSize, db.fontFlags or DEFAULTS.fontFlags)
    local alphaColor = UnitIsUnit("target", unit) and db.targetColor or db.otherColor
    local rgbColor = db.textColor or DEFAULTS.textColor
    text.fontString:SetTextColor(rgbColor[1] or 1, rgbColor[2] or 1, rgbColor[3] or 1, alphaColor[4] or 1)
end

local function ShouldShowForUnit(unit)
    if db.hideInCombat == true and UnitAffectingCombat(unit) then
        return false
    end
    return true
end

local function UpdateUnit(unit)
    ReleaseText(unit)

    if not ShouldShow() then
        PrintDebug("skip " .. tostring(unit) .. " (ShouldShow=false)")
        return
    end

    local value, percentString = GetEnemyForcesForUnit(unit)
    if not percentString then
        return
    end

    if not ShouldShowForUnit(unit) then
        return
    end

    local plateFrame = GetPlateForUnit(unit)
    if not plateFrame then
        return
    end

    local text = AcquireText()
    local parent = GetTextParent(plateFrame)
    local previousText = parent[PARENT_TEXT_KEY]
    if previousText and previousText.unit and previousText.unit ~= unit then
        ReleaseText(previousText.unit)
    end

    text.frame:SetParent(parent)
    text.frame:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
    text.frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 20)
    text.frame:ClearAllPoints()
    text.frame:SetPoint(
        db.anchorPoint or DEFAULTS.anchorPoint,
        parent,
        db.relativePoint or DEFAULTS.relativePoint,
        db.x or DEFAULTS.x,
        db.y or DEFAULTS.y
    )

    ApplyTextStyle(text, unit)
    text.fontString:SetText(FormatForcesText(value, percentString))
    text.frame:SetSize(1, 1)
    text.frame:Show()

    text.unit = unit
    text.parent = parent
    parent[PARENT_TEXT_KEY] = text
    activeTexts[unit] = text
end

local function UpdateAllNameplates()
    if not ShouldShow() then
        ReleaseAllTexts()
        return
    end

    for index = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. index
        if UnitExists(unit) then
            UpdateUnit(unit)
        else
            ReleaseText(unit)
        end
    end
end

local function RefreshAfterDelay()
    C_Timer.After(0.2, UpdateAllNameplates)
    C_Timer.After(0.8, UpdateAllNameplates)
end

local function DisableBigWigsNameplateProgress()
    if not (BigWigsLoader and BigWigsLoader.db and BigWigsLoader.db.GetNamespace) then
        return false, "BigWigs database is not available."
    end

    local mythicPlusDB = BigWigsLoader.db:GetNamespace("MythicPlus", true)
    if not (mythicPlusDB and mythicPlusDB.profile) then
        return false, "BigWigs MythicPlus options are not loaded yet."
    end

    mythicPlusDB.profile.progressNameplate = false
    return true
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function ParseCommand(message)
    local args = {}
    for token in string.gmatch(message or "", "%S+") do
        args[#args + 1] = token
    end
    return args
end

local function OpenOptionsPanel()
    if not optionsPanel then
        return
    end

    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsPanel.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    end
end

local function CreateLabeledSlider(parent, labelText, minValue, maxValue, step, width)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(width or 260)
    slider.Text:SetText(labelText)
    slider.Low:SetText(tostring(minValue))
    slider.High:SetText(tostring(maxValue))
    slider.ValueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slider.ValueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    return slider
end

local function CreateLabel(parent, text, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetText(text)
    return label
end

local function BuildOptionsPanel()
    if optionsPanel then
        return
    end

    optionsPanel = CreateFrame("Frame", ADDON_NAME .. "OptionsPanel", UIParent)
    optionsPanel.name = ADDON_TITLE
    optionsPanel:EnableMouse(true)

    local scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "OptionsScrollFrame", optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", ADDON_NAME .. "OptionsContent", scrollFrame)
    content:SetSize(1, 900)
    scrollFrame:SetScrollChild(content)

    local title = CreateLabel(content, ADDON_TITLE, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local subtitle = CreateLabel(content, "Ajuste fino del texto en placas", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

    local offsetX = CreateLabeledSlider(content, "Offset X", -200, 200, 1, 300)
    offsetX:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 6, -36)
    local offsetY = CreateLabeledSlider(content, "Offset Y", -200, 200, 1, 300)
    offsetY:SetPoint("TOPLEFT", offsetX, "BOTTOMLEFT", 0, -48)
    local fontSize = CreateLabeledSlider(content, "Tamano de fuente", 6, 72, 1, 300)
    fontSize:SetPoint("TOPLEFT", offsetY, "BOTTOMLEFT", 0, -48)
    local alpha = CreateLabeledSlider(content, "Alpha (otros)", 0, 1, 0.01, 300)
    alpha:SetPoint("TOPLEFT", fontSize, "BOTTOMLEFT", 0, -48)
    local targetAlpha = CreateLabeledSlider(content, "Alpha (target)", 0, 1, 0.01, 300)
    targetAlpha:SetPoint("TOPLEFT", alpha, "BOTTOMLEFT", 0, -48)

    local hideCombatCheckbox = CreateFrame("CheckButton", ADDON_NAME .. "HideCombatCheck", content, "UICheckButtonTemplate")
    hideCombatCheckbox:SetPoint("TOPLEFT", targetAlpha, "BOTTOMLEFT", -6, -36)
    local hideCombatText = _G[hideCombatCheckbox:GetName() .. "Text"]
    if hideCombatText then
        hideCombatText:SetText("Ocultar texto en mobs en combate")
    end

    local flagsLabel = CreateLabel(content, "Font Flags", "GameFontHighlight")
    flagsLabel:SetPoint("TOPLEFT", hideCombatCheckbox, "BOTTOMLEFT", -6, -30)
    local flagsDropDown = CreateFrame("Frame", ADDON_NAME .. "FontFlagsDropDown", content, "UIDropDownMenuTemplate")
    flagsDropDown:SetPoint("TOPLEFT", flagsLabel, "BOTTOMLEFT", -14, -4)

    local anchorLabel = CreateLabel(content, "Anclaje", "GameFontHighlight")
    anchorLabel:SetPoint("TOPLEFT", flagsDropDown, "BOTTOMLEFT", 20, -24)
    local anchorDropDown = CreateFrame("Frame", ADDON_NAME .. "AnchorDropDown", content, "UIDropDownMenuTemplate")
    anchorDropDown:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", -14, -4)

    local fontLabel = CreateLabel(content, "Fuente", "GameFontHighlight")
    fontLabel:SetPoint("TOPLEFT", anchorDropDown, "BOTTOMLEFT", 20, -24)
    local fontDropDown = CreateFrame("Frame", ADDON_NAME .. "FontDropDown", content, "UIDropDownMenuTemplate")
    fontDropDown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -14, -4)

    local textColorLabel = CreateLabel(content, "Color de texto", "GameFontHighlight")
    textColorLabel:SetPoint("TOPLEFT", fontDropDown, "BOTTOMLEFT", 20, -24)
    local textColorSwatch = CreateFrame("Button", ADDON_NAME .. "TextColorSwatch", content)
    textColorSwatch:SetSize(28, 28)
    textColorSwatch:SetPoint("TOPLEFT", textColorLabel, "BOTTOMLEFT", 0, -6)
    textColorSwatch.bg = textColorSwatch:CreateTexture(nil, "BACKGROUND")
    textColorSwatch.bg:SetAllPoints()
    textColorSwatch.bg:SetColorTexture(0, 0, 0, 1)
    textColorSwatch.fill = textColorSwatch:CreateTexture(nil, "ARTWORK")
    textColorSwatch.fill:SetPoint("TOPLEFT", 2, -2)
    textColorSwatch.fill:SetPoint("BOTTOMRIGHT", -2, 2)

    local debugHeader = CreateLabel(content, "DEBUG", "GameFontNormal")
    debugHeader:SetPoint("TOPLEFT", textColorSwatch, "BOTTOMLEFT", 0, -28)
    local debugGeneralCheckbox = CreateFrame("CheckButton", ADDON_NAME .. "DebugGeneralCheck", content, "UICheckButtonTemplate")
    debugGeneralCheckbox:SetPoint("TOPLEFT", debugHeader, "BOTTOMLEFT", -4, -8)
    local debugGeneralText = _G[debugGeneralCheckbox:GetName() .. "Text"]
    if debugGeneralText then
        debugGeneralText:SetText("Debug general (/pnsc debug)")
    end

    local flagOptions = {
        { text = "None", value = "" },
        { text = "OUTLINE", value = "OUTLINE" },
        { text = "THICKOUTLINE", value = "THICKOUTLINE" },
        { text = "MONOCHROME", value = "MONOCHROME" },
        { text = "MONOCHROME,OUTLINE", value = "MONOCHROME,OUTLINE" },
    }

    local anchorOptions = {
        { text = "RIGHT / RIGHT", anchor = "RIGHT", relative = "RIGHT" },
        { text = "LEFT / LEFT", anchor = "LEFT", relative = "LEFT" },
        { text = "TOP / TOP", anchor = "TOP", relative = "TOP" },
        { text = "BOTTOM / BOTTOM", anchor = "BOTTOM", relative = "BOTTOM" },
        { text = "CENTER / CENTER", anchor = "CENTER", relative = "CENTER" },
    }

    local function BuildFontOptions()
        local options = { { text = "Default", value = STANDARD_TEXT_FONT } }
        if LibStub then
            local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
            if ok and lsm and lsm.HashTable then
                local fonts = lsm:HashTable("font")
                for name, path in pairs(fonts or {}) do
                    options[#options + 1] = { text = name, value = path }
                end
                table.sort(options, function(a, b) return a.text < b.text end)
            end
        end
        return options
    end
    local fontOptions = BuildFontOptions()

    local function SetSwatchColor()
        local color = db.textColor or DEFAULTS.textColor
        textColorSwatch.fill:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, 1)
    end

    local function SetDropdownTextByValue(dropdown, options, value, fallbackText)
        for _, option in ipairs(options) do
            if option.value == value then
                UIDropDownMenu_SetText(dropdown, option.text)
                return
            end
        end
        UIDropDownMenu_SetText(dropdown, fallbackText or "")
    end

    local function RefreshFromDb()
        EnsureDatabase()
        offsetX:SetValue(db.x or DEFAULTS.x)
        offsetX.ValueText:SetText(string.format("%.0f", db.x or DEFAULTS.x))
        offsetY:SetValue(db.y or DEFAULTS.y)
        offsetY.ValueText:SetText(string.format("%.0f", db.y or DEFAULTS.y))
        fontSize:SetValue(db.fontSize or DEFAULTS.fontSize)
        fontSize.ValueText:SetText(string.format("%d", db.fontSize or DEFAULTS.fontSize))
        alpha:SetValue((db.otherColor and db.otherColor[4]) or DEFAULTS.otherColor[4])
        alpha.ValueText:SetText(string.format("%.2f", (db.otherColor and db.otherColor[4]) or DEFAULTS.otherColor[4]))
        targetAlpha:SetValue((db.targetColor and db.targetColor[4]) or DEFAULTS.targetColor[4])
        targetAlpha.ValueText:SetText(string.format("%.2f", (db.targetColor and db.targetColor[4]) or DEFAULTS.targetColor[4]))
        hideCombatCheckbox:SetChecked(db.hideInCombat == true)
        debugGeneralCheckbox:SetChecked(db.debug == true)

        local selectedFlags = db.fontFlags or DEFAULTS.fontFlags
        for _, option in ipairs(flagOptions) do
            if option.value == selectedFlags then
                UIDropDownMenu_SetText(flagsDropDown, option.text)
                break
            end
        end

        local selectedText = "RIGHT / RIGHT"
        for _, option in ipairs(anchorOptions) do
            if option.anchor == (db.anchorPoint or DEFAULTS.anchorPoint) and option.relative == (db.relativePoint or DEFAULTS.relativePoint) then
                selectedText = option.text
                break
            end
        end
        UIDropDownMenu_SetText(anchorDropDown, selectedText)
        SetDropdownTextByValue(fontDropDown, fontOptions, db.fontPath or DEFAULTS.fontPath, db.fontLabel or DEFAULTS.fontLabel)
        SetSwatchColor()
    end

    offsetX:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.x = math.floor(value + 0.5)
        self.ValueText:SetText(string.format("%d", db.x))
        UpdateAllNameplates()
    end)
    offsetY:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.y = math.floor(value + 0.5)
        self.ValueText:SetText(string.format("%d", db.y))
        UpdateAllNameplates()
    end)
    fontSize:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.fontSize = Clamp(math.floor(value + 0.5), 6, 72)
        self.ValueText:SetText(string.format("%d", db.fontSize))
        UpdateAllNameplates()
    end)
    alpha:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.otherColor[4] = Clamp(value, 0, 1)
        self.ValueText:SetText(string.format("%.2f", db.otherColor[4]))
        UpdateAllNameplates()
    end)
    targetAlpha:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.targetColor[4] = Clamp(value, 0, 1)
        self.ValueText:SetText(string.format("%.2f", db.targetColor[4]))
        UpdateAllNameplates()
    end)
    hideCombatCheckbox:SetScript("OnClick", function(self)
        db.hideInCombat = self:GetChecked() == true
        UpdateAllNameplates()
    end)
    debugGeneralCheckbox:SetScript("OnClick", function(self)
        db.debug = self:GetChecked() == true
        UpdateAllNameplates()
    end)

    UIDropDownMenu_SetWidth(flagsDropDown, 200)
    UIDropDownMenu_Initialize(flagsDropDown, function(_, level)
        for _, option in ipairs(flagOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.checked = (db.fontFlags or DEFAULTS.fontFlags) == option.value
            info.func = function()
                db.fontFlags = option.value
                UIDropDownMenu_SetText(flagsDropDown, option.text)
                UpdateAllNameplates()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetWidth(anchorDropDown, 200)
    UIDropDownMenu_Initialize(anchorDropDown, function(_, level)
        for _, option in ipairs(anchorOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.checked = (db.anchorPoint == option.anchor and db.relativePoint == option.relative)
            info.func = function()
                db.anchorPoint = option.anchor
                db.relativePoint = option.relative
                UIDropDownMenu_SetText(anchorDropDown, option.text)
                UpdateAllNameplates()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetWidth(fontDropDown, 240)
    UIDropDownMenu_Initialize(fontDropDown, function(_, level)
        for _, option in ipairs(fontOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.checked = (db.fontPath or DEFAULTS.fontPath) == option.value
            info.func = function()
                db.fontPath = option.value
                db.fontLabel = option.text
                UIDropDownMenu_SetText(fontDropDown, option.text)
                UpdateAllNameplates()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local function ApplyTextColor(r, g, b)
        db.textColor = db.textColor or { 1, 1, 1 }
        db.textColor[1] = r
        db.textColor[2] = g
        db.textColor[3] = b
        SetSwatchColor()
        UpdateAllNameplates()
    end

    textColorSwatch:SetScript("OnClick", function()
        local current = db.textColor or DEFAULTS.textColor
        local r, g, b = current[1] or 1, current[2] or 1, current[3] or 1
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r,
                g = g,
                b = b,
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    ApplyTextColor(nr, ng, nb)
                end,
                opacityFunc = nil,
                cancelFunc = function(previousValues)
                    if previousValues then
                        ApplyTextColor(previousValues.r, previousValues.g, previousValues.b)
                    end
                end,
                hasOpacity = false,
            })
        else
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = { r = r, g = g, b = b }
            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                ApplyTextColor(nr, ng, nb)
            end
            ColorPickerFrame.cancelFunc = function(previousValues)
                if previousValues then
                    ApplyTextColor(previousValues.r, previousValues.g, previousValues.b)
                end
            end
            ColorPickerFrame:Show()
        end
    end)

    optionsPanel:SetScript("OnShow", RefreshFromDb)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsPanel, ADDON_TITLE)
        Settings.RegisterAddOnCategory(category)
        optionsPanel.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(optionsPanel)
    end
end

SLASH_PACOSKINOSABECONTAR1 = "/pnsc"
SlashCmdList.PACOSKINOSABECONTAR = function(message)
    local args = ParseCommand(message)
    local command = string.lower(args[1] or "")
    EnsureDatabase()

    if command == "on" then
        db.enabled = true
        Print("enabled")
        UpdateAllNameplates()
    elseif command == "off" then
        db.enabled = false
        Print("disabled")
        ReleaseAllTexts()
    elseif command == "raw" then
        db.showRawValue = not db.showRawValue
        Print("raw value display " .. (db.showRawValue and "enabled" or "disabled"))
        UpdateAllNameplates()
    elseif command == "debug" then
        db.debug = not db.debug
        Print("debug " .. (db.debug and "enabled" or "disabled"))
        UpdateAllNameplates()
    elseif command == "nobw" then
        local disabled, reason = DisableBigWigsNameplateProgress()
        if disabled then
            Print("BigWigs nameplate progress disabled. Use /reload if its old texts are still visible.")
        else
            Print(reason)
        end
    elseif command == "offset" then
        local x = tonumber(args[2] or "")
        local y = tonumber(args[3] or "")
        if x == nil or y == nil then
            Print("usage: /pnsc offset <x> <y>")
            return
        end
        db.x = x
        db.y = y
        Print(string.format("offset set to x=%.1f y=%.1f", db.x, db.y))
        UpdateAllNameplates()
    elseif command == "fontsize" then
        local size = tonumber(args[2] or "")
        if size == nil then
            Print("usage: /pnsc fontsize <size>")
            return
        end
        db.fontSize = Clamp(math.floor(size + 0.5), 6, 72)
        Print("font size set to " .. db.fontSize)
        UpdateAllNameplates()
    elseif command == "fontflags" then
        local flagsInput = string.upper(args[2] or "")
        if flagsInput == "" then
            Print("usage: /pnsc fontflags <none|outline|thickoutline|monochrome[,outline]>")
            return
        end
        db.fontFlags = (flagsInput == "NONE") and "" or flagsInput
        Print("font flags set to " .. (db.fontFlags == "" and "none" or db.fontFlags))
        UpdateAllNameplates()
    elseif command == "alpha" then
        local alpha = tonumber(args[2] or "")
        if alpha == nil then
            Print("usage: /pnsc alpha <0-1>")
            return
        end
        db.otherColor[4] = Clamp(alpha, 0, 1)
        Print(string.format("other units alpha set to %.2f", db.otherColor[4]))
        UpdateAllNameplates()
    elseif command == "targetalpha" then
        local alpha = tonumber(args[2] or "")
        if alpha == nil then
            Print("usage: /pnsc targetalpha <0-1>")
            return
        end
        db.targetColor[4] = Clamp(alpha, 0, 1)
        Print(string.format("target alpha set to %.2f", db.targetColor[4]))
        UpdateAllNameplates()
    elseif command == "status" then
        Print(string.format(
            "offset x=%.1f y=%.1f | size=%d | flags=%s | alpha=%.2f | targetAlpha=%.2f | hideInCombat=%s | debug=%s",
            db.x or DEFAULTS.x,
            db.y or DEFAULTS.y,
            db.fontSize or DEFAULTS.fontSize,
            (db.fontFlags == "" and "none" or tostring(db.fontFlags or DEFAULTS.fontFlags)),
            db.otherColor and db.otherColor[4] or DEFAULTS.otherColor[4],
            db.targetColor and db.targetColor[4] or DEFAULTS.targetColor[4],
            (db.hideInCombat == true and "on" or "off"),
            (db.debug == true and "on" or "off")
        ))
    elseif command == "options" then
        OpenOptionsPanel()
    else
        Print("/pnsc on|off|raw|debug|nobw|status|options")
        Print("/pnsc offset <x> <y>")
        Print("/pnsc fontsize <size>")
        Print("/pnsc fontflags <none|outline|thickoutline|monochrome[,outline]>")
        Print("/pnsc alpha <0-1> | /pnsc targetalpha <0-1>")
        Print("/count -> abre opciones directas")
    end
end

SLASH_PACOSKINOSABECONTAROPEN1 = "/count"
SlashCmdList.PACOSKINOSABECONTAROPEN = function(message)
    local args = ParseCommand(message)
    if #args == 0 then
        EnsureDatabase()
        OpenOptionsPanel()
        return
    end
    SlashCmdList.PACOSKINOSABECONTAR(message)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:RegisterEvent("SCENARIO_UPDATE")
eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddonName = ...
        if loadedAddonName == ADDON_NAME then
            EnsureDatabase()
            BuildOptionsPanel()
        end
        return
    end

    if not db then
        EnsureDatabase()
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        UpdateUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        ReleaseText(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateAllNameplates()
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        ReleaseAllTexts()
    else
        RefreshAfterDelay()
    end
end)
