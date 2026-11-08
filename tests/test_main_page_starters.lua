-- The Starter profile row at the top of What to show on the main page: the list opens on the starter for your job and
-- marks the one in use, a pick holds until the job changes, and Apply asks for samples. Also Watched enemies' Also list
-- enemies I debuff, and the Silence notice finding a rule a starter added.
local defaults, hud, starters = require('ui.defaults'), require('ui.hud'), require('core.starters');
local window, imgui = require('ui.settings_window'), require('imgui');
local s = defaults.tidy(defaults.make());
s.window.open = true;
s.window.sections = setmetatable({}, { __index = function() return true; end });
local view = hud.sample(100);
view.context = { valid = true, job = 3, party = {}, entities = {} };
local called, revision, profiles = {}, 1, { 'Healer' };
local cb = {
    now = function() return 100; end, save = function() return true; end, changed = function() end, editor_changed = function() end,
    sound_files = function() return {}; end, reset = function() return true; end,
    profile_list = function() return profiles; end, profile_status = function() return {}; end,
    settings_revision = function() return revision; end,
    starter = function(...) called.starter = { ... }; return true; end,
};
local combo;
local real = imgui.BeginCombo;
imgui.BeginCombo = function(label, ...) real(label, ...); return label == combo; end;
local function draw(page, clicks, open)
    s.window.tab, MOCK.imgui_calls, combo = page, {}, open;
    for _, label in ipairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, cb);
    for _, label in ipairs(clicks or {}) do assert(not MOCK.clicks[label], 'Fixture: the control was on screen: ' .. label); end;
    MOCK.clicks, combo = {}, nil;
    assert(#MOCK.font_stack == 0, 'Each frame balances its fonts.');
end;
local function shown(kind, text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and tostring(call[2]):find(text, 1, true) then return call; end;
    end;
end;
local function seen(wanted)
    for _, call in ipairs(MOCK.imgui_calls) do
        if tostring(call[2]):find(wanted, 1, true) or tostring(call[3]):find(wanted, 1, true) then return true; end;
    end;
    return false;
end;
local function picked()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'BeginCombo' and call[2] == '##main_starter' then return call[3]; end;
    end;
end;

-- With no job read yet it goes by Melee.
view.context.job = nil;
draw('Home');
assert(picked() == 'Melee', 'With no job it opens on Melee.');
view.context.job = 3;

-- It opens on the starter for your job, says who it's for, and the first thing under What to show is this row.
draw('Home');
assert(picked() == 'Healer', 'WHM opens on Healer: ' .. tostring(picked()));
assert(shown('Button', 'Apply##main_starter') and not shown('Button', 'Save as a profile##main_starter'), 'It has Apply. Apply then Save as new keeps it.');
assert(not seen(starters.by_id.healer.about), 'What the starter does is no line of its own.');
local item_hovered = imgui.IsItemHovered;
imgui.IsItemHovered = function() return true; end;
draw('Home');
imgui.IsItemHovered = item_hovered;
assert(seen(starters.by_id.healer.about), 'Pointing at the list says what the starter does.');
-- Every job opens on its own.
for job, name in pairs({ [1] = 'Melee', [7] = 'Tank', [10] = 'Support', [4] = 'Crowd control', [15] = 'Pet' }) do
    view.context.job = job;
    draw('Home');
    assert(picked() == name, 'Job ' .. job .. ' opens on ' .. name);
end;
view.context.job = 3;
draw('Home');
assert(picked() == 'Healer');
-- Zoning reads no job for a moment, which isn't a change of job.
view.context.job = nil;
draw('Home');
assert(picked() == 'Healer', 'It keeps the job it knew.');
view.context.job = 3;

-- All six are on the list, and a pick holds through later frames, until the job changes.
draw('Home', nil, '##main_starter');
for _, entry in ipairs(starters.list) do assert(shown('Selectable', entry.name .. '##' .. entry.id), entry.name .. ' is on the list.'); end;
draw('Home', { 'Support##support' }, '##main_starter');
draw('Home');
assert(picked() == 'Support', 'A pick holds.');
draw('Home');
assert(picked() == 'Support', 'And holds.');
view.context.job = nil;
draw('Home');
assert(picked() == 'Support', 'It holds while no job is read.');
view.context.job = 3;
draw('Home');
assert(picked() == 'Support', 'And when the same job comes back.');
assert(not called.starter and s.panels.party.enabled == false, 'A pick changes nothing until Apply.');
view.context.job = 1;
draw('Home');
assert(picked() == 'Melee', 'A job change goes back to the starter for that job.');
view.context.job = 3;
draw('Home');
assert(picked() == 'Healer');

-- Apply asks for samples.
draw('Home', { 'Apply##main_starter' });
assert(called.starter[1] == 'healer' and called.starter[2] == true, 'Apply goes through the callback with samples.');
local function at(text)
    local first, times = nil, 0;
    for index, call in ipairs(MOCK.imgui_calls) do
        if call[1] ~= 'CalcTextSize' and tostring(call[2]):find(text, 1, true) then first, times = first or index, times + 1; end;
    end;
    return first, times;
end;
-- The note sits under the row, so nothing above the button moves, and it says where the samples end.
local SAMPLES = 'Its displays show samples until you press End samples, under Moving.';
draw('Home');
local line, times = at(SAMPLES);
assert(times == 1 and line > at('Apply##main_starter'), 'Under the button.');
local real_clock = os.clock;
os.clock = function() return real_clock() + 9; end;
draw('Home');
os.clock = real_clock;
assert(not seen(SAMPLES), 'The note goes after 8 seconds.');
-- While samples show, the button under Moving ends them.
s.preview, revision = true, revision + 1;
draw('Home');
line, times = at('End samples##main');
assert(times == 1 and line > at('Unlock all##main'), 'Under Moving.');
s.preview, revision = false, revision + 1;
-- A refused Apply says why.
cb.starter = function() return false, 'It would not apply.'; end;
draw('Home', { 'Apply##main_starter' });
draw('Home');
assert(seen('It would not apply.') and not seen(SAMPLES), 'It says why, and makes no claim.');
cb.starter = function(...) called.starter = { ... }; return true; end;

-- The one your settings match is marked, in the list and in the box, and the mark goes with the change.
for key, value in pairs(starters.apply(s, 'Tank')) do s[key] = value; end;
revision = revision + 1;
view.context.job = 7;
draw('Home');
assert(picked() == 'Tank (in use)', 'The box marks it: ' .. tostring(picked()));
draw('Home', nil, '##main_starter');
assert(shown('Selectable', 'Tank (in use)##tank') and not shown('Selectable', 'Melee (in use)'), 'The list marks it alone.');
s.panels.target.enabled = false;
revision = revision + 1;
draw('Home');
assert(picked() == 'Tank', 'Turning a display off takes the mark off.');
-- It's worked out when something changes, not every frame.
local real_matching, counted = starters.matching, 0;
starters.matching = function(...) counted = counted + 1; return real_matching(...); end;
draw('Home'); draw('Home'); draw('Home');
assert(counted == 0, 'Nothing changed, so nothing is worked out.');
revision = revision + 1;
draw('Home'); draw('Home');
assert(counted == 1, 'A change works it out once.');
-- Undo hands the window a new table at the same count.
local swapped = defaults.copy(s);
window.draw(swapped, view, cb);
assert(counted == 2, 'New settings are worked out again.');
starters.matching = real_matching;
view.context.job = 3;
draw('Home');

-- The row has narrow room too: Apply drops under the list when it can't fit its longest name beside it.
local function list_width()
    local width;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextItemWidth' then width = call[2]; end;
        if call[1] == 'BeginCombo' and call[2] == '##main_starter' then return width; end;
    end;
end;
draw('Home');
assert(list_width() < -1, 'With room Apply sits beside the list: ' .. tostring(list_width()));
MOCK.content_width = 280;
draw('Home');
assert(list_width() == -1 and picked() and shown('Button', 'Apply##main_starter'), 'Narrow, the list takes the line.');
MOCK.content_width = nil;

-- Starters and samples aren't on Profiles.
draw('Profiles');
for _, label in ipairs({ 'Starter layouts', 'Starter layout', 'Preview starter', 'Apply starter', 'Preview pane' }) do
    assert(not shown('Button', label) and not shown('CollapsingHeader', label) and not shown('BeginCombo', label) and not shown('TextUnformatted', label),
        label .. ' is not on Profiles.');
end;

-- The tick is on Watched enemies and no other panel, under its Show tab.
local panels = require('ui.panel_frame');
local function ticks(id)
    panels.open(id, 'show');
    draw('Display');
    return shown('Checkbox', 'Also list enemies I debuff') ~= nil;
end;
assert(ticks('watch'), 'Watched enemies has the tick.');
assert(s.panels.watch.list_debuffed == false);
draw('Display', { 'Also list enemies I debuff##frame' });
assert(s.panels.watch.list_debuffed == true, 'It sets the option.');
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party' }) do
    assert(not ticks(id), id .. ' has no such tick.');
end;

-- A search goes straight to the tick, whichever panel was open, and finds the row and the notice by other words.
local function finds(query, page, label)
    for _, result in ipairs(window.search(query)) do
        if result.tab == page and result.label == label then return result; end;
    end;
end;
for _, query in ipairs({ 'preset', 'presets', 'Starter profile', 'Starter layouts' }) do
    assert(finds(query, 'Home', 'Starter profile'), query .. ' finds the row.');
end;
assert(finds('silenced', 'Display', 'Silence notice'), 'silenced finds the notice.');
local topic = 'Watched enemies: list the ones you debuff';
assert(finds('debuff enemies', 'Display', topic) and finds('crowd control', 'Display', topic), 'It finds the topic.');
panels.open('spell_recasts', 'filters');
local real_input, typing = imgui.InputTextWithHint, 'debuff enemies';
imgui.InputTextWithHint = function(label, hint, value, ...)
    real_input(label, hint, value, ...);
    if label == '##find_settings' and typing then value[1], typing = typing, nil; return true; end;
    return false;
end;
draw('Home');
draw('Home');
local result;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Selectable' and tostring(call[2]):find(topic, 1, true) then result = call[2]; end;
end;
assert(result, 'The topic is on the list.');
draw('Home', { result });
imgui.InputTextWithHint = real_input;
assert(s.window.tab == 'Display', 'It opens the panels.');
draw('Display');
assert(shown('Checkbox', 'Also list enemies I debuff'), 'It opens on the tick.');

-- The Silence notice finds the rule a starter added instead of adding a second.
local silent = starters.apply(s, 'Tank');
for key, value in pairs(silent) do s[key] = value; end;
assert(#s.alerts.rules == 1, 'Fixture: Tank adds Silenced.');
panels.open('notices', 'show');
draw('Display', { 'Silence notice##frame' });
assert(#s.alerts.rules == 1 and s.alerts.rules[1].name == 'Silenced', 'One rule.');
-- A starter's Sleep ending goes for anything, so the Sleep reminder finds that instead of doubling it.
local slept = starters.apply(s, 'Crowd control');
for key, value in pairs(slept) do s[key] = value; end;
assert(#s.alerts.rules == 2 and s.alerts.rules[2].scope == 'all', 'Fixture: Crowd control adds Sleep ending.');
draw('Display', { 'Sleep reminder##frame' });
assert(#s.alerts.rules == 2, 'No second Sleep ending.');
s.alerts.rules[2].scope = 'party';
draw('Display', { 'Sleep reminder##frame' });
assert(#s.alerts.rules == 3 and s.alerts.rules[3].scope == 'target', 'One for another scope is still the player\'s own.');
return true;
