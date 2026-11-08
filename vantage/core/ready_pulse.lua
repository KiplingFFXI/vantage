-- The ready pulse (settings.ready_pulse). When a recast at least min_seconds long becomes ready, or comes within its
-- early warning, its icon pulses once: on its row in the recast panels, where that row was last drawn, or at a spot
-- of the screen you place. A recast's length is the full cooldown when its start was seen, else the most it was seen
-- with left. Recasts on the ignore list never pulse. It reads only the client's own recasts (core/recasts.lua) and
-- sends nothing; ui/ready_pulse.lua draws it. Off at first, like the overhead icons.
local pulse = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;
pulse.spots = { 'row', 'screen' };
-- Pulses playing at once, and recasts remembered.
local MOST, KEPT = 8, 256;

function pulse.make()
    return { enabled = false, min_seconds = 60, early = 0, ignore = {}, size = 64, color = { 1, 0.86, 0.45, 1 }, length = 1,
        spot = 'row', x = -1, y = 260, locked = true };
end

local function number(value, low, high, fallback, round)
    return (round and numbers.clamp_round or numbers.clamp)(value, low, high, fallback);
end

-- Keys this doesn't know are kept, as the rest of the settings keep them.
function pulse.tidy(value)
    value = type(value) == 'table' and value or {};
    local fresh = pulse.make();
    for _, key in ipairs({ 'enabled', 'locked' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
    end
    value.min_seconds = number(value.min_seconds, 0, 7200, fresh.min_seconds, true);
    value.early = number(value.early, 0, 600, 0, true);
    value.size = number(value.size, 16, 256, fresh.size, true);
    value.length = number(value.length, 0.2, 5, fresh.length);
    value.x = number(value.x, -1, 16000, -1, true);
    value.y = number(value.y, 0, 16000, fresh.y, true);
    local spot = value.spot;
    value.spot = (spot == 'row' or spot == 'screen') and spot or 'row';
    local color, base = {}, type(value.color) == 'table' and value.color or {};
    for index = 1, 4 do color[index] = number(base[index], 0, 1, fresh.color[index]); end
    value.color = color;
    local ignore = {};
    for key, on in pairs(type(value.ignore) == 'table' and value.ignore or {}) do
        local id = tonumber(key);
        if on == true and finite(id) and id >= 10000 and id <= 95534 and id == math.floor(id) then ignore[id] = true; end
    end
    for _, id in ipairs(type(value.ignore) == 'table' and value.ignore or {}) do
        if finite(id) and id >= 10000 and id <= 95534 and id == math.floor(id) then ignore[id] = true; end
    end
    value.ignore = ignore;
    return value;
end

-- What a pulse draws: the recast's icon, as recast_icons draws a row.
local ICON = { 'spell_id', 'item_id', 'ability_id', 'ability_ids', 'action_icons', 'list_icon_ids', 'list_icon_id', 'list_icon_hq',
    'list_icon_nq', 'ability_element', 'icon_ambiguous', 'recast_id', 'effect', 'name', 'key' };

local methods = {};
methods.__index = methods;

-- seen: each recast row by key, with its instance, the longest it was seen and whether its early pulse played.
-- active: the pulses playing, oldest first, refilled in place.
function pulse.new()
    return setmetatable({ seen = {}, kept = 0, active = {} }, methods);
end

local function start(self, source, kind, now, config, test)
    local active = self.active;
    if #active >= MOST then table.remove(active, 1); end
    local entry = { kind = kind, started = now, length = config.length, spot = config.spot, test = test };
    for _, field in ipairs(ICON) do entry[field] = source[field]; end
    active[#active + 1] = entry;
    return entry;
end

local function wanted(config, effect, length)
    return finite(length) and length >= config.min_seconds and not config.ignore[effect];
end

-- At each refresh: rows are the recast rows, events the recast reader's events. Returns the playing pulses.
function methods:update(rows, events, settings, now)
    local config = type(settings) == 'table' and settings.ready_pulse;
    local active, seen = self.active, self.seen;
    for index = #active, 1, -1 do
        local entry = active[index];
        if not config or not config.enabled or now - entry.started >= entry.length or now < entry.started then table.remove(active, index); end
    end
    if type(config) ~= 'table' or not config.enabled then
        if self.kept > 0 then self.seen, self.kept = {}, 0; end
        return active;
    end
    for _, row in ipairs(rows or {}) do
        if row.domain == 'recast' and row.key then
            local held = seen[row.key];
            if not held then
                if self.kept >= KEPT then seen = {}; self.seen, self.kept = seen, 0; end
                held = {};
                seen[row.key], self.kept = held, self.kept + 1;
            end
            if held.instance ~= row.instance then held.instance, held.longest, held.early = row.instance, 0, false; end
            held.longest = math.max(held.longest, finite(row.total) and row.total or 0, finite(row.remaining) and row.remaining or 0);
            held.at = now;
            local left = row.remaining;
            if config.early > 0 and not held.early and finite(left) and left > 0 and left <= config.early
                and held.longest > config.early and wanted(config, row.effect, held.longest) then
                held.early = true;
                start(self, row, row.kind, now, config);
            end
        end
    end
    for _, event in ipairs(events or {}) do
        if event.kind == 'ready' and event.key then
            local held = seen[event.key];
            local same = held and held.instance == event.instance;
            local length = math.max(finite(event.total) and event.total or 0, same and held.longest or 0);
            if not (same and held.early) and wanted(config, event.effect, length) then start(self, event, event.category, now, config); end
            if held then seen[event.key], self.kept = nil, self.kept - 1; end
        end
    end
    -- A recast not seen for a minute, which left without a ready, is forgotten.
    for key, held in pairs(seen) do
        if now - held.at > 60 then seen[key], self.kept = nil, self.kept - 1; end
    end
    return active;
end

-- A pulse to see the spot and look, from a made-up ability recast.
local test_source = { name = 'Ready pulse', effect = 20000, recast_id = 0, key = 'test' };
function methods:test(settings, now)
    local config = settings.ready_pulse;
    local metadata = require('core.recasts').preview_icon('ability', 547);
    for _, field in ipairs(ICON) do if metadata and metadata[field] ~= nil then test_source[field] = metadata[field]; end end
    return start(self, test_source, 'ability', now, config, true);
end

return pulse;
