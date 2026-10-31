-- Server-only config: this file is NOT listed in client_scripts, so clients never receive it.
ServerConfig = {}

ServerConfig.Database = {
    AutoCreateTables = true, -- creates ay_players / ay_logs on start (see sql/install.sql)
}

ServerConfig.Players = {
    DefaultGroup = 'user',
    AutosaveMinutes = 5,    -- 0 disables autosave
    DefaultMetadata = {},   -- merged into every player's metadata on load
}

-- Higher number = more permissions.
ServerConfig.Groups = {
    user = 0,
    helper = 1,
    moderator = 2,
    admin = 3,
    superadmin = 4,
}

ServerConfig.Security = {
    -- Default per-player, per-event limit for events registered via AY.RegisterServerEvent.
    RateLimit = { Window = 1000, Max = 30 },
}

ServerConfig.Logging = {
    Level = 'info',              -- debug | info | warn | error (console)
    LogConnections = true,       -- print join / leave messages in the server console
    Database = false,            -- also write logs to the ay_logs table
    DatabaseMinLevel = 'warn',
    -- Set in server.cfg:  set ay_log_webhook "https://discord.com/api/webhooks/..."
    DiscordWebhook = GetConvar('ay_log_webhook', ''),
    DiscordMinLevel = 'error',
}

ServerConfig.Vehicles = {
    SpawnGroup = 'admin',          -- minimum group for /car
    DeleteGroup = 'admin',         -- minimum group for /dv
    DeleteCurrentOnSpawn = true,   -- /car removes the vehicle you are already driving
    DefaultDeleteRadius = 5.0,     -- /dv with no argument
    MaxDeleteRadius = 25.0,        -- upper limit for /dv [radius]
}

ServerConfig.Health = {
    ReviveGroup = 'admin', -- minimum group for /revive
    KillGroup = 'admin',   -- minimum group for /kill
}

ServerConfig.Bans = {
    BanGroup = 'admin',       -- minimum group for /ban, /unban, /bans
    KickGroup = 'moderator',  -- minimum group for /kick
    -- A connecting player is blocked if ANY of these identifier kinds matches a stored ban.
    -- IP addresses are never stored or matched.
    MatchIdentifiers = { 'license', 'license2', 'steam', 'discord', 'fivem', 'xbl', 'live' },
    DefaultReason = 'No reason given.',
    MaxReasonLength = 200,
    -- Shown to the banned player. Placeholders: {reason} {id} {expires}
    Message = 'You are banned from this server.\nReason: {reason}\nBan ID: {id}\nExpires: {expires}',
}

ServerConfig.Admin = {
    TeleportGroup = 'admin', -- minimum group for /tp, /goto, /bring
}
