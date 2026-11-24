-- Back goes where a link, the top bar or the search came from, and says where. The display's name is a list of the
-- displays, which opens another on the same tab. Neither is a setting, so neither makes an Undo step.
local h = require('panel_fixture')();
local custom = require('core.customization');
local trail = h.panels._trail;
local function back_says() return trail[#trail] and trail[#trail].caption or '< Main page'; end;
local function back() h.draw('< Back##frame'); h.draw(); end;

h.fresh();
for index = #trail, 1, -1 do trail[index] = nil; end;
local before = custom.history_value(h.s);
h.draw();
assert(h.s.window.tab == 'Home', 'Fixture: the main page.');

-- A link from the main page, then one from a tab: Back retraces them, naming each.
h.draw('Edit##main_self_buffs'); h.draw();
assert(h.panels.context() == 'self_buffs/show' and back_says() == '< Main page', 'Back from a display opened on the main page says so.');
h.draw('Filters##frame_tab'); h.draw();
h.draw('Edit the list##frame'); h.draw();
assert(h.panels.context() == 'hidden/show' and back_says() == '< Self buffs, Filters', 'Back names the display and tab the link was on: ' .. back_says());
-- A link to the place open now leaves Back naming the place before it.
h.draw('Hide list'); h.draw();
assert(h.panels.context() == 'hidden/show' and back_says() == '< Self buffs, Filters', 'A link to the place open now: ' .. back_says());
back();
assert(h.s.window.tab == 'Display' and h.panels.context() == 'self_buffs/filters', 'Back opens that display on that tab.');
assert(back_says() == '< Main page', 'Then it names the main page.');
back();
assert(h.s.window.tab == 'Home', 'And goes there.');

-- The name is a list of the displays: a pick opens another on the same tab, and Back comes back.
h.on('self_buffs', 'look');
for index = #trail, 1, -1 do trail[index] = nil; end;
h.pick('##frame_switch', 'Self debuffs##frame_switch_self_debuffs');
assert(h.panels.context() == 'self_debuffs/look' and back_says() == '< Self buffs, Look', 'A pick keeps the tab: ' .. h.panels.context());
-- A display without that tab opens on its own.
h.on('self_buffs', 'filters');
h.pick('##frame_switch', 'Ready pulse##frame_switch_pulse');
assert(h.panels.context() == 'pulse/show', 'The ready pulse has no Filters, so it opens on Show: ' .. h.panels.context());
back();
assert(h.panels.context() == 'self_buffs/filters', 'Back comes back from a pick.');

-- The top bar and the search are noted too.
h.draw('Profiles'); h.draw();
assert(h.s.window.tab == 'Profiles' and back_says() == '< Self buffs, Filters', 'Back from a top bar page names where it was.');
back();
assert(h.s.window.tab == 'Display' and h.panels.context() == 'self_buffs/filters', 'And goes back there.');
for _, result in ipairs(h.window.search('Grid mode')) do
    if result.tab == 'Home' then h.window.open_result(result); break; end;
end;
h.draw();
assert(h.s.window.tab == 'Home' and back_says() == '< Self buffs, Filters', 'A search result is noted as well.');
assert(custom.equal(before, custom.history_value(h.s)) and #h.app.state.history == 0, 'None of it is a setting or an Undo step.');
MOCK.fire('unload');
return 'Back retraces the links, and the display name opens another display on the same tab';
