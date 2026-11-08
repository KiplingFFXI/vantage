-- The chat log moves only when the player moves it, so a refresh reads its place about once a second, and at once
-- when the screen size changed or the last read failed. Between reads each snapshot keeps the last one.
local chat = require('core.chat');
local reads, result = 0, nil;
chat.read = function() reads = reads + 1; return result, result == nil and 'Fixture: not ready yet.' or nil; end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.now = 1; app.refresh(1);
assert(reads == 1 and app.state.snapshot.chat == nil and app.state.snapshot.chat_area, 'Fixture: the first read failed.');
result = { x = 0, y = 600, width = 500, height = 200, windows = {} };
app.refresh(1.1);
assert(reads == 2 and app.state.snapshot.chat == result, 'After a failed read the next refresh reads again.');
local area = app.state.snapshot.chat_area;
app.refresh(1.2); app.refresh(2.05);
assert(reads == 2 and app.state.snapshot.chat == result and app.state.snapshot.chat_area == area,
    'Within a second each refresh keeps the last read.');
app.refresh(2.15);
assert(reads == 3, 'A second on, it is read again.');
MOCK.screen = { 1920, 1080 };
app.refresh(2.25);
assert(reads == 4, 'A new screen size reads it at once.');
app.refresh(2.35);
assert(reads == 4, 'And then it waits again.');
MOCK.screen = nil;
assert(#MOCK.commands == 0);
