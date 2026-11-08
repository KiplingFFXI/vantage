-- The Members line of Party members' timers and the Watching line of Watched enemy timers go by name, and an entry the game
-- has no name for now goes by words that say so, never by its id.
local h = require('panel_fixture')();
local hud = require('ui.hud');
local on_show = { TextUnformatted = true, TextWrapped = true, Checkbox = true, Button = true, Selectable = true };
local function no_id_on_show(id)
    for _, call in ipairs(MOCK.imgui_calls) do
        if on_show[call[1]] then
            -- A control's own ID after ## is not on show.
            local text = tostring(call[2]);
            local shown = text:match('^(.-)##') or text;
            assert(not shown:find(tostring(id), 1, true), 'No raw id on show: ' .. shown);
            assert(not shown:find('Member ', 1, true) and not shown:find('Entity ', 1, true) and not shown:find('unknown', 1, true), 'No stand-in on show: ' .. shown);
        end;
    end;
end;

-- Members ticks by the party's names.
h.fresh();
h.view.context.party = { { id = 7001, name = 'Aerith', scope = 'party' }, { id = 7002, name = 'Bob', scope = 'party' }, { id = 7003, scope = 'party' },
    { id = 7004, name = 'Faraway', scope = 'alliance' } };
h.on('party', 'show');
assert(not h.called('Checkbox', 'Faraway##member_7004'), 'Alliance members never show on this panel, so they aren\'t listed.');
assert(h.says('Members') and h.called('Checkbox', 'Aerith##member_7001') and h.called('Checkbox', 'Bob##member_7002'), 'Members are ticked by name.');
assert(h.called('Checkbox', 'A party member##member_7003'), 'One the list has no name for yet is still there, in words.');
no_id_on_show(7001);
no_id_on_show(7003);
h.draw('Aerith##member_7001');
h.draw();
assert(h.s.panels.party.members[7001] == true or h.s.panels.party.members['7001'] == true, 'Ticking saves the member.');
h.draw('Undo');
h.draw();
assert(next(h.s.panels.party.members) == nil, 'One Undo step.');

-- Someone ticked who isn't in the party now.
h.fresh(function(s) s.panels.party.members = { [9901] = true, [7001] = true }; end);
h.on('party', 'show');
assert(h.says('Someone not in your party now') and h.called('Button', 'Remove##member'), 'They have a line of words and a way off the list.');
no_id_on_show(9901);
h.draw('Remove##member');
h.draw();
assert(not h.says('Someone not in your party now') and h.s.panels.party.members[7001] == true, 'Remove takes that one off and leaves the others.');
assert(h.s.panels.party.members[9901] ~= true, 'And it is gone from the save.');
h.view.context.party = {};

-- With nobody to list, Members has a line that says so. It goes when someone joins, or with someone saved.
h.fresh();
h.on('party', 'show');
assert(h.says('Nobody in your party right now.'), 'Members says there is nobody to tick.');
h.view.context.party = { { id = 7001, name = 'Aerith', scope = 'party' } };
h.draw();
assert(not h.says('Nobody in your party right now.') and h.called('Checkbox', 'Aerith##member_7001'), 'The line goes when someone joins.');
h.view.context.party = {};
h.fresh(function(s) s.panels.party.members = { [9901] = true }; end);
h.on('party', 'show');
assert(not h.says('Nobody in your party right now.') and h.says('Someone not in your party now'), 'Someone saved stands in its place.');

-- Watching goes by the enemy's name while the game has it, then by what Vantage saw of it.
h.fresh(function(s) s.watch_ids = { 4101, 4102, 4103 }; end);
h.view.context.entities = { [4101] = { id = 4101, name = 'Goblin Smithy' } };
h.view.subjects = { { id = 4102, name = 'Crab' } };
h.on('watch', 'show');
assert(h.says('Goblin Smithy') and h.says('Crab') and h.says('An enemy that is out of range now'), 'Each enemy has its line, and one gone says so.');
assert(#h.calls('Button', 'Stop watching##watch') == 3, 'Each has Stop watching.');
for _, id in ipairs({ 4101, 4102, 4103 }) do no_id_on_show(id); end;
h.view.context.entities, h.view.subjects = {}, nil;

-- Stop watching takes that enemy off, by the callback the command uses.
local stopped;
local unwatch = h.app.callbacks.unwatch;
h.app.callbacks.unwatch = function(id) stopped = id; return unwatch(id); end;
h.draw('Stop watching##watch');
h.app.callbacks.unwatch = unwatch;
assert(stopped == 4101, 'Stop watching goes by its line.');
h.draw();
assert(#h.calls('Button', 'Stop watching##watch') == 2, 'Its line goes.');

-- Watch my target wants an enemy, and says so.
h.fresh();
h.on('watch', 'show');
h.draw('Watch my target##frame');
h.draw();
assert(h.says('Target an enemy first.') and #h.s.watch_ids == 0, 'With no target it says what to do.');
h.view.context.target = { id = 4200, kind = 'enemy', name = 'Bat' };
h.draw('Watch my target##frame');
h.draw();
assert(h.s.watch_ids[1] == 4200 and h.says('Bat') or h.says('An enemy that is out of range now'), 'A target goes on the list.');
h.view.context.target = nil;

-- Members is on Party members' timers only: it can't filter enemies.
h.fresh();
h.on('watch', 'show');
assert(not h.says('Members'), 'The enemy panel has no Members.');
local rows = { { effect = 1, name = 'Sleep', entity_id = 4101, scope = 'enemy', kind = 'debuff', domain = 'status', key = 'a' } };
h.s.watch_ids = { 4101 };
local p = h.s.panels.watch;
assert(#hud.filter_rows({ rows = rows, context = {} }, p, 'watch', h.s) == 1, 'A watched enemy shows, with nothing picked.');
MOCK.fire('unload');
return 'Members and watched enemies go by name, and by words once the name is gone';
