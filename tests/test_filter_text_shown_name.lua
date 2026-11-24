-- Show only names containing goes by the name a row shows. A recast panel keeps only recasts with the text in their
-- name, so your own name and the recast's number don't count there. A row renamed with Rename it is found by its new
-- name, and still by its game name.

-- Client timers: three spells on cooldown, no abilities or items.
local spell_timers = { [43] = 600, [57] = 900, [143] = 1200 }
local manager = {
    GetSpellTimer = function(_, id) return spell_timers[id] or 0 end,
    GetAbilityTimerId = function() return 0 end,
    GetAbilityTimer = function() return 0 end,
}
local spell_resources = { [43] = { Name = { [1] = 'Protect' } }, [57] = { Name = { [1] = 'Haste' } }, [143] = { Name = { [1] = 'Erase' } } }
local resources = {
    GetSpellById = function(_, id) return spell_resources[id] end,
    GetAbilityById = function() return nil end,
    GetAbilityByTimerId = function() return nil end,
    GetItemById = function() return nil end,
}
local memory = { GetRecast = function() return manager end, GetInventory = function() return { GetEquippedItem = function() return { Index = 0 } end } end }
AshitaCore.GetMemoryManager = function() return memory end
AshitaCore.GetResourceManager = function() return resources end

local recasts = require('core.recasts')
local defaults, hud = require('ui.defaults'), require('ui.hud')

-- A character whose name starts like a spell, so typing the start of the spell is part of the name too.
local snapshot = { valid = true, id = 1001, zone = 230, job = 3, name = 'Protagonist' }
local model = recasts.new()
model:update(snapshot, 100, { abilities = false, items = false })
local rows = model:view(100).rows
assert(#rows == 3, 'The tracker makes three spell recast rows.')
for _, row in ipairs(rows) do assert(row.entity_name == 'Protagonist' and row.effect > 10000, 'Live recast rows carry your name and a number.') end

local s = defaults.make()
s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = false, false, false
local view = { valid = true, context = { id = 1001, zone = 230, job = 3, name = 'Protagonist' }, rows = rows }
local function names(found)
    local out = {}
    for index, row in ipairs(found) do out[index] = row.name end
    table.sort(out)
    return table.concat(out, ',')
end
local function filtered(panel, key, from, text)
    panel.filter = text
    local found = names(hud.filter_rows(from, panel, key, s))
    panel.filter = ''
    return found
end

local p = s.panels.spell_recasts
assert(filtered(p, 'spell_recasts', view, 'eras') == 'Erase', 'A spell name narrows to that spell.')
local pro = filtered(p, 'spell_recasts', view, 'pro')
assert(pro == 'Protect', 'Text that is also part of your name keeps only the recasts with it in their name, kept: ' .. pro)
local own = filtered(p, 'spell_recasts', view, 'agonist')
assert(own == '', 'Text only in your name keeps no recast, kept: ' .. own)
local number = filtered(p, 'spell_recasts', view, '0')
assert(number == '', 'Text only in the recast numbers keeps no recast, kept: ' .. number)

-- Renamed on a recast panel: the new name finds it, and the game name still does.
p.labels[10057] = 'Speedup'
local renamed = filtered(p, 'spell_recasts', view, 'speedup')
assert(renamed == 'Haste', 'A renamed recast is found by the name it shows, found: [' .. renamed .. ']')
assert(filtered(p, 'spell_recasts', view, 'haste') == 'Haste', 'A renamed recast is still found by its game name.')

-- Renamed on a status panel, with the samples (Haste on you from a party member, effect 33).
local sample = hud.sample(100)
local b = s.panels.self_buffs
b.labels[33] = 'Speedup'
local shown = filtered(b, 'self_buffs', sample, 'speedup')
assert(shown == 'Haste', 'A renamed effect is found by the name it shows, found: [' .. shown .. ']')
assert(filtered(b, 'self_buffs', sample, 'haste') == 'Haste', 'A renamed effect is still found by its game name.')
-- Status rows still match who cast it and the effect number.
assert(filtered(b, 'self_buffs', sample, 'party member') == 'Haste', 'A status row is found by who cast it.')
assert(filtered(b, 'self_buffs', sample, '41') == 'Shell', 'A status row is found by its effect number.')
-- And who it is on, on a panel that shows other people's effects.
local enemy = filtered(s.panels.target, 'target', sample, 'training crab')
assert(enemy == 'Dia,Sleep', 'A status row is found by who it is on, found: [' .. enemy .. ']')
return true
