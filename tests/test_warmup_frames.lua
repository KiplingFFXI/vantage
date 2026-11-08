-- /load with a saved look, the party strips and overhead icons on, with what each slow call costs (warmup_fixture.lua):
-- the load event does only its font part and the sound list; the first Present runs no step; from the second on the
-- steps run in order, at least one a Present, and no Present spends more than the budget and its largest step. The
-- refresh runs from the first Present, so an action packet that arrives during the warmup is a row at once. Nothing
-- draws until the art is made, then every display draws in the same Present, the one after the Present the displays'
-- last step ran in, which runs no step itself. They find every texture and face, and draws read, upload and search
-- nothing. The overhead blocks wait for the name point's steps alone.
-- With VANTAGE_WARMUP_ESTIMATE set it writes the estimate the costs give.
local F = require('warmup_fixture');
local L, W = F.L, F.W;
local warmup = require('core.warmup');
local assets, client_fonts = require('ui.client_assets'), require('ui.client_fonts');
local overhead = require('core.overhead');
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Goblin Mugger', hitbox = 1.2 });
W.target = 0x100;
F.save('Original FFXI', function(settings) settings.party_ui.enabled, settings.overhead.enabled = true, true; end);

-- What a display finds at its first draw: the window frame in use and the stock font's textures, the stock face and
-- frame font, the status icons and the action icons. The frames no display draws with aren't loaded.
local missing = {};
local function art(label)
    if not assets.cached_texture('window', 'newtex', 1) then missing[#missing + 1] = label .. ': the window frame'; end
    for window = 2, 8 do
        if assets.cached_texture('window', 'newtex', window) then missing[#missing + 1] = label .. ': window ' .. window .. ' loaded'; end
    end
    for kind, name in pairs({ original_font = 'moji' }) do
        if not assets.cached_texture(kind, name) then missing[#missing + 1] = label .. ': ' .. kind; end
    end
    if not client_fonts.current('Original FFXI') then missing[#missing + 1] = label .. ': the face'; end
    if not assets.icons_prepared() then missing[#missing + 1] = label .. ': the status icons'; end
    for _, key in ipairs({ 'main', 'secondary', 'common' }) do
        if not assets.action_loaded('original', key) then missing[#missing + 1] = label .. ': the action icons ' .. key; end
    end
end
F.watch('ui.hud', 'draw', 'panels', art);
F.watch('ui.hud', 'draw_notices', 'notices', art);
F.watch('ui.native_party_hud', 'draw', 'party strips', art);
F.watch('ui.settings_window', 'draw', 'settings window', art);
F.watch('ui.overhead_icons', 'draw', 'overhead icons', art);
F.watch('ui.edit_mode', 'draw', 'edit mode');

local app = F.load();
assert(#warmup.report().steps == 0 and F.finds == 0 and F.uploads == 0, 'The load event runs no step, searches and uploads nothing.');
assert(F.stages['load.event'] and F.stages['load.fonts'] and F.stages['load.sound'] and F.stages['load.requires']
    and not F.stages['load.client'] and not F.stages['load.icons'], 'The load event times its own parts, and only those.');
assert(F.stages['fonts.registration'] and F.stages['fonts.menu'], 'Its font part is the menu fonts and the Windows fonts.');
assert(app.state.ready == false and not app.state.path, 'The displays wait, and the settings are read by the first refresh.');

-- The first Present belongs to the load's stall: it refreshes and runs no step.
local first_ms, ran = F.present();
assert(#ran == 0 and F.stages['load.first_present'], 'The first Present runs no step.');
assert(app.state.path and app.state.snapshot.valid, 'Its refresh reads the settings and the game.');
assert(F.stages['first_refresh.client_read'] and F.stages['first_refresh.read_settings'] and F.stages['first_refresh.roster']
    and F.stages['first_refresh.rest'], 'The first refresh is timed in parts.');
assert(warmup.wanted('party') and warmup.wanted('names') and not warmup.wanted('xiview'),
    'The saved settings want the party list and the name point, and not XI View.');
assert(next(F.first) == nil, 'Nothing draws.');

local expected = { 'clock.game_time', 'client.pointers', 'chat.table', 'chat.scale', 'assets.window', 'assets.original_font',
    'fonts.face', 'icons.pack', 'recasts.items', 'actions.original.main',
    'actions.original.secondary', 'actions.original.common', 'party.list_1', 'party.list_2', 'party.treasure' };
local sorted = {};
for name in pairs(require('core.name_anchor')._patterns) do sorted[#sorted + 1] = name; end
table.sort(sorted);
for _, name in ipairs(sorted) do expected[#expected + 1] = 'name_anchor.' .. name; end
expected[#expected + 1] = 'name_anchor.operands';

-- The Presents until every wanted step has run; Bob's Dia on your target arrives after the third.
local frames, largest, ready_at, names_at, packet = {}, 0, nil, nil, nil;
local function left() return warmup.pending('start') or warmup.pending('assets') or warmup.pending('party') or warmup.pending('names'); end
while left() do
    assert(F.presents < 100, 'Fixture: the warmup ends.');
    local waiting = warmup.pending('names');
    local ms, steps = F.present();
    frames[#frames + 1] = { ms = ms, steps = steps, ready = app.state.ready };
    for _, step in ipairs(steps) do largest = math.max(largest, step.ms); end
    if app.state.ready and not ready_at then
        ready_at = F.presents;
        assert(#steps == 0, 'The Present the displays first draw in runs no step.');
    else
        assert(#steps >= 1, 'Every other Present runs at least one step while some are left: Present ' .. F.presents);
    end
    if waiting and overhead.plan.count > 0 then error('A block was placed before the name point\'s steps ran.'); end
    if not warmup.pending('names') and not names_at then names_at = F.presents; end
    if F.presents == 3 then
        packet = L.action(4, 23, 1002, { { id = 0x1000100, rows = { { message = 2, param = 6 } } } });
        assert(left(), 'Fixture: the packet arrives during the warmup.');
    elseif F.presents == 4 then
        assert(packet.blocked == false and L.row(0x1000100, 134) and L.row(0x1000100, 134).source == 1002,
            'An action packet during the warmup is a row at the next refresh.');
    end
end
local order = F.names(warmup.report().steps);
assert(table.concat(order, ' ') == table.concat(expected, ' '), 'The steps in order: ' .. table.concat(order, ' '));
local worst = 0;
for index, frame in ipairs(frames) do
    worst = math.max(worst, frame.ms);
    assert(frame.ms < warmup._BUDGET + largest, ('Present %d spends %.2f ms, over the budget and the largest step (%.2f ms).')
        :format(index + 1, frame.ms, largest));
end

-- The displays: none before the art, then all of them in one Present, with everything there.
assert(#F.early == 0, 'Nothing draws before the warmup lets it: ' .. table.concat(F.early, ', '));
local last_step;
for _, step in ipairs(warmup.report().steps) do if step.name == 'party.treasure' then last_step = step.present; end end
assert(last_step == ready_at - 1, 'The displays\' last step ran in the Present before they drew: ' .. tostring(last_step));
assert(ready_at and F.first['panels'] == ready_at and F.first['party strips'] == ready_at and F.first['settings window'] == ready_at
    and F.first['overhead icons'] == ready_at, 'The panels, the party strips, the settings window and the overhead icons start together.');
assert(#missing == 0, 'The first draw finds every texture and face: ' .. table.concat(missing, ', '));
assert(#F.during == 0, 'Drawing reads, uploads and searches nothing: ' .. table.concat(F.during, ', '));
assert(names_at > ready_at, 'The name point\'s steps run after the displays could draw, which do not wait for them.');
F.present();
assert(L.unit(0x1000100) and L.unit(0x1000100).target, 'Once they have run, the target\'s block carries Bob\'s Dia.');
assert(#F.during == 0 and app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));

-- /vg report's startup section.
local report = warmup.report();
assert(report.spread and report.ready and report.displays_ready_present == ready_at and #report.presents == math.min(F.presents, 32)
    and report.presents[1].steps == 0 and report.presents[2].steps >= 1, 'The report has each Present and its steps.');

if os.getenv('VANTAGE_WARMUP_ESTIMATE') then
    local total = 0;
    for _, frame in ipairs(frames) do total = total + frame.ms; end
    io.write(('ESTIMATE load_event_ms=%.2f (menu fonts %.2f, Windows fonts %.2f) first_present_ms=%.2f stall_ms=%.2f '
        .. 'worst_frame_ms=%.2f largest_step_ms=%.2f presents_to_displays=%d presents_to_names=%d warmup_work_ms=%.2f\n'):format(
        F.load_ms, F.stages['fonts.menu'].total, F.stages['fonts.registration'].total, first_ms, F.load_ms + first_ms,
        worst, largest, ready_at, names_at, total));
    for index, frame in ipairs(frames) do
        io.write(('  Present %d: %.2f ms, %d steps\n'):format(index + 1, frame.ms, #frame.steps));
    end
end
return 'The warmup spreads the load over Presents and the displays wait for its art';
