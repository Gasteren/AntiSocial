-- FilterLogFrame.lua, themed log viewer for filtered whispers.
-- Mirrors the visual language of CustomFrame: title bar, scrollable list,
-- DIALOG strata so it sits on top of the main UI cleanly.
local _, AS = ...
AS.FilterLogFrame = {}

local C = AS.Theme

local frame
local scrollFrame, scrollChild
local statusText
local rowWidgets = {}

local function ClearRows()
    for _, row in ipairs(rowWidgets) do
        row:Hide()
        row:SetParent(nil)
        row:ClearAllPoints()
    end
    rowWidgets = {}
end

local function RenderLog()
    ClearRows()
    if not scrollChild then return end

    local log = AS.WhisperFilter:GetLog()
    statusText:SetText(("|cffaaaaaa%d filtered whisper%s in log|r"):format(
        #log, #log == 1 and "" or "s"))

    if #log == 0 then
        local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", 16, -16)
        empty:SetText("No filtered whispers yet. When the whisper filter blocks a message, it'll appear here.")
        empty:SetTextColor(unpack(C.color.textDim))
        empty:SetJustifyH("LEFT")
        empty:SetWidth(scrollChild:GetWidth() - 32)
        -- Empty isn't a "row widget" tracked in rowWidgets, but it'll get
        -- cleaned up next render via SetText("") + ClearAllPoints. Track as
        -- a row to be safe.
        table.insert(rowWidgets, empty)
        scrollChild:SetHeight(60)
        return
    end

    -- Newest first
    local y = -8
    local rowH = 44
    for i = #log, 1, -1 do
        local entry = log[i]
        local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 4, y)
        row:SetPoint("TOPRIGHT", -4, y)
        C:StyleRow(row, false)

        local timeStr = date("%Y-%m-%d %H:%M", entry.timestamp)
        local senderText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        senderText:SetPoint("TOPLEFT", 10, -6)
        senderText:SetText(entry.sender or "?")
        senderText:SetTextColor(unpack(C.color.accent))

        local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        levelText:SetPoint("LEFT", senderText, "RIGHT", 8, 0)
        levelText:SetText(("[L%d]"):format(entry.level or 0))
        levelText:SetTextColor(unpack(C.color.textMuted))

        local timestampText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        timestampText:SetPoint("TOPRIGHT", -10, -6)
        timestampText:SetText(timeStr)
        timestampText:SetTextColor(unpack(C.color.textMuted))

        local msgText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        msgText:SetPoint("TOPLEFT", 10, -24)
        msgText:SetPoint("TOPRIGHT", -10, -24)
        msgText:SetJustifyH("LEFT")
        msgText:SetText(entry.message or "")
        msgText:SetTextColor(unpack(C.color.textBody))
        msgText:SetWordWrap(false) -- single-line preview; tooltip on hover could show full

        -- Hover tooltip showing the full message
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(C.color.borderHi))
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(entry.sender or "?", 1, 0.498, 0.314)
            GameTooltip:AddLine(("|cff888888level %d   %s|r"):format(
                entry.level or 0, timeStr), 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(entry.message or "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(C.color.border))
            GameTooltip:Hide()
        end)

        table.insert(rowWidgets, row)
        y = y - (rowH + 4)
    end

    scrollChild:SetHeight(math.abs(y) + 8)
end

local function BuildFrame()
    frame = CreateFrame("Frame", "AntiSocialFilterLogUI", UIParent, "BackdropTemplate")
    frame:SetSize(620, 480)
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
    tinsert(UISpecialFrames, "AntiSocialFilterLogUI")

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
    title:SetText("AntiSocial: Filter Log")
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

    -- Action bar (just below the title bar): Refresh + Clear
    local actionBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    actionBar:SetHeight(40)
    actionBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    actionBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    C:ApplyBackdrop(actionBar, C.color.bgRaised, C.color.border, 1)

    local heading = actionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heading:SetPoint("LEFT", 12, 0)
    heading:SetText("FILTERED WHISPERS")
    heading:SetTextColor(unpack(C.color.accent))

    local clearBtn = C:Button(actionBar, "Clear log", 90, 24)
    clearBtn:SetPoint("RIGHT", -10, 0)
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["ANTISOCIAL_CLEAR_LOG"] = {
            text = "Clear all filtered whisper log entries?",
            button1 = "Yes",
            button2 = "Cancel",
            OnAccept = function()
                AS.WhisperFilter:ClearLog()
                RenderLog()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("ANTISOCIAL_CLEAR_LOG")
    end)

    local refreshBtn = C:Button(actionBar, "Refresh", 80, 24)
    refreshBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    refreshBtn:SetScript("OnClick", function() RenderLog() end)

    -- List area
    local listFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", actionBar, "BOTTOMLEFT", 8, -8)
    listFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 32)
    C:ApplyBackdrop(listFrame, C.color.bgDeep, C.color.border, 1)

    scrollFrame = CreateFrame("ScrollFrame", "AntiSocialFilterLogScrollFrame", listFrame,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(560, 1)
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

    local hoverHint = statusBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hoverHint:SetPoint("RIGHT", -12, 0)
    hoverHint:SetText("Hover a row for full message")
    hoverHint:SetTextColor(unpack(C.color.textMuted))
end

function AS.FilterLogFrame:Show()
    if not frame then BuildFrame() end
    RenderLog()
    frame:Show()
    frame:Raise()
end

function AS.FilterLogFrame:Hide()
    if frame then frame:Hide() end
end

function AS.FilterLogFrame:Toggle()
    if frame and frame:IsShown() then self:Hide() else self:Show() end
end
