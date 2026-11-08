-- With Ashita's item data library unable to load, the Recasts page says in one plain line that item recasts are
-- off, in both recast layouts. Before an item needs the library, and with it loaded, the page says nothing of it.
local defaults, hud = require('ui.defaults'), require('ui.hud')
local window = require('ui.settings_window')
MOCK.screen = { 1600, 900 }
package.preload['ffxi.itemdata'] = function() error('[lib.time] Error: Failed to locate required pointer(s).') end
local recasts = require('core.recasts')
local app = dofile(ADDON_DIR .. '/vantage.lua')
assert(app.callbacks.recast_item_status == recasts.item_status, 'Vantage hands the settings window the item recast status.')

local items = { [2050] = { Id = 17570, Index = 2050, Extra = string.char(1) .. string.rep('\0', 11) } }
local inventory = {
    GetEquippedItem = function(_, slot) return { Index = slot == 13 and 2050 or 0 } end,
    GetContainerItem = function(_, container, index) return items[container * 256 + index] end,
}
local manager = { GetSpellTimer = function() return 0 end, GetAbilityTimerId = function() return 0 end, GetAbilityTimer = function() return 0 end }
local resources = {
    GetSpellById = function() return nil end, GetAbilityById = function() return nil end, GetAbilityByTimerId = function() return nil end,
    GetItemById = function(_, id)
        return id == 17570 and { Name = { [1] = 'Enchanted ring' }, Type = 5, MaxCharges = 10, CastDelay = 30, RecastDelay = 1800 } or nil
    end,
}
AshitaCore.GetMemoryManager = function() return { GetRecast = function() return manager end, GetInventory = function() return inventory end } end
AshitaCore.GetResourceManager = function() return resources end

local now = 100
local callbacks = { changed = function() end, save = function() return true end, now = function() return now end,
    recast_item_status = app.callbacks.recast_item_status }
local reason = 'Item recasts are off because the Ashita item data library could not load on this client.'
local function said(display)
    local editor = defaults.make()
    editor.window.open, editor.window.tab = true, 'Recasts'
    editor.recast_display = display
    MOCK.imgui_calls = {}
    window.draw(editor, hud.sample(now), callbacks)
    local count = 0
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextWrapped' and type(call[2]) == 'string' and call[2]:find('Item recasts are', 1, true) then
            assert(call[2] == reason, 'The page line is the plain status line: ' .. call[2])
            count = count + 1
        end
    end
    return count
end

for _, display in ipairs({ 'separate', 'combined' }) do
    assert(said(display) == 0, 'Nothing is said before an item needs the library: ' .. display)
end
local model = recasts.new()
model:update({ valid = true, id = 1001, zone = 230, job = 1, name = 'Aster' }, now)
assert(recasts.item_status().available == false, 'Fixture: the item data library failed to load.')
for _, display in ipairs({ 'separate', 'combined' }) do
    assert(said(display) == 1, 'The Recasts page says once that item recasts are off: ' .. display)
end
assert(not reason:find('?', 1, true) and not reason:lower():find('unknown', 1, true))
callbacks.recast_item_status = function() return { available = true, reason = 'Item recasts are on.' } end
for _, display in ipairs({ 'separate', 'combined' }) do
    assert(said(display) == 0, 'With the library loaded the page says nothing of it: ' .. display)
end
return 'The Recasts page says when item recasts are off'
