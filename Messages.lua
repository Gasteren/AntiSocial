-- Messages.lua, message pools per mood profile per trigger, plus humanizer
-- that occasionally tweaks casing and punctuation. Backed by AceDB profile.
local _, AS = ...
AS.Messages = {}

-- Trigger key list, single source of truth
AS.Messages.triggerKeys = {
    "groupJoin",
    "keyTimed",
    "keyDepleted",
    "keyDefault",
    "groupLeave",
    "achievement",
    "levelUp",
    "readyCheck",
}

AS.Messages.triggerLabels = {
    groupJoin   = "Group join",
    keyTimed    = "Mythic+ timed",
    keyDepleted = "Mythic+ depleted",
    keyDefault  = "Mythic+ fallback",
    groupLeave  = "Group leave",
    achievement = "Achievement",
    levelUp     = "Level up",
    readyCheck  = "Ready check",
}

AS.Messages.profiles = {
    Introvert = {
        groupJoin = {
            "hi", "hey", "yo", "hi all", "sup", "ello", "o/", "hey all",
            "hi :)", "yo", "hello", "hey",
        },
        keyTimed = {
            "gg", "ggs", "nice", "gj", "well played", "wp", "gg all",
            "ggs all", "clean", "nice run",
        },
        keyDepleted = {
            "gg", "unlucky", "np", "ggs", "next one", "rip", "oh well",
            "ggs all", "tough one", "shame",
        },
        keyDefault = {
            "gg", "ggs", "gj",
        },
        groupLeave = {
            "ty", "thanks", "ty all", "tyfp", "ggs", "thanks all",
            "cheers", "ty for run",
        },
        achievement = {
            "gz", "grats", "nice", "gj", "well done", "gz!",
            "grats!", "nice one",
        },
        levelUp = {
            "gz", "grats", "nice", "gj", "well done",
            "grats!", "nice one",
        },
        readyCheck = { "r" },
    },

    Friendly = {
        groupJoin = {
            "hey all", "hi :)", "heya", "hello!", "hey", "yo",
            "hi everyone", "heya all", "hey :)", "hi guys", "o/",
            "hey hey", "hi all!", "hello there", "morning!",
        },
        keyTimed = {
            "gg!", "clean run", "nice key", "tyfp", "well played",
            "ggs!", "great run", "nice one", "smooth run", "well done",
            "good push", "nice work", "tyfp!", "ggs all", "clean :)",
        },
        keyDepleted = {
            "np, ggs", "unlucky :(", "ggs anyway", "tyfp", "no worries",
            "next one!", "ah well", "ggs guys", "tough one", "rip vault",
            "thats okay", "ggs ggs", "still ggs", "next time",
        },
        keyDefault = {
            "gg", "tyfp", "ggs", "nice", "well played",
        },
        groupLeave = {
            "ty for group!", "thanks all", "tyfp", "thanks, ggs",
            "cheers all!", "ty everyone", "appreciate it", "thanks guys",
            "ty :)", "ggs and ty", "cheers", "ty for run!",
        },
        achievement = {
            "gz!", "grats!", "nice!", "gz :)", "nicely done",
            "huge gz", "well done!", "grats :)", "thats awesome",
            "nice one!", "gj!", "lets goo", "yesss gz",
        },
        levelUp = {
            "gz!", "grats!", "nice!", "well done", "gz :)",
            "grats :)", "nice one!", "almost max!", "keep going",
            "gj!",
        },
        readyCheck = { "r", "ready", "r!", "ready!", "rdy" },
    },

    Goblin = {
        groupJoin = {
            "pumpers?", "lets time this", "free vault", "lfg", "lets go",
            "yo pumpers", "easy timer", "no wipes pls", "pump time",
            "lets cook", "send it", "we pumping?", "ez run incoming",
            "key on farm", "vault gamers",
        },
        keyTimed = {
            "ez clap", "free", "pumped", "nice pump", "ggs",
            "easy", "vault secured", "free loot", "pump",
            "ez timer", "smooth", "no thoughts only key",
            "huge pump", "called it", "ez",
        },
        keyDepleted = {
            "rip vault", "unlucky", "next one", "tank diff",
            "healer diff", "dps diff", "rng diff", "ggs ig",
            "next key better", "f", "rip", "back to weekly",
            "ah well",
        },
        keyDefault = {
            "gg", "ez", "ggs",
        },
        groupLeave = {
            "tyfp", "ggs", "thanks", "ty for the pump",
            "cheers pumpers", "ggs gamers", "ty",
        },
        achievement = {
            "gz", "nice", "pog", "huge", "lets goooo",
            "pog gz", "based", "absolute pump", "huge W",
            "W gz", "thats cracked",
        },
        levelUp = {
            "gz", "lets go", "nice", "pog", "W",
            "almost there", "send it", "based",
        },
        readyCheck = { "r" },
    },

    Raider = {
        groupJoin = {
            "hi", "hey", "yo", "hello", "hey all",
            "hi all", "o/", "hey team",
        },
        keyTimed = {
            "ggs", "clean", "gg", "wp", "good run",
            "tyfp", "ggs all", "nice work", "well played",
            "clean run",
        },
        keyDepleted = {
            "np", "ggs", "unlucky", "next one", "rip",
            "no worries", "ggs anyway", "tough",
        },
        keyDefault = {
            "gg", "ggs",
        },
        groupLeave = {
            "ty", "ggs", "tyfp", "thanks all", "cheers",
            "ty for run", "ggs all",
        },
        achievement = {
            "gz", "nice", "wp", "well done",
        },
        levelUp = {
            "gz", "nice", "almost max",
        },
        readyCheck = { "r", "ready" },
    },
}

AS.Messages.rareAchievement = {
    Introvert = { "gz", "nice one", "big one", "huge" },
    Friendly  = {
        "holy gz!", "huge gz!", "thats awesome, gz!", "massive gz",
        "wow nice, gz!", "thats a big one, gz", "huge!! gz",
    },
    Goblin    = {
        "BIG gz", "huge", "pog gz", "absolute cinema",
        "HOLY pog", "no way, gz", "huge W gz",
    },
    Raider    = { "gz", "huge", "nice one", "big one" },
}

-- ---------------------------------------------------------------------------
-- Humanizer
-- ---------------------------------------------------------------------------
local function humanize(text)
    if not text or text == "" then return text end
    if math.random() > 0.30 then return text end

    local mode = math.random(1, 4)
    if mode == 1 then
        text = text:gsub("[%.!%?]+$", "")
    elseif mode == 2 then
        text = text:lower()
    elseif mode == 3 then
        if not text:match("[%.!%?]$") and #text < 25 then
            text = text .. "!"
        end
    elseif mode == 4 then
        if text:sub(-1) == "s" and math.random() < 0.5 then
            text = text .. "s"
        end
    end
    return text
end

-- ---------------------------------------------------------------------------
-- DB accessor (AceDB profile)
-- ---------------------------------------------------------------------------
local function profileDB()
    return AntiSocial and AntiSocial.db and AntiSocial.db.profile
end

-- ---------------------------------------------------------------------------
-- Pool selection
-- ---------------------------------------------------------------------------
function AS.Messages:Pick(triggerKey, opts)
    opts = opts or {}
    local db = profileDB()
    if not db then return nil end
    local profileName = db.moodProfile or "Friendly"
    local pool

    if profileName == "Custom" then
        local custom = db.customPools and db.customPools[triggerKey]
        if custom and #custom > 0 then
            pool = custom
        else
            pool = self.profiles.Friendly[triggerKey]
        end
    elseif triggerKey == "achievement" and opts.rare then
        pool = self.rareAchievement[profileName] or self.rareAchievement.Friendly
    else
        local profile = self.profiles[profileName] or self.profiles.Friendly
        pool = profile[triggerKey]
    end

    if not pool or #pool == 0 then return nil end
    return humanize(pool[math.random(#pool)])
end

-- ---------------------------------------------------------------------------
-- Custom pool helpers (called by slash commands and CustomFrame)
-- ---------------------------------------------------------------------------
local function ensureCustom()
    local db = profileDB()
    if not db then return nil end
    db.customPools = db.customPools or {}
    return db.customPools
end

function AS.Messages:GetCustomPool(triggerKey)
    local pools = ensureCustom()
    if not pools then return {} end
    return pools[triggerKey] or {}
end

function AS.Messages:SetCustomPool(triggerKey, list)
    local pools = ensureCustom()
    if not pools then return end
    -- Mutate the existing pool table in place rather than replacing the
    -- reference, so AceDB persists the change correctly.
    if pools[triggerKey] then
        wipe(pools[triggerKey])
        if list then
            for i, v in ipairs(list) do pools[triggerKey][i] = v end
        end
    else
        pools[triggerKey] = list or {}
    end
end

function AS.Messages:AddCustom(triggerKey, message)
    local pools = ensureCustom()
    if not pools then return false, "DB not ready" end
    message = message and message:match("^%s*(.-)%s*$") or ""
    if message == "" then return false, "empty message" end
    if #message > 50 then return false, "message too long (50 char max)" end
    pools[triggerKey] = pools[triggerKey] or {}
    table.insert(pools[triggerKey], message)
    return true
end

function AS.Messages:RemoveCustom(triggerKey, index)
    local pools = ensureCustom()
    if not pools then return false, "DB not ready" end
    local list = pools[triggerKey]
    if not list or not list[index] then return false, "not found" end
    return true, table.remove(list, index)
end

function AS.Messages:ClearCustom(triggerKey)
    local pools = ensureCustom()
    if not pools then return end
    if triggerKey then
        if pools[triggerKey] then
            wipe(pools[triggerKey])
        else
            pools[triggerKey] = {}
        end
    else
        for k, list in pairs(pools) do
            if type(list) == "table" then wipe(list) else pools[k] = {} end
        end
    end
end

function AS.Messages:ParseList(str)
    local list = {}
    if not str or str == "" then return list end
    for part in str:gmatch("[^,\n]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(list, trimmed)
        end
    end
    return list
end

function AS.Messages:SerializeList(list)
    if not list or #list == 0 then return "" end
    return table.concat(list, ", ")
end
