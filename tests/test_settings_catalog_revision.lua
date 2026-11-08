-- Where the settings window keeps a revision of its effect catalog, a finder compares that instead of walking the catalog
-- each frame, and a live list on Filters is said again only when its table, the settings or the catalog's names change.
-- Without one both go on as before. A button caption too wide for the page is wrapped again only when its room, its
-- width, the font size or the settings change.
local editor, status = require('ui.effect_settings'), require('ui.status_panel');
local walks, same = 0, editor.same_catalog;
editor.same_catalog = function(...) walks = walks + 1; return same(...); end;

-- The finder by itself.
local entries, selection = { { id = 33, name = 'Haste', kind = 'buff' }, { id = 40, name = 'Protect', kind = 'buff' } }, { query = '' };
assert(editor.selection(entries, selection, 1) == 33, 'Fixture: the first effect is picked.');
local labels = selection.labels;
for _ = 1, 5 do editor.selection(entries, selection, 1); end;
assert(walks == 0 and selection.labels == labels, 'With a revision an unchanged catalog is not walked, and its list is kept.');
entries[1].name = 'Slow';
assert(editor.selection(entries, selection, 2) == 33 and selection.labels ~= labels and selection.labels[33] == 'Slow' and walks == 0,
    'A new revision lists the catalog again.');
labels = selection.labels;
selection.query = 'prot';
assert(editor.selection(entries, selection, 2) == 40 and selection.labels ~= labels, 'What is typed still lists it again.');
entries[#entries + 1] = { id = 58, name = 'Protectra', kind = 'buff' };
assert(editor.selection(entries, selection, 2) == 40 and selection.labels[58] == 'Protectra' and walks == 0,
    'One added to the same list shows by their count, with the same revision.');
walks = 0;
editor.selection(entries, selection);
editor.selection(entries, selection);
assert(walks == 2, 'Without a revision the catalog is walked each time, as before.');

-- The finders on Filters pass the window's revision.
local h = require('panel_fixture')();
local helpers = require('ui.settings_window').main_helpers;
local kept_revision, names = helpers.catalog_revision, 1;
local function revision() return names; end;
helpers.catalog_revision = revision;
h.fresh(function(s)
    s.panels.self_buffs.mode, s.overhead.enabled = 'bars', true;
    s.overhead.types.mob.include, s.overhead.types.party.include = { 33, 40 }, { 42 };
end);
for _, id in ipairs({ 'self_buffs', 'overhead' }) do
    h.on(id, 'filters');
    walks = 0;
    h.draw(); h.draw(); h.draw();
    assert(walks == 0, 'The finder does not walk a catalog the window keeps a revision of: ' .. id);
    helpers.catalog_revision = nil;
    h.draw(); h.draw();
    assert(walks == 2, 'Without one it walks it each frame, as before: ' .. id .. ' (' .. walks .. ')');
    helpers.catalog_revision = revision;
end;

-- The overhead icons' lists are live, as the kind they show is picked with no change of settings.
local overhead = require('ui.overhead_settings');
overhead._selection.kind = 'mob';
h.on('overhead', 'filters');
local entries_of, said = status.entries_of, 0;
status.entries_of = function(...) said = said + 1; return entries_of(...); end;
-- A whole line, as a tick's words can hold a name too.
local function listed(name) return #h.calls('TextUnformatted', name) > 0; end;
h.draw(); h.draw(); h.draw();
assert(said == 0 and listed('Haste') and listed('Protect'), 'A live list is said once while nothing it goes by changes.');
overhead._selection.kind = 'party';
h.draw();
assert(said == 1 and listed('Regen') and not listed('Haste'), 'Another kind is another table, so its list is said again.');
names = 2;
h.draw();
assert(said == 2 and listed('Regen'), 'A change to the catalog\'s names says it again.');
said = 0;
h.type('##frame_Find an effect', 'Protect');
assert(said == 0, 'Typing in the finder changes no list, so none is said again.');
h.draw('Show only##frame');
assert(said == 1 and listed('Protect') and listed('Regen'), 'A tick that changes the list in place shows on its line in the same frame.');
h.draw();
assert(said == 1, 'And it is kept after.');
helpers.catalog_revision = nil;
said = 0;
h.draw(); h.draw();
assert(said == 2, 'Where the window keeps no revision of the catalog\'s names, a live list is said each frame, as before.');
helpers.catalog_revision = revision;
status.entries_of = entries_of;
editor.same_catalog = same;

-- A caption too wide for the page.
local wrap, imgui = require('ui.text_wrap'), require('imgui');
local CAPTION, ID = 'Clear this kind\'s filters', '###Clear this kind\'s filters##frame';
local lines, wrapped = wrap.lines, 0;
wrap.lines = function(text, ...)
    if text == CAPTION then wrapped = wrapped + 1; end;
    return lines(text, ...);
end;
-- The mock keeps a button's ID alone, so what it was drawn with is kept here.
local button, shown = imgui.Button, {};
imgui.Button = function(label, ...)
    if tostring(label):sub(-#ID) == ID then shown[#shown + 1] = label; end;
    return button(label, ...);
end;
local function draw()
    shown = {};
    h.draw();
    assert(#shown == 1, 'Fixture: the button is drawn once.');
    return shown[1];
end;
local function fresh_label(room)
    return table.concat(lines(CAPTION, math.max(1, room - 20), imgui.CalcTextSize), '\n') .. ID;
end;
MOCK.content_width = 150;
local label = draw();
assert(wrapped == 1 and label == fresh_label(150) and label:find('\n', 1, true), 'Fixture: the caption wraps.');
assert(draw() == label and draw() == label and wrapped == 1, 'A wrapped caption is kept while nothing it goes by changes.');
MOCK.content_width = 120;
assert(draw() == fresh_label(120) and wrapped == 2, 'Less room wraps it again.');
h.bump();
assert(draw() == fresh_label(120) and wrapped == 3, 'So does a change of settings.');
local font_size = imgui.GetFontSize;
imgui.GetFontSize = function() return 20; end;
draw();
imgui.GetFontSize = font_size;
assert(wrapped == 4, 'And of the font size.');
MOCK.content_width = nil;
assert(draw() == CAPTION .. ID and wrapped == 4, 'With room the caption is drawn whole.');
imgui.Button = button;
wrap.lines = lines;
helpers.catalog_revision = kept_revision;
MOCK.fire('unload');
return 'The window\'s catalog revision spares the finders\' walk and the live lists, and wrapped captions are kept';
