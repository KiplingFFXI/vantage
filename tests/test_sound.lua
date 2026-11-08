local sound = require('core.sound');
MOCK.dirs = { [sound.FOLDER] = { 'Warning.wav', 'soft.MP3', 'SOFT.mp3', '../bad.wav', 'bad".wav', 'text.txt' } };
local files = sound.refresh();
assert(#files == 2 and files[1] == 'soft.MP3' and files[2] == 'Warning.wav');
files[1] = 'Changed'; assert(sound.files()[1] == 'soft.MP3');
assert(not sound.play(70));
assert(not sound.use('../bad.wav'));
assert(not sound.use('missing.wav'));
MOCK.fs[sound.FOLDER .. 'Warning.wav'] = true;
assert(sound.use('Warning.wav'));
assert(sound.play(65));
-- Each sound has its own numbered alias; the first one opened is vantage_alert1.
assert(MOCK.mci[#MOCK.mci] == 'play vantage_alert1 from 0');
assert(MOCK.mci[#MOCK.mci - 1] == 'setaudio vantage_alert1 volume to 650');
assert(sound.play(200));
assert(MOCK.mci[#MOCK.mci - 1] == 'setaudio vantage_alert1 volume to 1000');
MOCK.mci_code = function(command) return command:match('^play ') and 1 or 0; end;
assert(not sound.play(70));
assert(sound.problem('Warning.wav') ~= nil and not sound.is_open('Warning.wav'));
local calls = #MOCK.mci;
assert(not sound.use('Warning.wav') and #MOCK.mci == calls);
MOCK.mci_code = nil;
assert(sound.use('Warning.wav', true));
assert(sound.use('') and sound.problem() == nil);
assert(not sound.is_open('Warning.wav'));
MOCK.mci_code = function(command) return command:match('^open ') and 1 or 0; end;
assert(not sound.use('Warning.wav'));
MOCK.mci_code = nil;
sound.refresh();
assert(sound.use('Warning.wav'), 'Explicit file refresh must allow retrying a repaired local sound.');

-- A sound stays open once it has played, so switching between two sounds only plays them.
MOCK.fs[sound.FOLDER .. 'soft.MP3'] = true;
assert(sound.play(70) and sound.use('soft.MP3') and sound.play(70));
MOCK.mci = {};
for _ = 1, 3 do assert(sound.use('Warning.wav') and sound.play(70) and sound.use('soft.MP3') and sound.play(70)); end
assert(#MOCK.mci == 6, 'Switching sounds sends one command per play.');
for _, command in ipairs(MOCK.mci) do
    assert(command:match('^play vantage_alert%d from 0$'), 'Switching sounds opens and closes nothing: ' .. command);
end
assert(MOCK.mci[1] ~= MOCK.mci[2] and MOCK.mci[1] == MOCK.mci[3], 'Each sound plays on its own alias.');

-- At most 8 sounds stay open. Another one closes the sound played longest ago and takes its alias.
for i = 1, 7 do MOCK.fs[sound.FOLDER .. 'extra' .. i .. '.wav'] = true; end
for i = 1, 6 do assert(sound.use('extra' .. i .. '.wav') and sound.play(70)); end
assert(sound.use('Warning.wav') and sound.play(70));
MOCK.mci = {};
assert(sound.use('extra7.wav') and sound.play(70));
local closes = {};
for _, command in ipairs(MOCK.mci) do if command:match('^close ') then closes[#closes + 1] = command; end end
assert(#closes == 1 and closes[1] == 'close vantage_alert2', 'Only the sound played longest ago is closed.');
assert(MOCK.mci[2] and MOCK.mci[2]:match('alias vantage_alert2$'), 'The new sound takes the freed alias.');
assert(not sound.is_open('soft.MP3') and sound.is_open('Warning.wav') and sound.is_open('extra7.wav'));
for i = 1, 6 do assert(sound.is_open('extra' .. i .. '.wav')); end

-- A sound that fails leaves the other open sounds alone.
MOCK.mci = {};
assert(not sound.use('missing2.wav'));
assert(#MOCK.mci == 0 and sound.is_open('Warning.wav') and sound.problem('missing2.wav') and not sound.problem('Warning.wav'),
    'A failed sound closes nothing else.');
assert(sound.use('Warning.wav') and sound.play(70), 'Another sound still plays after one fails.');

-- Closing closes every open sound.
MOCK.mci = {};
sound.close();
assert(#MOCK.mci == 8, 'Close closes all 8 aliases.');
for _, command in ipairs(MOCK.mci) do assert(command:match('^close vantage_alert%d$')); end
assert(not sound.is_open('Warning.wav') and not sound.is_open('extra7.wav') and not sound.play(70));
return true;
