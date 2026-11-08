addon.name = 'vantage';
addon.author = 'Kipling';
addon.version = '1.0.0';
addon.desc = 'Customizable buff, debuff and recast timers, with buffs beside the game party list, for Phoenix.';
addon.link = 'https://github.com/KiplingFFXI/vantage';

-- Room for the traces and machine code that drawing every frame needs, so LuaJIT doesn't keep flushing them.
-- It sets this addon's own Lua state only. /vg report says whether it took.
local jit_options={applied=false};
do
    local ok,why=pcall(function() jit.opt.start('maxtrace=12000','maxmcode=16384'); end);
    jit_options.applied,jit_options.problem=ok,not ok and tostring(why) or nil;
end;

local performance,performance_problem;
do
    local ok,value=pcall(require,'core.performance');
    if ok then performance=value;else performance_problem=tostring(value);end;
end;

require('common');
local identity = require('core.identity');
local ffi = require('ffi');
local imgui = require('imgui');
local imgui_scopes = require('ui.imgui_scopes');
imgui_scopes.install(imgui);
-- These three hand their text to the game's printf as the format, so a % in a profile name prints junk and one before an
-- n closes the game. Doubled, it prints as itself.
for _,name in ipairs({'TextWrapped','BulletText','SetTooltip'}) do
    local draw=imgui[name];
    imgui[name]=function(text) return draw(type(text)=='string' and text:gsub('%%','%%%%') or text); end;
end;
local defaults = require('ui.defaults');
local store = require('core.store');
local profiles = require('core.profiles');
local sound = require('core.sound');
local client = require('core.client');
local observer = require('core.observer');
local catalog = require('core.catalog');
local tracker = require('core.tracker').new();
local alerts = require('core.alerts').new();
local hud = require('ui.hud');
-- The settings window loads the first time it opens (ui/settings_stub.lua).
local window = require('ui.settings_stub');
local fonts = require('ui.fonts');
local text_metrics = require('ui.text_metrics');
local icons = require('ui.icons');
local recast_icons = require('ui.recast_icons');
local customization = require('core.customization');
local chat_window = require('core.chat');
local party_roster = require('core.roster');
local effect_filters = require('core.effect_filters');
local native_hud = require('ui.native_party_hud');
local native_party = require('core.native_party_ui');
local recast_source = require('core.recasts');
local recasts = recast_source.new();
local cooldown_watch = require('core.party_cooldowns').new();
local roll_watch = require('core.rolls').new();
local pet_watch = require('core.pet').new(require('core.patterns').environment('VANTAGE_PET'));
local ready_pulses = require('core.ready_pulse').new();
local overhead = require('core.overhead');
local warmup = require('core.warmup');
local camera = require('core.camera');
local dispel = require('core.dispel');
local overhead_icons = require('ui.overhead_icons');
local overhead_preview = require('ui.overhead_preview');
local durations_clear = require('core.durations').CLEAR;
local conditions = require('core.conditions');
local edit_mode = require('ui.edit_mode');
local elements = require('ui.elements');
local snap = require('ui.snap');
pcall(ffi.cdef, 'short __stdcall GetAsyncKeyState(int vKey);');
pcall(ffi.cdef, [[void* __stdcall GetForegroundWindow(void);
    unsigned long __stdcall GetWindowThreadProcessId(void*, unsigned long*);
    unsigned long __stdcall GetCurrentProcessId(void);]]);
local foreground_process=ffi.new('unsigned long[1]');
local function game_in_front()
    local handle=ffi.C.GetForegroundWindow();
    if handle==nil or handle==ffi.NULL then return false; end;
    foreground_process[0]=0;
    return ffi.C.GetWindowThreadProcessId(handle,foreground_process)~=0
        and tonumber(foreground_process[0])==tonumber(ffi.C.GetCurrentProcessId());
end;
local function game_focused()
    local ok,focused=pcall(game_in_front);
    return ok and focused or false;
end;
local function shift_held()
    return ffi.C.GetAsyncKeyState(0x10)<0;
end;

local folder = identity.root();
local saved_profiles = profiles.new(folder);
local state = { settings=defaults.make(),snapshot={valid=false},view={rows={},subjects={},valid=false,context={}},
    dirty=false,sampled=-1,queue={},history={},redo={},transaction=nil,changed_at=0,hidden=false,shared_at=0,unsaved={},retry_at=0,report={},zone_epoch=0,failing={},
    chat_read_at=0,
    -- Counts every change to the settings, for the profile summary's Modified check.
    settings_revision=0 };
local callbacks = {};
local refresh;
-- Packets that wake a refresh at once. Your 0x037 wakes one only when your status icons change, and the party's HP
-- updates (0x0DF), which Phoenix sends many times a second in a fight, wait for the next refresh, at most 0.1 s away.
local refresh_packets = { [0x061]=true, [0x063]=true, [0x076]=true, [0x0DD]=true, [0x0E1]=true };
local no_subjects = {};
-- What a Present checks between refreshes, since no packet says it changed.
local visibility_keys = { 'hidden', 'map', 'in_event', 'chat_open' };

local function now()
    return tonumber(ashita.time.get_tick64()) / 1000;
end

callbacks.now=now;

-- Whether the displays may draw yet (core/warmup.lua). The first refresh once they may draw brings in what waited for them: the
-- game's party list and a fresh install's first placement. The party list asked for once they draw (a character
-- switch, edit mode turned on) is read by the refresh after its steps too, not the next timed one.
local function settle_ready()
    local ready=warmup.ready();
    if ready and state.ready==false then state.wake=true; end;
    if state.party_list_waits and ready and not warmup.pending('party') then state.party_list_waits,state.wake=nil,true; end;
    state.ready=ready;
end;

-- Runs every warmup step still to run, as a command or /vg report needs, and lets the displays draw if that ends it.
local function finish_warmup()
    warmup.drain();
    settle_ready();
end;

local function say(message)
    local colors = state.settings.chat_colors or {tag_brackets=81,tag_word=6,replies=106};
    local function code(value)
        value = tonumber(value) or 106;
        return string.char(math.max(1,math.min(255,math.floor(value))));
    end
    print('\30'..code(colors.tag_brackets)..'[\30'..code(colors.tag_word)..'Vantage\30'..code(colors.tag_brackets)
        ..']\30\1 \30'..code(colors.replies)..tostring(message)..'\30\1');
end

local function problem(message)
    if message and state.problem ~= message then say(message); end
    state.problem = message;
end

-- For what runs on every frame or packet: each failure, named by what, prints once, and a new reason for it at most every 5 seconds.
-- problem keeps only the last message, so two failing at once would both print every time they ran.
local function keeps_failing(what,why)
    local message,last=what..' '..tostring(why),state.failing[what];
    if last and (last.message==message or now()-last.at<5) then return; end;
    state.failing[what]={message=message,at=now()};
    problem(message);
end;

local function checkpoint()
    if state.transaction then
        local window_geometry,window_navigation=state.transaction.window_geometry,state.transaction.window_navigation;
        if not customization.equal(customization.history_value(state.transaction.settings,window_geometry,window_navigation),
            customization.history_value(state.settings,window_geometry,window_navigation)) then
            state.history[#state.history+1] = state.transaction;
            if #state.history>20 then table.remove(state.history,1); end
            state.redo={};
        end
        state.transaction=nil;
    end
end

-- The shared layout's placement, and its presentation when that is shared too, to compare before and after a change
-- from another character.
local function shared_layouts(settings)
    return {placement=profiles.capture_layout(settings,'placement'),
        presentation=settings.shared_scope=='presentation' and profiles.capture_layout(settings,'presentation') or nil};
end

-- Adds to out each field a newer shared layout changed, with its path and new value. It walks old and new together
-- until they stop both being tables, and a list counts as one value. A field new doesn't have changes to nil. path is
-- the way down to the current field.
local function changes(old,new,path,out)
    if type(old)~='table' or type(new)~='table' or #old>0 or #new>0 then
        if not customization.equal(old,new) then
            local at={};
            for index=1,#path do at[index]=path[index]; end
            out[#out+1]={path=at,value=new};
        end
        return;
    end
    for key,value in pairs(new) do
        path[#path+1]=key;
        changes(old[key],value,path,out);
        path[#path]=nil;
    end
    for key,value in pairs(old) do
        if new[key]==nil then
            path[#path+1]=key;
            changes(value,nil,path,out);
            path[#path]=nil;
        end
    end
end

-- Settings with the shared changes made since an Undo or Redo step was recorded. The changes of one scope in
-- a row go into one layout, applied once.
local function rebased(settings,held)
    held=held or {};
    local at=1;
    while held[at] do
        local scope=held[at].scope;
        local layout=profiles.capture_layout(settings,scope);
        while held[at] and held[at].scope==scope do
            for _,item in ipairs(held[at].list) do
                local node,path=layout,item.path;
                for index=1,#path-1 do
                    if type(node[path[index]])~='table' then node[path[index]]={}; end
                    node=node[path[index]];
                end
                node[path[#path]]=store.copy(item.value);
            end
            at=at+1;
        end
        profiles.apply_layout(settings,layout,scope);
    end
    return settings;
end

-- A newer shared layout from another character moves every shared Undo and Redo step too, field by field,
-- so undoing a personal change never publishes the older placement that step held. A field it left alone
-- keeps the step's own value. A step keeps the changes made since it was recorded and takes them when Undo
-- or Redo restores it; the open change takes them at once. Entries are replaced, never edited.
local function rebase_history(before,after)
    local found={};
    for scope,new in pairs(after) do
        local list={};
        if before[scope] then changes(before[scope],new,{},list); end
        if #list>0 then found[scope]=list; end
    end
    if not next(found) then return; end
    local function rebase(entry)
        if not entry or not entry.settings.shared_layout then return entry; end
        local scope=found.presentation and entry.settings.shared_scope=='presentation' and 'presentation' or 'placement';
        if not found[scope] then return entry; end
        local copy,held={},{};
        for key,value in pairs(entry) do copy[key]=value; end
        copy.origin=entry.origin or entry;
        for index,change in ipairs(entry.rebases or {}) do held[index]=change; end
        held[#held+1]={scope=scope,list=found[scope]};
        -- A step that took many changes takes them now, so they don't pile up.
        if #held>16 then copy.settings,held=rebased(store.copy(copy.settings),held),nil; end
        copy.rebases=held;
        return copy;
    end
    for index,entry in ipairs(state.history) do state.history[index]=rebase(entry); end
    for index,entry in ipairs(state.redo) do state.redo[index]=rebase(entry); end
    local open=rebase(state.transaction);
    if open and open~=state.transaction then open.settings,open.rebases=rebased(store.copy(open.settings),open.rebases),nil; end
    state.transaction=open;
end

-- Publishes this character's shared layout after its own file is saved. One that fails waits for its own
-- retry, which backs off while it keeps failing, and the shared poll waits with it, so a newer shared layout
-- can't take the place of the change still to be sent. Returns whether nothing is left to publish.
local function publish()
    if not state.settings.shared_layout or not state.path or state.unread==state.path then state.publish_pending=nil; return true; end
    local shared=profiles.capture_layout(state.settings);
    if customization.equal(shared,state.shared_value) then state.publish_pending=nil; return true; end
    local before=(#state.history>0 or #state.redo>0) and shared_layouts(state.settings);
    local ok,why,_,merged = saved_profiles:publish_layout(state.settings,state.shared_value);
    if not ok then
        state.publish_wait=state.publish_pending and math.min(60,state.publish_wait*2) or 5;
        state.publish_pending,state.publish_at=true,now()+state.publish_wait;
        state.publish_problem='Your settings were saved, but not the shared layout. '
            ..(why or 'shared_layout.json could not be saved.')..' Vantage keeps trying.';
        problem(state.publish_problem); return false,why;
    end
    state.publish_pending=nil;
    if state.problem==state.publish_problem then problem(nil); end
    -- The file can be in the other scope's form. The base is this character's own layout, as load and
    -- poll keep it, so the next save compares like with like.
    state.shared_value=profiles.capture_layout(state.settings);
    -- What another character changed since is in these settings now, and in their Undo steps.
    if merged then
        state.settings_revision=state.settings_revision+1;
        if before then rebase_history(before,shared_layouts(state.settings)); end
        local written,issue = store.write(state.path,state.settings);
        if not written then
            state.unsaved[state.path]=store.copy(state.settings);
            state.dirty,state.retry_at=true,now()+5;
            problem(issue or 'Settings could not be saved.'); return false,issue;
        end
    end
    return true;
end

local before_load='Changes made before a character loads are replaced by its saved settings.';
local function save()
    checkpoint();
    -- Times learned since the last save go with any save, or with their own a minute after the first of them.
    if state.learned_at then state.learned_at,state.dirty=nil,true; end
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    if not state.dirty and not state.navigation_dirty then
        -- A publish still waiting goes with a save.
        if state.publish_pending then publish(); end
        return true;
    end
    -- Before a character loads there is no file to save to, and its saved settings replace these when it does.
    if not state.path then problem(before_load); return true; end
    -- The saved file couldn't be read when these settings loaded, so they began as defaults: they never replace
    -- it, or the shared layout. It is read again until it can be.
    if state.unread==state.path then
        state.retry_at=now()+5;
        local why='Your saved settings could not be read, so changes are not saved over them. Fix or remove '
            ..store.name(state.path)..', which must be JSON saved as UTF-8.';
        problem(why); return false,why;
    end
    -- The job these settings are used on goes with them, so the next login knows whether the job changed.
    if state.last_job then state.settings.profile_job=state.last_job; end
    local ok,why = store.write(state.path,state.settings);
    if not ok then
        state.unsaved[state.path]=store.copy(state.settings);
        state.retry_at=now()+5;
        problem(why or 'Settings could not be saved.'); return false,why;
    end
    state.dirty,state.navigation_dirty=false,false;
    state.unsaved[state.path]=nil;
    state.retry_at=0;
    local published,issue=publish();
    if state.dirty then return false,issue; end
    if published then problem(nil); end
    return true;
end

local function changed_after()
    -- A drag changes settings every frame; the profile status waits for its 250 ms refresh meanwhile.
    state.settings_revision=state.settings_revision+1;
    if not state.mouse_held then state.profile_summary_cache=nil; end;
end
-- window_geometry marks a step that moves or resizes the settings window, which Undo and Redo put back.
-- window_navigation marks one that resets its navigation (the Hold Shift to see through this window switch), which they
-- put back too.
function callbacks.changed(stage, label, _, window_geometry, window_navigation)
    if stage=='before' then
        state.transaction = state.transaction or {settings=store.copy(state.settings),label=label or 'Settings change',
            window_geometry=window_geometry==true or nil,window_navigation=window_navigation==true or nil,epoch=state.zone_epoch};
    else
        state.dirty,state.changed_at = true,now();
        changed_after();
    end
end

-- Which page and sections the settings window shows is saved with the next save, when the window closes
-- or on unload, not on each click: a save stalls the frame it runs in. write saves it now.
function callbacks.editor_changed(write)
    state.navigation_dirty=true;
    changed_after();
    if write then return save(); end
end

callbacks.save = save;
-- The count of settings changes, so the settings window keeps what it works out from the settings until the next one.
function callbacks.settings_revision() return state.settings_revision; end;
-- An error stops the settings window for this character. Only a character switch, a window reset or
-- a command that opens the window tries it again. Undo, profiles and other /vg set changes keep it stopped.
local function settings_stopped()
    return state.settings_stopped==true;
end;

-- What a settings page can change, kept before each draw so a page that fails changes nothing. Undo
-- entries hold whole settings copies, so their lists are kept entry by entry. The store's journal keeps
-- the settings, profile and shared layout files as they were before the page's first write to each.
local editing={history={},redo={},journal={files={},paths={[saved_profiles.path]=true,[saved_profiles.layout_path]=true}}};
local function copy_list(target,source)
    for index=1,#source do target[index]=source[index]; end;
    for index=#target,#source+1,-1 do target[index]=nil; end;
end;
local function keep_editing()
    -- Walking the whole save is the dearest part, so it waits for a change.
    if editing.kept_from~=state.settings or editing.kept_revision~=state.settings_revision or editing.kept_at~=state.changed_at then
        editing.settings=customization.keep(editing.settings,state.settings);
        editing.kept_from,editing.kept_revision,editing.kept_at=state.settings,state.settings_revision,state.changed_at;
    end;
    editing.history_list,editing.redo_list,editing.transaction=state.history,state.redo,state.transaction;
    copy_list(editing.history,state.history);copy_list(editing.redo,state.redo);
    editing.dirty,editing.changed_at,editing.retry_at=state.dirty,state.changed_at,state.retry_at;
    editing.publish_pending,editing.publish_at,editing.publish_wait=state.publish_pending,state.publish_at,state.publish_wait;
    editing.navigation_dirty=state.navigation_dirty;
    editing.shared_value,editing.shared_at,editing.hidden=state.shared_value,state.shared_at,state.hidden;
    editing.identity,editing.last_job,editing.job_seen=state.identity,state.last_job,state.job_seen;
    editing.layout_seen=saved_profiles.layout_seen;
    local paths=editing.journal.paths;
    if editing.path~=state.path then
        if editing.path then paths[editing.path]=nil; end;
        if state.path then paths[state.path]=true; end;
    end;
    editing.path=state.path;
    editing.unsaved=state.path and state.unsaved[state.path];
    editing.recovery,editing.drawing=nil,true;
    store.journal(editing.journal);
end;
-- A draw that ends keeps what it did. Its alert reset waits until then, so a page that fails loses no alert.
local function finish_editing()
    editing.drawing=false;store.journal(nil);
    for path in pairs(editing.journal.files) do editing.journal.files[path]=nil; end;
    if editing.reset_alerts then editing.reset_alerts=nil;alerts:reset(); end;
end;
local function restore_editing()
    editing.drawing,editing.reset_alerts=false,nil;store.journal(nil);
    state.settings=customization.restore(editing.settings);
    copy_list(editing.history_list,editing.history);copy_list(editing.redo_list,editing.redo);
    state.history,state.redo,state.transaction=editing.history_list,editing.redo_list,editing.transaction;
    state.dirty,state.changed_at,state.retry_at=editing.dirty,editing.changed_at,editing.retry_at;
    state.publish_pending,state.publish_at,state.publish_wait=editing.publish_pending,editing.publish_at,editing.publish_wait;
    state.navigation_dirty=editing.navigation_dirty;
    state.shared_value,state.shared_at,state.hidden=editing.shared_value,editing.shared_at,editing.hidden;
    -- The shared file the page read stays unread, so the next poll still takes a newer one.
    saved_profiles.layout_seen=editing.layout_seen;
    -- A job change seen while the page drew is seen again by the next refresh, so its linked profile
    -- still loads. A character switch keeps the new character's job.
    if state.identity==editing.identity then state.last_job,state.job_seen=editing.last_job,editing.job_seen; end;
    if editing.path then state.unsaved[editing.path]=editing.unsaved; end;
    if editing.recovery then
        saved_profiles:restore_recovery(editing.recovery);
        state.deleted_history=editing.deleted_history;
    end;
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    -- Each file the page wrote goes back as it was. A newer one from another character is kept, and
    -- one that can't be read or written is saved again from what was put back. A profile file, or a
    -- shared layout this character no longer shares, is put back once it can be read.
    local files,later={},{};
    for path,kept in pairs(editing.journal.files) do files[path]=kept; end;
    local missed=store.undo(editing.journal.files) or {};
    -- Another program held a file that couldn't be read back a moment ago, so it is saved again after the usual wait.
    if missed[state.path]=='failed' then state.dirty,state.changed_at=true,now(); end;
    if missed[saved_profiles.layout_path]=='failed' then
        if state.settings.shared_layout then state.dirty,state.changed_at,state.shared_value=true,now(),nil;
        else later[saved_profiles.layout_path]=files[saved_profiles.layout_path]; end;
    end;
    if missed[saved_profiles.path]=='failed' then
        later[saved_profiles.path]=files[saved_profiles.path];
        problem('The profiles a failed settings page changed could not be put back.');
    end;
    if next(later) then
        state.undo_later=state.undo_later or {};
        for path,kept in pairs(later) do state.undo_later[path]=kept; end;
        -- Another program held them a moment ago, so the first try again comes a second later.
        state.undo_later_at=now()+1;
    end;
end;
-- Tries again, once a second, to put back the files a failed page left. One that reads as something
-- else now was written since, and is kept.
local function undo_later(t)
    if not state.undo_later or t<(state.undo_later_at or 0) then return; end;
    local files=state.undo_later;
    local pending={};
    for path,kept in pairs(files) do pending[path]=kept; end;
    state.undo_later,state.undo_later_at=nil,t+1;
    for path,why in pairs(store.undo(files) or {}) do
        if why=='failed' then state.undo_later=state.undo_later or {};state.undo_later[path]=pending[path]; end;
    end;
end;
local function reset_alerts()
    if editing.drawing then editing.reset_alerts=true; else alerts:reset(); end;
end;
-- A profile change also changes the recovery list, and what each delete took from Undo, which a page that
-- fails puts back.
local function keep_recovery()
    if editing.drawing and not editing.recovery then
        editing.recovery=saved_profiles:recovery_list();
        local held=state.deleted_history and {};
        for serial,record in pairs(state.deleted_history or {}) do held[serial]=record; end;
        editing.deleted_history=held;
    end;
end;
callbacks.settings_blocks_input = function(x,y,shift,typing)
    -- The edit mode bar takes the mouse over it, as the settings window does.
    if edit_mode.blocks_input(x,y) then return true; end;
    -- An open settings window stopped by an error isn't drawn, so it can't take the mouse.
    if window.blocks_input and not (settings_stopped() and state.settings.window.open) then
        return window.blocks_input(state.settings,x,y,shift,typing);
    end;
    return false;
end;
callbacks.party_native_status = native_party.status;
callbacks.recast_catalog = recast_source.catalog;
callbacks.recast_item_status = recast_source.item_status;

local function finish_layout(safely)
    if safely then
        for _,callback in pairs({window.cancel_resize,hud.cancel_gesture,hud.cancel_notice_gesture,
            native_hud.cancel_layout_gesture,edit_mode.cancel_gesture})do pcall(callback);end;
        return;
    end;
    if window.cancel_resize then window.cancel_resize(); end
    if hud.cancel_gesture then hud.cancel_gesture(); end
    if hud.cancel_notice_gesture then hud.cancel_notice_gesture(); end
    native_hud.cancel_layout_gesture();
    edit_mode.cancel_gesture();
end

callbacks.displays_hidden=function() return state.hidden; end;
-- The game's chat log for the Size buttons, which keep displays clear of it.
callbacks.chat_area=function() return state.snapshot.chat_area; end;
callbacks.show_displays=function() state.hidden=false;state.wake=true; end;
-- Edit mode on or off (/vg edit and the main page); nil turns it the other way. Turning it on shows the
-- displays again. Turning it off leaves every display where it is.
function callbacks.edit_mode(on)
    if on==nil then on=not edit_mode.active(); end;
    if on then edit_mode.start(); state.hidden,state.wake=false,true; else edit_mode.stop(); end;
    return true;
end;
-- The edit mode bar opens a settings page, as a command that opens the window does.
function callbacks.open_page(page)
    local w=state.settings.window;
    w.open,w.tab,state.settings_stopped=true,page,nil;
    callbacks.editor_changed();
    return true;
end;

local function party_subjects(view)
    local subjects, remapped = {}, {};
    for _, subject in ipairs(view.subjects or {}) do
        subjects[subject.id] = { known = subject.known == true, complete = subject.known == true,
            effects = {}, source = subject.known and 'client' or 'observed' };
    end
    for _, row in ipairs(view.rows or {}) do
        local subject = subjects[row.entity_id];
        if subject and row.domain ~= 'recast' then
            local effect = row;
            if row.kind ~= 'buff' and row.kind ~= 'debuff' then
                effect = {};
                for key, value in pairs(row) do effect[key] = value; end
                effect.kind = 'neutral';
                remapped[#remapped + 1] = effect;
            end
            subject.effects[#subject.effects + 1] = effect;
        end
    end
    return subjects, remapped;
end

function callbacks.sharing(enabled,scope)
    if type(enabled)~='boolean' or scope~='placement' and scope~='presentation' then
        return false,'Choose placement or full presentation.';
    end
    if enabled==state.settings.shared_layout and scope==state.settings.shared_scope then return true; end
    finish_layout();
    local candidate=store.copy(state.settings);
    candidate.shared_layout,candidate.shared_scope=enabled,scope;
    local shared;
    if enabled then
        local ok,why,found=saved_profiles:load_layout(candidate);
        if not ok then return false,why; end
        if found then shared=profiles.capture_layout(candidate); end
    end
    callbacks.changed('before','Shared settings');
    state.settings,state.shared_value=candidate,shared;
    callbacks.changed('after');
    return save();
end

-- An Undo or Redo that turns sharing on, or changes what it shares, joins it as the setting does: the shared
-- layout loads first, so the older one that step held is never published over a newer one.
local function rejoin(was)
    local s=state.settings;
    if not s.shared_layout or was.shared_layout and was.shared_scope==s.shared_scope then return; end
    local ok,issue,found=saved_profiles:load_layout(s);
    if not ok and issue then problem(issue); end
    state.shared_value=ok and found and profiles.capture_layout(s) or nil;
end

-- Undo takes the last step from history and keeps the settings it replaces in redo; Redo does the reverse.
-- A step that moved or resized the settings window puts the window back too, and a reset of its navigation
-- puts that back; any other leaves the window as it is.
local function step(from,to,empty)
    finish_layout();
    checkpoint();
    local entry=table.remove(state[from]);
    if not entry then return false,empty; end
    local kept=state[to];
    kept[#kept+1]={settings=store.copy(state.settings),label=entry.label,window_geometry=entry.window_geometry,
        window_navigation=entry.window_navigation,epoch=state.zone_epoch};
    local editor=store.copy(state.settings.window);
    local watched=store.copy(state.settings.watch_ids);
    local learned=state.settings.durations.learned;
    local was=state.settings;
    -- Entries are never edited, so a settings page that fails can put them back as they were.
    state.settings=rebased(defaults.tidy(store.copy(entry.settings)),entry.rebases);
    -- The times learned from your casts aren't settings: Undo and Redo keep what was learned since, except over the
    -- step that cleared them, which puts back the ones it cleared.
    if entry.label~=durations_clear then state.settings.durations.learned=learned; end
    if entry.window_geometry then
        for _,key in ipairs({'x','y','width','height'}) do editor[key]=state.settings.window[key]; end
    end
    if entry.window_navigation then
        for _,key in ipairs(customization.navigation) do editor[key]=store.copy(state.settings.window[key]); end
    end
    state.settings.window=editor;
    if entry.epoch~=state.zone_epoch then state.settings.watch_ids=watched; end
    rejoin(was);
    state.dirty=true;
    reset_alerts();
    return save();
end

function callbacks.undo() return step('history','redo','There is no earlier change to restore.'); end
function callbacks.redo() return step('redo','history','There is no change to redo.'); end

function callbacks.history_status()
    return {undo=#state.history,redo=#state.redo,
        undo_label=state.history[#state.history] and state.history[#state.history].label,
        redo_label=state.redo[#state.redo] and state.redo[#state.redo].label};
end

function callbacks.reset(section)
    finish_layout();
    local candidate,why=customization.reset(store.copy(state.settings),section);
    if not candidate then return false,why; end
    -- Reset all and /vg reset navigation can be undone, the window's part too: its
    -- navigation, and for Reset all its place and size.
    local all=section==nil or section=='all';
    callbacks.changed('before',customization.reset_label(section),nil,all,all or section=='navigation');
    state.settings=defaults.tidy(candidate);
    -- A first spot is where a fresh install's first frame puts a display on this screen.
    local screen,spots=imgui.GetIO().DisplaySize,require('ui.setup_defaults');
    local place={width=screen.x,height=screen.y,chat=state.snapshot.chat};
    if all or section=='displays' then spots.place_fresh(state.settings,place);
    else spots.place_reset(state.settings,section,place); end;
    -- Resetting the window, alone or with everything else, tries a stopped one again.
    if section==nil or section=='all' or section=='window' then state.settings_stopped=nil; end;
    callbacks.changed('after');
    reset_alerts();
    return save();
end

function callbacks.profile_list()
    return saved_profiles:list();
end

-- A copy of an Undo or Redo entry with other links and active profile. It keeps the step it was first
-- recorded as (origin). A new copy, so a settings page that fails can put the old one back.
local function relinked(entry,links,active)
    local copy={};
    for key,value in pairs(entry) do copy[key]=value; end
    copy.origin=entry.origin or entry;
    copy.settings={};
    for key,value in pairs(entry.settings) do copy.settings[key]=value; end
    copy.settings.job_profiles,copy.settings.active_profile=links,active;
    return copy;
end

-- Moves every step's links to a profile, and its active profile, from old to new (none when new is nil);
-- active_only leaves the links. Returns, for each step by origin, the links and active profile it lost.
local function remap_profile_history(old,new,active_only)
    local taken={};
    local function remap(entry)
        if not entry then return; end
        local settings=entry.settings;
        local linked=settings.active_profile==old;
        if not active_only then for _,profile in pairs(settings.job_profiles) do linked=linked or profile==old; end end
        if not linked then return entry; end
        local links,lost={},{jobs={}};
        for job,profile in pairs(settings.job_profiles) do
            if profile==old and not active_only then links[job],lost.jobs[job]=new,profile; else links[job]=profile; end
        end
        local active=settings.active_profile;
        if active==old then active,lost.active=new or '',old; end
        local copy=relinked(entry,links,active);
        taken[copy.origin]=lost;
        return copy;
    end
    for index,entry in ipairs(state.history) do state.history[index]=remap(entry); end
    for index,entry in ipairs(state.redo) do state.redo[index]=remap(entry); end
    state.transaction=remap(state.transaction);
    return taken;
end

-- Recovering a deleted profile gives each step what the delete took from it, and each step recorded after
-- the delete what the recovery gave back (restored), wherever that step has no link or active profile of
-- its own.
local function relink_profile_history(record,restored)
    if not record then return; end
    local function relink(entry)
        if not entry then return; end
        local origin=entry.origin or entry;
        local give=record.taken[origin] or not record.seen[origin] and restored;
        if not give then return entry; end
        local settings,links,changed=entry.settings,{},false;
        for job,profile in pairs(settings.job_profiles) do links[job]=profile; end
        for job,profile in pairs(give.jobs) do if links[job]==nil then links[job],changed=profile,true; end end
        local active=settings.active_profile;
        if give.active and active=='' then active,changed=give.active,true; end
        return changed and relinked(entry,links,active) or entry;
    end
    for index,entry in ipairs(state.history) do state.history[index]=relink(entry); end
    for index,entry in ipairs(state.redo) do state.redo[index]=relink(entry); end
    state.transaction=relink(state.transaction);
end

function callbacks.profile_save(name,overwrite,token)
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    checkpoint();
    keep_recovery();
    local was=state.settings.active_profile;
    local ok,why;
    if overwrite then ok,why=saved_profiles:overwrite(name,state.settings,token);
    else ok,why=saved_profiles:save_new(name,state.settings); end
    if ok then
        state.settings.active_profile=saved_profiles:source(name).name;
        -- These settings are that profile now, so every Undo step that came from the profile in use before now comes
        -- from this one.
        if state.settings.active_profile~=was then remap_profile_history(was,state.settings.active_profile,true); end
        state.dirty=true; return save();
    end
    return ok,why;
end

function callbacks.profile_load(name)
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    finish_layout();
    checkpoint();
    callbacks.changed('before','Load '..tostring(name));
    local ok,why=saved_profiles:load(name,state.settings);
    if ok then
        state.settings=defaults.tidy(state.settings);
        callbacks.changed('after');
        reset_alerts();
        return save();
    else
        state.transaction=nil;
    end
    return ok,why;
end

function callbacks.profile_delete(name,token)
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    local source=saved_profiles:source(name);
    keep_recovery();
    local ok,why=saved_profiles:delete(name,token,state.settings);
    if ok then
        name=source.name;
        -- Keyed by the steps themselves, so a step that leaves Undo and Redo isn't kept for it.
        local record={taken=setmetatable(remap_profile_history(name,nil),{__mode='k'}),seen=setmetatable({},{__mode='k'})};
        for _,list in ipairs({state.history,state.redo,{state.transaction}}) do
            for _,entry in ipairs(list) do record.seen[entry.origin or entry]=true; end
        end
        -- Kept while the delete can still be recovered.
        local kept={};
        for _,entry in ipairs(saved_profiles:recovery_list()) do
            kept[entry.serial]=state.deleted_history and state.deleted_history[entry.serial];
        end
        kept[saved_profiles:recovery().serial]=record;
        state.deleted_history=kept;
        for job,linked in pairs(state.settings.job_profiles) do
            if linked==name then state.settings.job_profiles[job]=nil; end
        end
        if state.settings.active_profile==name then state.settings.active_profile=''; end
        state.dirty=true;
        return save();
    end
    return ok,why;
end

function callbacks.profile_rename(name,new_name,token)
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    local source=saved_profiles:source(name);
    keep_recovery();
    local ok,why=saved_profiles:rename(name,new_name,state.settings,token);
    if ok then remap_profile_history(source.name,saved_profiles:source(new_name).name); state.dirty=true; return save(); end
    return ok,why;
end

function callbacks.profile_recover()
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    local recovery=saved_profiles:recovery();
    keep_recovery();
    local links,active={},state.settings.active_profile;
    for job,profile in pairs(state.settings.job_profiles) do links[job]=profile; end
    local ok,why=saved_profiles:recover(state.settings);
    if ok then
        if recovery and recovery.kind=='rename' then
            remap_profile_history(recovery.to_name,recovery.name);
            -- Links and an active profile set after the rename follow it back too.
            for job,linked in pairs(state.settings.job_profiles) do
                if linked==recovery.to_name then state.settings.job_profiles[job]=recovery.name; end
            end
            if state.settings.active_profile==recovery.to_name then state.settings.active_profile=recovery.name; end
        end
        if recovery and recovery.kind=='delete' and state.deleted_history then
            local restored={jobs={}};
            for job,profile in pairs(state.settings.job_profiles) do if links[job]~=profile then restored.jobs[job]=profile; end end
            if state.settings.active_profile~=active then restored.active=state.settings.active_profile; end
            relink_profile_history(state.deleted_history[recovery.serial],restored);
            state.deleted_history[recovery.serial]=nil;
        end
        state.dirty=true;
        return save();
    end
    return ok,why;
end

local function profile_status_fields(status,why)
    status=status or {};
    status.source=status.name or state.settings.active_profile;
    status.missing=status.source~='' and not status.exists;
    local recovery=saved_profiles:recovery();
    status.recover_available=recovery~=nil;
    status.recover_kind=recovery and recovery.kind;
    status.problem=why;
    return status;
end

function callbacks.profile_status(name)
    local status,why=saved_profiles:source(name or state.settings.active_profile,state.settings);
    return profile_status_fields(status,why);
end

function callbacks.profile_summary()
    local t,cache=now(),state.profile_summary_cache;
    local s=state.settings;
    if cache and cache.settings==s and cache.active==s.active_profile and cache.identity==state.identity
        and t>=cache.at and t-cache.at<0.25 then return cache.value; end;
    local summary=saved_profiles:summary(s,state.settings_revision);
    summary.status=profile_status_fields(summary.status,summary.problem);
    state.profile_summary_cache={settings=s,active=s.active_profile,identity=state.identity,at=t,value=summary};
    return summary;
end

-- A starter profile (core/starters.lua) in one Undo step. Apply on the main page asks for samples; /vg starter doesn't,
-- as it's typed with no End samples to hand.
function callbacks.starter(name,samples)
    finish_layout();
    local starters=require('core.starters');
    local candidate,why=starters.apply(state.settings,name,samples);
    if not candidate then return false,why; end
    callbacks.changed('before','Starter: '..starters.by_id[tostring(name):lower()].name);
    state.settings=candidate; callbacks.changed('after');
    return save();
end

function callbacks.copy_shown(panel,details,preview_settings)
    local settings=preview_settings or state.settings;
    -- Any other display has no timers of its own, so it copies what the timer panels show.
    local text=hud.copy_text(state.view,settings,settings.panels[panel] and panel or nil,details,now());
    if text=='' then return false,'No timers are showing, so nothing was copied.'; end
    imgui.SetClipboardText(text);
    return true;
end

function callbacks.copy_text(text)
    if type(text)~='string' or #text>262144 then return false,'The preview could not be copied.'; end
    imgui.SetClipboardText(text);
    return true;
end

-- Exports (core/share.lua). Copying puts one on the clipboard and returns what was left out, if anything;
-- reading takes the clipboard's text; an import is one Undo step that saves.
local function character_name()
    return state.snapshot.name or state.identity and state.identity:match(':(.*)$') or nil;
end
function callbacks.share_copy(kind,id)
    local text,note=require('core.share').export(state.settings,kind,id,character_name());
    if not text then return false,note; end
    imgui.SetClipboardText(text);
    return true,nil,note;
end
function callbacks.share_read()
    local ok,text=pcall(imgui.GetClipboardText);
    if not ok then return nil,'The clipboard could not be read.'; end
    return require('core.share').read(text);
end
function callbacks.share_preview(payload,mode)
    local share=require('core.share');
    local candidate,why=share.candidate(state.settings,payload,mode);
    if not candidate then return nil,why; end
    return share.changes(state.settings,candidate);
end
function callbacks.share_import(payload,mode)
    finish_layout();
    local share=require('core.share');
    local candidate,why=share.candidate(state.settings,payload,mode);
    if not candidate then return false,why; end
    callbacks.changed('before',(mode=='add' and 'Add from' or 'Replace with')..' an export');
    state.settings=candidate;
    callbacks.changed('after');
    reset_alerts();
    return save();
end
-- A saved profile as a whole profile export, made from it without loading it: on the clipboard, or with to_file
-- in a new file in the shared folder, whose name it returns. The settings and Undo stay as they are.
function callbacks.profile_share(name,to_file)
    local share=require('core.share');
    local candidate,why,saved=saved_profiles:settings_of(name,state.settings);
    if not candidate then return false,why; end
    local text,note=share.export(candidate,'profile',nil,character_name());
    if not text then return false,note; end
    if to_file then
        local file,problem=share.save_file(folder..'shared/',saved,text,character_name());
        if not file then return false,problem; end
        return true,nil,note,identity.relative('shared/'..file);
    end
    imgui.SetClipboardText(text);
    return true,nil,note;
end
-- The files Import from a file lists, and one of them read as an export.
function callbacks.shared_files() return require('core.share').files(folder..'shared/'); end
function callbacks.shared_read(file) return require('core.share').read_file(folder..'shared/',file); end
-- A whole profile export saved as a new profile named name, not loaded: what Replace would make, so your own
-- locks, members, watch list and job links stay, and with keep_positions your displays stay where they are. Returns
-- the name it was saved under.
function callbacks.profile_import(payload,name,keep_positions)
    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
    local candidate,why=require('core.share').profile_of(state.settings,payload,keep_positions);
    if not candidate then return false,why; end
    local ok,problem,taken=saved_profiles:save_new(name,candidate);
    -- Import has no Overwrite, so a name in use only asks for another.
    if not ok then return false,taken=='taken' and 'A profile with that name is already saved. Type another name.' or problem; end
    return true,nil,saved_profiles:source(name).name;
end

function callbacks.chat_sample()
    say('This is how your Vantage messages will look.');
    return true;
end

-- quiet writes it without saying so, for a command that prints its own lines.
function callbacks.export_report(quiet)
    -- A report asked for inside a settings page is written once the page has drawn. Its refresh can switch
    -- characters, which a page that then fails could not put back.
    if editing.drawing then state.export_pending=true; return true; end;
    -- The report sees everything loaded: the warmup's steps still to run run first, and again after its refresh, which
    -- can be the first after a load and ask for more (XI View, the party list, the name point).
    finish_warmup();
    refresh(now(), true);
    finish_warmup();
    local capabilities=client.capabilities and client.capabilities() or {};
    -- Whether the trace limits took, and LuaJIT's own state.
    local jit_report={applied=jit_options.applied,problem=jit_options.problem,maxtrace=12000,maxmcode=16384};
    local read_jit,jit_status=pcall(function() return {jit.status()}; end);
    if read_jit then jit_report.enabled,jit_report.flags=jit_status[1]==true,{select(2,unpack(jit_status))}; end;
    local report={version=addon.version,recorded_at=now(),capabilities=capabilities,problem=state.problem,
        jit=jit_report,clock=client.clock_status and client.clock_status() or nil,
        item_recasts=recast_source.item_status and recast_source.item_status() or nil,
        snapshot={valid=state.snapshot.valid,self_known=state.snapshot.self_known,self_effects=#(state.snapshot.self_effects or {}),
            in_event=state.snapshot.in_event,map=state.snapshot.map,hidden=state.snapshot.hidden,dead=state.snapshot.dead},
        self_status=store.copy(state.snapshot.self_diagnostics or {}),
        observed_self_effects=store.copy(state.snapshot.self_effects or {}),
        party_roster=store.copy(state.roster or {valid=false,members={}}),
        party_display=store.copy(state.settings.party_ui),native_party=native_party.status(),
        recasts=store.copy(state.recasts or {}),
        chat=chat_window.describe and chat_window.describe() or 'Unavailable',
        rows=store.copy(state.view.rows or {}),history=store.copy(state.report),pet=store.copy(pet_watch:report()),
        overhead=overhead.report(state.settings,state.snapshot),startup=warmup.report(),
        note='Client observations only. Estimated durations, and rows with no duration, can differ from the server.'};
    report.overhead.icons_drawn=overhead_icons.drawn();
    -- Party icons made at their drawn size: the sizes kept, textures made, builds, fallbacks and the slowest build.
    report.party_icon_sizes=require('ui.client_assets').icon_sizes_report();
    -- The client art and fonts: where each part came from, and why any part isn't drawn as chosen.
    report.art=require('ui.fonts').report(state.settings.style.font);
    -- The timings are taken last, so they hold the camera check above and /vg report's own time up to here
    -- (command.report).
    if performance and state.report_started then performance.record('command.report',state.report_started); end;
    state.report_started=nil;
    report.performance=performance and performance.snapshot() or {available=false,reason=performance_problem or 'Timings are unavailable.'};
    local path=folder..'reports/latest.json';
    local ok,why=store.write(path,report);
    if ok and not quiet then say('Report saved to '..identity.relative('reports/latest.json')..'.'); end
    return ok,why;
end

function callbacks.profile_link(job,name)
    checkpoint();
    callbacks.changed('before',name and name~='' and 'Link a job to '..tostring(name) or 'Unlink a job');
    local ok,why=saved_profiles:link(state.settings,job,name);
    if ok then callbacks.changed('after'); return save(); else state.transaction=nil; end
    return ok,why;
end

local function effect_name(rule, recast_names)
    if not rule.effect or rule.effect==0 then return; end
    if rule.domain=='recast' then
        if recast_names then return recast_names[rule.effect] or rule.effect_name or rule.name or 'Recast'; end
        for _,row in ipairs(state.view.rows or {}) do if row.domain=='recast' and row.effect==rule.effect then return row.name; end end
        return rule.effect_name or rule.name or 'Recast';
    end
    return catalog.get(rule.effect).name;
end

local function enrich_rule(rule,index,names)
    local value={};
    for key,item in pairs(rule) do value[key]=type(item)=='table' and store.copy(item) or item; end
    if value.effect and value.effect~=0 then
        value.effect_name=names and names[index] or effect_name(value);
    end
    return value;
end

local function alert_names()
    if not state.settings.alerts.enabled then return; end
    local names,recast_names={};
    for index,rule in ipairs(state.settings.alerts.rules) do
        if rule.domain=='recast' and rule.effect and rule.effect~=0 and not recast_names then
            recast_names={};
            for _,row in ipairs(state.recasts.rows or {}) do if not recast_names[row.effect] then recast_names[row.effect]=row.name; end end
        end
        names[index]=effect_name(rule,recast_names);
    end
    return names;
end

function callbacks.test_alert(rule)
    alerts:test(enrich_rule(rule),now());
    state.view.notices=alerts:view(now());
    return true;
end

-- Shows one ready pulse now with a sample icon, at the spot the pulse uses (the Recasts panel's Ready pulse).
function callbacks.test_pulse()
    ready_pulses:test(state.settings,now());
    state.view.pulses=ready_pulses.active;
    return true;
end

function callbacks.sound_files()
    return sound.files();
end

function callbacks.refresh_sounds()
    return sound.refresh();
end

function callbacks.watch(id)
    id=tonumber(id);
    if not id or id~=id or id<=0 or id>4294967295 or id~=math.floor(id) then return false,'Select an entity to watch.'; end
    for _,held in ipairs(state.settings.watch_ids) do if held==id then return true; end end
    if #state.settings.watch_ids>=64 then return false,'Remove a watched entity before adding another.'; end
    callbacks.changed('before');
    state.settings.watch_ids[#state.settings.watch_ids+1]=id;
    state.settings.panels.watch.enabled=true;
    callbacks.changed('after');
    return save();
end

function callbacks.unwatch(id)
    id=tonumber(id);
    local watched=false;
    for _,held in ipairs(state.settings.watch_ids) do watched=watched or held==id; end
    if not watched then return false,id and 'That entity is not watched.' or 'Select a watched entity to stop watching.'; end
    callbacks.changed('before');
    for i=#state.settings.watch_ids,1,-1 do if state.settings.watch_ids[i]==id then table.remove(state.settings.watch_ids,i); end end
    callbacks.changed('after');
    return save();
end

-- What the game calls a unit now. The context holds only your party and target, and the watch list has others.
function callbacks.unit_name(id)
    return client.resolve(id).name;
end

local function read_settings(snapshot)
    if not snapshot.valid or not snapshot.id then return; end
    if type(snapshot.name)~='string' or snapshot.name=='' or #snapshot.name>40 or snapshot.name:find('[%c]')
        or snapshot.name:gsub('[^%w_-]','')=='' then return;end;
    local identity=tostring(snapshot.id)..':'..tostring(snapshot.name or '');
    if state.identity==identity then
        -- A saved file that couldn't be read is tried again every few seconds; once it reads, it is loaded in
        -- place of the defaults this session ran on.
        if state.unread~=state.path or now()<(state.unread_at or 0) then return; end
        state.unread_at=now()+5;
        if not store.read(state.path) then return; end
        -- What this session changed on the defaults is dropped; the saved file is what was chosen.
        state.dirty,state.navigation_dirty,state.learned_at=false,false,nil;
        problem(nil);
        say('Your saved settings could be read again and are loaded.');
    end
    finish_layout();
    save();
    local name=tostring(snapshot.name or 'Character'):gsub('[^%w_-]',''):sub(1,40);
    local directory=folder..name..'_'..tostring(snapshot.id)..'/';
    state.path=directory..'settings.json';
    local loaded,why=store.read(state.path);
    if state.unsaved[state.path] then loaded=store.copy(state.unsaved[state.path]); end
    state.unread,state.unread_at=not loaded and state.path or nil,now()+5;
    state.settings=defaults.tidy(loaded or defaults.make());
    -- The window always opens on the main page, whatever page it was left on.
    state.settings.window.tab='Home';
    -- No saved file: a fresh install, whose displays are placed once they may draw and the screen size is known.
    state.place_fresh=type(loaded)=='table' and next(loaded)==nil or nil;
    -- The job these settings were last used on, saved with them and on each job change seen while Vantage runs: a
    -- login on that job loads no profile over them, and one on a job changed while Vantage wasn't loaded loads its
    -- profile.
    state.identity,state.history,state.redo,state.transaction,state.last_job=identity,{},{},nil,state.settings.profile_job;
    state.job_seen=nil;
    state.deleted_history=nil;
    state.settings_stopped=nil;
    state.settings_owner_id=snapshot.id;
    saved_profiles:set_owner(identity);
    state.report={};
    state.shared_value,state.publish_pending=nil,nil;
    state.dirty,state.navigation_dirty=state.unsaved[state.path]~=nil,false;
    alerts:reset();
    if state.problem==before_load then problem(nil); end
    if why then problem(why); end
    if state.settings.shared_layout then
        local ok,issue,found=saved_profiles:load_layout(state.settings);
        if not ok and issue then problem(issue); end
        if ok and found then state.shared_value=profiles.capture_layout(state.settings); end
    end
    -- What these settings draw with joins the warmup: their window frame, XI View for a look that uses it, the name point
    -- for overhead icons.
    require('ui.client_assets').want_window(state.settings.style.window_type);
    if require('ui.appearance').uses_xiview(state.settings) then warmup.want('xiview'); end;
    if state.settings.overhead.enabled then warmup.want('names'); end;
end

local function deliver(t)
    for _,notice in ipairs(alerts:drain(t,state.settings.alerts.volume)) do
        if notice.chat then say(notice.message); end
        if notice.sound and notice.sound~='' then
            local ok,why=sound.use(notice.sound);
            local volume=notice.volume and notice.volume>=0 and notice.volume or state.settings.alerts.volume;
            if ok then ok,why=sound.play(volume); end
            if not ok then problem(why or 'The selected sound could not be played.'); end
        end
    end
end

local function clear_zone(reason,t)
    finish_layout(true);
    state.zone_epoch=state.zone_epoch+1;
    tracker:clear(reason,t);
    recasts:reset();
    -- Rolls, charms and /check levels belong to the zone they were seen in. A jug can come along.
    roll_watch:clear(); pet_watch:clear(t);
    state.recast_sampled,state.recast_demand=nil,nil;
    alerts:reset();
    state.queue={};
    -- A new visit can reuse the same zone and entity IDs.
    if #state.settings.watch_ids>0 then state.settings.watch_ids={}; state.dirty=true; changed_after(); end
    -- Learned times are saved at a zone change.
    if state.learned_at then state.dirty=true; end
end

-- Whether a display follows the game's party list, or a move snaps to it, so the party list's place is read. A move
-- snaps to it only with Grid mode and Snap to the game's party list on, for a display ticked for Grid mode that is on
-- and unlocked. Then it is read while Shift and the mouse button are down, as a Shift drag snaps like edit mode, and
-- all the while edit mode is on, so the list's warmup is done before the first drag there and that drag snaps to it
-- from its first move.
local function wants_party_list(s)
    for _, element in ipairs(elements.list) do
        local anchor = element.anchor and elements.anchor(s, element.id);
        if anchor and anchor.to == 'party' then return true; end
    end
    local e = s.edit_mode;
    if not (edit_mode.active() or state.shift_drag) or not e.grid_mode or not e.snap_party then return false; end
    for _, element in ipairs(elements.movable) do
        local id = element.id;
        if snap.on(s, id) and elements.on(s, id) and not elements.locked(s, id) then return true; end
    end
    return false;
end

-- Whether the settings window has the Party list buffs panel, without loading the window to ask.
local function party_panel_open()
    local frame = package.loaded['ui.panel_frame'];
    return frame ~= nil and frame.opened() == 'party_ui';
end

local function needs_party_roster()
    local s = state.settings;
    return s.party_ui.enabled or s.window.open and s.window.tab == 'Display' and party_panel_open()
        or effect_filters.compile(s.effect_filters).needs_jobs or wants_party_list(s);
end

local function recast_options()
    local s=state.settings;
    local options={enabled=false,spells=false,abilities=false,items=false};
    for key,kind in pairs(defaults.recast_panels) do
        if defaults.panel_enabled(s,key) then
            if kind=='all' then
                local categories=s.panels[key].recast_categories;
                options.spells,options.abilities,options.items=categories.spell,categories.ability,categories.item;
            else options[kind=='ability' and 'abilities' or kind..'s']=true; end;
        end;
    end;
    if s.window.open and s.window.tab=='Display' then options.spells,options.abilities,options.items=true,true,true; end;
    -- A ready pulse at its own spot on the screen needs the recasts whatever the panels show.
    if s.ready_pulse.enabled and s.ready_pulse.spot=='screen' then options.spells,options.abilities,options.items=true,true,true; end;
    -- The pet display shows your pet commands' recasts.
    if s.pet.enabled and s.pet.show_recasts then options.abilities=true; end;
    if s.alerts.enabled then
        for _,rule in ipairs(s.alerts.rules) do
            if rule.enabled and rule.domain=='recast' then
                local id=rule.effect or 0;
                if id>=10000 and id<=11023 then options.spells=true;
                elseif id>=20000 and id<=24095 then options.abilities=true;
                elseif id>=30001 and id<=95534 then options.items=true;
                else options.spells,options.abilities,options.items=true,true,true; end;
            end;
        end;
    end;
    options.enabled=options.spells or options.abilities or options.items;
    return options;
end

-- The first refresh after a load times its parts for /vg report (first_refresh.*); later ones time none. true starts
-- the parts when the load asked for them; a name records the part since the last.
local split_at;
local function split(stage)
    if stage==true then
        split_at=state.split_refresh and performance and performance.now() or nil;
        state.split_refresh=nil;
    elseif split_at then
        performance.record(stage,split_at);
        split_at=performance.now();
    end;
end;

refresh = function(t, force_roster)
    local started=performance and performance.now();
    split(true);
    local snapshot=client.read(t,state.settings);
    split('first_refresh.client_read');
    read_settings(snapshot);
    split('first_refresh.read_settings');
    local changed=state.snapshot.id~=snapshot.id or state.snapshot.zone~=snapshot.zone;
    if changed then
        clear_zone('zone or character changed',t);
    end
    if snapshot.valid and snapshot.id==state.settings_owner_id then
        if snapshot.job~=state.last_job then
            -- A job change loads its linked profile, unless that profile is already the active one: the settings
            -- saved since it loaded, locks and moves too, are what was left.
            state.last_job=snapshot.job;
            local profile=state.settings.job_profiles[tostring(snapshot.job)] or state.settings.job_profiles[snapshot.job];
            if profile and profile~='' and profile~=state.settings.active_profile then
                local ok,why=callbacks.profile_load(profile);
                if not ok then problem(why); end
            elseif state.job_seen and state.unread~=state.path then
                -- Nothing loads, so nothing saves the new job with the settings, and a later login needs it to tell
                -- whether the job changed. The job the first refresh after a load sees is only read: loading
                -- writes nothing.
                state.dirty=true;
            end
        end
        state.job_seen=true;
    end
    -- The queue is taken first: an observation that can't be read goes with its frame, not again on every refresh.
    local queue=state.queue;
    state.queue={};
    -- Duration overrides and learned times set the estimates first, and mark your own casts to learn from.
    require('core.durations').prepare(queue,state.settings,snapshot);
    tracker:observe(queue,t,snapshot);
    tracker:reconcile(snapshot,t);
    split('first_refresh.tracker');
    local screen=imgui.GetIO().DisplaySize;
    local width,height=math.floor(screen.x),math.floor(screen.y);
    -- The chat log moves only when the player moves it, so its place is read about once a second, and at once when the
    -- screen size changed or the last read failed. Between reads each snapshot keeps the last one.
    local last=state.snapshot;
    if last.chat and t>=state.chat_read_at and t-state.chat_read_at<1 and state.chat_width==width and state.chat_height==height then
        snapshot.chat,snapshot.chat_problem,snapshot.chat_area=last.chat,last.chat_problem,last.chat_area;
    else
        snapshot.chat,snapshot.chat_problem=chat_window.read(width,height);
        -- Where the game's chat log is, or usually is when it can't be read: fresh spots and the Size buttons keep clear
        -- of it.
        snapshot.chat_area=require('ui.layout').chat_area(width,height,snapshot.chat);
        state.chat_read_at,state.chat_width,state.chat_height=t,width,height;
    end;
    split('first_refresh.chat');
    -- A fresh install places its displays once its screen and chat log are known, clear of the chat log: once the
    -- displays may draw, as the chat log is read by a warmup step.
    if state.place_fresh and state.ready~=false and screen.x>0 and screen.y>0 then
        state.place_fresh=nil;
        require('ui.setup_defaults').place_fresh(state.settings,{width=screen.x,height=screen.y,chat=snapshot.chat});
    end;
    state.snapshot=snapshot;
    state.view=tracker:view(t,state.settings,snapshot);
    split('first_refresh.view');
    local options=recast_options();
    local demand=tostring(options.spells)..tostring(options.abilities)..tostring(options.items);
    if state.recast_sampled==nil or t-state.recast_sampled>=0.1 or state.recast_demand~=demand then
        recasts:update(snapshot,t,options);
        state.recast_sampled,state.recast_demand=t,demand;
    end;
    state.recasts=recasts:view(t);
    -- Spell rows you can't afford, and rows locked by what is on you, tint (core/recast_tints.lua).
    require('core.recast_tints').mark(state.recasts.rows,snapshot,state.settings);
    state.view.recast_version=state.recasts.version;
    for _,row in ipairs(state.recasts.rows or {}) do state.view.rows[#state.view.rows+1]=row; end;
    split('first_refresh.recasts');
    if force_roster or needs_party_roster() then
        state.roster=party_roster.read(t,snapshot);
        state.roster_ready=needs_party_roster();
    else
        state.roster={valid=false,members={},typing=snapshot.chat_open==true};
        state.roster_ready=false;
    end
    split('first_refresh.roster');
    -- The game's party list (your party's window) for the displays that follow it and a move that snaps to it. Its
    -- client patterns are warmup steps, asked for once a display needs them (the strips' Treasure Pool check too), and
    -- it is read here only once they have run, by the refresh after the last one (settle_ready).
    local party_window=nil;
    if state.settings.party_ui.enabled then warmup.want('party'); end;
    if state.roster.valid and native_party.geometry and wants_party_list(state.settings) then
        if warmup.need('party') then
            state.party_list_waits=true;
        else
            local geometry=native_party.geometry(state.roster,math.floor(screen.x),math.floor(screen.y));
            party_window=geometry and geometry.available and geometry.groups[1] or nil;
        end;
    end;
    elements.party_list=party_window;
    -- What the settings draw with is asked for by now, once a refresh has read them: not at the title screen or a
    -- loading screen, where it reads none. After a load the displays wait for this too, so a command or a refresh
    -- before it can't let them draw without XI View or the game's party list. If a command at the title screen let
    -- them draw with the defaults, they wait again from here for what these settings ask for.
    if state.identity and warmup.asked() then state.ready=false; end;
    -- Each display's show conditions, from where you are now.
    conditions.update(state.settings,snapshot);
    state.party_subjects,state.party_remapped=party_subjects(state.view);
    -- The party cooldown watch: each member's estimates for the strips and overhead blocks, and its list's.
    -- While zoning the snapshot lists no one, which is no reason to drop the members.
    state.view.cooldowns=cooldown_watch:refresh(t,state.settings,snapshot.valid and snapshot.party or nil,state.roster);
    state.view.member_cooldowns=cooldown_watch.estimates;
    for id,subject in pairs(state.party_subjects) do subject.cooldowns=cooldown_watch:of(id); end
    -- The Phantom Roll display's rolls and the pet display's pet, from this refresh's view and recasts.
    state.view.rolls=roll_watch:refresh(t,state.settings,snapshot,state.view.rows);
    state.view.pet=pet_watch:refresh(t,state.settings,snapshot,state.party_subjects,state.recasts.rows);
    local events=tracker:drain_events();
    -- A wear-off of your own cast adds its time to the learned ones once nothing spoiled it for a second, saved with
    -- the settings but kept out of Undo. A fight can learn many, so they wait for the next save, at most a minute. Each
    -- counts as a change, so what the settings window shows of them is made again.
    if require('core.durations').learn(state.settings,tracker:samples(t)) then
        state.learned_at,state.settings_revision=state.learned_at or t,state.settings_revision+1;
    end;
    local recast_events=recasts:drain_events();
    -- A long recast that becomes ready, or comes within its early warning, starts a ready pulse.
    state.view.pulses=ready_pulses:update(state.recasts.rows,recast_events,state.settings,t);
    for _,event in ipairs(recast_events) do events[#events+1]=event; end;
    if state.settings.diagnostics and state.settings.diagnostics.record then
        for _,event in ipairs(events) do
            state.report[#state.report+1]=store.copy(event);
            if #state.report>state.settings.diagnostics.max_entries then table.remove(state.report,1); end
        end
    else state.report={}; end
    alerts:update(state.view,events,state.settings.alerts.rules,t,{
        enabled=state.settings.alerts.enabled,
        muted=state.settings.alerts.muted,
        quiet=state.settings.alerts.quiet_events and (snapshot.in_event or snapshot.dead or not snapshot.valid),
        watch_ids=state.settings.watch_ids,list_debuffed=state.settings.panels.watch.list_debuffed,
        enrich=enrich_rule,
        enrich_context=alert_names(),
    });
    state.view.notices=alerts:view(t);
    state.sampled=t;
    -- The first snapshot of the player in the new zone ends the wait of its zone window in /vg report.
    if state.zone_entered and snapshot.valid then
        state.zone_entered=false;
        if performance then performance.zone_ready();end;
    end;
    split('first_refresh.rest');
    if performance then performance.record('frame.refresh',started);end;
end

-- Ashita's /hideui keeps every Vantage panel off the screen, as /vg hide does. Only a hide seen at two Presents in a
-- row counts, as one can end in the same Present, before anything is drawn.
local function read_gui_visible() return AshitaCore:GetGuiManager():GetVisible(); end;

-- A report a settings page asked for, written after the page, whether it ended or failed.
local function export_pending()
    if not state.export_pending then return; end;
    state.export_pending=nil;
    local saved,issue=callbacks.export_report();
    if not saved then problem(issue or 'The report could not be saved.'); end;
end;

-- Whether the user's own rules hide the panels, and with them the settings window, for this snapshot.
local function hidden_by_rules(settings,snapshot)
    local rules=settings.visibility;
    return (rules.hide_events and snapshot.in_event) or (rules.hide_map and snapshot.map) or (rules.hide_ui and snapshot.hidden) or false;
end;

-- A copy parked by a save that failed on a character since switched away from is written once its file can
-- be. That character's shared-layout publish waits for its next login.
local function retry_unsaved(t,force)
    for path,copy in pairs(state.unsaved) do
        if path~=state.path and (force or t>=(state.unsaved_retry_at or 0)) then
            if store.write(path,copy) then state.unsaved[path]=nil; else state.unsaved_retry_at=t+5; end
        end
    end
end;

-- What Present hands the party list strips and the buff controls. Present refills the values each frame, so the
-- callbacks are made once.
local party_options={
    begin_edit=function() callbacks.changed('before','Party layout'); end,
    end_edit=function() end,
    changed=function() callbacks.changed('after',nil,'party'); end,
};
local function present()
    local t=now();
    local gui_ok,gui_visible=pcall(read_gui_visible);
    local gui_hidden=gui_ok and gui_visible==false;
    state.gui_off,state.gui_hidden=gui_hidden and state.gui_hidden==true,gui_hidden;
    local displays_hidden=state.hidden or state.gui_off;
    -- A press with Shift held may start a Shift drag, so wants_party_list has the game's party list read now and the
    -- drag can snap to it from its first move.
    local shift_drag=callbacks.shift==true and imgui.IsMouseDown~=nil and imgui.IsMouseDown(0)==true;
    local pressed=shift_drag and not state.shift_drag;
    state.shift_drag=shift_drag;
    local due=t-state.sampled>=0.1 or state.sampled<0 or state.wake or pressed and wants_party_list(state.settings)
        or needs_party_roster() and not state.roster_ready;
    if not due and state.snapshot.valid and client.visibility then
        -- The map, events, the hidden UI and chat send no packet. Catch them now, not up to 0.1 s later.
        local ok,live=pcall(client.visibility,state.snapshot);
        if ok and type(live)=='table' then
            for _,key in ipairs(visibility_keys) do
                if (live[key]==true)~=(state.snapshot[key]==true) then due=true;break;end;
            end;
        end;
    end;
    if due then
        refresh(t);
        state.wake = false;
    end
    if t~=state.sampled then tracker:project(state.view,t,state.party_remapped); recasts:project(state.recasts,t); end
    local focused=game_focused();
    callbacks.focused=focused;
    local ok,shift=true,false;
    if focused then ok,shift=pcall(shift_held); end;
    callbacks.shift=ok and shift or false;
    -- Edit mode moves every display itself, so their own Shift drags wait while it is on.
    callbacks.editing,callbacks.typing=require('ui.edit_mode').active(),state.snapshot.chat_open==true;
    state.view.notices=alerts:view(t);
    -- Settings edits and a newer shared layout land before any panel is drawn, so this frame's
    -- panels already follow them. The window isn't drawn the frame it appears: nothing in it can be
    -- edited yet, and the next frame creates it after every panel exists, so it opens on top of them.
    local measured=performance and performance.now();
    -- Nothing draws until the warmup has made what the displays draw with (core/warmup.lua): not the settings window,
    -- the panels, the party list strips or edit mode. The refresh above keeps running all the same.
    local settings_shown=state.ready~=false and not hidden_by_rules(state.settings,state.snapshot) and not settings_stopped();
    if settings_shown and (state.settings_window_shown or not state.settings.window.open) then
        -- A page that fails still ends this frame, so no panel draws inside its open window, and
        -- everything it changed is put back. It stays stopped, so the next frames draw every panel.
        -- Each stop is reported, even when it repeats the last error.
        local open=state.settings.window.open==true;
        if open then keep_editing(); end;
        local ok,why=pcall(window.draw,state.settings,state.view,callbacks);
        if not ok then
            state.settings_stopped,state.settings_window_shown,state.problem,state.failing=true,false,nil,{};
            if open then restore_editing(); end;
            export_pending();
            error(why,0);
        end;
        if open then finish_editing(); end;
        export_pending();
    end
    state.settings_window_shown=settings_shown and state.settings.window.open==true;
    if performance then performance.record('draw.settings',measured);end;
    local mouse_down=false;
    if imgui.IsMouseDown then mouse_down=imgui.IsMouseDown(0); end
    -- Party list strip drags move their settings while the mouse is down and report the change when they draw
    -- after release, after this poll. The release frame doesn't poll.
    local held=mouse_down or state.mouse_held;
    state.mouse_held=mouse_down;
    if state.settings.shared_layout and not state.dirty and not state.publish_pending and t-state.shared_at>2 and not held then
        -- The file this character last read or wrote is in its settings already.
        local layout,issue,unchanged=saved_profiles:read_layout();
        if not layout and issue then problem(issue); end
        if layout and not unchanged then
            local before=(#state.history>0 or #state.redo>0 or state.transaction) and shared_layouts(state.settings);
            local loaded,why,found,changed=saved_profiles:load_layout(state.settings,nil,layout);
            if not loaded and why then problem(why); end
            if loaded and found then
                state.shared_value=profiles.capture_layout(state.settings);
                if changed~=false then
                    state.profile_summary_cache,state.settings_revision=nil,state.settings_revision+1;
                    if before then rebase_history(before,shared_layouts(state.settings)); end;
                end;
            end
        end
        state.shared_at=t;
    end
    local s=state.settings;
    local visibility=effect_filters.compile(s.effect_filters);
    if visibility.active and (state.filter_snapshot~=state.snapshot or state.filter_roster~=state.roster) then
        state.filter_recipients=effect_filters.recipients(state.snapshot,state.roster);
        state.filter_snapshot,state.filter_roster=state.snapshot,state.roster;
    end;
    callbacks.effect_filters=visibility;
    callbacks.effect_recipients=visibility.active and state.filter_recipients or nil;
    state.view.effect_recipients=callbacks.effect_recipients;
    local blocked=state.ready==false or hidden_by_rules(s,state.snapshot);
    measured=performance and performance.now();
    -- Size labels drawn this Present keep clear of the displays drawn in it and in the last one.
    require('ui.resize').frame();
    require('ui.elements').frame();
    if not blocked then
        if not displays_hidden then
            hud.draw(state.view,s,t,callbacks);
        else
            if hud.cancel_gesture then hud.cancel_gesture(); end
            hud.draw_notices(state.view,s,t,callbacks);
        end
    elseif hud.cancel_gesture then
        hud.cancel_gesture();
    end
    if blocked then
        if hud.cancel_notice_gesture then hud.cancel_notice_gesture(); end
        if window.cancel_resize then window.cancel_resize(); end
    end
    if performance then performance.record('draw.hud',measured);measured=performance.now();end;
    local mx,my=imgui.GetMousePos();
    local over_editor=not focused or callbacks.settings_blocks_input(mx,my,callbacks.shift,state.snapshot.chat_open);
    -- The strips and their Treasure Pool check wait while the game's party list steps are still to run, as the refresh
    -- does, so no draw searches for it: strips turned on after the displays opened ask for them here.
    local party_waits=s.party_ui.enabled and require('core.warmup').need('party');
    -- The Treasure Pool draws each member's lot or pass inside the game's party windows, so the strips step aside
    -- while it is open.
    local treasure_open=state.ready~=false and not party_waits and s.party_ui.enabled and not s.party_ui.preview and native_party.treasure_open()==true;
    -- The strips' show conditions hide them, unless their samples or edit mode show them.
    if state.ready~=false and not party_waits and not displays_hidden and not treasure_open and (s.party_ui.preview or callbacks.editing or require('core.conditions').shown('party_ui')) then
        party_options.shift,party_options.global_style,party_options.cooldowns=callbacks.shift and not callbacks.editing,s.style,s.party_cooldowns;
        -- A strip's Shift drag snaps by the main page's Grid and snapping settings.
        party_options.settings,party_options.revision=s,state.settings_revision;
        party_options.input_blocked=over_editor;
        -- Party list samples go over an open settings window, outside edit mode.
        party_options.samples_over=s.window.open==true and not callbacks.editing;
        party_options.effect_filters,party_options.effect_recipients=visibility,callbacks.effect_recipients;
        native_hud.draw(state.roster, state.party_subjects or {}, s.party_ui, t, party_options);
    else native_hud.cancel_layout_gesture(); end
    if performance then performance.record('draw.party',measured);end;
    -- Edit mode's outlines and bar go over every display drawn above.
    if not blocked and not displays_hidden then require('ui.edit_mode').draw(s,callbacks);
    else require('ui.edit_mode').cancel_gesture(); end;
end

-- Alerts, saves and file undos, run after present by the Present handler, each on its own, so a display that fails on
-- every frame stops none of them.
local function after_present()
    local t=now();
    local ok,why=pcall(deliver,t);
    if not ok then keeps_failing('An alert could not be given.',why); end;
    if state.learned_at and (t-state.learned_at>=60 or t<state.learned_at) then state.dirty=true; end;
    local read,mouse_down=false,false;
    if imgui.IsMouseDown then read,mouse_down=pcall(imgui.IsMouseDown,0); end;
    -- A shared layout still to publish is retried by save on its own, backed-off time.
    if not (read and mouse_down) and (state.dirty and t>=state.retry_at and t-state.changed_at>=0.6
        or state.publish_pending and not state.dirty and t>=state.publish_at) then
        ok,why=pcall(save);
        if not ok then keeps_failing('Your changes could not be saved.',why); end;
    end
    ok,why=pcall(retry_unsaved,t);
    if not ok then keeps_failing('A settings file could not be saved again.',why); end;
    ok,why=pcall(undo_later,t);
    if not ok then keeps_failing('A file change could not be undone.',why); end;
end

-- A character whose saved look uses XI View reads, parses and uploads the parts of it that look draws with on the
-- zone-in packet that brings it in, inside the loading screen, so neither its first frame nor its first buff waits for
-- them. Any XI View warmup step still to run is done then too. Once for each character. At /load the warmup's XI View
-- steps do this for the character in the game. Other looks, and the parts a look doesn't use, leave XI View for its
-- first use.
local xiview_checked;
local function preload_saved_xiview(id,name)
    if not id or not name then return; end;
    local key=tostring(id)..':'..name;
    if xiview_checked==key then return; end;
    xiview_checked=key;
    local started=performance and performance.now();
    local saved=store.read(folder..name:gsub('[^%w_-]',''):sub(1,40)..'_'..tostring(id)..'/settings.json');
    local appearance=require('ui.appearance');
    if type(saved)=='table' and next(saved)~=nil and appearance.uses_xiview(saved) then
        appearance.preload_xiview();
        -- The warmup's XI View steps find it made, so they are run now too and no display waits on them.
        warmup.want('xiview');
        warmup.drain('xiview');
    end;
    if performance then performance.record('zone.xiview_preload',started);end;
end;

-- The warmup's steps in the order they run: the client patterns for the game clock, the interface flags and the chat
-- log; the stock client art, the client's bitmap font, the status icons and recast icons; XI View's once a look uses it;
-- the game's party list once a display needs it; the name point's once overhead icons are on, which only the overhead
-- blocks wait for. An owner without steps runs its one-shot load as one, and one whose list fails gives a step that
-- says so.
local function warmup_list()
    local function steps(name,fallback,label)
        local ok,owner=pcall(require,name);
        if not ok or type(owner)~='table' then return {}; end;
        if type(owner.warmup_steps)=='function' then
            local made,list=pcall(owner.warmup_steps);
            if made and type(list)=='table' then return list; end;
            return {{name=name,run=function() error(list,0); end}};
        end;
        if fallback and type(owner[fallback])=='function' then return {{name=label,run=owner[fallback]}}; end;
        return {};
    end;
    -- what names each owner's steps in chat, should one fail.
    return {
        {group='start',steps=steps('core.clock'),what='the game clock'},
        {group='start',steps=steps('core.client','load','client.load'),what='the event, map and hidden interface checks'},
        {group='start',steps=steps('core.chat','load','chat.load'),what='the chat log position'},
        {group='assets',steps=steps('ui.fonts'),what='the client art and fonts'},
        {group='assets',steps=steps('ui.icons','prepare','icons.prepare'),what='the status icons'},
        {group='assets',steps=steps('ui.recast_icons','prepare','recasts.prepare'),what='the recast icons'},
        {group='xiview',deferred=true,steps=steps('ui.appearance','preload_xiview','xiview.preload'),what='XI View\'s art',
            note='Runs once a look uses XI View.'},
        {group='party',deferred=true,steps=steps('core.native_party_ui'),what='the game\'s party list',
            note='Runs once a display needs the game\'s party list.'},
        {group='names',deferred=true,displays=false,steps=steps('core.name_anchor'),what='the name points for overhead icons',
            note='Runs once overhead icons are on.'},
    };
end;

ashita.events.register('load','vantage_load',function()
    -- The module requires before this, from when core/performance.lua loaded.
    if performance then performance.record('load.requires',0);end;
    local began=performance and performance.now();
    -- A part that fails is said once, as a failed warmup step is, and the rest still loads.
    local failed={};
    local function prepare(stage,what,callback)
        local started=performance and performance.now();
        local ok,why=pcall(callback);
        if performance then performance.record(stage,started);end;
        if not ok then failed[#failed+1]={stage,what,why}; end;
    end;
    -- Only what must happen in the load event: ImGui takes new fonts only now (ui/fonts.lua), the menu fonts from their
    -- cache, and the sound list.
    prepare('load.fonts','the fonts',fonts.load);
    prepare('load.sound','the sound list',sound.refresh);
    say('Ready. /vantage opens the settings.');
    -- The rest runs as warmup steps from the second Present on, and the displays draw once they have run and a refresh
    -- has read the settings, the first with a character in the game.
    state.split_refresh=performance~=nil or nil;
    warmup.start(warmup_list(),problem);
    for _,failure in ipairs(failed) do warmup.fail(failure[1],failure[2],failure[3]); end;
    warmup.reloaded();
    settle_ready();
    if performance then performance.record('load.event',began);end;
end);

ashita.events.register('unload','vantage_unload',function()
    warmup.unloading();
    local function close(callback)
        local ok,why=pcall(callback);
        if not ok then pcall(say,'A display could not close cleanly. '..tostring(why)); end;
    end;
    -- No warmup step runs after this. What the steps uploaded so far is released below with the rest.
    close(warmup.reset);
    close(function()finish_layout(true);end);
    close(save);
    close(function()retry_unsaved(now(),true);end);
    close(sound.close);
    close(icons.clear);
    close(recast_icons.clear);
    close(function() require('ui.client_assets').clear(); end);
    warmup.unloaded();
end);

-- Managed textures survive a Reset, but belong to the device that made them. When the game makes a new device,
-- the icon and client art textures are cleared and made again on it.
local device;
local function read_device() return AshitaCore:GetDirect3DDevice(); end;
local function check_device()
    local ok,current=pcall(read_device);
    if not ok or type(current)~='number' or current==0 then return; end;
    local previous=device;
    -- Kept first, so a rebuild that fails is reported once instead of tried again every frame.
    device=current;
    if not previous or current==previous then return; end;
    local rebuilt,why=pcall(function()
        icons.clear();
        recast_icons.clear();
        require('ui.client_assets').clear();
        -- After a load the warmup makes the art again over the next Presents, and the displays wait for it as they did
        -- then. Before one, the icons are made now.
        local restarted=warmup.restart('assets');
        warmup.restart('xiview');
        if not restarted then
            icons.prepare();
            recast_icons.prepare();
        end;
    end);
    if not rebuilt then problem('Icons could not be made again for the new graphics device. '..tostring(why)); end;
end;

-- Whether a display shows this entity or the Watch list holds it.
local function shown_or_watched(id)
    for _,subject in ipairs(state.view.subjects or no_subjects) do if subject.id==id then return true; end end
    for _,held in ipairs(state.settings.watch_ids) do if held==id then return true; end end
    return false;
end;

ashita.events.register('packet_in','vantage_packet_in',function(e)
    if e.injected or e.blocked then return; end
    local id=e.id;
    if refresh_packets[id] then state.wake=true; end
    -- Each read of an event's data copies the packet, so a packet the observer takes is read once, here, for it and
    -- the overhead icons.
    local observed=not observer.interested or observer.interested(id);
    local size,data=0,nil;
    if observed and client.packet_size then size,data=client.packet_size(e); end
    -- Entity indexes and mob claims for the overhead icons, and the blue magic you have set.
    local read,why=pcall(overhead.packet,e,data and size,data);
    if not read then keeps_failing('An entity update could not be read.',why); end;
    read,why=pcall(dispel.packet,e);
    if not read then keeps_failing('The blue magic you have set could not be read.',why); end;
    -- A zone-in says whether it brings you into a Mog House, for the show conditions.
    read,why=pcall(conditions.packet,e);
    if not read then keeps_failing('The zone you entered could not be read.',why); end;
    if id==0x00A and client.zone_in_identity then
        local ok,why=pcall(function() preload_saved_xiview(client.zone_in_identity(e)); end);
        if not ok then problem('XI View could not be read. '..tostring(why)); end;
    end;
    if not observed then return; end
    local ok,result=pcall(observer.read,e,now(),state.snapshot,size,data);
    if not ok then keeps_failing('A status update could not be read.',result); return; end
    -- A job ability the player used names the status its recast can show.
    recast_icons.learn(result,state.snapshot);
    -- Phoenix sends your 0x037 after any HP, MP or TP change too, so it wakes a refresh only when your status icons
    -- changed.
    local woken=id==0x037 and client.icons_changed~=nil and client.icons_changed();
    for _,observation in ipairs(result or {}) do
        if observation.kind=='reset' then
            clear_zone(observation.reason or 'zone',now());
            state.sampled=-1;
        elseif observation.kind=='cooldown' or observation.kind=='cooldown_reset' then
            -- A member's watched ability goes to the party cooldown watch, and shows from the next refresh.
            if state.settings.party_cooldowns.enabled then cooldown_watch:observe(observation,now()); end
        elseif observation.kind=='roll' then
            -- A roll goes to the Phantom Roll display, and what the pet display follows goes to it, on or off.
            if state.settings.rolls.enabled then roll_watch:observe(observation,now()); end
        elseif pet_watch.takes[observation.kind] then
            pet_watch:observe(observation,now(),state.snapshot);
        -- Hits stop taking room once the queue is half full, so the wear-offs and despawns behind them still fit.
        elseif #state.queue<(observation.kind=='damage' and 128 or 256) then
            state.queue[#state.queue+1]=observation;
        end
        -- A hit only takes effects off, and a fight sends many, so it waits for the next refresh, as does an entity
        -- leaving view that no display shows. A party cooldown wakes it only while the watch keeps them.
        local kind=observation.kind;
        if kind=='cooldown' or kind=='cooldown_reset' then woken=woken or state.settings.party_cooldowns.enabled;
        elseif kind=='despawn' then woken=woken or shown_or_watched(observation.entity_id);
        elseif kind~='damage' then woken=true; end
    end
    -- A zone change the client takes starts the zone window in /vg report.
    if id==0x00A and size>=50 or id==0x00B and size>=5 then
        if performance then performance.zone_begin();end;
        -- Only an arrival brings the player into the new zone; a departure still has the old zone's snapshot.
        state.zone_entered=id==0x00A;
    end;
    if woken then state.wake=true; end
end);

-- Where the overhead icons go this frame, from the view the refresh made, and the icons drawn there with the
-- frame's hide rules, then the sample block while their Sample displays is on. A calibration asked for by command
-- reads the target and camera here, at the frame's own capture point, and its lines go to chat and the report.
local function overhead_frame()
    -- Its icons wait for the warmup's art as the other displays do; the name point has its own wait (core/overhead.lua).
    -- Meanwhile no scene read is kept for the first frame after.
    if state.ready==false then camera.skip(); return; end;
    local started=performance and performance.now();
    local t=now();
    -- Their show conditions hide the blocks over heads; the samples still show.
    local lines=overhead.update(state.view,state.settings,state.snapshot,t,state.hidden or state.gui_off,not conditions.shown('overhead'));
    overhead_icons.draw(overhead.plan,state.party_subjects,state.settings,t,callbacks.effect_filters,callbacks.effect_recipients);
    overhead_preview.draw(state.settings,state.snapshot,t,callbacks.effect_filters,callbacks.effect_recipients);
    if performance then performance.record('frame.overhead',started);end;
    if lines then
        for _,line in ipairs(lines) do say(line); end;
        local saved,issue=callbacks.export_report(true);
        if not saved then problem(issue or 'The report could not be saved.'); end;
    end;
end;

-- In scene mode the overhead camera is read at a BeginScene; otherwise this only counts them for /vg report.
ashita.events.register('d3d_beginscene','vantage_overhead_scene',function(backbuffer)
    local ok,why=pcall(camera.scene,backbuffer);
    if not ok then keeps_failing('The overhead camera could not be read.',why); end;
end);

ashita.events.register('d3d_present','vantage_present',function()
    local began=performance and performance.now();
    check_device();
    -- This Present's budgets: party icons made at their drawn size, and new 32 px status and action icon textures. The
    -- sized icons let go of earlier are released.
    pcall(require('ui.client_assets').icon_frame);
    -- This Present's warmup steps, before anything reads or draws.
    pcall(warmup.frame,began);
    settle_ready();
    -- Nothing else says the client's patterns came up short, so the first Present that can draw does, once.
    if state.ready and not state.client_checked then
        state.client_checked=true;
        local read,found=pcall(client.capabilities);
        if read and not (found.timers and found.map and found.hidden and found.event) then
            say('Part of this game client was not found, so some of Vantage is off. /vg report says which part.');
        end;
    end;
    local started=performance and performance.now();
    text_metrics.begin_frame();
    if client.frame_begin then client.frame_begin(); end;
    local mark=imgui_scopes.depth();
    local ok,why=pcall(present);
    -- A display that failed partway leaves the windows, fonts and styles it opened closed again.
    if not ok then imgui_scopes.close(mark); end;
    text_metrics.end_frame();
    if performance then performance.record('frame.render',started);end;
    if not ok then
        finish_layout(true);
        keeps_failing('The display could not update.',why);
    end;
    after_present();
    local placed,issue=pcall(overhead_frame);
    if not placed then keeps_failing('Overhead icons could not be drawn.',issue); end;
    if client.frame_end then client.frame_end(); end;
    warmup.frame_end();
end);

-- A command that shows the settings window also brings it back after a page error stopped it.
local function show_settings(tab)
    state.settings.window.open,state.settings.window.tab,state.settings_stopped=true,tab,nil;
end;

-- /vg party show, hide, preview, live, lock and unlock, as one Undo step that saves.
local function strip_command(p,action)
    callbacks.changed('before','Party '..action);
    if action=='show' or action=='live' then p.enabled,p.preview,state.hidden=true,false,false;
    elseif action=='hide' then p.enabled,p.preview=false,false;
    elseif action=='preview' then p.enabled,p.preview,state.hidden=true,true,false;
    else p.locked=action=='lock'; end;
    -- Showing them with every group off shows your party's, as the main page does.
    if action=='show' or action=='live' or action=='preview' then require('ui.party_defaults').ensure_strip(p); end;
    callbacks.changed('after'); save();
end;

local function run_command(e)
    local args=e.command:args();
    finish_layout();
    local command=(args[2] or ''):lower();
    if command=='' or command=='settings' then
        if not state.settings.window.open then
            show_settings('Home');
            if hidden_by_rules(state.settings,state.snapshot) then say('The settings window shows when the event, map or hidden interface ends.'); end
        else
            -- A stopped window isn't on screen, so this closes it too and the next /vg opens it and tries
            -- it again. The close is saved, so the window doesn't open (or fail) again on the next load.
            local stopped=settings_stopped();
            state.settings.window.open=false;
            callbacks.editor_changed();save();
            if stopped then say('The settings window closed after an error. /vg opens it again.'); end
        end;
    elseif command=='sort' then
        local choice=(args[3] or ''):lower();
        local labels={longest='longest remaining first',oldest='oldest applied first',remaining='soonest expiring first',name='by name'};
        if not labels[choice] or args[4] then say('Usage: /vg sort longest|oldest|remaining|name'); return; end;
        callbacks.changed('before','Buff and debuff sorting');
        state.settings.party_ui.effects.sort=choice;
        for _,id in ipairs({'self_buffs','self_debuffs','target','party','watch'}) do state.settings.panels[id].sort=choice; end;
        callbacks.changed('after'); state.wake=true;
        local saved=save();
        say('Buffs and debuffs now sort '..labels[choice]..'. Pinned effects stay first; saved custom orders remain available. /vg undo restores the previous sorting.'
            ..(saved and '' or ' Settings could not be saved; Vantage will retry.'));
    elseif command=='filters' then
        show_settings('Filters');
    elseif command=='party' or command=='alliance' then
        local action=(args[3] or ''):lower();
        if action=='' or action=='config' or action=='settings' then
            show_settings('Party & alliance');
        elseif ({show=true,hide=true,preview=true,live=true,lock=true,unlock=true})[action] and not args[4] then
            strip_command(state.settings.party_ui,action);
        else say('Usage: /vg party [config|show|hide|preview|live|lock|unlock]'); end
    elseif command=='recasts' then
        local action=(args[3] or 'config'):lower();
        if action=='config' and not args[4] then show_settings('Recasts');
        elseif (action=='combine' or action=='separate') and not args[4] then
            finish_layout();
            callbacks.changed('before','Recast display');
            state.settings.recast_display=action=='combine' and 'combined' or 'separate';
            callbacks.changed('after'); save(); state.wake=true;
        elseif (action=='show' or action=='hide') and not args[4] then
            callbacks.changed('before','Recasts '..action);
            for _,key in ipairs(defaults.recast_panel_order(state.settings)) do
                local panel=state.settings.panels[key];
                if panel then
                    panel.enabled=action=='show';
                    if action=='show' then defaults.ensure_recast_kind(panel); end;
                end;
            end;
            if action=='show' then state.hidden=false; end;
            callbacks.changed('after'); save(); state.wake=true;
        else say('Usage: /vg recasts [config|combine|separate|show|hide]'); end;
    elseif command=='show' or command=='hide' then
        state.hidden=command=='hide';
    elseif command=='preview' then
        local s,shown=state.settings,true;
        local ending=defaults.samples_showing(s);
        callbacks.changed('before',ending and 'End samples' or 'Show samples');
        if ending then defaults.samples_off(s); else shown=defaults.samples_on(s); end
        callbacks.changed('after'); save();
        if not shown then say(defaults.no_samples); end
    elseif command=='minimal' then
        local choice=args[3] and args[3]:lower();
        if args[4] or (choice and choice~='on' and choice~='off') then
            say('Usage: /vg minimal [on|off]');
            return;
        end
        local enabled=choice=='on' or (choice==nil and not state.settings.style.minimal);
        if enabled~=state.settings.style.minimal then
            callbacks.changed('before','No boxes or headings'); state.settings.style.minimal=enabled;
            callbacks.changed('after'); save();
        end
        say(state.settings.style.minimal and 'No boxes or headings is on.' or 'No boxes or headings is off.');
    elseif command=='mute' then
        callbacks.changed('before'); state.settings.alerts.muted=not state.settings.alerts.muted; callbacks.changed('after'); alerts:reset(); save();
        say(state.settings.alerts.muted and 'Alerts are muted.' or 'Alerts are unmuted.');
    elseif command=='lock' or command=='unlock' then
        callbacks.changed('before');
        for _,id in ipairs(defaults.panel_order) do state.settings.panels[id].locked=command=='lock'; end
        state.settings.party_ui.locked=command=='lock';
        state.settings.alerts.notice_locked=command=='lock';
        state.settings.party_cooldowns.list.locked,state.settings.ready_pulse.locked=command=='lock',command=='lock';
        state.settings.rolls.locked,state.settings.pet.locked=command=='lock',command=='lock';
        callbacks.changed('after'); save();
        say(command=='lock' and 'Every display is locked.' or 'Every display is unlocked. Hold Shift and drag one to move it.');
    elseif command=='edit' then
        -- Edit mode on, off, or the other way. Ending it leaves every display where it is.
        local choice=(args[3] or ''):lower();
        if args[4] or choice~='' and choice~='on' and choice~='off' then say('Usage: /vg edit [on|off]'); return; end;
        local on;
        if choice=='on' then on=true; elseif choice=='off' then on=false; end;
        callbacks.edit_mode(on);
        say(edit_mode.active() and 'Edit mode is on. Click a display to pick it; hold Shift and drag to move it. Esc or /vg edit ends it.'
            or 'Edit mode is off. Every display stays where it is.');
    elseif command=='watch' then
        local id=tonumber(args[3]) or (state.snapshot.target and state.snapshot.target.id);
        local ok,why=callbacks.watch(id); if not ok then say(why); end
    elseif command=='unwatch' then
        local id=tonumber(args[3]) or (state.snapshot.target and state.snapshot.target.id);
        local ok,why=callbacks.unwatch(id); if not ok then say(why); end
    elseif command=='undo' or command=='redo' then
        local ok,why=callbacks[command](); if not ok then say(why); end
    elseif command=='get' or command=='set' then
        local path,raw=e.command:match('^%S+%s+%S+%s+(%S+)%s*(.*)$');
        if command=='get' then
            local value,why=customization.get(state.settings,path);
            if value==nil then say(why);
            else say(path..' = '..(type(value)=='table' and store.encode(value) or tostring(value))); end
        else
            local current=customization.get(state.settings,path);
            if type(current)=='string' and raw:sub(1,1)=='"' and raw:sub(-1)=='"' then raw=raw:sub(2,-2); end
            local candidate,why=customization.set(state.settings,path,raw);
            -- What was stored, read back after tidying, so the line says what the setting holds now. One of the Grid
            -- mode ticks is told with the whole list, as tidy keeps it in the displays' order, each once.
            local function confirm(saved)
                local shown=path:match('^(edit_mode%.grid_displays)%.') or path;
                local value=customization.get(state.settings,shown);
                say(shown..' is now '..(type(value)=='table' and store.encode(value) or tostring(value))..'.'
                    ..(saved and '' or ' Settings could not be saved; Vantage will retry.'));
            end;
            if not candidate then say(why);
            elseif path=='shared_layout' or path=='shared_scope' then
                local ok,issue=callbacks.sharing(candidate.shared_layout,candidate.shared_scope);
                if not ok then say(issue); else confirm(true); end
            else
                -- Setting the window open this way tries a stopped one again too, even one still open.
                if candidate.window.open and (path=='window.open' or path=='window') then state.settings_stopped=nil; end;
                callbacks.changed('before','Set '..path); state.settings=candidate;
                callbacks.changed('after'); alerts:reset();
                confirm(save());
            end
        end
    elseif command=='skin' then
        -- A skin's name matches without regard to case, as the other commands' words do. Frameless is the Minimal skin.
        local typed=table.concat(args,' ',3):lower();
        local name=typed=='frameless' and 'Minimal' or nil;
        for _,known in ipairs(require('ui.appearance').names) do if known:lower()==typed then name=known; end end
        local candidate=store.copy(state.settings);
        if name and require('ui.appearance').apply(candidate,name,{matching=true}) then
            callbacks.changed('before','Skin: '..name); state.settings=candidate;
            callbacks.changed('after'); save();
        else say('Choose Phoenix, Classic FFXI, Original FFXI, XI View, Frameless, High contrast, Ember, Mint, Lavender or Colorblind safe.'); end
    elseif command=='font' then
        local name=table.concat(args,' ',3);
        if name=='' then say('Usage: /vg font "Name"'); return; end;
        local candidate,why=customization.set(state.settings,'style.font',name);
        if not candidate then say(why);
        else callbacks.changed('before','Font'); state.settings=candidate; callbacks.changed('after'); save(); end
    elseif command=='starter' then
        local ok,why=callbacks.starter(table.concat(args,' ',3),false); if not ok then say(why); end
    elseif command=='copy' then
        local panel=args[3] or 'self_buffs';
        if state.settings.panels[panel] then
            local ok,why=callbacks.copy_shown(panel,args[4]=='details'); if not ok then say(why); end
        else say('Choose self_buffs, self_debuffs, target, party or watch.'); end
    elseif command=='report' then
        local ok,why=callbacks.export_report(); if not ok then say(why); end
    elseif command=='overhead' then
        local action,o=not args[4] and (args[3] or ''):lower() or '',state.settings.overhead;
        -- Calibrate reads the current target and the camera on the next frame, prints them and writes them to the report.
        if action=='calibrate' then overhead.calibrate(state.settings);
        elseif action=='on' or action=='off' or action=='preview' then
            -- One Undo step that saves. Turning them off ends the samples, and the samples turn them on.
            callbacks.changed('before','Overhead icons '..action);
            if action=='on' then o.enabled,state.hidden=true,false;
            elseif action=='off' then o.enabled,o.preview=false,false;
            else
                o.preview=not o.preview;
                if o.preview then o.enabled,state.hidden=true,false; end;
            end;
            callbacks.changed('after'); save();
            say(action=='preview' and (o.preview and 'Overhead sample icons are on.' or 'Overhead sample icons are off.')
                or o.enabled and 'Overhead icons are on.' or 'Overhead icons are off.');
        else say('Usage: /vg overhead on|off|preview|calibrate'); end
    elseif command=='chatsample' then callbacks.chat_sample();
    elseif command=='profile' then
        local operation=(args[3] or ''):lower();
        local ok,why;
        if operation=='list' then
            local names,issue=callbacks.profile_list();
            if issue then ok,why=false,issue; else say(#names>0 and table.concat(names,', ') or 'No saved profiles.'); ok=true; end
        elseif operation=='recover' then ok,why=callbacks.profile_recover();
        elseif operation=='link' then
            -- The job ID is optional, so the name follows it or takes its place. A quoted name is a name, even
            -- one that reads as a number.
            local job=not e.command:lower():find('link%s+"') and tonumber(args[4]);
            ok,why=callbacks.profile_link(job or state.snapshot.job,args[job and 5 or 4] or '');
        elseif args[4] then
            if operation=='save' then ok,why=callbacks.profile_save(args[4],false);
            elseif operation=='load' then ok,why=callbacks.profile_load(args[4]);
            elseif operation=='delete' then ok,why=callbacks.profile_delete(args[4],callbacks.profile_status(args[4]).token);
            elseif operation=='overwrite' then ok,why=callbacks.profile_save(args[4],true,callbacks.profile_status(args[4]).token);
            elseif operation=='rename' then ok,why=callbacks.profile_rename(args[4],args[5],callbacks.profile_status(args[4]).token); end
        end
        if not ok then say(why or '/vantage profile save|overwrite|load|delete|rename|recover|list|link [job] "Name"'); end
    elseif command=='reset' then
        local last=state.history[#state.history];
        local ok,why=callbacks.reset(args[3]);
        -- A reset with nothing to change makes no step, and Undo would take back something else.
        say(ok and 'Reset '..(args[3] or 'all settings')..'.'..(state.history[#state.history]~=last and ' /vg undo steps back one change.' or '') or why);
    else
        say('/vantage: settings, sort [longest|oldest|remaining|name], filters, party, alliance, recasts, show, hide, preview, minimal [on|off], mute, lock, unlock, edit [on|off], watch, unwatch, undo, redo, profile, reset, get, set, skin, font, starter, copy, report, overhead [on|off|preview|calibrate], chatsample.');
    end
end;

ashita.events.register('command','vantage_command',function(e)
    local args=e.command:args();
    if not identity.command(args[1]) then return; end
    e.blocked=true;
    -- /vg report times itself from here, the drain below too, into the report it writes.
    if (args[2] or ''):lower()=='report' then state.report_started=performance and performance.now(); end;
    -- At the title screen no settings can be read until a character logs in, so what a command shows there (the
    -- settings window, edit mode) draws with the defaults in use. After the login the
    -- zone-in packet loads XI View for a saved XI View look, and the first refresh that reads the settings makes the
    -- displays wait again for the rest of what those ask for.
    if not state.identity and client.identity and not client.identity() then warmup.asked(true); end;
    -- A command finds everything loaded: the warmup's steps still to run run first.
    finish_warmup();
    run_command(e);
    state.report_started=nil;
end);

if VANTAGE_TEST_MODE then return {state=state,tracker=tracker,alerts=alerts,callbacks=callbacks,refresh=refresh,cooldowns=cooldown_watch,
    pulses=ready_pulses,rolls=roll_watch,pet=pet_watch}; end
