local texture_reads = 0
package.loaded['ui.client_assets'] = {
    texture = function(kind, name)
        texture_reads = texture_reads + 1
        if name == 'gauge' then return {id=kind..':gauge',width=64,height=64} end
    end,
}
local defaults, theme, skin = require('ui.defaults'), require('ui.theme'), require('ui.client_skin')
local hud, fonts, equal = require('ui.hud'), require('ui.fonts'), require('core.customization').equal
require('ui.icons').status=function() return 'status-icon' end
require('ui.recast_icons').draw=function(list,_,_,x,y,size)
    list:AddImage('recast-icon',{x,y},{x+size,y+size});return true
end
local captions = {}
fonts.measure = function(_, text, size) return #text*size*.5 end
fonts.draw = function(_, _, value, x, y, size)
    captions[#captions+1]={text=value,x=x,y=y,size=size};return true
end
local countdown = require('ui.countdown_text')
local draw_countdown = countdown.draw
countdown.draw = function(list, font, value, x, y, size, ink, options)
    local _, top, _, bottom = countdown.padding(options)
    local height = size + top + bottom
    captions[#captions+1] = {text=value,x=x,y=y,size=height}
    return draw_countdown(list,font,value,x,y,size,ink,options)
end
local function calls(name)
    local result={}
    for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='draw:'..name then result[#result+1]=call end end
    return result
end
local function fresh(key, mode, artwork)
    local s=defaults.make()
    theme.apply(s,'Original FFXI')
    s.style.minimal,s.style.text_shadow,s.style.text_outline=true,false,false
    s.style.gauge_art=artwork or 'Original FFXI'
    s.style.font_size,s.style.icon_size,s.style.bar_height,s.style.opacity=16,28,25,.92
    s.recast_display=key=='recasts' and 'combined' or 'separate'
    for id,p in pairs(s.panels) do p.enabled=id==key end
    local p=s.panels[key]
    p.x,p.y,p.width,p.show_icon,p.show_heading,p.mode=20,20,420,false,false,mode
    p.bar_style,p.bar_thickness='full',4
    local row={key='dedication',effect=249,name='Dedication',scope='self',kind='buff',group='Recovery',
        entity_id=1001,status='server',deadline=3094,total=3600,present=true,instance=1}
    if key=='self_debuffs' then row.kind='debuff' end
    if key=='party' then row.scope='party' end
    if key=='target' or key=='watch' then row.entity_id=16781313;row.scope='target' end
    if defaults.recast_panels[key] then
        row.domain,row.kind,row.effect,row.name='recast',defaults.recast_panels[key]=='all' and 'spell' or defaults.recast_panels[key],10057,'Haste'
    end
    s.watch_ids={16781313}
    local view={valid=true,context={valid=true,id=1001,target={id=16781313}},rows={row},notices={}}
    return s,p,view
end
local function draw(s,view)
    MOCK.imgui_calls,captions,texture_reads={},{},0
    hud.draw(view,s,100,{})
end

-- Theme-only selection, imported layouts, and intentional full bars all stay readable.
for _,key in ipairs(defaults.panel_order) do
    for _,mode in ipairs({'bars','expanded','icons'}) do
        for _,art in ipairs({'Original FFXI','XI View'}) do
            local s,p,view=fresh(key,mode,art)
            local before=defaults.copy(s)
            draw(s,view)
            local fills=calls('AddRectFilled')
            if mode=='icons' then
                assert(#calls('AddImage')==1 and texture_reads==0 and #fills==0, 'Icons only draws the actual picture without a native gauge or fill.')
                for _,caption in ipairs(captions) do assert(caption.text==hud.timer_text(view.rows[1],100), 'Only the countdown accompanies an icon.') end
            else
                assert(#calls('AddImage')==0 and texture_reads==0, 'Full timer bars never request or stretch a native gauge: '..key..' '..mode)
                assert(#fills==2 and fills[2][4]==theme.u32(s.style.buff_color,.3*s.style.opacity), 'Full timer fill uses its subdued regular drawing.')
            end
            assert(#captions>=(mode=='icons' and 1 or 2), 'Each visible timer keeps its countdown, and bar modes also retain their label.')
            assert(equal(s,before), 'Rendering retains the chosen full style and saved customization.')
        end
    end
end

for _,scale in ipairs({.5,1,2.5}) do
    for _,mode in ipairs({'bars','expanded','icons'}) do
        local s,p,view=fresh('self_buffs',mode)
        s.style.scale,s.style.font_size=scale,32
        p.bar_style,p.bar_thickness='rail',8
        draw(s,view)
        local images=calls('AddImage')
        assert(#images==(mode=='icons' and 1 or 4) and texture_reads==(mode=='icons' and 0 or 1),
            'Icons only omits the stored rail; bar layouts retain the selected client artwork.')
        local top=math.huge
        for _,image in ipairs(images) do
            if mode=='icons' then assert(image[4][2]-image[3][2]==s.style.icon_size*scale, 'The icon keeps its selected height.')
            else
                assert(image[4][2]-image[3][2]<=8*scale, 'A native timer rail keeps its selected height.')
                top=math.min(top,image[3][2])
            end
        end
        for _,caption in ipairs(captions) do
            if mode=='icons' then assert(caption.y>=images[1][4][2], 'The icon countdown stays below its picture.')
            else assert(caption.y+caption.size<=top,
                'Rail captions stay above the native gauge: '..scale..'/'..mode..'/'..caption.text..' bottom='..(caption.y+caption.size)..' rail='..top) end
        end
    end
end

-- Full-fill custom colors, gradients, dimensions and direction remain deliberate choices.
for _,gradient in ipairs({false,true}) do
    local s,p,view=fresh('self_buffs','expanded','XI View')
    p.gradient,p.fill_direction,p.row_height=gradient,'left',64
    p.colors={fill_start={.2,.8,.3,.6},fill_end={.7,.3,.1,.4},track={.1,.12,.15,.7}}
    local before=defaults.copy(s)
    draw(s,view)
    assert(equal(s,before) and p.bar_style=='full' and texture_reads==0)
    local fill=calls(gradient and 'AddRectFilledMultiColor' or 'AddRectFilled')
    local painted=gradient and fill[1] or fill[2]
    assert(painted and painted[3][2]-painted[2][2]>=64)
    local expected=gradient and p.colors.fill_end or p.colors.fill_start
    assert(painted[4]==theme.u32(expected,.3*s.style.opacity), 'Custom full fills keep their colors and opacity.')
end

-- Party resource gauges have their own measured geometry and no timer bar-style field.
local images={}
local list={AddImage=function(_,...)images[#images+1]={...}end}
local s=defaults.make();theme.apply(s,'Original FFXI')
local party_panel={colors={},fill_direction='right',gradient=false}
assert(skin.gauge(list,10,20,120,8,.5,s.style,party_panel,{1,1,1,1}) and #images==4,
    'The timer guard preserves party_theme resource gauge calls.')
party_panel.bar_style='full';images={};texture_reads=0
assert(not skin.gauge(list,10,20,120,32,.5,s.style,party_panel,{1,1,1,1}) and #images==0 and texture_reads==0)
