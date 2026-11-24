Vantage release tools

  python tools/check_repository.py
  python tools/package.py
  python tools/export_catalog.py --duration-source <checkout> --duration-path <path> --check
  python tools/client_check.py <FFXiMain.dll or decoded client image>
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\install_addon.ps1 -Zip <archive> -Sha256 <hash> -Game <game folder>

package.py builds the release, dist/vantage-VERSION-addon.zip.
python tools/package.py --help says what the zip holds, what it leaves out and
what it refuses to build.

release_files.py holds the runtime file list package.py and check_repository.py
use, and the private marker check they share. check_repository.py also refuses
a line of tools/private_markers.txt in any public file, not just the ones the
archive holds. The archive bundles no game assets, settings or sound files.
Local sounds stay in each player's settings folder.

install_addon.ps1 installs an archive into a game folder (Windows PowerShell
5.1), with the game open or closed. If the game is open, run
/addon reload vantage in game afterwards, right away and before you open /vg.
Get-Help tools\install_addon.ps1 -Full says what it checks, where the backup
goes, what it does when something fails and what its exit codes mean.
tests/test_install_addon.py runs it against temporary folders only.
Its four drive-root tests map a free drive letter, Z down to G, to a temporary
folder with subst while they run. A run stopped early, by Ctrl+C or a kill, can
leave that letter mapped until you run subst <letter>: /d or sign out.

client_check.py checks that a game client has every pattern the addon looks
for, each exactly once. Those are the patterns for the chat windows and menu
scale (core/chat.lua), the event, interface and map focus flags
(core/client.lua), the game's party list and the Treasure Pool window
(core/native_party_ui.lua), the game clock (core/clock.lua), the game's name
point and cameras (core/name_anchor.lua), the game's own buff icons and +
menu for Replace the game's buff icons (core/game_buffs.lua), and the game's
own pet line for Replace the game's pet bar (core/game_pet_bar.lua). For
those two it checks where each routine is found and each routine whole. The menu mover's
later bytes, which the addon looks for only when the mover's start isn't
found, are a part of its whole routine and have no check of their own. While the addon
loads ffxi.itemdata, they also include that library's patterns and those of
the ffxi libraries it loads. It reads the patterns from those files, prints
each one with where it was found, and exits 0 only when every one is found
once. It only reads the client. It decodes a DLL in memory with the research
decoder, which isn't in the repository. Put the decoder's folder at
research/native-solo-research, which .gitignore keeps out of commits, or set
VANTAGE_RESEARCH to the folder. Without it, a DLL stops the check with a line
that says where it looked, so pass a decoded client image. The libraries
default to the addons/libs folder of the Ashita install the client is in, or
ASHITA_LIBS.
--libs picks another.

The catalog exporter reads pinned Git objects from the source repositories,
never dirty checkout files. --phoenix picks the Phoenix checkout. If you leave
it out, the exporter uses a sibling folder. --duration-source and
--duration-path name the checkout that holds the duration tables and their path
there. Those tables are the author's own committed work, with the same Phoenix
revision, and generation copies them into the addon. docs/SOURCE_MANIFEST.json
records the revisions and hashes. --check verifies that the output can be
reproduced, without editing it.
The exporter leaves out the effects an audit found can't exist on Phoenix. The
list is in the tool, and the audit is in docs/VALIDATION.md. It also lists the
spells and job abilities players can have there, for the Timer durations page.
