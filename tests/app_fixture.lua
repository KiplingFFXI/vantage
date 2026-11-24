-- The headless app's stand-ins, put in before a test loads vantage.lua: the client reads a copy of snapshot each
-- refresh, the observer sees nothing, and ui.hud, ui.party_hud and ui.native_party_hud draw nothing.
return function(snapshot)
    local store = require('core.store');
    package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
    package.loaded['core.observer'] = { read = function() return {}; end };
    local hud = require('ui.hud');
    hud.draw, hud.draw_notices = function() end, function() end;
    require('ui.party_hud').draw = function() return 0, {}; end;
    require('ui.native_party_hud').draw = function() return 0, {}; end;
end
