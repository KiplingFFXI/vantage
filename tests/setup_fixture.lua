-- A whole setup, and a skin alone, for the fixtures that start from one.
local defaults, appearance, setup = require('ui.defaults'), require('ui.appearance'), require('ui.setup_defaults');
local copy = require('core.store').copy;
local placement={'x','y','locked','anchor','dock_match_width'};
local selection={'include','exclude','pinned','order','labels','groups','members','filter','mine_only','known_only','recast_categories',
    'dispel_light','list_debuffed'};
-- The party list strips keep their switches, their member labels and the sample switch as they are.
local strip_state={'enabled','preview','strips','locked','name_display','name_length'};
local font_art={'font','gauge_art','icon_art','recast_icon_art'};
local function keep(destination,source,keys)
    for _,key in ipairs(keys)do if source[key]~=nil then destination[key]=copy(source[key]);end;end;
end;

-- One complete display recipe, which fixtures start from; user data and activation choices remain separate. The
-- addon runs none: /vg starter is a starter profile (core/starters.lua), and the Size buttons set the scale and
-- re-space.
local sizes={minimal=1,minimal_1_5x=1.5,minimal_2x=2};
local function apply(settings,options)
    local factor=options and sizes[options.size];
    if not factor then return false;end;
    local fresh=defaults.make();
    local skin=options.skin=='keep' and appearance.candidate(settings) or options.skin;
    local old={alerts=settings.alerts,recast_display=settings.recast_display,placement_screen=settings.placement_screen,
        pet=settings.pet,rolls=settings.rolls,party_cooldowns=settings.party_cooldowns};
    keep(fresh.party_ui.effects,settings.party_ui.effects,selection);
    -- Effect types, which Buffs only and Debuffs only also set, is a filter too. Party countdowns, the light, and the
    -- icon size, which only sets a panel of its own, are the player's own picks, so they stay as well.
    keep(fresh.party_ui.effects,settings.party_ui.effects,{'kind','timers','icon_size','cleanse_light'});
    for index,group in ipairs(fresh.party_ui.groups)do
        keep(group,settings.party_ui.groups[index],{'order','native_x','native_y','native_side','native_detached','detached_x','detached_y'});
    end;
    for _,id in ipairs(defaults.panel_order)do
        local panel,old_panel=fresh.panels[id],settings.panels[id];
        keep(panel,old_panel,placement);keep(panel,old_panel,selection);
        panel.enabled=old_panel.enabled;
        -- Each panel keeps its Box, Show its heading and Heading.
        keep(panel,old_panel,{'box','show_heading','title'});
        -- Party timers and Watched enemies start as bars only on a fresh install, so an apply keeps their layout.
        if id=='party' or id=='watch' then keep(panel,old_panel,{'mode','stack_direction'});end;
        for _,key in ipairs({'width','min_width','max_width','height_limit'})do panel[key]=panel[key]*factor;end;
    end;
    if options.matching==false then
        keep(fresh.style,settings.style,font_art);
        keep(fresh.party_ui.style,settings.party_ui.style,{'icon_art'});
    end;
    if not appearance.apply(fresh,skin,{matching=options.matching~=false,window_type=options.window_type or settings.style.window_type})
        then return false;end;
    fresh.style.scale=factor;
    keep(fresh.party_ui,settings.party_ui,strip_state);
    -- Settings text size stays as the user set it. Alert notices keep their saved width, height and count, and are
    -- drawn at the setup's size like the timer panels.
    keep(fresh.window_style,settings.window_style or {},{'font_size'});
    for _,key in ipairs({'party_ui','panels','style','window_style'})do
        old[key]=settings[key];
        settings[key]=fresh[key];
    end;
    -- Overhead icons keep their switches, layouts and filters, take the size through style.scale, and their colors
    -- start again.
    appearance.overhead_look(settings.overhead);
    -- The Phantom Roll and pet displays the same way.
    appearance.element_look(settings);
    if options.screen_width then
        setup.respace(old,settings,{width=options.screen_width,height=options.screen_height,chat=options.chat});
    end;
    return true;
end;

local fixture = { apply = apply };

function fixture.apply_skin(settings, options)
    return appearance.apply(settings, options.skin, { matching = options.matching ~= false, window_type = options.window_type });
end;

function fixture.build(settings, options)
    local candidate = require('core.store').copy(settings);
    if apply(candidate, options) then return candidate; end;
end;

return fixture;
