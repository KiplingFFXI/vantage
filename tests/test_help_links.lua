-- The Help page's guide links. Each section ends with a button that copies the link to a heading the guide has, and
-- the window says it did.
local h = require('panel_fixture')();
local window = h.window;
local file = assert(io.open(ADDON_DIR .. '/../docs/GUIDE.md', 'rb'));
local guide = file:read('*a');
file:close();
-- A heading's anchor as GitHub makes it: lower case, no punctuation, a dash for each space.
local anchors = {};
for heading in ('\n' .. guide):gmatch('\n#+ ([^\n]+)') do
    local anchor = heading:lower():gsub('[^%w%s%-]', ''):gsub('%s', '-');
    anchors[anchor] = true;
end;
local count = 0;
for anchor in pairs(window.guide_topics) do
    count = count + 1;
    assert(anchors[anchor], 'The guide has a heading for the link: ' .. anchor);
end;
assert(count == 6, 'Six topics link to the guide: ' .. count);

-- Each section on the page has its link, and a click copies it.
h.fresh();
h.s.window.tab = 'Help';
for _, name in ipairs({ 'Getting started', 'Reading a timer', 'What can be tracked', 'Alerts', 'Move and customize', 'Files and behavior', 'Troubleshoot' }) do
    h.s.window.sections['Help/' .. name] = true;
end;
h.draw();
for anchor in pairs(window.guide_topics) do
    assert(h.called('Button', 'Copy the guide link##guide_' .. anchor), 'Help links to ' .. anchor);
end;
h.draw('Copy the guide link##guide_read-a-timer');
h.draw();
assert(MOCK.clipboard == addon.link .. '/blob/main/docs/GUIDE.md#read-a-timer', 'It copies the link: ' .. tostring(MOCK.clipboard));
assert(h.says('Copied the link to Read a timer in the guide.'), 'It says so.');
-- The links aren't settings, so the search leaves them out.
assert(not require('ui.search_index').controls.Help or not require('ui.search_index').controls.Help['Copy the guide link'], 'The search leaves the links out.');
MOCK.fire('unload');
return 'Each Help section links to its topic in the guide';
