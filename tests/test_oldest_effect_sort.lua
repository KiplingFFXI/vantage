local defaults, party = require('ui.defaults'), require('ui.party_defaults');
local hud, layout = require('ui.hud'), require('ui.party_layout');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local status_panels = {'self_buffs', 'self_debuffs', 'party', 'target', 'watch'};

for _,settings in ipairs({defaults.make(), defaults.tidy({})}) do
    for _,key in ipairs(status_panels) do
        assert(settings.panels[key].sort == 'longest', 'Every new status panel starts with the longest remaining duration.');
    end;
    assert(settings.party_ui.effects.sort == 'longest');
    for key in pairs(defaults.recast_panels) do
        assert(settings.panels[key].sort == 'remaining', 'Recast readiness keeps its existing default order.');
    end;
end;
for _,sort in ipairs({'longest', 'oldest', 'remaining', 'name', 'fixed'}) do
    local settings = defaults.make();
    for _,key in ipairs(status_panels) do settings.panels[key].sort = sort; end;
    settings = defaults.tidy(settings);
    for _,key in ipairs(status_panels) do assert(settings.panels[key].sort == sort, 'Saved panel order survives loading.'); end;
end;
for _,sort in ipairs({'longest', 'oldest', 'remaining', 'name'}) do
    assert(party.tidy({effects={sort=sort}}).effects.sort == sort, 'The party list buffs retain each supported manual sort.');
end;

local function effect(id, name, first_seen, sequence, remaining)
    return {effect=id, key='effect:'..id..':'..sequence, name=name, first_seen=first_seen, first_sequence=sequence,
        present=true, kind='buff', status=remaining and 'server' or 'unknown', remaining=remaining,
        deadline=remaining and 1000+remaining or nil, entity_id=1001, entity_name='Tester', scope='self'};
end;
local oldest = effect(45, 'Zulu', 10, 1, 600);
local unknown = effect(46, 'Middle', 20, 2);
local newest = effect(47, 'Alpha', 30, 3, 5);
local subject = {known=true, effects={newest, oldest, unknown}};
local options = party.make().effects;
options.sort = 'oldest';
local settings = defaults.make();
for _,key in ipairs(status_panels) do settings.panels[key].sort = 'oldest'; end;
local view = {valid=true, context={id=1001,target={id=1001}}, rows=subject.effects};
local function expect(rows, expected, message)
    assert(#rows == #expected, message..' (count)');
    for index,row in ipairs(rows) do assert(row == expected[index], message..' (position '..index..')'); end;
end;
local snapshot = copy(subject);
expect(layout.effects(subject, options), {oldest, unknown, newest}, 'Party order follows age, not expiry or alphabetical name.');
for _,key in ipairs(status_panels) do
    for _,row in ipairs(view.rows) do row.scope=key=='party' and 'party' or 'self';row.kind=key=='self_debuffs' and 'debuff' or 'buff';end;
    settings.watch_ids={1001};
    expect(hud.filter_rows(view, settings.panels[key], key, settings), {oldest, unknown, newest},
        'Every status panel keeps unknown-duration effects in their chronological position.');
end;
for _,row in ipairs(view.rows) do row.scope,row.kind='self','buff';end;
assert(equal(subject,snapshot), 'Sorting never rewrites the tracker rows.');
oldest.remaining,oldest.deadline=1,1001;
newest.remaining,newest.deadline=900,1900;
expect(layout.effects(subject, options), {oldest, unknown, newest}, 'Expiry updates cannot reshuffle chronological party icons.');
expect(hud.filter_rows(view, settings.panels.self_buffs, 'self_buffs', settings), {oldest, unknown, newest},
    'Expiry updates cannot reshuffle chronological status panels.');

local second, tenth = effect(33, 'Protect', 50, 2), effect(33, 'Protect', 50, 10);
local duplicates = {known=true,effects={tenth,second}};
expect(layout.effects(duplicates, options), {second,tenth}, 'Same-second duplicate icons use numeric observation order.');
view.rows=duplicates.effects;
expect(hud.filter_rows(view,settings.panels.self_buffs,'self_buffs',settings), {second,tenth},
    'Status duplicate icons use numeric order instead of sorting 10 before 2.');
second.first_seen=60;
expect(layout.effects(duplicates,options), {tenth,second}, 'Cached party order notices changed observation time.');
second.first_seen=50;second.first_sequence=12;
expect(layout.effects(duplicates,options), {tenth,second}, 'Cached party order notices changed observation sequence.');
second.first_sequence=1;
expect(layout.effects(duplicates,options), {second,tenth}, 'An age-only change invalidates an otherwise identical selection.');
expect(hud.filter_rows(view,settings.panels.self_buffs,'self_buffs',settings), {second,tenth},
    'Separate panels follow corrected age metadata too.');
second.first_seen,second.first_sequence=nil,nil;
expect(layout.effects(duplicates,options), {tenth,second}, 'Missing age sorts after a known observation.');

view.rows=subject.effects;
options.exclude={46};
expect(layout.effects(subject,options), {oldest,newest}, 'Changing filters refreshes the cached chronological selection.');
options.exclude={};options.pinned={47};
expect(layout.effects(subject,options), {newest,oldest,unknown}, 'Explicit pins still take priority.');
options.pinned={};options.sort='name';
expect(layout.effects(subject,options), {newest,unknown,oldest}, 'Name sorting remains available after chronological sorting.');
options.sort='remaining';
expect(layout.effects(subject,options), {oldest,newest,unknown}, 'Remaining-time sorting remains available.');
options.sort='oldest';
expect(layout.effects(subject,options), {oldest,unknown,newest}, 'Changing back to oldest clears the prior sort selection.');
local panel=settings.panels.self_buffs;
panel.exclude={46};expect(hud.filter_rows(view,panel,'self_buffs',settings), {oldest,newest}, 'Panel filters retain chronological order.');
panel.exclude={};panel.pinned={47};
expect(hud.filter_rows(view,panel,'self_buffs',settings), {newest,oldest,unknown}, 'Panel pins still take priority.');
panel.pinned={};panel.sort='fixed';panel.order={46,47,45};
expect(hud.filter_rows(view,panel,'self_buffs',settings), {unknown,newest,oldest}, 'Manual panel ordering remains available.');
panel.sort='name';expect(hud.filter_rows(view,panel,'self_buffs',settings), {newest,unknown,oldest}, 'Panel name sorting remains available.');
panel.sort='remaining';expect(hud.filter_rows(view,panel,'self_buffs',settings), {oldest,newest,unknown}, 'Panel expiry sorting remains available.');
panel.sort='oldest';panel.order={};

local chronological={};
for index=1,7 do
    local remaining=index~=4 and 400-index or nil;
    chronological[index]=effect(39+index,'Effect '..(8-index),100+index,index,remaining);
end;
subject.effects={chronological[7],chronological[2],chronological[5],chronological[1],chronological[6],chronological[3],chronological[4]};
for _,side in ipairs({'left','right'}) do
    local p=party.make();
    p.effects.sort='oldest';
    p.effects.icon_size=24;
    local area={x=40,y=60,width=86,height=900,align_right=side=='left'};
    local rows=layout.effects(subject,p.effects);
    expect(rows,chronological,'Party sorting is independent of the side the strip sits on.');
    local positions={};
    for _,growth in ipairs({'right','left'}) do
        p.effects.growth=growth;
        local cells,hidden=layout.effect_cells(rows,p.effects,area);
        assert(#cells==7 and hidden==0 and cells[7].y>cells[1].y, 'Both directions wrap every selected icon.');
        for index,cell in ipairs(cells) do
            assert(cell.effect==chronological[index], 'The oldest icon starts each visual traversal.');
            if index>1 and cell.y==cells[index-1].y then
                assert(growth=='left' and cell.x<cells[index-1].x or growth=='right' and cell.x>cells[index-1].x,
                    'Chronological traversal follows the selected horizontal growth direction.');
            end;
        end;
        positions[growth]=cells;
    end;
    -- Each row keeps against the side nearest the game's rows, so a row mirrors within its own width.
    local first,last={},{};
    for _,cell in ipairs(positions.right) do
        first[cell.y],last[cell.y]=math.min(first[cell.y] or cell.x,cell.x),math.max(last[cell.y] or cell.x,cell.x+cell.width);
    end;
    for index,cell in ipairs(positions.right) do
        assert(cell.y==positions.left[index].y and math.abs(cell.x+positions.left[index].x+cell.width-(first[cell.y]+last[cell.y]))<.001,
            'Mirroring moves the same chronological icon to the matching position.');
    end;
end;

local fonts=require('ui.fonts');
fonts.measure=function(_,text,size)return #text*size*.5;end;
fonts.draw=function()return false;end;
require('ui.icons').status=function(id)return 100000+id;end;
require('ui.recast_icons').draw=function(list,row,_,x,y,size)
    list:AddImage(100000+row.effect,{x,y},{x+size,y+size});return true;
end;
MOCK.screen={1600,1000};
view.rows=subject.effects;
for _,mode in ipairs({'bars','expanded','icons'}) do
    for _,stack in ipairs({'horizontal','vertical'}) do
        settings=defaults.make();
        settings.style.font,settings.style.font_size='Original FFXI',12;
        settings.style.scale,settings.style.gap,settings.style.bar_height,settings.style.icon_size=1,4,36,24;
        settings.style.minimal=true;
        for id,p in pairs(settings.panels) do p.enabled=id=='self_buffs';end;
        panel=settings.panels.self_buffs;
        panel.sort='oldest';
        panel.mode,panel.stack_direction,panel.item_width=mode,stack,180;
        panel.x,panel.y,panel.width=100,100,mode=='icons' and 160 or 640;
        panel.auto_width,panel.auto_height,panel.height_limit=false,false,mode=='icons' and 100 or mode=='expanded' and 240 or 180;
        panel.wrap,panel.locked,panel.show_heading,panel.show_target,panel.show_source=true,true,false,false,false;
        for _,growth in ipairs({'right','left'}) do
            panel.growth=growth;
            local saved=copy(settings);
            MOCK.imgui_calls={};
            hud.draw(view,settings,100,{shift=false});
            local pictures={};
            for _,call in ipairs(MOCK.imgui_calls) do
                if call[1]=='draw:AddImage' and type(call[2])=='number' and call[2]>=100000 then
                    local at=MOCK.drawn[call][3];
                    pictures[#pictures+1]={id=call[2]-100000,x=at[1],y=at[2]};
                end;
            end;
            assert(#pictures==7, 'Separate panels display every chronological icon in every mode.');
            for index,picture in ipairs(pictures) do
                assert(picture.id==chronological[index].effect, 'The drawn status cells begin with the oldest effect.');
            end;
            if stack=='horizontal' then
                assert(pictures[7].y>pictures[1].y, 'Horizontal chronological panels wrap down.');
                assert(growth=='left' and pictures[2].x<pictures[1].x or growth=='right' and pictures[2].x>pictures[1].x);
            else
                assert(pictures[2].x==pictures[1].x and pictures[2].y>pictures[1].y, 'Vertical panels fill downward in chronological order.');
                assert(growth=='left' and pictures[7].x<pictures[1].x or growth=='right' and pictures[7].x>pictures[1].x,
                    'Wrapped vertical columns follow the selected growth direction.');
            end;
            assert(equal(settings,saved), 'Drawing preserves appearance, sizing, saved order and locks.');
        end;
    end;
end;
assert(#MOCK.commands==0, 'Sorting never issues gameplay commands.');
return 'Longest-remaining defaults, retained chronological sorting, alternatives, cache invalidation and mirrored wrapped status layouts';
