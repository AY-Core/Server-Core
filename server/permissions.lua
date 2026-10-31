-- Level of a group (unknown groups count as 0).
function AY.GetGroupLevel(group)
    return ServerConfig.Groups[group] or 0
end

local warnedGroups = {}

-- True if the player's group level is >= the required group's level. The console (source 0) always passes.
-- Fail-closed: if the REQUIRED group does not exist in ServerConfig.Groups (typo in a config file),
-- nobody passes - a typo must never open a command to everyone.
function AY.HasPermission(src, requiredGroup)
    if src == 0 then return true end

    local required = ServerConfig.Groups[requiredGroup]
    if required == nil then
        if not warnedGroups[tostring(requiredGroup)] then
            warnedGroups[tostring(requiredGroup)] = true
            AY.Logger.Warn('permissions', ('Unknown required group "%s" - denying access. Check ServerConfig.Groups and your config.'):format(tostring(requiredGroup)))
        end
        return false
    end

    local player = AY.GetPlayer(src)
    if not player then return false end
    return (ServerConfig.Groups[player.GetGroup()] or 0) >= required
end

-- True if `src` outranks the target player (used so a moderator cannot ban/kick an admin).
-- The console outranks everyone.
function AY.CanTarget(src, targetPlayer)
    if src == 0 then return true end
    local actor = AY.GetPlayer(src)
    if not actor or not targetPlayer then return false end
    local actorLevel = ServerConfig.Groups[actor.GetGroup()] or 0
    local targetLevel = ServerConfig.Groups[targetPlayer.GetGroup()] or 0
    return actorLevel > targetLevel
end
