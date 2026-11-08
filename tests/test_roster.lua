local client=require('core.client');
local roster=require('core.roster');
local mm=AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager=function() return mm; end;
local party=mm:GetParty();
local members={};
for slot=0,17 do members[slot]={id=1001+slot,index=0x400+slot,zone=102,active=1,job=5,subjob=3}; end
local methods={GetMemberServerId='id',GetMemberTargetIndex='index',GetMemberZone='zone',GetMemberIsActive='active',
    GetMemberMainJob='job',GetMemberSubJob='subjob'};
for method,key in pairs(methods) do party[method]=function(_,slot) return members[slot] and members[slot][key]; end; end
party.GetMemberName=function(_,slot) return 'Member '..slot; end;
-- Nothing draws a member's vitals, level, leader flags, distance or target, so the roster never asks the game for them.
local asked={};
for _,method in ipairs({'GetMemberHP','GetMemberHPPercent','GetMemberMP','GetMemberMPPercent','GetMemberTP','GetMemberMainJobLevel',
    'GetMemberFlagMask','GetAllianceLeaderServerId','GetAlliancePartyLeaderServerId1','GetAlliancePartyLeaderServerId2',
    'GetAlliancePartyLeaderServerId3'}) do
    party[method]=function() asked[#asked+1]=method; end;
end
mm.GetTarget=function() asked[#asked+1]='GetTarget'; end;
mm.GetEntity=function() asked[#asked+1]='GetEntity'; end;
local s={valid=true,id=1001,zone=102};
local r=roster.read(0,s);
assert(r.valid and #r.members==18);
assert(r.members[1].slot==0 and r.members[7].group==2 and r.members[18].group==3);
assert(next(asked)==nil,'The roster reads only names, zones and jobs: '..tostring(asked[1]));
assert(r.members[7].scope=='alliance');
assert(r.members[2].job==5 and r.members[2].available);
for _, row in ipairs(r.members) do
    assert(row.subjob == 3, 'Known subjobs are available for every current party and alliance row.');
end
members[2].zone=103;members[3].job=0;
members[7].active=0;members[8].id=1002;
r=roster.read(2,s);
assert(#r.members==16,'Inactive slots and duplicate identities are omitted.');
local byslot={};for _,row in ipairs(r.members) do byslot[row.slot]=row;end
assert(not byslot[2].available and byslot[2].job==nil);
assert(byslot[2].subjob == nil, 'Another zone cannot expose a cached subjob.');
assert(byslot[3].job==nil);
party.GetMemberLastUpdatedTimestamp=function(_,slot) return slot==4 and 0 or 100;end;
r=roster.read(2.1,s);for _,row in ipairs(r.members) do
    if row.slot==4 then
        assert(row.job==nil and row.subjob == nil, 'An uninitialized slot does not expose its cached jobs.');
    end
end
s.chat_open,s.in_event,s.map,s.hidden=true,true,true,true;r=roster.read(3,s);
assert(r.typing and r.in_event and r.map and r.hidden);
members[0].job, s.job = 0, 5;
r = roster.read(3.1, s);
assert(r.members[1].job == 5);
for _, member in ipairs(r.members) do if member.slot == 3 then assert(member.job == nil); end end
s.job = nil;
r = roster.read(3.2, s);
assert(r.members[1].job == nil, 'A missing job of your own stays nil.');
s.valid=false;assert(#roster.read(4,s).members==0);
local zone_calls, search_calls, resources = {}, {}, {};
local zone_values = { [102] = 'La Theine Plateau', [230] = "Southern San d'Oria" };
resources.GetString = function(self, table_name, id)
    assert(self == resources, 'GetString uses the resource manager as its receiver.');
    if table_name == 'zones.names_search' then
        search_calls[id] = (search_calls[id] or 0) + 1;
        return ({[102]='LaTheine',[103]='Valkurm',[230]='SSandOria'})[id];
    end;
    assert(table_name == 'zones.names');
    zone_calls[id] = (zone_calls[id] or 0) + 1;
    return zone_values[id];
end;
AshitaCore.GetResourceManager = function() return resources; end;
roster.reset(); s.valid = true;
r = roster.read(5, s);
assert(r.members[1].zone_name == 'La Theine Plateau', 'Same-zone members get the client zone name.');
assert(r.members[1].zone_name_search == nil, 'Rows carry no short zone caption: nothing draws it.');
assert(zone_calls[102] == 1 and zone_calls[103] == 1, 'Zone names are shared across members.');
r = roster.read(6, s);
assert(zone_calls[102] == 1 and zone_calls[103] == 1, 'Missing names are not repeatedly queried.');
r = roster.read(36, s);
assert(zone_calls[102] == 1 and zone_calls[103] == 2, 'Missing resources can recover after the retry interval.');
roster.reset(); roster.read(37, s);
assert(zone_calls[102] == 2, 'Reset clears cached names.');
members[2].zone = 230;
r = roster.read(38, s);
assert(r.members[3].zone_name == "Southern San d'Oria" and not r.members[3].same_zone,
    'An out-of-zone member still uses its own client zone name.');
assert(r.members[3].job == nil, 'Reading a remote zone name does not bring back an old job.');
local secondary_zone = 1;
party.GetMemberZone2 = function(_, slot) return slot == 1 and secondary_zone or 0; end;
r = roster.read(38.1, s);
assert(r.members[2].same_zone and not r.members[2].available,
    'The native secondary-zone field keeps an otherwise matching zone unavailable.');
assert(r.members[2].job == nil and r.members[2].subjob == nil, 'Secondary-zone members cannot show old jobs.');
secondary_zone = 0;
r = roster.read(38.2, s);
assert(r.members[2].available and r.members[2].job == 5, 'Jobs return when the secondary-zone field clears.');
party.GetMemberZone2 = nil;
party.GetMemberZone2 = function() error('Older client API'); end;
r = roster.read(38.3, s);
assert(r.members[2].available and r.members[2].job == 5, 'An unavailable secondary-zone API leaves the zone check as it is.');
party.GetMemberZone2 = nil;
for _ = 1, 100 do roster.read(39, s); end
assert(zone_calls[230] == 1, 'Known names are reused across every roster refresh.');
assert(next(search_calls) == nil, 'The short zone captions are never read.');

members[2].zone = 103;
for _, invalid in ipairs({ '', '   ', '.', '\0', 'Zone\nname', 'Zone\127name', string.rep('x', 129), 103, true, {} }) do
    zone_values[103] = invalid;
    roster.reset();
    r = roster.read(40, s);
    assert(r.members[3].zone_name == nil, 'Unavailable or malformed resource strings stay unknown.');
    local count = zone_calls[103];
    zone_values[103] = 'Valkurm Dunes';
    r = roster.read(69.99, s);
    assert(r.members[3].zone_name == nil and zone_calls[103] == count, 'Unknown names respect the retry delay.');
    r = roster.read(70, s);
    assert(r.members[3].zone_name == 'Valkurm Dunes' and zone_calls[103] == count + 1,
        'Unavailable names recover when the client resource appears.');
end

resources.GetString = function() error('Resource unavailable'); end;
roster.reset();
assert(roster.read(71, s).members[1].zone_name == nil, 'Resource errors do not break roster updates.');
resources.GetString = nil;
roster.reset();
assert(roster.read(72, s).members[1].zone_name == nil, 'A missing resource method stays unknown.');
local invalid_calls = 0;
resources.GetString = function() invalid_calls = invalid_calls + 1; return 'Unexpected'; end;
members[2].zone = 1024;
roster.reset(); roster.read(73, s);
assert(invalid_calls == 1, 'Only the valid zone reaches the resource lookup.');

local subjob_reads, self_reads, self_subjob = {}, 0, 6;
local get_player = mm.GetPlayer;
mm.GetPlayer = function()
    return { GetSubJob = function() self_reads = self_reads + 1; return self_subjob; end };
end;
local function read_subjob(_, slot)
    subjob_reads[slot] = (subjob_reads[slot] or 0) + 1;
    return members[slot] and members[slot].subjob;
end
party.GetMemberSubJob = read_subjob;
r = roster.read(74, s);
assert(r.members[1].subjob == 3 and self_reads == 0, 'A valid roster subjob does not need a second player-memory lookup.');
assert(subjob_reads[2] == nil and subjob_reads[4] == nil, 'Remote and uninitialized slots are never read for subjobs.');
for _, invalid in ipairs({0, -1, 19, 3.5, 0/0, math.huge, '3', false, {}}) do
    members[1].subjob = invalid;
    r = roster.read(75, s);
    assert(r.members[2].subjob == nil, 'Invalid subjobs stay nil.');
end
for _, valid in ipairs({1, 18}) do
    members[1].subjob = valid;
    r = roster.read(76, s);
    assert(r.members[2].subjob == valid, 'The complete supported job range is accepted.');
end
members[1].subjob = nil;
r = roster.read(77, s);
assert(r.members[2].subjob == nil, 'Missing party subjobs cannot borrow the player subjob.');
members[0].subjob = 0;
r = roster.read(78, s);
assert(r.members[1].subjob == 6 and self_reads == 1,
    'Only self can recover an unavailable roster subjob from the player API.');
party.GetMemberSubJob = nil;
r = roster.read(79, s);
assert(r.members[1].subjob == 6 and r.members[2].subjob == nil,
    'An older party API leaves remote subjobs nil and keeps the self fallback.');
party.GetMemberSubJob = function() error('Unavailable subjob data'); end;
r = roster.read(80, s);
assert(r.members[1].subjob == 6 and r.members[2].subjob == nil, 'A failed party getter is handled as missing data.');
for _, invalid in ipairs({0, -1, 19, 3.5, 0/0, math.huge, '3', false, {}}) do
    self_subjob = invalid;
    r = roster.read(81, s);
    assert(r.members[1].subjob == nil, 'The self fallback validates the same job range.');
end
mm.GetPlayer = function() return {}; end;
r = roster.read(82, s);
assert(r.members[1].subjob == nil, 'Missing self APIs leave it nil.');
mm.GetPlayer = function() return { GetSubJob = function() error('Unavailable player data'); end }; end;
r = roster.read(83, s);
assert(r.members[1].subjob == nil, 'A failed self getter never invents a job.');
local player_reads = 0;
mm.GetPlayer = function() player_reads = player_reads + 1; return { GetSubJob = function() return 6; end }; end;
party.GetMemberLastUpdatedTimestamp = function() return 0; end;
r = roster.read(84, s);
assert(r.members[1].subjob == nil and player_reads == 0,
    'The self fallback does not bypass the uninitialized-row guard.');
mm.GetPlayer = get_player;
