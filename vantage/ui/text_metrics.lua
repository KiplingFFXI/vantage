local metrics = {};
local fonts, cache = require('ui.fonts'), require('ui.render_cache');
local widths, wrapped = cache.new(4096), cache.new(2048);
local countdowns = cache.new(2048);
local tokens, sequence = cache.new(256), 0;
-- The tokens given out, by font, size and base size, each with the Present it was given in and its key in tokens. A
-- token is only given again in that Present, and outside a Present every token is worked out again. The tables are
-- kept from one Present to the next, so a Present makes none for the sizes asked for before; when they come to 1024,
-- as sizes come and go while a scale is dragged, the next Present starts them over.
local frame_tokens, frame_count, present, open = {}, 0, 0, false;

-- Present calls these around its drawing. No token is kept from one Present to the next: a TTF font's
-- measured size can change without a new assets generation.
function metrics.begin_frame()
    if frame_count >= 1024 then frame_tokens, frame_count = {}, 0; end;
    present, open = present + 1, true;
end;

function metrics.end_frame()
    open = false;
end;

-- key, when given, is the font, size and base size as tokens keeps them.
local function fresh_token(font, size, base_size, key)
    local assets = require('ui.client_assets');
    if assets.retry_pending and assets.retry_pending() then assets.retry(); end;
    local imgui = require('imgui');
    local calc = type(imgui) == 'table' and rawget(imgui, 'CalcTextSize');
    key = key or tostring(font) .. '\0' .. tostring(size) .. '\0' .. tostring(base_size or size);
    local measurement = fonts.measure;
    local generation, face = assets.generation and assets.generation() or 0, fonts.face and fonts.face(font);
    local bitmap = fonts.is_bitmap(font);
    local saved = tokens:get(key);
    -- A bitmap font measures countdowns by their ink once its countdown atlas is up, so what was measured
    -- before then is stale. An atlas stays up until the assets change generation, so a token measured
    -- with it isn't asked again.
    local ready = bitmap and (saved ~= nil and saved.ready == true and saved.generation == generation and saved.face == face
        or type(fonts.countdown_renderer) == 'function' and fonts.countdown_renderer(font) ~= nil);
    if saved and saved.generation == generation and saved.face == face and saved.measure == measurement
        and saved.calc == calc and saved.ready == ready then return saved.token; end;
    sequence = sequence + 1;
    tokens:put(key, {generation=generation,face=face,measure=measurement,calc=calc,ready=ready,token=sequence});
    return sequence;
end;

local function measure_size(value)
    return type(value) == 'number' and value > 0 and value < math.huge;
end;

function metrics.token(font, size, base_size)
    if not open or type(font) ~= 'string' or not measure_size(size) or base_size ~= nil and not measure_size(base_size) then
        return fresh_token(font, size, base_size);
    end;
    local base = base_size or size;
    local by_size = frame_tokens[font];
    if not by_size then by_size = {}; frame_tokens[font] = by_size; end;
    local by_base = by_size[size];
    if not by_base then by_base = {}; by_size[size] = by_base; end;
    local saved = by_base[base];
    if saved and saved.present == present then return saved.token; end;
    if not saved then
        saved = {key=tostring(font) .. '\0' .. tostring(size) .. '\0' .. tostring(base)};
        by_base[base], frame_count = saved, frame_count + 1;
    end;
    saved.token, saved.present = fresh_token(font, size, base_size, saved.key), present;
    return saved.token;
end;

local function fallback(font, value, size)
    local imgui = require('imgui');
    fonts.push(font, size);
    local ok, width, height = pcall(imgui.CalcTextSize, value);
    fonts.pop();
    if not ok then error(width, 0); end;
    return width, height or size;
end;

function metrics.width(font, value, size, base_size)
    value = tostring(value or '');
    base_size = base_size or size;
    local key = cache.key(metrics.token(font, size, base_size), value);
    local saved = widths:get(key);
    if saved ~= nil then return saved; end;
    local width = fonts.measure(font, value, size);
    if type(width) ~= 'number' or width ~= width or math.abs(width) == math.huge then
        width = fallback(font, value, base_size) * size / base_size;
    end;
    return widths:put(key, width);
end;

function metrics.countdown(font, value, size, compact)
    if fonts.is_bitmap(font) then
        local width, height = fonts.measure_countdown(font, value, size, compact);
        if width ~= nil then return width, height; end;
        -- Retry bitmap uploads on later draws; fallback metrics must not hide recovery.
        return fallback(font, value, size);
    end;
    local key = cache.key(metrics.token(font, size), value, compact == true);
    local saved = countdowns:get(key);
    if saved then return saved.width, saved.height; end;
    local width, height = fallback(font, value, size);
    countdowns:put(key, {width=width,height=height});
    return width, height;
end;

-- Callers treat the returned lines as immutable. Unknown measurement callbacks
-- bypass caching so custom metrics can never reuse another font's layout.
function metrics.lines(value, width, measure, token)
    if token == nil then return require('ui.text_wrap').lines(value, width, measure); end;
    local key = cache.key(token, value, width);
    local saved = wrapped:get(key);
    if saved then return saved; end;
    return wrapped:put(key, require('ui.text_wrap').lines(value, width, measure));
end;

return metrics;
