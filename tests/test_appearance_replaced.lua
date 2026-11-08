local defaults=require('ui.defaults');
local copy=require('core.store').copy;
local appearance=require('ui.appearance');
local presets=require('setup_fixture');

-- appearance.replaced names the displays with their own look that a change would draw differently,
-- read the way describe reads them, so a question names only what it replaces.
local function fresh() return defaults.tidy(defaults.make());end;
local function labels(list)
    local out={};
    for index,entry in ipairs(list)do out[index]=entry.label;end;
    return table.concat(out,'|');
end;
local function agave(s)
    s.style.font='Agave';
    return s;
end;

-- Without the changed settings it is every display with its own look.
local s=agave(fresh());
s.overhead.countdown_color={1,0,0,1};
local _,differences=appearance.describe(s);
assert(#differences>=2 and labels(appearance.replaced(s))==labels(differences),'Without a result every listed display is named.');

-- Kept fonts are not replaced; matched fonts are.
s=agave(fresh());
_,differences=appearance.describe(s);
local kept=presets.build(s,{skin='keep',size='minimal',matching=false,window_type=s.style.window_type});
assert(kept and #appearance.replaced(s,kept)==0,'A size that keeps fonts replaces no look when only fonts differ.');
local matched=presets.build(s,{skin='keep',size='minimal',matching=true,window_type=s.style.window_type});
assert(labels(appearance.replaced(s,matched))==labels(differences),'Matching fonts replaces every display whose font differs.');

-- A look it replaces beside fonts it keeps: only that display is named.
s=agave(fresh());
s.panels.self_buffs.colors={background={1,0,0,1}};
kept=presets.build(s,{skin='keep',size='minimal',matching=false,window_type=s.style.window_type});
assert(labels(appearance.replaced(s,kept))=='Self buffs','Only the replaced Self buffs look is named.');

-- The party list buffs wear the timer panels' look, so only a change to their own icons names them.
s=fresh();
s.party_ui.style.icon_art='XI View';
_,differences=appearance.describe(s);
assert(labels(differences)=='Party buff icons','Fixture: the party buff icons are listed.');
local result=copy(s);
assert(#appearance.replaced(s,result)==0,'An unchanged copy replaces nothing.');
result.party_ui.style.icon_art='Original FFXI';
assert(labels(appearance.replaced(s,result))=='Party buff icons','The party buff icons are named when they change.');

-- Unset values read as describe reads them, and saved colors may round a little.
s=fresh();
s.style.font,s.style.background='Agave',nil;
s.panels.self_buffs.colors.background={0.2,0.3,0.4,1};
result=copy(s);
result.style.background=true;
s.panels.self_buffs.colors.background[1]=0.1995;
_,differences=appearance.describe(s);
assert(labels(differences):find('Self buffs',1,true) and labels(differences):find('Shared timer appearance',1,true),
    'Fixture: Self buffs and the timer panels are listed.');
assert(#appearance.replaced(s,result)==0,'Unset frame values and rounded colors are not a replaced look.');
result.panels.self_buffs.colors.background={1,0,0,1};
assert(labels(appearance.replaced(s,result))=='Self buffs','A changed panel color is.');
return 'appearance.replaced names only the looks a change would replace';
