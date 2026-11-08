local defaults,presets=require('ui.defaults'),require('setup_fixture');
local appearance=require('ui.appearance');

-- The whole-setup code keeps the menu text size and the alert notice size and count.
local function seed()
    local s=defaults.tidy(defaults.make());
    s.window_style.font_size=29;
    s.alerts.notice_width,s.alerts.notice_height,s.alerts.max_notices=512,96,9;
    return s;
end;
local skins={'keep'};
for _,name in ipairs(appearance.names)do skins[#skins+1]=name;end;
local factors={minimal=1,minimal_1_5x=1.5,minimal_2x=2};
for size,factor in pairs(factors)do for _,skin in ipairs(skins)do for _,matching in ipairs({true,false})do
    local s=seed();
    -- A key nothing reads.
    local options={size=size,skin=skin,matching=matching,window_type=3};
    assert(presets.apply(s,options),'The setup applies: '..size..' '..skin);
    assert(s.style.scale==factor,'The rest of the setup applies.');
    assert(s.window_style.font_size==29,'Menu text size stays as set: '..size..' '..skin);
    assert(s.alerts.notice_width==512 and s.alerts.notice_height==96 and s.alerts.max_notices==9,
        'Alert notice width, height and count stay as set: '..size..' '..skin);
end;end;end;
-- A table without a menu look still applies.
local bare=defaults.make();bare.window_style=nil;
assert(presets.apply(bare,{size='minimal',skin='keep'}) and bare.window_style.font_size==defaults.make().window_style.font_size,
    'A setup without a saved menu look uses the default menu text size.');
return 'A whole setup keeps menu text size and alert notices';
