local imgui, icons = require('imgui'), require('ui.item_icons')
return function()
    imgui.SetNextWindowPos({ 20, 20 })
    imgui.SetNextWindowSize({ 440, 240 })
    if imgui.Begin('Installed client item icons') then
        local list = imgui.GetWindowDrawList()
        local x, y = imgui.GetWindowPos()
        for index, item in ipairs({ { 15762, 'Empress Band' }, { 15763, 'Emperor Band' } }) do
            local texture = assert(icons.texture(item[1]), 'The installed item icon must load.')
            local top = y + 40 + (index - 1) * 90
            list:AddText({ x + 16, top }, 0xFFFFFFFF, item[2] .. ' / item ' .. item[1])
            list:AddImage(texture, { x + 16, top + 24 }, { x + 48, top + 56 })
            list:AddImage(texture, { x + 72, top + 24 }, { x + 120, top + 72 })
            list:AddText({ x + 145, top + 36 }, 0xFFAAAAAA, '32px native / 48px display')
        end
    end
    imgui.End()
end
