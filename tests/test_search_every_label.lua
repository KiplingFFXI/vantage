-- Plan 13 item 4, findable: every control a player can read a name on, on every page and in every layout, comes up when its
-- name is typed in the search box, and the words players use for the space under the party list's buffs land on its row.
local h = require('panel_fixture')();
local window = h.window;

local KIND = { Checkbox = true, Button = true, SmallButton = true, RadioButton = true, SliderFloat = true, InputText = true, BeginCombo = true, ColorEdit4 = true, CollapsingHeader = true };
-- Each page's own way back, which is no setting.
local PLAIN = { ['< Back'] = true };

-- What the control says: ##frame_Name and Name##id are both Name, and a name's tag tail isn't part of it.
local function shown(label)
    local text = label:match('^##frame_(.+)$') or label:match('^(.-)##') or label;
    return text:gsub('_%l[%l_]*$', '');
end;

local seen, labels = {}, 0;
local function collect(where)
    local in_page = false;
    for _, call in ipairs(MOCK.imgui_calls) do
        in_page = in_page or call[1] == 'BeginChild' and call[2] == '##settings_content';
        if in_page and KIND[call[1]] and type(call[2]) == 'string' then
            local text = shown(call[2]);
            if text ~= '' and not PLAIN[text] and not seen[text] then seen[text], labels = where, labels + 1; end;
        end;
    end;
end;

local displays = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'recasts', 'party_ui', 'overhead', 'cooldown_list', 'rolls', 'pet', 'notices', 'hidden' };
local tabs = { 'show', 'place', 'look', 'filters', 'when' };
for _, mode in ipairs({ 'bars', 'expanded', 'icons', 'text' }) do
    h.fresh(function(s)
        for _, panel in pairs(s.panels) do panel.mode, panel.bar_style, panel.gradient, panel.dispel_light = mode, 'rail', true, true; end;
        s.edit_mode.grid_mode, s.party_ui.enabled, s.overhead.enabled = true, true, true;
        s.recast_display = mode == 'bars' and 'combined' or 'separate';
        s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen';
    end);
    for _, id in ipairs(displays) do
        for _, tab in ipairs(tabs) do
            h.on(id, tab);
            collect(id .. '/' .. tab);
        end;
    end;
    for _, page in ipairs({ 'Home', 'Durations', 'Profiles', 'Help' }) do
        h.s.window.tab = page;
        h.draw(); h.draw();
        collect(page);
    end;
end;
assert(labels > 300, 'Fixture: the walk reached the pages: ' .. labels);
h.fresh();
h.s.window.tab = 'Home';
h.draw(); h.draw();
for text, where in pairs(seen) do
    assert(#window.search(text:lower()) > 0, 'Search finds nothing for ' .. text .. ', drawn on ' .. where);
end;

-- What the plan names, by the words a player would use.
local function lands(query)
    local result = window.search(query)[1];
    return result and result.panel == 'party_ui' and result.label == 'Longest row';
end;
for _, query in ipairs({ 'touching the next row', 'room', 'next row' }) do assert(lands(query), query .. ' lands on Longest row.'); end;
return 'Every label drawn comes up in the search';
