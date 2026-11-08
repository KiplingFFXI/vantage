# Runtime performance

This note covers how to measure Vantage's cost, what it costs today, and how the addon keeps a frame cheap and a load short.

## Frame benchmark

`tests/benchmark_frame.py` measures a frame without the game. It runs the real `vantage.lua` and UI modules in a plain LuaJIT 2.1. It uses the mocked SDK and the ImGui stand-in of `tests/frame_harness.lua`, and the installed client art, which it only reads. It needs `ASHITA_LIBS` set. `--runtime x86` runs `tests/luajit-x86/luajit.exe` through `tests/x86_runtime.lua`, the runtime the game uses. `--runtime host` is the default. It's the 64-bit test runtime, and its times move about 0.03 ms from run to run, so go by x86 for the time.

```powershell
python tests/benchmark_frame.py --runtime x86
python tests/benchmark_frame.py --runtime x86 --scenario party6 --scenario cooldowns --runs 8
python tests/benchmark_frame.py --runtime x86 --addon C:/path/to/baseline/vantage
```

With no `--scenario`, it runs every scene, panel tab, page and search. Each one runs in `--runs` separate runtimes, 3 by default. A run draws 300 frames to warm up, then `--repeats` timed batches for each collector setting, 5 by default. It prints KB a frame with the collector stopped and ms a frame with it running and stopped. It also prints the single-frame mean, p95, p99 and max, and LuaJIT's flushes.

These are offline Lua timings with no game, no GPU and no real ImGui, so they aren't frame rates. The harness stubs the reads of the game's party list. Its mocked getters are Lua, where the game's are C calls. To compare two builds, point `--addon` at a copy of the other one and keep both on the same cores. Let the builds take turns, because the one that ran second in a pair was the slower one in five of six solo pairs. With the JIT on, runs land on a few levels, so two runs can be a few KB apart. `tests/test_draw_digest.py` counts these frames' draw calls. `tests/test_frame_search.py` checks that the `main_`, `panel_` and search scenes draw what they say. `tests/test_frame_shut_cost.py` checks, with the JIT off, that a scene with the window shut leaves the window unloaded. It also checks that the scene makes at most 0.5 KB a frame more than with the window loaded first.

## Frame scenarios

The header of `tests/frame_harness.lua` has these in full. Every scene has four alert rules. The harness player is a RDM who is Silenced and Amnesia'd, so recast rows draw their locks where the tints are on.

- `solo` has fresh defaults, with 16 effects on the player and 8 on the target.
- `party6` has six members with 12 effects each, 16 on the player and 8 on the target, beside a fixed game party list.
- `alliance18` has 18 members with 32 effects each, 32 on the player and 32 on the target.
- `filters` is `party6` with five shared hide rules on.
- `overhead` is `party6` with overhead icons on. That's ten units with eight icons each.
- `cooldowns` is `overhead` with the combined recast panel and the party cooldown watch everywhere. It lights 16 borders a frame.
- `rolls` is `party6` with your Phantom Roll and a member's. Their members and Double-Up windows are ticking.
- `pet` is `party6` with a jug pet, eight effects, three lines of maneuvers and six pet command recasts.
- `edit` is `party6` in edit mode, with displays anchored and every timer panel shown only as RDM in a field.
- `settings` is `party6` with the window on the main page and every section open. `main_closed` and `main_open` are that page with **More look** closed and open. `main_grid` adds Grid mode with its section open.
- `settings_durations`, `settings_profiles` and `settings_help` each open the page they're named for. `settings_display`, `settings_party` and `settings_filters` open the panel frame.
- `search_home` and `search_<page>` have `effects` in the search box. It's a plural, and a plural costs the search the most. `search` is a player typing there, with a new word every 25 frames and a new page every 100.
- `panel_` scenes are one tab of a display, mostly with its sections closed. `panel_show` to `panel_when` are on Watched enemy timers in bars. That's the panel with the most rows that draws nothing in `party6`, so a row measures the editor and not a change of scene. The rest go by their display, from `panel_recasts` to `panel_hidden`.

## Offline benchmark

`tests/benchmark_runtime.py` uses the existing LuaJIT mock harness and the real client, roster, tracker, alert and entrypoint modules. Empty renderers replace the drawing. The benchmark counts instrumented mock SDK method calls and measures process CPU time around each batch. It leaves out setup, loading and 120 warm-up iterations. The values it reports are the median of three batches with 3,600 iterations each.

In the alliance scenario, self holds 32 effects, the target holds 32, and each of 17 members holds 32. That's 608 rows in all. `self_target` has self and the target, for 64 rows. `disabled` has self alone, for 32 rows, with the panels, the target and alerts off. The native-cache mock provides own-party presence. Alliance and target timers are observations with incomplete presence knowledge. Enabled scenarios include eight alert rules. `disabled`, `self_target` and `alliance` call the refresh each iteration. The `idle` and `bursts` rows of `alliance` fire a Present on a 60 Hz clock and leave the refresh to it. The burst scenario submits eight status packets before every sixth frame.

Run the current source with the Python environment you use for the Lua tests. To compare another build, point `--addon` at its folder that holds `vantage.lua`, `core` and `ui`. `--source` is an alias for `--addon`.

```powershell
python tests/benchmark_runtime.py --count 3600 --repeats 3 --out tests/out/performance-current.json
python tests/benchmark_runtime.py --addon C:/path/to/baseline/vantage --count 3600 --repeats 3 --out tests/out/performance-baseline.json
```

These are offline core measurements, not FPS measurements. They leave out GPU cost, real SDK access costs, texture/font loading, native-menu traversal and actual screen drawing. CPU timings vary between runs and machines. The call counts cover the instrumented mock methods. Live D3D8 behavior and fishing-menu transitions still have to be checked in the client. This benchmark doesn't prove zero overhead or a guaranteed frame-rate improvement.

## Other benchmarks

Each of the other benchmarks measures one piece offline, and `--help` lists its options. `tests/benchmark_render.py` measures the party strips alone, attached to the game's list and detached in a scrolled panel. `tests/benchmark_core_packets.py` measures observer processing after action decode. `tests/benchmark_countdowns.py` measures countdown glyph layout. `tests/benchmark_effect_filters.py` measures unchanged effect-rule compilation. `tests/benchmark_profiles.py` measures the mocked Profiles page. `tests/benchmark_recasts.py` measures mocked cooldown sampling and projection (see `docs/RECASTS.md`).

## Current numbers

All of these numbers come from `tests/benchmark_frame.py` in the x86 runtime with the collector running. The runs were pinned to one set of cores and had 0 flushes. The table below has the medians of eight runs.

| Scenario | x86 KB a frame | x86 frame | Times party6 |
| --- | ---: | ---: | ---: |
| party6, window shut | 12.2 | 0.130 ms | 1.00 |
| main_closed | 13.4 | 0.170 ms | 1.30 |
| main_open | 13.6 | 0.184 ms | 1.42 |
| One panel tab | 14.3 | 0.158 ms | 1.22 |

One panel tab is the median of the forty runs of `panel_show`, `panel_look`, `panel_filters`, `panel_party` and `panel_pet`. For the open window, the time goal is a frame of at most 1.25x party6. The KB goal is at most about 8 KB a frame over party6 in x86, and about 15 in the test runtime. Each of those five tabs is 1.19x to 1.25x and meets the time goal. `main_closed` and `main_open` are over it.

The other scenes ran in the same conditions. The table below has medians of two runs, and of eight for `party6` and `cooldowns`.

| Scenario | KB a frame | Frame |
| --- | ---: | ---: |
| solo | 2.0 | 0.062 ms |
| party6 | 12.2 | 0.130 ms |
| alliance18 | 44.0 | 0.530 ms |
| filters | 14.5 | 0.140 ms |
| overhead | 12.6 | 0.170 ms |
| cooldowns | 13.8 | 0.262 ms |
| rolls | 12.2 | 0.155 ms |
| edit | 12.5 | 0.145 ms |
| settings | 13.6 | 0.184 ms |
| settings_filters | 14.2 | 0.154 ms |
| settings_party | 14.3 | 0.160 ms |
| settings_durations | 14.2 | 0.162 ms |
| settings_profiles | 14.4 | 0.166 ms |
| settings_help | 13.7 | 0.172 ms |
| search | 25.0 | 0.258 ms |

`pet` makes 14.3 KB in 0.189 ms. That's the median of eight runs in the same conditions. A refresh copies only the tracker's rows that changed. A row that still holds what it did keeps the copy it had, with its time left worked out again (`tests/test_tracker_view_reuse.lua`). `overhead` makes about 0.4 KB a frame more than `party6`, because the 32 effect rows of the four mobs are handed out again like the rest. Drawing itself makes nothing. Grid mode on with its section open adds 0.1 KB at most and 0.002 ms. An open alert draws about 30 more rows for no more than 0.2 KB, because those rows are the same tables each frame.

Some costs come once rather than each frame. The first time the window opens, it takes about 6 ms and makes about 1 MB. The first key in the search box takes about 14 ms and 3.5 MB. Until then, neither one is loaded.

## How a frame stays cheap

The refresh works out what a display shows, and a frame only draws it. The refresh runs at 10 Hz, or sooner when a packet or a change wakes it. The packets a fight sends many of wait for the next refresh. Those are a hit on a mob, the party's HP updates, your own status update when your effects didn't change, and an entity leaving view that no display shows. So a fight still refreshes at about 10 Hz. Vantage copies each packet it reads out of the game once. It reads the game's UI flags once a frame, and the chat log's place about once a second. Vantage keeps and refills most of what a frame needs. What's left is small tables and strings, and that's the KB a frame above. A refresh frame makes several times what a plain one does.

### Party list strips

The strips beside the game's party list draw icons only, so they lay out no names, bars or text. They keep their plans, each row's effect options, its effect list and its cells from frame to frame (`overlay.plan` in `ui/native_party_hud.lua`, `kept_effects` and `kept_cells` in `ui/party_layout.lua`). They also reuse the corner and clip tables they hand to ImGui. They read the game's party windows again only for a new roster or another screen size, not every frame (`tests/test_native_party_list_reads.lua`). Each refresh makes a new roster. They check the selection settings once a draw for all their rows (`tests/test_party_strip_selection_check.lua`). Like the window's look, their look (`theme.party`) is kept until the settings count a change. A strip works out a row again only when one of these changes: a setting, the row's subject, one of the eight fields the selection compares, the order of a sort by time left, or a countdown's text. Each refresh makes the row's subject again. `effect_filters.subjects` gives back the same copy while the rules, the member and the effects stay the same. A member with nothing tracked keeps one empty list. A strip moved off the game's window keeps all of this too.

### Timer panels and other displays

- An icon panel's rows show the same few countdowns from frame to frame, so Vantage keeps the lines it makes for one. They're kept by what the panel's countdowns look like and the room they get, then by color, then by text, and each level is bounded (`kept_icon_lines` in `ui/hud.lua`, checked by `tests/test_icon_lines_kept.lua`). Each panel's working copy is refilled every frame.
- A bars, expanded or text row keeps its lines and where they go, by panel and row. It works them out again only when a setting they use or its countdown's text changes, at most once a second. Auto width keeps each row's width the same way (`tests/test_hud_kept_layout.lua`). The panels' places, the samples and their tags, and the alerts are all kept and refilled too. So drawing the panels makes nothing a frame once warm (`tests/test_hud_draw_allocation.lua`).
- Show conditions are worked out at the refresh (`core/conditions.lua`), and each display's result is a flag that a draw looks up. Anchors are a few sums a frame, from a kept entry that each display gives `ui/elements.lua` as it draws.
- The Phantom Roll and pet displays draw through one box (`ui/element_box.lua`) that keeps its tables. Each countdown's text is made once for each second and format (`tests/test_element_draw_allocation.lua`).
- Recast marks and locks, the party cooldown cells and list, and a ready pulse each keep and refill their tables. The client action icons they draw refill theirs. The watch, the tints' marks and the pulse's choice of what to play run at the refresh.
- Overhead icons start off. While they're off, they cost one check a frame. `tests/test_overhead_allocation.lua` and `tests/test_overhead_draw_allocation.lua` check that placing and drawing them make nothing a frame once warm.

### Moving displays

While edit mode is on, it draws an outline window for each display and the bar every frame, from kept tables. It works out the bar's look again only for other settings and each half second. Only a display ticked for Grid mode snaps, and only while Grid mode is on. Any other display's drag runs no snap search and draws no grid and no line. The search keeps its best line so far in the module and reuses two tables for line ends, so it makes nothing in a frame of a drag. `tests/test_snap.lua` runs a move's search and a resize's 600 times, and the collector counts under 0.002 KB each. While nothing is dragged, a frame makes nothing.

### Reading the game's party list

If a display is anchored to the list, Vantage reads the list whatever Grid mode is set to. For snapping, it reads the list only while Grid mode and Snap to the game's party list are on and a ticked display is on and unlocked. That happens in edit mode, and from the press of a Shift drag, but not while Shift is only held. A pass over the list runs inside one Present, and the client waits on it. So the pass queries each region once and forgets them all when it ends. The harness stubs these reads, so the frame tables can't show them. When the real reads run over a list in one buffer, they add under 0.03 ms, with 2 page checks a frame. The game's windows sit in more regions than that buffer, so a pass over them makes a few more page checks (`tests/test_native_page_regions.lua`, `tests/test_native_page_regions_geometry.lua`).

### Settings window

`vantage.lua` calls `ui/settings_stub.lua`, which loads the window the first time it opens and hands it every call after that. Until then, a frame draws nothing for the window, the mouse checks answer that it takes nothing, and there's no resize to end. A window file that can't load stops the window, and Vantage says so once. A command that opens the window tries it again. While the window is open, it brings its working copy of the save up to date only after something changes, because walking the whole save is the most expensive part. The main page and the panel frame (`ui/main_page.lua`, `ui/panel_frame.lua`) draw from row tables made once when the window loads, so a frame makes no closures or value boxes. The panel frame shares one scratch value for each kind of control. The window keeps its look (`theme.window`) until the settings count a change, or until its settings, style or window style tables are new ones (`tests/test_window_look_cache.lua`). What the pages work out from the settings is kept the same way. That covers the main page's lines about the settings, the Timer durations lists, and what an import read on Profiles would change. The main page's lines also wait for the mouse to come up while a drag changes the settings every frame. In the Timer durations lists, a learned time counts as a change. `skin.prepare_menu` makes no table or function. It runs each time, because the art it checks can go and come back with no settings change. Painting the skin under the window, its lists and its tooltips (`skin.menu`) makes none either. It works out the resize grip corner's color once for each look (`tests/test_menu_paint_allocation.lua`).

### Settings search

`ui/search_index.lua` builds the index as it loads. Nothing loads it until you type a key in the box, so an empty box does none of that work. The search scenes measure a warm index. The search leaves out what a page draws only while a state is on (`index.states`), so no result opens onto a control that isn't there. Those controls' names find the switch that shows them instead. A state that reads only the settings is read again when they count a change. A state marked live is read each time the search runs, because it reads what a page keeps, the view or the callbacks (`tests/test_search_states_read.lua`). A label going back to the text it just had doesn't count as a change, so on every page the search runs once for each new word or page.

### Party icons at their drawn size

Beside the game's party list, the icons fill the step from one row to the next with no space between them. That's 20 px at 1920x1080. Each status icon in Original FFXI or XI View art is made once at the size it draws (`icon_texture_at` in `ui/client_assets.lua`) and drawn 1:1. A build shrinks the icon's 32 px picture by area in Lua into the corner of a 32, 64 or 128 px square texture and uploads it. Up to 4 builds run in a Present. A size is built only once it has been asked for 0.25 s in a row, so a size you pass through while dragging a slider is never built. Each art keeps 4 sizes at most. A failed build draws the 32 px texture and is tried again after 5 s. Client art and 32 px icons draw the 32 px texture. `party_icon_sizes` in `/vg report` has the sizes, builds and slowest build.

Each texture is 4 KB up to 32 px, 16 KB up to 64 px and 64 KB up to 128 px, and each one is held twice as a managed texture. The party6 harness made 28 icons at 20 px (112 KB), and alliance18 made 54 (216 KB). At 128 px, 100 different icons would take 6.4 MB. In the x86 runtime with the installed client art, the median build took 0.036-0.076 ms at 20 px and 0.295-0.345 ms at 128 px, with the test's stand-in for the upload. In the game, each upload of a small texture took about 0.16 to 0.25 ms, so a Present that builds 4 icons is about 0.8 to 1.3 ms in all. Looking up the made textures is about 0.05 ms a frame in `alliance18`.

## Loading

The load event does only what must happen in it: the module requires, the menu fonts from their cache and the Windows font registration (`fonts.load`), and the sound list. The font work happens there because ImGui takes new fonts only in the load event. Everything else runs as named warmup steps (`core/warmup.lua`) at the top of each Present, and so does every client search the first frames would make. So loading is one short stall.

### Warmup steps

The steps run in this order. First come the game clock's pattern, the client's event, interface and map flags, and the chat log's table and scale. Then come the stock art, the bitmap face, the status icons, the recast item loader and the three action files. For the stock art, the window frame the settings draw with comes first, then the font. The last action file is taken from the font's read of `51.DAT`. After those come whichever of XI View's art, face, status icons and action files the saved look draws with. Next come the game's party list and the Treasure Pool's patterns, when a display needs them. Last come the name point's 16 patterns, then its offsets, when overhead icons are on.

- The first Present after the load runs no step, because nothing is shown between the load event and that Present. From the second on, each Present starts steps until 8 ms have gone, and it starts at least one. So no Present spends more on them than 8 ms plus its largest step. The one other Present that runs none is the one the displays first draw in, so their first draw never comes on top of a full budget of steps. The refresh runs on every Present from the first, so no packet is lost.
- No display draws until the steps it needs have run and a refresh has read the settings. That takes a character in the game. At the title screen, though, a command can still show the settings window or edit mode with the defaults in use. The displays then start in the same Present with all their art. Overhead blocks also wait for the name point's steps.
- The party strips and their Treasure Pool check wait while the party list's steps are still to run, so strips you turn on later never search inside a draw. Another window frame or a part of XI View that you pick later loads at its first use, inside that draw. A zone-in packet for a character whose saved look uses XI View loads the parts it draws with inside the loading screen.
- A Vantage command or `/vg report` first runs every step that's left. A new graphics device makes the art again as steps, and the displays wait for it as they do at load. An unload runs no more steps and lets every texture go.
- If a step fails, Vantage says so in chat in plain words and skips it, and the displays still draw. Each part is said once. `/vg report` keeps every failed step's name and error in `startup.failed`. Without a timing clock, every step runs in the load event.

Vantage keeps the client patterns for the life of the game process in the environment variable `VANTAGE_PATTERNS` (`core/patterns.lua`). Nothing is written to disk. A reload uses a kept address only while it lies in the client, its pages can be read, and the pattern's fixed bytes are still there.

### Fonts and client art

- The client font texture `moji` goes to the device as its top 64 rows, because the bitmap face draws only the first two rows of 16-pixel glyphs. That's 64 KB of DXT3 that becomes 256 KB. Rows 0-35 go up as they are, rows 36-59 go up blank, and the texture's own last four rows go up as rows 60-63. So a top glyph's top edge filters against the same row whether the sampler wraps or clamps (`tests/test_moji_upload.lua`).
- Vantage caches the menu fonts in `cache/client-fonts/<kind>-v2-<key>.ttf`. The key is made from the client file's path, size and last write time and the generator's version. A whole cached font loads with no client file read and no client art loaded. A changed client file, or a cached font that's cut short or damaged, makes the font again. Once a new font is written and reads back whole, Vantage removes the kind's other `<kind>-v2-<16 hex digits>.ttf` files in that folder, because they were made for a client file that has since changed. Nothing else is touched. A client file that's read but can't make a font gets a note under its key in place of the font, so it isn't read and tried again at every load.
- A font each load adds stays in ImGui's atlas, because nothing in Ashita's SDK says taking one out is safe. So a reload in the same game uses again each font the last load added, while the atlas still holds it with the same id, size and name. It goes by notes kept in the environment variable `VANTAGE_FONTS`, and it adds only the rest. `art.atlas` in `/vg report` has how many fonts the atlas held at load and how many this load used again or added (`tests/test_font_reuse.lua`). A custom font file is read as far as its table directory first. One that's cut short, damaged or not a font is left out.
- If a DAT file holds a texture that can't be used, or holds one twice, Vantage leaves that texture out with its reason. Only one the art needs makes the art fail. A window frame's four pieces must be the stock sizes. Those are a 128 px background and 32 px frame pieces and corner. A status icon file's records are checked at once, and each one is made into pixels the first time it's drawn. So Vantage keeps the file in place of all its records made. The file is about 3.9 MB a pack, and all its records made would be about 2.7 MB. New 32 px status icons and new action icon textures share a budget of 8 uploads a Present (`spend_upload` in `ui/client_assets.lua`), so a screen of new icons comes in over a few Presents. An icon past the budget draws nothing until it's made. It never draws another art's picture. Vantage lets an action texture's converted pixels go once it's uploaded.

In the test runtime (x64 LuaJIT), `fonts.menu` took 0.75-1.25 ms from a whole cache and 51.7-64.5 ms when the font was made and written. Those runs used the installed client files, with uploads and Windows font registration stubbed, over five sessions each. Five loads in the x86 runtime used the installed client's files, with uploads stubbed. In those, the stock art's two steps took 3.2-3.4 ms together and uploaded 6 textures, against 4.6-5.1 ms when the warmup loaded all eight window frames. `icons.pack` took 5.0-5.5 ms, against 13.0-14.9 ms when every status icon was made at load. `fonts.face` took 2.0-2.2 ms and `actions.original.main` took 12.3-13.8 ms. `actions.original.common` took under 0.01 ms, because it reads nothing.

### Load timings in /vg report

`startup` has the first 32 Presents after the load. It also has each step with its time and the Present it ran in, when the displays could draw, and what is still to run and why. After a reload, `reload` has the unload's time and the gap to the new load. They're passed in `VANTAGE_RELOAD`, which is read once if it's under 5 seconds old. The stages cover the load, each step by its name, the first refresh in parts and the client searches. An upload of 5 ms or more also records a stage named for its texture, such as `assets.upload.original_font.moji`. `warmup.total` moves each time the warmup runs out of steps after running some, so a group asked for later moves it too. Read its `last`. Its count is how many times that happened, 1 for a plain `/load` in the game. `/vg report` runs 7 camera checks of its own, so `performance.slow_events`, which has 16 slots, fills with those and the report's own time. Read the stages for the load instead.

### Load estimate

For an offline estimate, set `VANTAGE_WARMUP_ESTIMATE` and run `python tests/run.py test_warmup_frames.lua`. In the estimate, a search costs 5.5 ms for each pass over the client, a DAT read 0.6 ms, an upload 0.23 ms and the 16 Windows fonts 22.7 ms. Nothing else the Lua does is counted. With the Original look, party strips and overhead icons on, the load event is 26.7 ms. That's 4.0 for the menu fonts and 22.7 for the Windows fonts. The first Present is 1.5 ms. The worst warmup Present is 13.5 ms, and its bound is 8 + the largest step, which is 7.1. The warmup work is 133.4 ms in all, over Presents 2 to 15. The displays draw from Present 6, and the name point is ready at Present 15. Rerun it before you rely on these numbers, because the step list can move them a little.

The estimate is a lower bound, because the Lua work of making the faces and the action icons is what sets the worst Present. A replay with live-like costs for that work too gave a worst warmup Present of 17.9-19.0 ms. In it, the displays drew from Present 10 to 13, and the whole warmup took 337-378 ms. With a live report's 42 ms of module requires, its 13 ms gap and its 15 ms first refresh added, `/load` should stall for about 95 to 100 ms once the menu fonts are in their cache. It should stall for about 120-125 ms when it must make them. These are estimates, and `/vg report` gives a load's real numbers.

## Traces and the JIT

LuaJIT's default limit is 1,000 traces, and a session here holds thousands. So `vantage.lua` sets `maxtrace=12000` and `maxmcode=16384` for the addon's own Lua state as it loads. `jit` in `/vg report` says whether that took. A session pays only for the traces it makes.

`python tests/jit_flush_guard.py` runs in the x86 runtime and counts traces and bytes, never ms. It draws each of its scenes for 600 frames after 600 to warm up. Then it draws a mixed session of those scenes, without `search` and with `solo` and `party6`, 600 frames each, twelve times over. That's 72,000 frames. It fails on any flush, on fewer than 2,500 traces free, or if a full cache of such traces wouldn't fit `maxmcode`. The newest runs had 0 flushes in every scene and in the mixed session, twice. They had 5,632 and 5,313 traces free, against the guard's 2,500. The count held moves from run to run, in a range of about 5,700 to 7,650. `search` goes round every page, which nothing else there does, so it stays out of the mixed session. With it in, the session held 6,397 to 10,304 traces in 18 runs, and the run at 10,304 left fewer than the guard's 2,500 free.

A simulated twelve hours shows nothing growing. It has a frame every 0.1 s, 6,875 mobs, 144 party joins and 47 zone changes. Reachable tables stay near 22,900 from the third hour on. The collector's count settles near 37 MB, and most of it is trace data. The session holds 10,556 of 12,000 traces and 9,999 KB of machine code, and gains about 100 traces an hour by the end. Filling the 12,000 would take about a day of that. But three hours of steady editing, with 211 changes, filled it in three of six runs. A flush is cheap. `jit.flush()` took 0.155 ms, and the two seconds after it cost about 40 ms more than usual, with no frame over 3.3 ms. Those runs went on with normal frames and no second flush.
