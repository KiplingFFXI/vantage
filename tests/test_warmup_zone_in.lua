-- A zone-in packet (0x00A) during the warmup, for a character whose saved look uses XI View: the packet reads and
-- uploads all of XI View there and then, inside the loading screen, and the warmup's XI View steps are done with it, so
-- no Present runs them again and no display waits on them. The rest of the warmup goes on as before, and nothing draws
-- until it is done. A second zone-in loads nothing more.
local F = require('warmup_fixture');
local L = F.L;
local warmup = require('core.warmup');
local assets, client_fonts = require('ui.client_assets'), require('ui.client_fonts');
F.save('XI View');
local missing = {};
local function art(label)
    if not client_fonts.current('XI View') then missing[#missing + 1] = label .. ': the faces'; end
    if not assets.icons_loaded('xiview') or not assets.action_loaded('xiview', 'common') then missing[#missing + 1] = label .. ': icons'; end
    if not client_fonts.current('Original FFXI') then missing[#missing + 1] = label .. ': the stock face'; end
end
F.watch('ui.hud', 'draw', 'panels', art);
F.watch('ui.settings_window', 'draw', 'settings window', art);
local function view_uploads()
    local count = 0;
    for _, label in ipairs(F.labels) do if label:find('^xiview_') then count = count + 1; end end
    return count;
end

local app = F.load();
assert(view_uploads() == 0 and not warmup.wanted('xiview'), 'The load event uploads nothing of XI View; it makes only its menu font.');
F.present(); F.present();
assert(warmup.wanted('xiview') and warmup.pending('xiview') and warmup.pending('assets'),
    'The saved look wants XI View, and the stock art is still to make.');

local reads, uploads = F.reads, F.uploads;
local packet = L.zone_in(102, false);
assert(packet.blocked == false and F.stages['zone.xiview_preload'] and F.stages['zone.xiview_preload'].count == 1,
    'The zone-in loads XI View, timed.');
assert(F.reads > reads and view_uploads() > 0 and client_fonts.current('XI View') and assets.icons_loaded('xiview'),
    'It reads and uploads XI View there and then.');
assert(not warmup.pending('xiview') and warmup.pending('assets') and app.state.ready == false,
    'Its warmup steps are done with it; the stock art is still to make, and nothing draws yet.');

-- The rest of the warmup, back in the zone.
L.self_timers();
local uploaded = view_uploads();
while warmup.pending('start') or warmup.pending('assets') do assert(F.presents < 60, 'Fixture: the warmup ends.'); F.present(); end
F.present();
assert(view_uploads() == uploaded, 'No Present loads XI View again.');
assert(#F.early == 0 and F.first['panels'], 'Nothing drew before the warmup was done; then the panels drew.');
assert(#missing == 0, 'The first draw finds XI View and the stock art: ' .. table.concat(missing, ', '));
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));

-- A second zone-in for the same character loads nothing more.
reads, uploads = F.reads, F.uploads;
L.zone_in(102, false);
L.self_timers();
F.present();
assert(F.reads == reads and F.uploads == uploads, 'Nothing more is loaded.');
assert(F.stages['zone.xiview_preload'].count == 1, 'Its saved settings are not read again.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'A zone-in during the warmup loads XI View for a saved XI View look';
