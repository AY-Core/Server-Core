-- AY.Notify(src, message, kind)   kind: 'info' (default) | 'success' | 'warning' | 'error'
-- Shows a native GTA notification on the player's screen. Safe to call from other resources.
function AY.Notify(src, message, kind)
    if type(message) ~= 'string' or message == '' then return false end
    if GetPlayerName(src) == nil then return false end
    TriggerClientEvent('ay-core:client:notify', src, message:sub(1, 250), type(kind) == 'string' and kind or 'info')
    return true
end
