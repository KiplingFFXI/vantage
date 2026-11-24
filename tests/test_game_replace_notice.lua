-- On a client where Replace the game's buff icons or Replace the game's pet bar can't start, the game side hands back
-- a line each time it is asked to start again after being told to stop. When to show can now flip that on every
-- engage and disengage, so the chat line is said once and not again while it stays the same. The game sides are
-- stand-ins that act like core/game_buffs.lua and core/game_pet_bar.lua on such a client.
local BUFFS = 'Vantage could not change the game\'s buff drawing, so the game\'s buff icons stay as they are.';
local PET = 'Vantage could not change the game\'s pet bar drawing, so the game draws its own pet bar.';
local buffs_stopped, pet_stopped = nil, nil;
package.loaded['core.game_buffs'] = {
    update = function(want)
        if not want then buffs_stopped = nil; return nil; end
        if buffs_stopped then return nil; end
        buffs_stopped = true;
        return nil, BUFFS;
    end,
    release = function() return true; end,
    status = function() return { on = false, moved = 0, returned = 0 }; end,
    problem = function() return nil; end,
};
package.loaded['core.game_pet_bar'] = {
    warmup_steps = function() return { { name = 'game_pet_bar.pet_line', run = function() end } }; end,
    update = function(want)
        if not want then pet_stopped = nil; return nil; end
        if pet_stopped then return nil; end
        pet_stopped = true;
        return PET;
    end,
    release = function() return true; end,
    status = function() return { on = false }; end,
    problem = function() return nil; end,
};
local h = require('self_panel_fixture')();
local s = h.settings;
h.both({ 40, 41, 3 });
s.replace_game_buffs, s.replace_game_pet_bar = true, true;
s.pet.enabled, s.pet.show_vitals, s.pet.preview = true, true, false;
h.run(10);
local function said(text)
    local count = 0;
    for _, line in ipairs(MOCK.printed) do if line:find(text, 1, true) then count = count + 1; end end
    return count;
end
assert(said(BUFFS) == 1 and said(PET) == 1, 'Fixture: each line is said when it first fails: ' .. said(BUFFS) .. ', ' .. said(PET));
-- Each switch off and on again asks the game side to start again, and it hands back the same line each time.
for _ = 1, 3 do
    do local event = { command = '/vg hide' }; MOCK.fire('command', event); end
    h.run(2);
    do local event = { command = '/vg show' }; MOCK.fire('command', event); end
    h.run(2);
end
assert(said(BUFFS) == 1, 'The buff icons\' line is not said again: ' .. said(BUFFS));
assert(said(PET) == 1, 'The pet bar\'s line is not said again: ' .. said(PET));
return 'A client that can\'t replace the game\'s drawing says why once';
