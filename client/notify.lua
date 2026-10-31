-- AY.Notify(message, kind)   kind: 'info' (default) | 'success' | 'warning' | 'error'
-- Server side equivalent: AY.Notify(src, message, kind)
local COLORS = {
    info = '~b~',
    success = '~g~',
    warning = '~y~',
    error = '~r~',
}

function AY.Notify(message, kind)
    message = tostring(message or ''):sub(1, 250)
    if message == '' then return end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName((COLORS[kind] or COLORS.info) .. message)
    EndTextCommandThefeedPostTicker(false, true)
end

RegisterNetEvent('ay-core:client:notify', function(message, kind)
    AY.Notify(message, kind)
end)
