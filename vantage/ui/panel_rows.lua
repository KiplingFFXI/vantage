-- Rows more than one display shares: finding an effect and putting it on a display's lists, where those hold ids in a
-- list (a timer panel's are sets, on ui/status_panel.lua), a list of ticks in two columns, the samples tick of a
-- display with samples of its own and the Size and place tab of a display with a box of its own.
local effect_editor = require('ui.effect_settings');
local frame = require('ui.panel_frame');
local status = require('ui.status_panel');
local page = {};
local ctx = frame.ctx;

-- Samples show only on displays that are on, which on(ctx) says. options are the tick's.
function page.samples(help, on, options)
    options = options or {};
    options.refuse = function(c, value)
        if value and not on(c) then
            c.c.note(options.off_note or 'Turn a display on first. Samples show only on displays that are on.');
            return true;
        end;
    end;
    return frame.tick('Show samples', 'preview', help, options);
end;

-- Show its heading, on a display with a box of its own. No boxes or headings takes every heading away, so a line says so in
-- its place. on(ctx), if given, says when the display shows at all, and shown_by is what shows it.
function page.heading(help, on, shown_by)
    local why = 'Why there is no heading';
    return frame.group({
        frame.tick('Show its heading', 'show_heading', help, { alias = 'Panel heading', shown_by = why,
            only = function(c) return not c.s.style.minimal; end }),
        frame.note('No boxes or headings is on, so this display has no heading. Turn it off under Boxes on the main page to use it.', {
            find = why, only = function(c) return c.s.style.minimal; end }),
    }, { only = on, shown_by = shown_by });
end;

-- The Size and place tab of a display with a box of its own (ui/element_box.lua): its scale, its width from least, its
-- height, the resize note, where it goes and the row that puts it back. it names the display in the help and search
-- words, and fits says what Fit follows.
function page.box_place(least, it, fits)
    local place_rows = {
        frame.scale_line,
        frame.number('Width', 'width', least, 1400, 'The ' .. it .. '\'s width.', { alias = it:sub(1, 1):upper() .. it:sub(2) .. ' width' }),
        frame.number('Height', 'height', 0, 16000, 'Fit follows ' .. fits .. '. Any other value is a fixed height, at least 60 pixels.', { edge = 'y', special = { [0] = 'Fit' }, alias = 'Tallest ' .. it .. ' height Automatic',
            write = function(c, value) c.p.height = value == 0 and 0 or math.max(60, value); end }),
        frame.resize_note,
    };
    for _, item in ipairs(frame.place_rows()) do place_rows[#place_rows + 1] = item; end;
    place_rows[#place_rows + 1] = frame.put_back;
    return place_rows;
end;

-- A caption, then ticks in two columns, the first half down the first. options are the row's.
function page.columns(id, text, help, list, options)
    local half, first, second = math.ceil(#list / 2), {}, {};
    for index, item in ipairs(list) do
        if index <= half then first[#first + 1] = item; else second[#second + 1] = item; end;
    end;
    options = options or {};
    options.rows = list;
    return frame.custom(text, help, function(imgui, c, item)
        status.caption(imgui, c, item);
        if not imgui.BeginTable(id, 2, ImGuiTableFlags_SizingStretchSame or 0) then return; end;
        imgui.TableNextColumn();
        frame.draw_rows(imgui, c, first);
        imgui.TableNextColumn();
        frame.draw_rows(imgui, c, second);
        imgui.EndTable();
    end, options);
end;

-- The rows that find an effect and put it on a display's lists. spec says:
-- of(ctx): the table with the lists. sorted: keeps them in id order, as the overhead icons read them. live: for a table
-- that changes with no change of settings, so the lists are said again whenever of(ctx) gives another one.
-- show and hide: what those rows are called; pin, order and reset: the same, for a display that has them. Reset this tab
-- (ui/panel_frame.lua) empties the lists.
-- Each name's more words go in alias, by the same key, and alias.find has those of Choose an effect. listed: what the
-- lists under it are called, by the list.
function page.effect_lists(spec)
    local state = {};
    local alias = spec.alias or {};
    local FIND = 'Choose an effect';
    local function finder() return state; end;
    local function picked() return state.effect ~= nil; end;
    local rows = {};
    local function add(item) rows[#rows + 1] = item; end;

    local function tick(text, list, help, old)
        return frame.tick(text, nil, help, { only = picked, shown_by = FIND, alias = old,
            read = function(c) return effect_editor.contains(spec.of(c)[list], state.effect); end,
            write = function(c, on)
                local values = spec.of(c)[list];
                effect_editor.membership(values, state.effect, on);
                if spec.sorted then table.sort(values); end;
            end });
    end;

    local function list_row(text, help, list, options)
        options = options or {};
        options.live, options.source = spec.live, function(c) return spec.of(c)[list]; end;
        return status.list_line(text, help, function(c) return #spec.of(c)[list] > 0; end,
            function(c) return status.entries_of(c, spec.of(c)[list]); end,
            function(_, entry) effect_editor.membership(spec.of(ctx)[list], entry.id, false); end, options);
    end;

    add(status.choose_row('Effect', finder, { find = FIND, alias = alias.find,
        help = 'What the ticks under it change, on this display only. Type part of its name in the box at the top of the list to find it.' }));
    local ticks = { tick(spec.show, 'include', 'If any effects are listed, this display shows only those. An empty list shows all.', alias.show),
        tick(spec.hide, 'exclude', 'Hidden wins over Show only. Tracking and alerts go on.', alias.hide) };
    if spec.pin then ticks[3] = tick(spec.pin, 'pinned', 'Pinned effects come first.', alias.pin); end;
    add(frame.line(nil, nil, ticks));
    if spec.order then
        add(frame.button(spec.order, 'Adds it to My order, on the Show tab, and sets Sort to My order.', function(c)
            local effects, id = spec.of(ctx), state.effect;
            local listed = effect_editor.contains(effects.order, id);
            if listed and effects.sort == 'fixed' then return; end;
            c.changed(function()
                if not listed then effects.order[#effects.order + 1] = id; end;
                effects.sort = 'fixed';
            end, true, spec.order);
        end, { only = picked, shown_by = FIND }));
    end;
    if spec.reset then
        add(frame.button(spec.reset, 'Takes it off every list here.', function(c)
            local effects, id = spec.of(ctx), state.effect;
            c.changed(function()
                for _, list in ipairs({ 'include', 'exclude', 'pinned' }) do effect_editor.membership(effects[list], id, false); end;
            end, true, spec.reset);
        end, { only = picked, shown_by = FIND, alias = alias.reset }));
    end;
    add(list_row(spec.listed.include, 'While this list has effects, this display shows only those.', 'include', { tag = '_list', find = spec.listed.include .. ' list' }));
    add(list_row(spec.listed.exclude, 'Hidden wins over Show only. Tracking and alerts go on.', 'exclude', { tag = '_list', find = spec.listed.exclude .. ' list' }));
    if spec.listed.pinned then add(list_row(spec.listed.pinned, 'These come first.', 'pinned')); end;
    return rows;
end;

-- My order, under Sort on Show, for a display whose lists are in of(ctx), while shown(ctx) says the display shows effects:
-- the effects on it in their places, each with Up, Down and Remove. Add to My order on Filters (effect_lists' order)
-- fills it.
function page.order_line(of, shown)
    return status.list_line('My order', 'Used while Sort is My order. Effects not listed here follow these, by name.',
        function(c) return shown(c) and #of(c).order > 0; end, function(c) return status.entries_of(c, of(c).order); end,
        function(_, _, index) table.remove(of(ctx).order, index); end, { extra = status.order_moves(of), room = status.order_room, of = of, resets = { 'order' } });
end;

return page;
