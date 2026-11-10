# Validation

## Phoenix effect audit

This audit was done for 1.0. It judged all 668 status effects in the exporter's pinned `data/status_effects.yaml` against Phoenix `phoenix/live` at `ed41f351f6`, with its era settings. The question for each one was whether it can ever exist on Phoenix.

- 266 can and 375 can't. Of the ones that can't, 136 belong to DNC, SCH, GEO or RUN, 84 have nothing in the code that applies them, and 67 need a level past 75. 35 belong to a system that's off (Abyssea, Campaign, Monstrosity, Trusts), and 34 belong to content that's off. 14 exist only in zones with no way in, 3 come from items nothing gives, 1 is the empty slot marker and 1 is GM only.
- 27 needed a decision. 19 stayed: 18 staged ToAU effects and Commitment. 8 went: the six En-II effects, Magic Evasion Down and Flurry II, which only a shop could reach.
- 14 more can't reach a screen, so they went too. The client has no name or icon for them. 12 of them are applied with icon 0, Hysteria is only ever on a mob, and Full Speed Ahead belongs to a quest from after this era.
- That leaves 271 effects in `vantage/data/catalog.lua` and takes 397 out. The pickers list 268, because Copy Image's icons for 2, 3 and 4 or more shadows are Copy Image itself. By group, that's Buffs 133, Debuffs 61, Rolls 20, Songs 24, Other 13, Protection 7, Travel 6, Recovery 3 and Food 1. Of the 31 rolls, 18 stay.
- An effect nothing names gets no row, so no display can show it. If an effect was left out but the client does name it, it still tracks and draws under that name.
- `vantage/data/dispelable.lua` keeps 128 of its 180.
- Timer durations lists 436 of the 893 spells and 355 of the 616 job abilities. Those are the ones from the base game, RoZ, CoP and ToAU on a job up to PUP at level 75 or under, minus the 122 Trust spells, which every job has at level 1. `sql/spell_list.sql` and `sql/abilities.sql` give the same lists at the pin and at `ed41f351f6`, and the era SQL moves nothing across 75.

The exporter's pin `071c401048` has the same 668 ids as `ed41f351f6`. The only flag that differs is 794 losing `on_zone`. `phoenix/beta` doesn't change any verdict. A recheck read 15 removed and 15 kept effects from the source again, and they all held.

Some things weren't checked. `modules/phoenix_ac` is an empty gitlink (`0d44a6c0e1`), and the live host's settings, database and local patches can't be read from the source. The audit didn't trace items that only code hands out, and it counts GM commands as out of reach. It didn't run a client or a server.

Recheck when Phoenix opens WotG content or changes its era settings. The list is `AUDITED_OUT` in `tools/export_catalog.py`. An id that was left out does no harm if it does turn up. It tracks and draws under the game's own name, and one saved in a list or rule stays there until you take it out.

## Job ability effects

**Only effects from job abilities** goes by the action Vantage saw put each effect on. Blood pacts and rolls count as job abilities. When Vantage didn't see the action, because the effect was up before you zoned in or loaded Vantage or it landed out of range, the tick goes by `vantage/data/ability_effects.lua`.

- That list holds the 91 effects era job abilities put on players. They come from every era ability in `sql/abilities.sql` at the exporter's pin `071c401048`, read through its script in `scripts/actions/abilities` (`pets/` for blood pacts), the `job_utils` it calls and their `modules/era` overrides. It comes out the same at `ed41f351f6`.
- Effects a spell gives too are left out, since a copy Vantage didn't see land could be the spell's. That covers Chakra's Regen, Mantra's Max HP Boost, Hastega's Haste and what Ecliptic Howl gives. Effects only a pet gets, ones that land on the enemy and ones that can't exist on Phoenix are left out as well.
- `tests/test_ability_effects.lua` checks that the catalog names each id and that no spell in `vantage/data/effects.lua` gives one.

The exporter doesn't write this list, so it doesn't change when the catalog is exported again. Recheck it when Phoenix opens WotG content, changes its era settings or changes what an ability's script puts on.
