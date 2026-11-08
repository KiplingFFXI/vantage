-- /vg overhead calibrate reads the current target and the camera on the next frame, prints two plain lines and writes
-- them to the report, even with overhead icons off, and changes nothing. /vg report has the overhead lines: the
-- capture point, the camera checks and matrices, DisplaySize, the boot sizes, units considered and kept, and what the
-- target's block is sized from and where it went.
local W = require('overhead_fixture');
local store = require('core.store');
local path = MOCK_INSTALL_PATH .. '/config/addons/vantage/reports/latest.json';
local boot = { ['0001'] = 1920, ['0002'] = 1080, ['0003'] = 3840, ['0004'] = 2160 };
AshitaCore.GetConfigurationManager = function()
    return { GetUInt32 = function(_, section, file, key, fallback)
        assert(section == 'boot' and file == 'ffxi.registry');
        return boot[key] or fallback;
    end };
end;
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Goblin Mugger', hitbox = 1.2 });
-- You stand off the origin, so the camera's distance from you differs under the two mappings.
W.entities[W.self].y = 3;
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(1);
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked, text); end
-- With overhead icons off no frame reads the camera, so /vg report names where the setting reads it: scene on a
-- fresh install, then present once that is picked.
MOCK.frame();
command('/vg report');
assert(assert(store.read(path)).overhead.camera.capture == 'scene', 'Off, a fresh install reads at scene.');
-- Read at present: the mock's frames have no BeginScene.
app.state.settings.overhead.camera.capture = 'present';
MOCK.frame();
command('/vg report');
assert(assert(store.read(path)).overhead.camera.capture == 'present', 'Off, with present picked, at present.');
local function lines(from) local out = {}; for i = from, #MOCK.printed do out[#out + 1] = MOCK.printed[i]; end; return out; end
assert(app.state.settings.overhead.enabled == false, 'Overhead icons start off.');

-- No target: one line saying what to do.
local seen = #MOCK.printed;
command('/vg overhead calibrate');
assert(#MOCK.printed == seen, 'Calibrate waits for the next frame.');
MOCK.frame();
local said = lines(seen + 1);
assert(#said == 1 and said[1]:find('Target a unit, then use /vg overhead calibrate again.', 1, true), table.concat(said, ' | '));

-- With a target: two lines, the second checking the X,Z,Y mapping and that the head sits above the feet.
W.target = 0x100;
local before = store.copy(app.state.settings);
seen = #MOCK.printed;
command('/vg overhead calibrate');
MOCK.frame();
said = lines(seen + 1);
assert(#said == 2, 'Two lines: ' .. table.concat(said, ' | '));
assert(said[1]:find('Goblin Mugger: mob, SpawnFlags 0x10, Type 1, race 0, hitbox 1.2, ModelSize -1.00, head 1.80 yalms from its hitbox.', 1, true), said[1]);
assert(said[2]:find('Camera read at present: in use. It sits 7.3 yalms from you as X,Z,Y (11.2 as X,Y,Z). Both are within 60 yalms.', 1, true), said[2]);
-- 1.8 yalms at depth 15 is 1.8 * 1.7 * 1080 / 30 = 110 px; the Goblin Mugger as target at depth 15 is 19 px (doc 3.3).
assert(said[2]:find('The head is 110 px above the feet, icons 19 px at depth 15.0. Display 1920x1080.', 1, true), said[2]);
for _, line in ipairs(said) do assert(not line:find('?', 1, true) and not line:lower():find('unknown', 1, true)); end
assert(not table.concat(said, ' '):find('Report saved', 1, true), 'The report is written without a third line.');
local report = assert(store.read(path));
local kept = report.overhead.calibrate;
assert(#kept == 2 and said[1]:sub(-#kept[1]) == kept[1] and said[2]:sub(-#kept[2]) == kept[2], 'The lines are in the report.');
assert(store.equal(app.state.settings, before) and not app.state.dirty, 'Calibrate changes no setting.');
assert(require('core.overhead').plan.count == 0, 'With overhead icons off nothing is placed.');

-- /vg report: the overhead lines.
app.state.settings.overhead.enabled = true;
MOCK.frame(); MOCK.frame();
command('/vg report');
report = assert(store.read(path));
local o = report.overhead;
assert(o.enabled == true and o.camera.capture == 'present' and o.camera.valid == true and o.camera.read == true, 'The capture point and checks.');
assert(math.abs(o.camera.p22 - 1.7) < 1e-6 and math.abs(o.camera.p34 - 1) < 1e-6 and o.camera.p44 == 0 and o.camera.p11 > 0);
assert(type(o.camera.passes_per_second) == 'number' and type(o.camera.rejects_per_second) == 'number');
assert(o.camera.display.width == 1920 and o.camera.display.height == 1080, 'DisplaySize.');
assert(o.boot['0001'] == 1920 and o.boot['0002'] == 1080 and o.boot['0003'] == 3840 and o.boot['0004'] == 2160, 'The boot sizes.');
assert(o.considered == 1 and o.kept == 1 and o.hidden == nil, 'Units considered and kept.');
local t = o.target;
assert(t.name == 'Goblin Mugger' and t.kind == 'mob' and t.type == 1 and t.spawn_flags == 0x10 and t.race == 0
    and math.abs(t.hitbox - 1.2) < 1e-6 and t.model_size == -1 and t.render_flags == 0x200, 'The target as read.');
assert(math.abs(t.head - 1.8) < 1e-9 and t.head_source == 'hitbox' and math.abs(t.depth - 15) < 1e-9 and t.size == 19
    and math.abs(t.ppy - 1.7 * 1080 / 30) < 1e-9, 'Its head height, depth, px per yalm and icon size.');
-- Where it went: its feet 2 yalms under the camera at depth 15 are 540 + 61.2 * 2 = 662.4 down; its head, where a
-- mob's name is centered, 540 + 61.2 * 0.2 = 552.2. The name is 0.33 yalm, 20.2 px, and the cursor its 16 px, so the
-- block's edge is 552.24 - 10.1 - 16 - 3 = 523.1.
assert(t.feet_y == 662 and t.name_y == 552 and t.name_px == 20.2 and t.arrow_px == 16 and t.anchor_y == 523,
    ('Where its block went: %s %s %s %s %s'):format(t.feet_y, t.name_y, t.name_px, t.arrow_px, t.anchor_y));
assert(report.performance.available == false or report.performance.stages['frame.overhead'], 'Overhead time per frame.');
-- Its show conditions hiding the blocks say so, not that Vantage's displays are hidden.
local conditions = require('core.conditions');
app.state.settings.overhead.conditions = conditions.tidy({ engaged = 'yes' });
MOCK.frame(0.2); MOCK.frame();
command('/vg report');
report = assert(store.read(path));
assert(report.overhead.hidden == 'Its When to show choices hide it here.' and report.overhead.kept == 0, tostring(report.overhead.hidden));
app.state.settings.overhead.conditions = conditions.tidy(nil);
MOCK.frame(0.2); MOCK.frame();
command('/vg report');
assert(assert(store.read(path)).overhead.hidden == nil, 'Without them it shows again.');

-- Usage, and the command list.
seen = #MOCK.printed;
command('/vg overhead');
assert(lines(seen + 1)[1]:find('Usage: /vg overhead on|off|preview|calibrate', 1, true));
command('/vg nothing');
assert(lines(seen + 1)[2]:find('report, overhead [on|off|preview|calibrate],', 1, true));
-- Calibrate while hidden says why it can't.
seen = #MOCK.printed;
command('/vg hide');
command('/vg overhead calibrate');
MOCK.frame();
said = lines(seen + 1);
assert(#said == 1 and said[1]:find('Overhead icons can\'t calibrate now. Vantage displays are hidden.', 1, true), said[1]);

-- Scene mode with overhead icons off: calibrate wakes the camera, so the next frame's BeginScenes read it.
command('/vg show');
app.state.settings.overhead.enabled, app.state.settings.overhead.camera.capture = false, 'scene';
MOCK.frame(1);
seen = #MOCK.printed;
command('/vg overhead calibrate');
MOCK.fire('d3d_beginscene', true); MOCK.fire('d3d_beginscene', true);
MOCK.frame();
said = lines(seen + 1);
assert(#said == 2 and said[2]:find('Camera read at scene: in use. It sits 7.3 yalms', 1, true), table.concat(said, ' | '));
-- A frame with too few scenes says so.
MOCK.frame(1);
seen = #MOCK.printed;
command('/vg overhead calibrate');
MOCK.fire('d3d_beginscene', true);
MOCK.frame();
said = lines(seen + 1);
assert(#said == 2 and said[2]:find('Camera read at scene: not in use, the frame had too few scenes to read the camera. Display', 1, true),
    table.concat(said, ' | '));

-- A render space of X, Y, Z: the camera fails its 60 yalm check under X,Z,Y, and calibrate still says where it sits
-- under each mapping, X,Y,Z the near one, with no head line.
app.state.settings.overhead.camera.capture = 'present';
local me, mob = W.entities[W.self], W.entities[0x100];
me.x, me.y, me.z, mob.y, mob.z = 0, 300, 4, 295, 4;
W.view_matrix = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, 298, 14, 1 };
MOCK.frame(1);
seen = #MOCK.printed;
command('/vg overhead calibrate');
MOCK.frame();
said = lines(seen + 1);
assert(#said == 2 and said[1]:find('Goblin Mugger: mob,', 1, true), table.concat(said, ' | '));
assert(said[2]:find('Camera read at present: not in use, the view is not the world camera near you: the camera is 410.2 yalms '
    .. 'from you, past 60. It sits 410.2 yalms from you as X,Z,Y (10.2 as X,Y,Z). Only X,Y,Z is within 60 yalms. Display 1920x1080.',
    1, true), said[2]);
assert(not said[2]:find('px', 1, true), 'No head line without a camera in use.');
for _, line in ipairs(said) do assert(not line:find('?', 1, true) and not line:lower():find('unknown', 1, true)); end
-- With overhead icons on, the same camera hides every block.
app.state.settings.overhead.enabled = true;
MOCK.frame();
assert(require('core.overhead').plan.count == 0 and require('core.overhead').plan.hidden == 'The camera can\'t be used.');
