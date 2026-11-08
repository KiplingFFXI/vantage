-- Vantage ships its own strict json.lua as core.json, which settings and profiles are read with. tests/run.py
-- preloads the same file as json, ahead of the game folder's copy.
-- It refuses trailing commas, leading zeros and lone surrogates; the game folder's copy reads them.
for _,json in ipairs({require('core.json'),require('json')})do
    for _,text in ipairs({'[1,]','{"a":1,}','01','"\\uD800"'})do
        assert(not pcall(json.decode,text),'The fixtures decode with the strict json.lua, which refuses '..text);
    end;
    assert(json.decode('{"a":[1,2]}').a[2]==2,'The strict json.lua reads ordinary JSON.');
end;
-- Settings files are read with it, so a hand-edited file with a trailing comma is not taken for settings.
local store=require('core.store');
local path=MOCK_INSTALL_PATH..'/config/addons/vantage/strict.json';
local file=assert(io.open(path,'wb'));file:write('{"enabled":true,}');file:close();
assert(store.read(path)==nil,'A settings file the strict json.lua refuses is not read.');
file=assert(io.open(path,'wb'));file:write('{"enabled":true}');file:close();
assert(store.read(path).enabled==true,'An ordinary settings file reads.');
-- Every kind of escape in a string reads as its character, and a string's pieces are joined once at the end: joining
-- them one at a time copied the whole string so far at every escape, so an export full of them stopped the game for
-- most of a second.
local strict=require('core.json');
assert(strict.decode('"a\\nb\\"c\\\\d\\/e\\u00e9f\\uD83D\\uDE00g\\t"')=='a\nb"c\\d/e\195\169f\240\159\152\128g\t',
    'Every kind of escape reads as its character.');
assert(strict.decode('"\\n"')=='\n' and strict.decode('""')=='' and strict.decode('"plain"')=='plain' and strict.decode('"x\\n"')=='x\n',
    'A string that is only an escape, empty, plain or ends in an escape reads too.');
local count=4000;
local escapes='"'..('\\n'):rep(count)..'"';
collectgarbage('collect');collectgarbage('stop');
local before=collectgarbage('count');
local read=strict.decode(escapes);
local grown=collectgarbage('count')-before;
collectgarbage('restart');
assert(read==('\n'):rep(count),'A string of '..count..' escapes reads as '..count..' line breaks.');
assert(grown<1024,'Reading it takes memory by its length, not by the square of it: '..math.floor(grown)..' KB.');
