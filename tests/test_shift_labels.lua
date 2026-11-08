local resize, imgui = require('ui.resize'), require('imgui');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local draw_label = resize.label;
for _, screen in ipairs({{1600,900},{90,70}}) do
    MOCK.screen=screen;
    for _, rect in ipairs({{x=0,y=0,width=24,height=24},{x=screen[1]-24,y=screen[2]-24,width=24,height=24}}) do
        MOCK.imgui_calls={};
        local before=copy(rect);
        draw_label(imgui.GetWindowDrawList(),rect,'Self debuffs',{font='Agave',font_size=12});
        local background, text, clips, fonts=0,0,0,0;
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1]=='draw:AddRectFilled' then
                background=background+1;
                assert(call[2][1]>=0 and call[2][2]>=0 and call[3][1]<=screen[1] and call[3][2]<=screen[2]);
            elseif call[1]=='draw:AddText' then text=text+1;
            elseif call[1]=='draw:PushClipRect' then clips=clips+1;
            elseif call[1]=='draw:PopClipRect' then clips=clips-1;
            elseif call[1]=='PushFont' then fonts=fonts+1;
            elseif call[1]=='PopFont' then fonts=fonts-1;
            end;
            assert(call[1]~='InvisibleButton' and call[1]~='Begin' and call[1]~='Dummy','Labels cannot add mouse targets or layout extents.');
        end;
        assert(background==1 and text>0 and clips==0 and fonts==0 and equal(rect,before));
    end;
end;
MOCK.screen={1600,900};
local labels={};
resize.label=function(_,_,label) labels[label]=true; end;
local hud, defaults = require('ui.hud'), require('ui.defaults');
local s, view=defaults.make(),hud.sample(100);
s.style.minimal,s.window.open=true,false;
for _,p in pairs(s.panels) do p.enabled=false; end;
for _, id in ipairs({'self_buffs','self_debuffs','target','party','watch','spell_recasts','ability_recasts','item_recasts','recasts'}) do
    local p=s.panels[id]; p.enabled,p.locked,p.mode,p.title=true,false,'icons','Custom heading';
    s.recast_display=id=='recasts' and 'combined' or 'separate';
    labels={};hud.draw(view,s,100,{shift=true});
    assert(labels[require('ui.elements').label(id)],id..' has an identity even with headings hidden.');
    p.locked=true; labels={};hud.draw(view,s,100,{shift=true}); assert(next(labels)==nil);
    p.locked=false; labels={};hud.draw(view,s,100,{shift=false}); assert(next(labels)==nil);
    view.context.chat_open=true; labels={};hud.draw(view,s,100,{shift=true}); assert(next(labels)==nil);
    view.context.chat_open=false;p.enabled=false;
end;
-- The party list strips name their party.
local party,native=require('ui.party_hud'),require('ui.native_party_hud');
local roster,subjects=party.sample(18,100);
local game={available=true,groups={}};
for group=1,3 do
    local frame={x=1300,y=40+(group-1)*200,width=116,height=132,rows={}};
    for _,member in ipairs(roster.members)do if member.group==group then
        frame.rows[member.slot]={x=1300,y=frame.y+member.slot%6*22,width=116,height=22,slot=member.slot};
    end;end;
    game.groups[group]=frame;
end;
local p=s.party_ui;p.enabled,p.locked=true,false;
local function strips(options) options.native_geometry=game;native.draw(roster,subjects,p,100,options);end;
labels={};strips({shift=true});
assert(labels['Your party'] and labels['Alliance 1'] and labels['Alliance 2'],'Each strip has its own label, as edit mode names it.');
p.strips.alliance1=false;labels={};strips({shift=true});
assert(labels['Your party'] and not labels['Alliance 1'],'A strip switched off has no label.');
p.strips.alliance1=true;
labels={};strips({shift=true,input_blocked=true});assert(next(labels)==nil);
p.locked=true;labels={};strips({shift=true});assert(next(labels)==nil,'A locked strip shows no size label.');
resize.label=draw_label;
