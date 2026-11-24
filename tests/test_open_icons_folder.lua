-- Open icons folder, beside Reload icons on the main page and on Party list's Look tab: a folder drawn before its
-- caption, a click that opens the icons folder in File Explorer, and a note saying it did or where the folder is.
-- Overhead icons' Look tab says its icons are the main page's Icons, with a button that goes there.
local h = require('panel_fixture')();
local packs = require('ui.icon_packs');
local opened, works = {}, true;
packs._set_opener_for_tests(function(path) opened[#opened + 1] = path; return works; end);
local function folder_button(id)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' and call[2] == id then return true; end; end;
    return false;
end;
local function folder_drawn()
    local count = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddRectFilled' and call[5] == 1 then count = count + 1; end; end;
    return count;
end;

-- The main page, with Artwork open. A click makes the icons folder before it opens it.
local made = {};
local mkdir = MOCK_MKDIR;
MOCK_MKDIR = function(path) made[#made + 1] = path; if mkdir then return mkdir(path); end; return true; end;
packs._set_opener_for_tests(function(path) opened[#opened + 1] = path; assert(made[#made] and made[#made]:find('vantage/icons', 1, true), 'The folder is made first.'); return works; end);
h.fresh(function(s) s.window.sections['Home/Artwork'] = true; end);
h.draw();
assert(folder_button('Open icons folder##main_open_icons') and h.called('Button', 'Reload icons##main_reload_icons'), 'Open icons folder is beside Reload icons.');
assert(folder_drawn() == 2, 'Its folder is a tab and a front.');
h.draw('Open icons folder##main_open_icons');
h.draw();
assert(#opened == 1 and opened[1]:find('config\\addons\\vantage\\icons', 1, true) and not opened[1]:find('/', 1, true),
    'A click opens the icons folder, with Windows slashes: ' .. tostring(opened[1]));
assert(h.says('Opened the icons folder in File Explorer.'), 'A note says it opened.');
-- Where Windows can't open it, the note says where it is.
works = false;
h.draw('Open icons folder##main_open_icons');
h.draw();
assert(#opened == 2 and h.says('Windows couldn\'t open the icons folder. It\'s config/addons/vantage/icons/ in the Ashita folder.'),
    'A note says where the folder is.');
works = true;

-- Party list's Look tab has it too, after Reload icons.
h.fresh(function(s) s.party_ui.enabled = true; end);
h.on('party_ui', 'look');
assert(folder_button('Open icons folder##frame') and h.called('Button', 'Reload icons##frame'), 'Party list has it beside Reload icons.');
assert(folder_drawn() == 2, 'With its folder.');
h.draw('Open icons folder##frame');
h.draw();
assert(#opened == 3 and h.says('Opened the icons folder in File Explorer.'), 'It opens the same folder.');

-- An error while opening it is a folder that didn't open.
packs._set_opener_for_tests(function() error('could not start explorer.exe'); end);
assert(packs.open_folder() == false, 'An error is a folder that didn\'t open.');

-- Overhead icons' Look tab says where its icons come from, and its button opens Artwork on the main page.
h.fresh(function(s) s.overhead.enabled = true; end);
h.on('overhead', 'look');
assert(h.says('Its icons are the main page\'s Icons') and h.called('Button', 'Open Icons##frame'), 'Overhead icons point to Icons.');
h.draw('Open Icons##frame');
h.draw();
-- The mock opens every fold, so the fold it goes to is the one it scrolls to.
local function scrolled_to()
    local last;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'CollapsingHeader' then last = call[2]; end;
        if call[1] == 'SetScrollHereY' then return last; end;
    end;
end;
assert(h.s.window.tab == 'Home' and scrolled_to() == 'Artwork', 'Open Icons opens Artwork on the main page: ' .. tostring(scrolled_to()));
-- With a Largest too small for countdowns and no light, Look still shows, as the line is always there.
h.fresh(function(s)
    s.overhead.enabled, s.overhead.size.max_px = true, 12;
    for _, kind in pairs(s.overhead.types) do kind.cleanse_light = false; end;
end);
h.on('overhead', 'look');
assert(h.says("Its icons are the main page's Icons") and h.called('Button', 'Open Icons##frame'), 'Look still points to Icons.');
MOCK_MKDIR = mkdir;
MOCK.fire('unload');
return 'Open icons folder opens the icons folder from both pages, and Overhead icons point to Icons';
