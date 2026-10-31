-- AY.RegisterCommand itself lives in import.lua (shared with satellite resources).
function AY.Reply(src, message)
    if src == 0 then
        print(('[%s] %s'):format(AY.Name, message))
    else
        TriggerClientEvent('chat:addMessage', src, { args = { AY.Name, message } })
    end
end

-- /setgroup [id] [group]  - from the server console you can bootstrap your first admin.
AY.RegisterCommand('setgroup', 'superadmin', function(src, args)
    local target = tonumber(args[1])
    local group = args[2]
    local player = target and AY.GetPlayer(target)

    if not player then
        AY.Reply(src, 'Usage: setgroup [id] [group] (player must be online and loaded)')
        return
    end
    if not player.SetGroup(group) then
        AY.Reply(src, 'Invalid group.')
        return
    end

    local actor = src == 0 and 'console' or (GetPlayerName(src) or src)
    AY.Logger.Info('permissions', ('%s set the group of %s to "%s"'):format(actor, player.GetName(), group))
    AY.Reply(src, ('%s is now "%s".'):format(player.GetName(), group))
end)

-- Vehicle / health commands send no chat messages. Only the server console gets text output.
local function consoleReply(src, message)
    if src == 0 then AY.Reply(src, message) end
end

-- /car [model]  - spawns a vehicle and puts you in the driver seat.
AY.RegisterCommand('car', ServerConfig.Vehicles.SpawnGroup, function(src, args)
    if src == 0 then
        consoleReply(src, 'This command can only be used in-game.')
        return
    end
    if not AY.Security.CheckRate(src, 'cmd:car', { Window = 3000, Max = 3 }) then return end

    local model = args[1] and args[1]:lower()
    if not AY.Utils.IsNonEmptyString(model, 32) or not model:match('^[%w_]+$') then return end

    TriggerClientEvent('ay-core:client:spawnVehicle', src, model, ServerConfig.Vehicles.DeleteCurrentOnSpawn)
    AY.Logger.Info('vehicles', ('%s (id %s) spawned vehicle "%s"'):format(GetPlayerName(src) or 'unknown', src, model))
end)

-- /dv [radius]  - deletes the vehicle you are in, or the closest one within the radius.
AY.RegisterCommand('dv', ServerConfig.Vehicles.DeleteGroup, function(src, args)
    if src == 0 then
        consoleReply(src, 'This command can only be used in-game.')
        return
    end
    if not AY.Security.CheckRate(src, 'cmd:dv', { Window = 3000, Max = 5 }) then return end

    local cfg = ServerConfig.Vehicles
    local radius = tonumber(args[1]) or cfg.DefaultDeleteRadius
    radius = math.max(1.0, math.min(radius, cfg.MaxDeleteRadius))

    TriggerClientEvent('ay-core:client:deleteVehicle', src, radius + 0.0)
    AY.Logger.Info('vehicles', ('%s (id %s) used /dv (radius %.1f)'):format(GetPlayerName(src) or 'unknown', src, radius))
end)

-- Shared by /revive and /kill: [id] is optional in-game (defaults to yourself), required from the console.
local function healthCommand(name, event, verb)
    return function(src, args)
        if src ~= 0 and not AY.Security.CheckRate(src, 'cmd:' .. name, { Window = 3000, Max = 5 }) then return end

        local target = args[1] and tonumber(args[1]) or src
        if target == 0 or not AY.GetPlayer(target) then
            consoleReply(src, ('Usage: /%s [id]  (player must be online and loaded)'):format(name))
            return
        end

        TriggerClientEvent(event, target)

        local actor = src == 0 and 'console' or ('%s (id %s)'):format(GetPlayerName(src) or 'unknown', src)
        AY.Logger.Info('health', ('%s %s %s (id %s)'):format(actor, verb, GetPlayerName(target) or 'unknown', target))
    end
end

-- /revive [id]
AY.RegisterCommand('revive', ServerConfig.Health.ReviveGroup, healthCommand('revive', 'ay-core:client:revive', 'revived'))

-- /kill [id]
AY.RegisterCommand('kill', ServerConfig.Health.KillGroup, healthCommand('kill', 'ay-core:client:kill', 'killed'))
------------------------------------------------------------------------------
-- Moderation: /kick /ban /unban /bans
------------------------------------------------------------------------------
local function actorName(src)
    return src == 0 and 'console' or ('%s (id %s)'):format(GetPlayerName(src) or 'unknown', src)
end

-- /kick [id] [reason]
AY.RegisterCommand('kick', ServerConfig.Bans.KickGroup, function(src, args)
    local target = tonumber(args[1])
    if not target or not GetPlayerName(target) then
        AY.Reply(src, 'Usage: /kick [id] [reason]  (player must be online)')
        return
    end
    if target == src then
        AY.Reply(src, 'You cannot kick yourself.')
        return
    end

    local targetPlayer = AY.GetPlayer(target)
    if targetPlayer and not AY.CanTarget(src, targetPlayer) then
        AY.Reply(src, 'You cannot kick a player of equal or higher rank.')
        return
    end

    local reason = AY.Bans.CleanReason(table.concat(args, ' ', 2))
    local name = GetPlayerName(target)
    DropPlayer(target, ('You were kicked from the server.\nReason: %s'):format(reason))
    AY.Logger.Info('moderation', ('%s kicked %s (id %s): %s'):format(actorName(src), name, target, reason))
    AY.Reply(src, ('Kicked %s.'):format(name))
end)

-- /ban [id | license:xxxx] [duration] [reason]     duration: 30m, 12h, 7d, 2w, perm
AY.RegisterCommand('ban', ServerConfig.Bans.BanGroup, function(src, args)
    local duration = AY.Bans.ParseDuration(args[2])
    if not args[1] or duration == nil then
        AY.Reply(src, 'Usage: /ban [id | license:xxxx] [duration: 30m, 12h, 7d, 2w, perm] [reason]')
        return
    end

    local target = tonumber(args[1]) or args[1]
    if target == src then
        AY.Reply(src, 'You cannot ban yourself.')
        return
    end

    AY.Bans.Ban(target, {
        reason = table.concat(args, ' ', 3),
        duration = duration,
        source = src,
    }, function(ok, result)
        if ok then
            AY.Reply(src, ('Banned %s (ban #%s).'):format(result.name ~= '' and result.name or result.identifiers[1], tostring(result.id or '?')))
        else
            AY.Reply(src, tostring(result))
        end
    end)
end)

-- /unban [ban id | license:xxxx]
AY.RegisterCommand('unban', ServerConfig.Bans.BanGroup, function(src, args)
    local ref = tonumber(args[1]) or args[1]
    if not ref then
        AY.Reply(src, 'Usage: /unban [ban id | license:xxxx]')
        return
    end

    local count = AY.Bans.Unban(ref, actorName(src))
    AY.Reply(src, count > 0 and ('Lifted %d ban(s).'):format(count) or 'No active ban found.')
end)

-- /bans  - the 10 newest active bans
AY.RegisterCommand('bans', ServerConfig.Bans.BanGroup, function(src)
    local list = AY.Bans.List()
    if #list == 0 then
        AY.Reply(src, 'There are no active bans.')
        return
    end

    AY.Reply(src, ('%d active ban(s), showing the newest %d:'):format(#list, math.min(#list, 10)))
    for i = 1, math.min(#list, 10) do
        local ban = list[i]
        local expires = ban.expiresAt and os.date('!%Y-%m-%d %H:%M UTC', ban.expiresAt) or 'permanent'
        AY.Reply(src, ('#%s  %s  [%s]  %s'):format(tostring(ban.id or '?'), ban.name ~= '' and ban.name or ban.identifiers[1], expires, ban.reason))
    end
end)

------------------------------------------------------------------------------
-- Teleport: /tp /goto /bring   (server-side coordinates need OneSync)
------------------------------------------------------------------------------
local function isValidCoord(x, y, z)
    return type(x) == 'number' and type(y) == 'number' and type(z) == 'number'
        and x == x and y == y and z == z -- rejects NaN
        and math.abs(x) <= 10000.0 and math.abs(y) <= 10000.0 and z >= -500.0 and z <= 3000.0
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if not isValidCoord(coords.x, coords.y, coords.z) then return nil end
    return coords
end

-- /tp [x] [y] [z]
AY.RegisterCommand('tp', ServerConfig.Admin.TeleportGroup, function(src, args)
    if src == 0 then
        consoleReply(src, 'This command can only be used in-game.')
        return
    end
    if not AY.Security.CheckRate(src, 'cmd:tp', { Window = 3000, Max = 5 }) then return end

    local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not isValidCoord(x, y, z) then return end

    TriggerClientEvent('ay-core:client:teleport', src, x + 0.0, y + 0.0, z + 0.0)
    AY.Logger.Info('admin', ('%s used /tp to %.1f, %.1f, %.1f'):format(actorName(src), x, y, z))
end)

-- /goto [id]  - teleport to a player.   /bring [id]  - teleport a player to you.
local function playerTeleportCommand(name, bring)
    return function(src, args)
        if src == 0 then
            consoleReply(src, 'This command can only be used in-game.')
            return
        end
        if not AY.Security.CheckRate(src, 'cmd:' .. name, { Window = 3000, Max = 5 }) then return end

        local target = tonumber(args[1])
        if not target or target == src or not AY.GetPlayer(target) then return end

        -- Whoever moves, the destination is the other player's current position.
        local destination = pedCoords(bring and src or target)
        if not destination then return end

        local mover = bring and target or src
        TriggerClientEvent('ay-core:client:teleport', mover, destination.x + 1.0, destination.y, destination.z)
        AY.Logger.Info('admin', ('%s used /%s on %s (id %s)'):format(actorName(src), name, GetPlayerName(target) or 'unknown', target))
    end
end

AY.RegisterCommand('goto', ServerConfig.Admin.TeleportGroup, playerTeleportCommand('goto', false))
AY.RegisterCommand('bring', ServerConfig.Admin.TeleportGroup, playerTeleportCommand('bring', true))
