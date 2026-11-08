local assets=require('ui.client_assets');
local function le16(value)return string.char(value%256,math.floor(value/256)%256);end;
local function le32(value)return le16(value%65536)..le16(math.floor(value/65536));end;
local function record(bits,pixels)
    local data=string.rep('\0',0x280)..le32(57+#pixels)..'\145'..string.rep(' ',16)
        ..le32(40)..le32(32)..le32(32)..le16(1)..le16(bits)..string.rep('\0',24)..pixels;
    return data..string.rep('\0',0x1800-#data);
end;
local records,expected={},{};
-- Alpha is doubled when a record peaks at 160 or less: stock art peaks at 128, and eight XI View records at 136.
for _,maximum in ipairs({0,1,64,127,128,129,136,160,161,255})do
    for _,bits in ipairs({8,32})do
        local palette,rows,indices={},{},{};
        for index=0,255 do
            palette[index+1]=string.char(index,255-index,index*17%256,index%2==0 and maximum or math.min(128,maximum));
        end;
        for y=0,31 do
            local source,output={},{};
            for x=0,31 do
                local index=(x+y*32)%256;
                local pixel=palette[index+1];
                source[x+1]=pixel;indices[#indices+1]=string.char(index);
                local alpha=pixel:byte(4);
                output[x+1]=pixel:sub(1,3)..string.char(maximum>0 and maximum<=160 and math.min(255,alpha*2) or alpha);
            end;
            rows[#rows+1]=table.concat(source);expected[#records*32+32-y]=table.concat(output);
        end;
        records[#records+1]=record(bits,bits==32 and table.concat(rows) or table.concat(palette)..table.concat(indices));
    end;
end;
local bytes=table.concat(records);
local fallback=assert(assets.parse_icons(bytes));
local mock_ffi=package.loaded.ffi;
package.loaded.ffi=nil;local real_ffi=require('ffi');
local allocations,copies=0,0;
package.loaded.ffi={
    new=function(kind)assert(kind=='uint8_t[4096]');allocations=allocations+1;return real_ffi.new(kind);end,
    cast=real_ffi.cast,string=real_ffi.string,
    copy=function(...)copies=copies+1;return real_ffi.copy(...);end,
};
local accelerated=assert(assets.parse_icons(bytes));
assert(allocations==0 and copies==0,'Parsing a pack checks each record\'s header and makes no pixels.');
assert(accelerated.count==20 and accelerated.valid==20 and fallback.valid==20);
for id=0,19 do
    local pixels={};for row=1,32 do pixels[row]=expected[id*32+row];end;
    assert(accelerated.records[id].dds==fallback.records[id].dds,'Accelerated and portable conversion agree byte for byte.');
    assert(accelerated.records[id].dds:sub(129)==table.concat(pixels),'Rows, palette colors and source alpha retain their exact meaning.');
end;
assert(allocations==1 and copies>0,'A whole status pack uses one bounded scratch buffer, made with its first icon.');
local made=copies;
assert(accelerated.records[3]==accelerated.records[3] and copies==made,'A record is made once.');
-- Only whole records count: a cut record at the end and any past the 1024th are left out. A file too short for one
-- record, or past the size limit, is refused.
for _,case in ipairs({{bytes:sub(1,-2),19},{bytes..'x',20},{bytes..string.rep('\0',0x1800*1004+5),1024}})do
    local before=allocations;
    local parsed=assert(assets.parse_icons(case[1]));
    assert(parsed.count==case[2] and parsed.valid==math.min(case[2],20) and allocations==before,
        'Whole records count, and nothing is made yet: '..case[2]);
    local last=math.min(case[2],20)-1;
    assert(parsed.records[case[2]]==nil and parsed.records[last].dds==fallback.records[last].dds,
        'Nothing past the whole records, and the last whole one draws: '..case[2]);
end;
for _,invalid in ipairs({'',bytes:sub(1,0x17FF),string.rep('\0',16*1024*1024+1)})do
    local before=allocations;assert(not assets.parse_icons(invalid));assert(allocations==before,'Invalid container bounds are checked before native scratch allocation.');
end;
local invalid=records[1]:sub(1,0x2A3)..le16(24)..records[1]:sub(0x2A6);
local parsed=assert(assets.parse_icons(records[2]..invalid..records[3]));
assert(parsed.valid==2 and parsed.errors[1] and parsed.records[0].dds==fallback.records[1].dds
    and parsed.records[2].dds==fallback.records[2].dds,'Malformed neighbors cannot reuse or corrupt the scratch pixels.');
local unused_palette=string.char(10,20,30,128)..string.rep('\255',255*4);
local used=assert(assets.parse_icons(record(8,unused_palette..string.rep('\0',1024))));
assert(used.records[0].dds:sub(129)==string.rep(string.char(10,20,30,255),1024),
    'Unused palette alpha cannot change the range of the displayed pixels.');
local function replace(data,offset,value)return data:sub(1,offset)..value..data:sub(offset+#value+1);end;
for _,bad in ipairs({
    replace(records[1],0x280,le32(9999)),replace(records[1],0x284,'\0'),replace(records[1],0x295,le32(108)),
    replace(records[1],0x299,le32(512)),replace(records[1],0x29D,le32(0xFFFFFFE0)),
    replace(records[1],0x2A1,le16(2)),replace(records[1],0x2A3,le16(24)),replace(records[1],0x2A5,le32(1)),
})do
    local unsupported=assert(assets.parse_icons(bad));
    assert(unsupported.valid==0 and unsupported.errors[0] and not unsupported.records[0],
        'Native conversion keeps each bitmap-header rejection.');
end;
package.loaded.ffi=mock_ffi;
