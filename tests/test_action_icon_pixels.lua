local assets=require('ui.client_assets');
local convert=assets._action_dds_for_tests;
local function le16(value)return string.char(value%256,math.floor(value/256)%256);end;
local alphas={};for index=0,7 do alphas[index+1]=string.char(index*2+(index*2+1)*16);end;
local cases={
    {0xF800,0x07E0,{{0,0,255},{0,255,0},{0,85,170},{0,170,85}}},
    {0x07E0,0xF800,{{0,255,0},{0,0,255},{0,170,85},{0,85,170}}},
    {3*2048+7*32+11,21*2048+33*32+29,{{90,28,24},{239,134,173},{139,63,73},{189,98,123}}},
};
local inputs,expected,portable={},{},{};
for _,case in ipairs(cases)do
    local block=table.concat(alphas)..le16(case[1])..le16(case[2])..string.rep('\228',4);
    for _,size in ipairs({{1,1},{3,2},{7,5},{8,8}})do
        local width,height=size[1],size[2];
        local raw={format='DXT3',width=width,height=height,
            dds=string.rep('\0',128)..string.rep(block,math.ceil(width/4)*math.ceil(height/4))};
        for _,alpha in ipairs({0,1,64,127,128,192,255})do
            local output={};
            for y=0,height-1 do for x=0,width-1 do
                local color=case[3][x%4+1];
                local effective=math.min(255,math.floor(((y%4)*4+x%4)*17*alpha*2/255+0.5));
                output[#output+1]=string.char(color[1],color[2],color[3],effective);
            end end;
            inputs[#inputs+1]={raw,alpha};expected[#expected+1]=table.concat(output);
            portable[#portable+1]=assert(convert(raw,alpha));
        end;
    end;
end;
local mock_ffi=package.loaded.ffi;
package.loaded.ffi=nil;local real_ffi=require('ffi');
local allocations=0;
package.loaded.ffi={abi=real_ffi.abi,string=real_ffi.string,new=function(kind,count)
    assert(kind=='uint32_t[?]' and count>=1 and count<=1024*1024);
    allocations=allocations+1;return real_ffi.new(kind,count);
end};
for index,input in ipairs(inputs)do
    local output=assert(convert(input[1],input[2]));
    assert(output==portable[index],'Portable and native output keep the same DDS header and pixels.');
    assert(output:sub(129)==expected[index],'Four-color DXT3 selectors, RGB565 expansion, clipping and all sixteen alpha levels match independent expected pixels.');
end;
assert(allocations==#inputs,'Each conversion uses one bounded pixel buffer.');
local valid=inputs[1][1];
local invalid={false,{},
    {format='DXT1',width=1,height=1,dds=valid.dds},
    {format='DXT3',width=0,height=1,dds=valid.dds},
    {format='DXT3',width=1,height=-1,dds=valid.dds},
    {format='DXT3',width=1.5,height=1,dds=valid.dds},
    {format='DXT3',width=0/0,height=1,dds=valid.dds},
    {format='DXT3',width=1,height=math.huge,dds=valid.dds},
    {format='DXT3',width=2049,height=1,dds=valid.dds},
    {format='DXT3',width=2048,height=2048,dds=valid.dds},
    {format='DXT3',width='1',height=1,dds=valid.dds},
    {format='DXT3',width=1,height=1,dds=false},
    {format='DXT3',width=1,height=1,dds=valid.dds:sub(1,-2)},
    {format='DXT3',width=1,height=1,dds=valid.dds..'x'},
};
local before=allocations;
assert(not convert(nil,192));
for _,raw in ipairs(invalid)do assert(not convert(raw,192),'Invalid dimensions, format and payload lengths stop before pointer access.');end;
for _,alpha in ipairs({-1,256,1.5,0/0,math.huge,'192',false})do assert(not convert(valid,alpha));end;
assert(not convert(valid,nil) and allocations==before,'Invalid inputs cannot allocate or enter native conversion.');
package.loaded.ffi=mock_ffi;
