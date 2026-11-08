-- Every Vantage display, by one id each, for edit mode, anchors, When to show and exports: where its settings
-- are, the keys of its place, lock, anchor and When to show, and where it was drawn. Each display gives its
-- place here as it draws (record), with the draw list of the window it opens (opened), and an anchored one asks
-- place for where its anchor puts it. The party list strips
-- move in edit mode as three strips but share one When to show; the overhead icons sit over heads in the world,
-- so they have When to show only. The records are kept and refilled, so a frame makes nothing here.
local elements = {};
local anchors = require('core.anchors');

local function panel(id, label) return { id = id, label = label, panel = true, x = 'x', y = 'y',
    lock = 'locked', anchor = 'anchor', conditions = 'conditions' }; end
local function box(id, label) return { id = id, label = label, x = 'x', y = 'y',
    lock = 'locked', anchor = 'anchor', conditions = 'conditions' }; end

elements.list = {
    panel('self_buffs', 'Self buffs'), panel('self_debuffs', 'Self debuffs'), panel('target', 'Target timers'),
    panel('party', 'Party members\' timers'), panel('watch', 'Watched enemy timers'),
    panel('spell_recasts', 'Spell recasts'), panel('ability_recasts', 'Ability recasts'),
    panel('item_recasts', 'Item recasts'), panel('recasts', 'Recasts (one panel)'),
    { id = 'notices', label = 'Alerts', x = 'notice_x', y = 'notice_y',
        lock = 'notice_locked', anchor = 'notice_anchor', conditions = 'notice_conditions' },
    box('cooldown_list', 'Party cooldowns list'),
    { id = 'pulse', label = 'Ready pulse', x = 'x', y = 'y', lock = 'locked', anchor = 'anchor', conditions = 'conditions' },
    box('rolls', 'Phantom Roll'), box('pet', 'Pet'),
    { id = 'party_ui', label = 'Party list buffs', lock = 'locked', conditions = 'conditions', strips = true },
    { id = 'overhead', label = 'Overhead icons', conditions = 'conditions', world = true },
};
-- What edit mode moves: every display drawn on the screen, the strips one by one.
elements.movable = {};
for _, element in ipairs(elements.list) do
    if not element.strips and not element.world then elements.movable[#elements.movable + 1] = element; end
end
for group, label in ipairs({ 'Your party', 'Alliance 1', 'Alliance 2' }) do
    elements.movable[#elements.movable + 1] = { id = 'strip_' .. group, label = label, strip = group, lock = 'locked' };
end
elements.by_id = {};
for _, element in ipairs(elements.list) do elements.by_id[element.id] = element; end
for _, element in ipairs(elements.movable) do elements.by_id[element.id] = element; end
-- The displays an anchor can follow: the ones with a place of their own.
elements.anchorable = {};
for _, element in ipairs(elements.list) do if element.anchor then elements.anchorable[element.id] = true; end end

function elements.label(id)
    local element = elements.by_id[id];
    return element and element.label or tostring(id);
end

-- The settings table that holds an element's place, lock, anchor and When to show.
function elements.config(settings, id)
    if type(settings) ~= 'table' then return nil; end
    local element = elements.by_id[id];
    if not element then return nil; end
    if element.panel then return type(settings.panels) == 'table' and settings.panels[id] or nil; end
    if id == 'notices' then return settings.alerts; end
    if id == 'cooldown_list' then return type(settings.party_cooldowns) == 'table' and settings.party_cooldowns.list or nil; end
    if id == 'pulse' then return settings.ready_pulse; end
    if element.strip then
        local party = settings.party_ui;
        return type(party) == 'table' and type(party.groups) == 'table' and party.groups[element.strip] or nil;
    end
    return settings[id];
end

-- The table that holds an element's lock: a strip's is the party list buffs' own.
function elements.lock_holder(settings, id)
    local element = elements.by_id[id];
    if element and element.strip then return settings.party_ui; end
    return elements.config(settings, id);
end

function elements.locked(settings, id)
    local element, holder = elements.by_id[id], elements.lock_holder(settings, id);
    return holder ~= nil and element.lock ~= nil and holder[element.lock] ~= false;
end

function elements.anchor(settings, id)
    local element, config = elements.by_id[id], elements.config(settings, id);
    return element and element.anchor and config and config[element.anchor] or nil;
end

function elements.conditions(settings, id)
    local element, config = elements.by_id[id], elements.config(settings, id);
    return element and element.conditions and config and config[element.conditions] or nil;
end

-- Whether an element is switched on, so edit mode shows it. A strip shows when the game's party list has it.
function elements.on(settings, id)
    local element, config = elements.by_id[id], elements.config(settings, id);
    if not element or not config then return false; end
    if element.panel then return settings.enabled ~= false and require('ui.defaults').panel_enabled(settings, id); end
    if id == 'notices' then return config.enabled == true and not config.muted; end
    if id == 'cooldown_list' then return settings.party_cooldowns.enabled == true and config.enabled == true; end
    if id == 'pulse' then return config.enabled == true and config.spot == 'screen'; end
    if element.strip then return elements.drawn(id) ~= nil; end
    return config.enabled == true;
end

-- Where each element was drawn, with the Present it was drawn in, and the Present its anchor last placed it. The host
-- starts each Present with frame.
local frame, drawn, placed = 0, {}, {};
function elements.frame() frame = frame + 1; end

function elements.record(id, rect)
    local entry = drawn[id];
    if not entry then entry = {}; drawn[id] = entry; end
    entry.x, entry.y, entry.width, entry.height, entry.frame = rect.x, rect.y, rect.width, rect.height, frame;
end

-- The element's place from this Present or the one before, which holds the ones drawn after the one asking.
function elements.drawn(id)
    local entry = drawn[id];
    return entry and entry.frame >= frame - 1 and entry or nil;
end

-- The draw list of the window each display opened, with the Present it opened in. Edit mode draws each outline and
-- name on it, so they sit over the display. A list lasts one Present.
local lists, opened = {}, {};
function elements.opened(id, list) lists[id], opened[id] = list, frame; end

-- The draw list of id's window from this Present, or nil.
function elements.window_list(id)
    return opened[id] == frame and lists[id] or nil;
end

-- The game's party list (your party's window) and the chat log, where Vantage knows them. The host gives the party
-- list at each refresh and hud.draw the chat log each frame; either is nil when it isn't known.
elements.party_list, elements.chat = nil, nil;

-- The display an element's anchor follows.
local function follows(settings, id)
    local anchor = elements.anchor(settings, id);
    return anchors.active(anchor) and anchor.to == 'element' and anchor.element or nil;
end
elements.follows = follows;

-- What a display can move with, in the words its Size and place tab uses. Another display goes by its own name.
elements.follow_names = { none = 'Nothing', screen = 'A spot on the screen', party = 'The game\'s party list', chat = 'The chat log' };

-- What id moves with in plain words. A party group beside the game's list moves with that list.
function elements.moves_with(settings, id)
    local names, anchor = elements.follow_names, elements.anchor(settings, id);
    if anchors.active(anchor) then return anchor.to == 'element' and elements.label(anchor.element) or names[anchor.to]; end
    local element, config = elements.by_id[id], elements.config(settings, id);
    return names[element.strip and not config.native_detached and 'party' or 'none'];
end

-- Whether following from id comes back to it.
function elements.circular(settings, id)
    local at = follows(settings, id);
    for _ = 1, #elements.list do
        if at == nil then return false; end
        if at == id then return true; end
        at = follows(settings, at);
    end
    return true;
end

-- Puts rect where id's anchor puts it, beside a target drawn this Present or the one before. Returns true when the
-- anchor placed it; otherwise rect keeps its fallback spot. The caller keeps it on the screen.
function elements.place(settings, id, rect, screen_width, screen_height, target)
    local anchor = elements.anchor(settings, id);
    if not anchors.active(anchor) then return false; end
    if anchor.to == 'element' then
        if elements.circular(settings, id) then return false; end
        target = target or elements.drawn(anchor.element);
    elseif anchor.to == 'party' then target = elements.party_list;
    elseif anchor.to == 'chat' then target = elements.chat; end
    local x, y = anchors.position(anchor, rect.width, rect.height, target, screen_width, screen_height);
    if not x then return false; end
    rect.x, rect.y = x, y;
    placed[id] = frame;
    return true;
end

-- Whether id's anchor placed it in this Present; otherwise it is at its fallback spot.
function elements.anchored(id)
    return placed[id] == frame;
end

-- For a place the anchor gave that can't be used after all.
function elements.unplace(id) placed[id] = nil; end

-- Every element's anchor and When to show at their defaults, in fresh settings.
function elements.fill(settings)
    local conditions = require('core.conditions');
    for _, element in ipairs(elements.list) do
        local config = elements.config(settings, element.id);
        if config then
            if element.anchor then config[element.anchor] = anchors.make(); end
            if element.conditions then config[element.conditions] = conditions.make(); end
        end
    end
end

-- Each anchor and condition set tidied, as defaults.tidy does every other setting.
function elements.tidy(settings)
    local conditions = require('core.conditions');
    for _, element in ipairs(elements.list) do
        local config = elements.config(settings, element.id);
        if type(config) == 'table' then
            if element.anchor then config[element.anchor] = anchors.tidy(config[element.anchor], element.id, elements.anchorable); end
            if element.conditions then config[element.conditions] = conditions.tidy(config[element.conditions]); end
        end
    end
    -- An anchor that would follow itself round has none.
    for _, element in ipairs(elements.list) do
        if element.anchor and elements.circular(settings, element.id) then
            local anchor = elements.anchor(settings, element.id);
            if anchors.active(anchor) and anchor.to == 'element' then anchor.to, anchor.element = 'none', ''; end
        end
    end
end

return elements;
