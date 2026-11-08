-- A display cut by its limit or its room draws nothing after its last icon or bar: no '+N', no 'N more', no
-- ellipsis of its own. That holds for the timer panels, the recast panels, the party list strips (attached and
-- detached) and a shared recast's name. A strip name too long for its bar still ends in '...' inside that bar; that
-- cuts the name, not the list.
local function marker(text)
    text = tostring(text or '');
    return text:find('%+%s*%d') or text:lower():find('more', 1, true) or text:match('^%s*%.%.%.%s*$')
        or text:find('\226\128\166', 1, true);
end;

-- A shared ability timer is named for two of its actions, with nothing for the others.
local abilities = {
    [700] = { Name = { [1] = 'Alpha' }, RecastTimerId = 20, ListIconId = 30, Element = 0 },
    [701] = { Name = { [1] = 'Beta' }, RecastTimerId = 20, ListIconId = 31, Element = 0 },
    [702] = { Name = { [1] = 'Gamma' }, RecastTimerId = 20, ListIconId = 32, Element = 0 },
};
local resources = { GetAbilityById = function(_, id) return abilities[id]; end, GetSpellById = function() return nil; end,
    GetString = function() return nil; end };
local saved_resources = AshitaCore.GetResourceManager;
AshitaCore.GetResourceManager = function() return resources; end;
local shared;
for _, entry in ipairs(require('core.recasts').catalog('ability')) do if entry.recast_id == 20 then shared = entry.name; end; end;
assert(shared == 'Alpha / Beta (shared)', 'A shared recast names two actions and says nothing of the third: ' .. tostring(shared));
AshitaCore.GetResourceManager = saved_resources;

package.loaded['ui.icons'] = { status = function(effect) return tonumber(effect) and 5000 + effect or nil; end };
-- The strips ask for an icon at the size they draw it; this one has a single size.
package.loaded['ui.icons'].status_at = function(id, artwork) return package.loaded['ui.icons'].status(id, artwork), { 1, 1 }; end;
local hud, defaults = require('ui.hud'), require('ui.defaults');
local party_defaults, overlay = require('ui.party_defaults'), require('ui.native_party_hud');
local fonts = require('ui.fonts');
MOCK.screen = { 1600, 1000 };

-- Every text a frame drew, through the fonts or straight to the draw list.
local painted = {};
local plain_draw = fonts.draw;
fonts.draw = function(list, face, value, ...) painted[#painted + 1] = value; return plain_draw(list, face, value, ...); end;
local function frame_texts()
    local out = {};
    for _, value in ipairs(painted) do out[#out + 1] = value; end;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' and type(call[6]) == 'string' then out[#out + 1] = call[6]; end;
        if (call[1] == 'TextUnformatted' or call[1] == 'Text' or call[1] == 'TextWrapped') and type(call[2]) == 'string' then
            out[#out + 1] = call[2];
        end;
    end;
    return out;
end;
local function begin()
    painted, MOCK.imgui_calls = {}, {};
end;
local function images()
    local count = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddImage' then count = count + 1; end; end;
    return count;
end;
local function assert_clean(label)
    for _, text in ipairs(frame_texts()) do
        assert(not marker(text), label .. ' draws nothing after its last shown effect: ' .. tostring(text));
    end;
end;

-- Timer and recast panels cut by their row limit, in every layout.
local s = defaults.make();
s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
-- The recast tints are off at first; on, the sample recast rows draw their locks' times, which are checked too.
s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = true, true, true;
-- Six more of every sample row, so each panel lists more than its limit.
local view = hud.sample(100);
local originals = #view.rows;
for i = 1, 6 do
    for index = 1, originals do
        local extra = defaults.copy(view.rows[index]);
        extra.key, extra.instance = 'sample_extra_' .. i .. '_' .. index, 100 * i + index;
        view.rows[#view.rows + 1] = extra;
    end;
end;
for _, key in ipairs({ 'self_buffs', 'target', 'party', 'spell_recasts' }) do
    for _, mode in ipairs({ 'icons', 'bars', 'expanded', 'text' }) do
        for id, panel in pairs(s.panels) do panel.enabled = id == key; end;
        local p = s.panels[key];
        p.mode, p.max_rows, p.locked, p.show_heading = mode, 2, true, true;
        p.auto_height, p.height_limit = true, 700;
        local listed = #hud.filter_rows(view, p, key, s);
        assert(listed > 2, 'Fixture: ' .. key .. ' lists more than it shows.');
        begin();
        hud.draw(view, s, 100, {});
        assert_clean(key .. ' ' .. mode);
        if mode == 'icons' and key ~= 'spell_recasts' then
            assert(images() == 2, key .. ' icons are cut silently at the row limit: ' .. images());
        end;
        local copied = hud.copy_text(view, s, key, false, 100);
        assert(not marker(copied), 'Copy shown of ' .. key .. ' ' .. mode .. ' adds no count: ' .. copied);
    end;
end;

-- The party list strips beside the game's party list, and detached, cut by the effect limit and by their room.
local config = party_defaults.make();
config.enabled, config.locked, config.include_self = true, true, true;
config.effects.timers = true;
local roster = { valid = true, id = 1001, zone = 230, members = {} };
local subjects = {};
local names = { 'Aster', 'Bramble', 'Cinder', 'Dawn', 'Elm', 'Fable' };
for i = 1, 6 do
    local member = { id = 1000 + i, index = 1023 + i, slot = i - 1, group = 1, name = names[i], zone = 230, active = true,
        job = 5, level = 75, known = true, available = true };
    roster.members[i] = member;
    local effects = {};
    for n = 1, 8 do
        effects[n] = { effect = 30 + n, name = 'Effect ' .. n, kind = n > 5 and 'debuff' or 'buff', status = 'server',
            remaining = 60 + n, total = 120, present = true, key = 'e' .. i .. '_' .. n };
    end;
    subjects[member.id] = { known = true, complete = true, effects = effects };
end;
local game = { available = true, groups = { { x = 1300, y = 300, width = 200, height = 6 * 30, rows = {} } } };
for _, member in ipairs(roster.members) do
    game.groups[1].rows[member.slot] = { x = 1300, y = 300 + member.slot * 30, width = 200, height = 30, slot = member.slot };
end;
config.groups[1].detached_x, config.groups[1].detached_y, config.groups[1].detached_width, config.groups[1].detached_height = 30, 40, 300, 700;
local function strips(label)
    begin();
    overlay.draw(roster, subjects, config, 100, { native_geometry = game, global_style = s.style });
    assert_clean(label);
    return images();
end;
for _, detached in ipairs({ false, true }) do
    config.groups[1].native_detached = detached;
    local place = detached and 'Detached strips' or 'Attached strips';
    -- The effect limit: two of eight.
    config.effects.fit_all, config.effects.max = false, 2;
    local shown = strips(place .. ' at the effect limit');
    assert(shown == 2 * #roster.members, place .. ' show two icons a member: ' .. shown);
    -- The room: every effect is wanted, a narrow strip fits a few.
    config.effects.fit_all, config.native.width = true, 70;
    config.groups[1].detached_width = 80;
    shown = strips(place .. ' out of room');
    assert(shown > 0 and shown < 8 * #roster.members, place .. ' cut by their room: ' .. shown);
    config.native.width, config.groups[1].detached_width = 180, 300;
end;

fonts.draw = plain_draw;
return 'A cut display draws nothing past its last shown effect';
