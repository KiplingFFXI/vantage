-- /vg set says, once it has stored a value, one plain line naming the setting and what it holds now, read back from
-- the settings: text in quotes, a number, a switch or a table, the shared layout too, and a note on the same line when
-- the file could not be written. A path or value it refuses says what it always said, and nothing more. /vg get shows
-- text in quotes too, so text of spaces shows, and what it prints sets the setting back as it was.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() end };
local customization = require('core.customization');
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(0.11); end
MOCK.printed = {};
local function set(text)
    local event = { command = text };
    MOCK.fire('command', event);
    assert(event.blocked, 'Vantage takes ' .. text);
    local out = MOCK.printed;
    MOCK.printed = {};
    return out;
end
local function says(text, line)
    local out = set(text);
    assert(#out == 1 and out[1] == '[Vantage] ' .. line, text .. ' says one line: ' .. table.concat(out, ' | '));
end

says('/vg set overhead.camera.capture present', 'overhead.camera.capture is now "present".');
assert(app.state.settings.overhead.camera.capture == 'present' and store.read(app.state.path).overhead.camera.capture == 'present',
    'and it is stored and saved.');
says('/vg set overhead.camera.capture "scene"', 'overhead.camera.capture is now "scene".');
local blank = app.state.settings.panels.target.separator;
assert(type(blank) == 'string' and blank:find('^ +$'), 'Fixture: the separator is spaces.');
local got = set('/vg get panels.target.separator');
assert(#got == 1 and got[1] == '[Vantage] panels.target.separator = "' .. blank .. '"', 'Get shows text in quotes: ' .. table.concat(got, ' | '));
says('/vg set panels.target.separator ' .. got[1]:match(' = (.*)$'), 'panels.target.separator is now "' .. blank .. '".');
assert(app.state.settings.panels.target.separator == blank, 'Set from what get printed, it is as it was.');
says('/vg set overhead.max_units 4', 'overhead.max_units is now 4.');
says('/vg set overhead.size.alpha 0.25', 'overhead.size.alpha is now 0.25.');
says('/vg set overhead.enabled true', 'overhead.enabled is now true.');
says('/vg set overhead.dispel_color [1,0,0,1]', 'overhead.dispel_color is now ' .. store.encode({ 1, 0, 0, 1 }) .. '.');
assert(store.equal(app.state.settings.overhead.dispel_color, { 1, 0, 0, 1 }), 'The table is stored.');
says('/vg set shared_layout true', 'shared_layout is now true.');
assert(app.state.settings.shared_layout == true, 'The shared layout is on.');

-- Refused: the line customization.set gives, alone, and nothing changes.
for _, case in ipairs({ { 'overhead.nothing', '1' }, { 'overhead.max_units', '99' }, { 'overhead.enabled', 'maybe' },
    { 'overhead.camera.capture', 'later' } }) do
    local before = store.copy(app.state.settings);
    local _, why = customization.set(store.copy(app.state.settings), case[1], case[2]);
    assert(type(why) == 'string' and why ~= '', 'Fixture: ' .. case[1] .. ' ' .. case[2] .. ' is refused.');
    local out = set('/vg set ' .. case[1] .. ' ' .. case[2]);
    assert(#out == 1 and out[1] == '[Vantage] ' .. why and not out[1]:find('is now', 1, true),
        'A refused set says only why: ' .. table.concat(out, ' | '));
    assert(store.equal(app.state.settings, before), 'and changes nothing: ' .. case[1]);
end

-- A file that can't be written: the value is set, the save says why, as any save does, and the line says it is not
-- saved yet.
MOCK.file_replace_error = true;
local out = set('/vg set overhead.max_units 5');
MOCK.file_replace_error = nil;
assert(#out == 2 and out[1] == '[Vantage] The saved file could not be replaced. Your previous file was kept.'
    and out[2] == '[Vantage] overhead.max_units is now 5. Settings could not be saved; Vantage will retry.',
    'Not saved yet: ' .. table.concat(out, ' | '));
assert(app.state.settings.overhead.max_units == 5, 'The value is set.');
return true;
