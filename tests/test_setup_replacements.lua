local defaults=require('ui.defaults');
local custom=require('core.customization');
local page=require('setup_fixture');
local s=defaults.make();
s.enabled,s.preview=false,true;
s.party_ui.enabled,s.party_ui.preview=false,true;
s.party_ui.strips.party,s.party_ui.strips.alliance1=false,true;
s.party_ui.locked=false;
s.party_ui.style.icon_art='Client';
s.panels.self_buffs.enabled,s.panels.self_debuffs.enabled=false,false;
s.panels.self_buffs.locked,s.panels.self_debuffs.locked=true,false;
s.panels.self_buffs.x,s.panels.self_buffs.y=145,267;
s.panels.self_debuffs.width=321;
s.panels.self_buffs.exclude={33};
s.effect_filters.rules={{enabled=true,effect=253,kind='all',name='Sample',job=0,scope='self'}};
s=defaults.tidy(s);
local function value() return custom.history_value(s);end;
local original=value();

-- The whole-setup code behind exports and starters: what it keeps.
local selection={skin='keep',size='minimal_1_5x',screen_width=1600,screen_height=900};
local expected=page.build(s,selection);
assert(custom.equal(value(),original),'Building a candidate is read only.');
assert(page.apply(s,selection),'The setup applies.');
assert(custom.equal(value(),custom.history_value(expected)),'Apply gives the candidate.');
assert(s.style.scale==1.5 and not s.party_ui.enabled and s.party_ui.preview
    and not s.party_ui.strips.party and s.party_ui.strips.alliance1,
    'It keeps the party list buffs switches and sample as they are.');
assert(not s.enabled and s.preview
    and not s.panels.self_buffs.enabled and not s.panels.self_debuffs.enabled,'It keeps the switches as they are.');
assert(s.party_ui.locked==original.party_ui.locked and s.panels.self_buffs.locked==original.panels.self_buffs.locked
    and s.panels.self_debuffs.locked==original.panels.self_debuffs.locked,'A setup never changes saved locks.');
assert(custom.equal(s.effect_filters,original.effect_filters) and custom.equal(s.panels.self_buffs.exclude,original.panels.self_buffs.exclude));
assert(#MOCK.commands==0,'A setup issues no gameplay commands.');

return 'The whole-setup code keeps the switches';
