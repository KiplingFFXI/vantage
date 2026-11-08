local defaults=require('ui.defaults');
local anchors=require('core.anchors');
local setup={};
-- The Size buttons re-space what is still where a fresh install, or an earlier apply, put it: the timer
-- panels, the alert notices, the Pet display and the Phantom Roll display. A fresh install does the same on its first
-- frame with a screen (setup.place_fresh).
-- Panels flow left to right at their new size from where their row starts, wrap at the screen edge, and skip the
-- chat log, the game's own party list and target window, and every display the player placed. One with no free spot
-- on screen goes back to its fresh spot, so where they end up depends only on the size, the screen and the chat log.
-- Their sizes are estimates with room to spare, so nothing has to be drawn first. The Pet display and then the Phantom
-- Roll display go last, each from its starting spot, so neither moves a panel.
local GAP=15;
local ROWS={{y=120,ids={'self_buffs','self_debuffs','target','item_recasts'}},
    {y=420,ids={'party','watch','spell_recasts','ability_recasts'}}};
-- Two rolls with every line on, the most a corsair has up alone, in the lines box_rect counts.
local ROLL_LINES=7;

local function overlaps(a,b)
    return a.x<b.x+b.width and b.x<a.x+a.width and a.y<b.y+b.height and b.y<a.y+a.height;
end;
local function free(rect,taken)
    for _,other in ipairs(taken)do if overlaps(rect,other) then return false;end;end;
    return true;
end;

-- The first free spot in reading order at or after origin that fits the screen. Rows start at origin.x.
local function spot(width,height,origin,taken,screen,also_x)
    local xs,ys={origin.x,also_x},{origin.y};
    for _,rect in ipairs(taken)do xs[#xs+1],ys[#ys+1]=rect.x+rect.width+GAP,rect.y+rect.height+GAP;end;
    table.sort(xs);table.sort(ys);
    for _,y in ipairs(ys)do
        if y>=origin.y and y+height<=screen.height then
            for _,x in ipairs(xs)do
                local rect={x=math.floor(x),y=math.floor(y),width=width,height=height};
                if x>=origin.x and x+width<=screen.width and free(rect,taken) then return rect;end;
            end;
        end;
    end;
end;

-- Bitmap client fonts sit tighter than the Agave family.
local function bitmap(font) return font=='Original FFXI' or font=='XI View';end;

local function panel_height(panel,style)
    if panel.auto_height==false then return panel.height_limit;end;
    local scale=style.scale or 1;
    if panel.mode=='icons' then return (style.icon_size+(bitmap(style.font) and 19 or 24))*scale;end;
    return (3*(style.bar_height+style.gap)+style.title_size+12)*scale;
end;

-- One more row of a panel, the room it takes as it fills: an icon row with its countdown, or a bar.
local function row_more(panel,style)
    if panel.auto_height==false then return 0;end;
    local scale=style.scale or 1;
    if panel.mode=='icons' then return panel_height(panel,style)-8*scale+style.gap*scale;end;
    return (style.bar_height+style.gap)*scale;
end;

-- The Pet display, the Phantom Roll display or the party cooldown list: its height if it has one set, or room for its
-- title and lines, five unless told.
local function box_rect(config,style,lines)
    local height=(style.title_size+16+(lines or 5)*(style.font_size+8))*(style.scale or 1);
    return {x=config.x,y=config.y,width=config.width,height=config.height>0 and config.height or height};
end;

local function notice_rect(settings,screen,x,y)
    local style,alerts=settings.style,settings.alerts;
    local width=math.min(alerts.notice_width*(style.scale or 1),screen.width);
    if x<0 then x=(screen.width-width)/2;end;
    -- Room for as many notices as show at once, each up to two lines, and one line more.
    return {x=math.max(0,math.min(x,screen.width-width)),y=y,width=width,
        height=(2*(alerts.max_notices or 2)+1)*(style.font_size+3)*(style.scale or 1)};
end;

-- The chat log's windows, the main one first.
local function chat_windows(chat)
    local out={};
    if chat then
        out[1]=chat;
        for _,window in ipairs(chat.windows or {})do out[#out+1]=window;end;
    end;
    return out;
end;

-- The game's own party list and target window.
local function native_corner(screen)
    return require('ui.layout').native_corner(screen.width,screen.height);
end;

-- What a fresh spot keeps clear of besides the timer row: the chat log's windows and the game's own windows.
local function blocked(context)
    local out=chat_windows(context.chat);
    if context.corner then out[#out+1]=context.corner;end;
    return out;
end;

-- The chat log and the game's windows the fresh spots are worked out with.
local function spot_context(screen,chat)
    return {chat=chat,corner=native_corner(screen)};
end;

-- What the panels have to keep clear of: the displays on screen that stay where they are, the chat log and the
-- game's own windows. flowing names the panels, the notice, the Pet display and the Phantom Roll display being placed.
-- context holds the chat
-- log and the game's windows. A panel's grow is the room it takes as it fills one more row.
local function obstacles(settings,screen,flowing,context)
    local out={};
    for _,id in ipairs(defaults.panel_order)do
        local panel=settings.panels[id];
        if not flowing[id] and defaults.panel_enabled(settings,id) and not anchors.active(panel.anchor) then
            out[#out+1]={x=panel.x,y=panel.y,width=panel.width,height=panel_height(panel,settings.style),
                grow=row_more(panel,settings.style)};
        end;
    end;
    for _,window in ipairs(blocked(context))do out[#out+1]=window;end;
    if not flowing.notice then out[#out+1]=notice_rect(settings,screen,settings.alerts.notice_x,settings.alerts.notice_y);end;
    return out;
end;

-- The rects in list with each panel's room to fill one more row.
local function grown(list)
    local out={};
    for index,rect in ipairs(list)do
        out[index]=rect.grow and {x=rect.x,y=rect.y,width=rect.width,height=rect.height+rect.grow} or rect;
    end;
    return out;
end;

-- Where each flowing panel, the notice, the Pet display and the Phantom Roll display go on this screen. Panels on screen
-- take the first spots in their row and the notice comes next; the panels turned off follow, so each still has its own
-- spot when it is turned on. The Pet display and then the Phantom Roll display come last, on or off, each at the first
-- free spot from where it starts, clear of each other and the party cooldown list as well. The Pet display goes first
-- so a Phantom Roll display with no room at its start can't take the spot. The combined recast panel and the spell
-- recast panel share one spot,
-- as they do at a fresh install. What goes under a panel leaves it room to fill one more row where the screen has a
-- spot for that. One turned off with no spot from where its row starts, which a panel off in the first row can push
-- past the bottom of the screen, looks again from the top of the first row.
local function slots(settings,screen,flowing,context)
    local taken,result,bottom=obstacles(settings,screen,flowing,context),{},nil;
    local function take(rect) taken[#taken+1]=rect;end;
    local function find(width,height,origin,also_x)
        return spot(width,height,origin,grown(taken),screen,also_x) or spot(width,height,origin,taken,screen,also_x);
    end;
    local function flow(shown_pass)
        for index,row in ipairs(ROWS)do
            local origin={x=40,y=index==1 and row.y or math.max(row.y,(bottom or 0)+GAP)};
            for _,id in ipairs(row.ids)do
                local group,shown={},false;
                for _,member in ipairs(id=='spell_recasts' and {'spell_recasts','recasts'} or {id})do
                    if flowing[member] then group[#group+1]=member;end;
                    if flowing[member] and defaults.panel_enabled(settings,member) then shown=member;end;
                end;
                if #group>0 and shown_pass==(shown~=false) then
                    local panel=settings.panels[shown or group[1]];
                    local height=panel_height(panel,settings.style);
                    local rect=find(panel.width,height,origin);
                    if index>1 and not (rect or shown_pass) then rect=find(panel.width,height,{x=40,y=ROWS[1].y});end;
                    if rect then
                        rect.grow=row_more(panel,settings.style);
                        take(rect);
                        for _,member in ipairs(group)do result[member]=rect;end;
                        if index==1 then bottom=math.max(bottom or 0,rect.y+rect.height);end;
                    end;
                end;
            end;
        end;
    end;
    flow(true);
    if flowing.notice then
        local fresh=defaults.make().alerts;
        local preferred=notice_rect(settings,screen,fresh.notice_x,fresh.notice_y);
        -- The starting spot is kept as saved; drawing moves it in from a narrow screen's edge.
        local fits=preferred.y+preferred.height<=screen.height;
        if fits and free(preferred,grown(taken)) then result.notice={x=fresh.notice_x,y=fresh.notice_y};
        else
            result.notice=spot(preferred.width,preferred.height,{x=40,y=fresh.notice_y},grown(taken),screen,preferred.x);
            if not result.notice and fits and free(preferred,taken) then result.notice={x=fresh.notice_x,y=fresh.notice_y};end;
            result.notice=result.notice or find(preferred.width,preferred.height,{x=40,y=fresh.notice_y},preferred.x);
        end;
        if result.notice then take(notice_rect(settings,screen,result.notice.x,result.notice.y));end;
    end;
    flow(false);
    local layout,style=require('ui.layout'),settings.style;
    local function stays(config,lines) take(layout.clamp(box_rect(config,style,lines),screen.width,screen.height));end;
    local function flows(id,start,lines)
        local rect=box_rect(settings[id],style,lines);
        result[id]=find(rect.width,rect.height,start) or find(rect.width,rect.height,{x=40,y=ROWS[1].y});
        if result[id] then take(result[id]);end;
    end;
    stays(settings.party_cooldowns.list);
    if not flowing.rolls then stays(settings.rolls,ROLL_LINES);end;
    if flowing.pet then flows('pet',require('core.pet').make()); else stays(settings.pet);end;
    if flowing.rolls then flows('rolls',require('core.rolls').make(),ROLL_LINES);end;
    return result;
end;

local function chat_area(screen)
    return require('ui.layout').chat_area(screen.width,screen.height,screen.chat);
end;

-- Moves the panels, the notice, the Pet display and the Phantom Roll display in flowing to where the flow puts them: a
-- panel with no spot keeps its fresh one, the others their own.
local function place_flowing(settings,screen,flowing,context)
    local placed=slots(settings,screen,flowing,context);
    local fresh=defaults.make();
    for id in pairs(flowing)do
        local rect=placed[id];
        if id=='notice' then
            if rect then settings.alerts.notice_x,settings.alerts.notice_y=rect.x,rect.y;end;
        elseif id=='pet' or id=='rolls' then
            if rect then settings[id].x,settings[id].y=rect.x,rect.y;end;
        elseif rect then settings.panels[id].x,settings.panels[id].y=rect.x,rect.y;
        else settings.panels[id].x,settings.panels[id].y=fresh.panels[id].x,fresh.panels[id].y;end;
    end;
end;

-- A fresh install's first frame with a screen (width, height, and the client's chat rectangle in chat when it can
-- be read), placed as an apply of the fresh setup would place it: the timer panels, alert notices, Pet display and
-- Phantom Roll display still at their starting spots go where they keep clear of the chat log, the game's own party
-- list and target window, and each other. Nothing else moves.
function setup.place_fresh(settings,screen)
    if type(screen)~='table' or not ((screen.width or 0)>0 and (screen.height or 0)>0) then return;end;
    local context=spot_context(screen,chat_area(screen));
    local fresh=defaults.make();
    local flowing={};
    for _,id in ipairs(defaults.panel_order)do
        local panel,origin=settings.panels[id],fresh.panels[id];
        if panel.x==origin.x and panel.y==origin.y and not anchors.active(panel.anchor) then flowing[id]=true;end;
    end;
    local alerts=settings.alerts;
    if alerts.notice_x==fresh.alerts.notice_x and alerts.notice_y==fresh.alerts.notice_y then flowing.notice=true;end;
    for _,id in ipairs({'pet','rolls'})do
        if settings[id].x==fresh[id].x and settings[id].y==fresh[id].y then flowing[id]=true;end;
    end;
    place_flowing(settings,screen,flowing,context);
    settings.placement_screen={width=screen.width,height=screen.height};
end;

-- Where a fresh install's first frame on this screen put the panels, the notices, the Pet and Phantom Roll displays.
-- Import and add (core/share.lua) counts a display still there as one the player never moved.
local function first_frame(screen)
    local first=defaults.make();
    setup.place_fresh(first,screen);
    return first;
end;
setup.first_frame=first_frame;

-- Where a fresh install's first frame on this screen puts one display: x, y.
function setup.first_spot(id,screen)
    local elements=require('ui.elements');
    local element,config=elements.by_id[id],elements.config(first_frame(screen),id);
    return config[element.x],config[element.y];
end;

-- The display a reset of one display's settings takes back, by the reset's scope.
local reset_scopes={alerts='notices',pet='pet',rolls='rolls'};

-- After that reset, puts it at its first spot, and every timer and recast panel after /vg reset panels. Any other scope
-- moves nothing here.
function setup.place_reset(settings,scope,screen)
    local elements=require('ui.elements');
    local function place(id)
        local element,config=elements.by_id[id],elements.config(settings,id);
        config[element.x],config[element.y]=setup.first_spot(id,screen);
    end;
    if scope=='panels' or scope=='layouts' then
        for _,id in ipairs(defaults.panel_order)do place(id);end;
    elseif reset_scopes[scope] or settings.panels[scope] then place(reset_scopes[scope] or scope);end;
end;

-- The screen a fresh install's first frame or an apply last placed the displays for, when that was another size.
local function placed_for(settings,screen)
    local placed=settings.placement_screen;
    if type(placed)~='table' or not ((placed.width or 0)>0 and (placed.height or 0)>0)
        or placed.width==screen.width and placed.height==screen.height then return nil;end;
    return {width=placed.width,height=placed.height};
end;

-- old is the settings before the apply, new the result with the kept positions. Both name the same alerts, Pet
-- display, Phantom Roll display and party cooldown list. screen has the width and height, and the client's chat
-- rectangle in chat when it can be read.
function setup.respace(old,new,screen)
    if type(screen)~='table' or not ((screen.width or 0)>0 and (screen.height or 0)>0) then return;end;
    local fresh=defaults.make();
    local chat=chat_area(screen);
    local first=first_frame(screen);
    local old_context=spot_context(screen,chat);
    local new_context=old_context;
    -- Spots placed for another screen are Vantage's too: that screen's first frame and its applies, with the game's
    -- usual chat log for it.
    local other=placed_for(old,screen);
    local other_first,other_context;
    if other then
        other_first=first_frame(other);
        other_context=spot_context(other,chat_area(other));
    end;
    local ids={};
    for index,id in ipairs(defaults.panel_order)do ids[index]=id;end;
    ids[#ids+1]='notice';
    ids[#ids+1]='pet';
    ids[#ids+1]='rolls';
    local function spot_of(source,id)
        if id=='notice' then return source.alerts.notice_x,source.alerts.notice_y;end;
        if id=='pet' or id=='rolls' then return source[id].x,source[id].y;end;
        return source.panels[id].x,source.panels[id].y;
    end;
    -- What an apply flows: the panels, the notice and a Pet or Phantom Roll display on no anchor.
    local free_ids,away={notice=true,pet=not anchors.active(old.pet.anchor) or nil,rolls=not anchors.active(old.rolls.anchor) or nil},{};
    for _,id in ipairs(defaults.panel_order)do
        local panel=old.panels[id];
        if not anchors.active(panel.anchor) then free_ids[id]=true;end;
    end;
    for id in pairs(free_ids)do
        local x,y=spot_of(old,id);
        local start=id=='notice' and {x=fresh.alerts.notice_x,y=fresh.alerts.notice_y} or fresh[id] or fresh.panels[id];
        local placed_x,placed_y=spot_of(first,id);
        local other_x,other_y;
        if other_first then other_x,other_y=spot_of(other_first,id);end;
        if not (x==start.x and y==start.y or x==placed_x and y==placed_y or x==other_x and y==other_y) then away[id]=true;end;
    end;
    -- One away from its start, or from where a fresh install's first frame put it, is where the player put it or
    -- where an earlier apply did. Those had the player's ones in their way, so one is theirs when, with the others
    -- still away standing where they are, the flow puts it there. Taking those out one at a time leaves the player's.
    local function flowing_without(skip)
        local flowing={};
        for id in pairs(free_ids)do if not away[id] or id==skip then flowing[id]=true;end;end;
        return flowing;
    end;
    local found=true;
    while found do
        found=false;
        for _,id in ipairs(ids)do
            if away[id] then
                local x,y=spot_of(old,id);
                local was=slots(old,screen,flowing_without(id),old_context)[id];
                local before=other and slots(old,other,flowing_without(id),other_context)[id];
                if was and x==was.x and y==was.y or before and x==before.x and y==before.y then away[id],found=nil,true;break;end;
            end;
        end;
    end;
    local flowing=flowing_without(nil);
    local alerts=new.alerts;
    local placed=slots(new,screen,flowing,new_context);
    for id in pairs(flowing)do
        local rect=placed[id];
        if id=='notice' then
            rect=rect or {x=fresh.alerts.notice_x,y=fresh.alerts.notice_y};
            alerts.notice_x,alerts.notice_y=rect.x,rect.y;
        elseif id=='pet' or id=='rolls' then
            rect=rect or fresh[id];
            new[id].x,new[id].y=rect.x,rect.y;
        else
            rect=rect or fresh.panels[id];
            new.panels[id].x,new.panels[id].y=rect.x,rect.y;
        end;
    end;
    new.placement_screen={width=screen.width,height=screen.height};
end;
return setup;
