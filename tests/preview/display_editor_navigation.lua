local imgui, window = require('imgui'), require('ui.settings_window');
local panels, custom = require('ui.panel_frame'), require('core.customization');
local s, seen, ids = PREVIEW.settings, {}, {};
s.window.tab, s.window.open = 'Display', true;
panels.open('party_ui', 'show');
s.window.sections = setmetatable({}, { __index=function() return true; end });
s.party_ui.style.icon_art = 'XI View';
s.party_ui.effects.icon_size, s.party_ui.locked = 47, true;
local original_button = imgui.Button;
imgui.Button = function(label, ...)
    local identity = label:match('###(.*)$') or label;
    local caption = label:match('^(.-)##') or label;
    local x, y = imgui.GetCursorScreenPos();
    local available = imgui.GetContentRegionAvail();
    local clicked = original_button(label, ...);
    if identity:find('##frame_tab',1,true) then
        local id = imgui.GetID(label);
        if ids[identity] then assert(ids[identity] == id, 'Subpage button identity stays stable.'); end;
        ids[identity] = id;
        local left, top = imgui.GetItemRectMin();
        local right, bottom = imgui.GetItemRectMax();
        assert(right <= x + available + 1, 'Subpage button fits available width: '..identity);
        assert(imgui.CalcTextSize(caption) <= right-left+1, 'Subpage caption fits its button: '..identity);
        assert(bottom > top and right > left, 'Subpage button has a usable hit area.');
    end;
    return clicked;
end;
for _, name in ipairs({'Checkbox','SliderFloat','InputText','BeginCombo'}) do
    local original = imgui[name];
    imgui[name] = function(label, ...)
        seen[label:gsub('^##','')] = true;
        return original(label, ...);
    end;
end;
local labels = {
    show='frame_Your own row', place='frame_Longest row', look='frame_Opacity', filters='frame_Find an effect', when='frame_From_min',
};
local before;
function PREVIEW.verify_editor(key)
    assert(panels.context() == 'party_ui/'..key, 'Actual mouse click selects '..key);
    assert(seen[labels[key]], 'Selected subpage contains '..labels[key]);
    assert(key ~= 'place' or seen['frame_Buff side'], 'Size and place holds the size rows and the place rows.');
    for other, label in pairs(labels) do
        if other ~= key then assert(not seen[label], 'Unselected controls stay hidden: '..label); end;
    end;
    assert(custom.equal(custom.history_value(s),before), 'Navigation preserves themes, fonts, icons, layouts and locks.');
end;
return function()
    seen = {};
    window.draw(s, PREVIEW.view, PREVIEW.services);
    if PREVIEW.frame == 2 then before = custom.history_value(s); end;
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.verify_editor('show');
        local count = 0;
        for _ in pairs(ids) do count = count + 1; end;
        assert(count == #panels.tabs, 'The panel offers its five tabs and no more.');
        assert(s.party_ui.locked, 'Navigation never unlocks the frame.');
        PREVIEW.log('Actual subpage clicks isolate controls and preserve customization and locks.');
    end;
end;
