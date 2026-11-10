local icons = {}
local loaded, kept, retry = {}, {}, {}
-- A status icon's bitmap owns up to 0x156A bytes.
local client = require('ui.client_bitmap').loader(0x156A)
local resolved, test_loader = {}, nil
local artwork_kinds = { ['Original FFXI'] = 'original', ['XI View'] = 'xiview' }

function icons.prepare()
    client.prepare()
    require('ui.client_assets').prepare_icons()
end

-- The stock status icon pack as one warmup step; XI View's is in appearance's steps.
function icons.warmup_steps()
    local assets = require('ui.client_assets')
    return { assets.step('icons.pack', assets.icons_prepared, icons.prepare) }
end

local function load(id)
    if test_loader then return test_loader(id) end
    if not client.prepare() or not AshitaCore then return false end
    return client.load(AshitaCore:GetResourceManager():GetStatusIconByIndex(id))
end

-- The client's own image for id, made the first time it is drawn within this Present's budget of new icon textures
-- (client_assets.spend_upload). While that is spent, nil and true: it is made in a later Present.
local function client_status(id)
    if type(loaded[id]) == 'number' then return loaded[id] end
    local now = os.clock()
    if loaded[id] == nil or loaded[id] == false and now >= (retry[id] or 0) then
        if not require('ui.client_assets').spend_upload() then return nil, true end
        local ok, value, release = pcall(load, id)
        local valid = ok and type(value) == 'number' and value > 0 and value == value and value ~= math.huge
        loaded[id] = valid and value or false
        if type(release) == 'function' then
            if valid then kept[#kept + 1] = release else pcall(release) end
        end
        retry[id] = not loaded[id] and now + 30 or nil
    end
    return loaded[id] or nil
end

local function artwork_name(artwork)
    return artwork_kinds[artwork] and artwork or 'Client'
end

-- An icon whose texture waits for a later Present (client_assets' upload budget) gives nil until it is made, never
-- another artwork's image in the meantime.
function icons.status(id, artwork)
    if type(id) ~= 'number' or id ~= id or id < 0 or id > 1023 or id ~= math.floor(id) then return nil end
    artwork = artwork_name(artwork)
    if artwork == 'Client' then return (client_status(id)) end
    local assets = require('ui.client_assets')
    local image, reason, waiting = assets.icon_texture(artwork_kinds[artwork], id)
    local using = artwork
    if not image and not waiting and artwork == 'XI View' then
        local _
        image, _, waiting = assets.icon_texture('original', id)
        using = 'Original FFXI'
    end
    if waiting then return nil end
    local texture = image and image.id
    if not texture then
        texture, waiting = client_status(id)
        if waiting then return nil end
        using = 'Client'
    end
    resolved[artwork] = resolved[artwork] or {}
    local status = resolved[artwork][id] or {}
    resolved[artwork][id] = status
    status.using, status.reason = texture and using or nil, reason
    return texture
end

-- icons.status for a party icon drawn size px square, and the corner of the texture to draw (UV1). Original FFXI and
-- XI View art made at that size once client_assets has made it; otherwise icons.status's texture, whole.
local whole = { 1, 1 }
function icons.status_at(id, artwork, size)
    local texture = icons.status(id, artwork)
    local name = artwork_name(artwork)
    local status = texture and name ~= 'Client' and resolved[name] and resolved[name][id]
    local kind = status and artwork_kinds[status.using]
    if kind then
        local image, corner = require('ui.client_assets').icon_texture_at(kind, id, size)
        if image then return image.id, corner end
    end
    return texture, whole
end

-- These lookups go by prepared data and previous upload results. The only file read is XI View's icons, when nothing
-- has asked for them yet. out, when given, is emptied and filled in place of a new table.
local NONE = {}
function icons.artwork_status(artwork, id, out)
    artwork = artwork_name(artwork)
    if artwork == 'Client' then
        if out then require('table.clear')(out) else out = {} end
        out.available, out.using = id == nil or loaded[id] ~= false, artwork
        out.reason = id ~= nil and loaded[id] == false and 'The client status image is unavailable.' or nil
        return out
    end
    local assets = require('ui.client_assets')
    local status = assets.icon_status(artwork_kinds[artwork], id, out)
    local previous = id ~= nil and resolved[artwork] and resolved[artwork][id]
    if previous then status.using, status.reason = previous.using, previous.reason or status.reason
    elseif status.available then status.using = artwork
    else status.using = artwork == 'XI View' and assets.icon_status('original', id).available and 'Original FFXI' or 'Client' end
    if status.reason then
        status.reason = status.reason .. (status.using and status.using ~= artwork
            and ' Falling back to ' .. status.using .. ' artwork where available.' or '')
    end
    if id == nil and status.available then
        local count, first_id, first = 0
        for observed_id, observed in pairs(resolved[artwork] or NONE) do
            if observed.reason and observed.using ~= artwork then
                count = count + 1
                if not first_id or observed_id < first_id then first_id, first = observed_id, observed end
            end
        end
        status.fallbacks = count
        if first then
            local detail = ('Some effects use other artwork. %s %s'):format(first.reason,
                first.using and 'Using ' .. first.using .. ' artwork.' or 'No image is available.')
            status.reason = status.reason and status.reason .. ' ' .. detail or detail
        end
    end
    return status
end

-- More look and the party list buffs' note ask each frame, so the answer goes through one table.
local reason_status = {}
function icons.reason(artwork, id)
    return icons.artwork_status(artwork, id, reason_status).reason
end

function icons.clear()
    for _, release in ipairs(kept) do pcall(release) end
    loaded, kept, retry = {}, {}, {}
    client.reset()
    resolved = {}
    require('ui.client_assets').clear_icons()
end

if VANTAGE_TEST_MODE then
    function icons._set_loader_for_tests(value) test_loader = value end
end

return icons
