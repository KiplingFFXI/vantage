local catalog = require('core.catalog');
local alerts = {};
local methods = {};
methods.__index = methods;

local function selected(list, value)
    if type(list) ~= 'table' then return false; end
    if list[value] == true or list[tostring(value)] == true then return true; end
    for _, item in ipairs(list) do if item == value or tostring(item) == tostring(value) then return true; end end
    return false;
end

local function has_choices(list)
    return type(list) == 'table' and next(list) ~= nil;
end

local function fingerprint(value)
    if type(value) ~= 'table' then return tostring(value); end
    local keys, parts = {}, {};
    for key in pairs(value) do if key~='effect_name' then keys[#keys + 1] = key; end; end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b); end);
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. '=' .. fingerprint(value[key]); end
    return '{' .. table.concat(parts,';') .. '}';
end

local function same(a, b)
    if type(a) ~= type(b) then return false; end
    if type(a) ~= 'table' then return a == b; end
    for key, value in pairs(a) do if not same(value, b[key]) then return false; end end
    for key in pairs(b) do if a[key] == nil then return false; end end
    return true;
end

local function copy(value)
    if type(value) ~= 'table' then return value; end
    local result = {};
    for key, item in pairs(value) do result[key] = copy(item); end
    return result;
end

local function matches(rule, row, view, options)
    local context = view.context or {};
    if (rule.domain or 'status') ~= (row.domain or 'status') then return false; end;
    if rule.entity_id and rule.entity_id ~= 0 and row.entity_id ~= rule.entity_id then return false; end
    if rule.effect and rule.effect ~= 0 and row.effect ~= rule.effect then return false; end
    local scope = rule.scope or 'self';
    if rule.domain == 'recast' then
        if scope ~= 'self' and scope ~= 'recast' and scope ~= 'all' then return false; end;
    elseif scope == 'target' then
        if not context.target or row.entity_id ~= context.target.id then return false; end
    elseif scope == 'watch' then
        -- Whoever Watched enemies lists: the ones you watch, and with its option on the ones you debuff.
        if not selected(options.watch_ids, row.entity_id)
            and not (options.list_debuffed and (row.mine or row.by_pet) and (row.category or row.kind) == 'debuff' and row.scope == 'enemy') then return false; end
    elseif scope == 'party' then
        -- My party takes you in, and your own rows are scoped self.
        if row.scope ~= 'party' and row.scope ~= 'self' then return false; end
    elseif scope ~= 'all' and row.scope ~= scope then
        return false;
    end
    if rule.combat == 'in' and not context.combat then return false; end
    if rule.combat == 'out' and context.combat then return false; end
    if has_choices(rule.jobs) and not selected(rule.jobs,context.job) and not selected(rule.jobs,context.job_name) then return false; end
    return true;
end

-- Whether the same batch has the copy that left back on that entity: the same row renewed, or a new copy of
-- its tier or spell, or for an effect with no other copy left a new one. Another copy renewed or kept
-- doesn't bring back the one that left; the copy leaving isn't another copy.
local function undone(events, index, view)
    local gone = events[index];
    for i = index + 1, #events do
        local event = events[i];
        if (event.kind == 'gain' or event.kind == 'refresh') and event.entity_id == gone.entity_id
            and event.effect == gone.effect then
            if event.key == gone.key then return true; end
            if event.kind == 'gain' then
                if gone.tier ~= nil and event.tier == gone.tier or gone.spell ~= nil and event.spell == gone.spell then return true; end
                local other = false;
                for _, row in ipairs(view and view.rows or {}) do
                    if row.entity_id == gone.entity_id and row.effect == gone.effect and row.key ~= event.key
                        and row.key ~= gone.key and not row.departing then other = true; break; end
                end
                if not other then return true; end
            end
        end
    end
    return false;
end

local function token(row)
    return tostring(row.key) .. ':' .. tostring(row.instance or 1);
end

local function countdown(rule, row)
    if not row or not row.remaining or row.remaining <= 0 or not (row.status == 'server' or row.status == 'estimated') then return false; end
    if rule.unit == 'percent' then
        return row.total ~= nil and row.total > 0 and not (row.duration_min and row.duration_min < row.total);
    end
    return true;
end

local function wording(rule, row, event, threshold)
    local name = row.name;
    if row.domain == 'recast' then
        if event == 'started' then return name .. ' is on cooldown.'; end;
        if event == 'ready' then return name .. ' recast is ready.'; end;
        if rule.unit == 'percent' then return name .. ' recast has ' .. tostring(threshold) .. '% left.'; end;
        return name .. ' recast has ' .. tostring(math.ceil(row.remaining or threshold or 0)) .. ' seconds left.';
    end;
    local recipient = row.scope == 'self' and 'you' or row.entity_name or 'the target';
    if event == 'gain' then return name .. ' on ' .. recipient .. '.'; end
    if event == 'removed' then return name .. ' was removed from ' .. recipient .. '.'; end
    if event == 'missing' then return name .. ' is missing on ' .. recipient .. '.'; end
    if row.status == 'estimated' then return name .. ' on ' .. recipient .. ' may wear off soon.'; end
    if rule.unit == 'percent' then return name .. ' on ' .. recipient .. ' has ' .. tostring(threshold) .. '% left.'; end
    return name .. ' on ' .. recipient .. ' has ' .. tostring(math.ceil(row.remaining or threshold or 0)) .. ' seconds left.';
end

function alerts.new()
    return setmetatable({states={},queue={},notices={},current={},ready=false,last_time=nil,last_sound=-math.huge},methods);
end

function methods:reset()
    self.states,self.queue,self.notices,self.current = {},{},{},{};
    self.ready,self.last_time = false,nil;
    self.last_sound = -math.huge;
    self.compiled, self.disabled = nil, nil;
end

function methods:compile(rules, enrich, context)
    rules = rules or {};
    local held = self.compiled;
    if held and held.enrich == enrich and same(rules, held.source_rules) and same(context, held.context) then return held; end
    held = {source_rules=copy(rules),enrich=enrich,context=copy(context),entries={},active={}};
    for index, source in ipairs(held.source_rules) do
        local rule = enrich and enrich(source,index,context) or copy(source);
        local id = rule.id or tostring(index);
        held.entries[#held.entries+1] = {rule=rule,id=id,stamp=fingerprint(rule)};
        held.active[id] = rule;
    end
    self.compiled = held;
    return held;
end

-- Returns whether the notice was queued: the minimum time between repeats can hold it back, though not a threshold
-- crossed (crossed), as each fires once.
function methods:enqueue(rule,row,event,now,threshold,state,crossed)
    local key = token(row);
    local cooldown = math.max(0,tonumber(rule.cooldown) or 0);
    if not crossed and state.last[key] and now-state.last[key] < cooldown then return false; end
    state.last[key], state.since[key] = now, now;
    local notice = { rule_id=rule.id, token=key, key=row.key, instance=row.instance,
        entity_id=row.entity_id,effect=row.effect,event=event,time=now,
        scope=row.scope,mine=row.mine,by_pet=row.by_pet,category=row.category or row.kind,name=row.name,status=row.status,domain=row.domain,
        ends=now+math.max(1,math.min(30,tonumber(rule.duration) or 4)),
        message=wording(rule,row,event,threshold),visual=rule.visual==true,
        chat=rule.chat==true,sound=rule.sound or '',emphasis=rule.emphasis==true,
        volume=rule.volume or -1,flash=rule.flash==true,flash_color=rule.flash_color,
        flash_ends=now+(rule.flash_seconds or rule.duration or 4),
        threshold=threshold,estimated=row.status=='estimated' };
    if #self.queue >= 32 then table.remove(self.queue,1); end
    self.queue[#self.queue+1] = notice;
    if #self.notices >= 12 then table.remove(self.notices,1); end
    self.notices[#self.notices+1] = notice;
    return true;
end

function methods:update(view,events,rules,now,options)
    options = options or {};
    if self.last_time and (now < self.last_time or now-self.last_time > 10) then self:reset(); end
    self.last_time = now;
    for _, event in ipairs(events or {}) do
        if event.kind == 'reset' then self:reset(); self.last_time=now; break; end
    end
    if options.enabled == false then
        if not self.disabled then
            local last_sound = self.last_sound;
            self:reset();
            self.last_sound, self.disabled = last_sound, true;
        end
        self.last_time = now;
        self.queue, self.notices = {}, {};
        return;
    end
    self.disabled = false;
    local compiled = self:compile(rules, options.enrich, options.enrich_context);
    local current, held, by_entity = {}, {}, {};
    for _, row in ipairs(view.rows or {}) do
        -- A row whose removal was seen is gone here, even while its icon waits for the status update. One a
        -- recast holds is not: its new copy renews it, so it is held like a split send's.
        if not row.departing or row.recast then
            -- A self row a split status send held back may be the copy that left. It isn't present until
            -- the 0x063 says so, but its countdown and notices wait for that instead of starting over.
            -- So do the other copies of its effect: the copy that kept the slot may be the one that left.
            if row.scope == 'self' and (row.present == false or row.unsettled or row.departing) then held[token(row)] = row;
            else current[token(row)] = row; end
            if row.present then
                local rows = by_entity[row.entity_id];
                if not rows then rows = {}; by_entity[row.entity_id] = rows; end
                rows[#rows+1] = row;
            end
        end
    end
    self.current = current;
    local quiet = not view.valid or options.enabled == false or options.muted or options.quiet;
    if quiet then self.queue,self.notices = {},{}; end
    local active_rules = compiled.active;
    for _, entry in ipairs(compiled.entries) do
        local rule, id, stamp = entry.rule, entry.id, entry.stamp;
        local state = self.states[id];
        local baseline = not state or state.stamp ~= stamp or quiet or not self.ready;
        if not state or state.stamp ~= stamp then
            -- last: when each key last notified, for the cooldown. since: when its repeat reminder counts from,
            -- that notice or the last quiet baseline (a reset, a mute, an event). told: when a missing effect was
            -- told in the stretch it has been missing, cleared once it is found.
            state={stamp=stamp,previous={},fired={},last={},since={},told={},missing={},missing_at={}};
            self.states[id]=state;
            for i=#self.queue,1,-1 do if self.queue[i].rule_id==id then table.remove(self.queue,i); end end
            for i=#self.notices,1,-1 do if self.notices[i].rule_id==id then table.remove(self.notices,i); end end
        end
        local previous = {};
        if rule.enabled ~= false then
            if rule.event == 'remaining' then
                for key,row in pairs(current) do
                    if matches(rule,row,view,options) and countdown(rule,row) then
                        local value = row.remaining;
                        if rule.unit=='percent' then
                            local ranged = row.duration_min and row.total and row.duration_min < row.total;
                            value = not ranged and row.total and row.total > 0 and row.remaining/row.total*100 or nil;
                        end
                        if value then
                            previous[key] = value;
                            if baseline then state.since[key] = now; end
                            state.fired[key] = state.fired[key] or {};
                            local chosen;
                            for _, threshold in ipairs(rule.thresholds or {30}) do
                                if type(threshold)=='number' and threshold >= 0 then
                                    if baseline or state.previous[key]==nil then
                                        if value<=threshold then state.fired[key][threshold]=true; end
                                    elseif not state.fired[key][threshold] and state.previous[key]>threshold and value<=threshold then
                                        state.fired[key][threshold]=true;
                                        chosen = not chosen and threshold or math.min(chosen,threshold);
                                    end
                                end
                            end
                            if chosen and not baseline then self:enqueue(rule,row,'remaining',now,chosen,state,true); end
                            local repeat_seconds = tonumber(rule.repeat_seconds) or 0;
                            if repeat_seconds > 0 and not chosen and not baseline and state.since[key]
                                and now-state.since[key]>=repeat_seconds then
                                local nearest;
                                for threshold in pairs(state.fired[key]) do
                                    if value <= threshold then nearest=not nearest and threshold or math.min(nearest,threshold); end
                                end
                                if nearest then self:enqueue(rule,row,'remaining',now,nearest,state); end
                            end
                        end
                    end
                end
                for key in pairs(held) do previous[key] = state.previous[key]; end
            elseif rule.event=='gain' or rule.event=='removed' or rule.event=='started' or rule.event=='ready' then
                if not baseline then
                    for index,event in ipairs(events or {}) do
                        if event.kind==rule.event and not event.quiet and matches(rule,event,view,options)
                            and not (event.kind=='removed' and undone(events,index,view)) then
                            -- An estimated deadline alone never creates a removal event.
                            local key=token(event)..':'..event.kind;
                            if not state.fired[key] then
                                self:enqueue(rule,event,event.kind,now,nil,state);
                                state.fired[key]=true;
                            end
                        end
                    end
                end
            elseif rule.domain~='recast' and rule.event=='missing' and rule.effect and rule.effect~=0
                and not catalog.get(rule.effect).unnamed then
                local missing = {};
                local info = catalog.get(rule.effect);
                for _, subject in ipairs(view.subjects or {}) do
                    local row={entity_id=subject.id,entity_name=subject.name,scope=subject.scope,effect=rule.effect,
                        key='missing:'..subject.id..':'..rule.effect,instance=1,name=rule.effect_name or info.name};
                    if subject.known and matches(rule,row,view,options) then
                        local found=false;
                        for _,held in ipairs(by_entity[subject.id] or {}) do
                            if matches(rule,held,view,options) then found=true; break; end
                        end
                        local key=token(row);
                        if not found then
                            missing[row.key]=true;
                            state.missing_at[row.key]=quiet and now or state.missing_at[row.key] or now;
                            if baseline then state.since[key]=now; end
                            -- Each time it goes missing it is told: at once when an update sees it go, else 3 s
                            -- after it is first seen missing or a quiet spell ends. One the minimum time between
                            -- repeats holds back is told when that time is up, if it is still missing.
                            local due;
                            if not baseline and state.missing[row.key]==false then due=true;
                            elseif not baseline and not state.told[key] and now-state.missing_at[row.key]>=3 then due=true;
                            elseif not baseline and state.missing[row.key]==true and (tonumber(rule.repeat_seconds) or 0)>0 then
                                local since=state.since[key];
                                due=since and now-since>=rule.repeat_seconds;
                            end
                            if due and self:enqueue(rule,row,'missing',now,nil,state) then state.told[key]=now; end
                        else
                            missing[row.key]=false;
                            state.missing_at[row.key],state.told[key]=nil,nil;
                        end
                    end
                end
                state.missing=missing;
                for key in pairs(state.missing_at) do if missing[key]==nil then state.missing_at[key]=nil; end end
            end
        else state.missing, state.missing_at = {}, {}; end
        state.previous=previous;
        for key in pairs(state.fired) do
            if type(state.fired[key])=='table' and not current[key] and not held[key] then
                state.fired[key], state.last[key], state.since[key] = nil, nil, nil;
            end
        end
        -- Gain/removal deduplication only needs the recent event window. A key still shown, held or missing keeps
        -- its notice times: they are its cooldown, its missing notice and its repeat reminder.
        if not state.cleanup_at or now-state.cleanup_at>60 then
            for _, times in ipairs({state.last, state.since, state.told}) do
                for key,at in pairs(times) do
                    if now-at>300 and not current[key] and not held[key]
                        and not (key:sub(-2)==':1' and state.missing[key:sub(1,-3)]~=nil) then times[key]=nil; end
                end
            end
            for key,value in pairs(state.fired) do if value==true then state.fired[key]=nil; end end
            state.cleanup_at=now;
        end
    end
    for id in pairs(self.states) do if not active_rules[id] then self.states[id]=nil; end end
    for _, list in ipairs({self.queue,self.notices}) do
        for i=#list,1,-1 do
            local notice=list[i];
            local rule=active_rules[notice.rule_id];
            local live=current[notice.token] or held[notice.token];
            local gone=notice.event=='remaining' and (not rule or not countdown(rule,live));
            local stale_gain=(notice.event=='gain' or notice.event=='started') and not live;
            local scope_changed=rule and notice.event~='missing' and not matches(rule,live or notice,view,options);
            local held_state=self.states[notice.rule_id];
            local no_longer_missing=notice.event=='missing' and (not held_state or held_state.missing[notice.key]~=true);
            local finished=notice.ends<=now and not (notice.emphasis and notice.flash and (notice.flash_ends or 0)>now);
            if not notice.test and (not rule or gone or stale_gain or scope_changed or no_longer_missing or finished) then table.remove(list,i); end
        end
    end
    self.ready = view.valid and not quiet;
end

function methods:test(rule,now)
    local row={key='test',instance=now,effect=rule.effect,name=rule.effect_name or rule.name or 'Sample effect',
        entity_id=0,entity_name='You',scope=rule.domain=='recast' and 'recast' or 'self',domain=rule.domain,
        remaining=(rule.thresholds or {15})[1] or 15,status='server'};
    local state={last={},since={}};
    self:enqueue(rule,row,rule.event or 'remaining',now,row.remaining,state);
    if self.queue[#self.queue] then self.queue[#self.queue].test=true; end
end

function methods:view(now)
    local result = {};
    for _,notice in ipairs(self.notices) do
        if notice.ends>now or notice.emphasis and notice.flash and (notice.flash_ends or 0)>now then result[#result+1]=notice; end
    end
    return result;
end

-- volume is the shared alert volume. A notice plays at its rule's own volume when that is 0 or more, else at the
-- shared one, as deliver does; at 0 it has no sound, so it doesn't take the one sound a second.
function methods:drain(now, volume)
    local result={};
    local sound_given=false;
    for _,notice in ipairs(self.queue) do
        if notice.ends>now then
            local value={};
            for key,item in pairs(notice) do value[key]=item; end
            local level=(tonumber(value.volume) or -1)>=0 and value.volume or volume;
            if level==0 then value.sound=''; end
            if value.sound~='' then
                if sound_given or now-self.last_sound<1 then value.sound='';
                else sound_given=true; self.last_sound=now; end
            end
            result[#result+1]=value;
        end
    end
    self.queue={};
    return result;
end

return alerts;
