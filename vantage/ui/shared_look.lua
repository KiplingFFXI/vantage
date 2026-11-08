-- Countdown text and blink for every display at once, from More look on the main page. Each display keeps its own keys
-- and its renderer reads them, so a pick writes them all and nothing new is saved: Usual, Every display, None
-- and Mixed are read back from those keys each time.
local copy = require('core.store').copy;
local defaults = require('ui.defaults');
local look = {};

-- Every display with a countdown, then the ones of those that blink, in the order a question names them.
local ids, blink_ids = {}, {};
for _, id in ipairs(defaults.panel_order) do
    ids[#ids + 1] = id;
    if not defaults.recast_panels[id] then blink_ids[#blink_ids + 1] = id; end;
end;
for _, id in ipairs({ 'party_ui', 'overhead', 'rolls', 'pet' }) do ids[#ids + 1] = id; end;
blink_ids[#blink_ids + 1], blink_ids[#blink_ids + 2], blink_ids[#blink_ids + 3] = 'party_ui', 'overhead', 'pet';

look.names = { self_buffs = 'Self buffs', self_debuffs = 'Self debuffs', target = 'Target timers', party = 'Party members\' timers',
    watch = 'Watched enemy timers', spell_recasts = 'Spell recasts', ability_recasts = 'Ability recasts', item_recasts = 'Item recasts',
    recasts = 'Recasts (one panel)', party_ui = 'Party list buffs', overhead = 'Overhead icons', rolls = 'Phantom Roll', pet = 'Pet' };
local recast_ids = { 'spell_recasts', 'ability_recasts', 'item_recasts', 'recasts' };

-- Outlines are on where text sits on busy art: the status timers and the party list.
local function usual_outline(id) return id == 'party_ui' or (id ~= 'overhead' and id ~= 'rolls' and id ~= 'pet' and not defaults.recast_panels[id]); end;

look.outlines = { 'usual', 'every', 'none' };
look.outline_labels = { usual = 'Usual for each display', every = 'Every display', none = 'None', mixed = 'Mixed' };

local function holder(settings, id)
    if id == 'party_ui' then return settings.party_ui.effects; end;
    if id == 'overhead' or id == 'rolls' or id == 'pet' then return settings[id]; end;
    return settings.panels[id];
end;

-- Puts every display's countdown text and blink back as fresh has them.
function look.restore(settings, fresh)
    for _, id in ipairs(ids) do defaults.copy_countdown(holder(fresh, id), holder(settings, id)); end;
    for _, id in ipairs(blink_ids) do
        local from, into = holder(fresh, id), holder(settings, id);
        into.blink_icons, into.blink_seconds = from.blink_icons, from.blink_seconds;
    end;
end;

local function same_color(a, b)
    for index = 1, 4 do if a[index] ~= b[index] then return false; end; end;
    return true;
end;

local function same_value(a, b)
    if type(a) == 'table' and type(b) == 'table' then return same_color(a, b); end;
    return a == b;
end;

-- The one value a key has on every display, or nil while they differ.
local function shared(settings, list, key)
    local first = holder(settings, list[1])[key];
    for index = 2, #list do
        if not same_value(holder(settings, list[index])[key], first) then return nil; end;
    end;
    return first;
end;

function look.bold(settings) return shared(settings, ids, 'countdown_bold'); end;
function look.shadow(settings) return shared(settings, ids, 'countdown_shadow'); end;
function look.outline_color(settings) return shared(settings, ids, 'countdown_outline_color'); end;
function look.blink(settings) return shared(settings, blink_ids, 'blink_icons'); end;
function look.blink_seconds(settings) return shared(settings, blink_ids, 'blink_seconds'); end;

-- The color a swatch starts from while the displays differ.
function look.first_outline_color(settings) return holder(settings, ids[1]).countdown_outline_color; end;
function look.first_blink_seconds(settings) return holder(settings, blink_ids[1]).blink_seconds; end;

-- Which of the three outline choices the saved outlines are, or mixed for a save that is none of them.
function look.outline(settings)
    local usual, every, none = true, true, true;
    for _, id in ipairs(ids) do
        local on = holder(settings, id).countdown_outline == true;
        if on ~= usual_outline(id) then usual = false; end;
        if on then none = false; else every = false; end;
    end;
    return usual and 'usual' or every and 'every' or none and 'none' or 'mixed';
end;

local function outline_value(choice, id)
    if choice == 'usual' then return usual_outline(id); end;
    return choice == 'every';
end;

local function write(settings, list, key, value)
    for _, id in ipairs(list) do holder(settings, id)[key] = type(value) == 'table' and copy(value) or value; end;
end;

function look.set_bold(settings, value) write(settings, ids, 'countdown_bold', value == true); end;
function look.set_shadow(settings, value) write(settings, ids, 'countdown_shadow', value == true); end;
function look.set_outline_color(settings, value) write(settings, ids, 'countdown_outline_color', value); end;
function look.set_blink(settings, value) write(settings, blink_ids, 'blink_icons', value == true); end;
function look.set_blink_seconds(settings, value) write(settings, blink_ids, 'blink_seconds', value); end;

function look.set_outline(settings, choice)
    for _, id in ipairs(ids) do holder(settings, id).countdown_outline = outline_value(choice, id); end;
end;

-- Names the displays, with the four recast panels said once when a pick changes them all.
local function named(changing)
    local out, all_recasts = {}, true;
    for _, id in ipairs(recast_ids) do all_recasts = all_recasts and changing[id] == true; end;
    for _, id in ipairs(ids) do
        if changing[id] then
            if not all_recasts or not defaults.recast_panels[id] then out[#out + 1] = look.names[id];
            elseif id == recast_ids[1] then out[#out + 1] = 'Recasts'; end;
        end;
    end;
    return table.concat(out, ', ');
end;

local function differing(settings, list, key, value)
    local changing = {};
    for _, id in ipairs(list) do changing[id] = not same_value(holder(settings, id)[key], value) or nil; end;
    return named(changing);
end;

-- The displays a pick would change, for the question asked before it overrides Mixed.
function look.changes_bold(settings, value) return differing(settings, ids, 'countdown_bold', value == true); end;
function look.changes_shadow(settings, value) return differing(settings, ids, 'countdown_shadow', value == true); end;
function look.changes_outline_color(settings, value) return differing(settings, ids, 'countdown_outline_color', value); end;
function look.changes_blink(settings, value) return differing(settings, blink_ids, 'blink_icons', value == true); end;
function look.changes_blink_seconds(settings, value) return differing(settings, blink_ids, 'blink_seconds', value); end;

function look.changes_outline(settings, choice)
    local changing = {};
    for _, id in ipairs(ids) do
        changing[id] = (holder(settings, id).countdown_outline == true) ~= outline_value(choice, id) or nil;
    end;
    return named(changing);
end;

return look;
