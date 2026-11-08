local theme = require('ui.theme');
local defaults = require('ui.defaults');
local s = defaults.make();
assert(theme.apply(s, 'Phoenix'));
assert(#theme.WINDOW_COLORS == 37);
-- Whether the window shows every color of a theme as that theme gives it.
local function wears(settings, name)
    local look = theme.window(settings);
    local base = theme.window_defaults({ style = { theme = name, window_type = look.window_type } });
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        for i = 1, 4 do if math.abs(look[entry.key][i] - base[entry.key][i]) > 0.002 then return false; end end
    end
    return true;
end
local missing = defaults.make();
missing.window_style = nil;
missing.style.font = 'Bahnschrift';
missing = defaults.tidy(missing);
assert(theme.window(missing).font == 'Bahnschrift');
assert(missing.window_style.font_size == 17);
assert(wears(s, 'Phoenix'));
theme.apply(s, 'Mint');
assert(wears(s, 'Mint') and theme.window(s).font == s.style.font, 'The window writes in the one font.');
s.window_style.font_size = 22;
assert(theme.window(s).font_size == 22 and wears(s, 'Mint'), 'The saved text size goes on the look.');
local malformed = { style = 'bad', window_style = { linked = false, font_size = math.huge,
    text = { -5, 8, 0/0, 'bad' }, rounding = -10, spacing = 100 } };
theme.tidy_window(malformed);
assert(require('core.store').equal(malformed.window_style, { font_size = 17 }), 'The text size is all a save keeps.');
local imgui = require('imgui');
local colors, vars, popped_colors = {}, {}, 0;
imgui.PushStyleColor = function(key, value) assert(key ~= nil); colors[#colors + 1] = {key, value}; end;
imgui.PushStyleVar = function(key, value) assert(key ~= nil); vars[#vars + 1] = {key, value}; end;
imgui.PopStyleColor = function(n) popped_colors = popped_colors + n; end;
local index = 0;
for _, entry in ipairs(theme.WINDOW_COLORS) do
    if entry.paints then _G['ImGuiCol_' .. entry.paints] = index; index = index + 1; end
    if entry.also then _G['ImGuiCol_' .. entry.also] = index; index = index + 1; end
end
local nc = theme.push(s);
assert(nc == #colors and nc > 30 and #vars == 0);
theme.pop(nc);
assert(popped_colors == nc);
-- Vantage's windows don't dock, so they draw no tab: no Tabs color is pushed, under any name an Ashita build gives them.
local tab_names, kept = { 'Tab', 'TabHovered', 'TabSelected', 'TabActive', 'TabSelectedOverline', 'TabDimmed',
    'TabUnfocused', 'TabDimmedSelected', 'TabUnfocusedActive', 'TabDimmedSelectedOverline' }, {};
for offset, name in ipairs(tab_names) do kept[name] = _G['ImGuiCol_' .. name]; _G['ImGuiCol_' .. name] = 1000 + offset; end
colors, vars = {}, {};
nc = theme.push(s);
for _, entry in ipairs(colors) do assert(entry[1] < 1000, 'No Tabs color is pushed: ' .. tostring(entry[1])); end
theme.pop(nc);
for _, name in ipairs(tab_names) do _G['ImGuiCol_' .. name] = kept[name]; end
s = defaults.make();
colors, vars = {}, {};
nc = theme.push(s);
assert(nc == #colors and nc > 30 and #vars == 0, 'Defaults apply the complete menu palette without new size overrides.');
theme.pop(nc);
local native = defaults.make();
native.style.window_type = 8;
assert(theme.apply(native, 'Original FFXI'));
assert(theme.window(native).theme == 'Original FFXI' and theme.window(native).window_type == 8);
assert(theme.window_paint(theme.window(native), 'background')[1] < 0.2);
assert(theme.window(native).background[1] == 1 and theme.window(native).text[1] == 1);
native.style.window_type = 3;
assert(theme.window(native).window_type == 3, 'The window follows the window type of the timer panels.');
colors, vars = {}, {};
local original_nc = theme.push(native);
assert(original_nc > 30 and #vars == 0);
for _, entry in ipairs(colors) do
    if entry[1] == ImGuiCol_WindowBg or entry[1] == ImGuiCol_PopupBg then assert(entry[2][1] < 0.2); end
end
theme.pop(original_nc);
local command = require('core.customization');
assert(command.set(native, 'style.window_type', '7').style.window_type == 7);
assert(not command.set(native, 'style.window_type', '1.5'));
assert(not command.set(native, 'style.window_type', '9'));
assert(not command.set(native, 'window_style.window_type', '0'));
native.style.window_type = 7;
assert(theme.window(native).text[1] < 0.2 and theme.window(native).buttons[1] > 0.6,
    'The light client skin needs dark ink and lighter controls, without darkening its artwork.');
assert(theme.window(native).background[1] == 1);
assert(theme.window_paint(theme.window(native), 'background')[1] > 0.65
    and theme.window_paint(theme.window(native), 'dropdowns')[1] > 0.65,
    'Missing light-skin resources and internal color-picker popups must keep dark text readable.');
native.style.window_type = 1;
assert(theme.window(native).buttons[1] < 0.3, 'Changing skins restores matching defaults.');
return true;
