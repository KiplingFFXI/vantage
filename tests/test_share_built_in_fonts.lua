-- Exports (core/share.lua) keep a font picked from the built-in list when your character's name is one of its words,
-- as they keep a built-in icon set. A font file of your own named after you is still left out.
local share, defaults, json, store = require('core.share'), require('ui.defaults'), require('core.json'), require('core.store');
local function fresh() return defaults.tidy(defaults.make()); end;
local function data_of(text) return json.decode(text:match('^VG:1:%x+:(.+)$')).data; end;

do -- Section: a fresh install's font stays for a character named Original.
    local s = fresh();
    assert(s.style.font == 'Original FFXI', 'Fixture: a fresh install draws with the Original FFXI font: ' .. tostring(s.style.font));
    local text, note = share.export(s, 'profile', nil, 'Original');
    assert(text and note == nil, 'It exports with nothing left out: ' .. tostring(note));
    local font = data_of(text).style.font;
    assert(font == 'Original FFXI', 'A character named Original keeps the default font, but the export holds "' .. tostring(font) .. '".');
    assert(data_of(text).style.icon_art == 'Original FFXI', 'The built-in icon set stays too.');
    local added = assert(share.candidate(store.copy(s), assert(share.read(text)), 'add'));
    assert(added.style.font == 'Original FFXI', 'Add keeps the default font: ' .. tostring(added.style.font));
end; -- end of section

do -- Section: a font picked from the list stays for a character named after one of its words.
    local s = fresh();
    s.style.font = 'Georgia Bold';
    s = defaults.tidy(s);
    local text, note = share.export(s, 'profile', nil, 'Georgia');
    assert(text and note == nil, 'It exports with nothing left out: ' .. tostring(note));
    local font = data_of(text).style.font;
    assert(font == 'Georgia Bold', 'Georgia keeps the font Georgia Bold, but the export holds "' .. tostring(font) .. '".');
end; -- end of section

do -- Section: a font file of your own with your name in it is still left out.
    local s = fresh();
    s.style.font = 'Georgia Rose';
    s = defaults.tidy(s);
    local text = assert(share.export(s, 'profile', nil, 'Georgia'));
    local font = data_of(text).style.font;
    assert(font == '', 'Georgia\'s own font Georgia Rose is left out, but the export holds "' .. tostring(font) .. '".');
end; -- end of section
