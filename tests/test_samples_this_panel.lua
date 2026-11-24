-- A timer panel's Show samples is its own: its rows turn to samples while the others stay live. Show samples on the main
-- page still samples them all, and turning one off then leaves the others on. Home says while samples show and ends
-- them there. A panel's samples stay out of profiles and shared files, and its Show off ends them.
local h = require('panel_fixture')();
local defaults, hud = require('ui.defaults'), require('ui.hud');

-- The words each panel's window drew.
local function texts()
    local out, window = {}, nil;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then window = call[2];
        elseif call[1] == 'draw:AddText' and window then
            local text = MOCK.drawn[call][6];
            if type(text) == 'string' then out[window] = (out[window] or '') .. '|' .. text; end;
        end;
    end;
    return out;
end;
local live = { valid = true, context = { id = 1001, valid = true, target = { id = 16781313, name = 'Training Crab' } }, rows = {} };
local function draw(s)
    MOCK.imgui_calls = {};
    hud.draw(live, s, 1000, {});
    return texts();
end;

-- One panel sampled: its heading says Sample and it has the samples' rows, the other panel stays live and empty.
local s = defaults.tidy(defaults.make());
s.enabled = true;
for id, panel in pairs(s.panels) do
    panel.enabled, panel.mode, panel.show_heading, panel.empty = id == 'self_buffs' or id == 'target', 'bars', true, 'show';
end;
defaults.sample_panel(s, 'self_buffs', true);
assert(s.panels.self_buffs.preview and not s.preview and defaults.sampled(s, 'self_buffs') and not defaults.sampled(s, 'target'),
    'Its own Show samples samples only it.');
local drawn = draw(s);
local buffs, target = drawn['##vantage_self_buffs'] or '', drawn['##vantage_target'] or '';
assert(buffs:find('Self buffs  /  Sample', 1, true), 'The sampled panel says so: ' .. buffs);
assert(target:find('Target timers', 1, true) and not target:find('Sample', 1, true), 'The other panel stays live: ' .. target);
assert(hud.copy_text(live, s, 'self_buffs', false, 1000) ~= '' and hud.copy_text(live, s, 'target', false, 1000) == '',
    'Copying a panel copies what it shows.');

-- Show samples on the main page samples every panel. Turning one off leaves the others on.
defaults.samples_off(s);
assert(not defaults.any_sampled(s), 'End samples ends them all.');
defaults.samples_on(s);
assert(s.preview and defaults.sampled(s, 'target') and defaults.sampled(s, 'self_buffs'), 'The main page samples every panel.');
defaults.sample_panel(s, 'target', false);
assert(not s.preview and not defaults.sampled(s, 'target') and defaults.sampled(s, 'self_buffs') and not defaults.sampled(s, 'party'),
    'Turning one off leaves the others that are on with theirs, and a panel that\'s off takes none.');
drawn = draw(s);
assert((drawn['##vantage_self_buffs'] or ''):find('Sample', 1, true) and not (drawn['##vantage_target'] or ''):find('Sample', 1, true),
    'And they draw that way.');

-- Samples on a self panel are no stand-in for the game's buff icons, samples elsewhere are.
defaults.samples_off(s);
s.replace_game_buffs, s.panels.self_debuffs.enabled = true, true;
defaults.sample_panel(s, 'target', true);
assert(defaults.game_buffs_replaced(s) == true, 'Samples on Target timers leave the game\'s icons replaced.');
defaults.sample_panel(s, 'self_debuffs', true);
local replaced, why = defaults.game_buffs_replaced(s);
assert(replaced == false and why == 'While samples show, the game draws its own buff icons.', 'Samples on a self panel don\'t.');

-- Profiles and shared files keep no panel's samples.
local captured = require('core.profiles').capture(s);
assert(captured.panels.target.preview == nil, 'A profile keeps no panel\'s samples.');

-- The header: its tick is this panel's samples, refused while the panel is off, and Show off ends them.
h.fresh(function(saved) saved.enabled, saved.panels.self_buffs.enabled, saved.panels.target.enabled = true, true, true; end);
h.on('self_buffs', 'show');
h.draw('Show samples##frame');
assert(h.s.panels.self_buffs.preview and not h.s.preview and not h.s.panels.target.preview and #h.app.state.history == 1,
    'The header samples this panel only, as one Undo step.');
h.on('target', 'show');
assert(h.calls('Checkbox', 'Show samples##frame')[1][3][1] == false, 'Another panel\'s tick shows its own samples, off.');
h.on('self_buffs', 'show');
h.draw('On##frame_display');
assert(not h.s.panels.self_buffs.enabled and not h.s.panels.self_buffs.preview, 'Show off ends its samples.');
h.draw('Show samples##frame');
h.draw();
assert(not h.s.panels.self_buffs.preview and h.says('Turn a display on first.'), 'Off, its samples are refused, and it says why.');

-- Home says while samples show, by name for one display, and ends them there in one Undo step.
h.fresh(function(saved) saved.enabled, saved.panels.self_buffs.enabled, saved.panels.self_buffs.preview = true, true, true; end);
h.draw();
assert(h.says('Samples show on Self buffs.'), 'Home names the one display with samples.');
assert(not h.called('Button', 'Show samples##main'), 'Show samples waits while samples show.');
h.s.rolls.enabled, h.s.rolls.preview = true, true;
h.bump();
h.draw();
assert(h.says('Samples show on 2 displays.'), 'Home counts several.');
h.draw('End samples##main');
assert(not h.s.panels.self_buffs.preview and not h.s.rolls.preview and #h.app.state.history == 1, 'End samples ends them all, as one step.');
h.draw();
assert(not h.says('Samples show on 2 displays.') and not h.says('Samples show on Self buffs.') and h.called('Button', 'Show samples##main'),
    'Then the line goes and Show samples is back.');
MOCK.fire('unload');
return 'A timer panel\'s Show samples is its own, and Home says while any show';
