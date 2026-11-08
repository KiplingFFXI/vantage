-- Ashita's renderer draws each clip as a viewport of whole pixels (X = trunc(x0), Width = trunc(x1 - x0)) and
-- stretches the clip's own range over it, so a clip off whole pixels shifts and squeezes its countdown and
-- text, with linear filtering. Every clip the HUD pushes is on whole pixels, rounded outward.
package.loaded['ui.icons'] = {status=function() return 123; end};
local hud, defaults = require('ui.hud'), require('ui.defaults');
MOCK.screen = {1600, 1000};
local function whole(value) return type(value) == 'number' and value == math.floor(value); end;
local function check(mode, scale)
    local s = defaults.make();
    s.style.scale = scale;
    for id, p in pairs(s.panels) do p.enabled = id == 'self_buffs' or id == 'self_debuffs'; end;
    local p = s.panels.self_buffs;
    p.mode, p.x, p.y, p.width = mode, 40, 120, 333;
    local rows, listed = {}, {};
    for index, effect in ipairs({33, 40, 41, 42, 43}) do
        rows[index] = {key='r' .. index, instance=1, effect=effect, slot=index - 1, scope='self', entity_id=1001, kind='buff',
            status='server', present=true, name='Effect ' .. effect, entity_name='You', deadline=1000 + 61 * index, total=300};
        listed[index] = {effect=effect, slot=index - 1};
    end;
    MOCK.imgui_calls = {};
    hud.draw({valid=true, context={id=1001, valid=true, self_effects=listed}, rows=rows}, s, 1000, {});
    local clips, fractional, example = 0, 0, nil;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:PushClipRect' and call[4] ~= false then
            clips = clips + 1;
            local a, b = call[2], call[3];
            if not (whole(a[1]) and whole(a[2]) and whole(b[1]) and whole(b[2])) then
                fractional = fractional + 1;
                example = example or ('%.17g,%.17g - %.17g,%.17g'):format(a[1], a[2], b[1], b[2]);
            end;
        end;
    end;
    return clips, fractional, example;
end;
for _, mode in ipairs({'icons', 'bars', 'expanded'}) do
    for _, scale in ipairs({1, 1.1, 1.15, 1.2, 0.8, 1.25}) do
        local clips, fractional, example = check(mode, scale);
        assert(clips > 0, 'Fixture: the ' .. mode .. ' panel pushes clips.');
        assert(fractional == 0, ('%d of %d %s clips at scale %s are off whole pixels: %s'):format(fractional, clips, mode,
            tostring(scale), tostring(example)));
    end;
end;
