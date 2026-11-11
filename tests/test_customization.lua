local defaults=require('ui.defaults');
local custom=require('core.customization');
local s=defaults.make();
s.panels.self_buffs.labels[33]='My haste';
s.panels.self_buffs.include[33]=true;
s.panels.self_buffs.width=480;
s.alerts.rules={defaults.rule('keep')};
s.style.font_size=22;
local original=defaults.copy(s);
assert(custom.reset(s,'appearance')==s);
assert(s.style.font_size==16 and s.panels.self_buffs.labels[33]=='My haste' and #s.alerts.rules==1,
    'Appearance reset preserves effect selections and rules.');
assert(custom.reset(s,'panels')==s and s.panels.self_buffs.width==300);
assert(s.panels.self_buffs.labels[33]=='My haste' and s.panels.self_buffs.include[33],
    'Layout reset preserves each panel filter and custom effect label.');
local before=defaults.copy(s);
local map_path=MOCK_INSTALL_PATH..'/config/addons/vantage/sparse.json';
assert(require('core.store').write(map_path,s), 'Effect-keyed maps must be writable as valid JSON.');
local reloaded=defaults.tidy(assert(require('core.store').read(map_path)));
assert(reloaded.panels.self_buffs.labels[33]=='My haste' and reloaded.panels.self_buffs.include[33],
    'Sparse labels and include filters survive a real JSON file round trip.');
assert(custom.reset(s,'typo')==nil and custom.equal(s,before), 'An unknown reset cannot reset everything.');
local changed=assert(custom.set(s,'style.font_size','24'));
assert(changed.style.font_size==24 and s.style.font_size==16);
assert(custom.set(s,'style.font_size','9999')==nil and custom.set(s,'style.font_size','nan')==nil);
assert(custom.set(s,'panels.self_buffs.mode','typo')==nil);
assert(custom.set(s,'style.text_shadow','off').style.text_shadow==false);
assert(custom.set(s,'style.text_color','FF000080').style.text_color[4]==128/255);
assert(custom.set(s,'panels.self_buffs.labels','{"33":"Quick haste"}').panels.self_buffs.labels[33]=='Quick haste');
assert(custom.set(s,'watch_ids','[999]')==nil, 'Generic settings edits cannot inject gameplay identities.');
assert(custom.set(s,'style..font','Arial')==nil and custom.set(s,'unknown','x')==nil);
local extra=defaults.copy(s); extra.panels.future_panel={zz_newer=1};
local function future(settings) return type(settings.panels.future_panel)=='table' and settings.panels.future_panel.zz_newer==1; end
for _,scope in ipairs({'appearance','panels','effects'}) do
    assert(custom.reset(extra,scope) and future(extra), 'Scoped resets ignore unrecognized saved panels.');
end
assert(future(require('core.starters').apply(extra,'Melee')) and custom.reset(extra,'future_panel')==nil);
local starter=assert(require('core.starters').apply(s,'Support'));
assert(starter.party_ui.enabled and starter.rolls.enabled and not starter.panels.watch.enabled);
assert(starter.panels.self_buffs.labels[33]=='My haste' and #starter.alerts.rules==2);
assert(custom.equal(before,s), 'A starter leaves the settings it was given intact.');
local window_change=defaults.copy(s); window_change.window.x=500;
assert(custom.equal(custom.history_value(s),custom.history_value(window_change)));
assert(not custom.equal(original,s));

local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,job_name='WAR',self_known=true,
    self_effects={},party={},entities={},self_diagnostics={source='GetStatusIcons',icon_type='table',icon_base=1,
        rejected_slots={{slot=2,index=3,raw_type='number',raw_value=-1,readable=true}}}};
package.loaded['core.client']={read=function() return defaults.copy(snapshot); end,load=function() end};
package.loaded['core.observer']={read=function() return {}; end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function command(text) local event={command=text}; MOCK.fire('command',event); assert(event.blocked); end
MOCK.fire('load'); app.refresh(1);
command('/vg set style.font_size 24');
assert(app.state.settings.style.font_size==24);
command('/vg undo'); assert(app.state.settings.style.font_size==16);
command('/vg redo'); assert(app.state.settings.style.font_size==24);
local count=app.callbacks.history_status().undo;
command('/vg set style.font_size 24'); assert(app.callbacks.history_status().undo==count, 'No-op edits do not consume Undo.');
app.callbacks.changed('before'); app.state.settings.window.x=250; app.callbacks.changed('after'); app.callbacks.save();
assert(app.callbacks.history_status().undo==count, 'Moving the settings window does not consume Undo.');
command('/vg set panels.self_buffs.labels {"33":"Quick haste"}');
assert(app.state.settings.panels.self_buffs.labels[33]=='Quick haste');
command('/vg get panels.self_buffs.labels'); assert(MOCK.printed[#MOCK.printed]:find('Quick haste',1,true));
command('/vg reset typo'); assert(app.state.settings.style.font_size==24);
command('/vg profile save "Parity"');
assert(app.callbacks.profile_status().source=='Parity');
command('/vg set style.font_size 22');
command('/vg profile save "Parity"');
command('/vg profile load "Parity"'); assert(app.state.settings.style.font_size==24, 'Save-new never replaces an existing profile.');
command('/vg profile link 3 "Parity"');
command('/vg profile rename "Parity" "Support"');
assert(app.state.settings.job_profiles['3']=='Support');
command('/vg profile delete "Support"'); assert(app.state.settings.job_profiles['3']==nil);
command('/vg profile recover'); assert(app.state.settings.job_profiles['3']=='Support');
command('/vg set style.font_size 22');
command('/vg profile delete "Support"');
command('/vg undo');
assert(app.state.settings.job_profiles['3']==nil and not app.callbacks.profile_status('Support').exists,
    'Undoing a display change must not resurrect a link to a deleted profile.');
command('/vg profile recover');
assert(app.state.settings.job_profiles['3']=='Support', 'Profile recovery follows the character across settings-table replacements.');
command('/vg watch 999'); command('/vg set style.font_size 26');
snapshot.zone=103; app.refresh(5);
assert(#app.state.settings.watch_ids==0);
command('/vg undo');
assert(#app.state.settings.watch_ids==0, 'Undo never revives watched IDs from an earlier zone visit.');
command('/vg watch 777'); command('/vg undo');
assert(#app.state.settings.watch_ids==0, 'Watch edits within the same zone remain undoable.');
command('/vg report');
assert(require('core.store').read(MOCK_INSTALL_PATH..'/config/addons/vantage/reports/latest.json').version=='1.2.1');
local report=require('core.store').read(MOCK_INSTALL_PATH..'/config/addons/vantage/reports/latest.json');
assert(report.snapshot.valid and report.snapshot.self_known and report.snapshot.self_effects==0,
    'A local report distinguishes a complete empty snapshot from unavailable self-status data.');
assert(report.self_status.icon_base==1 and report.self_status.rejected_slots[1].raw_value==-1
    and #report.observed_self_effects==0, 'Reports preserve status-reader diagnostics and observed slot data.');
command('/vg chatsample'); assert(MOCK.printed[#MOCK.printed]:find('This is how your',1,true));
assert(#MOCK.commands==0, 'Customization commands do not queue gameplay commands.');
command('/vg profile save "Before rename"');
command('/vg profile link 4 "Before rename"');
command('/vg set style.font_size 20');
command('/vg profile rename "Before rename" "After rename"');
command('/vg profile recover');
command('/vg undo');
assert(app.state.settings.job_profiles['4']=='Before rename' and app.state.settings.active_profile=='Before rename',
    'Undo after recovering a rename follows the restored profile name.');

local store=require('core.store');
local shared_profiles=require('core.profiles').new(MOCK_INSTALL_PATH..'/config/addons/vantage');
local shared=defaults.make(); shared.shared_scope='presentation';
shared.panels.self_buffs.width=432; shared.style.font_size=23;
assert(shared_profiles:save_layout(shared));
local shared_original=store.read(shared_profiles.layout_path);
assert(app.callbacks.sharing(true,'placement'));
assert(app.state.settings.panels.self_buffs.width==432 and app.state.settings.style.font_size==24,
    'Joining placement imports shared positions and retains personal appearance.');
assert(custom.equal(shared_original,store.read(shared_profiles.layout_path)),
    'Joining placement cannot overwrite a full shared presentation.');
shared.panels.self_buffs.width=444; assert(shared_profiles:save_layout(shared));
shared_original=store.read(shared_profiles.layout_path);
app.callbacks.changed('before'); app.state.settings.window.x=390; app.callbacks.changed('after'); app.callbacks.save();
assert(custom.equal(shared_original,store.read(shared_profiles.layout_path)),
    'A personal editor change cannot replace another character\'s newer shared layout.');
command('/vg set style.font_size 21');
assert(custom.equal(shared_original,store.read(shared_profiles.layout_path)),
    'Appearance remains personal while only placement is shared.');
command('/vg set shared_scope presentation');
assert(app.state.settings.style.font_size==23 and app.state.settings.panels.self_buffs.width==444,
    'Changing shared scope imports the existing presentation first.');
assert(custom.equal(shared_original,store.read(shared_profiles.layout_path)));
command('/vg set style.font_size 22');
assert(store.read(shared_profiles.layout_path).presentation.style.font_size==22,
    'An intentional shared appearance edit is published.');
command('/vg set shared_layout off');
command('/vg set style.font_size 26');
command('/vg set shared_layout on');
assert(app.state.settings.style.font_size==22, 'The command join follows the same import behavior as the editor.');
return true;
