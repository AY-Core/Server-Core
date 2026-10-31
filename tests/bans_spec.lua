-- Offline logic test for AY-Core bans + permissions. Runs the REAL server files against stubbed FiveM natives.
--   lua5.4 tests/bans_spec.lua      (run from the repository root)

local failures, passed = 0, 0
local function check(name, cond, extra)
    if cond then passed = passed + 1
    else failures = failures + 1; print(('FAIL: %s %s'):format(name, extra and ('(' .. tostring(extra) .. ')') or '')) end
end

------------------------------------------------------------------------------ stubs
local now = 1000000
local realTime = os.time
os.time = function() return now end

local jsonStore, jsonN = {}, 0
json = {
    encode = function(t) jsonN = jsonN + 1; jsonStore['J' .. jsonN] = t; return 'J' .. jsonN end,
    decode = function(s) return jsonStore[s] end,
}

function IsDuplicityVersion() return true end
function GetCurrentResourceName() return 'AY-Core' end
function GetResourceMetadata() return '0.0.0-test' end
function GetConvar(_, d) return d end
function PerformHttpRequest() end
function Wait() end
function CreateThread(fn) fn() end
function TriggerEvent() end
function TriggerClientEvent() end
function GetGameTimer() return 0 end
function vec4(...) return { ... } end

local connected = {} -- [src] = { name, ids = {...}, group }
function GetPlayerName(src) return connected[src] and connected[src].name end
function GetNumPlayerIdentifiers(src) return #connected[src].ids end
function GetPlayerIdentifier(src, i) return connected[src].ids[i + 1] end

local dropped = {}
function DropPlayer(src, msg) dropped[#dropped + 1] = { src = src, msg = msg }; connected[src] = nil end

local dbRows, inserts, updates = {}, {}, {}
local playerRow
MySQL = {
    insert = function(q, p, cb) inserts[#inserts + 1] = { q = q, p = p }; if cb then cb(#inserts) end end,
    update = function(q, p) updates[#updates + 1] = { q = q, p = p } end,
    single = function(q, p, cb) cb(playerRow) end,
    query = { await = function() return dbRows end },
}

print = function() end -- silence logger output
Config = {}

local function load(path) local chunk = assert(loadfile(path)); return chunk() end
load('config/shared.lua')
load('config/server.lua')
load('shared/utils.lua')
load('server/logger.lua')
AY.DB = { ready = true }
AY.Logger.Level = 'error'
ServerConfig.Logging.Level = 'error'

local loaded = {} -- loaded players: [src] = group
function AY.GetPlayer(src)
    if not loaded[src] then return nil end
    return { GetGroup = function() return loaded[src] end, GetSource = function() return src end }
end
function AY.GetPlayerByLicense(license)
    for src, p in pairs(connected) do
        if p.ids[1] == license and loaded[src] then return AY.GetPlayer(src) end
    end
end

load('server/permissions.lua')
dbRows = { { id = 7, name = 'Old', identifiers = nil, reason = 'x', banned_by = 'c', expires_at = 0 } }
load('server/bans.lua')

------------------------------------------------------------------------------ ParseDuration
local P = AY.Bans.ParseDuration
check('30m', P('30m') == 1800)
check('12h', P('12h') == 43200)
check('7d', P('7d') == 604800)
check('2w', P('2w') == 1209600)
check('perm', P('perm') == 0 and P('PERMANENT') == 0 and P('0') == 0)
check('invalid -> nil', P('abc') == nil and P('') == nil and P(nil) == nil and P('0m') == nil and P('-5d') == nil and P('5x') == nil)
check('too long -> nil', P('99999w') == nil)

------------------------------------------------------------------------------ CleanReason
local C = AY.Bans.CleanReason
check('empty -> default', C('') == ServerConfig.Bans.DefaultReason and C(nil) == ServerConfig.Bans.DefaultReason)
check('colour codes stripped', C('^1red ^2text') == 'red text')
check('control chars stripped', C('a\nb\tc') == 'a b c')
check('truncated', #C(('x'):rep(500)) == ServerConfig.Bans.MaxReasonLength)

------------------------------------------------------------------------------ loading from DB
check('loaded flag set', AY.Bans.loaded == true)
check('row loaded (bad identifiers tolerated)', #AY.Bans.List() == 1)
AY.Bans.Unban(7, 'test')

------------------------------------------------------------------------------ permissions
loaded[1] = 'admin'; connected[1] = { name = 'Admin', ids = { 'license:aaa' } }
check('known group passes', AY.HasPermission(1, 'admin') == true)
check('lower group fails', AY.HasPermission(1, 'superadmin') == false)
check('unknown required group is DENIED', AY.HasPermission(1, 'adimn') == false)
check('console always passes', AY.HasPermission(0, 'superadmin') == true)

------------------------------------------------------------------------------ banning an online player
connected[5] = { name = 'Cheater', ids = { 'license:bad1', 'discord:111', 'ip:1.2.3.4', 'steam:777' } }
loaded[5] = 'user'
local okBan, banObj
AY.Bans.Ban(5, { reason = 'cheating', duration = 3600, source = 0 }, function(ok, b) okBan, banObj = ok, b end)
check('ban ok', okBan == true)
check('ip never stored', not table.concat(banObj.identifiers, ','):find('ip:', 1, true))
check('3 identifiers stored', #banObj.identifiers == 3)
check('insert uses 0/NULL-safe params', inserts[1] and #inserts[1].p == 5 and inserts[1].p[5] == now + 3600)
check('player was dropped with message', dropped[1] and dropped[1].src == 5 and dropped[1].msg:find('cheating', 1, true) and dropped[1].msg:find('Ban ID: 1', 1, true))

connected[6] = { name = 'Alt', ids = { 'license:other', 'discord:111' } } -- same discord, new license
check('matched by shared discord', AY.Bans.Check(6) ~= nil)
connected[7] = { name = 'Innocent', ids = { 'license:clean', 'discord:999' } }
check('unrelated player passes', AY.Bans.Check(7) == nil)

now = now + 3601
check('expired ban no longer matches', AY.Bans.Check(6) == nil)
check('expired ban removed from cache', #AY.Bans.List() == 0)

------------------------------------------------------------------------------ permanent ban + unban
connected[8] = { name = 'Perm', ids = { 'license:perm1' } }; loaded[8] = 'user'
AY.Bans.Ban(8, { reason = 'rdm', duration = 0, source = 0 }, function(ok, b) banObj = b end)
check('permanent has no expiry', banObj.expiresAt == nil and inserts[2].p[5] == 0)
connected[9] = { name = 'PermAgain', ids = { 'license:perm1' } }
check('permanent ban matches', AY.Bans.Check(9) ~= nil)
check('unban by id', AY.Bans.Unban(banObj.id, 'admin') == 1)
check('unban hits database', updates[#updates] and updates[#updates].p[2] == banObj.id)
check('after unban player passes', AY.Bans.Check(9) == nil)
check('unban unknown -> 0', AY.Bans.Unban(9999) == 0)

------------------------------------------------------------------------------ rank enforcement
loaded[20] = 'moderator'; connected[20] = { name = 'Mod', ids = { 'license:mod' } }
loaded[21] = 'admin';     connected[21] = { name = 'Adm', ids = { 'license:adm' } }
loaded[22] = 'moderator'; connected[22] = { name = 'Mod2', ids = { 'license:mod2' } }
loaded[23] = 'user';      connected[23] = { name = 'Usr', ids = { 'license:usr' } }
local res
AY.Bans.Ban(21, { reason = 'x', duration = 60, source = 20 }, function(ok, e) res = { ok, e } end)
check('moderator cannot ban admin', res[1] == false and tostring(res[2]):find('rank'))
AY.Bans.Ban(22, { reason = 'x', duration = 60, source = 20 }, function(ok, e) res = { ok, e } end)
check('moderator cannot ban equal rank', res[1] == false)
AY.Bans.Ban(23, { reason = 'x', duration = 60, source = 20 }, function(ok, e) res = { ok, e } end)
check('moderator can ban user', res[1] == true)
AY.Bans.Ban(99, { reason = 'x', source = 0 }, function(ok, e) res = { ok, e } end)
check('unknown id -> error', res[1] == false)

------------------------------------------------------------------------------ offline bans
AY.Bans.Ban('discord:123', { reason = 'x' }, function(ok, e) res = { ok, e } end)
check('offline needs license', res[1] == false)
AY.Bans.Ban('license:x; DROP TABLE', { reason = 'x' }, function(ok, e) res = { ok, e } end)
check('malformed license rejected', res[1] == false)

jsonStore['ids1'] = { discord = '555', license = 'off1' }
playerRow = { name = 'Gone', group_name = 'user', identifiers = 'ids1' }
AY.Bans.Ban('license:off1', { reason = 'left', duration = 0, source = 21 }, function(ok, e) res = { ok, e } end)
check('offline ban ok', res[1] == true and res[2].name == 'Gone')
check('offline ban expands stored identifiers', #res[2].identifiers == 2)
connected[30] = { name = 'Back', ids = { 'license:new', 'discord:555' } }
check('offline-banned discord blocked on return', AY.Bans.Check(30) ~= nil)

playerRow = { name = 'BossGone', group_name = 'superadmin', identifiers = 'ids1' }
AY.Bans.Ban('license:boss', { reason = 'x', source = 21 }, function(ok, e) res = { ok, e } end)
check('admin cannot ban offline superadmin', res[1] == false)

check('unban by identifier', AY.Bans.Unban('license:off1', 'admin') == 1)

------------------------------------------------------------------------------
os.time = realTime
io.write(('%d passed, %d failed\n'):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
