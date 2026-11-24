-- Replace the game's buff icons looks for seven routines in the client. Each search can pass over the whole client,
-- so all seven in the frame that first replaces the icons is a stall of tens of milliseconds. They are warmup steps
-- instead (core/warmup.lua), one pattern a step, asked for once the tick is on, and the game draws its own icons until
-- they have run. Each step keeps what it found, or why it found nothing, so the replacement then starts, or says why it
-- can't, without searching again.
local game_buffs = require('core.game_buffs');
local ORDER = { 'icon_paint', 'timer_paint', 'icon_draw', 'timer_draw', 'menu_move', 'rebuild', 'registry' };

-- The steps: one for each pattern, in the order they are looked for, each asking the client once.
local asked = {};
game_buffs._set_platform({ find = function(name) asked[#asked + 1] = name; return 0x400000 + #asked; end });
local steps = game_buffs.warmup_steps();
assert(#steps == #ORDER, 'One step for each of the seven patterns: ' .. #steps);
for index, step in ipairs(steps) do
    assert(step.name == 'game_buffs.' .. ORDER[index] and type(step.run) == 'function', 'Step ' .. index .. ' is ' .. tostring(step.name));
    step.run();
    assert(#asked == index and asked[index] == ORDER[index], 'It looks for ' .. ORDER[index] .. ' and nothing else.');
end
for _, step in ipairs(steps) do step.run(); end
assert(#asked == #ORDER, 'A step that has run does nothing when run again.');
-- A client that can't be reached: the steps do nothing, and nothing is raised.
game_buffs._set_platform(nil);
for _, step in ipairs(game_buffs.warmup_steps()) do step.run(); end
assert(game_buffs.update(true) == nil and game_buffs.problem() ~= nil, 'With no client to reach the replacement says why it is off, as before.');
game_buffs._set_platform(nil);
-- A search that fails doesn't stop the others, or the load.
local tried = 0;
game_buffs._set_platform({ find = function(name) tried = tried + 1; if name == 'icon_draw' then error('Search failed', 0); end return 0x400000; end });
local failed = 0;
for _, step in ipairs(game_buffs.warmup_steps()) do
    local ok = pcall(step.run);
    if not ok then failed = failed + 1; end
end
assert(tried == #ORDER and failed == 1, 'Each pattern is tried, and one failure is that step\'s alone: ' .. tried .. ', ' .. failed);
game_buffs._set_platform(nil);

-- In the addon: with the tick off nothing is searched. Ticked, the searches run before the game's icons are replaced,
-- and only once.
local ran, wants = {}, {};
package.loaded['core.game_buffs'] = {
    warmup_steps = function()
        local list = {};
        for index, name in ipairs(ORDER) do
            list[index] = { name = 'game_buffs.' .. name, run = function() ran[#ran + 1] = name; end };
        end
        return list;
    end,
    update = function(want) wants[#wants + 1] = { want = want, searched = #ran }; return nil; end,
    release = function() return true; end,
    status = function() return { on = false, moved = 0, returned = 0 }; end,
    problem = function() return nil; end,
};
local h = require('self_panel_fixture')();
-- The load event lists the warmup's steps.
MOCK.fire('load');
h.app.refresh(MOCK.now);
local s = h.app.state.settings;
s.party_ui.enabled = false;
for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs' or id == 'self_debuffs'; end
h.both({ 40, 41, 3 });
h.run(5);
assert(s.replace_game_buffs == false and #ran == 0, 'With the tick off no client search is made: ' .. #ran);
for _, call in ipairs(wants) do assert(call.want == false, 'And the game draws its own icons.'); end
s.replace_game_buffs = true;
h.run(10);
assert(#ran == #ORDER, 'Ticked, each pattern is searched once: ' .. #ran);
local first;
for _, call in ipairs(wants) do if call.want == true then first = first or call; end end
assert(first and first.searched == #ORDER, 'The game\'s icons are replaced only after every search has run: ' .. tostring(first and first.searched));
assert(wants[#wants].want == true, 'And they stay replaced.');
s.replace_game_buffs = false;
h.run(3);
s.replace_game_buffs = true;
h.run(5);
assert(#ran == #ORDER and wants[#wants].want == true, 'Ticked again, nothing is searched again.');
return 'The buff icon searches are warmup steps';
