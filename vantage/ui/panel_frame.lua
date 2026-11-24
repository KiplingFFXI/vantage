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
-- Where Back goes: each place a link, the top bar, the search or edit mode left, newest last, for this session only.
-- page_names: what Back calls a page that isn't a display, set by the settings window.
local trail = {};
frame.page_names = {};

if VANTAGE_TEST_MODE then frame._displays, frame._trail = displays, trail; end;

-- The displays come in on first use, as this file is what they build on.
local DISPLAY_FILES = { 'status_panel', 'recast_panel', 'party_settings', 'overhead_settings', 'cooldown_settings', 'roll_settings', 'pet_settings', 'alert_panel', 'filter_settings', 'pulse_settings' };
local function load_displays()
    if loaded then return; end;
    loaded = true;
    for _, name in ipairs(DISPLAY_FILES) do
        require('ui.' .. name);
    end;
end;

-- While the settings window is open, warm loads the displays one a frame, in the same order, so the first visit to
-- Display doesn't load them all in one frame. It starts the frame after the window first draws, as that frame costs
-- the most already. A visit before they're all in loads the rest at once, as before.
local warmed = -1;
function frame.warm()
    if loaded then return; end;
    warmed = warmed + 1;
    if warmed == 0 then return; end;
    require('ui.' .. DISPLAY_FILES[warmed]);
    if warmed >= #DISPLAY_FILES then loaded = true; end;
end;

-- Rows. Every kind takes these in options:
-- only(ctx): draw it only while this holds. shown_by: the label, or labels, that show it, which find it while it is hidden.
-- locks(ctx): grey it while this holds.
-- of(ctx): the table its key is in, if it isn't the display's own. key_of(ctx): its key, if that changes.
-- read(ctx) and write(ctx, value): in place of a key. find: its name in the search and its Undo step's, if it isn't its label.
-- alias: more words that find it. tag: tells apart two rows with the same label on one tab.
-- transient: what it writes isn't a setting, so it makes no Undo step. refuse(ctx, value): true leaves the value as it is.
-- A row's table on the panel, by the name of its key there, so Copy this tab to knows the row's values go with the panel.
local panel_tables = setmetatable({}, { __mode = 'k' });
function frame.panel_table(name)
    local of = function(c) return c.p[name]; end;
    panel_tables[of] = name;
    return of;
end;

-- The keys a tab's rows keep on the panel: each row's own key, a table made by frame.panel_table, and what a custom row
-- names in copies. A row with a table of another kind, or read and write of its own, keeps nothing on the panel, and
-- own marks one that is the panel's alone, as its heading is.
function frame.tab_keys(rows, out)
    out = out or {};
    for _, item in ipairs(rows) do
        if item.rows then frame.tab_keys(item.rows, out); end;
        if item.own then
        elseif item.of then
            if panel_tables[item.of] then out[panel_tables[item.of]] = true; end;
        elseif item.key and item.kind ~= 'fold' and not item.read and not item.transient and not item.key_of then
            out[item.key] = true;
        end;
        for _, key in ipairs(item.copies or {}) do out[key] = true; end;
    end;
    return out;
end;

-- The keys in a set, in order, for a display's copy lists.
function frame.key_list(set)
    local list = {};
    for key in pairs(set) do list[#list + 1] = key; end;
    table.sort(list);
    return list;
end;

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
-- leaves names a button drawn beside it, and it stops short to leave that room. buttons draws a button for each choice, the
-- chosen one pressed, in place of a list, for a pick of what the rows below change.
function frame.pick(text, key, choices, names, help, options)
    local made = row('pick', text, help, options);
    made.key, made.choices, made.names = key, choices, names;
    if made.buttons then made.button_labels = {}; end;
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

-- fallback(ctx) is the color shown while there is none saved. back marks one that can go back to the color it comes from.
-- unset, in options, is what it says while there is none saved, From the main page unless given, and back_word the button
-- that lets it go.
function frame.color(text, key, help, options)
    local made = row('color', text, help, options);
    made.key = key;
    if made.back then
        made.back_word = made.back_word or 'Use the main page\'s color';
        made.back_text = made.back_word .. '###frame_back_' .. text .. (made.tag or '');
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
    -- A title is what the fold reads, made again only when the settings change.
    if made.title then made.title_memo = {}; end;
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

local reset_row, tab_reset_row, copy_row;
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
    c.light(words_for(c.search[1], c.matches, item, ctx.display and hidden_words(ctx.display)[item]), item.words, item.find);
end;
frame.lit = lit;

local function caption(imgui, text)
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end;
    imgui.TextUnformatted(text);
end;
frame.caption = caption;

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

local function pick_buttons(imgui, c, item, current, names)
    local choices = item.choices_of and item.choices_of(ctx) or item.choices;
    local used, available, chosen = 0, imgui.GetContentRegionAvail(), nil;
    for index = 1, #choices do
        local value = choices[index];
        local label = item.button_labels[value];
        if not label then label = names[value] .. item.bare .. '_' .. tostring(value); item.button_labels[value] = label; end;
        local width = imgui.CalcTextSize(names[value]) + 24;
        if index > 1 then
            if used + width <= available then imgui.SameLine(); else used = 0; end;
        end;
        local selected = current == value;
        if selected then imgui.PushStyleColor(ImGuiCol_Button, c.look.buttons_pressed); end;
        if imgui.Button(label) and not selected then chosen = value; end;
        if selected then imgui.PopStyleColor(); end;
        if index == 1 then lit(c, item); end;
        tip(c, item.help);
        used = used + width + 8;
    end;
    return chosen;
end;

function drawers.pick(imgui, c, item)
    local holder, key = table_of(item), key_of(item);
    local current, names = value_of(item, holder, key), item.names_of and item.names_of(ctx) or item.names;
    controls.label(imgui, item.text);
    tip(c, item.help);
    if item.buttons then
        local chosen = pick_buttons(imgui, c, item, current, names);
        if chosen ~= nil then write(c, item, holder, key, chosen, true); end;
        return;
    end;
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
            caption(imgui, item.unset or 'From the main page');
        elseif imgui.Button(item.back_text) then
            c.changed(function() holder[key] = nil; end, true, item.back_word .. ': ' .. item.find);
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
    if item.folder then
        -- A folder drawn before its caption (ui/controls.lua). Its caption is short enough never to wrap.
        if controls.folder_width(imgui, item.text) > imgui.GetContentRegionAvail() and imgui.GetCursorPosX() > imgui.GetFontSize() then imgui.NewLine(); end;
        local clicked = controls.folder_button(imgui, c.look, item.text, item.label);
        lit(c, item);
        tip(c, item.help);
        if clicked then item.action(c); end;
        return;
    end;
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

-- title(ctx), if given, is what the fold says now; its saved open state goes by key all the same.
function drawers.fold(imgui, c, item)
    local label, memo = item.label, item.title_memo;
    if memo then
        if memo.owner ~= ctx.s or memo.id ~= ctx.id or ctx.revision == nil or memo.revision ~= ctx.revision then
            memo.owner, memo.id, memo.revision, memo.label = ctx.s, ctx.id, ctx.revision, item.title(ctx) .. '##' .. item.key;
        end;
        label = memo.label;
    end;
    local open = c.section(label, item.help, item.opened, ctx.display.fold_page);
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
frame.lock_row = frame.tick('Locked', nil, 'Locked, Shift and drag don\'t move or resize it. Arrange on screen and the numbers on Size and place still do.', {
    alias = 'Lock position and size lock unlock move resize shift left drag edges corners protect',
    read = function() return ctx.locked; end,
    write = function(_, on) lock_of()[ctx.element.lock] = on; end,
});

local reset_ids = {};
reset_row = frame.button('Reset all of this display', 'Puts this display back as it started, every tab. Undo brings your settings back.', function(c)
    local id, scope, name = ctx.id, ctx.display.reset_scope or ctx.id, ctx.display.name_of and ctx.display.name_of(ctx) or ctx.display.name;
    local extra = ctx.display.reset_note and ctx.display.reset_note(ctx) or '';
    c.ask(reset_ids[id], 'Reset ' .. name .. '? It goes back to how it started' .. (ctx.element.lock and ': locked, in its first spot.' or '.') .. extra, function() c.call('reset', scope); end,
        'Reset', 'Reset it. Undo brings your settings back.', 'Leave it as it is.');
end, { alias = 'Reset this display Reset selected panel Reset this page Restore defaults' });

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
    for _, tab in ipairs(frame.tabs) do
        if not display.plain and display.tabs[tab.key] then walk({ tab_reset_row }, tab.key); end;
        if display.copy and display.copy[tab.key] and display.tabs[tab.key] then walk({ copy_row }, tab.key); end;
    end;
    display.entries, display.named, display.hidden = entries, named, {};
end;

-- A display: id, name, fold_page (what starts its folds' saved names), tabs (rows by tab key, and a tab it has no rows for
-- doesn't show), tab_on (by tab key, whether that tab's rows can do anything now), lock_on(ctx), when its lock counts only at
-- times, header (the rows above the tabs), under (rows under the Unlocked line), under_box, to draw a box round them as
-- they pick what every tab changes, panels (more ids it edits),
-- fill(ctx) to set ctx.id, pick(id) to choose one of its panels, title_of(ctx), when its title changes, unlocked(ctx), when
-- its Unlocked line isn't the usual one, reset_scope, when Reset all of this display doesn't go by its id, reset_note(ctx), more
-- words for its question, and reset_alias, more words that find it. tab_reset, by tab key, puts that tab back:
-- tab_reset[key](ctx, fresh), with fresh the display's settings as they start, and frame.reset_keys makes one. plain, for what isn't a display on the screen, leaves
-- out the tabs and the Reset: it has only rows on show.
function frame.register(display)
    displays[#displays + 1], by_id[display.id], owner[display.id] = display, display, display.id;
    display.switch_label = display.name .. '##frame_switch_' .. display.id;
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

-- Puts back the keys named, each a path from the display's settings such as 'effects.include', from fresh.
function frame.reset_keys(keys)
    return function(c, fresh)
        for _, path in ipairs(keys) do
            local into, from, key = c.p, fresh, path;
            local part, rest = key:match('^([^.]+)%.(.+)$');
            while part and type(into) == 'table' and type(from) == 'table' do
                into, from, key = into[part], from[part], rest;
                part, rest = key:match('^([^.]+)%.(.+)$');
            end;
            if type(into) == 'table' and type(from) == 'table' and from[key] ~= nil then into[key] = defaults.copy(from[key]); end;
        end;
    end;
end;

-- Puts back what rows write, as a fresh install has it. Each row's table is found for fresh settings and for these alike,
-- by putting them in ctx in turn, and gets its key back, or the keys it names in resets: a row that works out its value
-- from several keys names them there. A row of its own (own, transient), a button and a list kept elsewhere put back
-- nothing.
local function put_back_rows(rows, fresh_settings)
    local found = {};
    local function walk(list)
        for _, item in ipairs(list) do
            if item.rows then walk(item.rows); end;
            local keys = item.resets or (item.kind ~= 'fold' and { key_of(item) }) or {};
            local holder = #keys > 0 and not item.own and not item.transient and table_of(item);
            if type(holder) == 'table' then
                for _, key in ipairs(keys) do found[#found + 1] = { item = item, key = key, value = defaults.copy(holder[key]) }; end;
            end;
        end;
    end;
    local s, p = ctx.s, ctx.p;
    ctx.s, ctx.p = fresh_settings, elements.config(fresh_settings, ctx.id);
    walk(rows);
    ctx.s, ctx.p = s, p;
    for _, entry in ipairs(found) do
        local holder = table_of(entry.item);
        if type(holder) == 'table' then holder[entry.key] = entry.value; end;
    end;
end;

-- Every tab has one. When to show puts back the display's conditions whole, and a display's own tab_reset adds what its
-- rows don't name.
tab_reset_row = frame.button('Reset this tab', 'Puts the settings on this tab back as they started. Undo brings them back.', function(c)
    local display, tab = ctx.display, tab_of(ctx.display);
    local own = display.tab_reset and display.tab_reset[tab];
    -- A fresh install's first frame on this screen, so Across and Down go back to the first spot, as Put it back where it
    -- started does.
    local fresh_settings = require('ui.setup_defaults').first_frame({ width = c.screen_edge('x'), height = c.screen_edge('y'), chat = elements.chat });
    local fresh, conditions = elements.config(fresh_settings, ctx.id), ctx.element and ctx.element.conditions;
    c.changed(function()
        put_back_rows(display.tabs[tab], fresh_settings);
        if tab == 'when' and conditions and fresh then ctx.p[conditions] = defaults.copy(fresh[conditions]); end;
        if own then own(ctx, fresh); end;
    end, true, 'Reset this tab');
end, { alias = 'Clear filters Clear effect filters Clear list filters' });

-- Copy this tab to: another panel of this kind, or every other one, takes this tab's settings in one Undo step. A key the
-- other panel doesn't have stays out, as the light of what you can take off is only on some panels, and so does one the
-- display's copy_skip(key, from, into) keeps as each panel has it.
local copy_labels = {};
local function copy_tab(c, ids, tab)
    local keys, from, settings, skip, source = ctx.display.copy[tab], ctx.p, ctx.s, ctx.display.copy_skip, ctx.id;
    local name = #ids == 1 and elements.label(ids[1]) or 'every other panel';
    c.changed(function()
        for _, id in ipairs(ids) do
            local into = elements.config(settings, id);
            for _, key in ipairs(keys) do
                if into[key] ~= nil and type(into[key]) == type(from[key]) and not (skip and skip(key, source, id)) then into[key] = defaults.copy(from[key]); end;
            end;
        end;
    end, true, 'Copy ' .. tab_names[tab] .. ' to ' .. name);
end;
copy_row = frame.custom('Copy this tab to', 'Gives another panel of this kind the settings on this tab. Undo takes them back.', function(imgui, c, item)
    local tab, ids = tab_of(ctx.display), ctx.display.copy_to(ctx);
    controls.label(imgui, item.text);
    tip(c, item.help);
    imgui.SetNextItemWidth(-1);
    skin.prepare_menu(imgui, c.look);
    local chosen;
    if imgui.BeginCombo(item.bare, 'Choose a panel') then
        skin.menu(imgui, c.look, 'popup');
        for _, id in ipairs(ids) do
            copy_labels[id] = copy_labels[id] or elements.label(id) .. '##frame_copy_' .. id;
            if imgui.Selectable(copy_labels[id], false) then chosen = { id }; end;
        end;
        if #ids > 1 and imgui.Selectable('Every other panel##frame_copy_all', false) then chosen = ids; end;
        imgui.EndCombo();
    end;
    lit(c, item);
    tip(c, item.help);
    if chosen then copy_tab(c, chosen, tab); end;
end, { alias = 'Copy settings to another panel Same look Same filters Same conditions Copy to all panels',
    only = function(c) return c.display.copy ~= nil and #c.display.copy_to(c) > 0; end });
local copy_rows = { copy_row };

-- Why the display open isn't on the screen now: the first reason that holds, with its fix where it has one. Nothing
-- is said while it shows, while it is off, as its On tick says that, or while samples or Arrange on screen show it.
-- It needs a place on the screen to say it has nothing to show: the overhead icons and Party list have none.
local conditions = require('core.conditions');
local function element_on(c) return c.element ~= nil and elements.on(c.s, c.id); end;
local function shown_anyway(c)
    if require('ui.edit_mode').active() then return true; end;
    return c.p ~= nil and c.p.preview == true or c.element ~= nil and c.element.panel == true and c.s.preview == true;
end;
local function paused(c) return c.element ~= nil and c.element.panel == true and c.s.enabled == false and defaults.panel_enabled(c.s, c.id); end;
local function put_away(c)
    return not paused(c) and c.callbacks ~= nil and c.callbacks.displays_hidden ~= nil and c.callbacks.displays_hidden() == true;
end;
local function ruled_out(c) return element_on(c) and not put_away(c) and not shown_anyway(c) and not conditions.shown(c.id); end;
local function empty_now(c)
    return element_on(c) and c.element.x ~= nil and not put_away(c) and not shown_anyway(c) and conditions.shown(c.id)
        and elements.drawn(c.id) == nil;
end;
local why_rows = {
    frame.problem(paused, 'Timer panels are paused, so this panel is hidden.', 'Resume', 'Turns the timer panels back on.', nil,
        function(s) s.enabled = true; end),
    frame.group({
        frame.note('Vantage displays are hidden (/vg hide).', { tone = 'problem_messages' }),
        frame.button('Show', 'Shows the Vantage displays again. Nothing is saved.', function()
            if ctx.callbacks.show_displays then ctx.callbacks.show_displays(); end;
        end),
    }, { only = put_away }),
    frame.note('Its When to show rules hide it now.', { only = ruled_out }),
    frame.note('It has nothing to show now, so it is hidden.', { only = empty_now }),
};

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

-- The place open now: its page, and on a display, its panel, its tab and what Back calls it. probe stands in for ctx, which
-- the search may have filled for another display.
local probe = {};
local function here(settings)
    local page = settings.window.tab;
    if page ~= 'Display' then
        local name = frame.page_names[page] or page;
        return { page = page, name = name };
    end;
    local display = current();
    probe.s, probe.id = settings, display.id;
    if display.fill then display.fill(probe); end;
    local title, tab = display.title_of and display.title_of(probe) or display.name, tab_of(display);
    return { page = page, panel = probe.id, tab = tab, name = display.plain and title or title .. ', ' .. tab_names[tab] };
end;
local function same_place(a, b) return a.page == b.page and a.panel == b.panel and a.tab == b.tab; end;

-- Notes the place open now, so Back comes here, before a link leaves it.
function frame.remember(settings)
    local place, last = here(settings), trail[#trail];
    if last and same_place(last, place) then return; end;
    place.caption, place.tip = '< ' .. place.name, 'Back to ' .. place.name .. '.';
    place.button = place.caption .. '###< Back##frame';
    trail[#trail + 1] = place;
    if #trail > 20 then table.remove(trail, 1); end;
end;

-- After a link or a search result opens a place, drops what was noted for the place open now, so Back never names where
-- you are.
function frame.settle(settings)
    local now = here(settings);
    while trail[#trail] and same_place(trail[#trail], now) do trail[#trail] = nil; end;
end;

-- Goes to the place last noted that isn't the one open, or the main page.
function frame.back(c, settings)
    local now, place = here(settings), table.remove(trail);
    while place and same_place(place, now) do place = table.remove(trail); end;
    if not place then c.open_page('Home', nil, nil, true); return; end;
    c.open_page(place.page, place.panel, place.tab, true);
end;

-- Back, and the name of what is open, on a display and on a tool page. switch draws the name as a list of the displays.
-- Returns how wide they are.
local home = { caption = '< Main page', button = '< Main page###< Back##frame', tip = 'Back to the main page.' };
function frame.top_line(imgui, c, name, switch, settings)
    local place = trail[#trail] or home;
    if imgui.Button(place.button) then frame.back(c, settings); end;
    c.tip(place.tip);
    imgui.SameLine();
    if switch then switch(imgui, c, name); else imgui.TextColored(c.look.headings, name); end;
    return imgui.CalcTextSize(place.caption) + imgui.CalcTextSize(name) + (switch and imgui.GetFrameHeight() + 16 or 0) + 36;
end;

-- The name of the display open, as a list of every display: a pick opens it on the same tab, when it has one.
local function switch(imgui, c, name)
    imgui.SetNextItemWidth(imgui.CalcTextSize(name) + imgui.GetFrameHeight() + 16);
    skin.prepare_menu(imgui, c.look);
    imgui.PushStyleColor(ImGuiCol_Text, c.look.headings);
    local open = imgui.BeginCombo('##frame_switch', name);
    imgui.PopStyleColor();
    local chosen;
    if open then
        skin.menu(imgui, c.look, 'popup');
        for _, display in ipairs(displays) do
            if imgui.Selectable(display.switch_label, display == ctx.display) then chosen = display; end;
        end;
        imgui.EndCombo();
    end;
    tip(c, 'Opens another display, on this same tab when it has one.');
    if chosen and chosen ~= ctx.display then
        local tab = tab_of(ctx.display);
        frame.remember(ctx.s);
        frame.open(chosen.id, chosen.tabs[tab] and tab or nil);
        c.reselect();
    end;
end;

-- The rows under the header in a box, drawn round them once they are drawn so it fits what they took.
local box_from, box_to = { 0, 0 }, { 0, 0 };
local function boxed(imgui, c, rows)
    imgui.Spacing();
    imgui.BeginGroup();
    draw_rows(imgui, c, rows);
    imgui.EndGroup();
    if imgui.GetItemRectMin and imgui.GetWindowDrawList then
        box_from[1], box_from[2] = imgui.GetItemRectMin();
        box_to[1], box_to[2] = imgui.GetItemRectMax();
        box_from[1], box_from[2], box_to[1], box_to[2] = box_from[1] - 4, box_from[2] - 4, box_to[1] + 4, box_to[2] + 4;
        imgui.GetWindowDrawList():AddRect(box_from, box_to, require('ui.theme').u32(c.look.heading_lines), 3, 0, 1);
    end;
    imgui.Spacing();
end;

-- Above the page, so it stays put as a long tab scrolls.
function frame.header(imgui, settings, view, callbacks, c)
    local display = current();
    fill(display, settings, view, callbacks, c);
    local title = display.title_of and display.title_of(ctx) or display.name;
    header_used = frame.top_line(imgui, c, title, switch, settings);
    draw_rows(imgui, c, display.header);
    header_used = 0;
    if display.plain then imgui.Separator(); return; end;
    draw_rows(imgui, c, why_rows);
    -- What has no lock has no Unlocked line: the overhead icons sit over heads.
    if ctx.element.lock and not ctx.locked and (not display.lock_on or display.lock_on(ctx)) then
        shaded(imgui, c, display.unlocked and display.unlocked(ctx) or 'Unlocked: hold Shift and drag it to move it, or drag an edge to resize it.');
    end;
    if display.under then
        if display.under_box then boxed(imgui, c, display.under); else draw_rows(imgui, c, display.under); end;
    end;
    draw_tabs(imgui, c, display);
    imgui.Separator();
end;

function frame.body(imgui, settings, view, callbacks, c)
    local display = current();
    fill(display, settings, view, callbacks, c);
    local tab = tab_of(display);
    draw_rows(imgui, c, display.tabs[tab]);
    if display.plain then return; end;
    imgui.Spacing();
    if display.copy and display.copy[tab] then draw_rows(imgui, c, copy_rows); end;
    drawers.button(imgui, c, tab_reset_row);
    imgui.SameLine();
    drawers.button(imgui, c, reset_row);
    c.confirm_line(reset_ids[ctx.id]);
end;

-- What rows show changed with no change of settings, as a pick that isn't a setting does.
function frame.touch() moves = moves + 1; end;

-- What the settings window's scroll goes by: it starts each display's tab at the top.
function frame.context()
    local display = current();
    return display.id .. '/' .. tab_of(display);
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

-- Whether a display shows a tab now, and the row entry on it if one is given. ctx is filled for the display to ask, and
-- put back after, as a link or Back can open a place while a page is drawing. Before anything has filled it, they show.
local kept = {};
local function shown_now(display, key, entry)
    if ctx.s == nil then return true; end;
    for name, value in pairs(ctx) do kept[name] = value; end;
    fill(display, ctx.s, ctx.view, ctx.callbacks, ctx.c);
    local shown = tab_here(display, key) and (entry == nil or visible(entry));
    for name in pairs(ctx) do ctx[name] = nil; end;
    for name, value in pairs(kept) do ctx[name], kept[name] = value, nil; end;
    return shown and true or false;
end;

-- Whether a display shows destination now, a tab's key or a row's name, or with none, whether it has tabs at all. A tab
-- or a row hidden now, as Size and place on the ready pulse while it sits on its row, counts as not there.
local function holds(display, destination)
    if display.plain then return false; end;
    if destination == nil then return true; end;
    local key, entry = destination == 'Filters' and 'filters' or tab_names[destination] and destination, nil;
    if not key then
        entry = display.named[destination];
        key = entry and entry.tab;
    end;
    return key ~= nil and display.tabs[key] ~= nil and shown_now(display, key, entry);
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
    -- A row hidden now, as the recast tints are while no panel shows spells or abilities, is no place to go to, so its tab
    -- opens at the top, as it does for a tab hidden now.
    if not shown_now(display, entry.tab, entry) then return nil; end;
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
        -- A tab the display doesn't show now, such as Filters on a list that is off, has nothing to find. The key is made
        -- only for a row that matches, as most don't.
        local key = tab_here(display, entry.tab) and visible(entry) and matches(query, words_for(query, matches, item, extra[item]))
            and display.id .. '/' .. item.find;
        if key and not seen[key] then
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
-- Moves with's choices change with the display, so the kinds' names go in its words.
local follow_words = table.concat({ follow_names.none, follow_names.screen, follow_names.party, follow_names.chat }, ' ');

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

function frame.place_rows(fixed, fills, prefix)
    local tag = fixed and '_' .. fixed or nil;
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
        tag = tag, find = named('Across'), alias = 'Horizontal position X Fallback spot across move place', edge = 'x', of = config,
        only = off_spot, shown_by = named('Moves with'),
        key_of = function() return elements.by_id[id_of()].x; end, room_of = function() return drawn_size('width'); end });
    local down = frame.number('Down', nil, 0, 16000, 'Distance from the top edge of the game window. While it moves with something, this is where it goes when that isn\'t on the screen.', {
        tag = tag, find = named('Down'), alias = 'Vertical position Y Fallback spot down move place', edge = 'y', of = config,
        only = off_spot, shown_by = named('Moves with'),
        key_of = function() return elements.by_id[id_of()].y; end, room_of = function() return drawn_size('height'); end });
    -- The ready pulse and the notices can sit in the middle of the screen.
    if fixed == 'pulse' or fixed == 'notices' then
        across.low, across.special = -1, { [-1] = 'Centered' };
    end;
    local rows = { across, down };
    for _, item in ipairs(fills or {}) do rows[#rows + 1] = item; end;
    rows[#rows + 1] = frame.pick('Moves with', nil, nil, follow_names, 'What it follows. It keeps its place beside that, even while locked.', {
        of = anchor, resets = { 'to', 'element' }, tag = tag, find = named('Moves with'), alias = 'anchor anchors anchored attach attachment dock follow corner edge screen party list chat log Clear this anchor Clear every anchor Every display\'s anchor Use where it is now as its fallback spot ' .. follow_words,
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
            -- Nothing keeps it where its anchor drew it, as its own Across and Down, so it doesn't jump. One its anchor
            -- didn't place is at its Across and Down already.
            local here = value == 'none' and elements.anchored(id_of()) and elements.drawn(id_of());
            if here then
                local element, own = elements.by_id[id_of()], config();
                own[element.x], own[element.y] = math.floor(here.x + 0.5), math.floor(here.y + 0.5);
            end;
            kept.to, kept.element = target and 'element' or value, target or kept.element;
        end,
    });
    rows[#rows + 1] = frame.pick('Spot', 'point', anchors.points, spot_names, 'Its same corner or edge keeps its distance from this spot on the screen.', {
        tag = tag, find = named('Spot'), alias = 'Screen point', only = to('screen'), shown_by = named('Moves with'), of = anchor });
    rows[#rows + 1] = frame.number('Across from it', 'dx', -4000, 4000, 'Pixels right of the spot, or left when below 0.', {
        tag = tag, find = named('Across from it'), alias = 'Distance across', only = to('screen'), shown_by = named('Moves with'), of = anchor });
    rows[#rows + 1] = frame.number('Down from it', 'dy', -4000, 4000, 'Pixels down from the spot, or up when below 0.', {
        tag = tag, find = named('Down from it'), alias = 'Distance down', only = to('screen'), shown_by = named('Moves with'), of = anchor });
    rows[#rows + 1] = frame.pick('Side', 'side', anchors.sides, side_names, 'Which side of it this display goes on.', {
        tag = tag, find = named('Side'), alias = 'Attachment side', only = beside, shown_by = named('Moves with'), of = anchor });
    rows[#rows + 1] = frame.pick('Line up', 'align', anchors.aligns, align_names, 'Where along that side it starts.', {
        tag = tag, find = named('Line up'), alias = 'Line up with Attachment alignment', only = beside, shown_by = named('Moves with'), of = anchor });
    rows[#rows + 1] = frame.number('Gap', 'gap', -300, 300, 'Pixels between them. Below 0 they overlap.', {
        tag = tag, find = named('Gap'), alias = 'Attachment gap', only = beside, shown_by = named('Moves with'), of = anchor });
    rows[#rows + 1] = frame.number('Along the side', 'offset', -2000, 2000, 'Pixels along the side, from where it lines up.', {
        tag = tag, find = named('Along the side'), alias = 'Move along the side', only = beside, shown_by = named('Moves with'), of = anchor });
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

-- Size, on the main page, scales every display but the party list beside the game's, so each Size and place tab it
-- reaches points there.
frame.scale_line = frame.line('Bigger or smaller', 'Size, on the main page, makes every display bigger or smaller: text, icons and rows.', {
    frame.button('Open Size', 'Opens How it looks on the main page, where Size is.', function(c) c.open_page('Home', nil, 'How it looks'); end),
}, { alias = 'Scale zoom Size on the main page' });

-- What a Shift drag does to a display with one Height.
frame.resize_note = frame.note('Moving or resizing it on the screen stops it moving with anything. Resizing by its top or bottom edge gives it a fixed Height.', {
    find = 'What a resize changes', alias = 'resize edges corners Shift left drag' });

frame.put_back = frame.button('Put it back where it started', 'Goes back to its first spot, and stops moving with anything.', function(c)
    local id, config, element = ctx.id, ctx.p, ctx.element;
    local x, y = require('ui.setup_defaults').first_spot(id, { width = c.screen_edge('x'), height = c.screen_edge('y'), chat = elements.chat });
    c.changed(function()
        config[element.x], config[element.y] = x, y;
        config[element.anchor] = anchors.make();
    end, true, 'Put ' .. elements.label(id) .. ' back');
end, { alias = 'Reset this position Clear this anchor' });

return frame;
