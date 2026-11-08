local requests = {};
package.loaded['ui.icons'] = {
    status = function(id, artwork) requests[#requests + 1] = { id = id, artwork = artwork }; return 901; end,
    reason = function() return nil; end,
};
-- The strips ask for an icon at the size they draw it; this one has a single size.
package.loaded['ui.icons'].status_at = function(id, artwork) return package.loaded['ui.icons'].status(id, artwork), { 1, 1 }; end;
local defaults = require('ui.defaults');
local settings = defaults.make();
assert(settings.style.icon_art == 'Original FFXI' and settings.party_ui.style.icon_art == 'Original FFXI');
settings.style.font, settings.style.gauge_art = 'Tahoma Bold', 'XI View';
settings.style.icon_art, settings.party_ui.style.icon_art = 'XI View', 'Original FFXI';
local normalized = defaults.tidy(defaults.copy(settings));
assert(normalized.style.icon_art == 'XI View' and normalized.style.font == 'Tahoma Bold' and normalized.style.gauge_art == 'XI View');
assert(normalized.party_ui.style.icon_art == 'Original FFXI');
local missing = defaults.copy(settings); missing.style.icon_art, missing.party_ui.style.icon_art = nil, nil;
missing = defaults.tidy(missing);
assert(missing.style.icon_art == 'Original FFXI' and missing.party_ui.style.icon_art == 'Original FFXI', 'A save with no artwork choice takes the default.');
missing.style.icon_art, missing.party_ui.style.icon_art = 'bad', 'bad';
missing = defaults.tidy(missing);
assert(missing.style.icon_art == 'Original FFXI' and missing.party_ui.style.icon_art == 'Original FFXI');
local custom = require('core.customization');
assert(custom.set(settings, 'style.icon_art', 'Original FFXI').style.icon_art == 'Original FFXI');
assert(custom.set(settings, 'party_ui.style.icon_art', 'XI View').party_ui.style.icon_art == 'XI View');
assert(not custom.set(settings, 'style.icon_art', 'bad'));

local hud, party, native = require('ui.hud'), require('ui.party_hud'), require('ui.native_party_hud');
local view = hud.sample(100);
hud.draw(view, settings, 100, {});
assert(#requests > 0);
for _, request in ipairs(requests) do assert(request.artwork == 'XI View', 'Every timer panel uses its selected icon artwork.'); end
requests = {};
local roster, subjects = party.sample(18, 100);
settings.party_ui.enabled = true;
-- The game's party list: a window for each of the three parties, with a row for each member.
local game = { available = true, groups = {} };
for group = 1, 3 do
    local frame = { x = 1300, y = 60 + (group - 1) * 200, width = 200, height = 180, rows = {} };
    for _, member in ipairs(roster.members) do if member.group == group then
        frame.rows[member.slot] = { x = 1300, y = frame.y + member.slot % 6 * 30, width = 200, height = 30, slot = member.slot };
    end; end;
    game.groups[group] = frame;
end;
native.draw(roster, subjects, settings.party_ui, 100, { global_style = settings.style, native_geometry = game });
local seen = {};
for _, request in ipairs(requests) do seen[request.artwork] = true; end
-- Every group wears the party's icons.
assert(seen['Original FFXI'] and not seen['XI View'] and not seen.Client, 'The party icon choice reaches every strip.');

local profiles = require('core.profiles');
local named = profiles.capture(settings);
assert(named.style.icon_art == 'XI View' and named.party_ui.style.icon_art == 'Original FFXI');
local placement = profiles.capture_layout(settings, 'placement');
assert(placement.style == nil and placement.party_ui.style == nil, 'Icon art stays outside shared placement.');
local presentation = profiles.capture_layout(settings, 'presentation').presentation;
assert(presentation.style.icon_art == 'XI View' and presentation.party_ui.style.icon_art == 'Original FFXI');

local window, imgui = require('ui.settings_window'), require('imgui');
settings.window.open, settings.window.tab = true, 'Home';
settings.style.icon_art = 'Client';
local phases = {};
local callbacks = { changed = function(phase) phases[#phases + 1] = phase; end, save = function() return true; end };
imgui.BeginCombo = function(label) return label == '##main_icon_art'; end;
MOCK.clicks['XI View##XI View'] = true;
window.draw(settings, view, callbacks);
assert(settings.style.icon_art == 'XI View' and settings.style.font == 'Tahoma Bold');
assert(phases[1] == 'before' and phases[2] == 'after', 'Icon edits participate in the normal Undo transaction.');
-- Party buff icons sit among the party's buffs and debuffs.
settings.window.tab = 'Display';
require('ui.panel_frame').open('party_ui', 'look');
imgui.BeginCombo = function(label) return label == '##frame_Party buff icons'; end;
MOCK.clicks['XI View##XI View'] = true;
window.draw(settings, view, callbacks);
assert(settings.party_ui.style.icon_art == 'XI View');
-- A group has no icon choice of its own.
local group_icons = false;
imgui.BeginCombo = function(label) group_icons = group_icons or label:find('Group buff icons', 1, true) ~= nil; return false; end;
window.draw(settings, view, callbacks);
assert(not group_icons, 'There is no icon choice of a group\'s own.');
assert(require('setup_fixture').apply(settings, { size = 'minimal', skin = 'keep', matching = false }));
assert(settings.party_ui.style.icon_art == 'XI View', 'A setup size keeps the icon art.');
require('original_skin_fixture')(settings);
assert(settings.style.icon_art == 'Original FFXI' and settings.style.font == 'Original FFXI');
assert(#MOCK.font_stack == 0 and #MOCK.commands == 0);
return true;
