-- The strips beside the game's party list keep their plans, each row's effect options, its effect list and its
-- cells from frame to frame, work out each row's effects once a frame, and draw what a fresh plan draws. A setting,
-- a subject, an effect's state or a countdown that changes is picked up the next frame. The same holds under a shared
-- hide rule, for a member with nothing tracked and for a strip moved off the game's window.
local imgui = require('imgui');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local hud, party = require('ui.party_hud'), require('ui.party_defaults');
local native, layout = require('ui.native_party_hud'), require('ui.party_layout');
require('ui.icons').status = function(id) return 100000 + id; end;
imgui.GetMousePos = function() return -1, -1; end;
imgui.IsMouseDown = function() return false; end;
MOCK.screen = { 2400, 1600 };

local p = party.make();
p.enabled, p.locked, p.show_solo = true, true, true;
-- Countdowns start off; on here, so the strips draw them.
p.effects.timers = true;
local roster, subjects = hud.sample(6, 100);
local geometry = { available = true, groups = { [1] = { x = 1800, y = 100, width = 116, height = 240, rows = {} } } };
for _, member in ipairs(roster.members) do
    geometry.groups[1].rows[member.slot] = { x = 1800, y = 100 + member.slot * 40, width = 116, height = 40, slot = member.slot };
end
local callbacks = { native_geometry = geometry };

-- Counts how often each row's effects are worked out in a draw.
local counts = { kept = 0, effects = 0 };
local kept_effects, effects = layout.kept_effects, layout.effects;
layout.kept_effects = function(...) counts.kept = counts.kept + 1; return kept_effects(...); end;
layout.effects = function(...) counts.effects = counts.effects + 1; return effects(...); end;
local planned;
local plan = native.plan;
native.plan = function(...) planned = plan(...); return planned; end;
local function frame(now)
    counts.kept, counts.effects, MOCK.imgui_calls = 0, 0, {};
    native.draw(roster, subjects, p, now or 100, callbacks);
    local drawn = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1]:sub(1, 5) == 'draw:' then drawn[#drawn + 1] = MOCK.drawn[call]; end
    end
    return drawn;
end
local rows = #roster.members;

local first = frame();
local strip = planned[1];
assert(strip and #strip.rows == rows, 'One row for each member: ' .. (strip and #strip.rows or 0));
assert(counts.kept == rows, 'Each row\'s effects are worked out once a frame: ' .. counts.kept);
local held = {};
for index, item in ipairs(strip.rows) do
    held[index] = { item = item, options = item.options, effects = item.effects, cells = item.cells.cells, area = item.area };
end
local second = frame();
assert(equal(first, second), 'The same draw calls on the next frame.');
assert(counts.kept == rows and counts.effects == 0, 'A frame where nothing changed works out no effect list: ' .. counts.effects);
assert(planned[1] == strip, 'The plan is kept.');
for index, item in ipairs(planned[1].rows) do
    local saved = held[index];
    assert(item == saved.item and item.options == saved.options and item.effects == saved.effects and item.area == saved.area
        and item.cells.cells == saved.cells, 'Row ' .. index .. ' keeps its options, effects, cells and area.');
end

-- A fresh plan (overlay.plan on its own) has the same rows, options, effects and areas.
local fresh = plan(roster, subjects, p, geometry, MOCK.screen[1], MOCK.screen[2], {}, nil);
assert(fresh[1] ~= strip and #fresh[1].rows == rows, 'overlay.plan on its own makes new tables.');
for index, item in ipairs(fresh[1].rows) do
    local kept = planned[1].rows[index];
    assert(item.member == kept.member and equal(item.area, kept.area) and equal(item.options, kept.options), 'Row ' .. index .. ' matches');
    assert(#item.effects == #kept.effects, 'with the same effects');
    for at, effect in ipairs(item.effects) do assert(kept.effects[at] == effect, 'in the same order'); end
end

-- A setting changes: a list edited in place hides its effect at once, and a changed value makes new options.
p.effects.exclude[33] = true;
frame();
for _, item in ipairs(planned[1].rows) do
    for _, effect in ipairs(item.effects) do assert(effect.effect ~= 33, 'Haste is excluded at once.'); end
end
p.effects.exclude[33] = nil;
frame();
assert(#planned[1].rows[1].effects == #held[1].effects, 'and back when it is taken out.');
-- The icon size is the room's beside the rows now, so a value the options copy as it is changes here.
p.effects.blink_seconds = 20;
frame();
assert(planned[1].rows[1].options ~= held[1].options and planned[1].rows[1].options.blink_seconds == 20, 'A changed value makes new options.');
p.effects.blink_seconds = 15;
-- A key the settings gain or lose is gained or lost by the options too.
p.effects.saved_extra = 1;
frame();
assert(planned[1].rows[1].options.saved_extra == 1, 'A new key is copied.');
p.effects.saved_extra = nil;
frame();
assert(planned[1].rows[1].options.saved_extra == nil, 'A key taken out goes.');
local count = #planned[1].rows[2].effects;
-- A new subject (the refresh makes new ones) is worked out again.
local member = roster.members[2];
subjects[member.id] = copy(subjects[member.id]);
table.remove(subjects[member.id].effects, 1);
frame();
assert(#planned[1].rows[2].effects == count - 1, 'A new subject\'s effects are worked out again.');
-- An effect's state changes in place, as a timer that runs out does: one whose timer is lost stays, and one that
-- wears off leaves at once.
local before = #planned[1].rows[3].effects;
local changing = subjects[roster.members[3].id].effects[1];
changing.status, changing.remaining = 'unknown', nil;
frame();
assert(#planned[1].rows[3].effects == before, 'An effect whose timer is lost stays.');
changing.present = false;
frame();
assert(#planned[1].rows[3].effects == before - 1, 'An effect that wears off leaves at once.');
changing.present = true;
-- A countdown that changes text moves to new cells, and the draw shows it.
local function texts(drawn)
    local out = {};
    for _, call in ipairs(drawn) do if call[1] == 'draw:AddText' then out[#out + 1] = call[6]; end end
    return table.concat(out, ' ');
end
local subject = subjects[roster.members[4].id];
subject.effects[2].remaining = 45;
local shown = texts(frame());
subject.effects[2].remaining = 44.5;
assert(texts(frame()) == shown, 'The same text, the same cells.');
subject.effects[2].remaining = 43;
local changed = texts(frame());
assert(changed ~= shown and changed:find('43s', 1, true), 'A new countdown is drawn: ' .. changed);
-- Sorted by time left, a changed order is seen too.
p.effects.sort = 'remaining';
frame();
subject.effects[1].remaining, subject.effects[2].remaining = 5, 900;
frame();
local order = {};
for _, effect in ipairs(planned[1].rows[4].effects) do order[#order + 1] = effect.effect; end
local first_id = subject.effects[1].effect;
assert(order[1] == first_id, 'The effect with the least time left comes first: ' .. table.concat(order, ' '));
p.effects.sort = 'longest';

local function has(item, id)
    for _, effect in ipairs(item.effects) do if effect.effect == id then return true; end end
    return false;
end
local function hold(strip)
    local out = {};
    for index, item in ipairs(strip.rows) do
        out[index] = { item = item, options = item.options, effects = item.effects, cells = item.cells and item.cells.cells, area = item.area };
    end
    return out;
end
local function kept_rows(strip, saved, label)
    for index, item in ipairs(strip.rows) do
        local before = saved[index];
        assert(item == before.item and item.options == before.options and item.effects == before.effects and item.area == before.area
            and item.cells and item.cells.cells == before.cells, label .. ': row ' .. index .. ' keeps its options, effects, cells and area.');
    end
end

-- A shared hide rule keeps the rows too: the members' filtered effects are kept while the rules, the member and the
-- effects stay the same.
local effect_filters = require('core.effect_filters');
local hide = effect_filters.rule();
hide.effect = 40;
local rules = { enabled = true, rules = { hide } };
callbacks.effect_filters, callbacks.effect_recipients = rules, effect_filters.recipients(nil, roster);
frame();
for _, item in ipairs(planned[1].rows) do assert(not has(item, 40), 'Protect is hidden by the rule.'); end
local ruled = hold(planned[1]);
local ruled_first = frame();
local ruled_second = frame();
assert(equal(ruled_first, ruled_second), 'Under a rule, the same draw calls on the next frame.');
assert(counts.kept == rows and counts.effects == 0, 'Under a rule a frame where nothing changed works out no effect list: ' .. counts.effects);
kept_rows(planned[1], ruled, 'Under a rule');
-- Recipients worked out again (the draw's own, when none are given) name the same members, so the rows are kept.
callbacks.effect_recipients = nil;
frame();
assert(counts.effects == 0, 'Recipients worked out again keep the rows: ' .. counts.effects);
kept_rows(planned[1], ruled, 'With new recipients');
-- What the rules hide is what a fresh plan of the filtered members shows.
local filtered = effect_filters.subjects(rules, subjects, effect_filters.recipients(nil, roster));
local fresh_ruled = plan(roster, filtered, p, geometry, MOCK.screen[1], MOCK.screen[2], {}, nil);
for index, item in ipairs(fresh_ruled[1].rows) do
    local kept = planned[1].rows[index];
    assert(#item.effects == #kept.effects, 'Row ' .. index .. ' shows what a fresh plan shows under the rule.');
    for at, effect in ipairs(item.effects) do assert(kept.effects[at] == effect, 'in the same order'); end
end
-- An effect that changes in place is filtered again.
local changing = subjects[roster.members[3].id].effects[1];
assert(changing.effect == 40, 'The sample starts with Protect.');
changing.effect = 41;
frame();
assert(has(planned[1].rows[3], 41), 'An effect the rule no longer matches shows at once.');
changing.effect = 40;
frame();
assert(not has(planned[1].rows[3], 40), 'and hides again when it does.');
-- A rule for one member: that member's name changing is seen with the new recipients.
hide.name = 'Cinder';
callbacks.effect_recipients = effect_filters.recipients(nil, roster);
frame();
assert(not has(planned[1].rows[3], 40) and has(planned[1].rows[1], 40), 'Only Cinder\'s Protect is hidden.');
local named = roster.members[3].name;
roster.members[3].name = 'Ember';
callbacks.effect_recipients = effect_filters.recipients(nil, roster);
frame();
assert(has(planned[1].rows[3], 40), 'A member who is no longer Cinder shows Protect.');
roster.members[3].name, hide.name = named, '';
-- The rule switched off in place shows the effect the next frame.
hide.enabled = false;
frame();
for _, item in ipairs(planned[1].rows) do
    assert(has(item, 40) == has(subjects[item.member.id], 40), 'Protect is back once the rule is off.');
end
callbacks.effect_filters, callbacks.effect_recipients = nil, nil;

-- A member with no effects tracked yet keeps one empty list and its cells.
local missing = roster.members[5];
local missing_subject = subjects[missing.id];
subjects[missing.id] = nil;
frame();
local empty_row = planned[1].rows[5];
assert(empty_row.member == missing and #empty_row.effects == 0, 'The member with nothing tracked shows no effects.');
local empty_list, empty_cells = empty_row.effects, empty_row.cells.cells;
frame();
assert(planned[1].rows[5].effects == empty_list and planned[1].rows[5].cells.cells == empty_cells and counts.effects == 0,
    'An unchanged frame keeps the empty list and its cells: ' .. counts.effects);
subjects[missing.id] = missing_subject;
frame();
assert(#planned[1].rows[5].effects > 0, 'Effects that arrive later show.');

-- A strip moved off the game's window keeps its plan, rows, options, effects, cells and areas too.
local strip_saved = p.groups[1];
strip_saved.native_detached = true;
strip_saved.detached_x, strip_saved.detached_y, strip_saved.detached_width, strip_saved.detached_height = 200, 150, 300, 400;
frame();
local detached = planned[1];
assert(detached and detached.detached and #detached.rows == rows, 'One detached row for each member.');
local loose = hold(detached);
local detached_first = frame();
local detached_second = frame();
assert(equal(detached_first, detached_second), 'Detached, the same draw calls on the next frame.');
assert(counts.effects == 0, 'Detached, a frame where nothing changed works out no effect list: ' .. counts.effects);
assert(planned[1] == detached, 'The detached plan is kept.');
kept_rows(detached, loose, 'Detached');
-- Options hold the strip's text measure, a function each fresh plan makes for itself.
local function same_options(a, b)
    for key, value in pairs(a) do if key ~= 'text_measure' and not equal(value, b[key]) then return false; end end
    for key in pairs(b) do if a[key] == nil then return false; end end
    return true;
end
local function matches_fresh(label)
    local fresh_plan = plan(roster, subjects, p, geometry, MOCK.screen[1], MOCK.screen[2], {}, nil)[1];
    local kept_plan = planned[1];
    assert(fresh_plan ~= kept_plan and fresh_plan.detached, label .. ': overlay.plan on its own makes new tables.');
    for _, key in ipairs({ 'group', 'x', 'y', 'width', 'height', 'content_height', 'min_width' }) do
        assert(fresh_plan[key] == kept_plan[key], label .. ': the plan\'s ' .. key .. ' matches.');
    end
    assert(#fresh_plan.rows == #kept_plan.rows, label .. ': the same rows.');
    for index, item in ipairs(fresh_plan.rows) do
        local kept = kept_plan.rows[index];
        assert(item.member == kept.member and equal(item.area, kept.area) and same_options(item.options, kept.options)
            and item.label_y == kept.label_y and equal(item.label_lines, kept.label_lines), label .. ': row ' .. index .. ' matches');
        assert(#item.effects == #kept.effects, label .. ': with the same effects');
        for at, effect in ipairs(item.effects) do assert(kept.effects[at] == effect, label .. ': in the same order'); end
    end
end
matches_fresh('Detached');
-- A list edited in place and a new width are picked up the next frame.
p.effects.exclude[33] = true;
frame();
for _, item in ipairs(planned[1].rows) do assert(not has(item, 33), 'Detached, Haste is excluded at once.'); end
p.effects.exclude[33] = nil;
strip_saved.detached_width = 180;
frame();
matches_fresh('Narrower');
strip_saved.native_detached = false;
frame();
assert(not planned[1].detached and #planned[1].rows == rows, 'Back beside the game\'s window.');
