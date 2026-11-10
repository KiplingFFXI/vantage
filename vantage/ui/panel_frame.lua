-- The editor every display shares: a header with its name, On, samples and Locked, the tabs it has rows for, and Reset this
-- display at the foot of each. A display gives rows, made once at load, and they draw from one table, ctx, filled for
-- the display that is open, so a frame makes no closures and no value boxes; a click makes what it needs. Which display
-- and tab are open lasts the session, so nothing here is saved.
local anchors = require('core.anchors');
local bit = require('bit');
local controls = require('ui.controls');
local defaults = require('ui.defaults');
local elements = require('ui.elements');
local skin = require('ui.client_skin');
local frame = {};

frame.tabs = { { key = 'show', label = 'Show' }, { key = 'place', label = 'Size and place' }, { key = 'look', label = 'Look' },
    { key = 'filters', label = 'Filters' }, { key = 'when', label = 'When to show' } };
local tab_names = {};
for _, tab in ipairs(frame.tabs) do tab.button, tab_names[tab.key] = tab.label .. '##frame_tab', tab.label; end;

-- What every row draws with. s is the settings, p the table of the one being edited, id its id in ui/elements.lua and
-- element its entry there.
local ctx = {};
frame.ctx = ctx;

local displays, by_id, owner = {}, {}, {};
local open_id, open_tabs = nil, {};
local loaded = false;
-- Goes up when a display or tab opens, as what the search finds can change with them.
local moves = 0;

if VANTAGE_TEST_MODE then frame._displays = displays; end;

-- The displays come in on first use, as this file is what they build on.
local function load_displays()
    if loaded then return; end;
    loaded = true;
    for _, name in ipairs({ 'status_panel', 'recast_panel', 'party_settings', 'overhead_settings', 'cooldown_settings', 'roll_settings', 'pet_settings', 'alert_panel', 'filter_settings' }) do
        require('ui.' .. name);
    end;
end;

-- Rows. Every kind takes these in options:
-- only(ctx): draw it only while this holds. shown_by: the label, or labels, that show it, which find it while it is hidden.
-- locks: true greys it while the display is locked, or a function says when it is greyed.
-- of(ctx): the table its key is in, if it isn't the display's own. key_of(ctx): its key, if that changes.
-- read(ctx) and write(ctx, value): in place of a key. find: its name in the search and its Undo step's, if it isn't its label.
-- alias: more words that find it. tag: tells apart two rows with the same label on one tab.
-- transient: what it writes isn't a setting, so it makes no Undo step. refuse(ctx, value): true leaves the value as it is.
local function row(kind, text, help, options)
    local made = options or {};
    made.kind, made.text, made.help = kind, text, help;
    made.find = made.find or text;
    made.label = text .. '##frame' .. (made.tag or '');
    made.bare = '##frame_' .. text .. (made.tag or '');
    made.words = made.find .. ' ' .. (made.find ~= text and text .. ' ' or '') .. (help or '') .. ' ' .. (made.alias or '');
    return made;
end;

-- What a row's choices are called finds it too.
local function choice_words(made)
    local names = made.names;
    for _, value in ipairs(names and made.choices or {}) do
        if names[value] then made.words = made.words .. ' ' .. names[value]; end;
    end;
end;

function frame.tick(text, key, help, options)
    local made = row('tick', text, help, options);
    made.key = key;
    return made;
end;

-- choices lists the values and names says each. choices_of(ctx) and names_of(ctx) are those, if they change with the display.
-- leaves names a button drawn beside it, and it stops short to leave that room.
function frame.pick(text, key, choices, names, help, options)
    local made = row('pick', text, help, options);
    made.key, made.choices, made.names = key, choices, names;
    choice_words(made);
    return made;
end;

function frame.radio(text, key, choices, names, help, options)
    local made = row('radio', text, help, options);
    made.key, made.choices, made.names, made.labels = key, choices, names, {};
    for _, value in ipairs(choices) do made.labels[value] = names[value] .. made.bare .. '_' .. value; end;
    choice_words(made);
    return made;
end;

-- whole false keeps fractions. edge 'x' or 'y' ends the slider at the screen's edge; Ctrl-click typing still reaches high.
-- special says what a value stands for and shown(ctx, value) says it where that changes. low_of(ctx) and high_of(ctx) are
-- the least and most values, if those change. width puts it in a line with no label of its own. top ends the slider short
-- of high.
function frame.number(text, key, low, high, help, options)
    local made = row('number', text, help, options);
    made.key, made.low, made.high = key, low, high;
    made.format = made.format or made.whole == false and '%.2f' or '%.0f';
    made.tip = (help or '') .. ' Ctrl-click the slider to type a value.';
    return made;
end;

function frame.text(text, key, help, options)
    local made = row('text', text, help, options);
    made.key = key;
    made.length = (made.length or 80) + 1;
    return made;
end;

-- fallback(ctx) is the color shown while there is none saved. back marks one that can go back to the shared color.
function frame.color(text, key, help, options)
    local made = row('color', text, help, options);
    made.key = key;
    if made.back then
        made.back_text = 'Use the shared color###frame_back_' .. text .. (made.tag or '');
    end;
    return made;
end;

-- action(c) runs on a click.
function frame.button(text, help, action, options)
    local made = row('button', text, help, options);
    made.action, made.shown = action, text .. '###' .. made.label;
    return made;
end;

-- A line of words: text, or say(ctx) worked out when the settings change, or each frame with live set. find, in options,
-- makes it a search target, and tone is the look's color for it in place of the notes' one.
function frame.note(text, options)
    local made = options or {};
    made.kind = 'note';
    if type(text) == 'function' then made.say, made.memo = text, {}; else made.line = text; end;
    if made.find then made.words = made.find .. ' ' .. (made.alias or ''); end;
    return made;
end;

function frame.heading(text, help, options)
    return row('heading', text, help, options);
end;

-- draw(imgui, c, row) draws it and calls frame.lit after its first item. rows, in options, are rows it draws itself.
function frame.custom(text, help, draw, options)
    local made = row('custom', text, help, options);
    made.draw = draw;
    return made;
end;

-- A fold keeps its open state in the settings as <display's fold page>/<key>.
function frame.fold(text, help, rows, options)
    local made = row('fold', text, help, options);
    made.rows = rows;
    made.key = made.key or text;
    made.label = made.key == text and text or text .. '##' .. made.key;
    return made;
end;

-- A caption and rows on one line, wrapping as they run out of room. every starts a new line after that many; below puts
-- the rows under the caption.
function frame.line(text, help, rows, options)
    local made = text and row('line', text, help, options) or options or {};
    made.kind, made.rows = 'line', rows;
    return made;
end;

-- Rows that come and go together.
function frame.group(rows, options)
    local made = options or {};
    made.kind, made.rows = 'group', rows;
    return made;
end;

-- A line saying what's wrong, over the button that puts it right, in one Undo step. only(ctx) says when, fix(settings) puts
-- it right and place is the row that finds the button while it's hidden.
function frame.problem(only, line, text, help, place, fix)
    return frame.group({
        frame.note(line, { tone = 'problem_messages' }),
        frame.button(text, help, function(c)
            local s = ctx.s;
            c.changed(function() fix(s); end, true, text);
        end, { shown_by = place }),
    }, { only = only });
end;

local function shows(item)
    return not item.only or item.only(ctx);
end;

local function grey(imgui, on)
    if on and imgui.BeginDisabled then imgui.BeginDisabled(true); end;
end;

local function ungrey(imgui, on)
    if on and imgui.EndDisabled then imgui.EndDisabled(); end;
end;

local function greyed(item)
    local locks = item.locks;
    if locks == true then return ctx.locked; end;
    return locks and locks(ctx);
end;

local function tip(c, text)
    c.tip(text, ImGuiHoveredFlags_AllowWhenDisabled);
end;

-- Whether a row and the rows it sits in all show now.
local function visible(entry)
    while entry do
        if not shows(entry.row) then return false; end;
        entry = entry.parent;
    end;
    return true;
end;

local reset_row;
-- The words of each row hidden now, on the row that shows it, for the display ctx is filled for.
local function hidden_words(display)
    local memo = display.hidden;
    if memo.owner == ctx.s and memo.id == ctx.id and ctx.revision ~= nil and memo.revision == ctx.revision and memo.moves == moves then return memo.words; end;
    local words = {};
    local function pass_on(entry, text, depth)
        local labels = entry.shown_by;
        for _, label in ipairs(type(labels) == 'table' and labels or { labels }) do
            local target = display.named[label];
            if target and visible(target) then
                local list = words[target.row] or {};
                words[target.row], list[#list + 1] = list, text;
            elseif target and target.shown_by and depth < 4 then pass_on(target, text, depth + 1); end;
        end;
    end;
    for _, entry in ipairs(display.entries) do
        if entry.shown_by and not visible(entry) then pass_on(entry, entry.row.words, 0); end;
    end;
    if display.reset_alias then words[reset_row] = { reset_row.words .. ' ' .. display.reset_alias }; end;
    memo.owner, memo.id, memo.revision, memo.moves, memo.words = ctx.s, ctx.id, ctx.revision, moves, words;
    return words;
end;

-- The words a query goes by for a row: those of a hidden row it shows, one at a time, if one is named, else its own.
local function words_for(query, matches, item, hidden)
    for index = 1, hidden and #hidden or 0 do
        if matches(query, hidden[index]) then return hidden[index]; end;
    end;
    return item.words;
end;

-- The search's light on the item just drawn. It runs only while the box has text.
local function lit(c, item)
    if c.search[1] == '' or not item.words then return; end;
    c.light(words_for(c.search[1], c.matches, item, ctx.display and hidden_words(ctx.display)[item]), item.words);
end;
frame.lit = lit;

local function caption(imgui, text)
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end;
    imgui.TextUnformatted(text);
end;

local function shaded(imgui, c, text, tone)
    local color = c.look and c.look[tone or 'notes'];
    if color then imgui.PushStyleColor(ImGuiCol_Text, color); end;
    imgui.TextWrapped(text);
    if color then imgui.PopStyleColor(); end;
end;
frame.shaded = shaded;

-- What a line of words says, for ctx. A line from settings is worked out when they change.
local function said(item)
    if not item.say then return item.line; end;
    if item.live then return item.say(ctx); end;
    local memo = item.memo;
    if memo.owner ~= ctx.s or memo.id ~= ctx.id or ctx.revision == nil or memo.revision ~= ctx.revision then
        memo.owner, memo.id, memo.revision, memo.value = ctx.s, ctx.id, ctx.revision, item.say(ctx);
    end;
    return memo.value;
end;
frame.said = said;

local function table_of(item)
    if item.of then return item.of(ctx); end;
    return ctx.p;
end;

local function key_of(item)
    if item.key_of then return item.key_of(ctx); end;
    return item.key;
end;

local function value_of(item, holder, key)
    if item.read then return item.read(ctx); end;
    return holder[key];
end;

local function write(c, item, holder, key, value, save)
    if item.refuse and item.refuse(ctx, value) then return; end;
    local function apply()
        if item.write then item.write(ctx, value); else holder[key] = value; end;
    end;
    -- A pick that isn't saved changes what the rows show, so the search goes again.
    if item.transient then apply(); moves = moves + 1; else c.changed(apply, save, item.find); end;
end;

local drawers = {};
local flag, number_box, text_box, color_box = { false }, { 0 }, { '' }, { 0, 0, 0, 1 };
local color_flags;

-- A tick. A label too long for the page wraps beside its box.
function drawers.tick(imgui, c, item)
    local holder, key = table_of(item), key_of(item);
    flag[1] = value_of(item, holder, key) == true;
    local clicked;
    if imgui.CalcTextSize(item.text) + imgui.GetFrameHeight() + 10 > imgui.GetContentRegionAvail() then
        clicked = controls.checkbox(imgui, c.look, item.bare, flag);
        imgui.SameLine();
        imgui.TextWrapped(item.text);
    else clicked = controls.checkbox(imgui, c.look, item.label, flag); end;
    lit(c, item);
    tip(c, item.help);
    if clicked then write(c, item, holder, key, flag[1], true); end;
end;

function drawers.pick(imgui, c, item)
    local holder, key = table_of(item), key_of(item);
    local current, names = value_of(item, holder, key), item.names_of and item.names_of(ctx) or item.names;
    controls.label(imgui, item.text);
    tip(c, item.help);
    imgui.SetNextItemWidth(item.leaves and -(imgui.CalcTextSize(item.leaves) + 28) or -1);
    skin.prepare_menu(imgui, c.look);
    local chosen;
    if imgui.BeginCombo(item.bare, names[current] or tostring(current or '')) then
        skin.menu(imgui, c.look, 'popup');
        local choices = item.choices_of and item.choices_of(ctx) or item.choices;
        for index = 1, #choices do
            local value = choices[index];
            if imgui.Selectable(names[value] .. '##' .. tostring(value), current == value) then chosen = value; end;
        end;
        imgui.EndCombo();
    end;
    lit(c, item);
    tip(c, item.help);
    if chosen ~= nil and chosen ~= current then write(c, item, holder, key, chosen, true); end;
end;

function drawers.radio(imgui, c, item)
    local holder, key = table_of(item), key_of(item);
    local current = value_of(item, holder, key);
    caption(imgui, item.text);
    lit(c, item);
    tip(c, item.help);
    local used, available = imgui.CalcTextSize(item.text) + 8, imgui.GetContentRegionAvail();
    local chosen;
    for index = 1, #item.choices do
        local value = item.choices[index];
        local width = imgui.CalcTextSize(item.names[value]) + imgui.GetFrameHeight() + 12;
        if used + width <= available then imgui.SameLine(); else used = 0; end;
        if controls.radio(imgui, c.look, item.labels[value], current == value) and current ~= value then chosen = value; end;
        tip(c, item.help);
        used = used + width;
    end;
    if chosen ~= nil then write(c, item, holder, key, chosen, true); end;
end;

function drawers.number(imgui, c, item)
    local holder, key = table_of(item), key_of(item);
    local low, high = item.low_of and item.low_of(ctx) or item.low, item.high_of and item.high_of(ctx) or item.high;
    local current = tonumber(value_of(item, holder, key)) or low;
    if item.width then imgui.SetNextItemWidth(item.width);
    else
        controls.label(imgui, item.text);
        tip(c, item.tip);
        imgui.SetNextItemWidth(-1);
    end;
    -- A place row stops where the display still fits, and shows that, as it can't be drawn past it. What's typed stays.
    local room = item.room_of and item.room_of(ctx) or 0;
    local top = item.edge and math.max(low, math.min(high, c.screen_edge(item.edge) - room)) or item.top or high;
    local format = item.shown and item.shown(ctx, current) or item.special and item.special[current] or item.format;
    number_box[1] = item.room_of and math.min(current, top) or current;
    local moved = imgui.SliderFloat(item.bare, number_box, low, top, format);
    lit(c, item);
    tip(c, item.tip);
    if moved then
        local chosen = tonumber(number_box[1]);
        if chosen and chosen == chosen and math.abs(chosen) ~= math.huge then
            chosen = math.max(low, math.min(high, chosen));
            write(c, item, holder, key, item.whole == false and chosen or math.floor(chosen + 0.5), false);
        end;
    end;
end;

function drawers.text(imgui, c, item)
    local holder, key = table_of(item), key_of(item);
    controls.label(imgui, item.text);
    tip(c, item.help);
    text_box[1] = value_of(item, holder, key) or '';
    imgui.SetNextItemWidth(-1);
    local typed = imgui.InputText(item.bare, text_box, item.length);
    lit(c, item);
    tip(c, item.help);
    if typed then
        local value = text_box[1]:gsub('[%c]', ''):gsub('##', '');
        write(c, item, holder, key, value, false);
    end;
end;

function drawers.color(imgui, c, item)
    local holder, key = table_of(item), key_of(item);
    local source = holder[key] or item.fallback(ctx);
    for index = 1, 4 do color_box[index] = source[index]; end;
    color_flags = color_flags or bit.bor(ImGuiColorEditFlags_NoInputs or 0, ImGuiColorEditFlags_AlphaBar or 0);
    local start = imgui.GetCursorPosX();
    local moved = imgui.ColorEdit4(item.label, color_box, color_flags);
    lit(c, item);
    tip(c, item.help);
    if moved then
        local value = defaults.copy(source);
        for index = 1, 4 do value[index] = color_box[index]; end;
        write(c, item, holder, key, value, false);
    end;
    if item.back then
        -- Every word after a swatch lines up past the longest color name.
        imgui.SameLine(start + imgui.GetFrameHeight() + 12 * imgui.GetFontSize());
        if holder[key] == nil then
            caption(imgui, 'Shared');
        elseif imgui.Button(item.back_text) then
            c.changed(function() holder[key] = nil; end, true, 'Use the shared color: ' .. item.find);
        end;
    end;
end;

-- A color by itself, for a row a display draws. Returns a new color when it is changed.
function frame.swatch(imgui, label, source)
    for index = 1, 4 do color_box[index] = source[index]; end;
    color_flags = color_flags or bit.bor(ImGuiColorEditFlags_NoInputs or 0, ImGuiColorEditFlags_AlphaBar or 0);
    if not imgui.ColorEdit4(label, color_box, color_flags) then return nil; end;
    local value = defaults.copy(source);
    for index = 1, 4 do value[index] = color_box[index]; end;
    return value;
end;

-- A button with no room left on its line starts the next one, and a caption wider than the page wraps. The wrapped
-- caption is kept until the room, the caption's width, the font size or the settings change.
function drawers.button(imgui, c, item)
    local size = imgui.CalcTextSize(item.text) + 20;
    if size > imgui.GetContentRegionAvail() and imgui.GetCursorPosX() > imgui.GetFontSize() then imgui.NewLine(); end;
    local available = imgui.GetContentRegionAvail();
    local label = item.shown;
    if size > available then
        local kept, font_size = item.wrapped, imgui.GetFontSize();
        if not kept or kept.available ~= available or kept.size ~= size or kept.font_size ~= font_size or kept.revision ~= ctx.revision then
            -- The same button ID whether or not its caption wraps.
            kept = { available = available, size = size, font_size = font_size, revision = ctx.revision,
                label = table.concat(require('ui.text_wrap').lines(item.text, math.max(1, available - 20), imgui.CalcTextSize), '\n') .. '###' .. item.label };
            item.wrapped = kept;
        end;
        label = kept.label;
    end;
    local clicked = imgui.Button(label);
    lit(c, item);
    tip(c, item.help);
    if clicked then item.action(c); end;
end;

function drawers.note(imgui, c, item)
    local text = said(item);
    if text then
        shaded(imgui, c, text, item.tone);
        lit(c, item);
    end;
end;

function drawers.heading(imgui, c, item)
    c.heading(item.text, item.help, true);
    lit(c, item);
end;

function drawers.custom(imgui, c, item)
    item.draw(imgui, c, item);
end;

local function draw_rows(imgui, c, rows)
    for index = 1, #rows do
        local item = rows[index];
        if shows(item) then
            local off = greyed(item);
            grey(imgui, off);
            if item.beside then imgui.SameLine(); end;
            drawers[item.kind](imgui, c, item);
            ungrey(imgui, off);
        end;
    end;
end;
frame.draw_rows = draw_rows;

function drawers.group(imgui, c, item)
    draw_rows(imgui, c, item.rows);
end;

function drawers.fold(imgui, c, item)
    local open = c.section(item.label, item.help, item.opened, ctx.display.fold_page);
    lit(c, item);
    if open then draw_rows(imgui, c, item.rows); end;
end;

local function width_of(imgui, item)
    if item.width then return item.width + 8; end;
    if item.kind == 'tick' or item.kind == 'color' then return imgui.CalcTextSize(item.text) + imgui.GetFrameHeight() + 20; end;
    return imgui.CalcTextSize(item.text or '') + 28;
end;

-- How much of its line the header's name takes, for the rows that start beside it.
local header_used = 0;

function drawers.line(imgui, c, item)
    local used, available = header_used, imgui.GetContentRegionAvail();
    header_used = 0;
    if item.text then
        caption(imgui, item.text);
        lit(c, item);
        tip(c, item.help);
        used = not item.below and imgui.CalcTextSize(item.text) + 8 or 0;
    end;
    local rows, count = item.rows, 0;
    for index = 1, #rows do
        local inner = rows[index];
        if shows(inner) then
            local width = width_of(imgui, inner);
            local starts = item.every and count > 0 and count % item.every == 0;
            if (used > 0 or count > 0) and used + width <= available and not starts then imgui.SameLine(); else used = 0; end;
            local off = greyed(inner);
            grey(imgui, off);
            drawers[inner.kind](imgui, c, inner);
            ungrey(imgui, off);
            used, count = used + width, count + 1;
        end;
    end;
end;

-- The rows every display's header has: its lock, by whichever table holds it.
local function lock_of() return elements.lock_holder(ctx.s, ctx.id); end;
frame.lock_row = frame.tick('Locked', nil, 'Locked, it stays where it is, even while Shift is held. Unlock it, then hold Shift and drag it to move it, or drag an edge to resize it.', {
    alias = 'Lock position and size lock unlock move resize shift left drag edges corners protect',
    read = function() return ctx.locked; end,
    write = function(_, on) lock_of()[ctx.element.lock] = on; end,
});

local locked_line = frame.note('Unlock it to move or resize it.', { only = function() return ctx.locked; end });
frame.locked_line = locked_line;

local reset_ids = {};
reset_row = frame.button('Reset this display', 'Puts this display back as it started. Undo brings your settings back.', function(c)
    local id, scope, name = ctx.id, ctx.display.reset_scope or ctx.id, ctx.display.name_of and ctx.display.name_of(ctx) or ctx.display.name;
    local extra = ctx.display.reset_note and ctx.display.reset_note(ctx) or '';
    c.ask(reset_ids[id], 'Reset ' .. name .. '? It goes back to how it started' .. (ctx.element.lock and ': locked, in its first spot.' or '.') .. extra, function() c.call('reset', scope); end,
        'Reset', 'Reset it. Undo brings your settings back.', 'Leave it as it is.');
end, { alias = 'Reset selected panel Reset this page Restore defaults' });

-- Every row of a display with a name, or with rows, for the search, and the rows it can open by name.
local function list_entries(display)
    local entries, named = {}, {};
    local function walk(rows, tab, parent, fold)
        for _, item in ipairs(rows) do
            local entry = { row = item, tab = tab, parent = parent, fold = fold, shown_by = item.shown_by or parent and parent.shown_by };
            if item.find then
                entries[#entries + 1] = entry;
                named[item.find] = named[item.find] or entry;
                named[item.text or item.find] = named[item.text or item.find] or entry;
            end;
            if item.rows then walk(item.rows, tab, entry, item.kind == 'fold' and item or fold); end;
        end;
    end;
    for _, tab in ipairs(frame.tabs) do
        if display.tabs[tab.key] then walk(display.tabs[tab.key], tab.key); end;
    end;
    walk(display.header, 'show');
    if display.under then walk(display.under, 'show'); end;
    if not display.plain then walk({ reset_row }, 'show'); end;
    display.entries, display.named, display.hidden = entries, named, {};
end;

-- A display: id, name, fold_page (what starts its folds' saved names), tabs (rows by tab key, and a tab it has no rows for
-- doesn't show), tab_on (by tab key, whether that tab's rows can do anything now), lock_on(ctx), when its lock counts only at
-- times, header (the rows above the tabs), under (rows under the Unlocked line), panels (more ids it edits),
-- fill(ctx) to set ctx.id, pick(id) to choose one of its panels, title_of(ctx), when its title changes, unlocked(ctx), when
-- its Unlocked line isn't the usual one, reset_scope, when Reset this display doesn't go by its id, reset_note(ctx), more
-- words for its question, and reset_alias, more words that find it. plain, for what isn't a display on the screen, leaves
-- out the tabs and the Reset: it has only rows on show.
function frame.register(display)
    displays[#displays + 1], by_id[display.id], owner[display.id] = display, display, display.id;
    for _, id in ipairs(display.panels or {}) do owner[id] = display.id; end;
    list_entries(display);
end;

local function current()
    load_displays();
    return by_id[open_id] or displays[1];
end;

local function fill(display, settings, view, callbacks, c)
    ctx.s, ctx.view, ctx.callbacks, ctx.c, ctx.display, ctx.id = settings, view, callbacks, c, display, display.id;
    ctx.revision = callbacks and callbacks.settings_revision and callbacks.settings_revision();
    if display.fill then display.fill(ctx); end;
    ctx.p, ctx.element = elements.config(settings, ctx.id), elements.by_id[ctx.id];
    ctx.locked = elements.locked(settings, ctx.id);
    reset_ids[ctx.id] = reset_ids[ctx.id] or 'frame_reset_' .. ctx.id;
end;

local function tab_here(display, key)
    local on = display.tab_on and display.tab_on[key];
    return display.tabs[key] and (not on or ctx.display ~= display or on(ctx));
end;

local function tab_of(display)
    local key = open_tabs[display.id];
    if not key or not tab_here(display, key) then return 'show'; end;
    return key;
end;

local function draw_tabs(imgui, c, display)
    local chosen, available, used = tab_of(display), imgui.GetContentRegionAvail(), 0;
    for _, tab in ipairs(frame.tabs) do
        if tab_here(display, tab.key) then
            local width = imgui.CalcTextSize(tab.label) + 24;
            if used > 0 and used + width < available then imgui.SameLine(); else used = 0; end;
            local selected = chosen == tab.key;
            if selected then imgui.PushStyleColor(ImGuiCol_Button, c.look.buttons_pressed); end;
            local clicked = imgui.Button(tab.button);
            if selected then imgui.PopStyleColor(); end;
            if clicked and not selected then
                open_tabs[display.id], moves = tab.key, moves + 1;
                c.reselect();
            end;
            used = used + width + 8;
        end;
    end;
end;

-- The way back to the main page and the name of what is open, on a display and on a tool page.
function frame.top_line(imgui, c, name)
    if imgui.Button('< Back##frame') then c.open_page('Home'); end;
    c.tip('Back to the main page.');
    imgui.SameLine();
    imgui.TextColored(c.look.headings, name);
end;

-- Above the page, so it stays put as a long tab scrolls.
function frame.header(imgui, settings, view, callbacks, c)
    local display = current();
    fill(display, settings, view, callbacks, c);
    local title = display.title_of and display.title_of(ctx) or display.name;
    frame.top_line(imgui, c, title);
    header_used = imgui.CalcTextSize('< Back') + imgui.CalcTextSize(title) + 36;
    draw_rows(imgui, c, display.header);
    header_used = 0;
    if display.plain then imgui.Separator(); return; end;
    -- What has no lock has no Unlocked line: the overhead icons sit over heads.
    if ctx.element.lock and not ctx.locked and (not display.lock_on or display.lock_on(ctx)) then
        shaded(imgui, c, display.unlocked and display.unlocked(ctx) or 'Unlocked: hold Shift and drag it to move it, or drag an edge to resize it.');
    end;
    if display.under then draw_rows(imgui, c, display.under); end;
    draw_tabs(imgui, c, display);
    imgui.Separator();
end;

function frame.body(imgui, settings, view, callbacks, c)
    local display = current();
    fill(display, settings, view, callbacks, c);
    draw_rows(imgui, c, display.tabs[tab_of(display)]);
    if display.plain then return; end;
    imgui.Spacing();
    drawers.button(imgui, c, reset_row);
    c.confirm_line(reset_ids[ctx.id]);
end;

-- What the settings window's scroll goes by: it starts each display's tab at the top.
function frame.context()
    local display = current();
    return display.id .. '/' .. tab_of(display);
end;

-- The panel of the display open now, or last open.
function frame.panel(settings)
    fill(current(), settings);
    return ctx.id;
end;

-- The display open now, or last open, if one was, with nothing loaded for it.
function frame.opened() return open_id; end;

-- Opens a display, or the display that has that panel, on a tab, or on the one it was last on.
function frame.open(id, tab)
    load_displays();
    local display = by_id[owner[id]] or by_id[open_id] or displays[1];
    if display.pick then display.pick(id); end;
    open_id, moves = display.id, moves + 1;
    if tab then open_tabs[display.id] = tab; end;
end;

local page_ids = { Recasts = 'recasts', ['Party & alliance'] = 'party_ui', Filters = 'hidden' };

-- Whether a display has destination, a tab's key or a row's name, or with none, whether it has tabs at all.
local function holds(display, destination)
    if display.plain then return false; end;
    if destination == nil then return true; end;
    if destination == 'Filters' then return display.tabs.filters ~= nil; end;
    if tab_names[destination] then return display.tabs[destination] ~= nil; end;
    return display.named[destination] ~= nil;
end;

-- Where a link or a command opens: the display, then the tab, by a tab's key or the name of a row on it. Returns the fold
-- to go to, if the row is in one.
function frame.route(page, panel, destination)
    load_displays();
    local id = panel or page_ids[page] or open_id or displays[1].id;
    -- A link to a display's tab or row, with no display named, wants one that has it: the one open, or else the first.
    if page == 'Display' and not panel and not holds(by_id[owner[id]], destination) then
        id = displays[1].id;
        for _, display in ipairs(displays) do
            if holds(display, destination) then id = display.id; break; end;
        end;
    end;
    frame.open(id);
    local display = by_id[open_id];
    if not destination then return nil; end;
    if destination == 'Filters' then open_tabs[display.id] = 'filters'; return nil; end;
    if tab_names[destination] then open_tabs[display.id] = destination; return nil; end;
    local entry = display.named[destination];
    if not entry then return nil; end;
    open_tabs[display.id] = entry.tab;
    local fold = entry.row.kind == 'fold' and entry.row or entry.fold;
    return fold and fold.label or nil;
end;

-- Where a search topic about timer rows goes: the timer or recast panel that is open, or the first. A topic about what
-- only the status panels have stays off the recast panels.
function frame.timer_panel(status_only)
    load_displays();
    local kind = open_id and by_id[owner[open_id]].fold_page;
    return (kind == 'Panels' or kind == 'Recasts' and not status_only) and open_id or displays[1].id;
end;

-- What a search topic for this panel calls where it goes.
function frame.display_name(id)
    load_displays();
    return by_id[owner[id]].name;
end;

-- Goes where a search result points, with its fold open, and saves that.
function frame.go(result, settings, c)
    frame.open(result.panel, result.place);
    if result.fold then
        local key = by_id[open_id].fold_page .. '/' .. result.fold.key;
        c.editor_changed(function() settings.window.sections[key] = true; end);
    end;
end;

-- Every label of every display with what finds it, for the search index.
function frame.index(out)
    load_displays();
    for _, display in ipairs(displays) do
        for _, entry in ipairs(display.entries) do
            local item = entry.row;
            out[item.find] = out[item.find] or item.words;
        end;
    end;
    return out;
end;

-- What the search's results here depend on, past the words typed.
function frame.search_key(callbacks)
    local revision = callbacks and callbacks.settings_revision and callbacks.settings_revision();
    return tostring(revision) .. '/' .. moves;
end;

local function find_in(display, query, matches, settings, callbacks, out, seen)
    fill(display, settings, nil, callbacks, nil);
    local extra = hidden_words(display);
    for _, entry in ipairs(display.entries) do
        local item = entry.row;
        local key = display.id .. '/' .. item.find;
        if not seen[key] and visible(entry) and matches(query, words_for(query, matches, item, extra[item])) then
            seen[key] = true;
            local name = display.title_of and display.title_of(ctx) or display.name;
            out[#out + 1] = { tab = 'Display', panel = ctx.id, place = entry.tab, fold = item.kind == 'fold' and item or entry.fold, label = item.find,
                where = display.plain and name or name .. ', ' .. tab_names[entry.tab], alias = item.alias and matches(query, item.alias) };
        end;
    end;
end;

-- One result for each display a label is on, by what shows on it now. The open display's come first.
function frame.find(query, matches, settings, callbacks, out, seen)
    local open = current();
    find_in(open, query, matches, settings, callbacks, out, seen);
    for _, display in ipairs(displays) do
        if display ~= open then find_in(display, query, matches, settings, callbacks, out, seen); end;
    end;
end;

-- The place rows of Size and place. fixed is the id of what they place, if it isn't the display itself, and then find is what starts
-- their names in the search and locks greys them; fills is rows to add after the position.
local spot_names = { top_left = 'Top left', top = 'Top', top_right = 'Top right', left = 'Left', center = 'Center', right = 'Right',
    bottom_left = 'Bottom left', bottom = 'Bottom', bottom_right = 'Bottom right' };
local side_names = { below = 'Below', above = 'Above', left = 'Left', right = 'Right' };
local align_names = { start = 'Start', center = 'Middle', ['end'] = 'End' };
local follow_names = elements.follow_names;
local follow_lists = {};

-- What each display can move with: the kinds of anchor, then every other display by name. A display goes by element: and
-- its id, as a panel's id can be the name of a kind.
for _, element in ipairs(elements.list) do
    if element.anchor then follow_names['element:' .. element.id] = element.label; end;
end;
function frame.follow_choices(id)
    local list = follow_lists[id];
    if list then return list; end;
    list = { 'none', 'screen', 'party', 'chat' };
    for _, element in ipairs(elements.list) do
        if element.anchor and element.id ~= id then list[#list + 1] = 'element:' .. element.id; end;
    end;
    follow_lists[id] = list;
    return list;
end;

-- Whether target follows id, so id can't follow it.
local function follows_back(id, target)
    local at = target;
    for _ = 1, #elements.list do
        if at == nil then return false; end;
        if at == id then return true; end;
        at = elements.follows(ctx.s, at);
    end;
    return true;
end;

function frame.place_rows(fixed, fills, prefix, locks)
    local tag = fixed and '_' .. fixed or nil;
    locks = locks or true;
    local function id_of() return fixed or ctx.id; end;
    local function config() return elements.config(ctx.s, id_of()); end;
    local function anchor() return elements.anchor(ctx.s, id_of()); end;
    local function named(text) return prefix and prefix .. text:lower() or text; end;
    local function to(...)
        local kinds = {};
        for _, kind in ipairs({ ... }) do kinds[kind] = true; end;
        return function() return kinds[anchor().to] == true; end;
    end;
    local beside = to('element', 'party', 'chat');
    local follows = function() return anchors.active(anchor()); end;
    -- On a spot of the screen, Spot and its two distances say where it is.
    local off_spot = function() return anchor().to ~= 'screen'; end;
    local function drawn_size(key)
        local drawn = elements.drawn(id_of());
        return drawn and drawn[key] or 0;
    end;
    local across = frame.number('Across', nil, 0, 16000, 'Distance from the left edge of the game window. While it moves with something, this is where it goes when that isn\'t on the screen.', {
        tag = tag, find = named('Across'), alias = 'Horizontal position X Fallback spot across move place', locks = locks, edge = 'x', of = config,
        only = off_spot, shown_by = named('Moves with'),
        key_of = function() return elements.by_id[id_of()].x; end, room_of = function() return drawn_size('width'); end });
    local down = frame.number('Down', nil, 0, 16000, 'Distance from the top edge of the game window. While it moves with something, this is where it goes when that isn\'t on the screen.', {
        tag = tag, find = named('Down'), alias = 'Vertical position Y Fallback spot down move place', locks = locks, edge = 'y', of = config,
        only = off_spot, shown_by = named('Moves with'),
        key_of = function() return elements.by_id[id_of()].y; end, room_of = function() return drawn_size('height'); end });
    -- The ready pulse and the notices can sit in the middle of the screen.
    if fixed == 'pulse' or fixed == 'notices' then
        across.low, across.special = -1, { [-1] = 'Centered' };
    end;
    local rows = { across, down };
    for _, item in ipairs(fills or {}) do rows[#rows + 1] = item; end;
    rows[#rows + 1] = frame.pick('Moves with', nil, nil, follow_names, 'What it follows. It keeps its place beside that, even while locked.', {
        tag = tag, find = named('Moves with'), alias = 'anchor anchors anchored attach attachment dock follow corner edge screen party list chat log Clear this anchor Clear every anchor Every display\'s anchor Use where it is now as its fallback spot', locks = locks,
        choices_of = function() return frame.follow_choices(id_of()); end,
        read = function()
            local value = anchor();
            return value.to == 'element' and 'element:' .. value.element or value.to;
        end,
        refuse = function(_, value)
            local id, target = id_of(), value:match('^element:(.+)$');
            if not target or not follows_back(id, target) then return false; end;
            local name = elements.label(id);
            ctx.c.note(elements.label(target) .. ' already follows ' .. name .. ', so ' .. name .. ' can\'t follow it.');
            return true;
        end,
        write = function(_, value)
            local kept, target = anchor(), value:match('^element:(.+)$');
            -- The chat log and the game's list sit at the bottom of the screen, with no room below them.
            if kept.to ~= value and kept.side == 'below' then
                kept.side = value == 'chat' and 'above' or value == 'party' and 'left' or kept.side;
            end;
            -- A spot on the screen starts as where it is now.
            local drawn = value == 'screen' and kept.to ~= 'screen' and elements.drawn(id_of());
            if drawn then kept.point, kept.dx, kept.dy = 'top_left', drawn.x, drawn.y; end;
            kept.to, kept.element = target and 'element' or value, target or kept.element;
        end,
    });
    rows[#rows + 1] = frame.pick('Spot', 'point', anchors.points, spot_names, 'Its same corner or edge keeps its distance from this spot on the screen.', {
        tag = tag, find = named('Spot'), alias = 'Screen point', only = to('screen'), shown_by = named('Moves with'), of = anchor, locks = locks });
    rows[#rows + 1] = frame.number('Across from it', 'dx', -4000, 4000, 'Pixels right of the spot, or left when below 0.', {
        tag = tag, find = named('Across from it'), alias = 'Distance across', only = to('screen'), shown_by = named('Moves with'), of = anchor, locks = locks });
    rows[#rows + 1] = frame.number('Down from it', 'dy', -4000, 4000, 'Pixels down from the spot, or up when below 0.', {
        tag = tag, find = named('Down from it'), alias = 'Distance down', only = to('screen'), shown_by = named('Moves with'), of = anchor, locks = locks });
    rows[#rows + 1] = frame.pick('Side', 'side', anchors.sides, side_names, 'Which side of it this display goes on.', {
        tag = tag, find = named('Side'), alias = 'Attachment side', only = beside, shown_by = named('Moves with'), of = anchor, locks = locks });
    rows[#rows + 1] = frame.pick('Line up', 'align', anchors.aligns, align_names, 'Where along that side it starts.', {
        tag = tag, find = named('Line up'), alias = 'Line up with Attachment alignment', only = beside, shown_by = named('Moves with'), of = anchor, locks = locks });
    rows[#rows + 1] = frame.number('Gap', 'gap', -300, 300, 'Pixels between them. Below 0 they overlap.', {
        tag = tag, find = named('Gap'), alias = 'Attachment gap', only = beside, shown_by = named('Moves with'), of = anchor, locks = locks });
    rows[#rows + 1] = frame.number('Along the side', 'offset', -2000, 2000, 'Pixels along the side, from where it lines up.', {
        tag = tag, find = named('Along the side'), alias = 'Move along the side', only = beside, shown_by = named('Moves with'), of = anchor, locks = locks });
    if not fixed then
        rows[#rows + 1] = frame.tick('Same width as the chat log', 'dock_match_width', 'Its width follows the chat log\'s.', {
            alias = 'Match chat width', locks = locks, shown_by = 'Moves with', of = config,
            only = function() return anchor().to == 'chat' and ctx.element.panel == true; end });
    end;
    rows[#rows + 1] = frame.note('It follows even while locked.', { only = follows });
    rows[#rows + 1] = frame.note('What it follows isn\'t on the screen now, so it is at Across and Down until that\'s back.', {
        only = function()
            local id = id_of();
            return anchors.active(anchor()) and not elements.anchored(id) and elements.drawn(id) ~= nil
                and not (anchor().to == 'chat' and elements.chat ~= nil);
        end });
    rows[#rows + 1] = frame.note('There\'s no room on that side of the chat log, so it is at Across and Down.', {
        only = function()
            local id = id_of();
            return anchor().to == 'chat' and elements.chat ~= nil and not elements.anchored(id) and elements.drawn(id) ~= nil;
        end });
    return rows;
end;

frame.put_back = frame.button('Put it back where it started', 'Goes back to its first spot, and stops moving with anything.', function(c)
    local id, config, element = ctx.id, ctx.p, ctx.element;
    local x, y = require('ui.setup_defaults').first_spot(id, { width = c.screen_edge('x'), height = c.screen_edge('y'), chat = elements.chat });
    c.changed(function()
        config[element.x], config[element.y] = x, y;
        config[element.anchor] = anchors.make();
    end, true, 'Put ' .. elements.label(id) .. ' back');
end, { alias = 'Reset this position Clear this anchor', locks = true });

return frame;
