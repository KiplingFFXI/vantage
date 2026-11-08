local imgui=require('imgui');
local defaults=require('ui.defaults');
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');

-- A button too wide for its row wraps its caption. It starts a new line only when something sits before it
-- on the line, so a wrapped button at the start of a row or table cell keeps its place.
local fit='Unlock all##main';
local cursor=imgui.GetCursorPosX;
local function frame(x)
    MOCK.imgui_calls={};
    imgui.GetCursorPosX=x and function() return x;end or cursor;
    window.draw(app.state.settings,{rows={},context={valid=false}},app.callbacks);
    imgui.GetCursorPosX=cursor;
    assert(#MOCK.font_stack==0);
end;
-- The layout call drawn just before the button, skipping size and position queries.
local function before_button(label)
    for index,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='Button' and call[2]==label then
            for back=index-1,1,-1 do
                local name=MOCK.imgui_calls[back][1];
                if not name:find('^Get') and not name:find('^Calc') then return name,call;end;
            end;
        end;
    end;
end;
local s=defaults.tidy(defaults.make());
s.window.open,s.window.tab=true,'Home';
app.state.settings=s;
-- The mock measures 8 px a character, so the caption is wider than this row.
MOCK.content_width=90;
frame();
local previous,button=before_button(fit);
assert(button and button[2]==fit,'Fixture: the button is drawn.');
assert(previous~='NewLine','A wrapped button at the start of its row adds no empty line above it.');
frame(400);
previous=before_button(fit);
assert(previous=='NewLine','A wrapped button after something on its line moves to the next line.');
MOCK.content_width=nil;
return 'Wrapped buttons start a new line only when something precedes them';
