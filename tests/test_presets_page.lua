local defaults, party = require('ui.defaults'), require('ui.party_defaults');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local page, imgui = require('setup_fixture'), require('imgui');
-- The code behind skins and setups, which the setups below run.
local appearance, skin = require('ui.appearance'), require('ui.client_skin');
local scales = {minimal=1,minimal_1_5x=1.5,minimal_2x=2};
local menu_calls = 0;
skin.prepare_menu = function() menu_calls = menu_calls + 1; end;
skin.menu = function() menu_calls = menu_calls + 1; end;
local s = defaults.make();
s.party_ui.enabled = false;
s.party_ui.locked = false;
s.party_ui.name_display = 'job';
s.party_ui.strips.alliance2 = false;
s.party_ui.groups[3].native_detached, s.party_ui.groups[3].detached_x = true, 444;
s.party_ui.groups[2].native_x, s.party_ui.groups[2].native_y = 789, 321;
s.party_ui.effects.exclude, s.party_ui.effects.pinned = {4}, {33};
s.party_ui.effects.countdown_bold = true;
s.party_ui.style.icon_art = 'XI View';
s.effect_filters.rules = {{enabled=true,effect=253,kind='all',name='Rowan',job=0,scope='self'}};
s.style.colors = { custom={.1,.2,.3,1} };
local changes, controls = {}, {};
local c = {};
c.open_page = function() end;
c.changed = function(fn,save,label)
    changes[#changes+1] = { before=copy(s), save=save, label=label };
    fn();
end;
-- The page passes the screen size, which Apply uses to re-space panels still where they started.
local function options(size,skin_name,matching,window_type)
    local screen=imgui.GetIO().DisplaySize;
    return {size=size,skin=skin_name or 'keep',matching=matching~=false,window_type=window_type or 1,
        screen_width=screen.x,screen_height=screen.y};
end;
-- What a setup keeps: the strips' switches, lock, labels and places, and the data. It writes no frame settings.
local function protected(before,after)
    local a,b=before.party_ui,after.party_ui;
    for _,key in ipairs({'enabled','locked','strips','name_display','name_length'}) do
        assert(equal(a[key],b[key]),'Setup preserves party '..key);
    end;
    for index,group in ipairs(a.groups)do
        for _,key in ipairs({'order','native_detached','native_x','native_y','detached_x','detached_y'})do
            assert(equal(group[key],b.groups[index][key]),'Setup preserves group '..key);
        end;
    end;
    -- The icon size only sets a panel of its own, which is the player's pick.
    for _,key in ipairs({'include','exclude','pinned','order','icon_size'})do
        assert(equal(a.effects[key],b.effects[key]),'Setup preserves effect '..key);
    end;
    assert(equal(before.effect_filters,after.effect_filters) and equal(before.alerts.rules,after.alerts.rules)
        and before.alerts.enabled==after.alerts.enabled and before.alerts.muted==after.alerts.muted and before.alerts.volume==after.alerts.volume);
end;

-- Build uses the same size/appearance contract without changing its source. A size that isn't one builds and applies
-- nothing.
local kept=copy(s);
assert(page.build(s,options('huge'))==nil and page.apply(copy(s),options('huge'))==false
    and equal(s,kept),'A size that isn\'t one does nothing.');
for _,size in ipairs({'minimal','minimal_1_5x','minimal_2x'})do
    local source=copy(s);
    local candidate=page.build(s,options(size));
    assert(candidate~=s and candidate.party_ui~=s.party_ui and candidate.style~=s.style);
    assert(equal(s,source),'A candidate never changes saved settings.');
    local expected=copy(s);assert(page.apply(expected,options(size)));
    assert(equal(candidate,expected),'Current skin applies the selected setup.');
    protected(s,candidate);
    assert(candidate.style.scale==scales[size]);
    -- The party list buffs wear the timer panels' look, with icon art and opacity of their own.
    local own=0;for _ in pairs(candidate.party_ui.style)do own=own+1;end;
    assert(candidate.party_ui.style.icon_art=='Original FFXI' and own==2 and candidate.party_ui.groups[2].style==nil,
        'Full setup clears old per-display visual overrides using the current skin defaults.');
    assert(candidate.panels.self_buffs.mode=='icons' and candidate.panels.self_buffs.stack_direction=='horizontal'
        and candidate.panels.self_buffs.auto_height);
    local applied=copy(s);assert(page.apply(applied,options(size)) and equal(applied,candidate));
end;
for _,size in ipairs({'minimal_1_5x','minimal_2x'})do
    for _,name in ipairs(appearance.names)do
        for _,matching in ipairs({true,false})do
            local selected=options(size,name,matching,7);
            local original=copy(s);local candidate=page.build(s,selected);
            local expected=copy(s);assert(page.apply(expected,selected));
            assert(equal(candidate,expected),'The chosen skin applies with the size: '..name);
            assert(equal(s,original));protected(s,candidate);
            if not matching then
                assert(candidate.party_ui.style.icon_art==s.party_ui.style.icon_art);
                assert(candidate.style.font==s.style.font);
            end;
            assert(candidate.party_ui.name_display=='job' and candidate.style.scale==scales[size],
                'A setup keeps the member labels of detached strips.');
        end;
    end;
end;

-- Applying only a skin keeps a hand-sized layout and every non-appearance choice.
local function without_appearance(config)
    local value=copy(config);
    value.style=nil;
    return value;
end;
local skin_source=copy(s);
skin_source.party_ui.native.width=319;
skin_source.party_ui.effects.icon_size=41;
skin_source.party_ui.groups[2].detached_width,skin_source.party_ui.groups[2].detached_height=333,417;
skin_source.party_ui.style.opacity=.5;
for _,name in ipairs(appearance.names)do
    for _,matching in ipairs({true,false})do
        local chosen=options('minimal_2x',name,matching,6);
        local actual,expected=copy(skin_source),copy(skin_source);
        assert(appearance.apply(expected,name,chosen));
        assert(page.apply_skin(actual,chosen));
        assert(equal(actual,expected),'Apply skin only uses the established all-display appearance transformation.');
        assert(equal(without_appearance(actual.party_ui),without_appearance(skin_source.party_ui)),
            'Applying a skin preserves all layout, content, lock and filter fields for party_ui');
        assert(actual.party_ui.style.opacity==.5,'Applying a skin keeps the opacity of the strips.');
        protected(skin_source,actual);
    end;
end;

local before;
-- The same two choices stay discoverable on the party panel.
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local function party_draw()
    controls = {};
    s.window.open, s.window.tab = true, 'Display';
    for _, tab in ipairs(panels.tabs) do
        panels.open('party_ui', tab.key);
        MOCK.imgui_calls = {};
        window.draw(s, { rows = {}, context = {} }, { save = function() return true; end, changed = function() end, editor_changed = function() end });
        for _, call in ipairs(MOCK.imgui_calls) do
            if type(call[2]) == 'string' then controls[call[2]:match('^##frame_(.+)$') or call[2]:match('^(.-)##') or call[2]] = true; end;
        end;
    end;
end;
s.window.open, s.window.tab = true, 'Display';
before=copy(s);party_draw();
assert(equal(s,before),'Opening the panel never applies a preset.');
-- The icon size is for a panel of its own, so the party is in one here.
s.party_ui.groups[1].native_detached=true;
party_draw();
for _,label in ipairs({'Countdowns','Icon size in a panel of its own','Party buff icons','Opacity','Buff side','Longest row','Sort','Icons fill'}) do
    assert(controls[label],'Detailed customization remains reachable: '..label);
end;
