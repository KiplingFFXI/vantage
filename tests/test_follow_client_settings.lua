local defaults = require('ui.defaults');
local appearance = require('ui.appearance');
local assets = require('ui.client_assets');
local profiles, store = require('core.profiles'), require('core.store');
local equal = require('core.customization').equal;
local follow = 'Follow game client';
local fields = { 'font', 'gauge_art', 'icon_art', 'recast_icon_art' };
local reads = 0;
assets._set_platform_for_tests({
    game_root=function() return 'C:/Client' end,
    ashita_root=function() return 'C:/Ashita' end,
    xiview_path=function() return 'C:/Mods/XiView-Standard/ROM/119/51.DAT' end,
    read=function() reads=reads+1 end,
    upload=function() error('Settings must not upload artwork.') end,
});
-- The looks Vantage draws: the timer panels', the menus' and the party list buffs' own.
local function styles(settings)
    return {settings.style,settings.window_style,settings.party_ui.style};
end;
for _,fresh in ipairs({defaults.make(),defaults.tidy(nil),defaults.tidy({})}) do
    assert(appearance.current(fresh)=='Original FFXI');
    assert(fresh.party_ui.locked);
    for _,style in ipairs(styles(fresh)) do
        for _,key in ipairs(fields) do assert(style[key]~=follow) end;
    end;
end;
assert(reads==0,'Fresh settings never discover mods.');
for _,name in ipairs(appearance.names) do assert(name~=follow) end;
assert(not appearance.apply(defaults.make(),follow),'An appearance not on the list cannot be selected.');
local function customize(settings)
    settings.enabled, settings.preview = false, false;
    settings.style.font_size, settings.style.icon_size, settings.style.scale = 23, 37, 1.5;
    settings.style.text_color, settings.style.outline_color = { 0.2, 0.8, 0.6, 1 }, { 0.6, 0.2, 0.1, 0.9 };
    settings.window.x, settings.window.y = 530, 390;
    settings.window_style.font_size = 24;
    settings.party_ui.groups[1].native_x, settings.party_ui.groups[1].native_y, settings.party_ui.native.width = 14, 7, 386;
    settings.party_ui.locked, settings.party_ui.enabled = true, true;
    settings.party_ui.style.opacity = 0.7;
    settings.party_ui.effects.growth, settings.party_ui.effects.icon_size = 'left', 38;
    settings.party_ui.effects.exclude, settings.party_ui.effects.countdown_outline = { 253, 255 - 1 }, false;
    settings.panels.self_buffs.x, settings.panels.self_buffs.y = 491, 233;
    settings.panels.self_buffs.width, settings.panels.self_buffs.locked = 427, true;
    settings.panels.self_buffs.mode, settings.panels.self_buffs.growth = 'icons', 'left';
    settings.panels.self_buffs.include, settings.panels.self_buffs.countdown_outline = { 33, 40 }, false;
    settings.effect_filters.rules = { { enabled = true, effect = 253, kind = 'buff', name = 'Aster', job = 1, scope = 'party' } };
    return settings;
end;


local original=defaults.tidy(customize(defaults.make()));
for _,name in ipairs({'Original FFXI','XI View','Phoenix','Minimal'}) do
    local manual=defaults.copy(original);assert(appearance.apply(manual,name));
    manual=defaults.tidy(manual);local before=defaults.copy(manual);
    assert(equal(before,defaults.tidy(manual)),'Every manual appearance remains idempotent.');
end;
-- The customized settings with one pack picked in every look.
local function picked(pack)
    local settings=defaults.copy(original);
    for _,style in ipairs(styles(settings)) do
        for _,key in ipairs(fields) do if style[key]~=nil then style[key]=pack end end;
    end;
    return settings;
end;
for _,pack in ipairs({'XI View','Original FFXI'}) do
    local actual=defaults.tidy(picked(pack));
    for _,size in ipairs({'minimal','minimal_1_5x','minimal_2x'}) do
        local config=defaults.copy(actual);
        assert(require('setup_fixture').apply(config,{size=size,skin='keep',matching=false}));
        assert(config.style.font==pack and config.style.gauge_art==pack and config.party_ui.style.icon_art==pack
            and config.party_ui.locked);
    end;
end;
local folder=MOCK_INSTALL_PATH..'/config/addons/vantage';
local manager=profiles.new(folder);
local saved=picked('XI View');
assert(store.write(manager.path,{Saved=saved}));
local written=assert(store.read(manager.path)).Saved;
local receiver=defaults.copy(original);
assert(manager:load('Saved',receiver));
local expected=defaults.tidy(defaults.copy(written));
assert(equal(profiles.capture(receiver),profiles.capture(expected)),'A real saved profile imports with all customization intact.');
assert(equal(store.read(manager.path).Saved,written),'Loading never rewrites the saved source profile.');
assert(store.write(manager.layout_path,{scope='presentation',presentation=saved}));
receiver=defaults.copy(original);
assert(manager:load_layout(receiver,'presentation'));
for _,key in ipairs({'style','window_style','effect_filters'}) do assert(equal(receiver[key],expected[key])) end;
assert(equal(receiver.party_ui.style,expected.party_ui.style) and receiver.party_ui.locked);
assert(store.write(folder..'/saved-settings.json',saved));
assert(equal(defaults.tidy(assert(store.read(folder..'/saved-settings.json'))),expected),'A settings JSON file loads with every value intact.');
local manual=defaults.copy(original);
local before=defaults.copy(manual);
assert(manager:load_layout(manual,'placement'));
for i,style in ipairs(styles(manual)) do assert(equal(style,styles(before)[i]),'Placement-only import preserves artwork.');end;
assets._set_platform_for_tests(nil);
return 'No automatic artwork, picked artwork through each size, saved profiles and shared layouts';
