-- WhisperFilter.lua, configurable incoming-whisper filter.
--
-- Behavior model (matches the long-standing BadBoy_Levels pattern, which has
-- been on CurseForge for years without ToS issues):
--
--   1. Filter incoming whisper out of chat (CHAT_MSG_WHISPER filter)
--   2. Send a single fixed-text rejection notice via SendChatMessage
--   3. Filter the OUTGOING whisper notice (CHAT_MSG_WHISPER_INFORM) so the
--      user doesn't see their own auto-reply in chat
--   4. Throttle per-sender (60s cooldown) so repeat whispers don't spam
--   5. The reply message is static and identical for every sender. It does
--      not react to what they said. It is never AI-generated.
--
-- These five properties together are what make this pattern acceptable.
-- DO NOT add any feature that varies the reply based on the sender's
-- message content, or sends more than one notice per cooldown window.

local _, AS = ...
AS.WhisperFilter = {}

-- Rejection notice template. Static text, identical every time. The %s
-- placeholder is filled with our own character first name (not the sender's
-- input) at send-time, never reactive to the whisper contents.
local REJECT_NOTICE_TEMPLATE =
    "[AntiSocial]: %s has blocked you from messaging them. The message you just sent was not delivered."

local LEVEL_QUERY_TIMEOUT = 2.0
local LOG_MAX_ENTRIES = 100
local REPLY_COOLDOWN_SECONDS = 60

-- Per-sender rejection-notice cooldown is now persisted in the AceDB
-- profile under `whisperFilterNoticeSent` so /reload doesn't reset it.

-- IDs of outgoing whispers we've sent ourselves (so we can suppress them
-- from CHAT_MSG_WHISPER_INFORM and not show our own auto-reply in chat)
local outgoingFilterIds = {}

-- ---------------------------------------------------------------------------
-- DB
-- ---------------------------------------------------------------------------
local function cfg()
    return AntiSocial and AntiSocial.db and AntiSocial.db.profile and AntiSocial.db.profile.whisperFilter
end

local function logDB()
    -- Always return the existing table reference. AceDB's defaults guarantee
    -- whisperFilterLog exists as an empty table on profile creation, so we
    -- don't need to reassign here (which would break AceDB's change tracking).
    if not AntiSocial.db.profile.whisperFilterLog then
        AntiSocial.db.profile.whisperFilterLog = {}
    end
    return AntiSocial.db.profile.whisperFilterLog
end

-- Debug print that always shows up when filter is active, useful for
-- diagnosing why a whisper was or wasn't filtered.
local function debugLog(...)
    if AntiSocial and AntiSocial.db and AntiSocial.db.profile and AntiSocial.db.profile.debug then
        print("|cffff7f50[AS filter]|r", ...)
    end
end

-- ---------------------------------------------------------------------------
-- Sender classification
-- ---------------------------------------------------------------------------
local function nameOnly(fullName)
    if not fullName then return nil end
    return fullName:match("^([^%-]+)") or fullName
end

local function isFriend(name)
    if not name then return false end
    if not C_FriendList or not C_FriendList.GetNumFriends then return false end
    local short = nameOnly(name)
    -- Trigger a fetch if the list is empty; it's a server roundtrip but cheap
    if C_FriendList.GetNumFriends() == 0 and C_FriendList.ShowFriends then
        C_FriendList.ShowFriends()
    end
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name and nameOnly(info.name) == short then return true end
    end
    return false
end

local function isBNetFriend(name)
    if not name or not BNGetNumFriends then return false end
    local short = nameOnly(name)
    local total = BNGetNumFriends()
    for i = 1, total do
        if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
            local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
            if accountInfo and accountInfo.gameAccountInfo then
                local ga = accountInfo.gameAccountInfo
                if ga.characterName and nameOnly(ga.characterName) == short then return true end
            end
        end
    end
    return false
end

local function isGuildMate(name)
    if not name or not GetNumGuildMembers or not IsInGuild() then return false end
    local short = nameOnly(name)
    -- Roster may be empty until we request it
    if GetNumGuildMembers() == 0 and GuildRoster then GuildRoster() end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    for i = 1, GetNumGuildMembers() do
        local fullName = GetGuildRosterInfo(i)
        if fullName and nameOnly(fullName) == short then return true end
    end
    return false
end

local function isInMyGroup(name)
    if not name or not IsInGroup() then return false end
    local short = nameOnly(name)
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers() or 0
    for i = 1, count do
        local unit = prefix .. i
        local unitName = UnitName(unit)
        if unitName == short then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Level lookup
-- ---------------------------------------------------------------------------
local function tryGetLevelImmediate(name)
    if not name then return nil end
    local short = nameOnly(name)
    local candidates = { "target", "mouseover", "focus" }
    if IsInGroup() then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, GetNumGroupMembers() do
            table.insert(candidates, prefix .. i)
        end
    end
    for _, unit in ipairs(candidates) do
        if UnitExists(unit) and UnitName(unit) == short then
            local lvl = UnitLevel(unit)
            if lvl and lvl > 0 then return lvl end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Filter decision
-- ---------------------------------------------------------------------------
-- Returns true if the whisper should be filtered, false if shown,
-- nil if we need to defer for a level check.
local function shouldFilter(senderName, level)
    local c = cfg()
    if not c or not c.enabled then return false end

    -- Whitelist
    if c.allowFriends and isFriend(senderName) then
        debugLog(senderName, "allowed (friend)")
        return false
    end
    if c.allowBNetFriends and isBNetFriend(senderName) then
        debugLog(senderName, "allowed (BNet friend)")
        return false
    end
    if c.allowGuild and isGuildMate(senderName) then
        debugLog(senderName, "allowed (guild)")
        return false
    end
    if c.allowGroup and isInMyGroup(senderName) then
        debugLog(senderName, "allowed (group)")
        return false
    end

    if c.mode == "blockAll" then
        debugLog(senderName, "FILTERED (block all)")
        return true
    end

    if c.mode == "blockLowLevel" then
        if not level then return nil end -- defer
        if level <= (c.levelThreshold or 10) then
            debugLog(senderName, "FILTERED (L" .. level .. " <= " .. c.levelThreshold .. ")")
            return true
        end
        debugLog(senderName, "allowed (L" .. level .. " > " .. c.levelThreshold .. ")")
        return false
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Log
-- ---------------------------------------------------------------------------
local function logFiltered(sender, level, message, source)
    local log = logDB()
    local now = time()

    -- Anti-replay check 0 (MOST IMPORTANT): suppress logging during the
    -- login grace period. WoW replays recent chat history on /reload and
    -- delivers queued offline whispers on relog; both fire CHAT_MSG_WHISPER
    -- which we'd otherwise treat as fresh log entries. If a user cleared
    -- the log before reloading, this is what prevents the entries from
    -- "coming back". The whisper is still filtered from chat normally,
    -- just not added to the log. 10 seconds matches the notice grace.
    if AntiSocial.session.loginTime then
        local sinceLogin = GetTime() - AntiSocial.session.loginTime
        if sinceLogin < 10 then
            debugLog(sender, "log suppressed (login grace,", sinceLogin, "s)")
            return
        end
    end

    -- Anti-replay check 1: if we already have an identical entry in the
    -- last 24h, this is a reload/relog replay that slipped past the login
    -- grace window (e.g. a slow relog), not a fresh whisper.
    local recentCutoff = now - 86400
    for i = #log, math.max(1, #log - 50), -1 do
        local existing = log[i]
        if existing.timestamp < recentCutoff then break end
        if existing.sender == sender and existing.message == ((message or ""):sub(1, 200)) then
            debugLog(sender, "log dedup, same sender+message within 24h")
            return
        end
    end

    -- Anti-replay check 2: notice-throttle backstop for the in-between case
    -- where login grace expired but the original whisper is still being
    -- replayed (rare, but possible with slow chat-history catchup).
    local sentTimes = AntiSocial.db.profile.whisperFilterNoticeSent
    if sentTimes and sentTimes[sender] then
        local seenAgo = now - sentTimes[sender]
        if seenAgo < 600 then
            debugLog(sender, "log dedup via notice throttle (seen", seenAgo, "s ago)")
            return
        end
    end

    table.insert(log, {
        sender    = sender or "?",
        level     = level or 0,
        message   = (message or ""):sub(1, 200),
        timestamp = now,
        source    = source or "whisper",
    })
    while #log > LOG_MAX_ENTRIES do
        table.remove(log, 1)
    end
    AntiSocial.session.stats.whispersFiltered = (AntiSocial.session.stats.whispersFiltered or 0) + 1
end

function AS.WhisperFilter:ClearLog()
    -- Clear ONLY the log entries. Do NOT touch whisperFilterNoticeSent;
    -- that table is what prevents reload replays from re-logging the same
    -- whispers we already saw (see logFiltered below).

    local profile = AntiSocial.db.profile

    if profile.whisperFilterLog then wipe(profile.whisperFilterLog) end
    profile.whisperFilterLog = {}

    -- Reset session counter to match the visible log
    AntiSocial.session.stats.whispersFiltered = 0

    -- Belt-and-suspenders: also clear at the raw SavedVariables level
    if _G.AntiSocialDB and _G.AntiSocialDB.profiles then
        local currentProfileKey = AntiSocial.db:GetCurrentProfile()
        local persisted = _G.AntiSocialDB.profiles[currentProfileKey]
        if persisted then
            persisted.whisperFilterLog = {}
            -- Intentionally do not touch persisted.whisperFilterNoticeSent
        end
    end

    debugLog("ClearLog: in-memory entries =", #profile.whisperFilterLog)
end

function AS.WhisperFilter:GetLog()
    return logDB()
end

-- ---------------------------------------------------------------------------
-- Rejection notice (matches BadBoy_Levels pattern)
-- ---------------------------------------------------------------------------
-- Sends a single fixed-text notice back to the sender. Throttled per-sender
-- to prevent spam, never reactive to message content, never repeated within
-- the cooldown window. The outgoing whisper is also filtered from chat so
-- the user doesn't see their own auto-reply.
local function sendRejectionNotice(sender)
    local c = cfg()
    if not c or not c.sendRejectionNotice then return end
    if not sender or sender == "" then return end
    if not C_ChatInfo or not C_ChatInfo.SendChatMessage then return end

    -- Don't fire notices during the login grace period. The server delivers
    -- queued offline whispers in the first few seconds after login, and we
    -- don't want to auto-reply to those (they're old by definition; if the
    -- player is still online they may be confused by a delayed bounce).
    -- The whispers are still filtered out of our chat, just no notice sent.
    if AntiSocial.session.loginTime then
        local sinceLogin = GetTime() - AntiSocial.session.loginTime
        if sinceLogin < 10 then
            debugLog(sender, "rejection notice skipped (login grace,", sinceLogin, "s)")
            return
        end
    end

    -- Persistent throttle: stored in DB so a /reload doesn't reset it.
    local sentTimes = AntiSocial.db.profile.whisperFilterNoticeSent
    if not sentTimes then
        AntiSocial.db.profile.whisperFilterNoticeSent = {}
        sentTimes = AntiSocial.db.profile.whisperFilterNoticeSent
    end

    local now = time()
    local lastSent = sentTimes[sender]
    if lastSent and (now - lastSent) < REPLY_COOLDOWN_SECONDS then
        debugLog(sender, "rejection notice throttled (sent",
            (now - lastSent), "s ago)")
        return
    end

    -- Clean up stale entries while we're here (older than 1 hour). This
    -- window also acts as the reload-replay protection in logFiltered, so
    -- we keep it longer than the per-sender notice cooldown.
    local staleCutoff = now - 3600
    for k, t in pairs(sentTimes) do
        if t < staleCutoff then sentTimes[k] = nil end
    end

    sentTimes[sender] = now

    local ownName = UnitName("player") or "the player"
    local text = REJECT_NOTICE_TEMPLATE:format(ownName)

    debugLog(sender, "sending rejection notice:", text)
    C_ChatInfo.SendChatMessage(text, "WHISPER", nil, sender)
end

-- ---------------------------------------------------------------------------
-- Pending queue (for deferred level-checked whispers)
-- ---------------------------------------------------------------------------
local pending = {}

local function showHeldMessage(entry)
    if entry.shown then return end
    entry.shown = true
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        local prefix = (entry.level and entry.level > 0)
            and (("|cffaaaaaa[L%d]|r "):format(entry.level)) or ""
        frame:AddMessage(("|Hplayer:%s|h[%s]|h |cffa9d2ff%swhispers:|r %s"):format(
            entry.sender, entry.sender, prefix, entry.message),
            1.0, 0.5, 1.0)
    end
end

local function evaluateAndHandle(entry)
    if entry.handled then return end
    local level = tryGetLevelImmediate(entry.sender)
    if level then entry.level = level end
    local verdict = shouldFilter(entry.sender, entry.level)
    if verdict == true then
        entry.handled = true
        logFiltered(entry.sender, entry.level, entry.message, "whisper")
        local c = cfg()
        if c then sendRejectionNotice(entry.sender) end
    elseif verdict == false then
        entry.handled = true
        showHeldMessage(entry)
    end
end

local function timeoutPending(senderName)
    local entry = pending[senderName]
    if not entry or entry.handled then
        pending[senderName] = nil
        return
    end
    -- Fail open: show the message
    entry.handled = true
    debugLog(senderName, "level check timed out, showing message")
    showHeldMessage(entry)
    pending[senderName] = nil
end

-- ---------------------------------------------------------------------------
-- Chat filters
-- ---------------------------------------------------------------------------
-- The CHAT_MSG_WHISPER event fires once per registered chat frame (often
-- 2-4 frames on a typical setup). Each invocation hits our filter, so we
-- need to deduplicate to avoid double-logging and double-notifying.
--
-- We dedup using sender+message hashing over a short time window. If the
-- same sender sends the same message within 500ms, the second call is a
-- duplicate frame invocation, not a genuinely repeated message. The
-- verdict is cached so all frames suppress consistently.
local seenVerdicts = {}  -- key -> { suppress = bool, t = time }

local function dedupKey(sender, message)
    return (sender or "?") .. "\0" .. (message or "")
end

local function getCachedVerdict(sender, message)
    local key = dedupKey(sender, message)
    local entry = seenVerdicts[key]
    if not entry then return nil end
    if (GetTime() - entry.t) > 0.5 then
        seenVerdicts[key] = nil
        return nil
    end
    return entry.suppress
end

local function setCachedVerdict(sender, message, suppress)
    seenVerdicts[dedupKey(sender, message)] = { suppress = suppress, t = GetTime() }
end

local function cleanupSeenVerdicts()
    if math.random() > 0.05 then return end
    local cutoff = GetTime() - 2.0
    for k, entry in pairs(seenVerdicts) do
        if entry.t < cutoff then seenVerdicts[k] = nil end
    end
end

-- In-game whisper. We only care about the first 2 args; rest are ignored.
local function whisperFilter(_, _, message, sender, ...)
    -- Replay cached verdict for duplicate frame invocations
    local cached = getCachedVerdict(sender, message)
    if cached ~= nil then
        return cached
    end
    cleanupSeenVerdicts()

    debugLog("CHAT_MSG_WHISPER from", sender, "msg:", (message or ""):sub(1, 40))
    local c = cfg()
    if not c or not c.enabled then
        setCachedVerdict(sender, message, false)
        return false
    end

    local level = tryGetLevelImmediate(sender)
    local verdict = shouldFilter(sender, level)

    if verdict == true then
        logFiltered(sender, level, message, "whisper")
        sendRejectionNotice(sender)
        setCachedVerdict(sender, message, true)
        return true
    elseif verdict == false then
        setCachedVerdict(sender, message, false)
        return false
    end

    -- Defer for level check
    debugLog(sender, "level unknown, deferring up to " .. LEVEL_QUERY_TIMEOUT .. "s")
    local entry = {
        sender = sender, message = message, level = nil,
        handled = false, shown = false,
    }
    pending[sender] = entry

    if NotifyInspect and UnitExists("target") and UnitName("target") == sender then
        NotifyInspect("target")
    end

    AntiSocial:ScheduleTimer(function()
        local e = pending[sender]
        if e and not e.handled then evaluateAndHandle(e) end
    end, 0.5)
    AntiSocial:ScheduleTimer(function()
        local e = pending[sender]
        if e and not e.handled then evaluateAndHandle(e) end
    end, 1.2)
    AntiSocial:ScheduleTimer(function() timeoutPending(sender) end, LEVEL_QUERY_TIMEOUT)

    setCachedVerdict(sender, message, true)
    return true
end

-- Battle.net whisper. No level context available, but we still apply
-- whitelists and the "block all" rule. BN friends should normally be on
-- the BNet friend whitelist (default), so this is mostly belt-and-suspenders.
local function bnWhisperFilter(_, _, message, sender, ...)
    debugLog("CHAT_MSG_BN_WHISPER from", sender, "msg:", message:sub(1, 40))
    local c = cfg()
    if not c or not c.enabled then return false end

    -- BN sender is a presenceID or BNet name, not a character name. We
    -- conservatively allow through unless block-all is on.
    if c.mode == "blockAll" then
        if c.allowBNetFriends then
            debugLog(sender, "allowed (BNet whitelist)")
            return false
        end
        logFiltered(sender, 0, message, "bn_whisper")
        debugLog(sender, "FILTERED BN (block all)")
        -- Note: we cannot SendChatMessage back over BN reliably; the BNet
        -- whisper system uses a different API. Skip the rejection notice
        -- for BN whispers to be safe.
        return true
    end
    return false
end

-- Filter our own outgoing rejection notices out of chat so the user doesn't
-- see "To Foobar: [AntiSocial]: Frost has blocked you..." every time. Matches
-- BadBoy's CHAT_MSG_WHISPER_INFORM filter approach.
local function whisperInformFilter(_, _, message, ...)
    if not message then return false end
    if message:find("^%[AntiSocial%]: ") then
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
function AS.WhisperFilter:Register()
    if self._registered then return end
    if not ChatFrame_AddMessageEventFilter then
        if AntiSocial then AntiSocial:Print("ERROR: ChatFrame_AddMessageEventFilter unavailable, filter cannot register") end
        return
    end
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", whisperFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", bnWhisperFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", whisperInformFilter)
    debugLog("registered whisper filters")
    self._registered = true
end

function AS.WhisperFilter:Unregister()
    if not self._registered then return end
    ChatFrame_RemoveMessageEventFilter("CHAT_MSG_WHISPER", whisperFilter)
    ChatFrame_RemoveMessageEventFilter("CHAT_MSG_BN_WHISPER", bnWhisperFilter)
    ChatFrame_RemoveMessageEventFilter("CHAT_MSG_WHISPER_INFORM", whisperInformFilter)
    self._registered = false
end

-- Diagnostic command, called by /as filter test
function AS.WhisperFilter:Diagnose()
    local c = cfg()
    AntiSocial:Print("=== whisper filter diagnosis ===")
    AntiSocial:Print(("registered: %s"):format(tostring(self._registered)))
    AntiSocial:Print(("enabled: %s"):format(tostring(c and c.enabled)))
    AntiSocial:Print(("mode: %s"):format(tostring(c and c.mode)))
    AntiSocial:Print(("threshold: %s"):format(tostring(c and c.levelThreshold)))
    AntiSocial:Print(("in-memory log entries: %d"):format(#logDB()))
    AntiSocial:Print(("session filtered: %d"):format(
        AntiSocial.session.stats.whispersFiltered or 0))

    -- Walk the raw SavedVariables to find where log entries actually live.
    -- AceDB stores under different keys depending on profile config; we
    -- check the common ones.
    AntiSocial:Print("--- SavedVariables walk ---")
    if not _G.AntiSocialDB then
        AntiSocial:Print("AntiSocialDB global: nil")
        return
    end
    AntiSocial:Print("AntiSocialDB.profiles keys:")
    if _G.AntiSocialDB.profiles then
        for k, v in pairs(_G.AntiSocialDB.profiles) do
            local n = (type(v) == "table" and v.whisperFilterLog
                and type(v.whisperFilterLog) == "table") and #v.whisperFilterLog or 0
            AntiSocial:Print(("  [%s] -> whisperFilterLog: %d entries"):format(tostring(k), n))
        end
    else
        AntiSocial:Print("  (no profiles table)")
    end
    AntiSocial:Print(("current profile: %s"):format(
        AntiSocial.db and AntiSocial.db:GetCurrentProfile() or "?"))
    -- Also check other locations AceDB might store data
    for _, key in ipairs({"profileKeys", "char", "realm", "factionrealm", "global"}) do
        if _G.AntiSocialDB[key] then
            AntiSocial:Print(("AntiSocialDB.%s exists"):format(key))
        end
    end
end
