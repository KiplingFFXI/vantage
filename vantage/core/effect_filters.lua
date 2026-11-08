-- These rules change visibility only. Tracking and alerts keep their original data.
local filters = {};
local marker = {};
local empty = {active=false, needs_jobs=false, marker=marker};
local cache = setmetatable({}, {__mode='k'});
-- enemy, other and pet follow the tracker's own scope for the unit.
local scopes = {all=true, self=true, party=true, alliance=true, alliance1=true, alliance2=true,
    enemy=true, other=true, pet=true};
local kinds = {all=true, buff=true, debuff=true, neutral=true};
local no_rules = {};
local rule_fields = {'enabled','effect','kind','name','job','scope'};
-- Copy Image (66) shows its shadows as icons 444, 445 and 446, and every copy leaves the tracker as 66, so a rule for
-- one of them is a rule for 66, or it would never match.
local copy_image = {[444]=66, [445]=66, [446]=66};
-- What subject and subjects worked out, by the subject or map they were given. The same rules, unit and effects
-- give back the same tables, so a display that keeps its rows from frame to frame keeps them under rules too.
local kept_subjects = setmetatable({}, {__mode='k'});
local kept_maps = setmetatable({}, {__mode='k'});
-- The fields of a unit that matches reads, and a unit with none of them.
local unit_fields = {'name','job','group','is_self','player','scope'};
local nobody = {};
-- subjects fills this for a unit the recipients don't list, in place of a new table each call.
local unlisted = {};

local function integer(value, maximum, minimum)
    if type(value)=='number' and value==value and value==math.floor(value)
        and value>=(minimum or 0) and value<=maximum then return value; end;
end;

local function name(value)
    if type(value)~='string' then return ''; end;
    -- Far too long for a name, and this trim takes seconds on a long run of spaces. The length check refuses it.
    if #value>256 then return value; end;
    return value:match('^%s*(.-)%s*$');
end;

-- A rule that hides this one effect for everyone. While it is on it shows on the Hidden everywhere list, and any other
-- rule shows in the Hide only for some players or jobs fold.
function filters.global_rule(rule, effect)
    return rule.effect == effect and rule.kind == 'all' and rule.scope == 'all'
        and rule.name:match('^%s*$') ~= nil and rule.job == 0;
end

function filters.listed(rule)
    return rule.enabled and rule.effect > 0 and filters.global_rule(rule, rule.effect);
end

function filters.rule()
    return {enabled=true, effect=0, kind='all', name='', job=0, scope='all'};
end;

function filters.make()
    return {enabled=true, rules={}};
end;

function filters.tidy(value)
    local out = filters.make();
    if type(value)~='table' then return out; end;
    out.enabled = value.enabled==nil or value.enabled==true;
    if type(value.rules)~='table' then return out; end;
    for index=1,math.min(#value.rules,128) do
        local source=value.rules[index];
        if type(source)=='table' then
            local rule=filters.rule();
            rule.effect=source.effect==nil and 0 or integer(source.effect,1023);
            if rule.effect then rule.effect=copy_image[rule.effect] or rule.effect; end;
            rule.job=source.job==nil and 0 or integer(source.job,18);
            rule.kind=source.kind==nil and 'all' or source.kind;
            rule.scope=source.scope==nil and 'all' or source.scope;
            rule.name=name(source.name);
            -- Invalid restrictions must never turn into a broader hide rule.
            if rule.effect and rule.job and kinds[rule.kind] and scopes[rule.scope]
                and #rule.name<=32 and not rule.name:find('[%c]')
                and (source.name==nil or type(source.name)=='string' and not source.name:find('[%c]')) then
                rule.enabled=source.enabled==nil or source.enabled==true;
                out.rules[#out.rules+1]=rule;
            end;
        end;
    end;
    return out;
end;

local function unchanged(previous, value)
    if not previous or previous.enabled~=value.enabled or #previous.rules~=math.min(#value.rules,128) then return false; end;
    for index, saved in ipairs(previous.rules) do
        local rule=value.rules[index];
        if type(rule)=='table' then
            if not saved then return false; end;
            for _, key in ipairs(rule_fields) do
                if rule[key]~=saved[key] then return false; end;
            end;
        elseif saved then return false; end;
    end;
    return true;
end;

local function remember(value, compiled)
    local previous={enabled=value.enabled, rules={}, compiled=compiled};
    for index=1,math.min(#value.rules,128) do
        local rule=value.rules[index];
        local saved=false;
        if type(rule)=='table' then
            saved={};
            for _, key in ipairs(rule_fields) do saved[key]=rule[key]; end;
        end;
        previous.rules[index]=saved;
    end;
    return previous;
end;

function filters.compile(value)
    if type(value)~='table' then return empty; end;
    if value.marker==marker then return value; end;
    if value.enabled~=nil and value.enabled~=true or type(value.rules)~='table' or #value.rules==0 then return empty; end;
    local previous=cache[value];
    if unchanged(previous,value) then return previous.compiled; end;
    local compiled={active=false, needs_jobs=false, marker=marker, effects={}, any={}};
    for _, rule in ipairs(filters.tidy(value).rules) do
        if rule.enabled then
            rule.name=rule.name:lower();
            local bucket=compiled.any;
            if rule.effect~=0 then
                bucket=compiled.effects[rule.effect] or {};
                compiled.effects[rule.effect]=bucket;
            end;
            bucket[#bucket+1]=rule;
            compiled.active=true;
            compiled.needs_jobs=compiled.needs_jobs or rule.job~=0;
        end;
    end;
    cache[value]=remember(value,compiled);
    return compiled;
end;

-- Units outside the party take a scope from what the client says they are.
local kind_scopes = {player='other', monster='enemy', mob='enemy', enemy='enemy', pet='pet'};

-- into, when given, is filled and returned in place of a new table.
local function recipient(value, id, self_id, into)
    value=type(value)=='table' and value or {};
    local group=integer(value.group,3,1);
    local slot=integer(value.slot,17);
    if not group and slot then group=math.floor(slot/6)+1; end;
    local is_self=(id~=nil and id==self_id) or value.is_self==true or value.scope=='self';
    if is_self then group=1; end;
    local scope=is_self and 'self' or group==1 and 'party' or group and 'alliance' or value.scope or kind_scopes[value.kind];
    local player=is_self or group~=nil or scope=='party' or scope=='alliance'
        or value.kind=='player' or value.player==true;
    local job=integer(value.job,18,1);
    -- A row's own name is its effect's, so a row whose unit has no name yet gives none here.
    local unit=value.entity_name or value.entity_id==nil and value.name;
    if not into then
        return {id=id, name=name(unit):lower(), job=player and job or nil,
            group=group, is_self=is_self, player=player, scope=scope};
    end;
    into.id, into.name, into.job, into.group = id, name(unit):lower(), player and job or nil, group;
    into.is_self, into.player, into.scope = is_self, player, scope;
    return into;
end;

function filters.recipients(snapshot, roster)
    local out={};
    if snapshot and snapshot.valid==false then return out; end;
    local self_id=snapshot and integer(snapshot.id,4294967295,1)
        or roster and roster.valid~=false and integer(roster.id,4294967295,1);
    if snapshot then
        if self_id then out[self_id]=recipient(snapshot,self_id,self_id); end;
        for id, entity in pairs(snapshot.entities or {}) do
            if entity.kind=='player' and not out[id] then out[id]=recipient(entity,id,self_id); end;
        end;
        for _, member in ipairs(snapshot.party or {}) do
            local id=integer(member.id,4294967295,1);
            if id then out[id]=recipient(member,id,self_id); end;
        end;
    end;
    local current=roster and roster.valid~=false and (not snapshot
        or roster.id==snapshot.id and roster.zone==snapshot.zone);
    if current then
        for _, member in ipairs(roster.members or {}) do
            local id=integer(member.id,4294967295,1);
            if id then out[id]=recipient(member,id,self_id); end;
        end;
    end;
    return out;
end;

-- into, when given, is filled for a unit the recipients don't list, in place of a new table.
function filters.context(recipients, id, fallback, into)
    if recipients and recipients[id] then return recipients[id]; end;
    return recipient(fallback,id,nil,into);
end;

local function matches(rule, kind, subject)
    if rule.kind~='all' and rule.kind~=kind then return false; end;
    if rule.name~='' and (not subject.player or subject.name~=rule.name) then return false; end;
    if rule.job~=0 and (not subject.player or subject.job~=rule.job) then return false; end;
    local scope=rule.scope;
    if scope=='all' then return true; end;
    if scope=='self' then return subject.is_self; end;
    if scope=='party' then return subject.is_self or subject.group==1 or subject.scope=='party'; end;
    if scope=='alliance' then return subject.group==2 or subject.group==3 or subject.scope=='alliance'; end;
    if scope=='enemy' or scope=='other' or scope=='pet' then return subject.scope==scope; end;
    return scope=='alliance1' and subject.group==2 or scope=='alliance2' and subject.group==3;
end;

function filters.hide(compiled, effect, subject)
    compiled=filters.compile(compiled);
    if not compiled.active or type(effect)~='table' or effect.domain=='recast' then return false; end;
    local id=integer(effect.effect,1023,1);
    if not id then return false; end;
    subject=subject or {};
    local kind=effect.kind=='buff' and 'buff' or effect.kind=='debuff' and 'debuff' or 'neutral';
    for _, rule in ipairs(compiled.effects[id] or no_rules) do
        if matches(rule,kind,subject) then return true; end;
    end;
    for _, rule in ipairs(compiled.any) do
        if matches(rule,kind,subject) then return true; end;
    end;
    return false;
end;

-- Whether kept was worked out from these rules, this unit and these effects, each still with the fields hide reads.
-- kept holds the unit's fields by name and, in order, each effect followed by its id, kind and domain.
local function same_selection(kept, compiled, effects, unit)
    if kept.compiled~=compiled or kept.effects~=effects or kept.count~=#effects then return false; end;
    for _, key in ipairs(unit_fields) do
        if kept[key]~=unit[key] then return false; end;
    end;
    local at=0;
    for index=1,kept.count do
        local effect=effects[index];
        if kept[at+1]~=effect or type(effect)=='table' and (kept[at+2]~=effect.effect or kept[at+3]~=effect.kind
            or kept[at+4]~=effect.domain) then return false; end;
        at=at+4;
    end;
    return true;
end;

function filters.subject(compiled, subject, context)
    compiled=filters.compile(compiled);
    if not compiled.active or not subject or type(subject.effects)~='table' then return subject; end;
    local unit, effects = context or nobody, subject.effects;
    local kept=kept_subjects[subject];
    if kept and same_selection(kept,compiled,effects,unit) then
        local out=kept.out;
        -- The rest of the subject is copied as it is now.
        for key, value in pairs(subject) do if key~='effects' then out[key]=value; end; end;
        for key in pairs(out) do if key~='effects' and subject[key]==nil then out[key]=nil; end; end;
        return out;
    end;
    local selected;
    for index, effect in ipairs(effects) do
        if filters.hide(compiled,effect,unit) then
            if not selected then
                selected={};
                for previous=1,index-1 do selected[#selected+1]=effects[previous]; end;
            end;
        elseif selected then selected[#selected+1]=effect; end;
    end;
    -- Only a subject the rules hide something on is kept: one they leave alone costs nothing to give back.
    if not selected then kept_subjects[subject]=nil; return subject; end;
    local out={};
    for key, value in pairs(subject) do out[key]=value; end;
    out.effects=selected;
    kept={compiled=compiled, effects=effects, count=#effects, out=out};
    for _, key in ipairs(unit_fields) do kept[key]=unit[key]; end;
    local at=0;
    for index=1,kept.count do
        local effect=effects[index];
        kept[at+1]=effect;
        if type(effect)=='table' then kept[at+2], kept[at+3], kept[at+4] = effect.effect, effect.kind, effect.domain; end;
        at=at+4;
    end;
    kept_subjects[subject]=kept;
    return out;
end;

-- The map that comes back is kept for the map given and refilled on later calls with the same rules.
function filters.subjects(compiled, subjects, recipients)
    compiled=filters.compile(compiled);
    if not compiled.active or not subjects then return subjects; end;
    local kept=kept_maps[subjects];
    local out=kept and kept.compiled==compiled and kept.out or nil;
    local changed=false;
    for id, subject in pairs(subjects) do
        local filtered=filters.subject(compiled,subject,filters.context(recipients,id,subject,unlisted));
        if filtered~=subject then
            changed=true;
            if not out then
                out={};
                for key, value in pairs(subjects) do out[key]=value; end;
                kept_maps[subjects]={compiled=compiled, out=out};
            end;
        end;
        if out then out[id]=filtered; end;
    end;
    if not changed then return subjects; end;
    for id in pairs(out) do if subjects[id]==nil then out[id]=nil; end; end;
    return out;
end;

return filters;
