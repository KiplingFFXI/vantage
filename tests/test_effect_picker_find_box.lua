-- One find box serves every effect and recast picker, as one list is open at a time. What is typed stays while its list
-- is open, and a list that opens, the same one again or another, starts with the box empty.
local h = require('panel_fixture')();
local imgui = h.imgui;
local typed, hint = {}, imgui.InputTextWithHint;
imgui.InputTextWithHint = function(label, text, value, ...)
    hint(label, text, value, ...);
    if typed[label] == nil then return false; end;
    value[1], typed[label] = typed[label], nil;
    return true;
end;
local function open(label) h.combo = '##' .. label; h.draw(); end;
local function shut() h.combo = nil; h.draw(); end;
local function box(label)
    local call = h.calls('InputTextWithHint', '##effect_search_' .. label)[1];
    assert(call, 'Fixture: the list of ' .. label .. ' is open.');
    return call[4][1];
end;

h.fresh(function(s) s.ready_pulse.enabled = true; end);
h.on('notices', 'show');
h.draw('New alert##frame');
h.draw();
open('Effect');
assert(box('Effect') == '', 'Fixture: the box starts empty.');
typed['##effect_search_Effect'] = 'haste';
h.draw();
h.draw();
assert(box('Effect') == 'haste', 'What was typed stays while the list is open.');
shut();
open('Effect');
assert(box('Effect') == '', 'The same list opened again starts with the box empty.');
typed['##effect_search_Effect'] = 'haste';
h.draw();
shut();
h.on('recasts', 'show');
open('Never pulse for');
assert(box('Never pulse for') == '', 'Another list starts with the box empty.');
shut();
rawset(imgui, 'InputTextWithHint', nil);
return 'Each effect picker starts with its find box empty';
