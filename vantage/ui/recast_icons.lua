local icons = {}
local actions = require('ui.action_icons')
local items = require('ui.item_icons')
local statuses = require('ui.icons')
local data = require('data.effects')
local rolls = require('data.actions').rolls
local shared = setmetatable({}, { __mode = 'k' })
-- Job ability ID to the status the player's own use of it gave, false once it gave two different ones.
-- Kept across zones and texture resets: it is game data, not character state.
local learned = {}
-- Actions whose row in the effect data names an effect they give only sometimes, so it isn't the effect they give.
-- Every Cure's Stoneskin needs Afflatus Solace (scripts/actions/spells/white/cure.lua :70-72), which is WotG
-- (sql/abilities.sql :263). Chakra's Regen and Chi Blast's Inhibit TP need merits (globals/job_utils/monk.lua :66-72,
-- :80-83). Charm binds only a monster it can't charm (beastmaster.lua :165-172), Jump lowers Defense only under Spirit
-- Surge (dragoon.lua :237-242), and Double-Up gives Bust only when you bust (corsair.lua :498-502). The rows still give
-- the effect's length when it lands (core/catalog.lua).
local sometimes = { spells = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true },
    abilities = { [38] = true, [52] = true, [66] = true, [82] = true, [123] = true } }

local function choices(entries)
    if type(entries) ~= 'table' then return nil end
    if shared[entries] then return shared[entries] end
    local result, seen = {}, {}
    for _, entry in ipairs(entries) do
        local hq, nq = entry.list_icon_id, entry.ability_element
        if type(hq) == 'number' or type(nq) == 'number' then
            local key = tostring(hq) .. ':' .. tostring((hq == nil or hq == 65535) and nq or '')
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = { hq = hq, nq = nq }
            end
        end
    end
    shared[entries] = result
    return result
end

function icons.prepare()
    items.prepare()
    actions.prepare()
end

-- The item picture loader, then the stock action pack one file at a time, as warmup steps.
function icons.warmup_steps()
    local steps = { require('ui.client_assets').step('recasts.items', items.ready, items.prepare) }
    for _, step in ipairs(actions.warmup_steps('Original FFXI')) do steps[#steps + 1] = step end
    return steps
end

-- A job ability resource ID is its action ID plus 0x200.
local function ability_effect(id)
    local action = type(id) == 'number' and id - 512
    if not action or action < 0 or action > 1023 then return nil end
    if rolls[action] then return rolls[action] end
    local info = not sometimes.abilities[action] and data.abilities[action]
    if info then return info.effect end
    return learned[action] or nil
end

-- The status a recast's action gives, from the effect data or the player's own observed use. A shared timer
-- has one only when every action it can stand for gives the same one. Items and anything unknown have none.
function icons.effect(row)
    if row.kind == 'spell' then
        local info = not sometimes.spells[row.recast_id] and data.spells[row.recast_id]
        return info and info.effect or nil
    elseif row.kind ~= 'ability' then return nil end
    local candidates, found = row.action_icons
    -- A row with no action pictures stands for its own ability alone.
    if type(candidates) ~= 'table' or #candidates == 0 then return row.ability_id and ability_effect(row.ability_id) or nil end
    for _, candidate in ipairs(candidates) do
        local effect = ability_effect(candidate.ability_id)
        if not effect or found and effect ~= found then return nil end
        found = effect
    end
    return found
end

-- Observations from one packet. Only the player's own job abilities teach anything.
function icons.learn(observations, snapshot)
    local self_id = type(snapshot) == 'table' and snapshot.id
    if not self_id or type(observations) ~= 'table' then return end
    for _, seen in ipairs(observations) do
        local action, effect = seen.spell, seen.effect
        if seen.kind == 'apply' and seen.action_category == 6 and seen.source == self_id and not seen.exact
            and type(action) == 'number' and action >= 0 and action <= 1023 and type(effect) == 'number' then
            if learned[action] == nil then learned[action] = effect
            elseif learned[action] ~= effect then learned[action] = false end
        end
    end
end

-- An image's corners and tint, refilled for each draw: the binding copies a vector when it is called and keeps none.
local corner, far, UV0, UV1, white = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 }
local function image(list, texture, x, y, size, opacity)
    corner[1], corner[2], far[1], far[2], white[4] = x, y, x + size, y + size, opacity or 1
    list:AddImage(texture, corner, far, UV0, UV1, require('ui.theme').u32(white))
end

-- status_art is the buff icon artwork when recasts show the status their action gives.
function icons.draw(list, row, artwork, x, y, size, opacity, status_art)
    if status_art then
        local texture = statuses.status(icons.effect(row), status_art)
        if texture then
            image(list, texture, x, y, size, opacity)
            return true
        end
    end
    if row.kind == 'item' then
        local texture = items.texture(row.item_id or row.recast_id)
        if not texture then return false end
        image(list, texture, x, y, size, opacity)
        return true
    elseif row.kind == 'spell' then
        return actions.draw(list, artwork, row.list_icon_hq, row.list_icon_nq, x, y, size, opacity)
    elseif row.kind ~= 'ability' then return false end
    if row.list_icon_id ~= nil then
        return actions.draw(list, artwork, row.list_icon_id, row.ability_element, x, y, size, opacity)
    end
    local variants = choices(row.action_icons)
    if not variants or #variants == 0 then return false end
    if #variants == 1 then
        return actions.draw(list, artwork, variants[1].hq, variants[1].nq, x, y, size, opacity)
    end
    local cell, shown = math.max(1, (size - 2) / 2), false
    for index = 1, math.min(4, #variants) do
        local icon = variants[index]
        local left = x + (index - 1) % 2 * (cell + 2)
        local top = y + math.floor((index - 1) / 2) * (cell + 2)
        shown = actions.draw(list, artwork, icon.hq, icon.nq, left, top, cell, opacity) or shown
    end
    return shown
end

function icons.clear()
    items.clear()
    actions.clear()
    shared = setmetatable({}, { __mode = 'k' })
end

-- The buff icon artwork a recast draws its status with, or nil for action icons.
function icons.status_art(style)
    if style.recast_icon_source ~= 'action' then return style.icon_art or 'Client' end
end

if VANTAGE_TEST_MODE then
    function icons._forget_for_tests() learned = {} end
end

return icons
