-- Fine-tune scaling's line gives the icon sizes in pixels on this screen, with Size on the main page, while overhead icons
-- are off as they start too. It follows the screen when that changes, with no setting changed.
MOCK.screen = { 3840, 2160 };
local h = require('panel_fixture')();
local overhead = require('core.overhead');
h.fresh();
h.on('overhead', 'place');
assert(not h.s.overhead.enabled, 'Fixture: overhead icons are off.');

local function line()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextWrapped' and tostring(call[2]):find('yalms from the camera', 1, true) then return call[2]; end;
    end;
end;
-- A medium unit's icons at the distance Icon size is for, as the icons draw them on a screen this high.
local function medium(height)
    local o = h.s.overhead;
    local ui = height / 1080 * h.s.style.scale;
    return math.floor(overhead.icon_size(false, 0, o.size.ref_hitbox, '', o.size.ref_depth, false, o, ui) + 0.5);
end;
local function says(height)
    local text = line() or 'no line';
    return text:find('a medium unit gets ' .. medium(height) .. ' px icons', 1, true) ~= nil, text;
end;

assert(medium(2160) == 44, 'Fixture: Icon size 22 is 44 px on a screen 2160 high: ' .. medium(2160));
local ok, text = says(2160);
assert(ok, 'The line gives the size on this screen, 44 px, but says: ' .. text);

MOCK.screen = { 1920, 1080 };
h.draw();
ok, text = says(1080);
assert(ok, 'The line follows a new screen size: ' .. text);

h.s.style.scale = 1.5;
h.bump();
h.draw();
ok, text = says(1080);
assert(medium(1080) == 33 and ok, 'And Size on the main page: ' .. text);
MOCK.screen = nil;
MOCK.fire('unload');
return 'ok';
