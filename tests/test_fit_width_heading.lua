-- Fit the width makes room for the heading as it is drawn: the panel's usual name when its Heading box is left blank,
-- and the samples' mark after the title while Show samples is on.
package.loaded['ui.icons'] = {status=function() return 123; end};
rawset(require('imgui'), 'CalcTextSize', function(text) return #tostring(text) * 8, 18; end);
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local function row(index, name)
    return {key='r' .. index, effect=40 + index, slot=index - 1, scope='self', entity_id=1001, kind='buff',
        status='server', present=true, name=name, deadline=1000 + 60 * index};
end;
local rows = {row(1, 'Protect'), row(2, 'Shell')};
-- Draws Self buffs with a Title size of 30, so its heading is wider than its rows. Returns the window's width and the
-- room the clip gives the title, which must draw as text.
local function heading(title, text, preview)
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale, s.style.title_size = 'Ashita', 14, 1, 30;
    s.preview = preview;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
    local p = s.panels.self_buffs;
    p.mode, p.auto_width, p.min_width, p.max_width, p.stack_direction = 'bars', true, 60, 900, 'vertical';
    p.show_heading, p.max_rows, p.title = true, 2, title;
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true}, rows=rows}, s, 1000, {});
    local width, inside, clip;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowSize' then width = call[2][1];
        elseif call[1] == 'Begin' then inside = call[2] == '##vantage_self_buffs';
        elseif inside and call[1] == 'draw:PushClipRect' then clip = MOCK.drawn[call];
        elseif inside and call[1] == 'draw:AddText' and MOCK.drawn[call][6] == text then
            return width, clip[3][1] - clip[2][1];
        end;
    end;
    error('Fixture: the heading drew ' .. text);
end;
-- 8 px a character at Text size 14.
local function at(size, text) return #text * 8 * size / 14; end;
local name, marked = defaults.panel_names.self_buffs, defaults.panel_names.self_buffs .. '  /  Sample';
assert(at(30, name) > at(30, 'Vantage') + 8, 'Fixture: the usual name is wider than Vantage.');

-- A blank Heading box draws the usual name, with room for all of it, as when the name is typed in.
local blank, blank_room = heading('', name);
local typed, typed_room = heading(name, name);
assert(blank_room >= at(30, name), ('A blank heading has room for the usual name: %s px for %s'):format(blank_room, at(30, name)));
assert(math.abs(blank - typed) < 1e-6 and blank_room == typed_room,
    ('A blank heading fits as the usual name typed in does: %s and %s wide'):format(blank, typed));
-- A heading of the player's own fits as before.
local _, own_room = heading('My timers', 'My timers');
assert(own_room >= at(30, 'My timers'), 'A typed heading has room for itself.');
-- Show samples draws the title with the samples' mark, and the width makes room for the mark too.
for _, title in ipairs({name, ''}) do
    local _, room = heading(title, marked, true);
    assert(room >= at(30, marked), ('The samples\' mark fits after %s: %s px for %s'):format(
        title == '' and 'a blank heading' or title, room, at(30, marked)));
end;
