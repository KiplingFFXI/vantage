local icons = {}
local loaded, kept, retry = {}, {}, {}
-- A status icon's bitmap owns up to 0x156A bytes.
local client = require('ui.client_bitmap').loader(0x156A)
local steady = require('core.steady')
local resolved, test_loader = {}, nil
local artwork_kinds = { ['Original FFXI'] = 'original', ['XI View'] = 'xiview' }
-- What a note calls Ashita's own picture when an icon falls back on it.
local FALLBACK = "Ashita's"
-- The client has no picture for an effect that only ever sits on a monster. The catalog gives each of those the item
-- that puts it there (data/catalog.lua item), and it draws with that item's picture, whatever the artwork.
local entries = require('data.catalog')
local items = require('ui.item_icons')
-- Icon sets you add (ui/icon_packs.lua): any other name a set can have names one, found or not.
local packs = require('ui.icon_packs')

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
    local now = steady()
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

-- Client isn't a choice any more, so a saved Client, like any name that isn't a choice or a set's, draws as Original
-- FFXI. Ashita's own picture is only what an icon falls back on (client_status).
local function artwork_name(artwork)
    if artwork_kinds[artwork] then return artwork end
    return packs.valid_name(artwork) and artwork or 'Original FFXI'
end

local function is_set(name) return not artwork_kinds[name] end

-- An icon whose texture waits for a later Present (client_assets' upload budget) gives nil until it is made, never
-- another artwork's image in the meantime. A set's picture comes first, and an effect it has none for draws as with
-- Original FFXI.
function icons.status(id, artwork)
    if type(id) ~= 'number' or id ~= id or id < 0 or id > 1023 or id ~= math.floor(id) then return nil end
    artwork = artwork_name(artwork)
    if is_set(artwork) then
        local texture, waiting = packs.texture(artwork, id)
        if texture or waiting then return texture end
        artwork = 'Original FFXI'
    end
    local entry = entries[id]
    if entry and entry.item then return items.texture(entry.item) end
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
        using = FALLBACK
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
    local name = artwork_name(artwork)
    -- A set's picture is made at that size from the picture itself, and drawn whole.
    if is_set(name) then
        local sized = packs.texture_at(name, id, size)
        if sized then return sized, whole end
        local texture, waiting = packs.texture(name, id)
        if texture or waiting then return texture, whole end
        return icons.status_at(id, 'Original FFXI', size)
    end
    local texture = icons.status(id, artwork)
    local status = texture and resolved[name] and resolved[name][id]
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
-- Whether Original FFXI has the picture XI View is missing, asked each frame the note shows, so it goes in one table.
local fallback_status = {}
function icons.artwork_status(artwork, id, out)
    artwork = artwork_name(artwork)
    if is_set(artwork) then
        if out then require('table.clear')(out) else out = {} end
        out.available = packs.found(artwork) and (id == nil or packs.has(artwork, id))
        out.using, out.reason = out.available and artwork or 'Original FFXI', packs.reason(artwork)
        return out
    end
    local assets = require('ui.client_assets')
    local status = assets.icon_status(artwork_kinds[artwork], id, out)
    local previous = id ~= nil and resolved[artwork] and resolved[artwork][id]
    if previous then status.using, status.reason = previous.using, previous.reason or status.reason
    elseif status.available then status.using = artwork
    else status.using = artwork == 'XI View' and assets.icon_status('original', id, fallback_status).available and 'Original FFXI' or FALLBACK end
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

-- Artwork and Party list's note ask each frame, so the answer goes through one table.
local reason_status = {}
function icons.reason(artwork, id)
    return icons.artwork_status(artwork, id, reason_status).reason
end

-- The icon choices: Original FFXI and XI View, then your sets, with saved among them while its set isn't there, and
-- what each is called. Kept for each saved choice until the sets are read again, so a frame makes none.
local built_in = { 'Original FFXI', 'XI View' }
local choice_lists, choice_generation = {}, nil
function icons.choices(saved)
    local generation = packs.generation()
    if choice_generation ~= generation then choice_lists, choice_generation = {}, generation end
    local key = type(saved) == 'string' and saved or false
    local held = choice_lists[key]
    if held then return held.list, held.names end
    local list, names = {}, {}
    for index, name in ipairs(built_in) do list[index], names[name] = name, name end
    for _, name in ipairs(packs.names()) do list[#list + 1], names[name] = name, name end
    if key and not names[key] then
        local found = packs.name_of(key)
        if found then names[key] = found
        elseif packs.valid_name(key) then list[#list + 1], names[key] = key, key .. ' (not in the icons folder)' end
    end
    held = { list = list, names = names }
    choice_lists[key] = held
    return list, names
end

-- Reload icons: the icons folder is read again, and what a note says about it, with any packed set not extracted yet,
-- folder of sets that can't be told apart or pictures outside a set's folder.
function icons.reload_sets()
    local count = packs.reload()
    local where = require('core.identity').relative('icons/')
    local said = count == 0 and 'No icon sets are in ' .. where .. ' yet.'
        or (count == 1 and 'One icon set' or count .. ' icon sets') .. ' read from ' .. where .. '.'
    local warning = packs.warning()
    return warning and said .. ' ' .. warning or said
end

-- The line under Icons and Party buff icons while the icons folder holds a packed set not extracted yet, a folder of
-- sets that can't be told apart or pictures outside a set's folder, or nil.
icons.folder_warning = packs.warning

-- Open icons folder: the folder opens in File Explorer, and what a note says about it.
function icons.open_folder()
    if packs.open_folder() then return 'Opened the icons folder in File Explorer.' end
    return 'Windows couldn\'t open the icons folder. It\'s ' .. require('core.identity').relative('icons/') .. ' in the Ashita folder.'
end

function icons.clear()
    packs.clear()
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
