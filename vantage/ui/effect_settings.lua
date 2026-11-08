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

-- revision, when given, changes whenever an entry changes in place, so the entries aren't walked each frame to find out,
-- and one added or taken off shows in their count. Without one they are compared with what they were.
function editor.selection(entries, selection, revision)
    local query = selection.query:lower();
    local changed = selection.catalog ~= entries or selection.filtered_query ~= query;
    if not changed then
        if revision ~= nil then changed = selection.revision ~= revision or selection.count ~= #entries;
        else changed = not editor.same_catalog(entries, selection.catalog_snapshot); end;
    end;
    if changed then
        local ids, labels, exact = {}, {}, nil;
        for _, effect in ipairs(entries) do
            -- The rows show only names, but typing an effect's number still finds it.
            local number = tostring(effect.id) == query;
            if query == '' or number or effect.name:lower():find(query, 1, true) then ids[#ids + 1], labels[effect.id] = effect.id, effect.name; end;
            if number or effect.name:lower() == query then exact = effect.id; end;
        end;
        selection.catalog, selection.count, selection.filtered_query, selection.revision = entries, #entries, query, revision;
        selection.catalog_snapshot = editor.catalog_snapshot(entries);
        selection.ids, selection.labels, selection.first = ids, labels, exact or ids[1];
    end;
    if not selection.labels[selection.effect] then selection.effect = selection.first; end;
    return selection.effect;
end;

return editor;
