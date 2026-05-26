-- UI.lua, custom-themed main config window with tab strip.
-- Replaces AceConfig+AceConfigDialog entirely. The window is single-instance
-- and rebuilt lazily on first open.
local _, AS = ...
AS.UI = {}

local C = AS.Theme

local TABS = {
    { key = "settings", label = "Settings" },
    { key = "custom",   label = "Custom Pools" },
    { key = "filter",   label = "Whisper Filter" },
    { key = "stats",    label = "Stats" },
    { key = "profiles", label = "Profiles" },
}

local MOOD_PROFILES = {
    { key = "Introvert", desc = "hi / gg / ty" },
    { key = "Friendly",  desc = "heya / nice key / tyfp" },
    { key = "Goblin",    desc = "pumpers? / ez clap / free vault" },
    { key = "Raider",    desc = "ggs / r / wp" },
    { key = "Custom",    desc = "your own messages" },
}

local TRIGGER_TOGGLES = {
    { key = "groupJoin",   label = "Group join" },
    { key = "groupLeave",  label = "Group leave" },
    { key = "achievement", label = "Achievements" },
    { key = "levelUp",     label = "Level-ups" },
    { key = "keyComplete", label = "Mythic+ done" },
    { key = "readyCheck",  label = "Ready check" },
}

local frame              -- the master frame
local tabButtons = {}    -- key -> button widget
local tabContent         -- shared content container (children rebuilt per tab)
local currentTab = "settings"

local function db()
    return AntiSocial.db.profile
end

-- ---------------------------------------------------------------------------
-- Tab content builders
-- ---------------------------------------------------------------------------
local function ClearContent()
    if not tabContent then return end
    for _, child in ipairs({ tabContent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
        child:ClearAllPoints()
    end
    -- Region (fontstring/texture) cleanup
    for _, region in ipairs({ tabContent:GetRegions() }) do
        region:Hide()
        region:ClearAllPoints()
        if region.SetText then region:SetText("") end
    end
end

local function BuildSettings(parent)
    -- Forward-declared locals so the closures inside the OnClick handlers
    -- and OnValueChanged callbacks can see them after we assign them below.
    local moodDesc
    local minSliderRef, maxSliderRef

    -- Master enable row
    local masterRow = C:Checkbox(parent, "AntiSocial enabled",
        function() return db().enabled end,
        function(v) db().enabled = v end)
    masterRow:SetPoint("TOPLEFT", 16, -16)
    masterRow:SetPoint("TOPRIGHT", -16, -16)

    local masterDesc = C:Dim(parent, "Master switch. When off, no messages are sent.")
    masterDesc:SetPoint("TOPLEFT", masterRow, "BOTTOMLEFT", 2, -2)

    -- Mood section
    local moodHeading = C:Heading(parent, "Mood profile")
    moodHeading:SetPoint("TOPLEFT", masterDesc, "BOTTOMLEFT", -2, -16)

    local moodCards = {}
    local cardWidth = 100
    local cardGap = 6
    for i, profile in ipairs(MOOD_PROFILES) do
        local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
        card:SetSize(cardWidth, 32)
        card:SetPoint("TOPLEFT", moodHeading, "BOTTOMLEFT", (i - 1) * (cardWidth + cardGap), -8)

        local labelFs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelFs:SetPoint("CENTER")
        labelFs:SetText(profile.key)
        card.label = labelFs
        card.profileKey = profile.key

        local function refresh()
            local active = db().moodProfile == profile.key
            C:StyleRow(card, active)
            labelFs:SetTextColor(unpack(active and C.color.accent or C.color.textDim))
        end

        card:SetScript("OnEnter", function(self)
            if db().moodProfile ~= profile.key then
                self:SetBackdropBorderColor(unpack(C.color.borderHi))
            end
        end)
        card:SetScript("OnLeave", function(self)
            if db().moodProfile ~= profile.key then
                self:SetBackdropBorderColor(unpack(C.color.border))
            end
        end)
        card:SetScript("OnClick", function()
            db().moodProfile = profile.key
            for _, c in ipairs(moodCards) do c.Refresh() end
            moodDesc:SetText(profile.desc)
        end)

        card.Refresh = refresh
        refresh()
        table.insert(moodCards, card)
    end

    moodDesc = C:Dim(parent, "")
    moodDesc:SetPoint("TOPLEFT", moodCards[1], "BOTTOMLEFT", 2, -4)
    -- Show description for the currently active profile
    for _, profile in ipairs(MOOD_PROFILES) do
        if profile.key == db().moodProfile then
            moodDesc:SetText(profile.desc)
        end
    end

    -- Triggers section
    local trigHeading = C:Heading(parent, "Triggers")
    trigHeading:SetPoint("TOPLEFT", moodDesc, "BOTTOMLEFT", -2, -16)

    local trigGap = 8
    local trigCellH = 28
    for i, trig in ipairs(TRIGGER_TOGGLES) do
        local row = i - 1
        local col = row % 2
        local rowIdx = math.floor(row / 2)
        local cb = C:Checkbox(parent, trig.label,
            function() return db().triggers[trig.key] end,
            function(v) db().triggers[trig.key] = v end)
        cb:SetWidth(0) -- relative via SetPoint below
        cb:SetPoint("TOPLEFT", trigHeading, "BOTTOMLEFT",
            col * (260 + trigGap), -8 - rowIdx * (trigCellH + trigGap))
        cb:SetWidth(260)
    end

    -- Delay sliders (anchored at the bottom of the panel)
    local minLabel = C:Heading(parent, "Send delay")
    minLabel:SetPoint("BOTTOMLEFT", 16, 80)

    local sliderWidth = 280
    local minSlider = C:Slider(parent, "Min delay", 0, 10, 1,
        function() return db().minDelay end,
        function(v)
            db().minDelay = v
            if db().maxDelay < v then db().maxDelay = v end
            if maxSliderRef then maxSliderRef.Refresh() end
        end)
    minSlider:SetWidth(sliderWidth)
    minSlider:SetPoint("TOPLEFT", minLabel, "BOTTOMLEFT", 0, -4)

    local maxSlider = C:Slider(parent, "Max delay", 1, 15, 1,
        function() return db().maxDelay end,
        function(v)
            db().maxDelay = v
            if db().minDelay > v then db().minDelay = v end
            if minSliderRef then minSliderRef.Refresh() end
        end)
    maxSlider:SetWidth(sliderWidth)
    maxSlider:SetPoint("LEFT", minSlider, "RIGHT", 16, 0)

    minSliderRef = minSlider
    maxSliderRef = maxSlider
end

local function BuildCustom(parent)
    local heading = C:Title(parent, "Custom message pools")
    heading:SetPoint("TOPLEFT", 16, -16)

    local desc = C:Body(parent,
        "Custom pools are used when the Mood profile is set to |cffff7f50Custom|r. "
        .. "Empty pools fall back to Friendly defaults so you only have to customize what matters.")
    desc:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -42)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)

    local openBtn = C:AccentButton(parent, "Open custom pool editor", 200, 28)
    openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    openBtn:SetScript("OnClick", function()
        if AS.CustomFrame then AS.CustomFrame:Show() end
    end)

    local switchBtn = C:Button(parent, "Switch mood to Custom", 200, 28)
    switchBtn:SetPoint("LEFT", openBtn, "RIGHT", 8, 0)
    switchBtn:SetScript("OnClick", function()
        db().moodProfile = "Custom"
        AntiSocial:Print("mood profile set to Custom")
    end)
end

local function BuildProfiles(parent)
    local heading = C:Title(parent, "Saved variable profiles")
    heading:SetPoint("TOPLEFT", 16, -16)

    local desc = C:Body(parent,
        "Each character has its own profile by default. You can switch to a shared "
        .. "profile so multiple characters use the same setup. Profiles are managed "
        .. "by AceDB; for now use the slash commands listed below to manage them.")
    desc:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -42)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)

    -- Current profile display
    local currentBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    C:StyleRaised(currentBox)
    currentBox:SetHeight(60)
    currentBox:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    currentBox:SetPoint("TOPRIGHT", desc, "BOTTOMRIGHT", 0, -16)

    local lbl = C:Heading(currentBox, "Current profile")
    lbl:SetPoint("TOPLEFT", 12, -10)

    local name = C:Title(currentBox, AntiSocial.db:GetCurrentProfile())
    name:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)

    -- Profile commands hint
    local hint = C:Body(parent,
        "|cffff7f50/as profile copy <other>|r  copy from another character\n"
        .. "|cffff7f50/as profile list|r            list available profiles\n"
        .. "|cffff7f50/as profile reset|r           reset current to defaults")
    hint:SetPoint("TOPLEFT", currentBox, "BOTTOMLEFT", 0, -12)
    hint:SetJustifyH("LEFT")
end

local function BuildStats(parent)
    local heading = C:Title(parent, "Session stats")
    heading:SetPoint("TOPLEFT", 16, -16)

    local refresh = C:Button(parent, "Refresh", 80, 22)
    refresh:SetPoint("TOPRIGHT", -16, -18)

    local listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    C:StyleRaised(listFrame)
    listFrame:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -12)
    listFrame:SetPoint("BOTTOMRIGHT", -16, 16)

    local function repaint()
        for _, child in ipairs({ listFrame:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
            child:ClearAllPoints()
        end
        for _, region in ipairs({ listFrame:GetRegions() }) do
            if region.SetText then
                region:Hide()
                region:ClearAllPoints()
            end
        end

        local yOffset = -10
        local any = false
        for _, key in ipairs(AS.Messages.triggerKeys) do
            local count = AntiSocial.session.stats[key]
            if count and count > 0 then
                local rowLabel = C:Body(listFrame, AS.Messages.triggerLabels[key] or key)
                rowLabel:SetPoint("TOPLEFT", 16, yOffset)

                local countFs = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                countFs:SetPoint("TOPRIGHT", -16, yOffset)
                countFs:SetText(tostring(count))
                countFs:SetTextColor(unpack(C.color.accent))

                yOffset = yOffset - 22
                any = true
            end
        end

        -- Filtered whispers (separate category)
        local filtered = AntiSocial.session.stats.whispersFiltered
        if filtered and filtered > 0 then
            local rowLabel = C:Body(listFrame, "Whispers filtered")
            rowLabel:SetPoint("TOPLEFT", 16, yOffset)
            local countFs = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            countFs:SetPoint("TOPRIGHT", -16, yOffset)
            countFs:SetText(tostring(filtered))
            countFs:SetTextColor(unpack(C.color.accent))
            any = true
        end

        if not any then
            local empty = C:Dim(listFrame, "nothing fired yet this session")
            empty:SetPoint("CENTER")
        end
    end

    refresh:SetScript("OnClick", repaint)
    repaint()
end

local function BuildFilter(parent)
    local function fcfg() return db().whisperFilter end

    -- Master switch (narrowed to leave room for the log button on the right)
    local masterRow = C:Checkbox(parent, "Whisper filter enabled",
        function() return fcfg().enabled end,
        function(v) fcfg().enabled = v end)
    masterRow:SetPoint("TOPLEFT", 16, -16)
    masterRow:SetWidth(360)

    -- "View filter log" button anchored top-right of the panel
    local viewLogBtn = C:AccentButton(parent, "View filter log", 160, 28)
    viewLogBtn:SetPoint("TOPRIGHT", -16, -18)
    viewLogBtn:SetScript("OnClick", function()
        if AS.FilterLogFrame then AS.FilterLogFrame:Show() end
    end)

    local logCountFs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    logCountFs:SetPoint("RIGHT", viewLogBtn, "LEFT", -10, 0)
    local logCount = #AS.WhisperFilter:GetLog()
    logCountFs:SetText(("|cffaaaaaa%d entr%s|r"):format(
        logCount, logCount == 1 and "y" or "ies"))

    local masterDesc = C:Dim(parent,
        "Hides incoming whispers from your chat frame. Senders are not notified.")
    masterDesc:SetPoint("TOPLEFT", masterRow, "BOTTOMLEFT", 2, -2)

    -- Mode section
    local modeHeading = C:Heading(parent, "Filter mode")
    modeHeading:SetPoint("TOPLEFT", masterDesc, "BOTTOMLEFT", -2, -16)

    local modes = {
        { key = "blockLowLevel", label = "Low-level only",
          desc = "Hide whispers from players at or below the level threshold." },
        { key = "blockAll",      label = "Block all",
          desc = "Hide every whisper unless the sender is on a whitelist below." },
    }

    local modeCards = {}
    local cardW, cardH, cardGap = 200, 32, 8
    local modeDesc
    for i, mode in ipairs(modes) do
        local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
        card:SetSize(cardW, cardH)
        card:SetPoint("TOPLEFT", modeHeading, "BOTTOMLEFT", (i - 1) * (cardW + cardGap), -8)

        local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(mode.label)

        local function refresh()
            local active = fcfg().mode == mode.key
            C:StyleRow(card, active)
            label:SetTextColor(unpack(active and C.color.accent or C.color.textBody))
        end

        card:SetScript("OnEnter", function(self)
            if fcfg().mode ~= mode.key then
                self:SetBackdropBorderColor(unpack(C.color.borderHi))
            end
        end)
        card:SetScript("OnLeave", function(self)
            if fcfg().mode ~= mode.key then
                self:SetBackdropBorderColor(unpack(C.color.border))
            end
        end)
        card:SetScript("OnClick", function()
            fcfg().mode = mode.key
            for _, c in ipairs(modeCards) do c.Refresh() end
            modeDesc:SetText(mode.desc)
        end)

        card.Refresh = refresh
        refresh()
        table.insert(modeCards, card)
    end

    modeDesc = C:Dim(parent, "")
    modeDesc:SetPoint("TOPLEFT", modeCards[1], "BOTTOMLEFT", 2, -4)
    for _, m in ipairs(modes) do
        if m.key == fcfg().mode then modeDesc:SetText(m.desc) end
    end

    -- Level threshold slider (only meaningful in blockLowLevel mode)
    local levelLabel = C:Heading(parent, "Character level threshold")
    levelLabel:SetPoint("TOPLEFT", modeDesc, "BOTTOMLEFT", -2, -16)

    local levelDesc = C:Dim(parent,
        "Hide whispers from characters at or below this level (1 to 90).")
    levelDesc:SetPoint("TOPLEFT", levelLabel, "BOTTOMLEFT", 2, -2)

    local levelSlider = C:Slider(parent,
        "Block character levels up to and including:",
        1, 90, 1,
        function() return fcfg().levelThreshold end,
        function(v) fcfg().levelThreshold = v end,
        "Lvl %d")  -- value formatter
    levelSlider:SetWidth(280)
    levelSlider:SetPoint("TOPLEFT", levelDesc, "BOTTOMLEFT", -2, -8)

    -- Rejection notice toggle
    local noticeRow = C:Checkbox(parent, "Send rejection notice when blocking",
        function() return fcfg().sendRejectionNotice end,
        function(v) fcfg().sendRejectionNotice = v end)
    noticeRow:SetPoint("TOPLEFT", levelSlider, "BOTTOMLEFT", 0, -16)
    noticeRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, 0)

    local noticeDesc = C:Dim(parent,
        "Sends a single static reply (\"[AntiSocial]: <your name> has blocked you...\") to blocked senders. "
        .. "Throttled to once per minute per sender. The reply is hidden from your own chat.")
    noticeDesc:SetPoint("TOPLEFT", noticeRow, "BOTTOMLEFT", 2, -2)
    noticeDesc:SetPoint("TOPRIGHT", noticeRow, "BOTTOMRIGHT", -2, -2)
    noticeDesc:SetJustifyH("LEFT")
    noticeDesc:SetWordWrap(true)

    -- Whitelist toggles
    local listHeading = C:Heading(parent, "Always allow whispers from")
    listHeading:SetPoint("TOPLEFT", noticeDesc, "BOTTOMLEFT", -2, -16)

    local whitelist = {
        { key = "allowFriends",     label = "Friends" },
        { key = "allowBNetFriends", label = "Battle.net friends" },
        { key = "allowGuild",       label = "Guild members" },
        { key = "allowGroup",       label = "Party / raid members" },
    }
    for i, wl in ipairs(whitelist) do
        local row = i - 1
        local col = row % 2
        local rowIdx = math.floor(row / 2)
        local cb = C:Checkbox(parent, wl.label,
            function() return fcfg()[wl.key] end,
            function(v) fcfg()[wl.key] = v end)
        cb:SetWidth(260)
        cb:SetPoint("TOPLEFT", listHeading, "BOTTOMLEFT",
            col * (260 + 8), -8 - rowIdx * 36)
    end
end

local TAB_BUILDERS = {
    settings = BuildSettings,
    custom   = BuildCustom,
    profiles = BuildProfiles,
    stats    = BuildStats,
    filter   = BuildFilter,
}

local function SelectTab(key)
    currentTab = key
    for _, btn in pairs(tabButtons) do
        btn.SetActive(btn.key == key)
    end
    ClearContent()
    local builder = TAB_BUILDERS[key]
    if builder then builder(tabContent) end
end

-- ---------------------------------------------------------------------------
-- Window construction
-- ---------------------------------------------------------------------------
local function BuildFrame()
    frame = CreateFrame("Frame", "AntiSocialUI", UIParent, "BackdropTemplate")
    frame:SetSize(640, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    C:ApplyBackdrop(frame, C.color.bgPanel, C.color.border, 1)

    tinsert(UISpecialFrames, "AntiSocialUI")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    C:ApplyBackdrop(titleBar, C.color.bgRaised, C.color.accent, 1)

    -- Accent badge "A"
    local badge = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    badge:SetSize(20, 20)
    badge:SetPoint("LEFT", 10, 0)
    C:ApplyBackdrop(badge, C.color.accent, C.color.borderHi, 1)
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("CENTER")
    badgeText:SetText("A")
    badgeText:SetTextColor(unpack(C.color.bgDeep))

    -- Title
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", badge, "RIGHT", 8, 0)
    title:SetText("AntiSocial")
    title:SetTextColor(unpack(C.color.textBright))

    local version = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 6, -1)
    version:SetText("v" .. AntiSocial.version)
    version:SetTextColor(unpack(C.color.textMuted))

    -- Close button
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

    -- Help (?) button, left of the close button
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
        GameTooltip:SetText("AntiSocial help", 1, 0.498, 0.314)
        GameTooltip:AddLine("Click for an overview of what AntiSocial does.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(C.color.border))
        helpText:SetTextColor(unpack(C.color.textDim))
        GameTooltip:Hide()
    end)
    helpBtn:SetScript("OnClick", function()
        if AS.UI.ShowHelp then AS.UI:ShowHelp() end
    end)

    -- Tab strip
    local tabBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tabBar:SetHeight(32)
    tabBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    tabBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    C:ApplyBackdrop(tabBar, C.color.bgRaised, C.color.border, 1)

    local xOffset = 0
    for _, tab in ipairs(TABS) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetSize(110, 32)
        btn:SetPoint("LEFT", xOffset, 0)
        btn.key = tab.key

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", 0, 2)
        label:SetText(tab.label:upper())
        btn.label = label

        local underline = btn:CreateTexture(nil, "OVERLAY")
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", 0, 0)
        underline:SetColorTexture(unpack(C.color.accent))
        underline:Hide()

        function btn.SetActive(active)
            if active then
                label:SetTextColor(unpack(C.color.accent))
                underline:Show()
            else
                label:SetTextColor(unpack(C.color.textDim))
                underline:Hide()
            end
        end

        btn:SetScript("OnEnter", function() label:SetTextColor(unpack(C.color.textBright)) end)
        btn:SetScript("OnLeave", function()
            label:SetTextColor(unpack(btn.key == currentTab and C.color.accent or C.color.textDim))
        end)
        btn:SetScript("OnClick", function() SelectTab(tab.key) end)

        tabButtons[tab.key] = btn
        xOffset = xOffset + 110
    end

    -- Content area
    tabContent = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tabContent:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT")
    tabContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 24)
    C:ApplyBackdrop(tabContent, C.color.bgPanel, C.color.border, 1)

    -- Status bar
    local statusBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statusBar:SetHeight(24)
    statusBar:SetPoint("BOTTOMLEFT")
    statusBar:SetPoint("BOTTOMRIGHT")
    C:ApplyBackdrop(statusBar, C.color.bgRaised, C.color.border, 1)

    local tagline = statusBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tagline:SetPoint("LEFT", 12, 0)
    tagline:SetText("Minimal human interaction, maximum efficiency.")
    tagline:SetTextColor(unpack(C.color.textMuted))

    local sessionInfo = statusBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sessionInfo:SetPoint("RIGHT", -12, 0)
    sessionInfo:SetTextColor(unpack(C.color.textMuted))
    frame.sessionInfo = sessionInfo

    SelectTab(currentTab)
end

-- ---------------------------------------------------------------------------
-- Status updater (updates "N messages sent this session" in status bar)
-- ---------------------------------------------------------------------------
local function UpdateStatus()
    if not frame or not frame.sessionInfo then return end
    local total = 0
    for _, count in pairs(AntiSocial.session.stats or {}) do
        total = total + count
    end
    frame.sessionInfo:SetText(total .. " message" .. (total == 1 and "" or "s") .. " sent this session")
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function AS.UI:Show(tabKey)
    if not frame then BuildFrame() end
    if tabKey then SelectTab(tabKey) end
    UpdateStatus()
    frame:Show()
    frame:Raise()
end

function AS.UI:Hide()
    if frame then frame:Hide() end
end

function AS.UI:Toggle(tabKey)
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show(tabKey)
    end
end

-- ---------------------------------------------------------------------------
-- Help popup (overview of the whole addon)
-- ---------------------------------------------------------------------------
local helpFrame

local HELP_TEXT = [[|cffff7f50AntiSocial - Overview|r

A tiny QoL addon that handles social pleasantries you'd rather not
type yourself, and filters whispers you'd rather not see.

|cffff7f50Auto-messages on game events|r
Fires randomized chat messages on a 1-8 second delay when:
- You join a party or raid (says hi)
- You leave a group (says ty)
- A group member earns an achievement (gz)
- A group member levels up (gz)
- A Mythic+ key completes (gg / unlucky)
- A ready check pops (auto-confirm, off by default)

|cffff7f50Mood profiles|r
Pick a tone the addon uses:
- |cffff7f50Introvert|r: bare minimum (hi / gg)
- |cffff7f50Friendly|r: warm, expressive (heya / nice key)
- |cffff7f50Goblin|r: chaotic key-pusher (pumpers? / ez clap)
- |cffff7f50Raider|r: terse, business (ggs / wp)
- |cffff7f50Custom|r: your own messages

|cffff7f50Whisper filter|r
Hides whispers from your chat frame based on rules:
- Block low-level characters (configurable level)
- Block all whispers except friends/guild/group
Optional: send a static rejection notice back to the sender,
throttled to once per minute per sender.

|cffff7f50Saved variable profiles|r
Per-character by default. Switch to a shared profile in the
Profiles tab to apply the same setup across alts.

|cffaaaaaaSlash commands:|r
- /as              open this window
- /as on / off
- /as profile <name>
- /as custom       open the custom pool editor
- /as filter on / off / status / log
- /as test         preview what each trigger would say
- /as stats        show this session's trigger counts
- /as debug        toggle debug output

|cffaaaaaaTip:|r Each panel (Settings, Custom Pools, Whisper Filter,
Stats, Profiles) has its own tab in the strip above. Some sub-panels
like the Custom Pools editor have their own (?) help button for
more detail.]]

local function BuildHelpFrame()
    helpFrame = CreateFrame("Frame", "AntiSocialMainHelpUI", UIParent, "BackdropTemplate")
    helpFrame:SetSize(480, 520)
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
    tinsert(UISpecialFrames, "AntiSocialMainHelpUI")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, helpFrame, "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    C:ApplyBackdrop(titleBar, C.color.bgRaised, C.color.accent, 1)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 12, 0)
    title:SetText("Help: AntiSocial")
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

    -- Scrollable content
    local content = CreateFrame("Frame", nil, helpFrame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", helpFrame, "BOTTOMRIGHT", -8, 8)
    C:ApplyBackdrop(content, C.color.bgDeep, C.color.border, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(420, 1000)
    scrollFrame:SetScrollChild(scrollChild)

    local helpFs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    helpFs:SetPoint("TOPLEFT", 4, -4)
    helpFs:SetPoint("TOPRIGHT", -4, -4)
    helpFs:SetJustifyH("LEFT")
    helpFs:SetJustifyV("TOP")
    helpFs:SetText(HELP_TEXT)
    helpFs:SetTextColor(unpack(C.color.textBody))
    helpFs:SetSpacing(2)

    local h = helpFs:GetStringHeight() + 16
    scrollChild:SetHeight(math.max(h, 1))
end

function AS.UI:ShowHelp()
    if not helpFrame then BuildHelpFrame() end
    helpFrame:Show()
    helpFrame:Raise()
end
