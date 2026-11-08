local wrap, fields = require('ui.text_wrap'), require('ui.fields');
local measure = function(value) return #value; end;
assert(table.concat(wrap.lines('alpha beta gamma', 10, measure), '|') == 'alpha beta|gamma');
assert(table.concat(wrap.lines('abcdefghijklmnop', 5, measure), '|') == 'abcde|fghij|klmno|p');
assert(table.concat(wrap.lines('a\n\nb\r\nc', 20, measure), '|') == 'a||b|c');
local glyph = string.char(0xE3,0x81,0x82);
local lines = wrap.lines(glyph:rep(5), 6, measure);
assert(#lines == 3 and lines[1] == glyph:rep(2) and lines[3] == glyph);
assert(wrap.lines(glyph, 1, measure)[1] == glyph, 'A glyph is never split across byte boundaries.');
local red, green = {1,0,0,1}, {0,1,0,1};
local entry = {id='name',size=10,color=red,text='abcdefghijklmnop next',alignment='left',
    runs={{text='abcdefghijklmnop ',size=10,color=red},{text='next',size=12,color=green}}};
local result = fields.lines({entry,{id='time',text='20s',size=10,alignment='right'}}, 5, {wrap=true,separator=' '},measure);
local joined='';
for _,line in ipairs(result) do
    for _,part in ipairs(line) do
        assert(fields.width(part,measure)<=5);
        joined=joined..part.text:gsub('%s','');
        for _,run in ipairs(part.runs or {}) do assert(run.color == red or run.color == green); end;
    end;
    for _,position in ipairs(fields.positions(line,5,' ',measure)) do
        assert(position.x>=0 and position.x+position.width<=5);
        assert(position.width == fields.width(position.entry,measure),'Wrapped fields retain their complete visible width.');
    end;
end;
assert(joined=='abcdefghijklmnopnext20s','Wrapping loses no characters.');
assert(entry.text=='abcdefghijklmnop next' and entry.runs[1].text=='abcdefghijklmnop ', 'Wrapping preserves saved fields.');
