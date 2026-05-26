-- AntiSocial: Minimal human interaction, maximum efficiency.
-- Core.lua, AceAddon bootstrap, AceDB profile management, slash commands.

local addonName, AS = ...
local AntiSocial = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
_G.AntiSocial = AntiSocial
AS.addon = AntiSocial

-- Pull version from the TOC's ## Version field so there's one source of truth.
-- Uses the modern C_AddOns API with a fallback to the legacy global.
local function readTocVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(addonName, "Version") or "?"
    end
    return "?"
end

AntiSocial.version = readTocVersion()

-- ---------------------------------------------------------------------------
-- AceDB defaults
-- ---------------------------------------------------------------------------
-- Profile-scoped: settings the user might want to vary per character.
-- Global-scoped: anything that should always be account-wide (none for now).
AntiSocial.defaults = {
    profile = {
        enabled = true,
        moodProfile = "Friendly", -- Introvert, Friendly, Goblin, Raider, Custom
        minDelay = 1,
        maxDelay = 8,
        triggers = {
            groupJoin   = true,
            keyComplete = true,
            groupLeave  = true,
            achievement = true,
            levelUp     = true,
            readyCheck  = false,
        },
        customPools = {
            groupJoin   = {},
            keyTimed    = {},
            keyDepleted = {},
            keyDefault  = {},
            groupLeave  = {},
            achievement = {},
            levelUp     = {},
            readyCheck  = {},
        },
        whisperFilter = {
            enabled              = false,
            mode                 = "blockLowLevel",
            levelThreshold       = 10,
            allowFriends         = true,
            allowBNetFriends     = true,
            allowGuild           = true,
            allowGroup           = true,
            sendRejectionNotice  = true,
        },
        whisperFilterLog = {},
        whisperFilterNoticeSent = {},
        debug = false,
    },
}

-- Session state (never persisted)
AntiSocial.session = {
    inGroup = false,
    lastFired = {},
    keyActive = false,
    stats = {},
}

-- ---------------------------------------------------------------------------
-- Migration from 1.0.x raw-table SavedVariables to AceDB
-- ---------------------------------------------------------------------------
local function migrateLegacy()
    -- If AntiSocialDB exists but doesn't have AceDB's structure, we have a
    -- legacy 1.0.x install. Copy fields into the new profile defaults so
    -- users don't lose their setup.
    if type(AntiSocialDB) ~= "table" then return end
    if AntiSocialDB.profileKeys or AntiSocialDB.profiles then return end -- already AceDB

    -- Save what we can find under a known key, picked up by AceDB-3.0 when
    -- it initialises and finds no existing profile data for this character.
    local legacy = {
        enabled     = AntiSocialDB.enabled,
        moodProfile = AntiSocialDB.profile, -- field name changed
        minDelay    = AntiSocialDB.minDelay,
        maxDelay    = AntiSocialDB.maxDelay,
        triggers    = AntiSocialDB.triggers,
        customPools = AntiSocialDB.customPools,
        debug       = AntiSocialDB.debug,
    }
    AntiSocial._pendingLegacy = legacy
    -- Wipe so AceDB can take over the slot cleanly.
    wipe(AntiSocialDB)
end

local function applyPendingLegacy(profile)
    local legacy = AntiSocial._pendingLegacy
    if not legacy then return end
    for k, v in pairs(legacy) do
        if v ~= nil then profile[k] = v end
    end
    AntiSocial._pendingLegacy = nil
end

-- ---------------------------------------------------------------------------
-- AceAddon lifecycle
-- ---------------------------------------------------------------------------
function AntiSocial:OnInitialize()
    migrateLegacy()

    self.db = LibStub("AceDB-3.0"):New("AntiSocialDB", self.defaults, true)
    -- "true" above defaults to the character's own profile, then falls back
    -- to Default if not set. The user can copy/share profiles in the
    -- "Profiles" panel of the config UI.

    applyPendingLegacy(self.db.profile)

    -- Profile change callbacks: refresh anything that caches DB references.
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied",  "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset",   "RefreshConfig")

    -- Slash command bindings (AceConsole)
    self:RegisterChatCommand("antisocial", "SlashHandler")
    self:RegisterChatCommand("as",         "SlashHandler")

    -- Options table registration (defined in Options.lua)
    -- UI is built lazily on first /as call; nothing to register at init.
end

function AntiSocial:OnEnable()
    self.session.inGroup = IsInGroup()
    self.session.loginTime = GetTime()
    if AS.Triggers and AS.Triggers.Register then
        AS.Triggers:Register(self)
    end
    if AS.WhisperFilter and AS.WhisperFilter.Register then
        AS.WhisperFilter:Register()
    end
    self:Debug("Loaded v" .. self.version .. ", profile: " .. self.db.profile.moodProfile)
end

function AntiSocial:OnDisable()
    if AS.Triggers and AS.Triggers.Unregister then
        AS.Triggers:Unregister(self)
    end
    if AS.WhisperFilter and AS.WhisperFilter.Unregister then
        AS.WhisperFilter:Unregister()
    end
end

function AntiSocial:RefreshConfig()
    self:Print("profile switched to '" .. self.db:GetCurrentProfile() .. "'")
end

-- ---------------------------------------------------------------------------
-- Helpers exposed to other files
-- ---------------------------------------------------------------------------
function AntiSocial:Debug(msg)
    if self.db and self.db.profile.debug then
        self:Print("|cffaaaaaa[debug]|r " .. tostring(msg))
    end
end

function AntiSocial:RecordFire(triggerKey)
    self.session.stats[triggerKey] = (self.session.stats[triggerKey] or 0) + 1
end

-- ---------------------------------------------------------------------------
-- Slash command dispatcher
-- ---------------------------------------------------------------------------
local VALID_PROFILES = { Introvert = true, Friendly = true, Goblin = true, Raider = true, Custom = true }

local function capitalize(s)
    if not s or s == "" then return s end
    return s:sub(1, 1):upper() .. s:sub(2):lower()
end

local function printUsage(self)
    self:Print("commands:")
    print("  /as                       open settings")
    print("  /as on | off | toggle")
    print("  /as profile <name>        Introvert, Friendly, Goblin, Raider, Custom")
    print("  /as custom                open custom pool editor")
    print("  /as test                  preview what each trigger says")
    print("  /as stats                 show this session's trigger counts")
    print("  /as filter <sub>          on/off/toggle/status/log/clear")
    print("  /as add <trigger> <text>  add to custom pool")
    print("  /as remove <trigger> <n>  remove entry n from custom pool")
    print("  /as list <trigger>        list custom pool entries")
    print("  /as clear <trigger>       clear a custom pool")
    print("  /as debug                 toggle debug output")
end

local function printStats(self)
    self:Print("session stats:")
    local labels = AS.Messages.triggerLabels
    local any = false
    for _, key in ipairs(AS.Messages.triggerKeys) do
        local count = self.session.stats[key]
        if count and count > 0 then
            print(("  %-20s %d"):format(labels[key] or key, count))
            any = true
        end
    end
    if not any then print("  (nothing fired yet this session)") end
end

local function listCustom(self, triggerKey)
    local list = AS.Messages:GetCustomPool(triggerKey)
    local label = AS.Messages.triggerLabels[triggerKey] or triggerKey
    if #list == 0 then
        self:Print("custom pool [" .. label .. "] is empty")
        return
    end
    self:Print("custom pool [" .. label .. "]:")
    for i, entry in ipairs(list) do
        print(("  %d. %s"):format(i, entry))
    end
end

function AntiSocial:SlashHandler(input)
    input = input or ""
    local cmd, rest = input:match("^%s*(%S*)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "config" or cmd == "options" then
        if AS.UI then AS.UI:Show() end

    elseif cmd == "on" then
        self.db.profile.enabled = true
        self:Print("enabled")

    elseif cmd == "off" then
        self.db.profile.enabled = false
        self:Print("disabled")

    elseif cmd == "toggle" then
        self.db.profile.enabled = not self.db.profile.enabled
        self:Print(self.db.profile.enabled and "enabled" or "disabled")

    elseif cmd == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        self:Print("debug " .. (self.db.profile.debug and "on" or "off"))

    elseif cmd == "profile" then
        if rest == "" then
            self:Print("current mood profile: " .. self.db.profile.moodProfile)
        else
            local p = capitalize(rest:match("^(%S+)"))
            if VALID_PROFILES[p] then
                self.db.profile.moodProfile = p
                self:Print("mood profile set to " .. p)
                if p == "Custom" and AS.CustomFrame then
                    local hasAny = false
                    for _, pool in pairs(self.db.profile.customPools or {}) do
                        if type(pool) == "table" and #pool > 0 then hasAny = true; break end
                    end
                    if not hasAny then
                        self:Print("opening custom pool editor (empty pools fall back to Friendly)")
                        AS.CustomFrame:Show()
                    end
                end
            else
                self:Print("unknown profile. Options: Introvert, Friendly, Goblin, Raider, Custom")
            end
        end

    elseif cmd == "custom" then
        if AS.CustomFrame then AS.CustomFrame:Show() end

    elseif cmd == "test" then
        if AS.Triggers then AS.Triggers:TestFire() end

    elseif cmd == "stats" then
        printStats(self)

    elseif cmd == "filter" then
        local sub = rest:match("^(%S+)")
        sub = sub and sub:lower() or ""
        local fc = self.db.profile.whisperFilter
        if sub == "" or sub == "status" then
            self:Print(("whisper filter: %s, mode=%s, threshold=L%d"):format(
                fc.enabled and "ON" or "off", fc.mode, fc.levelThreshold))
        elseif sub == "on" then
            fc.enabled = true
            self:Print("whisper filter enabled")
        elseif sub == "off" then
            fc.enabled = false
            self:Print("whisper filter disabled")
        elseif sub == "toggle" then
            fc.enabled = not fc.enabled
            self:Print("whisper filter " .. (fc.enabled and "enabled" or "disabled"))
        elseif sub == "log" then
            local log = AS.WhisperFilter:GetLog()
            if #log == 0 then
                self:Print("filter log is empty")
            else
                self:Print(("filter log (%d entries, newest first):"):format(#log))
                for i = #log, math.max(1, #log - 9), -1 do
                    local e = log[i]
                    print(("  %s L%d %s: %s"):format(
                        date("%H:%M", e.timestamp), e.level or 0, e.sender or "?",
                        (e.message or ""):sub(1, 60)))
                end
            end
        elseif sub == "clear" then
            AS.WhisperFilter:ClearLog()
            self:Print("filter log cleared")
        elseif sub == "test" or sub == "diagnose" then
            AS.WhisperFilter:Diagnose()
        else
            self:Print("usage: /as filter on|off|toggle|status|log|clear|test")
        end

    elseif cmd == "add" then
        local trigger, text = rest:match("^(%S+)%s+(.+)$")
        if not trigger or not text then
            self:Print("usage: /as add <trigger> <text>")
            return
        end
        if not AS.Messages.triggerLabels[trigger] then
            self:Print("unknown trigger. Options: " .. table.concat(AS.Messages.triggerKeys, ", "))
            return
        end
        local ok, err = AS.Messages:AddCustom(trigger, text)
        if ok then
            self:Print("added to " .. trigger .. ": " .. text)
        else
            self:Print("could not add: " .. tostring(err))
        end

    elseif cmd == "remove" then
        local trigger, idx = rest:match("^(%S+)%s+(%d+)$")
        if not trigger or not idx then
            self:Print("usage: /as remove <trigger> <index>")
            return
        end
        local ok, removed = AS.Messages:RemoveCustom(trigger, tonumber(idx))
        if ok then
            self:Print("removed from " .. trigger .. ": " .. tostring(removed))
        else
            self:Print("could not remove: " .. tostring(removed))
        end

    elseif cmd == "list" then
        local trigger = rest:match("^(%S+)")
        if not trigger or not AS.Messages.triggerLabels[trigger] then
            self:Print("usage: /as list <trigger>")
            return
        end
        listCustom(self, trigger)

    elseif cmd == "clear" then
        local trigger = rest:match("^(%S+)")
        if not trigger or not AS.Messages.triggerLabels[trigger] then
            self:Print("usage: /as clear <trigger>")
            return
        end
        AS.Messages:ClearCustom(trigger)
        self:Print("cleared custom pool: " .. trigger)

    else
        printUsage(self)
    end
end
