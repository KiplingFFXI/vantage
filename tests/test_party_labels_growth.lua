local party,layout,labels=require('ui.party_defaults'),require('ui.party_layout'),require('ui.party_labels');
local copy,equal=require('core.store').copy,require('core.customization').equal;
local config=party.make();
assert(config.effects.growth=='right');
local missing=copy(config);missing.effects.growth=nil;
assert(equal(party.tidy(missing),party.tidy(copy(config))),'A save without a growth gains the default without changing its other choices.');
for _,mode in ipairs({'full','short','job','job_icon','icon'}) do
    local p=party.make();p.name_display=mode;
    local known={name='Longplayername',job=1};
    assert(labels.member_name(known,p)==(mode=='full' and known.name or mode=='short' and 'Longpla.' or 'WAR'));
    assert(labels.member_name({name='Player'},p)=='Player','Unavailable jobs retain the player identity.');
    assert(party.tidy(copy(p)).name_display==mode);
end;
local effects={};for i=1,12 do effects[i]={effect=i,name='Effect '..i,kind=i<=6 and 'buff' or 'debuff',status='unknown',present=true};end;
for _,separate in ipairs({false,true})do
    for _,width in ipairs({40,80,180,400})do
        for _,wrapped in ipairs({false,true})do
            local options=copy(config.effects);options.separate,options.wrap,options.rows=separate,wrapped,8;
            -- An area with no side, as a panel of its own has, so no row keeps to a side.
            local area={x=13,y=27,width=width,height=900};
            options.growth='right';local forward,hidden,height=layout.effect_cells(effects,options,area);
            options.growth='left';local reverse,reverse_hidden,reverse_height=layout.effect_cells(effects,options,area);
            assert(#forward==#reverse and hidden==reverse_hidden and height==reverse_height);
            assert(forward[1].x==area.x and reverse[1].x+reverse[1].width==area.x+area.width);
            for index,cell in ipairs(forward)do
                local mirrored=reverse[index];
                assert(mirrored.effect==cell.effect and mirrored.y==cell.y and mirrored.width==cell.width and mirrored.height==cell.height);
                assert(math.abs(cell.x+mirrored.x+cell.width-(area.x*2+area.width))<.001);
                assert(mirrored.x>=area.x and mirrored.x+mirrored.width<=area.x+area.width and mirrored.y+mirrored.height<=area.y+area.height);
                if index>1 and cell.y==forward[index-1].y then
                    assert(cell.x>forward[index-1].x and mirrored.x<reverse[index-1].x);
                end;
            end;
        end;
    end;
end;
for _,growth in ipairs({'left','right'})do
    local p=party.make();p.effects.growth=growth;
    assert(party.tidy(copy(p)).effects.growth==growth,'A saved growth direction stays.');
end;
local invalid=party.make();invalid.effects.growth='up';
invalid=party.tidy(invalid);assert(invalid.effects.growth=='right');
