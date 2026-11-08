local labels = require('ui.party_labels');
local member = { name = 'Alexandria', job = 1, zone = 230, zone_name = "Southern San d'Oria" };
assert(labels.member_name(member, {}) == 'Alexandria');
assert(labels.member_name(member, { name_display = 'full', name_length = 3 }) == 'Alexandria');
assert(labels.member_name(member, { name_display = 'short' }) == 'Alexand.');
assert(labels.member_name(member, { name_display = 'short', name_length = 3 }) == 'Al.');
assert(labels.member_name(member, { name_display = 'short', name_length = 16 }) == 'Alexandria');
for limit = 3, 16 do
    for count = 1, 24 do
        local value = string.rep('A', count);
        local result = labels.member_name({ name = value }, { name_display = 'short', name_length = limit });
        assert(#result <= limit and #result <= #value, 'A short name never grows or exceeds the selected length.');
        assert(result == (count <= limit and value or string.rep('A', limit - 1) .. '.'));
    end;
end;
for _, invalid in ipairs({ false, '8', 0 / 0, math.huge, -math.huge, {} }) do
    assert(labels.member_name(member, { name_display = 'short', name_length = invalid }) == 'Alexand.');
end;
assert(labels.member_name(member, { name_display = 'short', name_length = -1 }) == 'Al.');
assert(labels.member_name(member, { name_display = 'short', name_length = 5.9 }) == 'Alex.');
assert(labels.member_name(member, { name_display = 'short', name_length = 900 }) == 'Alexandria');
assert(labels.member_name({ name = '\195\137lodie' }, { name_display = 'short', name_length = 6 }) == '\195\137lodie', 'UTF-8 byte length does not shorten a six-character name.');
assert(labels.member_name({ name = '\195\137lodienne' }, { name_display = 'short', name_length = 4 }) == '\195\137lo.', 'Shortening preserves complete UTF-8 characters.');
assert(labels.member_name({ name = '\227\129\130\227\129\132\227\129\134\227\129\136' }, { name_display = 'short', name_length = 3 }) == '\227\129\130\227\129\132.');

local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
    'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
for id, job in ipairs(jobs) do
    assert(labels.job_name(id) == job);
    assert(labels.member_name({ name = 'Alexandria', job = id }, { name_display = 'job' }) == job);
end;
for _, invalid in ipairs({ 0, 19, 22, 23, -1, 1.5, 0 / 0, math.huge, -math.huge, '1', false, {} }) do
    assert(labels.job_name(invalid) == nil);
    assert(labels.member_name({ name = 'Alexandria', job = invalid }, { name_display = 'job' }) == 'Alexandria', 'Unknown jobs preserve the actual member name.');
end;
assert(labels.job_name(nil) == nil);
assert(labels.member_name(nil, { name_display = 'job' }) == 'Member', 'A member with no name reads Member, never unknown.');
assert(labels.member_name(member, { name_display = 'invalid' }) == 'Alexandria');

local samples = {
    { zone=1, zone_name="Phanauet Channel" },
    { zone=2, zone_name="Carpenters' Landing" },
    { zone=100, zone_name="West Ronfaure" },
    { zone=102, zone_name="La Theine Plateau" },
    { zone=110, zone_name="Rolanberry Fields" },
    { zone=111, zone_name="Beaucedine Glacier" },
    { zone=166, zone_name="Ranguemont Pass" },
    { zone=167, zone_name="Bostaunieux Oubliette" },
    { zone=184, zone_name="Lower Delkfutt's Tower" },
    { zone=187, zone_name="Dynamis - Windurst" },
    { zone=220, zone_name="Ship bound for Selbina" },
    { zone=221, zone_name="Ship bound for Mhaura" },
    { zone=223, zone_name="San d'Oria-Jeuno Airship" },
    { zone=224, zone_name="Bastok-Jeuno Airship" },
    { zone=225, zone_name="Windurst-Jeuno Airship" },
    { zone=226, zone_name="Kazham-Jeuno Airship" },
    { zone=227, zone_name="Ship bound for Selbina" },
    { zone=228, zone_name="Ship bound for Mhaura" },
    { zone=230, zone_name="Southern San d'Oria" },
    { zone=243, zone_name="Ru'Lude Gardens" },
    { zone=244, zone_name="Upper Jeuno" },
    { zone=245, zone_name="Lower Jeuno" },
    { zone=246, zone_name="Port Jeuno" },
    { zone=250, zone_name="Kazham" }
};
for _,source in ipairs(samples) do
    assert(labels.full_zone_name(source)==source.zone_name,'Hover details retain the full resource name.');
end;
for _,invalid in ipairs({'','.', 'unknown', ' UNKNOWN ', 'bad\nname', string.rep('x',129), false, 230, {}}) do
    assert(labels.full_zone_name({zone_name=invalid})=='','Missing zone names never fall back to guesses.');
end;
assert(labels.full_zone_name({zone=230})=='' and labels.full_zone_name(nil)=='');
assert(member.name=='Alexandria' and member.job==1 and member.zone_name=="Southern San d'Oria");
