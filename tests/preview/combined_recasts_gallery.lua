local hud, defaults, imgui = require('ui.hud'), require('ui.defaults'), require('imgui')
require('ui.recast_icons').prepare()
local view, sets = hud.sample(100), {}
for _,row in ipairs(view.rows) do
    if row.effect==10004 then row.spell_id,row.list_icon_hq,row.list_icon_nq=4,89,6
    elseif row.effect==10057 then row.spell_id,row.list_icon_hq,row.list_icon_nq=57,143,2
    elseif row.effect==20005 then row.ability_id,row.list_icon_id,row.ability_element=547,360,41
    elseif row.effect==45762 then row.item_id,row.recast_id=15762,15762 end
end
for index,mode in ipairs({'bars','expanded','icons'}) do
    local s=defaults.make();require('original_skin_fixture')(s)
    s.recast_display='combined';s.style.icon_size=48
    for key,p in pairs(s.panels)do p.enabled=key=='recasts' end
    local p=s.panels.recasts
    p.x,p.y,p.width,p.mode,p.title=20+(index-1)*345,25,325,mode,'Combined / '..mode
    p.wrap,p.show_total=true,mode=='expanded'
    sets[#sets+1]=s
end
local original=imgui.Begin
return function()
    for index,s in ipairs(sets)do
        imgui.Begin=function(name,...)return original(name..'_combined_gallery_'..index,...)end
        local ok,err=pcall(hud.draw,view,s,100,{})
        imgui.Begin=original;if not ok then error(err)end
    end
end
