local resize=require('ui.resize');
local expected={'top_left','top','top_right','left','right','bottom_left','bottom','bottom_right'};
for _,size in ipairs({{300,200},{300,24},{24,200},{24,24},{3,3},{1,1}}) do
    local rect={x=20,y=30,width=size[1],height=size[2]};
    local fills,lines={},{};
    local list={
        AddRect=function() end,
        AddRectFilled=function(_,a,b,color) fills[#fills+1]={a=a,b=b,color=color}; end,
        AddLine=function(_,a,b) lines[#lines+1]={a=a,b=b}; end,
    };
    resize.hint(list,rect,0x10223344,'bottom_right');
    assert(#fills==8 and #lines==2,'Eight visible handles and both selected corner axes.');
    for index,fill in ipairs(fills) do
        assert(fill.a[1]>=rect.x and fill.a[2]>=rect.y and fill.b[1]<=rect.x+rect.width and fill.b[2]<=rect.y+rect.height);
        assert(resize.grip(rect,(fill.a[1]+fill.b[1])/2,(fill.a[2]+fill.b[2])/2)==expected[index], 'Visible handle matches the hit area.');
        assert(require('bit').band(require('bit').rshift(fill.color,24),255)==255,'Editing handles remain visible at low display opacity.');
    end;
    assert(resize.grip(rect,rect.x+rect.width/2,rect.y+rect.height/2)==nil,'The center remains a move area.');
    assert(resize.grip(rect,rect.x-1,rect.y)==nil,'Editing never captures outside the display.');
end;
local thin={x=0,y=0,width=300,height=24};
assert(resize.grip(thin,12,12)=='left' and resize.grip(thin,288,12)=='right','A short frame keeps wide horizontal grab areas.');
local tall={x=0,y=0,width=24,height=300};
assert(resize.grip(tall,12,12)=='top' and resize.grip(tall,12,288)=='bottom','A narrow frame keeps tall vertical grab areas.');
return true;
