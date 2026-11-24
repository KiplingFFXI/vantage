-- The ready pulse's editor, as one display on the panel frame (core/ready_pulse.lua): when it plays and how it looks, its
-- spot of its own and its own conditions. The Recasts display links here.
local conditions_ui = require('ui.condition_settings');
local defaults = require('ui.defaults');
local frame = require('ui.panel_frame');
local status = require('ui.status_panel');
local ready_pulse = require('core.ready_pulse');
local page = {};
local ctx = frame.ctx;
local pulse_defaults = ready_pulse.make();

local function on(c) return c.p.enabled == true; end;
-- A spot of its own is the only place it can be moved to.
local function own_spot(c) return on(c) and c.p.spot == 'screen'; end;

-- Never pulse for.

local function ignore_recast(id)
    local c, s = ctx.c, ctx.s;
    if id ~= 0 then c.changed(function() s.ready_pulse.ignore[id] = true; end, true, 'Never pulse for ' .. c.effect_name(id, 'recast')); end;
end;

local function ignored_list(c)
    local out = {};
    for key in pairs(c.s.ready_pulse.ignore) do
        local id = tonumber(key) or key;
        out[#out + 1] = { id = id, key = key, line = status.plain_name(c.c, id, 'recast'), scope = 'pulse_ignore_' .. tostring(id) };
    end;
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id); end);
    return out;
end;

local ignored = { say = ignored_list, memo = {} };

local function draw_ignored(imgui, c, item)
    c.effect_picker(item.text, 0, ignore_recast, false, 'recast', 'Choose a recast');
    frame.lit(c, item);
    local list = frame.said(ignored);
    local kept = ctx.s.ready_pulse.ignore;
    for index = 1, #list do
        local entry = list[index];
        imgui.PushID(entry.scope);
        imgui.TextUnformatted(entry.line);
        imgui.SameLine();
        if imgui.Button('Pulse again') then c.changed(function() kept[entry.key] = nil; end, true, 'Pulse again for ' .. entry.line); end;
        c.tip('Take this recast off the list, so it pulses again.');
        imgui.PopID();
    end;
end;

-- Show.

local show_rows = {
    frame.problem(function(c) return defaults.pulse_has_no_row(c.s); end, 'No recast panel is on, so the pulse has no row to play on.', 'Use a spot of its own',
        'Sets Pulse spot to A spot of its own, which plays whether or not a panel shows the recast.', 'Pulse when a long recast is ready', function(s) s.ready_pulse.spot = 'screen'; end),
    frame.group({
        frame.number('Only recasts of at least', 'min_seconds', 0, 7200, 'Seconds. A recast is as long as its full cooldown when Vantage saw it start, else the most it saw left.', { top = 1200, alias = 'Shortest recast that pulses', format = '%.0f seconds' }),
        frame.number('Start early', 'early', 0, 600, 'Seconds before ready. Zero pulses when it is ready.', { alias = 'Pulse early by', format = '%.0f seconds' }),
        frame.number('Pulse for', 'length', 0.2, 5, 'How long it plays.', { whole = false, alias = 'Pulse length', format = '%.1f seconds' }),
        frame.number('Pulse size', 'size', 16, 256, 'How big the icon grows, in pixels at Size 1x, and 512 at most on screen. On a row it never goes under the row\'s own icon.'),
        frame.color('Pulse color', 'color', nil, { fallback = function() return pulse_defaults.color; end }),
        frame.pick('Pulse spot', 'spot', ready_pulse.spots, { row = 'On its row', screen = 'A spot of its own' },
            'On its row pulses where a recast panel shows that recast. A spot of its own pulses there, shown or not, and is set on Size and place.'),
        frame.button('Show a test pulse', 'Plays one pulse now with a sample icon: on a recast row a panel shows, or at the spot.', function(c) c.call('test_pulse'); end),
        frame.custom('Never pulse for', 'Recasts that never pulse.', draw_ignored, { alias = 'ignore list recasts that never pulse Pulse again', resets = { 'ignore' } }),
    }, { only = on, shown_by = 'Pulse when a long recast is ready' }),
};

-- Size and place: its spot of its own.

local place_rows = { frame.scale_line };
for _, item in ipairs(frame.place_rows('pulse')) do place_rows[#place_rows + 1] = item; end;
place_rows[#place_rows + 1] = frame.put_back;

frame.register({
    id = 'pulse', name = 'Ready pulse', fold_page = 'Ready pulse', reset_scope = 'ready_pulse',
    tabs = { show = show_rows, place = place_rows, when = conditions_ui.rows },
    tab_on = { place = own_spot, when = on }, lock_on = own_spot,
    unlocked = function() return 'Unlocked: hold Shift and drag the spot to move it.'; end,
    header = { frame.line(nil, nil, {
        frame.tick('On', 'enabled', 'A short pulse when a long recast is ready. It only draws: nothing is used or sent.', {
            tag = '_display', find = 'Pulse when a long recast is ready', alias = 'Show this display Ready pulse' }),
        frame.tick('Locked', nil, 'Locked, Shift and drag don\'t move its spot. Arrange on screen and the numbers on Size and place still do.', {
            find = 'Lock pulse spot', alias = 'Lock position lock unlock move shift drag protect', only = own_spot, shown_by = 'Pulse spot',
            read = function() return ctx.locked; end, write = function(c, value) c.p.locked = value; end }),
    }) },
});

return page;
