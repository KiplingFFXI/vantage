-- Countdown text and blink for every display at once. A pick writes each display's own keys and nothing else, what the
-- rows show is read back from those keys, and a pick over displays that differ asks first and names the ones it changes.
local defaults, look = require('ui.defaults'), require('ui.shared_look');
local custom, copy = require('core.customization'), require('core.store').copy;
local imgui = require('imgui');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');

local status = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' };
local recasts = { 'spell_recasts', 'ability_recasts', 'item_recasts', 'recasts' };
local function fresh() return defaults.tidy(defaults.make()); end;
local function holders(s)
    local out = {};
    for _, id in ipairs(status) do out[id] = s.panels[id]; end;
    for _, id in ipairs(recasts) do out[id] = s.panels[id]; end;
    out.party_ui, out.overhead, out.rolls, out.pet = s.party_ui.effects, s.overhead, s.rolls, s.pet;
    return out;
end;
local function count(list) local total = 0; for _ in pairs(list) do total = total + 1; end; return total; end;
-- Every leaf that differs, as a sorted list of paths.
local function walk(a, b, path, out)
    local keys = {};
    for key in pairs(a) do keys[key] = true; end;
    for key in pairs(b) do keys[key] = true; end;
    for key in pairs(keys) do
        local left, right, here = a[key], b[key], path .. '.' .. tostring(key);
        if type(left) == 'table' and type(right) == 'table' then walk(left, right, here, out);
        elseif left ~= right then out[#out + 1] = here; end;
    end;
    return out;
end;
local function differences(a, b) local out = walk(a, b, '', {}); table.sort(out); return out; end;
-- The paths of one key on the displays named.
local function paths(key, ids)
    local out = {};
    for _, id in ipairs(ids) do
        local base = id == 'party_ui' and '.party_ui.effects' or (id == 'overhead' or id == 'rolls' or id == 'pet') and '.' .. id or '.panels.' .. id;
        out[#out + 1] = base .. '.' .. key;
    end;
    table.sort(out);
    return out;
end;
local function joined(...)
    local out = {};
    for _, list in ipairs({ ... }) do for _, entry in ipairs(list) do out[#out + 1] = entry; end; end;
    return out;
end;
local function same(a, b) return table.concat(a, ' ') == table.concat(b, ' '); end;
local every = joined(status, recasts, { 'party_ui', 'overhead', 'rolls', 'pet' });
local blinking = joined(status, { 'party_ui', 'overhead', 'pet' });
assert(count(holders(fresh())) == 13 and #every == 13, 'Fixture: thirteen displays hold countdowns.');

-- A fresh install reads Usual, with one value for Bold, Shadow, Outline color and blink.
local s = fresh();
assert(look.outline(s) == 'usual' and look.bold(s) == false and look.shadow(s) == true, 'Fresh: Usual, not bold, shadow on.');
assert(look.blink(s) == true and look.blink_seconds(s) == 15 and custom.equal(look.outline_color(s), { 0, 0, 0, 1 }), 'Fresh: blinks at 15 seconds, black outline.');

-- Each choice is read back from the keys.
look.set_outline(s, 'every');
for id, holder in pairs(holders(s)) do assert(holder.countdown_outline == true, 'Every display: ' .. id); end;
assert(look.outline(s) == 'every', 'Every display reads back.');
look.set_outline(s, 'none');
for id, holder in pairs(holders(s)) do assert(holder.countdown_outline == false, 'None: ' .. id); end;
assert(look.outline(s) == 'none', 'None reads back.');
look.set_outline(s, 'usual');
assert(custom.equal(s, fresh()) and look.outline(s) == 'usual', 'Usual puts each display back as a fresh install has it.');
-- Usual is the status timers and the party list outlined, and the rest not.
for _, id in ipairs(joined(status, { 'party_ui' })) do assert(holders(s)[id].countdown_outline == true, 'Usual outlines ' .. id); end;
for _, id in ipairs(joined(recasts, { 'overhead', 'rolls', 'pet' })) do assert(holders(s)[id].countdown_outline == false, 'Usual leaves ' .. id); end;

-- One display off the pattern is Mixed, and so is any key that differs, with nothing written for reading it.
for id, holder in pairs(holders(s)) do
    local before = copy(s);
    holder.countdown_outline = not holder.countdown_outline;
    assert(look.outline(s) == 'mixed', 'One display off the pattern reads Mixed: ' .. id);
    holder.countdown_outline = not holder.countdown_outline;
    holder.countdown_bold = true;
    assert(look.bold(s) == nil, 'Bold that differs has no one value: ' .. id);
    holder.countdown_bold = false;
    holder.countdown_shadow = false;
    assert(look.shadow(s) == nil, 'Shadow that differs has no one value: ' .. id);
    holder.countdown_shadow = true;
    holder.countdown_outline_color = { 1, 0, 0, 1 };
    assert(look.outline_color(s) == nil, 'A color that differs has no one value: ' .. id);
    assert(custom.equal(look.first_outline_color(s), id == 'self_buffs' and { 1, 0, 0, 1 } or { 0, 0, 0, 1 }), 'The swatch has a color to start from.');
    holder.countdown_outline_color = { 0, 0, 0, 1 };
    assert(custom.equal(s, before), 'Reading writes nothing: ' .. id);
end;
-- A recast panel and the Phantom Roll don't blink, so what they hold is no difference. The pet's icons do.
s.panels.spell_recasts.blink_icons, s.rolls.blink_icons = false, false;
assert(look.blink(s) == true, 'Only the displays that blink count.');
s.pet.blink_icons = false;
assert(look.blink(s) == nil, 'The pet is one of them.');
s = fresh();
s.overhead.blink_seconds, s.party_ui.effects.blink_icons = 30, false;
assert(look.blink_seconds(s) == nil and look.blink(s) == nil and look.first_blink_seconds(s) == 15, 'Blink that differs has no one value.');

-- A pick writes exactly the display keys, on the displays that hold them.
for _, case in ipairs({
    { 'bold', function(t) look.set_bold(t, true); end, paths('countdown_bold', every) },
    { 'shadow', function(t) look.set_shadow(t, false); end, paths('countdown_shadow', every) },
    { 'outline, every display', function(t) look.set_outline(t, 'every'); end, paths('countdown_outline', joined(recasts, { 'overhead', 'rolls', 'pet' })) },
    { 'outline, none', function(t) look.set_outline(t, 'none'); end, paths('countdown_outline', joined(status, { 'party_ui' })) },
    { 'blink', function(t) look.set_blink(t, false); end, paths('blink_icons', blinking) },
    { 'blink seconds', function(t) look.set_blink_seconds(t, 40); end, paths('blink_seconds', blinking) },
}) do
    local before, after = fresh(), fresh();
    case[2](after);
    local changed = differences(before, after);
    assert(same(changed, case[3]), 'The pick writes only its keys: ' .. case[1] .. ': ' .. table.concat(changed, ' '));
end;
local before, after = fresh(), fresh();
look.set_outline_color(after, { 1, 0, 0, 1 });
local colors = {};
for _, path in ipairs(paths('countdown_outline_color', every)) do colors[#colors + 1] = path .. '.1'; end;
table.sort(colors);
assert(same(differences(before, after), colors), 'A color writes each display\'s color.');
assert(after.panels.self_buffs.countdown_outline_color ~= after.pet.countdown_outline_color, 'Each display has its own copy.');

-- The question names what changes, with the four recast panels said once.
s = fresh();
s.rolls.countdown_outline, s.pet.countdown_outline = true, true;
assert(look.outline(s) == 'mixed', 'Fixture: Mixed.');
assert(look.changes_outline(s, 'every') == 'Recasts, Overhead icons', 'Named: ' .. look.changes_outline(s, 'every'));
s.panels.item_recasts.countdown_outline = true;
assert(look.changes_outline(s, 'every') == 'Spell recasts, Ability recasts, Recasts (one panel), Overhead icons', 'Not every recast panel: each by name.');
assert(look.changes_outline(s, 'none') == 'Self buffs, Self debuffs, Target timers, Party members\' timers, Watched enemy timers, Item recasts, Party list buffs, Phantom Roll, Pet',
    'None names what has one: ' .. look.changes_outline(s, 'none'));
s = fresh();
s.overhead.countdown_bold = true;
assert(look.changes_bold(s, false) == 'Overhead icons', 'Named: ' .. look.changes_bold(s, false));
s = fresh();
s.overhead.blink_icons = false;
assert(look.changes_blink(s, false) == 'Self buffs, Self debuffs, Target timers, Party members\' timers, Watched enemy timers, Party list buffs, Pet', 'Only displays that blink are named.');
assert(look.changes_blink(s, true) == 'Overhead icons', 'Named: ' .. look.changes_blink(s, true));
s.panels.watch.blink_seconds = 20;
assert(look.changes_blink_seconds(s, 20) ~= '' and look.changes_blink_seconds(s, 15) == 'Watched enemy timers', 'When blinking starts is named too.');

-- The rows in the real window.
local combo, slid, colored;
imgui.BeginCombo = function(label, preview)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'BeginCombo', label, preview };
    return label == combo;
end;
imgui.SliderFloat = function(label, value, low, high, format)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'SliderFloat', label, value[1], format };
    if slid and slid[1] == label then value[1], slid = slid[2], nil; return true; end;
    return false;
end;
imgui.ColorEdit4 = function(label, value)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'ColorEdit4', label };
    if colored and colored[1] == label then
        for index = 1, 4 do value[index] = colored[2][index]; end;
        colored = nil;
        return true;
    end;
    return false;
end;
local function frame(click, opened)
    combo, MOCK.imgui_calls = opened, {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(app.state.settings, { rows = {}, context = { valid = false } }, app.callbacks);
    if click then assert(not MOCK.clicks[click], 'The control is on screen: ' .. click); end;
    MOCK.clicks = {};
    assert(#MOCK.font_stack == 0);
end;
local function open(settings)
    settings.window.open, settings.window.tab = true, 'Home';
    settings.window.sections['Home/More look'] = true;
    app.state.settings = settings;
    frame();
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
end;
local function value() return custom.history_value(app.state.settings); end;
local function called(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return call; end; end;
end;
local function asked()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextWrapped' and tostring(call[2]):find('^This changes ') then return call[2]; end;
    end;
end;
local function partly()
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddRectFilled' then return true; end; end;
    return false;
end;
local function history() return #app.state.history, (app.state.history[#app.state.history] or {}).label; end;
local COMBO, CHANGE, CANCEL = '##main_countdown_outline', 'Change##look_main_shared', 'Cancel##look_main_shared';

-- Usual shows what it is, and a pick over one shared value writes at once in one step.
open(fresh());
assert(called('BeginCombo', COMBO)[3] == 'Usual for each display', 'Fresh reads Usual for each display.');
assert(not partly(), 'Nothing draws partly ticked.');
frame('None##none', COMBO);
frame();
local steps, label = history();
assert(steps == 1 and label == 'Countdown outline: None' and look.outline(app.state.settings) == 'none' and not asked(), 'A pick over Usual asks nothing.');
assert(called('BeginCombo', COMBO)[3] == 'None', 'It reads back.');
frame('Every display##every', COMBO);
frame();
assert(called('BeginCombo', COMBO)[3] == 'Every display' and #app.state.history == 2, 'Every display reads back.');
frame('Usual for each display##usual', COMBO);
assert(look.outline(app.state.settings) == 'usual' and #app.state.history == 3, 'Usual puts it back.');
frame('Usual for each display##usual', COMBO);
assert(#app.state.history == 3, 'The choice already on does nothing.');

for _, tick in ipairs({
    { 'Bold##main_countdown_bold', 'Bold countdowns', look.bold, true },
    { 'Shadow##main_countdown_shadow', 'Countdown shadow', look.shadow, false },
}) do
    open(fresh());
    frame(tick[1]);
    steps, label = history();
    assert(steps == 1 and label == tick[2] and tick[3](app.state.settings) == tick[4], 'One step: ' .. tick[2]);
end;
open(fresh());
colored = { 'Outline color##main_countdown_color', { 1, 0, 0, 1 } };
frame();
for id, holder in pairs(holders(app.state.settings)) do assert(custom.equal(holder.countdown_outline_color, { 1, 0, 0, 1 }), 'The color reaches ' .. id); end;
steps, label = history();
assert(steps == 1 and label == 'Countdown outline color', 'The color is one step.');

-- Mixed changes nothing until a pick, the pick asks, and Cancel leaves it all alone.
s = fresh();
s.rolls.countdown_outline, s.pet.countdown_outline = true, true;
open(s);
local before_pick = value();
assert(called('BeginCombo', COMBO)[3] == 'Mixed', 'A save that matches nothing reads Mixed.');
frame(nil, COMBO);
assert(custom.equal(value(), before_pick) and #app.state.history == 0, 'Mixed writes nothing, even with the list open.');
frame('Every display##every', COMBO);
frame();
assert(asked() == 'This changes countdown outlines on: Recasts, Overhead icons.', 'It asks: ' .. tostring(asked()));
assert(custom.equal(value(), before_pick) and #app.state.history == 0, 'Nothing changes until the answer.');
frame(CANCEL);
frame();
assert(not asked() and custom.equal(value(), before_pick) and #app.state.history == 0, 'Cancel leaves every display as it is.');
frame('Every display##every', COMBO);
frame(CHANGE);
frame();
steps, label = history();
assert(not asked() and look.outline(app.state.settings) == 'every' and steps == 1 and label == 'Countdown outline: Every display', 'Change is one Undo step.');
local changed_value = value();
assert(app.callbacks.undo() and custom.equal(value(), before_pick), 'Undo brings the Mixed save back.');
assert(app.callbacks.redo() and custom.equal(value(), changed_value), 'Redo sets it again.');

-- Bold and Shadow that differ draw partly ticked, and a click asks.
s = fresh();
s.overhead.countdown_bold = true;
open(s);
assert(partly(), 'Bold that differs draws partly ticked.');
frame('Bold##main_countdown_bold');
frame();
assert(tostring(asked()):find('^This changes bold countdowns on: Self buffs, ') and #app.state.history == 0, 'A click asks: ' .. tostring(asked()));
frame(CHANGE);
assert(look.bold(app.state.settings) == true and #app.state.history == 1, 'Change sets every display.');
s = fresh();
s.overhead.countdown_shadow = false;
open(s);
frame('Shadow##main_countdown_shadow');
frame();
assert(tostring(asked()):find('^This changes countdown shadows on: ') and #app.state.history == 0, 'Shadow asks too.');
frame(CANCEL);
assert(look.shadow(app.state.settings) == nil, 'Cancel changes nothing.');

-- A color or a blink time that differs reads Mixed and asks too.
s = fresh();
s.overhead.countdown_outline_color = { 1, 1, 1, 1 };
open(s);
assert(called('TextUnformatted', 'Mixed'), 'The color says Mixed.');
colored = { 'Outline color##main_countdown_color', { 0, 1, 0, 1 } };
frame();
frame();
assert(tostring(asked()):find('^This changes countdown outline colors on: Self buffs') and #app.state.history == 0, 'A color over Mixed asks: ' .. tostring(asked()));
frame(CHANGE);
assert(custom.equal(look.outline_color(app.state.settings), { 0, 1, 0, 1 }) and #app.state.history == 1, 'Change sets it.');

s = fresh();
s.overhead.blink_seconds = 30;
open(s);
assert(called('SliderFloat', '##main_blink_seconds')[4] == 'Mixed', 'The blink time says Mixed.');
slid = { '##main_blink_seconds', 20 };
frame();
frame();
assert(tostring(asked()):find('^This changes when blinking starts on: Self buffs') and #app.state.history == 0, 'A blink time over Mixed asks: ' .. tostring(asked()));
frame(CHANGE);
assert(look.blink_seconds(app.state.settings) == 20 and #app.state.history == 1, 'Change sets it.');
s = fresh();
open(s);
slid = { '##main_blink_seconds', 40.4 };
frame();
assert(look.blink_seconds(app.state.settings) == 40 and #app.state.history == 1 and not asked(), 'One shared time just writes.');

-- Blink that differs asks, and with none blinking the tick drops its time.
s = fresh();
s.overhead.blink_icons = false;
open(s);
assert(partly(), 'Blink that differs draws partly ticked.');
frame('Blink before an effect ends, starting at##main_blink');
frame();
assert(asked() == 'This changes blinking on: Overhead icons.', 'It names the display that changes: ' .. tostring(asked()));
frame(CHANGE);
frame();
steps, label = history();
assert(steps == 1 and label == 'Blink before an effect ends' and look.blink(app.state.settings) == true, 'Change is one step.');
frame('Blink before an effect ends, starting at##main_blink');
frame();
assert(look.blink(app.state.settings) == false and called('Checkbox', 'Blink before an effect ends##main_blink')
    and not called('SliderFloat', '##main_blink_seconds'), 'With none blinking the time goes, and the tick says less.');
frame('Blink before an effect ends##main_blink');
frame();
assert(look.blink(app.state.settings) == true and called('SliderFloat', '##main_blink_seconds'), 'On again, the time is back.');

-- A question from before an Undo goes with the settings it was about.
s = fresh();
s.rolls.countdown_outline = true;
open(s);
frame('None##none', COMBO);
frame();
assert(asked(), 'Fixture: the question is up.');
app.state.settings = fresh();
app.state.settings.window.open, app.state.settings.window.tab = true, 'Home';
app.state.settings.window.sections['Home/More look'] = true;
frame();
assert(not asked(), 'Other settings drop the question.');
assert(#MOCK.commands == 0, 'The rows send no game commands.');
return 'One countdown look writes every display\'s own keys, reads Usual and Mixed from them, and asks before it overrides Mixed';
