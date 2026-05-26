-- CustomFrame.lua, themed custom pool editor.
-- Built with raw CreateFrame + Theme helpers, matches the visual language of
-- the main UI window.
local _, AS = ...
AS.CustomFrame = {}

local C = AS.Theme
local MAX_MESSAGE_LEN = 50

local TRIGGERS_ORDERED = {
    "groupJoin", "groupLeave", "achievement", "levelUp",
    "keyTimed", "keyDepleted", "readyCheck",
}
local TRIGGER_LABELS = {
    groupJoin = "Group join", groupLeave = "Group leave",
    achievement = "Achievement", levelUp = "Level-up",
    keyTimed = "Mythic+ timed", keyDepleted = "Mythic+ depleted",
    readyCheck = "Ready check",
}

local frame
local railButtons = {}
local listFrame, scrollFrame, scrollChild
local currentTrigger = "groupJoin"
local statusText
local headerText

-- ---------------------------------------------------------------------------
-- Row rendering
-- ---------------------------------------------------------------------------
local rowWidgets = {}

local function ClearRows()
    for _, row in ipairs(rowWidgets) do
        row:Hide()
        row:SetParent(nil)
        row:ClearAllPoints()
    end
    rowWidgets = {}
end

local function RenderList()
    ClearRows()
    if not currentTrigger then return end

    local pool = AS.Messages:GetCustomPool(currentTrigger)
    headerText:SetText("Editing: " .. (TRIGGER_LABELS[currentTrigger] or currentTrigger))

    local rowHeight = 28
    local gap = 4

    local function makeEditCallback(index)
        return function(self)
            local text = self:GetText():match("^%s*(.-)%s*$")
            local list = AS.Messages:GetCustomPool(currentTrigger)
            if text == "" then
                AS.Messages:RemoveCustom(currentTrigger, index)
                RenderList()
            elseif list[index] and text ~= list[index] then
                list[index] = text
                AS.Messages:SetCustomPool(currentTrigger, list)
            end
            self:ClearFocus()
        end
    end

    local y = -8
    for i, message in ipairs(pool) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", -4, y) -- leave room for scrollbar

        local indexBadge = C:Body(row, tostring(i) .. ".")
        indexBadge:SetPoint("LEFT", 6, 0)
        indexBadge:SetTextColor(unpack(C.color.textMuted))

        local editFrame, edit = C:EditBox(row, MAX_MESSAGE_LEN)
        editFrame:SetPoint("LEFT", indexBadge, "RIGHT", 8, 0)
        editFrame:SetPoint("RIGHT", -76, 0)
        edit:SetText(message)
        edit:SetScript("OnEnterPressed", makeEditCallback(i))

        local removeBtn = C:Button(row, "Remove", 64, 22)
        removeBtn:SetPoint("RIGHT", 0, 0)
        removeBtn:SetScript("OnClick", function()
            AS.Messages:RemoveCustom(currentTrigger, i)
            RenderList()
        end)

        table.insert(rowWidgets, row)
        y = y - (rowHeight + gap)
    end

    -- Add new row
    local addRow = CreateFrame("Frame", nil, scrollChild)
    addRow:SetHeight(rowHeight)
    addRow:SetPoint("TOPLEFT", 0, y - 8)
    addRow:SetPoint("TOPRIGHT", -4, y - 8)

    local plusBadge = C:Body(addRow, "+")
    plusBadge:SetPoint("LEFT", 6, 0)
    plusBadge:SetTextColor(unpack(C.color.accent))

    local addEditFrame, addEdit = C:EditBox(addRow, MAX_MESSAGE_LEN)
    addEditFrame:SetPoint("LEFT", plusBadge, "RIGHT", 8, 0)
    addEditFrame:SetPoint("RIGHT", -76, 0)

    local function doAdd()
        local text = addEdit:GetText():match("^%s*(.-)%s*$")
        if text == "" then return end
        local ok, err = AS.Messages:AddCustom(currentTrigger, text)
        if ok then
            addEdit:SetText("")
            RenderList()
        else
            AntiSocial:Print("could not add: " .. tostring(err))
        end
    end

    addEdit:SetScript("OnEnterPressed", doAdd)

    local addBtn = C:AccentButton(addRow, "Add", 64, 22)
    addBtn:SetPoint("RIGHT", 0, 0)
    addBtn:SetScript("OnClick", doAdd)

    table.insert(rowWidgets, addRow)
    y = y - (rowHeight + 8)

    -- Scroll child height
    scrollChild:SetHeight(math.max(math.abs(y) + 16, listFrame:GetHeight()))

    -- Status text
    if #pool == 0 then
        statusText:SetText("|cffaaaaaaEmpty pool, falls back to Friendly defaults.|r")
    else
        statusText:SetText(("|cffaaaaaa%d message%s in pool. Press Enter to save edits.|r"):format(
            #pool, #pool == 1 and "" or "s"))
    end
end

local function SelectTrigger(key)
    currentTrigger = key
    for k, btn in pairs(railButtons) do
        btn.SetActive(k == key)
    end
    RenderList()
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------
local function BuildFrame()
    frame = CreateFrame("Frame", "AntiSocialCustomUI", UIParent, "BackdropTemplate")
    frame:SetSize(640, 480)
    frame:SetPoint("CENTER", UIParent, "CENTER", 80, -40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    C:ApplyBackdrop(frame, C.color.bgPanel, C.color.border, 1)
    tinsert(UISpecialFrames, "AntiSocialCustomUI")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    C:ApplyBackdrop(titleBar, C.color.bgRaised, C.color.accent, 1)

    local badge = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    badge:SetSize(20, 20)
    badge:SetPoint("LEFT", 10, 0)
    C:ApplyBackdrop(badge, C.color.accent, C.color.borderHi, 1)
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("CENTER")
    badgeText:SetText("A")
    badgeText:SetTextColor(unpack(C.color.bgDeep))

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", badge, "RIGHT", 8, 0)
    title:SetText("AntiSocial: Custom Pools")
    title:SetTextColor(unpack(C.color.textBright))

    local closeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -8, 0)
    C:ApplyBackdrop(closeBtn, C.color.bgRaised, C.color.border, 1)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(unpack(C.color.textDim))
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.color.borderHi))
        closeText:SetTextColor(unpack(C.color.accent))
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(C.color.border))
        closeText:SetTextColor(unpack(C.color.textDim))
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Help (?) button, sits left of the close button
    local helpBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    helpBtn:SetSize(20, 20)
    helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    C:ApplyBackdrop(helpBtn, C.color.bgRaised, C.color.border, 1)
    local helpText = helpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpText:SetPoint("CENTER")
    helpText:SetText("?")
    helpText:SetTextColor(unpack(C.color.textDim))
    helpBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.color.borderHi))
        helpText:SetTextColor(unpack(C.color.accent))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Custom pools help", 1, 0.498, 0.314)
        GameTooltip:AddLine("Click for details on each trigger and how custom pools work.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(C.color.border))
        helpText:SetTextColor(unpack(C.color.textDim))
        GameTooltip:Hide()
    end)
    helpBtn:SetScript("OnClick", function()
        if AS.CustomFrame.ShowHelp then AS.CustomFrame:ShowHelp() end
    end)

    -- Left rail with trigger buttons
    local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rail:SetWidth(160)
    rail:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", 0, 24)
    C:ApplyBackdrop(rail, C.color.bgRaised, C.color.border, 1)

    local railHeading = C:Heading(rail, "Triggers")
    railHeading:SetPoint("TOPLEFT", 12, -10)

    local yOff = -32
    for _, key in ipairs(TRIGGERS_ORDERED) do
        local btn = CreateFrame("Button", nil, rail, "BackdropTemplate")
        btn:SetSize(140, 26)
        btn:SetPoint("TOPLEFT", 10, yOff)
        C:StyleRow(btn, false)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", 10, 0)
        lbl:SetText(TRIGGER_LABELS[key])

        function btn.SetActive(active)
            if active then
                C:StyleRow(btn, true)
                lbl:SetTextColor(unpack(C.color.accent))
            else
                C:StyleRow(btn, false)
                lbl:SetTextColor(unpack(C.color.textBody))
            end
        end

        btn:SetScript("OnEnter", function(self)
            if currentTrigger ~= key then
                self:SetBackdropBorderColor(unpack(C.color.borderHi))
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if currentTrigger ~= key then
                self:SetBackdropBorderColor(unpack(C.color.border))
            end
        end)
        btn:SetScript("OnClick", function() SelectTrigger(key) end)

        railButtons[key] = btn
        yOff = yOff - 30
    end

    -- Right content area: header + scrollable list
    local contentArea = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentArea:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 24)
    C:ApplyBackdrop(contentArea, C.color.bgPanel, C.color.border, 1)

    headerText = C:Title(contentArea, "Editing")
    headerText:SetPoint("TOPLEFT", 16, -12)

    listFrame = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", 16, -42)
    listFrame:SetPoint("BOTTOMRIGHT", -16, 16)
    C:ApplyBackdrop(listFrame, C.color.bgDeep, C.color.border, 1)

    scrollFrame = CreateFrame("ScrollFrame", "AntiSocialCustomScroll", listFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(420, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Status bar
    local statusBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statusBar:SetHeight(24)
    statusBar:SetPoint("BOTTOMLEFT")
    statusBar:SetPoint("BOTTOMRIGHT")
    C:ApplyBackdrop(statusBar, C.color.bgRaised, C.color.border, 1)

    statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("LEFT", 12, 0)
    statusText:SetTextColor(unpack(C.color.textMuted))
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function AS.CustomFrame:Show(trigger)
    if not frame then BuildFrame() end
    SelectTrigger(trigger or currentTrigger or "groupJoin")
    frame:Show()
    frame:Raise()
end

function AS.CustomFrame:Hide()
    if frame then frame:Hide() end
end

function AS.CustomFrame:Toggle(trigger)
    if frame and frame:IsShown() then self:Hide() else self:Show(trigger) end
end

-- ---------------------------------------------------------------------------
-- Help popup
-- ---------------------------------------------------------------------------
local helpFrame

local HELP_TEXT = [[|cffff7f50AntiSocial Custom Pools|r

When the mood profile is set to |cffff7f50Custom|r, the addon picks
from your own message pools instead of the built-in ones.

|cffff7f50How it works|r
Pick a trigger on the left, then add messages on the right. When
that game event fires, AntiSocial picks one of your messages at
random and sends it after a 1-8 second delay.

|cffff7f50Empty pools fall back to Friendly|r
If a pool is empty, that specific trigger uses the built-in
Friendly defaults. So you only have to customize the triggers
you actually care about.

|cffaaaaaaTriggers explained:|r

|cffff7f50Group join|r - when you enter a party or raid
|cffff7f50Group leave|r - when the group disbands or you leave
|cffff7f50Achievement|r - when a party/raid member earns an achievement
|cffff7f50Level-up|r - when a party/raid member levels up (English clients)
|cffff7f50Mythic+ timed|r - after a successfully timed M+ key
|cffff7f50Mythic+ depleted|r - after an over-timer M+ key
|cffff7f50Ready check|r - when a ready check is called (auto-confirm)

|cffaaaaaaTips:|r
- Press Enter in an edit box to save changes
- Empty an edit box and press Enter to remove that message
- Click Remove to delete a specific message
- Slash commands also work: /as add <trigger> <text>]]

local function BuildHelpFrame()
    helpFrame = CreateFrame("Frame", "AntiSocialCustomHelpUI", UIParent, "BackdropTemplate")
    helpFrame:SetSize(460, 440)
    helpFrame:SetPoint("CENTER", UIParent, "CENTER", 160, -20)
    helpFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    helpFrame:SetToplevel(true)
    helpFrame:SetMovable(true)
    helpFrame:EnableMouse(true)
    helpFrame:RegisterForDrag("LeftButton")
    helpFrame:SetScript("OnDragStart", helpFrame.StartMoving)
    helpFrame:SetScript("OnDragStop", helpFrame.StopMovingOrSizing)
    helpFrame:SetClampedToScreen(true)
    C:ApplyBackdrop(helpFrame, C.color.bgPanel, C.color.border, 1)
    tinsert(UISpecialFrames, "AntiSocialCustomHelpUI")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, helpFrame, "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    C:ApplyBackdrop(titleBar, C.color.bgRaised, C.color.accent, 1)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 12, 0)
    title:SetText("Help: Custom Pools")
    title:SetTextColor(unpack(C.color.textBright))

    local closeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -8, 0)
    C:ApplyBackdrop(closeBtn, C.color.bgRaised, C.color.border, 1)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(unpack(C.color.textDim))
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.color.borderHi))
        closeText:SetTextColor(unpack(C.color.accent))
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(C.color.border))
        closeText:SetTextColor(unpack(C.color.textDim))
    end)
    closeBtn:SetScript("OnClick", function() helpFrame:Hide() end)

    -- Content area (scrollable in case the text is long)
    local content = CreateFrame("Frame", nil, helpFrame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", helpFrame, "BOTTOMRIGHT", -8, 8)
    C:ApplyBackdrop(content, C.color.bgDeep, C.color.border, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(400, 800)
    scrollFrame:SetScrollChild(scrollChild)

    local helpFs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    helpFs:SetPoint("TOPLEFT", 4, -4)
    helpFs:SetPoint("TOPRIGHT", -4, -4)
    helpFs:SetJustifyH("LEFT")
    helpFs:SetJustifyV("TOP")
    helpFs:SetText(HELP_TEXT)
    helpFs:SetTextColor(unpack(C.color.textBody))
    helpFs:SetSpacing(2)

    -- Size scroll child to fit text
    local h = helpFs:GetStringHeight() + 16
    scrollChild:SetHeight(math.max(h, 1))
end

function AS.CustomFrame:ShowHelp()
    if not helpFrame then BuildHelpFrame() end
    helpFrame:Show()
    helpFrame:Raise()
end
