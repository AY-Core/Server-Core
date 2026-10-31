-- Ban system.
--
-- * Bans live in the `ay_bans` table and are mirrored in memory, so checking a connecting player
--   costs no database query.
-- * A ban stores several identifiers (license, discord, ...). A player is blocked when ANY of the
--   stored identifiers matches (which kinds count: ServerConfig.Bans.MatchIdentifiers).
-- * IP addresses are never stored. Rank is enforced: you cannot ban someone of equal/higher rank.
-- * Nothing in here yields, so AY.Bans.* is safe to call from other resources.

AY.Bans = { loaded = false }

local active = {} -- [key]        = ban
local index = {}  -- [identifier] = { [key] = ban }
local keyCounter = 0

local MAX_DURATION = 3650 * 86400 -- 10 years

------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------
local function allowedKinds()
    local set = {}
    for _, kind in ipairs(ServerConfig.Bans.MatchIdentifiers) do set[kind] = true end
    return set
end

-- 'kind:value' strings of a connected player, limited to the kinds used for matching.
local function playerMatchers(src)
    local kinds = allowedKinds()
    local list = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        local kind = id and id:match('^(%w+):')
        if kind and kinds[kind] then list[#list + 1] = id end
    end
    return list
end

local function isExpired(ban)
    return ban.expiresAt ~= nil and ban.expiresAt <= os.time()
end

local function addToCache(ban)
    keyCounter = keyCounter + 1
    ban.key = keyCounter
    active[ban.key] = ban
    for _, identifier in ipairs(ban.identifiers) do
        index[identifier] = index[identifier] or {}
        index[identifier][ban.key] = ban
    end
end

local function removeFromCache(ban)
    active[ban.key] = nil
    for _, identifier in ipairs(ban.identifiers) do
        local set = index[identifier]
        if set then
            set[ban.key] = nil
            if next(set) == nil then index[identifier] = nil end
        end
    end
end

local function formatMessage(ban)
    local expires = ban.expiresAt and os.date('!%Y-%m-%d %H:%M UTC', ban.expiresAt) or 'Never'
    return (ServerConfig.Bans.Message:gsub('{(%w+)}', {
        reason = ban.reason,
        id = tostring(ban.id or '?'),
        expires = expires,
    }))
end

-- Safe text for a reason: no control characters, no console colour codes, length limited.
function AY.Bans.CleanReason(text)
    local cfg = ServerConfig.Bans
    text = AY.Utils.Trim(text or ''):gsub('%c', ' '):gsub('%^%d', '')
    text = AY.Utils.Trim(text)
    if text == '' then text = cfg.DefaultReason end
    return text:sub(1, cfg.MaxReasonLength)
end

-- '30m', '12h', '7d', '2w'  ->  seconds.   'perm' / 'permanent' / '0'  ->  0.   Invalid  ->  nil.
function AY.Bans.ParseDuration(text)
    text = tostring(text or ''):lower()
    if text == 'perm' or text == 'permanent' or text == '0' then return 0 end

    local amount, unit = text:match('^(%d+)([mhdw])$')
    amount = tonumber(amount)
    if not amount or amount <= 0 then return nil end

    local seconds = amount * ({ m = 60, h = 3600, d = 86400, w = 604800 })[unit]
    if seconds > MAX_DURATION then return nil end
    return seconds
end

------------------------------------------------------------------------------
-- public API
------------------------------------------------------------------------------

-- Returns ban, kickMessage  if the connecting player is banned, otherwise nothing.
function AY.Bans.Check(src)
    for _, identifier in ipairs(playerMatchers(src)) do
        local set = index[identifier]
        if set then
            for _, ban in pairs(set) do
                if isExpired(ban) then
                    removeFromCache(ban)
                else
                    return ban, formatMessage(ban)
                end
            end
        end
    end
end

-- Ban an online player (number = server id) or a license (string 'license:xxxx', online or offline).
--   opts = { reason = '...', duration = seconds (nil/0 = permanent), by = 'name', source = actorSrc }
--   `source` enables the rank check (omit it, or use 0, for the console / system).
--   cb(ok, banOrError) is called when done.
function AY.Bans.Ban(target, opts, cb)
    opts = opts or {}
    cb = cb or function() end

    local actorSrc = tonumber(opts.source)
    local isStaffActor = actorSrc ~= nil and actorSrc ~= 0
    local reason = AY.Bans.CleanReason(opts.reason)
    local duration = tonumber(opts.duration)
    local expiresAt = (duration and duration > 0) and (os.time() + math.min(duration, MAX_DURATION)) or nil
    local bannedBy = tostring(opts.by or (isStaffActor and GetPlayerName(actorSrc)) or 'console'):sub(1, 100)

    local function finish(name, identifiers, targetGroup, targetSrc)
        if #identifiers == 0 then return cb(false, 'No usable identifiers found for this player.') end

        if isStaffActor then
            local actor = AY.GetPlayer(actorSrc)
            local actorLevel = actor and (ServerConfig.Groups[actor.GetGroup()] or 0) or -1
            if actorLevel <= (ServerConfig.Groups[targetGroup] or 0) then
                return cb(false, 'You cannot ban a player of equal or higher rank.')
            end
        end

        local ban = { name = name, identifiers = identifiers, reason = reason, bannedBy = bannedBy, expiresAt = expiresAt }
        addToCache(ban) -- effective immediately, even before the database answers

        -- 0 (not NULL) means "never expires": nil values are unreliable in query parameter lists.
        MySQL.insert(
            'INSERT INTO ay_bans (identifiers, name, reason, banned_by, expires_at) VALUES (?, ?, ?, ?, ?)',
            { json.encode(identifiers), name, reason, bannedBy, expiresAt or 0 },
            function(id)
                ban.id = id
                if not id then
                    AY.Logger.Error('bans', ('Could not save the ban of %s to the database (it is active until restart).'):format(name))
                end
                if targetSrc and GetPlayerName(targetSrc) then DropPlayer(targetSrc, formatMessage(ban)) end

                AY.Logger.Info('bans', ('%s banned %s (ban #%s, %s): %s'):format(
                    bannedBy, name ~= '' and name or identifiers[1], tostring(id or '?'),
                    expiresAt and ('until ' .. os.date('!%Y-%m-%d %H:%M UTC', expiresAt)) or 'permanent', reason))
                pcall(cb, true, ban)
            end
        )
    end

    if type(target) == 'number' then
        local name = GetPlayerName(target)
        if not name then return cb(false, 'Player not found.') end
        local player = AY.GetPlayer(target)
        return finish(name, playerMatchers(target), player and player.GetGroup() or ServerConfig.Players.DefaultGroup, target)
    end

    if type(target) == 'string' then
        if #target > 100 or not target:match('^license:[%w_%-%.]+$') then
            return cb(false, 'Offline bans need a license: license:xxxxxxxx')
        end

        local online = AY.GetPlayerByLicense(target)
        if online then return AY.Bans.Ban(online.GetSource(), opts, cb) end

        MySQL.single('SELECT name, group_name, identifiers FROM ay_players WHERE license = ?', { target }, function(row)
            local kinds = allowedKinds()
            local identifiers, name, group = { target }, '', ServerConfig.Players.DefaultGroup
            if row then
                name, group = row.name or '', row.group_name or group
                for kind, value in pairs(json.decode(row.identifiers or '{}') or {}) do
                    local identifier = kind .. ':' .. value
                    if kinds[kind] and identifier ~= target then identifiers[#identifiers + 1] = identifier end
                end
            end
            finish(name, identifiers, group)
        end)
        return
    end

    cb(false, 'Invalid target.')
end

-- Remove bans by ban id (number) or by identifier (string). Returns how many were lifted.
function AY.Bans.Unban(ref, by)
    local found = {}
    if type(ref) == 'number' then
        for _, ban in pairs(active) do
            if ban.id == ref then found[#found + 1] = ban end
        end
    elseif type(ref) == 'string' and index[ref] then
        for _, ban in pairs(index[ref]) do found[#found + 1] = ban end
    end

    for _, ban in ipairs(found) do
        removeFromCache(ban)
        if ban.id then
            MySQL.update('UPDATE ay_bans SET active = 0, unbanned_by = ? WHERE id = ?', { tostring(by or 'console'):sub(1, 100), ban.id })
        end
        AY.Logger.Info('bans', ('%s lifted ban #%s (%s)'):format(tostring(by or 'console'), tostring(ban.id or '?'), ban.name ~= '' and ban.name or ban.identifiers[1]))
    end
    return #found
end

-- Active bans, newest first.
function AY.Bans.List()
    local list = {}
    for _, ban in pairs(active) do
        if not isExpired(ban) then list[#list + 1] = AY.Utils.DeepCopy(ban) end
    end
    table.sort(list, function(a, b) return (a.id or math.huge) > (b.id or math.huge) end)
    return list
end

------------------------------------------------------------------------------
-- load active bans once the database (and migration 002_bans) is ready
------------------------------------------------------------------------------
CreateThread(function()
    while not AY.DB.ready do Wait(100) end

    local ok, err = pcall(function()
        local rows = MySQL.query.await(
            'SELECT id, name, identifiers, reason, banned_by, expires_at FROM ay_bans WHERE active = 1 AND (expires_at = 0 OR expires_at > ?)',
            { os.time() }
        ) or {}

        for _, row in ipairs(rows) do
            addToCache({
                id = row.id,
                name = row.name or '',
                identifiers = json.decode(row.identifiers or '[]') or {},
                reason = row.reason,
                bannedBy = row.banned_by,
                expiresAt = (tonumber(row.expires_at) or 0) > 0 and tonumber(row.expires_at) or nil,
            })
        end
        AY.Logger.Info('bans', ('Loaded %d active ban(s).'):format(#rows))
    end)

    if not ok then
        -- Stay closed: while the ban list is unavailable nobody is let in (see playerConnecting).
        AY.Logger.Error('bans', ('Could not load bans: %s'):format(tostring(err)))
        return
    end
    AY.Bans.loaded = true
end)
