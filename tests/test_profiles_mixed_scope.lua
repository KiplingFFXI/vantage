-- Three characters share the layout: A and C in presentation scope, B in placement scope. A changes the font
-- and publishes; before C polls, B moves a panel and publishes. B's publish keeps the shared appearance (with
-- B's move over it), so C's poll still brings A's font and C's own later publish doesn't put an older font back.
local store=require('core.store');
local profiles=require('core.profiles');
local defaults=require('ui.defaults');
local root=MOCK_INSTALL_PATH..'/config/addons/vantage';
local function character(scope)
    local s=defaults.tidy(defaults.make());s.shared_layout,s.shared_scope=true,scope;
    return {settings=s,store=profiles.new(root),base=nil};
end
local function publish(c)
    local ok,why,shared=c.store:publish_layout(c.settings,c.base);assert(ok,why);c.base=shared;
end
local function poll(c)
    local layout,err,unchanged=c.store:read_layout();assert(layout,err);
    if unchanged then return false; end
    local ok,why,found,changed=c.store:load_layout(c.settings,nil,layout);assert(ok,why);
    c.base=profiles.capture_layout(c.settings);
    return changed;
end
local A,B,C=character('presentation'),character('placement'),character('presentation');
A.settings.style.font_size=24;publish(A);
local ok,why,found=B.store:load_layout(B.settings);assert(ok and found);B.base=profiles.capture_layout(B.settings);
ok,why,found=C.store:load_layout(C.settings);assert(ok and found);C.base=profiles.capture_layout(C.settings);
assert(C.settings.style.font_size==24,'Fixture: C joined with A\'s font.');
A.settings.style.font_size=25;publish(A);
B.settings.panels.self_buffs.x=B.settings.panels.self_buffs.x+40;publish(B);
local file=assert(store.read(root..'/shared_layout.json'));
assert(file.scope=='presentation' and type(file.presentation)=='table' and file.presentation.style.font_size==25,
    'A placement publish over a presentation file keeps its appearance: scope '..tostring(file.scope)..'.');
assert(file.presentation.panels.self_buffs.x==B.settings.panels.self_buffs.x,'B\'s move is in the file.');
poll(C);poll(C);
assert(C.settings.panels.self_buffs.x==B.settings.panels.self_buffs.x,'C takes B\'s move.');
assert(C.settings.style.font_size==25,'C takes A\'s font change published before B\'s move: '..C.settings.style.font_size..'.');
C.settings.panels.self_debuffs.x=C.settings.panels.self_debuffs.x+40;publish(C);
poll(A);
assert(A.settings.style.font_size==25,'A keeps its own font after C publishes a move: '..A.settings.style.font_size..'.');
poll(B);
assert(B.settings.panels.self_debuffs.x==C.settings.panels.self_debuffs.x and B.settings.style.font_size~=25,
    'B takes C\'s move and keeps its own appearance.');
