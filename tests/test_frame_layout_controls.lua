local h = require('panel_fixture')();
local equal, copy = require('core.customization').equal, require('core.store').copy;

-- Party list buffs. The panel has no frames' layout, no effect placement and no choice of time format: every countdown has
-- one.
local settings = h.fresh(function(s)
    local p = s.party_ui;
    p.style.icon_art = 'XI View';
    p.effects.icon_size, p.effects.countdown_bold, p.effects.countdown_outline = 48, true, true;
    -- Party countdowns start off; on here, so their controls show.
    p.effects.timers = true;
end);
local p = settings.party_ui;
local before = copy(p);
local controls = h.every_tab('party_ui');
assert(equal(before, p), 'Opening the panel does not rewrite saved settings.');
assert(not controls['Party frame layout'] and not controls['Effect placement'], 'The frames layout and placement are not offered.');
assert(not controls['Effect time format'] and controls['Countdown size'], 'Nor is a time format, with countdowns on.');
assert(p.style.icon_art == 'XI View');
assert(p.effects.icon_size == 48 and p.effects.countdown_bold and p.effects.countdown_outline);
assert(p.locked == before.locked and p.enabled == before.enabled);
return 'The party list buffs offer no time format and keep the other customization.';
