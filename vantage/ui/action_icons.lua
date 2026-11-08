-- Native menu shapes preserve each action's layers, element colors and tier marks.
local icons = {}
local assets = require('ui.client_assets')
local packs, last_reason = {}, nil
-- Parsed layouts by their bytes: a pack without its own files reads the stock layout, parsed once.
local layouts = {}
local MAX_SHAPES, MAX_PARTS = 2048, 16

local function integer(value, high)
    return type(value) == 'number' and value == math.floor(value) and value >= 0 and value <= high
end

local function u16(data, at)
    local lo, hi = data:byte(at, at+1)
    return hi and lo+hi*256 or nil
end

local function i16(data, at)
    local value = u16(data, at)
    return value and (value >= 32768 and value-65536 or value)
end

function icons.parse(data)
    if type(data) ~= 'string' or #data < 19 or #data > 1024*1024 then return nil, 'Invalid action shape data.' end
    local at = 18+data:byte(17)*16
    local count = u16(data, at)
    if not count or count > MAX_SHAPES then return nil, 'Invalid action shape count.' end
    at = at+2
    local result = { count = count, shapes = {} }
    for id = 0, count-1 do
        local parts = data:byte(at)
        if not parts or parts > MAX_PARTS or at+parts*61 > #data then return nil, 'Truncated or oversized action shape.' end
        at = at+1
        local shape = { parts = {}, left = math.huge, top = math.huge, right = -math.huge, bottom = -math.huge }
        for _ = 1, parts do
            local xy = {}
            for index = 0, 7 do xy[index+1] = i16(data, at+index*2) end
            local w,h,u,v = i16(data,at+16),i16(data,at+18),i16(data,at+20),i16(data,at+22)
            local flip = data:byte(at+24)
            local rgba = { data:byte(at+25,at+28) }
            local blend = { data:byte(at+41,at+44) }
            local name = data:sub(at+45,at+60):lower()
            local valid = xy[1] == xy[5] and xy[3] == xy[7] and xy[2] == xy[4] and xy[6] == xy[8]
                and xy[3] > xy[1] and xy[6] > xy[2] and w > 0 and h > 0 and w <= 2048 and h <= 2048
                and u >= 0 and v >= 0 and flip <= 3 and not name:find('[%c]')
            for _, value in ipairs(xy) do if math.abs(value) > 4096 then valid = false end end
            for vertex = 1, 3 do
                for channel = 1, 4 do if data:byte(at+25+vertex*4+channel-1) ~= rgba[channel] then valid = false end end
            end
            if not valid then shape.reason = 'This action shape uses unsupported geometry or vertex colors.' end
            local subtractive = blend[1] == 1 and blend[2] == 2 and blend[3] == 0 and blend[4] == 1
            if not subtractive and (blend[1] ~= 1 or blend[2] ~= 0 or not (blend[3] == 1 and blend[4] == 1 or blend[3] == 2 and blend[4] == 2)) then
                shape.reason = 'This action shape uses an unsupported native blend mode.'
            end
            if subtractive then shape.approximate_blend = true end
            shape.parts[#shape.parts+1] = { x=xy[1], y=xy[2], width=xy[3]-xy[1], height=xy[6]-xy[2],
                source_width=w,source_height=h,u=u,v=v,flip=flip,rgba=rgba,name=name,black=blend[3] == 2,subtractive=subtractive }
            shape.left,shape.top = math.min(shape.left,xy[1]),math.min(shape.top,xy[2])
            shape.right,shape.bottom = math.max(shape.right,xy[3]),math.max(shape.bottom,xy[6])
            at = at+61
        end
        if parts == 0 then shape.reason = 'The native action icon is empty.' end
        result.shapes[id] = shape
    end
    return result
end

-- One layout of a pack (main or secondary), parsed unless it is already.
local function entry(kind, which)
    packs[kind] = packs[kind] or {}
    if packs[kind][which] then return end
    local data,why,using = assets.action_layout(kind,which == 'secondary')
    local parsed
    if data then
        layouts[data] = layouts[data] or { icons.parse(data) }
        parsed,why = layouts[data][1],layouts[data][2]
    end
    packs[kind][which] = { data=parsed,reason=why,using=using }
end

local function load_pack(kind)
    entry(kind,'main')
    entry(kind,'secondary')
    return packs[kind]
end

-- The XI View pack is read and parsed the first time something draws with it, or by its warmup steps.
function icons.prepare()
    assets.prepare_actions()
    load_pack('original')
end

-- An artwork's pack as warmup steps, one file each: main and secondary with their layouts, then the shared
-- source textures. The stock pack's steps have to run first, which appearance.warmup_steps sees to.
function icons.warmup_steps(artwork)
    local kind = artwork == 'XI View' and 'xiview' or 'original'
    local steps = {}
    for _, which in ipairs({ 'main', 'secondary', 'common' }) do
        local function done()
            return assets.action_loaded(kind,which) and (which == 'common' or packs[kind] ~= nil and packs[kind][which] ~= nil)
        end
        steps[#steps+1] = assets.step('actions.'..kind..'.'..which, done, function()
            assets.load_action(kind,which)
            if which ~= 'common' then entry(kind,which) end
        end)
    end
    return steps
end

local function selected(artwork,hq,nq)
    local kind = artwork == 'XI View' and 'xiview' or 'original'
    if not integer(hq,65535) or hq == 65535 then hq = nq end
    if not integer(hq,65534) then return nil,nil,nil,'The client gives no action icon index.' end
    local secondary = hq >= 1000
    local which = secondary and 'secondary' or 'main'
    local held = packs[kind] and packs[kind][which]
    if not held and packs.original then held = load_pack(kind)[which] end
    local shape = held and held.data and held.data.shapes[secondary and hq-1000 or hq]
    if kind ~= 'original' and (not shape or shape.reason) then
        local stock = packs.original and packs.original[secondary and 'secondary' or 'main']
        local fallback = stock and stock.data and stock.data.shapes[secondary and hq-1000 or hq]
        if fallback and not fallback.reason then shape,held,kind = fallback,stock,'original' end
    end
    if not shape then return nil,nil,nil,held and held.reason or 'The client action icon index is unavailable.' end
    return shape,kind,secondary,shape.reason
end

-- The client's loader adds 1 to each color byte, and the menu draws with MODULATE2X, which doubles it.
local function color(rgba,opacity)
    local r,g,b = math.min(255,(rgba[1]+1)*2),math.min(255,(rgba[2]+1)*2),math.min(255,(rgba[3]+1)*2)
    return r+g*256+b*65536+math.floor(255*opacity+0.5)*16777216
end

local function axis_parts(start,span,extent,flip)
    local result,finish = {},start+span
    while start < finish do
        local edge = math.min(finish,(math.floor(start/extent)+1)*extent)
        local a,b = (start-(finish-span))/span,(edge-(finish-span))/span
        local u,v = start%extent/extent,(edge-start+start%extent)/extent
        if flip then a,b,u,v = 1-b,1-a,v,u end
        result[#result+1] = {a,b,u,v}
        start = edge
    end
    return result
end

-- A draw's textures and corners, refilled for each one: the binding copies a vector when it is called and keeps none.
local drawn_textures = {}
local part_min, part_max, quad_min, quad_max, uv_min, uv_max = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }

local function source_textures(shape,kind,secondary)
    local textures = drawn_textures
    for index = #textures, #shape.parts + 1, -1 do textures[index] = nil end
    for index,part in ipairs(shape.parts) do
        -- The client's own alpha adjustment: 127 becomes 192.
        local alpha = part.rgba[4] == 0 and 0 or part.rgba[4] == 255 and 255 or math.min(255,math.floor((part.rgba[4]+1)*1.5))
        local texture,problem,waiting = assets.action_texture(kind,secondary,part.name,alpha)
        if not texture then return nil,problem,waiting end
        -- Native menu drawing wraps UVs. Bound each part to at most four quads.
        if part.u >= texture.width or part.v >= texture.height or part.u+part.source_width > texture.width*2
            or part.v+part.source_height > texture.height*2 then
            return nil,'The action icon source rectangle exceeds supported texture wrapping.'
        end
        if part.texture_width ~= texture.width or part.texture_height ~= texture.height then
            part.columns = axis_parts(part.u,part.source_width,texture.width,part.flip%2 == 1)
            part.rows = axis_parts(part.v,part.source_height,texture.height,math.floor(part.flip/2)%2 == 1)
            part.texture_width,part.texture_height = texture.width,texture.height
        end
        textures[index] = texture
    end
    return textures
end

function icons.draw(list,artwork,hq,nq,x,y,size,opacity)
    if type(x) ~= 'number' or x ~= x or math.abs(x) == math.huge or type(y) ~= 'number' or y ~= y or math.abs(y) == math.huge
        or type(size) ~= 'number' or size ~= size or size < 1 or size > 512 then return false end
    opacity = type(opacity) == 'number' and opacity == opacity and math.max(0,math.min(1,opacity)) or 1
    local shape,kind,secondary,why = selected(artwork,hq,nq)
    if why or not shape then last_reason = why; return false end
    -- A texture waiting for a later Present's upload (client_assets' budget) draws nothing until it is made, and the
    -- icon counts as drawn so nothing is put in its place meanwhile.
    local textures,problem,waiting = source_textures(shape,kind,secondary)
    if waiting then return true end
    if not textures and kind ~= 'original' then
        local fallback,stock,bank,reason = selected('Original FFXI',hq,nq)
        if fallback and not reason then
            local replacement,failure,later = source_textures(fallback,stock,bank)
            if later then return true end
            if replacement then shape,kind,secondary,textures = fallback,stock,bank,replacement
            else problem = failure end
        end
    end
    if not textures then last_reason = problem; return false end
    local width,height = shape.right-shape.left,shape.bottom-shape.top
    local scale = size/math.max(width,height)
    local left,top = x+(size-width*scale)/2-shape.left*scale,y+(size-height*scale)/2-shape.top*scale
    for index,part in ipairs(shape.parts) do
        local texture = textures[index]
        local x0,y0 = left+part.x*scale,top+part.y*scale
        local x1,y1 = left+(part.x+part.width)*scale,top+(part.y+part.height)*scale
        local tint = color(part.rgba,opacity)
        -- ImGui cannot subtract from the framebuffer; retain this native shadow's alpha.
        if part.subtractive then tint = tint-tint%16777216 end
        if part.black then
            part_min[1],part_min[2],part_max[1],part_max[2] = x0,y0,x1,y1
            list:AddRectFilled(part_min,part_max,math.floor(255*opacity+0.5)*16777216)
        end
        for _,row in ipairs(part.rows) do for _,column in ipairs(part.columns) do
            quad_min[1],quad_min[2] = x0+column[1]*(x1-x0),y0+row[1]*(y1-y0)
            quad_max[1],quad_max[2] = x0+column[2]*(x1-x0),y0+row[2]*(y1-y0)
            uv_min[1],uv_min[2],uv_max[1],uv_max[2] = column[3],row[3],column[4],row[4]
            list:AddImage(texture.id,quad_min,quad_max,uv_min,uv_max,tint)
        end end
    end
    last_reason = nil
    return true
end

-- Why the last icon drawn wasn't, or nil when it was: for /vg report.
function icons.reason() return last_reason end

if VANTAGE_TEST_MODE then
    function icons.status(artwork,hq,nq)
        local shape,kind,secondary,why = selected(artwork,hq,nq)
        local held = kind and packs[kind][secondary and 'secondary' or 'main']
        return { available=shape ~= nil and why == nil, reason=why, using=held and held.using,
            parts=shape and #shape.parts or 0, approximate_blend=shape and shape.approximate_blend or false }
    end
end
function icons.clear() assets.clear_actions(); packs,last_reason,layouts = {},nil,{} end
return icons
