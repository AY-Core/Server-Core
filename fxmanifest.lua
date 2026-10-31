fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'AY-Core'
author 'Amirali Yavari'
description 'AY-Core - a structured, scalable and secure core framework for FiveM.'
version '0.3.0'

dependency 'oxmysql'

-- Satellite resources load this with: shared_script '@AY-Core/import.lua'
files {
    'import.lua',
}

shared_scripts {
    'config/shared.lua',
    'shared/utils.lua',
    'import.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua', -- server only: never sent to clients
    'server/logger.lua',
    'server/database.lua',
    'server/security.lua',
    'server/hooks.lua',
    'server/modules.lua',
    'server/player.lua',
    'server/permissions.lua',
    'server/bans.lua',
    'server/notify.lua',
    'server/commands.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/notify.lua',
    'client/spawn.lua',
    'client/vehicles.lua',
    'client/health.lua',
    'client/admin.lua',
}
