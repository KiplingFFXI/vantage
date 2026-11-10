# Overhead icons: placement, size and drawing

This note covers how Vantage decides where overhead icons go and how big they are, how it draws them, and their settings page and samples. Placement and size are in `vantage/core/overhead.lua`, `vantage/core/camera.lua` and `vantage/core/name_anchor.lua`, with the settings in `vantage/ui/overhead_defaults.lua`. Drawing is in `vantage/ui/overhead_icons.lua`, with `vantage/core/dispel.lua` for the lit icons. Phoenix sources are at revision 730ac619c0. Values marked as a guess are settings, so a calibration in game needs no code change.

## Hitboxes in Phoenix

A hitbox is a radius in yalms that range checks use. It isn't a height or a model scale. Melee reach is both hitboxes plus 2 (`src/map/entities/battle_entity.cpp:595`), and spells add both to their range (`src/map/ai/states/magic_state.cpp:425`). The client gets it as `ModelHitboxSize` in 0x00D, 0x00E and 0x037.

- Players get one by race only. Tarutaru get 0.3, Galka 0.8 and every other race 0.4 (`src/map/utils/charutils.cpp:1230-1246`). Body size S, M or L changes nothing.
- Mobs take `render.hitbox` from their zone's `mobs.yaml` template, in tenths (`src/map/utils/zoneutils.cpp:383`). Over the era zones the templates run from 0.3 to 7.0, with quartiles of 1.2, 1.5 and 2.0. About one template in twenty has none, and the client then reads 0.
- Model size is a drawn size. It's GraphSize in 0x00E, and it runs from 0 to 3. Within a family the hitbox already steps up with it (goblins 1.0, 1.2, 1.7, 2.0), so Vantage doesn't need it. Ashita's `ModelSize` is a float that is usually -1. It isn't GraphSize, and Vantage only logs it.
- Pets and the mobs of instances and dynamic spawns take theirs from `sql/mob_pools.sql` instead (`src/map/utils/petutils.cpp:104`, `src/map/instance_loader.cpp:189`, `src/map/utils/mobutils.cpp:1840, 1977`). 791 of its 1,291 pools have one, with quartiles of 1.2, 1.5 and 2.0 like the zone templates. A NULL one loads as 0 and the client reads 0, as it does for some jug pets (Flytrap Familiar at `sql/mob_pools.sql:734` and Shellbuster Orob at `:712`).
- The client gets a pet's hitbox from its pool. Carbuncle (`:706`), the elemental spirits (`:888-895`), the automaton frames (`:765-768`) and the wyvern (`:813`) have 0.8. Garuda, Shiva, Ramuh and Diabolos have 2.0 (`:703-705`, `:708`). Fenrir has 2.5 (`:699`), and Ifrit, Titan and Leviathan have 3.0 (`:700-702`). Their heads come out at 1.4 yalms for the small ones, up to 3.6 for the big avatars, and at 2.1 for a pet with none.

The two scales can't be compared. As mobs, the same bodies have 1.2 to 1.6 (the Ark Angels, `laloff_amphitheater/mobs.yaml`). That's about 2 to 4 times the player values. Vantage never compares a player's raw hitbox with a mob's.

| race | as a player | the five Ark Angels, model size 1 | mob templates of that race, median |
| --- | ---: | ---: | ---: |
| Tarutaru | 0.3 | 1.2 (`:353`) | 1.2 |
| Mithra | 0.4 | 1.5 (`:280`) | 1.5 |
| Hume | 0.4 | 1.6 (`:189`) | 1.7 |
| Elvaan | 0.4 | 1.6 (`:24`) | 1.7 |
| Galka | 0.8 | 1.5 (`:98`) | 2.0 |

The medians are over era templates and lean on notorious monsters. The Galka ones are 11 templates, Zeid among them. Same-fight bodies put a Galka with a Mithra, below a Hume. Only a Tarutaru is clearly smaller. Model size steps the hitbox up within one family. These are medians of era templates:

| family | model size 0 (unset) | 1 | 2 | 3 |
| --- | ---: | ---: | ---: | ---: |
| goblin | 1.0 | 1.2 | 1.7 | 2.0 |
| orc | 1.2 | 1.5 | 1.7 | 2.0 |
| dragon | 2.8 | 3.4 | 3.9 | 4.7 |
| gigas | 2.5 | 3.0 | 3.4 | 4.1 |

So a mob's hitbox already carries its drawn size. On the mob scale a goblin (1.2) sits with a Tarutaru, and an orc or a quadav (1.5) sits with a Mithra. The large dragons (4.2 to 5.0) sit at three and a half to four times a Tarutaru.

## Head height

The head point is the entity's position raised by its head height H in yalms. Above the name, Vantage only uses it when the game's own name point can't be read (see Where a block goes). Under the head, Vantage always uses it.

| unit | H |
| --- | --- |
| players, by race 1 to 8 | Hume 1.80 / 1.70, Elvaan 2.05 / 1.95, Tarutaru 1.00, Mithra 1.55, Galka 2.05, any other race 1.80 |
| players mounted (status 5 or 85) | 1.35 + 0.55 H |
| players sitting or healing (33, 47) | 0.6 H |
| players in a chair (63 to 73) | 0.75 H |
| mobs and pets | 0.6 + 1.0 x hitbox, clamped 1.2 to 8.0. No hitbox counts as 1.5 |

All of these are guesses to settle in game. Phoenix itself uses one flat eye line of 2.0 yalms for everything. The hitbox line puts long, low bodies (rabbits, crabs, pugils) too high and floating elementals too low. That's why there are per-name heights. `head.heights[name]` replaces the standing height or the hitbox line. Then Vantage adds `head.offsets[name]`, and after that each unit type's `world_offset`. The race table, the mounted and posture factors and the hitbox line are all in `head`.

## Icon size

```
size = clamp(base * (ref_depth / depth) ^ alpha * class * target * type, min_px, max_px) * ui
class = clamp((R / ref_hitbox) ^ beta, s_min, s_max) * sizes[name]
```

- depth is the view depth of the point the block is placed from. It isn't your distance to the unit. Above the name, that point is the game's name point, or the name's guessed middle when the name point can't be read. Under the head, it's the head point (see Where a block goes).
- R is the hitbox for mobs and pets, or 1.5 when there's none. For players it's a value by race: Tarutaru 1.2, Mithra 1.5, Hume and Elvaan 1.7, Galka 2.0. That race table is a design choice to settle in game. Mob families of these races don't agree on their order (Galka Ark Angel 1.5, Hume 1.6).
- target is 1.2 on the current target. ui is DisplaySize height / 1080 times the style scale. The size settles on whole pixels and keeps that size while it moves 0.6 px or less, so camera bob doesn't flicker it.
- The defaults are base 22, ref_depth 10, alpha 0.5, ref_hitbox 1.5, beta 0.5, class 0.85 to 1.6, and 14 to 40 px.

Here are the sizes at 1080p:

| unit | depth 5 | 15 | 30 | as target, 5 / 15 / 30 |
| --- | ---: | ---: | ---: | ---: |
| Tarutaru player | 28 | 16 | 14 | 33 / 19 / 14 |
| Galka player | 36 | 21 | 15 | 40 / 25 / 18 |
| Goblin Mugger (1.2) | 28 | 16 | 14 | 33 / 19 / 14 |
| Fafnir (4.2), Nidhogg (5.0) | 40 | 29 | 20 | 40 / 34 / 24 |

## Where a block goes

The default placement is above the name (`layout.placement` `above_name`). There, a block sits a few pixels over the game's own name, which Vantage reads from the client (`vantage/core/name_anchor.lua`). The client hangs each name, and the target cursor over it, from one point of the unit's model. It works that point out each frame as:

```
P = root + point 2 of the first skeleton node * scale + m * h + lift
```

Vantage reads each part from the client's memory as the client keeps it. The offsets are from the actor, for FFXiMain.dll 04288488, the Phoenix client.

- root is the actor's root, with its render space x, y, z at 0x678, 0x67C, 0x680.
- scale has its x, y, z at 0x698, 0x6A0, 0x69C.
- point 2 is read through the first skeleton node (0x6B8) and its generator data (node + 0x0C, then that pointer). The bone count is at + 0x32, and the bones start at + 0x34, 0x1E each. Then comes the generator table, with 4 bytes and then 0x1A for each entry. Entry 2 holds the bone it hangs from and its offset at + 0x0E, + 0x12, + 0x16. With no node, generator or data yet, the client puts the name at the root, and so does Vantage. `/vg report` marks it `generator_zero`.
- m * h is 1.3 * h up on a chocobo (status 5) or a mount (85), and 0.5 * h in a chair (63 to 83). It only applies when point 2 hangs from no bone and the actor isn't the chocobo, mount or chair itself, going by its kind at 0xA4. h is the entity's model size (entity + 0x204, with the entity at actor + 0x70), or else the actor's 0x75C, or else 0x754. The client takes a mount's lift from its own tables, per mount. Vantage uses the highest, 1.3, for every mount, so a block on a mount may sit a little high but never on the name.
- lift is the float at 0x8C0, and the client adds it last.

Vantage reads those offsets out of the client's own code with 16 byte patterns, and holds each one to what that code allows. It searches for the patterns as warmup steps (`core/warmup.lua`, docs/PERFORMANCE.md), a couple a frame. That happens over the frames after `/addon load` when overhead icons are on, or after you turn them on. No block shows until every one has run, so each block first shows on its name point. Vantage keeps the addresses it finds for the life of the game process (`core/patterns.lua`). An `/addon reload` checks each kept address instead of searching again. Each kept address has to be inside the client and readable, with the pattern's fixed bytes still there. A pattern that is missing, found more than once or gives an offset out of range turns name points off for every unit. `/vg report` names it, and every block keeps the guess below. `tools/client_check.py` checks these patterns too.

Vantage checks each unit before it uses the unit's point. It page checks the actor's range, so there are no reads from memory that isn't there. The actor's entity must point back at it and carry the unit's server id. The name must hang from point 2, going by the name index at 0x8A7. Any other index means another point, which Vantage doesn't read. The values must be finite, the scale above 0 and up to 20, and the root within 10 yalms of the unit. The skeleton must be in range, with 1 to 512 bones, 3 to 128 generators, and point 2 at most 4 yalms to a side and 0 to 16 up. A unit that fails gets the guess, and `/vg report` gives the reason. Vantage reads the skeleton, the icon and the cursor's box again ten times a second, with each list of units, or as soon as the skeleton's node moves. It also does that while **When to show** hides the blocks, since the sample still shows. It reads the rest each frame, which is about 14 reads per unit, and it makes no table. It page checks each region of memory the units' actors and entities sit in once a frame, so units that share a region share its check. A unit whose name point was well off screen isn't read again until the next list. Vantage judges that each frame from where the unit is now and where its name point sat from it at the last read, with a yalm to spare, so one that comes on screen is read at once.

P goes through Vantage's camera to ax, ay on the display and its depth z. That depth runs 0 to 1 from the near plane to the far one. The client draws a name's font texel `DisplaySize height * 0.00234375 * s` px tall. s is 1 until `zi = floor(z * 4096)` reaches 4020, and after that it's `(4100 - zi) / 80`, so far names shrink. Then Vantage works these out:

```
name_top  = ay - 0.5                     the name hangs down from P, half a pixel up
icon_top  = name_top - ceil(rise * t)    an icon in front of the name, rise font texels over it
arrow_top = (y + box_low - 0.5) * ky     the target cursor, on the unit carrying it
anchor_y  = floor(min(name_top, icon_top, arrow_top) + dy - gap * ui + screen_y + 0.5)
anchor_x  = floor(ax + dx + screen_x + 0.5)
```

- t is that texel. rise follows the client's own pick of the icon in front of a name, from the render flags, and each icon's height in the font. It's 0 with no icon, 1.0625 for the two smallest, 2 for most, 4 for a few, and 18 for the second line of stars over a player's name. A Ballista or campaign icon counts as 2, since Vantage doesn't read the Ballista data that picks it.
- For the cursor, arrow A is the target's, and arrow B is the subtarget's while a command picks one. y is the cursor's point in the game's menu pixels. It's `trunc(ay / ky)`, with B 10 higher, or the point the target window keeps when the cursor floats or hangs from another point. box_low is the top row of the cursor's frames over its point. In the game's own frames it's -32, and Vantage uses that when it can't read them. ky is the display pixels per menu pixel. It's DisplaySize height / the menu height, or 1 until the chat reader has read the menu size. With no cursor on the unit, arrow_top is left out. A floating cursor (Ashita's IsArrowActive) still counts on the target wherever it is on screen. So it can lift the target's block to the cursor's height even when the cursor isn't over the name. The client itself ties a floating cursor to no unit.
- dx and dy are how far the block moves on screen when P is raised by the type's `world_offset` and `head.offsets[name]` yalms. Both are 0 at first.
- gap is 3 px, ui is the same as for the icon size, and screen_x and screen_y are as before.

The tests use a camera with the game's P11, P22 and planes, 8 yalms behind and 4 up, at 1920x1080 (`tests/test_overhead_name_point.lua`). That camera gives these numbers:

| unit | ay | name_top | arrow_top | anchor_y | targeted |
| --- | ---: | ---: | ---: | ---: | ---: |
| point 2.0 yalm up, 8.2 from the camera | 477.41 | 476.91 | 444.5 | 474 | 442 |
| mob near, 10.9 from the camera | 401.22 | 400.72 | 368.5 | 398 | 366 |
| mob far, 31.6 from the camera | 335.97 | 335.47 | 302.5 | 332 | 300 |

Above the name, Vantage uses the guess for a unit whose name point can't be read. That's when name points are off, or when the unit fails a check. The guess takes the head point, raised by its unit type's `name_lift`, as the name's middle. That lift is 0.5 yalm for players, the alliance, others and you, and 0 for mobs and pets. Vantage projects that point to sx, sy, with ppy pixels per yalm at its depth, and k is the DisplaySize height / 1080. The guess treats the name and target cursor as things in the world that stop growing up close:

```
name_px  = min(name_cap * k, name_height * ppy)
arrow_px = min(target_cap * k, target_height * ppy) on the target, 0 on anyone else
anchor_y = floor(sy - name_px / 2 - arrow_px - gap * ui + screen_y + 0.5)
```

The defaults are `name_height` 0.33 yalm, `name_cap` 24 px, `target_height` 0.4 yalm and `target_cap` 16 px. Those four, `name_lift` and the race heights only matter for the guess, so the page has no sliders for them. `/vg set` changes them, as in `/vg set overhead.layout.name_cap 30` or `/vg set overhead.types.party.name_lift 0.75`. With the game's camera (P22 1.26) at 1080, the guess gives:

| depth | px per yalm | name | cursor | edge over the name's middle, target | others |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 6.7 | 101.4 | 24 | 16 | 31 | 15 |
| 23 | 29.6 | 9.8 | 11.8 | 19.7 | 7.9 |

Under the head (`below_name`), the block's top edge sits `gap` under the head point, and the name isn't counted. Vantage doesn't place a block whose point is further off screen than about half a bar of icons.

## Who gets a block

Ten times a second, Vantage makes a list of at most 24 units. It places them every frame and keeps up to `max_units` (10) by priority, nearest first within one priority. The order is the target, the subtarget, mobs your party or alliance claimed, watched mobs, mobs with your party's debuffs, the party, your pet, the alliance, and then other players and pets. For a claim, Vantage reads the claimer at 0x2C of an 0x00E with its claim bit. Your party's debuffs are yours, a member's or your pet's. Other players and pets are off by default, and Vantage finds them by the index their 0x00D or 0x00E gave. You are off by default too. Vantage leaves out a unit when its type's own filters leave it no effect to show, so it takes no place from one with icons to draw. The target and subtarget are the exception. The shared hide rules apply when the block is drawn. A party or alliance member with party cooldown estimates gets a block for its cooldown line while that line is on (see Drawing), whatever its effects.

A mob is anything with SpawnFlags 0x10, whatever its Type. Vantage only skips a non-mob of Type 2 or 3, which are fixed models and doors. Units beyond `distance_cap` get nothing. The cap starts at 30 and can be at most 50. From 20 yalms they fade, by alpha only, down to half at the cap, and the target never fades. In era towns, only the target, the subtarget and the party get blocks. An era town is a zone that Phoenix `zone.yaml` types as city, leaving out later expansions' zones. Sealion's Den is typed city too, but its CoP fights need every block, so it isn't counted as a town.

Nothing gets a block while Vantage's displays are hidden, while you're zoning, or with the game's interface hidden. It's the same in an event, on the map, while the camera can't be used, or where the overhead icons' **When to show** choices don't hold. For an event, Vantage goes by the client's flag or your own status 4. A client pattern that wasn't found skips only its own check. A unit gets no block while it isn't drawn, has no model, is dead, or is off screen or behind the camera. It isn't drawn when its render flags have 0x200 off or 0x4000 on. It's dead at status 2 or 3, or as a mob at 0 HP. Your own block also hides in first person.

A mob the server keeps out of players' sight gets no block for any reason, the target included. Every 0x00E carries the entity's server status at 0x20. Phoenix sends 0 or 1 for a mob players can see, 3 while it's invisible, 2 as it disappears and 6 for a cutscene only. Vantage keeps each mob's last status and gives it a block only at 0 or 1. Shikigami Weapon, for one, is at 3 outside a fight. An 0x00E with its HP bit (0x04) also carries the entity flags at 0x21 and the name display at 0x2B. While the last of those had untargetable (0x800) and hide name (0x08) both set, the mob gets no block either. Phoenix sets both for a worm going under, a chigoe roaming hidden and an antlion buried in wait. Either one alone hides nothing. Vantage doesn't go by entity flags 0x080 or 0x008, since many mobs players can see carry them. A mob with no 0x00E seen yet gets no block until its next one, as after reloading Vantage near it. A despawn or a zone change forgets a mob's status, and its spawn brings it back. Vantage checks all this when it makes the list and again every frame, so a block goes the frame its mob is hidden (`test_overhead_hidden_mobs.lua`). The render flags stay a second check. There's no line of sight check, so a mob behind a wall still gets its block.

## What the client gets

A block shows only what Vantage has seen, and Phoenix sends less than the whole fight.

- An action (0x028) goes only to players within 30 yalms of whoever acts (`src/map/zone_entities.cpp:1547`). Other packets reach 50. A spell cast on a mob farther than that from you never reaches Vantage. That's why the distance cap starts at 30. It goes to 50 for what Vantage did see, since entities stay spawned to 50 yalms.
- A wear-off message goes to the effect's caster only, and to the player who loses it (`src/map/status_effect_container.cpp:634-646` for players, `:661-670` for mobs and pets). Your own debuffs on a mob leave when they wear off. Someone else's run on an estimate. One that runs out with no wear-off stays with no countdown, in its normal look, for as long as its row lives.
- Buff icons (0x076) come for the members of your own party only, the ones in your zone (`src/map/party.cpp:1231-1258`). The alliance and other players hold only what Vantage saw land on them, with estimated countdowns or none.

## The camera

Vantage reads the device's view and projection with `GetTransform` through the device's own vtable (Ashita's `libs/d3d8`), into buffers it makes once. By default (`overhead.camera.capture` `scene`), it reads them at the `camera.scene_index`-th BeginScene of the frame, which is 2 by default. Read at present, the blocks shook in game, and read at scene they held still. `present` reads them when the frame is shown. It's the one to try when scene reads no camera, as when `/vg overhead calibrate` says the frame had too few scenes. `/vg report` says which one is used and how many scenes each frame had. While overhead icons are off, it gives the one that's set.

Vantage uses a camera only when it looks like the world camera. It has to be a perspective of either handedness, with a vertical field of view of about 19 to 146 degrees and an aspect of 0.67 to 5. In its projection, P34 is 1 for a left-handed one and -1 for a right-handed one, P44 is 0, P33 has P34's sign, and P43 is below 0. It also needs a rigid view, and the camera within `max_distance` (60) yalms of you, which catches a menu's own preview camera. The game's own camera is right-handed, and its P34 is -1. With either handedness, w is the depth in front of the camera and the depth runs 0 to 1 from the near plane to the far one. So a point is placed the same way, and one behind the camera gets nothing. When a camera fails, Vantage keeps the last good one in use for `hold_ms` (250 ms), and after that it places nothing.

Points map to ImGui's DisplaySize, never to the device viewport. The scene can be drawn at 3840x2160 while the display is 1920x1080. Ashita keeps positions as X, Z, Y, with Z the height and up negative, so the head point is (X, Z - H, Y). That mapping is the one part not proven from code.

## Drawing

Each frame, after the panels, Vantage draws every unit's block on ImGui's background draw list, far to near and the target last. There's no window and no item, and nothing reads the mouse. So the icons are click-through and sit under every panel. The samples go on the foreground draw list instead, over the settings window you turn them on from, and they're click-through too. The effects are the tracker rows the panels show. Yours come from the client, your party's from 0x076, and everyone else's are as Vantage saw them land. An effect with no known time shows its icon in its normal look with no countdown. Vantage makes every table once, so a frame makes nothing (`test_overhead_draw_allocation.lua`).

Each unit type (mob, party, alliance, other, pet, other_pet, self) has its own layout and limits. Icons past a limit are left out, and nothing marks it. The row ends at the last icon shown.

| layout | what | mob | party, self | alliance, other | pets |
| --- | --- | ---: | ---: | ---: | ---: |
| `single` (default) | one row, `limit` | 8 | 8 | 6 | 6 |
| `lines` | debuffs nearest the name, buffs above (`swap_lines`) | 8 / 4 | 6 / 8 | 6 / 4 | 6 / 4 |
| `split` | buffs left, debuffs right of a `split_gap` (`swap_sides`) | 4 / 6 | 6 / 6 | 6 / 6 | 4 / 4 |

The limits fill tier by tier, oldest first within a tier, so icons keep their places as timers tick. On mobs the tiers are crowd control, the mob's lit buffs and what Always show has ticked, your debuffs, the others' debuffs, and then its other buffs. Crowd control is debuffs of catalog priority 80 or more, which are Sleep, Silence, Petrification, Stun, Charm, Amnesia, Terror and Lullaby, with Doom at 100. On everyone else the tiers are crowd control, other debuffs, what Always show has ticked, your buffs, and then other buffs. The single bar puts the debuffs it took left of the buffs. In Split the lit buffs sit nearest the gap. The crowd control slot (`cc_slot`) is for mobs in Split only. It draws the highest priority crowd control debuff at `cc_scale` (1.4) next to the gap, on the bottom line. It counts against the debuff limit, and it shows its countdown even with countdowns off.

Countdowns use the overhead's own copy of the panel options, with shadow on and outline off. They read like every countdown, in whole hours, then whole minutes, then seconds. From `small_icon_inside_px` (18) up, they go under the icon at half its size, 9 to 16 px. On 14 to 17 px icons they go inside at the bottom, shrunk as far as 8 px to fit, or not at all. Under 14 px there are none. Each type has a `countdown` switch. An effect whose duration override counts up (Timer durations in the guide) shows the time since it landed in the same place.

The party cooldown watch (`party_cooldowns.enabled`) and its **Over heads** (`party_cooldowns.overhead`) both start off. With both on, a party or alliance member's block gets one more line. It holds up to six of their party cooldown estimates (`core/party_cooldowns.lua`), soonest ready first. Each shows the ability's icon at the block's icon size, with its estimated time left. The line is centered, on the far side of the block from the name. Nothing marks the ones past six.

Each type's filters are the panels' tools: `kinds` (all, buff, debuff), `mine_only`, the `include` and `exclude` lists, and the shared hide rules (`shared_rules`). `buffs_mine_only` keeps only the buffs you cast. `debuffs_party_only` keeps only the debuffs from you, your party, your alliance or your pet, and one whose caster wasn't seen stays. Seven switches turn a group of effects off: `show_rolls`, `show_songs`, `show_protect_shell`, `show_food`, `show_barspells`, `show_stances` and `show_signet`. The last of them covers Signet, Sanction, Level Sync, Level Restriction, Reraise, Mounted and Battlefield. Each switch's ids are listed in `vantage/ui/overhead_defaults.lua`. The include list beats a switch, and `overhead.keeps` costs one table lookup for it. `show_copy_image` and `show_third_eye` are Always show keys. Mobs, your party, your alliance and you have them (`always_for`), and so do Party list buffs. With a key on, its effect shows whoever cast it and whatever `kinds` says. With it off, the effect doesn't. `exclude` still hides it, and an include list still shows only what it lists. Only your party's buffs reach the client. Vantage counts a mob's or an alliance member's shadows and follows their Third Eye itself (`core/observer.lua`). So the other types have no such key and treat these effects like any other. Copy Image leaves the tracker as 66 at any count, and the icon it shows is in `icon` (`core/tracker.lua`), so one id covers it. At first, mobs show the party's debuffs and their own buffs. The alliance shows its debuffs only, you show everything, and everyone else shows every debuff and the buffs you cast. Mobs and you start with all seven on and both Always show keys on. Everyone else starts with `show_protect_shell`, `show_food` and `show_signet` off, and your party and alliance start with both Always show keys off. Shared hide rules have the scopes Enemies, Other players and Pets. They match those units on every display.

Each block stays fixed on its own unit every frame. Blocks never move out of each other's way. Vantage draws them far to near and the target last, so where two overlap the nearer one is on top, and the target's always is.

## Dispellable buffs

A mob's buff lights up when Phoenix flags it dispelable and you can take it off now. It lights up in every layout, with a glow and a border in `dispel_color`. Phoenix flags 180 effects in `data/status_effects.yaml`, and the 128 that can exist on Phoenix are copied to `vantage/data/dispelable.lua`. Dispel, Magic Finale, Blank Gaze and Dark Shot all call `dispelStatusEffect`, whose default is that flag (`src/map/lua/lua_base_entity.cpp:14903`).

| tool | who | also needs |
| --- | --- | --- |
| Dispel (260) | RDM 32, or a RDM sub at sub level 32 (main 64) | learned |
| Magic Finale (462) | BRD 33, or a BRD sub at 33 (main 66) | learned |
| Blank Gaze (592) | BLU 38, main job | learned, and set, where 0x044 lists it as 80 |
| Dark Shot | COR 40, main job | a Dark Card or Trump Card in the inventory, a Marksmanship weapon and ammo |

The levels are the jobs bytes of `sql/spell_list.sql` (:429, :632, :759) and `sql/abilities.sql:152`. Phoenix lets a sub job cast a spell at its own sub level (`src/map/spell.cpp:807`). Blank Gaze and Dark Shot are past what a sub job reaches at 75, so only the main job counts for them. Phoenix sends 0x044 at every zone-in and when the set changes, and Ashita has no reader for the set the client keeps, so after a reload Blank Gaze counts from the next 0x044. The levels are the client's current ones, so Level Sync counts. Phoenix sends the synced levels in 0x061. Dark Shot's weapon and ammo check is Phoenix's own (`scripts/globals/job_utils/corsair.lua:899-904`). Vantage reads 0x044 at every zone-in. Until it has seen one, it doesn't light for Blank Gaze. A mob's debuffs never light, and neither do buffs on anyone but mobs.

Phoenix's Dispel only picks a buff with time left (`src/map/status_effect_container.cpp:960`). Vantage can't tell a mob buff with no time on the server from one whose time it didn't see, so it lights both.

## Debuffs you can remove

A debuff lights up the same way, in `dispel_glow` and `dispel_color`, on a type with `cleanse_light`. Party, alliance and self have that switch, and it's on at first. The debuff lights when it's in `vantage/data/cleansable.lua` and you can cast the spell that takes it off now. That list is built by hand from Phoenix at ed41f351f6 (phoenix/live). It has 41 effects, each with its spell.

| spell | WHM level | effects |
| --- | --- | --- |
| Poisona (14) | 6 | 3 |
| Paralyna (15) | 9 | 4 |
| Blindna (16) | 14 | 5 |
| Silena (17) | 19 | 6 |
| Cursna (20) | 29 | 9, 15, 30 |
| Erase (143) | 32 | 10-13, 128-142, 144-149, 156, 167, 174, 175, 192, 194 |
| Viruna (19) | 34 | 8, 31 |
| Stona (18) | 39 | 7 |

The levels are the jobs bytes of `sql/spell_list.sql` (:183-189, :312). No other job that's open on Phoenix has these spells. The job can be main or support, at the level the client shows now, and the spell has to be learned. A support job stops at 37, so a /WHM has no Stona. Erase takes any effect flagged erasable in `data/status_effects.yaml`. That's 38 effects, and 31 of them can exist on Phoenix. Erase's validTargets is 3, self and party, and the others' is 91, any player.

`dispel.cleansable(now, sample)` hands back two sets, which it refills at most four times a second. `near` is for you and your party. `far` is for the alliance, without what only Erase takes off. A draw looks each effect up in one of them, and asks the game nothing. `pick` sets the light after it has the effect's tier, so the light never changes the order or what a limit leaves out.

Vantage leaves out items, Benediction, Spring Water, wyverns and automatons, and it leaves out Silence and Mute checks too. A lit icon says you can try. Cursna only has a chance on Doom, and Erase takes one at random.

The Self debuffs and Party panels use `near`, under their own `dispel_light`, `dispel_glow` and `dispel_color`, with the light off at first. A party panel holds no alliance members. The party list icons have `party_ui.effects.cleanse_light`, which starts off. They light in the overhead `dispel_glow` and `dispel_color`, and they use `near` on your party and `far` on the alliance parties. Samples light whatever your job is, with the same reach.

## Settings, samples and commands

The Overhead icons panel (`vantage/ui/overhead_settings.lua`) is a display on the panel frame, and it has every setting players need. The settings that only matter for the guess are `name_lift`, `name_height`, `name_cap`, `target_height`, `target_cap` and the race heights. They stay in the settings file, and so do the hitbox line and the camera checks. `/vg set` reaches them there (`/vg set overhead.head.race_heights.8 2.2`). The panel's top line has **On** and **Show samples**. It has no **Locked**, since nothing over a head is dragged. **Show** has **Show icons over**, with a switch for each kind of unit in two columns. After that come the settings for the most units at once, the distance limit, the fade and the town rule. Then come **Change the settings for** and, for the kind picked, the layout, limits, countdown switch and which of buffs and debuffs show. Mobs also get the crowd control slot, and then comes the light the kind offers. **Size and place** has the icon sizes for every kind, with the crowd control icon's and **Countdowns go inside icons under**. Then it has **Icon size for this kind**, the setting for where blocks go, and the gaps. Last is **If icons sit too high or too low**, which starts closed. It has the offsets of the kind picked and the head offsets by name. Vantage saves that fold's open state as `Overhead/Head offsets by name`. **Look** has the countdown color, and **Lit icons** with the glow and color of a lit icon. The party list icons use those too. For the kind picked, **Filters** has the panels' filter tools, the effect switches, **Always show** and the shared hide rules. Its include and hide editor keeps its lists sorted. **Change the settings for** is one pick, on each tab that has rows for a kind. Your target, subtarget and the claimed, watched and debuffed mobs share Mobs. A player you target uses its own kind. Each change is one Undo step, and **Reset this display** (or `/vg reset overhead`) starts it all again. The main page has the switch, with **Edit**, and **Show samples**.

Show samples (`vantage/ui/overhead_preview.lua`) draws one block of made-up effects. It's laid out as the kind picked on the panel, and it goes through that kind's filters and limits. It sits above your own name, on your own name point where your own block would sit, and at your depth. When that point can't be read, it sits at your head height raised by the You type's name height instead. When you aren't on screen, it sits a third of the way down the middle of the screen, and it leaves the room a near name and cursor take. That's in first person, when you're turned away, or when there's no camera. The Mobs sample is the target. A player sample has an effect of yours for each switch under **Show these effects:**, and a type at its limit leaves the last ones out, as real icons do. What can be removed lights whenever the light is on, whatever your job. Its size holds through 0.6 px as a real block's does. It shows only while overhead icons are on, and it hides with the real blocks, but not for **When to show**. That hides only the real blocks, and `/vg report` gives it as the reason. A party or alliance sample shows the party cooldown samples in its line while the watch and that line are on.

**When to show** is the panel's last tab, and Vantage reads it at each refresh. Edit mode leaves the overhead icons out, since they sit over heads in the world. They have **When to show** only.

`/vg overhead on` and `off` turn them on and off, and `/vg overhead preview` turns the samples on or off. Each is one Undo step. Turning the icons off, by any switch or `/vg set`, ends the samples, and turning the samples on turns the icons on.

Profiles keep the overhead settings but never the samples, and a job-linked profile brings them on a job change. Shared presentation shares them with your other characters, but whether they're on and the samples stay with each one. A skin keeps their switches, layouts and filters and gives them its look. Their countdown and light colors start again, and they take the main page's font. Their size follows **Size** on the main page.

## Checking in game

`/vg overhead calibrate` reads your target on the next frame and prints two lines. They say what the target is (kind, SpawnFlags, Type, race, hitbox, ModelSize), its head height and where that came from. Then they say whether the camera is in use, how far it sits from you with the X, Z, Y mapping and with X, Y, Z, and which of them are within `max_distance`. With the camera in use, they go on with how many pixels the head sits above the feet, which should be positive, and the icon size. Last come the display and back buffer sizes. It still prints the distances when the camera fails its checks, so a wrong mapping shows as only X, Y, Z being near you, and it says which check failed. It also reads the camera in scene mode with overhead icons off. It writes the same to the report and changes nothing.

`/vg report` has an `overhead` section. It has the capture point and whether the camera passed. When it didn't pass, the section says which check failed, with the values it read. The check can be on the projection's shape, its depth for its handedness, its field of view or its aspect. It can also be on the view's last column, its rows, or the camera's distance from you. The section has how many frames passed or failed in the last second, and all 16 values of the last view and projection read, row by row, to 6 places. It has the projection's P11, P22, P34 and P44, DisplaySize, the viewport and back buffer, the client's boot sizes 0001 to 0004, and the units considered and kept. For the target it has its kind, SpawnFlags, Type, race, status, hitbox, ModelSize, render flags, claimer, head height and its source, depth, pixels per yalm and icon size. It also has where the target's block went, in pixels from the top of the display. `feet_y` is its feet and `anchor_y` is the block's edge. Above the name it also has `name_y`, which is the name point or the name's guessed middle. It has `name_px` and `arrow_px` there too, which are the room left for the name and the cursor, to 0.1 px. On the name point, `name_px` is 0 and `arrow_px` is how far the cursor reaches over the name's top. It's a good idea to check this on a Troll, a Lamia, a Mamool Ja and a Fomor, which Phoenix sends under other look kinds.

Here's what its `name_point` part has:

- `usable`, `problem` and `failed`, which names the pattern that turned name points off. It also has each pattern's address or `not found`, and the offsets read out of them.
- `display` (DisplaySize), `placement`, and `window`, the target window that the cursors are worked out from. It has the arrows' units, whether their stored points are used, the cursor box and where it came from, ky, the menu width and height, the action callback, death flag, AnkX and AnkY, the subtarget's, slots 0 and 1 with their actors, and each cursor frame with its box.
- `cameras`, the client's own cameras, for a cross check. It has the client's copies, the device wrapper's at the scene read and now, the window's size, and the viewport. It also has `scene_target`, the size of the scene the names are drawn into before it's stretched onto the window. That's 3840x2160 when the game draws at that size. Vantage reads these with 7 more patterns that it finds at the first report. Missing ones leave only this check out.
- `units`, a row for each unit with a block and each unit a cursor is on. A row has every raw value its name point is made from: actor, entity and back link, name and cursor point indexes, root, scale, `lift` (the float at 0x8C0), node, handle, data, bone and generator counts, point 2's bone, offset and rotation, `m` and the `model` size it multiplies, and the point x, y, z or why there is none. It has the unit's `status`, `race`, `model_size` (Ashita's) and `hitbox`. It has `actor_kind`, the actor's kind at 0xA4 that the chocobo, mount and chair gates test, while `kind` is Vantage's own. It has the flags its icon is picked from, with the icon rise and icon. Those flags are `flags0` to `flags4`, `flags7` and `flags8`, the render flags, and `campaign`, `ballista` and `monstrosity`. It has which arrow is on it, `path` (`name point` or `guess`) and `reason`, and `anchor_x` and `anchor_y`. On the name point it has ax, ay, z, zi, w, `ndc_x`, `ndc_y`, s, t, `name_top`, `icon_top` and `arrow_top`. Under the main cursor it has `ky_sample`, which is ay over the stored AnkY, to set against `window.ky`. Then come `guess_y` and `guess_anchor_y`, where the guess would have put it. It also has `check`, which is where the client's cameras put the name point, the guessed point and the root, against where Vantage's camera puts them. Its `_dx` and `_dy` are Vantage minus the client, in display px.
- Values read at offsets fixed for client 04288488 rather than found by a pattern, which `fixed_offsets` lists. Those are point 2's rotation (`rotation_x` to `rotation_z`, at its + 2, + 6 and + 0xA), the actor's copy of the unit's position (`base_x` to `base_z`, 0x5FC) and its attachment offset (`offset_x` to `offset_z`, 0x60C). The client makes the root from their sum. They also include the four model sizes `actor_754` to `actor_760`, and `actor_88`, `actor_8c` and `actor_b2`, which are the name's size and hide bits.

To check the name points in game, you need one `/vg report` and one full-screen screenshot with your character and a small mob on screen, with the mob targeted. Each block's bottom edge should sit `gap` px over the name, or over the cursor on the mob. The report's `check` should put Vantage within a pixel of the client's cameras, and every unit should say `name point`.

These are still to settle in game, and they're all guesses until then:

- Whether every name is drawn from P as read (mounted players, players in a chair, Ballista and campaign icons, names that hang from another point).
- Whether a floating target cursor should lift the target's block at all.
- The race heights and the mounted, sitting and chair factors, for the guess.
- The hitbox line for mobs, and how far it misses on long, low bodies (rabbits, crabs, pugils, sheep) and on floating elementals.
- The race size table for players (Galka 2.0 against Hume and Elvaan 1.7).
- For the guess, where the middle of the game's name sits over a head, which is 0.5 yalm over players and none over mobs. The same goes for the name's and target cursor's size in the world and their largest, which are 0.33 yalm and 24 px for the name and 0.4 yalm and 16 px for the cursor. These also need settling with the scene at 3840x2160 and the display at 1920x1080.
- What `ModelSize` holds.
- Whether the 2nd BeginScene holds the world camera on other setups than the one it was seen on, and the X, Z, Y position mapping.
- The meaning of render flags 0x200 and 0x4000, and how a Troll, a Lamia, a Mamool Ja and a Fomor classify.
- Whether the client's item Skill is 26 for a gun and its bullets.
- How many effects a mob and a party member carry in era fights, behind the limit of 8.
- How the lit look and the countdown sizes read at 1920x1080.
