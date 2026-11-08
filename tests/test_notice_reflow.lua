local hud, defaults = require('ui.hud'), require('ui.defaults');
local s=defaults.make();s.alerts.notice_width,s.alerts.notice_height=240,80;
local view={context={},notices={
    {message='First warning',visual=true,ends=100},
    {message='Second warning',visual=true,ends=100},
    {message='Newest warning',visual=true,ends=100}}};
local function text()
    local values={};
    for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='draw:AddText' then values[#values+1]=call[#call]; end; end;
    return table.concat(values,'|');
end;
MOCK.imgui_calls={};hud.draw_notices(view,s,1,{});local shown=text();
assert(shown:find('Newest warning',1,true) and not shown:find('First warning',1,true));
for value in (shown..'|'):gmatch('(.-)|') do
    assert(value=='Second warning' or value=='Newest warning','Fixed-height notices keep the newest alerts and say nothing of the others: '..shown);
end;
s.alerts.notice_height=240;MOCK.imgui_calls={};hud.draw_notices(view,s,1,{});shown=text();
assert(shown:find('First warning',1,true) and shown:find('Second warning',1,true) and shown:find('Newest warning',1,true));
assert(not shown:find('more alerts',1,true),'Resizing taller reveals retained alerts.');
s.alerts.notice_width=160;s.alerts.notice_height=80;
view.notices={{message=('abcdefghij'):rep(15),visual=true,ends=100}};
MOCK.imgui_calls={};hud.draw_notices(view,s,1,{});shown=text();
assert(not shown:find(('abcdefghij'):rep(15),1,true),'A notice too tall for its box shows the lines that fit.');
assert(shown~='' and not shown:find('More text',1,true) and not shown:find('...',1,true),'Its cut lines leave no marker: '..shown);
