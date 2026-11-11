# Client cooldown tracking

Vantage reads your own spell, ability and equipped enchanted-item cooldowns. It never casts, equips, uses items or sends recast commands.

## Display layouts

Separate panels for each category are the default. The combined layout puts the categories you pick into one panel with its own settings. Switching layouts keeps both sets of filters, order, look and placement. To switch, use **Show as** on the Recasts panel or `/vg recasts combine` and `/vg recasts separate`. Showing or hiding applies to the layout that's selected. An alert that's on can still request its category when its panel is hidden. Both layouts share the same passive reader and refresh rate.

Unlock any recast panel, hold Shift, and drag its center to move it, an edge to resize one dimension, or a corner to resize both. Captions wrap at the selected font and icon sizes. The combined panel uses the same renderer and customization controls as the separate panels.

Each recast panel and the combined panel offer **Text** next to **Bars**, **Expanded bars** and **Icons**. It shows one row for each recast with its name and countdown, and no icon or bar. It uses the panel's font, colors, sort, filters, alerts and ready-soon color. Rows take the height of their text rather than the bar height. **Row height** still applies. You can't show or hide fields there. Labels, dividers and colors still apply, and the fields you've set to show stay saved for the other layouts. **Bars** remain the default.

## Native clocks

The installed Ashita SDK exposes spell clocks through `IRecast:GetSpellTimer`, and ability slots through `GetAbilityTimerId` and `GetAbilityTimer`. The reader samples the spells the client has a name for among indexes 0 through 1023, and it finds those once. It also samples the 31 ability slots verified in the installed client's native timer loop. Spell and ability clocks use 60 frames per second. The reader deduplicates ability slots by timer ID. When the client has duplicate entries, it keeps the longest clock among them. Slot 0 is the shared job-special timer. Its caption doesn't assume a one-hour or two-hour server rule.

Resource names come from the client's `IResourceManager`. A shared ability timer's name shows up to two resource names and how many more aliases it has. A shared timer doesn't tell you which of its actions was used. Vantage doesn't work out charge counts from job levels, retail job points or hardcoded recharge formulas. An ability can be usable before its full client recast ends.

## Client artwork

Spells use their resource list-icon fields. Abilities use native ability icon metadata and keep the timer ID separate from the action ID. Native action shapes can contain several textured pieces, including tier markings and tints. The renderer puts those pieces together from the installed client files. The Original FFXI/XI View recast choice is separate from the buff-icon choice. Missing replacement artwork falls back to stock.

Known-ability data narrows shared timers down to the actions the client exposes. A common picture can stand for the group. Different pictures show together, in a group of up to four. An action Vantage can't identify stays unknown. Vantage never uses a retail job mapping or an assumed action use to pick an unrelated icon. Candidates for timer zero must also have the verified player-action resource type. Pet records with a default zero timer can't provide the job-special icon. Known-action metadata refreshes once a second, and right away when job, level or data-readiness fields change. A spell the client has no name for is never read, so it has no row.

**Icons show** lets you choose **The effect it gives** (the default) or **The spell or ability**. With the effect it gives, a spell or ability that gives a status shows that status icon in the buff icon artwork (**Icons** under **More look**). That's the same picture the buff and debuff panels draw. Spells use the status in `data/effects.lua` (`spells`), so every tier of Protect shows Protect. Phantom Rolls use `data/actions.lua` (`rolls`), and the other job abilities listed in `data/effects.lua` (`abilities`) use theirs. A row for an effect the action gives only sometimes doesn't count (`sometimes` in `ui/recast_icons.lua`): Cure's Stoneskin, which needs Afflatus Solace, and the effects of Chakra, Charm, Jump, Chi Blast and Double-Up. Any other job ability uses the status the observer read from your own use of it this session. Your use shows up as a category 6 action that names the status it gave. An ability seen giving two different statuses stays unknown. A shared timer shows a status only when every action it can stand for gives the same one. Actions with no status, unknown actions, the unidentified job-special timer and items keep their action or item picture. So does a status whose picture isn't available.

Item images use the actual item ID and the SDK resource bitmap. They use a 64-entry cache and bounded retries for data that isn't available. Vantage releases textures on eviction and on unload. The release archive never includes native artwork. Missing artwork never changes timer or alert behavior.

Item tracking uses Ashita's own `ffxi.itemdata.parse_timer_info(item, resource, true)` helper. The bounded 16-slot equipment scan resolves the inventory location that each equipment entry records. Only enchanted weapons or armor with valid charge and delay data are eligible. The use delay the helper gives includes equip delay. Items with a finite number of charges and none left don't produce a ready notification. Unlimited charges keep the client's 255 marker. This reader doesn't cover bag contents or ordinary consumables. If the helper or the client clock isn't available, Vantage leaves the item timer unknown.

## Confidence and alerts

- Timers that are already active when the addon starts, or when the character, zone or job changes, form a quiet baseline. Their full duration stays unknown. The exception is a cooldown Vantage was already following. It keeps its start, observed duration and instance through a zone change or a pause in sampling over 2 seconds. That happens when, for the same character and main job, the client's timer still ends when it did (within 1.5 seconds). A ready pulse that already played for it doesn't play again.
- A sampled zero followed by a positive clock emits `started`. So does a clock that rises by more than 0.1 seconds, or by more than 1.5 seconds for an ability. Abilities need the bigger rise because Phoenix sends every ability timer again, rounded up to whole seconds, each time an ability is used. The timer's first observed remaining time becomes the bar's observed duration. It isn't a reconstructed server cast time.
- An ability timer the client didn't list before emits `started` only with your own use of an ability on that timer, from 3 seconds before its first reading to 3 seconds after. Phoenix lists only the abilities on cooldown, so your first use of one since you logged in, zoned or changed jobs brings a timer with no reading before it. So does a zone's list that comes after the first read, and those timers start nothing. Your use is the action the observer reads from you: category 6, or category 3 for Jump, Steal, Shield Bash and the others that finish as weapon skills do. A use paralysis stops is category 4 with no ability id, and its timer still starts unless it's a job special. Your request to use an ability (0x01A) in the 10 seconds before the paralysis says which one it was. The server acts on a request at its next tick, so the paralysis comes about a round trip after it, and the 10 seconds leave room for a lag spike. The ability's resource gives its timer. Yonin and Innin share a timer on Phoenix, and a use of either starts both of theirs, 146 and 147. A Blood Pact's timer starts when the avatar's move goes off, which can be more than 3 seconds after your use when the avatar has far to run. So your avatar's pact going off, category 13 with the pact's id, is a use of it too.
- An active timer followed by an explicit client zero emits `ready`. Negative elapsed item delay from the SDK helper also counts as confirmed completion.
- A projected deadline doesn't emit `ready`. The row waits for a fresh client observation.
- Unreadable clocks, ability IDs that disappear, unequipped items and interrupted snapshots don't mean a recast is ready. Their unknown rows expire quietly after 10 seconds. The verified native expiry loop keeps the ability ID when its timer reaches zero, which supports confirmed ready alerts.
- Before and after sampling, the SDK identity fields that are available must still match the character, zone and main job the reader was given. Zoning or an identity change makes the whole sample invalid.

Recast rows use `domain='recast'` and `scope='self'`. Rule IDs and labels are separate from status effects. Spell IDs are 10000+spell ID, ability IDs are 20000+timer ID, and item IDs are 30000+item ID. Multiple equipped copies of an item share the rule ID but keep separate row keys and cooldown instances.

## Runtime API

`core.recasts.new()` returns a reader with `update(snapshot, now, options)`, `view(now)`, `project(view, now)`, `drain_events()`, `reset()`, `used(ability, now)`, `requested(ability, now)` and `paralyzed(now)` methods. The entrypoint calls `used` with each job ability of yours the observer reads, `requested` with each job ability you ask the server to use (0x01A), and `paralyzed` when the observer reads that paralysis stopped your action. The entrypoint's refresh interval controls sampling. Projection makes no SDK reads and creates no events. Options can turn off the whole reader or any of the `spells`, `abilities` and `items` categories. `view` includes capability flags and sample read counts for diagnostics. `recasts.catalog(kind)` returns a stable cached table for `spell`, `ability` or `item`, or for all categories when you leave the argument out. Callers treat these tables as read-only. The item catalog holds the equipped enchanted items Vantage has seen.

## Offline validation

Run the focused fixture and reproducible mocked benchmark from the repository root:

```powershell
python tests/run.py test_recasts.lua test_recasts_first_use.lua test_app_live_first_recast.lua test_recast_metadata.lua test_recast_alerts.lua
python tests/benchmark_recasts.py --out tests/out/recasts-benchmark.json
```

One 1000-iteration run measured these steady `update` plus `view` costs. Per-frame projection was timed separately.

| Scenario | Rows | Sample time | Projection time | Counted SDK/helper reads per sample |
| --- | ---: | ---: | ---: | ---: |
| Disabled | 0 | 0.000650 ms | 0.000003 ms | 0 |
| Idle | 0 | 0.029535 ms | 0.000006 ms | 1110 |
| 16 spells, 8 ability timers, 2 items | 26 | 0.071696 ms | 0.000220 ms | 1121.3 |
| Full synthetic capacity | 1071 | 1.398723 ms | 0.013240 ms | 1156.2 |

Every projection made zero SDK reads. Counts include identity verification, timer slots, equipment entries, occupied-item resolution, the mocked item parser and known-ability metadata reads. The benchmark gives each ability timer two resource candidates, one known player action and one unavailable action. It uses ready ability data and stable main/subjob levels. Sampling moves forward in 100 ms steps. The one-second known-action refresh adds an average of 2.3 checks per active sample and 9.2 per capacity sample. Fractional counts are averages across 1,000 updates. Active job/readiness fields are checked every sample.

The JSON output counts resource lookups separately. They come to 2 per active sample and 16 per capacity sample for equipped-item records. Spell metadata is cached on use, and ability aliases are indexed once. These steady measurements leave out initialization. Actual known-action work depends on the number of client resource aliases and on job or readiness changes. These scenarios don't cover every possible alias distribution.

These are isolated LuaJIT measurements with mocked SDK functions. They don't measure native pointer access, game packet processing, rendering, font or texture work, GPU load, FPS impact or live-client behavior.

The main local API references are `addons/libs/annotations/SDK/Memory/IRecast.lua`, `IInventory.lua`, `IPlayer.lua`, `addons/libs/annotations/SDK/IResourceManager.lua`, and `addons/libs/ffxi/itemdata.lua` plus `ffxi/time.lua` in the configured Ashita installation.
