-- The panel rows keep their word: what a part's Divider before it box takes, the save keeps, and a color row's search
-- words offer going back to the normal color only where the row has that button. An effect's color goes back through
-- the Colored list instead.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local panels = h.panels;

local rows = {};
local function walk(list)
    for _, item in ipairs(list) do
        rows[#rows + 1] = item;
        if item.rows then walk(item.rows); end;
    end;
end;
panels.index({});
for _, display in ipairs(panels._displays) do
    for _, list in pairs(display.tabs) do walk(list); end;
end;
local function row(find)
    for _, item in ipairs(rows) do if item.find == find then return item; end; end;
end;

local divider = assert(row('Divider before it'), 'Fixture: the part rows are on the frame.');
local s = defaults.tidy(defaults.make());
s.panels.self_buffs.field_dividers.name = string.rep('-', divider.length - 1);
local kept = defaults.tidy(s).panels.self_buffs.field_dividers.name;
assert(#kept == divider.length - 1, 'Divider before it takes no more than the save keeps: ' .. (divider.length - 1) .. ' typed, ' .. #kept .. ' kept.');

assert(row('Effect color') and row('Recast color') and row('Part color'), 'Fixture: the color rows are on the frame.');
for _, item in ipairs(rows) do
    if item.kind == 'color' and item.words:find('Use normal', 1, true) then
        assert(item.back, 'A color row offers going back only with the button for it: ' .. item.find);
    end;
end;
