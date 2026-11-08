-- Keeps ImGui's stacks balanced when a display fails partway. install puts a counting wrapper on imgui's own
-- table for each call that opens or closes a scope, so every module that looks them up there is counted. A
-- Present that fails closes, newest first, what it opened and didn't close, the settings window's pages
-- included, and Ashita's frame ends as it began. Clip rects pushed on a window's own draw list need nothing:
-- the window's next Begin starts its list again.
local scopes = {};
-- What each scope is closed with. Begin and BeginChild need their end whatever they return.
local ends = { Begin = 'End', BeginChild = 'EndChild', BeginDisabled = 'EndDisabled', BeginGroup = 'EndGroup',
    PushID = 'PopID', PushFont = 'PopFont', PushStyleColor = 'PopStyleColor', PushStyleVar = 'PopStyleVar',
    PushTextWrapPos = 'PopTextWrapPos', PushItemWidth = 'PopItemWidth', PushClipRect = 'PopClipRect' };
-- These need their end only when they open.
local shown = { BeginTooltip = 'EndTooltip', BeginCombo = 'EndCombo', BeginTable = 'EndTable',
    BeginPopup = 'EndPopup', BeginMenu = 'EndMenu' };
local counted = { PopStyleColor = true, PopStyleVar = true };
local open, depth, originals, installed = {}, 0, {}, nil;

local function lookup(real, name) return real[name]; end

local function opened(finish, ...)
    depth = depth + 1;
    open[depth] = finish;
    return ...;
end

local function opened_if(finish, visible, ...)
    if visible then opened(finish); end
    return visible, ...;
end

-- Removes from the list the newest count scopes that finish closes.
local function closed(finish, count)
    local index = depth;
    while count > 0 and index > 0 do
        if open[index] == finish then
            table.remove(open, index);
            depth, count = depth - 1, count - 1;
        end
        index = index - 1;
    end
end

-- Wraps each scope call imgui binds, once for its table.
function scopes.install(imgui)
    if installed == imgui then return; end
    installed, originals = imgui, {};
    for _, list in ipairs({ ends, shown }) do
        for name, finish in pairs(list) do
            local ok, begin = pcall(lookup, imgui, name);
            local done, close = pcall(lookup, imgui, finish);
            if ok and type(begin) == 'function' and done and type(close) == 'function' then
                originals[finish] = close;
                if list == ends then rawset(imgui, name, function(...) return opened(finish, begin(...)); end);
                else rawset(imgui, name, function(...) return opened_if(finish, begin(...)); end); end
                if not rawget(imgui, finish) or rawget(imgui, finish) == close then
                    rawset(imgui, finish, function(...)
                        local count = counted[finish] and tonumber((...)) or 1;
                        closed(finish, count);
                        return close(...);
                    end);
                end
            end
        end
    end
end

-- How many scopes are open now: a mark for close.
function scopes.depth()
    return depth;
end

-- Closes, newest first, every scope opened since mark. Each close runs on its own, so one that fails
-- doesn't keep the rest open.
function scopes.close(mark)
    mark = mark or 0;
    while depth > mark do
        local finish = open[depth];
        open[depth], depth = nil, depth - 1;
        local close = originals[finish];
        if close and counted[finish] then pcall(close, 1); elseif close then pcall(close); end
    end
end

return scopes;
