-- A unit the game hasn't named yet has no name until the game gives one. Nothing stands in for it: no Entity and a
-- number, no number alone, no empty name. The settings say what a remembered id means instead of printing it.
local defaults = require('ui.defaults');
local client = require('core.client');
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui = require('ui.settings_window'), require('imgui');

-- core/client.lua: a unit it can't name has no name, and takes one once the game has it.
local MOB, NAMES, IDS = 0x1000123, {}, {};
local entities = {
    GetServerId = function(_, index) return IDS[index]; end, GetSpawnFlags = function() return 0x10; end,
    GetName = function(_, index) return NAMES[index]; end,
};
assert(client.resolve(0x1000FFF, nil, entities).name == nil, 'A unit the client doesn\'t hold has no name.');
assert(client.resolve(0x1000FFF, nil, entities).kind == 'monster', 'It keeps its kind.');
IDS[0x123] = MOB;
assert(client.resolve(MOB, 0x123, entities).name == nil, 'A unit the game hasn\'t named has no name.');
NAMES[0x123] = '';
assert(client.resolve(MOB, 0x123, entities).name == nil, 'An empty name is no name.');
assert(client.resolve(MOB, nil, entities).name == nil, 'The kept row has none either.');
NAMES[0x123] = 'Goblin Mugger';
assert(client.resolve(MOB, nil, entities).name == 'Goblin Mugger', 'A kept row with no name asks again, and takes the game\'s.');

-- core/effect_filters: a row's own name is its effect's, and that isn't the unit's.
local filters = require('core.effect_filters');
local row = { entity_id = 2002, scope = 'party', effect = 33, name = 'Haste' };
assert(filters.context({}, 2002, row).name == '', 'A row whose unit has no name gives no name.');
assert(filters.context({}, 2002, { entity_id = 2002, entity_name = 'Bob', scope = 'party', name = 'Haste' }).name == 'bob', 'A named row gives its unit\'s.');
assert(filters.context({}, 2002, { name = 'Bob', scope = 'party' }).name == 'bob', 'A member gives its own.');

-- core/durations: times on a mob go by its name, so one with no name has no key, while other units keep theirs.
local durations = require('core.durations');
assert(durations.key({ scope = 'enemy', effect = 2, action_category = 4, spell = 2 }) == nil, 'A mob with no name teaches nothing.');
assert(durations.key({ scope = 'enemy', effect = 2, action_category = 4, spell = 2, entity_name = '' }) == nil, 'Nor one with an empty name.');
assert(durations.key({ scope = 'enemy', effect = 2, action_category = 4, spell = 2, entity_name = 'Goblin' }) == 'spell:2:2:goblin', 'A named mob keeps its key.');
assert(durations.key({ scope = 'party', effect = 33, action_category = 4, spell = 57 }) == 'spell:57:33:', 'A player needs no name.');

-- The settings.
local view = { rows = {}, subjects = {}, context = { valid = true, job = 3, entities = {},
    party = { { id = 1001, name = 'Tester', scope = 'party' }, { id = 1002, name = 'Friend', scope = 'party' } } } };
local s = app.state.settings;
s.window.open, s.window.tab = true, 'Display';
s.window.sections = setmetatable({}, { __index = function() return true; end });
local combo;
local real_combo = imgui.BeginCombo;
imgui.BeginCombo = function(label, ...) real_combo(label, ...); return label == combo; end;
local function draw(clicks)
    MOCK.imgui_calls = {};
    for _, label in ipairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, app.callbacks);
    MOCK.clicks = {};
end;
local function called(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true; end; end;
    return false;
end;
local function any(words)
    for _, call in ipairs(MOCK.imgui_calls) do
        for index = 2, 3 do
            if type(call[index]) == 'string' and call[index]:find(words) then return call[index]; end;
        end;
    end;
    return nil;
end;
local function pick(panel)
    require('ui.panel_frame').open(panel, 'show');
    draw();
end;

-- Members: someone who left the party.
pick('party');
s.panels.party.members = { [1002] = true, [2001] = true, [2002] = true };
draw();
assert(called('Checkbox', 'Friend##member_1002'), 'A member in the party keeps their name.');
local away = 0;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextUnformatted' and call[2] == 'Someone not in your party now' then away = away + 1; end;
end;
assert(away == 2, 'Each member no longer in the party reads Someone not in your party now, with a row of their own.');
assert(not any('not currently visible') and not any('Member %d'), 'No number: ' .. tostring(any('Member %d')));
-- Remove waits for the list to be drawn. Taking someone off adds a key to the table pairs is walking, and Lua doesn't say
-- what the walk does then, so the frame of the click draws both rows with the list as it was.
local text, whole = imgui.TextUnformatted, {};
imgui.TextUnformatted = function(words, ...)
    if words == 'Someone not in your party now' then whole[#whole + 1] = s.panels.party.members[2001] == true and s.panels.party.members[2002] == true; end;
    return text(words, ...);
end;
draw({ 'Remove##member' });
imgui.TextUnformatted = text;
assert(#whole == 2 and whole[1] and whole[2], 'The frame of a Remove draws each row once, with the list as it was.');
assert((s.panels.party.members[2001] and 1 or 0) + (s.panels.party.members[2002] and 1 or 0) == 1 and s.panels.party.members[1002] == true,
    'Remove takes out only that one.');
for _, result in ipairs(window.search('someone not in your party')) do assert(result.tab ~= 'Display', 'A remembered id isn\'t a thing to search for.'); end;
s.panels.party.members = {};

-- Watched enemies: the target goes by its name, one Vantage saw by the name it saw, and one it holds nothing on says so.
pick('watch');
s.watch_ids = { MOB, 0x1000200, 0x1000201, 0x1000202 };
view.context.entities = { [MOB] = { id = MOB, name = 'Crab', kind = 'monster' } };
view.subjects = { { id = 0x1000200, name = 'Goblin Smithy', scope = 'enemy' }, { id = 0x1000201, scope = 'enemy' } };
draw();
assert(called('TextUnformatted', 'Crab'), 'The target has its name.');
assert(called('TextUnformatted', 'Goblin Smithy'), 'One out of the context has the name Vantage saw.');
local gone = 0;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextUnformatted' and call[2] == 'An enemy that is out of range now' then gone = gone + 1; end;
end;
assert(gone == 2, 'One with no name and one Vantage holds nothing on read An enemy that is out of range now: ' .. gone);
assert(not any('Entity'), 'No Entity line: ' .. tostring(any('Entity')));
-- One the game still holds that isn't your target isn't out of range, whether or not Vantage saw anything on it.
local resolve = client.resolve;
client.resolve = function(id) return { id = id, name = id == 0x1000202 and 'Goblin Pathfinder' or nil }; end;
draw();
client.resolve = resolve;
assert(called('TextUnformatted', 'Goblin Pathfinder'), 'It has the game\'s name.');
s.watch_ids = {};
view.subjects, view.context.entities = {}, {};

-- An alert rule's Specific member: the list is your party.
require('ui.panel_frame').open('notices', 'show');
s.window.tab = 'Display';
draw({ 'New alert##frame' });
local rule = s.alerts.rules[#s.alerts.rules];
rule.scope, rule.entity_id = 'party', 2001;
draw();
local shown;
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'BeginCombo' and call[2] == '##frame_Specific member' then shown = call[3]; end; end;
assert(shown == 'Someone not in your party now', 'A remembered member reads the same: ' .. tostring(shown));
print('unnamed units passed');
return true;
