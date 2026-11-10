-- The Hidden everywhere and Timer durations pages find effects without walking the catalog each frame: they go by the
-- window's catalog revision, and a spell or ability list never changes once it's made. An effect new to the catalog
-- still reaches the finder.
local h = require('panel_fixture')();
h.fresh();
local effects = require('ui.effect_settings');
local same, walks = effects.same_catalog, 0;
effects.same_catalog = function(...) walks = walks + 1; return same(...); end;
local function frames(count)
    walks = 0;
    for _ = 1, count do h.draw(); end
    return walks;
end

h.on('hidden', 'show');
frames(2);
assert(frames(5) == 0, 'Hidden everywhere walks nothing while nothing changes: ' .. walks);
h.type('##frame_Find an effect', 'Zz Test Effect');
assert(h.previews['##frame_Effect'] == nil, 'Fixture: nothing has that name yet.');
h.view.rows[#h.view.rows + 1] = { domain = 'status', effect = 1000, name = 'Zz Test Effect', kind = 'buff', present = true };
h.draw(); h.draw();
assert(h.previews['##frame_Effect'] == 'Zz Test Effect', 'An effect new to the catalog reaches the finder: ' .. tostring(h.previews['##frame_Effect']));

local page = require('ui.duration_settings');
h.s.window.tab = 'Durations';
for _, kind in ipairs({ 'effect', 'spell', 'ability' }) do
    page._pick.kind, page._pick.query = kind, '';
    frames(2);
    assert(frames(5) == 0, 'Timer durations walks nothing for a ' .. kind .. ' while nothing changes: ' .. walks);
end
effects.same_catalog = same;
