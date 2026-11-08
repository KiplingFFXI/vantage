local calls, prepared, cleared, item = {}, 0, 0;
local available = true;
package.loaded['ui.action_icons'] = {
    prepare = function() prepared = prepared + 1; end,
    clear = function() cleared = cleared + 1; end,
    draw = function(...) calls[#calls + 1] = {...}; return available; end,
};
package.loaded['ui.item_icons'] = {
    prepare = function() prepared = prepared + 1; end,
    clear = function() cleared = cleared + 1; end,
    texture = function(id) item = id; return available and 909 or nil; end,
};
local icons = require('ui.recast_icons');
local images = {};
local list = {AddImage = function(_,...) images[#images + 1] = {...}; end};
icons.prepare(); assert(prepared == 2);
assert(icons.draw(list,{kind='spell',list_icon_hq=1002,list_icon_nq=4},'XI View',10,20,48,0.7));
local call = calls[1];
assert(call[1]==list and call[2]=='XI View' and call[3]==1002 and call[4]==4);
assert(call[5]==10 and call[6]==20 and call[7]==48 and call[8]==0.7);
calls = {};
assert(icons.draw(list,{kind='ability',list_icon_id=0,ability_element=7},'Original FFXI',0,0,32,1));
assert(#calls==1 and calls[1][3]==0,'Native icon zero is valid.');
local row = {kind='ability',action_icons={
    {list_icon_id=65535,ability_element=2}, {list_icon_id=65535,ability_element=3},
    {list_icon_id=65535,ability_element=2}, {list_icon_id=9,ability_element=2},
    {list_icon_id=9,ability_element=5}, {list_icon_id=12}, {list_icon_id=15},
}};
calls={}; assert(icons.draw(list,row,'XI View',10,20,48,1));
assert(#calls==4,'Shared timers show at most four distinct native pictures.');
assert(calls[1][4]==2 and calls[2][4]==3 and calls[3][3]==9 and calls[4][3]==12);
for i,c in ipairs(calls) do
    assert(c[7]==23 and c[5]>=10 and c[6]>=20 and c[5]+c[7]<=58 and c[6]+c[7]<=68);
end;
calls={}; assert(icons.draw(list,row,'XI View',10,20,48,1)); assert(#calls==4);
assert(icons.draw(list,{kind='item',item_id=15762,recast_id=44470},'XI View',12,24,48,0.5));
assert(item==15762 and #images==1 and images[1][1]==909);
assert(images[1][2][1]==12 and images[1][3][1]==60 and images[1][3][2]==72);
assert(icons.draw(list,{kind='item',recast_id=15763},nil,0,0,32,1)); assert(item==15763);
available=false;
assert(not icons.draw(list,{kind='spell',list_icon_hq=5},nil,0,0,32,1));
assert(not icons.draw(list,{kind='item',item_id=15762},nil,0,0,32,1));
assert(not icons.draw(list,{kind='ability'},nil,0,0,32,1));
assert(not icons.draw(list,{kind='unrecognized'},nil,0,0,32,1));
icons.clear(); assert(cleared==2);
local defaults = require('ui.defaults');
local settings = defaults.make();
assert(settings.style.recast_icon_art=='Original FFXI');
local window = require('ui.settings_window');
local found = {};
for _, result in ipairs(window.search('recast XI View')) do
    if result.label == 'Recast icons' then found[result.tab] = true; end;
end;
assert(found.Home and not found.Recasts, 'Cold search finds the recast artwork choice on the main page, not on Recasts.');

local hud, theme = require('ui.hud'), require('ui.theme');
settings = defaults.make();
settings.style.opacity = 0.05;
for key, panel in pairs(settings.panels) do panel.enabled = defaults.recast_panels[key] ~= nil; end;
local view = hud.sample(100);
for _, entry in ipairs(view.rows) do
    if entry.domain == 'recast' then
        if entry.kind == 'spell' then entry.list_icon_hq, entry.list_icon_nq = 1002, 4;
        elseif entry.kind == 'ability' then entry.list_icon_id, entry.ability_element = 9, 2; end;
    end;
end;
available = true;
for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    for _, panel in pairs(settings.panels) do panel.mode = mode; end;
    calls, MOCK.imgui_calls = {}, {};
    hud.draw(view, settings, 100, {});
    assert(#calls == 3, 'Both spell pictures and the ability picture render in ' .. mode);
    for _, action in ipairs(calls) do assert(action[8] == 1, 'Background opacity does not dim action artwork.'); end;
    local item_images = 0;
    for _, draw in ipairs(MOCK.imgui_calls) do
        if draw[1] == 'draw:AddImage' and draw[2] == 909 then
            item_images = item_images + 1;
            assert(draw[7] == theme.u32({ 1, 1, 1, 1 }), 'Background opacity does not dim item artwork.');
        end;
    end;
    assert(item_images == 1, 'The actual item picture renders in ' .. mode);
end;
settings.style.recast_icon_art='XI View'; settings=defaults.tidy(settings);
assert(settings.style.recast_icon_art=='XI View');
require('original_skin_fixture')(settings); assert(settings.style.recast_icon_art=='Original FFXI');
settings.style.recast_icon_art='invalid'; settings=defaults.tidy(settings);
assert(settings.style.recast_icon_art=='Original FFXI');
