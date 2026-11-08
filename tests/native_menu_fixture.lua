return function(memory, container, primitive, group)
    memory[0x12020], memory[0x12078] = 0x21000, 0x21100;
    memory[0x21000], memory[0x21100] = 0, 0;
    local header = 0x90000 + group * 0x100;
    local names = { { 0x74726170, 0x6E697779 }, { 0x64696172, 0x20202031 }, { 0x64696172, 0x20202032 } };
    memory[primitive + 4] = header;
    memory[header + 0x46], memory[header + 0x4A] = 0x756E656D, 0x20202020;
    memory[header + 0x4E], memory[header + 0x52] = names[group][1], names[group][2];
    memory[container + 0x3A], memory[container + 0x3B], memory[container + 0x40] = 255, 255, 0;
    return header;
end;
