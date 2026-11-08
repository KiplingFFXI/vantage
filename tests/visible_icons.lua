-- The icons the last frame left wholly in sight: inside the window they were drawn in and every clip rect pushed over
-- them, as MOCK.imgui_calls has them. want(texture) picks the icons that count. Each comes back as { texture, x, y,
-- window }, in the order drawn, window being the name of the window it was drawn in.
return function(want)
    local found, stack, position, size, window = {}, {}, nil, nil, nil;
    local open = {-1e9, -1e9, 1e9, 1e9};
    for _, call in ipairs(MOCK.imgui_calls) do
        local name = call[1];
        if name == 'SetNextWindowPos' then position = call[2];
        elseif name == 'SetNextWindowSize' then size = call[2];
        elseif name == 'Begin' then
            stack = {position and size and {position[1], position[2], position[1] + size[1], position[2] + size[2]} or open};
            position, size, window = nil, nil, call[2];
        elseif name == 'End' then stack, window = {}, nil;
        elseif name == 'draw:PushClipRect' then
            local drawn, top = MOCK.drawn[call], stack[#stack] or open;
            local a, b = drawn[2], drawn[3];
            local clip = {a[1], a[2], b[1], b[2]};
            if call[4] then clip = {math.max(clip[1], top[1]), math.max(clip[2], top[2]), math.min(clip[3], top[3]), math.min(clip[4], top[4])}; end;
            stack[#stack + 1] = clip;
        elseif name == 'draw:PopClipRect' then stack[#stack] = nil;
        elseif name == 'draw:AddImage' and want(call[2]) then
            local drawn, top = MOCK.drawn[call], stack[#stack] or open;
            local a, b = drawn[3], drawn[4];
            if a[1] >= top[1] and a[2] >= top[2] and b[1] <= top[3] and b[2] <= top[4] then
                found[#found + 1] = {texture=call[2], x=a[1], y=a[2], window=window};
            end;
        end;
    end;
    return found;
end;
