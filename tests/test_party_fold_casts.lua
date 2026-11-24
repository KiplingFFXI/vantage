-- One row for a cast on several members, on Party members' timers, through vantage.lua as the game drives it. A
-- Protectra is one Protect row that counts its members, and a Haste cast on one member at a time keeps a row each.
-- Copies with no countdown fold by effect, the panel's filters go first, and the tracker's rows stay as they were.
-- You are Tester (1001), and Bob (1002) and Dave (1003) are in your party.
local L = require('live_fixture');
local app = L.start();
local hud = require('ui.hud');
local ME, BOB, DAVE = 1001, 1002, 1003;
local HASTE, PROTECT, SIGNET, MARCH = 33, 40, 253, 214;
L.listing({ { BOB, 0x401, {} }, { DAVE, 0x402, {} } });
L.frame();

-- Dave's Protectra lands on all three of you in one action. Then you cast Haste on Bob, and later on Dave.
MOCK.player.buffs = { PROTECT };
L.action(4, 128, DAVE, { { id = DAVE, rows = { { message = 230, param = PROTECT } } }, { id = BOB, rows = { { message = 230, param = PROTECT } } },
    { id = ME, rows = { { message = 230, param = PROTECT } } } });
L.frame(); L.frame(3);
L.action(4, 57, ME, { { id = BOB, rows = { { message = 230, param = HASTE } } } });
L.frame(); L.frame(25);
L.action(4, 57, ME, { { id = DAVE, rows = { { message = 230, param = HASTE } } } });
L.frame(); L.frame();
for _, id in ipairs({ BOB, DAVE }) do
    local row = L.row(id, PROTECT);
    assert(row and row.deadline and row.source == DAVE, 'Fixture: Protect on ' .. id .. ' from Dave, with a countdown.');
    assert(L.row(id, HASTE) and L.row(id, HASTE).deadline, 'Fixture: Haste on ' .. id .. '.');
end
assert(L.row(BOB, PROTECT).start == L.row(DAVE, PROTECT).start, 'Fixture: one cast stamps its rows with one moment.');
assert(L.row(BOB, HASTE).start ~= L.row(DAVE, HASTE).start, 'Fixture: the Hastes landed apart.');
assert(L.row(ME, PROTECT) and L.row(ME, PROTECT).scope == 'self', 'Fixture: Protect on you.');

local settings = app.state.settings;
local panel = settings.panels.party;
assert(panel.fold_casts == false, 'It starts off.');
local function shown(into)
    local rows = hud.filter_rows(app.state.view, panel, 'party', settings, nil, into);
    local by = {};
    for _, row in ipairs(rows) do
        local key = row.effect .. ' on ' .. (row.folded and #row.folded .. ' members' or row.entity_id);
        assert(by[key] == nil, 'Each row is there once: ' .. key);
        by[key] = row;
    end
    return by, #rows, rows;
end

local by, count = shown();
assert(count == 4 and by['40 on 1002'] and by['40 on 1003'] and by['33 on 1002'] and by['33 on 1003'], 'Off, each copy has a row: ' .. count);

panel.fold_casts = true;
by, count = shown();
assert(count == 3, 'On, the Protectra is one row and the Hastes stay two: ' .. count);
local fold = by['40 on 2 members'];
assert(fold and by['33 on 1002'] and by['33 on 1003'], 'Protect counts its two members, and each Haste keeps its row.');
assert(fold.entity_name == '2 members' and fold.name == 'Protect' and fold.scope == 'party', 'The row says how many: ' .. tostring(fold.entity_name));
assert(fold.deadline == L.row(BOB, PROTECT).deadline and fold.status == 'estimated' and fold.source == DAVE, 'It has the cast\'s time and caster.');
assert(fold ~= L.row(BOB, PROTECT) and fold ~= L.row(DAVE, PROTECT), 'It is a row of its own.');
assert(L.row(BOB, PROTECT).entity_name == 'Bob' and L.row(DAVE, PROTECT).entity_name == 'Dave' and L.row(BOB, PROTECT).folded == nil,
    'The tracker\'s rows are as they were.');
local names = {};
for _, member in ipairs(fold.folded) do names[member.entity_name] = member; end
assert(names.Bob == L.row(BOB, PROTECT) and names.Dave == L.row(DAVE, PROTECT), 'Its members are the tracker\'s own rows.');
assert(type(fold.key) == 'string' and fold.key ~= L.row(BOB, PROTECT).key and fold.key ~= L.row(DAVE, PROTECT).key, 'It has a key of its own.');
local again = shown();
assert(again['40 on 2 members'].key == fold.key, 'The key holds from one frame to the next.');

-- Hovering it says who, each with their time.
local details = hud.details(fold, MOCK.now, panel);
assert(details:find('On 2 members', 1, true) and details:find('Bob', 1, true) and details:find('Dave', 1, true), 'The hover lists them: ' .. details);
assert(details:find('From Dave', 1, true), 'And who cast it: ' .. details);
local bob_left = hud.timer_text(L.row(BOB, PROTECT), MOCK.now);
assert(bob_left ~= '' and details:find('    Bob  ' .. bob_left .. '\n', 1, true), 'Each member has their time: ' .. details);
local plain = hud.details(by['33 on 1002'], MOCK.now, panel);
assert(plain:find('On Bob', 1, true) and not plain:find('members', 1, true), 'A single row\'s hover is as it was: ' .. plain);
-- The copy command reads the same rows.
panel.enabled = true;
local text = hud.copy_text(app.state.view, settings, 'party', false, MOCK.now, nil, true);
assert(text:find('2 members', 1, true) and select(2, text:gsub('Protect', '')) == 1, 'The copy has one Protect line: ' .. text);

-- Include me brings your own copy into the same row.
panel.include_self = true;
by, count = shown();
fold = by['40 on 3 members'];
assert(count == 3 and fold and fold.entity_name == '3 members', 'With Include me, the Protect row counts you: ' .. count);
assert(fold.status == 'estimated' and fold.scope == 'party', 'It still goes by the members\' estimate.');
panel.include_self = false;

-- The filters go first: the row counts only who the panel shows, and one member left is that member's own row.
panel.members = { [BOB] = true };
by, count = shown();
assert(count == 2 and by['40 on 1002'] == L.row(BOB, PROTECT) and by['33 on 1002'], 'With only Bob ticked, his Protect is his own row: ' .. count);
panel.members = {};
panel.mine_only = true;
by, count = shown();
assert(count == 2 and by['33 on 1002'] and by['33 on 1003'], 'Only effects I cast leaves Dave\'s Protectra out: ' .. count);
panel.mine_only = false;

-- Pins and By who it is on go for a folded row: pinned it leads, and by who it is on it comes ahead of the members.
panel.sort = 'remaining';
local _, _, rows = shown();
assert(rows[#rows].folded, 'Ending soonest, Protect is last.');
panel.pinned = { [PROTECT] = true };
_, _, rows = shown();
assert(rows[1].folded, 'Pinned, it is first.');
panel.pinned = {};
panel.group_by = 'target';
_, _, rows = shown();
assert(rows[1].folded and rows[2].entity_name == 'Bob' and rows[3].entity_name == 'Dave', 'By who it is on, it comes ahead of Bob and Dave.');
panel.group_by, panel.sort = 'none', 'longest';

-- No other panel folds, whatever its save holds.
settings.panels.self_buffs.fold_casts = true;
for _, row in ipairs(hud.filter_rows(app.state.view, settings.panels.self_buffs, 'self_buffs', settings)) do assert(row.folded == nil, 'Self buffs never folds.'); end
settings.panels.self_buffs.fold_casts = nil;

-- A frame's rows are filled in place, and the folded row is kept from one frame to the next.
local list = {};
local _, _, first = shown(list);
local kept;
for _, row in ipairs(first) do if row.folded then kept = row; end end
local _, _, second = shown(list);
assert(first == list and second == list, 'The list given is the one filled.');
for _, row in ipairs(second) do if row.folded then assert(row == kept, 'The same folded row comes back.'); end end
for _ = 1, 20 do shown(list); end
-- What 200 frames of the panel's rows leave behind, which without the frame's own filters is the same with the tick
-- off as on.
local function grown()
    jit.off(); collectgarbage('collect'); collectgarbage('stop');
    local counted = collectgarbage('count');
    for _ = 1, 200 do hud.filter_rows(app.state.view, panel, 'party', settings, nil, list); end
    local more = collectgarbage('count') - counted;
    collectgarbage('restart'); jit.on();
    return more;
end
local folding = grown();
panel.fold_casts = false;
local plain_rows = grown();
panel.fold_casts = true;
assert(folding - plain_rows < 1, 'Folding a frame\'s rows makes nothing new: ' .. folding .. ' KB against ' .. plain_rows .. ' KB over 200 frames.');

-- A full frame draws it, in each layout.
panel.x, panel.y = 100, 100;
for _, mode in ipairs({ 'bars', 'expanded', 'text', 'icons' }) do
    panel.mode = mode;
    L.frame(); L.frame();
end
panel.mode = 'bars';

-- An alert marks a member's row, so the folded row that member is in gets the mark.
local warning = require('ui.theme').u32(settings.style.warning_color);
local function marks(key)
    local now_view = app.state.view;
    now_view.emphasis = key and { [key] = true } or nil;
    MOCK.imgui_calls = {};
    hud.draw(now_view, settings, MOCK.now, { shift = false });
    now_view.emphasis = nil;
    local found = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddRect' and call[4] == warning then found = found + 1; end
    end
    return found;
end
local unmarked = marks(nil);
assert(marks(L.row(DAVE, PROTECT).key) == unmarked + 1, 'An alert on Dave\'s Protect marks the folded row.');
assert(marks(L.row(BOB, HASTE).key) == unmarked + 1, 'And one on a single row marks that row, as before.');
assert(marks(L.row(ME, PROTECT).key) == unmarked, 'One on a row the panel doesn\'t hold marks nothing there.');

-- Bob gets a Protect of his own later, so he leaves the row. With one member left, it is Dave's own row again.
L.frame(5);
L.action(4, 46, DAVE, { { id = BOB, rows = { { message = 230, param = PROTECT } } } });
L.frame(); L.frame();
by, count = shown();
assert(count == 4 and by['40 on 1002'] == L.row(BOB, PROTECT) and by['40 on 1003'] == L.row(DAVE, PROTECT), 'A copy from a later cast is a row of its own: ' .. count);
panel.include_self = true;
by, count = shown();
assert(count == 4 and by['40 on 2 members'] and by['40 on 1002'], 'With Include me, Dave and you still share the first cast\'s row: ' .. count);
local pair = {};
for _, member in ipairs(by['40 on 2 members'].folded) do pair[member.entity_name] = true; end
assert(pair.Dave and pair.Tester and not pair.Bob, 'Bob isn\'t in it.');
panel.include_self = false;

-- Copies nothing was seen to put on have no countdown, and fold by effect. Two songs of one kind on each member make
-- two rows of two, never one row of four.
L.listing({ { BOB, 0x401, { PROTECT, HASTE, SIGNET, MARCH, MARCH } }, { DAVE, 0x402, { PROTECT, HASTE, SIGNET, MARCH, MARCH } } });
L.frame(); L.frame();
assert(L.row(BOB, SIGNET) and not L.row(BOB, SIGNET).deadline and not L.row(DAVE, SIGNET).start, 'Fixture: Signet with nothing seen.');
local marches = 0;
for _, row in ipairs(app.state.view.rows) do if row.effect == MARCH and row.scope == 'party' then marches = marches + 1; end end
assert(marches == 4, 'Fixture: two Marches each on Bob and Dave: ' .. marches);
panel.include = { [SIGNET] = true, [MARCH] = true };
rows = hud.filter_rows(app.state.view, panel, 'party', settings);
assert(#rows == 3, 'Signet is one row and March two: ' .. #rows);
local keys = {};
for _, row in ipairs(rows) do
    assert(not keys[row.key], 'Each folded row has its own key: ' .. tostring(row.key));
    keys[row.key] = true;
end
for _, row in ipairs(rows) do
    assert(row.folded and #row.folded == 2 and row.entity_name == '2 members' and row.deadline == nil, 'Each counts Bob and Dave, with no countdown.');
    assert(row.folded[1].entity_id ~= row.folded[2].entity_id, 'A member is in a row once.');
    local said = hud.details(row, MOCK.now, panel);
    assert(said:find('    Bob\n', 1, true) and said:find('    Dave\n', 1, true), 'With no countdown the hover gives just the names: ' .. said);
end
panel.include = {};

-- Two casters land the same effect in the same moment, each on one member. Those are two casts, so two rows.
local REFRESH = 43;
L.action(4, 109, ME, { { id = BOB, rows = { { message = 230, param = REFRESH } } } });
L.action(4, 109, DAVE, { { id = DAVE, rows = { { message = 230, param = REFRESH } } } });
L.frame(); L.frame();
assert(L.row(BOB, REFRESH).start == L.row(DAVE, REFRESH).start and L.row(BOB, REFRESH).source ~= L.row(DAVE, REFRESH).source,
    'Fixture: two Refreshes from two casters at one moment.');
panel.include = { [REFRESH] = true };
rows = hud.filter_rows(app.state.view, panel, 'party', settings);
assert(#rows == 2 and not rows[1].folded and not rows[2].folded, 'Two casters\' copies stay two rows: ' .. #rows);
panel.include = {};

-- Copy Image's icon is how many shadows are left (core/tracker.lua as_copy_image, Phoenix
-- scripts/globals/spells/enhancing_ninjutsu.lua :47-61, :119 and src/map/utils/battleutils.cpp :3149-3168). Bob has
-- four or more and Dave two, with nothing seen, so each keeps a row and the row draws their own count. With one count
-- they fold.
local COPY_IMAGE = 66;
L.listing({ { BOB, 0x401, { 446 } }, { DAVE, 0x402, { 444 } } });
L.frame(); L.frame();
assert(L.row(BOB, COPY_IMAGE) and L.row(BOB, COPY_IMAGE).icon == 446 and not L.row(BOB, COPY_IMAGE).start
    and L.row(DAVE, COPY_IMAGE) and L.row(DAVE, COPY_IMAGE).icon == 444, 'Fixture: Copy Image on Bob and Dave, with nothing seen.');
panel.include = { [COPY_IMAGE] = true };
rows = hud.filter_rows(app.state.view, panel, 'party', settings);
local pictures = {};
for _, row in ipairs(rows) do pictures[row.entity_name] = row.icon or row.effect; end
assert(#rows == 2 and not rows[1].folded and not rows[2].folded, 'Two shadow counts stay two rows: ' .. #rows);
assert(pictures.Bob == 446 and pictures.Dave == 444, 'Each row draws its own count: ' .. tostring(pictures.Bob) .. ' ' .. tostring(pictures.Dave));
L.listing({ { BOB, 0x401, { 445 } }, { DAVE, 0x402, { 445 } } });
L.frame(); L.frame();
rows = hud.filter_rows(app.state.view, panel, 'party', settings);
assert(#rows == 1 and rows[1].folded and rows[1].entity_name == '2 members' and rows[1].icon == 445, 'With one count they fold: ' .. #rows);
panel.include = {};

-- Longest remaining, the panel's own sort, goes by the time the folded row shows. Your Protect ends well before the
-- members' estimates here, so the row shows yours and sorts under Bob's Haste.
do
    local function copy(key, id, name, scope, effect, left, status, start)
        return { key = key, effect = effect, name = 'Effect ' .. effect, kind = 'buff', scope = scope, entity_id = id, entity_name = name, source = 9,
            start = start, deadline = 1000 + left, remaining = left, total = 300, status = status, present = true };
    end
    local hand = { copy('a', ME, 'Tester', 'self', PROTECT, 60, 'server', 0), copy('b', BOB, 'Bob', 'party', PROTECT, 200, 'estimated', 0),
        copy('c', DAVE, 'Dave', 'party', PROTECT, 200, 'estimated', 0), copy('d', BOB, 'Bob', 'party', HASTE, 100, 'estimated', 50) };
    panel.include_self, panel.sort = true, 'longest';
    local sorted = hud.filter_rows({ rows = hand, context = {} }, panel, 'party', settings);
    assert(#sorted == 2 and sorted[2].folded and #sorted[2].folded == 3, 'Fixture: Protect on three of you folds, and Haste stays.');
    assert(sorted[2].remaining == 60 and sorted[2].deadline == 1060, 'The folded row has the time of the copy it shows: ' .. tostring(sorted[2].remaining));
    assert(sorted[1].effect == HASTE, 'So with a minute left it sorts under a Haste with 100 seconds.');
    panel.include_self = false;
end

-- Only Party members' timers folds. Watched enemies with one cast's debuff on two mobs keeps a row for each.
do
    local function mob(id) return { key = 'mob' .. id, effect = 2, name = 'Sleep', kind = 'debuff', scope = 'enemy', entity_id = id,
        entity_name = 'Crab', source = ME, start = 10, deadline = 70, total = 60, status = 'estimated' }; end
    local watch = settings.panels.watch;
    watch.fold_casts, settings.watch_ids = true, { 501, 502 };
    local seen = hud.filter_rows({ rows = { mob(501), mob(502) }, context = {} }, watch, 'watch', settings);
    assert(#seen == 2 and not seen[1].folded, 'Watched enemies keeps both rows: ' .. #seen);
    watch.fold_casts, settings.watch_ids = nil, {};
end

-- The folding itself, on rows made by hand.
do
    local folds = require('ui.cast_folds');
    local function row(member, fields)
        local made = { key = 'k' .. member .. (fields.tag or ''), effect = 40, scope = member == 1 and 'self' or 'party', entity_id = member,
            entity_name = 'M' .. member, status = 'estimated' };
        for name, value in pairs(fields) do made[name] = value; end
        return made;
    end
    assert(#folds.apply({}) == 0, 'No rows stay none.');
    local alone = row(2, { start = 5, deadline = 50 });
    local one = folds.apply({ alone });
    assert(#one == 1 and one[1] == alone, 'One row is left as it is.');

    -- The row goes by the copy that ends first, whole: its end, its time left, how sure its time is. Yours here ends
    -- three seconds before the members' estimates, so the row goes by yours.
    local mine = row(1, { start = 5, deadline = 47, remaining = 37, total = 42, status = 'server', source = 9 });
    local a = row(2, { start = 5.4, deadline = 50, remaining = 40, total = 45, source = 9 });
    local b = row(3, { start = 5, deadline = 51, remaining = 41, total = 46, source = 9 });
    local made = folds.apply({ mine, a, b });
    assert(#made == 1 and #made[1].folded == 3 and made[1].entity_name == '3 members', 'Three copies of one cast are one row.');
    assert(made[1].deadline == 47 and made[1].remaining == 37 and made[1].total == 42 and made[1].status == 'server',
        'It goes by your copy, which ends first: ' .. tostring(made[1].deadline) .. ' ' .. tostring(made[1].remaining) .. ' ' .. tostring(made[1].status));
    assert(made[1].key == 'fold:k1', 'Its key is its first member\'s, whichever copy it goes by: ' .. tostring(made[1].key));
    -- Among the members it is the one ending first, wherever it is in the list.
    made = folds.apply({ b, a });
    assert(made[1].deadline == 50 and made[1].remaining == 40 and made[1].total == 45, 'It goes by the member ending first: ' .. tostring(made[1].deadline));
    -- Your own timer can sit a moment either side of the members' estimates. Within a second it goes by a member's.
    local near = row(1, { start = 5, deadline = 49.4, remaining = 39.4, status = 'server', source = 9 });
    made = folds.apply({ near, a, b });
    assert(made[1].deadline == 50 and made[1].status == 'estimated' and made[1].scope == 'party', 'Within a second of yours, it goes by a member\'s: ' .. tostring(made[1].deadline));
    local late = row(1, { start = 5, deadline = 58, remaining = 48, status = 'server', source = 9 });
    made = folds.apply({ late, a, b });
    assert(made[1].deadline == 50 and made[1].status == 'estimated', 'Yours ending later, it goes by a member\'s.');
    -- The members' estimates ran out with the effect still on them, so their rows have no time, and yours still does.
    local out_a = row(2, { start = 5, status = 'unknown', source = 9 });
    local out_b = row(3, { start = 5, deadline = 9, status = 'unknown', source = 9 });
    made = folds.apply({ out_a, out_b, mine });
    assert(#made == 1 and made[1].deadline == 47 and made[1].status == 'server' and made[1].remaining == 37, 'With only yours timed, it goes by yours.');
    assert(hud.timer_text(made[1], 10) ~= '', 'So the row has a countdown.');
    made = folds.apply({ out_b, a });
    assert(made[1].deadline == 50 and made[1].status == 'estimated', 'A copy whose estimate ran out isn\'t the one it goes by.');
    made = folds.apply({ mine, out_a, out_b, a });
    assert(made[1].deadline == 47 and made[1].key == 'fold:k1', 'A timed copy comes before an untimed one.');
    -- With no copy timed it goes by a member's row.
    local untimed = row(1, { status = 'unknown' });
    made = folds.apply({ untimed, row(2, { status = 'unknown' }), row(3, { status = 'unknown' }) });
    assert(#made == 1 and made[1].scope == 'party' and made[1].deadline == nil and made[1].key == 'fold:k1', 'Untimed, it goes by a member\'s row.');
    assert(mine.folded == nil and a.entity_name == 'M2' and a.key == 'k2', 'The rows it stands for aren\'t changed.');

    -- A second landing more than a second later is another cast, and so is another caster's.
    made = folds.apply({ row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 6.5, deadline = 51, source = 9 }) });
    assert(#made == 2 and not made[1].folded, 'Landings a second and a half apart stay two rows.');
    made = folds.apply({ row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 5, deadline = 50, source = 8 }) });
    assert(#made == 2 and not made[1].folded, 'Two casters stay two rows.');
    made = folds.apply({ row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 5, deadline = 50, source = 9, effect = 41 }) });
    assert(#made == 2 and not made[1].folded, 'Two effects stay two rows.');

    -- A copy with a countdown and no cast seen, as your own can be, stays apart from the ones with neither.
    local timed = row(1, { deadline = 90, status = 'server' });
    made = folds.apply({ timed, row(2, { status = 'unknown' }), row(3, { status = 'unknown' }) });
    assert(#made == 2 and made[1] == timed and #made[2].folded == 2 and made[2].deadline == nil, 'Your timed copy has its own row.');
    -- A cast seen with no time known folds by the cast, not with copies nothing was seen for.
    made = folds.apply({ row(2, { start = 5, source = 9 }), row(3, { start = 5, source = 9 }), row(4, { status = 'unknown' }) });
    assert(#made == 2 and #made[1].folded == 2 and not made[2].folded, 'A cast with no time known is its own row.');
    -- Copy Image's icon is how many shadows are left (Phoenix
    -- scripts/globals/spells/enhancing_ninjutsu.lua :47-61, :119 and src/map/utils/battleutils.cpp :3149-3168), so
    -- copies with nothing seen and other counts stay apart. Those with one count fold, the last shadow too, which has
    -- no icon of its own.
    made = folds.apply({ row(2, { effect = 66, icon = 446, status = 'unknown' }), row(3, { effect = 66, icon = 444, status = 'unknown' }),
        row(4, { effect = 66, status = 'unknown' }) });
    assert(#made == 3 and not made[1].folded and made[1].icon == 446 and made[2].icon == 444 and made[3].icon == nil,
        'Three shadow counts stay three rows: ' .. #made);
    made = folds.apply({ row(2, { effect = 66, icon = 445, status = 'unknown' }), row(3, { effect = 66, icon = 445, status = 'unknown' }) });
    assert(#made == 1 and #made[1].folded == 2 and made[1].icon == 445, 'Two copies with one count fold: ' .. #made);
    made = folds.apply({ row(2, { effect = 66, status = 'unknown' }), row(3, { effect = 66, status = 'unknown' }) });
    assert(#made == 1 and #made[1].folded == 2 and made[1].icon == nil, 'So do two last shadows: ' .. #made);

    -- Where the folded row goes: the place of its first member, with the rows around it in their order.
    local x, y, z = row(5, { start = 1, deadline = 9, source = 7, effect = 33 }), row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 5, deadline = 50, source = 9 });
    local w = row(6, { start = 2, deadline = 8, source = 7, effect = 43 });
    made = folds.apply({ x, y, w, z });
    assert(#made == 3 and made[1] == x and made[2].folded and made[3] == w, 'It takes its first member\'s place.');

    -- With a pool the folded rows are kept, and without one each call makes its own.
    local pool = {};
    local first_made = folds.apply({ row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 5, deadline = 50, source = 9 }) }, pool)[1];
    local next_made = folds.apply({ row(2, { start = 7, deadline = 60, source = 9 }), row(3, { start = 7, deadline = 60, source = 9 }) }, pool)[1];
    assert(first_made == next_made and next_made.deadline == 60 and next_made.start == 7, 'A pool\'s row is filled again.');
    local stale = folds.apply({ row(2, { start = 5, deadline = 50, source = 9, mine = true }), row(3, { start = 5, deadline = 50, source = 9 }) }, pool)[1];
    assert(stale.mine == true, 'Fixture: a field on one frame\'s row.');
    stale = folds.apply({ row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 5, deadline = 50, source = 9 }) }, pool)[1];
    assert(stale.mine == nil, 'Nothing is left over from the frame before.');
    -- A row that had three members and now has two counts two, and a row that goes by another member takes its key.
    local three = folds.apply({ row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 5, deadline = 50, source = 9 }),
        row(4, { start = 5, deadline = 50, source = 9 }) }, pool)[1];
    assert(#three.folded == 3 and three.key == 'fold:k2', 'Fixture: three members, by the first one\'s key.');
    local two = folds.apply({ row(3, { start = 5, deadline = 50, source = 9 }), row(4, { start = 5, deadline = 50, source = 9 }) }, pool)[1];
    assert(two == three and #two.folded == 2 and two.entity_name == '2 members', 'With one gone it counts two: ' .. #two.folded);
    assert(two.key == 'fold:k3', 'And it takes the key of the member it goes by now: ' .. tostring(two.key));
    local loose = folds.apply({ row(2, { start = 5, deadline = 50, source = 9 }), row(3, { start = 5, deadline = 50, source = 9 }) })[1];
    assert(loose ~= stale and loose.folded and #loose.folded == 2, 'Without a pool, a call makes its own row.');
end
return 'One row for a cast on several members: what folds, what stays apart, and what the row says';
