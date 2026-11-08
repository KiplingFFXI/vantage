-- A recast whose action gives a buff or debuff shows that status icon, in the buff icon artwork. Actions with
-- none, shared timers the data can't narrow to one status, unknown actions and items keep their own picture.
local actions_drawn = {}
package.loaded['ui.action_icons'] = {
    prepare = function() end, clear = function() end,
    draw = function(_, _, hq) actions_drawn[#actions_drawn + 1] = hq; return true end,
}
package.loaded['ui.item_icons'] = {
    prepare = function() end, clear = function() end,
    texture = function() return 909 end,
}
local statuses = require('ui.icons')
local missing, status_calls = { [33] = true }, {}
statuses._set_loader_for_tests(function(id) if missing[id] then return nil end return 7000 + id end)
local status = statuses.status
statuses.status = function(id, artwork) status_calls[#status_calls + 1] = artwork; return status(id, artwork) end
local recast_icons = require('ui.recast_icons')
local defaults, hud, theme = require('ui.defaults'), require('ui.hud'), require('ui.theme')

-- What the player's own job abilities gave, read by the real observer.
local observer = require('core.observer')
local self_id, ally = 1001, 1002
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 1, self_known = true,
    self_effects = {}, party = { { id = ally, name = 'Ally', scope = 'party', zone = 102 } },
    entities = { [self_id] = { name = 'Tester' }, [ally] = { name = 'Ally', kind = 'player' } } }
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8) end
    end
end
local function action(actor, category, id, targets)
    local bytes, at = MOCK.bytes(2048), 150
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #targets); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id)
    for _, target in ipairs(targets) do
        putbits(bytes, at, 32, target[1]); putbits(bytes, at + 32, 4, 1); at = at + 36
        putbits(bytes, at + 27, 17, target[3]); putbits(bytes, at + 44, 10, target[2]); at = at + 87
    end
    bytes.n = math.ceil(at / 8)
    return MOCK.packet(0x028, bytes)
end
local function learn(packet)
    local seen = observer.read(packet, 1, snapshot)
    assert(#seen > 0, 'The observer reads the action.')
    recast_icons.learn(seen, snapshot)
end
learn(action(self_id, 4, 31, { { self_id, 230, 43 } }))      -- a spell numbered like Berserk teaches no ability
learn(action(self_id, 6, 31, { { self_id, 115, 56 } }))      -- Berserk
learn(action(self_id, 6, 33, { { self_id, 117, 57 } }))      -- Defender
learn(action(ally, 6, 32, { { ally, 116, 68 } }))            -- someone else's Warcry
learn(action(self_id, 6, 40, { { self_id, 100, 60 } }))      -- an ability seen giving two different statuses
learn(action(self_id, 6, 40, { { self_id, 100, 61 } }))
learn(action(self_id, 6, 999, { { self_id, 115, 56 } }))     -- the other action on a shared timer, same status

local now = 100
local function recast(kind, id, name, left, extra)
    local base = kind == 'spell' and 10000 or kind == 'ability' and 20000 or 30000
    local row = { key = 'r_' .. kind .. id, instance = 1, effect = base + id, recast_id = id, name = name, kind = kind,
        group = kind .. '_recasts', domain = 'recast', scope = 'self', entity_id = self_id, status = 'server', present = true,
        deadline = now + left, remaining = left, total = left, start = now }
    for key, value in pairs(extra or {}) do row[key] = value end
    return row
end
local function one(id, icon) return { ability_id = id, list_icon_id = icon, action_icons = { { ability_id = id, list_icon_id = icon } } } end
local rows = {
    recast('spell', 43, 'Protect', 20, { list_icon_hq = 101 }),
    recast('spell', 44, 'Protect II', 21, { list_icon_hq = 102 }),
    recast('spell', 58, 'Paralyze', 22, { list_icon_hq = 103 }),
    recast('spell', 23, 'Dia', 23, { list_icon_hq = 104 }),
    recast('spell', 394, 'Valor Minuet', 24, { list_icon_hq = 105 }),
    recast('spell', 137, 'Sneak', 25, { list_icon_hq = 106 }),
    recast('spell', 4, 'Cure IV', 26, { list_icon_hq = 107 }),
    recast('spell', 57, 'Haste', 27, { list_icon_hq = 108 }),
    recast('ability', 5, 'Provoke', 28, one(547, 201)),
    recast('ability', 193, 'Fighter\'s Roll / Monk\'s Roll (shared)', 29, { shared = true, icon_ambiguous = true,
        action_icons = { { ability_id = 610, list_icon_id = 202 }, { ability_id = 611, list_icon_id = 203 } } }),
    recast('ability', 194, 'Fighter\'s Roll', 30, one(610, 204)),
    recast('ability', 1, 'Berserk', 31, one(543, 205)),
    recast('ability', 3, 'Defender', 32, one(545, 206)),
    recast('ability', 2, 'Warcry', 33, one(544, 207)),
    recast('ability', 9, 'Berserk / Other (shared)', 34, { shared = true,
        action_icons = { { ability_id = 543, list_icon_id = 208 }, { ability_id = 1511, list_icon_id = 209 } } }),
    recast('ability', 10, 'Changing ability', 35, one(552, 210)),
    recast('ability', 11, 'Shadowbind', 36, one(569, 211)),
    recast('ability', 0, 'Job special (shared)', 37, { shared = true, icon_ambiguous = true, action_icons = {} }),
    recast('item', 15762, 'Empress Band', 38, { item_id = 15762 }),
}
local buff = { key = 'buff_protect', instance = 1, effect = 40, name = 'Protect', kind = 'buff', group = 'Buffs', scope = 'self',
    entity_id = self_id, entity_name = 'Tester', status = 'server', present = true, deadline = now + 600, remaining = 600 }
local view = hud.sample(now)
view.rows = { buff }
for _, row in ipairs(rows) do view.rows[#view.rows + 1] = row end

-- The mapping itself: each kind of action, tiers, shared timers, unknowns and items.
local expected = { Protect = 40, ['Protect II'] = 40, Paralyze = 4, Dia = 134, ['Valor Minuet'] = 198, Sneak = 71,
    ['Fighter\'s Roll'] = 310, Berserk = 56, Defender = 57, ['Berserk / Other (shared)'] = 56, Shadowbind = 11, Haste = 33 }
for _, row in ipairs(rows) do
    assert(recast_icons.effect(row) == expected[row.name], row.name .. ' maps to the status its action gives, or none.')
end
assert(recast_icons.effect({ kind = 'ability', ability_id = 547 }) == nil and recast_icons.effect({ kind = 'ability' }) == nil,
    'A single action with no status, or none known, has no status icon.')

local settings = defaults.make()
assert(settings.style.recast_icon_source == 'effect', 'Recasts show buff and debuff icons by default.')
settings.recast_display = 'combined'
for key, p in pairs(settings.panels) do p.enabled = key == 'recasts' or key == 'self_buffs' end
local panel = settings.panels.recasts
panel.max_rows, panel.height_limit, panel.width = 64, 4000, 600
MOCK.screen = { 3000, 4000 }

local function sorted(list) table.sort(list); return table.concat(list, ',') end
local function render(mode)
    panel.mode = mode
    actions_drawn, status_calls, MOCK.imgui_calls = {}, {}, {}
    hud.draw(view, settings, now, {})
    local shown, items, sizes = {}, 0, {}
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddImage' and call[2] == 909 then items = items + 1
        elseif call[1] == 'draw:AddImage' and type(call[2]) == 'number' and call[2] >= 7000 then
            shown[#shown + 1] = call[2] - 7000
            local values = MOCK.drawn[call]
            sizes[#sizes + 1] = { values[4][1] - values[3][1], values[4][2] - values[3][2], call[7] }
        end
    end
    assert(#MOCK.font_stack == 0, 'Every panel font push is popped.')
    return shown, items, sizes
end

for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    local shown, items, sizes = render(mode)
    -- The Protect buff's own icon is the first 40; the two Protect recasts share it.
    assert(sorted(shown) == '4,11,40,40,40,56,56,57,71,134,198,310',
        'Status recasts draw the same status icons as the buff panel in ' .. mode)
    assert(sorted(actions_drawn) == '107,108,201,202,203,207,210',
        'Rows with no single known status keep their action pictures in ' .. mode)
    assert(items == 1, 'Item recasts keep the item picture in ' .. mode)
    local haste = false
    for _, hq in ipairs(actions_drawn) do haste = haste or hq == 108 end
    assert(haste, 'Haste has no status art here, so it keeps its action picture in ' .. mode)
    for _, artwork in ipairs(status_calls) do assert(artwork == settings.style.icon_art, 'Recasts use the buff icon artwork.') end
    for _, size in ipairs(sizes) do
        assert(size[1] == settings.style.icon_size and size[2] == settings.style.icon_size, 'A status icon fills the icon box in ' .. mode)
        -- Compared as the 32 bits the binding takes: Ashita's col32 gives them signed.
        assert(size[3] % 4294967296 == theme.u32({ 1, 1, 1, 1 }) % 4294967296, 'Background opacity does not dim recast status icons.')
    end
end

-- The art choice follows the buff panels.
settings.style.icon_art = 'XI View'
settings.panels.self_buffs.enabled = false
render('bars')
assert(#status_calls > 0, 'Status icons are looked up for recasts.')
for _, artwork in ipairs(status_calls) do assert(artwork == 'XI View', 'Changing the buff icon artwork changes the recast status icons.') end

-- The setting switches every recast back to action icons.
settings.style.recast_icon_source = 'action'
for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    local shown, items = render(mode)
    assert(#shown == 0 and #status_calls == 0, 'Action icons draw no status icons in ' .. mode)
    assert(sorted(actions_drawn) == '101,102,103,104,105,106,107,108,201,202,203,204,205,206,207,208,209,210,211',
        'Action icons restore every action picture in ' .. mode)
    assert(items == 1, 'Action icons keep the item picture in ' .. mode)
end

-- Saved settings keep their choice; files without it take the default.
settings = defaults.tidy(settings)
assert(settings.style.recast_icon_source == 'action', 'A saved choice of action icons is kept.')
settings.style.recast_icon_source = 'other'
assert(defaults.tidy(settings).style.recast_icon_source == 'effect', 'An unknown saved choice takes the default.')
local saved = { style = { recast_icon_art = 'XI View', icon_art = 'Client' }, panels = { spell_recasts = { mode = 'icons' } } }
saved = defaults.tidy(saved)
assert(saved.style.recast_icon_source == 'effect' and saved.style.recast_icon_art == 'XI View' and saved.style.icon_art == 'Client'
    and saved.panels.spell_recasts.mode == 'icons', 'Settings without it take the default and keep every saved choice.')

-- The choice is on the Recasts panel's Show tab and found by search before the page is opened.
local window, imgui = require('ui.settings_window'), require('imgui')
local found = false
for _, result in ipairs(window.search('buff and debuff icons')) do
    if result.tab == 'Display' and result.label == 'Icons show' then found = true end
end
assert(found, 'Search finds the recast icon choice.')
local editor = defaults.make()
editor.window.open, editor.window.tab = true, 'Display'
local choices, selectable = {}, imgui.Selectable
imgui.BeginCombo = function(label) return label == '##frame_Icons show' end
imgui.Selectable = function(label, ...) choices[label] = true; return selectable(label, ...) end
require('ui.panel_frame').open('recasts', 'show')
MOCK.clicks['The spell or ability##action'] = true
window.draw(editor, hud.sample(now), { changed = function() end, save = function() return true end, now = function() return now end })
assert(choices['The effect it gives##effect'] and choices['The spell or ability##action'], 'The choice offers the effect or the action.')
assert(editor.style.recast_icon_source == 'action', 'Choosing the action saves it.')
imgui.Selectable = selectable

-- The entrypoint teaches it from every status packet it reads.
recast_icons._forget_for_tests()
assert(recast_icons.effect({ kind = 'ability', ability_id = 543 }) == nil, 'Forgetting clears what was learned.')
local copy = defaults.copy
package.loaded['core.client'] = { load = function() end, read = function() return copy(snapshot) end }
local reply = {}
package.loaded['core.observer'] = { read = function() return reply end }
package.loaded['core.recasts'] = { catalog = function() return {} end, new = function() return {
    reset = function() end, update = function() end, view = function() return { rows = {}, version = 0 } end,
    project = function() end, drain_events = function() return {} end,
} end }
local app = dofile(ADDON_DIR .. '/vantage.lua')
MOCK.now = MOCK.now + .2; app.refresh(MOCK.now)
reply = { { kind = 'apply', action_category = 6, spell = 34, effect = 58, source = self_id, entity_id = self_id, scope = 'self' } }
MOCK.fire('packet_in', MOCK.packet(0x028, MOCK.bytes(32)))
assert(recast_icons.effect({ kind = 'ability', ability_id = 546 }) == 58, 'An observed Aggressor teaches its recast the Aggressor icon.')
MOCK.fire('unload')
