local icons = {}
local capacity, retry_seconds = 64, 30
local entries, count, sequence = {}, 0, 0
-- Ashita's IItem bitmap owns 0x980 bytes.
local client, test_loader = require('ui.client_bitmap').loader(0x980), nil

function icons.prepare()
    return client.prepare()
end

function icons.ready()
    return client.ready()
end

local function load(item)
    if test_loader then return test_loader(item) end
    if not client.prepare() or not AshitaCore then return false end
    local resources = AshitaCore:GetResourceManager()
    return client.load(resources and resources:GetItemById(item))
end

local function retain(item)
    if count >= capacity then
        local oldest, touched
        for id, entry in pairs(entries) do
            if not touched or entry.touched < touched then oldest, touched = id, entry.touched end
        end
        local dropped = entries[oldest]
        entries[oldest], count = nil, count - 1
        if dropped.release then pcall(dropped.release) end
    end
    local entry = {}
    entries[item], count = entry, count + 1
    return entry
end

function icons.texture(item)
    if type(item) ~= 'number' or item ~= item or item < 1 or item > 65534 or item ~= math.floor(item) then return nil end
    local entry = entries[item] or retain(item)
    sequence = sequence + 1
    entry.touched = sequence
    if entry.texture then return entry.texture end
    local now = os.clock()
    if not entry.retry_at or now >= entry.retry_at then
        local ok, value, release = pcall(load, item)
        local valid = ok and type(value) == 'number' and value > 0 and value ~= math.huge and value == math.floor(value)
        entry.texture, entry.retry_at = valid and value or nil, not valid and now + retry_seconds or nil
        if type(release) == 'function' then
            if valid then entry.release = release else pcall(release) end
        end
    end
    return entry.texture
end

function icons.clear()
    local previous = entries
    entries, count, sequence = {}, 0, 0
    client.reset()
    for _, entry in pairs(previous) do if entry.release then pcall(entry.release) end end
end

if VANTAGE_TEST_MODE then
    function icons._set_loader_for_tests(value) test_loader = value end
end

return icons
