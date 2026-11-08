local calls, images, revision = {}, {}, 1;
local sizes = { newtex=128, corner=32, hfr1=32, vfr1=32, gauge=64, colorbal=64, anc=64, font=256 };
local ids = { window=10, original_font=30, xiview_font=40, party_pointer=100, xiview_pointer=110 };
local absent = {};
local function texture(kind, name)
    calls[#calls+1] = kind .. ':' .. name;
    if absent[kind] then return nil end;
    local size=sizes[name];
    if size and ids[kind] then return {id=ids[kind],width=size,height=size} end;
end;
local assets = {
    retry=function() end, retry_pending=function() return false end,
    generation=function() return revision end, prepare=function() end,
    cached_texture=texture, texture=texture,
    status=function(kind) return {available=not absent[kind],reason=absent[kind] and 'Missing fixture'} end,
};
package.loaded['ui.client_assets']=assets;
local list={AddImage=function(_,id) images[#images+1]=id end};
local function contains(id)
    for _,value in ipairs(images) do if value==id then return true end end;
    return false;
end;
local function reset() calls,images={},{} end;
local rect={x=10,y=20,width=140,height=36};
local look={gauge_art='XI View',window_type=1,
    theme='Original FFXI',opacity=1,scale=1,background=true,border=true,
    background_color={1,1,1,1},border_color={1,1,1,1},colors={background={1,1,1,1},border={1,1,1,1},track={1,1,1,1}}};
local skin=require('ui.client_skin');
reset();assert(skin.panel(list,rect,look));assert(contains(10));
local panel={colors={track={1,1,1,1}},bar_style='rail',gradient=false};
for _,case in ipairs({{'Original FFXI',30},{'XI View',40}}) do
    look.gauge_art=case[1];reset();assert(skin.gauge(list,0,0,100,8,.5,look,panel,{1,1,1,1}));assert(contains(case[2]));
end;
look.gauge_art='XI View';absent.xiview_font=true;
reset();assert(skin.gauge(list,0,0,100,8,.5,look,panel,{1,1,1,1}));assert(contains(30));
assert(skin.gauge_reason(look):find('XI View',1,true));absent.xiview_font=nil;
local theme=require('ui.party_theme');
-- A group has no look of its own; a font the look lacks comes from the timer style.
local resolved=theme.resolve({style=look},{font='Arial'});
assert(resolved.font=='Arial' and resolved.gauge_art=='XI View');
reset();assert(theme.panel(list,rect,look));assert(contains(10));
-- The gauges are drawn by the client skin, above; the party bridge has none.
assert(theme.gauge==nil,'The party bridge draws no gauges.');

-- Font aliases keep actual native metrics and use the selected atlas.
local function u16(value) return string.char(value%256,math.floor(value/256)%256) end;
local parts={};
for code=32,126 do
    local xy={0,0,9,0,0,11,9,11};local part={};
    for _,value in ipairs(xy) do part[#part+1]=u16(value) end;
    parts[#parts+1]='\1'..table.concat(part)..u16(9)..u16(11)..u16(0)..u16(0)..'\0'
        ..string.rep(string.char(127),16)..string.char(1,0,1,1)..'font    font    ';
end;
local layout='font    fontshp '..'\1'..'font    font    '..u16(95)..table.concat(parts);
local fonts=require('ui.client_fonts');assert(not fonts.is_bitmap('Follow game client'));
local named=require('ui.fonts');local found=false;
for _,name in ipairs(named.names()) do if name=='Follow game client' then found=true end end;
assert(not found,'Removed automatic artwork is absent from font choices.');

-- Icons and actions retain both manual packs.
local requested={};
assets.icon_texture=function(kind,id) requested[#requested+1]=kind;return {id=200+id} end;
assets.icon_status=function() return {available=true} end;
local icons=require('ui.icons');
assert(icons.status(1,'Original FFXI')==201 and requested[#requested]=='original');
assert(icons.status(1,'XI View')==201 and requested[#requested]=='xiview');
assets.prepare_actions=function() end;
assets.action_layout=function(kind) return layout,nil,kind end;
assets.action_texture=function(kind) requested[#requested+1]=kind;return {id=300,width=256,height=256} end;
local actions=require('ui.action_icons');actions.prepare();
for _,case in ipairs({{'Original FFXI','original'},{'XI View','xiview'}}) do
    assert(actions.draw(list,case[1],1,1,0,0,24,1));assert(requested[#requested]==case[2]);
end;

return 'Manual native rendering, fallback and removal of automatic font choices';
