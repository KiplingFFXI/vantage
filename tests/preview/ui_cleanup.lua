-- Offscreen ImGui only: exercise the fixed display controls above a scrolled page.
local app, imgui = assert(PREVIEW.addon), require('imgui');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local history_value = require('core.customization').history_value;
local page = PREVIEW.cleanup_page or 'Party & alliance';
local party = page == 'Party & alliance';
local s = app.state.settings;
s.window.tab, s.window.open, s.window.x, s.window.y = party and 'Display' or page, true, 40, 40;
-- Party list buffs' Size and place tab, with the party in a panel of its own and both folds open, is long enough to scroll.
if party then
    require('ui.panel_frame').open('party_ui', 'place');
    s.party_ui.groups[1].native_detached = true;
    s.window.sections['Party & alliance/Panels of their own'] = true;
    s.window.sections['Party & alliance/Detached panel members'] = true;
else
    -- Recasts' Size and place tab, as its Show tab fits even the shortest window.
    require('ui.panel_frame').open('recasts', 'place');
end;
s.style.font, s.window_style.font_size = 'Agave', PREVIEW.cleanup_font or 16;
s.enabled, s.preview, s.recast_display = true, false, 'combined';
s.party_ui.enabled, s.party_ui.preview, s.party_ui.locked = true, false, true;
s.alerts.notice_locked = true;
for _, panel in pairs(s.panels) do panel.locked = true; end;
s.panels.recasts.enabled = true;
local function object(settings)
    if party then return settings.party_ui; end;
    return settings.panels.recasts;
end;
local function preview_object(settings)
    return page=='Recasts' and settings or object(settings);
end;
local begin_child, input = imgui.BeginChild, imgui.InputTextWithHint;
imgui.BeginChild = function(label,...)
    local visible=begin_child(label,...);
    if label=='##settings_page' then
        local x,y=imgui.GetWindowPos(); local w,h=imgui.GetWindowSize();
        PREVIEW.body={x=x,y=y,width=w,height=h};
        PREVIEW.page_scroll=imgui.GetScrollY();
    end;
    return visible;
end;
imgui.InputTextWithHint = function(label,hint,value,...)
    local result=input(label,hint,value,...);
    if label=='##find_settings' then PREVIEW.search_value=value[1]; end;
    return result;
end;
local headers={'Undo','Redo','##find_settings','Show samples##frame','Locked##frame'};
local baseline, header_bounds;
local function visible_header()
    local win=app.state.settings.window;
    local out={};
    for _, label in ipairs(headers) do
        local rect=PREVIEW_PY.item_bounds(label);
        if #rect~=4 then rect=PREVIEW_PY.item_bounds('##'..label); end;
        assert(#rect==4, 'Header control was not drawn: '..label);
        assert(rect[1]>=win.x and rect[2]>=win.y and rect[3]<=win.x+win.width and rect[4]<=win.y+win.height,
            'Header control must fit: '..label..' '..table.concat(rect,','));
        out[label]=rect;
    end;
    return out;
end;
function PREVIEW.cleanup_capture()
    assert(PREVIEW.body and PREVIEW.body.height>=80,'The scrollable page retains usable height');
    baseline=history_value(app.state.settings);
    header_bounds=visible_header();
    app.state.history,app.state.redo,app.state.transaction={},{},nil;
end;
function PREVIEW.cleanup_scrolled()
    assert(PREVIEW.page_scroll>50,'The real page must scroll before checking fixed controls');
    assert(equal(visible_header(),header_bounds),'Scrolling content cannot move the display controls');
    assert(equal(history_value(app.state.settings),baseline),'Scrolling does not edit settings');
end;
function PREVIEW.cleanup_check(locked,preview,edits)
    local expected=copy(baseline);
    object(expected).locked=locked;
    preview_object(expected).preview=preview;
    assert(equal(history_value(app.state.settings),expected),'Lock and preview each change only their own setting');
    assert(object(app.state.settings).locked==locked and preview_object(app.state.settings).preview==preview);
    assert(#app.state.history==edits and not app.state.transaction,'Each explicit checkbox click is one completed edit');
    visible_header();
end;
function PREVIEW.cleanup_top()
    assert(PREVIEW.page_scroll<=1,'The body can scroll back to its first controls');
    assert(equal(visible_header(),header_bounds),'The header remains fixed after scrolling back');
end;
return function()
    MOCK.frame(1/60);
    PREVIEW.settings=app.state.settings;
    if PREVIEW.frame==PREVIEW.last_frame then
        PREVIEW.cleanup_check(true,false,4);
        assert(#MOCK.commands==0,'UI layout tests never issue gameplay commands');
        PREVIEW.log('Fixed header lock, preview, search and scrolling passed',page,PREVIEW.cleanup_font);
    end;
end;
