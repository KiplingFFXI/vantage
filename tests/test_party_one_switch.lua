-- Show party list buffs (party_ui.enabled) is the one switch over the party list buffs. A Party & alliance string and a
-- shared layout never hold it, so it stays each character's own; a whole profile and its string do. The strips, their
-- party cooldown cells among them, ask for nothing else: with Show party list buffs on they draw.
local defaults, share, store = require('ui.defaults'), require('core.share'), require('core.store');
local profiles = require('core.profiles');
local function fresh() return defaults.tidy(defaults.make()); end;

-- A saved profile and a shared layout of the whole presentation.
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/';
local off = fresh();
off.party_ui.enabled = false;
assert(store.write(folder .. 'profiles.json', { Off = profiles.capture(off) }), 'Fixture: the profiles file.');
local saved = profiles.new(folder);
local on = fresh();
on.party_ui.enabled = true;
local candidate = assert(saved:settings_of('Off', on));
assert(candidate.party_ui.enabled == false, 'A profile saved with Show party list buffs off loads with it off.');
-- A shared layout of the whole presentation holds no Show party list buffs: the reader's own stays, whether or not
-- anything else in the file differs.
for _, size in ipairs({ on.style.font_size, on.style.font_size + 3 }) do
    local publisher = store.copy(off);
    publisher.style.font_size = size;
    local layout = profiles.capture_layout(publisher, 'presentation');
    assert(layout.presentation.party_ui.enabled == nil, 'Fixture: a shared layout holds no Show party list buffs.');
    local receiver = store.copy(on);
    assert(profiles.apply_layout(receiver, layout, 'presentation'));
    assert(receiver.party_ui.enabled == true and receiver.style.font_size == size,
        'The reader of a shared presentation keeps Show party list buffs: ' .. size);
end;
local receiver = store.copy(on);
assert(profiles.apply_layout(receiver, profiles.capture_layout(off, 'placement'), 'placement') and receiver.party_ui.enabled == true,
    'A shared placement holds no switch either.');

-- Exports: a whole profile's and Party & alliance's.
local whole = assert(share.read(assert(share.export(off, 'profile', nil, 'Tester'))));
assert(whole.data.party_ui.enabled == false, 'It reads with Show party list buffs off.');
assert(assert(share.candidate(on, whole, 'replace')).party_ui.enabled == false, 'Replace lands it off.');
local party = assert(share.read(assert(share.export(on, 'element', 'party_ui', 'Tester'))));
assert(party.data.enabled == nil, 'Fixture: the Party & alliance string has no switch of its own.');
for _, mode in ipairs({ 'add', 'replace' }) do
    local landed = assert(share.candidate(on, party, mode));
    assert(landed.party_ui.enabled == true, 'Your Show party list buffs stays as it was: ' .. mode);
end;

-- With Show party list buffs on the strips draw their buffs and the party cooldown cells.
local overlay, party_hud = require('ui.native_party_hud'), require('ui.party_hud');
local p = require('ui.party_defaults').make();
local roster, subjects = party_hud.sample(6, 100);
local frame = { x = 900, y = 40, width = 116, height = 132, rows = {} };
for _, member in ipairs(roster.members) do
    frame.rows[member.slot] = { x = 900, y = 40 + member.slot * 22, width = 116, height = 22, slot = member.slot };
end;
local geometry = { available = true, groups = { frame } };
subjects[1002].cooldowns = { { member_id = 1002, member_name = 'Bramble', ability = 18, deadline = 700, total = 900,
    status = 'estimated', name = 'Bramble' } };
p.enabled = true;
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);
local function drawn()
    MOCK.imgui_calls = {};
    overlay.draw(roster, subjects, p, 100, { global_style = fresh().style, native_geometry = geometry,
        cooldowns = { enabled = true, strips = true } });
    local images, cells = 0, 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddImage' then images = images + 1; end; end;
    for _, plan in ipairs(overlay._kept and overlay._kept.plans or {}) do
        for _, row in ipairs(plan.rows or {}) do if row.cooldown_area then cells = cells + 1; end; end;
    end;
    return images, cells;
end;
local images, cells = drawn();
assert(images > 0, 'With Show party list buffs on, the strips draw their buffs.');
assert(cells == 1, 'And the party cooldown cells.');
p.enabled = false;
images = drawn();
assert(images == 0, 'With it off they draw nothing.');
return 'Show party list buffs is the one switch over the party list buffs';
