-- Theme.lua, centralized visual constants and widget factories.
-- All custom UI files (UI.lua, CustomFrame.lua) pull from here so the visual
-- language stays consistent.
local _, AS = ...
AS.Theme = {}

-- ---------------------------------------------------------------------------
-- Palette
-- ---------------------------------------------------------------------------
AS.Theme.color = {
    bgDeep      = { 0.055, 0.055, 0.063, 1 },  -- #0e0e10
    bgPanel     = { 0.102, 0.102, 0.110, 1 },  -- #1a1a1c
    bgRaised    = { 0.078, 0.078, 0.086, 1 },  -- #141416
    bgRow       = { 0.102, 0.102, 0.110, 1 },  -- #1a1a1c
    bgRowActive = { 0.165, 0.122, 0.094, 1 },  -- #2a1f18 (warm dark)
    border      = { 0.165, 0.165, 0.180, 1 },  -- #2a2a2e
    borderHi    = { 1.000, 0.498, 0.314, 1 },  -- #ff7f50 (accent)
    accent      = { 1.000, 0.498, 0.314, 1 },  -- #ff7f50
    accentDim   = { 0.706, 0.349, 0.220, 1 },  -- #b45938
    textBright  = { 0.941, 0.902, 0.863, 1 },  -- #f0e6dc
    textBody    = { 0.831, 0.812, 0.780, 1 },  -- #d4cfc7
    textDim     = { 0.533, 0.533, 0.533, 1 },  -- #888888
    textMuted   = { 0.416, 0.416, 0.416, 1 },  -- #6a6a6a
    success     = { 0.376, 0.749, 0.443, 1 },  -- soft green
    danger      = { 0.886, 0.376, 0.376, 1 },  -- soft red
}

-- ---------------------------------------------------------------------------
-- Backdrop helpers
-- ---------------------------------------------------------------------------
-- The new Backdrop API requires a BackdropTemplate parent template.
-- Returns the frame for chaining.
function AS.Theme:ApplyBackdrop(frame, bgColor, borderColor, edgeSize, inset)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    edgeSize = edgeSize or 1
    inset = inset or 0
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edgeSize,
        insets   = { left = inset, right = inset, top = inset, bottom = inset },
    })
    if bgColor   then frame:SetBackdropColor(unpack(bgColor)) end
    if borderColor then frame:SetBackdropBorderColor(unpack(borderColor)) end
    return frame
end

-- Shorthand for standard panel surface
function AS.Theme:StylePanel(frame)
    return self:ApplyBackdrop(frame, self.color.bgPanel, self.color.border, 1)
end

function AS.Theme:StyleRaised(frame)
    return self:ApplyBackdrop(frame, self.color.bgRaised, self.color.border, 1)
end

function AS.Theme:StyleRow(frame, active)
    return self:ApplyBackdrop(frame,
        active and self.color.bgRowActive or self.color.bgRow,
        active and self.color.borderHi or self.color.border, 1)
end

-- ---------------------------------------------------------------------------
-- Fonts and labels
-- ---------------------------------------------------------------------------
function AS.Theme:Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetText(text or "")
    return fs
end

function AS.Theme:Title(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(self.color.textBright))
    return fs
end

function AS.Theme:Heading(parent, text)
    -- All-caps section header in accent color, letter-spaced look
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text and text:upper() or "")
    fs:SetTextColor(unpack(self.color.accent))
    return fs
end

function AS.Theme:Body(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(self.color.textBody))
    return fs
end

function AS.Theme:Dim(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(self.color.textDim))
    return fs
end

-- ---------------------------------------------------------------------------
-- Themed button
-- ---------------------------------------------------------------------------
function AS.Theme:Button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 80, height or 22)
    self:ApplyBackdrop(btn, self.color.bgRaised, self.color.border, 1)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    label:SetTextColor(unpack(self.color.textBody))
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(AS.Theme.color.bgRowActive))
        self:SetBackdropBorderColor(unpack(AS.Theme.color.borderHi))
        self.label:SetTextColor(unpack(AS.Theme.color.accent))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(AS.Theme.color.bgRaised))
        self:SetBackdropBorderColor(unpack(AS.Theme.color.border))
        self.label:SetTextColor(unpack(AS.Theme.color.textBody))
    end)

    function btn:SetTextColored(newText) label:SetText(newText) end

    return btn
end

function AS.Theme:AccentButton(parent, text, width, height)
    local btn = self:Button(parent, text, width, height)
    btn:SetBackdropColor(unpack(self.color.accentDim))
    btn:SetBackdropBorderColor(unpack(self.color.borderHi))
    btn.label:SetTextColor(unpack(self.color.textBright))
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(AS.Theme.color.accent))
        self.label:SetTextColor(unpack(AS.Theme.color.bgDeep))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(AS.Theme.color.accentDim))
        self.label:SetTextColor(unpack(AS.Theme.color.textBright))
    end)
    return btn
end

-- ---------------------------------------------------------------------------
-- Themed checkbox
-- ---------------------------------------------------------------------------
function AS.Theme:Checkbox(parent, labelText, getter, setter)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(28)
    self:StyleRow(row, false)

    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 8, 0)
    self:ApplyBackdrop(box, self.color.bgDeep, self.color.border, 1)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(labelText or "")
    label:SetTextColor(unpack(self.color.textBody))

    local function refresh()
        local on = getter and getter() or false
        if on then
            box:SetBackdropColor(unpack(AS.Theme.color.accent))
            box:SetBackdropBorderColor(unpack(AS.Theme.color.borderHi))
            label:SetTextColor(unpack(AS.Theme.color.textBright))
        else
            box:SetBackdropColor(unpack(AS.Theme.color.bgDeep))
            box:SetBackdropBorderColor(unpack(AS.Theme.color.border))
            label:SetTextColor(unpack(AS.Theme.color.textBody))
        end
    end

    row:SetScript("OnClick", function()
        if setter then
            setter(not (getter and getter()))
            refresh()
        end
    end)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(AS.Theme.color.borderHi))
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(AS.Theme.color.border))
    end)

    row.Refresh = refresh
    refresh()
    return row
end

-- ---------------------------------------------------------------------------
-- Themed slider (range)
-- ---------------------------------------------------------------------------
function AS.Theme:Slider(parent, labelText, minV, maxV, step, getter, setter, valueFormat)
    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetHeight(40)

    local fmt = valueFormat or "%ds"

    local label = wrapper:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetTextColor(unpack(self.color.textBody))

    local value = wrapper:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("TOPRIGHT", 0, 0)
    value:SetTextColor(unpack(self.color.accent))

    local slider = CreateFrame("Slider", nil, wrapper, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetPoint("BOTTOMLEFT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", 0, 0)
    slider:SetHeight(16)
    if slider.Low  then slider.Low:Hide() end
    if slider.High then slider.High:Hide() end
    if slider.Text then slider.Text:Hide() end

    local function refresh()
        local v = getter and getter() or minV
        slider:SetValue(v)
        value:SetText(fmt:format(v))
        label:SetText(labelText or "")
    end

    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if setter then setter(v) end
        value:SetText(fmt:format(v))
    end)

    wrapper.Refresh = refresh
    wrapper.slider = slider
    refresh()
    return wrapper
end

-- ---------------------------------------------------------------------------
-- Themed edit box
-- ---------------------------------------------------------------------------
function AS.Theme:EditBox(parent, maxLen)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(24)
    self:ApplyBackdrop(frame, self.color.bgDeep, self.color.border, 1)

    local edit = CreateFrame("EditBox", nil, frame)
    edit:SetPoint("LEFT", 6, 0)
    edit:SetPoint("RIGHT", -6, 0)
    edit:SetHeight(20)
    edit:SetFontObject("GameFontHighlight")
    edit:SetTextColor(unpack(self.color.textBright))
    edit:SetAutoFocus(false)
    if maxLen then edit:SetMaxLetters(maxLen) end
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    frame.edit = edit

    frame:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- Hover/focus border highlight
    edit:HookScript("OnEditFocusGained", function()
        frame:SetBackdropBorderColor(unpack(AS.Theme.color.borderHi))
    end)
    edit:HookScript("OnEditFocusLost", function()
        frame:SetBackdropBorderColor(unpack(AS.Theme.color.border))
    end)

    return frame, edit
end
