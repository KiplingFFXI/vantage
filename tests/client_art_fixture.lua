-- Client art from the installed game for benchmarks and the draw digest: the real parsers read the DATs (read
-- only) and uploads only hand out texture ids. Needs ASHITA_LIBS; call it before anything draws.
return function()
    -- Two folders up from addons/libs, whatever its case or slashes.
    local ashita_root = ASHITA_LIBS:gsub('\\', '/'):gsub('/+$', ''):gsub('/[^/]+/[^/]+$', '');
    local game_root = ashita_root .. '/SquareEnix/FINAL FANTASY XI';
    local next_id = 100;
    require('ui.client_assets')._set_platform_for_tests({
        game_root = function() return game_root; end,
        ashita_root = function() return ashita_root; end,
        read = function(path, maximum)
            local file = io.open(path, 'rb');
            if not file then return nil, 'missing'; end;
            local data = file:read(maximum + 1);
            file:close();
            if data and #data > maximum then return nil, 'too big'; end;
            return data;
        end,
        upload = function() next_id = next_id + 1; return { id = next_id, release = function() end }; end,
    });
    local function loader() next_id = next_id + 1; return next_id, function() end; end;
    require('ui.icons')._set_loader_for_tests(loader);
    require('ui.item_icons')._set_loader_for_tests(loader);
    return game_root;
end;
