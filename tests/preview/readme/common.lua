-- What the README image scenes share: the stock look, rows of invented effects, the pictures of a few actions, a
-- copy of the game's party list and a way to draw several panel sets in one frame. The scenes load it with
-- require('preview.readme.common').
local defaults, hud, imgui = require('ui.defaults'), require('ui.hud'), require('imgui');
local catalog = require('core.catalog');
local M = {};

-- Every countdown is worked out from this time, so a scene shows the same times on every frame.
M.now = 1000;
M.self_id, M.target_id = 1001, 16781313;

-- The settings a fresh install starts with, the window shut and every display off.
function M.settings()
    local s = defaults.make();
    s.window.open = false;
    for _, p in pairs(s.panels) do p.enabled = false; end;
    return s;
end

-- One effect row. spec: effect, name, kind ('buff', 'debuff' or 'other'), scope ('self', 'party' or 'enemy'),
-- left (seconds, or nil for no known time), total (seconds), and optional fields:
-- status ('server' by default, 'estimated' or 'unknown'), entity, entity_name, source, mine.
local count = 0;
function M.row(spec)
    count = count + 1;
    local left, total = spec.left, spec.total;
    local status = spec.status or (left and 'server' or 'unknown');
    local scope = spec.scope or 'self';
    local entity = spec.entity or (scope == 'enemy' and M.target_id or M.self_id);
    return { key = 'readme_' .. count, instance = count, effect = spec.effect, name = spec.name,
        kind = spec.kind or 'buff', group = catalog.get(spec.effect).group, scope = scope, entity_id = entity,
        entity_name = spec.entity_name or (scope == 'enemy' and 'Training Crab' or 'You'), status = status,
        present = scope == 'self' or scope == 'party' or nil, deadline = left and M.now + left or nil, remaining = left,
        total = left and total or nil, start = left and total and M.now - (total - left) or nil,
        source_name = spec.source, mine = spec.mine == true, observed_at = M.now - 8 };
end

-- The pictures the game's own menus draw for a few actions, as the installed client's ROM/118/114.DAT has them: a
-- spell's NQ and HQ list icons from its mgc_ record, by spell id, and an ability's element, icon and recast timer from
-- its comm record, by ability id (its resource id less 512).
local SPELLS = {
    [4] = { 'Cure IV', 6, 89 }, [24] = { 'Dia II', 6, 100 }, [46] = { 'Protect IV', 6, 120 }, [51] = { 'Shell IV', 6, 130 },
    [53] = { 'Blink', 2, 148 }, [54] = { 'Stoneskin', 3, 147 }, [55] = { 'Aquaveil', 5, 134 }, [56] = { 'Slow', 3, 141 },
    [57] = { 'Haste', 2, 143 }, [58] = { 'Paralyze', 1, 144 }, [106] = { 'Phalanx', 6, 186 }, [108] = { 'Regen', 6, 152 },
    [109] = { 'Refresh', 6, 188 }, [143] = { 'Erase', 6, 156 }, [231] = { 'Bio II', 15, 292 }, [260] = { 'Dispel', 15, 316 },
};
local ABILITIES = {
    [18] = { 'Benediction', 46, 68, 0 }, [20] = { 'Chainspell', 44, 70, 0 }, [22] = { 'Invincible', 43, 72, 0 },
    [31] = { 'Berserk', 40, 361, 1 }, [32] = { 'Warcry', 40, 363, 2 }, [35] = { 'Provoke', 41, 360, 5 },
    [48] = { 'Sentinel', 43, 407, 75 }, [52] = { 'Charm', 46, 422, 97 }, [61] = { 'Call Wyvern', 46, 464, 163 },
    [62] = { 'Third Eye', 42, 447, 133 }, [63] = { 'Meditate', 46, 449, 134 }, [72] = { 'Sic', 46, 423, 102 },
    [74] = { 'Divine Seal', 46, 381, 26 }, [78] = { 'Reward', 46, 425, 103 }, [83] = { 'Convert', 47, 391, 49 },
    [85] = { 'Call Beast', 46, 423, 104 }, [88] = { 'Assault', 46, 473, 170 }, [91] = { 'Blood Pact: Rage', 46, 477, 173 },
    [92] = { 'Rampart', 43, 409, 77 }, [136] = { 'Activate', 46, 500, 205 }, [137] = { 'Repair', 46, 501, 206 },
    [141] = { 'Maneuvers', 40, 505, 210 }, [172] = { 'Blood Pact: Ward', 46, 478, 174 }, [173] = { 'Hasso', 46, 448, 138 },
};

-- The game's resource lookups for those actions, which the party cooldowns and the pet's recasts draw their pictures
-- from. Anything else it is asked for it doesn't have.
function M.resources()
    local manager = {
        GetSpellById = function(_, id)
            local spell = SPELLS[id];
            return spell and { Name = { spell[1] }, ListIconNQ = spell[2], ListIconHQ = spell[3] } or nil;
        end,
        GetAbilityById = function(_, id)
            local ability = ABILITIES[id - 512];
            return ability and { Name = { ability[1] }, Element = ability[2], ListIconId = ability[3], RecastTimerId = ability[4] } or nil;
        end,
    };
    AshitaCore.GetResourceManager = function() return manager; end;
end

-- One recast row: kind 'spell', 'ability' or 'item', a spell id, an ability id or an item id, the seconds left and the
-- full recast. A spell or an ability takes its name and picture from the tables above; an item is named.
function M.recast(kind, id, left, total, name)
    count = count + 1;
    local row = { key = 'readme_' .. count, instance = count, kind = kind, domain = 'recast', group = kind .. '_recasts',
        scope = 'recast', entity_id = M.self_id, entity_name = 'You', status = 'server', present = true, mine = true,
        source_name = 'You', deadline = M.now + left, remaining = left, total = total, start = M.now - (total - left),
        observed_at = M.now - 8 };
    if kind == 'spell' then
        local spell = SPELLS[id];
        row.name, row.recast_id, row.effect, row.spell_id = spell[1], id, 10000 + id, id;
        row.list_icon_nq, row.list_icon_hq = spell[2], spell[3];
    elseif kind == 'ability' then
        local ability = ABILITIES[id];
        row.name, row.recast_id, row.effect, row.ability_id = ability[1], ability[4], 20000 + ability[4], 512 + id;
        row.ability_element, row.list_icon_id = ability[2], ability[3];
    else
        row.name, row.recast_id, row.effect, row.item_id = name, id, 30000 + id, id;
    end;
    return row;
end

-- A view of rows, with you as a level 75 Red Mage and the crab as your target. party: the members, as
-- { id = , name = }, the party panel names.
function M.view(rows, party)
    local context = { id = M.self_id, name = 'You', job = 5, job_name = 'RDM', valid = true, combat = true,
        target = { id = M.target_id, name = 'Training Crab', kind = 'enemy' },
        party = party or {}, entities = { [M.target_id] = { id = M.target_id, name = 'Training Crab', kind = 'enemy' } } };
    return { now = M.now, valid = true, self_known = true, context = context, rows = rows, notices = {},
        subjects = context.entities };
end

-- You as a level 75 Red Mage who has learned Dispel, so the mob buffs you can take off light up.
function M.can_dispel()
    MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 5, 75, 3, 37;
    AshitaCore:GetMemoryManager():GetPlayer().HasSpell = function(_, id) return id == 260; end;
end

-- Draws each set ({ settings, view }) with its own window names, as the galleries do.
local begin = imgui.Begin;
function M.draw(sets, callbacks)
    for index, set in ipairs(sets) do
        imgui.Begin = function(name, ...) return begin(name .. '_readme_' .. index, ...); end;
        local ok, why = pcall(hud.draw, set.view, set.settings, M.now, callbacks or { shift = false });
        imgui.Begin = begin;
        if not ok then error(why); end;
    end;
end

-- A caption, in the preview's own font.
local caption_flags;
function M.caption(id, x, y, text)
    caption_flags = caption_flags or ImGuiWindowFlags_NoDecoration + ImGuiWindowFlags_NoInputs + ImGuiWindowFlags_NoBackground
        + ImGuiWindowFlags_NoSavedSettings;
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ 400, 30 }, ImGuiCond_Always);
    imgui.Begin('##readme_caption_' .. id, true, caption_flags);
    imgui.PushStyleColor(ImGuiCol_Text, { 0.78, 0.8, 0.84, 1 });
    imgui.TextUnformatted(text);
    imgui.PopStyleColor(1);
    imgui.End();
end

-- A copy of the game's own party list, so the party list buffs have a list to sit beside. It's drawn with the client's
-- window, gauge and font art, laid out the way the game lays it out: Party at the top, then two lines for each member.
-- The name and HP sit over the HP gauge. Under them, TP is on the left and MP sits over the MP gauge. The party leader
-- has a yellow dot. The places were measured on the game's list at 1920 x 1080 and are drawn 1.25 times as big, which
-- puts the names at the client font's own 16 pixels. members: { name = , job = , hp = , max_hp = , mp = , max_mp = ,
-- tp = , leader = } in slot order, and x, y is the window's top left corner. Returns the roster the strips read and
-- where the rows are, as the game's party list would give them, and the function that draws it.
local skin, fonts, theme, assets = require('ui.client_skin'), require('ui.fonts'), require('ui.theme'), require('ui.client_assets');
local SCALE, FONT, LOOK = 1.25, 'Original FFXI', { font = 'Original FFXI' };
-- These are in the game's pixels. The window is WIDTH wide. Party's letters start TITLE down and the first name's FIRST
-- down, the names are PITCH apart and the window ends BOTTOM below the last name. Across, a place is from the window's
-- left edge. Down, it's from the top of that member's name. A gauge is { left, right, top, height } and the leader's
-- dot { left, top, size }.
local WIDTH, TITLE, FIRST, PITCH, BOTTOM = 112, 5, 13, 19.6, 25;
local NAME, HP_RIGHT, TP_LEFT, MP_RIGHT, SECOND_LINE = 7, 88, 14, 98, 11;
local HP_GAUGE, MP_GAUGE, DOT = { 30, 99, 6, 7 }, { 52, 104, 16, 4.5 }, { 2.5, 7.5, 6 };
local HP_FILL, MP_FILL, TRACK = { 1, 0.61, 0.61, 1 }, { 0.84, 0.96, 0.6, 1 }, { 0.36, 0.47, 0.57, 1 };
local WHITE, LEADER = { 1, 1, 1, 1 }, { 1, 1, 0.55, 1 };

local p1, p2, t1, t2 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
-- Part of the client's gauge art, u, v, w, h in its pixels, drawn at x, y as width by height.
local function art(list, texture, x, y, width, height, u, v, w, h, color)
    p1[1], p1[2], p2[1], p2[2] = x, y, x + width, y + height;
    t1[1], t1[2], t2[1], t2[2] = u / texture.width, v / texture.height, (u + w) / texture.width, (v + h) / texture.height;
    list:AddImage(texture.id, p1, p2, t1, t2, theme.u32(color));
end

-- A gauge as the game draws one: half a ball at each end, the bar between them and the fill over the bar. The ends
-- are tinted ends, which is white for the HP gauge's and the bar's color for the MP gauge's.
local function gauge(list, texture, x, y, width, height, fraction, fill, ends)
    local cap = height / 2;
    local body = width - 2 * cap;
    art(list, texture, x, y, cap, height, 0, 8, 4, 8, ends);
    art(list, texture, x + cap, y, body, height, 0, 0, 64, 8, TRACK);
    art(list, texture, x + width - cap, y, cap, height, 4, 8, 4, 8, ends);
    if fraction > 0 then
        art(list, texture, x + cap, y + height / 8, body * math.min(fraction, 1), height * 3 / 4, 0, 0, 64, 8, fill);
    end;
end

-- White text with the game's dark edge. x, y is where its letters start, or with right set, x is where they end. The
-- client font's letters start size / 16 right of and size / 8 below where it's drawn.
local function text(list, value, x, y, size, right)
    value = tostring(value);
    if right then x = x - (fonts.measure(FONT, value, size) or 0); end;
    fonts.paint(imgui, list, LOOK, value, x - size / 16, y - size / 8, size, theme.u32(WHITE), 1);
end

function M.party_list(members, x, y)
    local function at(value) return math.floor(value * SCALE + 0.5); end;
    local pitch = PITCH * SCALE;
    local roster = { valid = true, id = M.self_id, zone = 230, members = {}, typing = false };
    local bounds = { x = x, y = y, width = at(WIDTH), height = at(FIRST + PITCH * (#members - 1) + BOTTOM), rows = {},
        row_height = pitch, pitch = pitch, measured_by = 'rows' };
    for index, member in ipairs(members) do
        roster.members[index] = { id = 1000 + index, slot = index - 1, group = 1, name = member.name, zone = 230,
            zone_name = "Southern San d'Oria", active = true, job = member.job or 1, subjob = member.subjob or 3, available = true };
        bounds.rows[index - 1] = { x = x + 2, y = y + at(FIRST - 1 + PITCH * (index - 1)), width = bounds.width - 4,
            height = pitch, slot = index - 1 };
    end;
    local geometry = { available = true, groups = { bounds } };
    local function draw(style)
        imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
        imgui.SetNextWindowSize({ bounds.width, bounds.height }, ImGuiCond_Always);
        imgui.Begin('##readme_party_list', true, ImGuiWindowFlags_NoDecoration + ImGuiWindowFlags_NoInputs
            + ImGuiWindowFlags_NoBackground + ImGuiWindowFlags_NoSavedSettings);
        local list, texture = imgui.GetWindowDrawList(), assets.texture('original_font', 'gauge');
        skin.panel(list, bounds, style);
        text(list, 'Party', x + (bounds.width - (fonts.measure(FONT, 'Party', 12) or 0)) / 2, y + at(TITLE), 12);
        for index, member in ipairs(members) do
            local top = y + at(FIRST + PITCH * (index - 1));
            if texture then
                gauge(list, texture, x + at(HP_GAUGE[1]), top + at(HP_GAUGE[3]), at(HP_GAUGE[2] - HP_GAUGE[1]),
                    at(HP_GAUGE[4]), member.hp / member.max_hp, HP_FILL, WHITE);
                gauge(list, texture, x + at(MP_GAUGE[1]), top + at(MP_GAUGE[3]), at(MP_GAUGE[2] - MP_GAUGE[1]),
                    at(MP_GAUGE[4]), member.max_mp > 0 and member.mp / member.max_mp or 0, MP_FILL, TRACK);
                if member.leader then
                    art(list, texture, x + at(DOT[1]), top + at(DOT[2]), at(DOT[3]), at(DOT[3]), 0, 8, 8, 8, LEADER);
                end;
            end;
            text(list, member.name, x + at(NAME), top, 16);
            text(list, member.hp, x + at(HP_RIGHT), top, 16, true);
            text(list, member.tp, x + at(TP_LEFT), top + at(SECOND_LINE), 16);
            text(list, member.mp, x + at(MP_RIGHT), top + at(SECOND_LINE), 16, true);
        end;
        imgui.End();
    end;
    return roster, geometry, draw;
end

return M;
