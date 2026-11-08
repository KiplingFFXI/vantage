local countdown={}
local fonts=require('ui.fonts')
local metrics=require('ui.text_metrics')
local offsets={{-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1}}

-- A number from 0 up, not infinite.
local function non_negative(value)
    return type(value)=='number' and value==value and value>=0 and value<math.huge
end

-- Every time Vantage shows reads as the game's own: whole hours from an hour, whole minutes from a minute, then
-- seconds rounded up, so 59.5 seconds shows 60s.
function countdown.time(seconds)
    if not non_negative(seconds) then return '' end
    if seconds >= 3600 then return tostring(math.floor(seconds / 3600)) .. 'h' end
    if seconds >= 60 then return tostring(math.floor(seconds / 60)) .. 'm' end
    return tostring(math.ceil(seconds)) .. 's'
end

-- 269 is Level Sync, which runs with no countdown.
function countdown.indefinite(row)
    return row~=nil and tonumber(row.effect)==269 and row.domain~='recast' and row.present==true
        and not non_negative(row.remaining) and not non_negative(row.deadline)
end

local function option(options,key)
    if not options then return nil end
    local value=options['countdown_'..key]
    if value==nil then value=options[key] end
    return value
end

local function rgba(value)
    if type(value)=='table' then return require('ui.theme').u32(value) end
    return type(value)=='number' and value or 0xFFFFFFFF
end

local function effects(options)
    return option(options,'bold')==true,option(options,'shadow')==true,option(options,'outline')==true
end

function countdown.padding(options)
    local bold,shadow,outline=effects(options)
    local before=outline and 1 or 0
    local after=(outline or shadow) and 1 or 0
    return before,before,(bold and 1 or 0)+after,after
end

function countdown.measure(font,text,size,options,compact)
    text=tostring(text or '')
    if text=='' then return 0,0 end
    size=math.max(1,size or 16)
    local width,height=metrics.countdown(font,text,size,compact)
    local left,top,right,bottom=countdown.padding(options)
    return width+left+right,height+top+bottom
end

-- An icon's countdown: its size, its text's width and height, and its gap, as icon_metrics gives them, without a table.
function countdown.icon_values(font,text,icon_size,options,pixel_scale)
    options = options or {}
    pixel_scale = non_negative(pixel_scale) and pixel_scale > 0 and pixel_scale or 1
    local chosen = tonumber(options.icon_countdown_size)
    local size = non_negative(chosen) and chosen > 0 and chosen * pixel_scale
        or math.max(6, math.min(64, math.floor(icon_size * pixel_scale / 2 + 0.5)))
    local width, height = countdown.measure(font,text,size,options,true)
    return size/pixel_scale, width/pixel_scale, height/pixel_scale, tonumber(options.icon_countdown_gap) or 0
end

function countdown.icon_metrics(font,text,icon_size,options,pixel_scale)
    local size, width, height, gap = countdown.icon_values(font,text,icon_size,options,pixel_scale)
    return { size=size, width=width, height=height, gap=gap }
end

-- A countdown's passes in drawing order: the shadow, the outline offsets, then the fill, each followed by
-- its bold copy one pixel right.
local pass_x,pass_y,pass_ink,passes={},{},{},0
local function add_pass(dx,dy,ink,bold)
    passes=passes+1
    pass_x[passes],pass_y[passes],pass_ink[passes]=dx,dy,ink
    if bold then
        passes=passes+1
        pass_x[passes],pass_y[passes],pass_ink[passes]=dx+1,dy,ink
    end
end

-- point, when given, is a table the caller keeps and the text position is written into, so a pass makes nothing
-- (the binding copies a vector when it is called and keeps none).
local function draw_pass(list,renderer,face,text,x,y,size,compact,dx,dy,ink,point)
    if renderer then renderer(list,text,x+dx,y+dy,size,ink,compact)
    elseif point then
        point[1],point[2]=x+dx,y+dy
        list:AddText(face,size,point,ink,text)
    else list:AddText(face,size,{x+dx,y+dy},ink,text) end
end

function countdown.draw(list,font,text,x,y,size,color,options,compact,point)
    text=tostring(text or '')
    if text=='' then return true end
    size=math.max(1,size or 16)
    local bold,shadow,outline=effects(options)
    local left,top=countdown.padding(options)
    x,y=math.floor(x+0.5)+left,math.floor(y+0.5)+top
    color=rgba(color)
    local alpha=math.floor(color/16777216)%256
    local renderer,replay
    if fonts.is_bitmap(font) then renderer,replay=fonts.countdown_renderer(font) end
    local face=not renderer and fonts.face(font)
    passes=0
    if shadow then add_pass(1,1,alpha*16777216,bold) end
    if outline then
        local ink=rgba(option(options,'outline_color') or 0xFF000000)
        local outline_alpha=math.floor(ink/16777216)%256
        ink=ink%16777216+math.floor(outline_alpha*alpha/255+0.5)*16777216
        for _,offset in ipairs(offsets) do add_pass(offset[1],offset[2],ink,bold) end
    end
    add_pass(0,0,color,bold)
    -- Bitmap text walks its glyphs once and replays them for every pass, from the same font lookup.
    if replay then
        replay(list,text,x,y,size,compact,passes,pass_x,pass_y,pass_ink)
        return true
    end
    for pass=1,passes do draw_pass(list,renderer,face,text,x,y,size,compact,pass_x[pass],pass_y[pass],pass_ink[pass],point) end
    return true
end

return countdown
