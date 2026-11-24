local editor = {};

local function contains(values, id)
    for _, value in ipairs(values) do if value == id then return true; end; end;
    return false;
end;
editor.contains = contains;

local function membership(values, id, enabled)
    for index = #values, 1, -1 do if values[index] == id then table.remove(values, index); end; end;
    if enabled then values[#values + 1] = id; end;
end;
editor.membership = membership;

function editor.same_catalog(entries, saved)
    if not saved or #entries ~= #saved then return false; end;
    for index, entry in ipairs(entries) do
        local previous = saved[index];
        if entry.id ~= previous.id or entry.name ~= previous.name or entry.kind ~= previous.kind then return false; end;
    end;
    return true;
end;

function editor.catalog_snapshot(entries)
    local snapshot = {};
    for index, entry in ipairs(entries) do snapshot[index] = {id=entry.id, name=entry.name, kind=entry.kind}; end;
    return snapshot;
end;

-- The effect picked from entries, or nil. selection keeps the pick, in effect, and the entries' names by id, in labels.
-- revision, when given, changes whenever an entry changes in place, so the entries aren't walked each frame to find out,
-- and one added or taken off shows in their count. Without one they are compared with what they were.
function editor.selection(entries, selection, revision)
    local changed = selection.catalog ~= entries;
    if not changed then
        if revision ~= nil then changed = selection.revision ~= revision or selection.count ~= #entries;
        else changed = not editor.same_catalog(entries, selection.catalog_snapshot); end;
    end;
    if changed then
        local labels = {};
        for _, effect in ipairs(entries) do labels[effect.id] = effect.name; end;
        selection.catalog, selection.count, selection.revision = entries, #entries, revision;
        selection.catalog_snapshot = editor.catalog_snapshot(entries);
        selection.labels = labels;
    end;
    -- Nothing is chosen until one is picked, and one the list no longer has is let go.
    if selection.effect ~= nil and not selection.labels[selection.effect] then selection.effect = nil; end;
    return selection.effect;
end;

return editor;
