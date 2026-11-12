-- Triggers.lua, event registration via AceEvent, AceTimer dispatch
local _, AS = ...
AS.Triggers = {}

-- Per-event handlers. Avoids comparing the event name (which can be a
-- tainted "secret string" in recent WoW versions, breaking == comparisons).
-- AceEvent calls function handlers as handler(event, ...), so the event
-- payload (message text first) starts right after the event name.
function AS.Triggers:Register(addon)
    self.addon = addon
    addon:RegisterEvent("GROUP_ROSTER_UPDATE",       function() AS.Triggers:OnGroupRoster() end)
    addon:RegisterEvent("CHALLENGE_MODE_START",      function() AS.Triggers:OnKeyStart() end)
    addon:RegisterEvent("CHALLENGE_MODE_COMPLETED",  function() AS.Triggers:OnKeyComplete() end)
    addon:RegisterEvent("CHAT_MSG_ACHIEVEMENT",      function(_, ...) AS.Triggers:OnAchievement(...) end)
    addon:RegisterEvent("CHAT_MSG_GUILD_ACHIEVEMENT",function(_, ...) AS.Triggers:OnAchievement(...) end)
    addon:RegisterEvent("CHAT_MSG_SYSTEM",           function(_, ...) AS.Triggers:OnSystemMessage(...) end)
    addon:RegisterEvent("READY_CHECK",               function() AS.Triggers:OnReadyCheck() end)
    addon:RegisterEvent("PLAYER_LEVEL_UP",           function() end) -- placeholder, no-op
end

function AS.Triggers:Unregister(addon)
    local events = {
        "GROUP_ROSTER_UPDATE", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
        "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT", "CHAT_MSG_SYSTEM",
        "READY_CHECK", "PLAYER_LEVEL_UP",
    }
    for _, ev in ipairs(events) do addon:UnregisterEvent(ev) end
end

local function db()
    return AntiSocial and AntiSocial.db and AntiSocial.db.profile
end

local function PickChannel()
    if IsInRaid() then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        return "RAID"
    elseif IsInGroup() then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        return "PARTY"
    end
    return nil
end

local function ScheduleSend(text, channelOverride, statKey)
    if not text then return end
    local p = db()
    if not p or not p.enabled then return end

    local minD = p.minDelay or 1
    local maxD = p.maxDelay or 8
    if maxD < minD then maxD = minD end
    local delay = minD + math.random() * (maxD - minD)

    AntiSocial:ScheduleTimer(function()
        local channel = channelOverride or PickChannel()
        if not channel then
            AntiSocial:Debug("no channel available, skipping: " .. text)
            return
        end
        AntiSocial:Debug(("send [%s] %s (delay %.1fs)"):format(channel, text, delay))
        SendChatMessage(text, channel)
        if statKey then AntiSocial:RecordFire(statKey) end
    end, delay)
end

local function CanFire(triggerKey, cooldown)
    cooldown = cooldown or 5
    local now = GetTime()
    local last = AntiSocial.session.lastFired[triggerKey] or 0
    if now - last < cooldown then return false end
    AntiSocial.session.lastFired[triggerKey] = now
    return true
end

local function IsTriggerEnabled(key)
    local p = db()
    return p and p.enabled and p.triggers and p.triggers[key]
end

-- Retail 12.x and Forever hand chat event args to addons as "secret" values
-- in restricted content. Addon code errors if it indexes or compares them,
-- so those messages are skipped.
local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- True if the sender is someone else in our party/raid. Matches on the
-- sender GUID when the event has one (name formats differ between clients),
-- otherwise on the character name without realm.
local function IsOtherGroupMember(name, guid)
    local key, lookup
    if type(guid) == "string" and guid ~= "" then
        key, lookup = guid, UnitGUID
    else
        key, lookup = name and name:match("^([^%-]+)"), UnitName
    end
    local own = lookup("player")
    if not key or IsSecret(own) or key == own then return false end

    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local value = lookup(prefix .. i)
        if value and not IsSecret(value) and value == key then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------
local function HandleGroupRosterChange()
    local nowInGroup = IsInGroup()
    local wasInGroup = AntiSocial.session.inGroup
    AntiSocial.session.inGroup = nowInGroup

    if nowInGroup and not wasInGroup then
        -- Suppress the join greeting during the login grace period. On a
        -- reconnect or relog into a group you were already in, IsInGroup()
        -- can briefly report false at OnEnable (roster not yet synced),
        -- then GROUP_ROSTER_UPDATE fires with the real roster and looks
        -- like a fresh join. The grace window swallows that false positive.
        if AntiSocial.session.loginTime
            and (GetTime() - AntiSocial.session.loginTime) < 15 then
            AntiSocial:Debug("groupJoin suppressed (login grace)")
            return
        end
        if IsTriggerEnabled("groupJoin") and CanFire("groupJoin", 30) then
            ScheduleSend(AS.Messages:Pick("groupJoin"), nil, "groupJoin")
        end
    elseif not nowInGroup and wasInGroup then
        -- Same grace guard: if you were removed from the group while
        -- disconnected, don't fire a leave message on reconnect.
        if AntiSocial.session.loginTime
            and (GetTime() - AntiSocial.session.loginTime) < 15 then
            AntiSocial:Debug("groupLeave suppressed (login grace)")
            return
        end
        if IsTriggerEnabled("groupLeave") and CanFire("groupLeave", 30) then
            local message = AS.Messages:Pick("groupLeave")
            if message then
                local channel = "PARTY"
                AntiSocial:Debug(("send [%s] %s"):format(channel, message))
                SendChatMessage(message, channel)
                AntiSocial:RecordFire("groupLeave")
            end
        end
    end
end

local function HandleKeyComplete()
    if not IsTriggerEnabled("keyComplete") then return end
    if not CanFire("keyComplete", 60) then return end

    local info = C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo
        and C_ChallengeMode.GetChallengeCompletionInfo()
    local onTime = info and info.onTime
    local key
    if onTime == true then
        key = "keyTimed"
    elseif onTime == false then
        key = "keyDepleted"
    else
        key = "keyDefault"
    end
    ScheduleSend(AS.Messages:Pick(key), nil, key)
    AntiSocial.session.keyActive = false
end

-- Chat event args: message text, sender name, ..., sender GUID (arg12).
local function HandleAchievement(msg, playerName, ...)
    local guid = select(10, ...)
    if IsSecret(msg) or IsSecret(playerName) or IsSecret(guid) then return end
    if not IsTriggerEnabled("achievement") then return end
    if not msg or not playerName or playerName == "" then return end

    -- Achievement broadcasts also cover nearby players, guildmates and you.
    if not IsInGroup() then return end
    if not IsOtherGroupMember(playerName, guid) then return end
    -- One congratulation per burst: a whole group often earns an achievement together.
    if not CanFire("achievement", 10) then return end

    local achievementID = msg:match("Hachievement:(%d+)")
    local rare = false
    if achievementID and GetAchievementInfo then
        local _, _, points = GetAchievementInfo(tonumber(achievementID))
        if points and points >= 25 then rare = true end
    end

    ScheduleSend(AS.Messages:Pick("achievement", { rare = rare }), nil, "achievement")
end

local function HandleSystemMessage(msg)
    if not msg or IsSecret(msg) then return end
    if not IsTriggerEnabled("levelUp") then return end
    if not IsInGroup() then return end

    local name = msg:match("^(%S+) has reached level %d+")
    if not name or not IsOtherGroupMember(name) then return end

    if not CanFire("levelUp", 10) then return end
    ScheduleSend(AS.Messages:Pick("levelUp"), nil, "levelUp")
end

local function HandleReadyCheck()
    if not IsTriggerEnabled("readyCheck") then return end
    if not CanFire("readyCheck", 5) then return end
    AntiSocial:ScheduleTimer(function()
        if ReadyCheckFrame and ReadyCheckFrame:IsShown() then
            ConfirmReadyCheck(true)
            AntiSocial:RecordFire("readyCheck")
        end
    end, 0.5 + math.random() * 1.5)
end

-- ---------------------------------------------------------------------------
-- Per-event method dispatchers (no event-name comparison required)
-- ---------------------------------------------------------------------------
local function enabled()
    local p = db()
    return p and p.enabled
end

function AS.Triggers:OnGroupRoster()
    if not enabled() then return end
    HandleGroupRosterChange()
end

function AS.Triggers:OnKeyStart()
    if not enabled() then return end
    AntiSocial.session.keyActive = true
end

function AS.Triggers:OnKeyComplete()
    if not enabled() then return end
    HandleKeyComplete()
end

function AS.Triggers:OnAchievement(...)
    if not enabled() then return end
    HandleAchievement(...)
end

function AS.Triggers:OnSystemMessage(...)
    if not enabled() then return end
    HandleSystemMessage(...)
end

function AS.Triggers:OnReadyCheck()
    if not enabled() then return end
    HandleReadyCheck()
end

function AS.Triggers:TestFire()
    local p = db()
    local samples = {
        { "groupJoin",   "group join" },
        { "keyTimed",    "key timed" },
        { "keyDepleted", "key depleted" },
        { "achievement", "achievement" },
        { "levelUp",     "level up" },
        { "groupLeave",  "group leave" },
    }
    AntiSocial:Print("test (mood: " .. (p and p.moodProfile or "?") .. "):")
    for _, s in ipairs(samples) do
        print(("  %s -> %s"):format(s[2], tostring(AS.Messages:Pick(s[1]))))
    end
end
