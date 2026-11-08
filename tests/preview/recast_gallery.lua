local hud, defaults = require('ui.hud'), require('ui.defaults');
local imgui, actions = require('imgui'), require('ui.action_icons');
require('ui.recast_icons').prepare();
local sets, view = {}, hud.sample(100);
-- Installed ROM/118/114.DAT mgc_ records: spell4 NQ6/HQ89; spell57 NQ2/HQ143.
-- The decoded ability547 resource gives Provoke HQ360/NQ41; its timer is5.
-- Installed ROM/118/109.DAT item15762 is Empress Band, with a32x32 picture.
for _, row in ipairs(view.rows) do
    if row.domain == 'recast' then
        if row.effect == 10004 then row.spell_id, row.list_icon_hq, row.list_icon_nq = 4, 89, 6;
        elseif row.effect == 10057 then row.spell_id, row.list_icon_hq, row.list_icon_nq = 57, 143, 2;
        elseif row.kind == 'ability' then row.ability_id, row.list_icon_id, row.ability_element = 547, 360, 41;
        elseif row.kind == 'item' then
            row.item_id, row.recast_id, row.effect, row.name = 15762, 15762, 45762, 'Empress Band';
        end;
    end;
end;
for _, artwork in ipairs({ 'Original FFXI', 'XI View' }) do
    for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
        local s = defaults.make();
        require('original_skin_fixture')(s);
        s.style.icon_size, s.style.recast_icon_art = 48, artwork;
        local column = 0;
        for _, key in ipairs(defaults.panel_order) do
            local p = s.panels[key]; p.enabled = defaults.recast_panels[key] ~= nil;
            if p.enabled then
                p.mode, p.x, p.y, p.width, p.wrap = mode, 20 + column * 370, 20 + #sets * 210, 350, true;
                p.show_total = mode == 'expanded';
                p.title = artwork .. ' / ' .. defaults.recast_panels[key] .. ' / ' .. mode;
                column = column + 1;
            end;
        end;
        sets[#sets + 1] = s;
    end;
end;
local original = imgui.Begin;
return function()
    for index, s in ipairs(sets) do
        imgui.Begin = function(name, ...) return original(name .. '_recast_gallery_' .. index, ...); end;
        local ok, err = pcall(hud.draw, view, s, 100, {});
        imgui.Begin = original; if not ok then error(err); end;
    end;
    for _, artwork in ipairs({ 'Original FFXI', 'XI View' }) do
        for _, icon in ipairs({ { 89, 6, 'Cure IV' }, { 143, 2, 'Haste' }, { 360, 41, 'Provoke' } }) do
            local status = actions.status(artwork, icon[1], icon[2]);
            assert(status.available, artwork .. ' ' .. icon[3] .. ' artwork must load.');
            PREVIEW.log(artwork .. ': ' .. icon[3] .. ' uses ' .. tostring(status.using));
        end;
    end;
end;
