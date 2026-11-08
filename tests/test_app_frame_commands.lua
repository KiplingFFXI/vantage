-- /vg party show|hide|preview|live|lock|unlock, and Undo of settings window moves.
local events={};
local store=require('core.store');
local write=store.write;
store.write=function(path,...)
    if path:find('settings.json',1,true) then events[#events+1]='save'; end;
    return write(path,...);
end;
package.loaded['core.observer']={read=function() return {}; end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.fire('load'); app.refresh(1);
local function command(text) local event={command=text}; MOCK.fire('command',event); assert(event.blocked); end

-- Each command is one Undo step named for it, saved once.
local results={
    show={enabled=true,preview=false,hidden=false},live={enabled=true,preview=false,hidden=false},
    preview={enabled=true,preview=true,hidden=false},hide={enabled=false},
    lock={locked=true},unlock={locked=false},
};
for _,action in ipairs({'show','preview','live','lock','unlock','hide'}) do
    local p=app.state.settings.party_ui;
    p.enabled,p.preview,p.locked=not results[action].enabled,not results[action].preview,not results[action].locked;
    app.state.hidden=results[action].hidden==false;
    events={};
    local undo=app.callbacks.history_status().undo;
    command('/vg party '..action);
    p=app.state.settings.party_ui;
    for key,value in pairs(results[action]) do
        if key=='hidden' then assert(app.state.hidden==value,'party '..action..' shows the displays');
        else assert(p[key]==value,'party '..action..' sets '..key); end;
    end;
    local status=app.callbacks.history_status();
    -- Undo keeps the last 20 steps.
    assert(status.undo==math.min(undo+1,20) and status.undo_label=='Party '..action,'party '..action..' is one named Undo step');
    local order=table.concat(events,', ');
    assert(order=='save','party '..action..' saves once, not '..order);
end;
-- Showing the party list buffs with every strip off shows the Party strip, as Home does.
for _,action in ipairs({'show','live','preview'}) do
    local p=app.state.settings.party_ui;
    p.enabled,p.strips.party,p.strips.alliance1,p.strips.alliance2=false,false,false,false;
    command('/vg party '..action);
    p=app.state.settings.party_ui;
    assert(p.enabled and p.strips.party and not p.strips.alliance1 and not p.strips.alliance2,
        'party '..action..' with every strip off shows the Party strip only.');
end;
local p=app.state.settings.party_ui;
p.enabled,p.strips.party,p.strips.alliance1=false,false,true;
command('/vg party show');
p=app.state.settings.party_ui;
assert(p.enabled and not p.strips.party and p.strips.alliance1,'party show keeps the strips already chosen.');

-- A step marked as moving or resizing the settings window puts the window back on Undo and forward on Redo,
-- whatever it is called. Any other step leaves the window where it is.
local window=app.state.settings.window;
window.x,window.y,window.width,window.height=100,120,900,600;
app.callbacks.changed('before','Resize the menu',nil,true);
window.x,window.y,window.width,window.height=140,160,1000,700;
app.callbacks.changed('after'); app.callbacks.save();
assert(app.callbacks.history_status().undo_label=='Resize the menu');
assert(app.callbacks.undo()~=false);
window=app.state.settings.window;
assert(window.x==100 and window.y==120 and window.width==900 and window.height==600,'Undo puts a resized settings window back.');
assert(app.callbacks.redo()~=false);
window=app.state.settings.window;
assert(window.x==140 and window.y==160 and window.width==1000 and window.height==700,'Redo resizes the settings window again.');
command('/vg set style.font_size 21');
window=app.state.settings.window;
window.x,window.width=300,1100;
assert(app.callbacks.undo()~=false);
window=app.state.settings.window;
assert(app.state.settings.style.font_size~=21 and window.x==300 and window.width==1100,
    'Undo of another change keeps the settings window where it is.');
