local client_fonts = {}
local kinds = { ['Original FFXI'] = 'original_font', ['XI View'] = 'xiview_font' }
local prepared, built, faces, problems = false, {}, {}, {}
local render_cache = require('ui.render_cache')
-- Every glyph fills these before it draws. The binding copies a vector when it is called and keeps none.
local q1, q2, q3, q4, t1, t2, t3, t4 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }

local function pixel(value)
    return math.floor(value + 0.5)
end

local function rgb565(value)
    return { math.floor(value / 2048) * 255 / 31, math.floor(value / 32) % 64 * 255 / 63, value % 32 * 255 / 31 }
end

local function le32(value)
    return string.char(value%256,math.floor(value/256)%256,math.floor(value/65536)%256,math.floor(value/16777216)%256)
end

local function foreground_atlas(face)
    local width,height,rows=256,128,{}
    for y=0,height-1 do
        local row={}
        for column=0,15 do
            local glyph=face.glyphs[32+math.floor(y/16)*16+column]
            local pixels=glyph and glyph.pixels[y%16+1] or ''
            for x=1,16 do
                local at=(x-1)*4+1
                local b,g,r,a=pixels:byte(at,at+3)
                -- Only the bright pixels are the glyph. The darker ones are the font's own shadow, and a countdown draws its own.
                local visible=a and a>0 and math.max(r,g,b)>=128
                row[#row+1]=visible and string.char(b,g,r,a) or '\0\0\0\0'
                if visible then
                    local ink=glyph.countdown_ink
                    if not ink then glyph.countdown_ink={x-1,y%16,x,y%16+1}
                    else
                        ink[1],ink[2]=math.min(ink[1],x-1),math.min(ink[2],y%16)
                        ink[3],ink[4]=math.max(ink[3],x),math.max(ink[4],y%16+1)
                    end
                end
            end
        end
        rows[y+1]=table.concat(row)
    end
    local dds='DDS '..le32(124)..le32(0x100F)..le32(height)..le32(width)..le32(width*4)
        ..le32(0)..le32(1)..string.rep('\0',44)..le32(32)..le32(0x41)..le32(0)..le32(32)
        ..le32(0xFF0000)..le32(0xFF00)..le32(0xFF)..le32(0xFF000000)..le32(0x1000)..string.rep('\0',16)
    return {dds=dds..table.concat(rows),width=width,height=height}
end

-- The ordinary UI font starts with ASCII space in a 64-column grid of 16-pixel cells. Those glyphs fill its top 32
-- rows, so the uploaded image may be the top of the texture only.
function client_fonts.parse(raw, image)
    if type(raw) ~= 'table' or type(raw.dds) ~= 'string' or raw.format ~= 'DXT3'
        or raw.width ~= 1024 or raw.height ~= 2048 or raw.dds:sub(1, 4) ~= 'DDS '
        or raw.dds:sub(85, 88) ~= 'DXT3' or #raw.dds ~= 128 + raw.width * raw.height then
        return nil, 'The ordinary client font texture is missing or unsupported.'
    end
    if type(image) ~= 'table' or type(image.id) ~= 'number' or image.id <= 0 or image.id ~= image.id
        or image.width ~= raw.width or type(image.height) ~= 'number' or image.height < 32
        or image.height > raw.height then
        return nil, 'The ordinary client font texture could not be uploaded.'
    end
    local result, blocks = { glyphs = {}, size = 16 }, {}
    for code = 32, 126 do
        local index = code - 32
        local u, v, right = index % 64 * 16, math.floor(index / 64) * 16, -1
        local rows = {}
        for y = 0, 15 do
            local row = {}
            for x = 0, 15 do
                local px, py = u + x, v + y
                local block = math.floor(py / 4) * (raw.width / 4) + math.floor(px / 4)
                local index_in_block = py % 4 * 4 + px % 4
                local byte = raw.dds:byte(129 + block * 16 + math.floor(index_in_block / 2))
                local alpha = index_in_block % 2 == 0 and byte % 16 or math.floor(byte / 16)
                if alpha > 0 then
                    local colors = blocks[block]
                    if not colors then
                        local a, b, c, d = raw.dds:byte(137 + block * 16, 140 + block * 16)
                        colors = { rgb565(a + b * 256), rgb565(c + d * 256), {}, {} }
                        for channel = 1, 3 do
                            colors[3][channel] = (2 * colors[1][channel] + colors[2][channel]) / 3
                            colors[4][channel] = (colors[1][channel] + 2 * colors[2][channel]) / 3
                        end
                        blocks[block] = colors
                    end
                    local indices = raw.dds:byte(141 + block * 16 + math.floor(index_in_block / 4))
                    local color = colors[math.floor(indices / 4 ^ (index_in_block % 4)) % 4 + 1]
                    -- Black shadow from the next cell is not part of this glyph's advance.
                    if alpha >= 8 and math.max(color[1], color[2], color[3]) >= 128 then right = math.max(right, x) end
                    row[x + 1] = string.char(pixel(color[3]), pixel(color[2]), pixel(color[1]), alpha * 17)
                else row[x + 1] = '\0\0\0\0' end
            end
            rows[y + 1] = table.concat(row)
        end
        if code ~= 32 and right < 0 then return nil, 'The client font is missing a printable English character.' end
        -- Ink bounds give this overlay consistent proportional spacing; these are not engine kerning values.
        local width = code == 32 and 8 or math.min(16, right + 2)
        for y = 1, 16 do rows[y] = rows[y]:sub(1, width * 4) end
        result.glyphs[code] = { code=code, advance = width, pixels = rows, pieces = {
            { image = image, xy = { 0, 0, width, 0, 0, 16, width, 16 },
                uv = { u / image.width, v / image.height, (u + width) / image.width, (v + 16) / image.height } },
        } }
    end
    return result
end

function client_fonts.is_bitmap(name)
    return kinds[name] ~= nil
end

-- XI View's face is made the first time its font is used. A face is made again only when its own texture is
-- replaced: another kind's late upload leaves it as it is.
local function refresh(name)
    if not prepared then return end
    local assets = require('ui.client_assets')
    if assets.retry and (not assets.retry_pending or assets.retry_pending()) then assets.retry() end
    local current = assets.generation and assets.generation() or 0
    local made = built[name]
    if made and made.generation == current then return end
    local kind = kinds[name]
    -- Texture lookup can recreate the cache after a device change.
    local image = assets.texture(kind, 'moji')
    if not (made and faces[name] and made.image == image) then
        local face, problem = client_fonts.parse(assets.raw(kind, 'moji'), image)
        if face then
            face.foreground=foreground_atlas(face)
            if assets.derived_texture then
                face.foreground.image=assets.derived_texture(kind,'countdown_foreground',face.foreground.dds,face.foreground.width,face.foreground.height)
            end
            -- The face keeps what it needs; assets.raw reads the pixels again for anything made later.
            if assets.release_pixels then assets.release_pixels(kind, 'moji') end
            faces[name], problems[name] = face, nil
        else
            local status = assets.status(kind) or {}
            faces[name], problems[name] = nil, status.reason or problem
        end
    end
    made = made or {}
    made.generation, made.image = assets.generation and assets.generation() or 0, image
    built[name] = made
end

-- The stock face is made by a warmup step, after fonts.load has made the menu fonts, so it lets the pixels go itself.
function client_fonts.prepare()
    if prepared then return end
    prepared = true
    require('ui.client_assets').prepare()
    refresh('Original FFXI')
end

-- Whether name's face is made for the textures uploaded now, so asking for it does no work.
function client_fonts.current(name)
    local made = built[name]
    if not prepared or not made then return false end
    local assets = require('ui.client_assets')
    return made.generation == (assets.generation and assets.generation() or 0)
end

function client_fonts.available(name)
    if not kinds[name] then return false end
    refresh(name)
    return faces[name] ~= nil
end

function client_fonts.reason(name)
    if not kinds[name] then return nil end
    refresh(name)
    if faces[name] then return nil end
    return problems[name] or 'Client bitmap fonts have not been prepared. Reload Vantage to load them.'
end

-- Consume one complete UTF-8 character. Unsupported characters use a visible question mark.
local function next_character(text, at)
    local first = text:byte(at)
    if first < 128 then return first, at + 1 end
    local length = first >= 194 and first <= 223 and 2 or first >= 224 and first <= 239 and 3
        or first >= 240 and first <= 244 and 4 or 1
    if length == 1 then return 63, at + 1 end
    local second = text:byte(at + 1)
    if not second or second < 128 or second > 191 or first == 224 and second < 160
        or first == 237 and second > 159 or first == 240 and second < 144 or first == 244 and second > 143 then
        return 63, at + 1
    end
    for offset = 2, length - 1 do
        local byte = text:byte(at + offset)
        if not byte or byte < 128 or byte > 191 then return 63, at + 1 end
    end
    return first == 194 and second == 160 and 32 or 63, at + length
end

-- emit gets the glyph, its offset and the scale, then a to f as passed.
local function walk(face, text, size, emit, a, b, c, d, e, f)
    size = math.max(1, pixel(size or face.size))
    local factor, x, y, widest, at = size / face.size, 0, 0, 0, 1
    while at <= #text do
        local code
        code, at = next_character(text, at)
        if code == 10 then
            widest, x, y = math.max(widest, x), 0, y + size
        elseif code == 13 and text:byte(at) == 10 then
            -- The following newline advances the line once.
        else
            local glyph = face.glyphs[code] or face.glyphs[63]
            if code == 9 then glyph = face.glyphs[32] end
            if emit and code ~= 32 and code ~= 9 then emit(glyph, x, y, factor, a, b, c, d, e, f) end
            x = x + math.max(1, pixel(glyph.advance * factor)) * (code == 9 and 4 or 1)
        end
    end
    return math.max(widest, x), #text > 0 and y + size or 0
end

function client_fonts.measure(name, text, size)
    if not kinds[name] then return nil end
    refresh(name)
    local face = faces[name]
    if not face then return nil end
    return walk(face, tostring(text or ''), size)
end

local function draw_glyph(glyph, dx, dy, factor, list, x, y, color)
    for _, piece in ipairs(glyph.pieces) do
        local p, uv = piece.xy, piece.uv
        q1[1], q1[2] = x + dx + pixel(p[1] * factor), y + dy + pixel(p[2] * factor)
        q2[1], q2[2] = x + dx + pixel(p[3] * factor), y + dy + pixel(p[4] * factor)
        q3[1], q3[2] = x + dx + pixel(p[7] * factor), y + dy + pixel(p[8] * factor)
        q4[1], q4[2] = x + dx + pixel(p[5] * factor), y + dy + pixel(p[6] * factor)
        t1[1], t1[2], t2[1], t2[2] = uv[1], uv[2], uv[3], uv[2]
        t3[1], t3[2], t4[1], t4[2] = uv[3], uv[4], uv[1], uv[4]
        list:AddImageQuad(piece.image.id, q1, q2, q3, q4, t1, t2, t3, t4, color)
    end
end

function client_fonts.draw(list, name, text, x, y, size, color)
    if not kinds[name] then return false end
    refresh(name)
    local face = faces[name]
    if not face then return false end
    -- Keep the original glyph pixels. Shrinking them into a nearest-neighbor atlas erases thin strokes.
    x, y = pixel(x), pixel(y)
    walk(face, tostring(text or ''), size, draw_glyph, list, x, y, color)
    return true
end

local function countdown_face(name)
    if not kinds[name] then return nil end
    refresh(name)
    local face=faces[name]
    if not face then return nil end
    local atlas=face.foreground
    if not atlas.image then
        local assets=require('ui.client_assets')
        if assets.derived_texture then atlas.image=assets.derived_texture(kinds[name],'countdown_foreground',atlas.dds,atlas.width,atlas.height) end
    end
    return atlas.image and face or nil
end

local function compact_bounds(face,text,size)
    size=math.max(1,pixel(size or face.size))
    face.compact_metrics=face.compact_metrics or render_cache.new(2048)
    local key=tostring(size)..'\0'..text
    local saved=face.compact_metrics:get(key)
    if saved then return saved[1],saved[2],saved[3],saved[4] end
    local left,top,right,bottom
    walk(face,text,size,function(glyph,dx,dy,factor)
        local ink=glyph.countdown_ink
        if not ink then return end
        local x1,y1=dx+pixel(ink[1]*factor),dy+pixel(ink[2]*factor)
        local x2,y2=dx+pixel(ink[3]*factor),dy+pixel(ink[4]*factor)
        if x2<=x1 or y2<=y1 then return end
        left,top=math.min(left or x1,x1),math.min(top or y1,y1)
        right,bottom=math.max(right or x2,x2),math.max(bottom or y2,y2)
    end)
    local result={left or 0,top or 0,right or 0,bottom or 0}
    face.compact_metrics:put(key,result)
    return result[1],result[2],result[3],result[4]
end

function client_fonts.measure_countdown(name,text,size,compact)
    local face=countdown_face(name)
    if not face then return end
    text=tostring(text or '')
    if compact then
        local left,top,right,bottom=compact_bounds(face,text,size)
        return right-left,bottom-top
    end
    return walk(face,text,size)
end

local function draw_foreground_glyph(glyph,dx,dy,factor,list,atlas,x,y,color,compact)
    local code=glyph.code
    local u,v=(code-32)%16*16,math.floor((code-32)/16)*16
    if compact then
        local ink=glyph.countdown_ink
        if not ink then return end
        local x1,y1=x+dx+pixel(ink[1]*factor),y+dy+pixel(ink[2]*factor)
        local x2,y2=x+dx+pixel(ink[3]*factor),y+dy+pixel(ink[4]*factor)
        if x2<=x1 or y2<=y1 then return end
        q1[1],q1[2],q2[1],q2[2],q3[1],q3[2],q4[1],q4[2]=x1,y1,x2,y1,x2,y2,x1,y2
        t1[1],t1[2],t2[1],t2[2]=(u+ink[1])/atlas.width,(v+ink[2])/atlas.height,(u+ink[3])/atlas.width,(v+ink[2])/atlas.height
        t3[1],t3[2],t4[1],t4[2]=(u+ink[3])/atlas.width,(v+ink[4])/atlas.height,(u+ink[1])/atlas.width,(v+ink[4])/atlas.height
        list:AddImageQuad(atlas.image.id,q1,q2,q3,q4,t1,t2,t3,t4,color)
        return
    end
    local width,height=pixel(glyph.advance*factor),pixel(16*factor)
    q1[1],q1[2],q2[1],q2[2]=x+dx,y+dy,x+dx+width,y+dy
    q3[1],q3[2],q4[1],q4[2]=x+dx+width,y+dy+height,x+dx,y+dy+height
    t1[1],t1[2],t2[1],t2[2]=u/atlas.width,v/atlas.height,(u+glyph.advance)/atlas.width,v/atlas.height
    t3[1],t3[2],t4[1],t4[2]=(u+glyph.advance)/atlas.width,(v+16)/atlas.height,u/atlas.width,(v+16)/atlas.height
    list:AddImageQuad(atlas.image.id,q1,q2,q3,q4,t1,t2,t3,t4,color)
end

local function draw_foreground(face,list,text,x,y,size,color,compact)
    local atlas=face.foreground
    text=tostring(text or '')
    x,y=pixel(x),pixel(y)
    if compact then
        local left,top=compact_bounds(face,text,size)
        x,y=x-left,y-top
    end
    walk(face,text,size,draw_foreground_glyph,list,atlas,x,y,color,compact)
    return true
end

-- One walk of a countdown's glyphs, kept for its passes. Positions here are whole pixels, so a pass offset
-- added after the walk gives the same corners as walking again at that offset.
local gx1,gy1,gx2,gy2,gu1,gv1,gu2,gv2,glyphs={},{},{},{},{},{},{},{},0

local function collect_foreground_glyph(glyph,dx,dy,factor,atlas,x,y,compact)
    local code=glyph.code
    local u,v=(code-32)%16*16,math.floor((code-32)/16)*16
    local x1,y1,x2,y2,u1,v1,u2,v2
    if compact then
        local ink=glyph.countdown_ink
        if not ink then return end
        x1,y1=x+dx+pixel(ink[1]*factor),y+dy+pixel(ink[2]*factor)
        x2,y2=x+dx+pixel(ink[3]*factor),y+dy+pixel(ink[4]*factor)
        if x2<=x1 or y2<=y1 then return end
        u1,v1,u2,v2=(u+ink[1])/atlas.width,(v+ink[2])/atlas.height,(u+ink[3])/atlas.width,(v+ink[4])/atlas.height
    else
        local width,height=pixel(glyph.advance*factor),pixel(16*factor)
        x1,y1,x2,y2=x+dx,y+dy,x+dx+width,y+dy+height
        u1,v1,u2,v2=u/atlas.width,v/atlas.height,(u+glyph.advance)/atlas.width,(v+16)/atlas.height
    end
    glyphs=glyphs+1
    gx1[glyphs],gy1[glyphs],gx2[glyphs],gy2[glyphs]=x1,y1,x2,y2
    gu1[glyphs],gv1[glyphs],gu2[glyphs],gv2[glyphs]=u1,v1,u2,v2
end

-- Draws the text once per pass, at each pass offset in its color, in the order the passes are given.
local function replay_foreground(face,list,text,x,y,size,compact,count,dxs,dys,colors)
    local atlas=face.foreground
    text=tostring(text or '')
    x,y=pixel(x),pixel(y)
    if compact then
        local left,top=compact_bounds(face,text,size)
        x,y=x-left,y-top
    end
    glyphs=0
    walk(face,text,size,collect_foreground_glyph,atlas,x,y,compact)
    local id=atlas.image.id
    for pass=1,count do
        local dx,dy,color=dxs[pass],dys[pass],colors[pass]
        for n=1,glyphs do
            local x1,y1,x2,y2=gx1[n]+dx,gy1[n]+dy,gx2[n]+dx,gy2[n]+dy
            q1[1],q1[2],q2[1],q2[2],q3[1],q3[2],q4[1],q4[2]=x1,y1,x2,y1,x2,y2,x1,y2
            t1[1],t1[2],t2[1],t2[2]=gu1[n],gv1[n],gu2[n],gv1[n]
            t3[1],t3[2],t4[1],t4[2]=gu2[n],gv2[n],gu1[n],gv2[n]
            list:AddImageQuad(id,q1,q2,q3,q4,t1,t2,t3,t4,color)
        end
    end
    return true
end

-- The second result draws every pass of one countdown from a single walk.
function client_fonts.countdown_renderer(name)
    local face=countdown_face(name)
    if not face then return nil end
    if not face.countdown_renderer then
        face.countdown_renderer=function(list,text,x,y,size,color,compact) return draw_foreground(face,list,text,x,y,size,color,compact) end
        face.countdown_replay=function(list,text,x,y,size,compact,count,dxs,dys,colors)
            return replay_foreground(face,list,text,x,y,size,compact,count,dxs,dys,colors)
        end
    end
    return face.countdown_renderer,face.countdown_replay
end

if VANTAGE_TEST_MODE then
    function client_fonts.draw_countdown(list,name,text,x,y,size,color,compact)
        local renderer=client_fonts.countdown_renderer(name)
        return renderer and renderer(list,text,x,y,size,color,compact) or false
    end
end

return client_fonts
