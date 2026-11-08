local theme = {};
local common = require('ui.theme');

theme.names = { unpack(common.names) };
theme.color_keys = { 'background', 'border', 'text', 'title' };

local palette_keys = { background = 'background_color', text = 'text_color', title = 'title_color', border = 'border_color' };
local palettes = {};
for _, name in ipairs(theme.names) do palettes[name] = true; end

local function color(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 };
end

local number = require('ui.numbers').clamp;

local function rgba(value, fallback)
    local out = {};
    value = type(value) == 'table' and value or {};
    for i = 1, 4 do out[i] = number(value[i], 0, 1, fallback[i]); end
    return out;
end

local function style(value)
    if type(value) ~= 'table' then return {}; end
    return type(value.style) == 'table' and value.style or value;
end

function theme.colors(name, window_type)
    local palette, result = common.colors(name), {};
    for key, source in pairs(palette_keys) do result[key] = palette[source]; end
    if name == 'Original FFXI' and window_type == 7 then
        result.text, result.title = color('201b13'), color('201b13');
    end
    return result;
end

-- A look from config's style, with globalstyle supplying what it doesn't have.
function theme.resolve(config, globalstyle)
    local base, inherited = style(config), style(globalstyle);
    local function choose(key, fallback)
        if base[key] ~= nil then return base[key]; end
        if inherited[key] ~= nil then return inherited[key]; end
        return fallback;
    end
    local name = base.theme or 'Phoenix';
    if not palettes[name] then name = 'Phoenix'; end
    local gauge_art = choose('gauge_art', 'Original FFXI');
    if gauge_art ~= 'XI View' then gauge_art = 'Original FFXI'; end;
    local result = {
        theme = name,
        window_type = math.floor(number(choose('window_type', 1), 1, 8, 1)),
        font = choose('font', 'Ashita'),
        gauge_art = gauge_art,
        icon_art = choose('icon_art', 'Client'),
        font_size = number(choose('font_size', 14), 8, 48, 14),
        scale = number(choose('scale', 1), 0.5, 3, 1),
        opacity = number(choose('opacity', 1), 0.05, 1, 1),
        rounding = number(choose('rounding', 3), 0, 24, 3),
        background = choose('background', true) ~= false,
        border = choose('border', true) ~= false,
        minimal = base.minimal == true,
    };
    if type(result.font) ~= 'string' or result.font == '' then result.font = 'Ashita'; end
    local colors = theme.colors(name, result.window_type);
    local parchment = name == 'Original FFXI' and result.window_type == 7;
    if parchment and (result.font == 'Original FFXI' or result.font == 'XI View') then
        result.waits_on_font = true;
        local ok, available = pcall(function() return not require('ui.fonts').failed(result.font); end);
        if ok and available then colors.text, colors.title = color('ffffff'), color('ffffff'); end
    end
    local custom_text = false;
    for _, key in ipairs(theme.color_keys) do
        local custom = type(base.colors) == 'table' and base.colors[key] or base[key .. '_color'];
        if custom ~= nil then
            colors[key] = rgba(custom, colors[key]);
            if key == 'text' then custom_text = true; end
        end
    end
    result.colors = colors;
    result.gauge_text_color = parchment and not custom_text and color('ffffff') or colors.text;
    for _, key in ipairs(theme.color_keys) do result[key .. '_color'] = colors[key]; end
    return result;
end

-- The party list buffs' look: the timer panels' look (global_style, settings.style), with the icon art and opacity of
-- the party's own style (config.style). Given the settings revision, the look is made again only when that revision or
-- those settings change. On parchment the game's font decides the text color and no setting says when that font loads,
-- so a look that waits on it is always made again.
local kept_party = {};
function theme.party(config, global_style, revision)
    local kept = kept_party;
    if revision ~= nil and kept.revision == revision and kept.config == config and kept.style == global_style
        and not kept.look.waits_on_font then return kept.look; end
    local look, own = theme.resolve(global_style), style(config);
    if own.icon_art ~= nil then look.icon_art = own.icon_art; end
    if own.opacity ~= nil then look.opacity = number(own.opacity, 0.05, 1, 1); end
    kept.look, kept.revision, kept.config, kept.style = look, revision, config, global_style;
    return look;
end

-- Looked up on first use: require on every call costs more than the conversion.
local col32;
function theme.u32(value, opacity)
    value = type(value) == 'table' and value or nil;
    local red = number(value and value[1], 0, 1, 1);
    local green = number(value and value[2], 0, 1, 1);
    local blue = number(value and value[3], 0, 1, 1);
    local alpha = number(value and value[4], 0, 1, 1) * number(opacity, 0, 1, 1);
    col32 = col32 or require('imgui').col32;
    return col32(math.floor(alpha * 255 + 0.5),
        math.floor(red * 255 + 0.5), math.floor(green * 255 + 0.5), math.floor(blue * 255 + 0.5));
end

function theme.window_paint(look, key)
    local value = look[key];
    if type(value) ~= 'table' then value = look.colors and look.colors[key] or look[key .. '_color']; end
    value = rgba(value, { 1, 1, 1, 1 });
    if look.theme == 'Original FFXI' and (key == 'background' or key == 'dropdowns') then
        local base = look.window_type == 7 and { 198, 185, 133 } or { 49, 48, 90 };
        return { value[1] * base[1] / 255, value[2] * base[2] / 255, value[3] * base[3] / 255, value[4] };
    end
    return value;
end

function theme.fallback_background(look)
    return theme.window_paint(look, 'background');
end

function theme.panel(list, rect, look)
    return require('ui.client_skin').panel(list, rect, look, look.colors, look.opacity);
end

-- A frame's own background and border where no window art paints it; Minimal draws neither. border is the
-- display's border color. Anything after it goes to AddRect as its flags and thickness.
function theme.frame_fallback(list, rect, look, border, ...)
    if look.background and not look.minimal then
        list:AddRectFilled({ rect.x, rect.y }, { rect.x + rect.width, rect.y + rect.height }, theme.u32(theme.fallback_background(look), look.opacity), look.rounding);
    end
    if look.border and not look.minimal then
        list:AddRect({ rect.x, rect.y }, { rect.x + rect.width, rect.y + rect.height }, theme.u32(border, look.opacity), look.rounding, ...);
    end
end

-- The window art behind a frame, or its own background and border where there is none.
function theme.frame(list, rect, look, border, ...)
    if not theme.panel(list, rect, look) then theme.frame_fallback(list, rect, look, border, ...); end
end

return theme;
