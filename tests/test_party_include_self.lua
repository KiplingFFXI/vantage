-- Include me on Party members' timers, through vantage.lua as the game drives it. Off, the panel holds only the other
-- members' effects. On, your own are there too under your name, and the panel's filters go for them as for anyone's.
-- You are Tester (1001), and Bob (1002) and Dave (1003) are in your party.
local L = require('live_fixture');
local app = L.start();
local hud = require('ui.hud');
local ME, BOB, DAVE = 1001, 1002, 1003;
local HASTE, REFRESH = 33, 43;
L.listing({ { BOB, 0x401, {} }, { DAVE, 0x402, {} } });
L.frame();

-- You cast Haste on Bob and on yourself, and Dave casts Refresh on you.
L.action(4, 57, ME, { { id = BOB, rows = { { message = 230, param = HASTE } } } });
MOCK.player.buffs = { HASTE, REFRESH };
L.action(4, 57, ME, { { id = ME, rows = { { message = 230, param = HASTE } } } });
L.action(4, 109, DAVE, { { id = ME, rows = { { message = 230, param = REFRESH } } } });
L.frame(); L.frame();
local mine, theirs = L.row(ME, HASTE), L.row(ME, REFRESH);
assert(mine and mine.scope == 'self' and mine.mine == true, 'Fixture: your Haste on yourself is yours.');
assert(theirs and theirs.scope == 'self' and theirs.mine ~= true, 'Fixture: Dave\'s Refresh on you isn\'t.');
assert(L.row(BOB, HASTE) and L.row(BOB, HASTE).scope == 'party', 'Fixture: your Haste on Bob.');

local settings = app.state.settings;
local panel = settings.panels.party;
assert(panel.include_self == false, 'It starts off.');
-- The panel's rows as 'effect on id'.
local function shown(key)
    local out, count = {}, 0;
    for _, row in ipairs(hud.filter_rows(app.state.view, panel, key or 'party', settings)) do
        out[row.effect .. ' on ' .. row.entity_id], count = row, count + 1;
    end
    return out, count;
end
local rows, count = shown();
assert(count == 1 and rows['33 on 1002'], 'Off, only Bob\'s Haste shows: ' .. count);

panel.include_self = true;
rows, count = shown();
assert(count == 3 and rows['33 on 1002'] and rows['33 on 1001'] and rows['43 on 1001'], 'On, your Haste and Refresh show too: ' .. count);
assert(rows['33 on 1001'].entity_name == 'Tester', 'Your rows go by your name: ' .. tostring(rows['33 on 1001'].entity_name));
assert(rows['33 on 1001'] == mine, 'They are the tracker\'s own rows, not copies.');

-- The self panels keep yours either way, and no other panel takes them.
local _, own = shown('self_buffs');
assert(own == 2, 'Self buffs still shows both: ' .. own);
for _, key in ipairs({ 'target', 'watch', 'self_debuffs' }) do
    local _, other = shown(key);
    assert(other == 0, key .. ' takes none of them: ' .. other);
end
for _, key in ipairs({ 'self_buffs', 'target', 'watch' }) do
    assert(settings.panels[key].include_self == nil, 'Only Party members\' timers has the setting, not ' .. key .. '.');
end

-- The panel's filters go for your rows as for a member's.
panel.mine_only = true;
rows, count = shown();
assert(count == 2 and rows['33 on 1001'] and rows['33 on 1002'] and not rows['43 on 1001'],
    'Only effects I cast keeps your own Haste and drops Dave\'s Refresh: ' .. count);
panel.mine_only = false;
panel.include = { [REFRESH] = true };
rows, count = shown();
assert(count == 1 and rows['43 on 1001'], 'Show only goes for your rows: ' .. count);
panel.include = {};
panel.exclude = { [HASTE] = true };
rows, count = shown();
assert(count == 1 and rows['43 on 1001'], 'Hide here goes for your rows: ' .. count);
panel.exclude = {};

-- Members: ticking Bob alone leaves you out, and ticking yourself brings you back.
panel.members = { [BOB] = true };
rows, count = shown();
assert(count == 1 and rows['33 on 1002'], 'Members with only Bob ticked shows only Bob: ' .. count);
panel.members = { [BOB] = true, [ME] = true };
rows, count = shown();
assert(count == 3, 'Ticking yourself too shows your rows: ' .. count);
panel.members = { [ME] = true };
rows, count = shown();
assert(count == 2 and not rows['33 on 1002'], 'Ticking only yourself shows only yours: ' .. count);
panel.members = {};

-- Off again, they go, and a tick left on Members for you hides nobody else.
panel.include_self = false;
panel.members = { [ME] = true };
rows, count = shown();
assert(count == 1 and rows['33 on 1002'], 'Off, with only you ticked, Bob\'s Haste still shows: ' .. count);
panel.members = { [tostring(ME)] = true };
rows, count = shown();
assert(count == 1 and rows['33 on 1002'], 'The same goes for your id kept as text: ' .. count);
-- Ticking someone else still picks them.
panel.members = { [ME] = true, [DAVE] = true };
rows, count = shown();
assert(count == 0, 'Off, with you and Dave ticked, Dave is all it shows, and he has nothing: ' .. count);
panel.members = {};
rows, count = shown();
assert(count == 1 and rows['33 on 1002'], 'Off, Bob\'s Haste is all there is again: ' .. count);

-- The copy command reads the same rows.
panel.include_self, panel.enabled = true, true;
local text = hud.copy_text(app.state.view, settings, 'party', false, MOCK.now, nil, true);
assert(text:find('Tester', 1, true) and text:find('Bob', 1, true), 'The copy names you and Bob: ' .. text);

-- The samples have an effect of your own, so the tick shows something there.
local sample = hud.sample(1000);
local function sampled()
    local yours = 0;
    for _, row in ipairs(hud.filter_rows(sample, panel, 'party', settings)) do if row.scope == 'self' then yours = yours + 1; end end
    return yours;
end
assert(sampled() > 0, 'With the tick, the samples show your own effects on the panel.');
panel.include_self = false;
assert(sampled() == 0, 'Without it, they don\'t.');
return 'Include me: your own effects on Party members\' timers, with its filters';
