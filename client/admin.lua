-- Client side of /tp, /goto and /bring. The server checks permission, rate limit and the
-- coordinates, then tells the client where to go.

RegisterNetEvent('ay-core:client:teleport', function(x, y, z)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end

    local ped = PlayerPedId()

    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(x, y, z)
    SetPedCoordsKeepVehicle(ped, x, y, z) -- moves the vehicle along when the player is in one

    -- Wait for the ground to load so the player does not fall through the map.
    local deadline = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end

    FreezeEntityPosition(ped, false)
end)
