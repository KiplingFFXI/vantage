local party,layout,hud=require('ui.party_defaults'),require('ui.party_layout'),require('ui.party_hud');
local copy,equal=require('core.store').copy,require('core.customization').equal;

local function effects(count)
    local out={};
    for index=1,count do
        out[index]={effect=index,name='Effect '..index,kind=index%3==0 and 'debuff' or 'buff',status='exact',
            present=true,remaining=index*120,total=7200};
    end;
    return out;
end;

local function row_bounds(cells)
    local rows={};
    for _,cell in ipairs(cells) do
        local row=rows[cell.y] or {left=math.huge,right=-math.huge};rows[cell.y]=row;
        row.left,row.right=math.min(row.left,cell.x),math.max(row.right,cell.x+cell.width);
    end;
    return rows;
end;

for _,side in ipairs({'left','right','below'}) do
    for _,growth in ipairs({'left','right'}) do
        for _,separate in ipairs({false,true}) do
            for _,count in ipairs({1,3,17,32}) do
                local options=copy(party.make().effects);
                options.growth,options.separate=growth,separate;
                options.icon_size,options.font_size=16,32;
                options.wrap_text,options.wrap,options.fit_all=true,true,true;
                options.text_measure=function(value) return #value*16; end;
                options.measure_key='snap-countdown-test';
                local area={x=19,y=27,width=240,height=10000};
                if side~='below' then area.align_right=side=='left'; end;
                local selected=effects(count);
                -- The same area with no side, so no row keeps to one, against the strip's.
                local before,old_omitted,old_height=layout.effect_cells(selected,options,{x=area.x,y=area.y,width=area.width,height=area.height});
                local old_rows=row_bounds(before);
                local after,omitted,height=layout.effect_cells(selected,options,area);
                local rows=row_bounds(after);
                assert(#before==count and #after==count and omitted==0 and old_omitted==0 and old_height==height);
                for index,cell in ipairs(after) do
                    local old=before[index];
                    assert(cell.effect==old.effect and cell.y==old.y and cell.width==old.width and cell.height==old.height,
                        'Snapping does not reorder, resize or hide effects and their countdowns.');
                    assert(cell.x>=area.x-.001 and cell.x+cell.width<=area.x+area.width+.001);
                    local row,old_row=rows[cell.y],old_rows[cell.y];
                    local shift=side=='left' and area.x+area.width-old_row.right or side=='right' and area.x-old_row.left or 0;
                    assert(math.abs(cell.x-old.x-shift)<.001, 'Every cell in a wrapped row moves by the same amount.');
                    if side=='left' then assert(math.abs(row.right-area.x-area.width)<.001);
                    elseif side=='right' then assert(math.abs(row.left-area.x)<.001);
                    else assert(cell.x==old.x, 'Target and below-frame areas without a side flag keep their original alignment.'); end;
                    if index>1 and after[index-1].y==cell.y then
                        local prior=after[index-1];
                        assert(growth=='left' and cell.x+cell.width<=prior.x or growth=='right' and cell.x>=prior.x+prior.width,
                            'Both growth directions keep their order and spacing.');
                    end;
                end;
            end;
        end;
    end;
end;

local options=copy(party.make().effects);
options.icon_size,options.measure_key=16,'snap-toggle-test';
local selected=effects(3);
for _,growth in ipairs({'left','right'}) do
    options.growth=growth;
    for _,side in ipairs({'left','right','below'}) do
        local area={x=10,y=20,width=240,height=80};
        if side~='below' then area.align_right=side=='left'; end;
        for _=1,2 do
            local cells=layout.effect_cells(selected,options,area);
            local row=row_bounds(cells)[20];
            local right=side=='left' or side=='below' and growth=='left';
            assert(right and row.right==250 or not right and row.left==10,
                'Cached placement follows the selected side and growth independently.');
        end;
    end;
end;

-- A strip beside the game's rows always snaps, so there is no switch. A shared layout brings its growth and keeps the
-- local lock.
local defaults=require('ui.defaults');
assert(party.make().effects.snap_to_frame==nil, 'Fresh settings have no snapping switch.');
local profiles=require('core.profiles').new(MOCK_INSTALL_PATH..'/config/addons/vantage');
for _,scope in ipairs({'placement','presentation'}) do
    local settings=defaults.make();
    settings.party_ui.effects.growth='left';
    assert(profiles:save_layout(settings,scope));
    local restored=defaults.make();restored.party_ui.locked=false;
    assert(profiles:load_layout(restored,scope));
    assert(restored.party_ui.effects.growth=='left' and not restored.party_ui.locked,
        'A shared layout brings its growth and keeps the local lock.');
end;

-- Short rows of a strip beside the game's party list sit next to its window, the gap away, on either side.
local native=require('ui.native_party_hud');
for _,side in ipairs({'left','right'}) do
    for _,growth in ipairs({'left','right'}) do
        local config=party.make();
        config.enabled,config.native.side,config.native.gap,config.native.width=true,side,2,240;
        config.effects.growth,config.effects.icon_size=growth,16;
        local roster,subjects=hud.sample(6,100);
        for _,member in ipairs(roster.members) do subjects[member.id]={known=true,effects=effects(3)}; end;
        local frame={x=800,y=100,width=116,height=6*32,rows={}};
        for _,member in ipairs(roster.members) do
            frame.rows[member.slot]={x=800,y=100+member.slot*32,width=116,height=32,slot=member.slot};
        end;
        local saved=copy(config);
        local plan=native.plan(roster,subjects,config,{available=true,groups={frame}},1600,900)[1];
        assert(plan and #plan.rows==6,'Fixture: the strip has a row for each member.');
        for _,item in ipairs(plan.rows) do
            local chosen=layout.effects(subjects[item.member.id],item.options);
            local cells=layout.effect_cells(chosen,item.options,item.area);
            local bounds=row_bounds(cells)[cells[1].y];
            assert(side=='left' and math.abs(frame.x-bounds.right-2)<.001
                or side=='right' and math.abs(bounds.left-frame.x-frame.width-2)<.001,
                'Short buff and debuff rows sit beside the game window\'s outside edge.');
        end;
        assert(equal(config,saved) and config.locked, 'Snapping never unlocks or moves saved strips.');
    end;
end;

return 'Window-facing snapping preserves wrapped rows, countdown cells, growth, caches, saved settings and locks';
