-- The shared layout poll: an unchanged file keeps the profile summary, a newer one is drawn in the Present that
-- reads it, and load_layout says when nothing changed so the summary and undo history stay as they are.
-- Real vantage.lua and core/profiles.lua; the client readers, the timer panels and the settings window are fixtures.
local store=require('core.store');
local defaults=require('ui.defaults');
local profiles=require('core.profiles');
local copy=store.copy;
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={{effect=33,slot=0}},party={},entities={}};
local seen={};
package.loaded['core.client']={load=function()end,read=function()return copy(snapshot);end,visibility=function()return copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
package.loaded['ui.hud']={draw=function(_,settings)seen.hud=settings.panels.self_buffs.x;end,
    draw_notices=function()end,cancel_gesture=function()end};
package.loaded['ui.settings_window']={draw=function()end,blocks_input=function()return false;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
local settings=app.state.settings;
settings.enabled=true;
settings.party_ui.enabled=false;
local function present()MOCK.frame(.011);end;
present();

settings.shared_layout,settings.shared_scope=true,'placement';
local shared=profiles.new(MOCK_INSTALL_PATH..'/config/addons/vantage');
assert(shared:save_layout(settings));
app.state.dirty,app.state.shared_at=false,MOCK.now-3;
present();
assert(app.state.shared_at==MOCK.now,'An unchanged shared layout is polled.');
local summary=app.callbacks.profile_summary();
for _=1,3 do
    app.state.shared_at=MOCK.now-3;present();
    assert(app.state.profile_summary_cache and app.state.profile_summary_cache.value==summary,
        'An unchanged shared layout keeps the profile summary.');
end;
local moved=copy(settings);moved.panels.self_buffs.x=settings.panels.self_buffs.x+50;assert(shared:save_layout(moved));
app.state.shared_at=MOCK.now-3;present();
assert(settings.panels.self_buffs.x==moved.panels.self_buffs.x and seen.hud==moved.panels.self_buffs.x,
    'A newer shared layout is drawn in the same Present.');
settings.shared_layout=false;

for _,scope in ipairs({'placement','presentation'})do
    local source=defaults.tidy(defaults.make());source.panels.self_buffs.x=321;source.style.font_size=19;
    assert(shared:save_layout(source,scope));
    local receiver=copy(source);
    local style,panel,party=receiver.style,receiver.panels.self_buffs,receiver.party_ui;
    local ok,_,found,changed=shared:load_layout(receiver,scope);
    assert(ok and found and changed==false,'An unchanged shared layout reports no change: '..scope);
    assert(receiver.style==style and receiver.panels.self_buffs==panel and receiver.party_ui==party,
        'An unchanged shared layout leaves every settings table in place: '..scope);
    assert(store.equal(profiles.capture_layout(receiver,scope),profiles.capture_layout(source,scope)));
    receiver.panels.self_buffs.x=111;
    ok,_,found,changed=shared:load_layout(receiver,scope);
    assert(ok and found and changed==true and receiver.panels.self_buffs.x==321,'A different shared layout still applies: '..scope);
end;
assert(#MOCK.commands==0);
