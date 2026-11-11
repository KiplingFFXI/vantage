Vantage developer checks

Create a Python virtual environment and install tests/requirements.txt. Set
ASHITA_LIBS to the installed Ashita addons/libs folder. It has no default. The
Lua runner loads json from vantage/core/json.lua, the strict copy Vantage
ships, and the rest of the Ashita libraries from ASHITA_LIBS.

Run these commands from the repository root:

  python tests/run.py
  python -m unittest discover -s tests -p "test_*.py"
  python tests/test_package.py
  python tests/test_install_addon.py
  python tests/test_client_check.py
  python tests/test_store_native.py
  python tests/test_share_native.py
  python tests/test_preview.py
  python tools/check_repository.py
  python tests/preview/preview.py --out tests/out/settings.png
  python tests/preview/preview.py --hud --out tests/out/panels.png --no-crop

The Lua runner starts a fresh LuaJIT runtime for every fixture and counts real
assertions. Each fixture gets its own temporary settings folder. No game client
is opened or controlled. Mocks verify behavior. They aren't live-client
validation.

tests/fixtures/clients holds two decoded client images (f2245d1c and 04288488).
They're game code, so .gitignore keeps them out of commits.
test_client_check.py runs tools/client_check.py on both and skips without them.
The Lua fixtures that read one skip too. tests/run.py prints SKIP for each and
counts them on its last line.
MOCK.load_client(name, base) in mock_ashita.lua maps one at a base behind
ashita.memory, relocated with its own .reloc section. See
client_image_fixture.lua. The images are only read.

Each image is an FFXiMain.dll decoded in memory. It's named by the first eight
hex digits of that DLL's SHA-256. f2245d1c is the client from before the
October 18 2026 game update, and 04288488 is the one after it. To make one,
decode the matching FFXiMain.dll into a new folder and copy the file it prints
into tests/fixtures/clients:

  python -B -c "import sys; sys.path.insert(0, 'tests'); import client_image; print(client_image.load(sys.argv[1], sys.argv[2]).path)" <FFXiMain.dll> <new folder>

client_image.py refuses to write over the two images in tests/fixtures/clients,
so write to a new folder and copy by hand. It uses the research decoder in
tests/out/native-solo-research. The -B option keeps Python from writing its
cache there. That folder isn't in the repository.

The preview runs the addon UI against real Dear ImGui through the local bridge.
It renders in a hidden window. Generated fonts, screenshots, and Python caches
stay out of runtime archives. Game icons use a neutral fallback in the preview.
Preview tests and scripts write to folders under tests/out (for example
tests/out/apply-setup-fit). FreeType draws the fonts without hinting, which is
closer to the stb_truetype atlas the game's ImGui uses. It isn't the same. The
game draws a font under 36 pixels at twice its width and narrows it again, and
Ashita has a style of its own (a slate child background, a border on every
button and box). So a picture can't show how sharp a font is in the game, nor
what a window that leaves a color or size to the style looks like there. Check
those in the game (docs/RELEASING.md, "The settings window in the game").

Use --client-assets to decode locally installed FFXI window/font DATs for an
Original FFXI preview. --client-xiview-root can point at a local XI View
overlay. The client-assets adapter also decodes installed item pictures for
recast icons. Run tests/test_item_preview.py to verify those bounded records.
The decoder and runtime drawing stay unchanged. Only file discovery and GPU
upload use the preview adapters. The source and the release package include no
client textures. Only the README pictures in docs/images show them. The preview
tests that read the client's files skip when those files aren't available.

preview/readme_images.py remakes the README pictures in docs/images from the
scenes in preview/readme, with the installed client's art:

  python tests/preview/readme_images.py [--only NAME]

Run it with ASHITA_LIBS set when the look changes, and look at each picture
before you commit them.

Combined recasts have focused filtering, category-demand, profile, Undo/Redo,
and all-edge resize fixtures in test_combined_recasts.lua. The matching
test_combined_recast_preview.py replays growing and shrinking from all eight
grips in bars, expanded and icon layouts, and then actual narrow wrapping. Run
preview/combined_recasts_gallery.lua with --client-assets to compare the local
spell, ability and item artwork.

Run python tests/benchmark_runtime.py for a mocked core CPU/read-count report.
See docs/PERFORMANCE.md for the scenarios and limitations.
Run python tests/benchmark_frame.py for the per-frame Lua time and allocation
of the default look with the installed client art. --runtime x86 runs it in a
plain x86 LuaJIT through tests/x86_runtime.lua, where vantage.lua sets LuaJIT's
trace limits itself as it does in the game. The x86 LuaJIT is
tests/luajit-x86/luajit.exe, or the one --exe names. That file is LuaJIT 2.1
built for 32-bit Windows. Its license is the COPYRIGHT file beside it, and
.gitignore keeps the folder out of commits. To make one, build LuaJIT 2.1 with
src/msvcbuild.bat static in an x86 Visual Studio prompt. The benchmark runs
solo, party6, alliance18, settings, filters, overhead, cooldowns, rolls, pet,
edit, main_closed, main_open, main_grid, the panel_ scenes, then
settings_filters to settings_help, search and search_home to search_help. The
settings scenario has the settings window open, and filters has shared hide
rules on. overhead is party6 with overhead icons drawn for ten units, eight
icons each. Those units are the target, four mobs the party debuffed and the
party. cooldowns is overhead with the party cooldown watch on the strips, over
heads and in its list. It also has two ready pulses playing and Dispel learned,
so the target's buffs light. rolls is the Phantom Roll display, pet is the pet
display, and edit is edit mode with anchors and show conditions. main_closed,
main_open and main_grid show the main page, and each panel_ scene shows one tab
of a display. settings_filters to settings_help have the settings window open
on each other page. search is a player typing in the settings search box, going
round the pages. search_home to search_help hold a word in the box on each
page. Each line it prints ends with the single-frame mean, p95, p99 and max and
the count of LuaJIT trace flushes.
tests/jit_flush_guard.py runs the same way, with the same --exe. It fails on
any trace flush in alliance18, settings, search, filters, overhead, cooldowns,
rolls, pet and edit, and in one long session that moves through the first ten
scenarios (H.scene in frame_harness.lua). It also fails when that session
leaves fewer than 2,500 traces of vantage.lua's limit free, or when a full
cache of its traces wouldn't fit vantage.lua's machine code limit.
test_draw_digest.py checks that every draw call of that look stays the same,
and skips without the client. test_frame_shut_cost.py checks that with the
settings window shut a frame makes no more than it did with the window loaded,
and skips without the client. test_frame_window_cost.py checks that with the
window open its own draw makes nothing a frame once warm, on each page and
display tab but Timer durations, Profiles and the Place tab of Party list
buffs, and skips without the client.
Run python tests/benchmark_recasts.py for the bounded cooldown reader and
projection measurements. See docs/RECASTS.md for timer contracts and readiness
evidence.

test_package.py builds the release archive from fixtures and from this project.
It checks the archive's layout, what it leaves out and that it refuses every
private marker. test_install_addon.py runs tools/install_addon.ps1 in Windows
PowerShell against a temporary fake game folder and backup folder only, never a
real game folder.
